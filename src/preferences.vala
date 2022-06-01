namespace Music {

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/preferences.ui")]
    public class PreferencesWindow : Adw.PreferencesWindow {
        [GtkChild]
        unowned Adw.ActionRow tracker_row;
        [GtkChild]
        unowned Gtk.Switch tracker_btn;
        [GtkChild]
        unowned Gtk.Button music_dir_btn;
        [GtkChild]
        unowned Gtk.Switch pipewire_btn;
        [GtkChild]
        unowned Gtk.Switch peak_btn;

        public PreferencesWindow (Application app) {
            var settings = app.settings;

#if HAS_TRACKER_SPARQL
            settings.bind ("tracker-mode", tracker_btn, "state", SettingsBindFlags.DEFAULT);
            tracker_row.visible = true;
            tracker_btn.state_set.connect ((state) => {
                // reload later after setting apply
                Idle.add (() => {
                    app.reload_song_store ();
                    return false;
                });
                return false;
            });
#else
            tracker_row.visible = false;
#endif

            var music_dir = app.get_music_folder ();
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
                        if (dir != null && dir != music_dir) {
                            music_dir_btn.label = dir?.get_basename () ?? "";
                            settings.set_string ("music-dir", dir?.get_uri () ?? "");
                            app.reload_song_store ();
                        }
                    }
                });
                chooser.show ();
            });

            settings.bind ("pipewire-sink", pipewire_btn, "state", SettingsBindFlags.DEFAULT);
            pipewire_btn.state_set.connect ((state) => {
                app.player.use_pipewire (state);
                app.player.restart ();
                return false;
            });

            settings.bind ("show-peak", peak_btn, "state", SettingsBindFlags.DEFAULT);
            peak_btn.state_set.connect ((state) => {
                app.player.show_peak (state);
                app.player.restart ();
                return false;
            });
        }
    }
}