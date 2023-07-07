local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")
local animation = require("helpers.animation")

local item = {mt = {}}

for _, v in pairs({"bg", "bg_hover", "shape", "on_release", "value"}) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  item["set_" .. v] = function(self, val)
    if self._private[v] == val then
      return
    end
    self._private[v] = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  item["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

local function hex2rgba(color)
  if not color then
    return nil
  end

  if type(color) == "table" then
    return color
  end

  local hex = color:gsub("#", "")
  local r = tonumber("0x" .. hex:sub(1, 2))
  local g = tonumber("0x" .. hex:sub(3, 4))
  local b = tonumber("0x" .. hex:sub(5, 6))
  local a = 1
  if #hex == 8 then
    a = tonumber("0x" .. hex:sub(7, 8)) / 255
  end
  return {r, g, b, a}
end

local function rgba2hex(color)
  local hex = "#"
  for i = 1, 3 do
    hex = hex .. string.format("%02x", math.floor(color[i]))
  end
  if color[4] then
    hex = hex .. string.format("%02x", math.floor(color[4] * 255))
  else
    hex = hex .. "ff"
  end
  return hex
end

function item:set_on_release(on_release)
  local wp = self._private
  wp.on_release = on_release
end

function item:set_bg(bg)
  local wp = self._private
  wp.bg_normal = bg
  wp.anim_data.bg = hex2rgba(bg)
  wp.animation.normal.target.bg = hex2rgba(bg)
  if not wp.widget then
    return
  end
  wp.widget.bg = bg
end

function item:set_bg_hover(bg)
  local wp = self._private
  wp.bg_hover = bg
  wp.animation.hover.target.bg = hex2rgba(bg)
end

function item:set_shape(shape)
  local wp = self._private
  if not wp.widget then
    return
  end
  wp.widget.shape = shape
end

function item:set_widget(widget)
  local w = widget and wibox.widget.base.make_widget_from_value(widget)
  if w then
    wibox.widget.base.check_widget(w)
  end

  local wp = self._private

  wp.widget =
    wibox.widget {
    widget = wibox.container.background,
    bg = wp.bg_normal,
    {
      widget = wibox.container.margin,
      top = config.dpi(10),
      bottom = config.dpi(10),
      left = config.dpi(20),
      right = config.dpi(20),
      {
        layout = wibox.layout.fixed.vertical,
        {
          widget = w
        }
      }
    }
  }

  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

local function new()
  local ret = wibox.container.background()

  gears.table.crush(ret, item)

  local wp = ret._private
  wp.state = false

  wp.anim_data = {}
  wp.animation =
    animation {
    subject = wp.anim_data,
    targets = {
      normal = {
        bg = hex2rgba(wp.bg_normal)
      },
      hover = {
        bg = hex2rgba(wp.bg_hover)
      }
    },
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_updated"] = function(s)
        wp.widget.bg = rgba2hex(s.subject.bg)
      end
    }
  }

  ret:connect_signal(
    "mouse::enter",
    function()
      wp.animation.normal:stopAnimation()
      wp.animation.hover:startAnimation()
    end
  )

  ret:connect_signal(
    "mouse::leave",
    function()
      wp.animation.hover:stopAnimation()
      wp.animation.normal:startAnimation()
    end
  )

  ret:connect_signal(
    "button::release",
    function(self, lx, ly, button, mods)
      gears.debug.dump(wp.state)
      if wp.checkbox_enabled then
        wp.state = not wp.state
        if wp.state then
          wp.animation.checked:startAnimation()
          wp.animation.unchecked:stopAnimation()
        else
          wp.animation.checked:stopAnimation()
          wp.animation.unchecked:startAnimation()
        end
      end

      if wp.on_release then
        wp.on_release(self, button, mods, wp.state)
      end
    end
  )

  ret:set_bg("#222222cc")
  ret:set_bg_hover("#333333cc")
  ret:set_shape(gears.shape.rectangle)
  ret:set_checkbox(false)

  return ret
end

function item.mt:__call(...)
  return new()
end

return setmetatable(item, item.mt)
