namespace G4 {

    public class MusicList : Adw.Bin {
        private bool _compact_list = false;
        private ListStore _data_store = new ListStore (typeof (Music));
        private Gtk.FilterListModel? _filter_model = null;
        private double _row_height = 0;
        private double _scroll_range = 0;
        private Gtk.ListView _list_view = new Gtk.ListView (null, null);
        private Gtk.ScrolledWindow _scroll_view = new Gtk.ScrolledWindow ();
        private Thumbnailer _thmbnailer;

        public signal void item_activated (uint position, Object? obj);
        public signal void item_created (Gtk.ListItem item);
        public signal void item_binded (Gtk.ListItem item);

        public MusicList (Application app) {
            this.child = _scroll_view;
            _thmbnailer = app.thumbnailer;

            _list_view.add_css_class ("navigation-sidebar");
            _list_view.enable_rubberband = false;
            _list_view.single_click_activate = true;
            _list_view.activate.connect ((position) => item_activated (position, _list_view.get_model ()?.get_item (position)));

            _scroll_view.child = _list_view;
            _scroll_view.hscrollbar_policy = Gtk.PolicyType.NEVER;
            _scroll_view.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            _scroll_view.vexpand = true;
            _scroll_view.vadjustment.changed.connect (on_vadjustment_changed);
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
        }

        public Gtk.FilterListModel? filter_model {
            get {
                return _filter_model;
            }
            set {
                if (value != null)
                    ((!)value).model = _data_store;
                _filter_model = value;
                _list_view.model = new Gtk.NoSelection (value);
            }
        }

        public uint visible_count {
            get {
                return _list_view.get_model ()?.get_n_items () ?? 0;
            }
        }

        public void create_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect (on_create_item);
            factory.bind.connect (on_bind_item);
            factory.unbind.connect (on_unbind_item);
            _list_view.factory = factory;
        }

        private Adw.Animation? _scroll_animation = null;

        public void scroll_to_item (int index) {
            var adj = _scroll_view.vadjustment;
            var list_height = _list_view.get_height ();
            if (_row_height > 0 && adj.upper - adj.lower > list_height) {
                var from = adj.value;
                var max_to = double.max ((index + 1) * _row_height - list_height, 0);
                var min_to = double.max (index * _row_height, 0);
                var scroll_to =  from < max_to ? max_to : (from > min_to ? min_to : from);
                var diff = (scroll_to - from).abs ();
                if (diff > list_height) {
                    _scroll_animation?.pause ();
                    adj.value = min_to;
                } else if (diff > 0) {
                    //  Scroll smoothly
                    var target = new Adw.CallbackAnimationTarget (adj.set_value);
                    _scroll_animation?.pause ();
                    _scroll_animation = new Adw.TimedAnimation (_scroll_view, from, scroll_to, 500, target);
                    _scroll_animation?.play ();
                } 
            } else if (visible_count > 0) {
#if GTK_4_10
                _list_view.activate_action_variant ("list.scroll-to-item", new Variant.uint32 (index));
#else
                //  Delay scroll if items not size_allocated, to ensure items visible in GNOME 42
                run_idle_once (() => scroll_to_item (index));
#endif
            }
        }

        private void on_create_item (Gtk.ListItem item) {
            var entry = new MusicEntry (_compact_list);
            item.child = entry;
            item_created (item);
            _row_height = entry.height_request + 2;
        }

        private void on_bind_item (Gtk.ListItem item) {
            var entry = (MusicEntry) item.child;
            var music = (Music) item.item;
            item_binded (item);

            var paintable = _thmbnailer.find (music);
            if (paintable != null) {
                entry.paintable = paintable;
            } else {
                entry.first_draw_handler = entry.cover.first_draw.connect (() => {
                    entry.disconnect_first_draw ();
                    _thmbnailer.load_async.begin (music, Thumbnailer.ICON_SIZE, (obj, res) => {
                        var paintable2 = _thmbnailer.load_async.end (res);
                        if (music == (Music) item.item) {
                            entry.paintable = paintable2;
                        }
                    });
                });
            }
        }

        private void on_unbind_item (Gtk.ListItem item) {
            var entry = (MusicEntry) item.child;
            entry.disconnect_first_draw ();
            entry.paintable = null;
        }

        private void on_vadjustment_changed () {
            var adj = _scroll_view.vadjustment;
            var range = adj.upper - adj.lower;
            var count = visible_count;
            if (count > 0 && _scroll_range != range && range > _list_view.get_height ()) {
                _row_height = range / count;
                _scroll_range = range;
            }
        }
    }
}