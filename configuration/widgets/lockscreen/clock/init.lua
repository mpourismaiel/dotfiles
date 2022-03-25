local wibox = require("wibox")

local clock = {mt = {}}

function clock.new()
  return wibox.widget {
    widget = wibox.widget.textclock,
    format = "<b><span font_size='70pt' color='#cccccc'>%H:%M</span></b>"
  }
end

function clock.mt:__call(...)
  return clock.new(...)
end

return setmetatable(clock, clock.mt)
