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

        public RoundPaintable (float radius, Gdk.Paintable? paintable = null) {
            base (paintable);
            _radius = radius;
        }

        public float radius {
            get {
                return _radius;
            }
            set {
                _radius = value;
            }
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var rect = Graphene.Rect().init(0, 0, (float) width, (float) height);

            if (_radius > 0) {
                var rounded = Gsk.RoundedRect ().init_from_rect (rect, _radius);
                snapshot.push_rounded_clip (rounded);
            }

            base.on_snapshot (snapshot, width, height);

            if (_radius > 0) {
                snapshot.pop ();
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
            //  stdout.printf ("fade: %g\n", _fade);
        }
    }

    public class TextPaintable : BasePaintable {
        public static uint32[] colors = {
            0x83b6ec, // blue
            0x7ad9f1, // cyan
            0x8de6b1, // green
            0xb5e98a, // lime
            0xf8e359, // yellow
            0xffcb62, // gold
            0xffa95a, // orange
            0xf78773, // raspberry
            0xe973ab, // magenta
            0xcb78d4, // purple
            0x9e91e8, // violet
            0xe3cf9c, // beige
            0xbe916d, // brown
            0xc0bfbc, // gray
        };

        private string? _text = null;

        public TextPaintable (string? text = null) {
            _text = text;
        }

        public string? text {
            get {
                return _text;
            }
            set {
                _text = value;
            }
        }

        public override int get_intrinsic_width () {
            return 1;
        }

        public override int get_intrinsic_height () {
            return 1;
        }

        protected override void on_snapshot (Gtk.Snapshot snapshot, double width, double height) {
            var str = _text ?? "";
            var color = colors[str_hash (str) % colors.length];
            var rgb = Gdk.RGBA ();
            rgb.parse (color.to_string ("#60%x"));

            var rect = Graphene.Rect().init(0, 0, (float) width, (float) height);
            var ctx = snapshot.append_cairo (rect);
            ctx.select_font_face ("Serif", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            ctx.set_antialias (Cairo.Antialias.BEST);
            ctx.set_source_rgba (rgb.red, rgb.green, rgb.blue, rgb.alpha);
            ctx.set_font_size (height * 0.5);
            ctx.move_to (0, height);
            ctx.show_text (str);
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
        // Rasterization to avoid color gradations
        //  var stride = width * 4;
        //  var data = new uint8[stride * height];
        //  texture.download (data, stride); // CAIRO_FORMAT_ARGB32
        //  // Swap R and B
        //  var p = 0;
        //  for (int j = 0; j < height; j++) {
        //      var saved = p;
        //      for (int i = 0; i < width; i++) {
        //          var b = data[p];
        //          data[p] = data[p + 2];
        //          data[p + 2] = b;
        //          p += 4;
        //      }
        //      p = saved + stride;
        //  }
        //  var pixbuf = new Gdk.Pixbuf.from_data (data, Gdk.Colorspace.RGB, true, 8, width, height, stride);
        //  return Gdk.Texture.for_pixbuf (pixbuf);
    }
}