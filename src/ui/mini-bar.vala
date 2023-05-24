namespace G4 {

    public class MiniBar : Adw.ActionRow {
        private Gtk.Image _cover = new Gtk.Image ();
        private Gtk.Label _title = new Gtk.Label (null);
        private PeakBar _peak = new PeakBar ();
        private Gtk.Label _time = new Gtk.Label ("0:00");
        private Gtk.Button _play = new Gtk.Button ();
        private Gtk.Button _next = new Gtk.Button ();
        private int _duration = 1;
        private int _position = 0;

        private CrossFadePaintable _paintable = new CrossFadePaintable ();
        private Adw.Animation? _fade_animation = null;

        construct {
            halign = Gtk.Align.FILL;
            hexpand = true;

            var controller = new Gtk.GestureClick ();
            controller.released.connect (this.activate);
            add_controller (controller);
            activatable_widget = this;

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            vbox.halign = Gtk.Align.START;
            vbox.hexpand = true;
            vbox.valign = Gtk.Align.CENTER;
            vbox.append (_title);
            vbox.append (_peak);
            vbox.append (_time);
            add_prefix (vbox);

            _title.halign = Gtk.Align.START;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.add_css_class ("title-leading");

            _peak.halign = Gtk.Align.START;
            _peak.width_request = 168;
            _peak.height_request = 16;
            _peak.add_css_class ("dim-label");

            _time.halign = Gtk.Align.START;
            _time.add_css_class ("dim-label");
            _time.add_css_class ("numeric");

            _cover.valign = Gtk.Align.CENTER;
            _cover.pixel_size = 40;
            _cover.paintable = new RoundPaintable (_paintable, 3);
            _paintable.queue_draw.connect (_cover.queue_draw);
            add_prefix (_cover);

            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            hbox.valign = Gtk.Align.CENTER;
            add_suffix (hbox);

            _play.valign = Gtk.Align.CENTER;
            _play.action_name = ACTION_APP + ACTION_PLAY;
            _play.icon_name = "media-playback-start-symbolic";
            _play.tooltip_text = _("Play/Pause");
            _play.add_css_class ("circular");
            _play.add_css_class ("flat");
            hbox.append (_play);

            _next.valign = Gtk.Align.CENTER;
            _next.action_name = ACTION_APP + ACTION_NEXT;
            _next.icon_name = "media-skip-forward-symbolic";
            _next.tooltip_text = _("Play Next");
            _next.add_css_class ("circular");
            _next.add_css_class ("flat");
            hbox.append (_next);

            var app = (Application) GLib.Application.get_default ();
            var settings = app.settings;
            settings?.bind ("show-peak", _peak, "visible", SettingsBindFlags.DEFAULT);
            settings?.bind ("show-peak", _time, "visible", SettingsBindFlags.GET | SettingsBindFlags.SET | SettingsBindFlags.INVERT_BOOLEAN);
            settings?.bind ("peak-character", _peak, "character", SettingsBindFlags.DEFAULT);

            var player = app.player;
            player.duration_changed.connect (on_duration_changed);
            player.position_updated.connect (on_position_changed);
            player.peak_parsed.connect (_peak.set_peak);
            player.state_changed.connect (on_state_changed);
        }

        public Gdk.Paintable? cover {
            get {
                return _paintable.paintable;
            }
            set {
                _paintable.paintable = value;
                var target = new Adw.CallbackAnimationTarget ((value) => _paintable.fade = value);
                _fade_animation?.pause ();
                _fade_animation = new Adw.TimedAnimation (_cover, 1 - _paintable.fade, 0, 800, target);
                ((!)_fade_animation).done.connect (() => {
                    _paintable.previous = null;
                    _fade_animation = null;
                });
                _fade_animation?.play ();
            }
        }

        public new string title {
            set {
                _title.label = value;
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            base.snapshot (snapshot);
            var color = Gdk.RGBA ();
            color.red = color.green = color.blue = color.alpha = 0.5f;
            var rect = (!)Graphene.Rect ().init (0, 0, get_width (), 0.5f);
            snapshot.append_color (color, rect);
        }

        private void on_duration_changed (Gst.ClockTime duration) {
            var value = GstPlayer.to_second (duration);
            if (_duration != (int) value) {
                _duration = (int) value;
                update_time_label ();
            }
        }

        private void on_position_changed (Gst.ClockTime position) {
            var value = GstPlayer.to_second (position);
            if (_position != (int) value) {
                _position = (int) value;
                update_time_label ();
            }
        }

        private void on_state_changed (Gst.State state) {
            var playing = state == Gst.State.PLAYING;
            _play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
        }

        private void update_time_label () {
            _time.label = format_time (_position) + "/" + format_time (_duration);
        }
    }
}
