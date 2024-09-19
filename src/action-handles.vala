namespace G4 {

    public const string ACTION_APP = "app.";
    public const string ACTION_ABOUT = "about";
    public const string ACTION_PREFS = "preferences";
    public const string ACTION_ADD_TO_PLAYLIST = "add-to-playlist";
    public const string ACTION_EXPORT_COVER = "export-cover";
    public const string ACTION_PLAY = "play";
    public const string ACTION_PLAY_AT_NEXT = "play-at-next";
    public const string ACTION_PLAY_PAUSE = "play-pause";
    public const string ACTION_PREV = "prev";
    public const string ACTION_NEXT = "next";
    public const string ACTION_RELOAD = "reload";
    public const string ACTION_SEARCH = "search";
    public const string ACTION_SHOW_FILE = "show-file";
    public const string ACTION_SORT = "sort";
    public const string ACTION_TOGGLE_SEARCH = "toggle-search";
    public const string ACTION_TOGGLE_SORT = "toggle-sort";
    public const string ACTION_QUIT = "quit";

    struct ActionShortKey {
        public unowned string name;
        public unowned string key;
    }

    public class ActionHandles : Object {
        private Application _app;

        public ActionHandles (Application app) {
            _app = app;

            ActionEntry[] action_entries = {
                { ACTION_ABOUT, show_about },
                { ACTION_ADD_TO_PLAYLIST, add_to_playlist, "aay" },
                { ACTION_EXPORT_COVER, export_cover, "aay" },
                { ACTION_NEXT, () => _app.play_next () },
                { ACTION_PLAY, play, "aay" },
                { ACTION_PLAY_AT_NEXT, play_at_next, "aay" },
                { ACTION_PLAY_PAUSE, () => _app.play_pause () },
                { ACTION_PREV, () => _app.play_previous () },
                { ACTION_PREFS, show_preferences },
                { ACTION_RELOAD, () => _app.reload_library () },
                { ACTION_SEARCH, search_by, "aay" },
                { ACTION_SHOW_FILE, show_file, "aay" },
                { ACTION_SORT, sort_by, "s", "'2'" },
                { ACTION_TOGGLE_SEARCH, toggle_search },
                { ACTION_TOGGLE_SORT, toggle_sort },
                { ACTION_QUIT, () => _app.quit () }
            };
            app.add_action_entries (action_entries, this);

            ActionShortKey[] action_keys = {
                { ACTION_PREFS, "<primary>comma" },
                { ACTION_PLAY_PAUSE, "<primary>p" },
                { ACTION_PREV, "<primary>Left" },
                { ACTION_NEXT, "<primary>Right" },
                { ACTION_RELOAD, "<primary>r" },
                { ACTION_TOGGLE_SEARCH, "<primary>f" },
                { ACTION_TOGGLE_SORT, "<primary>s" },
                { ACTION_QUIT, "<primary>q" }
            };
            foreach (var item in action_keys) {
                app.set_accels_for_action (ACTION_APP + item.name, {item.key});
            }
        }

        private async void _export_cover_async (Music music) {
            var cover = _app.current_cover;
            if (cover == null || music != _app.current_music) {
                var file = File.new_for_uri (music.uri);
                cover = yield run_async<Gst.Sample?> (() => {
                    var tags = parse_gst_tags (file);
                    return tags != null ? parse_image_from_tag_list ((!)tags) : null;
                });
            }
            if (cover != null) {
                var sample = (!)cover;
                var itype = sample.get_caps ()?.get_structure (0)?.get_name ();
                var pos = itype?.index_of_char ('/') ?? -1;
                var ext = itype?.substring (pos + 1) ?? "";
                var name = music.get_artist_and_title ().replace ("/", "&") + "." + ext;
                var filter = new Gtk.FileFilter ();
                filter.name = _("Image Files");
                filter.add_mime_type ("image/*");
                var initial = File.new_build_filename (name);
                var file = yield show_save_file_dialog (_app.active_window, initial, {filter});
                if (file != null) {
                    var saved = yield save_sample_to_file_async ((!)file, sample);
                    if (saved)
                        _app.show_uri_with_portal (((!)file).get_uri ());
                }
            }
        }

        private Music? _get_music_from_parameter (Variant? parameter) {
            var uri = _parse_uri_form_parameter (parameter);
            return uri != null ? _app.loader.find_cache ((!)uri) : null;
        }

        private void add_to_playlist (SimpleAction action, Variant? parameter) {
            var strv = parameter?.get_bytestring_array ();
            var obj = _parse_music_node_form_strv (strv);
            if (obj is Music) {
                var playlist = to_playlist ({(Music) obj});
                _app.save_to_playlist_file_async.begin (playlist, (obj, res) => _app.save_to_playlist_file_async.end (res));
            }
        }

        private void export_cover (SimpleAction action, Variant? parameter) {
            var music = _get_music_from_parameter (parameter);
            if (music != null)
                _export_cover_async.begin ((!)music, (obj, res) => _export_cover_async.end (res));
        }

        private unowned string? _parse_uri_form_parameter (Variant? parameter) {
            unowned var strv = parameter?.get_bytestring_array ();
            if (strv != null && ((!)strv).length > 1) {
                var arr = (!)strv;
                return arr[0] == "uri" ? (string?) arr[1] : null;
            }
            return null;
        }

        private Object? _parse_music_node_form_strv (string[]? strv) {
            if (strv != null && ((!)strv).length > 1) {
                var arr = (!)strv;
                var loader = _app.loader;
                var library = loader.library;
                unowned var key = arr[1];
                switch (arr[0]) {
                    case PageName.ALBUM:
                        return library.albums[key];
                    case PageName.ARTIST:
                        var artist = library.artists[key];
                        if ((artist is Artist) && arr.length > 2)
                            return ((Artist) artist)[arr[2]];
                        return artist;
                    case PageName.PLAYLIST:
                        return library.playlists[key];
                    default:
                        return loader.find_cache (key);
                }
            }
            return null;
        }

        private void play (SimpleAction action, Variant? parameter) {
            var strv = parameter?.get_bytestring_array ();
            var obj = _parse_music_node_form_strv (strv);
            if (obj is Artist) {
                obj = ((Artist) obj).to_playlist ();
            }
            (_app.active_window as Window)?.open_page (strv, obj);
            _app.play (obj);
        }

        private void play_at_next (SimpleAction action, Variant? parameter) {
            var strv = parameter?.get_bytestring_array ();
            var obj = _parse_music_node_form_strv (strv);
            if (obj is Artist) {
                obj = ((Artist) obj).to_playlist ();
            }
            _app.play_at_next (obj);
        }

        private void search_by (SimpleAction action, Variant? parameter) {
            var strv = parameter?.get_bytestring_array ();
            if (strv != null && ((!)strv).length > 1) {
                var arr = (!)strv;
                var text = arr[0] + ":";
                var mode = SearchMode.ANY;
                parse_search_mode (ref text, ref mode);
                (_app.active_window as Window)?.start_search (arr[1], mode);
            }
        }

        private void show_about () {
            string[] authors = { "Nanling" };
            var comments = _("A fast, fluent, light weight music player written in GTK4.");
            /* Translators: Replace "translator-credits" with your names, one name per line */
            var translator_credits = _("translator-credits");
            var website = "https://gitlab.gnome.org/neithern/g4music";
#if ADW_1_2
            var win = new Adw.AboutWindow ();
            win.application_icon = _app.application_id;
            win.application_name = _app.name;
            win.version = Config.VERSION;
            win.comments = comments;
            win.license_type = Gtk.License.GPL_3_0;
            win.developers = authors;
            win.website = website;
            win.issue_url = "https://gitlab.gnome.org/neithern/g4music/issues";
            win.translator_credits = translator_credits;
            win.transient_for = _app.active_window;
            win.present ();
#else
            Gtk.show_about_dialog (_app.active_window,
                                   "logo-icon-name", _app.application_id,
                                   "program-name", _app.name,
                                   "version", Config.VERSION,
                                   "comments", comments,
                                   "authors", authors,
                                   "translator-credits", translator_credits,
                                   "license-type", Gtk.License.GPL_3_0,
                                   "website", website
                                  );
#endif
        }

        private void show_file (SimpleAction action, Variant? parameter) {
            var uri = _parse_uri_form_parameter (parameter);
            _app.show_uri_with_portal (uri);
        }

        private PreferencesWindow? _pref_window = null;

        private void show_preferences () {
            var win = _pref_window ?? new PreferencesWindow (_app);
            _pref_window = win;
            win.destroy_with_parent = true;
            win.modal = false;
            win.close_request.connect (() => {
                _pref_window = null;
                return false;
            });
            win.present ();
        }

        private void sort_by (SimpleAction action, Variant? state) {
            unowned var value = state?.get_string () ?? "";
            int mode = 2;
            int.try_parse (value, out mode, null, 10);
            _app.sort_mode = mode;
        }

        public void toggle_search () {
            (_app.active_window as Window)?.toggle_search ();
        }

        private void toggle_sort () {
            if (_app.sort_mode >= SortMode.MAX)
                _app.sort_mode = SortMode.ALBUM;
            else
                _app.sort_mode = _app.sort_mode + 1;
        }
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
