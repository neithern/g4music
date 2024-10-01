namespace G4 {

    public interface SizeWatcher {
        public abstract void first_allocated ();
        public abstract void size_to_change (int width, int height);
    }

    namespace LeafletMode {
        public const int SIDEBAR = 1;
        public const int CONTENT = 2;
    }

    public class Leaflet : Gtk.Widget {
        private Gtk.Widget _content_box;
        private Gtk.Widget _sidebar_box;
        private Gtk.Widget _content = new Adw.Bin ();
        private Gtk.Widget _sidebar = new Adw.Bin ();
        private Stack _widget = new Stack (true);

        private bool _folded = false;
        private float _content_fraction = 3/8f;
        private int _content_min_width = 340;
        private int _content_max_width = 480;
        private int _view_width = 0;
        private int _view_height = 0;
        private int _visible_mode = LeafletMode.SIDEBAR;

        public Leaflet () {
            _sidebar_box = _widget.add (_sidebar, "sidebar");
            _content_box = _widget.add (_content, "content");
            _widget.widget.set_parent (this);
            _widget.notify["visible-child"].connect (() => {
                var mode = _widget.visible_child == _sidebar ? LeafletMode.SIDEBAR : LeafletMode.CONTENT;
                if (_folded && _visible_mode != mode) {
                    _visible_mode = mode;
                    notify_property ("visible-mode");
                }
            });
        }

        ~Leaflet () {
            _content.unparent ();
            _widget.widget.unparent ();
        }

        public bool folded {
            get {
                return _folded;
            }
        }

        public Gtk.Widget content {
            get {
                return _content;
            }
            set {
                _content = value;
                if (_folded) {
                    _widget.set_child (_content_box, value);
                } else {
                    _widget.set_child (_content_box, null);
                    _content.set_parent (this);
                }
                queue_allocate ();
            }
        }

        public Gtk.Widget sidebar {
            get {
                return _sidebar;
            }
            set {
                _sidebar = value;
                _widget.set_child (_sidebar_box, value);
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
            visible_mode = LeafletMode.SIDEBAR;
        }

        public void push () {
            visible_mode = LeafletMode.CONTENT;
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            var minimum1 = 0, minimum2 = 0;
            var natural1 = 0, natural2 = 0;
            _content.measure (orientation, for_size, out minimum1, out natural1, out minimum_baseline, out natural_baseline);
            _sidebar.measure (orientation, for_size, out minimum2, out natural2, out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = int.max (int.min (minimum1, minimum2), _content_min_width);
            } else {
                minimum = int.max (minimum1, minimum2);
            }
            natural = int.max (natural1, natural2);
        }

        public override void size_allocate (int width, int height, int baseline) {
            var first = _view_width == 0 && width > 0;
            if (first) {
                run_idle_once (() => {
                    (_content as SizeWatcher)?.first_allocated ();
                    (_sidebar as SizeWatcher)?.first_allocated ();
                });
            }
            _view_width = width;
            _view_height = height;

            var stack = _widget.widget;
            var folded = width < _content_min_width * 2;
            if (_folded != folded || first) {
                _folded = folded;
                if (folded && !_content.is_ancestor (_content_box)) {
                    _content.unparent ();
                    _widget.set_child (_content_box, _content);
                } else if (!folded && _content.is_ancestor (_content_box)) {
                    _widget.set_child (_content_box, null);
                    _content.insert_after (this, _widget.widget);
                }

                var animate = _widget.animate_transitions;
                _widget.animate_transitions = false;
                update_visible_child ();
                _widget.animate_transitions = animate;
                notify_property ("folded");
            }

            var allocation = Gtk.Allocation ();
            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;

            if (folded) {
                (_content as SizeWatcher)?.size_to_change (width, height);
                (_sidebar as SizeWatcher)?.size_to_change (width, height);
                _content.allocate_size (allocation, baseline);
                _sidebar.allocate_size (allocation, baseline);
                stack.allocate_size (allocation, baseline);
            } else {
                var rtl = get_direction () == Gtk.TextDirection.RTL;
                var content_width = (int) (width * _content_fraction).clamp (_content_min_width, _content_max_width);
                var side_width = width - content_width;

                //  put sidebar at start
                allocation.x = rtl ? content_width : 0;
                allocation.width = side_width;
                (_sidebar as SizeWatcher)?.size_to_change (side_width, height);
                _sidebar.allocate_size (allocation, baseline);
                stack.allocate_size (allocation, baseline);

                //  put content at end
                allocation.x = rtl ? 0 : side_width;
                allocation.width = content_width;
                (_content as SizeWatcher)?.size_to_change (content_width, height);
                _content.allocate_size (allocation, baseline);
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (!_folded) {
                var size = _sidebar.get_width ();
                var rtl = get_direction () == Gtk.TextDirection.RTL;
                var rect = Graphene.Rect ();
                rect.init (rtl ? _view_width - size : size, 0, 0.5f, _view_height);
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

        private void update_visible_child () {
            _widget.visible_child = _folded && _visible_mode == LeafletMode.CONTENT ? _content : _sidebar;
        }
    }

#if ADW_1_4
    public class Stack : Object {
        private bool _retain_last_popped = false;
        private Adw.NavigationPage? _last_page = null;
        private Adw.NavigationView _widget = new Adw.NavigationView ();

        public Stack (bool retain_last_popped = false) {
            _retain_last_popped = retain_last_popped;
            _widget = new Adw.NavigationView ();
            _widget.get_next_page.connect (() => {
                return (_widget.visible_page != _last_page && _last_page?.get_child () != null) ? _last_page : null;
            });
            _widget.pushed.connect(() => {
                notify_property ("visible-child");
            });
            _widget.popped.connect((page) => {
                notify_property ("visible-child");
                if (_retain_last_popped)
                    _last_page = page;
            });
        }

        public bool animate_transitions {
            get {
                return _widget.animate_transitions;
            }
            set {
                _widget.animate_transitions = value;
            }
        }

        public Gtk.Widget parent {
            get {
                return _widget.parent;
            }
        }

        public Gtk.Widget visible_child {
            get {
                return _widget.visible_page.child;
            }
            set {
                if (_widget.visible_page.child != value) {
                    if (_last_page?.child == value) {
                        _widget.push ((!)_last_page);
                    } else {
                        var page = find_page (value);
                        if (page != null)
                            _widget.pop_to_page ((!)page);
                    }
                }
            }
        }

        public Gtk.Widget widget {
            get {
                return _widget;
            }
        }

        public Gtk.Widget add (Gtk.Widget child, string? tag = null) {
            var page = new Adw.NavigationPage (child, tag ?? "");
            page.set_tag (tag);
            if (_retain_last_popped) {
                _last_page = page;
                _widget.add (page);
            } else {
                _widget.push (page);
            }
            return page;
        }

        public void pop () {
            _widget.pop ();
        }

        public Gtk.Widget? get_child_by_name (string name) {
            return _widget.find_page (name)?.child;
        }

        public GenericArray<Gtk.Widget> get_children () {
            var pages = _widget.navigation_stack;
            var count = pages.get_n_items ();
            var children = new GenericArray<Gtk.Widget> (count);
            for (var i = 0; i < count; i++) {
                var page = (Adw.NavigationPage) pages.get_item (i);
                children.add (page.child);
            }
            return children;
        }

        public void get_visible_names (GenericArray<string> names) {
            var pages = _widget.navigation_stack;
            var count = pages.get_n_items ();
            var visible_page = _widget.visible_page;
            for (var i = 0; i < count; i++) {
                var page = (Adw.NavigationPage) pages.get_item (i);
                names.add (page.tag);
                if (page == visible_page)
                    break;
            }
        }

        public void set_child (Gtk.Widget page, Gtk.Widget? child) {
            var p = page as Adw.NavigationPage;
            p?.set_child (child);
        }

        private Adw.NavigationPage? find_page (Gtk.Widget child) {
            var pages = _widget.navigation_stack;
            var count = pages.get_n_items ();
            for (var i = 0; i < count; i++) {
                var page = (Adw.NavigationPage) pages.get_item (i);
                if (page.child == child)
                    return page;
            }
            return null;
        }
    }
#else
    public class Stack : Object {
        private Gtk.Stack _widget = new Gtk.Stack ();

        public Stack (bool retain_last_popped = false) {
            _widget = new Gtk.Stack ();
            animate_transitions = true;
        }

        public bool animate_transitions {
            get {
                return _widget.transition_type != Gtk.StackTransitionType.NONE;
            }
            set {
                _widget.transition_type = value ? Gtk.StackTransitionType.SLIDE_LEFT_RIGHT : Gtk.StackTransitionType.NONE;
            }
        }

        public Gtk.Widget parent {
            get {
                return _widget.parent;
            }
        }

        public Gtk.Widget visible_child {
            get {
                return ((Adw.Bin) _widget.visible_child).child;
            }
            set {
                _widget.visible_child = value.parent;
            }
        }

        public Gtk.Widget widget {
            get {
                return _widget;
            }
        }

        public Gtk.Widget add (Gtk.Widget child, string? tag = null) {
            var bin = new Adw.Bin ();
            bin.child = child;
            _widget.add_named (bin, tag);
            _widget.visible_child = bin;
            notify_property ("visible-child");
            return bin;
        }

        public void pop () {
            var child = _widget.get_visible_child ();
            var previous = child?.get_prev_sibling ();
            if (child != null && previous != null) {
                _widget.visible_child = (!)previous;
                notify_property ("visible-child");
                run_timeout_once (_widget.transition_duration, () => {
                    _widget.remove ((!)child);
                });
            }
        }

        public Gtk.Widget? get_child_by_name (string name) {
            return (_widget.get_child_by_name (name) as Adw.Bin)?.child;
        }

        public GenericArray<Gtk.Widget> get_children () {
            var pages = _widget.pages;
            var count = pages.get_n_items ();
            var children = new GenericArray<Gtk.Widget> (count);
            for (var i = 0; i < count; i++) {
                var page = (Gtk.StackPage) pages.get_item (i);
                children.add (((Adw.Bin) page.child).child);
            }
            return children;
        }

        public void get_visible_names (GenericArray<string> names) {
            var pages = _widget.pages;
            var count = pages.get_n_items ();
            var child = _widget.visible_child;
            for (var i = 0; i < count; i++) {
                var page = (Gtk.StackPage) pages.get_item (i);
                names.add (page.name);
                if (page.child == child)
                    break;
            }
        }

        public void set_child (Gtk.Widget page, Gtk.Widget? child) {
            (page as Adw.Bin)?.set_child (child);
        }
    }
#endif
}
