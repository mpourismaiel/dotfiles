local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local dpi = require("beautiful").xresources.apply_dpi
local createAnimObject = require("utils.animation").createAnimObject
local lain = require("lain")
local markup = lain.util.markup

local apply_borders = require("lib.borders")

local createPopup = function(color)
  local icon =
    wibox.widget {
    font = "Fira Mono 28",
    align = "center",
    valign = "center",
    widget = wibox.widget.textbox
  }

  local progressbar =
    wibox.widget {
    value = 1,
    color = color,
    background_color = "#2f3240",
    forced_width = dpi(120),
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, dpi(6))
    end,
    forced_height = dpi(5),
    widget = wibox.widget.progressbar
  }

  local progressbar_container =
    wibox.widget {
    progressbar,
    direction = "east",
    layout = wibox.container.rotate
  }

  local widget =
    apply_borders(
    {
      {
        {
          nil,
          progressbar_container,
          nil,
          expand = "none",
          layout = wibox.layout.align.horizontal
        },
        icon,
        spacing = dpi(8),
        layout = wibox.layout.fixed.vertical
      },
      top = dpi(16),
      left = dpi(8),
      right = dpi(8),
      widget = wibox.container.margin
    },
    30,
    176,
    6
  )

  local popup =
    awful.popup {
    widget = widget,
    y = awful.screen.focused().geometry.height / 2 - 72,
    x = awful.screen.focused().geometry.width,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, dpi(6))
    end,
    bg = "#1C1E26",
    ontop = true,
    visible = false
  }

  local timer_die =
    gears.timer {
    autostart = true,
    single_shot = true,
    timeout = 3,
    callback = function()
      popup.x = awful.screen.focused().geometry.width
      popup.visible = false
      -- Prevent infinite timers events on errors.
      if timer_die.started then
        timer_die:stop()
      end
    end
  }

  popup:connect_signal(
    "button::press",
    function()
      popup.visible = false
      if timer_die.started then
        timer_die:stop()
      end
    end
  )

  popup.show = function()
    if timer_die.started then
      timer_die:again()
    else
      timer_die:start()
    end

    if popup.visible ~= true then
      popup.visible = true
      createAnimObject(1, popup, {x = awful.screen.focused().geometry.width - 48}, "outCubic")
    end
  end

  popup.update = function(value, image)
    icon.markup = markup("#ffffff", image)
    progressbar.value = value / 100
  end

  popup.updateValue = function(value)
    if value ~= nil then
      progressbar.value = (value / 100)
    end
  end

  return popup
end

return createPopup
