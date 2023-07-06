namespace G4 {

    namespace SearchMode {
        public const uint ALL = 0;
        public const uint ALBUM = 1;
        public const uint ARTIST = 2;
        public const uint TITLE = 3;
    }

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/store-panel.ui")]
    public class StorePanel : Gtk.Box {
        [GtkChild]
        private unowned Gtk.HeaderBar header_bar;
        [GtkChild]
        private unowned Gtk.Spinner spinner;
        [GtkChild]
        private unowned Gtk.Label index_title;
        [GtkChild]
        private unowned Gtk.MenuButton sort_btn;
        [GtkChild]
        public unowned Gtk.ToggleButton search_btn;
        [GtkChild]
        private unowned Gtk.SearchBar search_bar;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_view;
        [GtkChild]
        private unowned Gtk.ListView list_view;

        private Application _app;
        private bool _compact_playlist = false;
        private Gdk.Paintable _loading_paintable;
        private string _loading_text = _("Loading…");
        private double _row_height = 0;
        private double _scroll_range = 0;
        private uint _sort_mode = 0;

        private string _search_text = "";
        private string _search_property = "";
        private uint _search_mode = SearchMode.ALL;

        public StorePanel (Application app, Window win, Adw.Leaflet leaflet) {
            _app = app;

            leaflet.bind_property ("folded", header_bar, "show-title-buttons", BindingFlags.SYNC_CREATE);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = win.content;
            search_entry.search_changed.connect (on_search_text_changed);

            _app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = _app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            scroll_view.vadjustment.changed.connect (on_scrollview_vadjustment_changed);

            list_view.activate.connect ((index) => _app.current_item = (int) index);
            Idle.add (() => {
                // Delay set model after the window shown to avoid slowing down it showing
                if (root.get_height () > 0 && list_view.get_model () == null) {
                    list_view.model = new Gtk.NoSelection (_app.music_list);
                    run_idle_once (() => scroll_to_item (_app.current_item), Priority.HIGH);
                }
                return root.get_height () == 0;
            }, Priority.LOW);

            app.index_changed.connect (on_index_changed);
            app.music_store.loading_changed.connect (on_loading_changed);
            app.music_store.parse_progress.connect ((percent) => index_title.label = @"$percent%");

            var settings = app.settings;
            settings.bind ("compact-playlist", this, "compact-playlist", SettingsBindFlags.DEFAULT);
            settings.bind ("sort-mode", this, "sort-mode", SettingsBindFlags.DEFAULT);
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

        private const string[] SORT_MODE_ICONS = {
            "media-optical-cd-audio-symbolic",  // ALBUM
            "system-users-symbolic",            // ARTIST
            "folder-music-symbolic",            // TITLE
            "document-open-recent-symbolic",    // RECENT
            "media-playlist-shuffle-symbolic",  // SHUFFLE
            "avatar-default-symbolic",          // ARTIST_ALBUM
        };

        public uint sort_mode {
            get {
                return _sort_mode;
            }
            set {
                _sort_mode = value;
                if (value >= SortMode.ALBUM && value <= SortMode.MAX) {
                    sort_btn.set_icon_name (SORT_MODE_ICONS[value]);
                    if (get_music_count () > 0)
                        list_view.factory = create_list_factory ();
                }
            }
        }

        private Adw.Animation? _scroll_animation = null;

        public void scroll_to_item (int index) {
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
#if GTK_4_10
            var delay = search_entry.search_delay;
            search_entry.search_delay = 0;
            run_idle_once (() => search_entry.search_delay = delay);
#endif
            search_entry.text = text;
            search_entry.select_region (text.index_of_char (':') + 1, -1);
            search_btn.active = true;
        }

        private async void on_bind_item (Gtk.ListItem item) {
            var entry = (MusicEntry) item.child;
            var music = (Music) item.item;
            entry.playing = item.position == _app.current_item;
            entry.update (music, _sort_mode);
            //  print ("bind: %u\n", item.position);

            var thumbnailer = _app.thumbnailer;
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

        private void on_index_changed (int index, uint size) {
            root.action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
            root.action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
            index_title.label = size > 0 ? @"$(index+1)/$(size)" : "";
            scroll_to_item (index);
        }

        private void on_loading_changed (bool loading) {
            var index = _app.current_item;
            var size = get_music_count ();
            root.action_set_enabled (ACTION_APP + ACTION_RELOAD_LIST, !loading);
            spinner.spinning = loading;
            spinner.visible = loading;
            index_title.label = loading ? _loading_text : @"$(index+1)/$(size)";
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
            }
            update_music_filter ();
        }

        private bool on_search_match (Object obj) {
            var music = (Music) obj;
            switch (_search_mode) {
                case SearchMode.ALBUM:
                    return _search_property.match_string (music.album, true);
                case SearchMode.ARTIST:
                    return _search_property.match_string (music.artist, true);
                case SearchMode.TITLE:
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
                _search_mode = SearchMode.ALBUM;
            } else if (text.ascii_ncasecmp ("artist:", 7) == 0) {
                _search_property = text.substring (7);
                _search_mode = SearchMode.ARTIST;
            } else if (text.ascii_ncasecmp ("title:", 6) == 0) {
                _search_property = text.substring (6);
                _search_mode = SearchMode.TITLE;
            } else {
                _search_mode = SearchMode.ALL;
            }
            _search_text = text;
            update_music_filter ();
        }

        private void update_music_filter () {
            _app.music_list.set_filter (search_btn.active ? new Gtk.CustomFilter (on_search_match) : (Gtk.CustomFilter?) null);
        }
    }
}
