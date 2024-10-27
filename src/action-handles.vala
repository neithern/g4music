namespace G4 {

    public const string ACTION_APP = "app.";
    public const string ACTION_ABOUT = "about";
    public const string ACTION_PREFS = "preferences";
    public const string ACTION_ADD_TO_PLAYLIST = "add-to-playlist";
    public const string ACTION_ADD_TO_QUEUE = "add-to-queue";
    public const string ACTION_EXPORT_COVER = "export-cover";
    public const string ACTION_PLAY = "play";
    public const string ACTION_PLAY_AT_NEXT = "play-at-next";
    public const string ACTION_PLAY_PAUSE = "play-pause";
    public const string ACTION_PREV = "prev";
    public const string ACTION_NEXT = "next";
    public const string ACTION_RANDOM_PLAY = "random-play";
    public const string ACTION_RELOAD = "reload";
    public const string ACTION_REMOVE = "remove";
    public const string ACTION_SAVE_LIST = "save-list";
    public const string ACTION_SCHEME = "scheme";
    public const string ACTION_SHOW_FILE = "show-file";
    public const string ACTION_SHOW_TAGS = "show-tags";
    public const string ACTION_SHOW_TAGS_CURRENT = "show-cur-tags";
    public const string ACTION_SORT = "sort";
    public const string ACTION_TOGGLE_SORT = "toggle-sort";
    public const string ACTION_TRASH_FILE = "trash-file";
    public const string ACTION_QUIT = "quit";

    public const string ACTION_WIN = "win.";
    public const string ACTION_BUTTON = "button";
    public const string ACTION_SEARCH = "search";
    public const string ACTION_SELECT = "select";
    public const string ACTION_TOGGLE_SEARCH = "toggle-search";

    struct ActionShortKey {
        public unowned string name;
        public unowned string key;
    }

    public class ActionHandles : Object {
        private Application _app;
        private Portal _portal = new Portal ();

        public ActionHandles (Application app) {
            _app = app;

            ActionEntry[] action_entries = {
                { ACTION_ABOUT, () => show_about_dialog (_app) },
                { ACTION_ADD_TO_PLAYLIST, add_to_playlist, "s" },
                { ACTION_ADD_TO_QUEUE, play_or_queue, "s" },
                { ACTION_EXPORT_COVER, export_cover, "s" },
                { ACTION_NEXT, () => _app.play_next () },
                { ACTION_PLAY, play_or_queue, "s" },
                { ACTION_PLAY_AT_NEXT, play_at_next, "s" },
                { ACTION_PLAY_PAUSE, () => _app.play_pause () },
                { ACTION_PREV, () => _app.play_previous () },
                { ACTION_PREFS, show_preferences },
                { ACTION_RANDOM_PLAY, play_or_queue, "s" },
                { ACTION_RELOAD, () => _app.reload_library () },
                { ACTION_SCHEME, scheme, "s", "'0'" },
                { ACTION_SHOW_FILE, show_file, "s" },
                { ACTION_SHOW_TAGS, show_tags, "s" },
                { ACTION_SHOW_TAGS_CURRENT, show_tags },
                { ACTION_SORT, sort_by, "s", "'2'" },
                { ACTION_TOGGLE_SORT, toggle_sort },
                { ACTION_TRASH_FILE, trash_file, "s" },
                { ACTION_QUIT, () => _app.quit () }
            };
            app.add_action_entries (action_entries, this);

            ActionShortKey[] app_keys = {
                { ACTION_PREFS, "<primary>comma" },
                { ACTION_PLAY_PAUSE, "<primary>p" },
                { ACTION_PREV, "<primary>Left" },
                { ACTION_NEXT, "<primary>Right" },
                { ACTION_RELOAD, "<primary>r" },
                { ACTION_SHOW_TAGS_CURRENT, "<primary>t" },
                { ACTION_TOGGLE_SORT, "<primary>m" },
                { ACTION_QUIT, "<primary>q" }
            };
            foreach (var item in app_keys) {
                app.set_accels_for_action (ACTION_APP + item.name, {item.key});
            }

            ActionShortKey[] win_keys = {
                { ACTION_SAVE_LIST, "<primary>s" },
                { ACTION_TOGGLE_SEARCH, "<primary>f" },
            };
            foreach (var item in win_keys) {
                app.set_accels_for_action (ACTION_WIN + item.name, {item.key});
            }
        }

        public Portal portal {
            get {
                return _portal;
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
                    (_app.active_window as Window)?.show_toast (
                        saved ? _("Export cover successfully") : _("Export cover failed"), saved ? file?.get_uri () : (string?) null);
                }
            }
        }

        private void add_to_playlist (SimpleAction action, Variant? parameter) {
            var uri = parameter?.get_string ();
            var playlist = parse_playlist_from_music_uri (uri);
            if (playlist != null) {
                _app.show_add_playlist_dialog.begin ((!)playlist, (obj, res) => _app.show_add_playlist_dialog.end (res));
            }
        }

        private void export_cover (SimpleAction action, Variant? parameter) {
            var uri = parameter?.get_string ();
            var music = uri != null ? _app.loader.find_cache ((!)uri) : null;
            if (music != null)
                _export_cover_async.begin ((!)music, (obj, res) => _export_cover_async.end (res));
        }

        private Playlist? parse_playlist_from_music_uri (string? uri) {
            Music? node = null;
            if (uri != null) {
                string? ar = null, al = null, pl = null;
                parse_library_uri ((!)uri, out ar, out al, out pl);
                var loader = _app.loader;
                var library = loader.library;
                if (ar != null) {
                    var artist = library.get_artist ((!)ar);
                    if (artist != null && al != null && ((!)al).length > 0)
                        node = ((!)artist)[(!)al];
                    else
                        node = artist;
                } else if (al != null) {
                    node = library.get_album ((!)al);
                } else if (pl != null) {
                    node = library.get_playlist ((!)pl);
                } else {
                    node = loader.find_cache ((!)uri);
                }
            }
            return node != null ? to_playlist ({(!)node}) : (Playlist?) null;
        }

        private void play_or_queue (SimpleAction action, Variant? parameter) {
            var uri = parameter?.get_string ();
            if (action.name.has_suffix (ACTION_ADD_TO_QUEUE)) {
                var playlist = parse_playlist_from_music_uri (uri);
                if (playlist != null)
                    _app.insert_to_queue ((!)playlist);
            } else if (uri != null) {
                Window.get_default ()?.open_page ((!)uri, true, action.name.has_suffix (ACTION_RANDOM_PLAY));
            }
        }

        private void play_at_next (SimpleAction action, Variant? parameter) {
            var uri = parameter?.get_string ();
            var playlist = parse_playlist_from_music_uri (uri);
            if (playlist != null)
                _app.insert_after_current ((!)playlist);
        }

        private void scheme (SimpleAction action, Variant? state) {
            uint scheme = 0;
            if (uint.try_parse (state?.get_string () ?? "", out scheme))
                _app.settings.set_uint ("color-scheme", scheme);
        }

        private void show_file (SimpleAction action, Variant? parameter) {
            var uri = parameter?.get_string ();
            if (uri != null) {
                if (((!)uri).has_prefix (LIBRARY_SCHEME)) {
                    Window.get_default ()?.open_page ((!)uri, false);
                } else {
                    _portal.open_directory_async.begin ((!)uri, (obj, res) => {
                        try {
                            _portal.open_directory_async.end (res);
                        } catch (Error e) {
                            Window.get_default ()?.show_toast (e.message);
                        }
                    });
                }
            }
        }

        private void show_tags (SimpleAction action, Variant? parameter) {
            var uri = parameter?.get_string () ?? _app.current_music?.uri;
            if (uri != null) {
                var tags = strcmp (_app.current_music?.uri, uri) == 0 ? _app.player.tag_list : (Gst.TagList?) null;
                var dialog = new TagListDialog ((!)uri, tags);
                dialog.present (Window.get_default ());
            }
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
            if (int.try_parse (value, out mode))
                _app.sort_mode = mode;
        }

        private void toggle_sort () {
            if (_app.sort_mode >= SortMode.MAX)
                _app.sort_mode = SortMode.ALBUM;
            else
                _app.sort_mode = _app.sort_mode + 1;
        }

        private void trash_file (SimpleAction action, Variant? parameter) {
            var uri = parameter?.get_string ();
            if (uri != null) {
                _portal.trash_file_async.begin ((!)uri, (obj, res) => {
                    try {
                        if (_portal.trash_file_async.end (res)) {
                            _app.loader.on_file_removed.begin (File.new_for_uri ((!)uri),
                                (obj, res) => _app.loader.on_file_removed.end (res));
                        }
                    } catch (Error e) {
                        Window.get_default ()?.show_toast (e.message);
                    }
                });
            }
        }
    }
}
