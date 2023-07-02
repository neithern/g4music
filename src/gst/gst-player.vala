namespace G4 {

    public class GstPlayer : Object {
        struct Peak {
            Gst.ClockTime time;
            double peak;
        }

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
            var list = Gst.ElementFactory.list_get_elements (Gst.ElementFactoryType.AUDIOVIDEO_SINKS, Gst.Rank.NONE);
            list = Gst.ElementFactory.list_filter (list, caps, Gst.PadDirection.SINK, false);
            list.foreach ((factory) => {
                if (factory.get_rank () >= Gst.Rank.MARGINAL || factory.name == "pipewiresink")
                    sinks.add (factory);
            });
        }

        private dynamic Gst.Pipeline? _pipeline = Gst.ElementFactory.make ("playbin", "player") as Gst.Pipeline;
        private dynamic Gst.Element? _audio_sink = null;
        private dynamic Gst.Element? _replay_gain = null;
        private int _audio_channels = 2;
        private int _audio_bps = 2;
        private int _sample_bps = 2;
        private string _audio_sink_name = "";
        private string? _current_uri = null;
        private Gst.ClockTime _duration = Gst.CLOCK_TIME_NONE;
        private Gst.ClockTime _position = Gst.CLOCK_TIME_NONE;
        private ulong _about_to_finish_id = 0;
        private int _next_uri_requested = 0;
        private Gst.State _state = Gst.State.NULL;
        private bool _tag_parsed = false;
        private uint _timer_handle = 0;
        private double _last_peak = 0;
        private Queue<Peak?> _peaks = new Queue<Peak?> ();
        private unowned Gst.Caps? _last_caps = null;
        private unowned Gst.ClockTime _last_sample_time = Gst.CLOCK_TIME_NONE;
        private LevelCalculateFunc? _level_calculate = null;
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
            if (_pipeline != null) {
                var pipeline = (!)_pipeline;
                pipeline.async_handling = true;
                pipeline.flags = 0x0022; // audio | native audio
                pipeline.bind_property ("volume", this, "volume", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
                pipeline.get_bus ().add_watch (Priority.DEFAULT, bus_callback);
            } else {
                critical ("Create playbin failed\n");
            }
        }

        ~GstPlayer () {
            _peaks.clear ();
            _pipeline?.set_state (Gst.State.NULL);
            if (_timer_handle != 0) {
                Source.remove (_timer_handle);
                _timer_handle = 0;
            }
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
                        _about_to_finish_id = pipeline.about_to_finish.connect (on_about_to_finish);
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
                if (_pipeline != null) lock (_pipeline) {
                    _duration = Gst.CLOCK_TIME_NONE;
                    _position = Gst.CLOCK_TIME_NONE;
                    _last_sample_time = Gst.CLOCK_TIME_NONE;
                    _tag_parsed = false;
                    if (strcmp (_current_uri, value) != 0) {
                        _current_uri = value;
                        ((!)_pipeline).uri = value;
                    }
                }
            }
        }

        public string audio_sink {
            get {
                return _audio_sink_name;
            }
            set {
                if (_pipeline != null) {
                    var sink_name = value;
                    if (sink_name.length == 0) {
                        var sinks = new GenericArray<Gst.ElementFactory> (8);
                        get_audio_sinks (sinks);
                        if (sinks.length > 0)
                            sink_name = sinks[0].name;
                    }
                    var sink = Gst.ElementFactory.make (sink_name, "audiosink");
                    if (sink != null) {
                        _audio_sink = sink;
                        _audio_sink_name = value;
                        ((!)_audio_sink).enable_last_sample = true;
                    }
                    update_audio_sink ();
                    print (@"Audio sink$(sink != null ? ":" : "!=") $(sink_name)\n");
                }
            }
        }

        public uint replay_gain {
            get {
                if (_replay_gain != null)
                    return ((!)_replay_gain).album_mode ? 2 : 1;
                return 0;
            }
            set {
                if (_pipeline != null) {
                    _replay_gain = value != 0 ? Gst.ElementFactory.make ("rgvolume", "gain") : null;
                    if (_replay_gain != null)
                        ((!)_replay_gain).album_mode = value == 2;
                    update_audio_sink ();
                    print (@"Enable ReplayGain: $(value != 0 && _replay_gain != null)\n");
                }
            }
        }

        public double peak {
            get {
                double value = _last_peak;
                parse_peak_from_last_sample (ref value);
                value = double.max (value, _last_peak >= 0.033 ? _last_peak - 0.033 : 0);
                _last_peak = value;
                return value;
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
            var diff = (Gst.ClockTimeDiff) (position - _position);
            if (diff > 50 * Gst.MSECOND || diff < -50 * Gst.MSECOND) {
                //  print ("Seek: %g -> %g\n", to_second (_position), to_second (position));
                _position = position;
                _pipeline?.seek_simple (Gst.Format.TIME, Gst.SeekFlags.ACCURATE | Gst.SeekFlags.FLUSH, (int64) position);
            }
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
                case Gst.MessageType.DURATION_CHANGED:
                    parse_duration ();
                    break;

                case Gst.MessageType.STATE_CHANGED:
                    if (message.src == (!)_pipeline) {
                        Gst.State old = Gst.State.NULL;
                        Gst.State state = Gst.State.NULL;
                        Gst.State pending = Gst.State.NULL;
                        message.parse_state_changed (out old, out state, out pending);
                        if (old == Gst.State.READY && state == Gst.State.PAUSED) {
                            parse_duration ();
                            if (!_tag_parsed) {
                                //  Hack: force emit if no tag parsed for MOD files
                                _tag_parsed = true;
                                tag_parsed (_current_uri, null);
                            }
                        }
                        if (old != state && _state != state) {
                            _state = state;
                            if (_timer_handle != 0 && state != Gst.State.PLAYING) {
                                Source.remove (_timer_handle);
                                _timer_handle = 0;
                            } else if (_timer_handle == 0 && state == Gst.State.PLAYING) {
                                _timer_handle = Timeout.add (200, parse_position);
                            }
                            state_changed (state);
                            parse_position ();
                            //  print (@"State changed: $old -> $state\n");
                        }
                    }
                    break;

                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    message.parse_error (out err, out debug);
                    error (err);
                    break;

                case Gst.MessageType.EOS:
                    end_of_stream ();
                    break;

                case Gst.MessageType.STREAM_START:
                    if (AtomicInt.compare_and_exchange (ref _next_uri_requested, 1, 0)) {
                        _peaks.clear ();
                        next_uri_start ();
                        parse_duration ();
                        parse_position ();
                    }
                    break;

                case Gst.MessageType.TAG:
                    Gst.TagList? tags = null;
                    message.parse_tag (out tags);
                    _tag_parsed = true;
                    tag_parsed (_current_uri, tags);
                    break;

                default:
                    break;
            }
        }

        private void on_about_to_finish () {
            var next_uri = next_uri_request ();
            if (next_uri != null && ((!)next_uri).length > 0) {
                AtomicInt.set (ref _next_uri_requested, 1);
                uri = (!)next_uri;
            }
        }

        private bool parse_duration () {
            int64 duration = (int64) Gst.CLOCK_TIME_NONE;
            if ((_pipeline?.query_duration (Gst.Format.TIME, out duration) ?? false)
                    && _duration != duration) {
                _duration = duration;
                //  print ("Duration changed: %lld\n", duration);
                duration_changed (duration);
            }
            return duration != (int64) Gst.CLOCK_TIME_NONE;
        }

        private bool parse_position () {
            int64 position = (int64) Gst.CLOCK_TIME_NONE;
            if ((_pipeline?.query_position (Gst.Format.TIME, out position) ?? false)
                    && _position != position) {
                _position = position;
                position_updated (position);
            }
            return true;
        }

        private bool parse_peak_from_last_sample (ref double peak_value) {
            bool parsed = false;
            dynamic Gst.Element? sink = _audio_sink ?? _pipeline?.audio_sink;
            if (sink != null) {
                dynamic Gst.Sample? sample = ((!)sink).last_sample;
                var peak = Peak ();
                peak.time = sample?.get_segment ()?.position ?? int64.MIN;
                if (sample != null && _last_sample_time != peak.time
                        && parse_peak_in_sample ((!)sample, out peak.peak)) {
                    _peaks.push_tail (peak);
                    _last_sample_time = peak.time;
                    parsed = true;
                }
                while (_peaks.length > 0) {
                    unowned var p = (!)_peaks.peek_head ();
                    if (p.time >= _position) {
                        peak_value = p.peak;
                        _peaks.pop_head ();
                    } else {
                        break;
                    }
                }
            }
            return parsed;
        }

        private void update_audio_sink () {
            var saved_pos = _position;
            var saved_state = _state;
            _pipeline?.set_state (Gst.State.NULL);

            if (_audio_sink != null) {
                var bin = _audio_sink?.parent as Gst.Bin;
                bin?.remove_element ((!)_audio_sink);
            }
            if (_replay_gain != null) {
                var bin = _replay_gain?.parent as Gst.Bin;
                bin?.remove_element ((!)_replay_gain);
            }

            dynamic Gst.Bin? bin = null;
            if (_audio_sink != null && _replay_gain != null
                    && (bin = Gst.ElementFactory.make ("bin", null) as Gst.Bin) != null) {
                bin?.add_many ((!)_replay_gain, (!)_audio_sink);
                _replay_gain?.link ((!)_audio_sink);
                Gst.Pad? static_pad = _replay_gain?.get_static_pad ("sink");
                if (static_pad != null) {
                    bin?.add_pad (new Gst.GhostPad ("sink", (!)static_pad));
                } else {
                    bin = null;
                }
            }

            ((!)_pipeline).audio_sink = bin != null ? bin : _audio_sink;
            if (saved_state != Gst.State.NULL) {
                _pipeline?.set_state (saved_state);
            }
            if (saved_pos != Gst.CLOCK_TIME_NONE && saved_state >= Gst.State.PAUSED) {
                Idle.add (() => {
                    if (_state == saved_state) {
                        seek (saved_pos);
                        return false;
                    }
                    return _state != Gst.State.NULL;
                });
            }
        }

        private delegate void LevelCalculateFunc (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps);

        private bool parse_peak_in_sample (Gst.Sample sample, out double peak) {
            peak = 0;

            unowned var caps = sample.get_caps ();
            if (_last_caps != caps || _level_calculate == null) {
                unowned var st = caps?.get_structure (0);
                st?.get_int ("channels", out _audio_channels);
                if (_audio_channels == 0)
                    return false;

                unowned var format = st?.get_string ("format") ?? "";
                switch (format) {
                    case "S8":
                        _audio_bps = _sample_bps = 1;
                        _level_calculate = level_calculate_int;
                        break;
                    case "S16LE":
                        _audio_bps = _sample_bps = 2;
                        _level_calculate = level_calculate_int16;
                        break;
                    case "S24LE":
                        _audio_bps = _sample_bps = 3;
                        _level_calculate = level_calculate_int;
                        break;
                    case "S24_32LE":
                        _audio_bps = 3;
                        _sample_bps = 4;
                        _level_calculate = level_calculate_int;
                        break;
                    case "S32LE":
                        _audio_bps = _sample_bps = 4;
                        _level_calculate = level_calculate_int;
                        break;
                    case "F32LE":
                        _audio_bps = _sample_bps = 4;
                        _level_calculate = level_calculate_float;
                        break;
                    case "F64LE":
                        _audio_bps = _sample_bps = 8;
                        _level_calculate = level_calculate_double;
                        break;
                    default:
                        print ("Unsupported sample format: %s\n", format);
                        return false;
                }
                _last_caps = caps;
            }

            var channels = _audio_channels;
            var bps = _audio_bps;
            var sample_size = _sample_bps;
            var block_size = channels * sample_size;
            var buffer = sample.get_buffer ();
            var size = buffer?.get_size () ?? 0;

            Gst.MapInfo? map_info = null;
            if (buffer?.map (out map_info, Gst.MapFlags.READ) ?? false) {
                unowned uint8* p = ((!)map_info).data;
                var num = (uint) (size / block_size);
                double total_nps = 0;
                for (var i = 0; i < channels; i++) {
                    double nps = 0;
                    _level_calculate (p + (sample_size * i), num, channels, bps, sample_size, out nps);
                    total_nps += nps;
                }
                peak = double.min (total_nps / channels, 1);
                buffer?.unmap ((!)map_info);
                return true;
            }
            return false;
        }
    }

    void level_calculate_double (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        double peak = 0;
        double* p = (double*)data;
        for (uint i = 0; i < num; i += channels) {
            double value = p[i] >= 0 ? p[i] : -p[i];
            if (peak < value)
                peak = value;
        }
        nps = peak * peak;
    }

    void level_calculate_float (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        float peak = 0f;
        float* p = (float*)data;
        for (uint i = 0; i < num; i += channels) {
            float value = p[i] >= 0 ? p[i] : -p[i];
            if (peak < value)
                peak = value;
        }
        nps = (double) peak * peak;
    }

    void level_calculate_int16 (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        int16 peak = 0;
        int16* p = (int16*)data;
        for (uint i = 0; i < num; i += channels) {
            int16 value = p[i] >= 0 ? p[i] : -p[i];
            if (peak < value)
                peak = value;
        }
        nps = (double) peak * peak / (((int64) 1) << (15 * 2));
    }

    void level_calculate_int (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        int32 peak = 0;
        uint block_size = channels * sample_size;
        for (uint i = 0; i < num; i += channels) {
            int32 value = 0;
            uint8* p = (uint8*)&value + (4 - value_size);
            for (uint j = 0; j < value_size; j++) {
                p[j] = data[j];
            }
            data += block_size;
            value = value >= 0 ? value : -value;
            if (peak < value)
                peak = value;
        }
        nps = (double) peak * peak / (((int64) 1) << (31 * 2));
    }
}
