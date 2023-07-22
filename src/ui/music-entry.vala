namespace G4 {

    public class StableLabel : Gtk.Widget {
        private Gtk.Label _label = new Gtk.Label (null);

        public StableLabel () {
            add_child (new Gtk.Builder (), _label, null);
        }

        ~StableLabel () {
            _label.unparent ();
        }

        public Pango.EllipsizeMode ellipsize {
            get {
                return _label.ellipsize;
            }
            set {
                _label.ellipsize = value;
            }
        }

        public string label {
            get {
                return _label.label;
            }
            set {
                _label.label = value;
            }
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            var vertical = orientation == Gtk.Orientation.VERTICAL;
            _label.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (vertical) {
                // Ensure enough space for different text
                var font_size = _label.get_pango_context ().get_font_description ().get_size () / Pango.SCALE;
                minimum = natural = int.max ((int) (font_size * 1.65), natural);
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            var allocation = Gtk.Allocation ();
            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;
            _label.allocate_size (allocation, baseline);
        }
    }

    public class MusicWidget : Gtk.Box {
        protected Gtk.Image _cover = new Gtk.Image ();
        protected StableLabel _title = new StableLabel ();
        protected StableLabel _subtitle = new StableLabel ();
        protected RoundPaintable _paintable = new RoundPaintable ();

        public ulong first_draw_handler = 0;

        public RoundPaintable cover {
            get {
                return _paintable;
            }
        }

        public Gdk.Paintable? paintable {
            set {
                _paintable.paintable = value;
            }
        }

        public string title {
            set {
                _title.label = value;
            }
        }

        public string subtitle {
            set {
                _subtitle.label = value;
                _subtitle.visible = value.length > 0;
            }
        }

        public void disconnect_first_draw () {
            if (first_draw_handler != 0) {
                _paintable.disconnect (first_draw_handler);
                first_draw_handler = 0;
            }
        }
    }

    public class MusicCell : MusicWidget {
        public MusicCell () {
            orientation = Gtk.Orientation.VERTICAL;

            _cover.margin_start = 8;
            _cover.margin_end = 8;
            _cover.margin_top = 10;
            _cover.margin_bottom = 6;
            _cover.pixel_size = 128;
            _cover.paintable = _paintable;
            _paintable.queue_draw.connect (_cover.queue_draw);
            append (_cover);

            _title.halign = Gtk.Align.CENTER;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.margin_start = 4;
            _title.margin_end = 4;
            _title.margin_bottom = 10;
            _title.add_css_class ("title-leading");
            append (_title);

            width_request = _cover.pixel_size + _cover.margin_start + _cover.margin_end;
        }
    }

    public class MusicEntry : MusicWidget {
        private Gtk.Image _playing = new Gtk.Image ();

        public MusicEntry (bool compact = true) {
            var cover_margin = compact ? 3 : 4;
            var cover_size = compact ? 36 : 48;
            _cover.margin_top = cover_margin;
            _cover.margin_bottom = cover_margin;
            _cover.margin_start = 4;
            _cover.pixel_size = cover_size;
            _cover.paintable = _paintable;
            _paintable.queue_draw.connect (_cover.queue_draw);
            append (_cover);

            var spacing = compact ? 2 : 6;
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, spacing);
            vbox.hexpand = true;
            vbox.valign = Gtk.Align.CENTER;
            vbox.margin_start = 12;
            vbox.margin_end = 4;
            vbox.append (_title);
            vbox.append (_subtitle);
            append (vbox);

            _title.halign = Gtk.Align.START;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.add_css_class ("title-leading");

            _subtitle.halign = Gtk.Align.START;
            _subtitle.ellipsize = Pango.EllipsizeMode.END;
            _subtitle.add_css_class ("dim-label");
            var font_size = _subtitle.get_pango_context ().get_font_description ().get_size () / Pango.SCALE;
            if (font_size >= 13)
                _subtitle.add_css_class ("title-secondly");

            _playing.valign = Gtk.Align.CENTER;
            _playing.icon_name = "media-playback-start-symbolic";
            _playing.pixel_size = 12;
            _playing.margin_end = 4;
            _playing.visible = false;
            _playing.add_css_class ("dim-label");
            append (_playing);

            width_request = 300;
        }

        public Music? music { get; set; }

        public bool playing {
            set {
                _playing.visible = value;
            }
        }

        public void setup_right_clickable () {
            make_right_clickable (this, show_popover);
        }

        public void update (Music music, uint sort) {
            _music = music;
            switch (sort) {
                case SortMode.ALBUM:
                    _title.label = music.album;
                    _subtitle.label = (0 < music.track < int.MAX) ? @"$(music.track). $(music.title)" : music.title;
                    break;

                case SortMode.ARTIST:
                    _title.label = music.artist;
                    _subtitle.label = music.title;
                    break;

                case SortMode.ARTIST_ALBUM:
                    _title.label = @"$(music.artist): $(music.album)";
                    _subtitle.label = (0 < music.track < int.MAX) ? @"$(music.track). $(music.title)" : music.title;
                    break;

                case SortMode.RECENT:
                    var date = new DateTime.from_unix_local (music.modified_time);
                    _title.label = music.title;
                    _subtitle.label = date.format ("%x %H:%M");
                    break;

                default:
                    _title.label = music.title;
                    _subtitle.label = music.artist;
                    break;
            }
        }

        private void show_popover (double x, double y) {
            if (_music != null) {
                var music = (!) _music;
                var app = (Application) GLib.Application.get_default ();
                var popover = create_music_popover_menu (music, x, y);
                var menu = (Menu) popover.menu_model;
                if (music != app.current_music)
                    menu.prepend_item (create_menu_item (music.uri, _("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
                if (music.cover_uri != null)
                    menu.append_item (create_menu_item (music.uri, _("Show _Cover File"), ACTION_APP + ACTION_SHOW_COVER_FILE));
                else if (app.thumbnailer.find (music) is Gdk.Texture)
                    menu.append_item (create_menu_item (music.uri, _("_Export Cover"), ACTION_APP + ACTION_EXPORT_COVER));
                popover.set_parent (this);
                popover.popup ();
            }
        }
    }

    public MenuItem create_menu_item (string value, string label, string action) {
        var item = new MenuItem (label, null);
        item.set_action_and_target_value (action, new Variant.string (value));
        return item;
    }

    public Gtk.PopoverMenu create_music_popover_menu (Music music, double x, double y) {
        var menu = new Menu ();
        menu.append_item (create_menu_item (music.title, _("Search Title"), ACTION_APP + ACTION_SEARCH_TITLE));
        menu.append_item (create_menu_item (music.album, _("Search Album"), ACTION_APP + ACTION_SEARCH_ALBUM));
        menu.append_item (create_menu_item (music.artist, _("Search Artist"), ACTION_APP + ACTION_SEARCH_ARTIST));
        menu.append_item (create_menu_item (music.uri, _("_Show Music File"), ACTION_APP + ACTION_SHOW_MUSIC_FILES));

        var rect = Gdk.Rectangle ();
        rect.x = (int) x;
        rect.y = (int) y;
        rect.width = rect.height = 0;

        var popover = new Gtk.PopoverMenu.from_model (menu);
        popover.autohide = true;
        popover.halign = Gtk.Align.START;
        popover.has_arrow = false;
        popover.pointing_to = rect;
        return popover;
    }

    public delegate void Pressed (double x, double y);

    public void make_right_clickable (Gtk.Widget widget, Pressed pressed) {
        var long_press = new Gtk.GestureLongPress ();
        long_press.pressed.connect ((x, y) => pressed (x, y));
        var right_click = new Gtk.GestureClick ();
        right_click.button = Gdk.BUTTON_SECONDARY;
        right_click.pressed.connect ((n, x, y) => pressed (x, y));
        widget.add_controller (long_press);
        widget.add_controller (right_click);
    }
}
