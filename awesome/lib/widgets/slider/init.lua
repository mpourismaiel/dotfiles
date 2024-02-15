local capi = {
  awesome = awesome,
  root = root,
  mouse = mouse,
  mousegrabber = mousegrabber
}
local wibox = require("wibox")
local gears = require("gears")
local math_helpers = require("lib.helpers.math")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wbackground = require("lib.widgets.background")
local math = math

local slider = {
  mt = {}
}

local function set_x(x)
  return function(geo, args)
    return {x = x, y = (args.parent.height - geo.height) / 2}
  end
end

local function new(args)
  args = args or {}

  args.forced_width = args.forced_width or nil
  args.forced_height = args.forced_height or config.dpi(8)
  args.minimum = args.minimum or 0
  args.maximum = args.maximum or 1
  args.round = args.round
  args.margins = args.margins or config.dpi(0)
  args.bar_height = args.bar_height or config.dpi(8)
  args.bar_color = args.bar_color or theme.bg_normal
  args.bar_active_color = args.bar_active_color or theme.fg_primary
  args.handle_template = args.handle_template or nil
  args.handle_width = args.handle_width or config.dpi(20)
  args.handle_height = args.handle_height or config.dpi(20)
  args.handle_shape = args.handle_shape or gears.shape.circle
  args.handle_color = args.handle_color or args.bar_active_color
  args.handle_border_width = args.handle_border_width or config.dpi(2)
  args.handle_border_color = args.handle_border_color or theme.fg_primary

  local value = math_helpers.convert_range((args.value or 0), args.minimum, args.maximum, 0, 1)
  local w = 0
  local is_dragging = false

  local bar_start, bar_end, bar_current, height2, hb2, pi2, value_min, value_max, effwidth, ipos, lpos
  hb2 = args.bar_height / 2
  bar_start = args.margins + hb2
  bar_end = w - (bar_start)
  bar_current = value + args.bar_height
  pi2 = math.pi * 2
  value_min = args.margins - hb2
  value_max = w - bar_start - hb2
  effwidth = value_max - value_min

  local handle =
    args.handle_template or
    wibox.widget {
      widget = wbackground,
      point = {x = 0, y = 0},
      forced_width = args.handle_width,
      forced_height = args.handle_height,
      shape = args.handle_shape,
      bg = args.handle_color,
      border_width = args.handle_border_width,
      border_color = args.handle_border_color
    }

  local layout =
    wibox.layout {
    layout = wibox.layout.manual,
    handle
  }

  local bar =
    wibox.widget {
    widget = wibox.widget.make_base_widge,
    forced_width = args.forced_width,
    forced_height = args.forced_height,
    pos = value,
    fit = function(_, _, width, height)
      return width, height
    end,
    draw = function(self, _, cr, width, height)
      w = width --get the width whenever redrawing just in case
      bar_end = width - (bar_start) --update bar_end which depends on width
      height2 = height / 2 --update height2 which depends on height
      value_max = width - bar_start - hb2
      effwidth = value_max - value_min

      value = effwidth * self.pos + value_min
      bar_current = value + args.bar_height
      layout:move(1, set_x(value))

      cr:set_line_width(args.bar_height)

      cr:set_source(gears.color(args.bar_color))
      cr:arc(bar_end, height2, hb2, 0, pi2)
      cr:fill()

      cr:move_to(bar_start, height2)
      cr:line_to(bar_end, height2)
      cr:stroke()

      cr:set_source(gears.color(args.bar_active_color))
      cr:arc(bar_start, height2, hb2, 0, pi2)
      cr:arc(bar_current, height2, hb2, 0, pi2)
      cr:fill()

      cr:move_to(bar_start, height2)
      cr:line_to(bar_current, height2)
      cr:stroke()
    end
  }

  local widget =
    wibox.widget {
    layout = wibox.layout.stack,
    forced_width = args.forced_width,
    forced_height = args.forced_height,
    bar,
    layout
  }

  layout:connect_signal(
    "button::press",
    function(self, x, y, button, mods, geo)
      if gears.table.hasitem(mods, "Mod4") or button ~= 1 then
        return
      end

      --reset initial position for later
      ipos = nil

      --initially move it to the target (only one call of max and min is prolly fine)
      bar.pos = math.min(math.max(((x - args.bar_height) / effwidth), 0), 1)
      bar:emit_signal("widget::redraw_needed")

      widget:emit_signal("property::value", widget:get_value())

      capi.mousegrabber.run(
        function(mouse)
          --stop (and emit signal) if you release mouse 1
          if not mouse.buttons[1] then
            widget:emit_signal("slider::ended_mouse_things", bar.pos)
            is_dragging = false
            return false
          end

          is_dragging = true

          --get initial position
          if not ipos then
            ipos = mouse.x
          end

          lpos = (x + mouse.x - ipos - args.bar_height) / effwidth

          --make sure target \in (0, 1)
          bar.pos = math.max(math.min(lpos, 1), 0)
          bar:emit_signal("widget::redraw_needed")
          widget:emit_signal("property::value", widget:get_value())

          return true
        end,
        "fleur"
      )
    end
  )

  layout:connect_signal(
    "mouse::enter",
    function()
      capi.root.cursor("fleur")
      local widget = capi.mouse.current_wibox
      if widget then
        widget.cursor = "fleur"
      end
    end
  )

  layout:connect_signal(
    "mouse::leave",
    function()
      capi.root.cursor("left_ptr")
      local widget = capi.mouse.current_wibox
      if widget then
        widget.cursor = "left_ptr"
      end
    end
  )

  function widget:set_value(val)
    if is_dragging == false then
      val = math_helpers.convert_range(val, args.minimum, args.maximum, 0, 1)
      bar.pos = val
      bar:emit_signal("widget::redraw_needed")
    end
  end

  function widget:get_value()
    local value = math_helpers.convert_range(bar.pos, 0, 1, args.minimum, args.maximum)
    value = math_helpers.round(value, 2)
    if args.round then
      value = gears.math.round(value)
    end
    return value
  end

  function widget:set_minimum(minimum)
    args.minimum = minimum
  end

  function widget:set_maximum(maximum)
    args.maximum = maximum
  end

  return widget
end

function slider.mt:__call(...)
  return new(...)
end

return setmetatable(slider, slider.mt)
