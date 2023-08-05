local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local console = require("lib.helpers.console")

local slider = {mt = {}}

function slider:reset_slider()
  local wp = self._private
  awful.spawn.easy_async_with_shell(
    [[bash -c "amixer -D pulse sget Master"]],
    function(stdout)
      local volume = string.match(stdout, "(%d?%d?%d)%%")
      self:set_volume(volume)
    end
  )
end

function slider:set_volume(volume)
  local wp = self._private
  self:set_volume_text(volume)
  wp.volume_slider:set_value(tonumber(volume))
end

function slider:set_volume_text(volume)
  local wp = self._private
  wp.volume_text:set_text(volume)
end

local function new(args)
  local ret = {_private = {}}
  gears.table.crush(ret, slider)

  local wp = ret._private
  wp.callback = args.callback or nil

  local toggle =
    wibox.widget {
    widget = wibox.container.background,
    {
      widget = wbutton,
      bg_normal = theme.bg_secondary,
      rounded = theme.rounded_rect_large,
      callback = function()
        if not wp.callback then
          return
        end
        wp.callback(wp.menu)
      end,
      paddings = 0,
      {
        layout = wibox.layout.fixed.vertical,
        spacing = config.dpi(8),
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(16),
          height = config.dpi(16),
          {
            widget = wibox.container.place,
            {
              widget = wibox.widget.imagebox,
              image = theme.volume_icon
            }
          }
        },
        {
          widget = wibox.container.place,
          {
            widget = wtext,
            text = "100",
            id = "volume_text"
          }
        }
      }
    }
  }

  local menu =
    wibox {
    ontop = true,
    visible = false,
    type = "utility",
    width = config.dpi(60),
    height = config.dpi(200),
    bg = theme.bg_normal,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_large)
    end,
    widget = {
      widget = wibox.container.margin,
      top = theme.menu_vertical_spacing,
      bottom = theme.menu_vertical_spacing,
      {
        widget = wibox.container.rotate,
        direction = "east",
        {
          widget = wibox.container.place,
          {
            id = "volume_slider",
            bar_shape = gears.shape.rounded_rect,
            bar_height = config.dpi(8),
            bar_color = "#ffffff20",
            bar_active_color = "#f2f2f2EE",
            handle_color = "#ffffff",
            handle_shape = gears.shape.circle,
            handle_width = config.dpi(12),
            handle_border_color = "#00000012",
            handle_border_width = config.dpi(1),
            maximum = 100,
            widget = wibox.widget.slider
          }
        }
      }
    }
  }

  local volume_slider = menu:get_children_by_id("volume_slider")[1]
  volume_slider:connect_signal(
    "property::value",
    function()
      local volume_level = volume_slider:get_value()
      ret:set_volume_text(volume_level)
      awful.spawn("amixer -D pulse sset Master " .. volume_level .. "%", false)

      capi.awesome.emit_signal("widget::volume_osd", volume_level)
    end
  )

  local scroll_handler_buttons =
    gears.table.join(
    awful.button(
      {},
      4,
      nil,
      function()
        if volume_slider:get_value() >= 100 then
          ret:set_volume(100)
          return
        end
        ret:set_volume(volume_slider:get_value() + 5)
      end
    ),
    awful.button(
      {},
      5,
      nil,
      function()
        if volume_slider:get_value() <= 0 then
          ret:set_volume(0)
          return
        end
        ret:set_volume(volume_slider:get_value() - 5)
      end
    )
  )

  toggle:buttons(scroll_handler_buttons)
  menu:buttons(scroll_handler_buttons)

  wp.menu = menu
  wp.volume_slider = volume_slider
  wp.volume_text = toggle:get_children_by_id("volume_text")[1]

  ret.toggle = toggle
  ret:reset_slider()

  capi.awesome.connect_signal(
    "widget::volume",
    function()
      ret:reset_slider()
    end
  )

  return ret
end

function slider.mt:__call(...)
  return new(...)
end

return setmetatable(slider, slider.mt)
