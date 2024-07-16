namespace G4 {

    namespace PageName {
        public const string ALBUM = "album";
        public const string ARTIST = "artist";
        public const string PLAYING = "playing";
        public const string PLAYLIST = "playlist";
    }

    public enum EllipsizeMode {
        NONE = Pango.EllipsizeMode.NONE,
        START = Pango.EllipsizeMode.START,
        MIDDLE = Pango.EllipsizeMode.MIDDLE,
        END = Pango.EllipsizeMode.END,
        MARQUEE
    }

    public class StableLabel : Gtk.Widget {
        private static Gtk.Builder _builder = new Gtk.Builder ();

        private EllipsizeMode _ellipsize = EllipsizeMode.NONE;
        private Gtk.Label _label = new Gtk.Label (null);
        private float _label_offset = 0;
        private int _label_width = 0;

        construct {
            add_child (_builder, _label, null);
        }

        ~StableLabel () {
            _label.unparent ();
        }

        public EllipsizeMode ellipsize {
            get {
                return _ellipsize;
            }
            set {
                _ellipsize = value;
                _label.ellipsize = value == EllipsizeMode.MARQUEE ? Pango.EllipsizeMode.NONE : (Pango.EllipsizeMode) value;
                stop_tick ();
            }
        }

        public string label {
            get {
                return _label.label;
            }
            set {
                _label.label = value;
                stop_tick ();
            }
        }

        public bool marquee {
            get {
                return _ellipsize == EllipsizeMode.MARQUEE;
            }
            set {
                ellipsize = value ? EllipsizeMode.MARQUEE : EllipsizeMode.NONE;
            }
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            if (orientation == Gtk.Orientation.VERTICAL) {
                // Ensure enough space for different text
                var text = _label.label;
                _label.label = "A中";
                _label.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
                _label.label = text;
            } else {
                _label.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
                _label_width = natural;
                if (marquee)
                    minimum = 0;
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            var allocation = Gtk.Allocation ();
            allocation.x = 0;
            allocation.y = 0;
            allocation.width = width;
            allocation.height = height;
            _label.allocate_size (allocation, baseline);
            update_tick_delayed ();
        }

        private static float SPACE = 40f;

        public override void snapshot (Gtk.Snapshot snapshot) {
            var width = get_width ();
            var overflow = marquee && width < _label_width;
            if (overflow) {
                var height = get_height ();
                var mask_width = float.min (width * 0.1f, height * 1.25f);
                var total_width = _label_width + SPACE;
                var left_mask = _label_offset < mask_width ? _label_offset : (_label_offset + mask_width > total_width ? 0 : mask_width);
                var rect = Graphene.Rect ();
                rect.init (0, 0, left_mask, height);
                Gsk.ColorStop[] stops = { { 0, color_from_uint (0xff000000u) }, { 1, color_from_uint (0x00000000u) } };
                snapshot.push_mask(Gsk.MaskMode.INVERTED_ALPHA);
                snapshot.append_linear_gradient (rect, rect.get_top_left (), rect.get_top_right (), stops);
                rect.init (width - mask_width, 0, mask_width, height);
                snapshot.append_linear_gradient (rect, rect.get_top_right (), rect.get_top_left (), stops);
                snapshot.pop ();
                var bounds = Graphene.Rect ();
                bounds.init (0, 0, width, height);
                snapshot.push_clip (bounds);
                var point = Graphene.Point ();
                point.init (0, 0);
                if (_label_offset < _label_width) {
                    point.x = - _label_offset;
                    snapshot.translate (point);
                    base.snapshot (snapshot);
                    point.x = - point.x;
                    snapshot.translate (point);
                }
                if (_label_offset >= total_width - width) {
                    point.x = - _label_offset + total_width;
                    snapshot.translate (point);
                    base.snapshot (snapshot);
                    point.x = - point.x;
                    snapshot.translate (point);
                }
                snapshot.pop ();
                snapshot.pop ();  // To avoid 'Too many gtk_snapshot_push() calls.'???
            } else {
                base.snapshot (snapshot);
            }
        }

        private uint _pixels_per_second = 24;
        private uint _tick_handler = 0;
        private int64 _tick_last_time = 0;
        private bool _tick_moving = false;

        private bool on_tick_callback (Gtk.Widget widget, Gdk.FrameClock clock) {
            if (_tick_moving) {
                var now = get_monotonic_time ();
                var elapsed = (now - _tick_last_time) / 1e6f;
                var offset = elapsed * _pixels_per_second;
                _tick_last_time = now;
                _label_offset += offset;
                if (_label_offset > _label_width + SPACE) {
                    stop_tick ();
                    update_tick_delayed ();
                }
                queue_draw ();
            }
            return true;
        }

        private void stop_tick () {
            if (_tick_handler != 0) {
                remove_tick_callback (_tick_handler);
                _tick_handler = 0;
            }
            if (_timer_id != 0) {
                Source.remove (_timer_id);
                _timer_id = 0;
            }
            _label_offset = 0;
            _tick_moving = false;
        }

        private void update_tick () {
            var need_tick = marquee && get_width () < _label_width;
            if (need_tick && _tick_handler == 0) {
                _tick_last_time = get_monotonic_time ();
                _tick_handler = add_tick_callback (on_tick_callback);
                _tick_moving = _tick_handler != 0;
            } else if (!need_tick && _tick_handler != 0) {
                stop_tick ();
            }
        }

        private static uint TICK_WAIT = 3000;
        private uint _timer_id = 0;

        private void update_tick_delayed () {
            if (_timer_id == 0) {
                _timer_id = run_timeout_once (TICK_WAIT, () => {
                    _timer_id = 0;
                    update_tick ();
                });
            }
        }
    }

    public class MusicWidget : Gtk.Box {
        protected Gtk.Image _cover = new Gtk.Image ();
        protected StableLabel _title = new StableLabel ();
        protected StableLabel _subtitle = new StableLabel ();
        protected RoundPaintable _paintable = new RoundPaintable ();
        protected Gtk.Image _playing = new Gtk.Image ();

        public ulong first_draw_handler = 0;
        public Music? music = null;

        public MusicWidget () {
            _playing.valign = Gtk.Align.CENTER;
            _playing.halign = Gtk.Align.END;
            _playing.icon_name = "media-playback-start-symbolic";
            _playing.margin_end = 4;
            _playing.pixel_size = 10;
            _playing.visible = false;
            _playing.add_css_class ("dim-label");
        }

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

        public bool playing {
            get {
                return _playing.visible;
            }
            set {
                _playing.visible = value;
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

        public void show_popover_menu (Gtk.Widget widget, double x, double y) {
            var menu = create_item_menu ();
            var popover = create_popover_menu (menu, x, y);
            popover.set_parent (widget);
            popover.popup ();
        }

        public virtual Menu create_item_menu () {
            return new Menu ();
        }
    }

    public class MusicCell : MusicWidget {

        public MusicCell () {
            orientation = Gtk.Orientation.VERTICAL;
            margin_top = 10;
            margin_bottom = 10;

            _cover.margin_start = 8;
            _cover.margin_end = 8;
            _cover.margin_bottom = 8;
            _cover.pixel_size = 160;
            _cover.paintable = _paintable;
            _paintable.queue_draw.connect (_cover.queue_draw);

            var overlay = new Gtk.Overlay ();
            overlay.child = _cover;
            overlay.add_overlay (_playing);
            append (overlay);

            _title.halign = Gtk.Align.CENTER;
            _title.ellipsize = EllipsizeMode.MIDDLE;
            _title.margin_start = 2;
            _title.margin_end = 2;
            _title.add_css_class ("title-leading");
            append (_title);

            _subtitle.halign = Gtk.Align.CENTER;
            _subtitle.ellipsize = EllipsizeMode.MIDDLE;
            _subtitle.margin_start = 2;
            _subtitle.margin_end = 2;
            _subtitle.visible = false;
            _subtitle.add_css_class ("dim-label");
            var font_size = _subtitle.get_pango_context ().get_font_description ().get_size () / Pango.SCALE;
            if (font_size >= 13)
                _subtitle.add_css_class ("title-secondly");
            append (_subtitle);

            width_request = 200;
        }

        public override Menu create_item_menu () {
            if (music is Album) {
                return create_menu_for_album ((Album) music);
            } else if (music is Artist) {
                return create_menu_for_artist ((Artist) music);
            }
            return base.create_item_menu ();
        }
    }

    public class MusicEntry : MusicWidget {
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

            var overlay = new Gtk.Overlay ();
            var spacing = compact ? 2 : 6;
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, spacing);
            vbox.hexpand = true;
            vbox.valign = Gtk.Align.CENTER;
            vbox.margin_start = 12;
            vbox.margin_end = 4;
            vbox.append (_title);
            vbox.append (_subtitle);
            overlay.child = vbox;
            append (overlay);

            _title.halign = Gtk.Align.START;
            _title.ellipsize = EllipsizeMode.END;
            _title.add_css_class ("title-leading");

            _subtitle.halign = Gtk.Align.START;
            _subtitle.ellipsize = EllipsizeMode.END;
            _subtitle.add_css_class ("dim-label");
            var font_size = _subtitle.get_pango_context ().get_font_description ().get_size () / Pango.SCALE;
            if (font_size >= 13)
                _subtitle.add_css_class ("title-secondly");

            overlay.add_overlay (_playing);

            width_request = 328;
        }

        public void set_titles (Music music, uint sort) {
            this.music = music;
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

        public override Menu create_item_menu () {
            if (this.music != null) {
                var app = (Application) GLib.Application.get_default ();
                var music = (!) this.music;
                var menu = create_menu_for_music (music);
                if (music != app.current_music) {
                    /* Translators: Play this music at next position of current playing music */
                    menu.prepend_item (create_menu_item_for_uri (music.uri, _("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
                    menu.prepend_item (create_menu_item_for_uri (music.uri, _("Play"), ACTION_APP + ACTION_PLAY));
                }
                if (music.cover_uri != null) {
                    menu.append_item (create_menu_item_for_uri ((!)music.cover_uri, _("Show _Cover File"), ACTION_APP + ACTION_SHOW_FILE));
                } else if (app.thumbnailer.find (music) is Gdk.Texture) {
                    menu.append_item (create_menu_item_for_uri (music.uri, _("_Export Cover"), ACTION_APP + ACTION_EXPORT_COVER));
                }
                return menu;
            }
            return base.create_item_menu ();
        }
    }

    public string[] build_action_target_for_album (Album album) {
        unowned var album_artist = album.album_artist;
        unowned var album_key = album.album_key;
        var is_playlist = album is Playlist;
        if (is_playlist)
            return { PageName.PLAYLIST, album_key };
        else if (album_artist.length > 0)
            return { PageName.ARTIST, album_artist, album_key };
        else
            return { PageName.ALBUM, album_key };
    }

    public MenuItem create_menu_item_for_strv (string[] strv, string label, string action) {
        var item = new MenuItem (label, null);
        item.set_action_and_target_value (action, new Variant.bytestring_array (strv));
        return item;
    }

    public MenuItem create_menu_item_for_uri (string uri, string label, string action) {
        return create_menu_item_for_strv ({"uri", uri}, label, action);
    }

    public Menu create_menu_for_album (Album album) {
        var is_playlist = album is Playlist;
        var strv = build_action_target_for_album (album);
        var menu = new Menu ();
        menu.append_item (create_menu_item_for_strv (strv, _("Play"), ACTION_APP + ACTION_PLAY));
        menu.append_item (create_menu_item_for_strv (strv, _("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
        if (is_playlist)
            menu.append_item (create_menu_item_for_uri (((Playlist) album).list_uri, _("Show List File"), ACTION_APP + ACTION_SHOW_FILE));
        return menu;
    }

    public Menu create_menu_for_artist (Artist artist) {
        string[] strv = { PageName.ARTIST, artist.name };
        var menu = new Menu ();
        menu.append_item (create_menu_item_for_strv (strv, _("Play"), ACTION_APP + ACTION_PLAY));
        menu.append_item (create_menu_item_for_strv (strv, _("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
        return menu;
    }

    public Menu create_menu_for_music (Music music) {
        var menu = new Menu ();
        menu.append_item (create_menu_item_for_strv ({"title", music.title}, _("Search Title"), ACTION_APP + ACTION_SEARCH));
        menu.append_item (create_menu_item_for_strv ({"album", music.album}, _("Search Album"), ACTION_APP + ACTION_SEARCH));
        menu.append_item (create_menu_item_for_strv ({"artist", music.artist}, _("Search Artist"), ACTION_APP + ACTION_SEARCH));
        menu.append_item (create_menu_item_for_uri (music.uri, _("_Show Music File"), ACTION_APP + ACTION_SHOW_FILE));
        return menu;
    }

    public Gtk.PopoverMenu create_popover_menu (Menu menu, double x, double y) {
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

    public delegate void Pressed (Gtk.Widget widget, double x, double y);

    public void make_right_clickable (Gtk.Widget widget, Pressed pressed) {
        var long_press = new Gtk.GestureLongPress ();
        long_press.pressed.connect ((x, y) => pressed (widget, x, y));
        var right_click = new Gtk.GestureClick ();
        right_click.button = Gdk.BUTTON_SECONDARY;
        right_click.pressed.connect ((n, x, y) => pressed (widget, x, y));
        widget.add_controller (long_press);
        widget.add_controller (right_click);
    }
}
