namespace G4 {

    public class PlayBar : Gtk.Box {
        private Gtk.Scale _seek = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, null);
        private PeakBar _peak = new PeakBar ();
        private Gtk.Label _positive = new Gtk.Label ("0:00");
        private Gtk.Label _negative = new Gtk.Label ("0:00");
        private Gtk.ToggleButton _repeat = new Gtk.ToggleButton ();
        private Gtk.Button _prev = new Gtk.Button ();
        private Gtk.Button _play = new Gtk.Button ();
        private Gtk.Button _next = new Gtk.Button ();
        private Gtk.VolumeButton _volume = new Gtk.VolumeButton ();
        private bool _negative_progress = false;
        private int _duration = 1;
        private int _position = 0;

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            halign = Gtk.Align.CENTER;
            margin_top = 8;
            margin_bottom = 32;

            var app = (Application) GLib.Application.get_default ();
            var player = app.player;

            _seek.set_range (0, _duration);
            _seek.halign = Gtk.Align.FILL;
            _seek.width_request = 272;
            _seek.adjust_bounds.connect ((value) => {
                player.seek (GstPlayer.from_second (value));
            });
            append (_seek);

            var times = new Gtk.CenterBox ();
            times.baseline_position = Gtk.BaselinePosition.CENTER;
            times.halign = Gtk.Align.FILL;
            times.set_start_widget (_positive);
            times.set_end_widget (_negative);

            var overlay = new Gtk.Overlay ();
            overlay.child = times;
            overlay.add_overlay (_peak);
            append (overlay);

            _peak.align = Pango.Alignment.CENTER;
            _peak.halign = Gtk.Align.CENTER;
            _peak.width_request = 168;
            _peak.add_css_class ("dim-label");

            _positive.halign = Gtk.Align.START;
            _positive.margin_start = 12;
            _positive.add_css_class ("caption");
            _positive.add_css_class ("dim-label");
            _positive.add_css_class ("numeric");

            _negative.halign = Gtk.Align.END;
            _negative.margin_end = 12;
            _negative.add_css_class ("caption");
            _negative.add_css_class ("dim-label");
            _negative.add_css_class ("numeric");

            var settings = app.settings;
            _negative_progress = settings?.get_boolean ("remain-progress") ?? false;

            make_label_clickable (_negative).pressed.connect (() => {
                _negative_progress = !_negative_progress;
                update_negative_label ();
                settings?.set_boolean ("remain-progress", _negative_progress);
            });

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
            buttons.halign = Gtk.Align.CENTER;
            buttons.margin_top = 16;
            buttons.append (_repeat);
            buttons.append (_prev);
            buttons.append (_play);
            buttons.append (_next);
            buttons.append (_volume);
            append (buttons);

            _repeat.icon_name = "media-playlist-repeat-symbolic";
            _repeat.valign = Gtk.Align.CENTER;
            _repeat.tooltip_text = _("Repeat Music");
            _repeat.add_css_class ("flat");
            _repeat.toggled.connect (() => {
                _repeat.icon_name = _repeat.active ? "media-playlist-repeat-music-symbolic" : "media-playlist-repeat-symbolic";
                app.single_loop = ! app.single_loop;
            });

            _prev.valign = Gtk.Align.CENTER;
            _prev.action_name = ACTION_APP + ACTION_PREV;
            _prev.icon_name = "media-skip-backward-symbolic";
            _prev.tooltip_text = _("Play Previous");
            _prev.add_css_class ("circular");

            _play.valign = Gtk.Align.CENTER;
            _play.action_name = ACTION_APP + ACTION_PLAY;
            _play.icon_name = "media-playback-start-symbolic"; // media-playback-pause-symbolic
            _play.tooltip_text = _("Play/Pause");
            _play.add_css_class ("circular");
            _play.set_size_request (48, 48);

            _next.valign = Gtk.Align.CENTER;
            _next.action_name = ACTION_APP + ACTION_NEXT;
            _next.icon_name = "media-skip-forward-symbolic";
            _next.tooltip_text = _("Play Next");
            _next.add_css_class ("circular");

            _volume.valign = Gtk.Align.CENTER;
            player.bind_property ("volume", _volume, "value", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

            player.duration_changed.connect (on_duration_changed);
            player.position_updated.connect (on_position_changed);
            player.state_changed.connect (on_state_changed);
            player.peak_parsed.connect (_peak.set_peak);
        }

        private void on_duration_changed (Gst.ClockTime duration) {
            var value = GstPlayer.to_second (duration);
            _duration = (int) (value + 0.5);
            _seek.set_range (0, _duration);
            update_negative_label ();
        }

        private void on_position_changed (Gst.ClockTime position) {
            var value = GstPlayer.to_second (position);
            if (_position != (int) value) {
                _position = (int) value;
                _positive.label = format_time (_position);
                if (_negative_progress)
                    _negative.label = "-" + format_time (_duration - _position);
            }
            _seek.set_value (value);
        }

        private void on_state_changed (Gst.State state) {
            var playing = state == Gst.State.PLAYING;
            _play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
        }

        private void update_negative_label () {
            if (_negative_progress)
                _negative.label = "-" + format_time (_duration - _position);
            else
                _negative.label = format_time (_duration);
        }
    }

    public static string format_time (int seconds) {
        var sb = new StringBuilder ();
        var hours = seconds / 3600;
        var minutes = seconds / 60;
        seconds -= minutes * 60;
        if (hours > 0) {
            minutes -= hours * 60;
            sb.printf ("%d:%02d:%02d", hours, minutes, seconds);
        } else {
            sb.printf ("%d:%02d", minutes, seconds);
        }
        return sb.str;
    }

    public static Gtk.GestureClick make_label_clickable (Gtk.Label label) {
        var controller = new Gtk.GestureClick ();
        label.add_controller (controller);
        label.set_cursor_from_name ("hand");
        return controller;
    }
}
