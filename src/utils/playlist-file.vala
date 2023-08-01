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

    public bool is_playlist_file (string mimetype) {
        return get_playlist_type (mimetype) != PlayListType.NONE;
    }

    public bool is_valid_uri (string uri, UriFlags flags = UriFlags.NONE) {
        try {
            return Uri.is_valid (uri, flags);
        } catch (Error e) {
        }
        return false;
    }

    public string? load_playlist_file (File file, GenericArray<string> uris) {
        try {
            var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
            var type = get_playlist_type (info.get_content_type () ?? "");
            switch (type) {
                case PlayListType.M3U:
                    return load_m3u_file (file, uris);
                case PlayListType.PLS:
                    return load_pls_file (file, uris);
            }
        } catch (Error e) {
        }
        return null;
    }

    public string load_m3u_file (File file, GenericArray<string> uris) throws Error {
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
        return get_file_display_name (file);
    }

    public string load_pls_file (File file, GenericArray<string> uris) throws Error {
        var name = get_file_display_name (file);
        var fis = file.read ();
        var bis = new BufferedInputStream (fis);
        var dis = new DataInputStream (bis);
        var parent = file.get_parent ();
        bool list_found = false;
        size_t length = 0;
        int pos = -1;
        string? str = null;
        while ((str = dis.read_line_utf8 (out length)) != null) {
            var line = ((!)str).strip ();
            if (line.length > 1 && line[0] == '[') {
                list_found = strcmp (line, "[playlist]") == 0;
            } else if (list_found && (pos = line.index_of_char ('=')) > 0) {
                if (line.has_prefix ("File")) {
                    var uri = line.substring (pos + 1).strip ();
                    uris.add (parse_relative_uri (uri, parent));
                } else if (line.ascii_ncasecmp ("X-GNOME-Title", pos) == 0) {
                    var title = line.substring (pos + 1).strip ();
                    if (title.length > 0)
                        name = title;
                }
            }
        }
        return name;
    }

    public string parse_relative_uri (string uri, File? parent = null) {
        if (uri.length > 0 && uri[0] == '/') {
            return File.new_for_path (uri).get_uri ();
        } else if (is_valid_uri (uri)) {
            return uri;
        }
        return parent?.resolve_relative_path (uri)?.get_uri () ?? uri;
    }
}