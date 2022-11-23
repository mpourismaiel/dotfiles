local naughty = require("naughty")
local gears = require("gears")
local awful = require("awful")
local wibox = require("wibox")
local config = require("configuration.config")
local notification_widget = require("configuration.notifications.widget")
local global_state = require("configuration.config.global_state")

local c = global_state.cache

naughty.connect_signal(
  "request::display",
  function(n)
    c.add("notifications", n)

    if global_state.cache.get("lockscreen") then
      return
    end

    naughty.layout.box {
      notification = n,
      ontop = true,
      position = "bottom_right",
      bg = "#44444422",
      border_width = 0,
      border_color = "#00000000",
      shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, 5)
      end,
      widget_template = {
        widget = wibox.container.constraint,
        width = config.dpi(500),
        strategy = "max",
        notification_widget
      }
    }
  end
)
