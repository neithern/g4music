namespace G4 {

    public enum SortMode {
        ALBUM,
        ARTIST,
        TITLE,
        RECENT,
        SHUFFLE,
    }

    public class MusicStore : Object {
        private static ThreadPool<DirCache>? _save_dir_pool;

        static construct {
            try {
                _save_dir_pool = new ThreadPool<DirCache>.with_owned_data ((cache) => cache.save (), 1, false);
            } catch (Error e) {
            }
        }

        private SortMode _sort_mode = SortMode.TITLE;
        private CompareDataFunc<Object> _compare = Music.compare_by_title;
        private ListStore _store = new ListStore (typeof (Music));
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
                        _compare = Music.compare_by_album;
                        break;
                    case SortMode.ARTIST:
                        _compare = Music.compare_by_artist;
                        break;
                    case SortMode.RECENT:
                        _compare = Music.compare_by_date_ascending;
                        break;
                    case SortMode.SHUFFLE:
                        _compare = Music.compare_by_order;
                        break;
                    default:
                        _compare = Music.compare_by_title;
                        break;
                }
                if (_sort_mode == SortMode.SHUFFLE) {
                    var count = _store.get_n_items ();
                    var arr = new GenericArray<Object> (count);
                    for (var i = 0; i < count; i++) {
                        arr.add ((!)_store.get_item (i));
                    }
                    Music.shuffle_order (arr);
                }
                _store.sort (_compare);
            }
        }

        public void add_to_cache (Music music) {
            _tag_cache.add (music);
        }

        public void clear () {
            _store.remove_all ();
        }

        public Music? get_music (uint position) {
            return _store.get_item (position) as Music;
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
            var musics = new GenericArray<Object> (4096);
            yield run_async<void> (() => {
                var begin_time = get_monotonic_time ();
                foreach (var file in files) {
                    add_file (file, musics);
                }

                var queue = new AsyncQueue<Music?> ();
                for (var i = 0; i < musics.length; i++) {
                    var music = (Music) musics[i];
                    var cached_music = _tag_cache[music.uri];
                    if (cached_music != null && ((!)cached_music).modified_time == music.modified_time)
                        musics[i] = (!)cached_music;
                    else
                        queue.push (music);
                }
                var queue_count = queue.length ();
                if (queue_count > 0) {
                    int percent = 0;
                    int progress = 0;
                    var num_tasks = uint.min (queue_count, get_num_processors ());
                    run_in_threads<void> ((index) => {
                        Music? s;
                        while ((s = queue.try_pop ()) != null) {
                            var music = (!)s;
                            music.parse_tags ();
                            _tag_cache.add (music);
                            AtomicInt.inc (ref progress);
                            var per = progress * 100 / queue_count;
                            if (AtomicInt.compare_and_exchange (ref percent, percent, per)) {
                                Idle.add (() => {
                                    parse_progress (per);
                                    return false;
                                });
                            }
                        }
                    }, num_tasks);
                }

                if (_sort_mode == SortMode.SHUFFLE) {
                    Music.shuffle_order (musics);
                }
                musics.sort ((CompareFunc<Object>) _compare);
                print ("Found %u musics in %g seconds\n", musics.length,
                        (get_monotonic_time () - begin_time) / 1e6);
            });
            _store.splice (_store.get_n_items (), 0, musics.data);

            if (_tag_cache.modified) {
                save_tag_cache_async.begin ((obj, res) => save_tag_cache_async.end (res));
            }
        }

        private const string ATTRIBUTES = FileAttribute.STANDARD_CONTENT_TYPE + ","
                                        + FileAttribute.STANDARD_IS_HIDDEN + ","
                                        + FileAttribute.STANDARD_NAME + ","
                                        + FileAttribute.STANDARD_TYPE + ","
                                        + FileAttribute.TIME_MODIFIED;

        private static void add_file (File file, GenericArray<Object> musics) {
            try {
                var info = file.query_info (ATTRIBUTES, FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new Queue<File> ();
                    stack.push_head (file);
                    while (stack.length > 0) {
                        var dir = stack.pop_head ();
                        add_directory (dir, stack, musics);
                    }
                } else {
                    var music = Music.from_info (file, info);
                    if (music != null)
                        musics.add ((!)music);
                }
            } catch (Error e) {
                warning ("Query %s: %s\n", file.get_parse_name (), e.message);
            }
        }

        private static void add_directory (File dir, Queue<File> stack, GenericArray<Object> musics) {
            var cache = new DirCache (dir);
            if (cache.check_valid () && cache.load (stack, musics)) {
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
                        var music = Music.from_info (file, info);
                        if (music != null) {
                            musics.add ((!)music);
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
                threads[index] = new Thread<G> (null, () => func (index));
            }
            foreach (var thread in threads) {
                thread.join ();
            }
        }
    }
}
