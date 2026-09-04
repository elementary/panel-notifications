/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2026 elementary, Inc. (https://elementary.io)
*/

public class Notifications.NotificationsList : Granite.Bin {
    public signal void remove_notification (Notification notification);
    public signal void clear_all ();
    public signal void close_popover ();

    public const string ACTION_GROUP_PREFIX = "notifications-list";
    public const string ACTION_PREFIX = ACTION_GROUP_PREFIX + ".";

    public ListModel list_model { get; construct; }

    private Gtk.Button clear_all_btn;
    private Gtk.Stack stack;

    public NotificationsList (ListModel list_model) {
        Object (list_model: list_model);
    }

    construct {
        var not_disturb_switch = new Granite.SwitchModelButton (_("Do Not Disturb"));

        var dnd_switch_separator = new Gtk.Separator (HORIZONTAL) {
            margin_top = 3
        };

        var clear_all_btn_separator = new Gtk.Separator (HORIZONTAL) {
            margin_bottom = 3
        };

        clear_all_btn = new Wingpanel.PopoverMenuItem () {
            text = _("Clear All Notifications")
        };

        var settings_btn = new Wingpanel.PopoverMenuItem () {
            text = _("Notifications Settings…")
        };

        var placeholder = new Gtk.Label (_("No Notifications")) {
            margin_top = 24,
            margin_bottom = 24,
            margin_start = 12,
            margin_end = 12,
            visible = true
        };
        placeholder.add_css_class (Granite.STYLE_CLASS_H2_LABEL);
        placeholder.add_css_class (Granite.CssClass.DIM);

        var item_factory = new Gtk.SignalListItemFactory ();
        item_factory.setup.connect (setup_factory);
        item_factory.bind.connect (bind_factory);
        item_factory.unbind.connect (unbind_factory);

        var header_factory = new Gtk.SignalListItemFactory ();
        header_factory.setup.connect (setup_header_factory);
        header_factory.bind.connect (bind_header_factory);

        var list_view = new Gtk.ListView (new Gtk.NoSelection (list_model), item_factory) {
            header_factory = header_factory,
            margin_top = 3,
            margin_bottom = 3,
            single_click_activate = true
        };
        list_view.remove_css_class (Granite.STYLE_CLASS_VIEW);

        var scrolled = new Gtk.ScrolledWindow () {
            child = list_view,
            hscrollbar_policy = NEVER,
            max_content_height = 500,
            propagate_natural_height = true
        };

        stack = new Gtk.Stack ();
        stack.add_named (placeholder, "placeholder");
        stack.add_named (scrolled, "list");

        var main_box = new Gtk.Box (VERTICAL, 0) {
            width_request = 360
        };
        main_box.append (not_disturb_switch);
        main_box.append (dnd_switch_separator);
        main_box.append (stack);
        main_box.append (clear_all_btn_separator);
        main_box.append (clear_all_btn);
        main_box.append (settings_btn);

        child = main_box;

        insert_action_group (ACTION_GROUP_PREFIX, new NotificationsMonitor ().notifications_action_group);

        list_view.activate.connect (on_row_activated);

        list_model.items_changed.connect (on_items_changed);
        on_items_changed ();

        var settings = new GLib.Settings ("io.elementary.notifications");
        settings.bind ("do-not-disturb", not_disturb_switch, "active", DEFAULT);

        clear_all_btn.clicked.connect (() => clear_all ());
        settings_btn.clicked.connect (show_settings);
    }

    private void setup_factory (Object item) {
        var notification_entry = new NotificationEntry ();
        notification_entry.remove.connect ((notification) => remove_notification (notification));

        ((Gtk.ListItem) item).child = notification_entry;
    }

    private void bind_factory (Object item) {
        var list_item = (Gtk.ListItem) item;

        var notification_entry = (NotificationEntry) list_item.child;
        notification_entry.bind ((Notification) list_item.item);
    }

    private void unbind_factory (Object item) {
        var list_item = (Gtk.ListItem) item;

        var notification_entry = (NotificationEntry) list_item.child;
        notification_entry.unbind ();
    }

    private void setup_header_factory (Object item) {
        var app_entry = new AppEntry ();
        app_entry.clear.connect (clear_app_entry);

        ((Gtk.ListHeader) item).child = app_entry;
    }

    private void bind_header_factory (Object item) {
        var list_item = (Gtk.ListHeader) item;
        var notification = (Notification) list_item.item;

        var app_entry = (AppEntry) list_item.child;
        app_entry.app_name = notification.app_name;
        app_entry.app_id = notification.desktop_id;
    }

    private void show_settings () {
        close_popover ();

        var uri_launcher = new Gtk.UriLauncher (Granite.SettingsUri.NOTIFICATIONS);
        uri_launcher.launch.begin ((Gtk.Window) get_root (), null, (obj, res) => {
            try {
                uri_launcher.launch.end (res);
            } catch (Error e) {
                warning ("Failed to open notifications settings: %s", e.message);
            }
        });
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

        clear_all_btn.sensitive = list_model.get_n_items () > 0;
    }

    private void on_row_activated (uint pos) {
        var notification = (Notification) list_model.get_item (pos);
        if (notification.default_action != null) {
            activate_action (
                ACTION_PREFIX + notification.default_action,
                null
            );
            close_popover ();
        } else {
            try {
                var context = get_display ().get_app_launch_context ();
                notification.app_info.launch (null, context);
                notification.server_id = 0;
                close_popover ();
            } catch (Error e) {
                warning ("Unable to launch app: %s", e.message);
            }
        }
    }
}
