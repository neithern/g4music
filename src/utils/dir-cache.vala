namespace G4 {

    namespace FileType {
        public const uint8 UNKNOWN = 0;
        public const uint8 DIRECTORY = 1;
        public const uint8 MUSIC = 2;
        public const uint8 PLAYLIST = 3;
        public const uint8 COVER = 4;
    }

    public class DirCache : Object {
        private static uint32 MAGIC = 0x44495244; //  'DIRD'

        private class ChildInfo {
            public uint8 type;
            public string name;
            public int64 time;
    
            public ChildInfo (uint8 type, string name, int64 time) {
                this.type = type;
                this.name = name;
                this.time = time;
            }
        }

        private File _dir;
        private File _file;
        private int64 _time;
        private GenericArray<ChildInfo> _children = new GenericArray<ChildInfo> (128);

        public DirCache (File dir, FileInfo? info = null) {
            _dir = dir;
            var cache_dir = Environment.get_user_cache_dir ();
            var name = Checksum.compute_for_string (ChecksumType.MD5, dir.get_uri ());
            _file = File.new_build_filename (cache_dir, Config.APP_ID, "dir-cache", name);
            _time = info?.get_modification_date_time ()?.to_unix () ?? 0;
        }

        public File dir {
            get {
                return _dir;
            }
        }

        public bool check_valid () {
            try {
                if (_time == 0) {
                    var info = _dir.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                    _time = info.get_modification_date_time ()?.to_unix () ?? 0;
                }
                var info = _file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                return _time <= (info.get_modification_date_time ()?.to_unix () ?? 0);
            } catch (Error e) {
            }
            return false;
        }

        public void delete () {
            _file.delete_async.begin (Priority.DEFAULT, null, (obj, res) => {
                try {
                    _file.delete_async.end (res);
                } catch (Error e) {
                }
            });
        }

        public void add_child (FileInfo info, uint8 type) {
            var time = info.get_modification_date_time ()?.to_unix () ?? 0;
            var child = new ChildInfo (type, info.get_name (), time);
            _children.add (child);
        }

        public bool load (Queue<DirCache> stack, GenericArray<Music> musics, GenericArray<File>? playlists, out string? cover_name) {
            cover_name = null;
            try {
                var mapped = new MappedFile (_file.get_path () ?? "", false);
                var dis = new DataInputBytes (mapped.get_bytes ());

                var magic = dis.read_uint32 ();
                if (magic != MAGIC)
                    throw new IOError.INVALID_DATA (@"Magic:$magic");
                var base_name = _dir.get_basename () ?? "";
                var bname = dis.read_string ();
                if (bname != base_name)
                    throw new IOError.INVALID_DATA (@"Name:$bname!=$base_name");

                var count = dis.read_size ();
                for (var i = 0; i < count; i++) {
                    var type = dis.read_byte ();
                    var name = dis.read_string ();
                    var time = (int64) dis.read_uint64 ();
                    var child = _dir.get_child (name);
                    if (type == FileType.MUSIC) {
                        musics.add (new Music (child.get_uri (), name, time));
                    } else if (type == FileType.DIRECTORY) {
                        stack.push_head (new DirCache (child));
                    } else if (type == FileType.PLAYLIST) {
                        playlists?.add (child);
                    } else if (type == FileType.COVER) {
                        cover_name = name;
                    }
                }
                return true;
            } catch (Error e) {
                if (e.code != FileError.NOENT)
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
                var dos = new DataOutputBytes ();
                dos.write_uint32 (MAGIC);
                dos.write_string (_dir.get_basename () ?? "");
                dos.write_size (_children.length);
                foreach (var child in _children) {
                    dos.write_byte (child.type);
                    dos.write_string (child.name);
                    dos.write_uint64 (child.time);
                }
                dos.write_to (fos);
            } catch (Error e) {
                print ("Save dirs error: %s\n", e.message);
            }
        }
    }
}
