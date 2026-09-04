/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2026 elementary, Inc. (https://elementary.io)
*/

public class Notifications.NotificationsList : Granite.Bin {
    public signal void remove_notification (Notification notification);
    public signal void close_popover ();

    public const string ACTION_GROUP_PREFIX = "notifications-list";
    public const string ACTION_PREFIX = ACTION_GROUP_PREFIX + ".";

    public ListModel list_model { get; construct; }
    private Gtk.Stack stack;

    public NotificationsList (ListModel list_model) {
        Object (list_model: list_model);
    }

    construct {
        var placeholder = new Gtk.Label (_("No Notifications")) {
            margin_top = 24,
            margin_bottom = 24,
            margin_start = 12,
            margin_end = 12,
            visible = true
        };
        placeholder.add_css_class (Granite.STYLE_CLASS_H2_LABEL);
        placeholder.add_css_class (Granite.CssClass.DIM);

        var listbox = new Gtk.ListBox () {
            activate_on_single_click = true,
            selection_mode = NONE
        };
        listbox.bind_model (list_model, create_widget_func);
        listbox.set_header_func (header_func);

        stack = new Gtk.Stack ();
        stack.add_named (placeholder, "placeholder");
        stack.add_named (listbox, "list");

        child = stack;

        insert_action_group (ACTION_GROUP_PREFIX, new NotificationsMonitor ().notifications_action_group);

        listbox.row_activated.connect (on_row_activated);

        list_model.items_changed.connect (on_items_changed);
        on_items_changed ();
    }

    private void header_func (Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
        unowned var row_entry = (NotificationEntry) row;
        unowned NotificationEntry? before_entry = (NotificationEntry) before;
        unowned string row_app_id = row_entry.notification.desktop_id;

        if (before != null && row_app_id == before_entry.notification.desktop_id) {
            row.set_header (null);
            return;
        }

        var app_entry = new AppEntry () {
            app_name = row_entry.notification.app_name,
            app_id = row_app_id
        };
        app_entry.clear.connect (clear_app_entry);

        row.set_header (app_entry);
    }

    private Gtk.Widget create_widget_func (Object item) {
        var notification = (Notification) item;

        var notification_entry = new NotificationEntry ();
        notification_entry.bind (notification);
        notification_entry.remove.connect (() => remove_notification (notification));

        return notification_entry;
    }

    private void clear_app_entry (AppEntry app_entry) {
        app_entry.clear.disconnect (clear_app_entry);

        Notification[] to_remove = {};
        for (int i = 0; i < list_model.get_n_items (); i++) {
            var notification = (Notification) list_model.get_item (i);
            if (notification.desktop_id == app_entry.app_id) {
                notification.server_id = 0;
                to_remove += notification;
            }
        }

        Session.get_instance ().remove_notifications (to_remove);
    }

    private void on_items_changed () {
        if (list_model.get_n_items () == 0) {
            stack.visible_child_name = "placeholder";
            Session.get_instance ().clear ();
        } else {
            stack.visible_child_name = "list";
        }
    }

    private void on_row_activated (Gtk.ListBoxRow row) {
        if (row is NotificationEntry) {
            unowned var notification_entry = (NotificationEntry) row;

            if (notification_entry.notification.default_action != null) {
                activate_action (
                    ACTION_PREFIX + notification_entry.notification.default_action,
                    null
                );
                close_popover ();
            } else {
                try {
                    var context = notification_entry.get_display ().get_app_launch_context ();
                    notification_entry.notification.app_info.launch (null, context);
                    notification_entry.notification.server_id = 0;
                    close_popover ();
                } catch (Error e) {
                    warning ("Unable to launch app: %s", e.message);
                }
            }
        }
    }
}
