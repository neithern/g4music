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
        private bool _shuffled = false;
        private GstPlayer _player = new GstPlayer ();
        private Gtk.FilterListModel _song_list = new Gtk.FilterListModel (null, null);
        private SongStore _song_store = new SongStore ();
        private Thumbnailer _thumbnailer = new Thumbnailer ();

        public signal void index_changed (uint index, uint size);
        public signal void song_changed (Song song);
        public signal void song_tag_parsed (Song song, uint8[]? image);

        public Application () {
            Object (application_id: APP_ID, flags: ApplicationFlags.HANDLES_OPEN);

            ActionEntry[] action_entries = {
                { ACTION_ABOUT, this.show_about },
                { ACTION_PLAY, this.play_pause },
                { ACTION_PREV, this.play_previous },
                { ACTION_NEXT, this.play_next },
                { ACTION_SHUFFLE, this.shuffle_list },
                { ACTION_QUIT, this.quit }
            };
            this.add_action_entries (action_entries, this);
            this.set_accels_for_action ("app.quit", {"<primary>q"});

            _song_list.model = _song_store.store;

            _song_store.query_async.begin ((obj, res) => {
                _song_store.query_async.end (res);
                Idle.add (() => {
                    current_item = _song_list.filter != null ? 0 : Random.int_range (0, (int) _song_list.get_n_items ());
                    return false;
                });
            });

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
                @"org.mpris.MediaPlayer2." + APP_ID,
                BusNameOwnerFlags.NONE,
                on_bus_acquired,
                null, null
            );
            if (mpris_id == 0)
                warning ("Initialize MPRIS session failed\n");
        }

        public override void activate () {
            base.activate ();
            var window = active_window ?? new Window (this);
            window.present ();
        }

		public override void open (File[] files, string hint) {
            var items = new GenericSet<string> (str_hash, str_equal);
            foreach (var file in files) {
                items.add (file.get_uri ());
            }
            _song_list.filter = new Gtk.CustomFilter ((item) => {
                Song song = item as Song;
                return items.contains (song.url);
            });
            var window = active_window ?? new Window (this);
            window.present ();
        }

        public uint current_item {
            get {
                return _current_item;
            }
            set {
                var count = _song_list.get_n_items ();
                if ((int) value < 0)
                    value = count - 1;
                else if (value >= count)
                    value = 0;
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

        public bool is_shuffled {
            get {
                return _shuffled;
            }
            set {
                shuffle_list ();
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

        public void shuffle_list () {
            _shuffled = !_shuffled;
            if (_shuffled)
                _song_store.shuffle ();
            else
                _song_store.sort ();

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
            (active_window as Window)?.shuffle_btn?.set_active (_shuffled);
        }

        public void show_about () {
            string[] authors = { "Nanling" };
            Gtk.show_about_dialog (this.active_window,
                                   "program-name", "g4music Player",
                                   "authors", authors,
                                   "version", "0.1.0");
        }

        private void on_bus_acquired (DBusConnection connection, string name) {
            try {
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisRoot ());
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisPlayer (this, connection));
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