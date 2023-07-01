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
            string? child = null;
            lock (_cache) {
                child = _cache[uri];
                if (child == null) {
                    child = find_no_lock (dir);
                    _cache[uri] = child ?? "";
                }
            }
            if (child == null || ((!)child).length == 0)
                return (File?) null;
            return dir.get_child ((!)child);
        }

        public void put (File dir, string child) {
            var uri = dir.get_uri ();
            lock (_cache) {
                _cache[uri] = child;
            }
        }

        private static string? find_no_lock (File dir) {
            try {
                FileInfo? pi = null;
                var enumerator = dir.enumerate_children (ATTRIBUTES, FileQueryInfoFlags.NONE);
                while ((pi = enumerator.next_file ()) != null) {
                    var info = (!)pi;
                    unowned var ctype = info.get_content_type () ?? "";
                    unowned var name = info.get_name ();
                    if (is_cover_file (ctype, name)) {
                        //  print ("Find external cover: %s\n", name);
                        return name;
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