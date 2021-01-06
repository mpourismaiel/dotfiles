local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")

local background = wibox.container.background
local constraint = wibox.container.constraint
local margin = wibox.container.margin
local place = wibox.container.place

return function(icon, data_widget)
  return margin(
    place(
      wibox.widget {
        layout = wibox.layout.fixed.vertical,
        constraint(
          place(wibox.widget.textbox(icon)),
          "exact",
          48,
          30
        ),
        place(data_widget)
      }
    ),
    10,
    10,
    10,
    10
  )
end
