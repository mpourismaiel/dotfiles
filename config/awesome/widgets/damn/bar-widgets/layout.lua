local setmetatable = setmetatable
local capi = {screen = screen, tag = tag}
local awful = require("awful")
local layout = require("awful.layout")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local markup = require("lain").util.markup

local function get_screen(s)
  return s and capi.screen[s]
end

local layoutbox = {mt = {}}

local boxes = nil

local function update(widget, screen, args)
  screen = get_screen(screen)
  local name = layout.getname(layout.get(screen))
  widget:set_markup(args.icons[name])
end

local function update_from_tag(tag, args)
  local screen = get_screen(tag.screen)
  local widget = boxes[screen]
  if widget then
    update(widget, screen, args)
  end
end

function layoutbox.new(args)
  args = args or {}
  local screen = args.screen

  screen = get_screen(screen or 1)

  if boxes == nil then
    boxes = setmetatable({}, {__mode = "kv"})
    capi.tag.connect_signal(
      "property::selected",
      function(t)
        update_from_tag(t, args)
      end
    )
    capi.tag.connect_signal(
      "property::layout",
      function(t)
        update_from_tag(t, args)
      end
    )
    capi.tag.connect_signal(
      "property::screen",
      function()
        for s, widget in pairs(boxes) do
          if s.valid then
            update(widget, s, args)
          end
        end
      end
    )
    layoutbox.boxes = boxes
  end

  local widget = boxes[screen]
  if not widget then
    widget = wibox.widget.textbox()

    update(widget, screen, args)
    boxes[screen] = widget
  end

  return widget
end

local function layout_icon(color, icon, font)
  return markup(
    color or awful.util.theme.fg_normal,
    awful.util.theme_functions.icon_string({icon = icon, size = 11, font = font})
  )
end

function layoutbox.mt:__call(args)
  args = args or {}
  local widget =
    awful.util.theme_functions.bar_widget(
    wibox.container.constraint(
      wibox.container.place(
        layoutbox.new(
          {
            icons = {
              max = layout_icon(args.color, "", "Font Awesome 5 Pro"),
              tile = layout_icon(args.color, "", "Font Awesome 5 Free"),
              floating = layout_icon(args.color, "", "Font Awesome 5 Pro")
            }
          }
        )
      ),
      "exact",
      20
    )
  )

  widget:buttons(
    {
      awful.button(
        {},
        1,
        function()
          awful.layout.inc(1)
        end
      ),
      awful.button(
        {},
        2,
        function()
          awful.layout.set(awful.layout.layouts[1])
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
          awful.layout.inc(1)
        end
      ),
      awful.button(
        {},
        5,
        function()
          awful.layout.inc(-1)
        end
      )
    }
  )

  return widget
end

return setmetatable(layoutbox, layoutbox.mt)
