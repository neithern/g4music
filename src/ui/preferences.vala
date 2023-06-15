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
        unowned Adw.ComboRow audiosink_row;
        [GtkChild]
        unowned Adw.ExpanderRow peak_row;
        [GtkChild]
        unowned Gtk.Entry peak_entry;

        public PreferencesWindow (Application app) {
            var settings = app.settings;

            settings?.bind ("dark-theme", dark_btn, "active", SettingsBindFlags.DEFAULT);

            blur_row.expression = new Gtk.CClosureExpression (typeof (string), null, new Gtk.Expression[0], (Callback) get_blur_mode_name, null, null);
            blur_row.model = new Adw.EnumListModel (typeof (BackgroundBlurMode));
            settings?.bind ("background-blur", blur_row, "selected", SettingsBindFlags.DEFAULT);

            settings?.bind ("compact-playlist", compact_btn, "active", SettingsBindFlags.DEFAULT);

            music_dir_btn.label = get_display_name (app.music_folder);
            music_dir_btn.clicked.connect (() => {
                pick_music_folder_async.begin (app, this, (dir) => {
                    music_dir_btn.label = get_display_name (app.music_folder);
                }, (obj, res) => pick_music_folder_async.end (res));
            });

            settings?.bind ("monitor-changes", monitor_btn, "active", SettingsBindFlags.DEFAULT);

            settings?.bind ("remote-thumbnail", thumbnail_btn, "active", SettingsBindFlags.GET_NO_CHANGES);

            settings?.bind ("play-background", playbkgnd_btn, "active", SettingsBindFlags.GET_NO_CHANGES);

            settings?.bind ("replay-gain", replaygain_btn, "active", SettingsBindFlags.GET_NO_CHANGES);

            settings?.bind ("gapless-playback", gapless_btn, "active", SettingsBindFlags.GET_NO_CHANGES);

            settings?.bind ("show-peak", peak_row, "enable_expansion", SettingsBindFlags.GET_NO_CHANGES);
            settings?.bind ("peak-characters", peak_entry, "text", SettingsBindFlags.GET_NO_CHANGES);

            var audio_sinks = GstPlayer.audio_sinks;
            var sink_names = new string[audio_sinks.length];
            for (var i = 0; i < audio_sinks.length; i++)
                sink_names[i] = get_audio_sink_name (audio_sinks[i]);
            audiosink_row.model = new Gtk.StringList (sink_names);
            this.bind_property ("audio_sink", audiosink_row, "selected", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        }

        public uint audio_sink {
            get {
                var app = (Application) GLib.Application.get_default ();
                var sink_name = app.player.audio_sink;
                for (int i = 0; i < GstPlayer.audio_sinks.length; i++) {
                    if (sink_name == GstPlayer.audio_sinks[i].name)
                        return i;
                }
                return -1;
            }
            set {
                if (value < GstPlayer.audio_sinks.length) {
                    var app = (Application) GLib.Application.get_default ();
                    app.player.audio_sink = GstPlayer.audio_sinks[value].name;
                }
            }
        }
    }

    public string get_audio_sink_name (Gst.ElementFactory factory) {
        var name = factory.get_metadata ("long-name") ?? factory.name;
        name = name.replace ("Audio sink", "")
                    .replace ("Audio Sink", "")
                    .replace ("sink", "")
                    .replace ("(", "").replace (")", "");
        return name.strip ();
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
        var music_dir = File.new_for_uri (app.music_folder);
#if GTK_4_10
        var dialog = new Gtk.FileDialog ();
        dialog.initial_file = music_dir;
        dialog.modal = true;
        try {
            var dir = yield dialog.select_folder (parent, null);
            if (dir != null && dir != music_dir) {
                app.music_folder = ((!)dir).get_uri ();
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
                    app.music_folder = ((!)dir).get_uri ();
                    picked ((!)dir);
                }
            }
        });
        chooser.show ();
#endif
    }
}
