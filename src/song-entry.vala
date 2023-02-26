namespace Music {

    public class SongEntry : Gtk.Box {

        private Gtk.Image _cover = new Gtk.Image ();
        private Gtk.Label _title = new Gtk.Label (null);
        private Gtk.Label _subtitle = new Gtk.Label (null);
        private Gtk.Image _playing = new Gtk.Image ();
        private CoverPaintable _paintable = new CoverPaintable ();
        private Song? _song = null;

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

            var long_press = new Gtk.GestureLongPress ();
            long_press.pressed.connect (show_popover);
            var right_click = new Gtk.GestureClick ();
            right_click.button = Gdk.BUTTON_SECONDARY;
            right_click.pressed.connect ((n, x, y) => show_popover (x, y));
            add_controller (long_press);
            add_controller (right_click);
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
            _song = song;
            switch (sort) {
                case SortMode.ALBUM:
                    _title.label = song.album;
                    _subtitle.label = (0 < song.track < int.MAX) ? @"$(song.track). $(song.title)" : song.title;
                    break;

                case SortMode.ARTIST:
                    _title.label = song.artist;
                    _subtitle.label = song.title;
                    break;

                case SortMode.RECENT:
                    var date = new DateTime.from_unix_local (song.modified_time);
                    _title.label = song.title;
                    _subtitle.label = date.format ("%x %H:%M");
                    break;

                default:
                    _title.label = song.title;
                    _subtitle.label = song.artist;
                    break;
            }
        }

        private void show_popover (double x, double y) {
            var app = (Application) GLib.Application.get_default ();
            var song = _song;
            app.popover_song = song;

            var rect = Gdk.Rectangle ();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = rect.height = 0;

            var menu = new Menu ();
            menu.append (_("Move to Next"), ACTION_APP + ACTION_MOVE_TO_NEXT);
            menu.append (_("Show Album"), ACTION_APP + ACTION_SHOW_ALBUM);
            menu.append (_("Show Artist"), ACTION_APP + ACTION_SHOW_ARTIST);
            menu.append (_("_Show In Files"), ACTION_APP + ACTION_OPENDIR);

            var popover = new Gtk.PopoverMenu.from_model (menu);
            popover.autohide = true;
            popover.halign = Gtk.Align.START;
            popover.has_arrow = false;
            popover.pointing_to = rect;
            popover.set_parent (this);
            popover.closed.connect (() => {
                Idle.add (() => {
                    if (app.popover_song == song)
                        app.popover_song = null;
                    return false;
                });
            });
            popover.popup ();
        }
    }
}
