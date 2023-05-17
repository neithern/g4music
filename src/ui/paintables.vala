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
            var image_width = (float) get_intrinsic_width ();
            var image_height = (float) get_intrinsic_height ();
            if (image_width != image_height) {
                var point = Graphene.Point ();
                var ratio = image_width / image_height;
                snapshot.save ();
                if (ratio > 1) {
                    snapshot.scale (ratio, 1);
                    point.x = (float) (width - width * ratio) * 0.5f;
                    point.y = 0;
                } else {
                    snapshot.scale (1, 1 / ratio);
                    point.x = 0;
                    point.y = (float) (height - height / ratio) * 0.5f;
                }
                snapshot.translate (point);
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
        0xffcfe1f5u, 0xff83b6ecu, 0xff337fdcu,  // blue
        0xffcaeaf2u, 0xff7ad9f1u, 0xff0f9ac8u,  // cyan
        0xffcef8d8u, 0xff8de6b1u, 0xff29ae74u,  // green
        0xffe6f9d7u, 0xffb5e98au, 0xff6ab85bu,  // lime
        0xfff9f4e1u, 0xfff8e359u, 0xffd29d09u,  // yellow
        0xffffead1u, 0xffffcb62u, 0xffd68400u,  // gold
        0xffffe5c5u, 0xffffa95au, 0xffed5b00u,  // orange
        0xfff8d2ceu, 0xfff78773u, 0xffe62d42u,  // raspberry
        0xfffac7deu, 0xffe973abu, 0xffe33b6au,  // magenta
        0xffe7c2e8u, 0xffcb78d4u, 0xff9945b5u,  // purple
        0xffd5d2f5u, 0xff9e91e8u, 0xff7a59cau,  // violet
        0xfff2eadeu, 0xffe3cf9cu, 0xffb08952u,  // beige
        0xffe5d6cau, 0xffbe916du, 0xff785336u,  // brown
        0xffd8d7d3u, 0xffc0bfbcu, 0xff6e6d71u,  // gray
    };

    public static Gdk.RGBA color_from_uint (uint color) {
        var c = Gdk.RGBA ();
        c.alpha = ((color >> 24) & 0xff) / 255f;
        c.red = ((color >> 16) & 0xff) / 255f;
        c.green = ((color >> 8) & 0xff) / 255f;
        c.blue = (color & 0xff) / 255f;
        return c;
    }

    public static Gdk.Paintable? create_text_paintable (Pango.Context context, string text, int width, int height, uint color_index = 0x7fffffff) {
        var rect = (!)Graphene.Rect ().init (0, 0,  width, height);
        var snapshot = new Gtk.Snapshot ();

        var c = Gdk.RGBA ();
        if (color_index < BACKGROUND_COLORS.length / 3) {
            c = color_from_uint (BACKGROUND_COLORS[color_index * 3]);
            var c1 = color_from_uint (BACKGROUND_COLORS[color_index * 3 + 1]);
            var c2 = color_from_uint (BACKGROUND_COLORS[color_index * 3 + 2]);
            Gsk.ColorStop[] stops = { { 0, c1 }, { 0.5f, c2 }, { 1, c1 } };
            snapshot.append_linear_gradient (rect, rect.get_top_left (), rect.get_bottom_right (), stops);
        } else {
            c.alpha = 1f;
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

    public static Gdk.Paintable? create_blur_paintable (Gtk.Widget widget, Gdk.Paintable paintable,
                                int width = 128, int height = 128, double blur = 80, double opacity = 0.25) {
        var snapshot = new Gtk.Snapshot ();
        snapshot.push_blur (blur);
        snapshot.push_opacity (opacity);
        paintable.snapshot (snapshot, width, height);
        snapshot.pop ();
        snapshot.pop ();

        Gdk.Paintable? result = null;
        var rect = Graphene.Rect ().init (0, 0, width, height);
        var node = snapshot.free_to_node ();
        if (node is Gsk.RenderNode) {
            result = widget.get_native ()?.get_renderer ()?.render_texture ((!)node, rect);
        }
        return result ?? snapshot.free_to_paintable (rect?.size);
    }
}
