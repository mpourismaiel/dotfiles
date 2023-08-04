local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local animation = require("lib.helpers.animation")
local theme = require("lib.configuration.theme")
local config = require("lib.configuration")

local osd = {mt = {}}

function osd:show()
  self.animation.invisible:stopAnimation()
  self.animation.visible:startAnimation()
end

function osd:hide()
  self.animation.visible:stopAnimation()
  self.animation.invisible:startAnimation()
end

function osd.new(w)
  local ret = {}
  gears.table.crush(ret, osd)

  ret.anim_data = {x = 0, opacity = 0.0}
  local function placement_fn(c)
    return awful.placement.right(
      c,
      {
        margins = {
          right = ret.anim_data.x
        }
      }
    )
  end

  ret.w =
    awful.popup {
    widget = {},
    type = "normal",
    width = theme.osd_width,
    height = theme.osd_height,
    screen = awful.screen.focused(),
    ontop = true,
    visible = false,
    shape = gears.shape.rounded_rect,
    bg = "#44444430",
    opacity = ret.anim_data.opacity,
    placement = placement_fn
  }

  ret.w:setup {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = theme.osd_width,
    height = theme.osd_height,
    w
  }

  ret.animation =
    animation {
    subject = ret.anim_data,
    targets = {visible = {x = 24, opacity = 1.0}, invisible = {x = 0, opacity = 0.0}},
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_started"] = function(s)
        ret.w.visible = true
      end,
      ["anim::animation_updated"] = function(s, delta)
        placement_fn(ret.w)
        ret.w.opacity = ret.anim_data.opacity
      end,
      ["anim::animation_finished"] = function(s)
        if s.subject.x == 0 then
          ret.w.visible = false
        end
      end
    }
  }

  return ret
end

function osd.mt:__call(...)
  return osd.new(...)
end

return setmetatable(osd, osd.mt)
