namespace G4 {

    public class Switcher : Gtk.Widget {
        static construct {
            set_layout_manager_type (typeof (Gtk.BoxLayout));
        }

        private Gtk.Stack _stack = (Gtk.Stack) null;

        public Switcher (bool narrow, uint spacing = 4) {
            var layout = get_layout_manager () as Gtk.BoxLayout;
            layout?.set_homogeneous (true);
            layout?.set_spacing (spacing);
            add_css_class (narrow ? "narrow" : "wide");
        }

        public Gtk.Stack stack {
            get {
                return _stack;
            }
            set {
                _stack = value;
                _stack.bind_property ("visible-child-name", this, "visible-child-name");
                update_buttons ();
            }
        }

        public string visible_child_name {
            set {
                for (var child = get_first_child (); child != null; child = child?.get_next_sibling ()) {
                    var button = (Gtk.ToggleButton) child;
                    button.active = button.name == value;
                }
            }
        }

        public int get_min_width () {
            var layout = get_layout_manager () as Gtk.BoxLayout;
            var spacing = layout?.get_spacing () ?? 0;
            uint width = 0;
            for (var child = get_last_child (); child != null; child = child?.get_prev_sibling ()) {
                width += ((!)child).width_request + spacing;
            }
            return width > spacing ? (int) (width - spacing) : 0;
        }

        public void update_buttons () {
            var pages = _stack.pages;
            var n_items = pages.get_n_items ();
            for (var child = get_last_child (); child != null; child = child?.get_prev_sibling ()) {
                if (_stack.get_child_by_name (((!)child).name) == null)
                    ((!)child).unparent ();
            }
            var visible_child = _stack.visible_child;
            for (var i = 0; i < n_items; i++) {
                var page = (Gtk.StackPage) pages.get_item (i);
                if (find_child_by_name (page.name) == null) {
                    var button = new Gtk.ToggleButton ();
                    button.active = page.child == visible_child;
                    button.hexpand = true;
                    button.icon_name = page.icon_name;
                    button.name = page.name;
                    button.tooltip_text = page.title;
                    button.width_request = 48;
                    button.add_css_class ("flat");
                    button.toggled.connect (() => {
                        if (button.active && _stack.visible_child_name != button.name)
                            _stack.set_visible_child_name (button.name);
                        else if (!button.active && _stack.visible_child_name == button.name)
                            run_idle_once (() => button.active = true);
                    });
                    button.insert_before (this, null);
                }
            }
            queue_resize ();
        }

        private Gtk.Widget? find_child_by_name (string name) {
            for (var child = get_first_child (); child != null; child = child?.get_next_sibling ()) {
                if (((!)child).name == name)
                    return child;
            }
            return null;
        }
    }

    public class SwitchBar : Gtk.Widget {
        private int _minimum_width = 0;
        private bool _reveal = true;
        private Switcher _switcher;

        public SwitchBar (bool narrow, uint spacing = 4) {
            _switcher = new Switcher (narrow, spacing);
            _switcher.set_parent (this);
        }

        public bool reveal {
            get {
                return _reveal;
            }
            set {
                _reveal = value;
                queue_resize ();
            }
        }

        public Switcher switcher {
            get {
                return _switcher;
            }
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            _switcher.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                _minimum_width = _switcher.get_min_width ();
                minimum = _minimum_width / 2;
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            _reveal = width >= _minimum_width;
            notify_property ("reveal");

            var allocation = Gtk.Allocation ();
            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;
            _switcher.allocate_size (allocation, baseline);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (_reveal)
                base.snapshot (snapshot);
        }
    }
}
