namespace Music {

    public class SongEntry : Gtk.Box {

        private Gtk.Image _cover = new Gtk.Image ();
        private Gtk.Label _title = new Gtk.Label (null);
        private Gtk.Label _subtitle = new Gtk.Label (null);
        private Gtk.Image _playing = new Gtk.Image ();
        private CoverPaintable _paintable = new CoverPaintable ();

        public SongEntry () {
            margin_top = 4;
            margin_bottom = 4;

            _cover.pixel_size = 48;
            _cover.paintable = new RoundPaintable (_paintable, 5);
            _paintable.queue_draw.connect (_cover.queue_draw);
            append (_cover);

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            vbox.hexpand = true;
            vbox.margin_start = 16;
            vbox.margin_end = 4;
            vbox.append (_title);
            vbox.append (_subtitle);
            append (vbox);

            _title.halign = Gtk.Align.START;
            _title.margin_top = 4;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.add_css_class ("caption-heading");

            _subtitle.halign = Gtk.Align.START;
            _subtitle.valign = Gtk.Align.CENTER;
            _subtitle.ellipsize = Pango.EllipsizeMode.END;
            _subtitle.add_css_class ("caption");
            _subtitle.add_css_class ("dim-label");

            _playing.valign = Gtk.Align.CENTER;
            _playing.icon_name = "media-playback-start-symbolic";
            _playing.pixel_size = 12;
            _playing.add_css_class ("dim-label");
            append (_playing);
        }

        public Gdk.Paintable? cover {
            set {
                _paintable.paintable = value;
            }
        }

        public bool playing {
            set {
                _playing.visible = value;
            }
        }

        public void update (Song song, SortMode sort) {
            switch (sort) {
                case SortMode.ALBUM:
                    _title.label = song.album;
                    _subtitle.label = (0 < song.track < int.MAX) ? @"$(song.track). $(song.title)" : song.title;
                    break;

                case SortMode.ARTIST:
                    _title.label = song.artist;
                    _subtitle.label = song.title;
                    break;

                default:
                    _title.label = song.title;
                    _subtitle.label = song.artist;
                    break;
            }
        }
    }
}