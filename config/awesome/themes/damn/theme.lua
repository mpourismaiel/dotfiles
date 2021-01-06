local json = require("JSON")
local gears = require("gears")
local lain = require("lain")
local awful = require("awful")
local naughty = require("naughty")
local wibox = require("wibox")
local brightness = require("widgets.brightness")
local network_menu = require("widgets.damn.network")
local notifier = require('widgets.damn.notifier')
local tasklist_widget = require('widgets.tasklist.widget')
local string, os = string, os

-- Helpers
local my_table = awful.util.table or gears.table
local margin = wibox.container.margin
local background = wibox.container.background
local markup = lain.util.markup
local text = wibox.widget.textbox

local theme = awful.util.theme

awful.util.variables.is_network_connected = false

-- System Tray - Systray
local systray_widget = wibox.widget.systray(true)
systray_widget:set_horizontal(true)
systray_widget:set_base_size(22)
local systray = margin(wibox.container.place(systray_widget), 10, 10, 12, 0)

local keyboard = require("widgets.damn.bar-widgets.keyboard")()
local bat = require("widgets.damn.bar-widgets.battery")()
local volume = require("widgets.damn.bar-widgets.volume")()
local is_online = require("widgets.damn.bar-widgets.is-online")()
local clock = require("widgets.damn.clock")(theme)
local layoutbox = require("widgets.damn.bar-widgets.layout")
local menus = require("widgets.damn.bar-widgets.menus")

local function create_button(w, action, higher_color, color)
  local bg_normal = color and color or theme.widget_bg .. (higher_color and "ee" or "00")
  local bg_hover = (higher_color and theme.widget_bg .. "ff" or theme.widget_bg .. "ff")

  w = background(w, bg_normal)
  w:connect_signal(
    "mouse::enter",
    function()
      w.bg = bg_hover
    end
  )

  w:connect_signal(
    "mouse::leave",
    function()
      w.bg = bg_normal
    end
  )

  if type(action) == "function" then
    w:buttons(my_table.join(awful.button({}, 1, action)))
  end

  return w
end

function set_wallpaper()
  awful.spawn.easy_async_with_shell(
    "cat " .. os.getenv("HOME") .. "/.cache/wallpaper",
    function(stdout)
      gears.wallpaper.maximized(string.gsub(stdout, "^%s*(.-)%s*$", "%1"), nil, true)
    end
  )
end

theme.set_wallpaper = set_wallpaper

awesome.connect_signal(
  "awesome::update_wallpaper",
  function()
    set_wallpaper()
  end
)

function theme.at_screen_connect(s)
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
  notifier()

  local network_menu_widget =
    network_menu {
    layout = {
      layout = wibox.layout.fixed.vertical
    },
    margins = {
      right = 100,
      bottom = 50
    },
    update_function = require("widgets/damn/network/update_function")
  }

  -- If wallpaper is a function, call it with the screen
  set_wallpaper()

  s.mytaglist = require("widgets.taglist")(s)

  -- Task List
  s.mytasklist =
    tasklist_widget {
    screen = s,
    filter = tasklist_widget.filter.allscreen,
    buttons = awful.util.tasklist_buttons,
    layout = {layout = wibox.layout.fixed.horizontal},
    update_function = require("widgets.tasklist.update")
  }

  local notification_count_text = text(markup("#ffffff", font(string.format("%d", #naughty.active))))
  local notification_count =
    create_button(
    wibox.widget {
      {
        {
          {
            {
              {
                widget = notification_count_text
              },
              widget = wibox.container.place
            },
            widget = wibox.container.constraint,
            strategy = "exact",
            width = 20,
            height = 20
          },
          widget = wibox.container.background,
          bg = theme.primary,
          shape = function(cb, width, height)
            return gears.shape.circle(cb, width, height)
          end
        },
        widget = wibox.container.constraint,
        strategy = "exact",
        width = 20
      },
      widget = margin,
      left = 15,
      right = 15
    },
    notification_screen_show,
    theme.sidebar_bg,
    theme.sidebar_bg
  )

  notification_count.visible = #naughty.active > 0

  naughty.connect_signal(
    "property::active",
    function()
      notification_count_text:set_markup(markup("#ffffff", font(string.format("%d", #naughty.active))))
      notification_count.visible = #naughty.active > 0
    end
  )

  s.tags_list_widgets =
    wibox.widget {
    widget = wibox.container.background,
    bg = theme.sidebar_bg,
    shape = function(cr, width, height)
      gears.shape.rectangle(cr, width, height)
    end,
    {
      layout = wibox.layout.align.horizontal,
      {
        {
          menus,
          wibox.container.background(wibox.container.margin(wibox.widget {}, 1), theme.separator),
          margin(s.mytaglist, 10),
          layout = wibox.layout.align.horizontal
        },
        layout = wibox.layout.align.horizontal
      },
      margin(
        background(
          {
            wibox.container.background(wibox.container.margin(wibox.widget {}, 1), theme.separator),
            wibox.container.place(margin(s.mytasklist, 0, 10)),
            wibox.container.background(wibox.container.margin(wibox.widget {}, 1), theme.separator),
            layout = wibox.layout.align.horizontal
          },
          "#1f1f1f"
        ),
        10,
        10
      ),
      {
        layout = wibox.layout.fixed.horizontal,
        {
          systray,
          layoutbox,
          volume,
          bat,
          keyboard,
          network_menu_widget.indicator_widget,
          clock,
          notification_count,
          is_online,
          layout = wibox.layout.fixed.horizontal
        }
      }
    }
  }
  -- Bar
  s.tags_list = awful.wibar({position = "bottom", screen = s, type = "dock", height = 50, bg = "#ffffff00"})

  s.tags_list:setup {
    layout = wibox.layout.align.vertical,
    s.tags_list_widgets
  }

  s.main_bar = awful.wibar({position = "bottom", screen = s, height = 45, bg = theme.wibar_bg, visible = false})
end

return theme
