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

    private Gtk.Stack stack;
    private Gtk.SortListModel sort_list_model;

    private ListStore list_store;
    public ListModel notification_items {
        get {
            return list_store;
        }
    }

    static construct {
        app_datetime = new GLib.HashTable<string, GLib.DateTime> (str_hash, str_equal);
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

        list_store = new GLib.ListStore (typeof (Notification));

        sort_list_model = new Gtk.SortListModel (list_store, new Gtk.CustomSorter ((GLib.CompareDataFunc<GLib.Object>) Notification.compare)) {
            section_sorter = new Gtk.CustomSorter ((GLib.CompareDataFunc<GLib.Object>) section_func)
        };

        var item_factory = new Gtk.SignalListItemFactory ();
        item_factory.setup.connect (setup_factory);
        item_factory.bind.connect (bind_factory);
        item_factory.unbind.connect (unbind_factory);

        var header_factory = new Gtk.SignalListItemFactory ();
        header_factory.setup.connect (setup_header_factory);
        header_factory.bind.connect (bind_header_factory);

        var list_view = new Gtk.ListView (new Gtk.NoSelection (sort_list_model), item_factory) {
            header_factory = header_factory,
            single_click_activate = true
        };
        list_view.remove_css_class (Granite.STYLE_CLASS_VIEW);

        stack = new Gtk.Stack ();
        stack.add_named (placeholder, "placeholder");
        stack.add_named (list_view, "list");

        child = stack;

        insert_action_group (ACTION_GROUP_PREFIX, new NotificationsMonitor ().notifications_action_group);

        list_view.activate.connect (on_row_activated);

        list_store.items_changed.connect (on_items_changed);

        var previous_session = Session.get_instance ().get_session_notifications ();
        // Do not block animated drawing of wingpanel
        Idle.add_once (() => {
            foreach (unowned var notification in previous_session) {
                add_entry (notification);
            }
        });
    }

    private static int section_func (Notification a, Notification b) {
        unowned GLib.DateTime? time_a = app_datetime[a.desktop_id];
        unowned GLib.DateTime? time_b = app_datetime[b.desktop_id];

        if (time_a != null && time_b != null) {
            return time_b.compare (time_a);
        } else if (time_a != null) {
            return -1;
        } else if (time_b != null) {
            return 1;
        }

        return 0;
    }

    private void setup_factory (Object item) {
        var notification_entry = new NotificationEntry ();
        notification_entry.remove.connect (remove_notification);

        var list_item = (Gtk.ListItem) item;
        list_item.child = notification_entry;
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
        var app_entry =  new AppEntry ();
        app_entry.clear.connect (clear_app_entry);

        var list_item = (Gtk.ListHeader) item;
        list_item.child = app_entry;
    }

    private void bind_header_factory (Object item) {
        var list_item = (Gtk.ListHeader) item;
        var notification = (Notification) list_item.item;

        var app_entry = (AppEntry) list_item.child;
        app_entry.app_name = notification.app_name;
        app_entry.app_id = notification.desktop_id;
    }

    public async void add_entry (Notification notification) {
        unowned GLib.DateTime? time = app_datetime[notification.desktop_id];
        if (time == null || time.compare (notification.timestamp) <= 0) {
            app_datetime[notification.desktop_id] = notification.timestamp;
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

        items_changed ();
    }

    private void remove_notification (NotificationEntry notification_entry) {
        var app_id = notification_entry.notification.desktop_id;

        uint pos = -1;
        if (list_store.find (notification_entry.notification, out pos)) {
            list_store.remove (pos);
            Session.get_instance ().remove_notification (notification_entry.notification);
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

    private void on_row_activated (uint pos) {
        var notification = (Notification) sort_list_model.get_item (pos);
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
