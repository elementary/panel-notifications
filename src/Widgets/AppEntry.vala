/*-
 * Copyright 2015-2019 elementary, Inc. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

public class Notifications.AppEntry : Gtk.ListBoxRow {
    public signal void clear ();

    public string app_id { get; private set; }
    public AppInfo? app_info { get; construct; default = null; }
    public List<NotificationEntry> app_notifications;

    private static Gtk.CssProvider provider;
    private static Settings settings;
    private static HashTable<string, bool> headers;

    private Gtk.ToggleButton expander;

    static construct {
        provider = new Gtk.CssProvider ();
        provider.load_from_resource ("/io/elementary/wingpanel/notifications/AppEntry.css");
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        settings = new Settings ("io.elementary.panel.notifications");
        headers = (HashTable<string, bool>) settings.get_value ("headers");
    }

    public AppEntry (AppInfo? app_info) {
        Object (app_info: app_info);
    }

    construct {
        app_notifications = new List<NotificationEntry> ();

        unowned string name;
        if (app_info != null) {
            app_id = app_info.get_id ();
            name = app_info.get_name ();
        } else {
            app_id = "other";
            name = _("Other");
        }

        var image = new Gtk.Image.from_icon_name ("pan-end-symbolic");

        var label = new Gtk.Label (name) {
            hexpand = true,
            xalign = 0
        };
        label.add_css_class (Granite.STYLE_CLASS_H3_LABEL);

        var expander_content = new Gtk.Box (HORIZONTAL, 3);
        expander_content.append (label);
        expander_content.append (image);

        expander = new Gtk.ToggleButton () {
            child = expander_content,
            active = true
        };
        expander.add_css_class ("image-button");
        expander.add_css_class ("expander");

        var clear_btn_image = new Gtk.Image.from_icon_name ("edit-clear-all-symbolic");
        clear_btn_image.add_css_class ("sweep-animation");

        var clear_btn_entry = new Gtk.Button () {
            tooltip_text = _("Clear all %s notifications").printf (name),
            child = clear_btn_image,
            has_frame = false
        };

        var box = new Gtk.Box (HORIZONTAL, 6);
        box.append (expander);
        box.append (clear_btn_entry);

        margin_start = 12;
        margin_end = 12;
        margin_bottom = 3;
        margin_top = 6;
        can_focus = false;
        child = box;

        if (app_id in headers) {
            expander.active = headers[app_id];
        }

        expander.toggled.connect (() => {
            headers[app_id] = expander.active;
            settings.set_value ("headers", headers);
        });

        clear_btn_entry.clicked.connect (() => {
            clear_btn_image.add_css_class ("active");
            clear_all_notification_entries ();
            GLib.Timeout.add (600, () => {
                clear (); // Causes notification list to destroy this app entry after clearing its notification entries
                return GLib.Source.REMOVE;
            });
        });

        expander.bind_property ("active", image, "tooltip-text", SYNC_CREATE, (binding, srcval, ref targetval) => {
            targetval = (bool) srcval ? _("Show less") : _("Show more");
            return true;
        });
    }

    public void add_notification_entry (NotificationEntry entry) {
        app_notifications.prepend (entry);
        entry.clear.connect (remove_notification_entry);

        expander.bind_property ("active", entry.revealer, "reveal-child", SYNC_CREATE);
    }

    public void remove_notification_entry (NotificationEntry entry) {
        app_notifications.remove (entry);
        entry.dismiss ();

        Session.get_instance ().remove_notification (entry.notification);
        if (app_notifications.length () == 0) {
            if (headers.remove (app_id)) {
                settings.set_value ("headers", headers);
            }

            clear ();
        }
    }

    public void clear_all_notification_entries () {
        Notification[] to_remove = {};
        app_notifications.@foreach ((entry) => {
            entry.dismiss ();
            to_remove += entry.notification;
        });

        app_notifications = new List<NotificationEntry> ();
        Session.get_instance ().remove_notifications (to_remove);
    }
}
