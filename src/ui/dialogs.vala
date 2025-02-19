namespace G4 {

#if ADW_1_5
    public class Dialog : Adw.Dialog {

        public new void present (Gtk.Widget? parent) {
            content_width = compute_dialog_width (parent);
            base.present (parent);
        }
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
            width_request = compute_dialog_width (parent);
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

    public int compute_dialog_width (Gtk.Widget? parent) {
        var width = parent?.get_width () ?? ContentWidth.MIN;
        if (width > 360)
            width = (width * 3 / 8).clamp (360, ContentWidth.MAX);
        return width;
    }

    public void show_about_dialog (Application app) {
        string[] authors = { "Nanling" };
        /* Translators: Replace "translator-credits" with your names, one name per line */
        var translator_credits = _("translator-credits");
        var website = "https://gitlab.gnome.org/neithern/g4music";
        var parent = Window.get_default ();
#if ADW_1_5
        var win = new Adw.AboutDialog ();
        run_idle_once (() => {
            if (parent != null && ((!)parent).get_width () < win.width_request)
                ((!)parent).default_width = win.width_request;
        });
#elif ADW_1_2
        var win = new Adw.AboutWindow ();
#endif
#if ADW_1_2
        win.application_icon = app.application_id;
        win.application_name = app.name;
        win.version = Config.VERSION;
        win.license_type = Gtk.License.GPL_3_0;
        win.developers = authors;
        win.website = website;
        win.issue_url = "https://gitlab.gnome.org/neithern/g4music/issues";
        win.translator_credits = translator_credits;
#if ADW_1_5
        win.present (parent);
#else
        if (parent != null)
            win.transient_for = (!)parent;
        win.present ();
#endif
#else
        Gtk.show_about_dialog (parent,
                               "logo-icon-name", app.application_id,
                               "program-name", app.name,
                               "version", Config.VERSION,
                               "comments", comments,
                               "authors", authors,
                               "translator-credits", translator_credits,
                               "license-type", Gtk.License.GPL_3_0,
                               "website", website
                              );
#endif
    }

    public async bool show_alert_dialog (string text, Gtk.Window? parent = null) {
#if ADW_1_5
        var result = false;
        var dialog = new Adw.AlertDialog (null, text);
        dialog.add_response ("no", _("No"));
        dialog.add_response ("yes", _("Yes"));
        dialog.default_response = "yes";
        dialog.response.connect ((id) => {
            result = id == "yes";
            Idle.add (show_alert_dialog.callback);
        });
        dialog.present (parent);
        yield;
        return result;
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
        var result = -1;
        var dialog = new Gtk.MessageDialog (parent, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                            Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, text);
        dialog.response.connect ((id) => {
            dialog.destroy ();
            result = id;
            Idle.add (show_alert_dialog.callback);
        });
        dialog.set_titlebar (new Adw.Bin ());
        dialog.present ();
        yield;
        return result == Gtk.ResponseType.YES;
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
        File? result = null;
        var chooser = new Gtk.FileChooserNative (null, parent, Gtk.FileChooserAction.SAVE, null, null);
        chooser.modal = true;
        try {
            var folder = initial?.get_parent ();
            if (folder != null)
                chooser.set_current_folder ((!)folder);
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
                result = file;
                Idle.add (show_save_file_dialog.callback);
            }
        });
        chooser.show ();
        yield;
        return result;
#endif
    }

    public async File? show_select_folder_dialog (Gtk.Window? parent, File? initial = null) {
#if GTK_4_10
        var dialog = new Gtk.FileDialog ();
        dialog.set_initial_folder (initial);
        dialog.modal = true;
        try {
            return yield dialog.select_folder (parent, null);
        } catch (Error e) {
        }
        return null;
#else
        File? result = null;
        var chooser = new Gtk.FileChooserNative (null, parent,
                        Gtk.FileChooserAction.SELECT_FOLDER, null, null);
        try {
            if (initial != null)
                chooser.set_file ((!)initial);
        } catch (Error e) {
        }
        chooser.modal = true;
        chooser.response.connect ((id) => {
            if (id == Gtk.ResponseType.ACCEPT) {
                result = chooser.get_file ();
                Idle.add (show_select_folder_dialog.callback);
            }
        });
        chooser.show ();
        yield;
        return result;
#endif
    }
}
