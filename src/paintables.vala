namespace Music {

    public class BasePaintable : Object, Gdk.Paintable {
        protected Gdk.Paintable? _paintable = null;

        public BasePaintable (Gdk.Paintable? paintable = null) {
            _paintable = paintable;
        }

        public Gdk.Paintable? paintable {
            get {
                return _paintable;
            }
            set {
                on_change (_paintable, value);
            }
        }

        public virtual Gdk.Paintable get_current_image () {
            return _paintable?.get_current_image () ?? this;
        }

        public virtual Gdk.PaintableFlags get_flags () {
            return _paintable?.get_flags () ?? 0;
        }

        public virtual int get_intrinsic_width () {
            return _paintable?.get_intrinsic_width () ?? 0;
        }

        public virtual int get_intrinsic_height () {
            return _paintable?.get_intrinsic_height () ?? 0;
        }

        public void snapshot (Gdk.Snapshot shot, double width, double height) {
            on_snapshot (shot as Gtk.Snapshot, width, height);
        }

        protected virtual void on_change (Gdk.Paintable? previous, Gdk.Paintable? paintable) {
            _paintable = paintable;
        }

        protected virtual void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            _paintable?.snapshot (snapshot, width, height);
        }
    }

    public class RoundPaintable : BasePaintable {
        private float _radius = 0;
        private bool _shadow = false;

        public RoundPaintable (Gdk.Paintable? paintable = null, float radius = 0, bool shadow = false) {
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
            }
        }

        public bool shadow {
            get {
                return _shadow;
            }
            set {
                _shadow = value;
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var rect = Graphene.Rect().init(0, 0, (float) width, (float) height);
            var rounded = Gsk.RoundedRect ().init_from_rect (rect, _radius);

            if (_radius > 0) {
                snapshot.push_rounded_clip (rounded);
            }

            base.on_snapshot (snapshot, width, height);

            if (_radius > 0) {
                snapshot.pop ();
            }
            if (_shadow) {
                var color = Gdk.RGBA ();
                color.red = color.green = color.blue = 0.2f;
                color.alpha = 0.2f;
                snapshot.append_outset_shadow (rounded, color, _radius * 0.5f, _radius * 0.5f, _radius * 0.2f, _radius);
            }
        }
    }

    public class CoverPaintable : BasePaintable {
        public CoverPaintable (Gdk.Paintable? paintable = null) {
            base (paintable);
        }

        public override int get_intrinsic_width () {
            return 1;
        }

        public override int get_intrinsic_height () {
            return 1;
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var image_width = base.get_intrinsic_width ();
            var image_height = base.get_intrinsic_height ();
            
            if (image_width != image_height) {
                snapshot.save();
                var ratio = image_width / (double) image_height;
                if (ratio > 1)
                    snapshot.scale ((float) (1 / ratio), 1);
                else
                    snapshot.scale (1, (float) (1 / ratio));
                base.on_snapshot (snapshot, width, height);
                snapshot.restore();
            } else {
                base.on_snapshot (snapshot, width, height);
            }
        }
    }

    public class CrossFadePaintable : BasePaintable {
        private Gdk.Paintable? _previous = null;
        private double _fade = 0;

        public CrossFadePaintable (Gdk.Paintable? paintable = null) {
            _paintable = paintable;
        }

        public double fade {
            get {
                return _fade;
            }
            set {
                _fade = value;
            }
        }

        public Gdk.Paintable? previous {
            get {
                return _previous;
            }
            set {
                _previous = previous;
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
            _paintable = paintable;
        }

        public double scale {
            get {
                return _scale;
            }
            set {
                _scale = value;
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            if (_scale != 1) {
                var point = Graphene.Point ().init (
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

    public class TextPaintable : BasePaintable {
        public static uint32[] colors = {
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

        private string? _text = null;
        private uint _color = 0;

        public TextPaintable (string? text = null) {
            this.text = text;
        }

        public string? text {
            get {
                return _text;
            }
            set {
                _text = value ?? "";
                _color = colors[str_hash (_text) % colors.length];
            }
        }

        public override int get_intrinsic_width () {
            return 1;
        }

        public override int get_intrinsic_height () {
            return 1;
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var red = ((_color >> 16) & 0xff) / 255f;
            var green = ((_color >> 8) & 0xff) / 255f;
            var blue = (_color & 0xff) / 255f;
            var rect = Graphene.Rect ().init(0, 0, (float) width, (float) height);
            var ctx = snapshot.append_cairo (rect);
            ctx.select_font_face ("Serif", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            ctx.set_antialias (Cairo.Antialias.BEST);
            ctx.set_source_rgba (red, green, blue, 0.4f);
            ctx.set_font_size (height * 0.5);
            ctx.move_to (0, height);
            ctx.show_text (_text);
            ctx.paint ();
        }
    }

    public static Gdk.Texture create_blur_texture (Gtk.Widget widget, Gdk.Paintable paintable, int width = 128, int height = 128, double blur = 80) {
        var snapshot = new Gtk.Snapshot ();
        snapshot.push_blur (blur);
        paintable.snapshot (snapshot, width, height);
        snapshot.pop ();
        // Render to a new texture
        var node = snapshot.free_to_node ();
        var rect = Graphene.Rect ().init (0, 0, width, height);
        return widget.get_native ().get_renderer ().render_texture (node, rect);
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