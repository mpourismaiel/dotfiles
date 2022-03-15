local awful = require("awful")
local filesystem = require("gears.filesystem")
local xresources = require("beautiful.xresources")

local config_dir = filesystem.get_configuration_dir()

local config = {
  terminal = "kitty",
  modkey = "Mod4",
  dpi = xresources.apply_dpi,
  wallpaper = os.getenv("HOME") .. "/Pictures/wallpaper.jpg",
  auto_start = {
    debug_mode = false,
    apps = {
      -- Compositor
      "picom -b --experimental-backends --dbus --config " .. config_dir .. "/configuration/picom.conf",
      -- Polkit and keyring
      "/usr/bin/lxqt-policykit-agent &" .. " eval $(gnome-keyring-daemon -s --components=pkcs11,secrets,ssh,gpg)",
      -- Load X colors
      "xrdb $HOME/.Xresources",
      -- Audio equalizer
      "pulseeffects --gapplication-service",
      -- Lockscreen timer
      [[
      xidlehook --not-when-fullscreen --not-when-audio --timer 600 \
      "awesome-client 'awesome.emit_signal(\"module::lockscreen_show\")'" ""
      ]]
    }
  },
  commands = {
    rofi_appmenu = os.getenv("HOME") .. "/.config/rofi/launchers/misc/launcher.sh",
    full_screenshot = "flameshot full -p /home/mahdi/Pictures/Screenshots/ -c",
    area_screenshot = "flameshot gui"
  },
  tags = {
    {
      name = "1",
      layout = awful.layout.suit.max
    },
    {
      name = "2",
      layout = awful.layout.suit.max
    },
    {
      name = "3",
      layout = awful.layout.suit.max
    },
    {
      name = "4",
      layout = awful.layout.suit.max
    },
    {
      name = "5",
      layout = awful.layout.suit.max
    },
    {
      name = "6",
      layout = awful.layout.suit.max
    }
  }
}

return config
