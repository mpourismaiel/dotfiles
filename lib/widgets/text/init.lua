local wibox = require("wibox")
local gears = require("gears")
local theme = require("lib.configuration.theme")

local text = {mt = {}}

for _, v in pairs(
  {
    "halign",
    "valign",
    "foreground",
    "font_name",
    "font_size",
    "font_weight",
    "text",
    "ellipsize",
    "forced_height",
    "forced_width"
  }
) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  text["set_" .. v] = function(self, val)
    if self._private.label[v] == val then
      return
    end
    if v == "text" and val == nil then
      val = ""
    end
    self._private.label[v] = val
    self._private.textbox_widget.markup = self:get_markup()
    self._private.textbox_widget:emit_signal("widget::redraw_needed")
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  text["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

function text:set_bold(bold)
  local wp = self._private
  wp.label.font_weight = bold and "bold" or "normal"
  self:emit_signal("widget::layout_changed")
  self:emit_signal("property::font_weight", "bold")
end

function text:set_halign(halign)
  local wp = self._private
  wp.halign = halign
  wp.widget.halign = halign
end

function text:set_valign(valign)
  local wp = self._private
  wp.valign = valign
  wp.widget.valign = valign
end

function text:set_ellipsize(ellipsize)
  local wp = self._private
  wp.ellipsize = ellipsize
end

function text:get_markup()
  local wp = self._private
  local wpl = wp.label

  local font = wpl.font_name .. " " .. wpl.font_weight .. " " .. wpl.font_size
  return "<span foreground='" .. wpl.foreground .. "' font='" .. font .. "'>" .. wpl.text .. "</span>"
end

function text:set_forced_height(height)
  local wp = self._private
  wp.forced_height = height

  self.widget = self:contain()
  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

function text:set_forced_width(width)
  local wp = self._private
  wp.forced_width = width

  self.widget = self:contain()
  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

function text:contain()
  local wp = self._private
  if wp.forced_width ~= nil or wp.forced_height ~= nil then
    return wibox.widget {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = wp.forced_width,
      height = wp.forced_height,
      wp.widget
    }
  end

  return wp.widget
end

local function new()
  local ret = wibox.container.background()
  gears.table.crush(ret, text)

  local wp = ret._private
  wp.widget =
    wibox.widget {
    widget = wibox.container.place,
    halign = "left",
    valign = "center",
    {
      widget = wibox.widget.textbox,
      id = "text",
      text = ""
    }
  }

  ret.widget = ret:contain()
  ret:emit_signal("property::widget")
  ret:emit_signal("widget::layout_changed")

  wp.textbox_widget = wp.widget:get_children_by_id("text")[1]
  wp.label = {
    halign = "left",
    valign = "center",
    font_name = theme.font_name,
    font_size = theme.font_size,
    font_weight = "Regular",
    foreground = theme.fg_primary,
    text = ""
  }

  ret:connect_signal(
    "widget::layout_changed",
    function()
      wp.textbox_widget.markup = ret:get_markup()
    end
  )

  return ret
end

function text.mt:__call()
  return new()
end

return setmetatable(text, text.mt)
