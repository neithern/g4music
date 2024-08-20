namespace G4 {

    public interface SizeWatcher {
        public abstract void first_allocated ();
        public abstract void size_to_change (int width, int height);
    }

    namespace LeafletMode {
        public const int NONE = 0;
        public const int CONTENT = 1;
        public const int SIDEBAR = 2;
    }

    public class Leaflet : Gtk.Widget {
        private Gtk.Builder _builder = new Gtk.Builder ();
        private Gtk.Widget? _content = null;
        private Gtk.Widget? _sidebar = null;
        private Gtk.Stack _stack = new Gtk.Stack ();

        private bool _folded = false;
        private int _min_sidebar_width = 340;
        private int _max_sidebar_width = 480;
        private float _sidebar_fraction = 3/8f;
        private int _view_width = 0;
        private int _view_height = 0;
        private int _visible_mode = LeafletMode.NONE;

        public Leaflet () {
            add_child (_builder, _stack, null);
            _stack.transition_type = Gtk.StackTransitionType.OVER_LEFT_RIGHT;
        }

        ~Leaflet () {
            _content?.unparent ();
            _sidebar?.unparent ();
            _stack.unparent ();
        }

        public bool folded {
            get {
                return _folded;
            }
        }

        public Gtk.Widget? content {
            get {
                return _content;
            }
            set {
                _content?.unparent ();
                _content = value;
                if (value != null)
                    add_child (_builder, (!)value, null);
                queue_allocate ();
            }
        }

        public Gtk.Widget? sidebar {
            get {
                return _sidebar;
            }
            set {
                _sidebar?.unparent ();
                _sidebar = value;
                if (value != null)
                    add_child (_builder, (!)value, null);
                queue_allocate ();
            }
        }

        public int visible_mode {
            get {
                return _visible_mode;
            }
            set {
                _visible_mode = value;
                update_visible_child ();
            }
        }

        public void pop () {
            var child = _stack.get_first_child ();
            if (child != null) {
                _stack.visible_child = (!)child;
                update_visible_mode ();
            }
        }

        public void push () {
            var child = _stack.get_last_child ();
            if (child != null) {
                _stack.visible_child = (!)child;
                update_visible_mode ();
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            if (_view_width == 0 && width > 0) {
                Idle.add (() => {
                    (_content as SizeWatcher)?.first_allocated ();
                    (_sidebar as SizeWatcher)?.first_allocated ();
                    return false;
                });
            }
            _view_width = width;
            _view_height = height;

            var folded = width < _min_sidebar_width * 2;
            var fold_changed = _folded != folded;
            if (_folded != folded) {
                _folded = folded;
                notify_property ("folded");
                update_visible_mode ();
            }

            var parent = folded ? (Gtk.Widget) _stack : (Gtk.Widget) this;
            update_parent (parent, _content);
            update_parent (parent, _sidebar);
            if (fold_changed) {
                update_visible_child ();
            }

            var allocation = Gtk.Allocation ();
            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;

            if (folded) {
                (_content as SizeWatcher)?.size_to_change (width, height);
                (_sidebar as SizeWatcher)?.size_to_change (width, height);
                _content?.allocate_size (allocation, baseline);
                _sidebar?.allocate_size (allocation, baseline);
            } else {
                var rtl = get_direction () == Gtk.TextDirection.RTL;
                var side_width = (int) (width * _sidebar_fraction);
                side_width = side_width.clamp (_min_sidebar_width, _max_sidebar_width);
                var content_width = width - side_width;

                //  put Content at start
                allocation.x = rtl ? side_width : 0;
                allocation.width = content_width;
                (_content as SizeWatcher)?.size_to_change (content_width, height);
                _content?.allocate_size (allocation, baseline);

                //  put Sidebar at end
                allocation.x = rtl ? 0 : content_width;
                allocation.width = side_width;
                (_sidebar as SizeWatcher)?.size_to_change (side_width, height);
                _sidebar?.allocate_size (allocation, baseline);
            }

            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;
            _stack.allocate_size (allocation, baseline);
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            var minimum1 = 0, minimum2 = 0;
            var natural1 = 0, natural2 = 0;
            minimum_baseline = 0;
            natural_baseline = 0;
            _content?.measure (orientation, for_size, out minimum1, out natural1, out minimum_baseline, out natural_baseline);
            _sidebar?.measure (orientation, for_size, out minimum2, out natural2, out minimum_baseline, out natural_baseline);
            minimum = int.max (minimum1, minimum2);
            natural = int.max (natural1, natural2);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (!_folded) {
                var size = _content?.get_width () ?? 0;
                var rtl = get_direction () == Gtk.TextDirection.RTL;
                var rect = Graphene.Rect ();
                rect.init (rtl ? _view_width - size : size, 0, scale_factor * 0.25f, _view_height);
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

        private void update_parent (Gtk.Widget parent, Gtk.Widget? widget) {
            var parent0 = widget?.parent;
            if (widget != null && parent0 != parent) {
                var child = (!)widget;
                if (parent0 == _stack) {
                    _stack.remove (child);
                } else {
                    child.unparent ();
                }
                if (_folded) {
                    _stack.add_child (child);
                } else {
                    add_child (_builder, child, null);
                }
            }
        }

        private void update_visible_child () {
            Gtk.Widget? child = null;
            switch (_visible_mode) {
                case LeafletMode.CONTENT:
                    child = _content;
                    break;
                case LeafletMode.SIDEBAR:
                    child = _sidebar;
                    break;
            }
            if (child != null && child?.parent == _stack && _stack.visible_child != child) {
                _stack.transition_type = Gtk.StackTransitionType.NONE;
                _stack.visible_child = (!)child;
                _stack.transition_type = Gtk.StackTransitionType.OVER_LEFT_RIGHT;
            }
        }

        private void update_visible_mode () {
            var child = _stack.get_visible_child ();
            var mode = _visible_mode;
            if (child == _content)
                mode = LeafletMode.CONTENT;
            else if (child == _sidebar)
                mode = LeafletMode.SIDEBAR;
            if (_visible_mode != mode) {
                _visible_mode = mode;
                notify_property ("visible-mode");
            }
        }
    }
}
