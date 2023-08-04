local wibox = require("wibox")
local theme = require("lib.configuration.theme")

local clock = {mt = {}}

function clock.new()
  return wibox.widget {
    widget = wibox.widget.textclock,
    format = "<b><span font_size='70pt' color='" .. theme.fg_normal .. "'>%H:%M</span></b>"
  }
end

function clock.mt:__call(...)
  return clock.new(...)
end

return setmetatable(clock, clock.mt)
