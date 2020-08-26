local beautiful = require("beautiful")
local awful = require("awful")
local placement = require("awful.placement")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local helpers = require("utils.helpers")
local createAnimObject = require("utils.animation").createAnimObject

return function(awesome, screen, client, tag)
  tag.connect_signal(
    "property::selected",
    function(t)
      if not t.selected and t.wibar ~= nil then
        t.wibar.visible = false
        return
      end

      if t.wibar then
        t.wibar.visible = true
      end
    end
  )

  naughty.connect_signal(
    "request::preset",
    function(notification)
      if awful.util.disable_notification == 1 and notification.title ~= "Erfan" then
        notification.ignore = true
      elseif awful.util.disable_notification == 2 then
        notification.ignore = true
      end
    end
  )

  screen.connect_signal(
    "property::geometry",
    function(s)
      beautiful.set_wallpaper()
    end
  )

  client.connect_signal(
    "manage",
    function(c)
      -- Signal function to execute when a new client appears.
      if awesome.startup and not c.size_hints.user_position and not c.size_hints.program_position then
        awful.placement.no_offscreen(c)
      end
    end
  )

  client.connect_signal(
    "request::titlebars",
    function(c)
      require("widgets.damn.titlebar")(c)
    end
  )

  client.connect_signal(
    "property::maximized",
    function(c)
      helpers.client.border_adjust(c)
    end
  )

  local function attach(w, align, b)
    (placement[align] + (placement["maximize_horizontally"]))(
      w,
      {
        attach = true,
        update_workarea = true,
        margins = {left = 0, right = 0, top = 0, bottom = b}
      }
    )
  end

  client.connect_signal("focus", helpers.client.border_adjust)
  client.connect_signal(
    "unfocus",
    function(c)
      c.border_color = beautiful.border_normal
    end
  )

  screen.connect_signal(
    "request::desktop_decoration",
    function(s)
      for index, tag in pairs(awful.util.tags) do
        local rules = nil
        if tag.rules ~= nil then
          rules = {}
          for _, rule in ipairs(tag.rules) do
            rules[rule] = true
          end
        end
        awful.tag.add(
          tag.text,
          {
            icon = tag.icon,
            screen = s,
            layout = tag.layout or awful.layout.layouts[1],
            selected = index == 1,
            rules = rules,
            wibar = tag.wibar
          }
        )
      end
      beautiful.at_screen_connect(s)
    end
  )
end
