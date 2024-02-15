local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local animation = require("lib.helpers.animation")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local filesystem = require("gears.filesystem")
local keyboardlayout = require("lib.widgets.keyboardlayout")
local bluetooth = require("lib.widgets.bar.bluetooth")
local wbutton = require("lib.widgets.button")

local config_dir = filesystem.get_configuration_dir()
local chevron_right = config_dir .. "/images/chevron-right.svg"
local chevron_left = config_dir .. "/images/chevron-left.svg"

local systray = {mt = {}}

function systray.new(screen)
  screen = screen == nil and awful.screen.focused() or screen

  local anim_data = {x = config.dpi(48), y = config.dpi(8), opacity = 0}
  local function placement_fn(c)
    local result =
      awful.placement.bottom_left(
      c,
      {
        margins = {
          bottom = anim_data.y,
          left = anim_data.x
        },
        pretend = true
      }
    )

    c.x = result.x
    c.y = result.y
  end

  local w =
    awful.popup {
    widget = wibox.widget {
      widget = wibox.container.margin,
      top = config.dpi(8),
      bottom = config.dpi(8),
      left = config.dpi(4),
      right = config.dpi(4),
      {
        widget = wibox.container.margin,
        margins = config.dpi(2),
        {
          layout = wibox.layout.fixed.vertical,
          {
            widget = wbutton,
            margin = theme.bar_padding,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            paddings = 8,
            {
              widget = bluetooth
            }
          },
          {
            widget = wbutton,
            strategy = "exact",
            width = config.dpi(64),
            height = config.dpi(64),
            margin = theme.bar_padding,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            paddings = 0,
            {
              widget = keyboardlayout
            }
          }
        }
      }
    },
    ontop = true,
    visible = false,
    type = "dialog",
    screen = screen,
    shape = function(cr, w, h)
      return gears.shape.rounded_rect(cr, w, h, config.dpi(8))
    end,
    bg = "#111111ff",
    opacity = anim_data.opacity
  }

  local toggle_image = wibox.widget.imagebox()
  toggle_image.image = chevron_right
  local toggle =
    wibox.widget {
    widget = wbutton,
    margin = theme.bar_padding,
    bg_normal = theme.bg_normal,
    bg_hover = theme.bg_primary,
    paddings = 8,
    callback = function()
      awesome.emit_signal("widget::systray:toggle")
    end,
    toggle_image
  }

  local anim =
    animation {
    subject = anim_data,
    targets = {visible = {x = 56, opacity = 1}, invisible = {x = 48, opacity = 0}},
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_started"] = function(s)
        w.visible = true
      end,
      ["anim::animation_updated"] = function(s, delta)
        placement_fn(w)
        w.opacity = anim_data.opacity
      end,
      ["anim::animation_finished"] = function(s)
        if s.subject.x == 48 then
          w.visible = false
        end
      end
    }
  }

  awesome.connect_signal(
    "widget::systray:toggle",
    function()
      w.screen = awful.screen.focused()
      if w.visible then
        anim.visible:stopAnimation()
        anim.invisible:startAnimation()
      else
        anim.invisible:stopAnimation()
        anim.visible:startAnimation()
      end
      toggle_image.image = w.visible and chevron_left or chevron_right
    end
  )

  return wibox.widget {
    widget = wibox.container.place,
    {
      layout = wibox.layout.fixed.vertical,
      toggle
    }
  }
end

function systray.mt:__call(...)
  return systray.new(...)
end

return setmetatable(systray, systray.mt)
