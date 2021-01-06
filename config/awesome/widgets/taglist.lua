local wibox = require("wibox")
local naughty = require("naughty")
local awful = require("awful")
local gears = require("gears")
local clickable_container = require("widgets.clickable-container")
local capi = {button = _G.button}

local function create_buttons(buttons, object)
  if buttons then
    local btns = {}
    for _, b in ipairs(buttons) do
      -- Create a proxy button object: it will receive the real
      -- press and release events, and will propagate them to the
      -- button object the user provided, but with the object as
      -- argument.
      local btn = capi.button {modifiers = b.modifiers, button = b.button}
      btn:connect_signal(
        "press",
        function()
          b:emit_signal("press", object)
        end
      )
      btn:connect_signal(
        "release",
        function()
          b:emit_signal("release", object)
        end
      )
      btns[#btns + 1] = btn
    end

    return btns
  end
end

local icon_dir = os.getenv("HOME") .. "/.config/awesome/themes/icons"
local function taglist_update_function()
  return function(widget, buttons, label, data, objects)
    -- update the widgets, creating them if needed
    widget:reset()
    for i, object in ipairs(objects) do
      local cache = data[object]

      local text, bg = label(object)
      local circle
      if cache then
        circle = cache.circle
        main_circle = cache.main_circle
      else
        main_circle = wibox.container.background(
          wibox.container.margin(wibox.widget.textbox(' '), 3, 3, 3, 3),
          bg,
          function(cr, width, height)
            return gears.shape.circle(cr, width - 1, height - 1)
          end
        )
        circle = wibox.container.background(
          wibox.container.margin(main_circle, 1, 0, 1),
          awful.util.theme.taglist_border,
          function(cr, width, height)
            return gears.shape.circle(cr, width, height)
          end
        )
        data[object] = {
          circle = circle,
          main_circle = main_circle,
        }
      end

      main_circle.bg = bg
      if object.selected then
        circle.bg = "#FC438433"
      else
        circle.bg = awful.util.theme.taglist_border
      end
      local tag_widget = wibox.container.margin(circle, 4, 4)
      tag_widget:buttons(create_buttons(buttons, object))
      widget:add(tag_widget)
    end
  end
end

return function(s)
  return awful.widget.taglist {
    screen = s,
    filter = awful.widget.taglist.filter.all,
    buttons = awful.util.taglist_buttons,
    layout = {
      layout = wibox.layout.fixed.horizontal
    },
    update_function = taglist_update_function()
  }
end
