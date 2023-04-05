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
        public const uint MAX_SIZE = 50 * 1024 * 1024;
        public static CompareDataFunc<string> compare_string = (a, b) => { return strcmp (a, b); };

        private size_t _size = 0;
        private Tree<string, V> _cache = new Tree<string, V> (compare_string);

        public V? find (string key) {
            weak string orig_key;
            weak V value;
            if (_cache.lookup_extended (key, out orig_key, out value))
                return value;
            return null;
        }

        public bool has (string key) {
            return _cache.lookup (key) != null;
        }

        public void put (string key, V value) {
            var size = size_of_value (value);
            unowned TreeNode<string, V>? first = null;
            while (_size + size > MAX_SIZE && (first = _cache.node_first ()) != null) {
                _size -= size_of_value (((!)first).value ());
                _cache.remove (((!)first).key ());
            }

            unowned var cur = _cache.lookup (key);
            if (cur != null) {
                _size -= size_of_value (cur);
                _cache.replace (key, value);
            } else {
                _cache.insert (key, value);
            }
            _size += size;
            //  print (@"Cache $(_cache.nnodes ()) items, $_size bytes\n");
        }

        public bool remove (string key) {
            unowned var value = _cache.lookup (key);
            if (value != null) {
                _size -= size_of_value (value);
            }
            return _cache.remove (key);
        }

        public void remove_all () {
            _cache.remove_all ();
            _size = 0;
        }

        protected virtual size_t size_of_value (V value) {
            return 1;
        }
    }

    public class Thumbnailer : LruCache<Gdk.Paintable> {
        public const int ICON_SIZE = 96;

        private HashTable<string, string> _album_covers = new HashTable<string, string> (str_hash, str_equal);
        private CoverFinder _cover_finder = new CoverFinder ();
        private GenericSet<string> _loading = new GenericSet<string> (str_hash, str_equal);
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

        public new Gdk.Paintable? find (string key) {
            return base.find (key);
        }

        public bool has_image (Music music) {
            var paintable = find (music.cover_uri);
            return paintable != null && (!)paintable is Gdk.Texture;
        }

        public async Gdk.Paintable? load_async (Music music) {
            unowned var uri = music.cover_uri;
            if (uri in _loading)
                return null;

            _loading.add (uri);
            var texture = yield load_directly_async (music, ICON_SIZE);
            _loading.remove (uri);
            uri = music.cover_uri; //  Update cover uri maybe changed when loading
            if (texture != null) {
                put (uri, (!)texture);
                return texture;
            }

            var paintable = create_album_text_paintable (music, ICON_SIZE);
            put (uri, paintable);
            return paintable;
        }

        public async Gdk.Paintable? load_directly_async (Music music, int size = ICON_SIZE) {
            var file = File.new_for_uri (music.uri);
            var is_native = file.is_native ();
            if (!_remote_thumbnail && !is_native) {
                return null;
            }

            var album_key_ = @"$(music.album)-$(music.artist)-";
            var tags = new Gst.TagList?[] { null };
            var cover_uri = new string[] { music.cover_uri };
            var pixbuf = yield run_async<Gdk.Pixbuf?> (() => {
                var tag = tags[0] = parse_gst_tags (file);
                Gst.Sample? sample = null;
                if (tag != null && (sample = parse_image_from_tag_list ((!)tag)) != null) {
                    if (size <= ICON_SIZE) {
                        //  Check if there is an album cover with same artist and image size
                        var image_size = sample?.get_buffer ()?.get_size () ?? 0;
                        var album_key = album_key_ + image_size.to_string ("%x");
                        check_same_album_cover (album_key, ref cover_uri[0]);
                    }
                    var pixbuf = load_clamp_pixbuf_from_sample ((!)sample, size);
                    if (pixbuf != null)
                        return pixbuf;
                }
                //  Try load album art cover file in the folder
                var cover_file = _cover_finder.find (file);
                if (cover_file != null) {
                    cover_uri[0] = (!) cover_file?.get_uri ();
                    return load_clamp_pixbuf_from_file ((!)cover_file, size);
                }
                return null;
                //  Run in single_thread_pool for samba to save connections
            }, false, file.has_uri_scheme ("smb"));
            if (!is_native && tags[0] != null) {
                //  Update for remote file, since it maybe cached but not parsed from file early
                if (music.from_gst_tags ((!)tags[0]))
                    tag_updated (music);
            }
            if (music.cover_uri != cover_uri[0]) {
                //  Update cover uri if changed
                music.cover_uri = cover_uri[0];
            }
            if (pixbuf != null) {
                return Gdk.Texture.for_pixbuf ((!)pixbuf);
            }
            return null;
        }

        public Gdk.Paintable create_album_text_paintable (Music music, int size) {
            var text = music.album;
            var bkcolor = (text.length == 0 || text == UNKOWN_ALBUM)
                        ? 0xc0bfbc
                        : BACKGROUND_COLORS[str_hash (text) % BACKGROUND_COLORS.length];
            text = parse_abbreviation (text);
            return create_simple_text_paintable (text, size, 0xc0808080u, bkcolor | 0xff000000u);
        }

        public Gdk.Paintable create_simple_text_paintable (string text, int size, uint color = 0xc0808080u, uint bkcolor = 0) {
            var paintable = create_text_paintable ((!)_pango_context, text, size, size, color, bkcolor);
            return paintable ?? new BasePaintable ();
        }

        protected override size_t size_of_value (Gdk.Paintable paintable) {
            var pixels = paintable.get_intrinsic_width () * paintable.get_intrinsic_height ();
            return (paintable is Gdk.Texture) ? pixels * 4 : pixels;
        }

        private bool check_same_album_cover (string album_key, ref string cover_uri) {
            lock (_album_covers) {
                weak string key, uri;
                if (_album_covers.lookup_extended (album_key, out key, out uri)) {
                    cover_uri = uri;
                    //  print ("Same album cover: %s\n", album_key);
                    return true;
                } else {
                    _album_covers[album_key] = cover_uri;
                }
            }
            return false;
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
            return load_clamp_pixbuf_from_stream (bis, size);
        } catch (Error e) {
        }
        return null;
    }

    public static Gdk.Pixbuf? load_clamp_pixbuf_from_sample (Gst.Sample sample, int size) {
        var buffer = sample.get_buffer ();
        Gst.MapInfo? info = null;
        if (buffer?.map (out info, Gst.MapFlags.READ) ?? false) {
            var bytes = new Bytes.static (info?.data);
            var stream = new MemoryInputStream.from_bytes (bytes);
            var pixbuf = load_clamp_pixbuf_from_stream (stream, size);
            buffer?.unmap ((!)info);
            return pixbuf;
        }
        return null;
    }

    public static Gdk.Pixbuf? load_clamp_pixbuf_from_stream (InputStream stream, int size) {
        try {
            var pixbuf = new Gdk.Pixbuf.from_stream (stream);
            if (pixbuf is Gdk.Pixbuf)
                return create_clamp_pixbuf (pixbuf, size);
        } catch (Error e) {
        }
        return null;
    }
}
