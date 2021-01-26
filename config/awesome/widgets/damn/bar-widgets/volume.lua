local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local naughty = require("naughty")
local lain = require("lain")
local lain_helpers = require("lain.helpers")
local shell = require("awful.util").shell
local wibox = require("wibox")
local string = string

local markup = lain.util.markup

local volume = {mt = {}}
local createPopup = require("widgets.damn.popup.popup")

local popup = createPopup("#fbc02d")

local function getIcon(volume_now)
  local vlevel = ""
  if volume_now.status == "on" then
    local level = tonumber(volume_now.level)

    if level <= 35 then
      vlevel = ""
    elseif level <= 65 then
      vlevel = ""
    elseif level <= 100 then
      vlevel = ""
    end
  else
    vlevel = ""
  end
  return vlevel
end

function volume.new()
  local widget =
    lain.widget.alsa(
    {
      settings = function()
        local vlevel = getIcon(volume_now)
        widget:set_markup(
          markup(
            awful.util.theme.fg_normal,
            awful.util.theme_functions.icon_string({icon = vlevel, size = 12, font_weight = false})
          )
        )
      end
    }
  )

  local bar_controller = {}
  local height = 50

  bar_controller.cmd = "amixer"
  bar_controller.channel = "Master"

  local format_cmd = string.format("%s get %s", bar_controller.cmd, bar_controller.channel)

  bar_controller.last = {notSet = true}

  function bar_controller.update()
    lain_helpers.async(
      format_cmd,
      function(mixer)
        local l, s = string.match(mixer, "([%d]+)%%.*%[([%l]*)")
        if bar_controller.last.level ~= l or bar_controller.last.status ~= s then
          local volume_now = {level = l, status = s}
          local vlevel = getIcon(volume_now)

          popup.update(l, awful.util.theme_functions.icon_string({icon = vlevel, size = 14, font_weight = false}))

          if volume ~= l then
            popup.updateValue(l)
          end

          if bar_controller.notSet == false then
            popup.show()
          else
            bar_controller.notSet = false
          end

          bar_controller.last = volume_now
        end
      end
    )
  end

  lain_helpers.newtimer(
    string.format("alsa-%s-%s", bar_controller.cmd, bar_controller.channel),
    5,
    bar_controller.update
  )

  local volume = awful.util.theme_functions.bar_widget(widget.widget)
  volume:buttons(
    {
      awful.button(
        {},
        4,
        function()
          os.execute(string.format("%s set %s 5%%+", widget.cmd, widget.channel))
          widget.update()
          bar_controller.update()
        end
      ),
      awful.button(
        {},
        5,
        function()
          os.execute(string.format("%s set %s 5%%-", widget.cmd, widget.channel))
          widget.update()
          bar_controller.update()
        end
      ),
      awful.button(
        {},
        1,
        function()
          os.execute(string.format("%s set %s toggle", widget.cmd, widget.togglechannel or widget.channel))
          widget.update()
          bar_controller.update()
        end
      )
    }
  )

  if (awful.util.volume == nil) then
    awful.util.volume = widget
    awful.util.volume_indicator = bar_controller
  end

  return volume
end

function volume.mt:__call(...)
  return volume.new(...)
end

return setmetatable(volume, volume.mt)
