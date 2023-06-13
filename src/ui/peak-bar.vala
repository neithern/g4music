namespace G4 {

    public class PeakBar : Gtk.Box {
        private unichar[] _chars = { '=', 0 };
        private int[] _char_widths = { 10 };
        private int _char_count = 1;
        private Pango.Layout _layout;
        private StringBuilder _sbuilder = new StringBuilder ();
        private double _value = 0;

        public PeakBar () {
            _layout = create_pango_layout (null);
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
                    if (!c.ismark ()) {
                        Pango.Rectangle ink_rect, logic_rect;
                        var text = c.to_string ();
                        _layout.set_text (text, text.length);
                        _layout.get_pixel_extents (out ink_rect, out logic_rect);
                        _chars[_char_count] = c;
                        _char_widths[_char_count] = logic_rect.width;
                        _char_count++;
                    }
                }
                _chars[_char_count] = 0;
                _char_widths[_char_count] = 0;
                queue_draw ();
            }
        }

        public void set_peak (double value) {
            if (value > 1) value = 1;
            if (_value != value) {
                _value = value;
                queue_draw ();
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = get_width ();
            var height = get_height ();
            var center = _layout.get_alignment () == Pango.Alignment.CENTER;
            var value_width = _value * width;
            _layout.set_width (-1);
            _layout.set_height (height * Pango.SCALE);

            var char_count = 0;
            var char_width = 0;
            _sbuilder.truncate ();
            if (_char_count > 0) {
                var last = _char_count - 1;
                _sbuilder.append_unichar (_chars[0]);
                char_count++;
                char_width += _char_widths[0];
                if (_char_count >= 2) {
                    char_count++;
                    char_width += _char_widths[last];
                }
                var char1 = _chars[_char_count >= 3 ? 1 : 0];
                var cx1 = _char_widths[_char_count >= 3 ? 1 : 0];
                var char2 = _chars[_char_count >= 3 ? _char_count - 2 : _char_count - 1];
                var cx2 = _char_widths[_char_count >= 3 ? _char_count - 2 : _char_count - 1];
                if (char1 == char2) {
                    var count = (int) ((value_width - char_width) / cx1 + 0.5);
                    if (center && (count + _char_count) % 2 == 0)
                        count--;
                    for (var i = 0; i < count; i++) {
                        _sbuilder.append_unichar (char1);
                        char_count++;
                        char_width += cx1;
                    }
                } else {
                    var count = (int) ((value_width - char_width) / (cx1 + cx2) + 0.5);
                    if (center && (count + _char_count) % 2 == 0)
                        count--;
                    for (var i = 0; i < count; i++) {
                        _sbuilder.append_unichar (char1);
                        char_count++;
                        char_width += cx1;
                    }
                    for (var j = 0; j < count; j++) {
                        _sbuilder.append_unichar (char2);
                        char_count++;
                        char_width += cx2;
                    }
                }
                if (_char_count >= 2) {
                    _sbuilder.append_unichar (_chars[last]);
                }
            }

#if GTK_4_10
            var color = get_color ();
#else
            var color = get_style_context ().get_color ();
#endif
            var opacity = char_width > value_width ? value_width / char_width : 1;

            Pango.Rectangle ink_rect, logic_rect;
            _layout.set_text (_sbuilder.str, (int) _sbuilder.len);
            _layout.get_pixel_extents (out ink_rect, out logic_rect);
            var pt = Graphene.Point ();
            pt.x = center ? - ink_rect.x + (width - ink_rect.width) * 0.5f : 0;
            pt.y = - ink_rect.y + (height - ink_rect.height) * 0.5f;
            snapshot.translate (pt);
            if (opacity < 1)
                snapshot.push_opacity (opacity);
            snapshot.append_layout (_layout, color);
            if (opacity < 1)
                snapshot.pop ();
            pt.x = - pt.x;
            pt.y = - pt.y;
            snapshot.translate (pt);
        }
    }
}
