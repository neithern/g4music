namespace G4 {

    public class BasePaintable : Object, Gdk.Paintable {
        private bool _first_draw = false;
        private Gdk.Paintable? _paintable = null;

        public signal void first_draw ();
        public signal void queue_draw ();

        public BasePaintable (Gdk.Paintable? paintable = null) {
            _paintable = paintable;
        }

        public Gdk.Paintable? paintable {
            get {
                return _paintable;
            }
            set {
                if (_paintable != value) {
                    on_change (_paintable, value);
                    _paintable = value;
                    queue_draw ();
                }
            }
        }

        public virtual Gdk.Paintable get_current_image () {
            return _paintable?.get_current_image () ?? this;
        }

        public virtual Gdk.PaintableFlags get_flags () {
            return _paintable?.get_flags () ?? 0;
        }

        public virtual double get_intrinsic_aspect_ratio () {
            return _paintable?.get_intrinsic_aspect_ratio () ?? 1;
        }

        public virtual int get_intrinsic_width () {
            return _paintable?.get_intrinsic_width () ?? 1;
        }

        public virtual int get_intrinsic_height () {
            return _paintable?.get_intrinsic_height () ?? 1;
        }

        public void snapshot (Gdk.Snapshot shot, double width, double height) {
            if (_first_draw) {
                _first_draw = false;
                first_draw ();
            }
            on_snapshot ((!)(shot as Gtk.Snapshot), width, height);
        }

        protected virtual void on_change (Gdk.Paintable? previous, Gdk.Paintable? paintable) {
            _first_draw = previous != paintable;
        }

        protected virtual void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            _paintable?.snapshot (snapshot, width, height);
        }
    }

    public class RoundPaintable : BasePaintable {
        private double _ratio = 0;

        public RoundPaintable (Gdk.Paintable? paintable = null, double ratio = 0.1) {
            base (paintable);
            _ratio = ratio;
        }

        public double ratio {
            get {
                return _ratio;
            }
            set {
                if (_ratio != value) {
                    _ratio = value;
                    queue_draw ();
                }
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var rect = Graphene.Rect ();
            var rounded = Gsk.RoundedRect ();
            var size = (float) double.min (width, height);
            var circle = _ratio >= 0.5;
            if (circle) // Force clip to circle
                rect.init ((float) (width - size) * 0.5f, (float) (height - size) * 0.5f, size, size);
            else
                rect.init (0, 0, (float) width, (float) height);

            var radius = (float) (_ratio * size);
            rounded.init_from_rect (rect, radius);

            var saved = false;
            if (radius > 0) {
                if (circle && width != height) {
                    float scale = (float) double.max (width, height) / size;
                    saved = true;
                    snapshot.save ();
                    compute_matrix (snapshot, width, height, 0, scale);
                }
                snapshot.push_rounded_clip (rounded);
            }
            base.on_snapshot (snapshot, width, height);
            if (radius > 0) {
                snapshot.pop ();
            }
            if (saved) {
                snapshot.restore ();
            }
        }
    }

    public class CrossFadePaintable : BasePaintable {
        private Gdk.Paintable? _previous = null;
        private double _fade = 0;

        public CrossFadePaintable (Gdk.Paintable? paintable = null) {
            base (paintable);
        }

        public double fade {
            get {
                return _fade;
            }
            set {
                if (_fade != value) {
                    _fade = value;
                    queue_draw ();
                }
            }
        }

        public Gdk.Paintable? previous {
            get {
                return _previous;
            }
            set {
                if (_previous != value) {
                    _previous = value;
                    queue_draw ();
                }
            }
        }

        protected override void on_change (Gdk.Paintable? previous, Gdk.Paintable? paintable) {
            _previous = previous;
            base.on_change (previous, paintable);
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            if (_fade > 0 && _previous != null) {
                var width2 = width;
                var height2 = height;
                var prev = (!)_previous;
                var ratio2 = prev.get_intrinsic_aspect_ratio ();
                var point = Graphene.Point ();
                var different = ratio2 != get_intrinsic_aspect_ratio ();
                if (different) {
                    var max_side = double.max (width, height);
                    if (ratio2 < 1) {
                        height2 = max_side;
                        width2 = height2 * ratio2;
                    } else {
                        width2 = max_side;
                        height2 = width2 / ratio2;
                    }
                    point.x = (float) (width - width2) * 0.5f;
                    point.y = (float) (height - height2) * 0.5f;
                    snapshot.translate (point);
                }
                snapshot.push_opacity (_fade);
                prev.snapshot (snapshot, width2, height2);
                snapshot.pop ();
                if (different) {
                    point.x = - point.x;
                    point.y = - point.y;
                    snapshot.translate (point);
                }
            }
            if (_fade > 0) {
                snapshot.push_opacity (1 - _fade);
            }
            base.on_snapshot (snapshot, width, height);
            if (_fade > 0) {
                snapshot.pop ();
            }
            //  print ("fade: %g\n", _fade);
        }
    }

    public class MatrixPaintable : BasePaintable {
        private double _rotation = 0;
        private double _scale = 1;

        public MatrixPaintable (Gdk.Paintable? paintable = null) {
            base (paintable);
        }

        public double rotation {
            get {
                return _rotation;
            }
            set {
                if (_rotation != value) {
                    _rotation = value;
                    queue_draw ();
                }
            }
        }

        public double scale {
            get {
                return _scale;
            }
            set {
                if (_scale != value) {
                    _scale = value;
                    queue_draw ();
                }
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var saved = _rotation != 0 || _scale != 1;
            if (saved) {
                snapshot.save ();
                compute_matrix (snapshot, width, height, _rotation, _scale);
            }
            base.on_snapshot (snapshot, width, height);
            if (saved) {
                snapshot.restore ();
            }
        }
    }

    public void compute_matrix (Gtk.Snapshot snapshot, double width, double height,
                                double rotation = 0, double scale = 1) {
        var point = Graphene.Point ();
        point.init ((float) (width * 0.5), (float) (height * 0.5));
        snapshot.translate (point);
        if (rotation != 0)
            snapshot.rotate ((float) rotation);
        if (scale != 1)
            snapshot.scale ((float) scale, (float) scale);
        point.init (- point.x, - point.y);
        snapshot.translate (point);
    }

    public const uint32[] BACKGROUND_COLORS = {
        0xff83b6ecu, 0xff337fdcu,  // blue
        0xff7ad9f1u, 0xff0f9ac8u,  // cyan
        0xff8de6b1u, 0xff29ae74u,  // green
        0xffb5e98au, 0xff6ab85bu,  // lime
        0xfff8e359u, 0xffd29d09u,  // yellow
        0xffffcb62u, 0xffd68400u,  // gold
        0xffffa95au, 0xffed5b00u,  // orange
        0xfff78773u, 0xffe62d42u,  // raspberry
        0xffe973abu, 0xffe33b6au,  // magenta
        0xffcb78d4u, 0xff9945b5u,  // purple
        0xff9e91e8u, 0xff7a59cau,  // violet
        0xffe3cf9cu, 0xffb08952u,  // beige
        0xffbe916du, 0xff785336u,  // brown
        0xffc0bfbcu, 0xff6e6d71u,  // gray
    };

    public Gdk.RGBA color_from_uint (uint color) {
        var c = Gdk.RGBA ();
        c.alpha = ((color >> 24) & 0xff) / 255f;
        c.red = ((color >> 16) & 0xff) / 255f;
        c.green = ((color >> 8) & 0xff) / 255f;
        c.blue = (color & 0xff) / 255f;
        return c;
    }

    public Gdk.Paintable? create_blur_paintable (Gtk.Widget widget, Gdk.Paintable paintable,
                                int size, double blur = 80, double opacity = 0.25) {
        var snapshot = new Gtk.Snapshot ();
        snapshot.push_opacity (opacity);
        snapshot.push_blur (blur);
        paintable.snapshot (snapshot, size, size);
        snapshot.pop ();
        snapshot.pop ();

        var rect = Graphene.Rect ();
        rect.init (0, 0, size, size);
        Gdk.Paintable? result = null;
        var node = snapshot.free_to_node ();
        if (node is Gsk.RenderNode) {
            result = widget.get_native ()?.get_renderer ()?.render_texture ((!)node, rect);
        }
        return result ?? snapshot.free_to_paintable (rect.size);
    }

    public Pango.Layout create_center_text_layout (Pango.Context context, string family, int width, int height, double font_size) {
        var font = new Pango.FontDescription ();
        font.set_absolute_size (font_size * Pango.SCALE);
        font.set_family (family);
        font.set_weight (Pango.Weight.BOLD);

        var layout = new Pango.Layout (context);
        layout.set_alignment (Pango.Alignment.CENTER);
        layout.set_font_description (font);
        layout.set_width (width * Pango.SCALE);
        layout.set_height (height * Pango.SCALE);
        layout.set_single_paragraph_mode (true);
        return layout;
    }

    public Gdk.Paintable? create_text_paintable (Pango.Context context, string text, int width, int height, uint color_index = 0x7fffffff) {
        var snapshot = new Gtk.Snapshot ();
        var rect = Graphene.Rect ();
        rect.init (0, 0,  width, height);

        var c = Gdk.RGBA ();
        c.alpha = 1f;
        if (color_index < BACKGROUND_COLORS.length / 2) {
            c.red = c.green = c.blue = 0.9f;
            var c1 = color_from_uint (BACKGROUND_COLORS[color_index * 2]);
            var c2 = color_from_uint (BACKGROUND_COLORS[color_index * 2 + 1]);
            Gsk.ColorStop[] stops = { { 0, c1 }, { 0.5f, c2 }, { 1, c1 } };
            snapshot.append_linear_gradient (rect, rect.get_top_left (), rect.get_bottom_right (), stops);
        } else {
            c.red = c.green = c.blue = 0.5f;
        }

        var ink_rect = Pango.Rectangle ();
        var logic_rect = Pango.Rectangle ();
        var layout = create_center_text_layout (context, "Serif", width, height, height * 0.4);
        layout.set_text (text, text.length);
        layout.get_pixel_extents (out ink_rect, out logic_rect);

        var pt = Graphene.Point ();
        pt.x = 0;
        pt.y = - ink_rect.y + (height - ink_rect.height) * 0.5f;
        snapshot.translate (pt);
        snapshot.append_layout (layout, c);
        pt.y = - pt.y;
        snapshot.translate (pt);
        return snapshot.free_to_paintable (rect.size);
    }

    public unowned string TEXT_SVG_FORMAT = """
<svg width="128" height="128" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="background" x1="0" x2="1" y1="0" y2="1">
            <stop offset="0%" stop-color="#%06x"/>
            <stop offset="50%" stop-color="#%06x"/>
            <stop offset="100%" stop-color="#%06x"/>
        </linearGradient>
    </defs>
    <rect rx="12.8" ry="12.8" width="128" height="128" fill="url(#background)"/>
    <text x="%g" y="%g" fill="#e6e6e6" font-family="Serif" font-size="51.2" font-weight="bold">%s</text>
</svg>
    """;

    public string create_text_svg (Pango.Context context, string text, uint color_index = 0x7fffffff) {
        var rect = Graphene.Rect ();
        var width = 128, height = 128;
        rect.init (0, 0,  width, height);

        uint c1 = 0, c2 = 0;
        if (color_index < BACKGROUND_COLORS.length / 2) {
            c1 = BACKGROUND_COLORS[color_index * 2] & 0x00ffffffu;
            c2 = BACKGROUND_COLORS[color_index * 2 + 1] & 0x00ffffffu;
        }

        var ink_rect = Pango.Rectangle ();
        var logic_rect = Pango.Rectangle ();
        var layout = create_center_text_layout (context, "Serif", width, height, height * 0.4);
        layout.set_text (text, text.length);

        var x = - ink_rect.x + (width - logic_rect.width) * 0.5f;
        var y = - ink_rect.y + (height + logic_rect.height) * 0.5f;
        return TEXT_SVG_FORMAT.printf (c1, c2, c1, x, y, text);
    }

    public Gdk.Paintable? create_widget_paintable (Gtk.Widget widget, ref Graphene.Point point, string? title = null, int max_size = 64) {
        float width = widget.get_width ();
        float height = widget.get_height ();
        var scale = (width > max_size || height > max_size) ? max_size / float.max (width, height) : 1;
        width *= scale;
        height *= scale;
        point.x *= scale;
        point.y *= scale;

        var snapshot = new Gtk.Snapshot ();
        snapshot.scale (scale, scale);
        widget.snapshot (snapshot);
        snapshot.scale (1 / scale, 1 / scale);

        if (title != null) {
            var text = (!)title;
            var ink_rect = Pango.Rectangle ();
            var logic_rect = Pango.Rectangle ();
            var layout = create_center_text_layout (widget.get_pango_context (), "Sans", (int) width, (int) height, height * 0.2);
            layout.set_text (text, text.length);
            layout.get_pixel_extents (out ink_rect, out logic_rect);

            var pt = Graphene.Point ();
            pt.x = - ink_rect.x + (width - logic_rect.width);
            pt.y = (height - logic_rect.height * 0.5f);
            snapshot.translate (pt);

            var rect = Graphene.Rect ();
            rect.init (0, 0, int.max (logic_rect.width, logic_rect.height), logic_rect.height);
            rect.offset ((width - rect.get_width ()) * 0.5f, 0);
            rect.inset (-2, -2);
            var bounds = Gsk.RoundedRect ();
            bounds.init_from_rect (rect, rect.get_height () * 0.5f);
            snapshot.push_rounded_clip (bounds);

            var color = Gdk.RGBA ();
            color.alpha = color.red = 1;
            color.blue = color.green = 0;
            snapshot.append_color (color, rect);
            color.blue = color.green = 1;
            pt.x = 0;
            pt.y = - ink_rect.y + (logic_rect.height - ink_rect.height) * 0.5f;
            snapshot.translate (pt);
            snapshot.append_layout (layout, color);
            snapshot.pop ();
        }
        return snapshot.free_to_paintable (null);
    }

    public void draw_outset_shadow (Gtk.Snapshot snapshot, Graphene.Rect rect, float radius = 5) {
        var color = Gdk.RGBA ();
        color.alpha = 0.2f;
        color.red = color.green = color.blue = 0;
        rect.inset (radius, radius);
        var outline = Gsk.RoundedRect ();
        outline.init_from_rect (rect, radius);
        snapshot.append_outset_shadow (outline, color, 1, 1, 1, float.max (radius - 1, 0));
    }
}
