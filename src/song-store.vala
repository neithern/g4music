namespace Music {
    public const string UNKOWN_ALBUM = _("Unknown Album");
    public const string UNKOWN_ARTIST = _("Unknown Aritst");
    public const string DEFAULT_MIMETYPE = "audio/mpeg";

    public enum TagType {
        NONE,
        GST,
        TAGLIB,
        SPARQL
    }

    public class Song : Object {
        public string album = "";
        public string artist = "";
        public string title = "";
        public string uri = "";
        public uint track = int.MAX;
        public TagType ttype = TagType.NONE;

        private string _album_key = "";
        private string _artist_key = "";
        private string _title_key = "";
        private string? _cover_uri = null;
        private int _order = 0;

        public string cover_uri {
            get {
                return _cover_uri ?? uri;
            }
            set {
                _cover_uri = value;
            }
        }

        public void init_from_gst_tags (Gst.TagList? tags) {
            string? al = null, ar = null, ti = null;
            if (tags != null) {
                tags?.get_string (Gst.Tags.ALBUM, out al);
                tags?.get_string (Gst.Tags.ARTIST, out ar);
                tags?.get_string (Gst.Tags.TITLE, out ti);
                tags?.get_uint (Gst.Tags.TRACK_NUMBER, out track);
            }
            this.album = (al != null && al?.length > 0) ? (!)al : UNKOWN_ALBUM;
            this.artist = (ar != null && ar?.length > 0) ? (!)ar : UNKOWN_ARTIST;
            if (ti != null && ti?.length > 0)
                this.title = (!)ti;
            this.ttype = TagType.GST;
            update_keys ();
        }

#if HAS_TAGLIB_C
        public void init_from_taglib (TagLib.File file) {
            string? al = null, ar = null, ti = null;
            if (file.is_valid ()) {
                unowned var tags = file.tag;
                al = tags.album;
                ar = tags.artist;
                ti = tags.title;
                track = tags.track;
            }
            this.album = (al != null && al?.length > 0) ? (!)al : UNKOWN_ALBUM;
            this.artist = (ar != null && ar?.length > 0) ? (!)ar : UNKOWN_ARTIST;
            if (ti != null && ti?.length > 0)
                this.title = (!)ti;
            this.ttype = TagType.TAGLIB;
            update_keys ();
        }
#endif

        public bool update (string? al, string? ar, string? ti) {
            bool changed = false;
            if (al != null && al != album) {
                changed = true;
                album = (!)al;
                _album_key = album.collate_key ();
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
            _album_key = album.collate_key ();
            _artist_key = artist.collate_key ();
            _title_key = title.collate_key ();
        }

        public static int compare_by_album (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            int ret = strcmp (s1._album_key, s2._album_key);
            if (ret == 0)
                ret = (int) (s1.track - s2.track);
            if (ret == 0)
                ret = strcmp (s1._title_key, s2._title_key);
            if (ret == 0)
                ret = strcmp (s1.uri, s2.uri);
            return ret;
        }

        public static int compare_by_artist (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            int ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret == 0)
                ret = strcmp (s1._title_key, s2._title_key);
            if (ret == 0)
                ret = strcmp (s1.uri, s2.uri);
            return ret;
        }

        public static int compare_by_title (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            int ret = strcmp (s1._title_key, s2._title_key);
            if (ret == 0)
                ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret == 0)
                ret = strcmp (s1.uri, s2.uri);
            return ret;
        }

        public static int compare_by_order (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            return s1._order - s2._order;
        }

        public static void shuffle_order (GenericArray<Object> arr) {
            for (var i = arr.length - 1; i > 0; i--) {
                var r = Random.int_range (0, i);
                var s = arr[i];
                arr[i] = arr[r];
                arr[r] = s;
                ((Song)arr[i])._order = i;
            }
        }
    }

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
            var path = file.get_path ();
            var name = song.title;
            song.title = "";
            if (path != null) { // parse local path only
#if HAS_TAGLIB_C
                var tf = new TagLib.File ((!)path);
                song.init_from_taglib (tf);
#else
                var tags = parse_gst_tags (file);
                song.init_from_gst_tags (tags);
#endif
            }
            if (song.title.length == 0) {
                // title should not be empty always
                song.title = parse_name_from_path (name);
                song.update_keys ();
            }
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
