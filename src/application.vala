namespace G4 {

    public class Application : Adw.Application {
        private ActionHandles? _actions = null;
        private int _current_item = -1;
        private Music? _current_music = null;
        private string _current_uri = "";
        private Gst.Sample? _current_cover = null;
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
        private Settings _settings;
        private bool _store_external_changed = false;
        private HashTable<unowned ListModel, uint> _sort_map = new HashTable<unowned ListModel, uint> (direct_hash, direct_equal);
        private Thumbnailer _thumbnailer = new Thumbnailer ();

        public signal void end_of_playlist (bool forward);
        public signal void index_changed (int index, uint size);
        public signal void music_changed (Music? music);
        public signal void music_cover_parsed (Music music, Gdk.Pixbuf? cover, string? cover_uri);
        public signal void music_store_changed (bool external);
        public signal void playlist_added (Playlist playlist);

        public Application () {
            Object (application_id: Config.APP_ID, flags: ApplicationFlags.HANDLES_OPEN);
        }

        public override void startup () {
            base.startup ();

            //  Must load tag cache after the app register (GLib init), to make sort works
            _loader.load_tag_cache ();

            _actions = new ActionHandles (this);

            _music_list.model = _music_store;
            _music_list.items_changed.connect (on_music_list_changed);
            _music_store.items_changed.connect (on_music_store_changed);
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
            _player.tag_parsed.connect (on_player_tag_parsed);

            _mpris_id = Bus.own_name (BusType.SESSION,
                "org.mpris.MediaPlayer2.Gapless",
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

            if (files.length > 0 && _music_store.get_n_items () > 0) {
                open_files_async.begin (files, true, (obj, res) => open_files_async.end (res));
            } else {
                load_files_async.begin (files, (obj, res) => load_files_async.end (res));
            }
        }

        public override void shutdown () {
            _actions = null;
            _loader.save_tag_cache ();
            delete_cover_tmp_file_async.begin ((obj, res) => delete_cover_tmp_file_async.end (res));

            //  save playing-list's sort mode only
            _settings.set_uint ("sort-mode", _sort_map[_music_store]);

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
                var item = value;
                if (item >= (int) _music_list.get_n_items ()) {
                    end_of_playlist (true);
                    item = _music_list.get_n_items () > 0 ? 0 : -1;
                } else if (item < 0) {
                    end_of_playlist (false);
                    item = (int) _music_list.get_n_items () - 1;
                }
                current_music = _music_list.get_item (item) as Music;
                change_current_item (item);
            }
        }

        public Music? current_music {
            get {
                return _current_music;
            }
            set {
                var playing = _current_music != null || _player.state == Gst.State.PLAYING;
                if (_current_music != value || value == null) {
                    _current_music = value;
                    music_changed (value);
                }
                var uri = value?.uri ?? "";
                if (strcmp (_current_uri, uri) != 0) {
                    _current_cover = null;
                    _player.state = Gst.State.READY;
                    _player.uri = _current_uri = uri;
                    if (uri.length > 0)
                        _player.state = playing ? Gst.State.PLAYING : Gst.State.PAUSED;
                }
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
                    _icon = theme.lookup_icon (application_id, null, _cover_size,
                        active_window.scale_factor, Gtk.TextDirection.NONE, Gtk.IconLookupFlags.FORCE_REGULAR);
                }
                return _icon;
            }
        }

        public bool list_modified {
            get {
                return _list_modified;
            }
            set {
                _list_modified = value;
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
                    var path = ((string?) Environment.get_user_special_dir (UserDirectory.MUSIC)) ?? "Music";
                    _music_folder = File.new_build_filename (path).get_uri ();
                }
                return _music_folder;
            }
            set {
                if (strcmp (_music_folder, value) != 0) {
                    _music_folder = value;
                    if (active_window is Window)
                        reload_library ();
                }
            }
        }

        public Gtk.FilterListModel music_list {
            get {
                return _music_list;
            }
            set {
                _music_list.items_changed.disconnect (on_music_list_changed);
                _music_list = value;
                _music_list.items_changed.connect (on_music_list_changed);
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
                return _("Gapless");
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

        public uint sort_mode {
            get {
                return _sort_map[_music_list.model];
            }
            set {
                var action = lookup_action (ACTION_SORT);
                var state = new Variant.string (value.to_string ());
                (action as SimpleAction)?.set_state (state);

                if (_sort_map[_music_list.model] != value) {
                    _sort_map[_music_list.model] = value;
                    sort_music_store ((ListStore) _music_list.model, value);
                }
            }
        }

        public Thumbnailer thumbnailer {
            get {
                return _thumbnailer;
            }
        }

        public async bool add_playlist_to_file_async (Playlist playlist, bool append) {
            var file = File.new_for_uri (playlist.list_uri);
            var uris = new GenericArray<string> (1024);
            var saved = yield run_async <bool> (() => {
                string? name = null;
                var map = new GenericSet<string> (str_hash, str_equal);
                if (append) {
                    name = load_playlist_file (file, uris);
                    uris.foreach ((uri) => map.add (uri));
                }
                foreach (var music in playlist.items) {
                    var uri = music.uri;
                    if (!map.contains (uri))
                        uris.add (uri);
                }
                var ret = save_playlist_file (file, uris, name ?? playlist.title);
                if (ret) {
                    //  Replace items if loaded from existing file
                    playlist.clear ();
                    foreach (var uri in uris) {
                        var music = _loader.find_cache (uri);
                        if (music != null)
                            playlist.add_music ((!)music, true);
                    }
                    playlist.set_cover_uri ();
                    if (name != null)
                        playlist.set_title ((!)name);
                }
                return ret;
            });
            if (saved) {
                _loader.library.add_playlist (playlist);
                playlist_added (playlist);
            }
            return saved;
        }

        public async void load_files_async (owned File[] files) {
            var last_uri = _current_music?.uri ?? _settings.get_string ("played-uri");
            var default_mode = files.length == 0;
            if (default_mode) {
                files.resize (1);
                files[0] = File.new_for_uri (music_folder);
            }
            foreach (var file in files) {
                if (_current_music == null && last_uri.has_prefix (file.get_uri ())) {
                    // Load last played uri before load files
                    _current_music = new Music (last_uri, "", 0);
                    _player.uri = _current_uri = last_uri;
                    _player.state = Gst.State.PAUSED;
                    break;
                }
            }

            var musics = new GenericArray<Music> (4096);
            yield _loader.load_files_async (files, musics, !default_mode, !default_mode, _sort_map[_music_store]);
            if (default_mode) {
                var arr = new GenericArray<Music> (4096);
                var file = get_playing_list_file ();
                yield run_void_async (() => _loader.load_playlist (file, arr));
                if (arr.length > 0)
                    musics = arr;
            }
            _store_external_changed = true;
            _music_store.splice (0, _music_store.get_n_items (), (Object[]) musics.data);

            var count = _music_store.get_n_items ();
            var item = (count > 0 && last_uri.length > 0) ? find_music_item_by_uri (last_uri) : -1;
            current_item = (count > 0 && item == -1) ? 0 : item;
            if (_current_music != null && !default_mode) {
                _player.play ();
            }
        }

        public async void open_files_async (File[] files, bool play_now = false) {
            var playlist = new Playlist ("");
            yield _loader.load_files_async (files, playlist.items);
            if (playlist.length > 0) {
                if (play_now) {
                    queue (playlist);
                } else {
                    play_at_next (playlist);
                }
            }
        }

        public void queue (Music? node, bool play = true) {
            var store = _music_store;
            if (node is Playlist) {
                var playlist = (Playlist) node;
                var insert_pos = (uint) store.get_n_items ();
                foreach (var music in playlist.items) {
                    uint position = -1;
                    if (store.find (music, out position)) {
                        store.remove (position);
                        if (insert_pos > position) {
                            insert_pos = position;
                        }
                    }
                }
                _list_modified = true;
                playlist.insert_to (store, insert_pos);
                if (play) {
                    current_music = store.get_item (insert_pos) as Music;
                    update_current_item ();
                }
            } else if (node is Music) {
                var music = (Music) node;
                int position = find_item_in_model (store, music);
                if (position == -1) {
                    _list_modified = true;
                    store.append (music);
                    position = find_item_in_model (_music_list, music);
                }
                if (play) {
                    current_item = position;
                    if (position == -1)
                        current_music = music;
                }
            }
        }

        public void play_at_next (Music? node) {
            var store = _music_store;
            if (node is Playlist) {
                var playlist = (Playlist) node;
                foreach (var music in playlist.items) {
                    uint position = -1;
                    if (store.find (music, out position)) {
                        store.remove (position);
                    }
                }
                _list_modified = true;
                int insert_pos = find_music_in_store (store, _current_music);
                playlist.insert_to (store, insert_pos + 1);
            } else if (node is Music) {
                var music = (Music) node;
                uint position = -1;
                if (store.find (music, out position)) {
                    store.remove (position);
                }
                _list_modified = true;
                int playing_pos = find_music_in_store (store, _current_music);
                store.insert (playing_pos + 1, music);
            }
            update_current_item ();
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

        public void reload_library () {
            if (!_loading) {
                var file = get_playing_list_file ();
                file.delete_async.begin (Priority.DEFAULT, null, (obj, res) => {
                    try {
                        file.delete_async.end (res);
                    } catch (Error e) {
                    }
                });
                _loader.remove_all ();
                load_files_async.begin ({}, (obj, res) => load_files_async.end (res));
            }
        }

        public void request_background () {
            _portal.request_background_async.begin (_("Keep playing after window closed"),
                (obj, res) => _portal.request_background_async.end (res));
        }

        public async void save_to_playlist_file_async (Playlist playlist) {
            var uri = playlist.list_uri;
            var append = uri.length == 0;
            if (append) {
                var filter = new Gtk.FileFilter ();
                filter.name = _("Playlist Files");
                filter.add_mime_type ("audio/x-mpegurl");
                filter.add_mime_type ("audio/x-scpls");
                filter.add_mime_type ("public.m3u-playlist");
                var initial = File.new_for_uri (music_folder).get_child (playlist.title + ".m3u");
                var file = yield show_save_file_dialog (active_window, initial, {filter});
                if (file == null)
                    return;
                playlist.list_uri = ((!)file).get_uri ();
                playlist.set_title (get_file_display_name ((!)file));
            }
            var saved = yield add_playlist_to_file_async (playlist, append);
            if (saved)
                show_uri_with_portal (playlist.list_uri);
        }

        public uint get_list_sort_mode (ListModel model) {
            return _sort_map[model];
        }

        public void set_list_sort_mode (ListModel model, uint mode) {
            _sort_map[model] = mode;
        }

        public async void show_add_playlist_dialog (Playlist playlist) {
            var dialog = new PlaylistDialog (this);
            var result = yield dialog.choose (active_window);
            if (result) {
                var pls = dialog.playlist;
                if (pls != null) {
                    playlist.list_uri = ((!)pls).list_uri;
                    yield add_playlist_to_file_async (playlist, true);
                } else {
                    yield save_to_playlist_file_async (playlist);
                }
            }
        }
    
        public void show_uri_with_portal (string? uri) {
            if (uri != null) {
                _portal.open_directory_async.begin ((!)uri,
                    (obj, res) => _portal.open_directory_async.end (res));
            }
        }

        private void change_current_item (int item) {
            //  update _current_item but don't change current music
            var count = _music_list.get_n_items ();
            if (_current_item != item) {
                _current_item = item;
                index_changed (item, count);
            }

            var next = item + 1;
            var next_music = next < (int) count ? (Music) _music_list.get_item (next) : (Music?) null;
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

        private int find_music_in_store (ListStore store, Music? music) {
            uint pos = -1;
            if (music != null && store.find ((!)music, out pos)) {
                return (int) pos;
            }
            return -1;
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

        private int locate_music_item_by_uri (string uri) {
            var count = _music_list.get_n_items ();
            for (var i = 0; i < count; i++) {
                var music = _music_list.get_item (i) as Music;
                if (strcmp (uri, music?.uri) == 0)
                    return (int) i;
            }
            return -1;
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
                _store_external_changed = true;
                _music_store.splice (n_items, 0, (Object[]) arr.data);
            } else {
                _store_external_changed = true;
                _music_store.items_changed (0, n_items, n_items);
            }
        }

        private uint _pending_mic_handler = 0;
        private uint _pending_msc_handler = 0;

        private void on_music_list_changed (uint position, uint removed, uint added) {
            if (removed != 0 || added != 0) {
                if (_pending_mic_handler != 0)
                    Source.remove (_pending_mic_handler);
                _pending_mic_handler = run_idle_once (() => {
                    _pending_mic_handler = 0;
                    update_current_item ();
                });
            }
        }

        private void on_music_store_changed (uint position, uint removed, uint added) {
            if (removed != 0 || added != 0) {
                if (_pending_msc_handler != 0)
                    Source.remove (_pending_msc_handler);
                _pending_msc_handler = run_idle_once (() => {
                    _pending_msc_handler = 0;
                    music_store_changed (_store_external_changed);
                    _store_external_changed = false;
                    index_changed (_current_item, _music_list.get_n_items ());
                });
            }
        }

        private void on_music_lost (GenericSet<Music> removed) {
            var n_items = _music_store.get_n_items ();
            if (removed.length > 0) {
                var remain = new GenericArray<Music> (n_items);
                for (var i = 0; i < n_items; i++) {
                    var music = (Music) _music_store.get_item (i);
                    if (removed.contains (music)) {
                        if (_current_item > i)
                            _current_item--;
                    } else {
                        remain.add (music);
                    }
                }
                _store_external_changed = true;
                _music_store.splice (0, n_items, (Object[]) remain.data);
                current_item = _current_item;
            } else {
                _store_external_changed = true;
                _music_store.items_changed (0, n_items, n_items);
            }
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

        private int _cover_size = 360;

        private async void on_player_tag_parsed (string? uri, Gst.TagList? tags) {
            if (_current_music != null && strcmp (_current_uri, uri) == 0) {
                var music = _loader.find_cache (_current_uri) ?? (!)_current_music;
                if (music.title.length == 0 && tags != null && music.from_gst_tags ((!)tags)) {
                    music_changed (music);
                }

                _current_cover = tags != null ? parse_image_from_tag_list ((!)tags) : null;
                if (_current_cover == null && uri != null) {
                    _current_cover = yield run_async<Gst.Sample?> (() => {
                        var file = File.new_for_uri ((!)uri);
                        var t = parse_gst_tags (file);
                        return t != null ? parse_image_from_tag_list ((!)t) : null;
                    });
                }

                Gdk.Pixbuf? pixbuf = null;
                var image = _current_cover;
                if (strcmp (_current_uri, uri) == 0) {
                    var size = _cover_size * _thumbnailer.scale_factor;
                    if (image != null) {
                        pixbuf = yield run_async<Gdk.Pixbuf?> (
                            () => load_clamp_pixbuf_from_sample ((!)image, size), true);
                    }
                    if (pixbuf == null) {
                        pixbuf = yield _thumbnailer.load_directly_async (music, size);
                    }
                }

                if (strcmp (_current_uri, uri) == 0) {
                    var cover_uri = music.cover_uri;
                    if (cover_uri == null) {
                        var dir = File.new_build_filename (Environment.get_user_cache_dir (), application_id);
                        var name = Checksum.compute_for_string (ChecksumType.MD5, music.cover_key);
                        var file = dir.get_child (name);
                        cover_uri = file.get_uri ();
                        if (image != null) {
                            yield save_sample_to_file_async (file, (!)image);
                        } else {
                            var svg = _thumbnailer.create_music_text_svg (music);
                            yield save_text_to_file_async (file, svg);
                        }
                        if (strcmp (cover_uri, _cover_tmp_file?.get_uri ()) != 0) {
                            yield delete_cover_tmp_file_async ();
                            _cover_tmp_file = file;
                        }
                    }
                    if (strcmp (_current_uri, uri) == 0) {
                        music_cover_parsed (music, pixbuf, cover_uri);
                    }
                }

                //  Update thumbnail cache if remote thumbnail not loaded
                if (pixbuf != null && !(_thumbnailer.find (music) is Gdk.Texture)) {
                    var minbuf = yield run_async<Gdk.Pixbuf?> (
                        () => create_clamp_pixbuf ((!)pixbuf, Thumbnailer.ICON_SIZE * _thumbnailer.scale_factor)
                    );
                    if (minbuf != null) {
                        var paintable = Gdk.Texture.for_pixbuf ((!)minbuf);
                        _thumbnailer.put (music, paintable, true, Thumbnailer.ICON_SIZE);
                    }
                }
            }
        }

        private void update_current_item () {
            if (_current_music == null || _current_music != _music_list.get_item (_current_item)) {
                var item = find_music_item (_current_music);
                change_current_item (item);
            }
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

    public File get_playing_list_file () {
        var cache_dir = Environment.get_user_cache_dir ();
        return File.new_build_filename (cache_dir, Config.APP_ID, "playing.m3u");
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
