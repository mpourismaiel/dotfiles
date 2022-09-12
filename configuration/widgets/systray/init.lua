local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local config = require("configuration.config")
local filesystem = require("gears.filesystem")

local config_dir = filesystem.get_configuration_dir()
local chevron_up = config_dir .. "/images/chevron-up.svg"

local systray = {mt = {}}

function systray.new(screen)
  local w =
    wibox.widget {
    widget = wibox.container.background,
    visible = false,
    {
      widget = wibox.container.margin,
      margins = config.dpi(2),
      {
        base_size = config.dpi(16),
        horizontal = false,
        screen = screen == nil and awful.screen.focused() or screen,
        visible = true,
        widget = wibox.widget.systray
      }
    }
  }

  awesome.connect_signal(
    "widget::systray:toggle",
    function()
      w.screen = awful.screen.focused()
      w.visible = not w.visible
    end
  )

  local toggle =
    wibox.widget {
    widget = wibox.container.margin,
    top = config.dpi(9),
    wibox.widget.imagebox(chevron_up)
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

  return wibox.widget {
    widget = wibox.container.place,
    {
      layout = wibox.layout.fixed.vertical,
      {
        widget = wibox.container.place,
        w
      },
      toggle
    }
  }
end

function systray.mt:__call(...)
  return systray.new(...)
end

return setmetatable(systray, systray.mt)
