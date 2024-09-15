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
    public class StorePanel : Gtk.Box, SizeWatcher {
        [GtkChild]
        private unowned Gtk.HeaderBar header_bar;
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

        private Stack _album_stack = new Stack ();
        private Stack _artist_stack = new Stack ();
        private Stack _playlist_stack = new Stack ();
        private MiniBar _mini_bar = new MiniBar ();
        private Gtk.StackSwitcher _switcher_top = new Gtk.StackSwitcher ();
        private Gtk.StackSwitcher _switcher_btm = new Gtk.StackSwitcher ();

        private Application _app;
        private MusicList _album_list;
        private MusicList _artist_list;
        private MusicList _current_list;
        private MusicList _playing_list;
        private MusicList _playlist_list;
        private MusicLibrary _library;
        private string[]? _library_path = null;
        private Gdk.Paintable _loading_paintable;
        private Gtk.Widget? _popped_child = null;
        private uint _search_mode = SearchMode.ANY;
        private string _search_text = "";
        private bool _size_allocated = false;
        private uint _sort_mode_playing = SortMode.TITLE;
        private bool _updating_store = false;

        public StorePanel (Application app, Window win, Leaflet leaflet) {
            _app = app;
            _library = app.loader.library;
            margin_bottom = 6;

            var thumbnailer = app.thumbnailer;
            thumbnailer.pango_context = get_pango_context ();
            thumbnailer.scale_factor = this.scale_factor;
            _loading_paintable = thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = win.content;
            search_entry.search_changed.connect (on_search_text_changed);

            _current_list = _playing_list = create_playing_music_list ();
            _playing_list.data_store = _app.music_store;
            _app.music_list = _playing_list.filter_model;
            stack_view.add_titled (_playing_list, PageName.PLAYING, _("Playing")).icon_name = "user-home-symbolic";

            _artist_list = create_artist_list ();
            _artist_stack.add (_artist_list, PageName.ARTIST);
            _artist_stack.popped.connect (on_page_popped);
            stack_view.add_titled (_artist_stack.widget, PageName.ARTIST, _("Artists")).icon_name = "system-users-symbolic";

            _album_list = create_album_list ();
            _album_stack.add (_album_list, PageName.ALBUM);
            _album_stack.popped.connect (on_page_popped);
            stack_view.add_titled (_album_stack.widget, PageName.ALBUM, _("Albums")).icon_name = "drive-multidisk-symbolic";

            _playlist_list = create_playlist_list ();
            _playlist_stack.popped.connect (on_page_popped);
            _playlist_stack.add (_playlist_list, PageName.PLAYLIST);
            stack_view.add_titled (_playlist_stack.widget, PageName.PLAYLIST, _("Playlists")).icon_name = "view-list-symbolic";

            var mini_revealer = new Gtk.Revealer ();
            mini_revealer.child = _mini_bar;
            mini_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_UP;
            _mini_bar.activated.connect (leaflet.push);
            append (mini_revealer);
            leaflet.bind_property ("folded", mini_revealer, "reveal-child", BindingFlags.SYNC_CREATE);
            leaflet.bind_property ("folded", header_bar, "show-title-buttons");

            var top_revealer = new NarrowBar ();
            top_revealer.child = _switcher_top;
            _switcher_top.stack = stack_view;
            fix_switcher_style (_switcher_top);
            header_bar.pack_end (top_revealer);

            var btm_revealer = new Gtk.Revealer ();
            btm_revealer.child = _switcher_btm;
            btm_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_UP;
            append (btm_revealer);
            top_revealer.bind_property ("reveal", btm_revealer, "reveal-child", BindingFlags.INVERT_BOOLEAN);

            _switcher_btm.margin_top = 2;
            _switcher_btm.margin_start = 6;
            _switcher_btm.margin_end = 6;
            _switcher_btm.stack = stack_view;
            fix_switcher_style (_switcher_btm);

            app.end_of_playlist.connect (on_end_of_playlist);
            app.index_changed.connect (on_index_changed);
            app.music_changed.connect (on_music_changed);
            app.music_store_changed.connect (on_music_store_changed);

            var settings = app.settings;
            settings.bind ("sort-mode", this, "sort-mode", SettingsBindFlags.DEFAULT);
            _library_path = settings.get_strv ("library-path");
        }

        public uint sort_mode {
            get {
                return _app.sort_mode;
            }
            set {
                if (_current_list == _playing_list)
                    _sort_mode_playing = value;
                update_sort_mode (value);
            }
        }

        public Gtk.Widget visible_child {
            set {
                if (_size_allocated) {
                    update_visible_store ();
                }
                if (value == stack_view.visible_child) {
                    var stack = get_current_stack ();
                    if (stack != null)
                        value = ((!)stack).visible_child;
                }
                if (value is MusicList) {
                    _current_list = (MusicList) value;
                    if (_current_list.playable) {
                        _app.music_list = _current_list.filter_model;
                        //  Update sort menu item
                        _app.sort_mode = _app.sort_mode;
                    }
                    on_music_changed (_app.current_music);

                    var removing = _popped_child != null;
                    _popped_child = null;
                    var mlist = _current_list;
                    run_idle_once (() => mlist.set_to_current_item (!removing));
                }
                sort_btn.sensitive = _current_list.playable;
                _search_mode = SearchMode.ANY;
                on_search_btn_toggled ();

                var paths = new GenericArray<string> (4);
                get_library_paths (paths);
                paths.add ((string) null); // Must be null terminated
                _app.settings.set_strv ("library-path", paths.data);
            }
        }

        public void first_allocated () {
            // Delay set model after the window size allocated to avoid showing slowly
            _playing_list.create_factory ();
            _playing_list.scroll_to_item (_app.current_item);
            _album_list.create_factory ();
            _artist_list.create_factory ();
            _playlist_list.create_factory ();
            _album_stack.bind_property ("visible-child", this, "visible-child");
            _artist_stack.bind_property ("visible-child", this, "visible-child");
            _playlist_stack.bind_property ("visible-child", this, "visible-child");
            stack_view.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack_view.bind_property ("visible-child", this, "visible-child");
            _size_allocated = true;
            initialize_library_view ();
        }

        public void set_mini_cover_and_title (Gdk.Paintable? cover, string title) {
            _mini_bar.cover = cover;
            _mini_bar.title = title;
        }

        public void size_to_change (int width, int height) {
        }

        public void start_search (string text, uint mode = SearchMode.ANY) {
            switch (mode) {
                case SearchMode.ALBUM:
                    stack_view.visible_child = _album_stack.widget;
                    break;
                case SearchMode.ARTIST:
                    stack_view.visible_child = _artist_stack.widget;
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
            var list = new MusicList (_app, typeof (Album), artist);
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
            var list = new MusicList (_app, typeof (Artist));
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
            var is_artist_playlist = album is Playlist && from_artist;
            var list = new MusicList (_app, typeof (Music), album);
            list.item_activated.connect ((position, obj) => _app.current_item = (int) position);
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                var mode = _app.get_list_sort_mode (list.data_store);
                if (is_artist_playlist && mode <= SortMode.ARTIST_ALBUM)
                    mode = SortMode.ALBUM;
                else if (from_artist && mode == SortMode.ARTIST)
                    mode = SortMode.ALBUM;
                else if (mode == SortMode.ALBUM)
                    mode = SortMode.TITLE;
                entry.set_titles (music, mode);
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                make_right_clickable (entry, entry.show_popover_menu);
            });
            _app.set_list_sort_mode (list.data_store, SortMode.ALBUM);
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_playing_music_list () {
            var list = new MusicList (_app, typeof (Music));
            list.item_activated.connect ((position, obj) => _app.current_item = (int) position);
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.set_titles (music, _sort_mode_playing);
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                make_right_clickable (entry, entry.show_popover_menu);
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_playlist_list () {
            var list = new MusicList (_app, typeof (Playlist));
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

        private void create_sub_stack_page (Artist? artist, Album? album = null) {
            var album_mode = album != null;
            var artist_mode = artist != null;
            var playlist_mode = album is Playlist;
            var mlist = album_mode ? create_music_list ((!)album, artist_mode) : create_album_list (artist);
            mlist.create_factory ();

            var title = album_mode ? album?.album : artist?.name;
            var label = new Gtk.Label (title);
            label.ellipsize = Pango.EllipsizeMode.END;
            var icon = new Gtk.Image.from_icon_name (album_mode ? "media-optical-cd-audio-symbolic" : "avatar-default-symbolic");
            var label_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            label_box.append (icon);
            label_box.append (label);

            var header = new Gtk.HeaderBar ();
            header.show_title_buttons = false;
            header.title_widget = label_box;
            header.add_css_class ("flat");
            mlist.prepend (header);

            var stack = artist_mode ? _artist_stack : playlist_mode ? _playlist_stack : _album_stack;
            var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
            back_btn.tooltip_text = _("Back");
            back_btn.clicked.connect (stack.pop);
            header.pack_start (back_btn);

            var button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
            button.tooltip_text = _("Play");
            button.clicked.connect (() => {
                if (album_mode) {
                    _app.current_item = 0;
                } else {
                    string[] strv = { PageName.ARTIST, artist?.name ?? "" };
                    _app.activate_action (ACTION_PLAY, new Variant.bytestring_array (strv));
                }
            });
            header.pack_end (button);

            stack.add (mlist, album_mode ? album?.album_key : artist?.name);
            stack.visible_child = mlist;
        }

        private Stack? get_current_stack () {
            var child = stack_view.visible_child;
            if (_artist_stack.widget == child)
                return _artist_stack;
            else if (_album_stack.widget == child)
                return _album_stack;
            else if (_playlist_stack.widget == child)
                return _playlist_stack;
            return null;
        }

        private void get_library_paths (GenericArray<string> paths) {
            var stack = get_current_stack ();
            if (stack != null) {
                ((!)stack).get_visible_names (paths);
            } else {
                paths.add (stack_view.get_visible_child_name () ?? "");
            }
            for (var i = 0; i < paths.length; i++) {
                paths[i] = Uri.escape_string (paths[i]);
            }
        }

        private void initialize_library_view () {
            if (_library_path != null && _library.albums.length > 0) {
                var paths = (!)_library_path;
                _library_path = null;
                for (var i = 0; i < paths.length; i++) {
                    paths[i] = Uri.unescape_string (paths[i]) ?? paths[i];
                }
                locate_to_path (paths, null, true);
            }
        }

        public void locate_to_path (string[] paths, Object? obj = null, bool initializing = false) {
            if (paths.length > 0) {
                stack_view.transition_type = Gtk.StackTransitionType.NONE;
                stack_view.visible_child_name = paths[0];
                stack_view.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
                var stack = get_current_stack ();
                if (stack != null && paths.length > 1) {
                    if (initializing) {
                        ((!)stack).animate_transitions = false;
                    }
                    Artist? artist = null;
                    Album? album = obj as Album;
                    if (paths[0] == PageName.ARTIST) {
                        artist = _library.artists[paths[1]];
                        if (artist is Artist) {
                            if (stack?.get_child_by_name (((!)artist).name) == null) {
                                create_sub_stack_page (artist);
                            }
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
                    if ((album is Album) && stack?.get_child_by_name (((!)album).album_key) == null) {
                        create_sub_stack_page (artist, album);
                    }
                    ((!)stack).animate_transitions = true;
                }
            }
        }

        private void on_end_of_playlist (bool forward) {
            var stk = get_current_stack ();
            if (stk != null && !_updating_store) {
                var stack = (!)stk;
                if (_current_list.playable) {
                    stack.animate_transitions = false;
                    stack.pop ();
                    stack.animate_transitions = true;
                }
                var item = _current_list.set_to_current_item (false);
                if ((forward && item >= (int) _current_list.visible_count - 1)
                    || (!forward && item <= 0)) {
                    stack.animate_transitions = false;
                    stack.pop ();
                    stack.animate_transitions = true;
                    item = _current_list.set_to_current_item (false);
                }
                _current_list.activate_item (forward ? item + 1 : item - 1);
                if (!_current_list.playable)
                    _current_list.activate_item (0);
            }
        }

        private void on_index_changed (int index, uint size) {
            if (_current_list.playable) {
                _current_list.scroll_to_item (index);
            }
        }

        private void on_music_changed (Music? music) {
            if (_current_list.playable) {
                _current_list.current_node = music;
            } else if (_current_list.item_type == typeof (Artist)) {
                var artist = music?.artist ?? "";
                _current_list.current_node = _library.artists[artist];
            } else if (_current_list.item_type == typeof (Album)) {
                var album = music?.album_key ?? "";
                var artist = _current_list.music_node as Artist;
                _current_list.current_node = artist != null ? ((!)artist)[album] : _library.albums[album];
            }
        }

        private void on_music_store_changed () {
            _updating_store = true;
            _album_list.data_store.remove_all ();
            _artist_list.data_store.remove_all ();
            _playlist_list.data_store.remove_all ();
            if (_size_allocated) {
                update_visible_store ();
                update_stack_pages (_artist_stack);
                update_stack_pages (_album_stack);
                update_stack_pages (_playlist_stack);
                initialize_library_view ();
            }
            _updating_store = false;
        }

        private void on_page_popped (Gtk.Widget? child) {
            _popped_child = child;
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

        private void update_sort_mode (uint mode) {
            if (mode < SORT_MODE_ICONS.length) {
                sort_btn.set_icon_name (SORT_MODE_ICONS[mode]);
            }
            if (_current_list.get_height () > 0) {
                _current_list.create_factory ();
            }
        }

        private void update_stack_pages (Stack stack) {
            var animate = stack.animate_transitions;
            stack.animate_transitions = false;
            var children = stack.get_children ();
            for (var i = children.length - 1; i >= 0; i--) {
                var mlist = (MusicList) children[i];
                if (mlist.update_store () == 0)
                    stack.remove (mlist);
            }
            stack.animate_transitions = animate;
        }

        private void update_visible_store () {
            var visible_child = stack_view.visible_child;
            if (visible_child == _album_stack.widget && _album_list.data_store.get_n_items () == 0) {
                _library.get_sorted_albums (_album_list.data_store);
            } else if (visible_child == _artist_stack.widget && _artist_list.data_store.get_n_items () == 0) {
                _library.get_sorted_artists (_artist_list.data_store);
            } else if (visible_child == _playlist_stack.widget && _playlist_list.data_store.get_n_items () == 0) {
                _library.get_sorted_playlists (_playlist_list.data_store);
                _playlist_list.set_empty_text (_("No playlist found"));
            }
        }
    }

    public void fix_switcher_style (Gtk.StackSwitcher switcher) {
        var layout = switcher.get_layout_manager () as Gtk.BoxLayout;
        layout?.set_spacing (4);
        switcher.remove_css_class ("linked");
        for (var child = switcher.get_first_child (); child != null; child = child?.get_next_sibling ()) {
            child?.add_css_class ("flat");
            ((!)child).width_request = 48;
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
