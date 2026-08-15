/*
* SPDX-License-Identifier: LGPL-2.1-or-later
* SPDX-FileCopyrightText: 2026 elementary, Inc. (https://elementary.io)
*/

public class Granite.Symbol : Granite.Bin{
    public string resource_path { get; construct; }

    public int pixel_size {
        get { return image.pixel_size; }
        set { image.pixel_size = value; }
    }

    public uint state {
        get { return svg.state; }
        set { svg.state = value; }
    }

    private Gtk.Image image;
    private Gtk.Svg svg;

    public Symbol (string resource_path) {
        Object (resource_path: resource_path);
    }

    construct {
        svg = new Gtk.Svg.from_resource (resource_path);

        image = new Gtk.Image.from_paintable (svg);

        child = image;

        child.realize.connect (() => {
            svg.set_frame_clock (get_frame_clock ());
            svg.play ();
        });
    }
}
