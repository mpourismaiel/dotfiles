local wibox = require("wibox")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local config = require("lib.config")
local animation = require("helpers.animation")

local dropdown = {mt = {}}

local config_dir = filesystem.get_configuration_dir()
local chevron_up = config_dir .. "/images/chevron-up.svg"
local chevron_down = config_dir .. "/images/chevron-down.svg"

for _, v in pairs({"bg", "bg_hover", "shape", "on_select", "options", "value"}) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  dropdown["set_" .. v] = function(self, val)
    if self._private[v] == val then
      return
    end
    self._private[v] = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  dropdown["get_" .. v] = function(layout)
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

function dropdown:toggle()
  local wp = self._private
  if wp.opened == nil then
    wp.opened = false
  end

  wp.opened = not wp.opened
  if wp.opened then
    wp.dropdown_state.image = chevron_up
    wp.animation.close:stopAnimation()
    wp.animation.open:startAnimation()
  else
    wp.dropdown_state.image = chevron_down
    wp.animation.open:stopAnimation()
    wp.animation.close:startAnimation()
  end
end

function dropdown:set_value(value)
  local wp = self._private
  wp.value = value

  if not wp.widget then
    return
  end

  for _, v in pairs(wp.dropdown_options._private.options) do
    v.bg = "#888888"
  end
  local w = wp.dropdown_options._private.options[tonumber(value)]
  w.bg = "#ffffff"
end

function dropdown:set_options(options)
  local wp = self._private
  wp.options = type(options) == "function" and options() or options

  if not wp.widget then
    return
  end

  wp.dropdown_options:reset()
  wp.dropdown_options._private.options = {}
  for _, v in pairs(options) do
    local w =
      wibox.widget {
      widget = wibox.container.constraint,
      width = config.dpi(12),
      height = config.dpi(12),
      strategy = "exact",
      {
        widget = wibox.container.background,
        id = "option",
        shape = function(cr, w, h)
          return gears.shape.circle(cr, w, h)
        end,
        bg = "#888888",
        {
          widget = wibox.widget.textbox,
          text = " "
        }
      }
    }

    local option = w:get_children_by_id("option")[1]
    w:connect_signal(
      "mouse::enter",
      function()
        option.bg = "#ffffff"
      end
    )
    w:connect_signal(
      "mouse::leave",
      function()
        option.bg = wp.value == v and "#ffffff" or "#888888"
      end
    )
    w:connect_signal(
      "button::release",
      function()
        self.value = v
        if wp.on_select then
          wp.on_select(v)
        end
      end
    )

    wp.dropdown_options._private.options[v] = option
    wp.dropdown_options:add(w)
  end
end

function dropdown:set_on_select(on_select)
  local wp = self._private
  wp.on_select = on_select
end

function dropdown:set_bg(bg)
  local wp = self._private
  wp.bg_normal = bg
  wp.anim_data.bg = hex2rgba(bg)
  wp.animation.normal.target.bg = hex2rgba(bg)
  if not wp.widget then
    return
  end
  wp.widget.bg = bg
end

function dropdown:set_bg_hover(bg)
  local wp = self._private
  wp.bg_hover = bg
  wp.animation.hover.target.bg = hex2rgba(bg)
end

function dropdown:set_shape(shape)
  local wp = self._private
  if not wp.widget then
    return
  end
  wp.widget.shape = shape
end

function dropdown:set_widget(widget)
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
      layout = wibox.layout.fixed.vertical,
      {
        widget = wibox.container.margin,
        id = "dropdown_button",
        top = config.dpi(10),
        bottom = config.dpi(10),
        left = config.dpi(20),
        right = config.dpi(20),
        {
          layout = wibox.layout.stack,
          {
            widget = wibox.container.place,
            halign = "left",
            {
              widget = w
            }
          },
          {
            widget = wibox.container.place,
            halign = "right",
            {
              widget = wibox.container.constraint,
              width = config.dpi(16),
              height = config.dpi(16),
              strategy = "max",
              {
                widget = wibox.container.place,
                halign = "center",
                valign = "center",
                {
                  widget = wibox.widget.imagebox,
                  id = "dropdown_state",
                  image = chevron_down
                }
              }
            }
          }
        }
      },
      {
        widget = wibox.container.constraint,
        height = 0,
        strategy = "exact",
        id = "dropdown_menu",
        {
          widget = wibox.container.background,
          bg = "#333333cc",
          {
            widget = wibox.container.margin,
            top = config.dpi(10),
            bottom = config.dpi(10),
            left = config.dpi(20),
            right = config.dpi(20),
            {
              widget = wibox.layout.flex.horizontal,
              spacing = config.dpi(10),
              id = "dropdown_options"
            }
          }
        }
      }
    }
  }

  wp.dropdown_state = wp.widget:get_children_by_id("dropdown_state")[1]
  wp.dropdown_button = wp.widget:get_children_by_id("dropdown_button")[1]
  wp.dropdown_menu = wp.widget:get_children_by_id("dropdown_menu")[1]
  wp.dropdown_options = wp.widget:get_children_by_id("dropdown_options")[1]

  wp.dropdown_button:connect_signal(
    "button::release",
    function()
      self:toggle()
    end
  )

  if not wp.options_widget and wp.options then
    self:set_options(wp.options)
  end

  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

local function new()
  local ret = wibox.container.background()

  gears.table.crush(ret, dropdown)

  local wp = ret._private
  wp.state = false

  wp.anim_data = {height = 0}
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
      close = {
        height = 0
      },
      open = {
        height = 32
      }
    },
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_updated"] = function(s)
        wp.widget.bg = rgba2hex(s.subject.bg)
        wp.dropdown_menu.height = s.subject.height
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

  ret:set_bg("#222222cc")
  ret:set_bg_hover("#333333cc")
  ret:set_shape(gears.shape.rectangle)

  return ret
end

function dropdown.mt:__call(...)
  return new()
end

return setmetatable(dropdown, dropdown.mt)
