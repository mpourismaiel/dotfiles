local awful = require("awful")

local tasklist = {mt = {}}

function tasklist.new(screen)
  return awful.widget.tasklist {
    screen = screen,
    filter = awful.widget.tasklist.filter.currenttags,
    buttons = {
      awful.button(
        {},
        1,
        function(c)
          c:activate {context = "tasklist", action = "toggle_minimization"}
        end
      ),
      awful.button(
        {},
        3,
        function()
          awful.menu.client_list {theme = {width = 250}}
        end
      ),
      awful.button(
        {},
        4,
        function()
          awful.client.focus.byidx(-1)
        end
      ),
      awful.button(
        {},
        5,
        function()
          awful.client.focus.byidx(1)
        end
      )
    }
  }
end

function tasklist.mt:__call(...)
  return tasklist.new(...)
end

return setmetatable(tasklist, tasklist.mt)
