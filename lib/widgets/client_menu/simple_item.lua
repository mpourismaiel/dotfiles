local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")

local item = {mt = {}}

for _, v in pairs({"bg"}) do
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

function item:set_bg(bg)
  self._private.bg_normal = bg
  if not self._private.widget then
    return
  end
  self._private.widget.bg = bg
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
        widget = w
      }
    }
  }
  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

local function new()
  local ret = wibox.container.background()

  gears.table.crush(ret, item)

  ret:set_bg("#222222cc")

  return ret
end

function item.mt:__call(...)
  return new()
end

return setmetatable(item, item.mt)
