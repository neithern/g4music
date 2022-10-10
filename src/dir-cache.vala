namespace Music {

    public class DirCache : Object {
        private static uint32 MAGIC = 0x43524944; //  'DIRC'

        private class ChildInfo {
            public string name;
            public int64 time;
    
            public ChildInfo (string name, int64 time) {
                this.name = name;
                this.time = time;
            }
        }

        private File _dir;
        private File _file;
        private GenericArray<ChildInfo> _children = new GenericArray<ChildInfo> ();

        public DirCache (File dir) {
            _dir = dir;
            var cache_dir = Environment.get_user_cache_dir ();
            var name = Checksum.compute_for_string (ChecksumType.MD5, dir.get_uri ());
            _file = File.new_build_filename (cache_dir, Config.APP_ID, "dir-cache", name);
        }

        public bool check_valid () {
            try {
                var dt = _dir.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE).get_modification_date_time ();
                var dt2 = _file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE).get_modification_date_time ();
                if (dt != null && dt2 != null)
                    return ((!)dt).compare ((!)dt2) <= 0;
            } catch (Error e) {
            }
            return false;
        }

        public void add_child (Song song) {
            var info = new ChildInfo (song.title, song.modified_time);
            _children.add (info);
        }

        public void load_as_songs (GenericArray<Object> songs) {
            try {
                var fis = _file.read ();
                var bis = new BufferedInputStream (fis);
                bis.buffer_size = 16384;
                var dis = new DataInputStream (bis);

                var magic = dis.read_uint32 ();
                if (magic != MAGIC)
                    throw new IOError.INVALID_DATA (@"Magic:$magic");
                var uri = dis.read_upto ("\0", 1, null);
                dis.read_byte (); // == '\0'
                if (uri != _dir.get_uri ())
                    throw new IOError.INVALID_DATA (@"Uri:$uri");

                var count = dis.read_int32 ();
                for (var i = 0; i < count; i++) {
                    var name = dis.read_upto ("\0", 1, null);
                    dis.read_byte (); // == '\0'
                    var time = dis.read_int64 ();
                    var song = new Song ();
                    song.uri = _dir.get_child (name).get_uri ();
                    song.title = name;
                    song.modified_time = time;
                    songs.add (song);
                }
            } catch (Error e) {
                if (e.code != IOError.NOT_FOUND)
                    print ("Load dirs error: %s\n", e.message);
            }
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
                dos.put_string (_dir.get_uri ());
                dos.put_byte ('\0');
                dos.put_int32 (_children.length);
                foreach (var info in _children) {
                    dos.put_string (info.name);
                    dos.put_byte ('\0');
                    dos.put_int64 (info.time);
                }
            } catch (Error e) {
                print ("Save dirs error: %s\n", e.message);
            }
        }
    }
}