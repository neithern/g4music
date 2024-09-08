namespace G4 {

    public class NarrowBar : Gtk.Widget {
        private Gtk.Widget? _child = null;
        private int _minimum_width = 0;
        private bool _reveal = true;

        public Gtk.Widget? child {
            get {
                return _child;
            }
            set {
                _child?.unparent ();
                _child = value;
                _child?.set_parent (this);
                queue_allocate ();
            }
        }

        public bool reveal {
            get {
                return _reveal;
            }
            set {
                _reveal = value;
                queue_allocate ();
            }
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            if (_child != null) {
                ((!)_child).measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            } else {
                minimum = natural = minimum_baseline = natural_baseline = 0;
            }
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                _minimum_width = minimum;
                minimum = _minimum_width / 2;
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            var wide = width >= _minimum_width;
            if (_reveal != wide) {
                _reveal = wide;
                notify_property ("reveal");

                if (wide && _child?.parent == null) {
                    _child?.set_parent (this);
                } else if (!wide && _child?.parent != null) {
                    _child?.unparent ();
                }
            }

            if (_child != null) {
                var allocation = Gtk.Allocation ();
                allocation.x = 0;
                allocation.y = 0;
                allocation.width = width;
                allocation.height = height;
                ((!)_child).allocate_size (allocation, baseline);
            }
        }
    }
}
