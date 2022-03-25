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
        format = "<b><span font_size='12pt' color='#eeeeee'>%A</span></b>"
      },
      nil,
      {
        widget = wibox.widget.textclock,
        format = "<b><span font_size='12pt' color='#eeeeee'>%A %F</span></b>"
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
          format = "<span font_size='48pt' color='#ffffff'>%H:%M</span>"
        }
      }
    }
  }
end

function clock.mt:__call(...)
  return clock.new(...)
end

return setmetatable(clock, clock.mt)
