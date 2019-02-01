local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local markup = require("lain.util.markup")
local helpers = require("helpers")
local pad = helpers.pad
local keygrabber = require("awful.keygrabber")

-- Get screen geometry
local screen_width = awful.screen.focused().geometry.width
local screen_height = awful.screen.focused().geometry.height

-- Create the widget
settings_menu =
  wibox(
  {
    x = screen_width - (beautiful.settings_menu_width or 400),
    y = 0,
    visible = false,
    ontop = true,
    type = "dock",
    height = screen_height,
    width = (beautiful.settings_menu_width or 400)
  }
)

settings_menu.bg = beautiful.settings_menu_bg or beautiful.wibar_bg or "#111111"
settings_menu.fg = beautiful.settings_menu_bg or beautiful.wibar_fg or "#FEFEFE"
