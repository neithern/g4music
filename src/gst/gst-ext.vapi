[CCode (cprefix = "", lower_case_cprefix = "")]
namespace GstExt {
    [CCode (cheader_filename = "gst-ext.h")]
    public static Gst.TagList ape_demux_parse_tags ([CCode (array_length_cname = "size", array_length_pos = 2.5, array_length_type = "gsize")] uint8[] data);
}
