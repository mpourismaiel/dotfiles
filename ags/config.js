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

function forMonitors(widget) {
  const n = Gdk.Display.get_default()?.get_n_monitors() || 1;
  return range(n, 0).map(widget).flat(1);
}

InitializeGlobalDefaults();
InitializeWallpaper();
InitializeStyles();

forMonitors(Bar);
forMonitors(NotificationPopup);

export default {
  windows: [Menu(), AppLauncherMenu(), InfoPanel(), SettingsWindow()],
};
