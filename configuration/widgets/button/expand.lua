local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local animation = require("helpers.animation")
local wbutton = require("configuration.widgets.button")

local expand = {mt = {}}

for _, v in pairs({"bg_normal", "bg_hover", "hidden", "spacing", "widget"}) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  expand["set_" .. v] = function(self, val)
    if self._private[v] == val then
      return
    end
    self._private[v] = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  expand["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

function expand:set_bg_hover()
end

function expand:set_hidden(widget)
  local wp = self._private
  wp.hidden = widget

  if not wp.widget then
    return
  end

  local expandable = wp.widget:get_children_by_id("expandable")[1]
  expandable.children[2] = widget
end

function expand:set_widget(widget)
  local wp = self._private

  local w =
    wibox {
    widget = {
      widget = wibox.container.constraint,
      strategy = "exact",
      {
        widget = wbutton,
        bg_normal = wp.bg_normal,
        bg_hover = wp.bg_hover,
        callback = function()
          wp.hidden = not wp.hidden
          self:emit_signal("property::hidden")
        end,
        {
          layout = wibox.layout.fixed.horizontal,
          spacing = wp.spacing,
          id = "expandable",
          widget
        }
      }
    }
  }

  local expandable = w:get_children_by_id("expandable")[1]
  -- wp.width = geo.width
  -- expandable.children[2] = wp.hidden
  -- wp.max_width = geo.max_width
  -- wp.anim_data.width = wp.width

  wp.widget = w
  self:emit_signal("property::widget")
  self:emit_signal("widget::layout_changed")
end

local function new()
  local ret = wibox.container.background()
  gears.table.crush(ret, expand)

  local wp = ret._private
  wp.width = 0
  wp.max_width = 0
  wp.anim_data = {
    width = wp.width
  }
  wp.animation =
    animation {
    subject = wp.anim_data,
    targets = {
      normal = {
        width = wp.width
      },
      expanded = {
        width = wp.max_width
      }
    },
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_updated"] = function(s)
      end
    }
  }

  ret:connect_signal(
    "property::hidden",
    function()
      wp.animation.normal:stopAnimation()
      wp.animation.expanded:stopAnimation()

      if wp.hidden then
        wp.animation.normal:startAnimation()
      else
        wp.animation.expanded:startAnimation()
      end
    end
  )

  return ret
end

function expand.mt:__call()
  return new()
end

return setmetatable(expand, expand.mt)
