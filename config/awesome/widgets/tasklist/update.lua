local wibox = require("wibox")
local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local lain = require("lain")
local helpers = require("utils.helpers")
local clickable_container = require("widgets.clickable-container")
require "logging.file"
local logger = logging.file("/tmp/log.log")
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

local function tasklist(widget, buttons, label, data, classes)
  -- update the widgets, creating them if needed
  widget:reset()
  for _, clients in pairs(classes) do
    local client = clients[1]
    local text, bg, bg_image, icon, args = label(client)
    args = args or {}

    local cache = data[client]
    local iconbox, icon_box_container, indicator, bg_clickable_background, bg_clickable

    if cache then
      iconbox = cache.iconbox
      icon_box_container = cache.icon_box_container
      bg_clickable = cache.bg_clickable
      indicator = cache.indicator
      bg_clickable_background = cache.bg_clickable_background
    else
      iconbox = wibox.widget.imagebox()
      icon_box_container = constraint(margin(iconbox, 10, 10, 10, 10), "exact", 50, 47)
      icon_box_container:buttons(create_buttons(buttons, client))

      bg_clickable = clickable_container()
      bg_clickable:set_widget(icon_box_container)

      indicator = background(constraint(wibox.widget.textbox(), "exact", 4, 4), bg, gears.shape.circle)

      bg_clickable_background = background()
      bg_clickable_background:set_widget(
        wibox.widget {
          layout = wibox.layout.stack,
          bg_clickable,
          margin(place(indicator, "center", "bottom"), 0, 0, 0, 3)
        }
      )

      data[client] = {
        iconbox = iconbox,
        icon_box_container = icon_box_container,
        bg_clickable = bg_clickable,
        indicator = indicator,
        bg_clickable_background = bg_clickable_background
      }
    end

    if icon then
      iconbox.image = icon
    end

    bg_clickable_background:set_bg(bg)

    local focused = false
    local urgent = false
    for _, c in ipairs(clients) do
      if
        c.active or
          (capi.client.focus and capi.client.focus.skip_taskbar and
            capi.client.focus:get_transient_for_matching(
              function(cl)
                return not cl.skip_taskbar
              end
            ) == c)
       then
        focused = true
      end
      if c.urgent then
        indicator.bg = awful.util.theme.primary
      end
    end

    indicator.bg = "#ffffff00"
    if urgent then
      indicator.bg = awful.util.theme.primary
    end
    if focused then
      indicator.bg = "#14cef9"
    end

    widget:add(bg_clickable_background)
  end
end

return tasklist
