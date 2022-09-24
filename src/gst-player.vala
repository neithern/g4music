namespace Music {

    public class GstPlayer : Object {
        struct Peak {
            Gst.ClockTime time;
            double peak;
        }

        public static void init (ref weak string[]? args) {
            Gst.init (ref args);
        }

        public static double to_second (Gst.ClockTime time) {
            return (double) time / Gst.SECOND;
        }

        public static Gst.ClockTime from_second (double time) {
            return (Gst.ClockTime) (time * Gst.SECOND);
        }

        private dynamic Gst.Pipeline? _pipeline = Gst.ElementFactory.make ("playbin", "player") as Gst.Pipeline;
        private dynamic Gst.Element? _audio_sink = null;
        private dynamic Gst.Element? _replay_gain = null;
        private int _audio_channels = 2;
        private int _audio_bps = 2;
        private Gst.ClockTime _duration = Gst.CLOCK_TIME_NONE;
        private Gst.ClockTime _position = Gst.CLOCK_TIME_NONE;
        private ulong _about_to_finish_id = 0;
        private int _next_uri_requested = 0;
        private bool _show_peak = false;
        private Gst.State _state = Gst.State.NULL;
        private int64 _tag_hash = int64.MIN;
        private bool _tag_parsed = false;
        private TimeoutSource? _timer = null;
        private unowned Gst.Caps? _last_caps = null;
        private LevelCalculateFunc? _level_calculate = null;
        private Queue<Peak?> _peaks = new Queue<Peak?> ();
        private unowned Thread<void> _main_thread = Thread<void>.self ();

        public signal void duration_changed (Gst.ClockTime duration);
        public signal void error (Error error);
        public signal void end_of_stream ();
        public signal void position_updated (Gst.ClockTime position);
        public signal string? next_uri_request ();
        public signal void next_uri_start ();
        public signal void state_changed (Gst.State state);
        public signal void tag_parsed (string? album, string? artist, string? title, Gst.Sample? image);
        public signal void peak_parsed (double peak);

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
            _peaks.clear_full (free);
            _pipeline?.set_state (Gst.State.NULL);
            _timer?.destroy ();
        }

        public bool gapless {
            get {
                return _about_to_finish_id != 0;
            }
            set {
                if (_pipeline != null) {
                    var pipeline = (!)_pipeline;
                    if (_about_to_finish_id != 0) {
                        SignalHandler.disconnect (pipeline, _about_to_finish_id);
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
                if (_pipeline != null)
                    return ((!)_pipeline).uri;
                return null;
            }
            set {
                if (_pipeline != null) lock (_pipeline) {
                    _duration = Gst.CLOCK_TIME_NONE;
                    _position = Gst.CLOCK_TIME_NONE;
                    _tag_hash = int64.MIN;
                    _tag_parsed = false;
                    _peaks.clear_full (free);
                    string? uri = ((!)_pipeline).uri;
                    if (strcmp (uri, value) != 0)
                        ((!)_pipeline).uri = value;
                }
            }
        }

        public bool pipewire_sink {
            get {
                unowned var name = _audio_sink?.get_type ()?.name () ?? "";
                return name == "GstPipeWireSink";
            }
            set {
                if (_pipeline != null) {
                    _audio_sink = Gst.ElementFactory.make (value ? "pipewiresink" : "pulsesink", "audiosink");
                    if (_audio_sink != null)
                        ((!)_audio_sink).enable_last_sample = true;
                    update_audio_sink ();
                    print (@"Enable Pipewire: $(value && _audio_sink != null)\n");
                }
            }
        }

        public bool replay_gain {
            get {
                return _replay_gain != null;
            }
            set {
                if (_pipeline != null) {
                    _replay_gain = value ? Gst.ElementFactory.make ("rgvolume", "gain") : null;
                    if (_replay_gain != null)
                        ((!)_replay_gain).album_mode = false;
                    update_audio_sink ();
                    print (@"Enable ReplayGain: $(value && _replay_gain != null)\n");
                }
            }
        }

        public bool show_peak {
            get {
                return _show_peak;
            }
            set {
                _show_peak = value;
                if (_timer != null) {
                    reset_timer ();
                }
                if (!value) {
                    Timeout.add (200, () => {
                        // to clear the showing
                        peak_parsed (0);
                        return false;
                    });
                }
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
                    on_duration_changed ();
                    break;

                case Gst.MessageType.STATE_CHANGED:
                    if (message.src == (!)_pipeline) {
                        Gst.State old = Gst.State.NULL;
                        Gst.State state = Gst.State.NULL;
                        Gst.State pending = Gst.State.NULL;
                        message.parse_state_changed (out old, out state, out pending);
                        if (old == Gst.State.READY && state == Gst.State.PAUSED) {
                            on_duration_changed ();
                        }
                        if (old != state && _state != state) {
                            _state = state;
                            if (state == Gst.State.PLAYING) {
                                reset_timer ();
                            } else {
                                _timer?.destroy ();
                                _timer = null;
                            }
                            state_changed (state);
                            timeout_callback ();
                            //  print ("State changed: %d -> %d\n", old, state);
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
                        next_uri_start ();
                    }
                    break;

                case Gst.MessageType.TAG:
                    if (!_tag_parsed) {
                        parse_tags (message);
                    }
                    break;

                default:
                    break;
            }
        }

        private void on_about_to_finish () {
            var next_uri = next_uri_request ();
            if ((next_uri?.length ?? 0) > 0) {
                AtomicInt.set (ref _next_uri_requested, 1);
                uri = (!)next_uri;
            }
        }

        private void on_duration_changed () {
            int64 duration = (int64) Gst.CLOCK_TIME_NONE;
            if ((_pipeline?.query_duration (Gst.Format.TIME, out duration) ?? false)
                    && _duration != duration) {
                _duration = duration;
                //  print ("Duration changed: %lld\n", duration);
                duration_changed (duration);
            }
        }

        private void parse_tags (Gst.Message message) {
            Gst.TagList tags;
            message.parse_tag (out tags);

            string? album = null, artist = null, title = null;
            var ret = tags.get_string (Gst.Tags.ALBUM, out album);
            ret |= tags.get_string (Gst.Tags.ARTIST, out artist);
            ret |= tags.get_string (Gst.Tags.TITLE, out title);

            Gst.Sample? image = parse_image_from_tag_list (tags);
            ret |= image != null;
            _tag_parsed = ret;

            var hash = str_hash (album ?? "") | str_hash (artist ?? "") | str_hash (title ?? "")
                        | (image?.get_buffer ()?.get_size () ?? 0);
            if (_tag_hash != hash) {
                _tag_hash = hash;
                // notify only when changed
                tag_parsed (album, artist, title, image);
            }
        }

        private void reset_timer () {
            _timer?.destroy ();
            _timer = new TimeoutSource (_show_peak ? 66 : 200);
            _timer?.set_callback (timeout_callback);
            _timer?.attach (MainContext.default ());
        }

        private bool timeout_callback () {
            int64 position = (int64) Gst.CLOCK_TIME_NONE;
            if ((_pipeline?.query_position (Gst.Format.TIME, out position) ?? false)
                    && _position != position) {
                _position = position;
                position_updated (position);
            }

            dynamic Gst.Element? sink = null;
            if (_show_peak && (sink = _audio_sink ?? _pipeline?.audio_sink) != null) {
                var peak = Peak ();
                dynamic Gst.Sample? sample = ((!)sink).last_sample;
                if (sample != null && parse_peak_in_sample ((!)sample, out peak.peak)) {
                    peak.time = ((!)sample).get_segment ().position;
                    _peaks.push_tail (peak);
                }
                while (_peaks.length > 0) {
                    unowned var p = _peaks.peek_head ();
                    if (p != null && ((!)p).time >= _position) {
                        _peaks.pop_head ();
                        peak_parsed (((!)p).peak);
                    } else {
                        break;
                    }
                }
            }
            return true;
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

        public delegate void LevelCalculateFunc (void* data, uint num, uint channels, out double NCS, out double NPS);

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
                        _audio_bps = 1;
                        _level_calculate = GstExt.gst_level_calculate_gint8;
                        break;
                    case "S16LE":
                        _audio_bps = 2;
                        _level_calculate = GstExt.gst_level_calculate_gint16;
                        break;
                    case "S32LE":
                        _audio_bps = 4;
                        _level_calculate = GstExt.gst_level_calculate_gint32;
                        break;
                    case "F32LE":
                        _audio_bps = 4;
                        _level_calculate = GstExt.gst_level_calculate_gfloat;
                        break;
                    case "F64LE":
                        _audio_bps = 8;
                        _level_calculate = GstExt.gst_level_calculate_gdouble;
                        break;
                    default:
                        print ("Unsupported sample format: %s\n", format);
                        return false;
                }
                _last_caps = caps;
            }

            var channels = _audio_channels;
            var bps = _audio_bps;
            var block_size = channels * bps;
            var buffer = sample.get_buffer ();
            var size = buffer?.get_size () ?? 0;

            Gst.MapInfo? map_info = null;
            if (buffer?.map (out map_info, Gst.MapFlags.READ) ?? false) {
                unowned uint8* p = ((!)map_info).data;
                var num = (uint) (size / block_size);
                double total_nps = 0;
                for (var i = 0; i < channels; i++) {
                    double ncs = 0, nps = 0;
                    _level_calculate (p + (bps * i), num, channels, out ncs, out nps);
                    total_nps += nps;
                }
                peak = total_nps / channels;
                buffer?.unmap ((!)map_info);
                return true;
            }
            return false;
        }
    }
}
