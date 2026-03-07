namespace G4 {

    public class QueueSheet : Object {
        private Application _app;
        private MusicList _list;
        public Adw.BottomSheet bottom_sheet;

        public QueueSheet (Application app) {
            _app = app;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.height_request = 400;

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            header.add_css_class ("toolbar");
            header.margin_top = 24;
            header.hexpand = true;
            var title = new Gtk.Label (_("Queue"));
            title.add_css_class ("title-4");
            title.halign = Gtk.Align.CENTER;
            title.hexpand = true;
            header.append (title);
            box.append (header);

            _list = new MusicList (app, typeof (Music), null, false, true);
            _list.data_store = app.music_queue;
            _list.vexpand = true;
            _list.item_activated.connect ((position, obj) => {
                app.current_item = (int) position;
                app.player.play ();
            });
            var thumbnailer = app.thumbnailer;
            var loading_paintable = thumbnailer.create_simple_text_paintable ("...", Thumbnailer.ICON_SIZE);
            _list.item_binded.connect ((item) => {
                var entry = item.child as MusicEntry?;
                var music = (Music) item.item;
                if (entry == null) return;
                ((!)entry).paintable = loading_paintable;
                ((!)entry).set_titles (music, SortMode.TITLE);
            });
            
            box.append (_list);

            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            footer.margin_start = 12;
            footer.margin_end = 12;
            footer.margin_bottom = 12;
            footer.margin_top = 6;

            var shuffle_btn = new Gtk.ToggleButton ();
            shuffle_btn.icon_name = "media-playlist-shuffle-symbolic";
            shuffle_btn.tooltip_text = _("Shuffle Queue");
            shuffle_btn.add_css_class ("flat");
            shuffle_btn.active = app.queue_shuffled;
            shuffle_btn.opacity = app.queue_shuffled ? 1.0 : 0.5;
            shuffle_btn.toggled.connect (() => {
                app.queue_shuffled = shuffle_btn.active;
                if (shuffle_btn.active) {
                    shuffle_btn.opacity = 1.0;
                    sort_music_store (app.music_queue, SortMode.SHUFFLE);
                } else {
                    shuffle_btn.opacity = 0.5;
                    app.restore_queue_order ();
                }
                var index = find_item_in_model (_list.filter_model, app.current_music);
                if (index != -1)
                    _list.scroll_to_item (index);
            });

            footer.append (shuffle_btn);
            box.append (footer);

            bottom_sheet = new Adw.BottomSheet ();

            bottom_sheet.sheet = box;
            bottom_sheet.modal = true;

            app.index_changed.connect ((index, size) => {
                _list.current_node = app.current_music;
            });
            app.music_changed.connect ((music) => {
                _list.current_node = music;
            });
        }

        public void open () {
            var index = find_item_in_model (_list.filter_model, _app.current_music);
            if (index != -1)
                _list.scroll_to_item (index);
            bottom_sheet.open = true;
        }
    }
}
