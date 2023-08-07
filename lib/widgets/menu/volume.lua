local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local audio_daemon = require("lib.daemons.hardware.audio")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local wtabs = require("lib.widgets.tabs")
local wscrollbar = require("lib.widgets.scrollbar")
local woverflow = require("wibox.layout.overflow")
local wcontainer = require("lib.widgets.menu.container")
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

local function device_widget(device)
  local name =
    wibox.widget {
    widget = wtext,
    halign = "left",
    font_size = config.dpi(10),
    text = device.description
  }

  local mute =
    wibox.widget {
    widget = wbutton,
    callback = function()
      device:toggle_mute()
    end,
    {
      widget = wtext,
      font_size = config.dpi(8),
      text = "Mute"
    }
  }

  local slider =
    wibox.widget {
    widget = wibox.widget.slider,
    bar_shape = gears.shape.rounded_rect,
    bar_height = config.dpi(8),
    bar_color = "#ffffff20",
    bar_active_color = "#f2f2f2EE",
    handle_color = "#ffffff",
    handle_shape = gears.shape.circle,
    handle_width = config.dpi(12),
    handle_border_color = "#00000012",
    handle_border_width = config.dpi(1),
    maximum = 100
  }

  local widget =
    wibox.widget {
    layout = wibox.layout.fixed.vertical,
    forced_height = config.dpi(80),
    spacing = config.dpi(15),
    {
      layout = wibox.layout.align.horizontal,
      name,
      nil,
      mute
    },
    {
      widget = wibox.container.margin,
      margins = {right = config.dpi(15)},
      slider
    }
  }

  slider:connect_signal(
    "property::value",
    function(self, value, instant)
      device:set_volume(value)
    end
  )

  device:connect_signal(
    "updated",
    function()
      slider:set_value(device.volume)

      -- if device.mute == true then
      --   mute:turn_on()
      -- else
      --   mute:turn_off()
      -- end
    end
  )

  return widget
end

local function sinks()
  local group =
    wibox.widget {
    layout = woverflow.vertical,
    spacing = config.dpi(8),
    scrollbar_widget = wscrollbar,
    scrollbar_width = config.dpi(10),
    step = 50
  }

  local wp = group._private
  wp.options = {}

  audio_daemon:connect_signal(
    "sinks::added",
    function(self, sink)
      local w =
        wibox.widget {
        widget = device_widget(sink),
        id = sink.id
      }

      group:add(w)
      table.insert(wp.options, w)
    end
  )

  audio_daemon:connect_signal(
    "sinks::default",
    function(self, sink)
    end
  )

  audio_daemon:connect_signal(
    "sinks::removed",
    function(self, sink)
    end
  )

  return group
end

local function section(title, widget)
  return wibox.widget {
    layout = wibox.layout.fixed.vertical,
    spacing = config.dpi(12),
    {
      widget = wtext,
      bold = true,
      text = title
    },
    widget
  }
end

local function devices()
  return wibox.widget {
    widget = wcontainer,
    {
      layout = wibox.layout.fixed.vertical,
      spacing = config.dpi(16),
      section("Sinks", sinks()),
      section("Sources", wibox.widget.textbox("sources"))
    }
  }
end

local function new(args)
  args = args or {}
  args.width = args.width or config.dpi(400)
  args.height = args.height or config.dpi(400)

  local ret = {_private = {}}
  gears.table.crush(ret, slider)

  local wp = ret._private
  wp.callback = args.callback or nil

  local toggle =
    wibox.widget {
    widget = wibox.container.background,
    bg = theme.bg_secondary,
    shape = function(cr, w, h)
      gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_large)
    end,
    {
      layout = wibox.layout.fixed.horizontal,
      spacing = config.dpi(12),
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(60),
        height = config.dpi(60),
        {
          widget = wbutton,
          bg_normal = theme.bg_secondary,
          rounded = theme.rounded_rect_large,
          callback = function()
            if not wp.callback then
              return
            end
            wp.callback("Volume Manager", wp.menu)
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
      },
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        height = config.dpi(60),
        {
          widget = wibox.container.margin,
          right = config.dpi(12),
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
  }

  local menu =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = args.width,
    height = args.height,
    {
      widget = wtabs,
      forced_width = args.width,
      forced_height = args.height,
      tabs = {
        {
          id = "devices",
          title = "Devices",
          widget = devices()
        },
        {
          id = "applications",
          title = "Applications",
          widget = wibox.widget {widget = wtext, text = "applications"}
        }
      }
    }
  }

  local volume_slider = toggle:get_children_by_id("volume_slider")[1]
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
