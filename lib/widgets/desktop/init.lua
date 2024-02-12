local capi = {
  screen = screen
}

local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")

local wallpaper = require("lib.widgets.desktop.wallpaper")
local icons = require("lib.widgets.desktop.icons")

local wallpapers = {}
local desktop = {mt = {}}

local function new_wallpaper(screen)
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

local function new(screen)
  local ret = setmetatable({}, desktop.mt)

  local is_primary_screen = screen == capi.screen.primary
  ret._private = {
    screen = screen,
    wallpaper = new_wallpaper(screen),
    icons = is_primary_screen and icons(screen) or nil
  }

  return ret
end

awful.screen.connect_for_each_screen(
  function(screen)
    if not wallpapers[screen] then
      wallpapers[screen] = new(screen)
    end
  end
)
