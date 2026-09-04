/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2025 elementary, Inc. (https://elementary.io)
*/

public class Notifications.Indicator : Wingpanel.Indicator {
    private const string CHILD_SCHEMA_ID = "io.elementary.notifications.applications";
    private const string CHILD_PATH = "/io/elementary/notifications/applications/%s/";
    private const string KEYBINDING_SCHEMA = "io.elementary.panel.keybindings";
    private const string REMEMBER_KEY = "remember";

    private static GLib.HashTable<string, GLib.DateTime> app_datetime;
    private static GLib.Settings? keybinding_settings;
    private Gee.HashMap<string, Settings> app_settings_cache;
    private GLib.Settings notify_settings;

    private GLib.ListStore list_store;
    private Gtk.SortListModel sort_list_model;
    private Gtk.Box? main_box = null;
    private Wingpanel.PopoverMenuItem clear_all_btn;
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

        app_datetime = new GLib.HashTable<string, GLib.DateTime> (str_hash, str_equal);
    }

    construct {
        GLib.Intl.bindtextdomain (Notifications.GETTEXT_PACKAGE, Notifications.LOCALEDIR);
        GLib.Intl.bind_textdomain_codeset (Notifications.GETTEXT_PACKAGE, "UTF-8");

        notify_settings = new GLib.Settings ("io.elementary.notifications");
        app_settings_cache = new Gee.HashMap<string, Settings> ();

        monitor = new NotificationsMonitor ();

        list_store = new GLib.ListStore (typeof (Notification));

        sort_list_model = new Gtk.SortListModel (list_store, new Gtk.CustomSorter ((GLib.CompareDataFunc<GLib.Object>) Notification.compare)) {
            section_sorter = new Gtk.CustomSorter ((GLib.CompareDataFunc<GLib.Object>) section_func)
        };

        var previous_session = Session.get_instance ().get_session_notifications ();
        // Do not block animated drawing of wingpanel
        Idle.add_once (() => {
            foreach (unowned var notification in previous_session) {
                add_entry (notification);
            }
        });
    }

    public override Gtk.Widget get_display_widget () {
        if (dynamic_icon == null) {
            dynamic_icon = new NotificationsIndicator.Symbol ("/io/elementary/wingpanel/notifications/icons/notification.svg") {
                pixel_size = 24,
                tooltip_markup = _("Updating notifications…")
            };

            list_store.items_changed.connect (set_display_icon_name);

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
        if (main_box == null) {
            var not_disturb_switch = new Granite.SwitchModelButton (_("Do Not Disturb"));
            not_disturb_switch.add_css_class (Granite.STYLE_CLASS_H4_LABEL);

            var dnd_switch_separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL) {
                margin_top = 3,
                margin_bottom = 3
            };

            nlist = new NotificationsList (sort_list_model);

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

            clear_all_btn.clicked.connect (clear_all);

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
            add_entry (notification);

            Session.get_instance ().add_notification (notification);
        }

        set_display_icon_name ();
    }

    private void add_entry (Notification notification) {
        unowned GLib.DateTime? time = app_datetime[notification.desktop_id];
        if (time == null || time.compare (notification.timestamp) <= 0) {
            app_datetime[notification.desktop_id] = notification.timestamp;
            sort_list_model.section_sorter.changed (DIFFERENT);
        }

        list_store.append (notification);
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

    private uint get_n_app_items () {
        var app_list = new GenericSet<string> (str_hash, str_equal);
        for (var i = 0; i < list_store.n_items; i++) {
            app_list.add (((Notification) list_store.get_item (i)).desktop_id);
        }

        return app_list.length;
    }

    private void update_clear_all_sensitivity () {
        clear_all_btn.sensitive = list_store.get_n_items () > 0;
    }

    private void on_notification_closed (uint32 id, Notification.CloseReason reason) {
        for (int i = 0; i < list_store.get_n_items (); i++) {
            var notification = (Notification) list_store.get_item (i);
            if (id == notification.server_id) {
                notification.server_id = 0; // Notification is now outdated
                return;
            }
        }
    }

    private void clear_all () {
        Session.get_instance ().clear ();
        list_store.remove_all ();
        close ();
    }

    private void set_display_icon_name () {
        if (notify_settings.get_boolean ("do-not-disturb")) {
            dynamic_icon.state = NotificationsIndicator.SymbolState.DISABLED;
        } else if (nlist != null && list_store.get_n_items () > 0) {
            dynamic_icon.state = NotificationsIndicator.SymbolState.ACTIVE;
        } else {
            dynamic_icon.state = NotificationsIndicator.SymbolState.NORMAL;
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
        var number_of_notifications = list_store.get_n_items ();
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
                var number_of_apps = get_n_app_items ();
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
