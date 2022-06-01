namespace Music {

    public class PlayBar : Gtk.Box {
        private Gtk.Scale _seek = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, null);
        private Gtk.Label _peak = new Gtk.Label (null);
        private Gtk.Label _positive = new Gtk.Label ("0:00");
        private Gtk.Label _negative = new Gtk.Label ("-0:00");
        private Gtk.Button _prev = new Gtk.Button ();
        private Gtk.Button _play = new Gtk.Button ();
        private Gtk.Button _next = new Gtk.Button ();
        private int _duration = 1;
        private int _position = 0;
        private int _peak_length = 0;

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            halign = Gtk.Align.CENTER;
            margin_top = 16;
            margin_bottom = 24;

            var app = (!)(GLib.Application.get_default () as Application);
            var player = app.player;

            _seek.set_range (0, _duration);
            _seek.halign = Gtk.Align.FILL;
            _seek.width_request = 256;
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

            _peak.halign = Gtk.Align.CENTER;
            _peak.valign = Gtk.Align.CENTER;
            _peak.add_css_class ("caption");
            _peak.add_css_class ("dim-label");
            _peak.add_css_class ("numeric");

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

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            buttons.halign = Gtk.Align.CENTER;
            buttons.margin_top = 16;
            buttons.append (_prev);
            buttons.append (_play);
            buttons.append (_next);
            append (buttons);

            _prev.valign = Gtk.Align.CENTER;
            _prev.action_name = ACTION_APP + ACTION_PREV;
            _prev.icon_name = "media-skip-backward-symbolic";
            _prev.tooltip_text = _("Play Previous");
            _prev.add_css_class ("circular");

            _play.valign = Gtk.Align.CENTER;
            _play.action_name = ACTION_APP + ACTION_PLAY;
            _play.icon_name = "media-playback-start-symbolic"; // media-playback-pause-symbolic
            _play.tooltip_text = _("Play/Pause");
            _play.margin_start = 24;
            _play.margin_end = 24;
            _play.add_css_class ("circular");
            _play.set_size_request (48, 48);

            _next.valign = Gtk.Align.CENTER;
            _next.action_name = ACTION_APP + ACTION_NEXT;
            _next.icon_name = "media-skip-forward-symbolic";
            _next.tooltip_text = _("Play Next");
            _next.add_css_class ("circular");

            player.duration_changed.connect ((duration) => {
                this.duration = GstPlayer.to_second (duration);
            });
            player.position_updated.connect ((position) => {
                this.position = GstPlayer.to_second (position);
            });
            player.state_changed.connect ((state) => {
                var playing = state == Gst.State.PLAYING;
                _play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
                if (state < Gst.State.PLAYING) {
                    _peak_length = 0;
                    _peak.label = "";
                }
            });
            player.peak_parsed.connect ((peak) => {
                var length = (int) (peak * 18) / 2 * 2 + 1;
                if (_peak_length != length) {
                    _peak_length = length;
                    _peak.label = string.nfill (length, '=');
                }
            });
        }

        public double duration {
            set {
                _duration = (int) (value + 0.5);
                _seek.set_range (0, _duration);
                _negative.label = "-" + format_time (_duration - _position);
            }
        }

        public double position {
            set {
                if (_position != (int) value) {
                    _position = (int) value;
                    _positive.label = format_time (_position);
                    _negative.label = "-" + format_time (_duration - _position);
                }
                _seek.set_value (value);
            }
        }
    }

    public static string format_time (int seconds) {
        int minutes = seconds / 60;
        seconds -= minutes * 60;
        var sb = new StringBuilder ();
        sb.printf ("%d:%02d", minutes, seconds);
        return sb.str;
    }
}