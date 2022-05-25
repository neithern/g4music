namespace Music {

    //  [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/play-bar.ui")]
    public class PlayBar : Gtk.Box {
        //  [GtkChild]
        //  private unowned Gtk.Scale _seek;
        //  [GtkChild]
        //  private unowned Gtk.Label _positive;
        //  [GtkChild]
        //  private unowned Gtk.Label _negative;
        //  [GtkChild]
        //  private unowned Gtk.Button _play;

        private Gtk.Scale _seek = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, null);
        private Gtk.Label _positive = new Gtk.Label ("0:00");
        private Gtk.Label _negative = new Gtk.Label ("-0:00");
        private Gtk.Button _prev = new Gtk.Button ();
        private Gtk.Button _play = new Gtk.Button ();
        private Gtk.Button _next = new Gtk.Button ();
        private double _position = 0;
        private double _range = 1;

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            halign = Gtk.Align.CENTER;
            margin_top = 16;

            var app = GLib.Application.get_default () as Application;

            _seek.set_range (0, _range);
            _seek.halign = Gtk.Align.FILL;
            _seek.hexpand = true;
            _seek.width_request = 256;
            _seek.adjust_bounds.connect ((value) => {
                app.player.seek (GstPlayer.from_second (value));
            });
            append(_seek);

            var times = new Gtk.CenterBox ();
            times.halign = Gtk.Align.FILL;
            times.hexpand = true;
            times.set_start_widget (_positive);
            times.set_end_widget (_negative);
            append(times);

            _positive.halign = Gtk.Align.START;
            _positive.margin_start = 12;
            _positive.label = "0:00";
            _positive.add_css_class ("caption");
            _positive.add_css_class ("dim-label");
            _positive.add_css_class ("numeric");

            _negative.halign = Gtk.Align.END;
            _negative.margin_end = 12;
            _negative.label = "-0:00";
            _negative.add_css_class ("caption");
            _negative.add_css_class ("dim-label");
            _negative.add_css_class ("numeric");

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            buttons.halign = Gtk.Align.CENTER;
            buttons.hexpand = true;
            buttons.margin_top = 8;
            buttons.append (_prev);
            buttons.append (_play);
            buttons.append (_next);
            append(buttons);

            _prev.valign = Gtk.Align.CENTER;
            _prev.margin_start = 24;
            _prev.margin_end = 24;
            _prev.action_name = Application.ACTION_PREFIX + Application.ACTION_PREV;
            _prev.icon_name = "media-skip-backward-symbolic";
            _prev.add_css_class ("circular");

            _play.valign = Gtk.Align.CENTER;
            _play.action_name = Application.ACTION_PREFIX + Application.ACTION_PLAY;
            _play.icon_name = "media-playback-start-symbolic"; // media-playback-pause-symbolic
            _play.add_css_class ("circular");
            _play.set_size_request (48, 48);

            _next.valign = Gtk.Align.CENTER;
            _next.margin_start = 24;
            _next.margin_end = 24;
            _next.action_name = Application.ACTION_PREFIX + Application.ACTION_NEXT;
            _next.icon_name = "media-skip-forward-symbolic";
            _next.add_css_class ("circular");

            var player = app.player;
            player.duration_changed.connect ((duration) => {
                this.duration = GstPlayer.to_second (duration);
            });
            player.position_updated.connect ((position) => {
                this.position = GstPlayer.to_second (position);
            });
            player.state_changed.connect ((state) => {
                var playing = state == Gst.State.PLAYING;
                _play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            });
        }

        public double duration {
            set {
                _range = value;
                _seek.set_range (0, value);
                _negative.label = "-" + format_time(value - _position);
            }
        }

        public double position {
            set {
                if ((int) _position != (int) value) {
                    _position = value;
                    _positive.label = format_time(value, true);
                    _negative.label = "-" + format_time(_range - value);
                }
                _seek.set_value (value);
            }
        }

        public static string format_time (double value, bool round = false) {
            int seconds = (int) (value + (round ? 0.5 : 0));
            int minutes = seconds / 60;
            seconds -= minutes * 60;
            var s = (seconds < 10 ? "0" : "") + seconds.to_string ();
            return minutes.to_string () + ":" + s;
        }
    }
}