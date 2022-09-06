local naughty = require("naughty")
local wibox = require("wibox")
local message = require("configuration.notifications.message")
local title = require("configuration.notifications.title")
local config = require("configuration.config")

local notification_widget = {
  margins = config.dpi(8),
  widget = wibox.container.margin,
  {
    layout = wibox.layout.fixed.vertical,
    spacing = config.dpi(10),
    naughty.list.actions,
    {
      layout = wibox.layout.fixed.horizontal,
      fill_space = true,
      spacing = config.dpi(16),
      {
        widget = wibox.container.constraint,
        width = config.dpi(48),
        height = config.dpi(48),
        strategy = "max",
        naughty.widget.icon
      },
      {
        layout = wibox.layout.fixed.vertical,
        spacing = config.dpi(8),
        title,
        message
      }
    }
  }
}

return notification_widget
