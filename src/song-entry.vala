namespace Music {

    public class SongEntry : Gtk.Box {

        private Gtk.Image _cover = new Gtk.Image ();
        private Gtk.Label _artist = new Gtk.Label (null);
        private Gtk.Label _title = new Gtk.Label (null);
        private Gtk.Image _playing = new Gtk.Image ();
        private CoverPaintable _paintable = new CoverPaintable ();

        public SongEntry () {
            margin_top = 4;
            margin_bottom = 4;

            _cover.pixel_size = 48;
            _cover.paintable = new RoundPaintable (5, _paintable);
            append (_cover);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.hexpand = true;
            box.margin_start = 16;
            box.margin_end = 8;
            box.append (_title);
            box.append (_artist);
            append (box);

            _title.halign = Gtk.Align.START;
            _title.margin_top = 4;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.add_css_class ("caption-heading");

            _artist.halign = Gtk.Align.START;
            _artist.margin_top = 8;
            _artist.ellipsize = Pango.EllipsizeMode.END;
            _artist.add_css_class ("caption");
            _artist.add_css_class ("dim-label");

            _playing.valign = Gtk.Align.CENTER;
            _playing.margin_start = 8;
            _playing.icon_name = "media-playback-start-symbolic";
            _playing.pixel_size = 12;
            _playing.add_css_class ("dim-label");
            append (_playing);
        }

        public string artist {
            set {
                _artist.label = value;
            }
        }

        public string title {
            set {
                _title.label = value;
            }
        }

        public bool playing {
            set {
                _playing.visible = value;
            }
        }

        public Gdk.Paintable? cover {
            set {
                _paintable.paintable = value;
                _cover.queue_draw ();
            }
        }
    }
}