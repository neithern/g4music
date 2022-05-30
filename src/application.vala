namespace Music {

    struct ActionShortKey {
        public weak string name;
        public weak string key;
    }

    public class Application : Adw.Application {
        public static string ACTION_PREFIX = "app.";
        public static string ACTION_ABOUT = "about";
        public static string ACTION_PREFS = "preferences";
        public static string ACTION_PLAY = "play";
        public static string ACTION_PREV = "prev";
        public static string ACTION_NEXT = "next";
        public static string ACTION_SEARCH = "search";
        public static string ACTION_SHUFFLE = "shuffle";
        public static string ACTION_QUIT = "quit";

        private int _current_item = -1;
        private Song? _current_song = null;
        private GstPlayer _player = new GstPlayer ();
        private Gtk.FilterListModel _song_list = new Gtk.FilterListModel (null, null);
        private SongStore _song_store = new SongStore ();
        private Thumbnailer _thumbnailer = new Thumbnailer ();

        public signal void index_changed (int index, uint size);
        public signal void song_changed (Song song);
        public signal void song_tag_parsed (Song song, Bytes? image, string? mtype);

        public Application () {
            Object (application_id: "com.github.neithern.g4music",
                flags: ApplicationFlags.HANDLES_OPEN);

            ActionEntry[] action_entries = {
                { ACTION_ABOUT, show_about },
                { ACTION_PREFS, show_preferences },
                { ACTION_PLAY, play_pause },
                { ACTION_PREV, play_previous },
                { ACTION_NEXT, play_next },
                { ACTION_SEARCH, toggle_seach },
                { ACTION_SHUFFLE, toggle_shuffle },
                { ACTION_QUIT, quit }
            };
            add_action_entries (action_entries, this);

            ActionShortKey[] action_keys = {
                { ACTION_PLAY, "<primary>p" },
                { ACTION_PREV, "<primary>Left" },
                { ACTION_NEXT, "<primary>Right" },
                { ACTION_SEARCH, "<primary>f" },
                { ACTION_SHUFFLE, "<primary>t" },
                { ACTION_QUIT, "<primary>q" }
            };
            foreach (var item in action_keys) {
                set_accels_for_action (ACTION_PREFIX + item.name, {item.key});
            }

            _song_list.model = _song_store.store;

            _player.end_of_stream.connect (() => {
                current_item = current_item + 1;
            });

            _player.tag_parsed.connect ((info, image, mtype) => {
                if (_current_song.from_info (info)) {
                    _thumbnailer.update_text_paintable (_current_song);
                    _song_list.items_changed (_current_item, 0, 0);
                }
                song_tag_parsed (_current_song, image, mtype);
            });

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

            if (active_window != null) {
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

            var window = active_window ?? new Window (this);
            window.present ();
        }

        public override void shutdown () {
            var url = _current_song?.url;
            if (url != null) {
               save_playing_url (url);
            }

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
                    var old_item = _current_item;
                    _current_song = song;
                    _player.uri = song.url;
                    _current_item = value;
                    _song_list.items_changed (value, 0, 0);
                    _song_list.items_changed (old_item, 0, 0);
                    index_changed (value, count);
                    song_changed (song);
                }
                _player.state = playing ? Gst.State.PLAYING : Gst.State.PAUSED;
            }
        }

        public bool shuffle {
            get {
                return _song_store.shuffle;
            }
            set {
                _song_store.shuffle = value;
                find_current_item ();
            }
        }

        public Song current_song {
            get {
                return _current_song;
            }
        }

        public GstPlayer player {
            get {
                return _player;
            }
        }

        public Gtk.FilterListModel song_list {
            get {
                return _song_list;
            }
        }

        public Thumbnailer thumbnailer {
            get {
                return _thumbnailer;
            }
        }

        public File get_music_folder (Settings settings) {
            var music_path = settings.get_string ("music-dir");
            if (music_path == null || music_path.length == 0)
                music_path = Environment.get_user_special_dir (UserDirectory.MUSIC);
            return File.new_for_uri (music_path);
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
            load_songs_async.begin ({}, (obj, res) => {
                load_songs_async.end (res);
            });
        }

        public void toggle_seach () {
            var win = active_window as Window;
            if (win != null)
                win.search_btn.active = ! win.search_btn.active;
        }

        public void toggle_shuffle () {
            shuffle = !_song_store.shuffle;
        }

        public void find_current_item () {
            if (_song_list.get_item (_current_item) == _current_song)
                return;

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
            }
        }

        private async int load_songs_async (owned File[] files) {
            var saved_size = _song_store.size;
            var play_item = _current_item;

            var begin_time = get_monotonic_time ();
            if (saved_size == 0 && files.length == 0) {
                var settings = new Settings (application_id);
#if HAS_TRACKER_SPARQL
                if (settings.get_boolean ("tracker-mode")) {
                    yield _song_store.add_sparql_async ();
                }
#endif
                if (_song_store.size == 0) {
                    files.resize (1);
                    files[0] = get_music_folder (settings);
                }
            }
            if (files.length > 0) {
                yield _song_store.add_files_async (files);
            }
            print ("Found %u songs in %g seconds\n", _song_store.size - saved_size,
                (get_monotonic_time () - begin_time) / 1e6);

            if (saved_size > 0) {
                play_item = (int) saved_size;
            } else if (_current_song != null) {
                play_item = _current_item;
            } else {
                var url = yield run_async<string?> (load_playing_url);
                if (url != null) {
                    for (var i = 0; i < _song_store.size; i++) {
                        if (url == _song_store.get_song (i)?.url) {
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
                                   "program-name", "G4Music Player",
                                   "authors", authors,
                                   "version", "0.1.0");
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
            try {
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisPlayer (this, connection));
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisRoot ());
            } catch (Error e) {
                warning ("Register MPRIS failed: %s\n", e.message);
            }
        }

        private string? load_playing_url () {
            try {
                var dir = Environment.get_user_state_dir ();
                var file = File.new_build_filename (dir, application_id);
                var bytes = file.load_bytes (null, null);
                var key_file = new KeyFile ();
                key_file.load_from_bytes (bytes, KeyFileFlags.NONE);
                return key_file.get_string ("playing", "url");
            } catch (Error e) {
            }
            return null;
        }

        private void save_playing_url (string url) {
            try {
                var dir = Environment.get_user_state_dir ();
                var file = File.new_build_filename (dir, application_id);
                var key_file = new KeyFile ();
                key_file.set_string ("playing", "url", url);
                key_file.save_to_file (file.get_path ());
            } catch (Error e) {
                warning ("Save state failed: %s\n", e.message);
            }
        }
    }
}

int main (string[] args) {
    Music.GstPlayer.init (ref args);
    //  Environment.set_application_name ("G4Music");
    var app = new Music.Application ();
    return app.run (args);
}