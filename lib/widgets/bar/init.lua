local capi = {
  awesome = awesome,
  screen = screen
}
local awful = require("awful")
local wibox = require("wibox")

local theme = require("lib.configuration.theme")
local menu = require("lib.widgets.menu")
local taglist = require("lib.widgets.taglist")
local tasklist = require("lib.widgets.tasklist")
local wbutton = require("lib.widgets.button")
local datetime = require("lib.widgets.bar.datetime")
local console = require("lib.helpers.console")

local bar = {visible = true, screens = {}}

local function create_new_bar(screen)
  return awful.wibar {
    position = "left",
    width = theme.bar_width,
    screen = screen,
    bg = theme.bg_normal,
    widget = {
      layout = wibox.layout.stack,
      {
        widget = wibox.container.place,
        valign = "top",
        {
          widget = wbutton,
          margin = theme.bar_padding,
          bg_normal = theme.bg_normal,
          bg_hover = theme.bg_primary,
          paddings = 0,
          padding_top = 8,
          padding_bottom = 8,
          callback = function()
            capi.awesome.emit_signal("module::launcher::show", screen)
          end,
          taglist(screen)
        }
      },
      {
        layout = wibox.layout.align.vertical,
        nil,
        {
          widget = wibox.container.place,
          tasklist(screen)
        },
        nil
      },
      {
        widget = wibox.container.place,
        valign = "bottom",
        {
          layout = wibox.layout.fixed.vertical,
          datetime,
          menu(screen)
        }
      }
    }
  }
end

capi.screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    bar.screens[s] = create_new_bar(s)
  end
)

function bar.toggle()
  bar.visible = not bar.visible
  if bar.visible then
    for _, box in pairs(bar.screens) do
      box.visible = true
    end
  else
    for _, box in pairs(bar.screens) do
      box.visible = false
    end
  end
end

capi.awesome.connect_signal(
  "widget::bar::toggle",
  function()
    bar.toggle()
  end
)
