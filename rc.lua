local capi = {
  screen = screen
}
local collectgarbage = collectgarbage
collectgarbage("incremental", 110, 1000)
pcall(require, "luarocks.loader")

require("awful.autofocus")

local wibox = require("wibox")
local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local gears = require("gears")

local config_dir = gears.filesystem.get_configuration_dir()
package.path = package.path .. ";" .. config_dir .. "/external/?.lua;" .. config_dir .. "/external/?/init.lua"

local helpers = require("lib.module.helpers")

require("lib.tags")
require("lib.keys")
require("lib.ruled")
require("lib.client")
require("lib.notifications")
require("lib.widgets.lockscreen")
require("lib.widgets.volume.osd")

local theme = require("lib.configuration.theme")

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

require("lib.module.autostart")
require("lib.module.launcher.dialog")()
require("lib.module.calendar")()
require("lib.module.debug")
require("lib.widgets.bar")()

awful.screen.connect_for_each_screen(
  function(s)
    require("lib.module.launcher")(s)

    local widget =
      wibox.widget {
      widget = wibox.widget.imagebox,
      resize = true,
      horizontal_fit_policy = "fit",
      vertical_fit_policy = "fit",
      image = theme.wallpaper
    }

    awful.wallpaper {
      screen = s,
      widget = widget
    }
  end
)

if helpers.module_check("liblua_pam") == false then
  naughty.notification {
    title = "Missing dependency!",
    message = "Please install lua-pam library for lockscreen to work",
    timeout = 5
  }
end
