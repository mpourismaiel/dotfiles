import Gdk from "gi://Gdk";

import InitializeWallpaper from "./lib/wallpaper.js";

import Bar from "./widgets/bar/main.js";
import AppLauncherMenu from "./widgets/launcher/main.js";
import { Menu } from "./widgets/menu/main.js";
import NotificationPopup from "./widgets/notification/main.js";
import { range } from "./utils/array.js";
import InfoPanel from "./widgets/info/main.js";
import InitializeStyles from "./lib/styles.js";
import SettingsWindow from "./windows/settings/main.js";
import { InitializeGlobalDefaults } from "./lib/options.js";
import { PowerMenu, Verification } from "./windows/powermenu.js";
import OSD from "./windows/osd.js";
import ShortcutHelper from "./windows/shortcut-helper.js";

const Notifications = await Service.import("notifications");
Notifications.popupTimeout = 5000;

function forMonitors(widget) {
  const n = Gdk.Display.get_default()?.get_n_monitors() || 1;
  return range(n, 0).map(widget).flat(1);
}

InitializeGlobalDefaults();
InitializeWallpaper();
InitializeStyles();

export default {
  windows: [
    Menu(),
    AppLauncherMenu(),
    InfoPanel(),
    SettingsWindow(),
    PowerMenu(),
    ShortcutHelper(),
    Verification(),
    ...forMonitors(Bar),
    ...forMonitors(NotificationPopup),
    ...forMonitors(OSD),
  ],
};
