namespace Music {

    public class CoverFinder : Object {
        private HashTable<string, string?> _cache = new HashTable<string, string?> (str_hash, str_equal);

        public File? find (File file) {
            var parent = file.get_parent ();
            if (parent == null)
                return null;

            var dir = (!)parent;
            var uri = dir.get_uri ();
            lock (_cache) {
                var art_uri = _cache[uri];
                if (art_uri == null || ((!)art_uri).length == 0) {
                    var art_file = find_no_lock (dir);
                    art_uri = art_file?.get_uri ();
                    _cache[uri] = art_uri ?? "";
                }
                return art_uri != null ? File.new_for_uri ((!)art_uri) : (File?) null;
            }
        }

        private static File? find_no_lock (File dir) {
            try {
                FileInfo? info = null;
                var enumerator = dir.enumerate_children ("standard::*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                while ((info = enumerator.next_file ()) != null) {
                    unowned var type = ((!)info).get_content_type ();
                    if (type != null && ContentType.is_mime_type ((!)type, "image/*")) {
                        unowned var name = ((!)info).get_name ();
                        if (name.ascii_ncasecmp ("Cover", 5) == 0
                            || name.ascii_ncasecmp ("Folder", 6) == 0
                            || name.ascii_ncasecmp ("AlbumArt", 8) == 0
                            || name.ascii_ncasecmp ("AlbumArt_{", 10) == 0
                            || name.ascii_ncasecmp ("AlbumArtSmall", 13) == 0) {
                            //  print ("Find AlbumArt: %s\n", name);
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
    public class LruCache<V> {
        public static uint MAX_SIZE = 50 * 1024 * 1024;
        public static CompareDataFunc<string> compare_string = (a, b) => { return strcmp (a, b); };

        private size_t _size = 0;
        private Tree<string, V> _cache = new Tree<string, V> (compare_string);

        public unowned V find (string key) {
            return _cache.lookup (key);
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
            //  print (@"cache size: $(_size)\n");
        }

        public bool remove (string key) {
            unowned var value = _cache.lookup (key);
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
        private CoverFinder _cover_finder = new CoverFinder ();
        private bool _remote_thumbnail = false;

        public bool remote_thumbnail {
            set {
                _remote_thumbnail = value;
            }
        }

        public async Gdk.Paintable? load_async (Song song) {
            unowned var uri = song.cover_uri;
            if (uri in _loading)
                return null;

            _loading.add (uri);
            var texture = yield load_directly_async (song, icon_size);
            _loading.remove (uri);
            uri = song.cover_uri; //  Update cover uri maybe changed when loading
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
            if (!_remote_thumbnail && !file.is_native ()) {
                return null;
            }

            var tags = new Gst.TagList?[] { null };
            var cover_uri = new string?[] { null };
            var pixbuf = yield run_async<Gdk.Pixbuf?> (() => {
                var tag = tags[0] = parse_gst_tags (file);
                Gst.Sample? sample = null;
                if (tag != null && (sample = parse_image_from_tag_list ((!)tag)) != null) {
                    return load_clamp_pixbuf_from_gst_sample ((!)sample, size);
                }
                //  Try load album art cover file in the folder
                try {
                    var cover_file = _cover_finder.find (file);
                    var stream = cover_file?.read ();
                    if (cover_file != null && stream != null) {
                        cover_uri[0] = cover_file?.get_uri ();
                        return load_clamp_pixbuf_from_stream (new BufferedInputStream ((!)stream), size);
                    }
                } catch (Error e) {
                }
                return null;
                 //  run in single_thread_pool for samba to save connections
            }, false, file.has_uri_scheme ("smb"));
            if (! song.has_tags) {
                //  Update tags if not has
                song.from_gst_tags (tags[0]);
            }
            if (cover_uri[0] != null) {
                //  Update cover uri if available
                song.cover_uri = (!)cover_uri[0];
            }
            if (pixbuf != null) {
                return Gdk.Texture.for_pixbuf ((!)pixbuf);
            }
            return null;
        }

        protected override size_t size_of_value (Gdk.Paintable? paintable) {
            return (paintable?.get_intrinsic_width () ?? 0) * (paintable?.get_intrinsic_height () ?? 0) * 4;
        }

        public static Gdk.Paintable create_song_album_text_paintable (Song song) {
            unowned var album = song.album;
            var text = parse_abbreviation (album);
            var color = (album.length == 0 || album == UNKOWN_ALBUM) ? (int) 0xffc0bfbc : 0;
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

    public static Gdk.Pixbuf? load_clamp_pixbuf_from_gst_sample (Gst.Sample sample, int size) {
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
