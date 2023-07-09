local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local animation = require("helpers.animation")
local config = require("configuration.config")
local filesystem = require("gears.filesystem")
local keyboardlayout = require("configuration.widgets.keyboardlayout")
local bluetooth = require("configuration.widgets.bar.bluetooth")

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
          spacing = config.dpi(12),
          wibox.container.place(
            {
              base_size = config.dpi(16),
              horizontal = false,
              screen = screen,
              visible = true,
              widget = wibox.widget.systray
            },
            "center",
            "center"
          ),
          wibox.container.place(bluetooth, "center", "center"),
          wibox.container.place(keyboardlayout, "center", "center")
        }
      }
    },
    ontop = true,
    visible = false,
    type = "dialog",
    screen = screen,
    width = config.dpi(400),
    height = screen.geometry.height - config.dpi(16),
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
    widget = wibox.container.margin,
    top = config.dpi(8),
    toggle_image
  }

  toggle.buttons =
    require("gears").table.join(
    awful.button(
      {},
      1,
      function()
        awesome.emit_signal("widget::systray:toggle")
      end
    )
  )

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
