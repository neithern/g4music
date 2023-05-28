namespace G4 {
    public enum BackgroundBlurMode {
        ALWAYS,
        ART_ONLY,
        NEVER
    }

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/preferences.ui")]
    public class PreferencesWindow : Adw.PreferencesWindow {
        [GtkChild]
        unowned Gtk.Switch dark_btn;
        [GtkChild]
        unowned Adw.ComboRow blur_row;
        [GtkChild]
        unowned Gtk.Switch compact_btn;
        [GtkChild]
        unowned Gtk.Button music_dir_btn;
        [GtkChild]
        unowned Gtk.Switch monitor_btn;
        [GtkChild]
        unowned Gtk.Switch thumbnail_btn;
        [GtkChild]
        unowned Gtk.Switch playbkgnd_btn;
        [GtkChild]
        unowned Gtk.Switch gapless_btn;
        [GtkChild]
        unowned Gtk.Switch replaygain_btn;
        [GtkChild]
        unowned Gtk.Switch pipewire_btn;
        [GtkChild]
        unowned Adw.ExpanderRow peak_row;
        [GtkChild]
        unowned Gtk.Entry peak_entry;

        public PreferencesWindow (Application app) {
            var settings = app.settings;

            dark_btn.bind_property ("active", app, "dark-theme", BindingFlags.DEFAULT);
            settings?.bind ("dark-theme", dark_btn, "active", SettingsBindFlags.DEFAULT);

            blur_row.expression = new Gtk.CClosureExpression (typeof (string), null, new Gtk.Expression[0], (Callback) get_blur_mode_name, null, null);
            blur_row.model = new Adw.EnumListModel (typeof (BackgroundBlurMode));
            settings?.bind ("background-blur", blur_row, "selected", SettingsBindFlags.DEFAULT);
            blur_row.bind_property ("selected", app.active_window, "background-blur", BindingFlags.DEFAULT);

            settings?.bind ("compact-playlist", compact_btn, "active", SettingsBindFlags.DEFAULT);

            var music_dir = app.get_music_folder ();
            music_dir_btn.label = get_display_name (music_dir);
            music_dir_btn.clicked.connect (() => {
                pick_music_folder_async.begin (app, this, (dir) => {
                    music_dir_btn.label = get_display_name (dir);
                    app.reload_music_store ();
                }, (obj, res) => pick_music_folder_async.end (res));
            });

            settings?.bind ("monitor-changes", monitor_btn, "active", SettingsBindFlags.DEFAULT);
            monitor_btn.bind_property ("active", app.music_store, "monitor-changes", BindingFlags.DEFAULT);

            settings?.bind ("remote-thumbnail", thumbnail_btn, "active", SettingsBindFlags.GET_NO_CHANGES);
            thumbnail_btn.bind_property ("active", app.thumbnailer, "remote_thumbnail", BindingFlags.DEFAULT);

            settings?.bind ("play-background", playbkgnd_btn, "active", SettingsBindFlags.GET_NO_CHANGES);

            settings?.bind ("replay-gain", replaygain_btn, "active", SettingsBindFlags.GET_NO_CHANGES);
            replaygain_btn.bind_property ("active", app.player, "replay_gain", BindingFlags.DEFAULT);

            settings?.bind ("gapless-playback", gapless_btn, "active", SettingsBindFlags.GET_NO_CHANGES);
            gapless_btn.bind_property ("active", app.player, "gapless", BindingFlags.DEFAULT);

            settings?.bind ("pipewire-sink", pipewire_btn, "active", SettingsBindFlags.GET_NO_CHANGES);
            pipewire_btn.bind_property ("active", app.player, "pipewire_sink", BindingFlags.DEFAULT);

            settings?.bind ("show-peak", peak_row, "enable_expansion", SettingsBindFlags.GET_NO_CHANGES);
            peak_row.bind_property ("enable_expansion", app.player, "show_peak", BindingFlags.DEFAULT);
            settings?.bind ("peak-characters", peak_entry, "text", SettingsBindFlags.GET_NO_CHANGES);
        }
    }

    public string get_blur_mode_name (Adw.EnumListItem item, void* user_data) {
        switch (item.get_value ()) {
        case BackgroundBlurMode.ALWAYS:
            return _("Always");
        case BackgroundBlurMode.ART_ONLY:
            return _("Art Only");
        case BackgroundBlurMode.NEVER:
            return _("Never");
        default:
            return "";
        }
    }

    public delegate void FolderPicked (File dir);

    public async void pick_music_folder_async (Application app, Gtk.Window? parent, FolderPicked picked) {
        var music_dir = app.get_music_folder ();
#if GTK_4_10
        var dialog = new Gtk.FileDialog ();
        dialog.initial_folder = music_dir;
        dialog.modal = true;
        try {
            var dir = yield dialog.select_folder (parent, null);
            if (dir != null && dir != music_dir) {
                app.settings?.set_string ("music-dir", ((!)dir).get_uri ());
                picked ((!)dir);
            }
        } catch (Error e) {
        }
#else
        var chooser = new Gtk.FileChooserNative (null, parent,
                        Gtk.FileChooserAction.SELECT_FOLDER, null, null);
        try {
            chooser.set_file (music_dir);
        } catch (Error e) {
        }
        chooser.modal = true;
        chooser.response.connect ((id) => {
            if (id == Gtk.ResponseType.ACCEPT) {
                var dir = chooser.get_file ();
                if (dir is File && dir != music_dir) {
                    app.settings?.set_string ("music-dir", ((!)dir).get_uri ());
                    picked ((!)dir);
                }
            }
        });
        chooser.show ();
#endif
    }
}
