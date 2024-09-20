namespace G4 {

    public class DirMonitor : Object {
        private HashTable<string, FileMonitor> _monitors = new HashTable<string, FileMonitor> (str_hash, str_equal);

        public signal void add_file (File file);
        public signal void remove_file (File file);

        ~DirMonitor () {
            remove_all ();
        }

        public bool enabled { get; set; }

        public void monitor (GenericArray<File> dirs) {
            foreach (var dir in dirs) {
                if (dir.is_native ())
                    monitor_one (dir);
            }
        }

        public void monitor_one (File dir) {
            var uri = dir.get_uri ();
            unowned string orig_key;
            FileMonitor monitor;
            if (_monitors.lookup_extended (uri, out orig_key, out monitor)) {
                monitor.cancel ();
            }
            if (_enabled) try {
                monitor = dir.monitor (FileMonitorFlags.WATCH_MOVES, null);
                monitor.changed.connect (monitor_func);
                _monitors[uri] = monitor;
            } catch (Error e) {
                print ("Monitor dir error: %s\n", e.message);
            }
        }

        public void remove_all () {
            _monitors.foreach ((uri, monitor) => monitor.cancel ());
            _monitors.remove_all ();
        }

        private void monitor_func (File file, File? other_file, FileMonitorEvent event) {
            switch (event) {
                case FileMonitorEvent.CHANGED:
                    remove_file (file);
                    add_file (file);
                    break;

                case FileMonitorEvent.MOVED_IN:
                    add_file (file);
                    break;

                case FileMonitorEvent.DELETED:
                case FileMonitorEvent.MOVED_OUT:
                    remove_file (file);
                    break;

                case FileMonitorEvent.RENAMED:
                    remove_file (file);
                    if (other_file != null)
                        add_file ((!)other_file);
                    break;

                default:
                    break;
            }
        }
    }
}