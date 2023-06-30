namespace G4 {

    public class CoverCache : Object {
        private HashTable<string, string?> _cache = new HashTable<string, string?> (str_hash, str_equal);

        private const string ATTRIBUTES = FileAttribute.STANDARD_CONTENT_TYPE + ","
                                        + FileAttribute.STANDARD_NAME;

        public File? find (File? parent) {
            if (parent == null)
                return null;

            var dir = (!)parent;
            var uri = dir.get_uri ();
            lock (_cache) {
                var cover_uri = _cache[uri];
                if (cover_uri == null) {
                    var cover_file = find_no_lock (dir);
                    cover_uri = cover_file?.get_uri () ?? "";
                    _cache[uri] = cover_uri;
                }
                return ((!)cover_uri).length > 0 ? File.new_for_uri ((!)cover_uri) : (File?) null;
            }
        }

        public void put (File dir, string child) {
            var uri = dir.get_uri ();
            var cover_file = dir.get_child ((!)child);
            var cover_uri = cover_file.get_uri ();
            lock (_cache) {
                _cache[uri] = cover_uri;
            }
        }

        private static File? find_no_lock (File dir) {
            try {
                FileInfo? pi = null;
                var enumerator = dir.enumerate_children (ATTRIBUTES, FileQueryInfoFlags.NONE);
                while ((pi = enumerator.next_file ()) != null) {
                    var info = (!)pi;
                    unowned var ctype = info.get_content_type () ?? "";
                    unowned var name = info.get_name ();
                    if (is_cover_file (ctype, name)) {
                        //  print ("Find external cover: %s\n", name);
                        return dir.get_child (name);
                    }
                }
            } catch (Error e) {
            }
            return null;
        }
    }

    public bool is_cover_file (string content_type, string name) {
        return ContentType.is_mime_type (content_type, "image/*")
                && (name.ascii_ncasecmp ("Cover", 5) == 0
                || name.ascii_ncasecmp ("Folder", 6) == 0
                || name.ascii_ncasecmp ("AlbumArt", 8) == 0);
    }
}