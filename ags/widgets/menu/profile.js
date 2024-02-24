import { IconMap } from "../../utils/icons.js";
import { WINDOW_NAME } from "../../windows/settings/main.js";

const GLib = imports.gi.GLib;
const Gio = imports.gi.Gio;

function getUserName() {
  const userName = GLib.get_user_name();
  return userName.slice(0, 1).toUpperCase() + userName.slice(1);
}

const ProfilePicture = () => {
  const file = Gio.File.new_for_path(GLib.get_home_dir() + "/.face");
  if (file.query_exists(null)) {
    return Widget.Icon({
      className: "profile-picture",
      css: `
        min-width: 36px;
        min-height: 36px;
        background-image: url("${file.get_uri()}");
        background-size: contain;
        background-repeat: no-repeat;
        background-position: center;
      `,
    });
  }
  return Widget.Box({
    className: "profile-picture",
    icon: "face-smile",
    size: 48,
  });
};

const Profile = ({ onClose }) =>
  Widget.Box({
    className: "card profile",
    spacing: 16,
    children: [
      ProfilePicture(),
      Widget.Box({
        vertical: true,
        children: [
          Widget.Label({ className: "username", label: getUserName() }),
          Widget.Box(),
        ],
      }),
      Widget.Box({
        hexpand: true,
      }),
      Widget.Button({
        className: "settings-button",
        onPrimaryClick: () => {
          onClose();
          App.closeWindow(WINDOW_NAME);
          App.openWindow(WINDOW_NAME);
        },
        child: Widget.Icon({ size: 16, icon: IconMap.ui.settings }),
      }),
    ],
  });

export default Profile;
