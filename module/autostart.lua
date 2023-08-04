local awful = require("awful")
local gears = require("gears")
local naughty = require("naughty")
local config = require("lib.config")
local debug_mode = config.auto_start.debug_mode or false

local run_once = function(cmd)
  local findme = cmd
  local firstspace = cmd:find(" ")
  if firstspace then
    findme = cmd:sub(0, firstspace - 1)
  end
  awful.spawn.easy_async_with_shell(
    string.format("pgrep -u $USER -x %s > /dev/null || (%s)", findme, cmd),
    function(stdout, stderr)
      -- Debugger
      if not stderr or stderr == "" or not debug_mode then
        return
      end
      naughty.notification(
        {
          app_name = "Start-up Applications",
          title = "Oof! Error detected when starting an application!",
          message = stderr:gsub("%\n", ""),
          timeout = 20,
          icon = require("beautiful").awesome_icon
        }
      )
    end
  )
end

for _, app in ipairs(config.auto_start.apps) do
  run_once(app)
end
