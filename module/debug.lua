local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local naughty = require("naughty")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local wbutton = require("configuration.widgets.button")
local wtext = require("configuration.widgets.text")
local color = require("helpers.color")

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

local buttons_with_margin =
  wibox.widget {
  widget = wibox.container.background,
  bg = color.helpers.lighten(color.hex2rgba(theme.bg_normal), 0.1),
  {
    layout = wibox.layout.flex.horizontal,
    spacing = config.dpi(5),
    id = "list"
  }
}
for _, v in pairs({"left", "center", "right"}) do
  local button =
    wibox.widget {
    widget = wbutton,
    label = v:gsub("^%l", string.upper),
    halign = v,
    margin = theme.bar_padding,
    callback = function()
      naughty.notify {
        title = "Button",
        text = "Button pressed\nProperty: halign = " .. v,
        preset = naughty.config.presets.normal,
        timeout = 1
      }
    end
  }
  buttons_with_margin:get_children_by_id("list")[1]:add(button)
end

local buttons_with_widgets = wibox.widget {layout = wibox.layout.flex.horizontal, spacing = config.dpi(5)}
for _, v in pairs({"left", "center", "right"}) do
  local button =
    wibox.widget {
    widget = wbutton,
    halign = v,
    padding = theme.bar_padding,
    callback = function()
      naughty.notify {
        title = "Button",
        text = "Button pressed\nProperty: halign = " .. v,
        preset = naughty.config.presets.normal,
        timeout = 1
      }
    end,
    {
      widget = wibox.widget.textbox,
      text = v:gsub("^%l", string.upper)
    }
  }
  buttons_with_widgets:add(button)
end

local buttons_without_padding = wibox.widget {layout = wibox.layout.flex.horizontal, spacing = config.dpi(5)}
for _, v in pairs({"left", "center", "right"}) do
  local button =
    wibox.widget {
    widget = wbutton,
    label = v:gsub("^%l", string.upper),
    halign = v,
    paddings = 0,
    callback = function()
      naughty.notify {
        title = "Button",
        text = "Button pressed\nProperty: halign = " .. v,
        preset = naughty.config.presets.normal,
        timeout = 1
      }
    end
  }
  buttons_without_padding:add(button)
end

local texts = wibox.widget {layout = wibox.layout.flex.horizontal, spacing = config.dpi(5)}
for _, v in pairs({"left", "center", "right"}) do
  local text =
    wibox.widget {
    widget = wtext,
    text = v:gsub("^%l", string.upper),
    halign = v
  }
  texts:add(text)
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
      section("Buttons", buttons),
      section("Buttons with widget", buttons_with_widgets),
      section("Buttons with margin", buttons_with_margin),
      section("Buttons without padding", buttons_without_padding),
      section("Texts", texts)
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
