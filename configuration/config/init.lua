local xresources = require("beautiful.xresources")

local config = {
  terminal = "kitty",
  modkey = "Mod4",
  rofi_appmenu = os.getenv("HOME") .. "/.config/rofi/launchers/misc/launcher.sh",
  dpi = xresources.apply_dpi,
  wallpaper = os.getenv("HOME") .. "/Pictures/wallpaper.jpg"
}

return config
