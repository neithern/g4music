namespace G4 {

    namespace PageName {
        public const string ALBUM = "album";
        public const string ARTIST = "artist";
        public const string PLAYING = "playing";
        public const string PLAYLIST = "playlist";
    }

    public class MusicWidget : Gtk.Box {
        protected Gtk.Image _image = new Gtk.Image ();
        protected StableLabel _title = new StableLabel ();
        protected StableLabel _subtitle = new StableLabel ();
        protected RoundPaintable _paintable = new RoundPaintable ();
        protected Gtk.Image _playing = new Gtk.Image ();

        public ulong first_draw_handler = 0;
        public Music? music = null;

        public signal Menu? create_music_menu (Music? node);

        public MusicWidget () {
            _playing.halign = Gtk.Align.END;
            _playing.valign = Gtk.Align.CENTER;
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

        public Gtk.Image image {
            get {
                return _image;
            }
        }

        public Gdk.Paintable? paintable {
            set {
                _paintable.paintable = value;
            }
        }

        public Gtk.Image playing {
            get {
                return _playing;
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
            var menu = create_music_menu (music);
            if (menu != null) {
                var popover = create_popover_menu ((!)menu, x, y);
                popover.set_parent (widget);
                popover.popup ();
            }
        }
    }

    public class MusicCell : MusicWidget {
        public MusicCell () {
            orientation = Gtk.Orientation.VERTICAL;
            margin_top = 10;
            margin_bottom = 10;
            width_request = 200;

            var overlay = new Gtk.Overlay ();
            overlay.margin_start = 8;
            overlay.margin_end = 8;
            overlay.margin_bottom = 8;
            overlay.child = _image;
            overlay.add_overlay (_playing);
            append (overlay);

            _image.halign = Gtk.Align.CENTER;
            _image.pixel_size = 160;
            _image.paintable = _paintable;
            _paintable.queue_draw.connect (_image.queue_draw);

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
        }
    }

    public class MusicEntry : MusicWidget {
        public MusicEntry (bool compact = true) {
            width_request = 324;

            var cover_margin = compact ? 3 : 4;
            var cover_size = compact ? 36 : 48;
            _image.margin_top = cover_margin;
            _image.margin_bottom = cover_margin;
            _image.margin_start = 4;
            _image.pixel_size = cover_size;
            _image.paintable = _paintable;
            _paintable.queue_draw.connect (_image.queue_draw);
            append (_image);

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
            _title.ellipsize = EllipsizeMode.END;
            _title.add_css_class ("title-leading");

            _subtitle.halign = Gtk.Align.START;
            _subtitle.ellipsize = EllipsizeMode.END;
            _subtitle.add_css_class ("dim-label");
            var font_size = _subtitle.get_pango_context ().get_font_description ().get_size () / Pango.SCALE;
            if (font_size >= 13)
                _subtitle.add_css_class ("title-secondly");

            append (_playing);
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
        var strv = build_action_target_for_album (album);
        var menu = new Menu ();
        menu.append_item (create_menu_item_for_strv (strv, _("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
        menu.append_item (create_menu_item_for_strv (strv, _("Add to Queue"), ACTION_APP + ACTION_ADD_TO_QUEUE));
        menu.append_item (create_menu_item_for_strv (strv, _("Add to Playlist…"), ACTION_APP + ACTION_ADD_TO_PLAYLIST));
        if (album is Playlist)
            menu.append_item (create_menu_item_for_uri (((Playlist) album).list_uri, _("Show List File"), ACTION_APP + ACTION_SHOW_FILE));
        return menu;
    }

    public Menu create_menu_for_artist (Artist artist) {
        string[] strv = { PageName.ARTIST, artist.artist };
        var menu = new Menu ();
        menu.append_item (create_menu_item_for_strv (strv, _("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
        menu.append_item (create_menu_item_for_strv (strv, _("Add to Queue"), ACTION_APP + ACTION_ADD_TO_QUEUE));
        menu.append_item (create_menu_item_for_strv (strv, _("Add to Playlist…"), ACTION_APP + ACTION_ADD_TO_PLAYLIST));
        return menu;
    }

    public Menu create_menu_for_music (Music music) {
        var section = new Menu ();
        section.append_item (create_menu_item_for_strv ({"title", music.title}, _("Search Title"), ACTION_WIN + ACTION_SEARCH));
        section.append_item (create_menu_item_for_strv ({"album", music.album}, _("Search Album"), ACTION_WIN + ACTION_SEARCH));
        section.append_item (create_menu_item_for_strv ({"artist", music.artist}, _("Search Artist"), ACTION_WIN + ACTION_SEARCH));
        var section2 = new Menu ();
        section2.append_item (create_menu_item_for_uri (music.uri, _("_Show Music File"), ACTION_APP + ACTION_SHOW_FILE));
        var menu = new Menu ();
        menu.append_item (create_menu_item_for_uri (music.uri, _("Add to Playlist…"), ACTION_APP + ACTION_ADD_TO_PLAYLIST));
        menu.append_section (null, section);
        menu.append_section (null, section2);
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

    public Gtk.GestureLongPress make_long_pressable (Gtk.Widget widget, Pressed pressed) {
        var gesture = new Gtk.GestureLongPress ();
        gesture.pressed.connect ((x, y) => pressed (widget, x, y));
        widget.add_controller (gesture);
        return gesture;
    }

    public Gtk.GestureClick make_right_clickable (Gtk.Widget widget, Pressed pressed) {
        var gesture = new Gtk.GestureClick ();
        gesture.button = Gdk.BUTTON_SECONDARY;
        gesture.pressed.connect ((n, x, y) => pressed (widget, x, y));
        widget.add_controller (gesture);
        return gesture;
    }

    public void remove_controllers (Gtk.Widget widget) {
        var controllers = widget.observe_controllers ();
        for (var i = (int) controllers.get_n_items () - 1; i >= 0; i--) {
            var controller = (Gtk.EventController) controllers.get_item (i);
            widget.remove_controller (controller);
        }
    }
}
