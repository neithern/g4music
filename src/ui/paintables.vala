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
                on_change (_paintable, value);
                queue_draw ();
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
            _first_draw = _paintable != paintable;
            _paintable = paintable;
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
                _ratio = value;
                queue_draw ();
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var rect = Graphene.Rect ();
            var rounded = Gsk.RoundedRect ();
            var size = (float) double.max (width, height);
            if (_ratio >= 0.5) // Force clip to circle
                rect.init ((float) (width - size) * 0.5f, (float) (height - size) * 0.5f, size, size);
            else
                rect.init (0, 0, (float) width, (float) height);

            var radius = (float) (_ratio * size);
            rounded.init_from_rect (rect, radius);

            if (radius > 0) {
                snapshot.push_rounded_clip (rounded);
            }
            base.on_snapshot (snapshot, width, height);
            if (radius > 0) {
                snapshot.pop ();
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
                _fade = value;
                queue_draw ();
            }
        }

        public Gdk.Paintable? previous {
            get {
                return _previous;
            }
            set {
                _previous = previous;
                queue_draw ();
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
                point.init (0, 0);
                var different = ratio2 != get_intrinsic_aspect_ratio ();
                if (different) {
                    if (ratio2 < 1) {
                        width2 = height2 * ratio2;
                        point.x = (float) (width - width2) * 0.5f;
                    } else {
                        height2 = width2 / ratio2;
                        point.y = (float) (height - height2) * 0.5f;
                    }
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
                _rotation = value;
                queue_draw ();
            }
        }

        public double scale {
            get {
                return _scale;
            }
            set {
                _scale = value;
                queue_draw ();
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            if (_rotation != 0 || _scale != 1) {
                var matrix = Graphene.Matrix ();
                matrix.init_identity ();
                var point = Graphene.Point3D ();
                point.init ((float) (-width * 0.5), (float) (-height * 0.5), 0);
                matrix.translate (point);
                if (_rotation != 0)
                    matrix.rotate_z ((float) _rotation);
                if (_scale != 1)
                    matrix.scale ((float) _scale, (float) _scale, 1);
                point.init ((float) (width * 0.5), (float) (height * 0.5), 0);
                matrix.translate (point);
                snapshot.transform_matrix (matrix);
            }
            base.on_snapshot (snapshot, width, height);
        }
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

        var font_size = height * 0.4;
        var font = new Pango.FontDescription ();
        font.set_absolute_size (font_size * Pango.SCALE);
        font.set_family ("Serif");
        font.set_weight (Pango.Weight.BOLD);

        var layout = new Pango.Layout (context);
        layout.set_alignment (Pango.Alignment.CENTER);
        layout.set_font_description (font);
        layout.set_width (width * Pango.SCALE);
        layout.set_height (height * Pango.SCALE);
        layout.set_single_paragraph_mode (true);

        Pango.Rectangle ink_rect, logic_rect;
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

        var font_size = height * 0.4;
        var font = new Pango.FontDescription ();
        font.set_absolute_size (font_size * Pango.SCALE);
        font.set_family ("Serif");
        font.set_weight (Pango.Weight.BOLD);

        var layout = new Pango.Layout (context);
        layout.set_font_description (font);
        layout.set_width (width * Pango.SCALE);
        layout.set_height (height * Pango.SCALE);
        layout.set_single_paragraph_mode (true);

        Pango.Rectangle ink_rect, logic_rect;
        layout.set_text (text, text.length);
        layout.get_pixel_extents (out ink_rect, out logic_rect);

        var x = - ink_rect.x + (width - logic_rect.width) * 0.5f;
        var y = - ink_rect.y + (height + logic_rect.height) * 0.5f;
        return TEXT_SVG_FORMAT.printf (c1, c2, c1, x, y, text);
    }

    public Gdk.Paintable? create_blur_paintable (Gtk.Widget widget, Gdk.Paintable paintable,
                                int width = 128, int height = 128, double blur = 80, double opacity = 0.25) {
        var snapshot = new Gtk.Snapshot ();
        snapshot.push_blur (blur);
        snapshot.push_opacity (opacity);
        paintable.snapshot (snapshot, width, height);
        snapshot.pop ();
        snapshot.pop ();

        var rect = Graphene.Rect ();
        rect.init (0, 0, width, height);
        Gdk.Paintable? result = null;
        var node = snapshot.free_to_node ();
        if (node is Gsk.RenderNode) {
            result = widget.get_native ()?.get_renderer ()?.render_texture ((!)node, rect);
        }
        return result ?? snapshot.free_to_paintable (rect.size);
    }
}

