local awful = require("awful")
local wibox = require("wibox")
local layoutbox = {mt = {}}

function layoutbox.new(screen)
  return awful.widget.layoutbox {
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
end

function layoutbox.mt:__call(...)
  return layoutbox.new(...)
end

return setmetatable(layoutbox, layoutbox.mt)
