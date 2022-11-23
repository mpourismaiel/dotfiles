local naughty = require("naughty")
local wibox = require("wibox")
local gears = require("gears")
local message = require("configuration.notifications.message")
local title = require("configuration.notifications.title")
local config = require("configuration.config")

local notification_widget = {
  layout = wibox.layout.fixed.vertical,
  {
    widget = wibox.container.background,
    bg = "#11111188",
    {
      margins = config.dpi(8),
      widget = wibox.container.margin,
      {
        layout = wibox.layout.fixed.horizontal,
        fill_space = true,
        spacing = config.dpi(16),
        {
          widget = wibox.container.constraint,
          width = config.dpi(30),
          height = config.dpi(30),
          strategy = "max",
          {
            widget = wibox.container.background,
            shape = gears.shape.circle,
            naughty.widget.icon
          }
        },
        {
          widget = wibox.container.place,
          valign = "middle",
          halign = "left",
          title
        }
      }
    }
  },
  {
    widget = wibox.container.background,
    bg = "#00000000",
    {
      margins = config.dpi(8),
      widget = wibox.container.margin,
      {
        layout = wibox.layout.fixed.vertical,
        {
          widget = wibox.container.margin,
          top = config.dpi(6),
          bottom = config.dpi(6),
          {
            widget = message
          }
        },
        naughty.list.actions
      }
    }
  }
}

return notification_widget
