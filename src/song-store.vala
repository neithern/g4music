namespace Music {

    public enum SortMode {
        ALBUM,
        ARTIST,
        TITLE,
        SHUFFLE
    }

    public class SongStore : Object {
        private SortMode _sort_mode = SortMode.TITLE;
        private CompareDataFunc<Object> _compare = Song.compare_by_title;
        private ListStore _store = new ListStore (typeof (Song));

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

        public void clear () {
            _store.remove_all ();
        }

        public Song? get_song (uint position) {
            return _store.get_item (position) as Song;
        }

#if HAS_TRACKER_SPARQL
        public const string SQL_QUERY_SONGS = """
            SELECT 
                nie:title(nmm:musicAlbum(?song))
                nmm:artistName (nmm:artist (?song))
                nie:title (?song)
                nie:isStoredAs (?song)
            WHERE { ?song a nmm:MusicPiece }
        """;

        public async void add_sparql_async () {
            var arr = new GenericArray<Object> (4096);
            yield run_async<void> (() => {
                var begin_time = get_monotonic_time ();
                Tracker.Sparql.Connection connection;
                try {
                    connection = Tracker.Sparql.Connection.bus_new ("org.freedesktop.Tracker3.Miner.Files", null);
                    var cursor = connection.query (SQL_QUERY_SONGS);
                    while (cursor.next ()) {
                        var song = new Song ();
                        song.album = cursor.get_string (0) ?? UNKOWN_ALBUM;
                        song.artist = cursor.get_string (1) ?? UNKOWN_ARTIST;
                        song.title = cursor.get_string (2) ?? "";
                        song.uri = cursor.get_string (3) ?? "";
                        if (song.title.length == 0)
                            song.title = parse_name_from_uri (song.uri);
                        song.ttype = TagType.SPARQL;
                        song.update_keys ();
                        arr.add (song);
                    }
                } catch (Error e) {
                    warning ("Query error: %s\n", e.message);
                }
                if (_sort_mode == SortMode.SHUFFLE) {
                    Song.shuffle_order (arr);
                }
                arr.sort ((CompareFunc<Object>) _compare);
                print ("Found %u songs in %g seconds\n", arr.length,
                    (get_monotonic_time () - begin_time) / 1e6);
            });
            _store.splice (_store.get_n_items (), 0, arr.data);
        }
#endif

        public async void add_files_async (File[] files) {
            var arr = new GenericArray<Object> (4096);
            yield run_async<void> (() => {
                var begin_time = get_monotonic_time ();
                foreach (var file in files) {
                    add_file (file, arr);
                }

                var queue = new AsyncQueue<Song?> ();
                foreach (var obj in arr) {
                    queue.push ((Song) obj);
                }
                var num_thread = get_num_processors ();
                var threads = new Thread<void>[num_thread];
                for (var i = 0; i < num_thread; i++) {
                    threads[i] = new Thread<void> (@"thread$(i)",  () => {
                        Song? song;
                        while ((song = queue.try_pop ()) != null) {
                            parse_song_tags ((!)song);
                        }
                    });
                }
                foreach (var thread in threads) {
                    thread.join ();
                }

                if (_sort_mode == SortMode.SHUFFLE) {
                    Song.shuffle_order (arr);
                }
                arr.sort ((CompareFunc<Object>) _compare);
                print ("Found %u songs in %g seconds\n", arr.length,
                        (get_monotonic_time () - begin_time) / 1e6);
            });
            _store.splice (_store.get_n_items (), 0, arr.data);
        }

        private static void add_file (File file, GenericArray<Object> arr) {
            try {
                var info = file.query_info ("standard::*", FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new Queue<File> ();
                    stack.push_tail (file);
                    while (stack.length > 0) {
                        add_directory (stack, arr);
                    }
                } else {
                    var parent = file.get_parent ();
                    var base_uri = parent != null ? get_uri_with_end_sep ((!)parent) : "";
                    var song = new_song_from_info (base_uri, info);
                    if (song != null)
                        arr.add ((!)song);
                }
            } catch (Error e) {
                warning ("Query %s: %s\n", file.get_parse_name (), e.message);
            }
        }

        private static void add_directory (Queue<File> stack, GenericArray<Object> arr) {
            var dir = stack.pop_tail ();
            try {
                var base_uri = get_uri_with_end_sep (dir);
                FileInfo? info = null;
                var enumerator = dir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
                while ((info = enumerator.next_file ()) != null) {
                    var pi = (!)info;
                    if (pi.get_is_hidden ()) {
                        continue;
                    } else if (pi.get_file_type () == FileType.DIRECTORY) {
                        var sub_dir = dir.resolve_relative_path (pi.get_name ());
                        stack.push_tail (sub_dir);
                    } else {
                        var song = new_song_from_info (base_uri, pi);
                        if (song != null)
                            arr.add ((!)song);
                    }
                }
            } catch (Error e) {
                warning ("Enumerate %s: %s\n", dir.get_parse_name (), e.message);
            }
        }

        private static Song? new_song_from_info (string base_uri, FileInfo info) {
            unowned var type = info.get_content_type ();
            if (type != null && ContentType.is_mime_type ((!)type, "audio/*") && !((!)type).has_suffix ("url")) {
                unowned var name = info.get_name ();
                var song = new Song ();
                // build same file uri as tracker sparql
                song.uri = base_uri + Uri.escape_string (name, null, false);
                song.title = name;
                return song;
            }
            return null;
        }

        private static void parse_song_tags (Song song) {
            var file = File.new_for_uri (song.uri);
            var name = song.title;
            song.title = "";
#if HAS_TAGLIB_C
            var path = file.get_path ();
            if (path != null) { // parse local path only
                var tf = new TagLib.File ((!)path);
                song.from_taglib (tf);
            }
#else
            if (file.has_uri_scheme ("file")) {
                var tags = parse_gst_tags (file);
                song.from_gst_tags (tags);
            }
#endif
            if (song.title.length == 0) {
                //  title should always not empty
                song.title = parse_name_from_path (name);
                song.update_keys ();
            }
        }
    }
}
