namespace G4 {

    namespace TagGroup {
        public const int BASIC = 1;
        public const int SORT = 2;
        public const int FORMAT = 3;
        public const int OTHER = 4;
    }

    public class TagListDialog : Dialog {
        public struct TagOrder {
            unowned string tag;
            int order;
        }

        public class TagItem : Object {
            public int group;
            public string tag;
            public string value;
            public string description;
            private string _key;
            private int _order;

            public TagItem (string t, string v) {
                tag = embellish_tag_name (t);
                value = v;
                description = Gst.Tags.get_description (t) ?? "";
                _key = tag.collate_key_for_filename ();

                unowned string orig_key;
                if (ORDERS.lookup_extended (_key, out orig_key, out _order)) {
                    group = TagGroup.BASIC;
                } else {
                    _order = int.MAX >> 1;
                    if (t.contains ("bitrate") || t.contains ("channel")
                        || t.contains ("crc") || t.contains ("code")
                        || t.contains ("format")) {
                        group = TagGroup.FORMAT;
                    } else if (t.contains ("sortname")) {
                        group = TagGroup.SORT;
                    } else {
                        group = TagGroup.OTHER;
                    }
                }
            }

            public static int compare_by_name (TagItem ti1, TagItem ti2) {
                int ret = ti1.group - ti2.group;
                if (ret == 0)
                    ret = ti1._order - ti2._order;
                if (ret == 0)
                    ret = strcmp (ti1._key, ti2._key);
                return ret;
            }
        }

        public const string GST_DOMAIN = "gstreamer-1.0";
        public static HashTable<string, int> ORDERS = new HashTable<string, int> (str_hash, str_equal);

        static construct {
            Intl.bindtextdomain (GST_DOMAIN, null);
            Intl.bind_textdomain_codeset (GST_DOMAIN, "UTF-8");

            TagOrder [] tag_orders = {
                { Gst.Tags.TITLE, 1 },
                { Gst.Tags.ARTIST, 2 },
                { Gst.Tags.ALBUM, 3 },
                { Gst.Tags.ALBUM_ARTIST, 4 },
                { Gst.Tags.COMPOSER, 5 },
                { Gst.Tags.GENRE, 6 },
                { Gst.Tags.DATE_TIME, 7 },
                { Gst.Tags.TRACK_NUMBER, 8 },
                { Gst.Tags.ALBUM_VOLUME_NUMBER, 9 },
                { Gst.Tags.COMMENT, int.MAX - 1 },
                { Gst.Tags.EXTENDED_COMMENT, int.MAX }
            };
            foreach (var to in tag_orders) {
                ORDERS.insert (embellish_tag_name (to.tag).collate_key_for_filename (), to.order);
            }
        }

        public static string embellish_tag_name (string name) {
            var text = dgettext (GST_DOMAIN, Gst.Tags.get_nick (name) ?? name);
            var sb = new StringBuilder ();
            var arr = text.split (" ");
            var count = arr.length;
            for (var i = 0; i < count; i++) {
                var str = arr[i];
                var first = true;
                var next = 0;
                unichar c = 0;
                while (str.get_next_char (ref next, out c)) {
                    var s = c.to_string ();
                    if (first) {
                        first = false;
                        sb.append (s.up ());
                    } else {
                        sb.append (s);
                    }
                }
                if (i < count - 1)
                    sb.append_c (' ');
            }
            return sb.str;
        }

        private GenericArray<TagItem> items = new GenericArray<TagItem>();
        private Gtk.Button copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
        private Gtk.Box group = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        private Gtk.Spinner spinner = new Gtk.Spinner ();

        public TagListDialog (string uri, Gst.TagList? tags) {
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.child = content;
            content.width_request = 340;

            var header = new Gtk.HeaderBar ();
            header.show_title_buttons = true;
            header.title_widget = new Gtk.Label (null);
            header.add_css_class ("flat");
            content.append (header);

            copy_btn.clicked.connect (copy_to_clipboard);
            copy_btn.tooltip_text = _("Copy");
            header.pack_start (copy_btn);

            spinner.margin_start = 6;
            header.pack_start (spinner);

            var scroll_view = new Gtk.ScrolledWindow ();
            scroll_view.child = group;
            scroll_view.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll_view.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroll_view.propagate_natural_height = true;
            scroll_view.vexpand = true;
            content.append (scroll_view);

            if (tags != null) {
                load_tags ((!)tags);
            } else {
                laod_tags_async.begin (uri, (obj, res) => laod_tags_async.end (res));
            }
        }

        private Gtk.ListBox create_list_box () {
            var box = new Gtk.ListBox ();
            box.margin_start = 16;
            box.margin_end = 16;
            box.margin_top = 8;
            box.margin_bottom = 16;
            box.selection_mode = Gtk.SelectionMode.NONE;
            box.add_css_class ("boxed-list");
            return box;
        }

        private void copy_to_clipboard () {
            var sb = new StringBuilder ();
            foreach (var ti in items) {
                sb.append (ti.tag);
                sb.append (ti.value.contains ("\n") ? ":\n" : "=");
                sb.append (ti.value);
                sb.append_c ('\n');
            }
            get_clipboard ().set_text (sb.str);
        }

        private async void laod_tags_async (string uri) {
            child.height_request = 480;
            copy_btn.sensitive = false;
            spinner.start ();
            var file = File.new_for_uri (uri);
            var tags = yield run_async<Gst.TagList?> (() => parse_gst_tags (file));
            if (tags != null) {
                load_tags ((!)tags);
            }
            copy_btn.sensitive = true;
            spinner.stop ();
        }

        private void load_tags (Gst.TagList tags) {
            TagItem? tag_track_count = null;
            TagItem? tag_track_number = null;
            TagItem? tag_volumn_count = null;
            TagItem? tag_volumn_number = null;
            var count = tags.n_tags ();
            for (var i = 0; i < count; i++) {
                var tag = tags.nth_tag_name (i);
                var values = new GenericArray<string> (4);
                get_one_tag (tags, tag, values);
                if (values.length > 0) {
                    var sb = new StringBuilder ();
                    var size = values.length;
                    for (var j = 0; j < size; j++) {
                        sb.append (values[j]);
                        if (j != size - 1)
                            sb.append_c ('\n');
                    }
                    var ti = new TagItem (tag, sb.str);
                    if (tag == Gst.Tags.TRACK_COUNT)
                        tag_track_count = ti;
                    else if (tag == Gst.Tags.TRACK_NUMBER)
                        tag_track_number = ti;
                    else if (tag == Gst.Tags.ALBUM_VOLUME_COUNT)
                        tag_volumn_count = ti;
                    else if (tag == Gst.Tags.ALBUM_VOLUME_NUMBER)
                        tag_volumn_number = ti;
                    else
                        items.add (ti);
                }
            }
            if (tag_track_number != null) {
                if (tag_track_count != null)
                    ((!)tag_track_number).value += "/" + ((!)tag_track_count).value;
                items.add ((!)tag_track_number);
            }
            if (tag_volumn_number != null) {
                if (tag_volumn_count != null)
                    ((!)tag_volumn_number).value += "/" + ((!)tag_volumn_count).value;
                items.add ((!)tag_volumn_number);
            }
            items.sort (TagItem.compare_by_name);

            var tag_group = -1;
            Gtk.ListBox? list_box = null;
            foreach (var ti in items) {
                var row = new Adw.ActionRow ();
                row.title = ti.tag;
                row.tooltip_text = ti.description;
#if ADW_1_2
                row.use_markup = false;
#endif
#if ADW_1_3
                row.subtitle_selectable = true;
#endif
                row.subtitle = ti.value;
                row.add_css_class ("property");
                if (tag_group != ti.group || list_box == null) {
                    tag_group = ti.group;
                    list_box = create_list_box ();
                    group.append ((!)list_box);
                }
                list_box?.append (row);
            }
        }
    }
}
