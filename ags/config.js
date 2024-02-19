import Gdk from "gi://Gdk";
import Bar from "./widgets/bar/main.js";
import AppLauncherMenu from "./widgets/launcher/main.js";
import { Menu } from "./widgets/menu/main.js";
import { NotificationPopup } from "./widgets/notification/main.js";
import { range } from "./widgets/_utils/array.js";
import InfoPanel from "./widgets/info/main.js";

function forMonitors(widget) {
  const n = Gdk.Display.get_default()?.get_n_monitors() || 1;
  return range(n, 0).map(widget).flat(1);
}

function applyStyles() {
  const scss = `${App.configDir}/styles/style.scss`;
  const css = `${App.configDir}/style.css`;
  App.applyCss(css);

  Utils.exec(`sass ${scss} ${css}`);

  Utils.monitorFile(css, function () {
    App.resetCss();
    App.applyCss(css);
    console.log("[LOG] Styles loaded");
  });
}

applyStyles();
forMonitors(Bar);
forMonitors(NotificationPopup);

export default {
  windows: [Menu(), AppLauncherMenu(), InfoPanel()],
};
