namespace G4 {

    public enum SortMode {
        ALBUM,
        ARTIST,
        TITLE,
        RECENT,
        SHUFFLE,
    }

    public class Progress : Object {
        private int _percent = 0;
        private int _progress = 0;
        private int _total = 1;

        public signal void percent_changed (int percent);

        public Progress (int total) {
            _total = total;
        }

        public void step () {
            AtomicInt.inc (ref _progress);
            var per = _progress * 100 / _total;
            if (AtomicInt.compare_and_exchange (ref _percent, _percent, per)) {
                run_idle_once (() => percent_changed (per));
            }
        }
    }

    public class MusicStore : Object {
        private static ThreadPool<DirCache>? _save_dir_pool;

        static construct {
            try {
                _save_dir_pool = new ThreadPool<DirCache>.with_owned_data ((cache) => cache.save (), 1, false);
            } catch (Error e) {
            }
        }

        private bool _monitor_changes = false;
        private SortMode _sort_mode = SortMode.TITLE;
        private CompareDataFunc<Object> _compare = Music.compare_by_title;
        private ListStore _store = new ListStore (typeof (Music));
        private GenericSet<Music> _music_set = new GenericSet<Music> (Music.hash, Music.equal);
        private TagCache _tag_cache = new TagCache ();

        public signal void loading_changed (bool loading);
        public signal void parse_progress (int percent);

        public bool monitor_changes {
            get {
                return _monitor_changes;
            }
            set {
                _monitor_changes = value;
            }
        }

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
            lock (_tag_cache) {
                _tag_cache.add (music);
            }
        }

        public Music? find_cache (string uri) {
            lock (_tag_cache) {
                return _tag_cache[uri];
            }
        }

        public void clear () {
            lock (_monitors) {
                _monitors.foreach ((uri, monitor) => monitor.cancel ());
                _monitors.remove_all ();
            }
            _store.remove_all ();
            lock (_music_set) {
                _music_set.remove_all ();
            }
        }

        public void remove (string uri) {
            var music = _tag_cache[uri];
            if (music != null) {
                for (var pos = (int) _store.get_n_items () - 1; pos >= 0; pos--) {
                    if (_store.get_item (pos) == music) {
                        _store.remove (pos);
                    }
                }
                lock (_music_set) {
                    _music_set.remove ((!)music);
                }
            } else {
                var prefix = uri + "/";
                for (var pos = (int) _store.get_n_items () - 1; pos >= 0; pos--) {
                    var mus = (Music) _store.get_item (pos);
                    if (mus.uri.has_prefix (prefix)) {
                        _store.remove (pos);
                        lock (_music_set) {
                            _music_set.remove (mus);
                        }
                    }
                }
            }
        }

        public void load_tag_cache () {
            run_void_async.begin (_tag_cache.load, (obj, res) => run_void_async.end (res));
        }

        public void save_tag_cache () {
            if (_tag_cache.modified) {
                run_void_async.begin (_tag_cache.save, (obj, res) => run_void_async.end (res));
            }
        }

        public async void add_files_async (owned File[] files, bool ignore_exists = false) {
            var dirs = new GenericArray<File> (128);
            var musics = new GenericArray<Object> (4096);
            loading_changed (true);
            yield run_void_async (() => {
                var begin_time = get_monotonic_time ();
                foreach (var file in files) {
                    add_file (file, dirs, musics);
                }
                print ("Find %u files in %d folders in %lld ms\n", musics.length, dirs.length,
                    (get_monotonic_time () - begin_time + 500) / 1000);

                var queue = new AsyncQueue<Music?> ();
                _tag_cache.wait_loading ();
                for (var i = musics.length - 1; i >= 0; i--) {
                    var music = (Music) musics[i];
                    if (ignore_exists) lock (_music_set) {
                        if (_music_set.contains (music))
                            musics.remove_index_fast (i);
                    }
                    var cached_music = _tag_cache[music.uri];
                    if (cached_music != null && ((!)cached_music).modified_time == music.modified_time)
                        musics[i] = (!)cached_music;
                    else
                        queue.push (music);
                }
                var queue_count = queue.length ();
                if (queue_count > 0) {
                    var progress = new Progress (queue_count);
                    progress.percent_changed.connect ((percent) => parse_progress (percent));
                    var num_tasks = uint.min (queue_count, get_num_processors ());
                    run_in_threads<void> (() => {
                        Music? music;
                        while ((music = queue.try_pop ()) != null) {
                            music?.parse_tags ();
                            add_to_cache ((!)music);
                            progress.step ();
                        }
                    }, num_tasks);
                }

                if (_sort_mode == SortMode.SHUFFLE) {
                    Music.shuffle_order (musics);
                }
                musics.sort ((CompareFunc<Object>) _compare);
                print ("Load %u musics in %lld ms\n", musics.length,
                        (get_monotonic_time () - begin_time + 500) / 1000);
            });
            _store.splice (_store.get_n_items (), 0, musics.data);
            loading_changed (false);

            run_void_async.begin (() => {
                foreach (var obj in musics) {
                    lock (_music_set) {
                        _music_set.add (((Music)obj));
                    }
                }
                foreach (var dir in dirs) {
                    if (dir.is_native ())
                        _monitor_dir (dir);
                }
            }, (obj, res) => run_void_async.end (res));

            save_tag_cache ();
        }

        private HashTable<string, FileMonitor> _monitors = new HashTable<string, FileMonitor> (str_hash, str_equal);

        private void _monitor_dir (File dir) {
            var uri = dir.get_uri ();
            unowned string orig_key;
            FileMonitor monitor;
            lock (_monitors) {
                if (_monitors.lookup_extended (uri, out orig_key, out monitor)) {
                    monitor.cancel ();
                }
                if (_monitor_changes) try {
                    monitor = dir.monitor (FileMonitorFlags.WATCH_MOVES, null);
                    monitor.changed.connect (_monitor_func);
                    _monitors[uri] = monitor;
                } catch (Error e) {
                    print ("Monitor dir error: %s\n", e.message);
                }
            }
        }

        private void _monitor_func (File file, File? other_file, FileMonitorEvent event) {
            switch (event) {
                case FileMonitorEvent.ATTRIBUTE_CHANGED:
                case FileMonitorEvent.MOVED_IN:
                    add_files_async.begin ({file}, true, (obj, res) => add_files_async.end (res));
                    break;

                case FileMonitorEvent.DELETED:
                case FileMonitorEvent.MOVED_OUT:
                    remove (file.get_uri ());
                    break;

                case FileMonitorEvent.RENAMED:
                    remove (file.get_uri ());
                    if (other_file != null)
                        add_files_async.begin ({(!)other_file}, true, (obj, res) => add_files_async.end (res));
                    break;

                default:
                    break;
            }
        }

        private const string ATTRIBUTES = FileAttribute.STANDARD_CONTENT_TYPE + ","
                                        + FileAttribute.STANDARD_IS_HIDDEN + ","
                                        + FileAttribute.STANDARD_NAME + ","
                                        + FileAttribute.STANDARD_TYPE + ","
                                        + FileAttribute.TIME_MODIFIED;

        private static void add_file (File file, GenericArray<File> dirs, GenericArray<Object> musics) {
            try {
                var info = file.query_info (ATTRIBUTES, FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new Queue<File> ();
                    stack.push_head (file);
                    while (stack.length > 0) {
                        var dir = stack.pop_head ();
                        dirs.add (dir);
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

        private delegate G ThreadFunc<G> ();

        private static void run_in_threads<G> (owned ThreadFunc<G> func, uint num_tasks) {
            var threads = new Thread<G>[num_tasks];
            for (var i = 0; i < num_tasks; i++) {
                var index = i;
                threads[index] = new Thread<G> (null, func);
            }
            foreach (var thread in threads) {
                thread.join ();
            }
        }
    }
}
