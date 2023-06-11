namespace G4 {

    public class TagCache {
        private static uint32 MAGIC = 0x54414743; //  'TAGC'

        private Cond _cond = Cond ();
        private Mutex _mutex = Mutex ();
        private File _file;
        private bool _loading = false;
        private bool _modified = false;
        private HashTable<unowned string, Music> _cache = new HashTable<unowned string, Music> (str_hash, str_equal);

        public TagCache (string name = "tag-cache") {
            var dir = Environment.get_user_cache_dir ();
            _file = File.new_build_filename (dir, Config.APP_ID, name);
        }

        public bool modified {
            get {
                return _modified;
            }
        }

        public Music? @get (string uri) {
            unowned string key;
            unowned Music music;
            if (_cache.lookup_extended (uri, out key, out music)) {
                return music;
            }
            return null;
        }

        public void add (Music music) {
            _cache[music.uri] = music;
            _modified = true;
        }

        public void remove (Music music) {
            if (_cache.remove (music.uri))
                _modified = true;
        }

        public void load () {
            _loading = true;
            try {
                var mapped = new MappedFile (_file.get_path () ?? "", false);
                var dis = new DataInputBytes (mapped.get_bytes ());
                var magic = dis.read_uint32 ();
                if (magic != MAGIC)
                    throw new IOError.INVALID_DATA (@"Magic=$magic");

                var count = dis.read_size ();
                for (var i = 0; i < count; i++) {
                    var music = new Music.deserialize (dis);
                    _cache[music.uri] = music;
                }
            } catch (Error e) {
                if (e.code != FileError.NOENT)
                    print ("Load tags error: %s\n", e.message);
            }
            _mutex.lock ();
            _loading = false;
            _cond.broadcast ();
            _mutex.unlock ();
        }

        public void save () {
            _loading = true;
            try {
                var parent = _file.get_parent ();
                var exists = parent?.query_exists () ?? false;
                if (!exists)
                    parent?.make_directory_with_parents ();
                var fos = _file.replace (null, false, FileCreateFlags.NONE);
                var dos = new DataOutputBytes ();
                dos.write_uint32 (MAGIC);
                dos.write_size (_cache.length);
                _cache.for_each ((key, music) => {
                    try {
                        music.serialize (dos);
                    } catch (Error e) {
                    }
                });
                _modified = !dos.write_to (fos);
            } catch (Error e) {
                print ("Save tags error: %s\n", e.message);
            }
            _mutex.lock ();
            _loading = false;
            _cond.broadcast ();
            _mutex.unlock ();
        }

        public void wait_loading () {
            _mutex.lock ();
            while (_loading)
                _cond.wait (_mutex);
            _mutex.unlock ();
        }
    }
}
