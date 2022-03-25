local naughty = require("naughty")
local gears = require("gears")
local wibox = require("wibox")
local config = require("configuration.config")

naughty.connect_signal(
  "request::display",
  function(n)
    naughty.layout.box {
      notification = n,
      ontop = true,
      position = "bottom_right",
      border_width = 0,
      widget_template = {
        widget = wibox.container.constraint,
        width = config.dpi(500),
        strategy = "max",
        {
          widget = wibox.container.background,
          bg = "#22222260",
          shape = gears.shape.rounded_rect,
          {
            id = "background_role",
            widget = naughty.container.background,
            {
              margins = config.dpi(8),
              widget = wibox.container.margin,
              {
                layout = wibox.layout.fixed.vertical,
                spacing = config.dpi(10),
                naughty.list.actions,
                {
                  layout = wibox.layout.fixed.horizontal,
                  fill_space = true,
                  spacing = config.dpi(4),
                  {
                    widget = wibox.container.constraint,
                    width = config.dpi(48),
                    height = config.dpi(48),
                    strategy = "max",
                    {
                      widget = naughty.widget.icon
                    }
                  },
                  {
                    layout = wibox.layout.fixed.vertical,
                    spacing = config.dpi(8),
                    naughty.widget.title,
                    naughty.widget.message
                  }
                }
              }
            }
          }
        }
      }
    }
  end
)
