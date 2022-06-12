[CCode (cprefix = "", lower_case_cprefix = "")]
namespace GstExt {
    [CCode (cheader_filename = "gst-ext.h")]
    public static Gst.TagList ape_demux_parse_tags ([CCode (array_length_cname = "size", array_length_pos = 2.5, array_length_type = "gsize")] uint8[] data);

    [CCode (cheader_filename = "gst-ext.h")]
    public static void gst_level_calculate_gint8 (void* data, uint num, uint channels, out double NCS, out double NPS);
    [CCode (cheader_filename = "gst-ext.h")]
    public static void gst_level_calculate_gint16 (void* data, uint num, uint channels, out double NCS, out double NPS);
    [CCode (cheader_filename = "gst-ext.h")]
    public static void gst_level_calculate_gint32 (void* data, uint num, uint channels, out double NCS, out double NPS);
    [CCode (cheader_filename = "gst-ext.h")]
    public static void gst_level_calculate_gfloat (void* data, uint num, uint channels, out double NCS, out double NPS);
    [CCode (cheader_filename = "gst-ext.h")]
    public static void gst_level_calculate_gdouble (void* data, uint num, uint channels, out double NCS, out double NPS);
}