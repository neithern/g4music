namespace Music {

    public static Gst.TagList? parse_gst_tags (File file, string ctype) {
        FileInputStream? stream = null;
        try {
            stream = file.read ();
        } catch (Error e) {
            return null;
        }

        try {
            return parse_id3v2_tags ((!)stream);
        } catch (Error e) {
        }

        try {
            stream?.seek (0, SeekType.SET);
            return parse_demux_tags ((!)stream, ctype);
        } catch (Error e) {
        }
        return null;
    }

    public static Gst.TagList? parse_id3v2_tags (InputStream stream) throws Error {
        var header = new uint8[Gst.Tag.ID3V2_HEADER_SIZE];
        var n = stream.read (header);
        if (n != Gst.Tag.ID3V2_HEADER_SIZE) {
            throw new IOError.INVALID_DATA (@"read $(n) bytes");
        }

        var buffer = Gst.Buffer.new_wrapped_full (0, header, 0, header.length, null);
        var size = Gst.Tag.get_id3v2_tag_size (buffer);
        if (size == 0) {
            throw new IOError.INVALID_DATA ("invalid id3v2");
        }

        var data = new uint8[size];
        n = stream.read (data);
        if (n != size) {
            throw new IOError.INVALID_DATA (@"read $(n) bytes");
        }

        var buffer2 = Gst.Buffer.new_wrapped_full (0, data, 0, data.length, null);
        buffer = buffer.append (buffer2);
        return Gst.Tag.list_from_id3v2_tag (buffer);
    }

    public static Gst.TagList? parse_demux_tags (InputStream stream, string ctype) throws Error {
        var demux_name = get_demux_name (ctype);
        if (demux_name == null) {
            throw new ResourceError.NOT_FOUND (ctype);
        }

        var str = @"giostreamsrc name=src ! $((!)demux_name) ! fakesink";
        dynamic Gst.Pipeline? pipeline = Gst.parse_launch (str) as Gst.Pipeline;
        dynamic Gst.Element? src = pipeline?.get_by_name ("src");
        ((!)src).stream = stream;

        if (pipeline?.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
            throw new UriError.FAILED ("change state failed");
        }

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
