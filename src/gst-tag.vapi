[CCode (cprefix = "Gst", gir_namespace = "GstTag", gir_version = "1.0", lower_case_cprefix = "gst_")]
namespace Gst {
    namespace Tag {
        [CCode (cheader_filename = "gst/tag/tag.h")]
        public static Gst.TagList? list_from_id3v2_tag (Gst.Buffer buffer);
    }
}