local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local lain = require("lain")
local naughty = require("naughty")

local margin = wibox.container.margin
local background = wibox.container.background
local place = wibox.container.place
local markup = lain.util.markup
local text = wibox.widget.textbox

local function icon_string(args)
  args = args or {}
  local icon = args.icon
  local size = args.size or 10
  local font_weight = args.font_weight == nil and "solid" or args.font_weight == false and "" or args.font_weight
  local font = args.font or awful.util.theme.font_icon
  if args.debug then
    naughty.notify {
      text = string.format("%s %s %s", font, font_weight, size)
    }
  end
  return markup.font(string.format("%s %s %s", font, font_weight, size), icon)
end

local function colored_icon(color)
  color = color or "#ffffff"

  return function(args, string)
    if string == true then
      return icon_string(args)
    end

    return text(markup(color, icon_string(args)))
  end
end

function font(text)
  return markup.font(awful.util.theme.font, text)
end

function pad(size)
  local str = ""
  for i = 1, size or 1 do
    str = str .. " "
  end
  return font(str)
end

local function bar_widget(w)
  return background(margin(place(w), 10, 10, 0, 0), awful.util.theme.sidebar_bg, gears.shape.rectangle)
end

function set_github_listener(fn)
  awful.widget.watch(
    string.format("sh %s/.config/polybar/scripts/inbox-github.sh", os.getenv("HOME")),
    60,
    function(widget, stdout)
      fn(string.gsub(stdout, "^%s*(.-)%s*$", "%1"))
    end
  )
end

awful.util.theme_functions.set_github_listener = set_github_listener
awful.util.theme_functions.bar_widget = bar_widget
awful.util.theme_functions.font_fn = font
awful.util.theme_functions.icon_string = icon_string
awful.util.theme_functions.colored_icon = colored_icon
awful.util.theme_functions.pad_fn = pad
