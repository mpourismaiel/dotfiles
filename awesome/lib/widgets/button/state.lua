local wibox = require("wibox")
local gears = require("gears")
local theme = require("lib.configuration.theme")
local wbutton = require("lib.widgets.button")
local console = require("lib.helpers.console")

local state = {mt = {}}

function state:toggle()
  local wp = self._private
  wp.state = not wp.state
  if wp.state then
    self:turn_on()
  else
    self:turn_off()
  end
end

function state:turn_on()
  local wp = self._private
  if wp.widget_on then
    self:set_widget(wp.widget_on)
  end

  wp.off_bg_normal = self:get_bg_normal()
  self:set_bg_normal(wp.selected_color)
end

function state:turn_off()
  local wp = self._private
  if wp.widget_off then
    self:set_widget(wp.widget_off)
  end

  if wp.off_bg_normal then
    self:set_bg_normal(wp.off_bg_normal)
  end
end

function state:set_disabled(disabled)
  local wp = self._private
  wp.disabled = disabled
end

function state:get_disabled()
  local wp = self._private
  return wp.disabled
end

function state:set_selected_color(color)
  local wp = self._private
  wp.selected_color = color
end

function state:get_selected_color()
  local wp = self._private
  return wp.selected_color
end

function state:set_callback(callback)
  local wp = self._private

  wp.callback = function()
    if wp.disabled then
      return
    end

    if callback then
      local ret = callback(self, wp.state)
      if not ret then
        return
      end

      self:toggle()
    else
      self:toggle()
    end
  end
end

function state:get_callback()
  local wp = self._private
  return wp.callback
end

function state:set_widget_on(widget)
  local wp = self._private
  wp.widget_on = widget

  if wp.state then
    self:set_widget(widget)
  end
end

function state:get_widget_on()
  local wp = self._private
  return wp.widget_on
end

function state:set_widget_off(widget)
  local wp = self._private
  wp.widget_off = widget

  if not wp.state then
    self:set_widget(widget)
  end
end

function state:get_widget_off()
  local wp = self._private
  return wp.widget_off
end

local function new()
  local ret =
    wibox.widget {
    widget = wbutton,
    label = ""
  }
  gears.table.crush(ret, state, true)

  local wp = ret._private
  wp.state = false
  wp.selected_color = theme.bg_hover
  ret:set_callback()

  return ret
end

function state.mt:__call(...)
  return new(...)
end

return setmetatable(state, state.mt)
