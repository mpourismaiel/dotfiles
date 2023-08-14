local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")

local wallpaper = {mt = {}}

local function new(screen)
  local widget =
    wibox.widget {
    widget = wibox.widget.imagebox,
    resize = true,
    horizontal_fit_policy = "fit",
    vertical_fit_policy = "fit",
    image = theme.wallpaper
  }

  capi.awesome.connect_signal(
    "module::config::wallpaper_changed",
    function(self, config)
      widget.image = config.wallpaper
    end
  )

  return widget
end

function wallpaper.mt:__call(...)
  return new(...)
end

return setmetatable(wallpaper, wallpaper.mt)
