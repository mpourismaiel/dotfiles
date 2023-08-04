-- Provides:
-- signal::weather
--      temperature (integer)
--      description (string)
--      icon_code (string)
local awful = require("awful")
local naughty = require("naughty")
local helpers = require("lib.module.helpers")
local filesystem = require("gears.filesystem")
local config = require("lib.configuration")

local config_dir = filesystem.get_configuration_dir()
-- Configuration
local key = config.openweathermap.key
local city_id = config.openweathermap.city_id
local units = config.openweathermap.weather_units

if key == "" then
  naughty.notify(
    {
      title = "Weather",
      text = "OpenWeatherMap key is not set in config/lib.json",
      preset = naughty.config.presets.critical
    }
  )
end

-- Don't update too often, because your requests might get blocked for 24 hours
local update_interval = 1200000
local temp_file = "/tmp/awesomewm-signal-weather-" .. city_id .. "-" .. units

local sun_icon = config_dir .. "/images/sun.svg"
local moon_icon = config_dir .. "/images/moon.svg"
local dcloud_icon = config_dir .. "/images/cloud.svg"
local ncloud_icon = config_dir .. "/images/cloud.svg"
local cloud_icon = config_dir .. "/images/cloud.svg"
local rain_icon = config_dir .. "/images/cloud-rain.svg"
local storm_icon = config_dir .. "/images/cloud-lightning.svg"
local snow_icon = config_dir .. "/images/cloud-snow.svg"
local mist_icon = config_dir .. "/images/cloud-drizzle.svg"
local whatever_icon = config_dir .. "/images/umbrella.svg"

local weather_icons = {
  ["01d"] = sun_icon,
  ["01n"] = moon_icon,
  ["02d"] = dcloud_icon,
  ["02n"] = ncloud_icon,
  ["03d"] = cloud_icon,
  ["03n"] = cloud_icon,
  ["04d"] = cloud_icon,
  ["04n"] = cloud_icon,
  ["09d"] = rain_icon,
  ["09n"] = rain_icon,
  ["10d"] = rain_icon,
  ["10n"] = rain_icon,
  ["11d"] = storm_icon,
  ["11n"] = storm_icon,
  ["13d"] = snow_icon,
  ["13n"] = snow_icon,
  ["40d"] = mist_icon,
  ["40n"] = mist_icon,
  ["50d"] = mist_icon,
  ["50n"] = mist_icon,
  ["_"] = whatever_icon
}

local weather_details_script =
  [[
    bash -c '
    KEY="]] ..
  key ..
    [["
    CITY="]] ..
      city_id ..
        [["
    UNITS="]] ..
          units ..
            [["

    weather=$(curl -sf "http://api.openweathermap.org/data/2.5/weather?APPID=$KEY&id=$CITY&units=$UNITS")

    if [ ! -z "$weather" ]; then
        weather_temp=$(echo "$weather" | jq ".main.temp" | cut -d "." -f 1)
        weather_name=$(echo "$weather" | jq -r ".name" | cut -d "." -f 1)
        weather_icon=$(echo "$weather" | jq -r ".weather[].icon" | head -1)
        weather_description=$(echo "$weather" | jq -r ".weather[].description" | head -1)

        echo "$weather_icon" "$weather_description"@@"$weather_temp"##"$weather_name"
    else
        echo "..."
    fi
  ']]

helpers.remote_watch(
  weather_details_script,
  update_interval,
  temp_file,
  function(stdout)
    local icon_code = string.sub(stdout, 1, 3)
    local weather_details = string.sub(stdout, 5)
    weather_details = string.gsub(weather_details, "^%s*(.-)%s*$", "%1")
    -- Replace "-0" with "0" degrees
    weather_details = string.gsub(weather_details, "%-0", "0")
    -- Capitalize first letter of the description
    weather_details = weather_details:sub(1, 1):upper() .. weather_details:sub(2)
    local description = weather_details:match("(.*)@@")
    local temperature = weather_details:match("@@(.*)##")
    local city = weather_details:match("##(.*)")
    local icon
    local color
    local weather_icon

    if icon_code == "..." then
      -- Remove temp_file to force an update the next time
      awful.spawn.with_shell("rm " .. temp_file)
      awesome.emit_signal("signal::weather", 999, "Weather unavailable", weather_icons["_"])
    else
      awesome.emit_signal("signal::weather", tonumber(temperature), description, weather_icons[icon_code], city)
    end
  end
)
