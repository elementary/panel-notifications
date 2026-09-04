/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2025 elementary, Inc. (https://elementary.io)
*/

public class Notifications.ListItem : Granite.Bin {
    public signal void remove (Notification notification);

    public Notification notification { get; private set; }

    private const int ICON_SIZE_PRIMARY = 48;
    private const int ICON_SIZE_SECONDARY = 24;

    private static Regex entity_regex;
    private static Regex tag_regex;
    private static Settings settings;

    private uint timeout_id;
    private Granite.Box action_area;
    private Gtk.Image primary_image;
    private Gtk.Image secondary_image;
    private Gtk.Label body_label;
    private Gtk.Label title_label;
    private Gtk.Revealer revealer;

    static construct {
        try {
            entity_regex = new Regex ("&(?!amp;|quot;|apos;|lt;|gt;|nbsp;|#39)");
            tag_regex = new Regex ("<(?!\\/?[biu]>)");
        } catch (Error e) {
            warning ("Invalid regex: %s", e.message);
        }

        settings = new Settings ("io.elementary.panel.notifications");
    }

    class construct {
        set_css_name ("notification");

        var provider = new Gtk.CssProvider ();
        provider.load_from_resource ("io/elementary/wingpanel/notifications/ListItem.css");

        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    construct {
        primary_image = new Gtk.Image () {
            pixel_size = ICON_SIZE_PRIMARY,
            overflow = HIDDEN
        };

        secondary_image = new Gtk.Image () {
            halign = END,
            valign = END,
            pixel_size = ICON_SIZE_SECONDARY
        };

        var image_overlay = new Gtk.Overlay () {
            child = primary_image,
            valign = START
        };
        image_overlay.add_overlay (secondary_image);

        title_label = new Gtk.Label ("") {
            ellipsize = END,
            hexpand = true,
            width_chars = 27,
            max_width_chars = 27,
            use_markup = true,
            xalign = 0
        };
        title_label.add_css_class ("title");

        var time_label = new Gtk.Label ("") {
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

        body_label = new Gtk.Label ("") {
            ellipsize = END,
            use_markup = true,
            valign = START,
            wrap_mode = WORD_CHAR,
            wrap = true,
            xalign = 0
        };

        grid.attach (body_label, 1, 1, 2);

        action_area = new Granite.Box (HORIZONTAL, HALF) {
            margin_top = 12,
            halign = END,
            homogeneous = true,
            visible = false
        };
        grid.attach (action_area, 0, 2, 3);

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

        delete_button.clicked.connect (() => {
            dismiss ();
        });

        var motion_controller = new Gtk.EventControllerMotion ();

        motion_controller.enter.connect (() => {
            delete_revealer.reveal_child = true;
        });

        motion_controller.leave.connect (() => {
            delete_revealer.reveal_child = false;
        });

        revealer.add_controller (motion_controller);

        map.connect (() => {
            time_label.label = Granite.DateTime.get_relative_datetime (notification.timestamp);
            timeout_id = Timeout.add_seconds_full (Priority.DEFAULT, 60, () => {
                time_label.label = Granite.DateTime.get_relative_datetime (notification.timestamp);
                return GLib.Source.CONTINUE;
            });
        });

        unmap.connect (() => {
            Source.remove (timeout_id);
        });

        bind (notification);
    }

    public void bind (Notification value) {
        notification = value;

        Icon app_icon = new ThemedIcon ("io.elementary.notifications");
        if (notification.app_icon.contains ("/")) {
            var file = File.new_for_uri (notification.app_icon);
            if (file.query_exists ()) {
                app_icon = new FileIcon (file);
            }
        } else if (notification.app_icon != "") {
            app_icon = new ThemedIcon (notification.app_icon);
        }

        if (notification.image_path != null && notification.image_path != "") {
            var file = File.new_for_path (notification.image_path);
            if (file.query_exists ()) {
                primary_image.gicon = new FileIcon (file);
                primary_image.add_css_class (Granite.CssClass.CARD);
                primary_image.add_css_class (Granite.CssClass.CHECKERBOARD);
                secondary_image.gicon = app_icon;
            } else {
                primary_image.gicon = app_icon;
            }
        } else {
            primary_image.gicon = app_icon;
            secondary_image.gicon = notification.badge_icon;
        }

        var entry_title = notification.summary;
        if (notification.message_body == "") {
            entry_title = notification.app_name;
        }

        title_label.label = fix_markup (entry_title);

        var entry_body = notification.message_body;
        if (entry_body == "") {
            entry_body = notification.summary;
        }

        if ("\n" in entry_body) {
            string[] lines = entry_body.split ("\n");
            string stripped_body = lines[0] + "\n";
            for (int i = 1; i < lines.length; i++) {
                stripped_body += lines[i].strip () + " ";
            }

            entry_body = stripped_body.strip ();
            body_label.lines = 1;
        } else {
            body_label.lines = 2;
        }

        body_label.label = fix_markup (entry_body);

        for (int i = 0; i < notification.actions.length; i += 2) {
            if (notification.actions[i] == Notification.DEFAULT_ACTION_NAME) {
                continue;
            }

            var label = notification.actions[i + 1].strip ();
            if (label == "") {
                warning ("Action '%s' sent without label, skipping…", notification.actions[i]);
                continue;
            }

            var button = new Gtk.Button.with_label (label) {
                action_name = string.join (
                    ".",
                    NotificationsList.ACTION_GROUP_PREFIX,
                    notification.server_id.to_string (),
                    notification.actions[i]
                )
            };

            action_area.append (button);
        }

        if (notification.actions.length >= 2) {
            action_area.visible = true;
        }

        settings.bind_with_mapping (
            "headers", revealer, "reveal-child", GET,
            get_bind_func, () => false,
            new Variant.string (notification.desktop_id), null
        );

        notification.notify["server-id"].connect (dismiss_if_stale);
    }

    public void unbind () {
        notification.notify.disconnect (dismiss_if_stale);
        Settings.unbind (settings, "headers");
    }

    private static bool get_bind_func (Value value, Variant variant, void* user_data) {
        var app_id = ((Variant) user_data).get_string ();
        var headers_table = (HashTable<string, bool>) variant;
        value.set_boolean (headers_table[app_id]);
        return true;
    }

    private void dismiss () {
        if (!revealer.child_revealed) {
            remove (notification);
        } else {
            revealer.notify["child-revealed"].connect (() => {
                if (!revealer.child_revealed) {
                    remove (notification);
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

    private void dismiss_if_stale () {
        if (notification.server_id == 0) {
            dismiss ();
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
