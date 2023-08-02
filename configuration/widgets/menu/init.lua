local capi = {
  awesome = awesome
}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local config = require("configuration.config")
local theme = require("configuration.config.theme")

local wcontainer = require("configuration.widgets.menu.container")
local profile = require("configuration.widgets.menu.profile")
local power = require("configuration.widgets.menu.power")
local notifications = require("configuration.widgets.menu.notifications")
local power_button = require("configuration.widgets.menu.power-button")
local volumeslider = require("configuration.widgets.volume.slider")
local wbutton = require("configuration.widgets.button")

local config_dir = filesystem.get_configuration_dir()
local menu_icon = config_dir .. "/images/circle.svg"

local menu = {mt = {}}

function menu:calculate_position()
  local wp = self._private
  local theme_position = theme.menu_position
  local position = {
    fn = nil,
    margins = {}
  }

  if theme_position == "bottom_left" then
    position.fn = awful.placement.bottom_left
    position.margins = {
      bottom = config.dpi(8),
      left = config.dpi(64)
    }
  end

  wp.position = position
end

function menu:set_screen(screen)
  local wp = self._private

  wp.drawer.screen = screen
  wp.backdrop.screen = screen
  wp.systray.screen = screen

  wp.backdrop.x = screen.geometry.x
  wp.backdrop.y = screen.geometry.y
  wp.backdrop.width = screen.geometry.width
  wp.backdrop.height = screen.geometry.height

  wp.drawer.height = config.dpi(600)
  local geo =
    wp.position.fn(
    wp.drawer,
    {
      margins = wp.position.margins,
      pretend = true
    }
  )
  wp.drawer.x = geo.x
  wp.drawer.y = geo.y
end

local function new()
  local ret = {_private = {}}
  gears.table.crush(ret, menu)

  local toggle =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    height = config.dpi(48),
    {
      widget = wbutton,
      margin = theme.bar_padding,
      paddings = 12,
      bg_normal = theme.bg_normal,
      bg_hover = theme.bg_primary,
      callback = function()
        capi.awesome.emit_signal("widget::drawer:toggle")
      end,
      {
        widget = wibox.widget.imagebox(menu_icon)
      }
    }
  }

  local backdrop =
    wibox {
    ontop = true,
    bg = "#ffffff00",
    type = "utility"
  }

  local drawer =
    wibox {
    ontop = true,
    visible = false,
    type = "utility",
    width = config.dpi(460),
    bg = theme.bg_normal,
    shape = gears.shape.rounded_rect,
    widget = {
      widget = wibox.container.margin,
      top = theme.menu_vertical_spacing,
      bottom = theme.menu_vertical_spacing,
      left = theme.menu_horizontal_spacing,
      right = theme.menu_horizontal_spacing,
      {
        layout = wibox.layout.fixed.horizontal,
        spacing = theme.menu_horizontal_spacing,
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(60),
          {
            widget = wcontainer,
            {
              widget = wibox.container.place,
              valign = "bottom",
              {
                widget = wibox.widget.systray,
                base_size = config.dpi(16),
                horizontal = false,
                id = "systray"
              }
            }
          }
        },
        {
          layout = wibox.layout.align.vertical,
          {
            widget = wibox.container.margin,
            bottom = theme.menu_vertical_spacing,
            {
              layout = wibox.layout.fixed.horizontal,
              spacing = theme.menu_horizontal_spacing,
              {
                widget = wibox.container.constraint,
                strategy = "exact",
                width = config.dpi(292),
                height = config.dpi(48),
                profile
              },
              {
                widget = wibox.container.constraint,
                strategy = "exact",
                width = config.dpi(60),
                height = config.dpi(60),
                power
              }
            }
          },
          {
            widget = wibox.container.margin,
            bottom = theme.menu_vertical_spacing,
            {
              widget = wcontainer,
              notifications
            }
          },
          {
            layout = wibox.layout.fixed.vertical,
            spacing = theme.menu_vertical_spacing,
            volumeslider,
            {
              layout = wibox.layout.flex.horizontal,
              spacing = config.dpi(8),
              power_button("lock"),
              power_button("sleep"),
              power_button("logout"),
              power_button("reboot"),
              power_button("power")
            }
          }
        }
      }
    }
  }

  local wp = ret._private
  wp.backdrop = backdrop
  wp.drawer = drawer
  wp.systray = wp.drawer:get_children_by_id("systray")[1]

  ret:calculate_position()

  backdrop:connect_signal(
    "button::release",
    function()
      capi.awesome.emit_signal("widget::drawer:hide")
    end
  )

  capi.awesome.connect_signal(
    "widget::drawer:toggle",
    function()
      local s = awful.screen.focused()
      local is_visible = backdrop.visible
      if not is_visible then
        ret:set_screen(s)
      end

      wp.backdrop.visible = not is_visible
      wp.drawer.visible = not is_visible
      notifications.reset()
    end
  )

  capi.awesome.connect_signal(
    "widget::drawer:hide",
    function()
      wp.backdrop.visible = false
      drawer.visible = false
    end
  )
  return toggle
end

function menu.mt:__call()
  return new()
end

return setmetatable(menu, menu.mt)
