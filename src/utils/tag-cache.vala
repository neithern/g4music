namespace G4 {

    public class TagCache {
        private static uint32 MAGIC = 0x54414743; //  'TAGC'

        private File _file;
        private bool _loaded = false;
        private bool _modified = false;
        private HashTable<unowned string, Music> _cache = new HashTable<unowned string, Music> (str_hash, str_equal);

        public TagCache (string name = "tag-cache") {
            var dir = Environment.get_user_cache_dir ();
            _file = File.new_build_filename (dir, Config.APP_ID, name);
        }

        public bool loaded {
            get {
                return _loaded;
            }
        }

        public bool modified {
            get {
                return _modified;
            }
        }

        public Music? @get (string uri) {
            unowned string key;
            unowned Music music;
            lock (_cache) {
                if (_cache.lookup_extended (uri, out key, out music)) {
                    return music;
                }
            }
            return null;
        }

        public void add (Music music) {
            lock (_cache) {
                _cache[music.uri] = music;
                _modified = true;
            }
        }

        public void remove (string uri) {
            lock (_cache) {
                _cache.remove (uri);
                _modified = true;
            }
        }

        public void load () {
            try {
                var fis = _file.read ();
                var bis = new BufferedInputStream (fis);
                bis.buffer_size = 16384;
                var dis = new DataInputStream (bis);
                var magic = dis.read_uint32 ();
                if (magic != MAGIC)
                    throw new IOError.INVALID_DATA (@"Magic=$magic");

                var count = read_size (dis);
                lock (_cache) {
                    for (var i = 0; i < count; i++) {
                        var music = new Music.deserialize (dis);
                        _cache[music.uri] = music;
                    }
                }
            } catch (Error e) {
                if (e.code != IOError.NOT_FOUND)
                    print ("Load tags error: %s\n", e.message);
            }
            _loaded = true;
        }

        public void save () {
            try {
                var parent = _file.get_parent ();
                var exists = parent?.query_exists () ?? false;
                if (!exists)
                    parent?.make_directory_with_parents ();
                var fos = _file.replace (null, false, FileCreateFlags.NONE);
                var bos = new BufferedOutputStream (fos);
                bos.buffer_size = 16384;
                var dos = new DataOutputStream (bos);
                dos.put_uint32 (MAGIC);
                lock (_cache) {
                    write_size (dos, _cache.length);
                    _cache.for_each ((key, music) => {
                        try {
                            music.serialize (dos);
                        } catch (Error e) {
                        }
                    });
                }
                _modified = false;
            } catch (Error e) {
                print ("Save tags error: %s\n", e.message);
            }
        }
    }
}
