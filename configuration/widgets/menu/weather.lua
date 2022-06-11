local wibox = require("wibox")
local config = require("configuration.config")

local weather = {mt = {}}

function weather.new()
  local w =
    wibox.widget.base.make_widget_from_value(
    wibox.widget {
      widget = wibox.container.constraint,
      height = config.dpi(80),
      strategy = "exact",
      {
        layout = wibox.layout.align.horizontal,
        {
          widget = wibox.container.margin,
          right = config.dpi(16),
          {
            widget = wibox.container.place,
            valign = "middle",
            {
              layout = wibox.layout.fixed.vertical,
              spacing = config.dpi(8),
              {
                widget = wibox.container.place,
                valign = "middle",
                halign = "middle",
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
                widget = wibox.container.place,
                halign = "middle",
                {
                  widget = wibox.widget.textbox,
                  id = "city"
                }
              }
            }
          }
        },
        nil,
        {
          widget = wibox.container.place,
          halign = "right",
          valign = "middle",
          {
            layout = wibox.layout.fixed.vertical,
            {
              widget = wibox.container.place,
              halign = "right",
              {
                id = "temp",
                widget = wibox.widget.textbox,
                markup = ""
              }
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

  local icon = w:get_children_by_id("icon")[1]
  local temp = w:get_children_by_id("temp")[1]
  local desc = w:get_children_by_id("desc")[1]
  local city = w:get_children_by_id("city")[1]
  awesome.connect_signal(
    "signal::weather",
    function(temperature, description, icon_widget, city_name)
      local weather_temp_symbol
      if config.openweathermap.weather_units == "metric" then
        weather_temp_symbol = "°C"
      elseif config.openweathermap.weather_units == "imperial" then
        weather_temp_symbol = "°F"
      end

      icon.image = icon_widget
      temp.markup = "<b><span color='#ffffff' font_size='24pt'>" .. temperature .. weather_temp_symbol .. "</span></b>"
      desc.markup = "<span color='#ffffff' font_size='14pt'>" .. description .. "</span>"
      city.markup = "<span color='#ffffffcc' font_size='12pt'>" .. city_name .. "</span>"
    end
  )

  return w
end

function weather.mt:__call(...)
  return weather.new(...)
end

return setmetatable(weather, weather.mt)
