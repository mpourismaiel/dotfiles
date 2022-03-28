local wibox = require("wibox")

local date = {mt = {}}

function date.new()
  return wibox.widget {
    widget = wibox.widget.textclock,
    format = "<span font_size='35pt' color='#cccccc'>%F</span>"
  }
end

function date.mt:__call(...)
  return date.new(...)
end

return setmetatable(date, date.mt)