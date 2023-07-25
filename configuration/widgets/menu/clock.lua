local wibox = require("wibox")
local config = require("configuration.config")
local theme = require("configuration.config.theme")

local clock = {mt = {}}

local function new()
  local weather =
    wibox.widget.base.make_widget_from_value(
    {
      layout = wibox.layout.fixed.horizontal,
      {
        widget = wibox.container.place,
        valign = "middle",
        {
          widget = wibox.container.constraint,
          width = config.dpi(40),
          height = config.dpi(40),
          strategy = "exact",
          {
            id = "icon",
            widget = wibox.widget.imagebox
          }
        }
      },
      {
        widget = wibox.container.margin,
        left = config.dpi(12),
        {
          widget = wibox.container.place,
          valign = "middle",
          {
            layout = wibox.layout.fixed.vertical,
            {
              id = "temp",
              widget = wibox.widget.textbox,
              markup = ""
            },
            {
              id = "desc",
              widget = wibox.widget.textbox,
              markup = ""
            }
          }
        }
      }
    }
  )

  weather.visible = false

  local icon = weather:get_children_by_id("icon")[1]
  local temp = weather:get_children_by_id("temp")[1]
  local desc = weather:get_children_by_id("desc")[1]
  awesome.connect_signal(
    "signal::weather",
    function(temperature, description, icon_widget)
      local weather_temp_symbol
      if config.openweathermap.weather_units == "metric" then
        weather_temp_symbol = "°C"
      elseif config.openweathermap.weather_units == "imperial" then
        weather_temp_symbol = "°F"
      end

      if temperature and temperature ~= 999 then
        weather.visible = true

        icon.image = icon_widget
        temp.markup =
          "<b><span color='" ..
          theme.fg_primary .. "' font_size='16pt'>" .. temperature .. weather_temp_symbol .. "</span></b>"
        desc.markup = "<span color='" .. theme.fg_primary .. "' font_size='12pt'>" .. description .. "</span>"
      else
        weather.visible = false
      end
    end
  )

  return wibox.widget {
    layout = wibox.layout.fixed.vertical,
    {
      layout = wibox.layout.align.horizontal,
      {
        widget = wibox.widget.textclock,
        format = "<b><span font_size='12pt' color='" .. theme.fg_normal .. "'>%A</span></b>"
      },
      nil,
      {
        widget = wibox.widget.textclock,
        format = "<b><span font_size='12pt' color='" .. theme.fg_normal .. "'>%F</span></b>"
      }
    },
    {
      widget = wibox.container.margin,
      top = config.dpi(4),
      {
        layout = wibox.layout.align.horizontal,
        weather,
        nil,
        {
          widget = wibox.widget.textclock,
          format = "<span font_size='40pt' color='" .. theme.fg_primary .. "'>%H:%M</span>"
        }
      }
    }
  }
end

function clock.mt:__call()
  return new()
end

return setmetatable(clock, clock.mt)
