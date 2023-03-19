namespace G4 {
    public const string ACTION_APP = "app.";
    public const string ACTION_ABOUT = "about";
    public const string ACTION_PREFS = "preferences";
    public const string ACTION_EXPORT_COVER = "export-cover";
    public const string ACTION_PLAY_AT_NEXT = "play-at-next";
    public const string ACTION_PLAY = "play";
    public const string ACTION_PREV = "prev";
    public const string ACTION_NEXT = "next";
    public const string ACTION_RELOAD_LIST = "reload-list";
    public const string ACTION_SEARCH = "search";
    public const string ACTION_SHOW_ALBUM = "show-album";
    public const string ACTION_SHOW_ARTIST = "show-artist";
    public const string ACTION_SHOW_COVER_FILE = "show-cover-file";
    public const string ACTION_SHOW_MUSIC_FILES = "show-music-file";
    public const string ACTION_SORT = "sort";
    public const string ACTION_TOGGLE_SORT = "toggle-sort";
    public const string ACTION_QUIT = "quit";

    struct ActionShortKey {
        public weak string name;
        public weak string key;
    }

    internal Settings? new_application_settings () {
        var source = SettingsSchemaSource.get_default ()?.lookup (Config.APP_ID, false);
        if (source != null)
            return new Settings.full ((!)source, null, null); 
        return null; //  new Settings (Config.APP_ID);
    }

    public class Application : Adw.Application {
        private int _current_item = -1;
        private Music? _current_music = null;
        private Gst.Sample? _cover_image = null;
        private bool _loading_store = false;
        private StringBuilder _next_uri = new StringBuilder ();
        private GstPlayer _player = new GstPlayer ();
        private Gtk.FilterListModel _music_list = new Gtk.FilterListModel (null, null);
        private MusicStore _music_store = new MusicStore ();
        private Thumbnailer _thumbnailer = new Thumbnailer ();
        private Settings? _settings = new_application_settings ();
        private MprisPlayer? _mpris = null;
        private uint _mpris_id = 0;
        private Portal? _portal = null;

        public signal void loading_changed (bool loading, uint size);
        public signal void index_changed (int index, uint size);
        public signal void music_changed (Music music);
        public signal void music_tag_parsed (Music music, Gst.Sample? image);

        public Application () {
            Object (application_id: Config.APP_ID, flags: ApplicationFlags.HANDLES_OPEN);

            ActionEntry[] action_entries = {
                { ACTION_ABOUT, show_about },
                { ACTION_PREFS, show_preferences },
                { ACTION_EXPORT_COVER, export_cover },
                { ACTION_PLAY_AT_NEXT, play_at_next },
                { ACTION_PLAY, play_pause },
                { ACTION_PREV, play_previous },
                { ACTION_NEXT, play_next },
                { ACTION_RELOAD_LIST, reload_music_store },
                { ACTION_SEARCH, toggle_seach },
                { ACTION_SHOW_ALBUM, show_album },
                { ACTION_SHOW_ARTIST, show_artist },
                { ACTION_SHOW_COVER_FILE, show_cover_file },
                { ACTION_SHOW_MUSIC_FILES, show_music_file },
                { ACTION_TOGGLE_SORT, toggle_sort },
                { ACTION_QUIT, quit }
            };
            add_action_entries (action_entries, this);

            ActionShortKey[] action_keys = {
                { ACTION_PLAY, "<primary>p" },
                { ACTION_PREV, "<primary>Left" },
                { ACTION_NEXT, "<primary>Right" },
                { ACTION_SEARCH, "<primary>f" },
                { ACTION_TOGGLE_SORT, "<primary>s" },
                { ACTION_QUIT, "<primary>q" }
            };
            foreach (var item in action_keys) {
                set_accels_for_action (ACTION_APP + item.name, {item.key});
            }

            var sort_mode = _settings?.get_uint ("sort-mode") ?? SortMode.TITLE;
            ActionEntry[] action_sort = {
                { ACTION_SORT, sort_by, "s", "'2'" },
            };
            var state = "'" + sort_mode.to_string () + "'";
            action_sort[0].state = state;
            add_action_entries (action_sort, this);

            dark_theme = _settings?.get_boolean ("dark-theme") ?? true;

            _music_list.model = _music_store.store;
            _music_store.sort_mode = (SortMode) (_settings?.get_uint ("sort-mode") ?? SortMode.TITLE);

            _thumbnailer.tag_updated.connect (_music_store.add_to_cache);
            _thumbnailer.remote_thumbnail = _settings?.get_boolean ("remote-thumbnail") ?? false;

            _player.gapless = _settings?.get_boolean ("gapless-playback") ?? true;
            _player.replay_gain = _settings?.get_boolean ("replay-gain") ?? false;
            _player.pipewire_sink = _settings?.get_boolean ("pipewire-sink") ?? false;
            _player.show_peak = _settings?.get_boolean ("show-peak") ?? false;
            _player.volume = _settings?.get_double ("volume") ?? 1;

            _player.end_of_stream.connect (on_player_end);
            _player.error.connect (on_player_error);
            _player.next_uri_request.connect (on_player_next_uri_request);
            _player.next_uri_start.connect (on_player_next_uri_start);
            _player.state_changed.connect (on_player_state_changed);
            _player.tag_parsed.connect (on_tag_parsed);
        }

        public override void startup () {
            base.startup ();

            //  Must load tag cache after the app register (GLib init), to make sort works
            _music_store.load_tag_cache_async.begin ((obj, res) => {
                _music_store.load_tag_cache_async.end (res);
            });

            _mpris_id = Bus.own_name (BusType.SESSION,
                "org.mpris.MediaPlayer2." + Config.APP_ID,
                BusNameOwnerFlags.NONE,
                on_bus_acquired,
                null, null
            );
            if (_mpris_id == 0)
                warning ("Initialize MPRIS session failed\n");
        }

        public override void activate () {
            base.activate ();

            if (active_window is Window) {
                active_window.present ();
            } else {
                open ({}, "");
            }
        }

        public override void open (File[] files, string hint) {
            load_musics_async.begin (files, (obj, res) => {
                var play_item = load_musics_async.end (res);
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
            if (_mpris_id != 0) {
                Bus.unown_name (_mpris_id);
                _mpris_id = 0;
            }

            _settings?.set_double ("volume", _player.volume);

            _music_store.save_tag_cache_async.begin ((obj, res) => {
                _music_store.save_tag_cache_async.end (res);
            });

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
                var playing = _player.state == Gst.State.PLAYING;
                var music = get_next_music (ref value);
                if (music != _current_music) {
                    _player.state = Gst.State.READY;
                    current_music = music;
                }
                if (_current_item != value) {
                    update_current_item (value);
                }
                var next = value + 1;
                var next_music = get_next_music (ref next);
                lock (_next_uri) {
                    _next_uri.assign (next_music?.uri ?? "");
                }
                _player.state = playing ? Gst.State.PLAYING : Gst.State.PAUSED;
            }
        }

        public Music? current_music {
            get {
                return _current_music;
            }
            set {
                if (_current_music != value) {
                    _current_music = value;
                    _player.uri = value?.uri;
                    if (value != null) {
                        music_changed ((!)value);
                        _settings?.set_string ("played-uri", ((!)value).uri);
                    }
                }
            }
        }

        public bool dark_theme {
            set {
                style_manager.color_scheme = value ? Adw.ColorScheme.PREFER_DARK : Adw.ColorScheme.DEFAULT;
            }
        }

        public bool is_loading_store {
            get {
                return _loading_store;
            }
        }

        public GstPlayer player {
            get {
                return _player;
            }
        }

        public Music? popover_music { get; set; }

        public Settings? settings {
            get {
                return _settings;
            }
        }

        public bool single_loop { get; set; }

        public Gtk.FilterListModel music_list {
            get {
                return _music_list;
            }
        }

        public SortMode sort_mode {
            get {
                return _music_store.sort_mode;
            }
            set {
                _music_store.sort_mode = value;
                _settings?.set_uint ("sort-mode", value);
            }
        }

        public MusicStore music_store {
            get {
                return _music_store;
            }
        }

        public Thumbnailer thumbnailer {
            get {
                return _thumbnailer;
            }
        }

        public File get_music_folder () {
            var music_uri = _settings?.get_string ("music-dir") ?? "";
            if (music_uri.length > 0) {
                return File.new_for_uri (music_uri);
            }
            var music_path = Environment.get_user_special_dir (UserDirectory.MUSIC);
            return File.new_for_path (music_path);
        }

        public void play_next () {
            current_item++;
            _player.play ();
        }

        public void play_pause() {
            _player.playing = !_player.playing;
        }

        public void play_previous () {
            current_item--;
            _player.play ();
        }

        public void reload_music_store () {
            if (!_loading_store) {
                _music_store.clear ();
                update_current_item (-1);
                load_musics_async.begin ({}, (obj, res) => {
                    current_item = load_musics_async.end (res);
                });
            }
        }

        private void sort_by (SimpleAction action, Variant? state) {
            action.set_state ((!)state);

            unowned var value = state?.get_string () ?? "";
            int mode = 2;
            int.try_parse (value, out mode, null, 10);
            sort_mode = (SortMode) mode;
            find_current_item ();
        }

        public void toggle_seach () {
            var win = active_window as Window;
            if (win != null)
                ((!)win).search_btn.active = ! ((!)win).search_btn.active;
        }

        private void toggle_sort () {
            if (sort_mode >= SortMode.SHUFFLE)
                sort_mode = SortMode.ALBUM;
            else
                sort_mode = (SortMode) (sort_mode + 1);
        }

        public bool find_current_item () {
            if (_music_list.get_item (_current_item) == _current_music)
                return true;

            //  find current item
            var item = find_music_item (_current_music);
            if (item != -1) {
                current_item = item;
                return true;
            }

            update_current_item (-1);
            return false;
        }

        private void update_current_item (int item) {
            //  update _current_item but don't change current music
            var old_item = _current_item;
            _current_item = item;
            _music_list.items_changed (old_item, 0, 0);
            _music_list.items_changed (item, 0, 0);
            index_changed (item, _music_list.get_n_items ());
        }

        private int find_music_item (Music? music) {
            var count = _music_list.get_n_items ();
            for (var i = 0; i < count; i++) {
                if (music == _music_list.get_item (i)) {
                    return (int) i;
                }
            }
            return -1;
        }

        public async int load_musics_async (owned File[] files) {
            var saved_size = _music_store.size;
            var play_item = _current_item;
            _loading_store = true;
            loading_changed (true, saved_size);

            if (saved_size == 0 && files.length == 0) {
                files.resize (1);
                files[0] = get_music_folder ();
            }
            if (files.length > 0) {
                yield _music_store.add_files_async (files);
            }

            _loading_store = false;
            loading_changed (false, _music_store.size);
            if (saved_size > 0) {
                play_item = (int) saved_size;
            } else if (_current_music != null && _current_music == _music_list.get_item (_current_item)) {
                play_item = _current_item;
            } else {
                var uri = _current_music?.uri ?? _settings?.get_string ("played-uri");
                if (uri != null && ((!)uri).length > 0) {
                    var count = _music_list.get_n_items ();
                    for (var i = 0; i < count; i++) {
                        var music = (Music) _music_list.get_item (i);
                        if (((!)uri) == music.uri) {
                            play_item = i;
                            break;
                        }
                    }
                }
            }
            return play_item;
        }

        private Portal _get_portal () {
            if (_portal == null)
                _portal = new Portal ();
            return (!)_portal;
        }

        public void request_background () {
            var portal = _get_portal ();
            portal.request_background_async.begin (_("Keep playing after window closed"), (obj, res) => {
                portal.request_background_async.end (res);
            });
        }

        public void show_about () {
            string[] authors = { "Nanling" };
            var app_name = _("G4Music");
            var comments = _("A fast, fluent, light weight music player written in GTK4.");
            /* Translators: Replace "translator-credits" with your names, one name per line */
            var translator_credits = _("translator-credits");
            var website = "https://gitlab.gnome.org/neithern/g4music";
#if HAS_ADW_ABOUT
            var win = new Adw.AboutWindow ();
            win.application_icon = application_id;
            win.application_name = app_name;
            win.version = Config.VERSION;
            win.comments = comments;
            win.license_type = Gtk.License.GPL_3_0;
            win.developers = authors;
            win.website = website;
            win.issue_url = "https://gitlab.gnome.org/neithern/g4music/issues";
            win.translator_credits = translator_credits;
            win.transient_for = active_window;
            win.present ();
#else
            Gtk.show_about_dialog (active_window,
                                   "logo-icon-name", application_id,
                                   "program-name", app_name,
                                   "version", Config.VERSION,
                                   "comments", comments,
                                   "authors", authors,
                                   "translator-credits", translator_credits,
                                   "license-type", Gtk.License.GPL_3_0,
                                   "website", website
                                  );
#endif
        }

        public void show_preferences () {
            var win = new PreferencesWindow (this);
            win.destroy_with_parent = true;
            win.transient_for = active_window;
            win.modal = true;
            win.present ();
        }

        private void on_bus_acquired (DBusConnection connection, string name) {
            _mpris = new MprisPlayer (this, connection);
            try {
                connection.register_object ("/org/mpris/MediaPlayer2", (!)_mpris);
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisRoot (this));
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

        private void export_cover () {
            if (_cover_image != null && active_window is Window) {
                var sample = (!)_cover_image;
                var itype = sample.get_caps ()?.get_structure (0)?.get_name ();
                var pos = itype?.index_of_char ('/') ?? -1;
                var ext = itype?.substring (pos + 1) ?? "";
                var name = active_window.title.replace ("/", "&") + "." + ext;
                var filter = new Gtk.FileFilter ();
                filter.add_mime_type (itype ??  "image/*");
                var chooser = new Gtk.FileChooserNative (null, active_window, Gtk.FileChooserAction.SAVE, null, null);
                chooser.set_current_name (name);
                chooser.set_filter (filter);
                chooser.modal = true;
                chooser.response.connect ((id) => {
                    var file = chooser.get_file ();
                    if (id == Gtk.ResponseType.ACCEPT && file is File) {
                        save_sample_to_file.begin ((!)file, sample, (obj, res) => {
                            save_sample_to_file.end (res);
                        });
                    }
                });
                chooser.show ();
            }
        }

        private Music? get_next_music (ref int index) {
            var count = _music_list.get_n_items ();
            index = index < count ? index : 0;
            return _music_list.get_item (index) as Music;
        }

        private void play_at_next () {
            if (_current_music != null && popover_music != null) {
                uint playing_item = -1;
                uint popover_item = -1;
                var store = _music_store.store;
                if (store.find ((!)_current_music, out playing_item)
                        && store.find ((!)popover_music, out popover_item)
                        && playing_item != popover_item
                        && playing_item != popover_item - 1) {
                    var next_item = popover_item > playing_item ? playing_item + 1 : playing_item;
                    store.remove (popover_item);
                    store.insert (next_item, (!)popover_music);
                    //  update current playing item without scrolling
                    var old_item = _current_item;
                    _current_item = find_music_item (_current_music);
                    _music_list.items_changed (old_item, 0, 0);
                    _music_list.items_changed (_current_item, 0, 0);
                }
            }
        }

        private void _show_uri_with_portal (string? uri) {
            if (uri != null) {
                var portal = _get_portal ();
                portal.open_directory_async.begin ((!)uri, (obj, res) => {
                    portal.open_directory_async.end (res);
                });
            }
        }

        private void show_cover_file () {
            var music = popover_music ?? _current_music;
            _show_uri_with_portal (music?.cover_uri);
        }

        private void show_music_file () {
            var music = popover_music ?? _current_music;
            _show_uri_with_portal (music?.uri);
        }

        private void show_album () {
            var album = (popover_music ?? _current_music)?.album;
            if (album != null)
                (active_window as Window)?.start_search ("album=" + (!)album);
        }

        private void show_artist () {
            var artist = (popover_music ?? _current_music)?.artist;
            if (artist != null)
                (active_window as Window)?.start_search ("artist=" + (!)artist);
        }

        private void on_player_end () {
            if (single_loop) {
                _player.seek (0);
                _player.play ();
            } else {
                current_item++;
            }
        }

        private void on_player_error (Error err) {
            print ("Player error: %s\n", err.message);
            if (!_player.gapless) {
                on_player_end ();
            }
        }

        private string? on_player_next_uri_request () {
            //  This callback is NOT called in main UI thread
            string? next_uri = null;
            if (!single_loop) {
                lock (_next_uri) {
                    next_uri = _next_uri.str;
                }
            }
            //  stream_start will be received soon later
            return next_uri;
        }

        private void on_player_next_uri_start () {
            //  Received after request_next_uri
            on_player_end ();
        }

        private uint _inhibit_id = 0;

        private void on_player_state_changed (Gst.State state) {
            if (state == Gst.State.PLAYING && _inhibit_id == 0) {
                _inhibit_id = this.inhibit (active_window, Gtk.ApplicationInhibitFlags.SUSPEND, _("Keep playing"));
            } else if (state != Gst.State.PLAYING && _inhibit_id != 0) {
                this.uninhibit (_inhibit_id);
                _inhibit_id = 0;
            }
        }

        private async void on_tag_parsed (string? album, string? artist, string? title, Gst.Sample? image) {
            _cover_image = image;
            if (_current_music != null) {
                var music = (!)current_music;
                music_tag_parsed (music, image);

                string? cover_uri = null;
                if (image != null) {
                    var file = File.new_build_filename (Environment.get_tmp_dir (), application_id + "_" + str_hash (music.cover_uri).to_string ("%x"));
                    yield save_sample_to_file (file, (!)image);
                    yield delete_cover_tmp_file_async ();
                    _cover_tmp_file = file;
                    cover_uri = file.get_uri ();
                }

                if (music == _current_music) {
                    if (cover_uri == null && music.cover_uri != music.uri) {
                        cover_uri = music.cover_uri;
                    }
                    _mpris?.send_meta_data (music, cover_uri);
                }
            }
        }
    }

    public static async void save_sample_to_file (File file, Gst.Sample sample) {
        try {
            var buffer = sample.get_buffer ();
            Gst.MapInfo? info = null;
            if (buffer?.map (out info, Gst.MapFlags.READ) ?? false) {
                var stream = yield file.create_async (FileCreateFlags.NONE);
                yield stream.write_all_async (info?.data, Priority.DEFAULT, null, null);
                buffer?.unmap ((!)info);
            }
        } catch (Error e) {
        }
    }
}
