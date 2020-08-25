local awesome, client, mouse, screen, tag = awesome, client, mouse, screen, tag
local ipairs, string, os, table, tostring, tonumber, type = ipairs, string, os, table, tostring, tonumber, type

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local lain = require("lain")
require("awful.autofocus")

-- {{{ Error handling
-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
if awesome.startup_errors then
  naughty.notify(
    {
      preset = naughty.config.presets.critical,
      title = "Oops, there were errors during startup!",
      text = awesome.startup_errors
    }
  )
end

-- Handle runtime errors after startup
do
  local in_error = false
  awesome.connect_signal(
    "debug::error",
    function(err)
      if in_error then
        return
      end
      in_error = true

      naughty.notify(
        {
          preset = naughty.config.presets.critical,
          title = "Oops, an error happened!",
          text = tostring(err)
        }
      )
      in_error = false
    end
  )
end
-- }}}

awful.spawn.with_shell(string.format("sh %s/.config/awesome/autorun.sh", os.getenv("HOME")))

require("utils.variables")
require("utils.functions")

beautiful.init(string.format("%s/.config/awesome/themes/damn/theme.lua", os.getenv("HOME")))

require("screens")

local keys = require("keys")

root.keys(keys.globalkeys)

require("rules")(keys)
require("signals")(awesome, screen, client, tag)
