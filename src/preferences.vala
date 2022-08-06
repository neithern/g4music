namespace Music {
    public enum BackgroundRenderingType {
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
        unowned Gtk.Button music_dir_btn;
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
        unowned Gtk.Switch peak_btn;

        public PreferencesWindow (Application app) {
            var settings = app.settings;

            dark_btn.bind_property ("state", app, "dark_theme", BindingFlags.DEFAULT);
            settings?.bind ("dark-theme", dark_btn, "state", SettingsBindFlags.DEFAULT);

            blur_row.expression = new Gtk.CClosureExpression (typeof (string), null, new Gtk.Expression[0], (Callback) get_rendering_name, null, null);
            blur_row.model = new Adw.EnumListModel (typeof (BackgroundRenderingType));
            settings?.bind ("background-blur", blur_row, "selected", SettingsBindFlags.DEFAULT);
            blur_row.bind_property ("selected", app.active_window, "background-blur", BindingFlags.DEFAULT);

            var music_dir = app.get_music_folder ();
            music_dir_btn.label = get_display_name (music_dir);
            music_dir_btn.clicked.connect (() => {
                pick_music_folder (app, this, (dir) => {
                    music_dir_btn.label = get_display_name (dir);
                    app.reload_song_store ();
                });
            });

            settings?.bind ("remote-thumbnail", thumbnail_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            thumbnail_btn.bind_property ("state", app.thumbnailer, "remote_thumbnail", BindingFlags.DEFAULT);

            settings?.bind ("play-background", playbkgnd_btn, "state", SettingsBindFlags.GET_NO_CHANGES);

            settings?.bind ("replay-gain", replaygain_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            replaygain_btn.bind_property ("state", app.player, "replay_gain", BindingFlags.DEFAULT);

            settings?.bind ("gapless-playback", gapless_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            gapless_btn.bind_property ("state", app.player, "gapless", BindingFlags.DEFAULT);

            settings?.bind ("pipewire-sink", pipewire_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            pipewire_btn.bind_property ("state", app.player, "pipewire_sink", BindingFlags.DEFAULT);

            settings?.bind ("show-peak", peak_btn, "state", SettingsBindFlags.GET_NO_CHANGES);
            peak_btn.bind_property ("state", app.player, "show_peak", BindingFlags.DEFAULT);
        }
    }

    public string get_rendering_name (Adw.EnumListItem item, void* user_data) {
        switch (item.get_value ()) {
        case BackgroundRenderingType.ALWAYS:
            return _("Always");
        case BackgroundRenderingType.ART_ONLY:
            return _("Art Only");
        case BackgroundRenderingType.NEVER:
            return _("Never");
        default:
            return "";
        }
    }

    public delegate void FolderPicked (File dir);

    public void pick_music_folder (Application app, Gtk.Window? parent, FolderPicked picked) {
        var music_dir = app.get_music_folder ();
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
    }
}