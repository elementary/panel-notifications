/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2025 elementary, Inc. (https://elementary.io)
*/

public class Notifications.NotificationEntry : Gtk.ListBoxRow {
    public signal void clear ();

    public Notification notification { get; construct; }
    public Gtk.Revealer revealer { get; construct; }

    private uint timeout_id;

    private const int ICON_SIZE_PRIMARY = 48;
    private const int ICON_SIZE_SECONDARY = 24;

    private static Regex entity_regex;
    private static Regex tag_regex;

    public NotificationEntry (Notification notification) {
        Object (notification: notification);
    }

    static construct {
        try {
            entity_regex = new Regex ("&(?!amp;|quot;|apos;|lt;|gt;|nbsp;|#39)");
            tag_regex = new Regex ("<(?!\\/?[biu]>)");
        } catch (Error e) {
            warning ("Invalid regex: %s", e.message);
        }
    }

    class construct {
        set_css_name ("notification");

        var provider = new Gtk.CssProvider ();
        provider.load_from_resource ("io/elementary/wingpanel/notifications/NotificationEntry.css");

        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    construct {
        var app_image = new Gtk.Image ();

        if (notification.app_icon.contains ("/")) {
            var file = File.new_for_uri (notification.app_icon);
            if (file.query_exists ()) {
                app_image.gicon = new FileIcon (file);
            } else {
                app_image.icon_name = "dialog-information";
            }
        } else {
            app_image.icon_name = notification.app_icon;
        }

        var image_overlay = new Gtk.Overlay () {
            valign = START
        };

        if (notification.image_path != null && notification.image_path != "") {
            try {
                var masked_image = new Gtk.Image.from_file (notification.image_path) {
                    pixel_size = ICON_SIZE_PRIMARY,
                    overflow = HIDDEN
                };
                masked_image.add_css_class (Granite.CssClass.CARD);
                masked_image.add_css_class (Granite.CssClass.CHECKERBOARD);

                app_image.pixel_size = ICON_SIZE_SECONDARY;
                app_image.halign = app_image.valign = END;

                image_overlay.child = masked_image;
                image_overlay.add_overlay (app_image);
            } catch (Error e) {
                critical ("Unable to mask image: %s", e.message);

                app_image.pixel_size = ICON_SIZE_PRIMARY;
                image_overlay.child = app_image;
            }
        } else {
            app_image.pixel_size = ICON_SIZE_PRIMARY;
            image_overlay.child = app_image;

            if (notification.badge_icon != null) {
                var badge_image = new Gtk.Image.from_gicon (notification.badge_icon) {
                    halign = END,
                    valign = END,
                    pixel_size = ICON_SIZE_SECONDARY
                };
                image_overlay.add_overlay (badge_image);
            }
        }

        var entry_title = notification.summary;

        if (notification.message_body == "") {
            if (notification.app_name == "" && notification.app_info != null) {
                notification.app_name = notification.app_info.get_display_name ();
            }

            entry_title = notification.app_name;
        }

        var title_label = new Gtk.Label (fix_markup (entry_title)) {
            ellipsize = END,
            hexpand = true,
            width_chars = 27,
            max_width_chars = 27,
            use_markup = true,
            xalign = 0
        };
        title_label.add_css_class ("title");

        var time_label = new Gtk.Label (Granite.DateTime.get_relative_datetime (notification.timestamp)) {
            margin_end = 6
        };
        time_label.add_css_class (Granite.CssClass.DIM);

        var grid = new Gtk.Grid () {
            hexpand = true,
            column_spacing = 6
        };
        grid.add_css_class (Granite.CssClass.CARD);


        var delete_button = new Gtk.Button.from_icon_name ("window-close-symbolic") {
            halign = START,
            valign = START
        };
        delete_button.add_css_class ("close");

        var delete_revealer = new Gtk.Revealer () {
            child = delete_button,
            halign = START,
            valign = START,
            reveal_child = false,
            overflow = VISIBLE,
            transition_duration = Granite.TRANSITION_DURATION_CLOSE,
            transition_type = CROSSFADE
        };

        grid.attach (image_overlay, 0, 0, 1, 2);
        grid.attach (title_label, 1, 0);
        grid.attach (time_label, 2, 0);

        var entry_body = notification.message_body;

        if (entry_body == "") {
            entry_body = notification.summary;
        }

        var body = fix_markup (entry_body);

        var body_label = new Gtk.Label (body) {
            ellipsize = END,
            lines = 2,
            use_markup = true,
            valign = START,
            wrap_mode = WORD_CHAR,
            wrap = true,
            xalign = 0
        };

        if ("\n" in body) {
            string[] lines = body.split ("\n");
            string stripped_body = lines[0] + "\n";
            for (int i = 1; i < lines.length; i++) {
                stripped_body += lines[i].strip () + " ";
            }

            body_label.label = stripped_body.strip ();
            body_label.lines = 1;

        }

        grid.attach (body_label, 1, 1, 2);

        if (notification.buttons.length () > 0) {
            var action_area = new Gtk.Box (HORIZONTAL, 6) {
                margin_top = 12,
                halign = END,
                homogeneous = true
            };
            grid.attach (action_area, 0, 2, 3);

            foreach (var button in notification.buttons) {
                action_area.append (button);
            };
        }

        var delete_left = new DeleteAffordance (END) {
            // Have to match with the grid
            margin_top = 9,
            margin_bottom = 9
        };
        delete_left.add_css_class ("left");

        var delete_right = new DeleteAffordance (START) {
            // Have to match with the grid
            margin_top = 9,
            margin_bottom = 9
        };
        delete_right.add_css_class ("right");

        var overlay = new Gtk.Overlay () {
            child = grid
        };
        overlay.add_overlay (delete_revealer);

        var carousel = new Adw.Carousel () {
            allow_scroll_wheel = false,
        };
        carousel.append (overlay);
        carousel.prepend (delete_left);
        carousel.append (delete_right);

        revealer = new Gtk.Revealer () {
            child = carousel,
            reveal_child = true,
            transition_duration = 200,
            transition_type = SLIDE_UP
        };

        child = revealer;

        delete_button.clicked.connect (() => clear ());

        var motion_controller = new Gtk.EventControllerMotion ();

        motion_controller.enter.connect (() => {
            delete_revealer.reveal_child = true;
        });

        motion_controller.leave.connect (() => {
            delete_revealer.reveal_child = false;
        });

        revealer.add_controller (motion_controller);

        timeout_id = Timeout.add_seconds_full (Priority.DEFAULT, 60, () => {
            time_label.label = Granite.DateTime.get_relative_datetime (notification.timestamp);
            return GLib.Source.CONTINUE;
        });

        carousel.page_changed.connect (() => {
            if (carousel.position != 1) {
                clear ();
            }
        });
    }

    public void dismiss () {
        Source.remove (timeout_id);

        if (!revealer.child_revealed) {
            destroy ();
        } else {
            revealer.notify["child-revealed"].connect (() => {
                if (!revealer.child_revealed) {
                    destroy ();
                }
            });
            revealer.reveal_child = false;
        }

        if (notification.server_id > 0) {
            activate_action_variant (
                NotificationsList.ACTION_PREFIX + "close",
                new Variant.array (VariantType.UINT32, { notification.server_id })
            );
        }
    }

    private class DeleteAffordance : Granite.Bin {
        public Gtk.Align alignment { get; construct; }

        public DeleteAffordance (Gtk.Align alignment) {
            Object (alignment: alignment);
        }

        class construct {
           set_css_name ("delete-affordance");
        }

        construct {
            var image = new Gtk.Image.from_icon_name ("edit-delete-symbolic");

            var label = new Gtk.Label (_("Delete"));
            label.add_css_class (Granite.CssClass.SMALL);

            var box = new Gtk.Box (VERTICAL, 3) {
                halign = alignment,
                hexpand = true,
                valign = CENTER,
                vexpand = true
            };
            box.append (image);
            box.append (label);

            child = box;
        }
    }

    /**
     * Copied from gnome-shell, fixes the mess of markup that is sent to us
     */
    private string fix_markup (string markup) {
        var text = markup;

        try {
            text = entity_regex.replace (markup, markup.length, 0, "&amp;");
            text = tag_regex.replace (text, text.length, 0, "&lt;");
        } catch (Error e) {
            warning ("Invalid regex: %s", e.message);
        }

        return text;
    }
}
