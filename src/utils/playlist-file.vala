namespace G4 {

    namespace PlayListType {
        public const uint NONE = 0;
        public const uint M3U = 1;
        public const uint PLS = 2;
    }

    public uint get_playlist_type (string mimetype) {
        switch (mimetype) {
            case "audio/x-mpegurl":
                return PlayListType.M3U;
            case "audio/x-scpls":
                return PlayListType.PLS;
            default:
                return PlayListType.NONE;
        }
    }

    public void load_playlist_file (File file, uint type, GenericArray<string> uris) throws Error {
        switch (type) {
            case PlayListType.M3U:
                load_m3u_file (file, uris);
                break;

            case PlayListType.PLS:
                load_pls_file (file, uris);
                break;

            default:
                break;
        }
    }

    public void load_m3u_file (File file, GenericArray<string> uris) throws Error {
        var fis = file.read ();
        var bis = new BufferedInputStream (fis);
        var dis = new DataInputStream (bis);
        var parent = file.get_parent ();
        size_t length = 0;
        string? str = null;
        while ((str = dis.read_line_utf8 (out length)) != null) {
            var uri = (!)str;
            if (length > 0 && uri[0] != '#') {
                uris.add (parse_relative_uri (uri, parent));
            }
        }
    }

    public void load_pls_file (File file, GenericArray<string> uris) throws Error {
        Bytes? bytes = null;
        if (file.is_native ()) {
            var mapped = new MappedFile (file.get_path () ?? "", false);
            bytes = mapped.get_bytes ();
        } else {
            var fis = file.read (null);
            bytes = fis.read_bytes (ssize_t.MAX);
        }

        var kfile = new KeyFile ();
        if (bytes != null && kfile.load_from_bytes ((!)bytes, KeyFileFlags.NONE)) {
            var parent = file.get_parent ();
            var count = kfile.get_integer ("playlist", "NumberOfEntries");
            for (var i = 1; i <= count; i++) {
                var uri = kfile.get_string ("playlist", @"File$i");
                uris.add (parse_relative_uri (uri, parent));
            }
        }
    }

    public string parse_relative_uri (string uri, File? parent = null) {
        if (uri.contains ("://"))
            return uri;
        else if (uri.length > 0 && uri[0] == '/')
            return File.new_for_path (uri).get_uri ();
        return parent?.resolve_relative_path (uri)?.get_uri () ?? uri;
    }
}