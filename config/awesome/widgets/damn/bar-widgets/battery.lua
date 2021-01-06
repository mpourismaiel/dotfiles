local awful = require("awful")
local lain = require("lain")

local battery = {mt = {}}

function battery.new()
  local widget = awful.util.theme_functions.bar_widget(
    lain.widget.bat(
      {
        notify = "off",
        settings = function()
          bat_icon = ""

          -- bat_now.ac_status == 1 means is charging
          if bat_now.ac_status == 1 then
            bat_icon = ""
          else
            if bat_now.perc <= 25 then
              bat_icon = ""
            elseif bat_now.perc <= 50 then
              bat_icon = ""
            elseif bat_now.perc <= 75 then
              bat_icon = ""
            elseif bat_now.perc <= 100 then
              bat_icon = ""
            end
          end
          widget:set_markup(awful.util.theme_functions.icon_string({icon = bat_icon, size = 12, font_weight = false}))
        end
      }
    ).widget
  )

  return widget
end

function battery.mt:__call(...)
  return battery.new(...)
end

return setmetatable(battery, battery.mt)
