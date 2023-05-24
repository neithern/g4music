namespace G4 {

    public class PeakBar : Gtk.Box {
        private unichar[] _chars = new unichar[2] { '=', 0 };
        private long _char_count = 1;
        private Pango.FontDescription _font = new Pango.FontDescription ();
        private Pango.Rectangle _ink_rect;
        private Pango.Rectangle _logic_rect;
        private StringBuilder _sbuilder = new StringBuilder ();
        private double _value = 0;
        private Pango.Layout _layout;

        public PeakBar () {
            _layout = create_pango_layout (null);
            _layout.set_font_description (_font);
            _layout.set_alignment (get_direction () == Gtk.TextDirection.RTL ? Pango.Alignment.RIGHT : Pango.Alignment.LEFT);
        }

        public Pango.Alignment align {
            get {
                return _layout.get_alignment ();
            }
            set {
                _layout.set_alignment (value);
                queue_draw ();
            }
        }

        public string characters {
            get {
                return ((string32) _chars).to_string () ?? "";
            }
            set {
                var count = value.char_count ();
                _chars = new unichar[count + 1];
                _char_count = 0;
                var next = 0;
                unichar c = 0;
                while (value.get_next_char (ref next, out c)) {
                    if (!c.ismark ())
                        _chars[_char_count++] = c;
                }
                _chars[_char_count] = 0;
                var text = ((string32) _chars).to_string () ?? "";
                _layout.set_text (text, text.length);
                _layout.get_pixel_extents (out _ink_rect, out _logic_rect);
                queue_draw ();
            }
        }

        public void set_peak (double value) {
            if (_value != value) {
                _value = value;
                queue_draw ();
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = get_width ();
            var height = get_height ();
            _font.set_absolute_size (height * Pango.SCALE);
            _layout.set_width (width * Pango.SCALE);
            _layout.set_height (height * Pango.SCALE);

            var center = _layout.get_alignment () == Pango.Alignment.CENTER;
            var dcount = width * _value / int.max (_logic_rect.width, 1);
            var count = (long) (dcount + 0.5);
            if (center && _char_count > 0 && _char_count <= 2)
                count = count / _char_count * _char_count;

            _sbuilder.truncate ();
            if (count <= _char_count) {
                for (var i = 0; i < _char_count; i++)
                    _sbuilder.append_unichar (_chars[i]);
            } else if (_char_count > 0) {
                var half_count = count / 2;
                var char1 = _chars[_char_count >= 3 ? 1 : 0];
                var char2 = _chars[_char_count >= 3 ? _char_count - 2 : _char_count - 1];
                _sbuilder.append_unichar (_chars[0]);
                for (var i = 1; i < count - 1; i++)
                    _sbuilder.append_unichar (i < half_count ? char1 : char2);
                _sbuilder.append_unichar (_chars[_char_count - 1]);
            }
            unowned var text = _sbuilder.str;
            _layout.set_text (text, text.length);

#if GTK_4_10
            var color = get_color ();
#else
            var color = get_style_context ().get_color ();
#endif
            if (count <= _char_count)
                color.alpha = (float) double.min (dcount, 1);

            var pt = Graphene.Point ();
            pt.x = 0;
            pt.y = - _ink_rect.y + (height - _ink_rect.height) * 0.5f;
            snapshot.translate (pt);
            snapshot.append_layout (_layout, color);
            pt.y = - pt.y;
            snapshot.translate (pt);
        }
    }
}
