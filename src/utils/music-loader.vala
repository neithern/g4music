namespace G4 {

    public class Progress {
        private int _progress = 0;
        private int _total = 0;

        public Progress (int total = 0) {
            _total = total;
        }

        public int total {
            get {
                return AtomicInt.get (ref _total);
            }
            set {
                AtomicInt.set (ref _total, value);
            }
        }

        public double fraction {
            get {
                return _total > 0 ? _progress / (double) _total : 0;
            }
        }

        public void reset () {
            _progress = 0;
            _total = 0;
        }

        public void step () {
            AtomicInt.inc (ref _progress);
        }
    }

    public class MusicLoader : Object {
        private static Once<ThreadPool<DirCache>?> _save_dir_pool;

        static unowned ThreadPool<DirCache>? get_save_dir_pool () {
            return _save_dir_pool.once(() => {
                try {
                    return new ThreadPool<DirCache>.with_owned_data ((cache) => cache.save (), 1, false);
                } catch (Error e) {
                }
                return null;
            });
        }

        private CoverCache _cover_cache = new CoverCache ();
        private DirMonitor _dir_monitor = new DirMonitor ();
        private MusicLibrary _library = new MusicLibrary ();
        private Progress _progress = new Progress ();
        private TagCache _tag_cache = new TagCache ();

        public signal void loading_changed (bool loading);
        public signal void music_found (GenericArray<Music> arr);
        public signal void music_lost (GenericSet<Music> arr);

        public MusicLoader () {
            _dir_monitor.add_file.connect (on_file_added);
            _dir_monitor.remove_file.connect (on_file_removed);
        }

        public CoverCache cover_cache {
            get {
                return _cover_cache;
            }
        }

        public bool monitor_changes {
            get {
                return _dir_monitor.enabled;
            }
            set {
                _dir_monitor.enabled = value;
            }
        }

        public double loading_progress {
            get {
                return _progress.fraction;
            }
        }

        public MusicLibrary library {
            get {
                return _library;
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

        public void load_tag_cache () {
            run_void_async.begin (_tag_cache.load, (obj, res) => run_void_async.end (res));
        }

        public void save_tag_cache () {
            if (_tag_cache.modified) {
                run_void_async.begin (_tag_cache.save, (obj, res) => run_void_async.end (res));
            }
        }

        public async void load_files_async (owned File[] files, GenericArray<Music> musics, bool ignore_exists = false, bool load_lists = true, uint sort_mode = -1) {
            var dirs = new GenericArray<File> (128);

            _progress.reset ();
            loading_changed (true);
            yield run_void_async (() => {
                var begin_time = get_monotonic_time ();
                foreach (var file in files) {
                    add_file (file, musics, dirs, null, load_lists);
                }
                print ("Find %u files in %d folders in %lld ms\n", musics.length, dirs.length,
                    (get_monotonic_time () - begin_time + 500) / 1000);

                load_tags_in_threads (musics);
                if (sort_mode <= SortMode.MAX) {
                    sort_music_array (musics, sort_mode);
                }
                lock (_library) {
                    for (var i = musics.length - 1; i >= 0; i--) {
                        var music = musics[i];
                        if (!_library.add_music (music) && ignore_exists)
                            musics.remove_index_fast (i);
                    }
                }
                print ("Load %u artists %u albums %u musics in %lld ms\n",
                    _library.artists.length, _library.albums.length, musics.length,
                    (get_monotonic_time () - begin_time + 500) / 1000);
            });
            loading_changed (false);

            run_void_async.begin (() => {
                lock (_dir_monitor) {
                    _dir_monitor.monitor (dirs);
                }
            }, (obj, res) => run_void_async.end (res));

            save_tag_cache ();
        }

        public void remove_all () {
            lock (_dir_monitor) {
                _dir_monitor.remove_all ();
            }
            lock (_library) {
                _library.remove_all ();
            }
        }

        private const string ATTRIBUTES = FileAttribute.STANDARD_CONTENT_TYPE + ","
                                        + FileAttribute.STANDARD_IS_HIDDEN + ","
                                        + FileAttribute.STANDARD_NAME + ","
                                        + FileAttribute.STANDARD_TYPE + ","
                                        + FileAttribute.TIME_MODIFIED;

        private void add_file (File file, GenericArray<Music> musics, GenericArray<File>? dirs = null, GenericArray<File>? playlists = null, bool load_lists = false) {
            try {
                var info = file.query_info (ATTRIBUTES, FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new Queue<DirCache> ();
                    stack.push_head (new DirCache (file, info));
                    while (stack.length > 0) {
                        var cache = stack.pop_head ();
                        dirs?.add (cache.dir);
                        add_directory (cache, stack, musics, playlists);
                    }
                } else {
                    unowned var ctype = info.get_content_type () ?? "";
                    unowned var name = info.get_name ();
                    if (is_music_type (ctype)) {
                        var time = info.get_modification_date_time ()?.to_unix () ?? 0;
                        var music = new Music (file.get_uri (), name, time);
                        musics.add (music);
                    } else if (is_playlist_file (ctype)) {
                        if (load_lists)
                            load_playlist (file, musics);
                        else
                            playlists?.add (file);
                    } else if (is_cover_file (ctype, name)) {
                        var parent = file.get_parent ();
                        if (parent != null)
                            _cover_cache.put ((!)parent, name);
                    } else {
                        print ("unknown type: %s, %s\n", ctype, file.get_path () ?? "");
                    }
                }
            } catch (Error e) {
                warning ("Query %s: %s\n", file.get_parse_name (), e.message);
            }
        }

        private void add_directory (DirCache cache, Queue<DirCache> stack, GenericArray<Music> musics, GenericArray<File>? playlists) {
            var dir = cache.dir;
            var start = musics.length;
            string? cover_name = null;
            if (cache.check_valid () && cache.load (stack, musics, playlists, out cover_name)) {
                _cover_cache.put (dir, cover_name ?? "");
            } else try {
                FileInfo? pi = null;
                var enumerator = dir.enumerate_children (ATTRIBUTES, FileQueryInfoFlags.NONE);
                while ((pi = enumerator.next_file ()) != null) {
                    var info = (!)pi;
                    if (info.get_is_hidden ()) {
                        continue;
                    } else if (info.get_file_type () == FileType.DIRECTORY) {
                        var child = dir.get_child (info.get_name ());
                        stack.push_head (new DirCache (child, info));
                        cache.add_child (info, ChildType.FOLDER);
                    } else {
                        unowned var ctype = info.get_content_type () ?? "";
                        unowned var name = info.get_name ();
                        if (is_music_type (ctype)) {
                            var time = info.get_modification_date_time ()?.to_unix () ?? 0;
                            var file = dir.get_child (name);
                            var music = new Music (file.get_uri (), name, time);
                            musics.add (music);
                            cache.add_child (info, ChildType.MUSIC);
                        } else if (playlists != null && is_playlist_file (ctype)) {
                            var child = dir.get_child (info.get_name ());
                            ((!)playlists).add (child);
                            cache.add_child (info, ChildType.PLAYLIST);
                        } else if (cover_name == null && is_cover_file (ctype, name)) {
                            cover_name = name;
                            cache.add_child (info, ChildType.COVER);
                        }
                    }
                }
                _cover_cache.put (dir, cover_name ?? "");
                get_save_dir_pool ()?.add (cache);
            } catch (Error e) {
                warning ("Enumerate %s: %s\n", dir.get_parse_name (), e.message);
            }
            if (cover_name != null && ((!)cover_name).length > 0) {
                for (var i = musics.length - 1; i >= start; i--) {
                    var music = (Music) musics[i];
                    music.has_cover = true;
                }
            }
        }

        private void load_playlist (File file, GenericArray<Music> musics) {
            var uris = new GenericArray<string> (1024);
            load_playlist_file (file, uris);
            foreach (var uri in uris) {
                var cached_music = _tag_cache[uri];
                if (cached_music != null) {
                    musics.add ((!)cached_music);
                } else {
                    add_file (File.new_for_uri (uri), musics);
                }
            }
        }

        private void load_tags_in_threads (GenericArray<Music> musics) {
            var queue = new AsyncQueue<Music?> ();
            _tag_cache.wait_loading ();
            lock (_tag_cache) {
                for (var i = musics.length - 1; i >= 0; i--) {
                    unowned var music = musics[i];
                    var cached_music = _tag_cache[music.uri];
                    if (cached_music != null && ((!)cached_music).modified_time == music.modified_time) {
                        musics[i] = (!)cached_music;
                    } else {
                        _tag_cache.add (music);
                        queue.push (music);
                    }
                }
            }
            var queue_count = queue.length ();
            if (queue_count > 0) {
                _progress.total = queue_count;
                var num_tasks = uint.min (queue_count, get_num_processors ());
                run_in_threads<void> (() => {
                    Music? music;
                    while ((music = queue.try_pop ()) != null) {
                        music?.parse_tags ();
                        _progress.step ();
                    }
                }, num_tasks);
            }
        }

        private void on_file_added (File file) {
            var arr = new GenericArray<Music> (1024);
            load_files_async.begin ({file}, arr, true, false, -1, (obj, res) => {
                load_files_async.end (res);
                if (arr.length > 0) {
                    music_found (arr);
                }
            });
        }

        private void on_file_removed (File file) {
            var uri = file.get_uri ();
            var music = _tag_cache.remove (uri);
            if (music != null) {
                lock (_library) {
                    _library.remove_music ((!)music);
                }
            } else {
                var removed = new GenericSet<Music> (direct_hash, direct_equal);
                lock (_library) {
                    _library.remove_uri (uri, removed);
                }
                if (removed.length > 0) {
                    music_lost (removed);
                }
                new DirCache (file).delete ();
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
