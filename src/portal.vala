namespace Music {

    public class Portal {
        private DBusConnection? _bus = null;

        public async void open_directory_async (string uri) {
            _bus = _bus ?? yield get_connection_async ();
            if (_bus != null) try {
                var file = File.new_for_uri (uri);
                var fd = GLib.open ((!)file.get_path (), 02 | 02000000); // O_RDWR | O_CLOEXEC
                var fd_list = new GLib.UnixFDList ();
                fd_list.append (fd);
                var param = new Variant ("(sha{sv})", "", 0);
                yield ((!)_bus).call_with_unix_fd_list (
                            "org.freedesktop.portal.Desktop",
                            "/org/freedesktop/portal/desktop",
                            "org.freedesktop.portal.OpenURI",
                            "OpenDirectory",
                            param,
                            null,
                            DBusCallFlags.NONE,
                            -1,
                            fd_list);
            } catch (Error e) {
                print ("Bus.call error: %s\n", e.message);
            }
        }

        private static async DBusConnection? get_connection_async () {
            try {
                return yield Bus.get (BusType.SESSION);
            } catch (Error e) {
                print ("Bus.get error: %s\n", e.message);
            }
            return null;
        }
    }
}