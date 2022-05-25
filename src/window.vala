namespace Music {

    enum SearchType {
        ALL,
        ALBUM,
        ARTIST,
        TITLE
    }

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/window.ui")]
    public class Window : Adw.ApplicationWindow {
        [GtkChild]
        private unowned Gtk.Box content_box;
        [GtkChild]
        private unowned Gtk.Image cover_image;
        [GtkChild]
        public unowned Gtk.Label song_album;
        [GtkChild]
        public unowned Gtk.Label song_artist;
        [GtkChild]
        public unowned Gtk.Label song_title;
        [GtkChild]
        private unowned Adw.Flap flap;
        [GtkChild]
        private unowned Gtk.ListView list_view;
        [GtkChild]
        public unowned Gtk.ToggleButton search_btn;
        [GtkChild]
        public unowned Gtk.Entry search_entry;
        [GtkChild]
        public unowned Gtk.ToggleButton shuffle_btn;

        private CrossFadePaintable _bkgnd_paintable = new CrossFadePaintable ();
        private CrossFadePaintable _cover_paintable = new CrossFadePaintable ();
        private TextPaintable _loading_paintable = new TextPaintable ("...");

        private string _search_text = "";
        private string _search_property = "";
        private SearchType _search_type = SearchType.ALL;

        public Window (Application app) {
            Object (application: app);

            flap.bind_property ("folded", this, "flap_folded", BindingFlags.DEFAULT);

            app.bind_property ("shuffle", shuffle_btn, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

            search_entry.bind_property ("text", this, "search_text", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
            search_btn.bind_property ("active", search_entry, "visible", BindingFlags.SYNC_CREATE);
            search_btn.toggled.connect (() => {
                update_song_filter ();
                if (search_btn.active)
                    search_entry.grab_focus ();
                app.find_current_item ();
            });

            _cover_paintable.paintable = _loading_paintable;
            cover_image.paintable = new RoundPaintable (9, _cover_paintable);

            song_album.activate_link.connect (on_song_info_link);
            song_artist.activate_link.connect (on_song_info_link);

            var play_bar = new PlayBar ();
            content_box.append (play_bar);

            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((item) => {
                item.child = new SongEntry ();
            });
            factory.bind.connect (on_bind_item);
            factory.unbind.connect ((item) => {
                var entry = item.child as SongEntry;
                entry.cover = null;
            });
            list_view.factory = factory;
            list_view.model = new Gtk.NoSelection (app.song_list);
            list_view.activate.connect ((index) => {
                app.current_item = index;
            });

            app.index_changed.connect ((index, size) => {
                action_set_enabled (Application.ACTION_PREFIX + Application.ACTION_PREV, index > 0);
                action_set_enabled (Application.ACTION_PREFIX + Application.ACTION_NEXT, index < size - 1);
                list_view.activate_action ("list.scroll-to-item", "u", index);
                //  print ("play item: %u\n", index);
            });
            app.song_changed.connect (on_song_changed);
            app.song_tag_parsed.connect (on_song_tag_parsed);
        }

        public bool flap_folded {
            set {
                var flap_box = flap.flap;
                if (value) {
                    Timeout.add (flap.fold_duration, () => {
                        if (flap.folded && !flap_box.has_css_class ("background"))
                            flap_box.add_css_class ("background");
                        return false;
                    });
                } else if (!value && flap_box.has_css_class ("background")) {
                    flap_box.remove_css_class ("background");
                }
            }
        }

        public string? search_text {
            get {
                return _search_text;
            }
            set {
                if (value.ascii_ncasecmp ("album=", 6) == 0) {
                    _search_property = value.substring (6);
                    _search_type = SearchType.ALBUM;
                } else if (value.ascii_ncasecmp ("artist=", 7) == 0) {
                    _search_property = value.substring (7);
                    _search_type = SearchType.ARTIST;
                } else if (value.ascii_ncasecmp ("title=", 6) == 0) {
                    _search_property = value.substring (6);
                    _search_type = SearchType.TITLE;
                } else {
                    _search_type = SearchType.ALL;
                }
                _search_text = value;
                update_song_filter ();
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            update_blur_paintable (width, height);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = get_width ();
            var height = get_height ();
            if (!flap.folded) {
                var left = list_view.get_width ();
                var rect = Graphene.Rect ().init(left - 0.5f, 0, 0.5f, (float) height);
                draw_gray_linear_gradient_line (snapshot, rect);
            }
            snapshot.push_opacity (0.25);
            _bkgnd_paintable.snapshot (snapshot, width, height);
            snapshot.pop ();
            base.snapshot (snapshot);
        }

        private async void on_bind_item (Gtk.ListItem item) {
            var entry = item.child as SongEntry;
            var song = item.item as Song;
            entry.artist = song.artist;
            entry.title = song.title;

            var app = application as Application;
            entry.playing = item.position == app.current_item;
            //  print ("bind: %u\n", item.position);

            var thumbnailer = app.thumbnailer;
            var paintable = thumbnailer.find (song.url);
            entry.cover = paintable ?? _loading_paintable;
            if (paintable == null) {
                var saved_pos = item.position;
                var saved_entry = entry;
                var saved_song = song;
                var paintable2 = yield thumbnailer.load_async (this, song);
                if (saved_song == song) {
                    saved_entry.cover = paintable2;
                } else {
                    print ("item swapped: %u -> %u\n", saved_pos, item.position);
                }
            }
        }

        private async void on_song_tag_parsed (Song song, uint8[]? image) {
            update_song_info (song);

            if (image != null) try {
                var pixbuf = yield new Gdk.Pixbuf.from_stream_async (new MemoryInputStream.from_data (image));
                var paintable = Gdk.Texture.for_pixbuf (pixbuf);
                if (paintable != null) {
                    update_cover_paintable (song, paintable);
                    return;
                }
            } catch (Error e) {
            }

            var app = application as Application;
            var paintable = yield app.thumbnailer.load_directly_async (song);
            if (song == app.current_song) {
                update_cover_paintable (song, paintable);
            }
        }

        private async void on_song_changed (Song song) {
            update_song_info (song);
            print ("play song: %s\n", song.url);
        }

        private bool on_song_info_link (string uri) {
            search_text = uri;
            search_btn.active = true;
            return true;
        }

        private void update_song_info (Song song) {
            song_album.set_markup (@"<a href=\"album=$(song.album)\">$(song.album)</a>");
            song_artist.set_markup (@"<a href=\"artist=$(song.artist)\">$(song.artist)</a>");
            song_title.label = song.title;
            this.title = @"$(song.artist) - $(song.title)";
        }

        private void update_song_filter () {
            var app = application as Application;
            if (search_btn.active && _search_text.length > 0) {
                app.song_list.filter = new Gtk.CustomFilter ((obj) => {
                    var song = obj as Song;
                    switch (_search_type) {
                        case SearchType.ALBUM:
                            return song.album == _search_property;
                        case SearchType.ARTIST:
                            return song.artist == _search_property;
                        case SearchType.TITLE:
                            return song.title == _search_property;
                        default:
                            return _search_text.match_string (song.album, false)
                                || _search_text.match_string (song.artist, false)
                                || _search_text.match_string (song.title, false);
                    }
                });
            } else {
                app.song_list.filter = null;
            }
        }

        private Adw.Animation? _fade_animation = null;

        private void update_cover_paintable (Song song, Gdk.Paintable? paintable) {
            if (paintable == null) {
                var app = application as Application;
                paintable = app.thumbnailer.find (song.url) ?? _loading_paintable;
            }
            _cover_paintable.paintable = paintable;
            //  cover_image.queue_draw ();

            var width = get_width ();
            var height = get_height ();
            if (width > 0 && height > 0) {
                update_blur_paintable (width, height, true);
                //  queue_draw ();
            }

            var target = new Adw.CallbackAnimationTarget ((value) => {
                _cover_paintable.fade = value;
                cover_image.queue_draw ();
                _bkgnd_paintable.fade = value;
                queue_draw ();
            });
            _fade_animation?.pause ();
            _fade_animation = new Adw.TimedAnimation (cover_image, 1 - _cover_paintable.fade, 0, 500, target);
            _fade_animation.done.connect (() => {
                _cover_paintable.previous = null;
                _fade_animation = null;
            });
            _fade_animation.play ();
        }

        private int _blur_width = 0;
        private int _blur_height = 0;

        private bool update_blur_paintable (int width, int height, bool force = false) {
            var paintable = _cover_paintable.paintable;
            if (paintable != null) {
                if (force || _blur_width != width || _blur_height != height) {
                    _blur_width = width;
                    _blur_height = height;
                    _bkgnd_paintable.paintable = create_blur_texture (this, paintable, width, height);
                    print ("update blur: %dx%d\n", width, height);
                    return true;
                }
            } else if (force) {
                _bkgnd_paintable.paintable = null;
                return true;
            }
            return false;
        }
    }
}