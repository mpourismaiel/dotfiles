local wibox = require("wibox")
local naughty = require("naughty")
local gears = require("gears")
local lain = require("lain")
local awful = require("awful")
local createAnimObject = require("utils.animation").createAnimObject

local markup = lain.util.markup
local background = wibox.container.background
local constraint = wibox.container.constraint
local place = wibox.container.place
local icon_string = awful.util.theme_functions.icon_string

local buttons = {}

function buttons.button(icon, color, bg_color, action)
  local icon_container =
    wibox.widget.textbox(markup(awful.util.theme.fg_normal, icon_string({icon = icon, font = "Font Awesome 5 Pro", size = 9})))
  local background = place(background(constraint(wibox.widget.textbox(), "exact", 18, 18), bg_color, gears.shape.circle))
  background.opacity = 0
  local button =
    wibox.widget {
    layout = wibox.layout.stack,
    background,
    constraint(place(icon_container), "exact", 18, 18)
  }

  button:buttons(gears.table.join(awful.button({}, 1, nil, action)))

  button:connect_signal(
    "mouse::enter",
    function()
      createAnimObject(0.3, background, {opacity = 1}, "outCubic")
    end
  )

  button:connect_signal(
    "mouse::leave",
    function()
      createAnimObject(0.3, background, {opacity = 0}, "outCubic")
    end
  )

  return button
end

buttons.exit = function(client)
  return buttons.button(
    "",
    "#3f0102",
    "#ff5d56",
    function()
      client:kill()
    end
  )
end

buttons.maximize = function(client)
  return buttons.button(
    "",
    "#006615",
    "#00cb4b",
    function()
      client.maximized = not client.maximized
    end
  )
end

buttons.minimize = function(client)
  return buttons.button(
    "",
    "#440601",
    "#ffbd35",
    function()
      client.minimized = not client.minimized
    end
  )
end

return buttons
