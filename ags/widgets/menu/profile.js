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
      icon: file.get_uri(),
      size: 48,
    });
  }
  return Widget.Icon({
    className: "profile-picture",
    icon: "face-smile",
    size: 48,
  });
};

const Profile = () =>
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
    ],
  });

export default Profile;
