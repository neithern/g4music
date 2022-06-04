namespace Music {

    public static void parse_tags (string path, Song song) {
        string? album = null, artist = null, title = null;
#if HAS_TAGLIB_C
        var file = new TagLib.File (path);
        if (file.is_valid ()) {
            unowned var tag = file.tag;
            album = tag.album;
            artist = tag.artist;
            title = tag.title;
        }
#else
        var tags = parse_gst_tags (path, song.type);
        if (tags != null) {
            tags?.get_string ("album", out album);
            tags?.get_string ("artist", out artist);
            tags?.get_string ("title", out title);
        }
#endif
        song.album = album ?? UNKOWN_ALBUM;
        song.artist = artist ?? UNKOWN_ARTIST;
        song.title = title ?? song.title;
    }

    public static Gst.TagList? parse_gst_tags (string path, string ctype) {
        var tags = parse_id3v2_tags (path);
        if (tags == null)
            tags = parse_demux_tags (path, ctype);
        return tags;
    }

    public static Gst.TagList? parse_id3v2_tags (string path) {
        try {
            var file = File.new_for_path (path);
            var stream = file.read ();
            var header = new uint8[Gst.Tag.ID3V2_HEADER_SIZE];
            var n = stream.read (header);
            if (n != Gst.Tag.ID3V2_HEADER_SIZE)
                return null;

            var buffer = Gst.Buffer.new_wrapped_full (0, header, 0, header.length, null);
            var size = Gst.Tag.get_id3v2_tag_size (buffer);
            if (size == 0)
                return null;

            var data = new uint8[size];
            n = stream.read (data);
            if (n != size)
                return null;

            var buffer2 = Gst.Buffer.new_wrapped_full (0, data, 0, data.length, null);
            buffer = buffer.append (buffer2);
            return Gst.Tag.list_from_id3v2_tag (buffer);
        } catch (Error e) {
            //  print ("id3v2 error %s: %s\n", uri, e.message);
        }
        return null;
    }

    public static Gst.TagList? parse_demux_tags (string path, string mtype) {
        var demux_name = get_demux_name (mtype);
        if (demux_name == null)
            return null;

        var str = @"filesrc name=src ! $((!)demux_name) ! fakesink";
        dynamic Gst.Pipeline? pipeline = null;
        try {
            pipeline = Gst.parse_launch (str) as Gst.Pipeline;
            dynamic Gst.Element? src = pipeline?.get_by_name ("src");
            ((!)src).location = path;
        } catch (Error e) {
            print ("Parse error: %s, %s\n", path, e.message);
            return null;
        }
        if (pipeline?.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE)
            return null;

        var bus = pipeline?.get_bus ();
        bool quit = false;
        Gst.TagList? tags = null;
        do {
            var message = bus?.timed_pop (Gst.SECOND * 5);
            if (message == null)
                break;
            var msg = (!)message;
            switch (msg.type) {
                case Gst.MessageType.TAG:
                    msg.parse_tag (out tags);
                    break;

                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    ((!)msg).parse_error (out err, out debug);
                    print ("Parse error: %s, %s\n", err.message, debug);
                    quit = true;
                    break;

                case Gst.MessageType.EOS:
                    quit = true;
                    break;

                default:
                    break;
            }
        } while (!quit);
        pipeline?.set_state (Gst.State.NULL);
        return tags;
    }

    // TODO: use typefind
    private static string? get_demux_name (string content_type) {
        switch (content_type) {
            case "audio/mp4":
            case "audio/x-m4a":
            case "audio/x-m4b":
                return "qtdemux";

            case "audio/x-aiff":
                return "aiffparse";

            case "audio/x-ape":
                return "apetag";

            case "audio/x-flac":
                return "flacparse";

            case "audio/x-vorbis":
            case "audio/x-vorbis+ogg":
                return "vorbisparse";

            default:
                return "id3demux";
        }
    }

    public static bool parse_image_from_tag_list (Gst.TagList tags, out Bytes? image, out string? itype) {
        image = null;
        itype = null;
        Gst.Sample? sample = null;
        if (!tags.get_sample ("image", out sample)) {
            for (var i = 0; i < tags.n_tags (); i++) {
                var tag = tags.nth_tag_name (i);
                var value = tags.get_value_index (tag, 0);
                if (value?.type () == typeof (Gst.Sample)
                        && tags.get_sample (tag, out sample)) {
                    var caps = sample?.get_caps ();
                    if (caps != null) {
                        break;
                    }
                    //  print (@"unknown image tag: $(tag)\n");
                }
                sample = null;
            }
        }
        if (sample != null) {
            uint8[]? data = null;
            var buffer = sample?.get_buffer ();
            buffer?.extract_dup (0, buffer?.get_size () ?? 0, out data);
            if (data != null) {
                image = new Bytes.take (data);
                itype = sample?.get_caps ()?.get_structure (0)?.get_name ();
            }
        }
        return image != null;
    }
}
