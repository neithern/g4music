namespace G4 {

#if ADW_1_5
    public class Dialog : Adw.Dialog {
#else
    public class Dialog : Gtk.Window {

        public override bool close_request () {
            closed ();
            return false;
        }

        public new void present (Gtk.Window? parent = null) {
            if (parent != null) {
                modal = true;
                transient_for = (!)parent;
            }
            set_titlebar (new Adw.Bin ());
            base.present ();
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            child.measure (orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.VERTICAL) {
                var height = transient_for.get_height ();
                if (natural > height && height > 0)
                    natural = height;
            }
        }

        public virtual signal void closed () {
        }
#endif
    }

    public async bool show_alert_dialog (string text, Gtk.Window? parent = null) {
#if ADW_1_5
        var result = new bool[] { false };
        var dialog = new Adw.AlertDialog (null, text);
        dialog.add_response ("no", _("No"));
        dialog.add_response ("yes", _("Yes"));
        dialog.default_response = "yes";
        dialog.response.connect ((id) => {
            result[0] = id == "yes";
            Idle.add (show_alert_dialog.callback);
        });
        dialog.present (parent);
        yield;
        return result[0];
#elif GTK_4_10
        var dialog = new Gtk.AlertDialog (text);
        dialog.buttons = { _("No"), _("Yes") };
        dialog.cancel_button = 0;
        dialog.default_button = 1;
        dialog.modal = true;
        try {
            var btn = yield dialog.choose (parent, null);
            return btn == 1;
        } catch (Error e) {
        }
        return false;
#else
        var result = new int[] { -1 };
        var dialog = new Gtk.MessageDialog (parent, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                            Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, text);
        dialog.response.connect ((id) => {
            dialog.destroy ();
            result[0] = id;
            Idle.add (show_alert_dialog.callback);
        });
        dialog.set_titlebar (new Adw.Bin ());
        dialog.present ();
        yield;
        return result[0] == Gtk.ResponseType.YES;
#endif
    }

    public async File? show_save_file_dialog (Gtk.Window? parent, File? initial = null, Gtk.FileFilter[]? filters = null) {
        Gtk.FileFilter? default_filter = filters != null && ((!)filters).length > 0 ? ((!)filters)[0] : (Gtk.FileFilter?) null;
#if GTK_4_10
        var filter_list = new ListStore (typeof (Gtk.FileFilter));
        if (filters != null) {
            foreach (var filter in (!)filters) 
                filter_list.append (filter);
        }
        var dialog = new Gtk.FileDialog ();
        dialog.filters = filter_list;
        dialog.modal = true;
        dialog.set_default_filter (default_filter);
        dialog.set_initial_file (initial);
        try {
            return yield dialog.save (parent, null);
        } catch (Error e) {
        }
        return null;
#else
        var result = new File?[] { (File?) null };
        var chooser = new Gtk.FileChooserNative (null, parent, Gtk.FileChooserAction.SAVE, null, null);
        chooser.modal = true;
        try {
            chooser.set_current_folder (initial?.get_parent ());
            chooser.set_current_name (initial?.get_basename () ?? "");
        } catch (Error e) {
        }
        if (filters != null) {
            foreach (var filter in (!)filters) 
                chooser.add_filter (filter);
            if (default_filter != null)
                chooser.set_filter ((!)default_filter);
        }
        chooser.response.connect ((id) => {
            var file = chooser.get_file ();
            if (id == Gtk.ResponseType.ACCEPT && file is File) {
                result[0] = file;
                Idle.add (show_save_file_dialog.callback);
            }
        });
        chooser.show ();
        yield;
        return result[0];
#endif
    }
}
