local beautiful = require("beautiful")
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local helpers = require("utils.helpers")
local createAnimObject = require("utils.animation").createAnimObject

return function(awesome, screen, client, tag)
  naughty.connect_signal(
    "request::preset",
    function(notification)
      if awful.util.disable_notification == 1 and notification.timeout == 5 and notification.title ~= "Erfan" then
        notification.ignore = true
      elseif awful.util.disable_notification == 2 and notification.timeout == 5 then
        notification.ignore = true
      end
    end
  )

  screen.connect_signal(
    "property::geometry",
    function(s)
      -- Wallpaper
      if beautiful.wallpaper then
        local wallpaper = beautiful.wallpaper
        -- If wallpaper is a function, call it with the screen
        if type(wallpaper) == "function" then
          wallpaper = wallpaper(s)
        end
        gears.wallpaper.maximized(wallpaper, s, true)
      end
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
      -- Add a titlebar if titlebars_enabled is set to true in the rules.
      if beautiful.titlebar_fun then
        beautiful.titlebar_fun(c)
        return
      end
    end
  )

  client.connect_signal(
    "mouse::enter",
    function(c)
      -- Enable sloppy focus, so that focus follows mouse.
      c:emit_signal("request::activate", "mouse_enter", {raise = true})
    end
  )

  client.connect_signal(
    "property::maximized",
    function(c)
      helpers.client.border_adjust(c)
    end
  )

  -- screen.connect_signal("tag::history::update", function(s)
  --   local maximized = false
  --   for i, c in ipairs(s.selected_tag:clients()) do
  --     if c.maximized then
  --       maximized = true
  --       break
  --     end
  --   end

  --   if maximized then
  --     awful.screen.focused().selected_tag.gap = 0
  --     s.mytagbar_widgets:set_shape(function(cr, width, height)
  --       gears.shape.rectangle(cr, width, height, 0)
  --     end)
  --     createAnimObject(0.6, s.mytagbar_margin, {left = 0, right = 0}, "outCubic")
  --   else
  --     awful.screen.focused().selected_tag.gap = 10
  --     s.mytagbar_widgets:set_shape(function(cr, width, height)
  --       gears.shape.rounded_rect(cr, width, height, 10)
  --     end)
  --     createAnimObject(0.6, s.mytagbar_margin, {left = 20, right = 20}, "outCubic")
  --   end
  -- end)

  client.connect_signal("focus", helpers.client.border_adjust)
  client.connect_signal(
    "unfocus",
    function(c)
      c.border_color = beautiful.border_normal
    end
  )

  if awful.util.theme_functions.at_screen_connect then
    awful.screen.connect_for_each_screen(awful.util.theme_functions.at_screen_connect)
  end
end
