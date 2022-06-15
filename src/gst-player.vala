namespace Music {

    public class GstPlayer : Object {

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
        private Gst.ClockTime _duration = Gst.CLOCK_TIME_NONE;
        private Gst.ClockTime _position = Gst.CLOCK_TIME_NONE;
        private Gst.ClockTime _last_seeked_pos = Gst.CLOCK_TIME_NONE;
        private bool _show_peak = false;
        private Gst.State _state = Gst.State.NULL;
        private uint _tag_hash = 0;
        private bool _tag_parsed = false;
        private TimeoutSource? _timer = null;

        public signal void duration_changed (Gst.ClockTime duration);
        public signal void error (Error error);
        public signal void end_of_stream ();
        public signal void position_updated (Gst.ClockTime position);
        public signal void state_changed (Gst.State state);
        public signal void tag_parsed (string? album, string? artist, string? title, Bytes? image, string? itype);
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
            _pipeline?.set_state (Gst.State.NULL);
            _timer?.destroy ();
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
                _duration = Gst.CLOCK_TIME_NONE;
                _position = Gst.CLOCK_TIME_NONE;
                _state = Gst.State.NULL;
                _tag_hash = 0;
                _tag_parsed = false;
                _pipeline?.set_state (Gst.State.READY);
                if (_pipeline != null)
                    ((!)_pipeline).uri = value;
            }
        }

        public double volume { get; set; }

        public void play () {
            _pipeline?.set_state (Gst.State.PLAYING);
        }

        public void pause () {
            _pipeline?.set_state (Gst.State.PAUSED);
        }

        public void restart () {
            var saved_state = _state;
            if (saved_state != Gst.State.NULL) {
                _pipeline?.set_state (Gst.State.NULL);
                _pipeline?.set_state (saved_state);
            }
        }

        public void seek (Gst.ClockTime position) {
            var diff = (Gst.ClockTimeDiff) (position - _last_seeked_pos);
            if (diff > 10 * Gst.MSECOND || diff < -10 * Gst.MSECOND) {
                //  print ("Seek: %g -> %g\n", to_second (_last_seeked_pos), to_second (position));
                _last_seeked_pos = position;
                _pipeline?.seek_simple (Gst.Format.TIME, Gst.SeekFlags.ACCURATE | Gst.SeekFlags.FLUSH, (int64) position);
            }
        }

        public void show_peak (bool show) {
            _show_peak = show;
            if (_timer != null) {
                reset_timer ();
            }
            peak_parsed (-1);
        }

        public void use_pipewire (bool use) {
            if (_pipeline != null) {
                _audio_sink = Gst.ElementFactory.make (use ? "pipewiresink" : "pulsesink", "audiosink");
                ((!)_audio_sink).enable_last_sample = true;
                ((!)_pipeline).audio_sink = _audio_sink;
                print (@"Enable pipewire: $(use && _audio_sink != null)\n");
            }
        }

        private bool bus_callback (Gst.Bus bus, Gst.Message message) {
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
                        if (_state != state) {
                            _state = state;
                            //  print ("State changed: %d -> %d\n", old, state);
                            state_changed (_state);
                        }
                        if (state == Gst.State.PLAYING) {
                            reset_timer ();
                        } else {
                            _timer?.destroy ();
                            _timer = null;
                        }
                        timeout_callback ();
                    }
                    break;

                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    message.parse_error (out err, out debug);
                    _state = Gst.State.NULL;
                    print ("Player error: %s, %s\n", err.message, debug);
                    error (err);
                    break;

                case Gst.MessageType.EOS:
                    _pipeline?.set_state (Gst.State.READY);
                    end_of_stream ();
                    break;

                case Gst.MessageType.TAG:
                    if (!_tag_parsed) {
                        parse_tags (message);
                    }
                    break;

                default:
                    break;
            }
            return true;
        }

        private void reset_timer () {
            _timer?.destroy ();
            _timer = new TimeoutSource (_show_peak ? 66 : 200);
            _timer?.set_callback (timeout_callback);
            _timer?.attach (MainContext.default ());
        }

        private void parse_tags (Gst.Message message) {
            Gst.TagList tags;
            message.parse_tag (out tags);

            string? album = null, artist = null, title = null;
            var ret = tags.get_string ("album", out album);
            ret |= tags.get_string ("artist", out artist);
            ret |= tags.get_string ("title", out title);

            Bytes? image = null;
            string? itype = null;
            ret |= parse_image_from_tag_list (tags, out image, out itype);
            _tag_parsed = ret;

            var hash = str_hash (album ?? "") | str_hash (artist ?? "") | str_hash (title ?? "")
                        | (image?.length ?? 0) | str_hash (itype ?? "");
            if (_tag_hash != hash) {
                _tag_hash = hash;
                // notify only when changed
                tag_parsed (album, artist, title, image, itype);
            }
        }

        private bool timeout_callback () {
            int64 position = (int64) Gst.CLOCK_TIME_NONE;
            if ((_pipeline?.query_position (Gst.Format.TIME, out position) ?? false)
                    && _position != position) {
                _position = position;
                _last_seeked_pos = position;
                position_updated (position);
            }

            if (_show_peak) {
                dynamic var sink = _audio_sink ?? _pipeline?.audio_sink;
                if (sink != null) {
                    double peak = 0;
                    dynamic Gst.Sample? sample = ((!)sink).last_sample;
                    if (sample != null && parse_peak_in_sample ((!)sample, out peak)) {
                        peak_parsed (peak);
                    }
                }
            }
            return true;
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

        public delegate void LevelCalculateFunc (void* data, uint num, uint channels, out double NCS, out double NPS);

        private static bool parse_peak_in_sample (Gst.Sample sample, out double peak) {
            peak = 0;

            unowned var caps = sample.get_caps ();
            unowned var st = caps?.get_structure (0);

            int channels = 0;
            st?.get_int ("channels", out channels);
            if (channels == 0)
                return false;

            unowned var format = st?.get_string ("format");
            //  print ("Sample format: %s\n", format ?? "");
            if (format == null)
                return false;

            uint bps = 1;
            LevelCalculateFunc process;
            switch ((!)format) {
                case "S8":
                    bps = 1;
                    process = GstExt.gst_level_calculate_gint8;
                    break;
                case "S16LE":
                    bps = 2;
                    process = GstExt.gst_level_calculate_gint16;
                    break;
                case "S32LE":
                    bps = 4;
                    process = GstExt.gst_level_calculate_gint32;
                    break;
                case "F32LE":
                    bps = 4;
                    process = GstExt.gst_level_calculate_gfloat;
                    break;
                case "F64LE":
                    bps = 8;
                    process = GstExt.gst_level_calculate_gdouble;
                    break;
                default:
                    return false;
            }

            var block_size = channels * bps;
            var buffer = sample.get_buffer ();
            var size = buffer?.get_size () ?? 0;

            Gst.MapInfo? map_info = null;
            var ret = buffer?.map (out map_info, Gst.MapFlags.READ) ?? false;
            if (!ret)
                return false;

            unowned uint8* p = ((!)map_info).data;
            var num = (uint) (size / block_size);
            double total_nps = 0;
            for (var i = 0; i < channels; i++) {
                double ncs = 0, nps = 0;
                process (p + (bps * i), num, channels, out ncs, out nps);
                total_nps += nps;
            }
            peak = total_nps / channels;

            buffer?.unmap ((!)map_info);
            return true;
        }
    }
}
