local awful = require("awful")
local naughty = require("naughty")
local os = os

awful.util.modkey = "Mod4"
awful.util.altkey = "Mod1"
awful.util.terminal = "xterm"

naughty.config.padding = 20
naughty.config.defaults.icon_size = 36
naughty.config.defaults.margin = 10
naughty.config.defaults.position = "bottom_right"

awful.layout.layouts = {
  awful.layout.suit.tile,
  awful.layout.suit.floating,
  awful.layout.suit.max
}

awful.util.tagnames = {
  "",
  "",
  "",
  "",
  "",
  "6",
  "7",
  "8",
  "9"
}

awful.util.tags = {
  {
    text = awful.util.tagnames[1],
    layout = awful.layout.suit.max
  },
  {
    icon_only = false,
    text = awful.util.tagnames[2],
    layout = awful.layout.suit.max
  },
  {
    icon_only = false,
    text = awful.util.tagnames[3],
    layout = awful.layout.suit.tile
  },
  {
    icon_only = false,
    text = awful.util.tagnames[4],
    layout = awful.layout.suit.max
  },
  {
    icon_only = false,
    text = awful.util.tagnames[5],
    layout = awful.layout.suit.max
  },
  {
    icon_only = false,
    text = awful.util.tagnames[6]
  },
  {
    icon_only = false,
    text = awful.util.tagnames[7]
  },
  {
    icon_only = false,
    text = awful.util.tagnames[8]
  },
  {
    icon_only = false,
    text = awful.util.tagnames[9]
  }
}
