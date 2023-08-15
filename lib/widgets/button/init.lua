local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local animation = require("lib.helpers.animation")
local colors = require("lib.helpers.color")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local console = require("lib.helpers.console")

local button = {mt = {}}

for _, v in pairs(
  {
    "bg_press",
    "fg_press",
    "margin",
    "padding_top",
    "padding_bottom",
    "padding_left",
    "padding_right",
    "paddings",
    "bg_normal",
    "fg_normal",
    "bg_hover",
    "fg_hover",
    "bg_press",
    "fg_press",
    "shape",
    "halign",
    "callback",
    "middle_click_callback",
    "right_click_callback",
    "disable_hover",
    "rounded"
  }
) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  button["set_" .. v] = function(self, val)
    if self._private[v] == val then
      return
    end
    self._private[v] = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  button["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

function button:set_rounded(rounded)
  local wp = self._private
  wp.rounded = rounded
  self:set_shape(wp.shape_value)
end

function button:set_halign(halign)
  local wp = self._private
  wp.halign = halign
  wp.place_role.halign = halign
end

function button:set_shape(shape)
  local wp = self._private
  wp.shape_value = shape
  if type(shape) == "string" then
    if shape == "rounded" then
      shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, wp.rounded or theme.rounded_rect_normal)
      end
    elseif shape == "circle" then
      shape = function(cr, width, height)
        gears.shape.circle(cr, width, height)
      end
    elseif shape == "rectangle" then
      shape = function(cr, width, height)
        gears.shape.rectangle(cr, width, height)
      end
    end
  end
  wp.shape = shape
  wp.background_role.shape = shape
end

function button:set_bg_normal(bg)
  local wp = self._private
  wp.bg_normal = bg
  wp.anim_data.bg = colors.hex2rgba(bg)
  wp.animation.normal.target.bg = colors.hex2rgba(bg)
  wp.background_role.bg = bg
end

function button:set_fg_normal(fg)
  local wp = self._private
  wp.fg_normal = fg
  wp.anim_data.fg = colors.hex2rgba(fg)
  wp.animation.normal.target.fg = colors.hex2rgba(fg)
  if not wp.label or not wp.label.markup then
    return
  end
  wp.label.foreground = fg
  wp.label.widget.markup = self:get_markup()
end

function button:set_bg_hover(bg)
  local wp = self._private
  wp.bg_hover = bg
  wp.animation.hover.target.bg = colors.hex2rgba(bg)
end

function button:set_fg_hover(fg)
  local wp = self._private
  wp.fg_hover = fg
  wp.animation.hover.target.fg = colors.hex2rgba(fg)
end

function button:get_markup()
  local wp = self._private
  return "<span foreground='" .. wp.label.foreground .. "'>" .. wp.label.text .. "</span>"
end

function button:hover()
  local wp = self._private
  if wp.hovered then
    return
  end

  wp.hovered = true
  wp.animation.normal:stopAnimation()
  wp.animation.hover:startAnimation()
  self:emit_signal("widget::hover")
end

function button:unhover()
  local wp = self._private
  if not wp.hovered then
    return
  end
  wp.hovered = false
  wp.animation.hover:stopAnimation()
  wp.animation.normal:startAnimation()
end

function button:set_margin(margin)
  local wp = self._private
  wp.margin = margin
  wp.margin_role.top = margin
  wp.margin_role.bottom = margin
  wp.margin_role.left = margin
  wp.margin_role.right = margin
end

function button:set_paddings(paddings)
  local wp = self._private
  wp.paddings = paddings
  wp.padding_role.top = paddings
  wp.padding_role.bottom = paddings
  wp.padding_role.left = paddings
  wp.padding_role.right = paddings
end

function button:set_padding_left(padding_left)
  local wp = self._private
  wp.padding_left = padding_left
  wp.padding_role.left = padding_left
end

function button:set_padding_right(padding_right)
  local wp = self._private
  wp.padding_right = padding_right
  wp.padding_role.right = padding_right
end

function button:set_padding_top(padding_top)
  local wp = self._private
  wp.padding_top = padding_top
  wp.padding_role.top = padding_top
end

function button:set_padding_bottom(padding_bottom)
  local wp = self._private
  wp.padding_bottom = padding_bottom
  wp.padding_role.bottom = padding_bottom
end

function button:get_paddings()
  local wp = self._private
  local default = wp.paddings or 0
  return {
    top = wp.padding_top or default,
    bottom = wp.padding_bottom or default,
    left = wp.padding_left or default,
    right = wp.padding_right or default
  }
end

function button:set_label(label)
  self:set_widget(label)
end

function button:set_widget(widget)
  local wp = self._private
  if type(widget) == "string" then
    wp.label = {
      foreground = self._private.fg_normal,
      text = widget
    }
    wp.label.widget =
      wibox.widget {
      widget = wibox.widget.textbox,
      markup = self:get_markup()
    }
  else
    wp.label = {widget = widget}
  end

  local w = wp.label.widget and wibox.widget.base.make_widget_from_value(wp.label.widget)
  if w then
    wibox.widget.base.check_widget(w)
  end

  wp.place_role:set_widget(w)
end

local function new()
  local ret =
    wibox.widget {
    widget = wibox.container.margin,
    id = "margins",
    {
      widget = wibox.container.background,
      id = "background",
      {
        widget = wibox.container.margin,
        id = "paddings",
        {
          widget = wibox.container.place,
          id = "place"
        }
      }
    }
  }
  gears.table.crush(ret, button)

  local wp = ret._private
  wp.background_role = ret:get_children_by_id("background")[1]
  wp.padding_role = ret:get_children_by_id("paddings")[1]
  wp.margin_role = ret:get_children_by_id("margins")[1]
  wp.place_role = ret:get_children_by_id("place")[1]
  wp.anim_data = {
    bg = colors.hex2rgba(wp.bg_normal)
  }

  wp.animation =
    animation {
    subject = wp.anim_data,
    targets = {
      normal = {
        bg = colors.hex2rgba(wp.bg_normal),
        fg = colors.hex2rgba(wp.fg_normal)
      },
      hover = {
        bg = colors.hex2rgba(wp.bg_hover),
        fg = colors.hex2rgba(wp.fg_hover)
      }
    },
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_updated"] = function(s)
        wp.background_role.bg = colors.rgba2hex(s.subject.bg)
        wp.label.foreground = colors.rgba2hex(s.subject.fg)
        if wp.label and wp.label.markup then
          wp.label.widget.markup = ret:get_markup()
        end
      end
    }
  }

  ret:connect_signal(
    "mouse::enter",
    function()
      if wp.disable_hover then
        return
      end
      ret:hover()
    end
  )

  ret:connect_signal(
    "mouse::leave",
    function()
      if wp.disable_hover then
        return
      end
      ret:unhover()
    end
  )

  ret:connect_signal(
    "button::press",
    function()
      wp.animation.hover:stopAnimation()
      wp.background_role.bg = wp.bg_press
      wp.label.foreground = wp.fg_press
      if wp.label and wp.label.markup then
        wp.label.widget.markup = ret:get_markup()
      end
    end
  )

  ret:connect_signal(
    "button::release",
    function()
      wp.animation.normal:stopAnimation()
      wp.background_role.bg = wp.bg_hover
      wp.label.foreground = wp.fg_hover
      if wp.label and wp.label.markup then
        wp.label.widget.markup = ret:get_markup()
      end
      if not wp.callback then
        return
      end
    end
  )

  ret.buttons =
    gears.table.join(
    awful.button(
      {},
      1,
      function()
        if not wp.callback then
          return
        end
        wp.callback()
      end
    ),
    awful.button(
      {},
      2,
      function()
        if not wp.middle_click_callback then
          return
        end
        wp.middle_click_callback()
      end
    ),
    awful.button(
      {},
      3,
      function()
        if not wp.right_click_callback then
          return
        end
        wp.right_click_callback()
      end
    )
  )

  ret:set_bg_normal(theme.bg_primary)
  ret:set_fg_normal(theme.fg_normal)
  ret:set_bg_hover(theme.bg_hover)
  ret:set_fg_hover(theme.fg_primary)
  ret:set_bg_press(theme.bg_press)
  ret:set_fg_press(theme.fg_press)
  ret:set_shape(theme.button_shape)
  ret:set_halign(theme.button_halign)
  ret:set_padding_top(theme.button_padding_top)
  ret:set_padding_bottom(theme.button_padding_bottom)
  ret:set_padding_left(theme.button_padding_left)
  ret:set_padding_right(theme.button_padding_right)
  ret:set_margin(config.dpi(0))

  return ret
end

function button.mt:__call()
  return new()
end

return setmetatable(button, button.mt)
