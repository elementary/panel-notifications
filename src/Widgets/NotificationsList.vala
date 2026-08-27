/*-
 * Copyright 2015-2020 elementary, Inc (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public class Notifications.NotificationsList : Granite.Bin {
    public signal void close_popover ();
    public signal void items_changed ();

    public const string ACTION_GROUP_PREFIX = "notifications-list";
    public const string ACTION_PREFIX = ACTION_GROUP_PREFIX + ".";

    private GLib.HashTable<string, GLib.DateTime> app_datetime;
    public Gee.HashMap<string, AppEntry> app_entries { get; private set; }

    private ListStore list_store;
    public ListModel notification_items {
        get {
            return list_store;
        }
    }

    construct {
        app_entries = new Gee.HashMap<string, AppEntry> ();
        app_datetime = new GLib.HashTable<string, GLib.DateTime> (str_hash, str_equal);

        var placeholder = new Gtk.Label (_("No Notifications")) {
            margin_top = 24,
            margin_bottom = 24,
            margin_start = 12,
            margin_end = 12,
            visible = true
        };
        placeholder.add_css_class (Granite.STYLE_CLASS_H2_LABEL);
        placeholder.add_css_class (Granite.CssClass.DIM);

        list_store = new GLib.ListStore (typeof (NotificationEntry));

        var listbox = new Gtk.ListBox () {
            activate_on_single_click = true,
            selection_mode = NONE
        };
        listbox.bind_model (list_store, (object) => (NotificationEntry) object);
        listbox.set_placeholder (placeholder);
        listbox.set_header_func (header_func);

        child = listbox;

        insert_action_group (ACTION_GROUP_PREFIX, new NotificationsMonitor ().notifications_action_group);

        listbox.row_activated.connect (on_row_activated);

        list_store.items_changed.connect (() => items_changed ());

        var previous_session = Session.get_instance ().get_session_notifications ();
        // Do not block animated drawing of wingpanel
        Idle.add_once (() => {
            foreach (unowned var notification in previous_session) {
                add_entry (notification);
            }
        });
    }

    private int sort_func (Object obj1, Object obj2) {
        var a = ((NotificationEntry) obj1).notification;
        var b = ((NotificationEntry) obj2).notification;
        if (a.desktop_id == b.desktop_id) {
            return Notification.compare (a, b);
        }

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

    private void header_func (Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
        unowned var row_entry = (NotificationEntry) row;
        unowned NotificationEntry? before_entry = (NotificationEntry) before;
        unowned string row_app_id = row_entry.notification.desktop_id;

        if (before != null && row_app_id == before_entry.notification.desktop_id) {
            row.set_header (null);
            return;
        }

        var app_entry = app_entries[row_app_id];
        if (app_entry == null) {
            app_entry = new AppEntry (row_entry.notification.app_info);
            app_entry.clear.connect (clear_app_entry);

            app_entries[row_app_id] = app_entry;
        }

        app_entry.add_notification_entry (row_entry);

        row.set_header (app_entries[row_app_id]);
    }

    public async void add_entry (Notification notification) {
        var entry = new NotificationEntry (notification);
        list_store.insert_sorted (entry, sort_func);

        unowned GLib.DateTime? time = app_datetime[notification.desktop_id];
        if (time == null || time.compare (notification.timestamp) <= 0) {
            app_datetime[notification.desktop_id] = notification.timestamp;
        }

        Idle.add (add_entry.callback);
        yield;
    }

    public void clear_all () {
        var iter = app_entries.map_iterator ();
        while (iter.next ()) {
            var entry = iter.get_value ();
            iter.unset ();
            clear_app_entry (entry);
        }

        list_store.remove_all ();
        close_popover ();
    }

    private void clear_app_entry (AppEntry app_entry) {
        app_entry.clear.disconnect (clear_app_entry);
        app_entries.unset (app_entry.app_id);
        app_entry.clear_all_notification_entries ();

        if (app_entries.size == 0) {
            Session.get_instance ().clear ();
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
                    notification_entry.clear ();
                    close_popover ();
                } catch (Error e) {
                    warning ("Unable to launch app: %s", e.message);
                }
            }
        }
    }
}
