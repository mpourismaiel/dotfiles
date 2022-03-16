local wibox = require("wibox")
local config = require("configuration.config")

local clock = {mt = {}}

function clock.new()
  return wibox.widget {
    layout = wibox.layout.fixed.vertical,
    {
      layout = wibox.layout.align.horizontal,
      {
        widget = wibox.widget.textclock,
        format = "<span font_size='12pt' color='#cccccc'>%A</span>"
      },
      nil,
      {
        widget = wibox.widget.textclock,
        format = "<span font_size='12pt' color='#cccccc'>%A %F</span>"
      }
    },
    {
      widget = wibox.container.margin,
      top = config.dpi(16),
      {
        widget = wibox.container.place,
        halign = "right",
        {
          widget = wibox.widget.textclock,
          format = "<b><span font_size='40pt' color='#cccccc'>%H:%M</span></b>"
        }
      }
    }
  }
end

function clock.mt:__call(...)
  return clock.new(...)
end

return setmetatable(clock, clock.mt)
