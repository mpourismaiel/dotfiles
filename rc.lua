-- awesome_mode: api-level=4:screen=on
-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")

local filesystem = require("gears.filesystem")
local config_dir = filesystem.get_configuration_dir()

local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local ruled = require("ruled")
local bling = require("bling")
local menubar = require("menubar")
local helpers = require("module.helpers")

require("configuration.tags")
require("configuration.keys")
require("configuration.ruled")
require("configuration.client")
require("configuration.notifications")
require("configuration.widgets.lockscreen")
require("configuration.widgets.volume.osd")

local theme = require("configuration.config.theme")
local global_state = require("configuration.config.global_state")

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

bling.module.wallpaper.setup {
  wallpaper = {beautiful.wallpaper},
  position = "maximized"
}

screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    global_state.bar = widgets.bar.new(s)
    require("module.launcher")(s)
  end
)

if helpers.module_check("liblua_pam") == false then
  naughty.notification {
    title = "Missing dependency!",
    message = "Please install lua-pam library for lockscreen to work",
    timeout = 5
  }
end
