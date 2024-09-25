namespace G4 {

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/play-panel.ui")]
    public class PlayPanel : Gtk.Box, SizeWatcher {
        [GtkChild]
        private unowned Gtk.MenuButton action_btn;
        [GtkChild]
        private unowned Gtk.Button back_btn;
        [GtkChild]
        private unowned Gtk.Label index_label;
        [GtkChild]
        private unowned Gtk.Box music_box;
        [GtkChild]
        private unowned Gtk.Image music_cover;
        [GtkChild]
        private unowned StableLabel music_album;
        [GtkChild]
        private unowned StableLabel music_artist;
        [GtkChild]
        private unowned StableLabel music_title;
        [GtkChild]
        private unowned Gtk.Label initial_label;

        private PlayBar _play_bar = new PlayBar ();

        private Application _app;
        private double _degrees_per_second = 360 / 20; // 20s per lap
        private CrossFadePaintable _crossfade_paintable = new CrossFadePaintable ();
        private MatrixPaintable _matrix_paintable = new MatrixPaintable ();
        private RoundPaintable _round_paintable = new RoundPaintable ();
        private bool _rotate_cover = true;
        private bool _show_peak = true;
        private bool _size_allocated = false;

        public signal void cover_changed (Music? music, CrossFadePaintable cover);

        public PlayPanel (Application app, Window win, Leaflet leaflet) {
            _app = app;

            _play_bar.halign = Gtk.Align.FILL;
            _play_bar.position_seeked.connect (on_position_seeked);
            music_box.append (_play_bar);

            leaflet.bind_property ("folded", back_btn, "visible", BindingFlags.SYNC_CREATE);

            action_btn.set_create_popup_func (() => action_btn.menu_model = create_music_action_menu ());

            back_btn.clicked.connect (leaflet.pop);

            initial_label.activate_link.connect (on_music_folder_clicked);

            _matrix_paintable.paintable = _round_paintable;
            _crossfade_paintable.paintable = _matrix_paintable;
            _crossfade_paintable.queue_draw.connect (music_cover.queue_draw);
            music_cover.paintable = _crossfade_paintable;
            create_drag_source ();

            music_album.tooltip_text = _("Search Album");
            music_artist.tooltip_text = _("Search Artist");
            music_title.tooltip_text = _("Search Title");
            make_widget_clickable (music_album).released.connect (
                () => win.start_search (music_album.label, SearchMode.ALBUM));
            make_widget_clickable (music_artist).released.connect (
                () => win.start_search (music_artist.label, SearchMode.ARTIST));
            make_widget_clickable (music_title).released.connect (
                () => win.start_search (music_title.label, SearchMode.TITLE));
            make_right_clickable (music_box, show_popover_menu);

            app.index_changed.connect (on_index_changed);
            app.music_changed.connect (on_music_changed);
            app.music_cover_parsed.connect (on_music_cover_parsed);
            app.player.state_changed.connect (on_player_state_changed);

            var settings = app.settings;
            settings.bind ("rotate-cover", this, "rotate-cover", SettingsBindFlags.DEFAULT);
            settings.bind ("show-peak", this, "show-peak", SettingsBindFlags.DEFAULT);
        }

        public bool rotate_cover {
            get {
                return _rotate_cover;
            }
            set {
                _rotate_cover = value;
                _round_paintable.ratio = value ? 0.5 : 0.05;
                _matrix_paintable.rotation = value ? _play_bar.position * _degrees_per_second : 0;
                on_player_state_changed (_app.player.state);
            }
        }

        public bool show_peak {
            get {
                return _show_peak;
            }
            set {
                _show_peak = value;
                on_player_state_changed (_app.player.state);
            }
        }

        public void first_allocated () {
            // Delay update info after the window size allocated to avoid showing slowly
            _size_allocated = true;
            if (_app.current_music != _current_music || _current_music == null) {
                on_music_changed (_app.current_music);
            }
        }

        public void size_to_change (int width, int height) {
            var max_size = int.max (width * 3 / 4, music_cover.pixel_size);
            var margin_horz = (width - max_size) / 2;
            var margin_cover = int.max (margin_horz, 32);
            music_cover.margin_start = margin_cover;
            music_cover.margin_end = margin_cover;

            var margin_bar = int.max (margin_horz / 2, 16);
            var spacing = (height - 540).clamp (8, 16);
            _play_bar.margin_start = margin_bar;
            _play_bar.margin_end = margin_bar;
            _play_bar.margin_top = spacing;
            _play_bar.margin_bottom = spacing * 2;
            _play_bar.on_size_changed (width - margin_bar * 2, spacing);
        }

        private void create_drag_source () {
            var point = Graphene.Point ();
            var source = new Gtk.DragSource ();
            source.actions = Gdk.DragAction.LINK;
            source.drag_begin.connect ((drag) => source.set_icon (new Gtk.WidgetPaintable (music_cover), (int) point.x, (int) point.y));
            source.prepare.connect ((x, y) => {
                point.init ((float) x, (float) y);
                if (_current_music != null) {
                    var playlist = to_playlist ({ (!)_current_music });
                    return create_content_provider (playlist);
                }
                return null;
            });
            music_cover.add_controller (source);
        }

        private Menu create_music_action_menu () {
            var music = _app.current_music ?? new Music.empty ();
            var menu = create_menu_for_music (music);
            if (music.cover_uri != null) {
                menu.append_item (create_menu_item_for_uri ((!)music.cover_uri, _("Show _Cover File"), ACTION_APP + ACTION_SHOW_FILE));
            } else if (_app.current_cover != null) {
                menu.append_item (create_menu_item_for_uri (music.uri, _("_Export Cover"), ACTION_APP + ACTION_EXPORT_COVER));
            }
            return menu;
        }

        private void on_index_changed (int index, uint size) {
            root.action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
            root.action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
            index_label.label = size > 0 ? @"$(index+1)/$(size)" : "";
        }

        private Music? _current_music = null;

        private void on_music_changed (Music? music) {
            _current_music = music;

            music_album.label = music?.album ?? "";
            music_artist.label = music?.artist ?? "";
            music_title.label = music?.title ?? "";

            var empty = _app.current_list.get_n_items () == 0;
            initial_label.visible = empty;
            if (empty) {
                if (_app.loading)
                    initial_label.label = "";
                else
                    update_initial_label (_app.music_folder);
            }

            var enabled = music != null;
            if (!enabled) {
                update_cover_paintables (music, _app.icon);
            }
            action_btn.sensitive = enabled;
            root.action_set_enabled (ACTION_APP + ACTION_PLAY_PAUSE, enabled);
            (_app.active_window as Window)?.set_title (music?.get_artist_and_title () ?? _app.name);
        }

        private bool on_music_folder_clicked (string uri) {
            pick_music_folder_async.begin (_app, _app.active_window,
                (dir) => update_initial_label (dir.get_uri ()),
                (obj, res) => pick_music_folder_async.end (res));
            return true;
        }

        private async void on_music_cover_parsed (Music music, Gdk.Pixbuf? pixbuf, string? uri) {
            var paintable = pixbuf != null ? Gdk.Texture.for_pixbuf ((!)pixbuf)
                            : _app.thumbnailer.create_music_text_paintable (music);
            update_cover_paintables (music, paintable);
        }

        private Adw.Animation? _scale_animation = null;
        private uint _tick_handler = 0;
        private int64 _tick_last_time = 0;

        private void on_player_state_changed (Gst.State state) {
            var playing = state == Gst.State.PLAYING;
            if (state >= Gst.State.PAUSED) {
                var target = new Adw.CallbackAnimationTarget ((value) => _matrix_paintable.scale = value);
                _scale_animation?.pause ();
                _scale_animation = new Adw.TimedAnimation (music_cover, _matrix_paintable.scale,
                                        _rotate_cover || playing ? 1 : 0.85, 500, target);
                _scale_animation?.play ();
            }

            var need_tick = _rotate_cover || _show_peak;
            if (need_tick && playing && _tick_handler == 0) {
                _tick_last_time = get_monotonic_time ();
                _tick_handler = add_tick_callback (on_tick_callback);
            } else if ((!need_tick || !playing) && _tick_handler != 0) {
                remove_tick_callback (_tick_handler);
                _tick_handler = 0;
            }
        }

        private void on_position_seeked (double pos) {
            if (_rotate_cover)
                _matrix_paintable.rotation = pos * _degrees_per_second;
        }

        private bool on_tick_callback (Gtk.Widget widget, Gdk.FrameClock clock) {
            if (_rotate_cover) {
                var now = get_monotonic_time ();
                var elapsed = (now - _tick_last_time) / 1e6;
                var angle = elapsed * _degrees_per_second;
                _matrix_paintable.rotation += angle;
                _tick_last_time = now;
            }
            if (_show_peak) {
                var peak = _app.player.peak;
                _play_bar.peak = peak;
            }
            return true;
        }

        private void show_popover_menu (Gtk.Widget widget, double x, double y) {
            if (_app.current_music != null) {
                var menu = create_music_action_menu ();
                var popover = create_popover_menu (menu, x, y);
                popover.set_parent (widget);
                popover.popup ();
            }
        }

        private void update_cover_paintables (Music? music, Gdk.Paintable? paintable) {
            _round_paintable = new RoundPaintable (paintable);
            _round_paintable.ratio = _rotate_cover ? 0.5 : 0.05;
            _round_paintable.queue_draw.connect (music_cover.queue_draw);
            _matrix_paintable = new MatrixPaintable (_round_paintable);
            _matrix_paintable.queue_draw.connect (music_cover.queue_draw);
            _crossfade_paintable.paintable = _matrix_paintable;
            cover_changed (music, _crossfade_paintable);
        }

        private void update_initial_label (string uri) {
            var dir_name = Uri.escape_string (get_display_name (uri));
            var link = @"<a href=\"change_dir\">$dir_name</a>";
            initial_label.set_markup (_("Drag and drop music files here,\nor change music location: ") + link);
        }
    }
}
