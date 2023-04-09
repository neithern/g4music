namespace G4 {

    public class VolumeButton : Gtk.ScaleButton, Gtk.Accessible, Gtk.AccessibleRange, Gtk.Buildable, Gtk.ConstraintTarget, Gtk.Orientable {

        public static double EPSILON = 1e-10;

        public static string[] ICONS =
        {
            "audio-volume-muted-symbolic",
            "audio-volume-high-symbolic",
            "audio-volume-low-symbolic",
            "audio-volume-medium-symbolic",
        };

        construct {
            var adj = adjustment;
            adj.lower = 0;
            adj.upper = 1.0;
            adj.page_increment = 0.1;
            adj.step_increment = 0.1;

            icons = ICONS;
            query_tooltip.connect (on_query_tooltip);
            value_changed.connect (on_value_changed);
            tooltip_text = get_volume_text ();
        }

        private string get_volume_text () {
            var adj = adjustment;
            var value = get_value ();
            var percent = (int) (100 * value / (adj.upper - adj.lower) + 0.5);
            return "Volume: " + @"$percent%";
        }

        private bool on_query_tooltip (int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
            tooltip.set_text (get_volume_text ());
            return true;
        }

        private void on_value_changed (double value) {
            trigger_tooltip_query ();
        }
    }
}