namespace Music {

    public delegate V TaskFunc<V> ();

    private class Worker<V> {
        private TaskFunc<V> _task;
        private SourceFunc? _callback;
        private V? _result = null;

        public Worker (TaskFunc<V> task, SourceFunc? callback = null) {
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
            if (_callback != null) {
                Idle.add ((owned) _callback);
                _callback = null;
            }
        }

        private static Once<ThreadPool<Worker>> multi_thread_pool;
        internal static unowned ThreadPool<Worker> get_multi_thread_pool () {
            return multi_thread_pool.once(() => {
                return new_thread_pool (get_num_processors ());
            });
        }

        private static Once<ThreadPool<Worker>> single_thread_pool;
        internal static unowned ThreadPool<Worker> get_single_thread_pool () {
            return single_thread_pool.once(() => {
                return new_thread_pool (1);
            });
        }

        private static ThreadPool<Worker> new_thread_pool (uint num_threads) {
            try {
                return new ThreadPool<Worker>.with_owned_data ((tdata) => {
                    tdata.run();
                }, (int) num_threads, false);
            } catch (Error e) {
                critical ("Create %u threads pool failed: %s\n", num_threads, e.message);
                Process.abort ();
            }
        }
    }

    public static async V run_async<V> (TaskFunc<V> task, bool front = false, bool in_single_pool = false) {
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

    public static void run_async_no_wait (TaskFunc<void> task, bool front = false, bool in_single_pool = false) {
        var worker = new Worker<void> (task);
        try {
            unowned var pool = in_single_pool ? Worker.get_single_thread_pool () : Worker.get_multi_thread_pool ();
            pool.add (worker);
            if (front) {
                pool.move_to_front (worker);
            }
        } catch (Error e) {
        }
    }
}
