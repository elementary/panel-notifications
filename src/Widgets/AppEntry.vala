/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2015-2026 elementary, Inc. (https://elementary.io)
*/

public class Notifications.AppEntry : Granite.Bin {
    public signal void clear ();

    private string _app_id = "";
    public string app_id {
        get {
            return _app_id;
        }
        set {
            _app_id = value;

            if (value in headers) {
                expander.active = headers[value];
            }
        }
    }

    public string app_name { get; set; default = ""; }

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

    construct {
        var image = new Gtk.Image.from_icon_name ("pan-end-symbolic");

        var label = new Granite.HeaderLabel (name) {
            hexpand = true,
            size = H3
        };

        var expander_content = new Granite.Box (HORIZONTAL, HALF);
        expander_content.append (label);
        expander_content.append (image);

        expander = new Gtk.ToggleButton () {
            child = expander_content,
            has_frame = false,
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

        var box = new Granite.Box (HORIZONTAL, HALF);
        box.append (expander);
        box.append (clear_btn_entry);

        margin_bottom = 3;
        margin_top = 6;
        child = box;

        bind_property ("app-name", label, "label");

        expander.toggled.connect (() => {
            headers[app_id] = expander.active;
            settings.set_value ("headers", headers);
        });

        clear_btn_entry.clicked.connect (() => {
            clear_btn_image.add_css_class ("active");
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
}
