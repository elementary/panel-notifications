/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2026 elementary, Inc. (https://elementary.io)
*/

public class Notifications.NotificationsList : Granite.Bin {
    public signal void close_popover ();
    public signal void items_changed ();

    public const string ACTION_GROUP_PREFIX = "notifications-list";
    public const string ACTION_PREFIX = ACTION_GROUP_PREFIX + ".";

    private static GLib.HashTable<string, GLib.DateTime> app_datetime;

    private ListStore list_store;
    public ListModel notification_items {
        get {
            return list_store;
        }
    }

    private Gtk.Button clear_all_btn;
    private Gtk.SortListModel sort_list_model;
    private Gtk.Stack stack;

    construct {
        app_datetime = new GLib.HashTable<string, GLib.DateTime> (str_hash, str_equal);

        var not_disturb_switch = new Granite.SwitchModelButton (_("Do Not Disturb"));
        not_disturb_switch.add_css_class (Granite.STYLE_CLASS_H4_LABEL);

        var dnd_switch_separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL) {
            margin_top = 3,
            margin_bottom = 3
        };

        var clear_all_btn_separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL) {
            margin_top = 3,
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

        list_store = new GLib.ListStore (typeof (Notification));

        sort_list_model = new Gtk.SortListModel (list_store, new Gtk.CustomSorter ((GLib.CompareDataFunc<GLib.Object>) Notification.compare)) {
            section_sorter = new Gtk.CustomSorter ((GLib.CompareDataFunc<GLib.Object>) section_compare)
        };

        var listbox = new Gtk.ListBox () {
            activate_on_single_click = true,
            selection_mode = NONE
        };
        listbox.bind_model (sort_list_model, create_widget_func);
        listbox.set_header_func (header_func);

        var scrolled = new Gtk.ScrolledWindow () {
            child = listbox,
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
        main_box.append (scrolled);
        main_box.append (clear_all_btn_separator);
        main_box.append (clear_all_btn);
        main_box.append (settings_btn);

        child = main_box;

        insert_action_group (ACTION_GROUP_PREFIX, new NotificationsMonitor ().notifications_action_group);

        listbox.row_activated.connect (on_row_activated);

        list_store.items_changed.connect (on_items_changed);

        var previous_session = Session.get_instance ().get_session_notifications ();
        // Do not block animated drawing of wingpanel
        Idle.add_once (() => {
            foreach (unowned var notification in previous_session) {
                add_entry (notification);
            }
        });

        var settings = new GLib.Settings ("io.elementary.notifications");
        settings.bind ("do-not-disturb", not_disturb_switch, "active", DEFAULT);

        clear_all_btn.clicked.connect (clear_all);
        settings_btn.clicked.connect (show_settings);
    }

    private static int section_compare (Notification a, Notification b) {
        return app_datetime[b.desktop_id].compare (app_datetime[a.desktop_id]);
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

    public async void add_entry (Notification notification) {
        unowned GLib.DateTime? time = app_datetime[notification.desktop_id];
        if (time == null || time.compare (notification.timestamp) <= 0) {
            app_datetime[notification.desktop_id] = notification.timestamp;
            sort_list_model.section_sorter.changed (DIFFERENT);
        }

        list_store.append (notification);

        Idle.add (add_entry.callback);
        yield;
    }

    public void clear_all () {
        Session.get_instance ().clear ();
        list_store.remove_all ();
        close_popover ();
    }

    private void show_settings () {
        close_popover ();

        try {
            AppInfo.launch_default_for_uri ("settings://notifications", null);
        } catch (Error e) {
            warning ("Failed to open notifications settings: %s", e.message);
        }
    }

    public uint get_n_app_items () {
        var app_list = new GenericSet<string> (str_hash, str_equal);
        for (var i = 0; i < list_store.n_items; i++) {
            app_list.add (((Notification) list_store.get_item (i)).desktop_id);
        }

        return app_list.length;
    }

    private void clear_app_entry (AppEntry app_entry) {
        app_entry.clear.disconnect (clear_app_entry);

        Notification[] to_remove = {};
        for (int i = 0; i < list_store.n_items; i++) {
            var notification = (Notification) list_store.get_item (i);
            if (notification.desktop_id == app_entry.app_id) {
                notification.server_id = 0;
                to_remove += notification;
            }
        }

        Session.get_instance ().remove_notifications (to_remove);
    }

    private void on_items_changed () {
        if (list_store.n_items == 0) {
            stack.visible_child_name = "placeholder";
            Session.get_instance ().clear ();
        } else {
            stack.visible_child_name = "list";
        }

        clear_all_btn.sensitive = list_store.n_items > 0;

        items_changed ();
    }

    private void remove_notification (Notification notification) {
        var app_id = notification.desktop_id;

        uint pos = -1;
        if (list_store.find (notification, out pos)) {
            list_store.remove (pos);
            Session.get_instance ().remove_notification (notification);
        }

        var items_for_appid = new Gtk.FilterListModel (
            list_store, new Gtk.CustomFilter ((item) => {
                return ((Notification) item).desktop_id == app_id;
            })
        );

        if (items_for_appid.n_items == 0) {
            var settings = new Settings ("io.elementary.panel.notifications");
            var headers = (HashTable<string, bool>) settings.get_value ("headers");
            if (headers.remove (app_id)) {
                settings.set_value ("headers", headers);
            }
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
