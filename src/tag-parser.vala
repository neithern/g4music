namespace Music {

    public static Gst.TagList? parse_gst_tags (File file) {
        FileInputStream? fis = null;
        try {
            fis = file.read ();
        } catch (Error e) {
            return null;
        }

        var stream = new BufferedInputStream ((!)fis);
        size_t n = 0;
        try {
            var head = new uint8[16];
            if (! stream.read_all (head, out n)) {
                throw new IOError.INVALID_DATA (@"read $(n) bytes");
            }

            //  Try parse start tag: ID3v2 or APE
            if (Memory.cmp (head, "ID3", 3) == 0) {
                var buffer = Gst.Buffer.new_wrapped_full (0, head, 0, head.length, null);
                var size = Gst.Tag.get_id3v2_tag_size (buffer);
                if (size > head.length) {
                    var data = new_uint8_array (size);
                    Memory.copy (data, head, head.length);
                    if (stream.read_all (data[head.length:], out n)) {
                        var buffer2 = Gst.Buffer.new_wrapped_full (0, data, 0, data.length, null);
                        return Gst.Tag.List.from_id3v2_tag (buffer2);
                    }
                }
            } else if (Memory.cmp (head, "APETAGEX", 8) == 0 && stream.seek (0, SeekType.SET)) {
                var size = read_uint32_le (head, 12) + 32;
                var data = new_uint8_array (size);
                Memory.copy (data, head, head.length);
                if (stream.read_all (data[head.length:], out n)) {
                    return TagDemux.ape_demux_parse_tags (data);
                }
            }
        } catch (Error e) {
            print ("Parse start tag %s: %s\n", file.get_parse_name (), e.message);
        }

        Gst.TagList? tags = null;
        try {
            //  Try parse end tag: ID3v1 or APE
            if (! stream.seek (-128, SeekType.END))  {
                throw new IOError.INVALID_DATA (@"seek -32");
            }
            var foot = new uint8[128];
            if (! stream.read_all (foot, out n)) {
                throw new IOError.INVALID_DATA (@"read $(n) bytes");
            }

            if (Memory.cmp (foot, "TAG", 3) == 0) {
                tags = Gst.Tag.List.new_from_id3v1 (foot);
                //  Try check if there is APE at front of ID3v1
                if (stream.seek (- (int) (128 + 32), SeekType.END)) {
                    var head = new uint8[32];
                    if (stream.read_all (head, out n) && Memory.cmp (head, "APETAGEX", 8) == 0) {
                        uint32 size = read_uint32_le (head, 12) + 32;
                        if (stream.seek (- (int) (size), SeekType.CUR)) {
                            var data = new_uint8_array (size);
                            if (stream.read_all (data, out n)) {
                                tags = TagDemux.ape_demux_parse_tags (data);
                            }
                        }
                    }
                }
            } else if (Memory.cmp (foot[128-32:], "APETAGEX", 8) == 0) {
                var size = read_uint32_le (foot, foot.length - 32 + 12) + 32;
                if (stream.seek (- (int) (size), SeekType.END)) {
                    var data = new_uint8_array (size);
                    if (stream.read_all (data, out n)) {
                        tags = TagDemux.ape_demux_parse_tags (data);
                    }
                }
            }
        } catch (Error e) {
            print ("Parse end tag %s: %s\n", file.get_parse_name (), e.message);
        }
        if (tags != null) {
            return tags;
        }

        try {
            if (stream.seek (0, SeekType.SET)) {
                var uri = file.get_uri ();
                var pos = uri.last_index_of_char ('.');
                return parse_demux_tags (stream, uri.substring (pos + 1));
            }
        } catch (Error e) {
            //  print ("Parse demux %s: %s\n", file.get_parse_name (), e.message);
        }
        return null;
    }

    public static uint8[] new_uint8_array (uint size) throws Error {
        if ((int) size <= 0 || size > int32.MAX)
            throw new IOError.INVALID_ARGUMENT ("invalid size");
        return new uint8[size];
    }

    public static uint32 read_uint32_le (uint8[] data, int pos = 0) {
        return data[pos]
            | ((uint32) (data[pos+1]) << 8)
            | ((uint32) (data[pos+2]) << 16)
            | ((uint32) (data[pos+3]) << 24);
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
    private static string? get_demux_name (string ext_name) {
        var ext = ext_name.down ();
        if ("aiff" == ext)
            return "aiffparse";
        else if ("flac" == ext)
            return "flacparse";
        else if ("mp4" == ext || "m4a" == ext || "m4b" == ext)
            return "qtdemux";
        else if ("ogg" == ext || "oga" == ext)
            return "oggdemux";
        else if ("opus" == ext)
            return "opusparse";
        else if ("vobis" == ext)
            return "flacparse";
        else if ("wma" == ext)
            return "asfparse";
        else if ("wav" == ext)
            return "wavparse";
        return "id3demux";
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
