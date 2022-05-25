namespace Music {

    public static SongInfo? parse_tags (string url) {
        var file = new TagLib.File (File.new_for_uri (url).get_path ());
        if (file.is_valid ()) {
            unowned TagLib.Tag tag = file.tag;
            SongInfo info = new SongInfo ();
            if (tag.album != null && tag.album.length > 0)
                info.album = tag.album;
            if (tag.artist != null && tag.artist.length > 0)
                info.artist = tag.artist;
            if (tag.title != null && tag.title.length > 0)
                info.title = tag.title;
            //  print ("Parse: %s\n", url);
            return info;
        }
        return null;
    }

    public static async SongInfo? parse_tags_async (owned string url) {
        try {
            var future = Gee.task<SongInfo?> (() => {
                return parse_tags (url);
            });
            return future.wait ();
        } catch (Error e) {
            print ("Parse task %s: %s\n", url, e.message);
        }
        return null;
    }
/*
    public static async SongInfo? parse_id3v2_tags_async (string url) {
        try {
            var file = File.new_for_uri (url);
            var stream = yield file.read_async ();
            var header = new uint8[Gst.Tag.ID3V2_HEADER_SIZE];
            var n = yield stream.read_async (header);
            if (n != Gst.Tag.ID3V2_HEADER_SIZE)
                return null;

            var buffer = Gst.Buffer.new_wrapped_full (0, header, 0, header.length, null);
            var size = Gst.Tag.get_id3v2_tag_size (buffer);
            if (size == 0)
                return null;

            var data = new uint8[size];
            n = yield stream.read_async (data);
            if (n != size)
                return null;

            var buffer2 = Gst.Buffer.new_wrapped_full (0, data, 0, data.length, null);
            buffer = buffer.append (buffer2);
            var tags = Gst.Tag.list_from_id3v2_tag (buffer);
            if (tags == null)
                return null;

            SongInfo info = new SongInfo ();
            tags.get_string ("album", out info.album);
            tags.get_string ("artist", out info.artist);
            tags.get_string ("title", out info.title);
            return info;
        } catch (Error e) {
            print ("Parse %s: %s\n", url, e.message);
        }
        return null;
    }
*/
}