namespace G4 {

#if ADW_1_5
    public class Dialog : Adw.Dialog {
#else
    public class Dialog : Gtk.Window {

        public new void close () {
            base.destroy ();
        }

        public new void present (Gtk.Window? parent = null) {
            if (parent != null) {
                modal = true;
                transient_for = (!)parent;
            }
            set_titlebar (new Adw.Bin ());
            base.present ();
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            child.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.VERTICAL) {
                var height = transient_for.get_height ();
                if (natural > height && height > 0)
                    natural = height;
            }
        }
#endif
    }

    public class PlaylistDialog : Dialog {
        private Gtk.ToggleButton search_btn = new Gtk.ToggleButton ();
        private Gtk.SearchEntry search_entry = new Gtk.SearchEntry ();

        private Application _app;
        private SourceFunc? _callback = null;
        private MusicList _list;
        private Playlist? _playlist = null;
        private bool _result = false;

        public PlaylistDialog (Application app) {
            _app = app;

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.child = content;

            var header = new Gtk.HeaderBar ();
            header.show_title_buttons = false;
            header.title_widget = new Gtk.Label (_("Add to Playlist"));
            header.add_css_class ("flat");
            content.append (header);

            var new_btn = new Gtk.Button.from_icon_name ("folder-new-symbolic");
            new_btn.tooltip_text = _("New Playlist");
            new_btn.clicked.connect (() => {
                close_with_result (true);
            });
            header.pack_start (new_btn);

            var close_btn = new Gtk.Button.from_icon_name ("window-close-symbolic");
            close_btn.tooltip_text = _("Close");
            close_btn.clicked.connect (() => {
                close_with_result (false);
            });
            header.pack_end (close_btn);
            header.pack_end (search_btn);

            var search_bar = new Gtk.SearchBar ();
            search_bar.child = search_entry;
            search_bar.key_capture_widget = content;
            content.append (search_bar);

            search_btn.icon_name = "edit-find-symbolic";
            search_btn.tooltip_text = _("Search");
            search_btn.toggled.connect (on_search_btn_toggled);
            search_btn.bind_property ("active", search_bar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);
            search_entry.hexpand = true;
            search_entry.search_changed.connect (on_search_text_changed);

            var loading_paintable = app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);
            var list = _list = new MusicList (app, typeof (Playlist), null, false, false);
            list.hexpand = true;
            list.vexpand = true;
            list.margin_bottom = 2;
            list.item_activated.connect ((position, obj) => {
                _playlist = obj as Playlist;
                close_with_result (true);
            });
            list.item_binded.connect ((item) => {
                var cell = (MusicWidget) item.child;
                var playlist = (Playlist) item.item;
                cell.music = playlist;
                cell.paintable = loading_paintable;
                cell.title = playlist.title;
            });
            content.append (list);

            app.music_library_changed.connect (on_music_library_changed);
            on_music_library_changed (true);
        }

        public Playlist? playlist {
            get {
                return _playlist;
            }
        }

        public async bool choose (Gtk.Window? parent = null) {
            _callback = choose.callback;
            present (parent);
            yield;
            return _result;
        }

        private void close_with_result (bool result) {
            _app.music_library_changed.disconnect (on_music_library_changed);
            _result = result;
            if (_callback != null)
                Idle.add ((!)_callback);
            close ();
        }

        private void on_music_library_changed (bool external) {
            if (external) {
                unowned var store = _list.data_store;
                var text = _("No playlist found in %s").printf (get_display_name (_app.music_folder));
                _app.loader.library.overwrite_playlists_to (store);
                _list.set_empty_text (text);
            }
        }

        private void on_search_btn_toggled () {
            if (search_btn.active) {
                search_entry.grab_focus ();
            }
            on_search_text_changed ();
        }

        private string _search_text = "";

        private bool on_search_match (Object obj) {
            unowned var playlist = (Playlist) obj;
            return _search_text.match_string (playlist.title, true);
        }

        private void on_search_text_changed () {
            _search_text = search_entry.text;
            var model = _list.filter_model;
            if (search_btn.active && model.get_filter () == null) {
                model.set_filter (new Gtk.CustomFilter (on_search_match));
            } else if (!search_btn.active && model.get_filter () != null) {
                model.set_filter (null);
            }
            model.get_filter ()?.changed (Gtk.FilterChange.DIFFERENT);
        }
    }

    public class TagListDialog : Dialog {
        public struct TagOrder {
            unowned string tag;
            int order;
        }

        public class TagItem : Object {
            public string tag;
            public string value;
            private string _key;
            private int _order;

            public TagItem (string t, string v) {
                tag = embellish_tag_name (t);
                value = v;
                _key = tag.collate_key_for_filename ();

                unowned string orig_key;
                if (!ORDERS.lookup_extended (_key, out orig_key, out _order))
                    _order = int.MAX >> 1;
            }

            public static int compare_by_name (TagItem ti1, TagItem ti2) {
                int ret = ti1._order - ti2._order;
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
                { Gst.Tags.GENRE, 5 },
                { Gst.Tags.DATE_TIME, 6 },
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
            foreach (var str in text.split (" ")) {
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
                sb.append_c (' ');
            }
            return sb.str;
        }

        private Gtk.ListBox list_box = new Gtk.ListBox ();
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

            spinner.margin_start = 6;
            header.pack_start (spinner);

            var scroll_view = new Gtk.ScrolledWindow ();
            scroll_view.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll_view.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroll_view.propagate_natural_height = true;
            scroll_view.vexpand = true;
            content.append (scroll_view);

            list_box.margin_start = 16;
            list_box.margin_end = 16;
            list_box.margin_top = 8;
            list_box.margin_bottom = 16;
            list_box.selection_mode = Gtk.SelectionMode.NONE;
            list_box.add_css_class ("boxed-list");
            scroll_view.child = list_box;

            if (tags != null) {
                load_tags ((!)tags);
            } else {
                laod_tags_async.begin (uri, (obj, res) => laod_tags_async.end (res));
            }
        }

        private async void laod_tags_async (string uri) {
            child.height_request = 480;
            spinner.start ();
            var file = File.new_for_uri (uri);
            var tags = yield run_async<Gst.TagList?> (() => parse_gst_tags (file));
            if (tags != null) {
                load_tags ((!)tags);
            }
            spinner.stop ();
        }

        private void load_tags (Gst.TagList tags) {
            var count = tags.n_tags ();
            var arr = new GenericArray<TagItem> (count);
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
                            sb.append_c ('/');
                    }
                    arr.add (new TagItem (tag, sb.str));
                }
            }
            arr.sort (TagItem.compare_by_name);

            foreach (var ti in arr) {
                var row = new Adw.ActionRow ();
                row.title = ti.tag;
                row.subtitle = ti.value;
#if ADW_1_2
                row.use_markup = false;
#endif
#if ADW_1_3
                row.subtitle_selectable = true;
#endif
                row.add_css_class ("property");
                list_box.append (row);
            }
        }
    }

    public async bool show_alert_dialog (string text, Gtk.Window? parent = null) {
#if ADW_1_5
        var result = new bool[] { false };
        var dialog = new Adw.AlertDialog (null, text);
        dialog.add_response ("no", _("No"));
        dialog.add_response ("yes", _("Yes"));
        dialog.default_response = "yes";
        dialog.response.connect ((id) => {
            result[0] = id == "yes";
            Idle.add (show_alert_dialog.callback);
        });
        dialog.present (parent);
        yield;
        return result[0];
#elif GTK_4_10
        var dialog = new Gtk.AlertDialog (text);
        dialog.buttons = { _("No"), _("Yes") };
        dialog.cancel_button = 0;
        dialog.default_button = 1;
        dialog.modal = true;
        try {
            var btn = yield dialog.choose (parent, null);
            return btn == 1;
        } catch (Error e) {
        }
        return false;
#else
        var result = new int[] { -1 };
        var dialog = new Gtk.MessageDialog (parent, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                            Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, text);
        dialog.response.connect ((id) => {
            dialog.destroy ();
            result[0] = id;
            Idle.add (show_alert_dialog.callback);
        });
        dialog.set_titlebar (new Adw.Bin ());
        dialog.present ();
        yield;
        return result[0] == Gtk.ResponseType.YES;
#endif
    }

    public async File? show_save_file_dialog (Gtk.Window? parent, File? initial = null, Gtk.FileFilter[]? filters = null) {
        Gtk.FileFilter? default_filter = filters != null && ((!)filters).length > 0 ? ((!)filters)[0] : (Gtk.FileFilter?) null;
#if GTK_4_10
        var filter_list = new ListStore (typeof (Gtk.FileFilter));
        if (filters != null) {
            foreach (var filter in (!)filters) 
                filter_list.append (filter);
        }
        var dialog = new Gtk.FileDialog ();
        dialog.filters = filter_list;
        dialog.modal = true;
        dialog.set_default_filter (default_filter);
        dialog.set_initial_file (initial);
        try {
            return yield dialog.save (parent, null);
        } catch (Error e) {
        }
        return null;
#else
        var result = new File?[] { (File?) null };
        var chooser = new Gtk.FileChooserNative (null, parent, Gtk.FileChooserAction.SAVE, null, null);
        chooser.modal = true;
        try {
            chooser.set_current_folder (initial?.get_parent ());
            chooser.set_current_name (initial?.get_basename () ?? "");
        } catch (Error e) {
        }
        if (filters != null) {
            foreach (var filter in (!)filters) 
                chooser.add_filter (filter);
            if (default_filter != null)
                chooser.set_filter ((!)default_filter);
        }
        chooser.response.connect ((id) => {
            var file = chooser.get_file ();
            if (id == Gtk.ResponseType.ACCEPT && file is File) {
                result[0] = file;
                Idle.add (show_save_file_dialog.callback);
            }
        });
        chooser.show ();
        yield;
        return result[0];
#endif
    }
}
