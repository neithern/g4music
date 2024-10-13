namespace G4 {

    public class Application : Adw.Application {
        private ActionHandles? _actions = null;
        private int _current_index = -1;
        private Music? _current_music = null;
        private string _current_uri = "";
        private Gst.Sample? _current_cover = null;
        private bool _list_modified = false;
        private bool _loading = false;
        private string _music_folder = "";
        private uint _mpris_id = 0;
        private MusicLoader _loader = new MusicLoader ();
        private Gtk.FilterListModel _current_list = new Gtk.FilterListModel (null, null);
        private ListStore _music_queue = new ListStore (typeof (Music));
        private StringBuilder _next_uri = new StringBuilder ();
        private GstPlayer _player = new GstPlayer ();
        private Settings _settings;
        private uint _sort_mode = SortMode.TITLE;
        private bool _store_external_changed = false;
        private Thumbnailer _thumbnailer = new Thumbnailer ();

        public signal void index_changed (int index, uint size);
        public signal void music_changed (Music? music);
        public signal void music_cover_parsed (Music music, Gdk.Pixbuf? cover, string? cover_uri);
        public signal void music_library_changed (bool external);
        public signal void playlist_added (Playlist playlist);
        public signal void thumbnail_changed (Music music, Gdk.Paintable paintable);

        public Application () {
            Object (application_id: Config.APP_ID, flags: ApplicationFlags.HANDLES_OPEN);
        }

        public override void startup () {
            base.startup ();

            //  Must load tag cache after the app register (GLib init), to make sort works
            _loader.load_tag_cache ();

            _actions = new ActionHandles (this);

            _current_list.model = _music_queue;
            _current_list.items_changed.connect (on_music_list_changed);
            _music_queue.items_changed.connect (on_music_library_changed);
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
            settings.bind ("color-scheme", this, "color-scheme", SettingsBindFlags.DEFAULT);
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

            var window = Window.get_default ();
            if (window != null) {
                ((!)window).present ();
            } else {
                open ({}, "");
            }
        }

        public override void open (File[] files, string hint) {
            var window = Window.get_default ();
            var initial = window == null;
            (window ?? new Window (this))?.present ();

            if (initial && _current_music == null) {
                var folders = files;
                folders.resize (folders.length + 1);
                folders[folders.length - 1] = File.new_for_uri (music_folder);
                var recent_uri = _current_music?.uri ?? _settings.get_string ("recent-music");
                foreach (var file in folders) {
                    if (recent_uri.has_prefix (file.get_uri ())) {
                        // 1.Load recent played uri if in folders
                        _current_music = new Music (recent_uri, "", 0);
                        _player.uri = _current_uri = recent_uri;
                        _player.state = Gst.State.PAUSED;
                        break;
                    }
                }
            }

            var saved_modified = _list_modified;
            var plist_file = get_playing_list_file ();
            var load_plist = initial && files.length == 0;
            var files_ref = load_plist ? new File[] { plist_file } : files;
            // 2.Load last playing queue if no other files to load
            open_files_async.begin (files_ref, -1, files.length > 0, (obj, res) => {
                var ret = open_files_async.end (res);
                if (ret) {
                    _list_modified = saved_modified;
                    if (load_plist)
                        _loader.library.playlists.remove (plist_file.get_uri ());
                }
                if (initial) {
                    // 3. Load music folder to build the library
                    load_music_folder_async.begin (!ret, (obj, res)
                        => load_music_folder_async.end (res));
                }
            });
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

        public uint color_scheme {
            get {
                return (uint) style_manager.color_scheme;
            }
            set {
                var action = lookup_action (ACTION_SCHEME);
                (action as SimpleAction)?.set_state (value.to_string ());
                style_manager.color_scheme = (Adw.ColorScheme) value;
            }
        }

        public unowned Gst.Sample? current_cover {
            get {
                return _current_cover;
            }
        }

        public int current_item {
            get {
                return _current_index;
            }
            set {
                if (value >= (int) _current_list.get_n_items ()) {
                    value = Window.get_default ()?.open_next_playable_page () ?? value;
                }
                current_music = _current_list.get_item (value) as Music;
                _current_index = value;
                index_changed (_current_index, _current_list.get_n_items ());
                update_next_item (value);
            }
        }

        public Gtk.FilterListModel current_list {
            get {
                return _current_list;
            }
            set {
                if (_current_list != value) {
                    _current_list.items_changed.disconnect (on_music_list_changed);
                    _current_list = value;
                    _current_list.items_changed.connect (on_music_list_changed);
                    update_current_item ();
                }
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
                if (_current_uri != uri) {
                    _current_cover = null;
                    _player.state = Gst.State.READY;
                    _player.uri = _current_uri = uri;
                    if (uri.length > 0)
                        _player.state = playing ? Gst.State.PLAYING : Gst.State.PAUSED;
                }
                _settings.set_string ("recent-music", uri);
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
                if (_music_folder != value) {
                    _music_folder = value;
                    if (Window.get_default () != null)
                        reload_library ();
                }
            }
        }

        public ListStore music_queue {
            get {
                return _music_queue;
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
                return _sort_mode;
            }
            set {
                var action = lookup_action (ACTION_SORT);
                var state = new Variant.string (value.to_string ());
                (action as SimpleAction)?.set_state (state);

                if (_sort_mode != value) {
                    _sort_mode = value;
                    sort_music_store ((ListStore) _music_queue, value);
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
                string? title = null;
                var map = new GenericSet<string> (str_hash, str_equal);
                if (append) {
                    title = load_playlist_file (file, uris);
                    uris.foreach ((uri) => map.add (uri));
                }
                foreach (var music in playlist.items) {
                    var uri = music.uri;
                    if (!map.contains (uri))
                        uris.add (uri);
                }
                var ret = save_playlist_file (file, uris, title ?? playlist.title);
                if (ret) {
                    //  Replace items if loaded from existing file
                    playlist.clear ();
                    foreach (var uri in uris) {
                        var music = _loader.find_cache (uri);
                        if (music != null)
                            playlist.add_music ((!)music);
                    }
                    playlist.set_cover_uri ();
                    if (title != null)
                        playlist.set_title ((!)title);
                }
                return ret;
            });
            if (saved)
                playlist_added (_loader.library.add_playlist (playlist));
            else
                Window.get_default ()?.show_toast (_("Save playlist failed"));
            return saved;
        }

        public bool insert_after_current (Playlist playlist) {
            uint position = _current_index;
            if (_current_music != null) {
                if (!_music_queue.find ((!)_current_music, out position))
                    position = -1;
                playlist.remove_music ((!)_current_music);
            }
            return insert_to_queue (playlist, position + 1);
        }

        public bool insert_to_queue (Playlist playlist, uint position = -1, bool play_now = false) {
            var changed = merge_items_to_store (_music_queue, playlist.items, ref position);
            list_modified |= changed;
            if (play_now) {
                current_item = (int) position;
                _player.play ();
            }
            return changed;
        }

        public async void load_music_folder_async (bool replace) {
            var files = new File[] { File.new_for_uri (music_folder) };
            var musics = new GenericArray<Music> (4096);
            yield _loader.load_files_async (files, musics, false, false, _sort_mode);
            _store_external_changed = true;
            if (replace) {
                _music_queue.splice (0, _music_queue.get_n_items (), (Object[]) musics.data);
            } else {
                on_music_library_changed (0, 1, 1);
            }
            if (_current_music == null) {
                current_item = 0;
            }
        }

        public async bool open_files_async (File[] files, uint position = -1, bool play_now = false) {
            var playlist = new Playlist ("");
            yield _loader.load_files_async (files, playlist.items);
            return playlist.length > 0 && insert_to_queue (playlist, position, play_now || _current_music == null);
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
                    _loader.remove_all ();
                    load_music_folder_async.begin (true, (obj, res) => load_music_folder_async.end (res));
                });
            }
        }

        public void request_background () {
            var portal = _actions?.portal ?? new Portal ();
            portal.request_background_async.begin (_("Keep playing after window closed"),
                (obj, res) => portal.request_background_async.end (res));
        }

        public async bool rename_playlist_async (Playlist playlist, string title) {
            var file = File.new_for_uri (playlist.list_uri);
            var uris = new GenericArray<string> (playlist.length);
            playlist.items.foreach ((music) => uris.add (music.uri));
            var saved = yield run_async<bool> (() => save_playlist_file (file, uris, title));
            if (saved) {
                playlist.set_title (title);
                playlist_added (_loader.library.add_playlist (playlist));
            }
            return saved;
        }

        public async void save_to_playlist_file_async (Playlist playlist) {
            var uri = playlist.list_uri;
            var file = File.new_for_uri (uri);
            var append = uri.length == 0;
            if (append) {
                var filter = new Gtk.FileFilter ();
                filter.name = _("Playlist Files");
                filter.add_mime_type ("audio/x-mpegurl");
                filter.add_mime_type ("audio/x-scpls");
                filter.add_mime_type ("public.m3u-playlist");
                var initial = File.new_for_uri (music_folder).get_child (playlist.title + ".m3u");
                var file_new = yield show_save_file_dialog (active_window, initial, {filter});
                if (file_new == null)
                    return;
                file = (!)file_new;
                playlist.set_list_uri (file.get_uri ());
                playlist.set_title (get_file_display_name (file));
            }
            var saved = yield add_playlist_to_file_async (playlist, append);
            if (saved && append)
                Window.get_default ()?.show_toast (_("Save playlist successfully"), build_library_uri (null, playlist));
        }

        public async void show_add_playlist_dialog (Playlist playlist) {
            var dialog = new PlaylistDialog (this);
            var pls = yield dialog.choose (Window.get_default ());
            if (pls != null) {
                var list_uri = ((!)pls).list_uri;
                if (list_uri.length > 0) {
                    playlist.set_list_uri (list_uri);
                    yield add_playlist_to_file_async (playlist, true);
                } else {
                    yield save_to_playlist_file_async (playlist);
                }
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

        private int find_music_item_by_uri (string uri) {
            var music = _loader.find_cache (uri);
            if (music != null) {
                var index = find_item_in_model (_current_list, music, _current_index);
                if (index != -1)
                    return index;
            }
            var count = _current_list.get_n_items ();
            for (var i = 0; i < count; i++) {
                var m = (Music) _current_list.get_item (i);
                if (m.uri == uri)
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
            _store_external_changed = true;
            if (arr.length > 0) {
                _music_queue.splice (_music_queue.get_n_items (), 0, (Object[]) arr.data);
            } else {
                on_music_library_changed (0, 1, 1);
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
                }, Priority.LOW);
            }
        }

        private void on_music_library_changed (uint position, uint removed, uint added) {
            if (removed != 0 || added != 0) {
                if (_pending_msc_handler != 0)
                    Source.remove (_pending_msc_handler);
                _pending_msc_handler = run_idle_once (() => {
                    _pending_msc_handler = 0;
                    music_library_changed (_store_external_changed);
                    _store_external_changed = false;
                }, Priority.LOW);
            }
        }

        private void on_music_lost (GenericSet<Music> removed) {
            _store_external_changed = true;
            if (removed.length > 0) {
                var arr = new GenericArray<Music> (removed.length);
                removed.foreach ((music) => arr.add (music));
                remove_items_from_store (_music_queue, arr);
            } else {
                on_music_library_changed (0, 1, 1);
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
            Window.get_default ()?.show_toast (err.message);
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
                _inhibit_id = this.inhibit (Window.get_default (), Gtk.ApplicationInhibitFlags.SUSPEND, _("Keep playing"));
            } else if (state != Gst.State.PLAYING && _inhibit_id != 0) {
                this.uninhibit (_inhibit_id);
                _inhibit_id = 0;
            }
        }

        private int _cover_size = 360;

        private async void on_player_tag_parsed (string? u, Gst.TagList? tags) {
            var uri = u ?? "";
            if (_current_music != null && _current_uri == uri) {
                var music = _loader.find_cache (_current_uri) ?? (!)_current_music;
                if (music != _current_music) {
                    _current_music = music;
                    music_changed (music);
                } else if (music.has_unknown () && tags != null && music.from_gst_tags ((!)tags)) {
                    _loader.add_to_cache (music);
                    music_changed (music);
                }

                _current_cover = tags != null ? parse_image_from_tag_list ((!)tags) : null;
                if (_current_cover == null && u != null) {
                    _current_cover = yield run_async<Gst.Sample?> (() => {
                        var file = File.new_for_uri ((!)uri);
                        var t = parse_gst_tags (file);
                        return t != null ? parse_image_from_tag_list ((!)t) : null;
                    });
                }

                Gdk.Pixbuf? pixbuf = null;
                var image = _current_cover;
                if (_current_uri == uri) {
                    var size = _cover_size * _thumbnailer.scale_factor;
                    if (image != null) {
                        pixbuf = yield run_async<Gdk.Pixbuf?> (
                            () => load_clamp_pixbuf_from_sample ((!)image, size), true);
                    }
                    if (pixbuf == null) {
                        pixbuf = yield _thumbnailer.load_directly_async (music, size);
                    }
                }

                if (_current_uri == uri) {
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
                    if (_current_uri == uri) {
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
                        thumbnail_changed (music, paintable);
                    }
                }
            }
        }

        private void update_current_item () {
            _current_index = find_item_in_model (_current_list, _current_music, _current_index);
            if (_current_index == -1 && _current_music != null) {
                unowned var uri = ((!)_current_music).uri;
                _current_index = find_music_item_by_uri (uri);
                current_music = _current_index != -1 ? _current_list.get_item (_current_index) as Music : _loader.find_cache (uri);
            }
            index_changed (_current_index, _current_list.get_n_items ());
            update_next_item (_current_index);
        }

        private void update_next_item (int index) {
            var count = _current_list.get_n_items ();
            var next = index + 1;
            var next_music = next < (int) count ? (Music) _current_list.get_item (next) : (Music?) null;
            lock (_next_uri) {
                _next_uri.assign (next_music?.uri ?? "");
            }
        }
    }

    public File get_playing_list_file () {
        var cache_dir = Environment.get_user_cache_dir ();
        return File.new_build_filename (cache_dir, Config.APP_ID, PageName.PLAYING + ".m3u");
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
