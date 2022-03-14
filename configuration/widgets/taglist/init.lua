local awful = require("awful")
local wibox = require("wibox")

local taglist = {mt = {}}

function taglist.new(screen)
  return awful.widget.taglist {
    screen = screen,
    filter = awful.widget.taglist.filter.all,
    widget_template = {
      {
        {
          {
            id = "icon_role",
            widget = wibox.widget.imagebox
          },
          margins = 2,
          widget = wibox.container.margin
        },
        {
          id = "text_role",
          widget = wibox.widget.textbox
        },
        layout = wibox.layout.fixed.horizontal
      },
      left = 18,
      right = 18,
      widget = wibox.container.margin
    },
    buttons = {
      awful.button(
        {},
        1,
        function(t)
          t:view_only()
        end
      ),
      awful.button(
        {modkey},
        1,
        function(t)
          if client.focus then
            client.focus:move_to_tag(t)
          end
        end
      ),
      awful.button({}, 3, awful.tag.viewtoggle),
      awful.button(
        {modkey},
        3,
        function(t)
          if client.focus then
            client.focus:toggle_tag(t)
          end
        end
      ),
      awful.button(
        {},
        4,
        function(t)
          awful.tag.viewprev(t.screen)
        end
      ),
      awful.button(
        {},
        5,
        function(t)
          awful.tag.viewnext(t.screen)
        end
      )
    }
  }
end

function taglist.mt:__call(...)
  return taglist.new(...)
end

return setmetatable(taglist, taglist.mt)
