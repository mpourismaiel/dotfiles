local awful = require("awful")
local naughty = require("naughty")

awful.util.modkey = "Mod4"
awful.util.altkey = "Mod1"
awful.util.terminal = "xterm"

naughty.config.padding = 20
naughty.config.defaults.icon_size = 36
naughty.config.defaults.margin = 10
naughty.config.defaults.position = "bottom_right"

awful.util.tagnames = {
  "  ",
  "  ",
  "  ",
  "  ",
  "  ",
  " 6 ",
  " 7 ",
  " 8 ",
  " 9 "
}

awful.layout.layouts = {
  awful.layout.suit.tile,
  awful.layout.suit.floating,
  awful.layout.suit.max
}
