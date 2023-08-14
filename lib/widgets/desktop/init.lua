local capi = {}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")

local wallpaper = require("lib.widgets.desktop.wallpaper")

local desktop = {mt = {}}

local function new(screen)
  local ret =
    wibox.widget {
    layout = wibox.layout.stack,
    wallpaper(screen)
  }

  return ret
end

awful.screen.connect_for_each_screen(
  function(screen)
    awful.wallpaper {
      screen = screen,
      widget = new(screen)
    }
  end
)
