namespace G4 {

    public class MusicList : Gtk.Box {
        private HashTable<Music?, MusicWidget?> _binding_items = new HashTable<Music?, MusicWidget?> (direct_hash, direct_equal);
        private bool _compact_list = false;
        private Music? _current_node = null;
        private ListStore _data_store = new ListStore (typeof (Music));
        private Gtk.FilterListModel _filter_model = new Gtk.FilterListModel (null, null);
        private bool _grid_mode = false;
        private Gtk.GridView _grid_view = new Gtk.GridView (null, null);
        private int _image_size = Thumbnailer.ICON_SIZE;
        private Type _item_type = typeof (Music);
        private Music? _parent_node = null;
        private Gtk.ScrolledWindow _scroll_view = new Gtk.ScrolledWindow ();
        private Thumbnailer _thmbnailer;

        private bool _child_drawed = false;
        private uint _columns = 1;
        private uint _row_width = 0;
        private double _row_height = 0;
        private double _scroll_range = 0;
        private int _scrolling_item = -1;

        public signal void item_activated (uint position, Object? obj);
        public signal void item_created (Gtk.ListItem item);
        public signal void item_binded (Gtk.ListItem item);

        public MusicList (Application app, Type item_type = typeof (Music), Music? parent = null) {
            orientation = Gtk.Orientation.VERTICAL;
            hexpand = true;
            append (_scroll_view);

            _filter_model.model = _data_store;
            _item_type = item_type;
            _parent_node = parent;
            _thmbnailer = app.thumbnailer;
            update_store ();

            _grid_view.enable_rubberband = false;
            _grid_view.max_columns = 5;
            _grid_view.margin_start = 6;
            _grid_view.margin_end = 6;
            _grid_view.margin_top = 0;
            _grid_view.margin_bottom = 6;
            _grid_view.single_click_activate = true;
            _grid_view.activate.connect ((position) => item_activated (position, _filter_model.get_item (position)));
            _grid_view.model = new Gtk.NoSelection (_filter_model);
            _grid_view.add_css_class ("navigation-sidebar");

            _scroll_view.child = _grid_view;
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
                var factory = _grid_view.get_factory ();
                _compact_list = value;
                if (factory != null) {
                    create_factory ();
                }
            }
        }

        public Music? current_node {
            set {
                var cur = _binding_items[_current_node];
                if (cur != null)
                    ((!)cur).playing = false;
                _current_node = value;
                var widget = _binding_items[value];
                if (widget != null)
                    ((!)widget).playing = true;
            }
        }

        public ListStore data_store {
            get {
                return _data_store;
            }
            set {
                _data_store = value;
                _filter_model.model = value;
            }
        }

        public Gtk.FilterListModel filter_model {
            get {
                return _filter_model;
            }
        }

        public bool grid_mode {
            get {
                return _grid_mode;
            }
            set {
                var factory = _grid_view.get_factory ();
                _grid_mode = value;
                _image_size = value ? Thumbnailer.GRID_SIZE : Thumbnailer.ICON_SIZE;
                if (factory != null) {
                    create_factory ();
                }
            }
        }

        public Type item_type {
            get {
                return _item_type;
            }
        }

        public Music? parent_node {
            get {
                return _parent_node;
            }
        }

        public bool playable {
            get {
                return _item_type == typeof (Music);
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
            _child_drawed = false;
        }

        public void scroll_to_current_item () {
            var item = find_item_in_model (_filter_model, _current_node);
            if (item != -1)
                scroll_to_item (item);
        }

        private Adw.Animation? _scroll_animation = null;

        public void scroll_to_item (int index, bool smoothly = true) {
            var adj = _scroll_view.vadjustment;
            var list_height = _grid_view.get_height ();
            if (smoothly && _columns > 0 && _row_height > 0 && adj.upper - adj.lower > list_height) {
                var from = adj.value;
                var row = index / _columns;
                var max_to = double.max ((row + 1) * _row_height - list_height, 0);
                var min_to = double.max (row * _row_height, 0);
                var scroll_to =  from < max_to ? max_to : (from > min_to ? min_to : from);
                var diff = (scroll_to - from).abs ();
                var jump = diff > list_height;
                if (jump) {
                    // Jump to correct position first
                    scroll_to_item_directly (index);
                }
                //  Scroll smoothly
                var target = new Adw.CallbackAnimationTarget (adj.set_value);
                _scroll_animation?.pause ();
                _scroll_animation = new Adw.TimedAnimation (_scroll_view, adj.value, scroll_to, jump ? 50 : 500, target);
                _scroll_animation?.play ();
            } else {
                scroll_to_item_directly (index);
                // Hack: sometime show only first item if no child drawed, so scroll it when first draw an item
                _scrolling_item = _child_drawed ? -1 : index;
            }
        }

        public void scroll_to_item_directly (uint index) {
            _grid_view.activate_action_variant ("list.scroll-to-item", new Variant.uint32 (index));
        }

        public uint update_store () {
            if (_parent_node != null) {
                _data_store.remove_all ();
                if (_parent_node is Album)
                    ((Album)_parent_node).insert_to_store (_data_store);
                else if (_parent_node is Artist)
                    ((Artist)_parent_node).replace_to_store (_data_store);
            }
            return _data_store.get_n_items ();
        }

        private void on_create_item (Object obj) {
            var item = (Gtk.ListItem) obj;
            item.child = _grid_mode ? (MusicWidget) new MusicCell () : (MusicWidget) new MusicEntry (_compact_list);
            item.selectable = false;
            item_created (item);
            _row_width = item.child.width_request;
        }

        private void on_bind_item (Object obj) {
            var item = (Gtk.ListItem) obj;
            var entry = (MusicWidget) item.child;
            var music = (Music) item.item;
            entry.playing = music == _current_node;
            item_binded (item);

            _binding_items[music] = entry;

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
                    _child_drawed = true;
                    if (_scrolling_item != -1) {
                        scroll_to_item_directly (_scrolling_item);
                        _scrolling_item = -1;
                    }
                });
            }
        }

        private void on_unbind_item (Object obj) {
            var item = (Gtk.ListItem) obj;
            var entry = (MusicWidget) item.child;
            entry.disconnect_first_draw ();
            entry.paintable = null;
            _binding_items.remove (item.item as Music);
        }

        private void on_vadjustment_changed () {
            var adj = _scroll_view.vadjustment;
            var range = adj.upper - adj.lower;
            var count = visible_count;
            if (count > 0 && _row_width > 0 && _scroll_range != range && range > _grid_view.get_height ()) {
                var max_columns = _grid_view.get_max_columns ();
                var min_columns = _grid_view.get_min_columns ();
                var columns = _grid_view.get_width () / _row_width;
                _columns = uint.min (uint.max (columns, min_columns), max_columns);
                _row_height = range / ((count + _columns - 1) / _columns);
                _scroll_range = range;
            }
        }
    }
}
