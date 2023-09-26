namespace G4 {

    public class SwitchBar : Gtk.Widget {
        private Gtk.Box _box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        private Gtk.Revealer _revealer = new Gtk.Revealer ();
        private int _minimum_width = 0;
        private Gtk.Stack _stack = (Gtk.Stack) null;

        public SwitchBar () {
            _box.hexpand = true;
            _revealer.child = _box;
            _revealer.reveal_child = true;
            add_child (new Gtk.Builder (), _revealer, null);
        }

        public bool reveal_child {
            get {
                return _revealer.reveal_child;
            }
            set {
                _revealer.reveal_child = value;
            }
        }

        public Gtk.Stack stack {
            get {
                return _stack;
            }
            set {
                _stack = value;
                _stack.bind_property ("visible-child-name", this, "visible-child-name", BindingFlags.SYNC_CREATE);
                update_buttons ();
            }
        }

        public Gtk.RevealerTransitionType transition_type {
            get {
                return _revealer.transition_type;
            }
            set {
                _revealer.transition_type = value;
            }
        }

        public string visible_child_name {
            set {
                for (var child = _box.get_first_child (); child != null; child = child?.get_next_sibling ()) {
                    var button = (Gtk.ToggleButton) child;
                    button.active = button.name == value;
                }
            }
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            var horizontal = orientation == Gtk.Orientation.HORIZONTAL;
            if (for_size < 0) {
                var parent = get_parent ();
                for_size = (horizontal ? parent?.get_width () : parent?.get_height ()) ?? 1000;
            }
            _box.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (horizontal) {
                minimum = 0;
                _minimum_width = natural;
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            var allocation = Gtk.Allocation ();
            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;
            _revealer.allocate_size (allocation, baseline);
            reveal_child = width >= _minimum_width - 4; // -4 to avoid size_allocate() be called continuously when (_minimum_width - width) == 1
        }

        public void update_buttons () {
            var pages = _stack.pages;
            var n_items = pages.get_n_items ();
            for (var child = _box.get_last_child (); child != null; child = child?.get_prev_sibling ()) {
                if (_stack.get_child_by_name (child?.name ?? "") == null)
                    _box.remove((!)child);
            }
            var visible_child = _stack.visible_child;
            for (var i = 0; i < n_items; i++) {
                var page = (Gtk.StackPage) pages.get_item (i);
                if (find_child_by_name (page.name) == null) {
                    var button = new Gtk.ToggleButton ();
                    button.active = page.child == visible_child;
                    button.name = page.name;
                    button.icon_name = page.icon_name;
                    button.tooltip_text = page.title;
                    button.toggled.connect (() => {
                        if (button.active && _stack.visible_child_name != button.name)
                            _stack.set_visible_child_name (button.name);
                        else if (!button.active && _stack.visible_child_name == button.name)
                            run_idle_once (() => button.active = true);
                    });
                    _box.append (button);
                }
            }
        }

        private Gtk.Widget? find_child_by_name (string name) {
            for (var child = _box.get_first_child (); child != null; child = child?.get_next_sibling ()) {
                if (strcmp (child?.name, name) == 0)
                    return child;
            }
            return null;
        }
    }
}
