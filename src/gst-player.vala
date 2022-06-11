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
        private Gst.ClockTime _duration = Gst.CLOCK_TIME_NONE;
        private Gst.ClockTime _position = Gst.CLOCK_TIME_NONE;
        private Gst.ClockTime _last_seeked_pos = Gst.CLOCK_TIME_NONE;
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
            if (show && _pipeline != null) {
                dynamic var level = Gst.ElementFactory.make ("level", "filter");
                if (level != null) {
                    ((!)level).interval = Gst.MSECOND * 66; // 15fps
                    ((!)level).post_messages = true;
                }
                ((!)_pipeline).audio_filter = level;
            } else if (!show && _pipeline != null) {
                ((!)_pipeline).audio_filter = null;
            }
        }

        public void use_pipewire (bool use) {
            if (use && _pipeline != null) {
                var sink = Gst.ElementFactory.make ("pipewiresink", "audiosink");
                if (sink != null) {
                    ((!)_pipeline).audio_sink = sink;
                    print ("Enable pipewire\n");
                }
            } else if (!use && _pipeline != null) {
                ((!)_pipeline).audio_sink = null;
            }
        }

        private bool bus_callback (Gst.Bus bus, Gst.Message message) {
            switch (message.type) {
                case Gst.MessageType.DURATION_CHANGED:
                    on_duration_changed ();
                    break;

                case Gst.MessageType.STATE_CHANGED:
                    Gst.State old = Gst.State.NULL;
                    Gst.State state = Gst.State.NULL;
                    Gst.State pending = Gst.State.NULL;
                    message.parse_state_changed (out old, out state, out pending);
                    if (old == Gst.State.READY && state == Gst.State.PAUSED) {
                        on_duration_changed ();
                    }
                    if (_state != state) {
                        _state = state;
                        //  print ("State changed: %d, %d\n", old, state);
                        state_changed (_state);
                    }
                    if (state == Gst.State.PLAYING) {
                        if (_timer == null) {
                            _timer = new TimeoutSource (200);
                            _timer?.set_callback (timeout_callback);
                            _timer?.attach (MainContext.default ());
                        }
                    } else {
                        _timer?.destroy ();
                        _timer = null;
                    }
                    timeout_callback ();
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

                case Gst.MessageType.ELEMENT:
                    if (message.has_name ("level")) {
                        parse_peak (message);
                    }
                    break;

                default:
                    break;
            }
            return true;
        }

        private void parse_peak (dynamic Gst.Message message) {
            unowned var structure = message.get_structure ();
            var value = structure?.get_value ("peak");
            unowned ValueArray? arr = (ValueArray*) value?.get_boxed ();
            if (arr != null) {
                double total = 0;
                var count = ((!)arr).n_values;
                for (var i = 0; i < count; i++) {
                    var v = ((!)arr).get_nth (0);
                    if (v != null)
                        total += Math.pow (10, ((!)v).get_double () / 20);
                }
                if (count > 0)
                    peak_parsed (total / count);
            }
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
    }
}
