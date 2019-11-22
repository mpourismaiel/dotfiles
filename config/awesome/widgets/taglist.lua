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

local function taglist(theme)
  return function(widget, buttons, label, data, objects)
    -- update the widgets, creating them if needed
    widget:reset()
    for i, object in ipairs(objects) do
      local cache = data[object]
      local textbox, background_box, textbox_container, widget_layout, bg_clickable
      if cache then
        textbox = cache.textbox
        background_box = cache.background_box
        textbox_container = cache.textbox_container
      else
        textbox = wibox.widget.textbox()
        background_box = wibox.container.background()
        textbox_container = wibox.container.margin(wibox.container.place(textbox), 0, 0, 16, 16)
        widget_layout = wibox.layout.fixed.horizontal()
        bg_clickable = clickable_container()

        -- All of this is added in a fixed widget
        widget_layout:fill_space(true)
        widget_layout:add(textbox_container)
        bg_clickable:set_widget(widget_layout)

        -- And all of this gets a background
        background_box:set_widget(bg_clickable)

        background_box:buttons(create_buttons(buttons, object))

        data[object] = {
          textbox = textbox,
          background_box = background_box,
          textbox_container = textbox_container
        }
      end

      local text, bg, args = label(object, textbox)
      args = args or {}
      -- The text might be invalid, so use pcall.
      if text == nil or text == "" then
        textbox_container:set_margins(0)
      else
        if not textbox:set_markup_silently(text) then
          textbox:set_markup("<i>&lt;Invalid text&gt;</i>")
        end
      end

      background_box:set_bg(bg)
      background_box.shape = args.shape
      background_box.shape_border_width = args.shape_border_width
      background_box.shape_border_color = args.shape_border_color

      widget:add(background_box)
    end
  end
end

return taglist
