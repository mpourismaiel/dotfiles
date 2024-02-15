local capi = {
  awesome = awesome,
  screen = screen,
  tag = tag,
  client = client
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
local debounce = require("lib.helpers.debounce")

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

function bar.handle_fullscreen()
  local screen = awful.screen.focused()
  if not screen then
    return
  end

  local bar = bar.screens[screen]
  if not bar then
    return
  end

  local tag = screen.selected_tag
  if not bar then
    return
  end

  local focused_client = capi.client.focus

  if focused_client then
    if focused_client.fullscreen then
      bar.visible = false
    else
      local tag_has_fullscreen = false
      for _, c in pairs(tag:clients()) do
        if c.fullscreen and not c.minimized then
          tag_has_fullscreen = true
          break
        end
      end

      if tag_has_fullscreen then
        bar.visible = false
      else
        bar.visible = true
      end
    end
  else
    bar.visible = true
  end
end

local adjust_visibility = debounce(bar.handle_fullscreen, 0.1)

capi.tag.connect_signal("property::selected", adjust_visibility)
capi.tag.connect_signal("property::layout", adjust_visibility)
capi.tag.connect_signal("tagged", adjust_visibility)
capi.tag.connect_signal("untagged", adjust_visibility)
capi.tag.connect_signal("property::master_count", adjust_visibility)
capi.client.connect_signal("property::minimized", adjust_visibility)
capi.client.connect_signal("property::fullscreen", adjust_visibility)
capi.client.connect_signal("focus", adjust_visibility)
capi.client.connect_signal("unfocus", adjust_visibility)

capi.awesome.connect_signal(
  "widget::bar::toggle",
  function()
    bar.toggle()
  end
)
