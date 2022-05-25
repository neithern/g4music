namespace Music {

    public class Application : Adw.Application {
        public static string APP_ID = "com.github.neithern.g4music";

        public static string ACTION_PREFIX = "app.";
        public static string ACTION_ABOUT = "about";
        public static string ACTION_PLAY = "play";
        public static string ACTION_PREV = "prev";
        public static string ACTION_NEXT = "next";
        public static string ACTION_SHUFFLE = "shuffle";
        public static string ACTION_QUIT = "quit";

        private uint _current_item = -1;
        private Song? _current_song = null;
        private GstPlayer _player = new GstPlayer ();
        private Gtk.FilterListModel _song_list = new Gtk.FilterListModel (null, null);
        private SongStore _song_store = new SongStore ();
        private Thumbnailer _thumbnailer = new Thumbnailer ();

        public signal void index_changed (uint index, uint size);
        public signal void song_changed (Song song);
        public signal void song_tag_parsed (Song song, uint8[]? image);

        public Application () {
            Object (application_id: APP_ID, flags: ApplicationFlags.HANDLES_OPEN);
            this.application_id = APP_ID; // must set again???

            ActionEntry[] action_entries = {
                { ACTION_ABOUT, this.show_about },
                { ACTION_PLAY, this.play_pause },
                { ACTION_PREV, this.play_previous },
                { ACTION_NEXT, this.play_next },
                { ACTION_SHUFFLE, this.toggle_shuffle },
                { ACTION_QUIT, this.quit }
            };
            this.add_action_entries (action_entries, this);
            this.set_accels_for_action ("app.quit", {"<primary>q"});

            _song_list.model = _song_store.store;

            _player.end_of_stream.connect (() => {
                current_item = current_item + 1;
            });

            _player.tag_parsed.connect ((info, image) => {
                if (_current_song.from_info (info)) {
                    _song_list.items_changed (_current_item, 0, 0);
                }
                song_tag_parsed (_current_song, image);
            });

            var mpris_id = Bus.own_name (BusType.SESSION,
                "org.mpris.MediaPlayer2." + APP_ID,
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
                return;
            }

            open ({}, "");
        }

        public override void open (File[] files, string hint) {
            load_songs_async.begin (files, (obj, res) => {
                load_songs_async.end (res);
            });

            var window = active_window ?? new Window (this);
            window.present ();
        }

        public override void shutdown () {
            try {
                var dir = Environment.get_user_state_dir ();
                var file = File.new_build_filename (dir, application_id);
                var key_file = new KeyFile ();
                key_file.set_string ("playing", "url", _current_song?.url);
                key_file.save_to_file (file.get_path ());
            } catch (Error e) {
                warning ("Save state failed: %s\n", e.message);
            }
            base.shutdown ();
        }

        public uint current_item {
            get {
                return _current_item;
            }
            set {
                var count = _song_list.get_n_items ();
                if ((int) value < 0)
                    value = 0;
                else if (value >= count)
                    value = count - 1;
                if (value < count) {
                    var song = _song_list.get_item (value) as Song;
                    if (_current_song != song) {
                        var old_item = _current_item;
                        _current_song = song;
                        _player.uri = song.url;
                        _current_item = value;
                        _song_list.items_changed (value, 0, 0);
                        _song_list.items_changed (old_item, 0, 0);
                        index_changed (value, count);
                        song_changed (song);
                    }
                    _player.play ();
                }
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

        public void play_next () {
            current_item = current_item + 1;
        }

        public void play_pause() {
            _player.playing = !_player.playing;
        }

        public void play_previous () {
            current_item = current_item - 1;
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

        private async void load_songs_async (owned File[] files) {
            var saved_size = _song_store.size;
            var play_item = _current_item;

            if (saved_size == 0 && files.length == 0) {
                yield _song_store.add_sparql_async ();
                if (_song_store.size == 0) {
                    files.resize (1);
                    files[0] = File.new_for_path (Environment.get_user_special_dir (UserDirectory.MUSIC));
                }
            }
            if (files.length > 0) {
                yield _song_store.add_files_async (files);
            }

            if (saved_size == 0) {
                _song_store.shuffle = false; // sort by title
                try {
                    var dir = Environment.get_user_state_dir ();
                    var file = File.new_build_filename (dir, application_id);
                    var bytes = yield file.load_bytes_async (null, null);
                    var key_file = new KeyFile ();
                    key_file.load_from_bytes (bytes, KeyFileFlags.NONE);
                    var url = key_file.get_string ("playing", "url");
                    if (url != null) {
                        for (var i = 0; i < _song_store.size; i++) {
                            if (url == _song_store.get_song (i)?.url) {
                                play_item = i;
                                break;
                            }
                        }
                    }
                } catch (Error e) {
                }
            } else {
                play_item = saved_size;
            }

            Idle.add (() => {
                current_item = play_item;
                return false;
            });
        }

        public void show_about () {
            string[] authors = { "Nanling" };
            Gtk.show_about_dialog (this.active_window,
                                   "program-name", "G4Music Player",
                                   "authors", authors,
                                   "version", "0.1.0");
        }

        private void on_bus_acquired (DBusConnection connection, string name) {
            try {
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisPlayer (this, connection));
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisRoot ());
            } catch (Error e) {
                warning ("Register MPRIS failed: %s\n", e.message);
            }
        }
    }
}

int main (string[] args) {
    Music.GstPlayer.init (ref args);
    Environment.set_application_name ("G4Music");
    var app = new Music.Application ();
    return app.run (args);
}