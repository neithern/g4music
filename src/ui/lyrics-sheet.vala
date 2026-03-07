namespace G4 {

    public struct LyricWord {
        public string text;
        public double start_sec;
        public double end_sec;
    }

    public struct LyricLine {
        public int64 time_ms;
        public string text;
        public LyricWord[] words;
        public bool is_bg;
    }

    public class LyricsSheet : Object {
        private Application _app;
        private Gtk.ListBox _list_box;
        private Gtk.ScrolledWindow _scroll;
        private LyricLine[] _lines = {};
        private int _current_index = -1;
        private Gtk.Label _provider_label;
        private Gtk.Label _offset_label;
        private int64 _offset_ms = 0;
        private string _current_uri = "";
        private string _current_raw = "";   // raw lyrics string in cache
        public Adw.BottomSheet bottom_sheet;

        private static Soup.Session? _http_session = null;

        private static Soup.Session http_session () {
            if (_http_session == null)
                _http_session = new Soup.Session ();
            return (!)_http_session;
        }

        public LyricsSheet (Application app) {
            _app = app;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.height_request = 900;

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            header.add_css_class ("toolbar");
            header.margin_top = 24;
            header.hexpand = true;
            var title = new Gtk.Label (_("Lyrics"));
            title.add_css_class ("title-4");
            title.halign = Gtk.Align.CENTER;
            title.hexpand = true;
            header.append (title);
            box.append (header);

            _provider_label = new Gtk.Label ("");
            _provider_label.add_css_class ("dim-label");
            _provider_label.add_css_class ("caption");
            _provider_label.margin_bottom = 4;
            box.append (_provider_label);

            _list_box = new Gtk.ListBox ();
            _list_box.selection_mode = Gtk.SelectionMode.NONE;
            _list_box.vexpand = true;
            _list_box.margin_start = 16;
            _list_box.margin_end = 16;
            _list_box.margin_top = 8;
            _list_box.margin_bottom = 8;
            _list_box.row_activated.connect ((row) => {
                var index = row.get_index ();
                if (index >= 0 && index < _lines.length) {
                    var ms = _lines[index].time_ms;
                    _app.player.seek (GstPlayer.from_second (ms / 1000.0));
                }
            });

            _scroll = new Gtk.ScrolledWindow ();
            _scroll.child = _list_box;
            _scroll.vexpand = true;
            _scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            _scroll.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            box.append (_scroll);

            // ── Bottom bar ───────────────────────────────────────────
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            bar.add_css_class ("toolbar");
            bar.margin_start = 8;
            bar.margin_end = 8;

            // Refresh button
            var refresh_btn = new Gtk.Button ();
            refresh_btn.icon_name = "view-refresh-symbolic";
            refresh_btn.tooltip_text = _("Refresh lyrics");
            refresh_btn.add_css_class ("flat");
            refresh_btn.clicked.connect (() => {
                clear_cache (_current_uri);
                load_lyrics.begin ();
            });
            bar.append (refresh_btn);

            // Offset controls (centred)
            var offset_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            offset_box.halign = Gtk.Align.CENTER;
            offset_box.hexpand = true;

            var minus_btn = new Gtk.Button.with_label ("-100ms");
            minus_btn.add_css_class ("flat");
            minus_btn.add_css_class ("pill");
            minus_btn.clicked.connect (() => {
                _offset_ms -= 100;
                update_offset_label ();
                save_cache (_current_uri, _current_raw,
                    _provider_label.label, _offset_ms);
            });

            _offset_label = new Gtk.Label ("0ms");
            _offset_label.width_chars = 7;
            _offset_label.halign = Gtk.Align.CENTER;

            var plus_btn = new Gtk.Button.with_label ("+100ms");
            plus_btn.add_css_class ("flat");
            plus_btn.add_css_class ("pill");
            plus_btn.clicked.connect (() => {
                _offset_ms += 100;
                update_offset_label ();
                save_cache (_current_uri, _current_raw,
                    _provider_label.label, _offset_ms);
            });

            offset_box.append (minus_btn);
            offset_box.append (_offset_label);
            offset_box.append (plus_btn);
            bar.append (offset_box);

            // Edit button
            var edit_btn = new Gtk.Button ();
            edit_btn.icon_name = "document-edit-symbolic";
            edit_btn.tooltip_text = _("Edit lyrics");
            edit_btn.add_css_class ("flat");
            edit_btn.clicked.connect (open_edit_dialog);
            bar.append (edit_btn);

            box.append (bar);

            bottom_sheet = new Adw.BottomSheet ();
            bottom_sheet.sheet = box;
            bottom_sheet.modal = true;

            bottom_sheet.notify["open"].connect (() => {
                if (bottom_sheet.open) {
                    _app.player.position_updated.connect (on_position_updated);
                    load_lyrics.begin ();
                } else {
                    _app.player.position_updated.disconnect (on_position_updated);
                }
            });

            app.music_changed.connect ((music) => {
                _current_index = -1;
                if (bottom_sheet.open)
                    load_lyrics.begin ();
            });

            apply_lyrics_css ();
        }

        public void open () {
            bottom_sheet.open = true;
        }

        // ── Offset ───────────────────────────────────────────────────

        private void update_offset_label () {
            _offset_label.label = "%lldms".printf (_offset_ms);
        }

        // ── Position tracking ────────────────────────────────────────

        private void on_position_updated (Gst.ClockTime position) {
            var sec = GstPlayer.to_second (position);
            var ms = (int64) (sec * 1000) + _offset_ms;
            update_current_line (ms, ms / 1000.0);
        }

        private void update_current_line (int64 ms, double sec) {
            if (_lines.length == 0) return;

            var new_index = 0;
            for (var i = 0; i < _lines.length; i++) {
                if (_lines[i].time_ms <= ms)
                    new_index = i;
                else
                    break;
            }

            update_word_highlights (new_index, sec);

            if (new_index == _current_index) return;
            _current_index = new_index;

            var idx = 0;
            var child = _list_box.get_first_child ();
            while (child != null) {
                var next = ((!)child).get_next_sibling ();
                if (child is Gtk.ListBoxRow) {
                    var row = (Gtk.ListBoxRow)(!)child;
                    if (idx == _current_index) {
                        row.remove_css_class ("lyrics-row-inactive");
                        row.add_css_class ("lyrics-row-active");
                    } else {
                        row.remove_css_class ("lyrics-row-active");
                        row.add_css_class ("lyrics-row-inactive");
                    }
                    idx++;
                }
                child = next;
            }

            var active_row = _list_box.get_row_at_index (_current_index);
            if (active_row != null) {
                Idle.add (() => {
                    var r = (!)active_row;
                    var alloc = Gtk.Allocation ();
                    r.get_allocation (out alloc);
                    var adj = _scroll.vadjustment;
                    var target = alloc.y - (adj.page_size / 2.0) + (alloc.height / 2.0);
                    adj.set_value (target.clamp (adj.lower, adj.upper - adj.page_size));
                    return false;
                });
            }
        }

        private void update_word_highlights (int line_index, double sec) {
            var row = _list_box.get_row_at_index (line_index);
            if (row == null) return;
            var label = ((!)row).child as Gtk.Label;
            if (label == null) return;
            ((!)label).set_label (build_line_markup (_lines[line_index], sec));
        }

        private string build_line_markup (LyricLine line, double sec) {
            if (line.words.length == 0) {
                return Markup.escape_text (line.text.length > 0 ? line.text : "·");
            }
            var sb = new StringBuilder ();
            foreach (var word in line.words) {
                var escaped = Markup.escape_text (word.text);
                if (sec < 0) {
                    sb.append ("<span alpha='40%%'>%s</span> ".printf (escaped));
                } else if (sec >= word.start_sec && sec < word.end_sec) {
                    sb.append ("<span alpha='100%%' underline='single'>%s</span> ".printf (escaped));
                } else if (sec >= word.end_sec) {
                    sb.append ("<span alpha='65%%'>%s</span> ".printf (escaped));
                } else {
                    sb.append ("<span alpha='40%%'>%s</span> ".printf (escaped));
                }
            }
            return sb.str.strip ();
        }

        // ── UI state ─────────────────────────────────────────────────

        private void set_provider (string name) {
            _provider_label.label = name;
        }

        private void clear_list () {
            var child = _list_box.get_first_child ();
            while (child != null) {
                var next = ((!)child).get_next_sibling ();
                _list_box.remove ((!)child);
                child = next;
            }
        }

        private void populate_list () {
            clear_list ();
            foreach (var line in _lines) {
                var line_label = new Gtk.Label ("");
                line_label.use_markup = true;
                line_label.wrap = true;
                line_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
                line_label.justify = Gtk.Justification.CENTER;
                line_label.halign = Gtk.Align.CENTER;
                line_label.margin_top = line.is_bg ? 2 : 8;
                line_label.margin_bottom = line.is_bg ? 2 : 8;
                line_label.add_css_class (line.is_bg ? "lyrics-word-bg" : "lyrics-word");
                line_label.set_label (build_line_markup (line, -1.0));

                var row = new Gtk.ListBoxRow ();
                row.child = line_label;
                row.activatable = true;
                row.selectable = false;
                row.add_css_class ("lyrics-row-inactive");
                _list_box.append (row);
            }
        }

        private void show_not_found () {
            clear_list ();
            _lines = {};
            _current_index = -1;
            var label = new Gtk.Label (_("Lyrics Not Found"));
            label.add_css_class ("dim-label");
            label.add_css_class ("title-4");
            label.margin_top = 48;
            var row = new Gtk.ListBoxRow ();
            row.child = label;
            row.activatable = false;
            row.selectable = false;
            _list_box.append (row);
        }

        private void show_loading () {
            set_provider ("");
            clear_list ();
            var spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            spinner.margin_top = 48;
            var row = new Gtk.ListBoxRow ();
            row.child = spinner;
            row.activatable = false;
            row.selectable = false;
            _list_box.append (row);
        }

        // ── Edit dialog ──────────────────────────────────────────────

        private void open_edit_dialog () {
            var dialog = new Adw.Dialog ();
            dialog.title = _("Edit Lyrics");
            dialog.content_width = 600;
            dialog.content_height = 500;

            var toolbar_view = new Adw.ToolbarView ();

            var header_bar = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header_bar);

            var save_btn = new Gtk.Button.with_label (_("Save"));
            save_btn.add_css_class ("suggested-action");
            header_bar.pack_end (save_btn);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hexpand = true;

            var text_view = new Gtk.TextView ();
            text_view.monospace = true;
            text_view.wrap_mode = Gtk.WrapMode.NONE;
            text_view.margin_start = 12;
            text_view.margin_end = 12;
            text_view.margin_top = 8;
            text_view.margin_bottom = 8;
            text_view.buffer.text = _current_raw;
            scroll.child = text_view;

            toolbar_view.content = scroll;
            dialog.child = toolbar_view;

            save_btn.clicked.connect (() => {
                var new_raw = text_view.buffer.text;
                _current_raw = new_raw;
                save_cache (_current_uri, new_raw, _provider_label.label, _offset_ms);
                // Re-parse and redisplay
                _lines = {};
                _current_index = -1;
                _lines = parse_rich_sync (new_raw);
                if (_lines.length == 0)
                    _lines = parse_ttml (new_raw);
                if (_lines.length == 0)
                    _lines = parse_lrc (new_raw);
                if (_lines.length > 0)
                    populate_list ();
                else
                    show_not_found ();
                dialog.close ();
            });

            var win = bottom_sheet.get_root () as Gtk.Window;
            dialog.present (win);
        }

        // ── Cache ─────────────────────────────────────────────────────

        private string get_cache_path (string uri) {
            var cache_dir = GLib.Path.build_filename (
                GLib.Environment.get_user_cache_dir (), "semitone", "lyrics");
            DirUtils.create_with_parents (cache_dir, 0755);
            var hash = GLib.Checksum.compute_for_string (GLib.ChecksumType.MD5, uri, -1);
            return GLib.Path.build_filename (cache_dir, hash + ".json");
        }

        private void save_cache (string uri, string raw, string provider, int64 offset) {
            if (uri.length == 0) return;
            var path = get_cache_path (uri);
            var now = (int64) GLib.get_real_time () / 1000000;
            // Build JSON manually to avoid extra deps
            var escaped_uri = uri.replace ("\\", "\\\\").replace ("\"", "\\\"");
            var escaped_provider = provider.replace ("\"", "\\\"");
            var escaped_raw = raw.replace ("\\", "\\\\")
                                 .replace ("\"", "\\\"")
                                 .replace ("\n", "\\n")
                                 .replace ("\r", "");
            var json = "{\"uri\":\"%s\",\"provider\":\"%s\",\"fetched_at\":%lld,\"offset_ms\":%lld,\"lyrics\":\"%s\"}"
                .printf (escaped_uri, escaped_provider, now, offset, escaped_raw);
            try {
                FileUtils.set_contents (path, json);
            } catch (Error e) {}
        }

        // Returns true if cache was loaded successfully
        private bool load_cache (string uri) {
            if (uri.length == 0) return false;
            var path = get_cache_path (uri);
            string contents;
            try {
                FileUtils.get_contents (path, out contents);
            } catch (Error e) {
                return false;
            }

            // Parse fetched_at to check staleness (7 days)
            var fetched_at = extract_json_int (contents, "fetched_at");
            var now = (int64) GLib.get_real_time () / 1000000;
            if (fetched_at > 0 && (now - fetched_at) > 7 * 24 * 3600) {
                return false; // stale, re-fetch
            }

            var provider = extract_json_string (contents, "provider");
            var offset = extract_json_int (contents, "offset_ms");
            var raw = extract_json_string (contents, "lyrics");

            if (raw.length == 0) return false;

            _current_raw = raw;
            _offset_ms = offset;
            update_offset_label ();
            set_provider (provider + " (cached)");

            _lines = parse_rich_sync (raw);
            if (_lines.length == 0)
                _lines = parse_ttml (raw);
            if (_lines.length == 0)
                _lines = parse_lrc (raw);

            return _lines.length > 0;
        }

        private void clear_cache (string uri) {
            if (uri.length == 0) return;
            var path = get_cache_path (uri);
            FileUtils.unlink (path);
        }

        // Minimal JSON field extractors (no deps)
        private string extract_json_string (string json, string key) {
            var search = "\"" + key + "\":\"";
            var idx = json.index_of (search);
            if (idx < 0) return "";
            var start = idx + search.length;
            var sb = new StringBuilder ();
            var i = start;
            while (i < json.length) {
                var c = json[i];
                if (c == '\\' && i + 1 < json.length) {
                    var next = json[i + 1];
                    if (next == 'n') sb.append_c ('\n');
                    else if (next == '\\') sb.append_c ('\\');
                    else if (next == '"') sb.append_c ('"');
                    else sb.append_c (next);
                    i += 2;
                } else if (c == '"') {
                    break;
                } else {
                    sb.append_c (c);
                    i++;
                }
            }
            return sb.str;
        }

        private int64 extract_json_int (string json, string key) {
            var search = "\"" + key + "\":";
            var idx = json.index_of (search);
            if (idx < 0) return 0;
            var start = idx + search.length;
            var end = start;
            while (end < json.length && (json[end].isdigit () || json[end] == '-'))
                end++;
            return int64.parse (json.substring (start, end - start));
        }

        // ── Main load ────────────────────────────────────────────────

        private async void load_lyrics () {
            _lines = {};
            _current_index = -1;
            _current_raw = "";
            _offset_ms = 0;
            update_offset_label ();
            show_loading ();

            var music = _app.current_music;
            if (music == null) {
                show_not_found ();
                return;
            }
            var m = (!)music;
            _current_uri = m.uri;

            // 1. Try cache first
            if (load_cache (_current_uri)) {
                populate_list ();
                return;
            }

            // 2. Local test file (dev only)
            var test_file = File.new_for_path (
                GLib.Environment.get_home_dir () + "/Documents/LyricsTest.txt");
            if (test_file.query_exists ()) {
                try {
                    uint8[] data;
                    test_file.load_contents (null, out data, null);
                    var raw = (string) data;
                    if (raw.length > 0) {
                        _current_raw = raw;
                        _lines = parse_lrc (raw);
                        set_provider ("Test File");
                        populate_list ();
                        return;
                    }
                } catch (Error e) {}
            }

            var settings = _app.settings;

            // 3. BetterLyrics
            if (settings.get_boolean ("lyrics-betterlyrics-enabled")) {
                var bl_result = yield fetch_betterlyrics (m.title, m.artist, m.album);
                if (bl_result != null) {
                    _lines = parse_ttml ((!)bl_result);
                    if (_lines.length > 0) {
                        _current_raw = (!)bl_result;
                        set_provider ("BetterLyrics");
                        save_cache (_current_uri, _current_raw, "BetterLyrics", 0);
                        populate_list ();
                        return;
                    }
                }
            }

            // 4. SimpMusic
            if (settings.get_boolean ("lyrics-simpmusic-enabled")) {
                var yt_id = extract_youtube_id (m.comment);
                if (yt_id != null) {
                    var sm_result = yield fetch_simpmusic ((!)yt_id);
                    if (sm_result != null) {
                        _lines = parse_rich_sync ((!)sm_result);
                        if (_lines.length == 0)
                            _lines = parse_lrc ((!)sm_result);
                        if (_lines.length > 0) {
                            _current_raw = (!)sm_result;
                            set_provider ("SimpMusic");
                            save_cache (_current_uri, _current_raw, "SimpMusic", 0);
                            populate_list ();
                            return;
                        }
                    }
                }
            }

            // 5. LRCLib
            if (settings.get_boolean ("lyrics-lrclib-enabled")) {
                var lrclib_result = yield fetch_lrclib (m.title, m.artist, m.album);
                if (lrclib_result != null) {
                    _lines = parse_lrc ((!)lrclib_result);
                    if (_lines.length > 0) {
                        _current_raw = (!)lrclib_result;
                        set_provider ("LRCLib");
                        save_cache (_current_uri, _current_raw, "LRCLib", 0);
                        populate_list ();
                        return;
                    }
                }
            }

            set_provider ("");
            show_not_found ();
        }

        // ── HTTP ─────────────────────────────────────────────────────

        private async string? http_get (string url) {
            try {
                var msg = new Soup.Message ("GET", url);
                msg.request_headers.append ("User-Agent", "Semitone/1.0");
                var stream = yield http_session ().send_async (msg, GLib.Priority.DEFAULT, null);
                if (msg.status_code != 200) return null;
                var dis = new DataInputStream (stream);
                var sb = new StringBuilder ();
                string? line = null;
                do {
                    line = yield dis.read_line_async (GLib.Priority.DEFAULT, null);
                    if (line != null) {
                        sb.append ((!)line);
                        sb.append_c ('\n');
                    }
                } while (line != null);
                return sb.str;
            } catch (Error e) {
                return null;
            }
        }

        // ── BetterLyrics ─────────────────────────────────────────────

        private async string? fetch_betterlyrics (string title, string artist, string album) {
            var url = "https://lyrics-api.boidu.dev/getLyrics?s=%s&a=%s&al=%s".printf (
                Uri.escape_string (title, null, false),
                Uri.escape_string (artist, null, false),
                Uri.escape_string (album, null, false));
            var body = yield http_get (url);
            if (body == null) return null;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data ((!)body);
                var root_obj = parser.get_root ()?.get_object ();
                if (root_obj == null) return null;
                var obj = (!)root_obj;
                return obj.get_string_member ("ttml");
            } catch (Error e) {
                return null;
            }
        }

        // ── SimpMusic ────────────────────────────────────────────────

        private static string? extract_youtube_id (string comment) {
            if (comment.length == 0) return null;
            try {
                var re = new Regex (
                    "(?:youtu\\.be/|youtube\\.com/(?:watch\\?v=|v/|embed/))([A-Za-z0-9_-]{11})");
                MatchInfo info;
                if (re.match (comment, 0, out info))
                    return info.fetch (1);
            } catch (RegexError e) {}
            return null;
        }

        private async string? fetch_simpmusic (string video_id) {
            var url = "https://api-lyrics.simpmusic.org/v1/%s".printf (
                Uri.escape_string (video_id, null, false));
            var body = yield http_get (url);
            if (body == null) return null;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data ((!)body);
                var root_obj = parser.get_root ()?.get_object ();
                if (root_obj == null) return null;
                var obj = (!)root_obj;
                if (!obj.get_boolean_member ("success")) return null;
                var data = obj.get_array_member ("data");
                if (data == null) return null;
                Json.Object? best = null;
                ((!)data).foreach_element ((arr, i, node) => {
                    if (best != null) return;
                    var track = node.get_object ();
                    if (track == null) return;
                    best = track;
                });
                if (best == null) return null;
                var b = (!)best;
                string? result = null;
                if (b.has_member ("richSyncLyrics"))
                    result = b.get_string_member ("richSyncLyrics");
                if ((result == null || ((!)result).length == 0) && b.has_member ("syncedLyrics"))
                    result = b.get_string_member ("syncedLyrics");
                if ((result == null || ((!)result).length == 0) && b.has_member ("plainLyrics"))
                    result = b.get_string_member ("plainLyrics");
                return result;
            } catch (Error e) {
                return null;
            }
        }

        // ── LRCLib ───────────────────────────────────────────────────

        private async string? fetch_lrclib (string title, string artist, string album) {
            var url = "https://lrclib.net/api/get?track_name=%s&artist_name=%s&album_name=%s".printf (
                Uri.escape_string (title, null, false),
                Uri.escape_string (artist, null, false),
                Uri.escape_string (album, null, false));
            var body = yield http_get (url);
            if (body == null) return null;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data ((!)body);
                var root_obj = parser.get_root ()?.get_object ();
                if (root_obj == null) return null;
                var obj = (!)root_obj;
                string? result = null;
                if (obj.has_member ("syncedLyrics"))
                    result = obj.get_string_member ("syncedLyrics");
                if ((result == null || ((!)result).length == 0) && obj.has_member ("plainLyrics"))
                    result = obj.get_string_member ("plainLyrics");
                return result;
            } catch (Error e) {
                return null;
            }
        }

        // ── TTML parser ──────────────────────────────────────────────

        private LyricLine[] parse_ttml (string ttml) {
            LyricLine[] result = {};
            if (!ttml.contains ("<tt") && !ttml.contains ("<body"))
                return result;
            var doc = Xml.Parser.parse_memory (ttml, ttml.length);
            if (doc == null) return result;
            unowned Xml.Node* root = doc->get_root_element ();
            if (root == null) { delete doc; return result; }

            unowned Xml.Node* body = null;
            for (var n = root->children; n != null; n = n->next) {
                if (n->name == "body") { body = n; break; }
            }
            if (body == null) { delete doc; return result; }

            for (var div = body->children; div != null; div = div->next) {
                if (div->type != Xml.ElementType.ELEMENT_NODE) continue;
                for (var p = div->children; p != null; p = p->next) {
                    if (p->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (p->name != "p") continue;

                    var begin_str = p->get_prop ("begin");
                    if (begin_str == null) continue;
                    var ms = ttml_time_to_ms ((!)begin_str);
                    if (ms < 0) continue;

                    LyricWord[] main_words = {};
                    LyricWord[] bg_words = {};
                    var line_text_sb = new StringBuilder ();

                    for (var span = p->children; span != null; span = span->next) {
                        if (span->type != Xml.ElementType.ELEMENT_NODE) continue;
                        if (span->name != "span") continue;

                        var role = span->get_prop ("role");
                        bool is_this_bg = (role != null && (!)role == "x-bg");

                        if (is_this_bg) {
                            for (var ws = span->children; ws != null; ws = ws->next) {
                                if (ws->type != Xml.ElementType.ELEMENT_NODE) continue;
                                var w_begin = ws->get_prop ("begin");
                                var w_end = ws->get_prop ("end");
                                var w_text = ws->get_content ();
                                if (w_begin != null && w_end != null && w_text.length > 0) {
                                    LyricWord w = {
                                        w_text,
                                        ttml_time_to_ms ((!)w_begin) / 1000.0,
                                        ttml_time_to_ms ((!)w_end) / 1000.0
                                    };
                                    bg_words += w;
                                }
                            }
                        } else {
                            var w_begin = span->get_prop ("begin");
                            var w_end = span->get_prop ("end");
                            var w_text = span->get_content ();
                            if (w_begin != null && w_end != null && w_text.length > 0) {
                                LyricWord w = {
                                    w_text,
                                    ttml_time_to_ms ((!)w_begin) / 1000.0,
                                    ttml_time_to_ms ((!)w_end) / 1000.0
                                };
                                main_words += w;
                                line_text_sb.append (w_text);
                            }
                        }
                    }

                    LyricLine main_line = { ms, line_text_sb.str, main_words, false };
                    result += main_line;

                    if (bg_words.length > 0) {
                        var bg_text_sb = new StringBuilder ();
                        foreach (var bw in bg_words)
                            bg_text_sb.append (bw.text);
                        LyricLine bg_line = { ms, bg_text_sb.str, bg_words, true };
                        result += bg_line;
                    }
                }
            }
            delete doc;
            return result;
        }

        private int64 ttml_time_to_ms (string t) {
            var parts = t.split (":");
            if (parts.length == 3) {
                var h = int.parse (parts[0]);
                var m = int.parse (parts[1]);
                var s = double.parse (parts[2]);
                return (int64) ((h * 3600 + m * 60 + s) * 1000);
            } else if (parts.length == 2) {
                var m = int.parse (parts[0]);
                var s = double.parse (parts[1]);
                return (int64) ((m * 60 + s) * 1000);
            } else {
                return (int64) (double.parse (t) * 1000);
            }
        }

        // ── richSyncLyrics parser ────────────────────────────────────

        private LyricLine[] parse_rich_sync (string lrc) {
            if (!lrc.contains ("<")) return {};

            LyricLine[] result = {};
            foreach (var raw_line in lrc.split ("\n")) {
                var line = raw_line.strip ();
                if (line.length < 5 || line[0] != '[') continue;

                var close = line.index_of_char (']');
                if (close < 0) continue;

                var line_ts = line.substring (1, close - 1);
                var line_ms = parse_timestamp (line_ts);
                if (line_ms < 0) continue;

                var rest = line.substring (close + 1);

                LyricWord[] words = {};
                var text_sb = new StringBuilder ();
                var pos = 0;

                while (pos < rest.length) {
                    if (rest[pos] == '<') {
                        var end = rest.index_of_char ('>', pos);
                        if (end < 0) break;
                        var ts_str = rest.substring (pos + 1, end - pos - 1);
                        var word_start_ms = parse_timestamp (ts_str);
                        pos = end + 1;

                        var word_start = pos;
                        while (pos < rest.length && rest[pos] != '<')
                            pos++;
                        var word_text = rest.substring (word_start, pos - word_start)
                            .replace ("&#x27;", "'")
                            .replace ("&amp;", "&")
                            .replace ("&lt;", "<")
                            .replace ("&gt;", ">")
                            .strip ();

                        if (word_text.length > 0 && word_start_ms >= 0) {
                            LyricWord w = { word_text, word_start_ms / 1000.0, 0.0 };
                            words += w;
                            text_sb.append (word_text);
                            text_sb.append_c (' ');
                        }
                    } else {
                        pos++;
                    }
                }

                for (var i = 0; i < words.length - 1; i++)
                    words[i].end_sec = words[i + 1].start_sec;
                if (words.length > 0)
                    words[words.length - 1].end_sec = words[words.length - 1].start_sec + 3.0;

                LyricLine l = { line_ms, text_sb.str.strip (), words, false };
                result += l;
            }
            return result;
        }

        // ── LRC parser ───────────────────────────────────────────────

        private LyricLine[] parse_lrc (string lrc) {
            LyricLine[] result = {};
            var raw_lines = lrc.split ("\n");
            var i = 0;
            while (i < raw_lines.length) {
                var line = raw_lines[i].strip ();
                i++;

                if (line.length < 5 || line[0] != '[') continue;

                var close = line.index_of_char (']');
                if (close < 0) continue;

                var timestamp = line.substring (1, close - 1);
                var rest = line.substring (close + 1).strip ();

                var is_bg = false;
                if (rest.has_prefix ("{")) {
                    var tag_end = rest.index_of_char ('}');
                    if (tag_end >= 0) {
                        var tag = rest.substring (1, tag_end - 1);
                        is_bg = tag == "bg";
                        rest = rest.substring (tag_end + 1).strip ();
                    }
                }

                var ms = parse_timestamp (timestamp);
                if (ms < 0) continue;

                LyricWord[] words = {};
                if (i < raw_lines.length && raw_lines[i].strip ().has_prefix ("<")) {
                    words = parse_word_timings (raw_lines[i].strip ());
                    i++;
                }

                LyricLine l = { ms, rest, words, is_bg };
                result += l;
            }
            return result;
        }

        private LyricWord[] parse_word_timings (string timing_line) {
            LyricWord[] words = {};
            var inner = timing_line;
            if (inner.has_prefix ("<")) inner = inner.substring (1);
            if (inner.has_suffix (">")) inner = inner.substring (0, inner.length - 1);

            var parts = inner.split ("|");
            foreach (var part in parts) {
                var segments = part.split (":");
                if (segments.length >= 3) {
                    LyricWord w = { segments[0], double.parse (segments[1]), double.parse (segments[2]) };
                    words += w;
                }
            }
            return words;
        }

        private int64 parse_timestamp (string ts) {
            var parts = ts.split (":");
            if (parts.length != 2) return -1;
            var minutes = int.parse (parts[0]);
            var sec_parts = parts[1].split (".");
            if (sec_parts.length != 2) return -1;
            var seconds = int.parse (sec_parts[0]);
            var centis = int.parse (sec_parts[1]);
            return (int64) (minutes * 60 * 1000 + seconds * 1000 + centis * 10);
        }

        // ── CSS ──────────────────────────────────────────────────────

        private void apply_lyrics_css () {
            var css = new Gtk.CssProvider ();
            css.load_from_string ("""
                .lyrics-row-inactive {
                    opacity: 0.35;
                }
                .lyrics-row-active {
                    opacity: 1.0;
                }
                .lyrics-word {
                    font-size: 20px;
                    font-weight: bold;
                    padding: 1px 8px;
                }
                .lyrics-word-bg {
                    font-size: 15px;
                    font-weight: normal;
                    padding: 1px 8px;
                }
            """);
            var display = Gdk.Display.get_default ();
            if (display != null) {
                Gtk.StyleContext.add_provider_for_display (
                    (!)display, css,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );
            }
        }
    }
}
