local gears = require('gears')
local awful = require('awful')

return gears.table.join(
  awful.button(
    {},
    1,
    function(c)
      if c == client.focus then
        c.minimized = true
      else
        c.minimized = false
        if not c:isvisible() and c.first_tag then
          c.first_tag:view_only()
        end
        client.focus = c
        c:raise()
      end
    end
  ),
  awful.button(
    {awful.util.modkey},
    2,
    function(c)
      c:kill()
    end
  ),
  awful.button(
    {},
    4,
    function()
      awful.client.focus.byidx(1)
    end
  ),
  awful.button(
    {},
    5,
    function()
      awful.client.focus.byidx(-1)
    end
  )
)
