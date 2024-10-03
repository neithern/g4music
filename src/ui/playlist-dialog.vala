namespace G4 {

    public class PlaylistDialog : Dialog {
        private Gtk.ToggleButton search_btn = new Gtk.ToggleButton ();
        private Gtk.SearchEntry search_entry = new Gtk.SearchEntry ();

        private Application _app;
        private SourceFunc? _callback = null;
        private MusicList _list;
        private Playlist? _playlist = null;
        private bool _result = false;

        public PlaylistDialog (Application app) {
            _app = app;

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.child = content;

            var header = new Gtk.HeaderBar ();
            header.show_title_buttons = false;
            header.title_widget = new Gtk.Label (_("Add to Playlist"));
            header.add_css_class ("flat");
            content.append (header);

            var new_btn = new Gtk.Button.from_icon_name ("folder-new-symbolic");
            new_btn.tooltip_text = _("New Playlist");
            new_btn.clicked.connect (() => {
                close_with_result (true);
            });
            header.pack_start (new_btn);

            var close_btn = new Gtk.Button.from_icon_name ("window-close-symbolic");
            close_btn.tooltip_text = _("Close");
            close_btn.clicked.connect (() => {
                close_with_result (false);
            });
            header.pack_end (close_btn);
            header.pack_end (search_btn);

            var search_bar = new Gtk.SearchBar ();
            search_bar.child = search_entry;
            search_bar.key_capture_widget = content;
            content.append (search_bar);

            search_btn.icon_name = "edit-find-symbolic";
            search_btn.tooltip_text = _("Search");
            search_btn.toggled.connect (on_search_btn_toggled);
            search_btn.bind_property ("active", search_bar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);
            search_entry.hexpand = true;
            search_entry.search_changed.connect (on_search_text_changed);

            var loading_paintable = app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);
            var list = _list = new MusicList (app, typeof (Playlist), null, false, false);
            list.hexpand = true;
            list.vexpand = true;
            list.margin_bottom = 2;
            list.item_activated.connect ((position, obj) => {
                _playlist = obj as Playlist;
                close_with_result (true);
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicWidget) item.child;
                var playlist = (Playlist) item.item;
                cell.music = playlist;
                cell.paintable = loading_paintable;
                cell.title = playlist.title;
            });
            content.append (list);

            app.music_library_changed.connect (on_music_library_changed);
            on_music_library_changed (true);
        }

        public Playlist? playlist {
            get {
                return _playlist;
            }
        }

        public async bool choose (Gtk.Window? parent = null) {
            _callback = choose.callback;
            present (parent);
            yield;
            return _result;
        }

        private void close_with_result (bool result) {
            _app.music_library_changed.disconnect (on_music_library_changed);
            _result = result;
            if (_callback != null)
                Idle.add ((!)_callback);
            close ();
        }

        private void on_music_library_changed (bool external) {
            if (external) {
                unowned var store = _list.data_store;
                var text = _("No playlist found in %s").printf (get_display_name (_app.music_folder));
                _app.loader.library.overwrite_playlists_to (store);
                _list.set_empty_text (text);
            }
        }

        private void on_search_btn_toggled () {
            if (search_btn.active) {
                search_entry.grab_focus ();
            }
            on_search_text_changed ();
        }

        private string _search_text = "";

        private bool on_search_match (Object obj) {
            unowned var playlist = (Playlist) obj;
            return _search_text.match_string (playlist.title, true);
        }

        private void on_search_text_changed () {
            _search_text = search_entry.text;
            var model = _list.filter_model;
            if (search_btn.active && model.get_filter () == null) {
                model.set_filter (new Gtk.CustomFilter (on_search_match));
            } else if (!search_btn.active && model.get_filter () != null) {
                model.set_filter (null);
            }
            model.get_filter ()?.changed (Gtk.FilterChange.DIFFERENT);
        }
    }
}
