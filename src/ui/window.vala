namespace G4 {

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
        private unowned Gtk.Label music_album;
        [GtkChild]
        private unowned Gtk.Label music_artist;
        [GtkChild]
        private unowned Gtk.Label music_title;
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

        private BackgroundBlurMode _bkgnd_blur = BackgroundBlurMode.ALWAYS;
        private CrossFadePaintable _bkgnd_paintable = new CrossFadePaintable ();
        private CrossFadePaintable _cover_paintable = new CrossFadePaintable ();
        private Gdk.Paintable? _loading_paintable = null;
        private ScalePaintable _scale_cover_paintable = new ScalePaintable ();

        private int _cover_size = 1024;
        private string _loading_text = _("Loading...");

        private string _search_text = "";
        private string _search_property = "";
        private SearchType _search_type = SearchType.ALL;

        public Window (Application app) {
            Object (application: app);
            this.icon_name = app.application_id;

            this.close_request.connect (on_close_request);

            var settings = app.settings;
            settings?.bind ("width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings?.bind ("height", this, "default-height", SettingsBindFlags.DEFAULT);
            settings?.bind ("background-blur", this, "background-blur", SettingsBindFlags.DEFAULT);

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
                update_music_filter ();
            });
            search_bar.key_capture_widget = this.content;
            search_entry.search_changed.connect (on_search_text_changed);

            mini_box.append (_mini_bar);
            _mini_bar.activated.connect (() => {
                leaflet.navigate (Adw.NavigationDirection.FORWARD);
            });

            _bkgnd_paintable.queue_draw.connect (this.queue_draw);
            _cover_paintable.queue_draw.connect (cover_image.queue_draw);

            app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            _scale_cover_paintable.paintable = new RoundPaintable (_cover_paintable, 12);
            _scale_cover_paintable.scale = 0.8;
            _scale_cover_paintable.queue_draw.connect (cover_image.queue_draw);
            cover_image.paintable = _scale_cover_paintable;

            make_label_clickable (music_album).released.connect (() => {
                start_search ("album=" + music_album.label);
            });
            make_label_clickable (music_artist).released.connect (() => {
                start_search ("artist=" + music_artist.label);
            });

            var play_bar = new PlayBar ();
            content_box.append (play_bar);
            action_set_enabled (ACTION_APP + ACTION_PREV, false);
            action_set_enabled (ACTION_APP + ACTION_PLAY, false);
            action_set_enabled (ACTION_APP + ACTION_NEXT, false);

            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((item) => {
                item.child = new MusicEntry ();
            });
            factory.bind.connect (on_bind_item);
            factory.unbind.connect ((item) => {
                var entry = (MusicEntry) item.child;
                entry.paintable = null;
            });
            list_view.factory = factory;
            list_view.model = new Gtk.NoSelection (app.music_list);
            list_view.activate.connect ((index) => {
                app.current_item = (int) index;
                app.player.play ();
            });

            initial_label.activate_link.connect (on_music_folder_clicked);

            if (app.is_loading_store) {
                //  Make a call to show start loading
                on_loading_changed (true, 0);
            }
            app.loading_changed.connect (on_loading_changed);
            app.index_changed.connect (on_index_changed);
            app.music_changed.connect (on_music_changed);
            app.music_tag_parsed.connect (on_music_tag_parsed);
            app.player.state_changed.connect (on_player_state_changed);
            app.music_store.parse_progress.connect ((percent) => {
                index_title.label = @"$_loading_text $percent%";
            });
        }

        public uint background_blur {
            get {
                return _bkgnd_blur;
            }
            set {
                _bkgnd_blur = (BackgroundBlurMode) value;
                update_background ();
            }
        }

        public bool leaflet_folded {
            set {
                leaflet.navigate (Adw.NavigationDirection.FORWARD);
            }
        }

        private const string[] SORT_MODE_ICONS = {
            "media-optical-cd-audio-symbolic",  // ALBUM
            "system-users-symbolic",            // ARTIST
            "folder-music-symbolic",            // TITLE
            "document-open-recent-symbolic",    // RECENT
            "media-playlist-shuffle-symbolic"   // SHUFFLE
        };

        public SortMode sort_mode {
            set {
                if (value >= SortMode.ALBUM && value <= SortMode.SHUFFLE) {
                    sort_btn.set_icon_name (SORT_MODE_ICONS[value]);
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
                var size = page.child.get_width ();
                var rtl = get_direction () == Gtk.TextDirection.RTL;
                var rect = (!)Graphene.Rect ().init (rtl ? width - size : size, 0, 0.5f, height);
                var color = Gdk.RGBA ();
#if GTK_4_10
                var color2 = get_color ();
#else
                var color2 = get_style_context ().get_color ();
#endif
                color.red = color.green = color.blue = color.alpha = 0;
                color2.alpha = 0.25f;
                Gsk.ColorStop[] stops = { { 0, color }, { 0.5f, color2 }, { 1, color } };
                snapshot.append_linear_gradient (rect, rect.get_top_left (), rect.get_bottom_right (), stops);
            }
            base.snapshot (snapshot);
        }

        public void start_search (string text) {
            search_entry.text = text;
            search_btn.active = true;
            leaflet.navigate (Adw.NavigationDirection.BACK);
        }

        private HashTable<unowned Object, ulong> _first_draw_handles = new HashTable<unowned Object, ulong> (null, null);

        private void _remove_draw_signal_handle (Object key) {
            var id = _first_draw_handles[key];
            if (id != 0)
                key.disconnect (id);
            _first_draw_handles.remove (key);
        }

        private async void on_bind_item (Gtk.ListItem item) {
            var app = (Application) application;
            var entry = (MusicEntry) item.child;
            var music = (Music) item.item;
            entry.playing = item.position == app.current_item;
            entry.update (music, app.sort_mode);
            //  print ("bind: %u\n", item.position);

            var thumbnailer = app.thumbnailer;
            var paintable = thumbnailer.find (music);
            entry.paintable = paintable ?? _loading_paintable;
            if (paintable == null) {
                _remove_draw_signal_handle (entry.cover);
                var id = entry.cover.first_draw.connect(() => {
                    _remove_draw_signal_handle (entry.cover);
                    if (music == (Music) item.item) {
                        var paintable1 = thumbnailer.find (music);
                        if (paintable1 != null) {
                            entry.paintable = paintable1;
                        } else {
                            thumbnailer.load_async.begin (music, (obj, res) => {
                                var paintable2 = thumbnailer.load_async.end (res);
                                if (music == (Music) item.item) {
                                    entry.paintable = paintable2;
                                }
                            });
                        }
                    }
                });
                _first_draw_handles[entry.cover] = id;
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
            index_title.label = size > 0 ? @"$(index+1)/$(size)" : "";
            scroll_to_item (index);
        }

        private void on_loading_changed (bool loading, uint size) {
            spinner.spinning = loading;
            spinner.visible = loading;
            index_title.label = loading ? _loading_text : size.to_string ();

            var app = (Application) application;
            var empty = !loading && size == 0 && app.current_music == null;
            if (empty) {
                var dir_name = get_display_name (app.get_music_folder ());
                var link = @"<a href=\"change_dir\">$dir_name</a>";
                initial_label.set_markup (_("Drag and drop music files here,\nor change music location: ") + link);

                var theme = Gtk.IconTheme.get_for_display (this.display);
                var paintable = theme.lookup_icon (app.application_id, null,
                    _cover_size, 1, Gtk.TextDirection.NONE, Gtk.IconLookupFlags.FORCE_REGULAR);
                update_cover_paintables (new Music ("", "", 0), paintable);
            }
            initial_label.visible = empty;
            music_title.visible = !empty;
        }

        private bool on_music_folder_clicked (string uri) {
            var app = (Application) application;
            pick_music_folder_async.begin (app, this, (dir) => app.reload_music_store (),
                (obj, res) => pick_music_folder_async.end (res));
            return true;
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
            update_music_filter ();
        }

        private void on_music_changed (Music music) {
            update_music_info (music);
            action_set_enabled (ACTION_APP + ACTION_PLAY, true);
            print ("Play: %s\n", Uri.unescape_string (music.uri) ?? music.uri);
        }

        private async void on_music_tag_parsed (Music music, Gst.Sample? image) {
            update_music_info (music);

            var app = (Application) application;
            Gdk.Pixbuf? pixbuf = null;
            if (image != null) {
                pixbuf = yield run_async<Gdk.Pixbuf?> (() => {
                    return load_clamp_pixbuf_from_sample ((!)image, _cover_size);
                }, true);
            }
            if (music == app.current_music) {
                Gdk.Paintable? paintable = null;
                if (pixbuf != null) {
                    paintable = Gdk.Texture.for_pixbuf ((!)pixbuf);
                } else {
                    paintable = yield app.thumbnailer.load_directly_async (music, _cover_size);
                    if (paintable != null) {
                        app.music_cover_uri_parsed (music, music.cover_uri);
                    } else {
                        paintable = app.thumbnailer.create_album_text_paintable (music, _cover_size);
                    }
                }
                update_cover_paintables (music, paintable);
            }

            action_set_enabled (ACTION_APP + ACTION_EXPORT_COVER, image != null);
            action_set_enabled (ACTION_APP + ACTION_SHOW_COVER_FILE, image == null && music.cover_uri != null);
        }

        private void scroll_to_item (int index) {
            list_view.activate_action_variant ("list.scroll-to-item", new Variant.uint32 (index));
            Idle.add (() => {
                //  scrolling may failed when building the list, so scroll again later
                if (list_view.vadjustment.value == 0) {
                    list_view.activate_action_variant ("list.scroll-to-item", new Variant.uint32 (index));
                }
                return false;
            });
        }

        private void setup_drop_target () {
            var drop_target = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
#if GTK_4_10
            drop_target.drop.connect ((value, x, y) => {
#else
            drop_target.on_drop.connect ((value, x, y) => {
#endif
                var file_list = ((Gdk.FileList) value).get_files ();
                var count = file_list.length ();
                var files = new File[count];
                var index = 0;
                foreach (var file in file_list) {
                    files[index++] = file;
                }
                var app = (Application) application;
                app.load_musics_async.begin (files, (obj, res) => {
                    var item = app.load_musics_async.end (res);
                    if (app.current_music == null) {
                        app.current_item = item;
                    } else {
                        scroll_to_item (item);
                    }
                });
                return true;
            });
            this.content.add_controller (drop_target);
        }

        private void update_music_info (Music music) {
            music_album.label = music.album;
            music_artist.label = music.artist;
            music_title.label = music.title;
            _mini_bar.title = music.title;
            this.title = music.artist == UNKOWN_ARTIST ? music.title : @"$(music.artist) - $(music.title)";
        }

        private void update_music_filter () {
            var app = (Application) application;
            if (search_btn.active && _search_text.length > 0) {
                app.music_list.filter = new Gtk.CustomFilter ((obj) => {
                    var music = (Music) obj;
                    switch (_search_type) {
                        case SearchType.ALBUM:
                            return music.album == _search_property;
                        case SearchType.ARTIST:
                            return music.artist == _search_property;
                        case SearchType.TITLE:
                            return music.title == _search_property;
                        default:
                            return _search_text.match_string (music.album, false)
                                || _search_text.match_string (music.artist, false)
                                || _search_text.match_string (music.title, false);
                    }
                });
            } else {
                app.music_list.set_filter (null);
            }
            app.find_current_item ();
        }

        private Adw.Animation? _fade_animation = null;

        private void update_cover_paintables (Music music, Gdk.Paintable? paintable) {
            var app = (Application) application;
            _mini_bar.cover = app.thumbnailer.find (music);
            _cover_paintable.paintable = paintable ?? _mini_bar.cover;
            update_background ();

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
            var paintable = _mini_bar.cover ?? _cover_paintable.paintable;
            if ((_bkgnd_blur == BackgroundBlurMode.ALWAYS && paintable != null)
                || (_bkgnd_blur == BackgroundBlurMode.ART_ONLY && paintable is Gdk.Texture)) {
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

        private void update_background () {
            var width = get_width ();
            var height = get_height ();
            if (width > 0 && height > 0) {
                update_blur_paintable (width, height, true);
            }
        }
    }
}


