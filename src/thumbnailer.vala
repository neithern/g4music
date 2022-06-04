namespace Music {

    //  Sorted by insert order
    public class LruCache<V> {
        public static uint MAX_SIZE = 50 * 1024 * 1024;
        public static CompareDataFunc<string> compare_string = (a, b) => { return strcmp (a, b); };

        private size_t _size = 0;
        private Tree<string, V> _cache = new Tree<string, V> (compare_string);

        public V find (string key) {
            return _cache.lookup (key);
        }

        public void put (string key, V value) {
            var size = size_of_value (value);
            unowned TreeNode<string, V>? first = null;
            while (_size + size > MAX_SIZE && (first = _cache.node_first ()) != null) {
                _size -= size_of_value (((!)first).value ());
                _cache.remove (((!)first).key ());
            }

            var cur = _cache.lookup (key);
            if (cur != null) {
                _size -= size_of_value (cur);
                _cache.replace (key, value);
            } else {
                _cache.insert (key, value);
            }
            _size += size;
            //  print (@"cache size: $(_size)\n");
        }

        public bool remove (string key) {
            var value = _cache.lookup (key);
            if (value != null) {
                _size -= size_of_value (value);
            }
            return _cache.remove (key);
        }

        protected virtual size_t size_of_value (V value) {
            return 1;
        }
    }

    public class Thumbnailer : LruCache<Gdk.Paintable?> {
        public static int icon_size = 96;

        private GenericSet<string> _loading = new GenericSet<string> (str_hash, str_equal);
        private bool _remote_thumbnail = false;

        public bool remote_thumbnail {
            set {
                _remote_thumbnail = value;
            }
        }

        public async Gdk.Paintable? load_async (Song song) {
            var uri = song.uri;
            if (uri in _loading)
                return null;

            _loading.add (uri);
            var texture = yield load_directly_async (song, icon_size);
            _loading.remove (uri);
            if (texture != null) {
                put (uri, (!)texture);
                return texture;
            }

            var paintable = create_song_album_text_paintable (song);
            put (uri, paintable);
            return paintable;
        }

        public async Gdk.Paintable? load_directly_async (Song song, int size = 0) {
            var file = File.new_for_uri (song.uri);
            if (!_remote_thumbnail && "file" != (file.get_uri_scheme () ?? "")) {
                return null;
            }

            var tags = new Gst.TagList?[] { null };
            var pixbuf = yield run_async<Gdk.Pixbuf?> (() => {
                var t = tags[0] = parse_gst_tags (file, song.type);
                Bytes? image = null;
                string? itype = null;
                if (t != null && parse_image_from_tag_list ((!)t, out image, out itype)
                        && image != null) {
                    return load_clamp_pixbuf ((!)image, size);
                }
                return null;
            });
            if (song.artist.length == 0) {
                song.init_from_gst_tags (tags[0]);
                song.update_keys ();
            }
            if (pixbuf != null) {
                return Gdk.Texture.for_pixbuf ((!)pixbuf);
            }
            return null;
        }

        public void update_text_paintable (Song song) {
            var uri = song.uri;
            var paintable = find (uri);
            if (! (paintable is Gdk.Texture)) {
                var paintable2 = create_song_album_text_paintable (song);
                put (uri, paintable2);
            }
        }

        protected override size_t size_of_value (Gdk.Paintable? paintable) {
            return (paintable?.get_intrinsic_width () ?? 0) * (paintable?.get_intrinsic_height () ?? 0) * 4;
        }

        protected static Gdk.Paintable create_song_album_text_paintable (Song song) {
            var text = parse_abbreviation (song.album);
            var color = (song.album.length == 0 || song.album == UNKOWN_ALBUM) ? (int) 0xffc0bfbc : 0;
            var paintable = create_text_paintable (text, icon_size, icon_size, color);
            return paintable ?? new BasePaintable ();
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

    public static Gdk.Pixbuf? load_clamp_pixbuf (Bytes image, int size) {
        try {
            var stream = new MemoryInputStream.from_bytes (image);
            var pixbuf = new Gdk.Pixbuf.from_stream (stream);
            if (pixbuf is Gdk.Pixbuf)
                return create_clamp_pixbuf (pixbuf, size);
        } catch (Error e) {
        }
        return null;
    }
}
