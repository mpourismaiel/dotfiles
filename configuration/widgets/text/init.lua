local wibox = require("wibox")
local gears = require("gears")
local animation = require("helpers.animation")
local colors = require("helpers.color")
local theme = require("configuration.config.theme")

local text = {mt = {}}

for _, v in pairs({"halign", "valign", "foreground", "font_name", "font_size", "font_weight", "text"}) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  text["set_" .. v] = function(self, val)
    gears.debug.dump(val, "=========== " .. v .. ":")
    if self._private.label[v] == val then
      return
    end
    self._private.label[v] = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  text["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

function text:set_fg_normal(fg)
  local wp = self._private
  wp.fg_normal = fg
  if not wp.label then
    return
  end
  wp.label.foreground = fg
  wp.label.widget.markup = self:get_markup()
end

function text:set_halign(halign)
  local wp = self._private
  wp.halign = halign
  if not wp.label then
    return
  end
  wp.label.halign = halign
end

function text:set_valign(valign)
  local wp = self._private
  wp.valign = valign
  if not wp.label then
    return
  end
  wp.label.valign = valign
end

function text:get_markup()
  local wp = self._private
  local wpl = wp.label

  local font = wpl.font_name .. " " .. wpl.font_weight .. " " .. wpl.font_size
  return "<span foreground='" .. wpl.foreground .. "' font='" .. font .. "'>" .. wpl.text .. "</span>"
end

local function new()
  local ret =
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
  gears.table.crush(ret, text)

  local wp = ret._private
  wp.widget = ret:get_children_by_id("text")[1]
  wp.fg_normal = theme.fg_primary
  wp.label = {
    halign = "left",
    valign = "center",
    font_name = theme.font_name,
    font_size = theme.font_size,
    font_weight = "Regular",
    foreground = wp.fg_normal
  }

  ret:connect_signal(
    "widget::layout_changed",
    function()
      wp.widget.markup = ret:get_markup()
    end
  )

  return ret
end

function text.mt:__call()
  return new()
end

return setmetatable(text, text.mt)
