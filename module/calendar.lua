local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.config")
local theme = require("lib.config.theme")
local wdate = require("lib.widgets.calendar.date")
local wcalendar = require("lib.widgets.calendar")

local instance
local calendar = {mt = {}}

function calendar:calculate_position()
  local wp = self._private
  local theme_position = theme.calendar_position
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
      bottom = theme.calendar_margin_bottom,
      left = theme.bar_width + theme.calendar_margin_left
    }
  end

  wp.position = position
end

function calendar:set_screen_dimensions(screen)
  local wp = self._private

  wp.popup.screen = screen
  wp.backdrop.screen = screen

  wp.backdrop.x = screen.geometry.x
  wp.backdrop.y = screen.geometry.y
  wp.backdrop.width = screen.geometry.width
  wp.backdrop.height = screen.geometry.height

  local geo =
    wp.position.fn(
    wp.popup,
    {
      margins = wp.position.margins,
      pretend = true
    }
  )

  local offset_x = 0
  wp.popup.x = geo.x + offset_x
  wp.popup.y = geo.y
end

function calendar:set_screen(screen)
  local wp = self._private
  wp.screen = screen
  wp.popup.screen = screen
end

function calendar:show(screen)
  local wp = self._private
  wp.screen = screen
  self:set_screen_dimensions(wp.screen)
  wp.backdrop.visible = true
  wp.popup.visible = true
  wp.is_visible = true
end

function calendar:hide()
  local wp = self._private
  wp.backdrop.visible = false
  wp.popup.visible = false
  wp.is_visible = false
end

local function new()
  if instance then
    return instance
  end

  local ret = {_private = {}}
  gears.table.crush(ret, calendar)

  local wp = ret._private

  local backdrop =
    wibox {
    ontop = true,
    bg = "#ffffff00",
    type = "utility"
  }
  backdrop:connect_signal(
    "button::release",
    function()
      ret:hide()
    end
  )
  wp.backdrop = backdrop

  local popup =
    wibox {
    ontop = true,
    visible = false,
    type = "utility",
    width = theme.calendar_width,
    height = theme.calendar_height,
    bg = theme.bg_normal,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_large)
    end,
    widget = {
      widget = wibox.container.margin,
      top = theme.calendar_vertical_spacing,
      bottom = theme.calendar_vertical_spacing,
      left = theme.calendar_horizontal_spacing,
      right = theme.calendar_horizontal_spacing,
      {
        layout = wibox.layout.fixed.horizontal,
        spacing = config.dpi(16),
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = theme.calendar_widget_width,
          {
            layout = wibox.layout.fixed.vertical,
            spacing = config.dpi(16),
            wdate,
            {
              widget = wcalendar,
              id = "calendar_role"
            }
          }
        },
        -- separator
        {
          widget = wibox.container.background,
          bg = theme.bg_primary,
          forced_width = config.dpi(1)
        }
      }
    }
  }
  wp.popup = popup

  ret:calculate_position()

  capi.awesome.connect_signal(
    "module::calendar::toggle",
    function(screen)
      if wp.is_visible then
        ret:hide()
      else
        ret:show(screen)
      end
    end
  )

  capi.awesome.connect_signal(
    "module::calendar::today",
    function()
      popup:get_children_by_id("calendar_role")[1]:set_date_current()
    end
  )

  instance = ret
  return ret
end

function calendar.mt:__call(...)
  return new(...)
end

return setmetatable(calendar, calendar.mt)
