namespace G4 {

    public class MusicList : Adw.Bin {
        private bool _compact_list = false;
        private ListStore _data_store = new ListStore (typeof (Music));
        private Gtk.FilterListModel _filter_model = new Gtk.FilterListModel (null, null);
        private bool _grid_mode = false;
        private int _image_size = 96;
        private Gtk.GridView _grid_view = new Gtk.GridView (null, null);
        private Gtk.ScrolledWindow _scroll_view = new Gtk.ScrolledWindow ();
        private Thumbnailer _thmbnailer;

        public signal void item_activated (uint position, Object? obj);
        public signal void item_created (Gtk.ListItem item);
        public signal void item_binded (Gtk.ListItem item);

        public MusicList (Application app, bool grid = false) {
            this.child = _scroll_view;
            _filter_model.model = _data_store;
            _grid_mode = grid;
            _image_size = grid ? Thumbnailer.GRID_SIZE : Thumbnailer.ICON_SIZE;
            _thmbnailer = app.thumbnailer;

            _grid_view.enable_rubberband = false;
            _grid_view.single_click_activate = true;
            _grid_view.activate.connect ((position) => item_activated (position, _filter_model.get_item (position)));
            _grid_view.model = new Gtk.NoSelection (_filter_model);
            _grid_view.add_css_class ("navigation-sidebar");

            _scroll_view.child = _grid_view;
            _scroll_view.hscrollbar_policy = Gtk.PolicyType.NEVER;
            _scroll_view.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            _scroll_view.vexpand = true;
        }

        public bool compact_list {
            get {
                return _compact_list;
            }
            set {
                _compact_list = value;
                create_factory ();
            }
        }

        public ListStore data_store {
            get {
                return _data_store;
            }
            set {
                _data_store = value;
            }
        }

        public Gtk.FilterListModel filter_model {
            get {
                return _filter_model;
            }
            set {
                _filter_model = value;
                _grid_view.model = new Gtk.NoSelection (_filter_model);
            }
        }

        public uint visible_count {
            get {
                return _filter_model.get_n_items ();
            }
        }

        public void create_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect (on_create_item);
            factory.bind.connect (on_bind_item);
            factory.unbind.connect (on_unbind_item);
            _grid_view.factory = factory;
        }

        public void scroll_to_item (int index) {
            _grid_view.activate_action_variant ("list.scroll-to-item", new Variant.uint32 (index));
        }

        private void on_create_item (Gtk.ListItem item) {
            if (_grid_mode)
                item.child = new MusicCell ();
            else
                item.child = new MusicEntry (_compact_list);
            item_created (item);
        }

        private void on_bind_item (Gtk.ListItem item) {
            var entry = (MusicWidget) item.child;
            var music = (Music) item.item;
            item_binded (item);

            var paintable = _thmbnailer.find (music, _image_size);
            if (paintable != null) {
                entry.paintable = paintable;
            } else {
                entry.first_draw_handler = entry.cover.first_draw.connect (() => {
                    entry.disconnect_first_draw ();
                    _thmbnailer.load_async.begin (music, _image_size, (obj, res) => {
                        var paintable2 = _thmbnailer.load_async.end (res);
                        if (music == (Music) item.item) {
                            entry.paintable = paintable2;
                        }
                    });
                });
            }
        }

        private void on_unbind_item (Gtk.ListItem item) {
            var entry = (MusicWidget) item.child;
            entry.disconnect_first_draw ();
            entry.paintable = null;
        }
    }
}