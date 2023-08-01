namespace G4 {

    public class Application : Adw.Application {
        private ActionHandles? _actions = null;
        private int _current_item = -1;
        private Music? _current_music = null;
        private string _current_uri = "";
        private Gst.Sample? _current_cover = null;
        private bool _current_tag_parsed = false;
        private bool _list_modified = false;
        private bool _loading = false;
        private string _music_folder = "";
        private uint _mpris_id = 0;
        private MusicLoader _loader = new MusicLoader ();
        private Gtk.FilterListModel _music_list = new Gtk.FilterListModel (null, null);
        private ListStore _music_store = new ListStore (typeof (Music));
        private StringBuilder _next_uri = new StringBuilder ();
        private GstPlayer _player = new GstPlayer ();
        private Portal _portal = new Portal ();
        private Thumbnailer _thumbnailer = new Thumbnailer ();
        private Settings _settings;

        public signal void index_changed (int index, uint size);
        public signal void music_batch_changed ();
        public signal void music_changed (Music? music);
        public signal void music_external_changed ();
        public signal void music_tag_parsed (Music music, Gst.Sample? image);
        public signal void music_cover_parsed (Music music, string? uri);

        public Application () {
            Object (application_id: Config.APP_ID, flags: ApplicationFlags.HANDLES_OPEN);
        }

        public override void startup () {
            base.startup ();

            //  Must load tag cache after the app register (GLib init), to make sort works
            _loader.load_tag_cache ();

            _actions = new ActionHandles (this);

            _music_list.model = _music_store;
            _music_store.items_changed.connect (on_music_items_changed);
            _loader.loading_changed.connect ((loading) => _loading = loading);
            _loader.music_found.connect (on_music_found);
            _loader.music_lost.connect (on_music_lost);

            _thumbnailer.cover_finder = _loader.cover_cache;
            _thumbnailer.tag_updated.connect (_loader.add_to_cache);

            _player.end_of_stream.connect (on_player_end);
            _player.error.connect (on_player_error);
            _player.next_uri_request.connect (on_player_next_uri_request);
            _player.next_uri_start.connect (on_player_next_uri_start);
            _player.state_changed.connect (on_player_state_changed);
            _player.tag_parsed.connect (on_tag_parsed);

            _mpris_id = Bus.own_name (BusType.SESSION,
                "org.mpris.MediaPlayer2.G4Music",
                BusNameOwnerFlags.NONE,
                on_bus_acquired,
                null, null
            );
            if (_mpris_id == 0)
                warning ("Initialize MPRIS session failed\n");

            var settings = _settings = new Settings (application_id); 
            settings.bind ("dark-theme", this, "dark-theme", SettingsBindFlags.DEFAULT);
            settings.bind ("music-dir", this, "music-folder", SettingsBindFlags.DEFAULT);
            settings.bind ("sort-mode", this, "sort-mode", SettingsBindFlags.DEFAULT);
            settings.bind ("monitor-changes", _loader, "monitor-changes", SettingsBindFlags.DEFAULT);
            settings.bind ("remote-thumbnail", _thumbnailer, "remote-thumbnail", SettingsBindFlags.DEFAULT);
            settings.bind ("gapless-playback", _player, "gapless", SettingsBindFlags.DEFAULT);
            settings.bind ("replay-gain", _player, "replay-gain", SettingsBindFlags.DEFAULT);
            settings.bind ("audio-sink", _player, "audio-sink", SettingsBindFlags.DEFAULT);
            settings.bind ("volume", _player, "volume", SettingsBindFlags.DEFAULT);
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
            var window = (active_window as Window) ?? new Window (this);
            window.present ();

            var has_files = files.length > 0;
            if (has_files && _music_store.get_n_items () > 0) {
                open_files_async.begin (files, true, (obj, res) => open_files_async.end (res));
            } else {
                load_files_async.begin (files, (obj, res) => {
                    current_item = load_files_async.end (res);
                    if (has_files)
                        _player.play ();
                });
            }
        }

        public override void shutdown () {
            _actions = null;
            _loader.save_tag_cache ();
            delete_cover_tmp_file_async.begin ((obj, res) => delete_cover_tmp_file_async.end (res));

            if (_mpris_id != 0) {
                Bus.unown_name (_mpris_id);
                _mpris_id = 0;
            }
            base.shutdown ();
        }

        public unowned Gst.Sample? current_cover {
            get {
                return _current_cover;
            }
        }

        public int current_item {
            get {
                return _current_item;
            }
            set {
                current_music = get_next_music (ref value);
                change_current_item (value);
            }
        }

        public Music? current_music {
            get {
                return _current_music;
            }
            set {
                var playing = _current_music != null || _player.state == Gst.State.PLAYING;
                if (_current_music != value) {
                    _current_music = value;
                    _current_cover = null;
                    _current_tag_parsed = false;
                    music_changed (value);
                }
                var uri = value?.uri ?? "";
                if (strcmp (_current_uri, uri) != 0) {
                    _player.state = Gst.State.READY;
                    _player.uri = _current_uri = uri;
                }
                _player.state = playing ? Gst.State.PLAYING : Gst.State.PAUSED;
                _settings.set_string ("played-uri", uri);
            }
        }

        public bool dark_theme {
            get {
                var scheme = style_manager.color_scheme;
                return scheme == Adw.ColorScheme.FORCE_DARK || scheme ==  Adw.ColorScheme.PREFER_DARK;
            }
            set {
                style_manager.color_scheme = value ? Adw.ColorScheme.PREFER_DARK : Adw.ColorScheme.DEFAULT;
            }
        }

        private Gtk.IconPaintable? _icon = null;

        public Gtk.IconPaintable? icon {
            get {
                if (_icon == null) {
                    var theme = Gtk.IconTheme.get_for_display (active_window.display);
                    _icon = theme.lookup_icon (application_id, null, 512,
                        active_window.scale_factor, Gtk.TextDirection.NONE, Gtk.IconLookupFlags.FORCE_REGULAR);
                }
                return _icon;
            }
        }

        public bool list_modified {
            get {
                return _list_modified;
            }
        }

        public MusicLoader loader {
            get {
                return _loader;
            }
        }

        public bool loading {
            get {
                return _loading;
            }
        }

        public string music_folder {
            get {
                if (_music_folder.length == 0) {
                    var path = Environment.get_user_special_dir (UserDirectory.MUSIC);
                    _music_folder = File.new_build_filename (path).get_uri ();
                }
                return _music_folder;
            }
            set {
                _music_folder = value;
                if (active_window is Window) {
                    reload_library ();
                }
            }
        }

        public Gtk.FilterListModel music_list {
            get {
                return _music_list;
            }
            set {
                _music_list = value;
                update_current_item ();
            }
        }

        public ListStore music_store {
            get {
                return _music_store;
            }
        }

        public string name {
            get {
                return _("G4Music");
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

        private uint _sort_mode = SortMode.TITLE;

        public uint sort_mode {
            get {
                return _sort_mode;
            }
            set {
                var action = lookup_action (ACTION_SORT);
                var state = new Variant.string (value.to_string ());
                (action as SimpleAction)?.set_state (state);

                _sort_mode = value;
                sort_music_store (_music_store, _sort_mode);
            }
        }

        public Thumbnailer thumbnailer {
            get {
                return _thumbnailer;
            }
        }

        public async int load_files_async (owned File[] files) {
            var default_mode = files.length == 0;
            if (default_mode) {
                files.resize (1);
                files[0] = File.new_for_uri (music_folder);
            }
            if (files.length > 0) {
                var musics = new GenericArray<Music> (4096);
                yield _loader.load_files_async (files, musics, true, !default_mode, _sort_mode);
                _music_store.splice (0, _music_store.get_n_items (), musics.data);
                _list_modified = false;
            }
            if (_current_music != null && _current_music == _music_list.get_item (_current_item)) {
                return _current_item;
            } else {
                var uri = _current_music?.uri ?? _settings.get_string ("played-uri");
                return uri.length > 0 ? find_music_item_by_uri ((!)uri) : -1;
            }
        }

        public async void open_files_async (File[] files, bool play_now = false) {
            var musics = new GenericArray<Music> (4096);
            yield _loader.load_files_async (files, musics);
            var album = new Album ("");
            musics.foreach ((music) => album.add_music (music));
            if (play_now) {
                play (album);
            } else {
                play_at_next (album);
            }
        }

        public async void parse_music_cover_async () {
            if (_current_music != null) {
                var music = (!)_current_music;
                if (music.cover_uri != null) {
                    music_cover_parsed (music, music.cover_uri);
                } else {
                    var dir = File.new_build_filename (Environment.get_user_cache_dir (), application_id);
                    var name = Checksum.compute_for_string (ChecksumType.MD5, music.cover_key);
                    var file = dir.get_child (name);
                    var file_uri = file.get_uri ();
                    if (_current_cover != null) {
                        yield save_sample_to_file_async (file, (!)_current_cover);
                    } else {
                        var svg = _thumbnailer.create_album_text_svg (music);
                        yield save_text_to_file_async (file, svg);
                    }
                    if (music == _current_music) {
                        music_cover_parsed (music, file_uri);
                        if (strcmp (file_uri, _cover_tmp_file?.get_uri ()) != 0) {
                            yield delete_cover_tmp_file_async ();
                            _cover_tmp_file = file;
                        }
                    }
                }
            }
        }

        public void play (Object? obj, bool immediately = true) {
            if (obj is Music) {
                var music = (Music) obj;
                uint position = -1;
                var store = (ListStore) _music_list.model;
                if (!store.find (music, out position)) {
                    store.append (music);
                    position = (int) store.get_n_items () - 1;
                    _list_modified = true;
                }
                if (immediately) {
                    current_item = (int) position;
                }
            } else if (obj is Album) {
                var album = (Album) obj;
                var store = _music_store;
                var insert_pos = (uint) store.get_n_items () - 1;
                rebind_current_item ();
                album.foreach ((uri, music) => {
                    uint position = -1;
                    if (store.find (music, out position)) {
                        store.remove (position);
                        if (insert_pos > position) {
                            insert_pos = position;
                        }
                    }
                });
                album.get_sorted_musics (store, insert_pos);
                _list_modified = true;
                if (immediately) {
                    current_music = store.get_item (insert_pos) as Music;
                    update_current_item ();
                }
            }
        }

        public void play_at_next (Object? obj) {
            if (_current_music != null) {
                rebind_current_item ();
                if (obj is Music) {
                    var music = (Music) obj;
                    var store = (ListStore) _music_list.model;
                    if (insert_to_next (music, _music_store)) {
                        _list_modified = true;
                    }
                    if (store != _music_store) {
                        insert_to_next (music, store);
                    }
                } else if (obj is Album) {
                    var album = (Album) obj;
                    var store = _music_store;
                    album.foreach ((uri, music) => {
                        uint position = -1;
                        if (store.find (music, out position)) {
                            store.remove (position);
                        }
                    });
                    uint insert_pos = store.get_n_items () - 1;
                    store.find ((!)_current_music, out insert_pos);
                    album.get_sorted_musics (store, insert_pos + 1);
                    _list_modified = true;
                }
                _current_item = find_music_item (_current_music);
                rebind_current_item ();
            }
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

        public void rebind_current_item () {
            _music_list.items_changed (_current_item, 0, 0);
        }

        public void reload_library () {
            if (!_loading) {
                _loader.remove_all ();
                load_files_async.begin ({}, (obj, res) => {
                    var item = load_files_async.end (res);
                    run_idle_once (() => current_item = item);
                });
            }
        }

        public void request_background () {
            _portal.request_background_async.begin (_("Keep playing after window closed"),
                (obj, res) => _portal.request_background_async.end (res));
        }

        public void show_uri_with_portal (string? uri) {
            if (uri != null) {
                _portal.open_directory_async.begin ((!)uri,
                    (obj, res) => _portal.open_directory_async.end (res));
            }
        }

        public void toggle_search () {
            (active_window as Window)?.toggle_search ();
        }

        private void change_current_item (int item) {
            //  update _current_item but don't change current music
            rebind_current_item ();
            _current_item = item;
            rebind_current_item ();
            index_changed (item, _music_list.get_n_items ());

            var next = item + 1;
            var next_music = get_next_music (ref next);
            lock (_next_uri) {
                _next_uri.assign (next_music?.uri ?? "");
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

        private int find_music_item (Music? music) {
            var index = find_item_in_model (_music_list, music);
            if (index != -1)
                return index;
            return music != null ? locate_music_item_by_uri (((!)music).uri) : -1;
        }

        private int find_music_item_by_uri (string uri) {
            var music = _loader.find_cache (uri);
            if (music != null) {
                var item = find_music_item (music);
                if (item != -1)
                    return item;
            }
            return locate_music_item_by_uri (uri);
        }

        private bool insert_to_next (Music music, ListStore store) {
            uint playing_pos = -1;
            if (!store.find ((!)_current_music, out playing_pos)) {
                playing_pos = -1;
            }
            uint music_pos = -1;
            if (store.find ((!)music, out music_pos)
                    && playing_pos != music_pos
                    && playing_pos != music_pos - 1) {
                var next_pos = (int) music_pos > (int) playing_pos ? playing_pos + 1 : playing_pos;
                store.remove (music_pos);
                store.insert (next_pos, music);
                return true;
            }
            return false;
        }

        private int locate_music_item_by_uri (string uri) {
            var count = _music_list.get_n_items ();
            for (var i = 0; i < count; i++) {
                var music = _music_list.get_item (i) as Music;
                if (strcmp (uri, music?.uri) == 0)
                    return (int) i;
            }
            return -1;
        }

        private Music? get_next_music (ref int index) {
            var count = _music_list.get_n_items ();
            index = index < count ? index : 0;
            return _music_list.get_item (index) as Music;
        }

        private void on_bus_acquired (DBusConnection connection, string name) {
            try {
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisPlayer (this, connection));
                connection.register_object ("/org/mpris/MediaPlayer2", new MprisRoot (this));
            } catch (Error e) {
                warning ("Register MPRIS failed: %s\n", e.message);
            }
        }

        private void on_music_found (GenericArray<Music> arr) {
            var n_items = _music_store.get_n_items ();
            if (arr.length > 0) {
                _music_store.splice (n_items, 0, arr.data);
            } else {
                _music_store.items_changed (0, n_items, n_items);
            }
            music_external_changed ();
        }

        private uint _pending_mic_handler = 0;

        private void on_music_items_changed (uint position, uint removed, uint added) {
            if (removed != 0 || added != 0) {
                if (_pending_mic_handler != 0)
                    Source.remove (_pending_mic_handler);
                _pending_mic_handler = run_idle_once (() => {
                    _pending_mic_handler = 0;
                    if (!update_current_item ())
                        index_changed (_current_item, _music_list.get_n_items ());
                    music_batch_changed ();
                });
            }
        }

        private void on_music_lost (GenericSet<Music> removed) {
            var n_items = _music_store.get_n_items ();
            if (removed.length > 0) {
                var remain = new GenericArray<Music> (n_items);
                for (var i = 0; i < n_items; i++) {
                    var music = (Music) _music_store.get_item (i);
                    if (!removed.contains (music))
                        remain.add (music);
                }
                _music_store.splice (0, n_items, remain.data);
            } else {
                _music_store.items_changed (0, n_items, n_items);
            }
            music_external_changed ();
        }

        private void on_player_end () {
            if (_single_loop) {
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
            //  This is NOT called in main UI thread
            lock (_next_uri) {
                if (!_single_loop)
                    _current_uri = _next_uri.str;
                //  next_uri_start will be received soon later
                return _current_uri;
            }
        }

        private void on_player_next_uri_start () {
            //  Received after next_uri_request
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

        private async void on_tag_parsed (string? uri, Gst.TagList? tags) {
            if (_current_music != null && strcmp (_current_music?.uri, uri) == 0
                    && !_current_tag_parsed) {
                _current_cover = tags != null ? parse_image_from_tag_list ((!)tags) : null;
                _current_tag_parsed = true;
                music_tag_parsed ((!)_current_music, _current_cover);
            }
        }

        private bool update_current_item () {
            if (_music_list.get_item (_current_item) != _current_music) {
                var item = find_music_item (_current_music);
                change_current_item (item);
                return true;
            }
            return false;
        }
    }

    public int find_item_in_model (ListModel model, Object? obj) {
        var count = model.get_n_items ();
        for (var i = 0; i < count; i++) {
            if (model.get_item (i) == obj)
                return (int) i;
        }
        return -1;
    }

    public async bool save_sample_to_file_async (File file, Gst.Sample sample) {
        var buffer = sample.get_buffer ();
        Gst.MapInfo? info = null;
        try {
            var stream = yield file.replace_async (null, false, FileCreateFlags.NONE);
            if (buffer?.map (out info, Gst.MapFlags.READ) ?? false) {
                return yield stream.write_all_async (info?.data, Priority.DEFAULT, null, null);
            }
        } catch (Error e) {
        } finally {
            if (info != null)
                buffer?.unmap ((!)info);
        }
        return false;
    }

    public async bool save_text_to_file_async (File file, string text) {
        try {
            var stream = yield file.replace_async (null, false, FileCreateFlags.NONE);
            unowned uint8[] data = (uint8[])text;
            var size = text.length;
            return yield stream.write_all_async (data[0:size], Priority.DEFAULT, null, null);
        } catch (Error e) {
        }
        return false;
    }
}
