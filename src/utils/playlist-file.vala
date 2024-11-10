namespace G4 {

    namespace PlayListType {
        public const uint NONE = 0;
        public const uint M3U = 1;
        public const uint PLS = 2;
    }

    public uint get_playlist_type (string mimetype) {
        switch (mimetype) {
            case "audio/x-mpegurl":
            case "public.m3u-playlist":
                return PlayListType.M3U;
            case "audio/x-scpls":
            case "public.pls-playlist":
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
        string? title = null;
        try {
            var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
            var type = get_playlist_type (info.get_content_type () ?? "");
            var fis = file.read ();
            var bis = new BufferedInputStream (fis);
            var dis = new DataInputStream (bis);
            var parent = file.get_parent ();
            switch (type) {
                case PlayListType.M3U:
                    title = load_m3u_file (dis, parent, uris);
                    break;
                case PlayListType.PLS:
                    title = load_pls_file (dis, parent, uris);
                    break;
            }
            return title ?? get_file_display_name (file);
        } catch (Error e) {
        }
        return null;
    }

    public string? load_m3u_file (DataInputStream dis, File? parent, GenericArray<string> uris) throws Error {
        size_t length = 0;
        string? str = null, title = null;
        while ((str = dis.read_line_utf8 (out length)) != null) {
            var line = (!)str;
            if (line.has_prefix ("#PLAYLIST:")) {
                var text = line.substring (10).strip ();
                if (text.length > 0)
                    title = text;
            } else if (length > 0 && line[0] != '#') {
                var abs_uri = parse_relative_uri (line.strip (), parent);
                if (abs_uri != null)
                    uris.add ((!)abs_uri);
            }
        }
        return title;
    }

    public string? load_pls_file (DataInputStream dis, File? parent, GenericArray<string> uris) throws Error {
        bool list_found = false;
        size_t length = 0;
        string? str = null, title = null;
        while ((str = dis.read_line_utf8 (out length)) != null) {
            int pos = -1;
            var line = ((!)str).strip ();
            if (line.length > 1 && line[0] == '[') {
                list_found = line == "[playlist]";
            } else if (list_found && (pos = line.index_of_char ('=')) > 0) {
                if (line.has_prefix ("File")) {
                    var uri = line.substring (pos + 1).strip ();
                    var abs_uri = parse_relative_uri (uri, parent);
                    if (abs_uri != null)
                        uris.add ((!)abs_uri);
                } else if (line.ascii_ncasecmp ("X-GNOME-Title", pos) == 0) {
                    var text = line.substring (pos + 1).strip ();
                    if (text.length > 0)
                        title = text;
                }
            }
        }
        return title;
    }

    public string get_relative_path (File? parent, File file) {
        var path = parent?.get_relative_path (file);
        if (path != null)
            return (!)path;

        path = file.get_path ();
        if (path == null)
            return "";
        var file_path = (!)path;

        path = parent?.get_path ();
        if (path == null)
            return file_path;
        var parent_path = (!)path;

        var pos = 0;
        do {
            var ret = file_path.index_of_char ('/', pos + 1);
            if (ret > pos && file_path.ascii_ncasecmp (parent_path, ret) == 0)
                pos = ret;
            else
                break;
        } while (pos > 0);
        if (pos > 1) { // Skip the first '/'
            var len = parent_path.length;
            var sb = new StringBuilder ();
            for (var p = pos; p > 0 && p < len; p = parent_path.index_of_char ('/', p + 1))
                sb.append ("../");
            file_path = sb.str + file_path.substring (pos + 1);
        }
        return file_path;
    }

    public string? parse_relative_uri (string uri, File? parent = null) {
        if (uri.length > 0 && uri[0] == '/') {
            return File.new_for_path (uri).get_uri ();
        } else if (is_valid_uri (uri)) {
            //  Native files only
            return uri.has_prefix ("file://") ? (string?) uri : null;
        }
        return parent?.resolve_relative_path (uri)?.get_uri ();
    }

    public bool save_m3u8_file (DataOutputStream dos, File? parent, GenericArray<string> uris, string? title, bool with_titles) throws Error {
        if (!dos.put_string ("#EXTM3U\n"))
            return false;
        if (title != null && with_titles && !dos.put_string (@"#PLAYLIST:$((!)title)\n"))
            return false;
        foreach (var uri in uris) {
            var f = File.new_for_uri (uri);
            var path = get_relative_path (parent, f);
            if (with_titles) {
                var name = get_file_display_name (f);
                if (!dos.put_string (@"#EXTINF:,$name\n"))
                    return false;
            }
            if (!dos.put_string (@"$path\n"))
                return false;
        }
        return true;
    }

    public bool save_pls_file (DataOutputStream dos, File? parent, GenericArray<string> uris, string? title, bool with_titles) throws Error {
        if (!dos.put_string ("[playlist]\n"))
            return false;
        if (title != null && with_titles && !dos.put_string (@"X-GNOME-Title=$((!)title)\n"))
            return false;
        var count = uris.length;
        if (!dos.put_string (@"NumberOfEntries=$count\n"))
            return false;
        for (var i = 0; i < count; i++) {
            var f = File.new_for_uri (uris[i]);
            var path = get_relative_path (parent, f);
            var n = i + 1;
            if (with_titles) {
                var name = get_file_display_name (f);
                if (!dos.put_string (@"Title$n=$name\n"))
                    return false;
            }
            if (!dos.put_string (@"File$n=$path\n"))
                return false;
        }
        return true;
    }

    public bool save_playlist_file (File file, GenericArray<string> uris, string? title = null, bool with_titles = true) {
        var bname = file.get_basename () ?? "";
        var pos = bname.last_index_of_char ('.');
        var name = bname.substring (0, pos);
        var ext = bname.substring (pos + 1);
        try {
            var fos = file.replace (null, false, FileCreateFlags.NONE);
            var bos = new BufferedOutputStream (fos);
            var dos = new DataOutputStream (bos);
            var parent = file.get_parent ();
            if (ext.ascii_ncasecmp ("pls", 3) == 0) {
                return save_pls_file (dos, parent, uris, title ?? name, with_titles);
            } else {
                return save_m3u8_file (dos, parent, uris, title ?? name, with_titles);
            }
        } catch (Error e) {
            print ("Save playlist %s: %s\n", file.get_parse_name (), e.message);
        }
        return false;
    }
}