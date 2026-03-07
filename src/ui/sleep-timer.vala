namespace G4 {

    public class SleepTimer : Object {
        private Application _app;
        private uint _timer_handle = 0;
        private int _seconds_remaining = 0;
        private bool _finish_track = false;

        public signal void state_changed (bool active);
        public signal void tick (int seconds_remaining);

        public SleepTimer (Application app) {
            _app = app;
        }

        public bool active {
            get { return _timer_handle != 0; }
        }

        public bool finish_track {
            get { return _finish_track; }
            set { _finish_track = value; }
        }

        public void start (int seconds) {
            stop ();
            _seconds_remaining = seconds;
            _timer_handle = Timeout.add (1000, on_tick);
            state_changed (true);
        }

        public void add_seconds (int seconds) {
            _seconds_remaining += seconds;
            tick (_seconds_remaining);
        }

        public void stop () {
            if (_timer_handle != 0) {
                Source.remove (_timer_handle);
                _timer_handle = 0;
            }
            _seconds_remaining = 0;
            state_changed (false);
        }

        public int seconds_remaining {
            get { return _seconds_remaining; }
        }

        private bool on_tick () {
            _seconds_remaining--;
            tick (_seconds_remaining);
            if (_seconds_remaining <= 0) {
                _timer_handle = 0;
                if (_finish_track) {
                     SignalHandler.disconnect_by_func (_app.player,
    (void*) on_end_of_stream_for_sleep, this);
_app.player.end_of_stream.connect (on_end_of_stream_for_sleep);
} else {
                    _app.player.state = Gst.State.PAUSED;
                    state_changed (false);
                }
                return false;
            }
            return true;
        }
        private void on_end_of_stream_for_sleep () {
            _app.player.state = Gst.State.PAUSED;
            SignalHandler.disconnect_by_func (_app.player,
                (void*) on_end_of_stream_for_sleep, this);
            state_changed (false);
        }
    }
}
