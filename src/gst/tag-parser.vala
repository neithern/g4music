namespace G4 {

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
                read_full (stream, head);
                //  Try parse start tag: ID3v2 or APE
                if (Memory.cmp (head, "ID3", 3) == 0) {
                    var buffer = Gst.Buffer.new_wrapped_full (0, head, 0, head.length, null);
                    var size = Gst.Tag.get_id3v2_tag_size (buffer);
                    if (size > head.length) {
                        var data = new_uint8_array (size);
                        Memory.copy (data, head, head.length);
                        read_full (stream, data[head.length:]);
                        var buffer2 = Gst.Buffer.new_wrapped_full (0, data, 0, data.length, null);
                        var tags2 = Gst.Tag.List.from_id3v2_tag (buffer2);
                        tags = merge_tags (tags, tags2);
                    }
                } else if (Memory.cmp (head, "APETAGEX", 8) == 0) {
                    seek_full (stream, 0, SeekType.SET);
                    var size = read_uint32_le (head, 12) + 32;
                    var data = new_uint8_array (size);
                    Memory.copy (data, head, head.length);
                    read_full (stream, data[head.length:]);
                    var tags2 = GstExt.ape_demux_parse_tags (data);
                    tags = merge_tags (tags, tags2);
                } else {
                    //  Parse by file container format
                    if (Memory.cmp (head, "fLaC", 4) == 0) {
                        seek_full (stream, - head.length);
                        var tags2 = parse_flac_tags (stream);
                        tags = merge_tags (tags, tags2);
                    } else if (Memory.cmp (head, "OggS", 4) == 0) {
                        seek_full (stream, - head.length);
                        var tags2 = parse_ogg_tags (stream);
                        tags = merge_tags (tags, tags2);
                    } else if (Memory.cmp (head + 4, "ftyp", 4) == 0) {
                        seek_full (stream, - head.length);
                        var tags2 = parse_mp4_tags (stream);
                        tags = merge_tags (tags, tags2);
                    }
                    // No ID3v2/APE any more, quit the loop
                    break;
                }
            } catch (Error e) {
                print ("Parse begin tag %s: %s\n", file.get_parse_name (), e.message);
                break;
            }
        }

        if (tags_has_text (tags) || tags_has_image (tags)) {
            return tags;
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
            var demux_name = get_demux_name_by_content (head);
            if (demux_name != null) {
                seek_full (stream, 0, SeekType.SET);
                tags = parse_demux_tags (stream, (!)demux_name);
            }
        } catch (Error e) {
            //  print ("Parse demux %s: %s\n", file.get_parse_name (), e.message);
        }
        return tags;
    }

    public static bool tags_has_image (Gst.TagList? tags) {
        if (tags == null)
            return false;
        var t = (!)tags;
        return t.get_tag_size (Gst.Tags.IMAGE) > 0
            || t.get_tag_size (Gst.Tags.PREVIEW_IMAGE) > 0;
    }

    public static bool tags_has_text (Gst.TagList? tags) {
        if (tags == null)
            return false;
        var t = (!)tags;
        return t.get_tag_size (Gst.Tags.ARTIST) > 0
            || t.get_tag_size (Gst.Tags.TITLE) > 0;
    }

    public inline uint8[] new_uint8_array (uint size) throws Error {
        if ((int) size <= 0 || size > 0xfffffff) // 28 bits
            throw new IOError.INVALID_ARGUMENT ("invalid size");
        return new uint8[size];
    }

    public inline void read_full (BufferedInputStream stream, uint8[] buffer) throws Error {
        size_t bytes = 0;
        if (! stream.read_all (buffer, out bytes) || bytes != buffer.length)
            throw new IOError.FAILED ("read_all");
    }

    public inline void seek_full (BufferedInputStream stream, int64 offset, SeekType type = SeekType.CUR) throws Error {
        if (! stream.seek (offset, type))
            throw new IOError.FAILED ("seek");
    }

    public inline uint32 read_uint32_be (uint8[] data, uint pos = 0) {
        return data[pos + 3]
            | ((uint32) (data[pos+2]) << 8)
            | ((uint32) (data[pos+1]) << 16)
            | ((uint32) (data[pos]) << 24);
    }

    public inline uint32 read_uint32_le (uint8[] data, uint pos = 0) {
        return data[pos]
            | ((uint32) (data[pos+1]) << 8)
            | ((uint32) (data[pos+2]) << 16)
            | ((uint32) (data[pos+3]) << 24);
    }

    public inline uint32 read_decimal_uint (uint8[] data) {
        uint32 n = 0;
        for (var i = 0; i < data.length; i++) {
            n = n * 10 + (data[i] - '0');
        }
        return n;
    }

    public static Gst.TagList? merge_tags (Gst.TagList? tags, Gst.TagList? tags2,
                                            Gst.TagMergeMode mode = Gst.TagMergeMode.KEEP) {
        return tags != null ? tags?.merge (tags2, mode) : tags2;
    }

    public static Gst.TagList? parse_end_tags (BufferedInputStream stream) throws Error {
        var apev2_found = false;
        var foot = new uint8[128];
        Gst.TagList? tags = null;
        seek_full (stream, 0, SeekType.END);
        while (true) {
            try {
                //  Try parse end tag: ID3v1 or APE
                seek_full (stream, -128);
                read_full (stream, foot);
                if (Memory.cmp (foot, "TAG", 3) == 0) {
                    var tags2 = Gst.Tag.List.new_from_id3v1 (foot);
                    tags = merge_tags (tags, tags2);
                    //  print ("ID3v1 parsed: %d\n", tags2.n_tags ());
                    seek_full (stream, -128);
                } else if (Memory.cmp (foot[128-32:], "APETAGEX", 8) == 0) {
                    var size = read_uint32_le (foot, 128 - 32 + 12) + 32;
                    seek_full (stream, - (int) size);
                    var data = new_uint8_array (size);
                    read_full (stream, data);
                    var tags2 = GstExt.ape_demux_parse_tags (data);
                    //  APEv2 is better than others, do REPLACE merge
                    tags = merge_tags (tags, tags2, Gst.TagMergeMode.REPLACE);
                    apev2_found = ! tags2.is_empty ();
                    //  print ("APEv2 parsed: %d\n", tags2.n_tags ());
                    seek_full (stream, - (int) size);
                } else if (Memory.cmp (foot[128-9:], "LYRICS200", 9) == 0) {
                    var size = read_decimal_uint (foot[128-15:128-9]);
                    seek_full (stream, - (int) (size + 15));
                    var data = new_uint8_array (size);
                    read_full (stream, data);
                    var tags2 = parse_lyrics200_tags (data);
                    tags = merge_tags (tags, tags2, apev2_found ? Gst.TagMergeMode.KEEP : Gst.TagMergeMode.REPLACE);
                    //  print ("LYRICS200 parsed: %d\n", tags2.n_tags ());
                    seek_full (stream, - (int) (size + 15));
                } else {
                    break;
                }
            } catch (Error e) {
                if (tags == null)
                    throw e;
                break;
            }
        }
        return tags;
    }

    public static Gst.TagList? parse_flac_tags (BufferedInputStream stream) throws Error {
        var head = new uint8[4];
        read_full (stream, head);
        if (Memory.cmp (head, "fLaC", 4) != 0) {
            return null;
        }
        int flags = 0;
        Gst.TagList? tags = null;
        do {
            try {
                read_full (stream, head);
                var type = head[0] & 0x7f;
                var size = ((uint32) (head[1]) << 16) | ((uint32) (head[2]) << 8) | head[3];
                //  print ("FLAC block: %d, %u\n", type, size);
                if (type == 4) {
                    var data = new_uint8_array (size + 4);
                    read_full (stream, data[4:]);
                    head[0] &= (~0x80); // clear the is-last flag
                    Memory.copy (data, head, 4);
                    var tags2 = Gst.Tag.List.from_vorbiscomment (data, head, null);
                    tags = merge_tags (tags, tags2);
                    flags |= 0x01;
                } else if (type == 6) {
                    var data = new_uint8_array (size);
                    read_full (stream, data);
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
                    flags |= 0x02;
                } else {
                    seek_full (stream, size);
                }
            } catch (Error e) {
                if (tags == null)
                    throw e;
                break;
            }
        } while ((flags & 0x03) != 0x03);
        return tags;
    }

    public const string[] ID3_TAG_ENCODINGS = {
        "GST_ID3V1_TAG_ENCODING",
        "GST_ID3_TAG_ENCODING",
        "GST_TAG_ENCODING",
        (string) null
    };

    public static Gst.TagList parse_lyrics200_tags (uint8[] data) {
        var tags = new Gst.TagList.empty ();
        if (Memory.cmp (data, "LYRICSBEGIN", 11) != 0) {
            return tags;
        }

        var length = data.length;
        var pos = 11;
        while (pos + 8 < length) {
            var id = data[pos:pos+3];
            pos += 3;
            var len = read_decimal_uint (data[pos:pos+5]);
            pos += 5;
            if (pos + len > length) {
                break;
            }
            var str = data[pos:pos+len];
            pos += (int) len;
            string? tag = null;
            if (Memory.cmp (id, "EAL", 3) == 0) {
                tag = Gst.Tags.ALBUM;
            } else if (Memory.cmp (id, "EAR", 3) == 0) {
                tag = Gst.Tags.ARTIST;
            } else if (Memory.cmp (id, "ETT", 3) == 0) {
                tag = Gst.Tags.TITLE;
            } else if (Memory.cmp (id, "LYR", 3) == 0) {
                tag = Gst.Tags.LYRICS;
            }
            if (tag != null) {
                var value = Gst.Tag.freeform_string_to_utf8 ((char[]) str, ID3_TAG_ENCODINGS);
                if (value != (string)null && value.length > 0) {
                    tags.add (Gst.TagMergeMode.REPLACE, (!)tag, value);
                }
            }
        }
        return tags;
    }

    private static void parse_mp4_date_value (uint8[] data, string tag, Gst.TagList tags) throws Error {
        var str = parse_mp4_string (data);
        if (str != null) {
            var date = new Gst.DateTime.from_iso8601_string ((!)str);
            tags.add (Gst.TagMergeMode.REPLACE, tag, date);
            //  print (@"Tag: $tag=$(date.get_year ())\n");
        } else {
            print ("MP4: unknown date type: %s\n", str ?? "");
        }
    }

    private static void parse_mp4_image_value (uint8[] data, string tag, Gst.TagList tags) throws Error {
        var len = data.length;
        if (len > 16) {
            var type = read_uint32_be (data, 8);
            if ((type == 0x0000000d || type == 0x0000000e)) {
                var image_data = data[16:len];
                Gst.Tag.ImageType image_type;
                if (tags.get_tag_size (Gst.Tags.IMAGE) == 0)
                    image_type = Gst.Tag.ImageType.FRONT_COVER;
                else
                    image_type = Gst.Tag.ImageType.NONE;
                var sample = Gst.Tag.image_data_to_image_sample (image_data, image_type);
                if (sample != (Gst.Sample)null) {
                    tags.add (Gst.TagMergeMode.REPLACE, tag, sample);
                }
                //  print (@"Tag: $tag=$(data.length)\n");
            }
        } else {
            print ("MP4: unknown image type\n");
        }
    }

    private static void parse_mp4_number_value (uint8[] data, string tag1, string tag2, Gst.TagList tags) throws Error {
        var len = data.length;
        if (len >= 22) {
            var type = read_uint32_be (data, 8);
            if (type == 0x00000000) {
                var n = read_uint32_be (data, 18);
                var n1 = n >> 16;
                var n2 = n & 0xffff;
                if (n1 > 0) {
                    tags.add (Gst.TagMergeMode.REPLACE, tag1, n1);
                    //  print (@"Tag: $tag1=$n1\n");
                }
                if (n2 > 0) {
                    tags.add (Gst.TagMergeMode.REPLACE, tag2, n2);
                    //  print (@"Tag: $tag2=$n2\n");
                }
            }
        } else {
            print ("MP4: unknown number type\n");
        }
    }

    public const string[] MP4_TAG_ENCODINGS = {
        "GST_QT_TAG_ENCODING",
        "GST_TAG_ENCODING",
        (string) null
    };

    private static string? parse_mp4_string (uint8[] data) throws Error {
        var len = data.length;
        if (len > 16) {
            var type = read_uint32_be (data, 8);
            if (type == 0x00000001) {
                var str_data = data[16:len];
                return (string?) Gst.Tag.freeform_string_to_utf8 ((char[]) str_data, MP4_TAG_ENCODINGS);
            }
        }
        return null;
    }

    private static void parse_mp4_string_value (uint8[] data, string tag, Gst.TagList tags) throws Error {
        var str = parse_mp4_string (data);
        if (str != null && ((!)str).length > 0) {
            var value = (!)str;
            tags.add (Gst.TagMergeMode.REPLACE, tag, value);
            //  print (@"Tag: $tag=$value\n");
        } else {
            print ("MP4: unknown string type\n");
        }
    }

    private static uint find_mp4_data_child (uint8[] buffer, uint pos, uint end, uint32 fourcc) {
        while (pos + 8 < end) {
            var box_size = read_uint32_be (buffer, pos);
            var box_type = read_uint32_be (buffer, pos + 4);
            if (box_type == fourcc) {
                return pos;
            }
            pos += box_size;
        }
        return end;
    }

    private static void parse_mp4_ilst_box (uint8[] buffer, Gst.TagList tags) throws Error {
        var size = buffer.length;
        uint pos = 0;
        while (pos + 8 < size) {
            var box_size = read_uint32_be (buffer, pos);
            var box_type = read_uint32_be (buffer, pos + 4);
            var box_end = pos + box_size;
            var data_pos = find_mp4_data_child (buffer, pos + 8, box_end, 0x64617461); // data
            if (box_size > 16 && data_pos != box_end) {
                var data_size = read_uint32_be (buffer, data_pos);
                var data = buffer[data_pos : data_pos + data_size];
                switch (box_type) {
                    case 0xa96e616du: // _nam
                    case 0x7469746cu: // titl
                        parse_mp4_string_value (data, Gst.Tags.TITLE, tags);
                        break;
                    case 0xa9415254u: // _ART
                    case 0x70657266u: // perf
                        parse_mp4_string_value (data, Gst.Tags.ARTIST, tags);
                        break;
                    case 0xa9616c62u: // _alb
                    case 0x616c626du: // albm
                        parse_mp4_string_value (data, Gst.Tags.ALBUM, tags);
                        break;
                    case 0xa9777274u: // _wrt
                    case 0x61757468u: // auth
                        parse_mp4_string_value (data, Gst.Tags.COMPOSER, tags);
                        break;
                    case 0xa9636d74u: // _cmt
                    case 0xa9696e66u: // _inf
                        parse_mp4_string_value (data, Gst.Tags.COMMENT, tags);
                        break;
                    case 0xa9646179u: // _day
                    case 0x79727263u: // yrrc
                        parse_mp4_date_value (data, Gst.Tags.DATE_TIME, tags);
                        break;
                    case 0x636f7672u: // covr
                        parse_mp4_image_value (data, Gst.Tags.IMAGE, tags);
                        break;
                    case 0x64697363u: // disc
                    case 0x6469736bu: // disk
                        parse_mp4_number_value (data, Gst.Tags.ALBUM_VOLUME_NUMBER, Gst.Tags.ALBUM_VOLUME_COUNT, tags);
                        break;
                    case 0x74726b6eu: // trkn
                        parse_mp4_number_value (data, Gst.Tags.TRACK_NUMBER, Gst.Tags.TRACK_COUNT, tags);
                        break;
                    default:
                        break;
                }
            }
            pos = box_end;
        }
    }

    private static void parse_mp4_box (BufferedInputStream stream, Gst.TagList tags) throws Error {
        var box_head = new uint8[8];
        while (tags.is_empty ()) {
            read_full (stream, box_head);
            var box_size = read_uint32_be (box_head);
            var box_type = read_uint32_be (box_head, 4);
            if (box_size <= 8) {
                continue;
            } else if (box_type == 0x6d6f6f76) { // moov
                parse_mp4_box (stream, tags);
            } else if (box_type == 0x75647461) { // udta
                parse_mp4_box (stream, tags);
            } else if (box_type == 0x6d657461 && box_size > 16) { // meta
                read_full (stream, box_head);
                var v1 = read_uint32_be (box_head);
                var v2 = read_uint32_be (box_head, 4);
                if (v2 == 0x68646c72) { // hdlr
                    seek_full (stream, -8);
                    parse_mp4_box (stream, tags);
                } else if (v1 == 0) {
                    seek_full (stream, -4);
                    parse_mp4_box (stream, tags);
                }
            } else if (box_type == 0x696c7374) { // ilst
                var buffer = new_uint8_array (box_size - 8);
                read_full (stream, buffer);
                parse_mp4_ilst_box (buffer, tags);
            } else {
                seek_full (stream, box_size - 8);
            }
        }
    }

    public static Gst.TagList? parse_mp4_tags (BufferedInputStream stream) {
        var tags = new Gst.TagList.empty ();
        try {
            parse_mp4_box (stream, tags);
        } catch (Error e) {
            print ("Parse MP4 Error %s\n", e.message);
        }
        return tags.is_empty () ? (Gst.TagList?) null : tags;
    }

    public const string[] OGG_TAG_IDS = {
        "\x03vorbis",
        "\x81kate\0\0\0\0",
        //  "\x81daala",
        "\x81theora",
        "OpusTags",
        "OVP80\x02 ",
    };

    public static Gst.TagList? parse_ogg_tags (BufferedInputStream stream) throws Error {
        var head = new uint8[27];
        var mos = new MemoryOutputStream (null);
        while (true) {
            read_full (stream, head);
            uint seg_count = head[26];
            var last_page = seg_count == 0;
            if (seg_count > 0) {
                var segments = new_uint8_array (seg_count);
                read_full (stream, segments);
                uint page_size = 0;
                for (var i = 0; i < seg_count; i++) {
                    page_size += segments[i];
                }
                var buffer = new_uint8_array (page_size);
                read_full (stream, buffer);
                mos.write (buffer);
                last_page = segments[seg_count - 1] != 255;
            }

            size_t size = 0;
            if (last_page && (size = mos.get_data_size ()) > 0) {
                var data = mos.get_data ()[0:size];
                foreach (var id in OGG_TAG_IDS) {
                    if (size > id.length && Memory.cmp (data, id, id.length) == 0) {
                        return Gst.Tag.List.from_vorbiscomment (data, id.data, null);
                    }
                }
                mos = new MemoryOutputStream (null);
            }

            if (seg_count == 0) {
                break;
            }
        }
        return null;
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
                    if (tags_has_text (tags) || tags_has_image (tags)) {
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
        if (Memory.cmp (p, "FORM", 4) == 0 && (Memory.cmp (p + 8, "AIFF", 4) == 0 || Memory.cmp (p + 8, "AIFC", 4) == 0)) {
            return "aiffparse";
        //  } else if (Memory.cmp (p, "fLaC", 4) == 0) {
        //      return "flacparse";
        //  } else if (Memory.cmp (p + 4, "ftyp", 4) == 0) {
        //      return "qtdemux";
        //  } else if (Memory.cmp (p, "OggS", 4) == 0) {
        //      return "oggdemux";
        } else if (read_uint32_be (head) == 0x1A45DFA3) { // EBML_HEADER
            return "matroskademux";
        } else if (Memory.cmp (p, "RIFF", 4) == 0 && Memory.cmp (p + 8, "WAVE", 4) == 0) {
            return "wavparse";
        } else if (Memory.cmp (p, "\x30\x26\xB2\x75\x8E\x66\xCF\x11\xA6\xD9\x00\xAA\x00\x62\xCE\x6C", 16) == 0) {
            return "asfparse";
        }
        return null;
    }

    public static void get_one_tag (Gst.TagList tags, string tag, GenericArray<string> values) {
        var size = tags.get_tag_size (tag);
        for (var i = 0; i < size; i++) {
            var val = tags.get_value_index (tag, i);
            if (val != null) {
                var value = (!)val;
                if (value.holds (typeof (string))) {
                    values.add (value.get_string ());
                } else if (value.holds (typeof (uint))) {
                    values.add (value.get_uint ().to_string ());
                } else if (value.holds (typeof (double))) {
                    values.add (value.get_double ().to_string ());
                } else if (value.holds (typeof (bool))) {
                    values.add (value.get_boolean ().to_string ());
                } else if (value.holds (typeof (Gst.DateTime))) {
                    var date = (Gst.DateTime) value.get_boxed ();
                    values.add (date.to_iso8601_string () ?? "");
                }
            }
        }
    }

    public static Gst.Sample? parse_image_from_tag_list (Gst.TagList tags) {
        Gst.Sample? sample = null;
        if (tags.get_sample (Gst.Tags.IMAGE, out sample)) {
            return sample;
        }
        if (tags.get_sample (Gst.Tags.PREVIEW_IMAGE, out sample)) {
            return sample;
        }

        for (var i = 0; i < tags.n_tags (); i++) {
            var tag = tags.nth_tag_name (i);
            var value = tags.get_value_index (tag, 0);
            sample = null;
            if (value?.type () == typeof (Gst.Sample)
                    && tags.get_sample (tag, out sample)) {
                var caps = sample?.get_caps ();
                if (caps != null) {
                    return sample;
                }
                //  print (@"unknown image tag: $(tag)\n");
            }
        }
        return null;
    }
}
