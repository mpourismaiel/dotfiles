local wibox = require("wibox")

local tasklist = {mt = {}}

function tasklist.new()
  return wibox.widget {
    layout = wibox.layout.fixed.vertical,
    {
      widget = wibox.container.place,
      {
        widget = wibox.widget.textclock,
        format = "<b><span font_size='14pt'>%H</span></b>"
      }
    },
    {
      widget = wibox.container.place,
      {
        widget = wibox.widget.textclock,
        format = "<span font_size='14pt'>%M</span>"
      }
    }
  }
end

function tasklist.mt:__call(...)
  return tasklist.new(...)
end

return setmetatable(tasklist, tasklist.mt)
