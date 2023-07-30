namespace G4 {

    public const string ACTION_APP = "app.";
    public const string ACTION_ABOUT = "about";
    public const string ACTION_PREFS = "preferences";
    public const string ACTION_EXPORT_COVER = "export-cover";
    public const string ACTION_PLAY = "play";
    public const string ACTION_PLAY_AT_NEXT = "play-at-next";
    public const string ACTION_PLAY_PAUSE = "play-pause";
    public const string ACTION_PREV = "prev";
    public const string ACTION_NEXT = "next";
    public const string ACTION_RELOAD = "reload";
    public const string ACTION_SEARCH = "search";
    public const string ACTION_SHOW_COVER_FILE = "show-cover-file";
    public const string ACTION_SHOW_MUSIC_FILES = "show-music-file";
    public const string ACTION_SORT = "sort";
    public const string ACTION_TOGGLE_SEARCH = "toggle-earch";
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
                { ACTION_EXPORT_COVER, export_cover, "s" },
                { ACTION_NEXT, () => _app.play_next () },
                { ACTION_PLAY, play, "s" },
                { ACTION_PLAY_AT_NEXT, play_at_next, "s" },
                { ACTION_PLAY_PAUSE, () => _app.play_pause () },
                { ACTION_PREV, () => _app.play_previous () },
                { ACTION_PREFS, show_preferences },
                { ACTION_RELOAD, () => _app.reload_library () },
                { ACTION_SEARCH, search_by, "s" },
                { ACTION_SHOW_COVER_FILE, show_cover_file, "s" },
                { ACTION_SHOW_MUSIC_FILES, show_music_file, "s" },
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

        private async void _export_cover_async (Music? music) {
            Gst.Sample? sample = _app.current_cover;
            if (music != null && music != _app.current_music) {
                var file = File.new_for_uri (music?.uri ?? "");
                sample = yield run_async<Gst.Sample?> (() => {
                    var tags = parse_gst_tags (file);
                    return tags != null ? parse_image_from_tag_list ((!)tags) : null;
                });
            }
            if (music != null && sample != null && _app.active_window is Window) {
                var itype = sample?.get_caps ()?.get_structure (0)?.get_name ();
                var pos = itype?.index_of_char ('/') ?? -1;
                var ext = itype?.substring (pos + 1) ?? "";
                var name = ((!)music).get_artist_and_title ().replace ("/", "&") + "." + ext;
                var filter = new Gtk.FileFilter ();
                filter.add_mime_type (itype ??  "image/*");
#if GTK_4_10
                var dialog = new Gtk.FileDialog ();
                dialog.set_initial_name (name);
                dialog.set_default_filter (filter);
                dialog.modal = true;
                try {
                    var file = yield dialog.save (_app.active_window, null);
                    if (file != null) {
                        yield save_sample_to_file_async ((!)file, (!)sample);
                    }
                } catch (Error e) {
                }
#else
                var chooser = new Gtk.FileChooserNative (null, _app.active_window, Gtk.FileChooserAction.SAVE, null, null);
                chooser.set_current_name (name);
                chooser.set_filter (filter);
                chooser.modal = true;
                chooser.response.connect ((id) => {
                    var file = chooser.get_file ();
                    if (id == Gtk.ResponseType.ACCEPT && file is File) {
                        save_sample_to_file_async.begin ((!)file, (!)sample,
                            (obj, res) => save_sample_to_file_async.end (res));
                    }
                });
                chooser.show ();
#endif
            }
        }

        private Music? _get_music_from_parameter (Variant? parameter) {
            unowned var uri = parameter?.get_string (null);
            return uri != null ? _app.loader.find_cache ((!)uri) : null;
        }

        private void export_cover (SimpleAction action, Variant? parameter) {
            var music = _get_music_from_parameter (parameter);
            _export_cover_async.begin (music, (obj, res) => _export_cover_async.end (res));
        }

        private Object? _parse_music_or_album_from_parameter (Variant? parameter) {
            unowned var text = parameter?.get_string (null);
            if (text != null) {
                var uri = (!)text;
                var loader = _app.loader;
                var music = loader.find_cache (uri);
                if (music != null) {
                    return music;
                } else if (uri.has_prefix ("album://")) try {
                    var u = Uri.parse ((!)uri, UriFlags.NONE);
                    var library = loader.library;
                    var path = u.get_path ();
                    var arr = path.split ("/");
                    var count = arr.length;
                    if (count > 2) {
                        //  The first part is ""
                        var album_name = Uri.unescape_string (arr[2]) ?? "";
                        if (arr[1] != "*") {
                            var artist_name = Uri.unescape_string (arr[1]) ?? "";
                            var artist = library.artists[artist_name];
                            if (artist is Artist)
                                return artist.albums[album_name];
                        }
                        return Uri.is_valid (album_name, UriFlags.NONE) ? library.playlists[album_name] : library.albums[album_name];
                    }
                } catch (Error e) {
                }
            }
            return null;
        }

        private void play (SimpleAction action, Variant? parameter) {
            var obj = _parse_music_or_album_from_parameter (parameter);
            _app.play (obj);
        }

        private void play_at_next (SimpleAction action, Variant? parameter) {
            var obj = _parse_music_or_album_from_parameter (parameter);
            _app.play_at_next (obj);
        }

        private void search_by (SimpleAction action, Variant? parameter) {
            var text = parameter?.get_string (null) ?? "";
            var mode = SearchMode.ANY;
            parse_search_mode (ref text, ref mode);
            (_app.active_window as Window)?.start_search (text, mode);
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

        private void show_cover_file (SimpleAction action, Variant? parameter) {
            var music = _get_music_from_parameter (parameter);
            _app.show_uri_with_portal (music?.cover_uri);
        }

        private void show_music_file (SimpleAction action, Variant? parameter) {
            unowned var uri = parameter?.get_string (null);
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
}
