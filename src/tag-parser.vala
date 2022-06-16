namespace Music {

    public static Gst.TagList? parse_gst_tags (File file) {
        FileInputStream? fis = null;
        try {
            fis = file.read ();
        } catch (Error e) {
            return null;
        }

        Gst.TagList? tags = null;
        var stream = new BufferedInputStream ((!)fis);
        var head = new uint8[16];

        //  Parse and merge all the leading tags as possible
        while (true) {
            try {
                if (! read_full (stream, head)) {
                    break;
                }
                //  Try parse start tag: ID3v2 or APE
                if (Memory.cmp (head, "ID3", 3) == 0) {
                    var buffer = Gst.Buffer.new_wrapped_full (0, head, 0, head.length, null);
                    var size = Gst.Tag.get_id3v2_tag_size (buffer);
                    if (size > head.length) {
                        var data = new_uint8_array (size);
                        Memory.copy (data, head, head.length);
                        if (read_full (stream, data[head.length:])) {
                            var buffer2 = Gst.Buffer.new_wrapped_full (0, data, 0, data.length, null);
                            var tags2 = Gst.Tag.List.from_id3v2_tag (buffer2);
                            tags = merge_tags (tags, tags2);
                        }
                    }
                } else if (Memory.cmp (head, "APETAGEX", 8) == 0 && stream.seek (0, SeekType.SET)) {
                    var size = read_uint32_le (head, 12) + 32;
                    var data = new_uint8_array (size);
                    Memory.copy (data, head, head.length);
                    if (read_full (stream, data[head.length:])) {
                        var tags2 = GstExt.ape_demux_parse_tags (data);
                        tags = merge_tags (tags, tags2);
                    }
                } else {
                    //  Parse by file container format
                    if (stream.seek (-head.length, SeekType.CUR)) {
                        if (Memory.cmp (head, "fLaC", 4) == 0) {
                            var tags2 = parse_flac_tags (stream);
                            tags = merge_tags (tags, tags2);
                        }
                    }
                    // No ID3v2/APE any more, quit the loop
                    break;
                }
            } catch (Error e) {
                print ("Parse begin tag %s: %s\n", file.get_parse_name (), e.message);
                break;
            }
        }

        //  Parse and merge all the ending tags as possible
        try {
            var tags2 = parse_end_tags (stream);
            tags = merge_tags (tags, tags2);
        } catch (Error e) {
            print ("Parse end tag %s: %s\n", file.get_parse_name (), e.message);
        }

        if (tags != null) {
            //  Fast parsing is done, just return
            return tags;
        }

        //  Parse tags by Gstreamer demux/parse, it is slow
        try {
            if (stream.seek (0, SeekType.SET)) {
                var demux_name = get_demux_name_by_content (head);
                if (demux_name == null) {
                    var uri = file.get_uri ();
                    var pos = uri.last_index_of_char ('.');
                    var ext = uri.substring (pos + 1);
                    demux_name = get_demux_name_by_extension (ext);
                }
                tags = parse_demux_tags (stream, (!)demux_name);
            }
        } catch (Error e) {
            //  print ("Parse demux %s: %s\n", file.get_parse_name (), e.message);
        }
        return tags;
    }

    public static uint8[] new_uint8_array (uint size) throws Error {
        if ((int) size <= 0 || size > int32.MAX)
            throw new IOError.INVALID_ARGUMENT ("invalid size");
        return new uint8[size];
    }

    public static bool read_full (BufferedInputStream stream, uint8[] buffer) throws Error {
        size_t bytes = 0;
        return stream.read_all (buffer, out bytes) && bytes == buffer.length;
    }

    public static uint32 read_uint32_be (uint8[] data, uint pos = 0) {
        return data[pos + 3]
            | ((uint32) (data[pos+2]) << 8)
            | ((uint32) (data[pos+1]) << 16)
            | ((uint32) (data[pos]) << 24);
    }

    public static uint32 read_uint32_le (uint8[] data, uint pos = 0) {
        return data[pos]
            | ((uint32) (data[pos+1]) << 8)
            | ((uint32) (data[pos+2]) << 16)
            | ((uint32) (data[pos+3]) << 24);
    }

    public static Gst.TagList? merge_tags (Gst.TagList? tags, Gst.TagList? tags2,
                                            Gst.TagMergeMode mode = Gst.TagMergeMode.APPEND) {
        return tags != null ? tags?.merge (tags2, mode) : tags2;
    }

    public static Gst.TagList? parse_end_tags (BufferedInputStream stream) throws Error {
        //  Try parse end tag: ID3v1 or APE
        if (! stream.seek (-128, SeekType.END))  {
            throw new IOError.INVALID_DATA (@"seek -128");
        }

        var foot = new uint8[128];
        if (! read_full (stream, foot)) {
            throw new IOError.INVALID_DATA (@"read 128 bytes");
        }

        Gst.TagList? tags = null;
        if (Memory.cmp (foot, "TAG", 3) == 0) {
            tags = Gst.Tag.List.new_from_id3v1 (foot);
            //  Try check if there is APE at front of ID3v1
            if (stream.seek (- (int) (128 + 32), SeekType.END)) {
                var head = new uint8[32];
                if (read_full (stream, head) && Memory.cmp (head, "APETAGEX", 8) == 0) {
                    uint32 size = read_uint32_le (head, 12) + 32;
                    if (stream.seek (- (int) (size), SeekType.CUR)) {
                        var data = new_uint8_array (size);
                        if (read_full (stream, data)) {
                            var tags2 = GstExt.ape_demux_parse_tags (data);
                            //  APE is better than ID3v1, do REPLACE merge
                            tags = merge_tags (tags, tags2, Gst.TagMergeMode.REPLACE);
                        }
                    }
                }
            }
        } else if (Memory.cmp (foot[128-32:], "APETAGEX", 8) == 0) {
            var size = read_uint32_le (foot, foot.length - 32 + 12) + 32;
            if (stream.seek (- (int) (size), SeekType.END)) {
                var data = new_uint8_array (size);
                if (read_full (stream, data)) {
                    tags = GstExt.ape_demux_parse_tags (data);
                }
            }
        }
        return tags;
    }

    public static Gst.TagList? parse_flac_tags (BufferedInputStream stream) throws Error {
        var head = new uint8[4];
        if (! read_full (stream, head) || Memory.cmp (head, "fLaC", 4) != 0) {
            return null;
        }
        Gst.TagList? tags = null;
        while (read_full (stream, head)) {
            var type = head[0] & 0x7f;
            var size = ((uint32) (head[1]) << 16) | ((uint32) (head[2]) << 8) | head[3];
            //  print ("FLAC block: %d, %u\n", type, size);
            if (type == 4) {
                var data = new_uint8_array (size + 4);
                if (read_full (stream, data[4:])) {
                    head[0] &= (~0x80); // clear the is-last flag
                    Memory.copy (data, head, 4);
                    var tags2 = Gst.Tag.List.from_vorbiscomment (data, head, null);
                    tags = merge_tags (tags, tags2);
                } else {
                    break;
                }
            } else if (type == 6) {
                var data = new_uint8_array (size);
                if (read_full (stream, data)) {
                    uint pos = 0;
                    var img_type = read_uint32_be (data, pos);
                    pos += 4;
                    var img_mimetype_len = read_uint32_be (data, pos);
                    pos += 4 + img_mimetype_len;
                    if (pos + 4 > size) {
                        break;
                    }
                    var img_description_len = read_uint32_be (data, pos);
                    pos += 4 + img_description_len;
                    pos += 4 * 4; // image properties
                    if (pos + 4 > size) {
                        break;
                    }
                    var img_len = read_uint32_be (data, pos);
                    pos += 4;
                    if (pos + img_len > size) {
                        break;
                    }
                    tags = tags ?? new Gst.TagList.empty ();
                    Gst.Tag.List.add_id3_image ((!)tags, data[pos:pos+img_len], img_type);
                } else {
                    break;
                }
            } else if (! stream.seek (size, SeekType.CUR)) {
                break;
            }
        }
        return tags;
    }

    public static Gst.TagList? parse_demux_tags (BufferedInputStream stream, string demux_name) throws Error {
        var str = @"giostreamsrc name=src ! $(demux_name) ! fakesink sync=false";
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
                    if (tags != null) {
                        Gst.TagList? tags2 = null;
                        msg.parse_tag (out tags2);
                        tags = merge_tags (tags, tags2);
                    } else {
                        msg.parse_tag (out tags);
                    }
                    unowned string? title = null;
                    Gst.Sample? sample = null;
                    if ((tags?.peek_string_index ("title", 0, out title) ?? false)
                        || (tags?.get_sample ("image", out sample) ?? false)) {
                        quit = true;
                    }
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

    private static string? get_demux_name_by_content (uint8[] head) {
        uint8* p = head;
        if (Memory.cmp (p, "FORM", 4) == 0 && (Memory.cmp(p + 8, "AIFF", 4) == 0 || Memory.cmp(p + 8, "AIFC", 4) == 0)) {
            return "aiffparse";
        } else if (Memory.cmp (p, "fLaC", 4) == 0) {
            return "flacparse";
        } else if (Memory.cmp (p + 4, "ftyp", 4) == 0) {
            return "qtdemux";
        } else if (Memory.cmp (p, "OggS", 4) == 0) {
            return "oggdemux";
        } else if (Memory.cmp (p, "RIFF", 4) == 0 && Memory.cmp(p + 8, "WAVE", 4) == 0) {
            return "wavparse";
        } else if (Memory.cmp (p, "\x30\x26\xB2\x75\x8E\x66\xCF\x11\xA6\xD9\x00\xAA\x00\x62\xCE\x6C", 16) == 0) {
            return "asfparse";
        }
        return null;
    }

    private static string get_demux_name_by_extension (string ext_name) {
        var ext = ext_name.down ();
        switch (ext) {
            case "aiff":
                return "aiffparse";
            case "flac":
                return "flacparse";
            case "m4a":
            case "m4b":
            case "mp4":
                return "qtdemux";
            case "ogg":
            case "oga":
                return "oggdemux";
            case "opus":
                return "opusparse";
            case "vorbis":
                return "vorbisparse";
            case "wav":
                return "wavparse";
            case "wma":
                return "asfparse";
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
