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

            _grid_view.enable_rubberband = false;
            _grid_view.max_columns = 5;
            _grid_view.margin_start = 6;
            _grid_view.margin_end = 6;
            _grid_view.model = _selection = new Gtk.MultiSelection (_filter_model);
            _grid_view.single_click_activate = true;
            _grid_view.activate.connect ((position) => item_activated (position, _filter_model.get_item (position)));
            _grid_view.add_css_class ("navigation-sidebar");
            _selection.selection_changed.connect (on_selection_changed);
            create_factory ();

            _scroll_view.child = _grid_view;
            _scroll_view.hscrollbar_policy = Gtk.PolicyType.NEVER;
            _scroll_view.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            _scroll_view.propagate_natural_height = true;
            _scroll_view.vexpand = true;
            _scroll_view.vadjustment.changed.connect (on_vadjustment_changed);
            append (_scroll_view);

            if (_editable) {
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
                    _header_bar_hided = get_first_child () as Gtk.HeaderBar;
                    var header = new Gtk.HeaderBar ();
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
                    _grid_view.enable_rubberband = value;
                    _grid_view.single_click_activate = !value;
                    _binding_items.foreach ((music, item) => item.selectable = value);
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
                    _app.append_to_queue (playlist, false);
                    break;

                case Button.REMOVE:
                    _modified |= remove_items_from_store (_data_store, playlist.items);
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
            _child_drawed = false;
        }

        public async Result prompt_save_if_modified () {
            if (_modified && _music_node is Playlist) {
                var playlist = new Playlist (_music_node?.title ?? "Untitled");
                playlist.list_uri = ((Playlist)_music_node).list_uri;

                var count = _data_store.get_n_items ();
                for (var i = 0; i < count; i++) {
                    var music = (Music) _data_store.get_item (i);
                    playlist.add_music (music);
                }

                var ret = yield show_alert_dialog (_("Playlist is modified, save it?"), root as Gtk.Window);
                if (ret) {
                    ret = yield _app.add_playlist_to_file_async (playlist, false);
                    _modified = !ret;
                    return ret ? Result.OK : Result.FAILED;
                }
            }
            return _modified ? Result.CANCEL : Result.OK;
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
                var rect = Graphene.Rect ();
                child.compute_bounds (this, out rect);
                draw_outset_shadow (snapshot, rect);
            }

            Object? obj = null;
            Gtk.Widget? child = null;
            if (_dropping_item >= 0 && (obj = _filter_model.get_item (_dropping_item)) is Music
                    && (child = get_binding_widget ((Music) obj)) != null) {
                var rect = Graphene.Rect ();
                ((!)child).compute_bounds (this, out rect);
                rect.size.height = scale_factor * 0.5f;
#if ADW_1_6
                var color = Adw.StyleManager.get_for_display (get_display ())
                                        .get_accent_color ().to_rgba ();
#else
                var color = Gdk.RGBA ();
                color.alpha = 1;
                color.red = color.green = color.blue = 0.5f;
#endif
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
                menu.append_item (create_menu_item_for_button (Button.INSERT, _("Play at Next"), action));
                if (_has_add_to_queque)
                    menu.append_item (create_menu_item_for_button (Button.QUEUE, _("Add to Queue"), action));
                menu.append_item (create_menu_item_for_button (Button.ADDTO, _("Add to Playlist…"), action));
                menu.append_item (create_menu_item_for_button (Button.REMOVE, _("Remove"), action));
                return menu;
            } else if (node is Album) {
                return create_menu_for_album ((Album) node);
            } else if (node is Artist) {
                return create_menu_for_artist ((Artist) node);
            } else if (node is Music) {
                var music = (Music) node;
                var menu = create_menu_for_music (music);
                if (music != _app.current_music) {
                    if (_has_add_to_queque)
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
            var child = (MusicWidget) item.child;
            child.paintable = null;
            child.disconnect_first_draw ();
            item_unbinded (item);
            _binding_items.remove ((Music) item.item);
        }

        private void on_vadjustment_changed () {
            var adj = _scroll_view.vadjustment;
            var range = adj.upper - adj.lower;
            var count = visible_count;
            if (count > 0 && _row_min_width > 0 && _scroll_range != range) {
                var columns = _grid_view.get_width () / _row_min_width;
                _columns = columns.clamp (_grid_view.get_min_columns (), _grid_view.get_max_columns ());
                _row_height = range / ((count + _columns - 1) / _columns);
                _scroll_range = range;
            }
        }

        private Gdk.ContentProvider? on_drag_prepare (Music? music) {
            var position = find_item_in_model (_filter_model, music);
            if (position != -1)
                _selection.select_item (position, false);

            var playlist = create_playlist_for_selection ();
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

        private int _dropping_item = -1;

        private bool on_drop_done (Value value, double x, double y) {
            var obj = value.get_object ();
            if (obj is Playlist) {
                uint position = _dropping_item;
                var dst_obj = _filter_model.get_item (position);
                if (dst_obj == null || !_data_store.find ((!)dst_obj, out position))
                    position = _data_store.get_n_items ();
                var playlist = (Playlist) obj;
                _modified |= move_items_in_store (_data_store, position, playlist.items);
            }
            dropping_item = -1;
            return true;
        }

        private Gdk.DragAction on_drop_motion (double x, double y) {
            var row_width = (double) _grid_view.get_width () / _columns;
            var col = (int) (x / row_width);
            var row = (int) ((_scroll_view.vadjustment.value + y) / _row_height);
            dropping_item = (int) _columns * row + col;
            return Gdk.DragAction.LINK;
        }

        private MusicWidget? get_binding_widget (Music? music) {
            var item = music != null ? _binding_items[(!)music] : (Gtk.ListItem?) null;
            return item?.child as MusicWidget;
        }

        private static void create_drag_source (Gtk.Widget widget, Gtk.ListItem item) {
            var point = Graphene.Point ();
            var source = new Gtk.DragSource ();
            source.actions = Gdk.DragAction.LINK;
            source.drag_begin.connect ((drag) => source.set_icon (new Gtk.WidgetPaintable (widget), (int) point.x, (int) point.y));
            source.prepare.connect ((x, y) => {
                point.init ((float) x, (float) y);
                //  Hack: don't use `this` directly, because it will not be destroyed when detach???
                var list = find_ancestry_with_type (widget, typeof (MusicList));
                return (list as MusicList)?.on_drag_prepare (item.item as Music);
            });
            widget.add_controller (source);
        }

        private void create_drop_target (Gtk.Widget widget) {
            var target = new Gtk.DropTarget (typeof (Playlist), Gdk.DragAction.LINK);
            target.accept.connect ((drop) => drop.formats.contain_gtype (typeof (Playlist)));
            target.motion.connect (on_drop_motion);
            target.leave.connect (() => dropping_item = -1);
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

        private void on_selection_changed (uint position, uint n_items) {
            var bits = _selection.get_selection ();
            var selected = bits.get_size ();
            if (selected > 1)
                multi_selection = true;
            _header_title?.set_label (@"$selected/$visible_count");

            var enabled = selected > 0;
            foreach (var button in _action_buttons)
                button.sensitive = enabled;
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
                    prompt_save_if_modified.begin ((obj, res) => {
                        var ret = prompt_save_if_modified.end (res);
                        if (ret != Result.FAILED) {
                            _modified = false;
                            multi_selection = false;
                        }
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
                remove_btn.clicked.connect (() => button_command (Button.REMOVE));
                remove_btn.name = Button.REMOVE;
                _action_buttons.add (remove_btn);
            }

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

            _action_buttons.foreach (header.pack_end);
        }
    }

    public class MainMusicList : MusicList {
        public MainMusicList (Application app) {
            base (app, typeof (Music), null, true);
            _has_add_to_queque = false;
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
                var ret = yield run_async<bool> (() => save_playlist_file (file, uris, null, false), false, true);
                _modified = !ret;
            }
            return !_modified;
        }
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
}
