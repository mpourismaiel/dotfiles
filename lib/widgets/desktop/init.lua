local capi = {}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")

local wallpaper = require("lib.widgets.desktop.wallpaper")

local boxes = {}
local desktop = {mt = {}}

local function new(screen)
  local ret =
    wibox {
    visible = true,
    ontop = false,
    screen = screen,
    type = "desktop",
    widget = wibox.widget {
      layout = wibox.layout.stack,
      {
        widget = wallpaper
      }
    }
  }

  awful.placement.maximize(ret)

  return ret
end

awful.screen.connect_for_each_screen(
  function(screen)
    if not boxes[screen] then
      boxes[screen] = new(screen)
    end
  end
)
