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

#if HAS_GNOME_DESKTOP
        private Gnome.DesktopThumbnailFactory _factory =
            new Gnome.DesktopThumbnailFactory (Gnome.DesktopThumbnailSize.LARGE);

        protected Gdk.Pixbuf? load_directly (Song song, int size = 0) {
            var uri = song.uri;
            try {
                var path = Gnome.DesktopThumbnail.path_for_uri (uri, Gnome.DesktopThumbnailSize.LARGE);
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale (path, size, -1, true);
                if (pixbuf is Gdk.Pixbuf) {
                    song.thumbnail = path;
                    //  print ("Load thumbnail: %dx%d, %s\n", pixbuf.width, pixbuf.height, uri);
                    return pixbuf;
                }
            } catch (Error e) {
                //  warning ("Load thumbnail %s: %s\n", uri, e.message);
            }

            if (song.mtime == 0) try {
                var file = File.new_for_uri (uri);
                var info = file.query_info ("time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                song.mtime = (long) (info.get_modification_date_time ()?.to_unix () ?? 0);
                if (!_factory.has_valid_failed_thumbnail (uri, song.mtime)) {
                    var pixbuf = _factory.generate_thumbnail (uri, song.type);
                    if (pixbuf is Gdk.Pixbuf) {
                        //  print ("General thumbnail: %dx%d, %s\n", pixbuf.width, pixbuf.height, uri);
                        var pixbuf2 = create_clamp_pixbuf (pixbuf, size);
                        _factory.save_thumbnail (pixbuf, uri, song.mtime);
                        return pixbuf2;
                    } else {
                        _factory.create_failed_thumbnail (uri, song.mtime);
                    }
                }
            } catch (Error e) {
                //  warning ("Generate thumbnail %s: %s\n", uri, e.message);
            }
            return null;
        }
#else
        protected Gdk.Pixbuf? load_directly (Song song, int size = 0) {
            var path = File.new_for_uri (song.uri).get_path ();
            if (path == null)
                return null;

            var tags = parse_gst_tags ((!)path, song.type);
            if (tags == null)
                return null;

            string? album = null, artist = null, title = null;
            Bytes? image = null;
            string? itype = null;
            if (parse_from_tag_list ((!)tags, out album, out artist, out title, true, out image, out itype)
                    && image != null) {
                return load_clamp_pixbuf ((!)image, size);
            }
            return null;
        }
#endif

        public async Gdk.Paintable? load_directly_async (Song song, int size = 0) {
            var pixbuf = yield run_async<Gdk.Pixbuf?> (() => {
                return load_directly (song, size);
            });
            if (pixbuf != null)
                return Gdk.Texture.for_pixbuf ((!)pixbuf);
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
            var color = song.album == UNKOWN_ALBUM ? (int) 0xffc0bfbc : 0;
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
