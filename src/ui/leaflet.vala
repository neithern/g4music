namespace G4 {

    public interface SizeWatcher {
        public abstract void first_allocated ();
        public abstract void size_to_change (int width, int height);
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
                _content = value;
                queue_allocate ();
            }
        }

        public Gtk.Widget? sidebar {
            get {
                return _sidebar;
            }
            set {
                _sidebar = value;
                queue_allocate ();
            }
        }

        public void pop () {
            var child = _stack.get_first_child ();
            if (child != null) {
                _stack.visible_child = (!)child;
            }
        }

        public void push () {
            var child = _stack.get_last_child ();
            if (child != null) {
                _stack.visible_child = (!)child;
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
            if (_folded != folded) {
                _folded = folded;
                notify_property ("folded");
            }

            var parent = folded ? (Gtk.Widget) _stack : (Gtk.Widget) this;
            update_parent (parent, _content);
            update_parent (parent, _sidebar);

            var allocation = Gtk.Allocation ();
            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;
            _stack.allocate_size (allocation, baseline);

            if (folded) {
                (_content as SizeWatcher)?.size_to_change (width, height);
                (_sidebar as SizeWatcher)?.size_to_change (width, height);
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
    }
}
