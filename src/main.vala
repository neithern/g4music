/* 
 * Copyright 2022 Nanling
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

int main (string[] args) {
    Intl.bindtextdomain (Config.CODE_NAME, Config.LOCALEDIR);
    Intl.bind_textdomain_codeset (Config.CODE_NAME, "UTF-8");
    Intl.textdomain (Config.CODE_NAME);

    Environment.set_prgname (Config.APP_ID);
    Environment.set_application_name (_("Gapless"));
    fix_gst_tag_encoding ();

    Random.set_seed ((uint32) get_monotonic_time ());

    G4.GstPlayer.init (ref args);

    var app = new G4.Application ();
    return app.run (args);
}

void fix_gst_tag_encoding () {
    unowned var encoding = Environment.get_variable ("GST_TAG_ENCODING");
    unowned var lang = Environment.get_variable ("LANG");
    if (encoding == null && lang != null) {
        string[] lang_encodings = {
            "ja", "Shift_JIS",
            "ko", "EUC-KR",
            "zh_CN", "GB18030",
            "zh_HK", "BIG5HKSCS",
            "zh_SG", "GB2312",
            "zh_TW", "BIG5",
        };
        for (var i = 0; i < lang_encodings.length; i += 2) {
            if (((!)lang).has_prefix (lang_encodings[i])) {
                Environment.set_variable ("GST_TAG_ENCODING", lang_encodings[i + 1], true);
                print ("Fix tag encoding: %s\n", lang_encodings[i + 1]);
                break;
            }
        }
    }
}