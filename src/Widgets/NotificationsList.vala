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

public class Notifications.NotificationsList : Gtk.Bin {
    public signal void close_popover ();
    public signal void items_changed ();

    public const string ACTION_GROUP_PREFIX = "notifications-list";
    public const string ACTION_PREFIX = ACTION_GROUP_PREFIX + ".";

    public Gee.HashMap<string, AppEntry> app_entries { get; private set; }

    private HashTable<string, int> table;

    private Gtk.ListBox listbox;

    private static Settings settings;

    static construct {
        settings = new Settings ("io.elementary.wingpanel.notifications");
    }

    construct {
        app_entries = new Gee.HashMap<string, AppEntry> ();
        table = new HashTable<string, int> (str_hash, str_equal);

        var placeholder = new Gtk.Label (_("No Notifications")) {
            margin_top = 24,
            margin_bottom = 24,
            margin_start = 12,
            margin_end = 12,
            visible = true
        };

        unowned Gtk.StyleContext placeholder_style_context = placeholder.get_style_context ();
        placeholder_style_context.add_class (Granite.STYLE_CLASS_H2_LABEL);
        placeholder_style_context.add_class (Gtk.STYLE_CLASS_DIM_LABEL);

        listbox = new Gtk.ListBox () {
            activate_on_single_click = true,
            selection_mode = NONE
        };
        listbox.set_placeholder (placeholder);

        child = listbox;
        show_all ();

        insert_action_group (ACTION_GROUP_PREFIX, new NotificationsMonitor ().notifications_action_group);

        listbox.row_activated.connect (on_row_activated);
    }

    public async void add_entry (Notification notification, bool add_to_session = true) {
        var entry = new NotificationEntry (notification);

        if (app_entries[notification.desktop_id] != null) {
            var app_entry = app_entries[notification.desktop_id];

            resort_app_entry (app_entry);
            app_entry.add_notification_entry (entry);

            int insert_pos = table.get (app_entry.app_id);
            listbox.insert (entry, insert_pos + 1);
        } else {
            var app_entry = new AppEntry (notification.app_info);
            app_entry.add_notification_entry (entry);
            app_entry.clear.connect (clear_app_entry);

            app_entries[notification.desktop_id] = app_entry;

            listbox.prepend (app_entry);
            listbox.insert (entry, 1);
            table.insert (app_entry.app_id, 0);
        }

        show_all ();

        Idle.add (add_entry.callback);
        yield;

        if (add_to_session && settings.get_boolean ("keep-notifications")) { // If notification was obtained from session do not write it back
            Session.get_instance ().add_notification (notification);
        }

        items_changed ();
    }

    public uint count_notifications (out uint number_of_apps) {
        var count = 0;
        var n_apps = 0;

        for (int i = 0; listbox.get_row_at_index (i) != null; i++) {
            if (listbox.get_row_at_index (i) is NotificationEntry) {
                count++;
            } else if (listbox.get_row_at_index (i) is AppEntry) {
                n_apps++;
            }
        }

        number_of_apps = n_apps;
        return count;
    }

    public void clear_all () {
        var iter = app_entries.map_iterator ();
        while (iter.next ()) {
            var entry = iter.get_value ();
            iter.unset ();
            clear_app_entry (entry);
        }

        close_popover ();
    }

    private void resort_app_entry (AppEntry app_entry) {
        if (listbox.get_row_at_index (0) != app_entry) {
            listbox.remove (app_entry);
            listbox.prepend (app_entry);
            app_entry.app_notifications.foreach ((notification_entry) => {
                listbox.remove (notification_entry);
                listbox.insert (notification_entry, 1);
            });
        }
    }

    private void clear_app_entry (AppEntry app_entry) {
        app_entry.clear.disconnect (clear_app_entry);
        app_entries.unset (app_entry.app_id);
        app_entry.clear_all_notification_entries ();
        app_entry.destroy ();

        if (app_entries.size == 0) {
            Session.get_instance ().clear ();
        }

        items_changed ();
    }

    private void on_row_activated (Gtk.ListBoxRow row) {
        if (row is NotificationEntry) {
            unowned var notification_entry = (NotificationEntry) row;

            if (notification_entry.notification.default_action != null) {
                unowned var action_group = get_action_group (ACTION_GROUP_PREFIX);
                action_group.activate_action (notification_entry.notification.default_action, null);
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
