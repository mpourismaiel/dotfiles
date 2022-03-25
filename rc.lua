-- awesome_mode: api-level=4:screen=on
-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")

local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local ruled = require("ruled")
local menubar = require("menubar")

require("configuration.tags")
require("configuration.keys")
require("configuration.ruled")
require("configuration.client")
require("configuration.notifications")
require("configuration.widgets.lockscreen")

local theme = require("configuration.config.theme")

naughty.connect_signal(
  "request::display_error",
  function(message, startup)
    naughty.notification {
      urgency = "critical",
      title = "Oops, an error happened" .. (startup and " during startup!" or "!"),
      message = message
    }
  end
)

beautiful.init(theme)

require("module.autostart")
require("module.weather")
require("configuration.bling")
local widgets = require("configuration.widgets")

screen.connect_signal(
  "request::wallpaper",
  function(s)
    awful.wallpaper {
      screen = s,
      widget = {
        {
          image = beautiful.wallpaper,
          upscale = true,
          downscale = true,
          widget = wibox.widget.imagebox
        },
        valign = "center",
        halign = "center",
        tiled = false,
        widget = wibox.container.tile
      }
    }
  end
)

screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    widgets.bar.new(s)
  end
)
