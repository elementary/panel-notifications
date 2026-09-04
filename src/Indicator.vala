/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2025 elementary, Inc. (https://elementary.io)
*/

public class Notifications.Indicator : Wingpanel.Indicator {
    private const string CHILD_SCHEMA_ID = "io.elementary.notifications.applications";
    private const string CHILD_PATH = "/io/elementary/notifications/applications/%s/";
    private const string KEYBINDING_SCHEMA = "io.elementary.panel.keybindings";
    private const string REMEMBER_KEY = "remember";

    private static GLib.Settings? keybinding_settings;
    private Gee.HashMap<string, Settings> app_settings_cache;
    private GLib.Settings notify_settings;

    private NotificationsIndicator.Symbol? dynamic_icon = null;
    private NotificationsList nlist;
    private NotificationsMonitor monitor;

    public Indicator () {
        Object (
            code_name: Wingpanel.Indicator.MESSAGES,
            visible: true
        );
    }

    static construct {
        if (SettingsSchemaSource.get_default ().lookup (KEYBINDING_SCHEMA, true) != null) {
            keybinding_settings = new GLib.Settings (KEYBINDING_SCHEMA);
        }
    }

    construct {
        GLib.Intl.bindtextdomain (Notifications.GETTEXT_PACKAGE, Notifications.LOCALEDIR);
        GLib.Intl.bind_textdomain_codeset (Notifications.GETTEXT_PACKAGE, "UTF-8");

        notify_settings = new GLib.Settings ("io.elementary.notifications");
        app_settings_cache = new Gee.HashMap<string, Settings> ();

        monitor = new NotificationsMonitor ();
    }

    public override Gtk.Widget get_display_widget () {
        if (dynamic_icon == null) {
            dynamic_icon = new NotificationsIndicator.Symbol ("/io/elementary/wingpanel/notifications/icons/notification.svg") {
                pixel_size = 24,
                tooltip_markup = _("Updating notifications…")
            };

            nlist = new NotificationsList ();
            nlist.items_changed.connect (set_display_icon_name);

            monitor.notification_received.connect (on_notification_received);
            monitor.notification_closed.connect (on_notification_closed);
            monitor.init.begin ((obj, res) => {
                try {
                    ((NotificationsMonitor) obj).init.end (res);
                } catch (Error e) {
                    critical ("Unable to monitor notifications bus: %s", e.message);
                }
            });

            if (keybinding_settings != null) {
                keybinding_settings.changed["panel-notifications-menu"].connect (update_tooltip);
            }

            notify_settings.changed["do-not-disturb"].connect (() => {
                set_display_icon_name ();
            });

            var gesture_click = new Gtk.GestureClick () {
                button = Gdk.BUTTON_MIDDLE
            };

            gesture_click.pressed.connect (() => {
                notify_settings.set_boolean ("do-not-disturb", !notify_settings.get_boolean ("do-not-disturb"));
                gesture_click.set_state (CLAIMED);
                gesture_click.reset ();
            });

            dynamic_icon.add_controller (gesture_click);
        }

        return dynamic_icon;
    }

    public override Gtk.Widget? get_widget () {
        if (nlist == null) {
            nlist.close_popover.connect (() => close ());
        }

        return nlist;
    }

    public override void opened () {
    }

    public override void closed () {

    }

    private void on_notification_received (DBusMessage message, uint32 id) {
        var notification = new Notification.from_message (message, id);

        string app_id = notification.desktop_id.replace (Notification.DESKTOP_ID_EXT, "");
        Settings? app_settings = app_settings_cache.get (app_id);

        var schema = SettingsSchemaSource.get_default ().lookup (CHILD_SCHEMA_ID, true);
        if (schema != null && app_settings == null && app_id != "") {
            app_settings = new Settings.full (schema, null, CHILD_PATH.printf (app_id));
            app_settings_cache.set (app_id, app_settings);
        }

        if (app_settings == null || app_settings.get_boolean (REMEMBER_KEY)) {
            nlist.add_entry.begin (notification);

            Session.get_instance ().add_notification (notification);
        }

        set_display_icon_name ();
    }

    private void on_notification_closed (uint32 id, Notification.CloseReason reason) {
        for (int i = 0; i < nlist.notification_items.get_n_items (); i++) {
            var notification = (Notification) nlist.notification_items.get_item (i);
            if (id == notification.server_id) {
                notification.server_id = 0; // Notification is now outdated
                return;
            }
        }
    }

    private void set_display_icon_name () {
        if (notify_settings.get_boolean ("do-not-disturb")) {
            dynamic_icon.state = NotificationsIndicator.SymbolState.DISABLED;
        } else if (nlist != null && nlist.notification_items.get_n_items () > 0) {
            dynamic_icon.state = NotificationsIndicator.SymbolState.ACTIVE;
        } else {
            dynamic_icon.state = NotificationsIndicator.SymbolState.NORMAL;
        }
        update_tooltip ();
    }

    private void update_tooltip () {
        var number_of_notifications = nlist.notification_items.get_n_items ();
        string[] accels = {};
        string description;
        string middle_click_label = "";

        if (keybinding_settings != null) {
            var raw_accels = keybinding_settings.get_strv ("open-menu-notifications");
            foreach (unowned string raw_accel in raw_accels) {
                if (raw_accel != "") accels += raw_accel;
            }
        }

        if (notify_settings.get_boolean ("do-not-disturb")) {
            middle_click_label += _("Middle-click to disable Do Not Disturb");
        } else {
            middle_click_label += _("Middle-click to enable Do Not Disturb");
        }

        middle_click_label = Granite.TOOLTIP_SECONDARY_TEXT_MARKUP.printf (middle_click_label);

        switch (number_of_notifications) {
            case 0:
                description = _("No notifications");
                break;
            case 1:
                description = _("1 notification");
                break;
            default:
                var number_of_apps = nlist.get_n_app_items ();
                /// TRANSLATORS: A tooltip text for the indicator representing the number of notifications.
                /// e.g. "2 notifications from 1 app" or "5 notifications from 3 apps"
                description = _("%s from %s").printf (
                    dngettext (GETTEXT_PACKAGE, "%u notification", "%u notifications", number_of_notifications).printf (number_of_notifications),
                    dngettext (GETTEXT_PACKAGE, "%i app", "%u apps", number_of_apps).printf (number_of_apps)
                );
                break;
        }

        dynamic_icon.tooltip_markup = "%s\n%s".printf (Granite.markup_accel_tooltip (accels, description), middle_click_label);
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    debug ("Activating Notifications Indicator");

    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }

    var indicator = new Notifications.Indicator ();
    return indicator;
}
