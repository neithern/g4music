namespace G4 {

    public class Event {
        private Cond _cond = Cond ();
        private Mutex _mutex = Mutex ();
        private bool _notified = false;

        public void notify () {
            _mutex.lock ();
            _notified = true;
            _cond.broadcast ();
            _mutex.unlock ();
        }

        public void reset () {
            _mutex.lock ();
            _notified = false;
            _mutex.unlock ();
        }

        public void wait () {
            _mutex.lock ();
            while (!_notified)
                _cond.wait (_mutex);
            _mutex.unlock ();
        }
    }

    public delegate V TaskFunc<V> ();
    public delegate void VoidFunc ();

    private class Worker<V> {
        private TaskFunc<V> _task;
        private SourceFunc _callback;
        private V? _result = null;

        public Worker (TaskFunc<V> task, SourceFunc callback) {
            _task = task;
            _callback = callback;
        }

        public V? result {
            get {
                return _result;
            }
        }

        private void run () {
            _result = _task ();
            Idle.add ((owned) _callback);
        }

        private static Once<ThreadPool<Worker>> multi_thread_pool;
        internal static unowned ThreadPool<Worker> get_multi_thread_pool () {
            return multi_thread_pool.once(() => new_thread_pool (get_num_processors ()));
        }

        private static Once<ThreadPool<Worker>> single_thread_pool;
        internal static unowned ThreadPool<Worker> get_single_thread_pool () {
            return single_thread_pool.once(() => new_thread_pool (1));
        }

        private static ThreadPool<Worker> new_thread_pool (uint num_threads) {
            try {
                return new ThreadPool<Worker>.with_owned_data ((tdata) => tdata.run(), (int) num_threads, false);
            } catch (Error e) {
                critical ("Create %u threads pool failed: %s\n", num_threads, e.message);
                Process.abort ();
            }
        }
    }

    public async V run_async<V> (TaskFunc<V> task, bool front = false, bool in_single_pool = false) {
        var worker = new Worker<V> (task, run_async<V>.callback);
        try {
            unowned var pool = in_single_pool ? Worker.get_single_thread_pool () : Worker.get_multi_thread_pool ();
            pool.add (worker);
            if (front) {
                pool.move_to_front (worker);
            }
            yield;
        } catch (Error e) {
        }
        return worker.result;
    }

    public uint run_idle_once (owned VoidFunc func) {
        return Idle.add (() => {
            func ();
            return false;
        });
    }

    public uint run_timeout_once (uint interval, owned VoidFunc func) {
        return Timeout.add (interval, () => {
            func ();
            return false;
        });
    }

    public async void run_void_async (VoidFunc task) {
        yield run_async<void> (task);
    }
}
