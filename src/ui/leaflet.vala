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
        private Gtk.Widget _content_box;
        private Gtk.Widget _sidebar_box;
        private Gtk.Widget _content = new Gtk.Label (null);
        private Gtk.Widget _sidebar = new Gtk.Label (null);
        private Stack _widget = new Stack (true);

        private bool _folded = false;
        private int _min_sidebar_width = 340;
        private int _max_sidebar_width = 480;
        private float _sidebar_fraction = 3/8f;
        private int _view_width = 0;
        private int _view_height = 0;
        private int _visible_mode = LeafletMode.NONE;

        public Leaflet () {
            _sidebar_box = _widget.add (_sidebar, "sidebar");
            _content_box = _widget.add (_content, "content");
            _widget.widget.set_parent (this);
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
                if (_folded)
                    _widget.set_child (_content_box, value);
                else
                    _content.set_parent (this);
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
            var folded = width < _min_sidebar_width * 2;
            if (_folded != folded || first) {
                _folded = folded;
                if (folded && !_content.is_ancestor (_content_box)) {
                    _content.unparent ();
                    _widget.set_child (_content_box, _content);
                } else if (!folded && _content.is_ancestor (_content_box)) {
                    _widget.set_child (_content_box, new Gtk.Label (null));
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
                var side_width = (int) (width * _sidebar_fraction);
                side_width = side_width.clamp (_min_sidebar_width, _max_sidebar_width);
                var content_width = width - side_width;

                //  put sidebar at start
                allocation.x = rtl ? side_width : 0;
                allocation.width = content_width;
                (_sidebar as SizeWatcher)?.size_to_change (content_width, height);
                _sidebar.allocate_size (allocation, baseline);
                stack.allocate_size (allocation, baseline);

                //  put content at end
                allocation.x = rtl ? 0 : content_width;
                allocation.width = side_width;
                (_content as SizeWatcher)?.size_to_change (side_width, height);
                _content.allocate_size (allocation, baseline);
            }
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            var minimum1 = 0, minimum2 = 0;
            var natural1 = 0, natural2 = 0;
            _content.measure (orientation, for_size, out minimum1, out natural1, out minimum_baseline, out natural_baseline);
            _sidebar.measure (orientation, for_size, out minimum2, out natural2, out minimum_baseline, out natural_baseline);
            minimum = int.max (minimum1, minimum2);
            natural = int.max (natural1, natural2);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (!_folded) {
                var size = _sidebar.get_width ();
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

        private void update_visible_child () {
            _widget.visible_child = _folded && _visible_mode == LeafletMode.CONTENT ? _content : _sidebar;
        }
    }

#if ADW_1_4
    public class Stack : Object {
        private bool _retain_last_popped = false;
        private Adw.NavigationPage? _last_popped_page = null;
        private Adw.NavigationView _widget = new Adw.NavigationView ();

        public Stack (bool retain_last_popped = false) {
            _retain_last_popped = retain_last_popped;
            _widget = new Adw.NavigationView ();
            _widget.get_next_page.connect (() => {
                return _widget.visible_page != _last_popped_page ? _last_popped_page : null;
            });
            _widget.pushed.connect(() => {
                notify_property ("visible-child");
            });
            _widget.popped.connect((page) => {
                notify_property ("visible-child");
                if (_retain_last_popped)
                    _last_popped_page = page;
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
                    if (_last_popped_page?.child == value) {
                        _widget.push ((!)_last_popped_page);
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
                _last_popped_page = page;
                _widget.add (page);
            } else {
                _widget.push (page);
            }
            return page;
        }

        public void pop () {
            _widget.pop ();
        }

        public void remove (Gtk.Widget child) {
            if (_last_popped_page?.child == child) {
                _widget.remove ((!)_last_popped_page);
                _last_popped_page = null;
            } else {
                var page = find_page (child);
                if (page != null) {
                    _widget.remove ((!)page);
                }
            }
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

        public GenericArray<string> get_child_names () {
            var pages = _widget.navigation_stack;
            var count = pages.get_n_items ();
            var children = new GenericArray<string> (count);
            for (var i = 0; i < count; i++) {
                var page = (Adw.NavigationPage) pages.get_item (i);
                children.add (page.tag);
            }
            return children;
        }

        public void set_child (Gtk.Widget page, Gtk.Widget child) {
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
            var overlay = new Adw.Bin ();
            overlay.child = child;
            _widget.add_named (overlay, tag);
            return overlay;
        }

        public void pop () {
            var child = _widget.get_visible_child ();
            var previous = _widget.get_visible_child ()?.get_prev_sibling ();
            if (child != null && previous != null) {
                _widget.visible_child = (!)previous;
                run_timeout_once (_widget.transition_duration, () => {
                    _widget.remove ((!)child);
                });
            }
        }

        public void remove (Gtk.Widget child) {
            var page = find_page (child);
            if (page != null) {
                _widget.remove ((!)page);
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

        public GenericArray<string> get_child_names () {
            var pages = _widget.pages;
            var count = pages.get_n_items ();
            var children = new GenericArray<string> (count);
            for (var i = 0; i < count; i++) {
                var page = (Gtk.StackPage) pages.get_item (i);
                children.add (page.name);
            }
            return children;
        }

        public void set_child (Gtk.Widget page, Gtk.Widget child) {
            var p = page as Adw.Bin;
            p?.set_child (child);
        }

        private Gtk.Widget? find_page (Gtk.Widget child) {
            for (var page = _widget.get_first_child (); page != null; page = page?.get_next_sibling ()) {
                if ((page as Adw.Bin)?.child == child)
                    return page;
            }
            return null;
        }
    }
#endif
}
