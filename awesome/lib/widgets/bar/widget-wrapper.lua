local wibox = require("wibox")
local config = require("lib.configuration")

function bar_widget_wrapper(w)
  return wibox.widget {
    widget = wibox.container.margin,
    top = config.dpi(9),
    bottom = config.dpi(9),
    {
      widget = wibox.container.constraint,
      width = config.dpi(48),
      strategy = "exact",
      {
        widget = wibox.container.place,
        {
          widget = wibox.container.constraint,
          width = config.dpi(24),
          strategy = "exact",
          {
            widget = wibox.container.place,
            {
              widget = w
            }
          }
        }
      }
    }
  }
end

return bar_widget_wrapper
