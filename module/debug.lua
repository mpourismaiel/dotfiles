local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local naughty = require("naughty")
local config = require("configuration.config")
local wbutton = require("configuration.widgets.button")
local theme = require("configuration.config.theme")

local buttons = wibox.widget {layout = wibox.layout.flex.horizontal, spacing = config.dpi(5)}
for _, v in pairs({"left", "center", "right"}) do
  local button =
    wibox.widget {
    widget = wbutton,
    label = v:gsub("^%l", string.upper),
    halign = v,
    callback = function()
      naughty.notify {
        title = "Button",
        text = "Button pressed\nProperty: halign = " .. v,
        preset = naughty.config.presets.normal,
        timeout = 1
      }
    end
  }
  buttons:add(button)
end

local function section(text, w)
  return wibox.widget {
    layout = wibox.layout.fixed.vertical,
    spacing = config.dpi(5),
    {
      widget = wibox.container.margin,
      margins = config.dpi(10),
      {
        widget = wibox.widget.textbox,
        markup = "<b>" .. text .. "</b>"
      }
    },
    w
  }
end

local debug_screen =
  wibox {
  ontop = true,
  visible = false,
  width = config.dpi(400),
  height = config.dpi(600),
  shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_normal)
  end,
  type = "utility",
  widget = {
    widget = wibox.container.margin,
    margins = config.dpi(10),
    {
      layout = wibox.layout.fixed.vertical,
      spacing = config.dpi(20),
      {
        widget = wibox.container.margin,
        margins = config.dpi(10),
        {
          widget = wibox.widget.textbox,
          text = "Debug screen"
        }
      },
      section("Buttons", buttons)
    }
  }
}

local geo =
  awful.placement.centered(
  debug_screen,
  {
    honor_workarea = true,
    pretend = true
  }
)
debug_screen.x = geo.x
debug_screen.y = geo.y

awesome.connect_signal(
  "module::debug::toggle",
  function()
    debug_screen.visible = not debug_screen.visible
    debug_screen.screen = awful.screen.focused()
  end
)
