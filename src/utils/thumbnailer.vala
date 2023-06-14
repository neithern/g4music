namespace G4 {

    public class CoverFinder : Object {
        private HashTable<string, string?> _cache = new HashTable<string, string?> (str_hash, str_equal);

        private const string ATTRIBUTES = FileAttribute.STANDARD_CONTENT_TYPE + ","
                                        + FileAttribute.STANDARD_NAME;

        public File? find (File file) {
            var parent = file.get_parent ();
            if (parent == null)
                return null;

            var dir = (!)parent;
            var uri = dir.get_uri ();
            lock (_cache) {
                var art_uri = _cache[uri];
                if (art_uri == null) {
                    var art_file = find_no_lock (dir);
                    art_uri = art_file?.get_uri () ?? "";
                    _cache[uri] = art_uri;
                }
                return ((art_uri?.length ?? 0) > 0) ? File.new_for_uri ((!)art_uri) : (File?) null;
            }
        }

        private static File? find_no_lock (File dir) {
            try {
                FileInfo? pi = null;
                var enumerator = dir.enumerate_children (ATTRIBUTES, FileQueryInfoFlags.NONE);
                while ((pi = enumerator.next_file ()) != null) {
                    var info = (!)pi;
                    unowned var type = info.get_content_type () ?? "";
                    if (ContentType.is_mime_type (type, "image/*")) {
                        unowned var name = info.get_name ();
                        if (name.ascii_ncasecmp ("Cover", 5) == 0
                            || name.ascii_ncasecmp ("Folder", 6) == 0
                            || name.ascii_ncasecmp ("AlbumArt", 8) == 0) {
                            //  print ("Find external cover: %s\n", name);
                            return dir.get_child (name);
                        }
                    }
                }
            } catch (Error e) {
            }
            return null;
        }
    }

    //  Sorted by insert order
    public class LruCache<V> : Object {
        private size_t _max_size = 0;
        private size_t _size = 0;
        private HashTable<string, V> _cache = new HashTable<string, V> (str_hash, str_equal);
        private Queue<string> _queue = new Queue<string> ();

        public LruCache (size_t max_size) {
            _max_size = max_size;
        }

        public V find (string key) {
            return _cache[key];
        }

        public void put (string key, V value, bool replace = false) {
            if (replace) {
                remove (key);
            } else if (_cache.contains (key)) {
                return;
            }

            var size = size_of_value (value);
            while (_size + size > _max_size && _queue.length > 0) {
                string stolen_key;
                V stolen_value;
                if (_cache.steal_extended (_queue.pop_head (), out stolen_key, out stolen_value)) {
                    _size -= size_of_value (stolen_value);
                }
            }

            _cache[key] = value;
            _queue.push_tail (key);
            _size += size;
            //  print (@"Cache $(_cache.length)/$(_queue.length) items, $_size bytes\n");
        }

        public bool remove (string key) {
            string stolen_key;
            V stolen_value;
            if (_cache.steal_extended (key, out stolen_key, out stolen_value)) {
                unowned var link = _queue.find_custom (key, strcmp);
                if (link != (List<string>) null)
                    _queue.unlink (link);
                _size -= size_of_value (stolen_value);
                return true;
            }
            return false;
        }

        public void remove_all () {
            _cache.remove_all ();
            _queue.clear ();
            _size = 0;
        }

        protected virtual size_t size_of_value (V value) {
            return 1;
        }
    }

    public class Thumbnailer : Object {
        public const int ICON_SIZE = 96;
        public const size_t MAX_COUNT = 1000;

        private HashTable<string, string> _album_covers = new HashTable<string, string> (str_hash, str_equal);
        private LruCache<Gdk.Pixbuf?> _album_pixbufs = new LruCache<Gdk.Pixbuf?> (MAX_COUNT);
        private LruCache<Gdk.Paintable?> _cover_cache = new LruCache<Gdk.Paintable?> (MAX_COUNT);
        private CoverFinder _cover_finder = new CoverFinder ();
        private Quark _loading_quark = Quark.from_string ("loading_quark");
        private Pango.Context? _pango_context = null;
        private bool _remote_thumbnail = false;

        public signal void tag_updated (Music music);

        public Pango.Context? pango_context {
            get {
                return _pango_context;
            }
            set {
                _pango_context = value;
            }
        }

        public bool remote_thumbnail {
            get {
                return _remote_thumbnail;
            }
            set {
                _remote_thumbnail = value;
            }
        }

        public Gdk.Paintable? find (Music music) {
            return _cover_cache.find (music.cover_key);
        }

        public void put (Music music, Gdk.Paintable paintable, bool replace = false) {
            _cover_cache.put (music.cover_key, paintable, replace);
        }

        public async Gdk.Paintable? load_async (Music music, int size) {
            var is_small = size <= ICON_SIZE;
            if (is_small && !music.replace_qdata<bool, bool> (_loading_quark, false, true, null)) {
                return null;
            }

            var pixbuf = yield load_directly_async (music, size);
            if (is_small) {
                music.steal_qdata<bool> (_loading_quark);
            }

            var paintable0 = find (music);
            if (is_small && paintable0 != null) {
                //  Check if already exist with changed cover_key
                //  print ("Already exist: %s\n", music.cover_key);
                return paintable0;
            }

            var paintable = pixbuf != null
                ? Gdk.Texture.for_pixbuf ((!)pixbuf)
                : create_album_text_paintable (music);
            if (is_small) {
                put (music, paintable);
            } else if (pixbuf != null && paintable0 == null) {
                var minbuf = find_pixbuf_from_cache (music.cover_key);
                if (minbuf != null) {
                    put (music, Gdk.Texture.for_pixbuf ((!)minbuf));
                }
            }
            return paintable;
        }

        private async Gdk.Pixbuf? load_directly_async (Music music, int size) {
            var file = File.new_for_uri (music.uri);
            var is_native = file.is_native ();
            if (!_remote_thumbnail && !is_native) {
                return null;
            }

            var album_key_ = @"$(music.album)-$(music.artist)-";
            var tags = new Gst.TagList?[] { null };
            var cover_key = new string[] { music.cover_key, music.album };
            var pixbuf = yield run_async<Gdk.Pixbuf?> (() => {
                var tag = tags[0] = parse_gst_tags (file);
                File? cover_file = null;
                Gdk.Pixbuf? pixbuf = null;
                Gst.Sample? sample = null;
                if (tag != null && (sample = parse_image_from_tag_list ((!)tag)) != null) {
                    //  Check if there is an album cover with same artist and image size
                    var image_size = sample?.get_buffer ()?.get_size () ?? 0;
                    var album_key = album_key_ + image_size.to_string ("%x");
                    check_same_album_cover (album_key, ref cover_key[0]);
                    pixbuf = load_clamp_pixbuf_from_sample ((!)sample, size);
                } else if ((cover_file = _cover_finder.find (file)) != null) {
                    var album_key = (!) cover_file?.get_path ();
                    cover_key[0] = (!) cover_file?.get_uri ();
                    check_same_album_cover (album_key, ref cover_key[0]);
                    pixbuf = load_clamp_pixbuf_from_file ((!)cover_file, size);
                }
                if (pixbuf != null) {
                    var minbuf = find_pixbuf_from_cache (cover_key[0]);
                    if (minbuf == null) {
                        minbuf = create_clamp_pixbuf ((!)pixbuf, ICON_SIZE);
                        put_pixbuf_to_cache (cover_key[0], (!)minbuf);
                    }
                    return size <= ICON_SIZE ? minbuf : pixbuf;
                }
                cover_key[0] = parse_abbreviation (cover_key[1]);
                return null;
                //  Run in single_thread_pool for samba to save connections
            }, false, file.has_uri_scheme ("smb"));

            if (!is_native && tags[0] != null && music.from_gst_tags ((!)tags[0])) {
                //  Update for remote file, since it maybe cached but not parsed from file early
                tag_updated (music);
            }
            if (music.cover_key != cover_key[0]) {
                //  Update cover key if changed
                music.cover_key = cover_key[0];
            }
            return pixbuf;
        }

        public Gdk.Paintable create_album_text_paintable (Music music) {
            var text = parse_abbreviation (music.album);
            var color_count = BACKGROUND_COLORS.length / 3;
            var color_index = (text.length == 0 || text == UNKNOWN_ALBUM)
                    ? color_count - 1
                    : str_hash (text) % (color_count - 1);
            return create_simple_text_paintable (text, ICON_SIZE, color_index);
        }

        public Gdk.Paintable create_simple_text_paintable (string text, int size, uint color_index = 0x7fffffff) {
            var paintable = create_text_paintable ((!)_pango_context, text, size, size, color_index);
            return paintable ?? new BasePaintable ();
        }

        private void check_same_album_cover (string album_key, ref string cover_key) {
            unowned string key, uri;
            lock (_album_covers) {
                if (_album_covers.lookup_extended (album_key, out key, out uri)) {
                    cover_key = uri;
                    //  print ("Same album cover: %s\n", album_key);
                } else {
                    _album_covers[album_key] = cover_key;
                }
            }
        }

        private Gdk.Pixbuf? find_pixbuf_from_cache (string cover_key) {
            lock (_album_pixbufs) {
                return _album_pixbufs.find (cover_key);
            }
        }

        private void put_pixbuf_to_cache (string cover_key, Gdk.Pixbuf pixbuf) {
            lock (_album_pixbufs) {
                _album_pixbufs.put (cover_key, pixbuf);
            }
        }
    }

    public static Gdk.Pixbuf create_clamp_pixbuf (Gdk.Pixbuf pixbuf, int size) {
        var width = pixbuf.width;
        var height = pixbuf.height;
        if (size > 0 && width > size && height > size) {
            var scale = width > height ? (size / (double) height) : (size / (double) width);
            var dx = (int) (width * scale + 0.5);
            var dy = (int) (height * scale + 0.5);
            var newbuf = pixbuf.scale_simple (dx, dy, Gdk.InterpType.TILES);
            if (newbuf != null)
                return (!)newbuf;
        }
        return pixbuf;
    }

    public static Gdk.Pixbuf? load_clamp_pixbuf_from_file (File file, int size) {
        try {
            var fis = file.read ();
            var bis = new BufferedInputStream (fis);
            bis.buffer_size = 16384;
            return new Gdk.Pixbuf.from_stream_at_scale (bis, size, size, true);
        } catch (Error e) {
        }
        return null;
    }

    public static Gdk.Pixbuf? load_clamp_pixbuf_from_sample (Gst.Sample sample, int size) {
        var buffer = sample.get_buffer ();
        Gst.MapInfo? info = null;
        try {
            if (buffer?.map (out info, Gst.MapFlags.READ) ?? false) {
                var bytes = new Bytes.static (info?.data);
                var stream = new MemoryInputStream.from_bytes (bytes);
                return new Gdk.Pixbuf.from_stream_at_scale (stream, size, size, true);
            }
        } catch (Error e) {
        } finally {
            if (info != null)
                buffer?.unmap ((!)info);
        }
        return null;
    }
}
