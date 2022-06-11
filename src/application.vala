namespace Music {
    public const string ACTION_APP = "app.";
    public const string ACTION_ABOUT = "about";
    public const string ACTION_PREFS = "preferences";
    public const string ACTION_PLAY = "play";
    public const string ACTION_PREV = "prev";
    public const string ACTION_NEXT = "next";
    public const string ACTION_SEARCH = "search";
    public const string ACTION_SORT = "sort";
    public const string ACTION_QUIT = "quit";

    struct ActionShortKey {
        public weak string name;
        public weak string key;
    }

    public class Application : Adw.Application {
        private int _current_item = -1;
        private Song? _current_song = null;
        private GstPlayer _player = new GstPlayer ();
        private Gtk.FilterListModel _song_list = new Gtk.FilterListModel (null, null);
        private SongStore _song_store = new SongStore ();
        private Thumbnailer _thumbnailer = new Thumbnailer ();
        private Settings _settings = new Settings (Config.APP_ID);
        private MprisPlayer? _mpris = null;

        public signal void loading_changed (bool loading, uint size);
        public signal void index_changed (int index, uint size);
        public signal void song_changed (Song song);
        public signal void song_tag_parsed (Song song, Bytes? image, string? itype);

        public Application () {
            Object (application_id: Config.APP_ID, flags: ApplicationFlags.HANDLES_OPEN);

            ActionEntry[] action_entries = {
                { ACTION_ABOUT, show_about },
                { ACTION_PREFS, show_preferences },
                { ACTION_PLAY, play_pause },
                { ACTION_PREV, play_previous },
                { ACTION_NEXT, play_next },
                { ACTION_SEARCH, toggle_seach },
                { ACTION_QUIT, quit }
            };
            add_action_entries (action_entries, this);

            ActionEntry[] sort_entries = {
                { ACTION_SORT, sort_by, "u", "0" },
                { ACTION_SORT, sort_by, "u", "1" },
                { ACTION_SORT, sort_by, "u", "2" },
                { ACTION_SORT, sort_by, "u", "3" }
            };
            add_action_entries (sort_entries, this);

            ActionShortKey[] action_keys = {
                { ACTION_PLAY, "<primary>p" },
                { ACTION_PREV, "<primary>Left" },
                { ACTION_NEXT, "<primary>Right" },
                { ACTION_SEARCH, "<primary>f" },
                { ACTION_QUIT, "<primary>q" }
            };
            foreach (var item in action_keys) {
                set_accels_for_action (ACTION_APP + item.name, {item.key});
            }

            _song_list.model = _song_store.store;

            dark_theme = _settings.get_boolean ("dark-theme");

            sort_mode = (SortMode) _settings.get_uint ("sort-mode");

            _player.show_peak (_settings.get_boolean ("show-peak"));
            _player.use_pipewire (_settings.get_boolean ("pipewire-sink"));
            _player.volume = _settings.get_double ("volume");
            _thumbnailer.remote_thumbnail = _settings.get_boolean ("remote-thumbnail");

            _player.end_of_stream.connect (() => {
                if (single_loop) {
                    _player.seek (0);
                    _player.play ();
                } else {
                    current_item++;
                }
            });

            _player.tag_parsed.connect (on_tag_parsed);

            var mpris_id = Bus.own_name (BusType.SESSION,
                "org.mpris.MediaPlayer2." + application_id,
                BusNameOwnerFlags.NONE,
                on_bus_acquired,
                null, null
            );
            if (mpris_id == 0)
                warning ("Initialize MPRIS session failed\n");
        }

        public override void activate () {
            base.activate ();

            Gtk.Window? awindow = active_window;
            if (awindow != null) {
                active_window.present ();
            } else {
                open ({}, "");
            }
        }

        public override void open (File[] files, string hint) {
            load_songs_async.begin (files, (obj, res) => {
                var play_item = load_songs_async.end (res);
                Idle.add (() => {
                    current_item = play_item;
                    if (files.length > 0)
                        _player.play ();
                    return false;
                });
            });

            Gtk.Window? awindow = active_window;
            var window = awindow ?? new Window (this);
            window.present ();
        }

        public override void shutdown () {
             _settings.set_string ("played-uri", _current_song?.uri ?? "");
             _settings.set_double ("volume", _player.volume);

             delete_cover_tmp_file_async.begin ((obj, res) => {
                delete_cover_tmp_file_async.end (res);
             });

            base.shutdown ();
        }

        public int current_item {
            get {
                return _current_item;
            }
            set {
                var count = _song_list.get_n_items ();
                value = value < count ? value : 0;
                var playing = _current_song != null;
                var song = _song_list.get_item (value) as Song;
                if (song != null && _current_song != song) {
                    _current_song = song;
                    _player.uri = ((!)song).uri;
                    song_changed ((!)song);
                }
                if (_current_item != value) {
                    var old_item = _current_item;
                    _current_item = value;
                    _song_list.items_changed (old_item, 0, 0);
                    _song_list.items_changed (value, 0, 0);
                    index_changed (value, count);
                }
                _player.state = playing ? Gst.State.PLAYING : Gst.State.PAUSED;
            }
        }

        public Song? current_song {
            get {
                return _current_song;
            }
        }

        public bool dark_theme {
            set {
                style_manager.color_scheme = value ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.DEFAULT;
            }
        }

        public GstPlayer player {
            get {
                return _player;
            }
        }

        public Settings settings {
            get {
                return _settings;
            }
        }

        public bool single_loop { get; set; }

        public Gtk.FilterListModel song_list {
            get {
                return _song_list;
            }
        }

        public SortMode sort_mode {
            get {
                return _song_store.sort_mode;
            }
            set {
                _song_store.sort_mode = value;
            }
        }

        public Thumbnailer thumbnailer {
            get {
                return _thumbnailer;
            }
        }

        public File get_music_folder () {
            var music_uri = _settings.get_string ("music-dir");
            if (music_uri.length > 0) {
                return File.new_for_uri (music_uri);
            }
            var music_path = Environment.get_user_special_dir (UserDirectory.MUSIC);
            return File.new_for_path (music_path);
        }

        public void play_next () {
            current_item = current_item + 1;
        }

        public void play_pause() {
            _player.playing = !_player.playing;
        }

        public void play_previous () {
            current_item = current_item - 1;
        }

        public void reload_song_store () {
            _song_store.clear ();
            _current_item = -1;
            index_changed (-1, 0);
            load_songs_async.begin ({}, (obj, res) => {
                current_item = load_songs_async.end (res);
            });
        }

        private void sort_by (SimpleAction action, Variant? parameter) {
            sort_mode = (SortMode) (parameter?.get_uint32 () ?? 2);
            _settings.set_uint ("sort-mode", sort_mode);
            find_current_item ();
        }

        public void toggle_seach () {
            var win = active_window as Window;
            if (win != null)
                ((!)win).search_btn.active = ! ((!)win).search_btn.active;
        }

        public bool find_current_item () {
            if (_song_list.get_item (_current_item) == _current_song)
                return false;

            //  find current item
            var old_item = _current_item;
            var count = _song_list.get_n_items ();
            _current_item = -1;
            for (var i = 0; i < count; i++) {
                if (_current_song == _song_list.get_item (i)) {
                    _current_item = i;
                    break;
                }
            }
            if (old_item != _current_item) {
                _song_list.items_changed (old_item, 0, 0);
                _song_list.items_changed (_current_item, 0, 0);
                index_changed (_current_item, count);
                return true;
            }
            return false;
        }

        public async int load_songs_async (owned File[] files) {
            var saved_size = _song_store.size;
            var play_item = _current_item;
            loading_changed (true, saved_size);

            if (saved_size == 0 && files.length == 0) {
#if HAS_TRACKER_SPARQL
                if (_settings.get_boolean ("tracker-mode")) {
                    yield _song_store.add_sparql_async ();
                } else
#endif
                {
                    files.resize (1);
                    files[0] = get_music_folder ();
                }
            }
            if (files.length > 0) {
                yield _song_store.add_files_async (files);
            }

            loading_changed (false, _song_store.size);
            if (saved_size > 0) {
                play_item = (int) saved_size;
            } else if (_current_song != null && _current_song == _song_list.get_item (_current_item)) {
                play_item = _current_item;
            } else {
                var uri = _current_song?.uri ?? _settings.get_string ("played-uri");
                if (uri.length > 0) {
                    var count = _song_list.get_n_items ();
                    for (var i = 0; i < count; i++) {
                        var song = (Song) _song_list.get_item (i);
                        if (uri == song.uri) {
                            play_item = i;
                            break;
                        }
                    }
                }
            }
            return play_item;
        }

        public void show_about () {
            string[] authors = { "Nanling" };
            Gtk.show_about_dialog (active_window,
                                   "logo-icon-name", application_id,
                                   "program-name", _("G4Music"),
                                   "authors", authors,
                                   "version", Config.VERSION,
                                   "license-type", Gtk.License.GPL_3_0,
                                   "comments", _("A fast, flurent, light weight music player written in GTK4.")
                                  );
        }

        public void show_preferences () {
            activate ();
            var win = new PreferencesWindow (this);
            win.destroy_with_parent = true;
            win.transient_for = active_window;
            win.modal = true;
            win.present ();
        }

        private void on_bus_acquired (DBusConnection connection, string name) {
            _mpris = new MprisPlayer (this, connection);
            try {
                connection.register_object ("/org/mpris/MediaPlayer2", _mpris);
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisRoot ());
            } catch (Error e) {
                warning ("Register MPRIS failed: %s\n", e.message);
            }
        }

        private File? _cover_tmp_file = null;

        private async void delete_cover_tmp_file_async () {
            try {
                if (_cover_tmp_file != null) {
                    yield ((!)_cover_tmp_file).delete_async ();
                    _cover_tmp_file = null;
                }
            } catch (Error e) {
            }
        }

        private async void on_tag_parsed (string? album, string? artist, string? title, Bytes? image, string? itype) {
            if (_current_song != null) {
                var song = (!)current_song;
                song_tag_parsed (song, image, itype);

                if (image != null) try {
                    var file = File.new_build_filename (Environment.get_tmp_dir (), application_id + "_" + str_hash (song.uri).to_string ("%x"));
                    var stream = yield file.create_async (FileCreateFlags.REPLACE_DESTINATION);
                    yield stream.write_async (image?.get_data ());
                    yield stream.close_async ();
                    yield delete_cover_tmp_file_async ();
                    _cover_tmp_file = file;

                    if (song == _current_song) {
                        _mpris?.send_meta_data (song, file.get_uri ());
                    }
                } catch (Error e) {
                    //  print ("Temp file failed: %s\n", e.message);
                }
            }
        }
    }
}
