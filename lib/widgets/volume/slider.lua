local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local wcontainer = require("lib.widgets.menu.container")

local spawn = awful.spawn
local config_dir = gears.filesystem.get_configuration_dir()
local volume_icon = config_dir .. "/images/volume-high.svg"

local slider = {mt = {}}

function slider:update_slider()
  awful.spawn.easy_async_with_shell(
    [[bash -c "amixer -D pulse sget Master"]],
    function(stdout)
      local volume = string.match(stdout, "(%d?%d?%d)%%")
      self.volume_slider:set_value(tonumber(volume))
    end
  )
end

local function new()
  local ret = wibox.container.background()
  gears.table.crush(ret, slider)

  local w =
    wibox.widget {
    widget = wcontainer,
    {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(48),
      height = config.dpi(48),
      {
        widget = wibox.container.place,
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          height = config.dpi(24),
          {
            id = "volume_slider",
            bar_shape = gears.shape.rounded_rect,
            bar_height = config.dpi(16),
            bar_color = "#ffffff20",
            bar_active_color = "#f2f2f2EE",
            handle_color = "#ffffff",
            handle_shape = gears.shape.circle,
            handle_width = config.dpi(24),
            handle_border_color = "#00000012",
            handle_border_width = config.dpi(1),
            maximum = 100,
            widget = wibox.widget.slider
          }
        }
      }
    }
  }

  local volume_slider = w:get_children_by_id("volume_slider")[1]
  volume_slider:connect_signal(
    "property::value",
    function()
      local volume_level = volume_slider:get_value()

      spawn("amixer -D pulse sset Master " .. volume_level .. "%", false)

      -- Update volume osd
      awesome.emit_signal("widget::volume_osd", volume_level)
    end
  )

  w:buttons(
    gears.table.join(
      awful.button(
        {},
        4,
        nil,
        function()
          if volume_slider:get_value() > 100 then
            volume_slider:set_value(100)
            return
          end
          volume_slider:set_value(volume_slider:get_value() + 5)
        end
      ),
      awful.button(
        {},
        5,
        nil,
        function()
          if volume_slider:get_value() < 0 then
            volume_slider:set_value(0)
            return
          end
          volume_slider:set_value(volume_slider:get_value() - 5)
        end
      )
    )
  )

  awesome.connect_signal(
    "widget::volume",
    function()
      ret:update_slider()
    end
  )

  ret.widget = w
  ret.volume_slider = volume_slider
  ret:emit_signal("property::widget")
  ret:emit_signal("widget::layout_changed")
  ret:update_slider()

  return ret
end

function slider.mt:__call()
  return new()
end

return setmetatable(slider, slider.mt)
