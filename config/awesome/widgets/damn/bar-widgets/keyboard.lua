local awful = require("awful")
local layout_indicator = require("widgets.layout-indicator")

local keyboard = {mt = {}}

function keyboard.new(args)
  local widget = awful.util.theme_functions.bar_widget(layout_indicator(args))
  widget.font = awful.util.theme.font

  function relaunch_layout()
    awful.spawn.with_shell("setxkbmap -layout us,ir -option grp:alt_shift_toggle")
  end

  widget:buttons({ awful.button({}, 1, relaunch_layout) })

  return widget
end

function keyboard.mt:__call(...)
  return keyboard.new(...)
end

return setmetatable(keyboard, keyboard.mt)
