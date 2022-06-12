namespace Music {

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/preferences.ui")]
    public class PreferencesWindow : Adw.PreferencesWindow {
        [GtkChild]
        unowned Gtk.Switch dark_btn;
#if HAS_TRACKER_SPARQL
        [GtkChild]
        unowned Adw.ActionRow tracker_row;
        [GtkChild]
        unowned Gtk.Switch tracker_btn;
#endif
        [GtkChild]
        unowned Gtk.Button music_dir_btn;
        [GtkChild]
        unowned Gtk.Switch thumbnail_btn;
        [GtkChild]
        unowned Gtk.Switch pipewire_btn;
        [GtkChild]
        unowned Gtk.Switch peak_btn;

        public PreferencesWindow (Application app) {
            var settings = app.settings;

            dark_btn.bind_property ("state", app, "dark_theme", BindingFlags.DEFAULT);
            settings.bind ("dark-theme", dark_btn, "state", SettingsBindFlags.DEFAULT);

#if HAS_TRACKER_SPARQL
            settings.bind ("tracker-mode", tracker_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            tracker_row.visible = true;
            tracker_btn.state_set.connect ((state) => {
                // reload later after setting apply
                Idle.add (() => {
                    app.reload_song_store ();
                    return false;
                });
                return false;
            });
#endif

            var music_dir = app.get_music_folder ();
            music_dir_btn.label = get_display_name (music_dir);
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
                            music_dir_btn.label = get_display_name ((!)dir);
                            settings.set_string ("music-dir", ((!)dir).get_uri ());
                            app.reload_song_store ();
                        }
                    }
                });
                chooser.show ();
            });

            settings.bind ("remote-thumbnail", thumbnail_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            thumbnail_btn.state_set.connect ((state) => {
                app.thumbnailer.remote_thumbnail = state;
                return false;
            });

            settings.bind ("pipewire-sink", pipewire_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            pipewire_btn.state_set.connect ((state) => {
                app.player.use_pipewire (state);
                app.player.restart ();
                return false;
            });

            settings.bind ("show-peak", peak_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            peak_btn.state_set.connect ((state) => {
                app.player.show_peak (state);
                return false;
            });
        }

        private static string get_display_name (File dir) {
            var name = dir.get_basename () ?? "";
            if (name.length == 0 || name == "/")
                name = dir.get_parse_name ();
            return name;
        }
    }
}