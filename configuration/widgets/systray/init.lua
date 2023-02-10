local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
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
    placement = function(c)
      return awful.placement.bottom_left(
        c,
        {
          margins = {
            bottom = config.dpi(8),
            left = config.dpi(56)
          }
        }
      )
    end,
    bg = "#111111ff"
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

  awesome.connect_signal(
    "widget::systray:toggle",
    function()
      w.screen = awful.screen.focused()
      w.visible = not w.visible
      toggle_image.image = w.visible and chevron_left or chevron_right
    end
  )

  return wibox.widget {
    widget = wibox.container.place,
    {
      layout = wibox.layout.fixed.vertical,
      -- {
      --   widget = wibox.container.place,
      --   w
      -- },
      toggle
    }
  }
end

function systray.mt:__call(...)
  return systray.new(...)
end

return setmetatable(systray, systray.mt)
