namespace G4 {

    public class PlaylistDialog : Dialog {
        private Gtk.ToggleButton search_btn = new Gtk.ToggleButton ();
        private Gtk.SearchEntry search_entry = new Gtk.SearchEntry ();

        private Application _app;
        private SourceFunc? _callback = null;
        private MusicList? _list = null;
        private Playlist? _playlist = null;

        public PlaylistDialog (Application app) {
            _app = app;

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.child = content;

            var header = new Gtk.HeaderBar ();
            header.title_widget = new Gtk.Label (_("Add to Playlist"));
            header.add_css_class ("flat");
            content.append (header);

            var new_btn = new Gtk.Button.from_icon_name ("folder-new-symbolic");
            new_btn.tooltip_text = _("New Playlist");
            new_btn.clicked.connect (() => close_with_result (new Playlist ("")));
            header.pack_start (new_btn);

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
            var list = new MusicList (app, typeof (Playlist), null, false, false);
            list.hexpand = true;
            list.vexpand = true;
            list.margin_bottom = 2;
            list.item_activated.connect ((position, obj) => close_with_result (obj as Playlist));
            list.item_created.connect ((item) => {
                var cell = (MusicWidget) item.child;
                cell.playing.icon_name = "document-open-recent-symbolic";
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicWidget) item.child;
                var playlist = (Playlist) item.item;
                cell.music = playlist;
                cell.paintable = loading_paintable;
                cell.title = playlist.title;
            });
            content.append (list);
            _list = list;

            app.music_library_changed.connect (on_music_library_changed);
            on_music_library_changed (true);
        }

        public async Playlist? choose (Gtk.Window? parent = null) {
            _callback = choose.callback;
            present (parent);
            yield;
            return _playlist;
        }

        public override void closed () {
            _app.music_library_changed.disconnect (on_music_library_changed);

            var list = _list;
            _list = null;
            run_idle_once (() => list?.unparent (), Priority.LOW);

            var callback = _callback;
            _callback = null;
            if (callback != null)
                Idle.add ((!)callback);
        }

        private void close_with_result (Playlist? playlist) {
            _playlist = playlist;
            if ((playlist?.list_uri?.length ?? 0) > 0)
                _app.settings.set_string ("recent-playlist", ((!)playlist).list_uri);
            close ();
        }

        private void on_music_library_changed (bool external) {
            if (external && _list != null) {
                var list = (!)_list;
                var library = _app.loader.library;
                var store = list.data_store;
                var text = _("No playlist found in %s").printf (get_display_name (_app.music_folder));
                library.overwrite_playlists_to (store);
                list.set_empty_text (text);

                var recent_uri = _app.settings.get_string ("recent-playlist");
                list.current_node = library.get_playlist ((!)recent_uri);
                list.set_to_current_item (true);
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
            var model = _list?.filter_model;
            if (search_btn.active && model?.get_filter () == null) {
                model?.set_filter (new Gtk.CustomFilter (on_search_match));
            } else if (!search_btn.active && model?.get_filter () != null) {
                model?.set_filter (null);
            }
            model?.get_filter ()?.changed (Gtk.FilterChange.DIFFERENT);
        }
    }
}
