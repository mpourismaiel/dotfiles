local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local config = require("configuration.config")
local theme = require("configuration.config.theme")

local container = require("configuration.widgets.menu.container")
local clock = require("configuration.widgets.menu.clock")
local weather = require("configuration.widgets.menu.weather")

local config_dir = filesystem.get_configuration_dir()
local menu_icon = config_dir .. "/images/circle.svg"

local menu = {mt = {}}

function menu.new(screen)
  local toggle_template = {
    widget = wibox.container.constraint,
    strategy = "exact",
    height = config.dpi(48),
    {
      id = "background",
      widget = wibox.container.background,
      bar_widget_wrapper(
        wibox.widget {
          widget = wibox.container.margin,
          margins = config.dpi(4),
          wibox.widget.imagebox(menu_icon)
        }
      )
    },
    buttons = {
      awful.button(
        {},
        1,
        function()
          awesome.emit_signal("widget::drawer:toggle")
        end
      )
    }
  }

  local toggle = wibox.widget.base.make_widget_from_value(toggle_template)
  local background = toggle:get_children_by_id("background")[1]

  toggle:connect_signal(
    "mouse::enter",
    function()
      background.bg = "#eeeeee30"
    end
  )
  toggle:connect_signal(
    "mouse::leave",
    function()
      background.bg = ""
    end
  )

  local drawer =
    awful.popup {
    widget = {},
    ontop = true,
    visible = false,
    type = "normal",
    screen = screen,
    width = config.dpi(400),
    height = screen.geometry.height - config.dpi(16),
    shape = gears.shape.rounded_rect,
    placement = function(c)
      return awful.placement.top_left(
        c,
        {
          margins = {
            top = config.dpi(8),
            left = config.dpi(56)
          }
        }
      )
    end,
    bg = "#44444430"
  }

  drawer:setup {
    widget = wibox.container.constraint,
    width = config.dpi(400),
    height = screen.geometry.height - config.dpi(16),
    strategy = "exact",
    {
      widget = wibox.container.margin,
      margins = config.dpi(16),
      {
        layout = wibox.layout.fixed.vertical,
        spacing = config.dpi(16),
        container(clock()),
        {
          layout = wibox.layout.flex.horizontal,
          spacing = config.dpi(16),
          container(weather()),
          container(weather())
        }
      }
    }
  }

  awesome.connect_signal(
    "widget::drawer:toggle",
    function()
      drawer.visible = not drawer.visible
    end
  )

  return toggle
end

function menu.mt:__call(...)
  return menu.new(...)
end

return setmetatable(menu, menu.mt)
