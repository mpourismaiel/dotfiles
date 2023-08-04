local capi = {
  awesome = awesome,
  screen = screen
}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local config = require("lib.config")
local theme = require("lib.config.theme")
local animation = require("helpers.animation")

local wcontainer = require("lib.widgets.menu.container")
local profile = require("lib.widgets.menu.profile")
local power = require("lib.widgets.menu.power")
local notifications = require("lib.widgets.menu.notifications")
local power_button = require("lib.widgets.menu.power-button")
local volumeslider = require("lib.widgets.volume.slider")
local wbutton = require("lib.widgets.button")

local config_dir = filesystem.get_configuration_dir()
local menu_icon = config_dir .. "/images/circle.svg"

local instance = nil
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
    position.origin = {
      bottom = config.dpi(0),
      left = theme.bar_width
    }
    position.margins = {
      bottom = theme.menu_margin_bottom,
      left = theme.bar_width + theme.menu_margin_left
    }
  end

  wp.position = position
end

function menu:set_screen(screen)
  local wp = self._private

  wp.drawer.screen = screen
  wp.backdrop.screen = screen

  wp.backdrop.x = screen.geometry.x
  wp.backdrop.y = screen.geometry.y
  wp.backdrop.width = screen.geometry.width
  wp.backdrop.height = screen.geometry.height

  local geo =
    wp.position.fn(
    wp.drawer,
    {
      margins = wp.position.margins,
      pretend = true
    }
  )

  local offset_x = 0
  if wp.systray then
    wp.animation.open.target.systray.x = geo.x
    wp.systray.y = geo.y
    offset_x = wp.systray_box + theme.menu_horizontal_spacing
  end
  wp.animation.open.target.drawer.x = geo.x + offset_x
  wp.drawer.y = geo.y
end

function menu:init_animation()
  local wp = self._private
  wp.anim_data = {
    systray = {x = wp.position.origin.left, opacity = 0},
    drawer = {x = wp.position.origin.left, opacity = 0}
  }
  wp.animation =
    animation {
    subject = wp.anim_data,
    targets = {
      open = {
        systray = {x = 0, opacity = 1},
        drawer = {x = 0, opacity = 1}
      },
      close = {
        systray = {x = wp.position.origin.left, opacity = 0},
        drawer = {x = wp.position.origin.left, opacity = 0}
      }
    },
    easing = "inOutCubic",
    duration = 0.25,
    signals = {
      ["anim::animation_updated"] = function(s)
        if wp.systray then
          wp.systray.x = s.subject.systray.x
          wp.opacity = s.subject.systray.opacity
        end
        wp.drawer.x = s.subject.drawer.x
        wp.drawer.opacity = s.subject.drawer.opacity
      end
    }
  }
end

local function new()
  if instance then
    return instance._private.toggle
  end
  local ret = {_private = {}}
  gears.table.crush(ret, menu)
  local wp = ret._private
  wp.primary_screen = capi.screen.primary

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

  wp.systray_width = config.dpi(60)
  wp.systray_box = wp.systray_width + theme.menu_horizontal_spacing * 2
  local systray =
    wibox {
    ontop = true,
    visible = false,
    type = "utility",
    width = wp.systray_box,
    height = theme.menu_height,
    bg = theme.bg_normal,
    shape = gears.shape.rounded_rect,
    widget = {
      widget = wibox.container.margin,
      top = theme.menu_vertical_spacing,
      bottom = theme.menu_vertical_spacing,
      left = theme.menu_horizontal_spacing,
      right = theme.menu_horizontal_spacing,
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = wp.systray_width,
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
      }
    }
  }

  wp.drawer_width = config.dpi(380)
  wp.drawer_box = wp.drawer_width + theme.menu_horizontal_spacing * 2

  local drawer =
    wibox {
    ontop = true,
    visible = false,
    type = "utility",
    width = wp.drawer_box,
    height = theme.menu_height,
    bg = theme.bg_normal,
    shape = gears.shape.rounded_rect,
    widget = {
      widget = wibox.container.margin,
      top = theme.menu_vertical_spacing,
      bottom = theme.menu_vertical_spacing,
      left = theme.menu_horizontal_spacing,
      right = theme.menu_horizontal_spacing,
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
              width = config.dpi(308),
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

  wp.backdrop = backdrop
  wp.drawer = drawer
  wp.systray_instance = systray
  wp.toggle = toggle

  ret:calculate_position()
  ret:init_animation()

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
      notifications.reset()
      wp.systray = nil

      wp.backdrop.visible = not is_visible
      wp.drawer.visible = not is_visible
      if s == wp.primary_screen then
        wp.systray = wp.systray_instance
        wp.systray.visible = not is_visible
      end

      if not is_visible then
        ret:set_screen(s)
        wp.animation.close:stopAnimation()
        wp.animation.open:startAnimation()
      else
        wp.animation.open:stopAnimation()
        wp.animation.close:startAnimation()
      end
    end
  )

  capi.awesome.connect_signal(
    "widget::drawer:hide",
    function()
      wp.animation.open:stopAnimation()
      wp.animation.close:startAnimation()
      wp.backdrop.visible = false
      wp.drawer.visible = false
      if wp.systray then
        wp.systray.visible = false
      end
    end
  )

  instance = ret
  return toggle
end

function menu.mt:__call(...)
  return new(...)
end

return setmetatable(menu, menu.mt)
