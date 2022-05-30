namespace Music {

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/preferences.ui")]
    public class PreferencesWindow : Adw.PreferencesWindow {
        [GtkChild]
        unowned Adw.ActionRow tracker_row;
        [GtkChild]
        unowned Gtk.Switch tracker_btn;
        [GtkChild]
        unowned Gtk.Button music_dir_btn;

        public PreferencesWindow (Application app) {
#if HAS_TRACKER_SPARQL
            var settings = new Settings (app.application_id);
            tracker_row.visible = true;
            tracker_btn.state = settings.get_boolean ("tracker-mode");
            tracker_btn.state_set.connect ((state) => {
                settings.set_boolean ("tracker-mode", state);
                app.reload_song_store ();
                return false;
            });
#else
            tracker_row.visible = false;
#endif

            var music_dir = app.get_music_folder (settings);
            music_dir_btn.label = music_dir.get_basename ();
            music_dir_btn.clicked.connect (() => {
                var chooser = new Gtk.FileChooserNative (null, this,
                                Gtk.FileChooserAction.SELECT_FOLDER, null, null);
                try {
                    chooser.set_file (music_dir);
                } catch (Error e) {
                }
                chooser.modal = true;
                chooser.response.connect ((id) => {
                    if (id == Gtk.ResponseType.ACCEPT) {
                        var dir = chooser.get_file ();
                        if (dir != music_dir) {
                            music_dir_btn.label = dir.get_basename ();
                            settings.set_string ("music-dir", dir.get_uri ());
                            app.reload_song_store ();
                        }
                    }
                });
                chooser.show ();
            });
        }
    }
}