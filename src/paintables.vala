namespace Music {

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
        private float _radius = 0;
        private float _shadow = 0;

        public RoundPaintable (Gdk.Paintable? paintable = null, float radius = 0, float shadow = 0) {
            base (paintable);
            _radius = radius;
            _shadow = shadow;
        }

        public float radius {
            get {
                return _radius;
            }
            set {
                _radius = value;
                queue_draw ();
            }
        }

        public float shadow {
            get {
                return _shadow;
            }
            set {
                _shadow = value;
                queue_draw ();
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var rect = (!)Graphene.Rect ().init (0, 0, (float) width, (float) height);
            var rounded = (!)Gsk.RoundedRect ().init_from_rect (rect, _radius);

            if (_radius > 0) {
                snapshot.push_rounded_clip (rounded);
            }

            base.on_snapshot (snapshot, width, height);

            if (_radius > 0) {
                snapshot.pop ();
            }

            if (_shadow > 0) {
                var color = Gdk.RGBA ();
                color.red = color.green = color.blue = 0.2f;
                color.alpha = 0.2f;
                snapshot.append_outset_shadow (rounded, color, _shadow, _shadow, _shadow * 0.5f, _radius);
            }
        }
    }

    public class CoverPaintable : BasePaintable {
        public CoverPaintable (Gdk.Paintable? paintable = null) {
            base (paintable);
        }

        public override double get_intrinsic_aspect_ratio () {
            return 1;
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var image_width = base.get_intrinsic_width ();
            var image_height = base.get_intrinsic_height ();
            if (image_width != image_height) {
                snapshot.save ();
                var ratio = image_width / (float) image_height;
                if (ratio > 1)
                    snapshot.scale (ratio, 1);
                else
                    snapshot.scale (1, 1 / ratio);
                base.on_snapshot (snapshot, width, height);
                snapshot.restore ();
            } else {
                base.on_snapshot (snapshot, width, height);
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
            if (_fade > 0) {
                snapshot.push_opacity (_fade);
                _previous?.snapshot (snapshot, width, height);
                snapshot.pop ();
                snapshot.push_opacity (1 - _fade);
            }
            base.on_snapshot (snapshot, width, height);
            if (_fade > 0) {
                snapshot.pop ();
            }
            //  print ("fade: %g\n", _fade);
        }
    }

    public class ScalePaintable : BasePaintable {
        private double _scale = 1;

        public ScalePaintable (Gdk.Paintable? paintable = null) {
            base (paintable);
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
            if (_scale != 1) {
                var point = (!)Graphene.Point ().init (
                                (float) (width * (1 - _scale) * 0.5),
                                (float) (height * (1 - _scale) * 0.5));
                snapshot.save ();
                snapshot.translate (point);
                snapshot.scale ((float) _scale, (float) _scale);
            }
            base.on_snapshot (snapshot, width, height);
            if (_scale != 1) {
                snapshot.restore ();
            }
            //  print ("scale: %g\n", _scale);
        }
    }

    public const uint32[] BACKGROUND_COLORS = {
        0x83b6ec, // blue
        0x7ad9f1, // cyan
        0xb5e98a, // lime
        0xf8e359, // yellow
        0xffcb62, // gold
        0xffa95a, // orange
        0xf78773, // raspberry
        0x8de6b1, // green
        0xe973ab, // magenta
        0xcb78d4, // purple
        0x9e91e8, // violet
        0xe3cf9c, // beige
        0xbe916d, // brown
        0xc0bfbc, // gray
    };

    public static Gdk.Paintable? create_text_paintable (Pango.Context context, string text, int width = 128, int height = 128, uint color = 0) {
        if (color == 0)
            color = BACKGROUND_COLORS[str_hash (text) % BACKGROUND_COLORS.length];

        var c = Gdk.RGBA ();
        c.red = ((color >> 16) & 0xff) / 255f;
        c.green = ((color >> 8) & 0xff) / 255f;
        c.blue = (color & 0xff) / 255f;
        c.alpha = 1;

        var rect = (!)Graphene.Rect ().init (0, 0, (float) width, (float) height);
        var snapshot = new Gtk.Snapshot ();
        snapshot.append_color (c, rect);

        var c2 = Gdk.RGBA ();
        c2.red = c2.green = c2.blue = 0;
        c2.alpha = 0.25f;

        var font_size = height * 0.45;
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
        snapshot.append_layout (layout, c2);
        pt.y = - pt.y;
        snapshot.translate (pt);

        return snapshot.free_to_paintable (rect.size);
    }

    public static Gdk.Texture? create_blur_texture (Gtk.Widget widget, Gdk.Paintable paintable, int width = 128, int height = 128, double blur = 80) {
        var snapshot = new Gtk.Snapshot ();
        snapshot.push_blur (blur);
        paintable.snapshot (snapshot, width, height);
        snapshot.pop ();
        // Render to a new texture
        var node = snapshot.free_to_node ();
        if (node is Gsk.RenderNode) {
            var rect = Graphene.Rect ().init (0, 0, width, height);
            return widget.get_native ()?.get_renderer ()?.render_texture ((!)node, rect);
        }
        return null;
    }

    public static void draw_gray_linear_gradient_line (Gtk.Snapshot snapshot, Graphene.Rect rect) {
        var color = Gdk.RGBA ();
        var color2 = Gdk.RGBA ();
        color.red = color.green = color.blue = color.alpha = 0;
        color2.red = color2.green = color2.blue = color2.alpha = 0.5f;
        Gsk.ColorStop[] stops = { { 0, color }, { 0.5f, color2 }, { 1, color } };
        snapshot.append_linear_gradient (rect, rect.get_top_left (),
            rect.get_bottom_right (), stops);
    }
}