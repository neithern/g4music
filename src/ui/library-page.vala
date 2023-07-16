namespace G4 {

    public class ItemEntry : Gtk.Box {
        public MusicEntry entry;
        public Gtk.Image icon = new Gtk.Image ();

        public ItemEntry (bool compact = false) {
            this.orientation = Gtk.Orientation.HORIZONTAL;

            entry = new MusicEntry (compact);
            entry.halign = Gtk.Align.START;
            entry.hexpand = true;
            entry.margin_end = 8;
            append (entry);
            icon.pixel_size = 12;
            append (icon);
        }

        public bool expanded {
            set {
                icon.icon_name = value ? "go-up-symbolic" : "go-next-symbolic";
            }
        }

        public bool sub_mode {
            set {
                icon.visible = !value;
                margin_start = value ? 16 : 0;
            }
        }
    }

    public class LibraryPage : Gtk.Box {
        private Application _app;
        private ListStore _artists = new ListStore (typeof (Artist));
        //  private ListStore _musics = new ListStore (typeof (Music));
        private bool _compact_list = false;
        private Gdk.Paintable _loading_paintable;
        private Gtk.ListView _artist_list = new Gtk.ListView (null, null);
        //  private Gtk.ListView _music_list = new Gtk.ListView (null, null);
        private Gtk.TreeListModel _tree_model;

        public signal void finish ();

        public LibraryPage (Application app, Window win) {
            this.orientation = Gtk.Orientation.VERTICAL;
            this.width_request = 320;
            _app = app;

            _app.music_store.loading_changed.connect (on_loading_changed);
            _app.thumbnailer.pango_context = get_pango_context ();
            _loading_paintable = _app.thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);

            _tree_model = new Gtk.TreeListModel (_artists, false, false, create_child_model);

            _artist_list.add_css_class ("navigation-sidebar");
            _artist_list.enable_rubberband = false;
            _artist_list.single_click_activate = true;
            _artist_list.activate.connect (on_item_activate);
            Idle.add (() => {
                // Delay set model after the window shown to avoid slowing down it showing
                if (root.get_height () > 0 && _artist_list.get_model () == null) {
                    _artist_list.model = new Gtk.NoSelection (_tree_model);
                }
                return root.get_height () == 0;
            }, Priority.LOW);

            var scroll_view = new Gtk.ScrolledWindow ();
            scroll_view.child = _artist_list;
            scroll_view.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll_view.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroll_view.vexpand = true;
            append (scroll_view);

            //  _music_list.model = new Gtk.NoSelection (_musics);

            app.settings.bind ("compact-playlist", this, "compact-list", SettingsBindFlags.DEFAULT);
        }

        public bool compact_list {
            get {
                return _compact_list;
            }
            set {
                _compact_list = value;
                _artist_list.factory = create_list_factory ();
            }
        }

        private ListModel? create_child_model (Object item) {
            var artist = (Artist) item;
            var albums = new ListStore (typeof (Album));
            if (artist.albums.length == 0) {
                _app.music_store.library.albums.foreach ((name, album) => albums.append (album));
            } else {
                artist.albums.foreach ((name, album) => albums.append (album));
            }
            albums.sort ((a1, a2) => Music.compare_by_artist (((Album)a1).cover_music, ((Album)a2).cover_music));
            return albums;
        }

        private Gtk.ListItemFactory create_list_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect (on_item_create);
            factory.bind.connect (on_item_bind);
            factory.unbind.connect (on_item_unbind);
            return factory;
        }

        private void on_item_activate (uint position) {
            var row = (!)_tree_model.get_row (position);
            var obj = row.item;
            if (obj is Artist) {
                row.expanded = !row.expanded;
                _tree_model.items_changed (position, 0, 0);
            } else if (obj is Album) {
                var album = (Album) obj;
                var store = _app.music_store.store;                
                store.remove_all ();
                album.musics.foreach ((uri, music) => store.append (music));
                store.sort ((CompareDataFunc) Music.compare_by_album);
                _app.current_item = 0;
            }
        }

        private void on_item_create (Gtk.ListItem item) {
            var item_entry = new ItemEntry (_compact_list);
            item.child = item_entry;
        }

        private Music? _get_music_from_list_item (Gtk.ListItem item) {
            var row = (Gtk.TreeListRow) item.item;
            var obj = row.item;
            if (obj is Artist) {
                var artist = (Artist) obj;
                return artist.cover_music;
            } else if (obj is Album) {
                var album = (Album) obj;
                return album.cover_music;
            }
            return null;
        }

        private async void on_item_bind (Gtk.ListItem item) {
            var item_entry = (ItemEntry) item.child;
            var entry = item_entry.entry;
            var row = (Gtk.TreeListRow) item.item;
            var obj = row.item;
            Music music;
            if (obj is Artist) {
                var artist = (Artist) obj;
                entry.cover.ratio = 0.5;
                entry.title = artist.name;
                item_entry.expanded = row.expanded;
                item_entry.sub_mode = false;
                music = artist.cover_music;
            } else if (obj is Album) {
                var album = (Album) obj;
                entry.cover.ratio = 0.1;
                entry.title = album.name;
                item_entry.sub_mode = true;
                music = album.cover_music;
            } else {
                return;
            }

            var thumbnailer = _app.thumbnailer;
            var paintable = thumbnailer.find (music);
            entry.paintable = paintable ?? _loading_paintable;
            if (paintable == null) {
                entry.first_draw_handler = entry.cover.first_draw.connect (() => {
                    entry.disconnect_first_draw ();
                    thumbnailer.load_async.begin (music, Thumbnailer.ICON_SIZE, (obj, res) => {
                        var paintable2 = thumbnailer.load_async.end (res);
                        if (music == _get_music_from_list_item (item)) {
                            entry.paintable = paintable2;
                        }
                    });
                });
            }
        }

        private void on_item_unbind (Gtk.ListItem item) {
            var item_entry = (ItemEntry) item.child;
            var entry = item_entry.entry;
            entry.disconnect_first_draw ();
            entry.paintable = null;
        }

        private void on_loading_changed (bool loading) {
            if (!loading) {
                _artists.remove_all ();
                _app.music_store.library.artists.foreach ((name, artist) => _artists.append (artist));
                _artists.sort ((a1, a2) => Music.compare_by_artist (((Artist)a1).cover_music, ((Artist)a2).cover_music));
                _artists.insert (0, new Artist (_("All Albums")));
            }
        }
    }
}
