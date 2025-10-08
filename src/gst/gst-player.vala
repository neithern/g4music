namespace G4 {

    public class GstPlayer : Object {

        public static void init (ref unowned string[]? args) {
            Gst.init (ref args);
        }

        public static Gst.ClockTime from_second (double time) {
            return (Gst.ClockTime) (time * Gst.SECOND);
        }

        public static double to_second (Gst.ClockTime time) {
            return (double) time / Gst.SECOND;
        }

        public static void get_audio_sinks (GenericArray<Gst.ElementFactory> sinks) {
            var caps = new Gst.Caps.simple ("audio/x-raw", "format", Type.STRING, "S16LE", null);
            var list = Gst.ElementFactory.list_get_elements (Gst.ElementFactoryType.AUDIOVIDEO_SINKS, Gst.Rank.SECONDARY);
            list = Gst.ElementFactory.list_filter (list, caps, Gst.PadDirection.SINK, false);
            list.foreach ((factory) => sinks.add (factory));
        }

        private dynamic Gst.Pipeline? _pipeline = null;
        private dynamic Gst.Element? _audio_sink = null;
        private dynamic Gst.Element? _replay_gain = null;
        private dynamic Gst.Element? _pitch_element = null;
        private string _audio_sink_name = "";
        private int _audio_sink_requested = 0;
        private string? _current_uri = null;
        private Gst.ClockTime _duration = Gst.CLOCK_TIME_NONE;
        private Gst.ClockTime _position = Gst.CLOCK_TIME_NONE;
        private int _last_error_code = 0;
        private ulong _about_to_finish_id = 0;
        private int _next_uri_requested = 0;
        private double _last_peak = 0;
        private LevelCalculator _peak_calculator = new LevelCalculator ();
        private Gst.State _state = Gst.State.NULL;
        private bool _seeking = false;
        private Gst.TagList? _tag_list = null;
        private uint _tag_handle = 0;
        private bool _tag_parsed = false;
        private uint _timer_handle = 0;
        private bool _pitch_correction_enabled = true;
        private unowned Thread<void> _main_thread = Thread<void>.self ();

        public signal void duration_changed (Gst.ClockTime duration);
        public signal void error (Error error);
        public signal void end_of_stream ();
        public signal void position_updated (Gst.ClockTime position);
        public signal string? next_uri_request ();
        public signal void next_uri_start ();
        public signal void state_changed (Gst.State state);
        public signal void tag_parsed (string? uri, Gst.TagList? tags);

        public GstPlayer () {
            uint major = 0, minor = 0, micro = 0, nano = 0;
            Gst.version (out major, out minor, out micro, out nano);
            if (major > 1 || (major == 1 && minor >= 24)) {
                _pipeline = Gst.ElementFactory.make ("playbin3", "player") as Gst.Pipeline;
                if (_pipeline != null)
                    print (@"Use playbin3\n");
            }
            if (_pipeline == null) {
                _pipeline = Gst.ElementFactory.make ("playbin", "player") as Gst.Pipeline;
            }
            if (_pipeline != null) {
                var pipeline = (!)_pipeline;
                pipeline.async_handling = true;
                pipeline.flags = 0x0022; // audio | native audio
                var pitch = Gst.ElementFactory.make ("pitch", "pitch");
                if (pitch != null) {
                    pipeline.audio_filter = pitch;
                    _pitch_element = pitch;
                } else {
                    warning ("Could not create GStreamer pitch element - gst-plugins-bad may not be installed.");
                    warning ("Playback speed control will not be available.");
                }
                pipeline.bind_property ("volume", this, "volume", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
                pipeline.get_bus ().add_watch (Priority.DEFAULT, bus_callback);
            } else {
                critical ("Create playbin failed\n");
            }
        }

        ~GstPlayer () {
            if (_tag_handle != 0)
                Source.remove (_tag_handle);
            if (_timer_handle != 0)
                Source.remove (_timer_handle);
            _peak_calculator.clear ();
            _pipeline?.set_state (Gst.State.NULL);
        }

        public bool gapless {
            get {
                return _about_to_finish_id != 0;
            }
            set {
                if (_pipeline != null) {
                    var pipeline = (!)_pipeline;
                    if (_about_to_finish_id != 0) {
                        pipeline.disconnect (_about_to_finish_id);
                        _about_to_finish_id = 0;
                    }
                    if (value) {
                        _about_to_finish_id = pipeline.about_to_finish.connect (on_stream_to_finish);
                    }
                }
            }
        }

        public bool playing {
            get {
                return _state == Gst.State.PLAYING;
            }
            set {
                state = _state == Gst.State.PLAYING ? Gst.State.PAUSED : Gst.State.PLAYING;
            }
        }

        public Gst.State state {
            get {
                return _state;
            }
            set {
                _pipeline?.set_state (value);
            }
        }

        public string? uri {
            get {
                return _current_uri;
            }
            set {
                _current_uri = value;
                if (_pipeline != null) {
                    ((!)_pipeline).uri = value;
                    if (AtomicInt.compare_and_exchange (ref _audio_sink_requested, 1, 0))
                        update_audio_sink ();
                }
            }
        }

        public string audio_sink {
            get {
                return _audio_sink_name;
            }
            set {
                var sink_name = value;
                if (sink_name.length == 0 || (Gst.ElementFactory.find (sink_name)?.get_rank () ?? Gst.Rank.NONE) <= Gst.Rank.MARGINAL) {
                    var list = Gst.ElementFactory.list_get_elements (Gst.ElementFactoryType.AUDIOVIDEO_SINKS, Gst.Rank.PRIMARY);
                    if (!list.is_empty ())
                        sink_name = list.first ().data.name;
                }
                var sink = Gst.ElementFactory.make (sink_name, sink_name);
                if (sink != null) {
                    _audio_sink = sink;
                    _audio_sink_name = value;
                    ((!)_audio_sink).enable_last_sample = true;
                }
                if (_pipeline != null && _current_uri != null)
                    update_audio_sink ();
                else
                    AtomicInt.set (ref _audio_sink_requested, 1);
            }
        }

        public double peak {
            get {
                var value = _last_peak;
                dynamic Gst.Element? sink = _audio_sink ?? _pipeline?.audio_sink;
                if (sink != null) {
                    dynamic Gst.Sample? sample = ((!)sink).last_sample;
                    if (sample != null)
                        _peak_calculator.calculate_sample ((!)sample, _position, ref value);
                }
                value = double.max (value, _last_peak >= 0.033 ? _last_peak - 0.033 : 0);
                _last_peak = value;
                return value;
            }
        }

        public Gst.ClockTime position {
            get {
                return _position;
            }
            set {
                seek (value);
            }
        }

        public uint replay_gain {
            get {
                if (_replay_gain != null)
                    return ((!)_replay_gain).album_mode ? 2 : 1;
                return 0;
            }
            set {
                _replay_gain = value != 0 ? Gst.ElementFactory.make ("rgvolume", "gain") : null;
                if (_replay_gain != null)
                    ((!)_replay_gain).album_mode = value == 2;
                if (_pipeline != null && _current_uri != null)
                    update_audio_sink ();
                else
                    AtomicInt.set (ref _audio_sink_requested, 1);
            }
        }

        public double playback_speed {
            get {
                if (_pitch_element != null) {
                    var value = new GLib.Value (typeof (double));
                    var prop_name = _pitch_correction_enabled ? "tempo" : "rate";
                    ((!)_pitch_element).get_property (prop_name, ref value);
                    return value.get_double ();
                }
                return 1.0;
            }
            set {
                if (_pitch_element != null) {
                    if (_pitch_correction_enabled) {
                        ((!)_pitch_element).set_property ("rate", 1.0);
                        ((!)_pitch_element).set_property ("tempo", value);
                    } else {
                        ((!)_pitch_element).set_property ("tempo", 1.0);
                        ((!)_pitch_element).set_property ("rate", value);
                    }
                }
            }
        }

        public bool pitch_correction {
            get {
                return _pitch_correction_enabled;
            }
            set {
                var current_speed = this.playback_speed;
                _pitch_correction_enabled = value;
                this.playback_speed = current_speed;
            }
        }

        public Gst.TagList? tag_list {
            get {
                return _tag_list;
            }
        }

        public double volume { get; set; }

        public void play () {
            _pipeline?.set_state (Gst.State.PLAYING);
        }

        public void pause () {
            _pipeline?.set_state (Gst.State.PAUSED);
        }

        public void seek (Gst.ClockTime position) {
            if (_pipeline != null && !_seeking) {
                //  print ("Seek: %g -> %g\n", to_second (_position), to_second (position));
                _seeking = ((!)_pipeline).seek_simple (Gst.Format.TIME, Gst.SeekFlags.ACCURATE | Gst.SeekFlags.FLUSH, (int64) position);
            }
        }

        private void emit_tag_parsed (uint delay = 0) {
            if (_tag_handle != 0)
                Source.remove (_tag_handle);
            _tag_handle = run_timeout_once (delay, () => {
                _tag_handle = 0;
                _tag_parsed = true;
                tag_parsed (_current_uri, _tag_list);
            });
        }

        private bool bus_callback (Gst.Bus bus, Gst.Message message) {
            unowned Thread<void> thread = Thread<void>.self ();
            if (thread == _main_thread) {
                on_bus_message (message);
            } else {
                message.ref ();
                Idle.add (() => {
                    on_bus_message (message);
                    message.unref ();
                    return false;
                });
                warning ("Bus message not in main thread: %p, %s\n", thread, message.type.get_name ());
            }
            return true;
        }

        private void on_bus_message (Gst.Message message) {
            switch (message.type) {
                case Gst.MessageType.ASYNC_DONE:
                    parse_position ();
                    _seeking = false;
                    break;

                case Gst.MessageType.DURATION_CHANGED:
                    parse_duration ();
                    break;

                case Gst.MessageType.STATE_CHANGED:
                    if (message.src == (!)_pipeline) {
                        Gst.State old = Gst.State.NULL, state = Gst.State.NULL, pend = Gst.State.NULL;
                        message.parse_state_changed (out old, out state, out pend);
                        on_state_changed (old, state);
                    }
                    break;

                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    message.parse_error (out err, out debug);
                    print (@"Player error: $(err.domain), $(err.code), $(err.message)\n");
                    if (_last_error_code < err.code) {
                        _last_error_code = err.code;
                        error (err);
                    }
                    break;

                case Gst.MessageType.EOS:
                    end_of_stream ();
                    break;

                case Gst.MessageType.STREAM_START:
                    on_stream_start ();
                    if (!_tag_parsed) {
                        emit_tag_parsed (50);
                    }
                    break;

                case Gst.MessageType.TAG:
                    Gst.TagList? tags = null;
                    message.parse_tag (out tags);
                    _tag_list = merge_tags (_tag_list, tags);
                    if (!_tag_parsed) {
                        emit_tag_parsed (tags_has_image (_tag_list) ? 0 : 50);
                    }
                    break;

                default:
                    break;
            }
        }

        private void on_state_changed (Gst.State old, Gst.State state) {
            if (old != state && _state != state) {
                _state = state;
                state_changed (state);
                //  print (@"State changed: $old -> $state\n");
            }
            if (_timer_handle == 0 && state == Gst.State.PLAYING) {
                _timer_handle = Timeout.add (100, parse_position);
            } else if (_timer_handle != 0 && state != Gst.State.PLAYING) {
                Source.remove (_timer_handle);
                _timer_handle = 0;
            }
        }

        private void on_stream_start () {
            _last_error_code = 0;
            _peak_calculator.clear ();
            _tag_list = null;
            _tag_parsed = false;
            if (AtomicInt.compare_and_exchange (ref _next_uri_requested, 1, 0)) {
                next_uri_start ();
            }
            if (_pitch_element != null) {
                Idle.add (() => { seek (0); return false; });
            }
            parse_duration ();
            parse_position ();
        }

        private void on_stream_to_finish () {
            var next_uri = next_uri_request ();
            if (next_uri != null && ((!)next_uri).length > 0) {
                AtomicInt.set (ref _next_uri_requested, 1);
                uri = (!)next_uri;
            }
        }

        private void parse_duration () {
            if (((!)_pipeline).query_duration (Gst.Format.TIME, out _duration)) {
                duration_changed (_duration);
            } else {
                _duration = Gst.CLOCK_TIME_NONE;
            }
        }

        private bool parse_position () {
            if (((!)_pipeline).query_position (Gst.Format.TIME, out _position)) {
                position_updated (_position);
            } else {
                _position = Gst.CLOCK_TIME_NONE;
            }
            return true;
        }

        private Gst.Element? setup_audio_sink () {
            dynamic Gst.Bin? sink_bin = Gst.ElementFactory.make ("bin", "audio-sink-bin") as Gst.Bin;

            if (_replay_gain != null) {
                (_replay_gain?.parent as Gst.Bin)?.remove_element ((!)_replay_gain);
                sink_bin?.add ((!)_replay_gain);
            }
            print (@"Enable ReplayGain: $(_replay_gain != null)\n");

            if (_audio_sink != null) {
                (_audio_sink?.parent as Gst.Bin)?.remove_element ((!)_audio_sink);
                sink_bin?.add ((!)_audio_sink);
                _replay_gain?.link ((!)_audio_sink);
            }
            print ("Audio Sink: %s\n", _audio_sink?.name ?? "");

            Gst.Pad? static_pad = (_replay_gain ?? _audio_sink)?.get_static_pad ("sink");
            if (static_pad != null) {
                sink_bin?.add_pad (new Gst.GhostPad ("sink", (!)static_pad));
            } else {
                (_audio_sink?.parent as Gst.Bin)?.remove_element ((!)_audio_sink);
            }
            return static_pad != null ? sink_bin : _audio_sink;
        }

        private void update_audio_sink () {
            var pipeline = (!)_pipeline;
            var saved_pos = _position;
            var saved_state = _state;
            pipeline.set_state (Gst.State.NULL);
            pipeline.audio_sink = setup_audio_sink ();
            if (saved_state != Gst.State.NULL) {
                pipeline.set_state (saved_state);
            }
            if (saved_pos != Gst.CLOCK_TIME_NONE && saved_state >= Gst.State.PAUSED) {
                Idle.add (() => {
                    if (_state == saved_state) {
                        seek (saved_pos);
                        return false;
                    }
                    return _state != Gst.State.NULL;
                }, Priority.LOW);
            }
        }
    }
}
