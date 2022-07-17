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
        private unowned Adw.Leaflet leaflet;
        [GtkChild]
        private unowned Gtk.Spinner spinner;
        [GtkChild]
        private unowned Gtk.Label index_title;
        [GtkChild]
        private unowned Gtk.MenuButton sort_btn;
        [GtkChild]
        private unowned Gtk.Button back_btn;
        [GtkChild]
        private unowned Gtk.Box content_box;
        [GtkChild]
        private unowned Gtk.Image cover_image;
        [GtkChild]
        private unowned Gtk.Label song_album;
        [GtkChild]
        private unowned Gtk.Label song_artist;
        [GtkChild]
        private unowned Gtk.Label song_title;
        [GtkChild]
        private unowned Gtk.Label initial_label;
        [GtkChild]
        private unowned Gtk.ListView list_view;
        [GtkChild]
        private unowned Gtk.Box mini_box;
        [GtkChild]
        public unowned Gtk.ToggleButton search_btn;
        [GtkChild]
        private unowned Gtk.SearchBar search_bar;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry;

        private MiniBar _mini_bar = new MiniBar ();

        private CrossFadePaintable _bkgnd_paintable = new CrossFadePaintable ();
        private CrossFadePaintable _cover_paintable = new CrossFadePaintable ();
        private Gdk.Paintable? _loading_paintable = null;

        private string _loading_text = _("Loading...");

        private string _search_text = "";
        private string _search_property = "";
        private SearchType _search_type = SearchType.ALL;

        public Window (Application app) {
            Object (application: app);
            this.icon_name = app.application_id;

            this.close_request.connect (on_close_request);

            app.settings?.bind ("width", this, "default-width", SettingsBindFlags.DEFAULT);
            app.settings?.bind ("height", this, "default-height", SettingsBindFlags.DEFAULT);

            setup_drop_target ();

            leaflet.bind_property ("folded", this, "leaflet_folded", BindingFlags.DEFAULT);
            leaflet.navigate (Adw.NavigationDirection.FORWARD);
            back_btn.clicked.connect (() => {
            	leaflet.navigate (Adw.NavigationDirection.BACK);
            });

            app.bind_property ("sort_mode", this, "sort_mode", BindingFlags.DEFAULT);
            sort_mode = app.sort_mode;

            search_btn.toggled.connect (() => {
                if (search_btn.active) {
                    search_entry.grab_focus ();
                    if (leaflet.folded) {
                        leaflet.navigate (Adw.NavigationDirection.BACK);
                    }
                }
                update_song_filter ();
            });
            search_entry.search_changed.connect (on_search_text_changed);

            var provider = new Gtk.CssProvider ();
            provider.load_from_data ("searchbar revealer box {box-shadow: none; background-color: transparent;}".data);
            Gtk.StyleContext.add_provider_for_display (this.display, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
            search_bar.key_capture_widget = this.content;

            mini_box.append (_mini_bar);
            _mini_bar.activated.connect (() => {
                leaflet.navigate (Adw.NavigationDirection.FORWARD);
            });

            _bkgnd_paintable.queue_draw.connect (this.queue_draw);
            _cover_paintable.queue_draw.connect (cover_image.queue_draw);

            app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = app.thumbnailer.create_album_text_paintable ("G4", 0x8de6b1);
            _cover_paintable.paintable = _loading_paintable;
            _mini_bar.cover = _loading_paintable;

            var scale_paintable = new ScalePaintable (new RoundPaintable (_cover_paintable, 12));
            scale_paintable.scale = 0.8;
            cover_image.paintable = scale_paintable;
            scale_paintable.queue_draw.connect (cover_image.queue_draw);

            make_label_clickable (song_album).released.connect (() => {
                search_entry.text = "album=" + song_album.label;
                search_btn.active = true;
                leaflet.navigate (Adw.NavigationDirection.BACK);
            });
            make_label_clickable (song_artist).released.connect (() => {
                search_entry.text = "artist=" + song_artist.label;
                search_btn.active = true;
                leaflet.navigate (Adw.NavigationDirection.BACK);
            });

            var play_bar = new PlayBar ();
            content_box.append (play_bar);
            action_set_enabled (ACTION_APP + ACTION_PREV, false);
            action_set_enabled (ACTION_APP + ACTION_PLAY, false);
            action_set_enabled (ACTION_APP + ACTION_NEXT, false);

            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((item) => {
                item.child = new SongEntry ();
            });
            factory.bind.connect (on_bind_item);
            factory.unbind.connect ((item) => {
                var entry = (SongEntry) item.child;
                entry.cover = null;
            });
            list_view.factory = factory;
            list_view.model = new Gtk.NoSelection (app.song_list);
            list_view.activate.connect ((index) => {
                app.current_item = (int) index;
            });

            initial_label.activate_link.connect ((uri) => {
                pick_music_folder (app, this, (dir) => {
                    app.reload_song_store ();
                });
                return true;
            });

            on_loading_changed (true, 1);
            app.loading_changed.connect (on_loading_changed);
            app.index_changed.connect (on_index_changed);
            app.song_changed.connect (on_song_changed);
            app.song_tag_parsed.connect (on_song_tag_parsed);
            app.player.state_changed.connect (on_player_state_changed);
        }

        public bool leaflet_folded {
            set {
                leaflet.navigate (Adw.NavigationDirection.FORWARD);
            }
        }

        public SortMode sort_mode {
            set {
                switch (value) {
                    case SortMode.ALBUM:
                        sort_btn.set_icon_name ("media-optical-cd-audio-symbolic");
                        break;
                    case SortMode.ARTIST:
                        sort_btn.set_icon_name ("system-users-symbolic");
                        break;
                    case SortMode.SHUFFLE:
                        sort_btn.set_icon_name ("media-playlist-shuffle-symbolic");
                        break;
                    default:
                        sort_btn.set_icon_name ("folder-music-symbolic");
                        break;
                }
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            update_blur_paintable (width, height);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = get_width ();
            var height = get_height ();
            snapshot.push_opacity (0.25);
            _bkgnd_paintable.snapshot (snapshot, width, height);
            snapshot.pop ();
            if (!leaflet.folded) {
                var page = (Adw.LeafletPage) leaflet.pages.get_item (0);
                var right = page.child.get_width ();
                var rect = (!)Graphene.Rect ().init (right - 0.5f, 0, 0.5f, height);
                draw_gray_linear_gradient_line (snapshot, rect);
            }
            base.snapshot (snapshot);
        }

        private async void on_bind_item (Gtk.ListItem item) {
            var app = (Application) application;
            var entry = (SongEntry) item.child;
            var song = (Song) item.item;
            entry.playing = item.position == app.current_item;
            entry.update (song, app.sort_mode);
            //  print ("bind: %u\n", item.position);

            var thumbnailer = app.thumbnailer;
            var paintable = thumbnailer.find (song.cover_uri);
            entry.cover = paintable ?? _loading_paintable;
            if (paintable == null) {
                var saved_pos = item.position;
                var saved_song = song;
                var paintable2 = yield thumbnailer.load_async (song);
                if (saved_pos != item.position) {
                    // item rebinded, notify changed later to update it
                    Idle.add (() => {
                        app.song_list.items_changed (saved_pos, 0, 0);
                        return false;
                    });
                } else if (paintable2 != null) {
                    // maybe changed, update it
                    entry.cover = paintable2;
                    entry.update (saved_song, app.sort_mode);
                }
            }
        }

        private bool on_close_request () {
            var app = (Application) application;
            if (app.player.playing && (app.settings?.get_boolean ("play-background") ?? false)) {
                app.request_background ();
                this.hide ();
                return true;
            }
            return false;
        }

        private void on_index_changed (int index, uint size) {
            action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
            action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
            scroll_to_item (index);
            index_title.label = size > 0 ? @"$(index+1)/$(size)" : "";
        }

        private void on_loading_changed (bool loading, uint size) {
            spinner.spinning = loading;
            spinner.visible = loading;
            index_title.label = loading ? _loading_text : size.to_string ();

            var app = (Application) application;
            var empty = size == 0 && app.current_song == null;
            if (empty) {
                var dir_name = get_display_name (app.get_music_folder ());
                var link = @"<a href=\"change_dir\">$dir_name</a>";
                initial_label.set_markup (_("Drag and drop song files here,\nor change music location: ") + link);
            }
            initial_label.visible = empty;
            song_title.visible = !empty;
        }

        private Adw.Animation? _scale_animation = null;

        private void on_player_state_changed (Gst.State state) {
            if (state >= Gst.State.PAUSED) {
                var scale_paintable = (!)(cover_image.paintable as ScalePaintable);
                var target = new Adw.CallbackAnimationTarget ((value) => {
                    scale_paintable.scale = value;
                });
                _scale_animation?.pause ();
                _scale_animation = new Adw.TimedAnimation (cover_image,  scale_paintable.scale,
                                            state == Gst.State.PLAYING ? 1 : 0.8, 500, target);
                _scale_animation?.play ();
            }
        }

        private void on_search_text_changed () {
            string text = search_entry.text;
            if (text.ascii_ncasecmp ("album=", 6) == 0) {
                _search_property = text.substring (6);
                _search_type = SearchType.ALBUM;
            } else if (text.ascii_ncasecmp ("artist=", 7) == 0) {
                _search_property = text.substring (7);
                _search_type = SearchType.ARTIST;
            } else if (text.ascii_ncasecmp ("title=", 6) == 0) {
                _search_property = text.substring (6);
                _search_type = SearchType.TITLE;
            } else {
                _search_type = SearchType.ALL;
            }
            _search_text = text;
            update_song_filter ();
        }

        private void on_song_changed (Song song) {
            update_song_info (song);
            action_set_enabled (ACTION_APP + ACTION_PLAY, true);
            print ("Play: %s\n", Uri.unescape_string (song.uri) ?? song.uri);
        }

        private async void on_song_tag_parsed (Song song, Gst.Sample? image) {
            update_song_info (song);
            action_set_enabled (ACTION_APP + ACTION_EXPORT, image != null);

            var app = (Application) application;
            var pixbufs = new Gdk.Pixbuf?[2] {null, null};
            if (image != null) {
                var has_cache = app.thumbnailer.has_image (song);
                yield run_async<void> (() => {
                    pixbufs[0] = load_clamp_pixbuf_from_sample ((!)image, 1024);
                    if (! has_cache && pixbufs[0] != null)
                        pixbufs[1] = create_clamp_pixbuf ((!)pixbufs[0], Thumbnailer.icon_size);
                }, true);
            }
            if (song == app.current_song) {
                Gdk.Paintable? paintable = null;
                if (pixbufs[0] != null) {
                    paintable = Gdk.Texture.for_pixbuf ((!)pixbufs[0]);
                } else {
                    paintable = yield app.thumbnailer.load_directly_async (song, 1024);
                }
                if (pixbufs[1] != null) {
                    var mini = Gdk.Texture.for_pixbuf ((!)pixbufs[1]);
                    _mini_bar.cover = mini;
                    app.thumbnailer.put (song.cover_uri, mini);
                    app.song_list.items_changed (app.current_item, 0, 0);
                }
                update_cover_paintable (song, paintable);
            }
        }

        private void scroll_to_item (int index) {
            list_view.activate_action ("list.scroll-to-item", "u", index);
        }

        private void setup_drop_target () {
            var drop_target = new Gtk.DropTarget (Type.INVALID, Gdk.DragAction.COPY);
            drop_target.set_gtypes ({typeof (Gdk.FileList)});
            drop_target.on_drop.connect ((value, x, y) => {
                var file_list = ((Gdk.FileList) value).get_files ();
                var count = file_list.length ();
                var files = new File[count];
                var index = 0;
                foreach (var file in file_list) {
                    files[index++] = file;
                }
                var app = (Application) application;
                app.load_songs_async.begin (files, (obj, res) => {
                    var item = app.load_songs_async.end (res);
                    if (app.current_song == null) {
                        app.current_item = item;
                    } else {
                        scroll_to_item (item);
                    }
                });
                return true;
            });
            this.content.add_controller (drop_target);
        }

        private void update_song_info (Song song) {
            song_album.label = song.album;
            song_artist.label = song.artist;
            song_title.label = song.title;
            _mini_bar.title = song.title;
            this.title = song.artist == UNKOWN_ARTIST ? song.title : @"$(song.artist) - $(song.title)";
        }

        private void update_song_filter () {
            var app = (Application) application;
            if (search_btn.active && _search_text.length > 0) {
                app.song_list.filter = new Gtk.CustomFilter ((obj) => {
                    var song = (Song) obj;
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
                app.song_list.set_filter (null);
            }
            if (!app.find_current_item ()) {
                app.index_changed (app.current_item, app.song_list.get_n_items ());
            }
        }

        private Adw.Animation? _fade_animation = null;

        private void update_cover_paintable (Song song, Gdk.Paintable? paintable) {
            var app = (Application) application;
            _mini_bar.cover = app.thumbnailer.find (song.cover_uri);
            _cover_paintable.paintable = paintable ?? _mini_bar.cover;

            var width = get_width ();
            var height = get_height ();
            if (width > 0 && height > 0) {
                update_blur_paintable (width, height, true);
            }

            var target = new Adw.CallbackAnimationTarget ((value) => {
                _bkgnd_paintable.fade = value;
                _cover_paintable.fade = value;
            });
            _fade_animation?.pause ();
            _fade_animation = new Adw.TimedAnimation (cover_image, 1 - _cover_paintable.fade, 0, 800, target);
            ((!)_fade_animation).done.connect (() => {
                _bkgnd_paintable.previous = null;
                _cover_paintable.previous = null;
                _fade_animation = null;
            });
            _fade_animation?.play ();
        }

        private int _blur_width = 0;
        private int _blur_height = 0;

        private bool update_blur_paintable (int width, int height, bool force = false) {
            var paintable = _mini_bar.cover; // _cover_paintable.paintable;
            if (paintable != null) {
                if (force || _blur_width != width || _blur_height != height) {
                    _blur_width = width;
                    _blur_height = height;
                    _bkgnd_paintable.paintable = create_blur_texture (this, (!)paintable, width, height);
                    print ("Update blur: %dx%d\n", width, height);
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
