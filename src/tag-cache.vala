namespace Music {

    public class TagCache {
        private File _file;
        private bool _loaded = false;
        private bool _modified = false;
        private HashTable<weak string, Song> _cache = new HashTable<weak string, Song> (str_hash, str_equal);

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

        public Song? @get (string uri) {
            weak string key;
            weak Song song;
            lock (_cache) {
                if (_cache.lookup_extended (uri, out key, out song)) {
                    return song;
                }
            }
            return null;
        }

        public void add (Song song) {
            lock (_cache) {
                _cache[song.uri] = song;
                _modified = true;
            }
        }

        public void load () {
            try {
                var fis = _file.read ();
                var bis = new BufferedInputStream (fis);
                bis.buffer_size = 16384;
                var dis = new DataInputStream (bis);
                var count = dis.read_uint32 ();
                lock (_cache) {
                    for (var i = 0; i < count; i++) {
                        Song song = new Song ();
                        song.deserialize (dis);
                        _cache[song.uri] = song;
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
                lock (_cache) {
                    dos.put_uint32 (_cache.length);
                    _cache.for_each ((key, song) => {
                        try {
                            song.serialize (dos);
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