namespace G4 {

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
        private unowned Adw.ViewStack stack_view;

        private Adw.ViewStack _album_stack = new Adw.ViewStack ();
        private Adw.ViewStack _artist_stack = new Adw.ViewStack ();

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
            stack_view.add_titled (_playing_list, "Playing", _("Playing")).icon_name = "media-playback-start-symbolic";
            stack_view.visible_child = _playing_list;

            _artist_list = create_artist_list ();
            _artist_stack.add_named (_artist_list, "artists");
            stack_view.add_titled (_artist_stack, "Artists", _("Artists")).icon_name = "system-users-symbolic";

            _album_list = create_albums_list ();
            _album_stack.add_named (_album_list, "albums");
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
            insert_child_after (revealer, progress_bar);
            switcher.bind_property ("reveal-child", revealer, "reveal-child", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            Idle.add (() => {
                // Delay set model after the window shown to avoid slowing down it showing
                if (win.get_height () > 0) {
                    _album_list.create_factory ();
                    _artist_list.create_factory ();
                    _app.settings.bind ("compact-playlist", _playing_list, "compact-list", SettingsBindFlags.DEFAULT);
                    stack_view.bind_property ("visible-child", this, "visible-child", BindingFlags.SYNC_CREATE);
                }
                return win.get_height () == 0;
            }, Priority.LOW);

            app.index_changed.connect (on_index_changed);
            app.music_store.loading_changed.connect (on_loading_changed);
            app.settings.bind ("sort-mode", this, "sort-mode", SettingsBindFlags.DEFAULT);
        }

        public Gtk.Widget visible_child {
            set {
                var mlist = (MusicList) ((value as Adw.ViewStack)?.visible_child ?? value);
                var playing = mlist == _playing_list;
                var filter = _current_list.filter_model.get_filter ();
                _current_list = mlist;
                _current_list.filter_model.set_filter (filter);
                sort_btn.sensitive = playing;
                if (playing && _current_list.visible_count > 0) {
                    run_idle_once (() => scroll_to_item (_app.current_item));
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

                if (_playing_list.get_height () > 0) {
                    _playing_list.create_factory ();
                }
            }
        }

        public void size_to_change (int panel_width) {
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

        public bool toggle_search () {
            search_btn.active = ! search_btn.active;
            return search_btn.active;
        }

        private void append_to_playing_page (Object? obj) {
            var store = _playing_list.data_store;
            if (obj is Album) {
                var album = (Album) obj;
                var arr = new GenericArray<Music> (album.musics.length);
                var old_item = _app.current_item;
                var insert_pos = (uint) store.get_n_items ();
                album.foreach ((uri, music) => {
                    arr.add (music);
                    uint position = -1;
                    if (store.find (music, out position)) {
                        store.remove (position);
                        if (insert_pos > position) {
                            insert_pos = position;
                        }
                    }
                });
                arr.sort (Music.compare_by_album);
                store.splice (insert_pos, 0, arr.data);
                _app.current_item = (int) insert_pos;
                _app.music_list.items_changed (old_item, 0, 0);
            } else if (obj is Music) {
                var music = (Music) obj;
                uint position = -1;
                if (store.find (music, out position)) {
                    _app.current_item = (int) position;
                } else {
                    store.append (music);
                    _app.current_item = (int) store.get_n_items () - 1;
                }
            }
        }

        private MusicList create_albums_list (Artist? artist = null) {
            var list = new MusicList (_app, true);
            list.item_activated.connect ((position, obj) => {
                var name = (obj as Music)?.album ?? "";
                var album = artist != null ? ((!)artist).albums.lookup (name) : _library.albums.lookup (name);
                if (album is Album) {
                    var mlist  = create_music_list (album, true);
                    mlist.create_factory ();
                    var stack = artist != null ? _artist_stack : _album_stack;
                    create_page_for_music_list (stack, mlist, name, album);
                }
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
                    var mlist = create_albums_list (artist);
                    mlist.create_factory ();
                    create_page_for_music_list (_artist_stack, mlist, artist.name);
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

        private MusicList create_music_list (Album album, bool from_artist = false) {
            var list = new MusicList (_app);
            list.item_activated.connect ((position, obj) =>
                                        append_to_playing_page (obj));
            list.item_binded.connect ((item) => {
                var entry = (MusicEntry) item.child;
                var music = (Music) item.item;
                entry.music = music;
                entry.paintable = _loading_paintable;
                entry.title = music.title;
            });
            list.item_created.connect ((item) => {
                var entry = (MusicEntry) item.child;
                entry.setup_right_clickable ();
            });
            var store = list.data_store;
            album.foreach ((uri, music) => store.append (music));
            store.sort ((CompareDataFunc) Music.compare_by_album);
            return list;
        }

        private MusicList create_playing_music_list () {
            var list = new MusicList (_app);
            list.item_activated.connect ((position, obj) =>
                                        _app.current_item = (int) position);
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

        private void create_page_for_music_list (Adw.ViewStack stack, MusicList mlist, string name, Album? album = null) {
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
                stack.remove (mlist);
                stack.visible_child = (!)prev;
            });
            header.pack_start (back_btn);

            if (album != null) {
                var play_btn = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
                play_btn.tooltip_text = _("Play All");
                play_btn.clicked.connect (() => append_to_playing_page (album));
                header.pack_end (play_btn);
            }

            stack.add_titled (mlist, name, name);
            stack.visible_child = mlist;
        }

        private void on_index_changed (int index, uint size) {
            root.action_set_enabled (ACTION_APP + ACTION_PREV, index > 0);
            root.action_set_enabled (ACTION_APP + ACTION_NEXT, index < (int) size - 1);
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
