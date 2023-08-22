local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local osd = require("lib.widgets.osd")
local audio_daemon = require("lib.daemons.hardware.audio")

local spawn = awful.spawn

local icon =
  wibox.widget {
  widget = wibox.container.place,
  valign = "center",
  halign = "center",
  {
    widget = wibox.container.constraint,
    width = config.dpi(24),
    height = config.dpi(24),
    strategy = "exact",
    {
      image = theme.volume_icon,
      id = "image_role",
      resize = true,
      widget = wibox.widget.imagebox
    }
  }
}

local slider =
  wibox.widget.base.make_widget_from_value(
  wibox.widget {
    nil,
    {
      widget = wibox.container.rotate,
      direction = "east",
      {
        id = "volume_slider",
        bar_shape = gears.shape.rounded_rect,
        bar_height = config.dpi(4),
        bar_color = "#ffffff20",
        bar_active_color = "#f2f2f2EE",
        handle_color = "#ffffff",
        handle_shape = gears.shape.circle,
        handle_width = config.dpi(16),
        handle_border_color = "#00000012",
        handle_border_width = config.dpi(1),
        maximum = 100,
        widget = wibox.widget.slider
      }
    },
    nil,
    expand = "none",
    forced_height = config.osd_height,
    layout = wibox.layout.align.vertical
  }
)

local volume_slider = slider:get_children_by_id("volume_slider")[1]

volume_slider:connect_signal(
  "property::value",
  function()
    local volume_level = volume_slider:get_value()

    local image = theme.volume_mute_icon
    if volume_level == 0 then
      image = theme.volume_mute_icon
    elseif volume_level > 0 and volume_level < 30 then
      image = theme.volume_low_icon
    elseif volume_level >= 30 and volume_level < 70 then
      image = theme.volume_medium_icon
    elseif volume_level >= 70 then
      image = theme.volume_high_icon
    end
    icon:get_children_by_id("image_role")[1].image = image
  end
)

local update_slider = function(volume)
  volume_slider:set_value(tonumber(volume))
end

local volume_osd =
  osd(
  wibox.widget {
    widget = wibox.container.background,
    background = "#ff0000",
    {
      widget = wibox.container.margin,
      top = config.dpi(16),
      bottom = config.dpi(16),
      {
        layout = wibox.layout.fixed.vertical,
        spacing = config.dpi(20),
        icon,
        slider
      }
    }
  }
)

local timer = nil
audio_daemon:connect_signal(
  "sinks::default",
  function(_, sink)
    volume_osd:show()
    if timer ~= nil then
      timer:stop()
    end

    update_slider(sink.volume)
    timer =
      gears.timer.start_new(
      3,
      function()
        volume_osd:hide()
      end
    )
  end
)

return volume_osd
