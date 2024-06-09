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
        private Gtk.Stack _playlist_stack = new Gtk.Stack ();
        private SwitchBar _switch_bar = new SwitchBar ();
        private SwitchBar _switch_bar2 = new SwitchBar ();

        private Application _app;
        private MusicList _album_list;
        private MusicList _artist_list;
        private MusicList _current_list;
        private MusicList _playing_list;
        private MusicList _playlist_list;
        private MusicLibrary _library;
        private string[]? _library_path = null;
        private Gdk.Paintable _loading_paintable;
        private uint _search_mode = SearchMode.ANY;
        private string _search_text = "";
        private bool _size_allocated = false;
        private uint _sort_mode = 0;

        public StorePanel (Application app, Window win, Adw.Leaflet leaflet) {
            _app = app;
            _library = app.loader.library;

            var thumbnailer = app.thumbnailer;
            thumbnailer.pango_context = get_pango_context ();
            thumbnailer.scale_factor = this.scale_factor;
            _loading_paintable = thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            leaflet.bind_property ("folded", header_bar, "show-title-buttons", BindingFlags.SYNC_CREATE);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = win.content;
            search_entry.search_changed.connect (on_search_text_changed);

            _current_list = _playing_list = create_playing_music_list ();
            _playing_list.data_store = _app.music_store;
            _app.music_list = _playing_list.filter_model;
            stack_view.add_titled (_playing_list, PageName.PLAYING, _("Playing")).icon_name = "media-playback-start-symbolic";

            _artist_list = create_artist_list ();
            _artist_stack.add_named (_artist_list, "artist");
            _artist_stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack_view.add_titled (_artist_stack, PageName.ARTIST, _("Artists")).icon_name = "system-users-symbolic";

            _album_list = create_album_list ();
            _album_stack.add_named (_album_list, PageName.ALBUM);
            _album_stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack_view.add_titled (_album_stack, PageName.ALBUM, _("Albums")).icon_name = "drive-multidisk-symbolic";

            _playlist_list = create_playlist_list ();
            _playlist_stack.add_named (_playlist_list, PageName.PLAYLIST);
            _playlist_stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            //  stack_view.add_titled (_playlist_stack, PageName.PLAYLIST, _("Playlists")).icon_name = "view-list-symbolic";

            _switch_bar.stack = stack_view;
            _switch_bar.transition_type = Gtk.RevealerTransitionType.SLIDE_RIGHT;
            header_bar.pack_start (_switch_bar);

            var revealer = new Gtk.Revealer ();
            revealer.child = _switch_bar2;
            revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_UP;
            insert_child_after (revealer, header_bar);
            _switch_bar2.stack = stack_view;
            _switch_bar.bind_property ("reveal-child", revealer, "reveal-child", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            app.index_changed.connect (on_index_changed);
            app.music_changed.connect (on_music_changed);
            app.music_external_changed.connect (on_music_external_changed);
            app.music_store_changed.connect (on_music_store_changed);
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
                if (_size_allocated) {
                    update_visible_store ();
                }
                if (value is Gtk.Stack) {
                    value = ((Gtk.Stack) value).visible_child;
                }
                if (value is MusicList) {
                    _current_list = (MusicList) value;
                    if (_current_list.playable) {
                        _app.music_list = _current_list.filter_model;
                        _current_list.current_item = _app.current_music;
                        run_idle_once (() => _current_list.scroll_to_current_item ());
                    }
                }
                sort_btn.sensitive = _current_list == _playing_list;
                _search_mode = SearchMode.ANY;
                on_search_btn_toggled ();

                var paths = new GenericArray<string> (4);
                get_library_paths (paths);
                paths.add ((string) null); // Must be null terminated 
                _app.settings.set_strv ("library-path", paths.data);
            }
        }

        public void size_allocated () {
            // Delay set model after the window size allocated to avoid showing slowly
            _playing_list.create_factory ();
            _playing_list.scroll_to_item (_app.current_item);
            _album_list.create_factory ();
            _artist_list.create_factory ();
            _playlist_list.create_factory ();
            _album_stack.bind_property ("visible-child", this, "visible-child", BindingFlags.DEFAULT);
            _artist_stack.bind_property ("visible-child", this, "visible-child", BindingFlags.DEFAULT);
            _playlist_stack.bind_property ("visible-child", this, "visible-child", BindingFlags.DEFAULT);
            stack_view.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack_view.bind_property ("visible-child", this, "visible-child", BindingFlags.DEFAULT);
            _size_allocated = true;
            initialize_library_view ();
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
            _search_mode = mode;
        }

        public bool toggle_search () {
            search_btn.active = ! search_btn.active;
            return search_btn.active;
        }

        private MusicList create_album_list (Artist? artist = null) {
            var list = new MusicList (_app, false, artist);
            list.item_activated.connect ((position, obj) => {
                if (obj is Album) {
                    create_sub_stack_page (artist, (Album) obj);
                }
            });
            list.item_created.connect ((item) => {
                var cell = (MusicWidget) item.child;
                make_right_clickable (cell, cell.show_popover_menu);
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicWidget) item.child;
                var album = (Album) item.item;
                var album_artist = album.album_artist;
                var year = album.year;
                cell.music = album;
                cell.paintable = _loading_paintable;
                cell.title = album.album;
                var subtitle = year > 0 ? year.to_string () : " ";
                if (artist == null)
                    subtitle = (album_artist.length > 0 ? album_artist + " " : "") + subtitle;
                cell.subtitle = subtitle;
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            _app.settings.bind ("grid-mode", list, "grid-mode", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_artist_list () {
            var list = new MusicList (_app, false);
            list.item_activated.connect ((position, obj) => {
                if (obj is Artist) {
                    create_sub_stack_page ((Artist) obj);
                }
            });
            list.item_created.connect ((item) => {
                var cell = (MusicWidget) item.child;
                cell.cover.ratio = 0.5;
                make_right_clickable (cell, cell.show_popover_menu);
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicWidget) item.child;
                var artist = (Artist) item.item;
                cell.music = artist;
                cell.paintable = _loading_paintable;
                cell.title = artist.name;
                cell.subtitle = "";
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            _app.settings.bind ("grid-mode", list, "grid-mode", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_music_list (Album album, bool from_artist = false) {
            var sort_mode = (album is Playlist && from_artist) ? SortMode.ALBUM : SortMode.TITLE;
            var list = new MusicList (_app, true, album);
            list.item_activated.connect ((position, obj) => _app.current_item = (int) position);
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.playing = music == _app.current_music;
                entry.set_titles (music, sort_mode);
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                make_right_clickable (entry, entry.show_popover_menu);
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_playing_music_list () {
            var list = new MusicList (_app, true);
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
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_playlist_list () {
            var list = new MusicList (_app, false);
            list.item_activated.connect ((position, obj) => {
                if (obj is Playlist) {
                    create_sub_stack_page (null, (Playlist) obj);
                }
            });
            list.item_created.connect ((item) => {
                var cell = (MusicWidget) item.child;
                make_right_clickable (cell, cell.show_popover_menu);
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicWidget) item.child;
                var playlist = (Playlist) item.item;
                cell.music = playlist;
                cell.paintable = _loading_paintable;
                cell.title = playlist.title;
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            _app.settings.bind ("grid-mode", list, "grid-mode", SettingsBindFlags.DEFAULT);
            return list;
        }

        private void create_sub_stack_page (Artist? artist = null, Album? album = null) {
            var album_mode = album != null;
            var artist_mode = artist != null;
            var playlist_mode = album is Playlist;
            var mlist = album_mode ? create_music_list ((!)album, artist_mode) : create_album_list (artist);
            mlist.create_factory ();

            var title = album_mode ? album?.album : artist?.name;
            var label = new Gtk.Label (title);
            label.ellipsize = Pango.EllipsizeMode.END;
            var icon = new Gtk.Image.from_icon_name (album_mode ? "media-optical-cd-audio-symbolic" : "avatar-default-symbolic");
            var label_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            label_box.append (icon);
            label_box.append (label);

            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = false;
            header.title_widget = label_box;
            header.add_css_class ("flat");
            mlist.prepend (header);

            var stack = artist_mode ? _artist_stack : playlist_mode ? _playlist_stack : _album_stack;
            var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
            back_btn.tooltip_text = _("Back");
            back_btn.clicked.connect (() => remove_stack_child (stack, mlist));
            header.pack_start (back_btn);

            var button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
            button.tooltip_text = _("Play");
            button.clicked.connect (() => {
                if (album_mode) {
                    _app.play (album);
                } else {
                    string[] strv = { PageName.ARTIST, artist?.name ?? "" };
                    _app.activate_action (ACTION_PLAY, new Variant.bytestring_array (strv));
                }
            });
            header.pack_end (button);

            stack.add_titled (mlist, album_mode ? album?.album_key : artist?.name, title ?? "");
            stack.visible_child = mlist;
        }

        private void get_library_paths (GenericArray<string> paths) {
            var visible_child = stack_view.visible_child;
            if (visible_child is Gtk.Stack) {
                var stack = (Gtk.Stack) visible_child;
                for (var child = (Gtk.Widget?) stack.visible_child; child is MusicList; child = child?.get_prev_sibling ()) {
                    paths.insert (0, stack.get_page ((!)child).name);
                }
            } else {
                paths.add (stack_view.get_visible_child_name () ?? "");
            }
        }

        private void initialize_library_view () {
            if (_library.playlists.length > 0 && _playlist_stack.get_parent () == null) {
                stack_view.add_titled (_playlist_stack, PageName.PLAYLIST, _("Playlists")).icon_name = "view-list-symbolic";
                _switch_bar.update_buttons ();
                _switch_bar2.update_buttons ();
            } else if (_library.playlists.length == 0 && _playlist_stack.get_parent () != null) {
                remove_stack_child (stack_view, _playlist_stack);
                _switch_bar.update_buttons ();
                _switch_bar2.update_buttons ();
            }
            if (_library_path != null && _library.albums.length > 0) {
                locate_to_path ((!)_library_path, null, true);
                _library_path = null;
            }
        }

        public void locate_to_path (string[] paths, Object? obj = null, bool initializing = false) {
            if (paths.length > 0) {
                stack_view.transition_type = Gtk.StackTransitionType.NONE;
                stack_view.visible_child_name = paths[0];
                stack_view.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
                var visible_child = stack_view.visible_child;
                if (visible_child is Gtk.Stack && paths.length > 1) {
                    var stack = (Gtk.Stack) visible_child;
                    if (initializing)
                        stack.transition_type = Gtk.StackTransitionType.NONE;
                    Artist? artist = null;
                    Album? album = obj as Album;
                    if (paths[0] == PageName.ARTIST) {
                        artist = _library.artists[paths[1]];
                        if (artist is Artist) {
                            if (stack.get_child_by_name (((!)artist).name) == null)
                                create_sub_stack_page (artist, null);
                            if (paths.length > 2) {
                                unowned var album_key = paths[2];
                                if (album_key.length > 0)
                                    album = ((!)artist)[album_key];
                                else if (album == null)
                                    album = ((!)artist).to_playlist ();
                            }
                        }
                    } else if (paths[0] == PageName.ALBUM) {
                        album = _library.albums[paths[1]];
                    } else if (paths[0] == PageName.PLAYLIST) {
                        album = _library.playlists[paths[1]];
                    }
                    if ((album is Album) && stack.get_child_by_name (((!)album).album_key) == null) {
                        create_sub_stack_page (artist, album);
                    }
                    stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
                }
            }
        }

        private void on_index_changed (int index, uint size) {
            root.action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
            root.action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
            if (_current_list.playable) {
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

        private void on_music_changed (Music? music) {
            _current_list.current_item = music;
        }

        private void on_music_external_changed () {
            _album_list.data_store.remove_all ();
            _artist_list.data_store.remove_all ();
            _playlist_list.data_store.remove_all ();
            update_visible_store ();

            for (var child = stack_view.get_last_child (); child is Gtk.Stack; child = child?.get_prev_sibling ())
                update_stack_pages ((Gtk.Stack) child);
        }

        private void on_music_store_changed () {
            if (_size_allocated) {
                update_visible_store ();
                initialize_library_view ();
            }
        }

        private void on_search_btn_toggled () {
            if (search_btn.active) {
                search_entry.grab_focus ();
            }
            on_search_text_changed ();
        }

        private bool on_search_match (Object obj) {
            unowned var music = (Music) obj;
            unowned var text = _search_text;
            switch (_search_mode) {
                case SearchMode.ALBUM:
                    return text.match_string (music.album, true);
                case SearchMode.ARTIST:
                    return text.match_string (music.artist, true)
                        || text.match_string (music.album_artist, true)
                        || ((music as Artist)?.find_by_partial_artist (text) != null);
                case SearchMode.TITLE:
                    return text.match_string (music.title, true);
                default:
                    return text.match_string (music.album, true)
                        || text.match_string (music.album_artist, true)
                        || text.match_string (music.artist, true)
                        || text.match_string (music.title, true);
            }
        }

        private void on_search_text_changed () {
            _search_text = search_entry.text;
            parse_search_mode (ref _search_text, ref _search_mode);
            if (_current_list == _album_list) {
                _search_mode = SearchMode.ALBUM;
            } else if (_current_list == _artist_list) {
                _search_mode = SearchMode.ARTIST;
            }

            var model = _current_list.filter_model;
            if (search_btn.active && model.get_filter () == null) {
                model.set_filter (new Gtk.CustomFilter (on_search_match));
            } else if (!search_btn.active && model.get_filter () != null) {
                model.set_filter (null);
            }
            model.get_filter ()?.changed (Gtk.FilterChange.DIFFERENT);
        }

        private void remove_stack_child (Gtk.Stack stack, Gtk.Widget child) {
            var prev = child.get_prev_sibling ();
            if (prev != null)
                stack.visible_child = (!)prev;
            if (stack.transition_type == Gtk.StackTransitionType.NONE)
                stack.remove (child);
            else
                run_timeout_once (stack.transition_duration, () => stack.remove (child));
        }

        private void update_stack_pages (Gtk.Stack stack) {
            for (var child = stack.get_last_child (); child is MusicList; ) {
                var mlist = (MusicList) child;
                child = child?.get_prev_sibling ();
                if (mlist.update_store () == 0) {
                    stack.transition_type = Gtk.StackTransitionType.NONE;
                    remove_stack_child (stack, mlist);
                    stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
                }
            }
        }

        private void update_visible_store () {
            var visible_child = stack_view.visible_child;
            if (visible_child == _album_stack && _album_list.data_store.get_n_items () == 0) {
                _library.get_sorted_albums (_album_list.data_store);
            } else if (visible_child == _artist_stack && _artist_list.data_store.get_n_items () == 0) {
                _library.get_sorted_artists (_artist_list.data_store);
            } else if (visible_child == _playlist_stack && _playlist_list.data_store.get_n_items () == 0) {
                _library.get_sorted_playlists (_playlist_list.data_store);
            }
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
