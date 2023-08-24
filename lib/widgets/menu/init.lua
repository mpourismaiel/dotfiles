local capi = {
  awesome = awesome,
  screen = screen
}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local animation = require("lib.helpers.animation")
local animation_new = require("lib.helpers.animation-new")
local console = require("lib.helpers.console")

local wcontainer = require("lib.widgets.menu.container")
local layoutbox = require("lib.widgets.menu.layoutbox")
local profile = require("lib.widgets.menu.profile")
local power = require("lib.widgets.menu.power")
local notifications = require("lib.widgets.menu.notifications")
local info = require("lib.widgets.menu.info")
local volume = require("lib.widgets.menu.volume")
local compositor = require("lib.widgets.menu.compositor")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")

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

function menu:calculate_geo()
  local wp = self._private

  return wp.position.fn(
    wp.drawer,
    {
      margins = wp.position.margins,
      pretend = true
    }
  )
end

function menu:set_screen(screen)
  local wp = self._private

  wp.drawer.screen = screen
  wp.backdrop.screen = screen

  wp.backdrop.x = screen.geometry.x
  wp.backdrop.y = screen.geometry.y
  wp.backdrop.width = screen.geometry.width
  wp.backdrop.height = screen.geometry.height

  local geo = self:calculate_geo()

  local offset_x = 0
  if wp.systray then
    wp.animation.open.target.systray.x = geo.x
    wp.anim_data.systray.x = wp.animation.open.target.systray.x - config.dpi(10)
    wp.systray.y = geo.y
    offset_x = wp.systray_box + theme.menu_horizontal_spacing
  end
  wp.animation.open.target.drawer.x = geo.x + offset_x
  wp.anim_data.drawer.x = wp.animation.open.target.drawer.x - config.dpi(50)
  wp.drawer.y = geo.y

  wp.dropdown_x = wp.animation.open.target.drawer.x + wp.drawer_box + theme.menu_horizontal_spacing
  wp.dropdown_y = geo.y
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

  wp.slide_main =
    animation_new(
    {
      subject = {x = 0, y = -theme.menu_height},
      duration = 0.2
    }
  ):add(
    "visible",
    {
      target = {y = 0}
    }
  ):add(
    "invisible",
    {
      target = {y = -theme.menu_height}
    }
  ):onUpdate(
    function(name, new_subject)
      wp.menu_display:move(1, new_subject)
    end
  )
end

function menu:show_dropdown(dropdown)
  local wp = self._private

  if wp.dropdown then
    self:hide_dropdown()
    return
  end

  wp.dropdown = dropdown
  wp.dropdown.visible = true
  animation_new(
    {
      subject = {
        x = wp.dropdown_x - theme.menu_horizontal_spacing,
        opacity = 0.0
      }
    }
  ):add(
    "visible",
    {
      target = {
        x = wp.dropdown_x,
        opacity = 1.0
      }
    }
  ):onUpdate(
    function(name, new_subject)
      if name == "visible" then
        wp.dropdown.x = new_subject.x
      end
    end
  ):startAnimation("visible", {from_start = true})
  wp.dropdown.y = wp.dropdown_y
end

function menu:hide_dropdown()
  local wp = self._private
  if not wp.dropdown then
    return
  end

  wp.dropdown.visible = false
  wp.dropdown = nil
end

function menu:show_menu(title, menu, new_size)
  local wp = self._private

  if wp.menu then
    self:hide_menu()
    return
  end

  wp.menu =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = wp.drawer_box,
    height = theme.menu_height,
    {
      widget = wibox.container.margin,
      top = theme.menu_vertical_spacing,
      bottom = theme.menu_vertical_spacing,
      left = theme.menu_horizontal_spacing,
      right = theme.menu_horizontal_spacing,
      {
        layout = wibox.layout.fixed.vertical,
        spacing = theme.menu_vertical_spacing,
        {
          layout = wibox.layout.fixed.horizontal,
          spacing = theme.menu_horizontal_spacing,
          {
            widget = wibox.container.constraint,
            strategy = "exact",
            width = config.dpi(380 - 12 - 48),
            {
              widget = wcontainer,
              {
                widget = wtext,
                bold = true,
                text = title,
                font_size = config.dpi(12)
              }
            }
          },
          {
            widget = wibox.container.constraint,
            strategy = "exact",
            width = config.dpi(48),
            height = config.dpi(48),
            {
              widget = wbutton,
              bg_normal = theme.bg_secondary,
              paddings = 0,
              callback = function()
                self:hide_menu()
              end,
              {
                widget = wibox.container.place,
                {
                  widget = wibox.container.constraint,
                  strategy = "exact",
                  width = config.dpi(16),
                  height = config.dpi(16),
                  {
                    widget = wibox.widget.imagebox,
                    image = theme.menu_close_icon
                  }
                }
              }
            }
          }
        },
        menu
      }
    }
  }
  wp.menu.point = {x = 0, y = theme.menu_height}
  if new_size then
    if type(new_size) == "string" then
      if new_size == "full-height" then
        new_size = {
          height = wp.drawer.screen.geometry.height - theme.menu_vertical_spacing * 2
        }
      end
    end
    wp.drawer.width = new_size.width or wp.drawer.width
    wp.drawer.height = new_size.height or wp.drawer.height
    wp.drawer.y = self:calculate_geo().y
  end

  wp.menu_display:insert(2, wp.menu)
  wp.slide_main:startAnimation(
    "invisible",
    {
      callback = function()
        wp.menu_animation =
          animation_new(
          {
            subject = {x = 0, y = theme.menu_height},
            duration = 0.2
          }
        ):add(
          "visible",
          {
            target = {y = 0}
          }
        ):add(
          "invisible",
          {
            target = {y = theme.menu_height}
          }
        ):onUpdate(
          function(name, new_subject)
            if #wp.menu_display:get_children() < 2 then
              return
            end
            wp.menu_display:move(2, new_subject)
          end
        ):startAnimation("visible")
      end
    }
  )
end

function menu:hide_menu()
  local wp = self._private
  if not wp.menu then
    return
  end

  wp.drawer.width = wp.drawer_box
  wp.drawer.height = theme.menu_height
  wp.drawer.y = self:calculate_geo().y

  wp.menu_animation:startAnimation(
    "invisible",
    {
      callback = function()
        wp.menu_display:remove(2)
        wp.slide_main:startAnimation("visible")
      end
    }
  )
  wp.menu = nil
end

local function new(screen)
  local ret = {_private = {}}
  gears.table.crush(ret, menu)
  local wp = ret._private
  wp.primary_screen = capi.screen.primary

  local toggle =
    wibox.widget {
    layout = wibox.layout.stack,
    {
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
    },
    {
      widget = wibox.container.place,
      valign = "bottom",
      {
        widget = layoutbox(screen, config.dpi(48))
      }
    }
  }

  if instance then
    return toggle
  end

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

  local main =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = wp.drawer_box,
    height = theme.menu_height,
    {
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
              power(
                {
                  callback = function(menu)
                    ret:show_dropdown(menu)
                  end
                }
              ).toggle
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
          info,
          {
            layout = wibox.layout.fixed.horizontal,
            spacing = theme.menu_vertical_spacing,
            compositor
          },
          volume(
            {
              width = wp.drawer_box,
              height = theme.menu_height - theme.menu_vertical_spacing * 2 - config.dpi(48),
              callback = function(title, menu)
                ret:show_menu(title, menu)
              end
            }
          ).toggle
        }
      }
    }
  }
  main.point = {
    x = 0,
    y = 0
  }

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
      layout = wibox.layout.manual,
      id = "menu_display",
      main
    }
  }

  wp.backdrop = backdrop
  wp.drawer = drawer
  wp.menu_display = drawer:get_children_by_id("menu_display")[1]
  wp.main = main
  wp.systray_instance = systray
  wp.toggle = toggle

  ret:calculate_position()
  ret:init_animation()

  backdrop:connect_signal(
    "button::release",
    function()
      capi.awesome.emit_signal("widget::drawer::hide")
    end
  )

  capi.awesome.connect_signal(
    "widget::drawer:toggle",
    function()
      local s = awful.screen.focused()
      local is_visible = backdrop.visible
      notifications.reset()
      ret:hide_dropdown()
      ret:hide_menu()
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
    "widget::drawer::hide",
    function()
      wp.animation.open:stopAnimation()
      wp.animation.close:startAnimation()
      ret:hide_dropdown()
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
