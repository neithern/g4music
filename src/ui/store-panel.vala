namespace G4 {

    namespace PageType {
        public const uint PLAYING = 0;
        public const uint ALBUMS = 1;
        public const uint ARTIST = 2;
        public const uint ARTISTS = 3;
    }

    namespace SearchMode {
        public const uint ALL = 0;
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

    public const string[] PAGE_TYPE_ICONS = {
        "media-playback-start-symbolic",    // PLAYING
        "drive-multidisk-symbolic",         // ALBUMS
        "avatar-default-symbolic",          // ARTIST
        "system-users-symbolic",            // ARTISTS
    };

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/store-panel.ui")]
    public class StorePanel : Gtk.Box {
        [GtkChild]
        private unowned Gtk.HeaderBar header_bar;
        [GtkChild]
        private unowned Gtk.ProgressBar progress_bar;
        [GtkChild]
        private unowned Gtk.Label index_title;
        [GtkChild]
        private unowned Gtk.MenuButton sort_btn;
        [GtkChild]
        public unowned Gtk.ToggleButton search_btn;
        [GtkChild]
        private unowned Gtk.SearchBar search_bar;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry;
        [GtkChild]
        private unowned Adw.TabView tab_view;

        private Application _app;
        private MusicList _album_list;
        private MusicList _artist_list;
        private MusicList _current_list;
        private MusicList _playing_list;
        private MusicLibrary _library;
        private Gdk.Paintable _loading_paintable;
        private string _search_text = "";
        private string _search_property = "";
        private uint _search_mode = SearchMode.ALL;
        private uint _sort_mode = 0;

        public StorePanel (Application app, Window win, Adw.Leaflet leaflet) {
            _app = app;
            _library = app.music_store.library;

            leaflet.bind_property ("folded", header_bar, "show-title-buttons", BindingFlags.SYNC_CREATE);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = win.content;
            search_entry.search_changed.connect (on_search_text_changed);

            _app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = _app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            _current_list = _playing_list = create_playing_music_list ();
            _playing_list.data_store = _app.music_store.store;
            _playing_list.filter_model = _app.music_list;
            ensure_playing_page ();

            _album_list = create_albums_list ();
            _artist_list = create_artist_list ();
            append_tab_page (_artist_list, PageType.ARTISTS, _("Artists"), true);
            append_tab_page (_album_list, PageType.ALBUMS, _("Albums"), true);

            Idle.add (() => {
                // Delay set model after the window shown to avoid slowing down it showing
                if (win.get_height () > 0) {
                    _album_list.create_factory ();
                    _artist_list.create_factory ();
                    _app.settings.bind ("compact-playlist", _playing_list, "compact-list", SettingsBindFlags.DEFAULT);
                    _app.settings.bind ("sort-mode", this, "sort-mode", SettingsBindFlags.DEFAULT);
                    tab_view.bind_property ("selected-page", this, "selected-page", BindingFlags.SYNC_CREATE);
                }
                return win.get_height () == 0;
            }, Priority.LOW);

            app.index_changed.connect (on_index_changed);
            app.music_store.loading_changed.connect (on_loading_changed);
        }

        private Adw.TabPage? _current_page = null;

        public unowned Adw.TabPage? selected_page {
            get {
                return _current_page;
            }
            set {
                if (value != null && value != _current_page) {
                    var page = (!)value;
                    var child = (MusicList) page.child;
                    var playing = child == _playing_list;
                    var filter = _current_list.filter_model.get_filter ();
                    _current_list = child;
                    _current_list.filter_model.set_filter (filter);
                    _current_page = value;
                    sort_btn.visible = playing;
                    if (playing && _current_list.visible_count > 0) {
                        run_idle_once (() => scroll_to_item (_app.current_item));
                    }
                }
            }
        }

        public uint sort_mode {
            get {
                return _sort_mode;
            }
            set {
                _sort_mode = value;
                if (value < SORT_MODE_ICONS.length)
                    sort_btn.set_icon_name (SORT_MODE_ICONS[value]);

                var store = _playing_list.data_store;
                if (value == SortMode.SHUFFLE)
                    shuffle_order (store);
                var compare = (CompareDataFunc) get_sort_compare (value);
                store.sort (compare);

                if (_playing_list.visible_count > 0) {
                    _playing_list.create_factory ();
                }
            }
        }

        public void scroll_to_item (int index) {
            _current_list.scroll_to_item (index);
        }

        public void start_search (string text) {
#if GTK_4_10
            var delay = search_entry.search_delay;
            search_entry.search_delay = 0;
            run_idle_once (() => search_entry.search_delay = delay);
#endif
            search_entry.text = text;
            search_entry.select_region (text.index_of_char (':') + 1, -1);
            search_btn.active = true;
        }

        private Quark _page_type_quark = Quark.from_string ("icon_name_quark");

        private Adw.TabPage append_tab_page (Gtk.Widget widget, uint type, string title, bool pinned = false) {
            var page0 = find_tab_page (type, pinned, title);
            if (page0 != null) {
                return (!)page0;
            }

            var icon_name = type < PAGE_TYPE_ICONS.length ? PAGE_TYPE_ICONS[type] : "";
            var page = pinned ? tab_view.append_pinned (widget) : tab_view.append (widget);
            page.icon = new ThemedIcon (icon_name);
            page.title = page.tooltip = title;
            page.set_qdata<uint> (_page_type_quark, type);
            return page;
        }

        private Adw.TabPage append_to_playing_page (Object? obj) {
            var store = _playing_list.data_store;
            if (obj is Album) {
                var album = (Album) obj;
                var arr = new GenericArray<Music> (album.musics.length);
                var insert_pos = _app.current_item + 1;
                album.foreach ((uri, music) => {
                    arr.add (music);
                    uint position = -1;
                    if (store.find (music, out position)) {
                        store.remove (position);
                        if (insert_pos >= position)
                            insert_pos--;
                    }
                });
                arr.sort (Music.compare_by_album);
                if (insert_pos < 0)
                    insert_pos = 0;
                store.splice (insert_pos, 0, arr.data);
                _app.current_item = insert_pos;
            }
            if (obj is Music) {
                var music = (Music) obj;
                uint position = -1;
                if (store.find (music, out position)) {
                    _app.current_item = (int) position;
                } else {
                    store.append (music);
                    _app.current_item = (int) store.get_n_items () - 1;
                }
            }
            return ensure_playing_page ();
        }

        private Adw.TabPage ensure_playing_page () {
            return append_tab_page (_playing_list, PageType.PLAYING, _("Playing"), true);
        }

        private Adw.TabPage? find_tab_page (uint type, bool pinned, string title) {
            var pages = tab_view.pages;
            for (var i = (int) pages.get_n_items () - 1; i >= 0; i--) {
                var page = (Adw.TabPage) pages.get_item (i);
                if (page.pinned == pinned && page.get_qdata<uint> (_page_type_quark) == type
                        && page.title == title) {
                    return page;
                }
            }
            return null;
        }

        private MusicList create_albums_list (Artist? artist = null) {
            var list = new MusicList (_app, true);
            list.item_activated.connect ((position, obj) => {
                unowned var album = _library.albums.lookup ((obj as Music)?.album ?? "");
                append_to_playing_page (album);
            });
            list.item_binded.connect ((item) => {
                var entry = (MusicCell) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.title = music.album;
            });
            if (artist != null) {
                var store = list.data_store;
                ((!)artist).albums.foreach ((name, album) => store.append (album.cover_music));
                store.sort ((CompareDataFunc) Music.compare_by_album);
            }
            return list;
        }

        private MusicList create_artist_list () {
            var list = new MusicList (_app, true);
            list.item_activated.connect ((position, obj) => {
                unowned var artist = _library.artists.lookup ((obj as Music)?.artist ?? "");
                if (artist is Artist) {
                    if (artist.albums.length == 1) {
                        unowned var album = artist.albums.get_values ().first ().data;
                        append_to_playing_page (album);
                    } else {
                        var mlist = create_albums_list (artist);
                        mlist.create_factory ();
                        tab_view.selected_page = append_tab_page (mlist, PageType.ARTIST, artist.name);
                    }
                }
            });
            list.item_created.connect ((item) => {
                var entry = (MusicCell) item.child;
                entry.cover.ratio = 0.5;
            });
            list.item_binded.connect ((item) => {
                var entry = (MusicCell) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.title  = music.artist;
            });
            return list;
        }

        private MusicList create_playing_music_list () {
            var list = new MusicList (_app);
            list.item_activated.connect ((position, obj) => {
                _app.current_item = (int) position;
            });
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.playing = music == _app.current_music;
                entry.update (music, _sort_mode);
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                entry.setup_right_clickable ();
            });
            return list;
        }

        private void on_index_changed (int index, uint size) {
            root.action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
            root.action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
            index_title.label = size > 0 ? @"$(index+1)/$(size)" : "";
            if (_current_list == _playing_list && _current_list.visible_count > 0) {
                scroll_to_item (index);
            }
        }

        private uint _tick_handler = 0;

        private void on_loading_changed (bool loading) {
            root.action_set_enabled (ACTION_APP + ACTION_RELOAD_LIST, !loading);
            progress_bar.visible = loading;

            if (loading && _tick_handler == 0) {
                _tick_handler = add_tick_callback (on_loading_tick_callback);
            } else if (!loading && _tick_handler != 0) {
                remove_tick_callback (_tick_handler);
                _tick_handler = 0;
            }

            if (!loading) {
                var store = _app.music_store.store;
                var count = store.get_n_items ();
                var arr = new GenericArray<Music> (count);
                for (var i = 0; i < count; i++)
                    arr.add ((Music) store.get_item (i));
                if (_sort_mode == SortMode.SHUFFLE)
                    Music.shuffle_order (arr);
                arr.sort (get_sort_compare (_sort_mode));
                store.splice (0, count, arr.data);
                arr.remove_range (0, arr.length);
 
                _library.albums.foreach ((name, album) => arr.add (album.cover_music));
                arr.sort (Music.compare_by_album);
                _album_list.data_store.splice (0, _album_list.data_store.get_n_items (), arr.data);
                arr.remove_range (0, arr.length);

                _library.artists.foreach ((name, artist) => arr.add (artist.cover_music));
                arr.sort (Music.compare_by_artist);
                _artist_list.data_store.splice (0, _artist_list.data_store.get_n_items (), arr.data);
            }
        }

        private bool on_loading_tick_callback (Gtk.Widget widget, Gdk.FrameClock clock) {
            var fraction = _app.music_store.loading_progress;
            if (fraction > 0)
                progress_bar.fraction = fraction;
            else
                progress_bar.pulse ();
            return true;
        }

        private void on_search_btn_toggled () {
            if (search_btn.active) {
                search_entry.grab_focus ();
            }
            update_search_filter ();
        }

        private bool on_search_match (Object obj) {
            var music = (Music) obj;
            switch (_search_mode) {
                case SearchMode.ALBUM:
                    return _search_property.match_string (music.album, true);
                case SearchMode.ARTIST:
                    return _search_property.match_string (music.artist, true);
                case SearchMode.TITLE:
                    return _search_property.match_string (music.title, true);
                default:
                    return _search_text.match_string (music.album, true)
                        || _search_text.match_string (music.artist, true)
                        || _search_text.match_string (music.title, true);
            }
        }

        private void on_search_text_changed () {
            string text = search_entry.text;
            if (text.ascii_ncasecmp ("album:", 6) == 0) {
                _search_property = text.substring (6);
                _search_mode = SearchMode.ALBUM;
            } else if (text.ascii_ncasecmp ("artist:", 7) == 0) {
                _search_property = text.substring (7);
                _search_mode = SearchMode.ARTIST;
            } else if (text.ascii_ncasecmp ("title:", 6) == 0) {
                _search_property = text.substring (6);
                _search_mode = SearchMode.TITLE;
            } else {
                _search_mode = SearchMode.ALL;
            }
            _search_text = text;
            update_search_filter ();
        }

        private void update_search_filter () {
            _current_list.filter_model.set_filter (search_btn.active ? new Gtk.CustomFilter (on_search_match) : (Gtk.CustomFilter?) null);
        }
    }
}
