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
local wbutton_state = require("lib.widgets.button.state")
local wtext = require("lib.widgets.text")
local wtabs = require("lib.widgets.tabs")
local wscrollbar = require("lib.widgets.scrollbar")
local wslider = require("lib.widgets.slider")
local woverflow = require("wibox.layout.overflow")
local wcontainer = require("lib.widgets.menu.container")
local console = require("lib.helpers.console")

local slider = {mt = {}}

function slider:reset_slider(volume)
  self:set_volume(volume)
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

local function device_widget(device, args)
  local mute =
    wibox.widget {
    widget = wbutton_state,
    paddings = config.dpi(8),
    callback = function()
      device:toggle_mute()
    end,
    widget_on = wibox.widget {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(16),
      height = config.dpi(16),
      {
        widget = wibox.widget.imagebox,
        image = theme.volume_mute_icon
      }
    },
    widget_off = wibox.widget {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(16),
      height = config.dpi(16),
      {
        widget = wibox.widget.imagebox,
        image = theme.volume_icon
      }
    }
  }

  local device_volume =
    wslider {
    forced_height = config.dpi(10),
    value = device.volume,
    maximum = 100,
    bar_height = config.dpi(6),
    handle_width = config.dpi(10),
    handle_height = config.dpi(10)
  }

  local widget =
    wibox.widget {
    layout = wibox.layout.fixed.vertical,
    id = device.id,
    forced_height = config.dpi(80),
    spacing = config.dpi(16),
    {
      layout = wibox.layout.align.horizontal,
      {
        widget = wibox.container.constraint,
        strategy = "max",
        width = args.width - theme.menu_horizontal_spacing * 4 - config.dpi(120),
        {
          widget = wtext,
          halign = "left",
          font_size = config.dpi(10),
          text = device.description
        }
      },
      nil,
      {
        widget = wibox.container.place,
        halign = "right",
        {
          layout = wibox.layout.fixed.horizontal,
          spacing = config.dpi(8),
          id = "actions",
          mute
        }
      }
    },
    device_volume
  }

  device_volume:connect_signal(
    "property::value",
    function(self, value, instant)
      device:set_volume(value)
    end
  )

  device:connect_signal(
    "updated",
    function()
      device_volume:set_value(device.volume)

      if device.mute == true then
        mute:turn_on()
      else
        mute:turn_off()
      end
    end
  )

  return widget
end

local function attach_radio_group(group)
  local wp = group._private
  if not wp then
    group._private = {}
    wp = group._private
  end
  wp.options = wp.options or {values = {}}
  return wp
end

local function radio_button(group, device_widget, id, callback)
  local wp = group._private

  local action =
    wibox.widget {
    widget = wbutton_state,
    paddings = config.dpi(8),
    callback = function(action)
      callback(id)

      for _, v in ipairs(wp.options.values) do
        if v.id ~= id then
          v.widget:set_disabled(false)
          v.widget:turn_off()
        end
      end

      action:set_disabled(true)
      action:turn_on()
      return false
    end,
    widget_on = wibox.widget {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(16),
      height = config.dpi(16),
      {
        widget = wibox.widget.imagebox,
        image = theme.button_check_icon
      }
    },
    widget_off = wibox.widget {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(16),
      height = config.dpi(16),
      {
        widget = wibox.widget.textbox,
        text = ""
      }
    }
  }
  device_widget:get_children_by_id("actions")[1]:add(action)
  table.insert(wp.options.values, {widget = action, id = id})
end

local function sinks(args)
  local group =
    wibox.widget {
    layout = woverflow.vertical,
    spacing = config.dpi(12),
    scrollbar_widget = wscrollbar,
    scrollbar_width = config.dpi(10),
    step = 50
  }
  local wp = attach_radio_group(group)

  audio_daemon:connect_signal(
    "sinks::added",
    function(self, sink)
      local w = device_widget(sink, args)
      radio_button(
        group,
        w,
        sink.id,
        function(id)
          audio_daemon:set_default_sink(id)
        end
      )

      group:add(w)
    end
  )

  audio_daemon:connect_signal(
    "sinks::default",
    function(self, sink)
      for _, w in ipairs(wp.options.values) do
        if w.id == sink.id then
          w.widget:set_disabled(true)
          w.widget:turn_on()
        else
          w.widget:set_disabled(false)
          w.widget:turn_off()
        end
      end
    end
  )

  audio_daemon:connect_signal(
    "sinks::removed",
    function(self, sink)
      for _, w in ipairs(group:get_children()) do
        if w.id == sink.id then
          group:remove(w)
          return
        end
      end
    end
  )

  return group
end

local function sources(args)
  local group =
    wibox.widget {
    layout = woverflow.vertical,
    spacing = config.dpi(12),
    scrollbar_widget = wscrollbar,
    scrollbar_width = config.dpi(10),
    step = 50
  }
  local wp = attach_radio_group(group)

  audio_daemon:connect_signal(
    "sources::added",
    function(self, source)
      local w = device_widget(source, args)
      radio_button(
        group,
        w,
        source.id,
        function(id)
          audio_daemon:set_default_source(id)
        end
      )

      group:add(w)
    end
  )

  audio_daemon:connect_signal(
    "sources::default",
    function(self, source)
      for _, w in ipairs(wp.options.values) do
        if w.id == source.id then
          w.widget:set_disabled(true)
          w.widget:turn_on()
        else
          w.widget:set_disabled(false)
          w.widget:turn_off()
        end
      end
    end
  )

  audio_daemon:connect_signal(
    "sources::removed",
    function(self, source)
      for _, w in ipairs(group:get_children()) do
        if w.id == source.id then
          group:remove(w)
          return
        end
      end
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
      font_size = theme.font_size_large,
      text = title
    },
    {
      widget = wibox.container.constraint,
      strategy = "max",
      height = config.dpi(180),
      widget
    }
  }
end

local function devices(args)
  return wibox.widget {
    widget = wcontainer,
    {
      layout = wibox.layout.fixed.vertical,
      spacing = config.dpi(20),
      section("Outputs", sinks(args)),
      section("Inputs", sources(args))
    }
  }
end

local function applications(args)
  return wibox.widget {
    widget = wcontainer,
    {
      layout = wibox.layout.fixed.vertical,
      spacing = config.dpi(20)
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
          widget = devices(args)
        },
        {
          id = "applications",
          title = "Applications",
          widget = applications(args)
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
      audio_daemon:get_default_sink():set_volume(volume_level)

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

  wp.menu = menu
  wp.volume_slider = volume_slider
  wp.volume_text = toggle:get_children_by_id("volume_text")[1]

  ret.toggle = toggle
  audio_daemon:connect_signal(
    "sinks::default",
    function(_, sink)
      ret:reset_slider(sink.volume)
    end
  )

  return ret
end

function slider.mt:__call(...)
  return new(...)
end

return setmetatable(slider, slider.mt)
