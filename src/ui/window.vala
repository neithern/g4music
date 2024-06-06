namespace G4 {

    public class Window : Adw.ApplicationWindow {
        private Adw.Leaflet _leaflet = new Adw.Leaflet ();
        private MiniBar _mini_bar = new MiniBar ();
        private PlayPanel _play_panel;
        private StorePanel _store_panel;

        private int _blur_size = 512;
        private uint _bkgnd_blur = BlurMode.ALWAYS;
        private CrossFadePaintable _bkgnd_paintable = new CrossFadePaintable ();
        private Gdk.Paintable? _cover_paintable = null;
        private int _window_width = 0;
        private int _window_height = 0;

        public Window (Application app) {
            this.application = app;
            this.icon_name = app.application_id;
            this.title = app.name;
            this.close_request.connect (on_close_request);

            var handle = new Gtk.WindowHandle ();
            handle.child = _leaflet;
            this.content = handle;

            _bkgnd_paintable.queue_draw.connect (this.queue_draw);

            var revealer = new Gtk.Revealer ();
            revealer.child = _mini_bar;
            revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            _mini_bar.activated.connect (() => _leaflet.navigate (Adw.NavigationDirection.FORWARD));

            _store_panel = new StorePanel (app, this, _leaflet);
            _store_panel.append (revealer);

            _play_panel = new PlayPanel (app, this, _leaflet);
            _play_panel.cover_changed.connect (on_cover_changed);

            _leaflet.append (_store_panel);
            _leaflet.append (_play_panel);
            _leaflet.bind_property ("folded", revealer, "reveal-child", BindingFlags.SYNC_CREATE);

            setup_drop_target ();
            setup_focus_controller ();

            var settings = app.settings;
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
                if (_window_height > 0)
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

        public override void size_allocate (int width, int height, int baseline) {
            var min_width = 340;
            var play_width = int.max (width * 3 / 8, min_width);
            var store_width = int.max (width - play_width, min_width);
            var wide = width > min_width * 2;
            _play_panel.size_to_change (wide ? play_width : width);
            _store_panel.size_to_change (wide ? store_width : width);
            _mini_bar.size_to_change (wide ? store_width : width);

            base.size_allocate (width, height, baseline);

            var rtl = get_direction () == Gtk.TextDirection.RTL;
            var left_width = rtl ? play_width : store_width;
            var right_width = rtl ? store_width : play_width;
            var left_panel = rtl ? (Gtk.Widget) _play_panel : (Gtk.Widget) _store_panel;
            var right_panel = rtl ? (Gtk.Widget) _store_panel : (Gtk.Widget) _play_panel;
            var allocation = Gtk.Allocation ();
            allocation.x = allocation.y = 0;
            if (_leaflet.folded) {
                allocation.width = width;
                allocation.height = height;
                _leaflet.get_visible_child ()?.allocate_size (allocation, baseline);
            } else {
                allocation.width = left_width;
                allocation.height = height;
                left_panel.allocate_size (allocation, baseline);
                allocation.x = width - right_width;
                allocation.width = right_width;
                right_panel.allocate_size (allocation, baseline);
            }

            if (_window_width == 0 && width > 0) {
                run_idle_once (() => {
                    _play_panel.size_allocated ();
                    _store_panel.size_allocated ();
                });
            }
            _window_width = width;
            _window_height = height;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = _window_width;
            var height = _window_height;
            _bkgnd_paintable.snapshot (snapshot, width, height);
            if (!_leaflet.folded) {
                var page = (Adw.LeafletPage) _leaflet.pages.get_item (0);
                var size = page.child.get_width ();
                var rtl = get_direction () == Gtk.TextDirection.RTL;
                var line_width = scale_factor >= 2 ? 0.5f : 1;
                var rect = Graphene.Rect ();
                rect.init (rtl ? width - size : size, 0, line_width, height);
                var color = Gdk.RGBA ();
                color.red = color.green = color.blue = color.alpha = 0;
#if GTK_4_10
                var color2 = get_color ();
#else
                var color2 = get_style_context ().get_color ();
#endif
                color2.alpha = 0.25f;
                Gsk.ColorStop[] stops = { { 0, color }, { 0.5f, color2 }, { 1, color } };
                snapshot.append_linear_gradient (rect, rect.get_top_left (), rect.get_bottom_right (), stops);
            }
            base.snapshot (snapshot);
        }

        public void open_page (string[] paths, Object? obj = null) {
            _store_panel.locate_to_path (paths, obj);
        }

        public void start_search (string text, uint mode = SearchMode.ANY) {
            _store_panel.start_search (text, mode);
            if (_leaflet.folded) {
                _leaflet.navigate (Adw.NavigationDirection.BACK);
            }
        }

        public void toggle_search () {
            if (_store_panel.toggle_search () && _leaflet.folded) {
                _leaflet.navigate (Adw.NavigationDirection.BACK);
            }
        }

        private void focus_to_play_later (int delay = 100) {
            run_timeout_once (delay, () => {
                if (!focus_visible && !(focus_widget is Gtk.Editable)) {
                    _play_panel.focus_to_play ();
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
            _mini_bar.cover = music != null ? (app.thumbnailer.find ((!)music)  ?? _cover_paintable) : app.icon;
            _mini_bar.title = music?.title ?? "";
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
            this.bind_property ("focus_visible", this, "focused_visible", BindingFlags.SYNC_CREATE);
            this.bind_property ("focus_widget", this, "focused_widget", BindingFlags.SYNC_CREATE);
        }

        private void update_background () {
            var paintable = _cover_paintable;
            if ((_bkgnd_blur == BlurMode.ALWAYS && paintable != null)
                || (_bkgnd_blur == BlurMode.ART_ONLY && paintable is Gdk.Texture)) {
                _bkgnd_paintable.paintable = create_blur_paintable (this,
                    (!)paintable, _blur_size, _blur_size, 80, 0.25);
            } else {
                _bkgnd_paintable.paintable = null;
            }
        }
    }
}
