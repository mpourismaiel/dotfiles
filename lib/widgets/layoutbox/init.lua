local awful = require("awful")
local theme = require("lib.config.theme")
local wbutton = require("lib.widgets.button")
local layoutbox = {mt = {}}

function layoutbox.new(screen)
  return {
    widget = wbutton,
    margin = theme.bar_padding,
    bg_normal = theme.bg_normal,
    bg_hover = theme.bg_primary,
    paddings = 10,
    awful.widget.layoutbox {
      screen = screen,
      buttons = {
        awful.button(
          {},
          1,
          function()
            awful.layout.inc(1)
          end
        ),
        awful.button(
          {},
          3,
          function()
            awful.layout.inc(-1)
          end
        ),
        awful.button(
          {},
          4,
          function()
            awful.layout.inc(-1)
          end
        ),
        awful.button(
          {},
          5,
          function()
            awful.layout.inc(1)
          end
        )
      }
    }
  }
end

function layoutbox.mt:__call(...)
  return layoutbox.new(...)
end

return setmetatable(layoutbox, layoutbox.mt)
