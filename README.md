# Wingpanel Notifications Indicator
[![Translation status](https://l10n.elementaryos.org/widget/wingpanel/notifications/svg-badge.svg)](https://l10n.elementaryos.org/engage/wingpanel/)

![Screenshot](data/screenshot.png?raw=true)

## Building and Installation

You'll need the following dependencies:

* libadwaita-1-dev
* libgdk-pixbuf-2.0-dev
* libglib2.0-dev
* libgranite-7-dev >= 7.7.0
* libgtk-4-dev
* libwingpanel-9-dev
* meson >= 0.58.0
* valac

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install
