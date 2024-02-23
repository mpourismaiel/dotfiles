import { dependencies, sh } from "../utils/dots.js";
import options from "./options.js";

const WALLPAPER_PATH = `/home/${Utils.USER}/.config/background`;

async function wallpaper() {
  try {
    const pos = await sh("hyprctl cursorpos");

    await sh([
      "swww",
      "img",
      "--transition-type",
      "grow",
      "--transition-pos",
      pos.replace(" ", ""),
      WALLPAPER_PATH,
    ]);
  } catch (err) {
    Utils.notify({
      summary: "Error setting wallpaper",
      body: err,
      urgency: "critical",
    });
  }
}

export default async function InitializeWallpaper() {
  if (!dependencies("swww")) return;

  options.registerKey("wallpaper", WALLPAPER_PATH);
  Utils.monitorFile(WALLPAPER_PATH, () =>
    options.updateOption("wallpaper", WALLPAPER_PATH)
  );

  Utils.execAsync("swww init").catch(() => {});
  options.connect("wallpaper", wallpaper);
  wallpaper();
}
