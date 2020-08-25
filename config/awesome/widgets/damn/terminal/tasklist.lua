local wibox = require("wibox")
local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local lain = require("lain")
local helpers = require("utils.helpers")
local clickable_container = require("widgets.clickable-container")
local markup = lain.util.markup
local capi = {
  button = _G.button,
  client = client
}

local constraint = wibox.container.constraint
local margin = wibox.container.margin
local background = wibox.container.background
local place = wibox.container.place

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

local tasklist = {}

function tasklist.tasks(widget, buttons, label, data, objects)
  -- update the widgets, creating them if needed
  widget:reset()
  for i, object in ipairs(objects) do
    local text, bg, bg_image, icon, args = label(object)
    args = args or {}

    local cache = data[object]
    local title, title_container, indicator, bg_clickable_background, bg_clickable

    if cache then
      title = cache.title
      title_container = cache.title_container
      bg_clickable = cache.bg_clickable
      indicator = cache.indicator
      bg_clickable_background = cache.bg_clickable_background
    else
      title = wibox.widget.textbox()
      title_container = constraint(margin(title, 10, 10, 10, 10), "exact", 200, 40)

      bg_clickable = clickable_container()
      bg_clickable:set_widget(title_container)

      indicator = background(constraint(wibox.widget.textbox(), "exact", 200, 3), bg)

      bg_clickable_background = background()
      bg_clickable_background:set_widget(
        wibox.widget {
          bg_clickable,
          place(indicator, "center", "bottom"),
          layout = wibox.layout.stack
        }
      )
      bg_clickable_background:buttons(create_buttons(buttons, object))

      data[object] = {
        title = title,
        title_container = title_container,
        bg_clickable = bg_clickable,
        indicator = indicator,
        bg_clickable_background = bg_clickable_background
      }
    end

    if text then
      title:set_markup(text)
    end

    bg_clickable_background:set_bg(bg)

    local focused = object.active
    if
      not focused and capi.client.focus and capi.client.focus.skip_taskbar and
        capi.client.focus:get_transient_for_matching(
          function(cl)
            return not cl.skip_taskbar
          end
        ) == object
     then
      focused = true
    end

    indicator.bg = "#ffffff00"
    if object.urgent then
      indicator.bg = awful.util.theme.primary
    end
    if focused then
      indicator.bg = "#14cef9"
    end

    widget:add(bg_clickable_background)
  end
end

tasklist.wibar =
  awful.wibar({position = "top", screen = s, type = "dock", height = 40, bg = "#ff0000", visible = false})

tasklist.widgets = {
  layout = wibox.layout.flex.horizontal,
  background(
    {
      layout = wibox.layout.fixed.horizontal,
      awful.widget.tasklist {
        screen = awful.screen.focused(),
        filter = awful.widget.tasklist.filter.currenttags,
        buttons = awful.util.tasklist_buttons,
        layout = {layout = wibox.layout.fixed.horizontal},
        update_function = tasklist.tasks
      }
    },
    "#1f1f1f"
  )
}

return tasklist
