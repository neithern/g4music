namespace G4 {

    namespace SearchType {
        public const uint ALL = 0;
        public const uint ALBUM = 1;
        public const uint ARTIST = 2;
        public const uint TITLE = 3;
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
        private unowned Gtk.Box music_box;
        [GtkChild]
        private unowned Gtk.Image music_cover;
        [GtkChild]
        private unowned Gtk.Label music_album;
        [GtkChild]
        private unowned Gtk.Label music_artist;
        [GtkChild]
        private unowned Gtk.Label music_title;
        [GtkChild]
        private unowned Gtk.Label initial_label;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_view;
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

        private uint _bkgnd_blur = BlurMode.ALWAYS;
        private CrossFadePaintable _bkgnd_paintable = new CrossFadePaintable ();
        private CrossFadePaintable _cover_paintable = new CrossFadePaintable ();
        private Gdk.Paintable? _loading_paintable = null;
        private ScalePaintable _scale_cover_paintable = new ScalePaintable ();

        private bool _compact_playlist = false;
        private int _blur_size = 512;
        private int _cover_size = 1024;
        private string _loading_text = _("Loading…");
        private double _row_height = 0;
        private double _scroll_range = 0;

        private string _search_text = "";
        private string _search_property = "";
        private uint _search_type = SearchType.ALL;

        public Window (Application app) {
            Object (application: app);
            this.icon_name = app.application_id;
            this.title = app.name;

            this.close_request.connect (on_close_request);

            var settings = app.settings;
            settings.bind ("width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings.bind ("height", this, "default-height", SettingsBindFlags.DEFAULT);
            settings.bind ("blur-mode", this, "blur-mode", SettingsBindFlags.DEFAULT);
            settings.bind ("compact-playlist", this, "compact-playlist", SettingsBindFlags.DEFAULT);

            setup_drop_target ();

            leaflet.bind_property ("folded", this, "leaflet-folded");
            leaflet.navigate (Adw.NavigationDirection.FORWARD);
            back_btn.clicked.connect (() => leaflet.navigate (Adw.NavigationDirection.BACK));

            app.bind_property ("sort-mode", this, "sort-mode", BindingFlags.SYNC_CREATE);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = this.content;
            search_entry.search_changed.connect (on_search_text_changed);

            mini_box.append (_mini_bar);
            _mini_bar.cover = app.icon;
            _mini_bar.activated.connect (() => leaflet.navigate (Adw.NavigationDirection.FORWARD));

            _bkgnd_paintable.queue_draw.connect (this.queue_draw);
            _cover_paintable.queue_draw.connect (music_cover.queue_draw);
            _cover_paintable.paintable = app.icon;

            app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            _scale_cover_paintable.paintable = new RoundPaintable (_cover_paintable, 12);
            _scale_cover_paintable.scale = 0.8;
            _scale_cover_paintable.queue_draw.connect (music_cover.queue_draw);
            music_cover.paintable = _scale_cover_paintable;

            music_album.tooltip_text = _("Search Album");
            music_artist.tooltip_text = _("Search Artist");
            make_right_clickable (music_box, show_popover_menu);
            make_label_clickable (music_album).released.connect (
                () => start_search ("album:" + music_album.label));
            make_label_clickable (music_artist).released.connect (
                () => start_search ("artist:" + music_artist.label));

            var play_bar = new PlayBar ();
            music_box.append (play_bar);
            action_set_enabled (ACTION_APP + ACTION_PREV, false);
            action_set_enabled (ACTION_APP + ACTION_PLAY, false);
            action_set_enabled (ACTION_APP + ACTION_NEXT, false);

            scroll_view.vadjustment.changed.connect (on_scrollview_vadjustment_changed);

            list_view.activate.connect ((index) => app.current_item = (int) index);
            Idle.add (() => {
                // Delay set model after the window shown to avoid slowing down it showing
                if (get_height () > 0 && list_view.get_model () == null) {
                    list_view.model = new Gtk.NoSelection (app.music_list);
                    run_idle_once (() => scroll_to_item (app.current_item), Priority.HIGH);
                }
                return list_view.get_model () == null;
            }, Priority.LOW);

            initial_label.activate_link.connect (on_music_folder_clicked);

            app.index_changed.connect (on_index_changed);
            app.music_changed.connect (on_music_changed);
            app.music_tag_parsed.connect (on_music_tag_parsed);
            app.music_store.loading_changed.connect (on_loading_changed);
            app.music_store.parse_progress.connect ((percent) => index_title.label = @"$percent%");
            app.player.state_changed.connect (on_player_state_changed);
        }

        public uint blur_mode {
            get {
                return _bkgnd_blur;
            }
            set {
                _bkgnd_blur = value;
                update_background ();
            }
        }

        public bool compact_playlist {
            get {
                return _compact_playlist;
            }
            set {
                _compact_playlist = value;
                list_view.factory = create_list_factory ();
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

        public uint sort_mode {
            set {
                if (value >= SortMode.ALBUM && value <= SortMode.SHUFFLE) {
                    sort_btn.set_icon_name (SORT_MODE_ICONS[value]);
                }
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = get_width ();
            var height = get_height ();
            _bkgnd_paintable.snapshot (snapshot, width, height);
            if (!leaflet.folded) {
                var page = (Adw.LeafletPage) leaflet.pages.get_item (0);
                var size = page.child.get_width ();
                var rtl = get_direction () == Gtk.TextDirection.RTL;
                var rect = Graphene.Rect ();
                rect.init (rtl ? width - size : size, 0, 0.5f, height);
                var color = Gdk.RGBA ();
                color.red = color.green = color.blue = color.alpha = 0;
#if GTK_4_10
                var color2 = get_color ();
#else
                var color2 = get_style_context ().get_color ();
#endif
                color2.alpha = 0.25f;
                Gsk.ColorStop[] stops = { { 0, color }, { 0.5f, color2 }, { 1, color } };
                snapshot.append_linear_gradient (rect, rect.get_top_left (), rect.get_bottom_right (), stops);
            }
            base.snapshot (snapshot);
        }

        private Gtk.ListItemFactory create_list_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((item) => item.child = new MusicEntry (_compact_playlist));
            factory.bind.connect (on_bind_item);
            factory.unbind.connect (on_unbind_item);
            return factory;
        }

        private uint get_music_count () {
            return list_view.get_model ()?.get_n_items () ?? 0;
        }

        public void start_search (string text) {
            search_entry.text = text;
            search_entry.select_region (text.index_of_char (':') + 1, -1);
            search_btn.active = true;
            leaflet.navigate (Adw.NavigationDirection.BACK);
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
                entry.first_draw_handler = entry.cover.first_draw.connect (() => {
                    entry.disconnect_first_draw ();
                    thumbnailer.load_async.begin (music, Thumbnailer.ICON_SIZE, (obj, res) => {
                        var paintable2 = thumbnailer.load_async.end (res);
                        if (music == (Music) item.item) {
                            entry.paintable = paintable2;
                        }
                    });
                });
            }
        }

        private void on_unbind_item (Gtk.ListItem item) {
            var entry = (MusicEntry) item.child;
            entry.disconnect_first_draw ();
            entry.paintable = null;
        }

        private bool on_close_request () {
            var app = (Application) application;
            if (app.player.playing && app.settings.get_boolean ("play-background")) {
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

        private void on_loading_changed (bool loading) {
            var app = (Application) application;
            var index = app.current_item;
            var size = get_music_count ();
            action_set_enabled (ACTION_APP + ACTION_RELOAD_LIST, !loading);
            spinner.spinning = loading;
            spinner.visible = loading;
            index_title.label = loading ? _loading_text : @"$(index+1)/$(size)";
            update_music_info (app.current_music);
        }

        private void on_music_changed (Music? music) {
            update_music_info (music);
            action_set_enabled (ACTION_APP + ACTION_PLAY, music != null);
        }

        private bool on_music_folder_clicked (string uri) {
            var app = (Application) application;
            pick_music_folder_async.begin (app, this,
                (dir) => update_initial_label (dir.get_uri ()),
                (obj, res) => pick_music_folder_async.end (res));
            return true;
        }

        private async void on_music_tag_parsed (Music music, Gst.Sample? image) {
            update_music_info (music);

            var app = (Application) application;
            Gdk.Pixbuf? pixbuf = null;
            Gdk.Paintable? paintable = null;
            if (image != null) {
                pixbuf = yield run_async<Gdk.Pixbuf?> (
                    () => load_clamp_pixbuf_from_sample ((!)image, _cover_size), true);
                if (pixbuf != null)
                    paintable = Gdk.Texture.for_pixbuf ((!)pixbuf);
            } else {
                paintable = yield app.thumbnailer.load_async (music, _cover_size);
            }
            if (music == app.current_music) {
                //  Remote thumbnail may not loaded
                if (pixbuf != null && !(app.thumbnailer.find (music) is Gdk.Texture)) {
                    pixbuf = yield run_async<Gdk.Pixbuf?> (
                        () => create_clamp_pixbuf ((!)pixbuf, Thumbnailer.ICON_SIZE)
                    );
                    if (pixbuf != null && music == app.current_music) {
                        app.thumbnailer.put (music, Gdk.Texture.for_pixbuf ((!)pixbuf), true);
                        app.music_list.items_changed (app.current_item, 0, 0);
                    }
                }

                if (music == app.current_music) {
                    if (paintable == null)
                        paintable = app.thumbnailer.create_album_text_paintable (music);
                    update_cover_paintables (music, paintable);
                    yield app.parse_music_cover_async ();
                }
            }
        }

        private void on_scrollview_vadjustment_changed () {
            var adj = scroll_view.vadjustment;
            var range = adj.upper - adj.lower;
            var size = get_music_count ();
            if (size > 0 && _scroll_range != range && range > list_view.get_height ()) {
                _row_height = range / size;
                _scroll_range = range;
            }
        }

        private void on_search_btn_toggled () {
            if (search_btn.active) {
                search_entry.grab_focus ();
                if (leaflet.folded) {
                    leaflet.navigate (Adw.NavigationDirection.BACK);
                }
            }
            update_music_filter ();
        }

        private bool on_search_match (Object obj) {
            var music = (Music) obj;
            switch (_search_type) {
                case SearchType.ALBUM:
                    return _search_property.match_string (music.album, true);
                case SearchType.ARTIST:
                    return _search_property.match_string (music.artist, true);
                case SearchType.TITLE:
                    return _search_property.match_string (music.title, true);
                default:
                    return _search_text.match_string (music.album, true)
                        || _search_text.match_string (music.artist, true)
                        || _search_text.match_string (music.title, true);
            }
        }

        private void on_search_text_changed () {
            string text = search_entry.text;
            if (text.ascii_ncasecmp ("album:", 6) == 0) {
                _search_property = text.substring (6);
                _search_type = SearchType.ALBUM;
            } else if (text.ascii_ncasecmp ("artist:", 7) == 0) {
                _search_property = text.substring (7);
                _search_type = SearchType.ARTIST;
            } else if (text.ascii_ncasecmp ("title:", 6) == 0) {
                _search_property = text.substring (6);
                _search_type = SearchType.TITLE;
            } else {
                _search_type = SearchType.ALL;
            }
            _search_text = text;
            update_music_filter ();
        }

        private Adw.Animation? _scale_animation = null;

        private void on_player_state_changed (Gst.State state) {
            if (state >= Gst.State.PAUSED) {
                var scale_paintable = (!)(music_cover.paintable as ScalePaintable);
                var target = new Adw.CallbackAnimationTarget ((value) => scale_paintable.scale = value);
                _scale_animation?.pause ();
                _scale_animation = new Adw.TimedAnimation (music_cover,  scale_paintable.scale,
                                            state == Gst.State.PLAYING ? 1 : 0.85, 500, target);
                _scale_animation?.play ();
            }
        }

        private Adw.Animation? _scroll_animation = null;

        private void scroll_to_item (int index) {
            var adj = scroll_view.vadjustment;
            var list_height = list_view.get_height ();
            if (_row_height > 0 && adj.upper - adj.lower > list_height) {
                var from = adj.value;
                var max_to = double.max ((index + 1) * _row_height - list_height, 0);
                var min_to = double.max (index * _row_height, 0);
                var scroll_to =  from < max_to ? max_to : (from > min_to ? min_to : from);
                var diff = (scroll_to - from).abs ();
                if (diff > list_height) {
                    _scroll_animation?.pause ();
                    adj.value = min_to;
                } else if (diff > 0) {
                    //  Scroll smoothly
                    var target = new Adw.CallbackAnimationTarget (adj.set_value);
                    _scroll_animation?.pause ();
                    _scroll_animation = new Adw.TimedAnimation (scroll_view, from, scroll_to, 500, target);
                    _scroll_animation?.play ();
                } 
            } else if (get_music_count () > 0) {
#if GTK_4_10
                list_view.activate_action_variant ("list.scroll-to-item", new Variant.uint32 (index));
#else
                //  Delay scroll if items not size_allocated, to ensure items visible in GNOME 42
                run_idle_once (() => scroll_to_item (index));
#endif
            }
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

        private void show_popover_menu (double x, double y) {
            var app = (Application) application;
            var music = app.current_music;
            if (music != null) {
                var popover = create_music_popover_menu ((!)music, x, y, 
                                                false, app.current_cover != null);
                popover.set_parent (music_box);
                popover.popup ();
            }
        }

        private void update_music_info (Music? music) {
            var app = (Application) application;
            var size = get_music_count ();
            var empty = !app.is_loading_store && size == 0 && music == null;
            if (empty) {
                update_cover_paintables (new Music.empty (), app.icon);
                update_initial_label (app.music_folder);
            }
            initial_label.visible = empty;

            music_album.visible = !empty;
            music_artist.visible = !empty;
            music_title.visible = !empty;
            music_album.label = music?.album ?? "";
            music_artist.label = music?.artist ?? "";
            music_title.label = music?.title ?? "";
            _mini_bar.title = music?.title ?? "";
            this.title = music?.get_artist_and_title () ?? app.name;
        }

        private void update_music_filter () {
            var app = (Application) application;
            if (search_btn.active) {
                app.music_list.set_filter (new Gtk.CustomFilter (on_search_match));
            } else {
                app.music_list.set_filter (null);
            }
        }

        private Adw.Animation? _fade_animation = null;

        private void update_cover_paintables (Music music, Gdk.Paintable? paintable) {
            var app = (Application) application;
            _mini_bar.cover = app.thumbnailer.find (music) ?? paintable;
            _cover_paintable.paintable = paintable ?? _mini_bar.cover;
            update_background ();

            var target = new Adw.CallbackAnimationTarget ((value) => {
                _bkgnd_paintable.fade = value;
                _cover_paintable.fade = value;
            });
            _fade_animation?.pause ();
            _fade_animation = new Adw.TimedAnimation (music_cover, 1 - _cover_paintable.fade, 0, 800, target);
            ((!)_fade_animation).done.connect (() => {
                _bkgnd_paintable.previous = null;
                _cover_paintable.previous = null;
                _fade_animation = null;
            });
            _fade_animation?.play ();
        }

        private void update_background () {
            var paintable = _mini_bar.cover ?? _cover_paintable.paintable;
            if ((_bkgnd_blur == BlurMode.ALWAYS && paintable != null)
                || (_bkgnd_blur == BlurMode.ART_ONLY && paintable is Gdk.Texture)) {
                _bkgnd_paintable.paintable = create_blur_paintable (this,
                    (!)paintable, _blur_size, _blur_size, 64);
            } else {
                _bkgnd_paintable.paintable = null;
            }
        }

        private void update_initial_label (string uri) {
            var dir_name = get_display_name (uri);
            var link = @"<a href=\"change_dir\">$dir_name</a>";
            initial_label.set_markup (_("Drag and drop music files here,\nor change music location: ") + link);
        }
    }
}

