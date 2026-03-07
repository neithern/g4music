namespace G4 {

    public class PlayBar : Gtk.Box {
        private Gtk.Scale _seek = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, null);
        private PeakBar _peak = new PeakBar ();
        private Gtk.Label _positive = new Gtk.Label ("0:00");
        private Gtk.Label _negative = new Gtk.Label ("0:00");
        private Gtk.Button _repeat = new Gtk.Button ();
        private Gtk.Button _prev = new Gtk.Button ();
        private Gtk.Button _play = new Gtk.Button ();
        private Gtk.Button _next = new Gtk.Button ();
        private VolumeButton _volume = new VolumeButton ();
        private int _duration = 0;
        private int _position = 0;
        private bool _remain_progress = false;
        private bool _seeking = false;

        public signal void position_seeked (double position);

        construct {
            orientation = Gtk.Orientation.VERTICAL;

            var app = (Application) GLib.Application.get_default ();
            var player = app.player;

            _seek.set_range (0, _duration);
            _seek.halign = Gtk.Align.FILL;
            append (_seek);
            setup_seek_bar (player);

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
            _positive.add_css_class ("dim-label");
            _positive.add_css_class ("numeric");

            _negative.halign = Gtk.Align.END;
            _negative.margin_end = 12;
            _negative.add_css_class ("dim-label");
            _negative.add_css_class ("numeric");

            make_widget_clickable (_negative).pressed.connect (() => remain_progress = !remain_progress);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
            buttons.halign = Gtk.Align.CENTER;
            buttons.margin_top = 16;

            var sleep_btn = new Gtk.MenuButton ();
            sleep_btn.icon_name = "alarm-symbolic";
            sleep_btn.tooltip_text = _("Sleep Timer");
            sleep_btn.add_css_class ("flat");
            sleep_btn.valign = Gtk.Align.CENTER;
            sleep_btn.opacity = 0.5;
            setup_sleep_popover (sleep_btn, app);

            buttons.append (_repeat);
            buttons.append (_prev);
            buttons.append (_play);
            buttons.append (_next);
            buttons.append (sleep_btn);
            append (buttons);

            _repeat.icon_name = "media-playlist-repeat-symbolic";
            _repeat.valign = Gtk.Align.CENTER;
            _repeat.tooltip_text = _("No Repeat");
            _repeat.add_css_class ("flat");
            _repeat.opacity = 0.5;
            _repeat.clicked.connect (() => {
                var mode = (app.repeat_mode + 1) % 3;
                app.repeat_mode = mode;
                switch (mode) {
                    case RepeatMode.NONE:
                        _repeat.icon_name = "media-playlist-repeat-symbolic";
                        _repeat.tooltip_text = _("No Repeat");
                        _repeat.opacity = 0.5;
                        break;
                    case RepeatMode.ALL:
                        _repeat.icon_name = "media-playlist-repeat-symbolic";
                        _repeat.tooltip_text = _("Repeat All");
                        _repeat.opacity = 1.0;
                        break;
                    case RepeatMode.ONE:
                        _repeat.icon_name = "media-playlist-repeat-song-symbolic";
                        _repeat.tooltip_text = _("Repeat One");
                        _repeat.opacity = 1.0;
                        break;
                }
            });

            _prev.valign = Gtk.Align.CENTER;
            _prev.action_name = ACTION_APP + ACTION_PREV;
            _prev.icon_name = "media-skip-backward-symbolic";
            _prev.tooltip_text = _("Play Previous");
            _prev.add_css_class ("circular");

            _play.valign = Gtk.Align.CENTER;
            _play.action_name = ACTION_APP + ACTION_PLAY_PAUSE;
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

            var settings = app.settings;
            settings.bind ("show-peak", _peak, "visible", SettingsBindFlags.DEFAULT);
            settings.bind ("peak-characters", _peak, "characters", SettingsBindFlags.DEFAULT);
            settings.bind ("remain-progress", this, "remain-progress", SettingsBindFlags.DEFAULT);
        }

        public VolumeButton volume_button {
            get {
                return _volume;
            }
        }


        public double peak {
            set {
                _peak.peak = value;
            }
        }

        public double position {
            get {
                return _seek.get_value ();
            }
        }

        public bool remain_progress {
            get {
                return _remain_progress;
            }
            set {
                _remain_progress = value;
                update_negative_label ();
            }
        }

        public void on_size_changed (int bar_width, int bar_spacing) {
            var text_width = int.max (_positive.get_width (), _negative.get_width ());
            _peak.width_request = bar_width - (text_width + _positive.margin_start + _negative.margin_end) * 2;
            get_last_child ()?.set_margin_top (bar_spacing);
        }

        private void on_duration_changed (Gst.ClockTime duration) {
            var value = GstPlayer.to_second (duration);
            _duration = (int) (value + 0.5);
            _seek.set_range (0, _duration);
            update_negative_label ();
        }

        private void on_position_changed (Gst.ClockTime position) {
            if (!_seeking) {
                update_position (position);
            }
        }

        private void on_state_changed (Gst.State state) {
            var playing = state == Gst.State.PLAYING;
            _play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
        }

        private void setup_seek_bar (GstPlayer player) {
            _seek.change_value.connect ((type, value) => {
                if (_seeking) {
                    position_seeked (value);
                    update_position (GstPlayer.from_second (value));
                    return true;
                }
                return false;
            });

            // Hack that grabs the click gesture controller as mouse released event doesn't work otherwise
            // Bug: https://gitlab.gnome.org/GNOME/gtk/-/issues/4939
            Gtk.GestureClick? click_gesture = null;
            var controllers = _seek.observe_controllers ();
            for (var i = 0; i < controllers.get_n_items (); i++) {
                var controller = controllers.get_item (i);
                if (controller is Gtk.GestureClick) {
                    click_gesture = (Gtk.GestureClick) controller;
                    break;
                }
            }
            if (click_gesture == null) {
                click_gesture = new Gtk.GestureClick ();
                _seek.add_controller ((!)click_gesture);
            }
            var gesture = (!)click_gesture;
            gesture.set_button (0);
            gesture.pressed.connect(() => _seeking = true);
            gesture.released.connect(() => {
                _seeking = false;
                player.seek(GstPlayer.from_second (_seek.get_value ()));
            });
        }

        private void update_negative_label () {
            if (_remain_progress)
                _negative.label = "-" + format_time (_duration - _position);
            else
                _negative.label = format_time (_duration);
        }

        private void update_position (Gst.ClockTime position) {
            var value = GstPlayer.to_second (position);
            if (_position != (int) value) {
                _position = (int) value;
                _positive.label = format_time (_position);
                if (_remain_progress)
                    _negative.label = "-" + format_time (_duration - _position);
            }
            _seek.set_value (value);
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

    public static Gtk.GestureClick make_widget_clickable (Gtk.Widget label) {
        var controller = new Gtk.GestureClick ();
        controller.button = Gdk.BUTTON_PRIMARY;
        label.add_controller (controller);
        label.set_cursor_from_name ("pointer");
        return controller;
    }
    private void setup_sleep_popover (Gtk.MenuButton btn, Application app) {
            var timer = app.sleep_timer;

            // --- Setup popover ---
            var popover = new Gtk.Popover ();
            popover.has_arrow = true;
            btn.popover = popover;

            // --- Setup popover ---
            var setup_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            setup_box.margin_top = 12;
            setup_box.margin_bottom = 12;
            setup_box.margin_start = 16;
            setup_box.margin_end = 16;

            // Counter row
            var counter_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            counter_box.halign = Gtk.Align.CENTER;

            var minus_btn = new Gtk.Button.from_icon_name ("list-remove-symbolic");
            minus_btn.add_css_class ("circular");
            minus_btn.add_css_class ("flat");

            var value_label = new Gtk.Label ("15");
            value_label.add_css_class ("title-2");
            value_label.width_chars = 3;
            value_label.halign = Gtk.Align.CENTER;

            var plus_btn = new Gtk.Button.from_icon_name ("list-add-symbolic");
            plus_btn.add_css_class ("circular");
            plus_btn.add_css_class ("flat");

            counter_box.append (minus_btn);
            counter_box.append (value_label);
            counter_box.append (plus_btn);
            setup_box.append (counter_box);

            var unit_label = new Gtk.Label (_("minutes"));
            unit_label.add_css_class ("dim-label");
            unit_label.halign = Gtk.Align.CENTER;
            setup_box.append (unit_label);

            // Finish track checkbox
            var finish_check = new Gtk.CheckButton.with_label (_("Finish current track"));
            finish_check.halign = Gtk.Align.CENTER;
            setup_box.append (finish_check);

            // Start button
            var start_btn = new Gtk.Button.with_label (_("Start"));
            start_btn.add_css_class ("suggested-action");
            start_btn.add_css_class ("pill");
            start_btn.halign = Gtk.Align.CENTER;
            setup_box.append (start_btn);

            // --- Active popover ---
            var active_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            active_box.margin_top = 12;
            active_box.margin_bottom = 12;
            active_box.margin_start = 16;
            active_box.margin_end = 16;

            var countdown_label = new Gtk.Label ("15:00");
            countdown_label.add_css_class ("title-1");
            countdown_label.halign = Gtk.Align.CENTER;
            active_box.append (countdown_label);

            var active_btns = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            active_btns.halign = Gtk.Align.CENTER;

            var stop_btn = new Gtk.Button.from_icon_name ("media-playback-stop-symbolic");
            stop_btn.add_css_class ("circular");
            stop_btn.add_css_class ("destructive-action");
            stop_btn.tooltip_text = _("Stop Timer");

            var add_btn = new Gtk.Button.with_label ("+1 min");
            add_btn.add_css_class ("pill");

            active_btns.append (stop_btn);
            active_btns.append (add_btn);
            active_box.append (active_btns);

            // Stack to switch between setup and active views
            var stack = new Gtk.Stack ();
            stack.add_named (setup_box, "setup");
            stack.add_named (active_box, "active");
            popover.child = stack;

            // Wire up counter
            var minutes = 15;
            minus_btn.clicked.connect (() => {
                minutes = int.max (1, minutes - 1);
                value_label.label = minutes.to_string ();
            });
            plus_btn.clicked.connect (() => {
                minutes = int.min (180, minutes + 1);
                value_label.label = minutes.to_string ();
            });

            // Start
            start_btn.clicked.connect (() => {
                timer.finish_track = finish_check.active;
                timer.start (minutes * 60);
                stack.visible_child_name = "active";
            });

            // Stop
            stop_btn.clicked.connect (() => {
                timer.stop ();
                stack.visible_child_name = "setup";
            });

            // +1 min
            add_btn.clicked.connect (() => {
                timer.add_seconds (60);
            });

            // Tick updates
            timer.tick.connect ((secs) => {
                var m = secs / 60;
                var s = secs % 60;
                countdown_label.label = "%d:%02d".printf (m, s);
            });

            // State changes
            timer.state_changed.connect ((active) => {
                btn.opacity = active ? 1.0 : 0.5;
                stack.visible_child_name = active ? "active" : "setup";
                if (!active)
                    popover.popdown ();
            });

            // Reset to setup view when opening if not active
            popover.show.connect (() => {
                stack.visible_child_name = timer.active ? "active" : "setup";
                if (timer.active) {
                    var m = timer.seconds_remaining / 60;
                    var s = timer.seconds_remaining % 60;
                    countdown_label.label = "%d:%02d".printf (m, s);
                }
            });
        }
}
