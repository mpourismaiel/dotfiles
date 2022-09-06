local naughty = require("naughty")
local gears = require("gears")
local wibox = require("wibox")
local config = require("configuration.config")
local notification_widget = require("configuration.notifications.widget")

naughty.connect_signal(
  "request::display",
  function(n)
    if config.locked then
      return
    end

    naughty.layout.box {
      notification = n,
      ontop = true,
      position = "bottom_right",
      bg = "#22222299",
      border_width = 2,
      border_color = "#444444",
      shape = gears.shape.rounded_rect,
      widget_template = {
        widget = wibox.container.constraint,
        width = config.dpi(500),
        strategy = "max",
        notification_widget
      }
    }
  end
)
