local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")

local is_online = {mt={}}

function is_online.new()
  local widget = wibox.container.background(wibox.container.constraint(wibox.widget.textbox(""), "exact", 3, 50), awful.util.theme.primary)

  local ping_command =
    [[bash -c '
    wget -q --spider http://google.com

    if [ $? -eq 0 ]; then
        echo "Online"
    else
        echo "Offline"
    fi
  ']]

  gears.timer {
    timeout = 30,
    autostart = true,
    call_now = true,
    callback = function()
      awful.spawn.with_line_callback(
        ping_command,
        {
          stdout = function()
            widget.bg = awful.util.theme.sidebar_bg
            awful.util.variables.is_network_connected = true
          end,
          stderr = function()
            widget.bg = awful.util.theme.primary
            awful.util.variables.is_network_connected = false
          end
        }
      )
    end
  }

  return widget
end

function is_online.mt:__call(...)
  return is_online.new(...)
end

return setmetatable(is_online, is_online.mt)
