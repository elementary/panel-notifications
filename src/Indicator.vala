/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2025 elementary, Inc. (https://elementary.io)
*/

public class Notifications.Indicator : Wingpanel.Indicator {
    private const string CHILD_SCHEMA_ID = "io.elementary.notifications.applications";
    private const string CHILD_PATH = "/io/elementary/notifications/applications/%s/";
    private const string REMEMBER_KEY = "remember";

    private Gee.HashMap<string, Settings> app_settings_cache;
    private GLib.Settings notify_settings;

    private Gtk.Box? main_box = null;
    private Wingpanel.PopoverMenuItem clear_all_btn;
    private Gtk.Spinner? dynamic_icon = null;
    private NotificationsList nlist;

    private List<Notification> previous_session = null;
    private NotificationsMonitor monitor;

    public Indicator () {
        Object (
            code_name: Wingpanel.Indicator.MESSAGES,
            visible: true
        );
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
            var provider = new Gtk.CssProvider ();
            provider.load_from_resource ("io/elementary/wingpanel/notifications/indicator.css");

            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            dynamic_icon = new Gtk.Spinner () {
                spinning = true,
                tooltip_markup = _("Updating notifications…")
            };
            dynamic_icon.add_css_class ("notification-icon");

            nlist = new NotificationsList ();

            monitor.notification_received.connect (on_notification_received);
            monitor.notification_closed.connect (on_notification_closed);
            monitor.init.begin ((obj, res) => {
                try {
                    ((NotificationsMonitor) obj).init.end (res);
                } catch (Error e) {
                    critical ("Unable to monitor notifications bus: %s", e.message);
                }
            });

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

            previous_session = Session.get_instance ().get_session_notifications ();
            Timeout.add (2000, () => { // Do not block animated drawing of wingpanel
                load_session_notifications.begin (() => { // load asynchromously so spinner continues to rotate
                    set_display_icon_name ();
                    nlist.items_changed.connect (set_display_icon_name);
                });

                return Source.REMOVE;
            });
        }

        return dynamic_icon;
    }

    private async void load_session_notifications () {
        foreach (var notification in previous_session) {
            yield nlist.add_entry (notification, false); // This is slow as NotificationEntry is complex
        }
    }

    public override Gtk.Widget? get_widget () {
        if (main_box == null) {
            var not_disturb_switch = new Granite.SwitchModelButton (_("Do Not Disturb"));
            not_disturb_switch.add_css_class (Granite.STYLE_CLASS_H4_LABEL);

            var dnd_switch_separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL) {
                margin_top = 3,
                margin_bottom = 3
            };

            var scrolled = new Gtk.ScrolledWindow () {
                child = nlist,
                hscrollbar_policy = NEVER,
                max_content_height = 500,
                propagate_natural_height = true
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

            main_box = new Gtk.Box (VERTICAL, 0) {
                width_request = 360
            };
            main_box.append (not_disturb_switch);
            main_box.append (dnd_switch_separator);
            main_box.append (scrolled);
            main_box.append (clear_all_btn_separator);
            main_box.append (clear_all_btn);
            main_box.append (settings_btn);

            notify_settings.bind ("do-not-disturb", not_disturb_switch, "active", GLib.SettingsBindFlags.DEFAULT);

            nlist.close_popover.connect (() => close ());
            nlist.items_changed.connect (update_clear_all_sensitivity);

            clear_all_btn.clicked.connect (() => {
                nlist.clear_all (); // This calls each appentry's clear method, which also clears session
            });

            settings_btn.clicked.connect (show_settings);
        }

        return main_box;
    }

    public override void opened () {
        update_clear_all_sensitivity ();
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
            nlist.add_entry.begin (notification, true);
        }

        set_display_icon_name ();
    }

    private void update_clear_all_sensitivity () {
        clear_all_btn.sensitive = nlist.app_entries.size > 0;
    }

    private void on_notification_closed (uint32 id, Notification.CloseReason reason) {
        SearchFunc<NotificationEntry, uint32> find_entry = (e, i) => {
            return i == e.notification.server_id ? 0 : i > e.notification.server_id ? 1 : -1;
        };

        foreach (var app_entry in nlist.app_entries.values) {
            unowned var node = app_entry.app_notifications.search (id, find_entry);
            if (node != null) {
                node.data.notification.server_id = 0; // Notification is now outdated
                node.data.clear ();
                return;
            }
        }
    }

    private void set_display_icon_name () {
        if (notify_settings.get_boolean ("do-not-disturb")) {
            dynamic_icon.add_css_class ("disabled");
        } else if (nlist != null && nlist.app_entries.size > 0) {
            dynamic_icon.remove_css_class ("disabled");
            dynamic_icon.add_css_class ("new");
        } else {
            dynamic_icon.remove_css_class ("disabled");
            dynamic_icon.remove_css_class ("new");
        }
        update_tooltip ();
    }

    private void show_settings () {
        close ();

        try {
            AppInfo.launch_default_for_uri ("settings://notifications", null);
        } catch (Error e) {
            warning ("Failed to open notifications settings: %s", e.message);
        }
    }

    private void update_tooltip () {
        uint number_of_apps = 0;
        uint number_of_notifications = nlist.count_notifications (out number_of_apps);
        string description;
        string accel_label;

        if (notify_settings.get_boolean ("do-not-disturb")) {
            accel_label = _("Middle-click to disable Do Not Disturb");
        } else {
            accel_label = _("Middle-click to enable Do Not Disturb");
        }

        accel_label = Granite.TOOLTIP_SECONDARY_TEXT_MARKUP.printf (accel_label);

        switch (number_of_notifications) {
            case 0:
                description = _("No notifications");
                break;
            case 1:
                description = _("1 notification");
                break;
            default:
                /// TRANSLATORS: A tooltip text for the indicator representing the number of notifications.
                /// e.g. "2 notifications from 1 app" or "5 notifications from 3 apps"
                description = _("%s from %s").printf (
                    dngettext (GETTEXT_PACKAGE, "%u notification", "%u notifications", number_of_notifications).printf (number_of_notifications),
                    dngettext (GETTEXT_PACKAGE, "%u app", "%u apps", number_of_apps).printf (number_of_apps)
                );
                break;
        }

        dynamic_icon.tooltip_markup = "%s\n%s".printf (description, accel_label);
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
