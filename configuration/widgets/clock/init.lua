local wibox = require("wibox")
local beautiful = require("beautiful")
local theme = require("configuration.config.theme")
local wbutton = require("configuration.widgets.button")

local clock = {mt = {}}

function clock.new()
  return wibox.widget {
    widget = wbutton,
    margin = theme.bar_padding,
    bg_normal = theme.bg_normal,
    bg_hover = theme.bg_primary,
    paddings = 0,
    padding_top = 8,
    padding_bottom = 8,
    valign = "center",
    {
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
  }
end

function clock.mt:__call(...)
  return clock.new(...)
end

return setmetatable(clock, clock.mt)
