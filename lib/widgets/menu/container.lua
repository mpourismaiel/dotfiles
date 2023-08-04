local wibox = require("wibox")
local gears = require("gears")
local theme = require("lib.config.theme")

local container = {mt = {}}

for _, v in pairs({"padding_left", "padding_right", "padding_top", "padding_bottom", "bg"}) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  container["set_" .. v] = function(self, val)
    if self._private[v] == val then
      return
    end
    self._private[v] = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  container["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

function container:set_widget(w)
  local wp = self._private
  local widget =
    wibox.widget {
    widget = wibox.container.background,
    bg = wp.bg,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_large)
    end,
    {
      widget = wibox.container.margin,
      left = wp.padding_left,
      right = wp.padding_right,
      top = wp.padding_top,
      bottom = wp.padding_bottom,
      w
    }
  }

  wp.widget = widget
  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

local function new()
  local ret = wibox.container.background()
  gears.table.crush(ret, container)

  local wp = ret._private
  wp.padding_left = theme.menu_container_padding_left
  wp.padding_right = theme.menu_container_padding_right
  wp.padding_top = theme.menu_container_padding_top
  wp.padding_bottom = theme.menu_container_padding_bottom
  wp.bg = theme.bg_secondary

  return ret
end

function container.mt:__call(...)
  return new(...)
end

return setmetatable(container, container.mt)
