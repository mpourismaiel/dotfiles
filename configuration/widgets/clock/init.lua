local wibox = require("wibox")
local beautiful = require("beautiful")

local clock = {mt = {}}

function clock.new()
  return wibox.widget {
    layout = wibox.layout.fixed.vertical,
    {
      widget = wibox.container.place,
      {
        widget = wibox.widget.textclock,
        format = "<b><span font_size='12.5pt' color='" .. beautiful.fg_normal .. "'>%H</span></b>"
      }
    },
    {
      widget = wibox.container.place,
      {
        widget = wibox.widget.textclock,
        format = "<span font_size='13pt'>%M</span>"
      }
    }
  }
end

function clock.mt:__call(...)
  return clock.new(...)
end

return setmetatable(clock, clock.mt)
