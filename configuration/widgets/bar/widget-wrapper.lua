local wibox = require("wibox")
local config = require("configuration.config")

function bar_widget_wrapper(w)
  return wibox.widget {
    widget = wibox.container.margin,
    left = config.dpi(6),
    right = config.dpi(6),
    {
      widget = wibox.container.constraint,
      height = config.dpi(48),
      strategy = "exact",
      {
        widget = wibox.container.place,
        {
          widget = wibox.container.constraint,
          height = config.dpi(24),
          strategy = "exact",
          {
            widget = w
          }
        }
      }
    }
  }
end

return bar_widget_wrapper
