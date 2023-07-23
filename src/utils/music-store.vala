namespace G4 {

    namespace SortMode {
        public const uint ALBUM = 0;
        public const uint ARTIST = 1;
        public const uint ARTIST_ALBUM = 2;
        public const uint TITLE = 3;
        public const uint RECENT = 4;
        public const uint SHUFFLE = 5;
        public const uint MAX = 5;
    }

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

    public class MusicStore : Object {
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
        private ListStore _store = new ListStore (typeof (Music));
        private TagCache _tag_cache = new TagCache ();

        public signal void loading_changed (bool loading);

        public MusicStore () {
            _dir_monitor.add_file.connect ((file) => {
                add_files_async.begin ({file}, true, false, (obj, res) => add_files_async.end (res));
            });
            _dir_monitor.remove_file.connect (remove);
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
            lock (_dir_monitor) {
                _dir_monitor.remove_all ();
            }
            lock (_library) {
                _library.remove_all ();
            }
            _store.remove_all ();
            _tag_cache.reset_showing (false);
        }

        public void remove (File file) {
            var uri = file.get_uri ();
            var mus = _tag_cache.remove (uri);
            if (mus != null) {
                var music = (!)mus;
                for (var pos = (int) _store.get_n_items () - 1; pos >= 0; pos--) {
                    if (_store.get_item (pos) == music) {
                        _store.remove (pos);
                    }
                }
                lock (_library) {
                    _library.remove_music (music);
                }
            } else {
                var prefix = uri + "/";
                for (var pos = (int) _store.get_n_items () - 1; pos >= 0; pos--) {
                    var music = (Music) _store.get_item (pos);
                    unowned var uri2 = music.uri;
                    if (uri2.has_prefix (prefix) || uri2 == uri) {
                        _store.remove (pos);
                        lock (_library) {
                            _library.remove_music (music);
                        }
                        _tag_cache.remove (uri2);
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

        public async void add_files_async (owned File[] files, bool ignore_exists = false, bool include_playlist = true) {
            var dirs = new GenericArray<File> (128);
            var musics = new GenericArray<Music> (4096);

            _progress.reset ();
            loading_changed (true);
            yield run_void_async (() => {
                var begin_time = get_monotonic_time ();
                foreach (var file in files) {
                    add_file (file, dirs, musics, include_playlist);
                }
                print ("Find %u files in %d folders in %lld ms\n", musics.length, dirs.length,
                    (get_monotonic_time () - begin_time + 500) / 1000);

                load_tags_in_threads (musics, ignore_exists);
                lock (_library) {
                    musics.foreach (_library.add_music);
                }
                print ("Load %u artists %u albums %u musics in %lld ms\n",
                    _library.artists.length, _library.albums.length, musics.length,
                    (get_monotonic_time () - begin_time + 500) / 1000);
            });
            _store.splice (_store.get_n_items (), 0, musics.data);
            loading_changed (false);

            run_void_async.begin (() => {
                lock (_dir_monitor) {
                    _dir_monitor.monitor (dirs);
                }
            }, (obj, res) => run_void_async.end (res));

            save_tag_cache ();
        }

        private const string ATTRIBUTES = FileAttribute.STANDARD_CONTENT_TYPE + ","
                                        + FileAttribute.STANDARD_IS_HIDDEN + ","
                                        + FileAttribute.STANDARD_NAME + ","
                                        + FileAttribute.STANDARD_TYPE + ","
                                        + FileAttribute.TIME_MODIFIED;

        private void add_file (File file, GenericArray<File> dirs, GenericArray<Music> musics, bool include_playlist) {
            try {
                var info = file.query_info (ATTRIBUTES, FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new Queue<DirCache> ();
                    stack.push_head (new DirCache (file, info));
                    while (stack.length > 0) {
                        var cache = stack.pop_head ();
                        dirs.add (cache.dir);
                        add_directory (cache, stack, musics);
                    }
                } else {
                    uint playlist_type = 0;
                    unowned var ctype = info.get_content_type () ?? "";
                    unowned var name = info.get_name ();
                    if (include_playlist && (playlist_type = get_playlist_type (ctype)) != PlayListType.NONE) {
                        var uris = new GenericArray<string> (128);
                        load_playlist_file (file, playlist_type, uris);
                        foreach (var uri in uris) {
                            add_file (File.new_for_uri (uri), dirs, musics, false);
                        }
                    } else if (is_music_type (ctype)) {
                        var time = info.get_modification_date_time ()?.to_unix () ?? 0;
                        var music = new Music (file.get_uri (), name, time);
                        musics.add (music);
                    } else if (is_cover_file (ctype, name)) {
                        var parent = file.get_parent ();
                        if (parent != null)
                            _cover_cache.put ((!)parent, name);
                    }
                }
            } catch (Error e) {
                warning ("Query %s: %s\n", file.get_parse_name (), e.message);
            }
        }

        private void add_directory (DirCache cache, Queue<DirCache> stack, GenericArray<Music> musics) {
            var dir = cache.dir;
            var start = musics.length;
            string? cover_name = null;
            if (cache.check_valid () && cache.load (stack, musics, out cover_name)) {
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
                        cache.add_child (info);
                    } else {
                        unowned var ctype = info.get_content_type () ?? "";
                        unowned var name = info.get_name ();
                        if (is_music_type (ctype)) {
                            var time = info.get_modification_date_time ()?.to_unix () ?? 0;
                            var file = dir.get_child (name);
                            var music = new Music (file.get_uri (), name, time);
                            musics.add (music);
                            cache.add_child (info);
                        } else if (is_cover_file (ctype, name)) {
                            cover_name = name;
                            cache.add_child (info);
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

        private void load_tags_in_threads (GenericArray<Music> musics, bool ignore_exists) {
            var queue = new AsyncQueue<Music?> ();
            _tag_cache.wait_loading ();
            lock (_tag_cache) {
                for (var i = musics.length - 1; i >= 0; i--) {
                    unowned var music = musics[i];
                    var cached_music = _tag_cache[music.uri];
                    if (ignore_exists && cached_music != null && ((!)cached_music).showing) {
                        musics.remove_index_fast (i);
                    } else if (cached_music != null && ((!)cached_music).modified_time == music.modified_time) {
                        ((!)cached_music).showing = true;
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

    private const CompareFunc<Music>[] COMPARE_FUNCS = {
        Music.compare_by_album,
        Music.compare_by_artist,
        Music.compare_by_artist_album,
        Music.compare_by_title,
        Music.compare_by_recent,
        Music.compare_by_order,
    };

    public CompareFunc<Music> get_sort_compare (uint sort_mode) {
        if (sort_mode <= COMPARE_FUNCS.length)
            return COMPARE_FUNCS[sort_mode];
        return Music.compare_by_order;
    }

    public void shuffle_order (ListStore store) {
        var count = store.get_n_items ();
        var arr = new GenericArray<Music> (count);
        for (var i = 0; i < count; i++) {
            arr.add ((Music)store.get_item (i));
        }
        Music.shuffle_order (arr);
    }
}
