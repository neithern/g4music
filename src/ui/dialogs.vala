namespace G4 {

#if ADW_1_5
    public class PlaylistDialog : Adw.Dialog {
#else
    public class PlaylistDialog : Gtk.Window {
#endif
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
#if ADW_1_5
            present (parent);
#else
            if (parent != null) {
                modal = true;
                transient_for = (!)parent;
            }
            set_titlebar (new Adw.Bin ());
            present ();
#endif
            yield;
            return _result;
        }

#if ADW_1_5
#else
        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            child.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.VERTICAL) {
                var height = transient_for.get_height ();
                if (natural > height && height > 0)
                    natural = height;
            }
        }
#endif

        private void close_with_result (bool result) {
            _app.music_library_changed.disconnect (on_music_library_changed);
            _result = result;
            if (_callback != null)
                Idle.add ((!)_callback);
#if ADW_1_5
            close ();
#else
            destroy ();
#endif
        }

        private void on_music_library_changed (bool external) {
            if (external) {
                unowned var store = _list.data_store;
                _app.loader.library.overwrite_playlists_to (store);
                if (store.get_n_items () == 0)
                    _list.set_empty_text (_("No playlist found"));
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

    public async bool show_alert_dialog (string text, Gtk.Window? parent = null) {
#if ADW_1_5
        var result = new bool[] { false };
        var dialog = new Adw.AlertDialog (null, text);
        dialog.add_response ("no", _("No"));
        dialog.add_response ("yes", _("Yes"));
        dialog.default_response = "yes";
        dialog.response.connect ((id) => {
            result[0] = id == "yes";
            Idle.add (show_alert_dialog.callback);
        });
        dialog.present (parent);
        yield;
        return result[0];
#elif GTK_4_10
        var dialog = new Gtk.AlertDialog (text);
        dialog.buttons = { _("No"), _("Yes") };
        dialog.cancel_button = 0;
        dialog.default_button = 1;
        dialog.modal = true;
        try {
            var btn = yield dialog.choose (parent, null);
            return btn == 1;
        } catch (Error e) {
        }
        return false;
#else
        var result = new int[] { -1 };
        var dialog = new Gtk.MessageDialog (parent, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                            Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, text);
        dialog.response.connect ((id) => {
            dialog.destroy ();
            result[0] = id;
            Idle.add (show_alert_dialog.callback);
        });
        dialog.set_titlebar (new Adw.Bin ());
        dialog.present ();
        yield;
        return result[0] == Gtk.ResponseType.YES;
#endif
    }

    public async File? show_save_file_dialog (Gtk.Window? parent, File? initial = null, Gtk.FileFilter[]? filters = null) {
        Gtk.FileFilter? default_filter = filters != null && ((!)filters).length > 0 ? ((!)filters)[0] : (Gtk.FileFilter?) null;
#if GTK_4_10
        var filter_list = new ListStore (typeof (Gtk.FileFilter));
        if (filters != null) {
            foreach (var filter in (!)filters) 
                filter_list.append (filter);
        }
        var dialog = new Gtk.FileDialog ();
        dialog.filters = filter_list;
        dialog.modal = true;
        dialog.set_default_filter (default_filter);
        dialog.set_initial_file (initial);
        try {
            return yield dialog.save (parent, null);
        } catch (Error e) {
        }
        return null;
#else
        var result = new File?[] { (File?) null };
        var chooser = new Gtk.FileChooserNative (null, parent, Gtk.FileChooserAction.SAVE, null, null);
        chooser.modal = true;
        try {
            chooser.set_current_folder (initial?.get_parent ());
            chooser.set_current_name (initial?.get_basename () ?? "");
        } catch (Error e) {
        }
        if (filters != null) {
            foreach (var filter in (!)filters) 
                chooser.add_filter (filter);
            if (default_filter != null)
                chooser.set_filter ((!)default_filter);
        }
        chooser.response.connect ((id) => {
            var file = chooser.get_file ();
            if (id == Gtk.ResponseType.ACCEPT && file is File) {
                result[0] = file;
                Idle.add (show_save_file_dialog.callback);
            }
        });
        chooser.show ();
        yield;
        return result[0];
#endif
    }
}