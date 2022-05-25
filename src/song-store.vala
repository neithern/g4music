namespace Music {

    public class SongInfo : Object {
        public string album;
        public string artist;
        public string title;
    }

    public class Song : SongInfo {
        public string type;
        public string url;
        public string? thumbnail;
        public long mtime = 0;
        public int order = 0;

        //  private string _album_key;
        private string _artist_key;
        private string _title_key;

        public bool from_info (SongInfo info) {
            bool changed = false;
            changed = album != info.album;
            if (changed && info.album != null) {
                album = info.album;
                //  _album_key = album?.collate_key ();
            }
            changed = artist != info.artist;
            if (changed && info.artist != null) {
                artist = info.artist;
                _artist_key = artist?.collate_key ();
            }
            changed = title != info.title;
            if (changed && info.title != null) {
                title = info.title;
                _title_key = title?.collate_key ();
            }
            return changed;
        }

        public void update_keys () {
            //  _album_key = album?.collate_key ();
            _artist_key = artist?.collate_key ();
            _title_key = title?.collate_key ();
        }

        public static int compare_by_title (Object obj1, Object obj2) {
            var s1 = obj1 as Song;
            var s2 = obj2 as Song;
            int ret = strcmp (s1._title_key, s2._title_key);
            if (ret == 0)
                ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret == 0)
                ret = strcmp (s1.url, s2.url);
            return ret;
        }

        public static int compare_by_order (Object obj1, Object obj2) {
            var s1 = obj1 as Song;
            var s2 = obj2 as Song;
            return s1.order - s2.order;
        }
    }

    public class SongStore : Object {
        public static string UNKOWN_ALBUM = "Unknown Album";
        public static string UNKOWN_ARTIST = "Unknown Aritst";
        public static string DEFAULT_MIMETYPE = "audio/mpeg";

        public static string SQL_QUERY_SONGS = """
            SELECT 
                nie:title(nmm:musicAlbum(?song)) AS ?album
                nmm:artistName (nmm:artist (?song)) AS ?artist
                nie:title (?song) AS ?title
                nie:mimeType (?song) AS ?mtype
                nie:isStoredAs (?song) AS ?url
            WHERE { ?song a nmm:MusicPiece }
        """.replace ("\n", " ");

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
                    var count = (int) size;
                    var arr = new GenericArray<Song> (count);
                    for (var i = 0; i < count; i++) {
                        arr.add (_store.get_item (i) as Song);
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

        public Song? get_song (uint position) {
            return _store.get_item (position) as Song;
        }

        public async void add_sparql_async () {
            var arr = new GenericArray<Object> (4096);
            Tracker.Sparql.Connection connection = null;
            try {
                connection = yield Tracker.Sparql.Connection.bus_new_async ("org.freedesktop.Tracker3.Miner.Files", null);
                var cursor = yield connection.query_async (SQL_QUERY_SONGS);
                while (yield cursor.next_async ()) {
                    var song = new Song ();
                    song.album = cursor.get_string (0) ?? UNKOWN_ALBUM;
                    song.artist = cursor.get_string (1) ?? UNKOWN_ARTIST;
                    song.title = cursor.get_string (2);
                    song.type = cursor.get_string (3) ?? DEFAULT_MIMETYPE;
                    song.url = cursor.get_string (4);
                    if (song.title == null)
                        song.title = parse_name_from_url (song.url);
                    song.update_keys ();
                    arr.add (song);
                }
            } catch (Error e) {
                warning ("Query error: %s\n", e.message);
            } finally {
                connection?.close ();
            }
            _store.splice (_store.get_n_items (), 0, arr.data);
        }

        public async void add_files_async (owned File[] files) {
            var arr = new GenericArray<Object> (4096);
            foreach (var file in files) {
                yield add_file_async (file, arr);
            }
            _store.splice (_store.get_n_items (), 0, arr.data);
        }

        private async void add_file_async (File file, GenericArray<Object> arr) {
            try {
                var info = yield file.query_info_async ("standard::*", FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    yield add_directory_async (file, arr);
                } else {
                    var type = info.get_content_type ();
                    if (type?.ascii_ncasecmp ("audio/", 6) == 0) {
                        var song = new_song_file_info ("", info);
                        song.url = file.get_uri ();
                        var sinfo = yield parse_tags_async (song.url);
                        if (sinfo != null)
                            song.from_info (sinfo);
                        arr.add (song);
                    }
                }
            } catch (Error e) {
            }
        }

        private async void add_directory_async (File dir, GenericArray<Object> arr) {
            try {
                var base_uri = dir.get_uri ();
                if (base_uri[base_uri.length - 1] != '/')
                    base_uri += "/";
                FileInfo info = null;
                var enumerator = yield dir.enumerate_children_async ("standard::*", FileQueryInfoFlags.NONE);
                while ((info = enumerator.next_file ()) != null) {
                    if (info.get_is_hidden ()) {
                        continue;
                    } else if (info.get_file_type () == FileType.DIRECTORY) {
                        var sub_dir = dir.resolve_relative_path (info.get_name ());
                        yield add_directory_async (sub_dir, arr);
                    } else {
                        var type = info.get_content_type ();
                        if (type?.ascii_ncasecmp ("audio/", 6) == 0) {
                            var song = new_song_file_info (base_uri, info, type);
                            var sinfo = yield parse_tags_async (song.url);
                            if (sinfo != null)
                                song.from_info (sinfo);
                            arr.add (song);
                        }
                    }
                }
            } catch (Error e) {
                warning ("Enumerate %s: %s\n", dir.get_path (), e.message);
            }
        }

        private static Song new_song_file_info (string base_uri, FileInfo info, string? type = null) {
            var name = info.get_name ();
            var song = new Song ();
            song.album = UNKOWN_ALBUM;
            song.artist = UNKOWN_ARTIST;
            song.title = parse_name_from_path (name);
            song.type = type ?? info.get_content_type ();
            song.url = base_uri + name;
            song.update_keys ();
            return song;
        }
    }

    public static string parse_abbreviation (string text) {
        var pos = text.last_index_of_char (' ');
        if (pos > 0 && pos < text.length - 1) {
            unichar c = ' ';
            pos++; // skip current ' '
            if (text.get_next_char (ref pos, out c))
                return text.get_char (0).to_string () + c.to_string ();
        } else if (text.char_count () > 2) {
            unichar c = ' ';
            pos = 0;
            if (text.get_next_char (ref pos, out c) && text.get_next_char (ref pos, out c))
                return text.substring (0, pos);
        }
        return text;
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

    public static string parse_name_from_url (string url) {
        try {
            var uri = Uri.parse (url, UriFlags.NONE);
            return parse_name_from_path (uri.get_path ());
        } catch (Error e) {
            warning ("Parse %s: %s\n", url, e.message);
        }
        return url;
    }
}