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
        private Music? _music_node = null;
        private Gtk.ScrolledWindow _scroll_view = new Gtk.ScrolledWindow ();
        private Gtk.MultiSelection _selection;
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

        public MusicList (Application app, Type item_type = typeof (Music), Music? node = null) {
            orientation = Gtk.Orientation.VERTICAL;
            hexpand = true;
            append (_scroll_view);

            _filter_model.model = _data_store;
            _item_type = item_type;
            _music_node = node;
            _thmbnailer = app.thumbnailer;
            update_store ();

            _selection = new Gtk.MultiSelection (_filter_model);
            _selection.selection_changed.connect (on_selection_changed);

            _grid_view.enable_rubberband = false;
            _grid_view.max_columns = 5;
            _grid_view.margin_start = 6;
            _grid_view.margin_end = 6;
            _grid_view.model = _selection;
            _grid_view.single_click_activate = true;
            _grid_view.activate.connect ((position) => item_activated (position, _filter_model.get_item (position)));
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
                _compact_list = value;
                if (_grid_view.get_factory () != null)
                    create_factory ();
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
                _grid_mode = value;
                _image_size = value ? Thumbnailer.GRID_SIZE : Thumbnailer.ICON_SIZE;
                if (_grid_view.get_factory () != null)
                    create_factory ();
            }
        }

        public Type item_type {
            get {
                return _item_type;
            }
        }

        private GenericArray<Gtk.Button> _action_buttons = new GenericArray<Gtk.Button> (4);
        private Gtk.Widget? _header_bar_hided = null;
        private Gtk.Revealer? _header_revealer = null;
        private Gtk.Label? _header_title = null;
        private bool _multi_selection = false;

        public bool multi_selection {
            get {
                return _multi_selection;
            }
            set {
                if (_multi_selection != value) {
                    _multi_selection = value;
                    _grid_view.enable_rubberband = value;
                    _grid_view.single_click_activate = !value;
                    if (!value)
                        _selection.unselect_all ();
                    if (_grid_view.get_factory () != null)
                        create_factory ();
                }
                if (value && _header_revealer == null) {
                    var child = get_first_child ();
                    if (child is Gtk.HeaderBar) {
                        _header_bar_hided = child;
                        remove ((!)child);
                    }
                    var header = new Gtk.HeaderBar ();
                    setup_selection_header_bar (header);
                    var revealer = new Gtk.Revealer ();
                    revealer.child = header;
                    revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
                    prepend (revealer);
                    _header_revealer = revealer;
                } else if (!value && _header_bar_hided != null) {
                    prepend ((!)_header_bar_hided);
                    _header_bar_hided = null;
                }
                _header_revealer?.set_reveal_child (value);
            }
        }

        public Music? music_node {
            get {
                return _music_node;
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

        public void activate_item (int item) {
            _grid_view.activate (item);
        }

        public void create_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect (on_create_item);
            factory.bind.connect (on_bind_item);
            factory.unbind.connect (on_unbind_item);
            _grid_view.factory = factory;
            _child_drawed = false;
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

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (_header_revealer?.reveal_child ?? false) {
                var child = (!)_header_revealer;
                draw_outset_shadow (snapshot, 0, 0, child.get_width (), child.get_height ());
            }
            base.snapshot (snapshot);
        }

        private Gtk.Label? _empty_label = null;

        public void set_empty_text (string? text) {
            if (_data_store.get_n_items () > 0 && _empty_label != null) {
                remove ((!)_empty_label);
                _empty_label = null;
            } else if (_data_store.get_n_items () == 0 && _empty_label == null) {
                _empty_label = new Gtk.Label (text);
                ((!)_empty_label).margin_top = 8;
                prepend ((!)_empty_label);
            }
        }

        public int set_to_current_item (bool scroll = true) {
            var item = find_item_in_model (_filter_model, _current_node);
            if (item != -1 && scroll)
                scroll_to_item (item);
            return item;
        }

        public uint update_store () {
            if (_music_node != null) {
                _data_store.remove_all ();
                if (_music_node is Album)
                    ((Album)_music_node).insert_to_store (_data_store);
                else if (_music_node is Artist)
                    ((Artist)_music_node).replace_to_store (_data_store);
            }
            return _data_store.get_n_items ();
        }

        private void on_create_item (Object obj) {
            var child = _grid_mode ? (MusicWidget) new MusicCell () : (MusicWidget) new MusicEntry (_compact_list);
            var item = (Gtk.ListItem) obj;
            item.child = child;
            item.selectable = _multi_selection;
            item_created (item);
            _row_width = item.child.width_request;
            make_long_pressable (child, (widget, x, y) => multi_selection = true);
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

        private void on_selection_changed (uint position, uint n_items) {
            var bits = _selection.get_selection ();
            _header_title?.set_label (@"$(bits.get_size ())/$(_filter_model.get_n_items ())");
            var enabled = !bits.is_empty ();
            foreach (var button in _action_buttons)
                button.sensitive = enabled;
        }

        private Playlist playlist_for_selection () {
            var count = _filter_model.get_n_items ();
            var items = new GenericArray<Music> (count);
            for (var i = 0; i < count; i++) {
                if (_selection.is_selected (i)) {
                    var node = _filter_model.get_item (i);
                    if (node is Artist) {
                        var artist = (Artist) node;
                        var playlist = artist.to_playlist ();
                        items.extend (playlist.items, (src) => src);
                    } else if (node is Album) {
                        var album = (Album) node;
                        album.foreach ((uri, music) => items.add (music));
                    } else {
                        items.add ((Music) node);
                    }
                }
            }
            return new Playlist (_music_node?.title ?? "Untitled", "", items);
        }

        private async void save_to_playlist_file_async (Playlist playlist) {
            var app = (Application) GLib.Application.get_default ();
            var filter = new Gtk.FileFilter ();
            filter.name = _("Playlist Files");
            filter.add_mime_type ("audio/x-mpegurl");
            filter.add_mime_type ("audio/x-scpls");
            filter.add_mime_type ("public.m3u-playlist");
            var file = yield show_save_file_dialog (app.active_window, playlist.title + ".m3u", {filter});
            if (file != null) {
                yield app.add_playlist_to_file_async (playlist, (!)file);
            }
        }

        private void setup_selection_header_bar (Gtk.HeaderBar header) {
            header.show_title_buttons = false;
            header.add_css_class ("flat");

            var title = new Gtk.Label (null);
            title.add_css_class ("dim-label");
            header.title_widget = title;
            _header_title = title;

            var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
            back_btn.clicked.connect (() => multi_selection = false);
            back_btn.tooltip_text = _("Back");
            header.pack_start (back_btn);

            var all_btn = new Gtk.Button.from_icon_name ("edit-select-all-symbolic");
            all_btn.tooltip_text = _("Select All");
            all_btn.clicked.connect (() => {
                if (_selection.get_selection ().get_size () == visible_count)
                    _selection.unselect_all ();
                else
                    _selection.select_all ();
            });
            header.pack_start (all_btn);

            if (_item_type == typeof (Music)) {
                var remove_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                remove_btn.tooltip_text = _("Remove");
                remove_btn.clicked.connect (() => {
                    var count = (int) _filter_model.get_n_items ();
                    for (var i = count - 1; i >= 0; i--) {
                        if (_selection.is_selected (i)) {
                            var node = _filter_model.get_item (i);
                            uint position = -1;
                            if (_data_store.find ((!)node, out position))
                                _data_store.remove (position);
                        }
                    }
                    on_selection_changed (0, 0);
                });
                header.pack_end (remove_btn);
                _action_buttons.add (remove_btn);
            }

            var insert_btn = new Gtk.Button.from_icon_name ("format-indent-more-symbolic");
            insert_btn.tooltip_text = _("Play at Next");
            insert_btn.clicked.connect (() => {
                var app = (Application) GLib.Application.get_default ();
                var playlist = playlist_for_selection ();
                var current = app.current_music;
                if (current != null)
                    playlist.foreach_remove ((uri, music) => music == (!)current);
                app.play_at_next (playlist);
            });
            header.pack_end (insert_btn);
            _action_buttons.add (insert_btn);

            var store = ((Application) GLib.Application.get_default ()).music_store;
            if (store != _data_store) {
                var send_btn = new Gtk.Button.from_icon_name ("document-send-symbolic");
                send_btn.tooltip_text = _("Add to Playing");
                send_btn.clicked.connect (() => {
                    var app = (Application) GLib.Application.get_default ();
                    var playlist = playlist_for_selection ();
                    app.play (playlist, false);
                });
                header.pack_end (send_btn);
                _action_buttons.add (send_btn);
            }

            var add_to_btn = new Gtk.Button.from_icon_name ("document-new-symbolic");
            add_to_btn.tooltip_text = _("Add to Playlist");
            add_to_btn.clicked.connect (() => {
                var playlist = playlist_for_selection ();
                save_to_playlist_file_async.begin (playlist, (obj, res) => save_to_playlist_file_async.end (res));
            });
            header.pack_end (add_to_btn);
            _action_buttons.add (add_to_btn);
        }
    }
}
