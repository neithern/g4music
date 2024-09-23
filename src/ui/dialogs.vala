namespace G4 {

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/playlist-dialog.ui")]
    public class PlaylistDialog : Gtk.Window {
        [GtkChild]
        private unowned Gtk.Box content;
        [GtkChild]
        private unowned Gtk.Button new_btn;
        [GtkChild]
        private unowned Gtk.ToggleButton search_btn;
        [GtkChild]
        private unowned Gtk.SearchBar search_bar;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry;

        private Application _app;
        private SourceFunc? _callback = null;
        private MusicList _list;
        private Playlist? _playlist = null;
        private bool _result = false;

        public PlaylistDialog (Application app) {
            _app = app;

            new_btn.clicked.connect (() => {
                destroy ();
                set_result (true);
            });

            close_request.connect (() => {
                set_result (false);
                return false;
            });

            var loading_paintable = app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);
            var list = _list = new MusicList (app, typeof (Playlist), null, false, false);
            list.hexpand = true;
            list.vexpand = true;
            list.item_activated.connect ((position, obj) => {
                _playlist = obj as Playlist;
                destroy ();
                set_result (true);
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicWidget) item.child;
                var playlist = (Playlist) item.item;
                cell.music = playlist;
                cell.paintable = loading_paintable;
                cell.title = playlist.title;
            });

            app.music_library_changed.connect (on_music_library_changed);
            on_music_library_changed (true);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = content;
            search_entry.search_changed.connect (on_search_text_changed);

            content.append (list);
        }

        public Playlist? playlist {
            get {
                return _playlist;
            }
        }

        public async bool choose (Gtk.Window? parent = null) {
            if (parent != null) {
                modal = true;
                transient_for = (!)parent;
            }

            _callback = choose.callback;
            present ();
            yield;
            return _result;
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            base.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.VERTICAL) {
                var height = transient_for.get_height ();
                if (natural > height && height > 0)
                    natural = height;
            }
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

        private void set_result (bool result) {
            _app.music_library_changed.disconnect (on_music_library_changed);
            _result = result;
            if (_callback != null)
                Idle.add ((!)_callback);
        }
    }

    public async bool show_alert_dialog (string text, Gtk.Window? parent = null) {
#if GTK_4_10
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