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

        private ListStore _store = new ListStore (typeof (Song));

        public ListStore store { get { return _store; } }

        public uint size { get { return _store.get_n_items (); } }

        public Song? get_song (uint position) {
            return _store.get_item (position) as Song;
        }

        public void item_changed (uint position) {
            _store.items_changed (position, 0, 0);
        }

        public void shuffle () {
            var count = (int) size;
            var arr = new GenericArray<Song> (count);
            for (var i = 0; i < count; i++) {
                arr.add (_store.get_item (i) as Song);
            }
            //  simple huffle
            for (var i = arr.length - 1; i > 0; i--) {
                var r = Random.int_range (0, i);
                var s = arr[i];
                arr[i] = arr[r];
                arr[r] = s;
                arr[i].order = i;
            }
            _store.sort (Song.compare_by_order);
        }

        public void sort () {
            _store.sort (Song.compare_by_title);
        }

        public async uint query_async () {
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

            arr.sort (Song.compare_by_title);
            _store.splice (0, 0, arr.data);
            return arr.length;
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

    public static string parse_name_from_url (string url) {
        try {
            var uri = Uri.parse (url, UriFlags.NONE);
            var path = uri.get_path ();
            var begin = path.last_index_of_char ('/');
            var end = path.last_index_of_char ('.');
            if (end > begin)
                return path.slice (begin + 1, end);
            else if (begin > 0)
                return path.slice (begin + 1, path.length);
        } catch (Error e) {
            warning ("Parse %s: %s\n", url, e.message);
        }
        return url;
    }
}