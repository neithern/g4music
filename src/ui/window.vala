namespace G4 {

    public class Window : Adw.ApplicationWindow {
        private Leaflet _leaflet = new Leaflet ();
        private Gtk.ProgressBar _progress_bar = new Gtk.ProgressBar ();
        private PlayPanel _play_panel;
        private StorePanel _store_panel;

        private int _blur_size = 512;
        private uint _bkgnd_blur = BlurMode.ALWAYS;
        private CrossFadePaintable _bkgnd_paintable = new CrossFadePaintable ();
        private Gdk.Paintable? _cover_paintable = null;

        public Window (Application app) {
            this.application = app;
            this.icon_name = app.application_id;
            this.title = app.name;
            this.close_request.connect (on_close_request);

            var overlay = new Gtk.Overlay ();
            this.content = overlay;

            _progress_bar.hexpand = true;
            _progress_bar.margin_top = 46;  // at the bottom of the header_bar
            _progress_bar.pulse_step = 0.02;
            _progress_bar.sensitive = false;
            _progress_bar.visible = false;
            _progress_bar.add_css_class ("osd");
            overlay.child = _leaflet;
            overlay.add_overlay (_progress_bar);
            app.loader.loading_changed.connect (on_loading_changed);

            _bkgnd_paintable.queue_draw.connect (this.queue_draw);

            _store_panel = new StorePanel (app, this, _leaflet);

            _play_panel = new PlayPanel (app, this, _leaflet);
            _play_panel.cover_changed.connect (on_cover_changed);

            _leaflet.content = _play_panel;
            _leaflet.sidebar = _store_panel;

            setup_drop_target ();
            setup_focus_controller ();

            var settings = app.settings;
            settings.bind ("leaflet-mode", _leaflet, "visible-mode", SettingsBindFlags.DEFAULT);
            settings.bind ("maximized", this, "maximized", SettingsBindFlags.DEFAULT);
            settings.bind ("width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings.bind ("height", this, "default-height", SettingsBindFlags.DEFAULT);
            settings.bind ("blur-mode", this, "blur-mode", SettingsBindFlags.DEFAULT);
        }

        public uint blur_mode {
            get {
                return _bkgnd_blur;
            }
            set {
                _bkgnd_blur = value;
                if (get_height () > 0)
                    update_background ();
            }
        }

        public bool focused_visible {
            get {
                return focus_visible;
            }
            set {
                if (!value)
                    focus_to_play_later ();
            }
        }

        public Gtk.Widget focused_widget {
            owned get {
                return focus_widget;
            }
            set {
                if (!(value is Gtk.Editable))
                    focus_to_play_later (2000);
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            _bkgnd_paintable.snapshot (snapshot, get_width (), get_height ());
            base.snapshot (snapshot);
        }

        public void open_page (string[] paths, Object? obj = null) {
            _store_panel.locate_to_path (paths, obj);
        }

        public void start_search (string text, uint mode = SearchMode.ANY) {
            _store_panel.start_search (text, mode);
            if (_leaflet.folded) {
                _leaflet.pop ();
            }
        }

        public void toggle_search () {
            if (_store_panel.toggle_search () && _leaflet.folded) {
                _leaflet.pop ();
            }
        }

        private void focus_to_play_later (int delay = 100) {
            run_timeout_once (delay, () => {
                if (!focus_visible && !(focus_widget is Gtk.Editable)) {
                    var button = find_button_by_action_name (_leaflet, ACTION_APP + ACTION_PLAY_PAUSE);
                    button?.grab_focus ();
                }
            });
        }

        private bool on_close_request () {
            var app = (Application) application;
            if (app.player.playing && app.settings.get_boolean ("play-background")) {
                app.request_background ();
                this.visible = false;
                return true;
            }
            return false;
        }

        private Adw.Animation? _fade_animation = null;

        private void on_cover_changed (Music? music, CrossFadePaintable cover) {
            var paintable = cover.paintable;
            while (paintable is BasePaintable) {
                paintable = (paintable as BasePaintable)?.paintable;
            }
            _cover_paintable = paintable;

            var app = (Application) application;
            var mini_cover = music != null ? (app.thumbnailer.find ((!)music) ?? _cover_paintable) : app.icon;
            _store_panel.set_mini_cover (mini_cover);
            update_background ();

            var target = new Adw.CallbackAnimationTarget ((value) => {
                _bkgnd_paintable.fade = value;
                cover.fade = value;
            });
            _fade_animation?.pause ();
            _fade_animation = new Adw.TimedAnimation (this, 1 - cover.fade, 0, 800, target);
            ((!)_fade_animation).done.connect (() => {
                _bkgnd_paintable.previous = null;
                cover.previous = null;
                _fade_animation = null;
            });
            _fade_animation?.play ();
        }

        private bool on_file_dropped (Value value, double x, double y) {
            File[] files = {};
            var type = value.type ();
            if (type == Type.STRING) {
                var text = value.get_string ();
                var list = text.split_set ("\n");
                files = new File[list.length];
                var index = 0;
                foreach (var path in list) {
                    files[index++] = File.new_for_path (path);
                }
            } else if (type == typeof (Gdk.FileList)) {
                var list = ((Gdk.FileList) value).get_files ();
                files = new File[list.length ()];
                var index = 0;
                foreach (var file in list) {
                    files[index++] = file;
                }
            } else {
                print ("Uknown type: %s\n", value.type_name ());
                return false;
            }

            var app = (Application) application;
            app.open_files_async.begin (files, app.current_music == null,
                (obj, res) => app.open_files_async.end (res));
            return true;
        }

        private bool _loading = false;
        private uint _tick_handler = 0;

        private void on_loading_changed (bool loading) {
            root.action_set_enabled (ACTION_APP + ACTION_RELOAD, !loading);

            _loading = loading;
            if (loading) {
                run_timeout_once (100, () => _progress_bar.visible = _loading);
            } else {
                _progress_bar.visible = _loading;
            }

            if (loading && _tick_handler == 0) {
                _tick_handler = add_tick_callback (on_loading_tick_callback);
            } else if (!loading && _tick_handler != 0) {
                remove_tick_callback (_tick_handler);
                _tick_handler = 0;
            }
        }

        private bool on_loading_tick_callback (Gtk.Widget widget, Gdk.FrameClock clock) {
            var app = (Application) application;
            var fraction = app.loader.loading_progress;
            if (fraction > 0)
                _progress_bar.fraction = fraction;
            else
                _progress_bar.pulse ();
            return true;
        }

        private void setup_drop_target () {
            //  Hack: when drag a folder from nautilus,
            //  the value is claimed as GdkFileList in accept(),
            //  but the value can't be convert as GdkFileList in drop(),
            //  so use STRING type to get the file/folder path.
            var target = new Gtk.DropTarget (Type.INVALID, Gdk.DragAction.COPY);
            target.set_gtypes ({ Type.STRING, typeof (Gdk.FileList) });
            target.accept.connect ((drop) => drop.formats.contain_gtype (typeof (Gdk.FileList)));
#if GTK_4_10
            target.drop.connect (on_file_dropped);
#else
            target.on_drop.connect (on_file_dropped);
#endif
            this.content.add_controller (target);
        }

        private void setup_focus_controller () {
            var controller = new Gtk.EventControllerFocus ();
            controller.enter.connect (() => focused_visible = false);
            this.content.add_controller (controller);
            this.bind_property ("focus_visible", this, "focused_visible");
            this.bind_property ("focus_widget", this, "focused_widget");
        }

        private void update_background () {
            var paintable = _cover_paintable;
            if ((_bkgnd_blur == BlurMode.ALWAYS && paintable != null)
                || (_bkgnd_blur == BlurMode.ART_ONLY && paintable is Gdk.Texture)) {
                _bkgnd_paintable.paintable = create_blur_paintable (this,
                    (!)paintable, _blur_size, _blur_size * 0.2, 0.25);
            } else {
                _bkgnd_paintable.paintable = null;
            }
        }
    }

    public Gtk.Button? find_button_by_action_name (Gtk.Widget widget, string action) {
        for (var child = widget.get_first_child (); child != null; child = child?.get_next_sibling ()) {
            if (!((!)child).is_drawable ()) {
                continue;
            } else if (child is Gtk.Button) {
                var button = (Gtk.Button) child;
                if (button.action_name == action)
                    return button;
            } else {
                var button = find_button_by_action_name ((!)child, action);
                if (button != null)
                    return button;
            }
        }
        return null;
    }
}
