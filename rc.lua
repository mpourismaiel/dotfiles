local collectgarbage = collectgarbage
collectgarbage("incremental", 110, 1000)
pcall(require, "luarocks.loader")

require("awful.autofocus")

local beautiful = require("beautiful")
local naughty = require("naughty")
local bling = require("external.bling")
local gears = require("gears")

local config_dir = gears.filesystem.get_configuration_dir()
package.path = package.path .. ";" .. config_dir .. "/external/?.lua;" .. config_dir .. "/external/?/init.lua"
print("package.path:", package.path)

local helpers = require("lib.module.helpers")

require("lib.tags")
require("lib.keys")
require("lib.ruled")
require("lib.client")
require("lib.notifications")
require("lib.widgets.lockscreen")
require("lib.widgets.volume.osd")

local theme = require("lib.configuration.theme")
local global_state = require("lib.configuration.global_state")

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
require("lib.module.weather")
require("lib.module.launcher.dialog")()
require("lib.module.calendar")()
require("lib.module.debug")
local widgets = require("lib.widgets")

bling.module.wallpaper.setup {
  wallpaper = {beautiful.wallpaper},
  position = "maximized"
}

screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    global_state.bar = widgets.bar.new(s)
    require("lib.module.launcher")(s)
  end
)

if helpers.module_check("liblua_pam") == false then
  naughty.notification {
    title = "Missing dependency!",
    message = "Please install lua-pam library for lockscreen to work",
    timeout = 5
  }
end
