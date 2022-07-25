namespace Music {
    public const string DEFAULT_MIMETYPE = "audio/mpeg";
    public const string UNKOWN_ALBUM = _("Unknown Album");
    public const string UNKOWN_ARTIST = _("Unknown Artist");
    public const int UNKOWN_TRACK = int.MAX;

    public class Song : Object {
        public string album = "";
        public string artist = "";
        public string title = "";
        public string uri = "";
        public int track = UNKOWN_TRACK;
        public int64 modified_time = 0;

        //  for sorting
        private string _album_key = "";
        private string _artist_key = "";
        private string _title_key = "";
        private int _order = 0;

        private string? _cover_uri = null;

        public unowned string cover_uri {
            get {
                return _cover_uri ?? uri;
            }
            set {
                _cover_uri = value;
            }
        }

        public bool from_gst_tags (Gst.TagList tags) {
            var changed = false;
            unowned string? al = null, ar = null, ti = null;
            if (tags.peek_string_index (Gst.Tags.ALBUM, 0, out al)
                    && al != null && al?.length > 0 && album != (!)al) {
                album = (!)al;
                update_album_key ();
                changed = true;
            }
            if (tags.peek_string_index (Gst.Tags.ARTIST, 0, out ar)
                    && ar != null && ar?.length > 0 && artist != (!)ar) {
                artist = (!)ar;
                update_artist_key ();
                changed = true;
            }
            if (tags.peek_string_index (Gst.Tags.TITLE, 0, out ti)
                    && ti != null && ti?.length > 0 && title != (!)ti) {
                title = (!)ti;
                update_title_key ();
                changed = true;
            }
            uint tr = 0;
            if (tags.get_uint (Gst.Tags.TRACK_NUMBER, out tr)
                    && (int) tr > 0 && track != tr) {
                track = (int) tr;
                changed = true;
            }
            return changed;
        }

        public void update_album_key () {
            _album_key = album.collate_key_for_filename ();
        }

        public void update_artist_key () {
            _artist_key = artist.collate_key_for_filename ();
        }

        public void update_title_key () {
            _title_key = title.collate_key_for_filename ();
        }

        public void serialize (DataOutputStream dos) throws IOError {
            dos.put_byte (6);
            dos.put_string (album);
            dos.put_byte ('\0');
            dos.put_string (artist);
            dos.put_byte ('\0');
            dos.put_string (title);
            dos.put_byte ('\0');
            dos.put_int32 (track);
            dos.put_int64 (modified_time);
            dos.put_string (uri);
            dos.put_byte ('\0');
        }

        public void deserialize (DataInputStream dis) throws IOError {
            var count = dis.read_byte ();
            if (count != 6)
                throw new IOError.INVALID_DATA (@"$count != 5");
            album = dis.read_upto ("\0", 1, null);
            update_album_key ();
            dis.read_byte (); // == '\0'
            artist = dis.read_upto ("\0", 1, null);
            update_artist_key ();
            dis.read_byte (); // == '\0'
            title = dis.read_upto ("\0", 1, null);
            update_title_key ();
            dis.read_byte (); // == '\0'
            track = dis.read_int32 ();
            modified_time = dis.read_int64 ();
            uri = dis.read_upto ("\0", 1, null);
            dis.read_byte (); // == '\0'
        }

        public static int compare_by_album (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            int ret = strcmp (s1._album_key, s2._album_key);
            if (ret != 0) return ret;
            ret = s1.track - s2.track;
            if (ret != 0) return ret;
            ret = strcmp (s1._title_key, s2._title_key);
            if (ret != 0) return ret;
            return strcmp (s1.uri, s2.uri);
        }

        public static int compare_by_artist (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            int ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret != 0) return ret;
            ret = strcmp (s1._title_key, s2._title_key);
            if (ret != 0) return ret;
            return strcmp (s1.uri, s2.uri);
        }

        public static int compare_by_title (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            int ret = strcmp (s1._title_key, s2._title_key);
            if (ret != 0) return ret;
            ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret != 0) return ret;
            return strcmp (s1.uri, s2.uri);
        }

        public static int compare_by_order (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            return s1._order - s2._order;
        }

        public static int compare_by_date_ascending (Object obj1, Object obj2) {
            var s1 = (Song) obj1;
            var s2 = (Song) obj2;
            var diff = s2.modified_time - s1.modified_time;

            return (int) diff.clamp (-1, 1);
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

    public static int find_first_letter (string text) {
        var index = 0;
        var next = 0;
        var c = text.get_char (0);
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

    public static string get_display_name (File dir) {
        var name = dir.get_basename () ?? "";
        if (name.length == 0 || name == "/")
            name = dir.get_parse_name ();
        return name;
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
}
