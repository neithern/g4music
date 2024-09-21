namespace G4 {

    public class MusicList : Gtk.Box {
        protected Application _app;
        private HashTable<Music, Gtk.ListItem> _binding_items = new HashTable<Music, Gtk.ListItem> (direct_hash, direct_equal);
        private bool _compact_list = false;
        private Music? _current_node = null;
        private ListStore _data_store = new ListStore (typeof (Music));
        private bool _editable = false;
        private Gtk.FilterListModel _filter_model = new Gtk.FilterListModel (null, null);
        private bool _grid_mode = false;
        private Gtk.GridView _grid_view = new Gtk.GridView (null, null);
        private int _image_size = Thumbnailer.ICON_SIZE;
        private Type _item_type = typeof (Music);
        protected bool _modified = false;
        private Music? _music_node = null;

        private Gtk.ScrolledWindow _scroll_view = new Gtk.ScrolledWindow ();
        private Gtk.MultiSelection _selection;
        private Thumbnailer _thmbnailer;

        private bool _child_drawed = false;
        private uint _columns = 1;
        private uint _row_min_width = 0;
        private double _row_height = 0;
        private double _scroll_range = 0;
        private int _scrolling_item = -1;

        public signal void item_activated (uint position, Object? obj);
        public signal void item_binded (Gtk.ListItem item);
        public signal void item_created (Gtk.ListItem item);

        public MusicList (Application app, Type item_type = typeof (Music), Music? node = null, bool editable = false) {
            orientation = Gtk.Orientation.VERTICAL;
            hexpand = true;
            append (_scroll_view);

            _app = app;
            _editable = editable;
            _filter_model.model = _data_store;
            _item_type = item_type;
            _music_node = node;
            _thmbnailer = app.thumbnailer;

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

            update_store ();
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
                var cur = get_binding_widget (_current_node);
                if (cur != null)
                    ((!)cur).playing.visible = false;
                _current_node = value;
                var widget = get_binding_widget (value);
                if (widget != null)
                    ((!)widget).playing.visible = true;
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

        public bool modified {
            get {
                return _modified;
            }
            set {
                _modified = value;
            }
        }

        protected bool _has_add_to_quque = true;
        protected bool _prompt_to_save = true;
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
                    var movable = _editable && value;
                    _binding_items.foreach ((music, item) => {
                        item.selectable = value;
                        ((MusicWidget) item.child).handle.visible = movable;
                    });
                    if (!value)
                        _selection.unselect_all ();
                }
                if (value && _header_revealer == null) {
                    _header_bar_hided = get_first_child () as Gtk.HeaderBar;
                    var header = new Gtk.HeaderBar ();
                    setup_selection_header_bar (header);
                    var revealer = new Gtk.Revealer ();
                    revealer.child = header;
                    revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
                    revealer.insert_after (this, _header_bar_hided);
                    _header_revealer = revealer;
                }
                if (value && _editable && _drop_target == null) {
                    _drop_target = create_drop_target ();
                    _grid_view.add_controller ((!)_drop_target);
                } else if (!value && _drop_target != null) {
                    _grid_view.remove_controller ((!)_drop_target);
                    _drop_target = null;
                }
                _header_bar_hided?.set_visible (!value);
                _header_revealer?.set_reveal_child (value);
                if (value)
                    on_selection_changed (0, 0);
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
                var allocation = Gtk.Allocation ();
                get_widget_bounds (child, ref allocation);
                draw_outset_shadow (snapshot, allocation.x, allocation.y, allocation.width, allocation.height);
            }
            if (_dropping_item >= 0) {
                var allocation = Gtk.Allocation ();
                get_widget_bounds (_scroll_view, ref allocation);
                var row_width = (float) _grid_view.get_width () / _columns;
                var col = _dropping_item % _columns;
                var row = _dropping_item / _columns;
                var x = row_width * col + allocation.x + _grid_view.margin_start;
                var y = _row_height * row + allocation.y + _grid_view.margin_top - _scroll_view.vadjustment.value;
                var rect = Graphene.Rect ();
                rect.init (x, (float) y, row_width, scale_factor * 0.5f);
                var color = Gdk.RGBA ();
                color.alpha = 1f;
                color.red = color.green = color.blue = 0.5f;
                snapshot.append_color (color, rect);
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

        private Menu? on_create_music_menu (Music? node) {
            select_one_item (node);
            if (node is Album) {
                return create_menu_for_album ((Album) node);
            } else if (node is Artist) {
                return create_menu_for_artist ((Artist) node);
            } else if (node is Music) {
                var music = (Music) node;
                var menu = create_menu_for_music (music);
                if (music != _app.current_music) {
                    if (_has_add_to_quque)
                        menu.prepend_item (create_menu_item_for_uri (music.uri, _("Add to Queue"), ACTION_APP + ACTION_ADD_TO_QUEUE));
                    /* Translators: Play this music at next position of current playing music */
                    menu.prepend_item (create_menu_item_for_uri (music.uri, _("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
                }
                if (music.cover_uri != null) {
                    menu.append_item (create_menu_item_for_uri ((!)music.cover_uri, _("Show _Cover File"), ACTION_APP + ACTION_SHOW_FILE));
                } else if (_app.thumbnailer.find (music) is Gdk.Texture) {
                    menu.append_item (create_menu_item_for_uri (music.uri, _("_Export Cover"), ACTION_APP + ACTION_EXPORT_COVER));
                }
                return menu;
            }
            return null;
        }

        private void on_create_item (Object obj) {
            var child = _grid_mode ? (MusicWidget) new MusicCell () : (MusicWidget) new MusicEntry (_compact_list);
            var item = (Gtk.ListItem) obj;
            item.child = child;
            item.selectable = _multi_selection;
            item_created (item);
            _row_min_width = item.child.width_request;

            child.create_music_menu.connect (on_create_music_menu);
            make_right_clickable (child, child.show_popover_menu);
            make_long_pressable (child, (widget, x, y) => multi_selection = true);
            if (_editable)
                make_draggable (child.handle, child, item);
        }

        private void on_bind_item (Object obj) {
            var item = (Gtk.ListItem) obj;
            var entry = (MusicWidget) item.child;
            var music = (Music) item.item;
            entry.handle.visible = _multi_selection && _editable;
            entry.playing.visible = music == _current_node;
            item_binded (item);
            _binding_items[music] = item;

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
            _binding_items.remove ((Music) item.item);
        }

        private void on_vadjustment_changed () {
            var adj = _scroll_view.vadjustment;
            var range = adj.upper - adj.lower;
            var count = visible_count;
            if (count > 0 && _row_min_width > 0 && _scroll_range != range && range > _grid_view.get_height ()) {
                var max_columns = _grid_view.get_max_columns ();
                var min_columns = _grid_view.get_min_columns ();
                var columns = _grid_view.get_width () / _row_min_width;
                _columns = uint.min (uint.max (columns, min_columns), max_columns);
                _row_height = range / ((count + _columns - 1) / _columns);
                _scroll_range = range;
            }
        }

        private int _dropping_item = -1;

        private bool on_drag_dropped (Value value, double x, double y) {
            var item = value.get_object () as Gtk.ListItem;
            uint src_pos = item?.position ?? -1;
            uint dst_pos = _dropping_item;
            if (src_pos != -1 && dst_pos != -1 && src_pos != dst_pos) {
                var selected = _selection.is_selected (src_pos);
                var src_obj = _filter_model.get_item (src_pos);
                var dst_obj = _filter_model.get_item (dst_pos);
                if (src_obj != null && _data_store.find ((!)src_obj, out src_pos)) {
                    if (dst_obj == null || !_data_store.find ((!)dst_obj, out dst_pos))
                        dst_pos = _data_store.get_n_items ();
                    _data_store.remove (src_pos);
                    if (dst_pos >= src_pos)
                        dst_pos--;
                    _data_store.insert (dst_pos, (!)src_obj);
                    _modified = true;
                }
                if (selected)
                    _selection.select_item (_dropping_item, false);
            }
            set_dropping_item (-1);
            return true;
        }

        private Gdk.DragAction on_drag_motion (double x, double y) {
            var row_width = (double) _grid_view.get_width () / _columns;
            var col = (int) (x / row_width);
            var row = (int) ((_scroll_view.vadjustment.value + y) / _row_height);
            var item = (int) _columns * row + col;
            set_dropping_item (item);
            return Gdk.DragAction.MOVE;
        }

        private MusicWidget? get_binding_widget (Music? music) {
            var item = music != null ? _binding_items[(!)music] : (Gtk.ListItem?) null;
            return item?.child as MusicWidget;
        }

        private void make_draggable (Gtk.Widget handle, Gtk.Widget icon, Gtk.ListItem item) {
            var drag_source = new Gtk.DragSource ();
            drag_source.actions = Gdk.DragAction.MOVE;
            drag_source.prepare.connect ((x, y) => {
                select_one_item (((MusicWidget) item.child).music);
                if (item.selectable) {
                    var val = Value (item.get_type ());
                    val.set_object (item);
                    return new Gdk.ContentProvider.for_value (val);
                }
                return null;
            });
            drag_source.drag_begin.connect ((drag) => {
                var allocation = Gtk.Allocation ();
                var paintable = new Gtk.WidgetPaintable (icon);
                get_widget_bounds (handle, ref allocation);
                drag_source.set_icon (paintable, allocation.x, allocation.y);
            });
            handle.add_controller (drag_source);
        }

        private void set_dropping_item (int item) {
            if (_dropping_item != item) {
                _dropping_item = item;
                queue_draw ();
            }
        }

        private Gtk.DropTarget? _drop_target = null;

        private Gtk.DropTarget create_drop_target () {
            var target = new Gtk.DropTarget (typeof (Gtk.ListItem), Gdk.DragAction.MOVE);
            target.accept.connect ((drop) => drop.formats.contain_gtype (typeof (Gtk.ListItem)));
            target.motion.connect (on_drag_motion);
            target.leave.connect (() => set_dropping_item (-1));
#if GTK_4_10
            target.drop.connect (on_drag_dropped);
#else
            target.on_drop.connect (on_drag_dropped);
#endif
            return target;
        }

        private void on_selection_changed (uint position, uint n_items) {
            var bits = _selection.get_selection ();
            _header_title?.set_label (@"$(bits.get_size ())/$(_filter_model.get_n_items ())");
            var enabled = !bits.is_empty ();
            foreach (var button in _action_buttons)
                button.sensitive = enabled;
        }

        protected Playlist create_playlist_for_selection () {
            var count = _filter_model.get_n_items ();
            var musics = new GenericArray<Music> (count);
            for (var i = 0; i < count; i++) {
                if (_selection.is_selected (i))
                    musics.add ((Music) _filter_model.get_item (i));
            }
            return to_playlist (musics.data, _music_node?.title);
        }

        private async bool prompt_to_save_playlist () {
            if (_music_node is Playlist) {
                var playlist = new Playlist (_music_node?.title ?? "Untitled");
                playlist.list_uri = ((Playlist)_music_node).list_uri;

                var count = _data_store.get_n_items ();
                for (var i = 0; i < count; i++) {
                    var music = (Music) _data_store.get_item (i);
                    playlist.add_music (music);
                }

                var ret = yield show_alert_dialog (_("Playlist is modified, save it?"), root as Gtk.Window);
                if (ret) {
                    ret |= yield _app.add_playlist_to_file_async (playlist, false);
                }
                return ret;
            }
            return false;
        }

        private void select_one_item (Music? node) {
            var item = find_item_in_model (_filter_model, node);
            if (item != -1)
                _selection.select_item (item, true);
        }

        private void setup_selection_header_bar (Gtk.HeaderBar header) {
            header.show_title_buttons = false;
            header.add_css_class ("flat");

            var title = new Gtk.Label (null);
            title.add_css_class ("dim-label");
            header.title_widget = title;
            _header_title = title;

            var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
            back_btn.clicked.connect (() => {
                if (_modified && _prompt_to_save) {
                    prompt_to_save_playlist.begin ((obj, res) => {
                        if (prompt_to_save_playlist.end (res))
                            _modified = false;
                        multi_selection = false;
                    });
                } else {
                    multi_selection = false;
                }
            });
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

            if (_editable) {
                var remove_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                remove_btn.tooltip_text = _("Remove");
                remove_btn.clicked.connect (() => {
                    var count = (int) _filter_model.get_n_items ();
                    var to_removed = new GenericSet<uint> (null, null);
                    for (var i = 0; i < count; i++) {
                        if (_selection.is_selected (i)) {
                            var node = _filter_model.get_item (i);
                            uint position = -1;
                            if (_data_store.find ((!)node, out position))
                                to_removed.add (position);
                        }
                    }
                    if (to_removed.length > 0) {
                        var size = (int) _data_store.get_n_items ();
                        var items = new GenericArray<Music> (size);
                        for (var i = 0; i < size; i++) {
                            if (!to_removed.contains (i)) {
                                var node = _data_store.get_item (i);
                                items.add ((Music) node);
                            }
                        }
                        _data_store.splice (0, size, items.data);
                        _modified = true;
                    }
                    on_selection_changed (0, 0);
                });
                _action_buttons.add (remove_btn);
            }

            var insert_btn = new Gtk.Button.from_icon_name ("format-indent-more-symbolic");
            insert_btn.tooltip_text = _("Play at Next");
            insert_btn.clicked.connect (() => {
                var playlist = create_playlist_for_selection ();
                var current = _app.current_music;
                if (current != null)
                    playlist.foreach_remove ((uri, music) => music == (!)current);
                    _app.play_at_next (playlist);
            });
            _action_buttons.add (insert_btn);

            if (_has_add_to_quque) {
                var send_btn = new Gtk.Button.from_icon_name ("document-send-symbolic");
                send_btn.tooltip_text = _("Add to Queue");
                send_btn.clicked.connect (() => {
                    var app = (Application) GLib.Application.get_default ();
                    var playlist = create_playlist_for_selection ();
                    app.queue (playlist, false);
                });
                _action_buttons.add (send_btn);
            }

            var add_to_btn = new Gtk.Button.from_icon_name ("document-new-symbolic");
            add_to_btn.tooltip_text = _("Add to Playlist");
            add_to_btn.clicked.connect (() => {
                var playlist = create_playlist_for_selection ();
                _app.show_add_playlist_dialog.begin (playlist, (obj, res) => _app.show_add_playlist_dialog.end (res));
            });
            _action_buttons.add (add_to_btn);

            _action_buttons.foreach (header.pack_end);
        }
    }

    public class MainMusicList : MusicList {
        public MainMusicList (Application app) {
            base (app, typeof (Music), null, true);
            _has_add_to_quque = false;
            _prompt_to_save = false;
        }

        public async bool save_if_modified () {
            if (_modified) {
                var file = get_playing_list_file ();
                var store = data_store;
                var count = store.get_n_items ();
                var uris = new GenericArray<string> (count);
                for (var i = 0; i < count; i++) {
                    var music = (Music) store.get_item (i);
                    uris.add (music.uri);
                }
                var ret = yield run_async<bool> (() => save_playlist_file (file, uris));
                if (ret)
                    _modified = false;
            }
            return !_modified;
        }
    }

    public void get_widget_bounds (Gtk.Widget widget, ref Gtk.Allocation allocation) {
#if GTK_4_10
        widget.get_bounds (out allocation.x, out allocation.y, out allocation.width, out allocation.height);
#else
        widget.get_allocation (out allocation);
#endif
    }
}
