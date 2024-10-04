namespace G4 {

    public class Portal {
        private static string PORTAL_NAME = "org.freedesktop.portal.";
        private static string BUS_NAME = PORTAL_NAME + "Desktop";
        private static string OBJECT_PATH = "/org/freedesktop/portal/desktop";

        private DBusConnection? _bus = null;
        private string _parent;

        public Portal (string? parent = null) {
            _parent = parent ?? "";
        }

        public async bool open_directory_async (string uri) throws Error {
            var file = File.new_for_uri (uri);
            var options = make_options_builder ();
            var parameters = new Variant ("(sha{sv})", _parent, 0, options);
            var ret = yield call_with_file_async (file, Posix.O_CLOEXEC, PORTAL_NAME + "OpenURI", "OpenDirectory", parameters);
            return ret != null;
        }

        public async void request_background_async (string? reason) {
            try {
                var options = make_options_builder ();
                if (reason != null) {
                    options.add ("{sv}", "reason", new Variant.string ((!)reason));
                }
                options.add ("{sv}", "autostart", new Variant.boolean (false));
                options.add ("{sv}", "dbus-activatable", new Variant.boolean (false));
                var parameters = new Variant ("(sa{sv})", _parent, options);
                _bus = _bus ?? yield Bus.get (BusType.SESSION);
                yield ((!)_bus).call (BUS_NAME, OBJECT_PATH,
                                PORTAL_NAME + "Background", "RequestBackground", parameters,
                                null, DBusCallFlags.NONE, -1);
            } catch (Error e) {
                print ("Bus.call error: %s\n", e.message);
            }
        }

        public async bool trash_file_async (string uri) throws Error {
            var file = File.new_for_uri (uri);
            var parameters = new Variant ("(h)", 0);
            var ret = yield call_with_file_async (file, Posix.O_CLOEXEC | 010000000 /*O_PATH*/, PORTAL_NAME + "Trash", "TrashFile", parameters);
            uint val = 0;
            ret?.get ("(u)", out val);
            return val == 1;
        }

        private async Variant? call_with_file_async (File file, int flags, string interface_name, string method_name, Variant? parameters = null) throws Error {
            var fd = -1;
            try {
                var path = file.get_path () ?? file.get_parse_name ();
                fd = Posix.open (path, flags);
                if (fd == -1)
                    throw IOError.from_errno (Posix.errno);

                var fd_list = new GLib.UnixFDList ();
                fd_list.append (fd);
                _bus = _bus ?? yield Bus.get (BusType.SESSION);
                return yield ((!)_bus).call_with_unix_fd_list (BUS_NAME, OBJECT_PATH,
                                        interface_name, method_name, parameters,
                                        null, DBusCallFlags.NONE, -1, fd_list);
            } catch (Error e) {
                if (fd != -1) {
                    Posix.close (fd);
                }
                throw e;
            }
        }

        private VariantBuilder make_options_builder () {
            var token = "portal" + Random.next_int ().to_string ();
            var options = new VariantBuilder (VariantType.VARDICT);
            options.add ("{sv}", "handle_token", new Variant.string (token));
            return options;
        }
    }
}
