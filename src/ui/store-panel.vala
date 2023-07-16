namespace G4 {

    namespace PageType {
        public const uint ALL = 0;
        public const uint ALBUM = 1;
        public const uint ALBUMS = 2;
        public const uint ARTIST = 3;
        public const uint ARTISTS = 4;
    }

    namespace SearchMode {
        public const uint ALL = 0;
        public const uint ALBUM = 1;
        public const uint ARTIST = 2;
        public const uint TITLE = 3;
    }

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
        private MusicLibrary _library;
        private Gdk.Paintable _loading_paintable;
        private Adw.TabPage? _current_page = null;
        private uint _current_page_type = PageType.ALL;
        private uint _sort_mode = 0;

        private string _search_text = "";
        private string _search_property = "";
        private uint _search_mode = SearchMode.ALL;

        public StorePanel (Application app, Window win, Adw.Leaflet leaflet) {
            _app = app;
            _library = app.music_store.library;

            leaflet.bind_property ("folded", header_bar, "show-title-buttons", BindingFlags.SYNC_CREATE);

            search_btn.toggled.connect (on_search_btn_toggled);
            search_bar.key_capture_widget = win.content;
            search_entry.search_changed.connect (on_search_text_changed);

            _app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = _app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            _artist_list = create_artist_list ();
            _album_list = create_album_list_from_artist ();

            _current_list = create_music_list ();
            add_tab_page (_current_list, PageType.ALL, _("All"), true);
            add_tab_page (_artist_list, PageType.ARTISTS, _("Artists"), true);
            add_tab_page (_album_list, PageType.ALBUMS, _("Albums"), true);
            Idle.add (() => {
                // Delay set model after the window shown to avoid slowing down it showing
                if (win.get_height () > 0) {
                    tab_view.bind_property ("selected-page", this, "selected-page", BindingFlags.SYNC_CREATE);
                    _current_list.data_model = _app.music_store.store;
                    _current_list.filter_model = _app.music_list;
                    run_idle_once (() => scroll_to_item (_app.current_item), Priority.HIGH);
                }
                return win.get_height () == 0;
            }, Priority.LOW);

            app.index_changed.connect (on_index_changed);
            app.music_store.loading_changed.connect (on_loading_changed);

            app.settings.bind ("sort-mode", this, "sort-mode", SettingsBindFlags.DEFAULT);
        }

        private const string[] SORT_MODE_ICONS = {
            "media-optical-cd-audio-symbolic",  // ALBUM
            "system-users-symbolic",            // ARTIST
            "avatar-default-symbolic",          // ARTIST_ALBUM
            "folder-music-symbolic",            // TITLE
            "document-open-recent-symbolic",    // RECENT
            "media-playlist-shuffle-symbolic",  // SHUFFLE
        };

        public unowned Adw.TabPage? selected_page {
            get {
                return _current_page;
            }
            set {
                if (value != null && value != _current_page) {
                    var page = (!)value;
                    var type = page.get_qdata<uint> (_page_type_quark);
                    _current_list.filter_model = null;
                    _current_list = (MusicList) page.child;
                    _current_list.filter_model = _app.music_list;
                    _current_page = value;
                    _current_page_type = type;
                    sort_btn.visible = type == PageType.ALL;
                }
            }
        }

        public uint sort_mode {
            get {
                return _sort_mode;
            }
            set {
                _sort_mode = value;
                if (value < SORT_MODE_ICONS.length) {
                    sort_btn.set_icon_name (SORT_MODE_ICONS[value]);
                    if (_current_list.item_count > 0)
                        _current_list.create_factory ();
                }
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            base.snapshot (snapshot);
            var color = Gdk.RGBA ();
            color.red = color.green = color.blue = color.alpha = 0.5f;
            var line_width = scale_factor >= 2 ? 0.5f : 1;
            var allocation = Gtk.Allocation ();
            tab_view.get_allocation (out allocation);
            var rect = Graphene.Rect ();
#if ADW_1_2
            rect.init (allocation.x, allocation.y, allocation.width, line_width);
            snapshot.append_color (color, rect);
#endif
            rect.init (allocation.x, allocation.y + allocation.height, allocation.width, line_width);
            snapshot.append_color (color, rect);
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

        private const string[] PAGE_TYPE_ICONS = {
            "view-list-symbolic",               // ALL
            "media-optical-cd-audio-symbolic",  // ALBUM
            "drive-multidisk-symbolic",         // ALBUMS
            "avatar-default-symbolic",          // ARTIST
            "system-users-symbolic",            // ARTISTS
        };

        private Quark _page_type_quark = Quark.from_string ("icon_name_quark");

        private Adw.TabPage add_tab_page (Gtk.Widget widget, uint type, string title, bool pinned = false) {
            if (!pinned) {
                var pages = tab_view.pages;
                for (var i = (int) pages.get_n_items () - 1; i >= 0; i--) {
                    var page = (Adw.TabPage) pages.get_item (i);
                    if (page.pinned == pinned && page.title == title
                            && page.get_qdata<uint> (_page_type_quark) == type) {
                        tab_view.selected_page = page;
                        return page;
                    }
                }
            }

            var icon_name = type < PAGE_TYPE_ICONS.length ? PAGE_TYPE_ICONS[type] : "";
            var page = pinned ? tab_view.append_pinned (widget) : tab_view.append (widget);
            page.icon = new ThemedIcon (icon_name);
            page.title = page.tooltip = title;
            page.set_qdata<uint> (_page_type_quark, type);
            if (!pinned)
                tab_view.selected_page = page;
            return page;
        }

        private MusicList create_album_list_from_artist (Artist? artist = null) {
            var list = new MusicList (_app);
            if (artist != null) {
                var store = new ListStore (typeof (Music));
                ((!)artist).albums.foreach ((name, album) => store.append (album.cover_music));
                store.sort ((CompareDataFunc) Music.compare_by_album);
                list.data_model = store;
            }
            list.item_activated.connect ((position, obj) => {
                unowned var album = _library.albums.lookup ((obj as Music)?.album ?? "");
                if (album is Album) {
                    var mlist = create_music_list (album);
                    add_tab_page (mlist, PageType.ALBUM, album.name);
                }
            });
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.update_title (music.album);
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_artist_list () {
            var list = new MusicList (_app);
            list.item_activated.connect ((position, obj) => {
                unowned var artist = _library.artists.lookup ((obj as Music)?.artist ?? "");
                if (artist is Artist) {
                    if (artist.albums.length == 1) {
                        unowned var album = artist.albums.get_values ().first ().data;
                        var mlist = create_music_list (album);
                        add_tab_page (mlist, PageType.ALBUM, album.name);
                    } else {
                        var mlist = create_album_list_from_artist (artist);
                        add_tab_page (mlist, PageType.ARTIST, artist.name);
                    }
                }
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                entry.cover.ratio = 0.5;
            });
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.update_title (music.artist);
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            return list;
        }

        private MusicList create_music_list (Album? album = null) {
            var list = new MusicList (_app);
            if (album != null) {
                var store = new ListStore (typeof (Music));
                ((!)album).musics.foreach ((uri, music) => store.append (music));
                store.sort ((CompareDataFunc) Music.compare_by_album);
                list.data_model = store;
            }
            list.item_activated.connect ((position, obj) => {
                _app.current_item = (int) position;
            });
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.paintable = _loading_paintable;
                entry.playing = music == _app.current_music;
                if (album != null) {
                    var subtitle = (0 < music.track < int.MAX) ? @"$(music.track). $(music.title)" : music.title;
                    entry.update_title (music.artist, subtitle);
                } else {
                    entry.update (music, _sort_mode);
                }
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                entry.setup_right_clickable ();
            });
            _app.settings.bind ("compact-playlist", list, "compact-list", SettingsBindFlags.DEFAULT);
            return list;
        }

        private void on_index_changed (int index, uint size) {
            if (_current_page_type <= PageType.ALBUM) {
                root.action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
                root.action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
                index_title.label = size > 0 ? @"$(index+1)/$(size)" : "";
                scroll_to_item (index);
            } else {
                index_title.label = size > 0 ? @"$(size)" : "";
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
                var albums = new ListStore (typeof (Music));
                _library.albums.foreach ((name, album) => albums.append (album.cover_music));
                albums.sort ((CompareDataFunc) Music.compare_by_album);
                _album_list.data_model = albums;

                var artists = new ListStore (typeof (Music));
                _library.artists.foreach ((name, artist) => artists.append (artist.cover_music));
                artists.sort ((CompareDataFunc) Music.compare_by_artist);
                _artist_list.data_model = artists;
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
            _app.music_list.set_filter (search_btn.active ? new Gtk.CustomFilter (on_search_match) : (Gtk.CustomFilter?) null);
        }
    }
}
