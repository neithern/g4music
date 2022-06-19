namespace Music {

    public class PeakBar : Gtk.Box {
        private Gtk.Align _align = Gtk.Align.START;
        private double _value = 0;

        public Gtk.Align align {
            get {
                return _align;
            }
            set {
                _align = value;
                queue_draw ();
            }
        }

        public double peak {
            get {
                return _value;
            }
            set {
                if (_value != value) {
                    _value = value;
                    queue_draw ();
                }
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = get_width ();
            var height = get_height ();
            var rect = (!)Graphene.Rect ().init (0, 0, width, height);
            var ctx = snapshot.append_cairo (rect);

            var style = get_style_context ();
            var color = style.get_color ();
            ctx.set_source_rgba (color.red, color.green, color.blue, color.alpha);
            ctx.set_font_size (height);

            Cairo.TextExtents extents;
            ctx.text_extents ("=", out extents);

            var count = (int) ((width - extents.x_bearing) * _value / (extents.width + extents.x_bearing));
            if (_align == Gtk.Align.CENTER && count % 2 == 0)
                count--;

            var text = count > 0 ? string.nfill (count, '=') : "";
            ctx.text_extents (text, out extents);
            double x = 0;
            switch (_align) {
                case Gtk.Align.CENTER:
                    x = (width - extents.width) * 0.5 - extents.x_bearing;
                    break;
                case Gtk.Align.END:
                    x = width - extents.width;
                    break;
                default:
                    x = 0;
                    break;
            }
            double y = (height - extents.height) * 0.5 - extents.y_bearing;
            ctx.move_to (x, y);
            ctx.show_text (text);
            ctx.paint_with_alpha (0);
        }
    }
}