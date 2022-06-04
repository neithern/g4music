namespace Music {
    public const string UNKOWN_ALBUM = _("Unknown Album");
    public const string UNKOWN_ARTIST = _("Unknown Aritst");
    public const string DEFAULT_MIMETYPE = "audio/mpeg";

    public class Song : Object {
        public string album = "";
        public string artist = "";
        public string title = "";
        public string type = "";
        public string uri = "";
        public string thumbnail = "";
        public long mtime = 0;
        public int order = 0;

        //  private string _album_key;
        private string _artist_key = "";
        private string _title_key = "";

        public bool update (string? al, string? ar, string? ti) {
            bool changed = false;
            if (al != null && al != album) {
                changed = true;
                album = (!)al;
                //  _album_key = album?.collate_key ();
            }
            if (ar != null && ar != artist) {
                changed = true;
                artist = (!)ar;
                _artist_key = artist.collate_key ();
            }
            if (ti != null && ti != title) {
                changed = true;
                title = (!)ti;
                _title_key = title.collate_key ();
            }
            return changed;
        }

        public void update_keys () {
            //  _album_key = album?.collate_key ();
            _artist_key = artist.collate_key ();
            _title_key = title.collate_key ();
        }

        public static int compare_by_title (Object obj1, Object obj2) {
            var s1 = (!)(obj1 as Song);
            var s2 = (!)(obj2 as Song);
            int ret = strcmp (s1._title_key, s2._title_key);
            if (ret == 0)
                ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret == 0)
                ret = strcmp (s1.uri, s2.uri);
            return ret;
        }

        public static int compare_by_order (Object obj1, Object obj2) {
            var s1 = (!)(obj1 as Song);
            var s2 = (!)(obj2 as Song);
            return s1.order - s2.order;
        }
    }

    public class SongStore : Object {
        private bool _shuffled = false;
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

        public bool shuffle {
            get {
                return _shuffled;
            }
            set {
                _shuffled = value;
                if (value) {
                    var count = size;
                    var arr = new GenericArray<Song> (count);
                    for (var i = 0; i < count; i++) {
                        arr.add ((!)(_store.get_item (i) as Song));
                    }
                    //  simple shuffle
                    for (var i = arr.length - 1; i > 0; i--) {
                        var r = Random.int_range (0, i);
                        var s = arr[i];
                        arr[i] = arr[r];
                        arr[r] = s;
                        arr[i].order = i;
                    }
                    _store.sort (Song.compare_by_order);
                } else {
                    _store.sort (Song.compare_by_title);
                }
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
                nie:title(nmm:musicAlbum(?song)) AS ?album
                nmm:artistName (nmm:artist (?song)) AS ?artist
                nie:title (?song) AS ?title
                nie:mimeType (?song) AS ?mtype
                nie:isStoredAs (?song) AS ?uri
            WHERE { ?song a nmm:MusicPiece }
        """;

        public async void add_sparql_async () {
            var arr = new GenericArray<Object> (4096);
            yield run_async<void> (() => {
                Tracker.Sparql.Connection connection;
                try {
                    connection = Tracker.Sparql.Connection.bus_new ("org.freedesktop.Tracker3.Miner.Files", null);
                    var cursor = connection.query (SQL_QUERY_SONGS);
                    while (cursor.next ()) {
                        var song = new Song ();
                        song.album = cursor.get_string (0) ?? UNKOWN_ALBUM;
                        song.artist = cursor.get_string (1) ?? UNKOWN_ARTIST;
                        song.title = cursor.get_string (2) ?? "";
                        song.type = cursor.get_string (3) ?? DEFAULT_MIMETYPE;
                        song.uri = cursor.get_string (4) ?? "";
                        if (song.title.length == 0)
                            song.title = parse_name_from_uri (song.uri);
                        song.update_keys ();
                        arr.add (song);
                    }
                } catch (Error e) {
                    warning ("Query error: %s\n", e.message);
                }
                if (!_shuffled)
                    arr.sort (Song.compare_by_title);
            });
            _store.splice (_store.get_n_items (), 0, arr.data);
        }
#endif

        public async void add_files_async (File[] files) {
            var arr = new GenericArray<Object> (4096);
            yield run_async<void> (() => {
                foreach (var file in files) {
                    add_file (file, arr);
                }
                if (!_shuffled)
                    arr.sort (Song.compare_by_title);
            });
            _store.splice (_store.get_n_items (), 0, arr.data);
        }

        private static void add_file (File file, GenericArray<Object> arr) {
            try {
                var info = file.query_info ("standard::*", FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new GenericArray<File> (1024);
                    stack.add (file);
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
            }
        }

        private static void add_directory (GenericArray<File> stack, GenericArray<Object> arr) {
            var last = stack.length - 1;
            var dir = stack[last];
            stack.remove_index_fast (last);
            try {
                var base_uri = get_uri_with_end_sep (dir);
                FileInfo? info = null;
                var enumerator = dir.enumerate_children ("standard::*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                while ((info = enumerator.next_file ()) != null) {
                    var pi = (!)info;
                    if (pi.get_is_hidden ()) {
                        continue;
                    } else if (pi.get_file_type () == FileType.DIRECTORY) {
                        var sub_dir = dir.resolve_relative_path (pi.get_name ());
                        stack.add (sub_dir);
                    } else {
                        var song = new_song_from_info (base_uri, pi);
                        if (song != null)
                            arr.add ((!)song);
                    }
                }
            } catch (Error e) {
                warning ("Enumerate %s: %s\n", dir.get_uri (), e.message);
            }
        }

        private static Song? new_song_from_info (string base_uri, FileInfo info) {
            var type = info.get_content_type ();
            if (type != null && ((!)type).has_prefix ("audio/") && !((!)type).has_suffix ("url")) {
                var name = info.get_name ();
                var song = new Song ();
                song.type = (!)type;
                // build same file uri as tracker sparql
                song.uri = base_uri + Uri.escape_string (name, null, false);
                if (parse_tags (song.uri, song)) {
                    // not be empty only if parsed
                    if (song.album.length == 0)
                        song.album = UNKOWN_ALBUM;
                    if (song.artist.length == 0)
                        song.artist = UNKOWN_ARTIST;
                }
                if (song.title.length == 0) {
                    // title should not be empty always
                    song.title = parse_name_from_path (name);
                }
                song.update_keys ();
                return song;
            }
            return null;
        }
    }

    public static int find_first_letter (string text) {
        var index = 0;
        var next = 0;
        var c = text.get_char (index);
        do {
            if ((c >= '0' && c <= '9')
                    || (c >= 'a' && c <= 'z')
                    || (c >= 'A' && c <= 'Z')
                    || c >= 0xff) {
                return index;
            }
            index = next;
        }  while (text.get_next_char (ref next, out c));
        return -1;
    }

    public static string get_uri_with_end_sep (File file) {
        var uri = file.get_uri ();
        if (uri[uri.length - 1] != '/')
            uri += "/";
        return uri;
    }

    public static string parse_abbreviation (string text) {
        var sb = new StringBuilder ();
        foreach (var s in text.split (" ")) {
            var index = find_first_letter (s);
            if (index >= 0) {
                sb.append (s.get_char (index).to_string ());
                if (sb.str.char_count () >= 2)
                    break;
            }
        }

        if (sb.str.char_count () >= 2) {
            return sb.str.up ();
        } else if (text.char_count () > 2) {
            var index = text.index_of_nth_char (2);
            return text.substring (0, index).up ();
        }
        return text.up ();
    }

    public static string parse_name_from_path (string path) {
        var begin = path.last_index_of_char ('/');
        var end = path.last_index_of_char ('.');
        if (end > begin)
            return path.slice (begin + 1, end);
        else if (begin > 0)
            return path.slice (begin + 1, path.length);
        return path;
    }

    public static string parse_name_from_uri (string uri) {
        try {
            var u = Uri.parse (uri, UriFlags.NONE);
            return parse_name_from_path (u.get_path ());
        } catch (Error e) {
            warning ("Parse %s: %s\n", uri, e.message);
        }
        return uri;
    }
}
