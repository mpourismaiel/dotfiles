local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local naughty = require("naughty")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local console = require("lib.helpers.console")
local animation_new = require("lib.helpers.animation-new")
local wdialog = require("lib.widgets.dialog")
local wtabs = require("lib.widgets.tabs")
local wcontainer = require("lib.widgets.menu.container")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local wtext_input = require("lib.widgets.text_input")
local woverflow = require("wibox.layout.overflow")
local color = require("lib.helpers.color")

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

local inputs = wibox.widget {layout = wibox.layout.flex.horizontal, spacing = config.dpi(5)}
local input =
  wibox.widget {
  widget = wtext_input,
  unfocus_on_client_clicked = true,
  initial = "",
  widget_template = wibox.widget {
    widget = wibox.container.background,
    shape = gears.shape.rounded_rect,
    bg = theme.bg_primary,
    {
      widget = wibox.container.margin,
      margins = config.dpi(15),
      {
        layout = wibox.layout.stack,
        {
          widget = wibox.widget.textbox,
          id = "placeholder_role",
          text = "Placeholder"
        },
        {
          widget = wibox.widget.textbox,
          id = "text_role"
        }
      }
    }
  }
}
inputs:add(input)

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

local contained_texts = wibox.widget {layout = wibox.layout.fixed.horizontal, spacing = config.dpi(5)}
for _, v in pairs({"left", "center", "right"}) do
  local text =
    wibox.widget {
    widget = wibox.container.background,
    border_width = config.dpi(2),
    border_color = "#000000",
    {
      widget = wtext,
      text = v:gsub("^%l", string.upper),
      halign = v,
      forced_width = config.dpi(50)
    }
  }
  contained_texts:add(text)
end

local notifications = wibox.widget {layout = wibox.layout.flex.vertical, spacing = config.dpi(5)}
notifications:add(
  wibox.widget {
    widget = wbutton,
    label = "Small notification",
    margin = theme.bar_padding,
    callback = function()
      naughty.notify {
        title = "Notification",
        text = "Small notification",
        preset = naughty.config.presets.normal,
        timeout = 1
      }
    end
  }
)
notifications:add(
  wibox.widget {
    widget = wbutton,
    label = "Large notification",
    margin = theme.bar_padding,
    callback = function()
      naughty.notify {
        title = "Notification",
        text = "Small notification\nMultiple lines\nWith a lot of text that exceeds the width of the notification\nAnother text\nAnd even more text",
        preset = naughty.config.presets.normal,
        timeout = 1
      }
    end
  }
)

local tabs = wibox.widget {layout = wibox.layout.fixed.vertical, spacing = config.dpi(5)}
tabs:add(
  wibox.widget {
    widget = wtabs,
    forced_width = config.dpi(400),
    forced_height = config.dpi(200),
    tabs = {
      {
        id = "devices",
        title = "Devices",
        widget = wibox.widget {
          widget = wcontainer,
          {
            widget = wtext,
            text = "devices",
            valign = "top"
          }
        }
      },
      {
        id = "applications",
        title = "Applications",
        widget = wibox.widget {
          widget = wcontainer,
          {
            widget = wtext,
            text = "applications",
            valign = "top"
          }
        }
      }
    }
  }
)

local function section(text, w)
  return wibox.widget {
    layout = wibox.layout.align.vertical,
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
  wdialog {
  name = "debug_screen",
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
      layout = woverflow.vertical,
      step = 200,
      spacing = config.dpi(20),
      {
        widget = wibox.container.margin,
        margins = config.dpi(10),
        {
          widget = wibox.widget.textbox,
          text = "Debug screen"
        }
      },
      section("Notifications", notifications),
      section(
        "Tabs",
        wibox.widget {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(400),
          height = config.dpi(200),
          tabs
        }
      ),
      section("Inputs", inputs),
      section("Buttons", buttons),
      section("Buttons with widget", buttons_with_widgets),
      section("Buttons with margin", buttons_with_margin),
      section("Buttons without padding", buttons_without_padding),
      section("Texts", texts),
      section("Texts with forced dimensions", contained_texts)
    }
  }
}

awesome.connect_signal(
  "module::debug::toggle",
  function()
    debug_screen:toggle(awful.screen.focused())
  end
)
