namespace G4 {

    public class TagCache {
        private static uint32 MAGIC = 0x54414732; //  'TAG2'

        private Event _event = new Event ();
        private File _file;
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

        public Music? remove (string uri) {
            string key;
            Music value;
            if (_cache.steal_extended (uri, out key, out value)) {
                _modified = true;
                return value;
            }
            return null;
        }

        public void load () {
            _event.reset ();
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
            _event.notify ();
        }

        public void save () {
            _event.reset ();
            try {
                var parent = _file.get_parent ();
                var exists = parent?.query_exists () ?? false;
                if (!exists)
                    parent?.make_directory_with_parents ();
                var fos = _file.replace (null, false, FileCreateFlags.NONE);
                var dos = new DataOutputBytes ();
                dos.write_uint32 (MAGIC);
                dos.write_size (_cache.length);
                _cache.foreach ((key, music) => {
                    try {
                        music.serialize (dos);
                    } catch (Error e) {
                    }
                });
                _modified = !dos.write_to (fos);
            } catch (Error e) {
                print ("Save tags error: %s\n", e.message);
            }
            _event.notify ();
        }

        public void wait_loading () {
            _event.wait ();
        }
    }
}
