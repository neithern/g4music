namespace G4 {

    public class SwitchBar : Gtk.Widget {
        private Gtk.Box _box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        private Gtk.Revealer _revealer = new Gtk.Revealer ();
        private int _minimum_width = 0;
        private Gtk.Stack? _stack = null;

        public SwitchBar () {
            _box.hexpand = true;
            _box.add_css_class ("toolbar");
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

        public Gtk.Stack? stack {
            get {
                return _stack;
            }
            set {
                var pages = value?.get_pages ();
                var n_items = pages?.get_n_items () ?? 0;
                for (var i = 0; i < n_items; i++) {
                    var page = (Gtk.StackPage) pages?.get_item (i);
                    var button = new Gtk.ToggleButton ();
                    button.name = page.name;
                    button.icon_name = page.icon_name;
                    button.tooltip_text = page.title;
                    button.toggled.connect (() => {
                        if (button.active)
                            _stack?.set_visible_child_name (button.name);
                    });
                    _box.append (button);
                }
                _stack = value;
                _stack?.bind_property ("visible-child-name", this, "visible-child-name", BindingFlags.SYNC_CREATE);
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
            reveal_child = width >= _minimum_width;
        }
    }
}