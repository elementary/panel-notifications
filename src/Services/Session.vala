/*-
 * Copyright 2015-2021 elementary, Inc. (https://elementary.io)
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


/* This class is meant to remember the
 * notifications from the current session
 * and restore them in the next session.
 *
 */
public class Notifications.Session : GLib.Object {
    private const string SESSION_FILE_NAME = ".notifications.session";
    private static Session? instance = null;

    private File session_file = null;

    private const string ACTIONS_KEY = "Actions";
    private const string APP_ICON_KEY = "AppIcon";
    private const string APP_NAME_KEY = "AppName";
    private const string BODY_KEY = "Body";
    private const string IMAGE_KEY = "Image";
    private const string DESKTOP_ID_KEY = "DesktopID";
    private const string REPLACES_ID_KEY = "ReplacesID";
    private const string SENDER_KEY = "Sender";
    private const string SUMMARY_KEY = "Summary";
    private const string UNIX_TIME_KEY = "UnixTime";
    private const string HAS_TEMP_FILE_KEY = "HasTempFile";

    private KeyFile key;

    public static Session get_instance () {
        if (instance == null) {
            instance = new Session ();
        }

        return instance;
    }

    private Session () {
        session_file = File.new_for_path (Path.build_filename (Environment.get_user_cache_dir (), SESSION_FILE_NAME));
        if (!session_file.query_exists ()) {
            create_session_file ();
        }

        key = new KeyFile ();
        key.set_list_separator (';');
    }

    public List<Notification> get_session_notifications () {
        var list = new List<Notification> ();
        try {
            key.load_from_file (session_file.get_path (), KeyFileFlags.NONE);
            foreach (unowned string group in key.get_groups ()) {
                var notification = new Notification (
                    group,
                    key.get_string (group, APP_NAME_KEY),
                    key.get_string (group, APP_ICON_KEY),
                    key.get_string (group, SUMMARY_KEY),
                    key.get_string (group, BODY_KEY),
                    key.get_string (group, IMAGE_KEY),
                    key.get_string_list (group, ACTIONS_KEY),
                    key.get_string (group, DESKTOP_ID_KEY),
                    key.get_int64 (group, UNIX_TIME_KEY),
                    key.get_uint64 (group, REPLACES_ID_KEY),
                    key.get_string (group, SENDER_KEY),
                    key.get_boolean (group, HAS_TEMP_FILE_KEY)
                );
                list.prepend (notification);
            }
        } catch (KeyFileError e) {
            warning (e.message);
            create_session_file ();
        } catch (FileError e) {
            warning (e.message);
        }

        list.reverse ();
        return list;
    }

    public void add_notification (Notification notification, bool write_file = true) {
        string id = notification.internal_id;
        key.set_int64 (id, UNIX_TIME_KEY, notification.timestamp.to_unix ());
        key.set_string (id, APP_ICON_KEY, notification.app_icon);
        key.set_string (id, APP_NAME_KEY, notification.app_name);
        key.set_string (id, BODY_KEY, notification.message_body);
        key.set_string (id, IMAGE_KEY, notification.image_path);
        key.set_string (id, DESKTOP_ID_KEY, notification.desktop_id);
        key.set_string (id, SENDER_KEY, notification.sender);
        key.set_string (id, SUMMARY_KEY, notification.summary);
        key.set_string_list (id, ACTIONS_KEY, notification.actions);
        key.set_uint64 (id, REPLACES_ID_KEY, notification.replaces_id);
        key.set_boolean (id, HAS_TEMP_FILE_KEY, notification.has_temp_file);

        if (write_file) {
            write_contents ();
        }
    }

    public void remove_notification (Notification notification, bool write_file = true) {
        try {
            if (notification.has_temp_file) {
                var file = File.new_for_path (notification.image_path);
                try {
                    file.delete ();
                } catch (Error e) {
                    critical ("Unable to delete tmpfile: %s", notification.image_path);
                }
            }
            key.remove_group (notification.internal_id);
        } catch (KeyFileError e) {
            warning (e.message);
        }

        if (write_file) {
            write_contents ();
        }
    }

    public void clear () {
        try {
            FileUtils.set_contents (session_file.get_path (), "");
        } catch (FileError e) {
            warning (e.message);
        }
    }

    private void create_session_file () {
        try {
            session_file.create (FileCreateFlags.REPLACE_DESTINATION);
        } catch (Error e) {
            warning (e.message);
        }
    }

    private uint write_timeout_id = 0;
    private void write_contents () {
        if (write_timeout_id > 0) {
            Source.remove (write_timeout_id);
        }

        write_timeout_id = Timeout.add (1000, () => {
            write_timeout_id = 0;
            try {
                FileUtils.set_contents (session_file.get_path (), key.to_data ());
            } catch (FileError e) {
                warning (e.message);
            }

            return Source.REMOVE;
        });
    }
}
