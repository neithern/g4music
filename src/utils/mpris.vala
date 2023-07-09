namespace G4 {

    [DBus (name = "org.mpris.MediaPlayer2.Player")]
    public class MprisPlayer : Object {
        [DBus (visible = false)]
        private unowned Application _app;
        private unowned DBusConnection _connection;
        private HashTable<string, Variant> _metadata = new HashTable<string, Variant> (str_hash, str_equal);
        private int64 _music_hash = int64.MIN;

        public MprisPlayer (Application app, DBusConnection connection) {
            _app = app;
            _connection = connection;

            app.index_changed.connect (on_index_changed);
            app.music_changed.connect (on_music_changed);
            app.music_cover_parsed.connect (on_music_cover_parsed);
            app.player.state_changed.connect (on_state_changed);
            app.player.duration_changed.connect (on_duration_changed);
        }

        public bool can_control {
            get {
                return true;
            }
        }

        public bool can_go_next {
            get {
                return _app.current_item < (int) _app.music_list.get_n_items () - 1;
            }
        }

        public bool can_go_previous {
            get {
                return _app.current_item > 0;
            }
        }

        public bool can_play {
            get {
                return _app.current_music != null;
            }
        }

        public bool can_pause {
            get {
                return _app.current_music != null;
            }
        }

        public HashTable<string, Variant> metadata {
            get {
                return _metadata;
            }
        }

        public string playback_status {
            owned get {
                return get_mpris_status(_app.player.state);
            }
        }

        public bool shuffle {
            get {
                return _app.sort_mode == SortMode.SHUFFLE;
            }
            set {
                if (value && (_app.sort_mode != SortMode.SHUFFLE)) {
                    _app.sort_mode = SortMode.SHUFFLE;
                } else {
                    _app.sort_mode = SortMode.TITLE;
                }
            }
        }

        public void next () throws Error {
            _app.play_next ();
        }

        public void previous () throws Error {
            _app.play_previous ();
        }

        public void play_pause () throws Error {
            _app.play_pause();
        }

        public void play () throws Error {
            _app.player.play ();
        }

        public void pause () throws Error {
            _app.player.pause ();
        }

        private void on_index_changed (int index, uint size) {
            var builder = new VariantBuilder (new VariantType ("a{sv}"));
            builder.add ("{sv}", "CanGoNext", new Variant.boolean (index < (int) size - 1));
            builder.add ("{sv}", "CanGoPrevious", new Variant.boolean (index > 0));
            builder.add ("{sv}", "CanPlay", new Variant.boolean (_app.current_music != null));
            builder.add ("{sv}", "CanPause", new Variant.boolean (_app.current_music != null));
            send_properties (builder);
        }

        private void on_music_changed (Music? music) {
            _metadata.remove_all ();
            if (music != null) {
                var artists = new VariantBuilder (new VariantType ("as"));
                artists.add ("s", music?.artist ?? "");
                _metadata.insert ("xesam:artist", artists.end());
                _metadata.insert ("xesam:title", new Variant.string (music?.title ?? ""));
                _metadata.insert ("xesam:album", new Variant.string (music?.album ?? ""));
                _music_hash = direct_hash (music);
            } else {
                _music_hash = int64.MIN;
            }
        }

        private void on_music_cover_parsed (Music music, string? uri) {
            if (_music_hash != direct_hash (music)) {
                on_music_changed (music);
            }
            if (uri != null) {
                _metadata.insert ("mpris:artUrl", new Variant.string ((!)uri));
            } else {
                _metadata.remove ("mpris:artUrl");
            }
            send_property ("Metadata", _metadata);
        }

        private void on_state_changed (Gst.State state) {
            send_property ("PlaybackStatus", new Variant.string (get_mpris_status(state)));
        }

        private void on_duration_changed (Gst.ClockTime duration) {
            var value = (double) duration / Gst.USECOND;
            _metadata.insert ("mpris:length", new Variant.int64 ((int) value));
            send_property ("Metadata", _metadata);
        }

        private void send_property (string name, Variant variant) {
            var builder = new VariantBuilder (new VariantType ("a{sv}"));
            builder.add ("{sv}", name, variant);
            send_properties (builder);
        }

        private void send_properties (VariantBuilder builder) {
            var invalid = new VariantBuilder (new VariantType ("as"));
            try {
                _connection.emit_signal (
                    null,
                    "/org/mpris/MediaPlayer2",
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    new Variant (
                        "(sa{sv}as)",
                        "org.mpris.MediaPlayer2.Player",
                        builder,
                        invalid
                    )
                );
            } catch (Error e) {
                warning ("Send MPRIS failed: %s\n", e.message);
            }
        }

        private string get_mpris_status (Gst.State state) {
            switch (state) {
                case Gst.State.PLAYING:
                    return "Playing";
                case Gst.State.PAUSED:
                    return "Paused";
                default:
                    return "Stopped";
            }
        }
    }

    [DBus (name = "org.mpris.MediaPlayer2")]
    public class MprisRoot : Object {
        private unowned Application _app;

        public MprisRoot (Application app) {
            _app = app;
        }

        public bool can_quit {
            get {
                return true;
            }
        }

        public bool can_raise {
            get {
                return true;
            }
        }

        public bool has_track_list {
            get {
                return false;
            }
        }

        public string desktop_entry {
            get {
                return _app.application_id;
            }
        }

        public string identity {
            get {
                return _app.name;
            }
        }

        public string[] supported_uri_schemes {
            owned get {
                return {"file", "smb"};
            }
        }

        public string[] supported_mime_types {
            owned get {
                return {"audio/*"};
            }
        }

        public void quit () throws Error {
            _app.quit ();
        }

        public void raise () throws Error {
            _app.activate ();
        }
    }
}
