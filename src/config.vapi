[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "config.h")]
namespace Config {
    public const string APP_ID;
    public const string CODE_NAME;
    public const string VERSION;
    public const string LOCALEDIR;
}

[CCode (cprefix = "")]
namespace GLib {
    [CCode (cname = "g_strndup")]
    public string strndup (char* str, size_t n);
}
