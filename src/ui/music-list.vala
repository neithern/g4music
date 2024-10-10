namespace G4 {

    public enum Result {
        CANCEL = -1,
        FAILED = 0,
        OK = 1
    }

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
        private bool _selectable = false;
        private bool _single_click_activate = true;
        private Gtk.MultiSelection _selection;
        private Thumbnailer _thmbnailer;

        private uint _columns = 0;
        private Graphene.Size _cell_size = Graphene.Size ();
        private Graphene.Size _item_size = Graphene.Size ();
        private int _scrolling_item = -1;

        public signal void item_activated (uint position, Object? obj);
        public signal void item_binded (Gtk.ListItem item);
        public signal void item_created (Gtk.ListItem item);
        public signal void item_unbinded (Gtk.ListItem item);

        public MusicList (Application app, Type item_type = typeof (Music), Music? node = null, bool editable = false, bool selectable = true) {
            orientation = Gtk.Orientation.VERTICAL;
            hexpand = true;

            _app = app;
            _editable = editable;
            _filter_model.model = _data_store;
            _item_type = item_type;
            _music_node = node;
            _selectable = selectable;
            _thmbnailer = app.thumbnailer;

            _grid_view.max_columns = 5;
            _grid_view.margin_start = 6;
            _grid_view.margin_end = 6;
            _grid_view.model = _selection = new Gtk.MultiSelection (_filter_model);
            _grid_view.activate.connect ((position) => item_activated (position, _filter_model.get_item (position)));
            _grid_view.add_css_class ("navigation-sidebar");
            _selection.selection_changed.connect (on_selection_changed);
            create_factory ();
            update_grid_view ();

            _scroll_view.child = _grid_view;
            _scroll_view.hscrollbar_policy = Gtk.PolicyType.NEVER;
            _scroll_view.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            _scroll_view.propagate_natural_height = true;
            _scroll_view.vexpand = true;
            append (_scroll_view);

            if (editable || item_type == typeof (Playlist)) {
                create_drop_target (_grid_view);
            }

            print (@"MusicList created: $(++_instance_count)\n");
        }
        private static int _instance_count = 0;
        ~MusicList () {
            print (@"MusicList destroyed: $(--_instance_count)\n");
        }

        public bool compact_list {
            get {
                return _compact_list;
            }
            set {
                if (_compact_list != value) {
                    _compact_list = value;
                    create_factory ();
                }
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

        public int dropping_item {
            get {
                return _dropping_item;
            }
            set {
                if (_dropping_item != value) {
                    _dropping_item = value;
                    queue_draw ();
                }
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
                _image_size = value ? Thumbnailer.GRID_SIZE : Thumbnailer.ICON_SIZE;
                if (_grid_mode != value) {
                    _grid_mode = value;
                    create_factory ();
                }
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

        protected bool _has_add_to_queque = true;
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
                if (value && _header_revealer == null) {
                    var child = get_first_child ();
                    _header_bar_hided = child != _scroll_view ? child : null;
                    var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                    setup_selection_header_bar (header);
                    var revealer = new Gtk.Revealer ();
                    revealer.child = header;
                    revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
                    revealer.insert_after (this, _header_bar_hided);
                    _header_revealer = revealer;
                }
                _header_bar_hided?.set_visible (!value);
                _header_revealer?.set_reveal_child (value);

                if (_multi_selection != value) {
                    _multi_selection = value;
                    update_grid_view ();
                    if (value)
                        on_selection_changed (0, 0);
                    else
                        _selection.unselect_all ();
                }
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

        public bool single_click_activate {
            get {
                return _single_click_activate;
            }
            set {
                if (_single_click_activate != value) {
                    _single_click_activate = value;
                    update_grid_view ();
                }
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

        public void button_command (string name) {
            var playlist = create_playlist_for_selection ();
            switch (name) {
                case Button.ADDTO:
                    _app.show_add_playlist_dialog.begin (playlist, (obj, res) => _app.show_add_playlist_dialog.end (res));
                    break;

                case Button.INSERT:
                    _app.insert_after_current (playlist);
                    break;

                case Button.QUEUE:
                    _app.insert_to_queue (playlist);
                    break;

                case Button.REMOVE:
                    modified |= remove_items_from_store (_data_store, playlist.items) != 0;
                    on_selection_changed (0, 0);
                    break;
            }
        }

        public void create_factory () {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect (on_create_item);
            factory.bind.connect (on_bind_item);
            factory.unbind.connect (on_unbind_item);
            _grid_view.factory = factory;
        }

        public virtual async Result save_if_modified (bool prompt = true) {
            if (_modified && _music_node is Playlist) {
                var pls = (Playlist) _music_node;
                var playlist = new Playlist (pls.title, pls.list_uri);
                var items = playlist.items;
                var count = _data_store.get_n_items ();
                for (var i = 0; i < count; i++) {
                    var music = (Music) _data_store.get_item (i);
                    items.add (music);
                }

                var ret = !prompt || yield show_alert_dialog (_("Playlist is modified, save it?"), root as Gtk.Window);
                if (ret) {
                    ret = yield _app.add_playlist_to_file_async (playlist, false);
                    modified = !ret;
                    return ret ? Result.OK : Result.FAILED;
                }
                update_store ();
                modified = false;
            }
            return _modified ? Result.CANCEL : Result.OK;
        }

        private Adw.Animation? _scroll_animation = null;

        public void scroll_to_item (int index, bool smoothly = true) {
            var adj = _scroll_view.vadjustment;
            var list_height = _grid_view.get_height ();
            _columns = get_grid_view_item_size (_grid_view, ref _item_size, ref _cell_size);
            if (smoothly && _columns > 0 && _cell_size.height > 0 && adj.upper - adj.lower > list_height) {
                var from = adj.value;
                var row = index / _columns;
                var max_to = double.max ((row + 1) * _cell_size.height - list_height, 0);
                var min_to = double.max (row * _cell_size.height, 0);
                var scroll_to =  from < max_to ? max_to : (from > min_to ? min_to : from);
                var diff = (scroll_to - from).abs ();
                var jump = diff > list_height;
                if (jump) {
                    // Jump to correct position first
                    scroll_to_directly (index);
                }
                //  Scroll smoothly
                var target = new Adw.CallbackAnimationTarget (adj.set_value);
                _scroll_animation?.pause ();
                _scroll_animation = new Adw.TimedAnimation (_scroll_view, adj.value, scroll_to, jump ? 50 : 500, target);
                _scroll_animation?.play ();
            } else {
                scroll_to_directly (index);
                // Hack: sometime show only first item if no child drawed, so scroll it when first draw an item
                _scrolling_item = _columns > 0 ? -1 : index;
            }
        }

        public void scroll_to_directly (uint index) {
#if GTK_4_12
            _grid_view.scroll_to (index, Gtk.ListScrollFlags.NONE, null);
#else
            _grid_view.activate_action_variant ("list.scroll-to-item", new Variant.uint32 (index));
#endif
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (_header_revealer?.reveal_child ?? false) {
                var child = (!)_header_revealer;
                var rect = Graphene.Rect ();
                child.compute_bounds (this, out rect);
                draw_outset_shadow (snapshot, rect);
            }

            var rc_grid = Graphene.Rect ();
            if (_editable && _columns > 0 && _dropping_item >= 0 && _grid_view.compute_bounds (this, out rc_grid)) {
                var row = _dropping_item / _columns;
                var col = _dropping_item - _columns * row;
                var rc_cell = Graphene.Rect ();
                rc_cell.init (_cell_size.width * col, _cell_size.height * row, _cell_size.width, _cell_size.height);
                rc_cell.offset (rc_grid.origin.x, rc_grid.origin.y);
                rc_cell.origin.y -= (float) _scroll_view.vadjustment.value;
                rc_cell.size.height = 2;
#if ADW_1_6
                var color = Adw.StyleManager.get_for_display (get_display ())
                                        .get_accent_color ().to_rgba ();
#else
                var color = Gdk.RGBA ();
                color.alpha = 1;
                color.red = color.green = color.blue = 0.5f;
#endif
                snapshot.append_color (color, rc_cell);
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

        public void update_item_cover (Music music, Gdk.Paintable paintable) {
            var item = _binding_items[music];
            if (item is Gtk.ListItem) {
                item_unbinded (item);
                item_binded (item);
                var widget = item.child as MusicWidget;
                if (widget != null)
                    ((!)widget).paintable = paintable;
            }
        }

        public uint update_store () {
            if (_music_node is Playlist) {
                ((Playlist) _music_node).overwrite_to (_data_store);
            } else if (_music_node is Album) {
                ((Album) _music_node).overwrite_to (_data_store);
            } else if (_music_node is Artist) {
                ((Artist) _music_node).overwrite_store (_data_store);
            }
            return _data_store.get_n_items ();
        }

        private Menu? on_create_music_menu (Music? node) {
            int position = -1;
            if (_multi_selection && (position = find_item_in_model (_filter_model, node)) != -1) {
                _selection.select_item (position, false);
            }
            if (_selection.get_selection ().get_size () > 1) {
                var action = ACTION_WIN + ACTION_BUTTON;
                var menu = new Menu ();
                menu.append_item (create_menu_item_for_button (Button.INSERT, _("Play at _Next"), action));
                if (_has_add_to_queque)
                    menu.append_item (create_menu_item_for_button (Button.QUEUE, _("Add to _Queue"), action));
                menu.append_item (create_menu_item_for_button (Button.ADDTO, _("Add to _Playlist…"), action));
                menu.append_item (create_menu_item_for_button (Button.REMOVE, _("_Remove"), action));
                return menu;
            } else if (node is Album) {
                return create_menu_for_album ((Album) node);
            } else if (node is Artist) {
                return create_menu_for_artist ((Artist) node);
            } else if (node is Music) {
                var music = (Music) node;
                unowned var uri = music.uri;
                var menu = create_menu_for_music (music, _app.thumbnailer.find (music) is Gdk.Texture);
                if (music != _app.current_music) {
                    /* Translators: Play this music at next position of current playing music */
                    menu.insert_item (0, create_menu_item_for_uri (uri, _("Play at _Next"), ACTION_APP + ACTION_PLAY_AT_NEXT));
                    if (_has_add_to_queque)
                        menu.insert_item (1, create_menu_item_for_uri (uri, _("Add to _Queue"), ACTION_APP + ACTION_ADD_TO_QUEUE));
                }
                if (_editable) {
                    var section = new Menu ();
                    section.append_item (create_menu_item_for_uri (uri, _("_Remove"), ACTION_WIN + ACTION_REMOVE));
                    section.append_item (create_menu_item_for_uri (uri, _("_Move to Trash"), ACTION_APP + ACTION_TRASH_FILE));
                    menu.append_section (null, section);
                }
                return menu;
            }
            return null;
        }

        private void on_create_item (Object obj) {
            var child = _grid_mode ? (MusicWidget) new MusicCell () : (MusicWidget) new MusicEntry (_compact_list);
            var item = (Gtk.ListItem) obj;
            item.child = child;
            item.selectable = _multi_selection || !_single_click_activate;
            item_created (item);

            if (_selectable) {
                create_drag_source (child.image, item);
                child.create_music_menu.connect (on_create_music_menu);
                make_right_clickable (child, child.show_popover_menu);
                make_long_pressable (child, (widget, x, y) => multi_selection = true);
            }
        }

        private void on_bind_item (Object obj) {
            var item = (Gtk.ListItem) obj;
            var child = (MusicWidget) item.child;
            var music = (Music) item.item;
            child.playing.visible = music == _current_node;
            item_binded (item);
            _binding_items[music] = item;

            var paintable = _thmbnailer.find (music, _image_size);
            if (paintable != null) {
                child.paintable = paintable;
            } else {
                child.first_draw_handler = child.cover.first_draw.connect (() => {
                    child.disconnect_first_draw ();
                    _thmbnailer.load_async.begin (music, _image_size, (obj, res) => {
                        var paintable2 = _thmbnailer.load_async.end (res);
                        if (music == (Music) item.item) {
                            child.paintable = paintable2;
                        }
                    });
                    if (_scrolling_item != -1) {
                        scroll_to_directly (_scrolling_item);
                        _scrolling_item = -1;
                    }
                });
            }
        }

        private void on_unbind_item (Object obj) {
            var item = (Gtk.ListItem) obj;
            var child = (MusicWidget) item.child;
            child.paintable = null;
            child.disconnect_first_draw ();
            item_unbinded (item);
            _binding_items.remove ((Music) item.item);
        }

        private void on_drag_begin (Gtk.DragSource source, Gdk.Drag drag, Gtk.Widget widget, Graphene.Point point) {
            var size = _selection.get_selection ().get_size ();
            var title = size > 1 ? size.to_string () : (string) null;
            source.set_icon (create_widget_paintable (widget, ref point, title), (int) point.x, (int) point.y);
        }

        private Gdk.ContentProvider? on_drag_prepare (Music? music) {
            var position = find_item_in_model (_filter_model, music);
            if (position != -1)
                _selection.select_item (position, false);

            var playlist = create_playlist_for_selection ();
            return create_content_provider (playlist);
        }

        private int _dropping_item = -1;

        private bool on_drop_done (Value value, double x, double y) {
            if (_editable) {
                uint position = uint.min (_dropping_item, visible_count);
                if (value.holds (typeof (Playlist))) {
                    var dst_obj = _filter_model.get_item (position);
                    if (dst_obj == null || !_data_store.find ((!)dst_obj, out position))
                        position = _data_store.get_n_items ();
                    var playlist = (Playlist) value.get_object ();
                    modified |= merge_items_to_store (_data_store, playlist.items, ref position);
                } else {
                    var files = get_dropped_files (value);
                    _app.open_files_async.begin (files, position, false,
                                                (obj, res) => modified |= _app.open_files_async.end (res));
                }
            }
            dropping_item = -1;
            return true;
        }

        private uint _activate_handle = 0;

        private Gdk.DragAction on_drop_motion (double x, double y) {
            _columns = get_grid_view_item_size (_grid_view, ref _item_size, ref _cell_size);
            var col = (int) (x / _cell_size.width);
            var row = (int) ((y + _scroll_view.vadjustment.value) / _cell_size.height);
            var index = (int) _columns * row + col;
            if (_dropping_item != index && _filter_model.get_item (index) is Playlist) {
                if (_activate_handle != 0)
                    Source.remove (_activate_handle);
                _activate_handle = run_timeout_once (1000, () => {
                    _activate_handle = 0;
                    if (_dropping_item == index)
                        _grid_view.activate (index);
                });
            }
            dropping_item = int.min (index, (int) visible_count);
            return Gdk.DragAction.LINK;
        }

        private MusicWidget? get_binding_widget (Music? music) {
            var item = music != null ? _binding_items[(!)music] : (Gtk.ListItem?) null;
            return item?.child as MusicWidget;
        }

        private static void create_drag_source (Gtk.Widget widget, Gtk.ListItem item) {
            //  Hack: don't use `this` directly, because it will not be destroyed when detach???
            var point = Graphene.Point ();
            var source = new Gtk.DragSource ();
            source.actions = Gdk.DragAction.LINK;
            source.drag_begin.connect ((drag) => {
                var list = find_ancestry_with_type (widget, typeof (MusicList));
                (list as MusicList)?.on_drag_begin (source, drag, widget, point);
            });
            source.prepare.connect ((x, y) => {
                point.init ((float) x, (float) y);
                var list = find_ancestry_with_type (widget, typeof (MusicList));
                return (list as MusicList)?.on_drag_prepare (item.item as Music);
            });
            widget.add_controller (source);
        }

        private void create_drop_target (Gtk.Widget widget) {
            var target = new Gtk.DropTarget (Type.INVALID, Gdk.DragAction.COPY | Gdk.DragAction.LINK);
            target.set_gtypes ({ typeof (Playlist), typeof (Gdk.FileList) });
            target.accept.connect ((drop) => drop.formats.contain_gtype (typeof (Playlist))
                                || drop.formats.contain_gtype (typeof (Gdk.FileList)));
            target.motion.connect (on_drop_motion);
            target.leave.connect (() => run_timeout_once (100, () => dropping_item = -1));
#if GTK_4_10
            target.drop.connect (on_drop_done);
#else
            target.on_drop.connect (on_drop_done);
#endif
            widget.add_controller (target);
        }

        private Playlist create_playlist_for_selection () {
            var count = _filter_model.get_n_items ();
            var musics = new GenericArray<Music> (count);
            for (var i = 0; i < count; i++) {
                if (_selection.is_selected (i))
                    musics.add ((Music) _filter_model.get_item (i));
            }
            return to_playlist (musics.data, _music_node?.title);
        }

        private uint _remove_selection_handle = 0;

        private void on_selection_changed (uint position, uint n_items) {
            var bits = _selection.get_selection ();
            var selected = bits.get_size ();
            if (selected > 1)
                multi_selection = true;
            _header_title?.set_label (@"$selected/$visible_count");

            var enabled = selected > 0;
            foreach (var button in _action_buttons)
                button.sensitive = enabled;

            if (_remove_selection_handle != 0)
                Source.remove (_remove_selection_handle);
            _remove_selection_handle = run_timeout_once (3000, () => {
                _remove_selection_handle = 0;
                if (!_multi_selection && bits.get_size () == 1)
                    _selection.unselect_item (bits.get_minimum ());
            });
        }

        private void setup_selection_header_bar (Gtk.Box header) {
            header.hexpand = true;
            header.add_css_class ("flat");
            header.add_css_class ("toolbar");

            var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
            back_btn.clicked.connect (() => {
                if (_modified && _prompt_to_save) {
                    save_if_modified.begin (true, (obj, res) => {
                        var ret = save_if_modified.end (res);
                        if (ret != Result.FAILED) {
                            modified = false;
                            multi_selection = false;
                        }
                    });
                } else {
                    multi_selection = false;
                }
            });
            back_btn.tooltip_text = _("Back");
            header.append (back_btn);

            var all_btn = new Gtk.Button.from_icon_name ("edit-select-all-symbolic");
            all_btn.tooltip_text = _("Select All");
            all_btn.clicked.connect (() => {
                if (_selection.get_selection ().get_size () == visible_count)
                    _selection.unselect_all ();
                else
                    _selection.select_all ();
            });
            header.append (all_btn);

            var title = new Gtk.Label (null);
            title.add_css_class ("dim-label");
            title.halign = Gtk.Align.CENTER;
            title.hexpand = true;
            header.append (title);
            _header_title = title;

            var insert_btn = new Gtk.Button.from_icon_name ("format-indent-more-symbolic");
            insert_btn.tooltip_text = _("Play at Next");
            insert_btn.clicked.connect (() => button_command (Button.INSERT));
            insert_btn.name = Button.INSERT;
            _action_buttons.add (insert_btn);

            if (_has_add_to_queque) {
                var queue_btn = new Gtk.Button.from_icon_name ("document-send-symbolic");
                queue_btn.tooltip_text = _("Add to Queue");
                queue_btn.clicked.connect (() => button_command (Button.QUEUE));
                queue_btn.name = Button.QUEUE;
                _action_buttons.add (queue_btn);
            }

            var addto_btn = new Gtk.Button.from_icon_name ("document-new-symbolic");
            addto_btn.tooltip_text = _("Add to Playlist");
            addto_btn.clicked.connect (() => button_command (Button.ADDTO));
            addto_btn.name = Button.ADDTO;
            _action_buttons.add (addto_btn);

            if (_editable) {
                var remove_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                remove_btn.tooltip_text = _("Remove");
                remove_btn.clicked.connect (() => button_command (Button.REMOVE));
                remove_btn.name = Button.REMOVE;
                _action_buttons.add (remove_btn);
            }

            _action_buttons.foreach (header.append);
        }

        private void update_grid_view () {
            var enable = _multi_selection || !_single_click_activate;
            _grid_view.enable_rubberband = enable;
            _grid_view.single_click_activate = !enable;
            _binding_items.foreach ((music, item) => item.selectable = enable);
        }
    }

    public class MainMusicList : MusicList {
        public MainMusicList (Application app) {
            base (app, typeof (Music), null, true);
            _has_add_to_queque = false;
            _prompt_to_save = false;
        }

        public override async Result save_if_modified (bool prompt = true) {
            if (_modified) {
                var file = get_playing_list_file ();
                var store = data_store;
                var count = store.get_n_items ();
                var uris = new GenericArray<string> (count);
                for (var i = 0; i < count; i++) {
                    var music = (Music) store.get_item (i);
                    uris.add (music.uri);
                }
                var ret = yield run_async<bool> (() => save_playlist_file (file, uris, null, false), false, true);
                modified = !ret;
                return ret ? Result.OK : Result.FAILED;
            }
            return Result.OK;
        }
    }

    public Gdk.ContentProvider create_content_provider (Playlist playlist) {
        var val = Value (typeof (Playlist));
        val.set_object (playlist);
#if GTK_4_8
        var files = new GenericArray<File> (playlist.length);
        playlist.items.foreach ((music) => files.add (File.new_for_uri (music.uri)));
        var val2 = Value (typeof (Gdk.FileList));
        val2.set_boxed (new Gdk.FileList.from_array (files.data));
        return new Gdk.ContentProvider.union ({
            new Gdk.ContentProvider.for_value (val),
            new Gdk.ContentProvider.for_value (val2),
        });
#else
        return new Gdk.ContentProvider.for_value (val);
#endif
    }

    namespace Button {
        public const string ADDTO = "add";
        public const string INSERT = "insert";
        public const string QUEUE = "queue";
        public const string REMOVE = "remove";
    }

    public MenuItem create_menu_item_for_button (string button_name, string label, string action) {
        var item = new MenuItem (label, null);
        item.set_action_and_target_value (action, new Variant.string (button_name));
        return item;
    }

    public Gtk.Widget? find_ancestry_with_type (Gtk.Widget widget, Type type) {
        var parent = widget.get_parent ();
        if (parent?.get_type ()?.is_a (type) ?? false)
            return parent as MusicList;
        else if (parent != null)
            return find_ancestry_with_type ((!)parent, type);
        return null;
    }

    public struct CountedRect {
        public int count;
        public int index;
        public Graphene.Rect rect;

        public CountedRect (int c = 0, int i = 0, Graphene.Rect? rc = null) {
            count = c;
            index = i;
            if (rc != null)
                rect = (!)rc;
            else
                rect.init (0, 0, 0, 0);
        }
    }

    public uint get_grid_view_item_size (Gtk.GridView grid_view, ref Graphene.Size inner_size, ref Graphene.Size outer_size) {
        var arr = new GenericArray<Graphene.Rect?> ();
        var w_map = new HashTable<int, CountedRect?> (null, null);
        var x_set = new GenericSet<int> (null, null);
        for (var c = grid_view.get_first_child (); c != null; c = c?.get_next_sibling ()) {
            var child = (!)c;
            var rect = Graphene.Rect ();
            if (child.is_drawable () && child.compute_bounds (grid_view, out rect)
                    && rect.origin.x >= 0 && rect.origin.y >= 0
                    && rect.size.width > 0 && rect.size.height > 0) {
                var width = (int) rect.size.width;
                var count = 1, index = arr.length;
                var cr0 = w_map[width];
                if (cr0 != null) {
                    count = ((!)cr0).count + 1;
                    index = ((!)cr0).index;
                }
                var cr = CountedRect (count, index, rect);
                w_map[width] = cr;
                x_set.add ((int) rect.origin.x);
                arr.add (rect);
            }
        }
        var columns = x_set.length.clamp (grid_view.min_columns, grid_view.max_columns);

        var best_rect = CountedRect ();
        best_rect.index = -1;
        w_map.foreach ((w, rect) => {
            var cr = (!)rect;
            if (best_rect.count < cr.count) {
                best_rect.count = cr.count;
                if (best_rect.index == -1)
                    best_rect.index = cr.index;
                best_rect.rect = cr.rect;
            }
        });
        inner_size.init_from_size (best_rect.rect.size);
        outer_size.init_from_size (inner_size);

        var index = best_rect.index;
        if (index >= 0 && index + 1 < arr.length) {
            outer_size.width = columns > 1 ? ((!)arr[index + 1]).origin.x - ((!)arr[index]).origin.x : grid_view.get_width () / int.max (1, (int) columns);
            if (index + columns < arr.length)
                outer_size.height = ((!)arr[index + columns]).origin.y - ((!)arr[index]).origin.y;
        }
        return columns;
    }
}
