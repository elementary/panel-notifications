project(
    'notifications',
    'vala', 'c',
    version: '7.1.1',
    meson_version: '>= 0.58.0'
)

gettext_name = 'io.elementary.panel.' + meson.project_name()
gnome = import('gnome')
i18n = import('i18n')

prefix = get_option('prefix')
libdir = prefix / get_option('libdir')

add_global_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(gettext_name),
    language:'c'
)
add_project_arguments('-DG_LOG_DOMAIN="io.elementary.panel.notifications"', language:'c')

gresource = gnome.compile_resources(
    'gresource',
    'data' / 'gresource.xml',
    source_dir: 'data'
)

wingpanel_dep = dependency('wingpanel-9')
wingpanel_indicatorsdir = wingpanel_dep.get_variable('indicatorsdir', pkgconfig_define: ['libdir', libdir])

config_data = configuration_data()
config_data.set('GETTEXT_PACKAGE', meson.project_name() + '-indicator')
config_data.set('LOCALEDIR', prefix / get_option('localedir'))
config_vala = configure_file(
    input: 'src/Config.vala.in',
    output: '@BASENAME@',
    configuration: config_data
)

shared_module(
    meson.project_name(),
    'src/Indicator.vala',
    'src/Widgets/NotificationsList.vala',
    'src/Widgets/NotificationEntry.vala',
    'src/Widgets/AppEntry.vala',
    'src/Services/NotificationsMonitor.vala',
    'src/Services/Notification.vala',
    'src/Services/Session.vala',
    gresource,
    config_vala,
    dependencies: [
        dependency('glib-2.0'),
        dependency('gobject-2.0'),
        dependency('granite-7', version: '>=7.7.0'),
        dependency('gtk4'),
        dependency('libadwaita-1'),
        wingpanel_dep
    ],
    install: true,
    install_dir : wingpanel_indicatorsdir,
)

gnome.post_install (glib_compile_schemas: true)

subdir('data')
subdir('po')
