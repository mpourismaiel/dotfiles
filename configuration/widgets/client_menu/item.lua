local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")
local animation = require("helpers.animation")

local item = {mt = {}}

for _, v in pairs({"bg", "bg_hover", "shape", "on_release", "checkbox", "value"}) do
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

function item:set_value(value)
  local wp = self._private

  wp.state = value
  local target = wp.animation.unchecked.target
  if value then
    target = wp.animation.checked.target
  end
  for k, v in pairs(target) do
    if type(v) == "table" then
      wp.anim_data[k] = gears.table.clone(v)
    else
      wp.anim_data[k] = v
    end
  end
  if wp.checkbox_enabled and wp.checkbox_widget then
    wp.checkbox_widget.background.bg = rgba2hex(target.checkbox_bg)
    wp.checkbox_widget.indicator_container:move(
      1,
      {
        x = target.checkbox_indicator.x,
        y = 0
      }
    )
  end
end

function item:set_checkbox(value)
  self._private.checkbox_enabled = value
  if not self._private.widget then
    return
  end

  local wpcontainer = self._private.widget:get_children_by_id("container")[1]
  if value then
    wpcontainer:insert(2, self._private.checkbox_widget)
  else
    wpcontainer:remove(2)
  end
end

function item:set_on_release(on_release)
  self._private.on_release = on_release
end

function item:set_bg(bg)
  self._private.bg_normal = bg
  self._private.anim_data.bg = hex2rgba(bg)
  self._private.animation.normal.target.bg = hex2rgba(bg)
  if not self._private.widget then
    return
  end
  self._private.widget.bg = bg
end

function item:set_bg_hover(bg)
  self._private.bg_hover = bg
  self._private.animation.hover.target.bg = hex2rgba(bg)
end

function item:set_shape(shape)
  if not self._private.widget then
    return
  end
  self._private.widget.shape = shape
end

function item:set_widget(widget)
  local w = widget and wibox.widget.base.make_widget_from_value(widget)
  if w then
    wibox.widget.base.check_widget(w)
  end

  local wp = self._private

  wp.checkbox_widget = wibox.widget {}
  wp.checkbox_widget =
    wibox.widget {
    widget = wibox.container.place,
    halign = "right",
    {
      widget = wibox.container.constraint,
      width = config.dpi(32),
      height = config.dpi(16),
      strategy = "exact",
      {
        widget = wibox.container.background,
        id = "background",
        shape = function(cr, width, height)
          return gears.shape.rounded_rect(cr, width, height, height / 2)
        end,
        bg = rgba2hex(self._private.anim_data.checkbox_bg),
        {
          widget = wibox.container.margin,
          margins = config.dpi(2),
          {
            layout = wibox.layout.manual,
            id = "indicator_container",
            {
              widget = wibox.container.constraint,
              id = "indicator",
              width = config.dpi(12),
              height = config.dpi(12),
              point = {x = self._private.anim_data.checkbox_indicator.x, y = 0},
              strategy = "exact",
              {
                widget = wibox.container.background,
                shape = gears.shape.circle,
                bg = "#000000",
                {
                  widget = wibox.widget.textbox,
                  text = " "
                }
              }
            }
          }
        }
      }
    }
  }

  local wpc = wp.checkbox_widget
  wpc.background = wpc:get_children_by_id("background")[1]
  wpc.indicator_container = wpc:get_children_by_id("indicator_container")[1]
  wpc.indicator = wpc:get_children_by_id("indicator")[1]

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
        layout = wibox.layout.stack,
        id = "container",
        {
          widget = wibox.container.place,
          halign = "left",
          {
            widget = w
          }
        }
      }
    }
  }

  if wp.checkbox_enabled then
    wp.widget:get_children_by_id("container")[1]:insert(1, wp.checkbox_widget)
  end
  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

local function new()
  local ret = wibox.container.background()

  gears.table.crush(ret, item)

  local wp = ret._private
  wp.state = false

  wp.anim_data = {
    checkbox_bg = hex2rgba("#888888cc"),
    checkbox_indicator = {x = 0}
  }
  wp.animation =
    animation {
    subject = wp.anim_data,
    targets = {
      normal = {
        bg = hex2rgba(wp.bg_normal)
      },
      hover = {
        bg = hex2rgba(wp.bg_hover)
      },
      unchecked = {
        checkbox_bg = hex2rgba("#888888cc"),
        checkbox_indicator = {x = 0}
      },
      checked = {
        checkbox_bg = hex2rgba("#ffffffcc"),
        checkbox_indicator = {x = 16}
      }
    },
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_updated"] = function(s)
        wp.widget.bg = rgba2hex(s.subject.bg)

        if wp.checkbox_enabled then
          wp.checkbox_widget.background.bg = rgba2hex(s.subject.checkbox_bg)
          wp.checkbox_widget.indicator_container:move(
            1,
            {
              x = s.subject.checkbox_indicator.x,
              y = 0
            }
          )
        end
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
