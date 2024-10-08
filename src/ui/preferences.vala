namespace G4 {
    namespace BlurMode {
        public const uint NEVER = 0;
        public const uint ALWAYS = 1;
        public const uint ART_ONLY = 2;
    }

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/preferences.ui")]
    public class PreferencesWindow : Adw.PreferencesWindow {
        [GtkChild]
        unowned Adw.ComboRow blur_row;
        [GtkChild]
        unowned Gtk.Switch compact_btn;
        [GtkChild]
        unowned Gtk.Switch grid_btn;
        [GtkChild]
        unowned Gtk.Switch single_btn;
        [GtkChild]
        unowned Gtk.Button music_dir_btn;
        [GtkChild]
        unowned Gtk.Switch monitor_btn;
        [GtkChild]
        unowned Gtk.Switch thumbnail_btn;
        [GtkChild]
        unowned Gtk.Switch playbkgnd_btn;
        [GtkChild]
        unowned Gtk.Switch rotate_btn;
        [GtkChild]
        unowned Gtk.Switch gapless_btn;
        [GtkChild]
        unowned Adw.ComboRow replaygain_row;
        [GtkChild]
        unowned Adw.ComboRow audiosink_row;
        [GtkChild]
        unowned Adw.ExpanderRow peak_row;
        [GtkChild]
        unowned Gtk.Entry peak_entry;

        private GenericArray<Gst.ElementFactory> _audio_sinks = new GenericArray<Gst.ElementFactory> (8);

        public PreferencesWindow (Application app) {
            var settings = app.settings;

            blur_row.model = new Gtk.StringList ({_("Never"), _("Always"), _("Art Only")});
            settings.bind ("blur-mode", blur_row, "selected", SettingsBindFlags.DEFAULT);

            settings.bind ("compact-playlist", compact_btn, "active", SettingsBindFlags.DEFAULT);
            settings.bind ("grid-mode", grid_btn, "active", SettingsBindFlags.DEFAULT);
            settings.bind ("single-click-activate", single_btn, "active", SettingsBindFlags.DEFAULT);

            music_dir_btn.label = get_display_name (app.music_folder);
            music_dir_btn.clicked.connect (() => {
                pick_music_folder (app, this, (dir) => {
                    music_dir_btn.label = get_display_name (app.music_folder);
                });
            });

            settings.bind ("monitor-changes", monitor_btn, "active", SettingsBindFlags.DEFAULT);

            settings.bind ("remote-thumbnail", thumbnail_btn, "active", SettingsBindFlags.DEFAULT);

            settings.bind ("play-background", playbkgnd_btn, "active", SettingsBindFlags.DEFAULT);

            settings.bind ("rotate-cover", rotate_btn, "active", SettingsBindFlags.DEFAULT);

            replaygain_row.model = new Gtk.StringList ({_("Never"), _("Track"), _("Album")});
            settings.bind ("replay-gain", replaygain_row, "selected", SettingsBindFlags.DEFAULT);

            settings.bind ("gapless-playback", gapless_btn, "active", SettingsBindFlags.DEFAULT);

            settings.bind ("show-peak", peak_row, "enable_expansion", SettingsBindFlags.DEFAULT);
            settings.bind ("peak-characters", peak_entry, "text", SettingsBindFlags.DEFAULT);

            GstPlayer.get_audio_sinks (_audio_sinks);
            var sink_names = new string[_audio_sinks.length];
            for (var i = 0; i < _audio_sinks.length; i++)
                sink_names[i] = get_audio_sink_name (_audio_sinks[i]);
            audiosink_row.model = new Gtk.StringList (sink_names);
            this.bind_property ("audio_sink", audiosink_row, "selected", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        }

        public uint audio_sink {
            get {
                var app = (Application) GLib.Application.get_default ();
                var sink_name = app.player.audio_sink;
                for (int i = 0; i < _audio_sinks.length; i++) {
                    if (sink_name == _audio_sinks[i].name)
                        return i;
                }
                return _audio_sinks.length > 0 ? 0 : -1;
            }
            set {
                if (value < _audio_sinks.length) {
                    var app = (Application) GLib.Application.get_default ();
                    app.player.audio_sink = _audio_sinks[value].name;
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

    public delegate void FolderPicked (File dir);

    public void pick_music_folder (Application app, Gtk.Window? parent, FolderPicked picked) {
        var music_dir = File.new_for_uri (app.music_folder);
        show_select_folder_dialog.begin (parent, music_dir, (obj, res) => {
            var dir = show_select_folder_dialog.end (res);
            if (dir != null) {
                var uri = ((!)dir).get_uri ();
                if (app.music_folder != uri)
                    app.music_folder = uri;
                picked ((!)dir);
            }
        });
    }
}
