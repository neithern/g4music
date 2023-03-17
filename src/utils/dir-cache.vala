namespace G4 {

    public class DirCache : Object {
        private static uint32 MAGIC = 0x44495243; //  'DIRC'

        private class ChildInfo {
            public FileType type;
            public string name;
            public int64 time;
    
            public ChildInfo (FileType type, string name, int64 time) {
                this.type = type;
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

        public void add_child (FileInfo info) {
            var time = info.get_modification_date_time ()?.to_unix () ?? 0;
            var child = new ChildInfo (info.get_file_type (), info.get_name (), time);
            _children.add (child);
        }

        public bool load (Queue<File> stack, GenericArray<Object> musics) {
            try {
                var fis = _file.read ();
                var bis = new BufferedInputStream (fis);
                bis.buffer_size = 16384;
                var dis = new DataInputStream (bis);

                var magic = dis.read_uint32 ();
                if (magic != MAGIC)
                    throw new IOError.INVALID_DATA (@"Magic:$magic");
                var base_name = _dir.get_basename () ?? "";
                var bname = read_string (dis);
                if (bname != base_name)
                    throw new IOError.INVALID_DATA (@"Basename:$bname!=$base_name");

                var count = read_size (dis);
                for (var i = 0; i < count; i++) {
                    var type = dis.read_byte ();
                    var name = read_string (dis);
                    var time = dis.read_int64 ();
                    if (type == FileType.DIRECTORY) {
                        stack.push_head (_dir.get_child (name));
                    } else {
                        var music = new Music (_dir.get_child (name).get_uri (), name, time);
                        musics.add (music);
                    }
                }
                return true;
            } catch (Error e) {
                if (e.code != IOError.NOT_FOUND)
                    print ("Load dirs error: %s\n", e.message);
            }
            return false;
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
                write_string (dos, _dir.get_basename () ?? "");
                write_size (dos, _children.length);
                foreach (var child in _children) {
                    dos.put_byte (child.type);
                    write_string (dos, child.name);
                    dos.put_int64 (child.time);
                }
            } catch (Error e) {
                print ("Save dirs error: %s\n", e.message);
            }
        }
    }
}
