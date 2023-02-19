namespace Music {

    public enum SortMode {
        ALBUM,
        ARTIST,
        TITLE,
        RECENT,
        SHUFFLE,
    }

    public class SongStore : Object {
        private static ThreadPool<DirCache>? _save_dir_pool;

        static construct {
            try {
                _save_dir_pool = new ThreadPool<DirCache>.with_owned_data ((cache) => cache.save (), 1, false);
            } catch (Error e) {
            }
        }

        private SortMode _sort_mode = SortMode.TITLE;
        private CompareDataFunc<Object> _compare = Song.compare_by_title;
        private ListStore _store = new ListStore (typeof (Song));
        private TagCache _tag_cache = new TagCache ();

        public signal void parse_progress (int percent);

        public ListStore store {
            get {
                return _store;
            }
        }

        public uint size {
            get {
                return _store.get_n_items ();
            }
        }

        public SortMode sort_mode {
            get {
                return _sort_mode;
            }
            set {
                _sort_mode = value;
                switch (value) {
                    case SortMode.ALBUM:
                        _compare = Song.compare_by_album;
                        break;
                    case SortMode.ARTIST:
                        _compare = Song.compare_by_artist;
                        break;
                    case SortMode.RECENT:
                        _compare = Song.compare_by_date_ascending;
                        break;
                    case SortMode.SHUFFLE:
                        _compare = Song.compare_by_order;
                        break;
                    default:
                        _compare = Song.compare_by_title;
                        break;
                }
                if (_sort_mode == SortMode.SHUFFLE) {
                    var count = _store.get_n_items ();
                    var arr = new GenericArray<Object> (count);
                    for (var i = 0; i < count; i++) {
                        arr.add ((!)_store.get_item (i));
                    }
                    Song.shuffle_order (arr);
                }
                _store.sort (_compare);
            }
        }

        public void add_to_cache (Song song) {
            _tag_cache.add (song);
        }

        public void clear () {
            _store.remove_all ();
        }

        public Song? get_song (uint position) {
            return _store.get_item (position) as Song;
        }

        public async void load_tag_cache_async () {
            yield run_async<void> (_tag_cache.load);
        }

        public async void save_tag_cache_async () {
            if (_tag_cache.modified) {
                yield run_async<void> (_tag_cache.save);
            }
        }

        public async void add_files_async (File[] files) {
            var songs = new GenericArray<Object> (4096);
            yield run_async<void> (() => {
                var begin_time = get_monotonic_time ();
                foreach (var file in files) {
                    add_file (file, songs);
                }

                var queue = new AsyncQueue<Song?> ();
                for (var i = 0; i < songs.length; i++) {
                    var song = (Song) songs[i];
                    var cached_song = _tag_cache[song.uri];
                    if (cached_song != null && ((!)cached_song).modified_time == song.modified_time)
                        songs[i] = (!)cached_song;
                    else
                        queue.push (song);
                }
                var queue_count = queue.length ();
                if (queue_count > 0) {
                    int percent = 0;
                    int progress = 0;
                    var num_tasks = uint.min (queue_count, get_num_processors ());
                    run_in_threads<void> ((index) => {
                        Song? s;
                        while ((s = queue.try_pop ()) != null) {
                            var song = (!)s;
                            song.parse_tags ();
                            _tag_cache.add (song);
                            AtomicInt.inc (ref progress);
                            var per = progress * 100 / queue_count;
                            if (percent < per) {
                                AtomicInt.set (ref percent, per);
                                Idle.add (() => {
                                    parse_progress (per);
                                    return false;
                                });
                            }
                        }
                    }, num_tasks);
                }

                if (_sort_mode == SortMode.SHUFFLE) {
                    Song.shuffle_order (songs);
                }
                songs.sort ((CompareFunc<Object>) _compare);
                print ("Found %u songs in %g seconds\n", songs.length,
                        (get_monotonic_time () - begin_time) / 1e6);
            });
            _store.splice (_store.get_n_items (), 0, songs.data);

            if (_tag_cache.modified) {
                save_tag_cache_async.begin ((obj, res) => {
                    save_tag_cache_async.end (res);
                });
            }
        }

        private const string ATTRIBUTES = FileAttribute.STANDARD_CONTENT_TYPE + ","
                                        + FileAttribute.STANDARD_IS_HIDDEN + ","
                                        + FileAttribute.STANDARD_NAME + ","
                                        + FileAttribute.STANDARD_TYPE + ","
                                        + FileAttribute.TIME_MODIFIED;

        private static void add_file (File file, GenericArray<Object> songs) {
            try {
                var info = file.query_info (ATTRIBUTES, FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new Queue<File> ();
                    stack.push_head (file);
                    while (stack.length > 0) {
                        var dir = stack.pop_head ();
                        add_directory (dir, stack, songs);
                    }
                } else {
                    var song = Song.from_info (file, info);
                    if (song != null)
                        songs.add ((!)song);
                }
            } catch (Error e) {
                warning ("Query %s: %s\n", file.get_parse_name (), e.message);
            }
        }

        private static void add_directory (File dir, Queue<File> stack, GenericArray<Object> songs) {
            var cache = new DirCache (dir);
            if (cache.check_valid () && cache.load (stack, songs)) {
                return;
            }

            try {
                FileInfo? pi = null;
                var enumerator = dir.enumerate_children (ATTRIBUTES, FileQueryInfoFlags.NONE);
                while ((pi = enumerator.next_file ()) != null) {
                    var info = (!)pi;
                    if (info.get_is_hidden ()) {
                        continue;
                    } else if (info.get_file_type () == FileType.DIRECTORY) {
                        var child = dir.get_child (info.get_name ());
                        stack.push_head (child);
                        cache.add_child (info);
                    } else {
                        var file = dir.get_child (info.get_name ());
                        var song = Song.from_info (file, info);
                        if (song != null) {
                            songs.add ((!)song);
                            cache.add_child (info);
                        }
                    }
                }
                _save_dir_pool?.add (cache);
            } catch (Error e) {
                warning ("Enumerate %s: %s\n", dir.get_parse_name (), e.message);
            }
        }

        private delegate G ThreadFunc<G> (uint index);

        private static void run_in_threads<G> (owned ThreadFunc<G> func, uint num_tasks) {
            var threads = new Thread<G>[num_tasks];
            for (var i = 0; i < num_tasks; i++) {
                var index = i;
                threads[i] = new Thread<G> (null, () => {
                    return func (index);
                });
            }
            foreach (var thread in threads) {
                thread.join ();
            }
        }
    }
}
