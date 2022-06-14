namespace Music {

    public class MiniBar : Adw.ActionRow {
        private Gtk.Image _cover = new Gtk.Image ();
        private Gtk.Label _title = new Gtk.Label (null);
        private Gtk.Label _peak = new Gtk.Label (null);
        private Gtk.Button _play = new Gtk.Button ();
        private Gtk.Button _next = new Gtk.Button ();

        private CrossFadePaintable _paintable = new CrossFadePaintable ();
        private Adw.Animation? _fade_animation = null;
        private int _peak_length = 0;

        construct {
            halign = Gtk.Align.FILL;
            hexpand = true;

            var controller = new Gtk.GestureClick ();
            controller.released.connect (this.activate);
            add_controller (controller);
            activatable_widget = this;

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            vbox.halign = Gtk.Align.START;
            vbox.hexpand = true;
            vbox.valign = Gtk.Align.CENTER;
            vbox.append (_title);
            vbox.append (_peak);
            add_prefix (vbox);

            _title.halign = Gtk.Align.START;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.add_css_class ("caption-heading");

            _peak.halign = Gtk.Align.START;
            _peak.add_css_class ("caption");
            _peak.add_css_class ("dim-label");
            _peak.add_css_class ("numeric");

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
            app.settings?.bind ("show-peak", _peak, "visible", SettingsBindFlags.DEFAULT);

            var player = app.player;
            player.state_changed.connect ((state) => {
                var playing = state == Gst.State.PLAYING;
                _play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
                if (state < Gst.State.PLAYING) {
                    _peak_length = 0;
                    _peak.label = "";
                }
            });
            player.peak_parsed.connect ((peak) => {
                var length = peak > 0 ? (int) (peak * 18) / 2 * 2 + 1 : 0;
                if (_peak_length != length) {
                    _peak_length = length;
                    _peak.label = length > 0 ? string.nfill (length, '=') : "";
                }
            });
        }

        public Gdk.Paintable? cover {
            set {
                _paintable.paintable = value;

                var target = new Adw.CallbackAnimationTarget ((value) => {
                    _paintable.fade = value;
                });
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
    }
}