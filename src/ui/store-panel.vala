namespace G4 {

    namespace SearchMode {
        public const uint ANY = 0;
        public const uint ALBUM = 1;
        public const uint ARTIST = 2;
        public const uint TITLE = 3;
    }

    public const string[] SORT_MODE_ICONS = {
        "media-optical-cd-audio-symbolic",  // ALBUM
        "system-users-symbolic",            // ARTIST
        "avatar-default-symbolic",          // ARTIST_ALBUM
        "folder-music-symbolic",            // TITLE
        "document-open-recent-symbolic",    // RECENT
        "media-playlist-shuffle-symbolic",  // SHUFFLE
    };

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/store-panel.ui")]
    public class StorePanel : Gtk.Box {
        [GtkChild]
        private unowned Gtk.HeaderBar header_bar;
        [GtkChild]
        private unowned Gtk.ProgressBar progress_bar;
        [GtkChild]
        private unowned Gtk.MenuButton sort_btn;
        [GtkChild]
        private unowned Gtk.ToggleButton search_btn;
        [GtkChild]
        private unowned Gtk.SearchBar search_bar;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry;
        [GtkChild]
        private unowned Gtk.Stack stack_view;

        private Gtk.Stack _album_stack = new Gtk.Stack ();
        private Gtk.Stack _artist_stack = new Gtk.Stack ();

        private Application _app;
        private MusicList _album_list;
        private MusicList _artist_list;
        private MusicList _current_list;
        private MusicList _playing_list;
        private MusicLibrary _library;
        private string[]? _library_path = null;
        private Gdk.Paintable _loading_paintable;
        private uint _search_mode = SearchMode.ANY;
        private string _search_text = "";
        private uint _sort_mode = 0;

        public StorePanel (Application app, Window win, Adw.Leaflet leaflet) {
            _app = app;
            _library = app.loader.library;

            leaflet.bind_property ("folded", header_bar, "show-title-buttons", BindingFlags.SYNC_CREATE);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = win.content;
            search_entry.search_changed.connect (on_search_text_changed);

            _app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = _app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            _current_list = _playing_list = create_playing_music_list ();
            _playing_list.data_store = _app.music_store;
            _app.music_list = _playing_list.filter_model;
            stack_view.add_titled (_playing_list, "playing", _("Playing")).icon_name = "media-playback-start-symbolic";
            stack_view.visible_child = _playing_list;

            _artist_list = create_artist_list ();
            _artist_stack.add_named (_artist_list, "artists");
            _artist_stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack_view.add_titled (_artist_stack, "Artists", _("Artists")).icon_name = "system-users-symbolic";

            _album_list = create_albums_list ();
            _album_stack.add_named (_album_list, "albums");
            _album_stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack_view.add_titled (_album_stack, "Albums", _("Albums")).icon_name = "drive-multidisk-symbolic";

            var switcher = new SwitchBar ();
            switcher.stack = stack_view;
            switcher.transition_type = Gtk.RevealerTransitionType.SLIDE_RIGHT;
            header_bar.pack_start (switcher);

            var switcher2 = new SwitchBar ();
            switcher2.stack = stack_view;
            var revealer = new Gtk.Revealer ();
            revealer.child = switcher2;
            revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_UP;
            insert_child_after (revealer, header_bar);
            switcher.bind_property ("reveal-child", revealer, "reveal-child", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            app.index_changed.connect (on_index_changed);
            app.music_batch_changed.connect (on_music_batch_changed);
            app.music_changed.connect (on_music_changed);
            app.loader.loading_changed.connect (on_loading_changed);

            var settings = app.settings;
            settings.bind ("sort-mode", this, "sort-mode", SettingsBindFlags.DEFAULT);
            _library_path = settings.get_strv ("library-path");
        }

        public uint sort_mode {
            get {
                return _sort_mode;
            }
            set {
                if (value < SORT_MODE_ICONS.length) {
                    sort_btn.set_icon_name (SORT_MODE_ICONS[value]);
                    _sort_mode = value;
                }
                if (_playing_list.get_height () > 0) {
                    _playing_list.create_factory ();
                }
            }
        }

        public Gtk.Widget visible_child {
            set {
                if (value is Gtk.Stack) {
                    value = ((Gtk.Stack) value).visible_child;
                }
                if (value is MusicList) {
                    _current_list = (MusicList) value;
                    if (_current_list.list_mode) {
                        _app.music_list = _current_list.filter_model;
                        _current_list.current_item = _app.current_music;
                        run_idle_once (() => _current_list.scroll_to_current_item ());
                    }
                }
                sort_btn.sensitive = _current_list == _playing_list;
                on_search_text_changed ();

                var paths = new GenericArray<string> (4);
                get_library_paths (paths);
                paths.add ((string) null); // Must be null terminated 
                _app.settings.set_strv ("library-path", paths.data);
            }
        }

        public void size_allocated () {
            // Delay set model after the window size allocated to avoid showing slowly
            _album_list.create_factory ();
            _artist_list.create_factory ();
            _app.settings.bind ("compact-playlist", _playing_list, "compact-list", SettingsBindFlags.DEFAULT);
            _current_list.scroll_to_item (_app.current_item);
            _album_stack.bind_property ("visible-child", this, "visible-child", BindingFlags.DEFAULT);
            _artist_stack.bind_property ("visible-child", this, "visible-child", BindingFlags.DEFAULT);
            stack_view.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack_view.bind_property ("visible-child", this, "visible-child", BindingFlags.DEFAULT);
            if (_library.albums.length > 0) {
                locate_to_library_path ();
            }
        }

        public void size_to_change (int panel_width) {
        }

        public void start_search (string text, uint mode = SearchMode.ANY) {
            switch (mode) {
                case SearchMode.ALBUM:
                    stack_view.visible_child = _album_stack;
                    break;
                case SearchMode.ARTIST:
                    stack_view.visible_child = _artist_stack;
                    break;
                case SearchMode.TITLE:
                    stack_view.visible_child = _playing_list;
                    break;
            }

#if GTK_4_10
            var delay = search_entry.search_delay;
            search_entry.search_delay = 0;
            run_idle_once (() => search_entry.search_delay = delay);
#endif
            search_entry.text = text;
            search_entry.select_region (0, -1);
            search_btn.active = true;
        }

        public bool toggle_search () {
            search_btn.active = ! search_btn.active;
            return search_btn.active;
        }

        private MusicList create_albums_list (Artist? artist = null) {
            var list = new MusicList (_app, true);
            list.item_activated.connect ((position, obj) => {
                var name = (obj as Music)?.album ?? "";
                var album = artist != null ? ((!)artist).albums[name] : _library.albums[name];
                if (album is Album) {
                    create_sub_stack_page (artist, album);
                }
            });
            list.item_created.connect ((item) => {
                var cell = (MusicCell) item.child;
                make_right_clickable (cell, cell.show_popover_menu);
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicCell) item.child;
                var music = (Music) item.item;
                cell.album_name = music.album;
                cell.artist_name = artist?.name;
                cell.paintable = _loading_paintable;
                cell.title = music.album;
            });
            artist?.get_sorted_albums (list.data_store);
            return list;
        }

        private MusicList create_artist_list () {
            var list = new MusicList (_app, true);
            list.item_activated.connect ((position, obj) => {
                var artist_name = (obj as Music)?.artist ?? "";
                var artist = _library.artists[artist_name];
                if (artist is Artist) {
                    create_sub_stack_page (artist);
                }
            });
            list.item_created.connect ((item) => {
                var cell = (MusicCell) item.child;
                cell.cover.ratio = 0.5;
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicCell) item.child;
                var music = (Music) item.item;
                cell.paintable = _loading_paintable;
                cell.title  = music.artist;
            });
            return list;
        }

        private MusicList create_music_list (Album album, bool from_artist = false) {
            var list = new MusicList (_app);
            list.item_activated.connect ((position, obj) => _app.play (obj));
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.music = music;
                entry.paintable = _loading_paintable;
                entry.playing = music == _app.current_music;
                entry.title = music.title;
                entry.subtitle = "";
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                make_right_clickable (entry, entry.show_popover_menu);
            });
            album.get_sorted_musics (list.data_store);
            return list;
        }

        private MusicList create_playing_music_list () {
            var list = new MusicList (_app);
            list.item_activated.connect ((position, obj) => _app.current_item = (int) position);
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.playing = music == _app.current_music;
                entry.set_titles (music, _sort_mode);
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                make_right_clickable (entry, entry.show_popover_menu);
            });
            return list;
        }

        private void create_sub_stack_page (Artist? artist, Album? album = null) {
            var stack = artist != null ? _artist_stack : _album_stack;
            var album_mode = album != null;
            var mlist = album_mode ? create_music_list ((!)album, artist != null) : create_albums_list (artist);
            mlist.create_factory ();

            var name = (album_mode ? album?.name : artist?.name) ?? "";
            var label = new Gtk.Label (name);
            label.ellipsize = Pango.EllipsizeMode.END;
            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = false;
            header.title_widget = label;
            header.add_css_class ("flat");
            mlist.prepend (header);

            var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
            back_btn.tooltip_text = _("Back");
            back_btn.clicked.connect (() => {
                var prev = mlist.get_prev_sibling ();
                stack.visible_child = (!)prev;
                run_timeout_once (stack.transition_duration, () => stack.remove (mlist));
            });
            header.pack_start (back_btn);

            if (album_mode) {
                var cell = new MusicCell ();
                cell.album_name = album?.name;
                cell.artist_name = artist?.name;
                var menu_btn = new Gtk.MenuButton ();
                menu_btn.icon_name = "view-more-symbolic";
                menu_btn.menu_model = cell.create_item_menu ();
                header.pack_end (menu_btn);
            }

            stack.add_titled (mlist, name, name);
            stack.visible_child = mlist;
        }

        private void get_library_paths (GenericArray<string> paths) {
            paths.add (stack_view.get_visible_child_name () ?? "");
            var visible_child = stack_view.visible_child;
            if (visible_child is Gtk.Stack) {
                var stack = (Gtk.Stack) visible_child;
                for (var child = (Gtk.Widget?) stack.visible_child; child is MusicList; child = child?.get_prev_sibling ()) {
                    paths.insert (1, stack.get_page ((!)child).name);
                }
            }
        }

        private void locate_to_library_path () {
            var length = _library_path?.length ?? 0;
            if (length > 0) {
                var paths = (!)_library_path;
                stack_view.visible_child_name = paths[0];
                var visible_child = stack_view.visible_child;
                if (visible_child is Gtk.Stack && length > 2) {
                    if (paths[1] == "artists") {
                        var artist = _library.artists[paths[2]];
                        if (artist is Artist) {
                            create_sub_stack_page (artist, null);
                            if (length > 3) {
                                var album = artist.albums[paths[3]];
                                if (album is Album) {
                                    create_sub_stack_page (artist, album);
                                }
                            }
                        }
                    } else if (paths[1] == "albums") {
                        var album = _library.albums[paths[2]];
                        if (album is Album) {
                            create_sub_stack_page (null, album);
                        }
                    }
                }
            }
            _library_path = null;
        }

        private void on_index_changed (int index, uint size) {
            root.action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
            root.action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
            if (_current_list.list_mode) {
                _current_list.scroll_to_item (index);
            }
        }

        private uint _tick_handler = 0;

        private void on_loading_changed (bool loading) {
            root.action_set_enabled (ACTION_APP + ACTION_RELOAD, !loading);
            progress_bar.visible = loading;

            if (loading && _tick_handler == 0) {
                _tick_handler = add_tick_callback (on_loading_tick_callback);
            } else if (!loading && _tick_handler != 0) {
                remove_tick_callback (_tick_handler);
                _tick_handler = 0;
            }
        }

        private bool on_loading_tick_callback (Gtk.Widget widget, Gdk.FrameClock clock) {
            var fraction = _app.loader.loading_progress;
            if (fraction > 0)
                progress_bar.fraction = fraction;
            else
                progress_bar.pulse ();
            return true;
        }

        private void on_music_batch_changed () {
            _library.get_sorted_albums_and_artists (_album_list.data_store, _artist_list.data_store);
            if (stack_view.pages.get_n_items () > 0)
                locate_to_library_path ();
        }

        private void on_music_changed (Music? music) {
            _current_list.current_item = music;
        }

        private void on_search_btn_toggled () {
            if (search_btn.active) {
                search_entry.grab_focus ();
            }
            on_search_text_changed ();
        }

        private bool on_search_match (Object obj) {
            var music = (Music) obj;
            unowned var text = _search_text;
            switch (_search_mode) {
                case SearchMode.ALBUM:
                    return text.match_string (music.album, true);
                case SearchMode.ARTIST:
                    return text.match_string (music.artist, true);
                case SearchMode.TITLE:
                    return text.match_string (music.title, true);
                default:
                    return text.match_string (music.album, true)
                        || text.match_string (music.artist, true)
                        || text.match_string (music.title, true);
            }
        }

        private void on_search_text_changed () {
            var text = _search_text = search_entry.text;
            if (_current_list == _album_list) {
                _search_mode = SearchMode.ALBUM;
                if (text.ascii_ncasecmp ("album:", 6) == 0)
                    _search_text = text.substring (6);
            } else if (_current_list == _artist_list) {
                _search_mode = SearchMode.ARTIST;
                if (text.ascii_ncasecmp ("artist:", 7) == 0)
                    _search_text = text.substring (7);
            } else {
                _search_mode = SearchMode.ANY;
                parse_search_mode (ref _search_text, ref _search_mode);
            }
            _current_list.filter_model.set_filter (search_btn.active ? new Gtk.CustomFilter (on_search_match) : (Gtk.CustomFilter?) null);
        }
    }

    public void parse_search_mode (ref string text, ref uint mode) {
        if (text.ascii_ncasecmp ("album:", 6) == 0) {
            mode = SearchMode.ALBUM;
            text = text.substring (6);
        } else if (text.ascii_ncasecmp ("artist:", 7) == 0) {
            mode = SearchMode.ARTIST;
            text = text.substring (7);
        } else if (text.ascii_ncasecmp ("title:", 6) == 0) {
            mode = SearchMode.TITLE;
            text = text.substring (6);
        }
    }
}
