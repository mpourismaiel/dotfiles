local json = require("json")
local gears = require("gears")
local lain = require("lain")
local awful = require("awful")
local naughty = require("naughty")
local wibox = require("wibox")
local layout_indicator = require("widgets.layout-indicator")
local brightness = require("widgets.brightness")
local network_menu = require("widgets/damn/network")
local clock_widget = require("widgets/damn/clock")
local string, os = string, os

-- Helpers
local my_table = awful.util.table or gears.table
local margin = wibox.container.margin
local background = wibox.container.background
local markup = lain.util.markup
local text = wibox.widget.textbox

local theme = awful.util.theme

awful.util.variables.is_network_connected = false
theme.bar_widget_fn = bar_widget

-- System Tray - Systray
local systray_widget = wibox.widget.systray(true)
systray_widget:set_horizontal(true)
systray_widget:set_base_size(22)
local systray = margin(wibox.container.place(systray_widget), 10, 25, 12, 0)

-- Keyboard
local keyboard = bar_widget(layout_indicator())
keyboard.font = theme.font

function relaunch_layout()
  awful.spawn.with_shell("setxkbmap -layout us,ir -option grp:alt_shift_toggle")
end

keyboard:buttons(my_table.join(awful.button({}, 1, relaunch_layout)))

-- Battery
local bat =
  bar_widget(
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

-- ALSA volume bar
theme.volume =
  lain.widget.alsa(
  {
    settings = function()
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
      widget:set_markup(
        markup(theme.fg_normal, awful.util.theme_functions.icon_string({icon = vlevel, size = 12, font_weight = false}))
      )
    end
  }
)
local volume = bar_widget(theme.volume.widget)
volume:buttons(
  awful.util.table.join(
    awful.button(
      {},
      4,
      function()
        os.execute(string.format("%s set %s 5%%+", theme.volume.cmd, theme.volume.channel))
        theme.volume.update()
      end
    ),
    awful.button(
      {},
      5,
      function()
        os.execute(string.format("%s set %s 5%%-", theme.volume.cmd, theme.volume.channel))
        theme.volume.update()
      end
    ),
    awful.button(
      {},
      1,
      function()
        os.execute(
          string.format("%s set %s toggle", theme.volume.cmd, theme.volume.togglechannel or theme.volume.channel)
        )
        theme.volume.update()
      end
    )
  )
)

theme.myswitcher =
  awful.popup {
  widget = {
    awful.widget.tasklist {
      screen = awful.screen.focused(),
      filter = awful.widget.tasklist.filter.allscreen,
      buttons = my_table.join(
        awful.button(
          {},
          1,
          function(c)
            c.minimized = false

            if not c:isvisible() and c.first_tag then
              c.first_tag:view_only()
            end

            client.focus = c
            c:raise()

            theme.myswitcher.visible = false
            awful.keygrabber.stop(awful.util.switcher_keygrabber)
          end
        )
      ),
      layout = {
        layout = wibox.layout.fixed.horizontal
      },
      widget_template = {
        {
          {
            {
              {
                id = "clienticon",
                widget = awful.widget.clienticon
              },
              widget = margin,
              bottom = 5
            },
            {
              id = "text_role",
              widget = text,
              align = "center",
              forced_width = 80
            },
            layout = wibox.layout.fixed.vertical
          },
          widget = wibox.container.margin,
          top = 10,
          bottom = 10,
          left = 20,
          right = 20
        },
        forced_width = 120,
        forced_height = 120,
        widget = wibox.container.background,
        create_callback = function(self, c, index, objects)
          self:get_children_by_id("clienticon")[1].client = c
        end
      }
    },
    layout = wibox.layout.fixed.horizontal
  },
  bg = theme.widget_bg .. "d6",
  ontop = true,
  placement = awful.placement.centered,
  shape = gears.shape.rectangle,
  visible = false
}

local line = wibox.container.background(wibox.container.constraint(text(""), "exact", 3, 50), theme.primary)

local ping_command =
  [[bash -c '
  wget -q --spider http://google.com

  if [ $? -eq 0 ]; then
      echo "Online"
  else
      echo "Offline"
  fi
']]

gears.timer {
  timeout = 30,
  autostart = true,
  call_now = true,
  callback = function()
    awful.spawn.with_line_callback(
      ping_command,
      {
        stdout = function()
          line.bg = theme.sidebar_bg
          awful.util.variables.is_network_connected = true
        end,
        stderr = function()
          line.bg = theme.primary
          awful.util.variables.is_network_connected = false
        end
      }
    )
  end
}

function create_button(w, action, higher_color, color)
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
  local clock = clock_widget(theme)
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

  -- Tag List
  for index, tag in pairs(awful.util.tags) do
    local rules = nil
    if tag.rules ~= nil then
      rules = {}
      for _, rule in ipairs(tag.rules) do
        rules[rule] = true
      end
    end
    awful.tag.add(
      tag.text,
      {
        icon = tag.icon,
        screen = s,
        layout = tag.layout or awful.layout.layouts[1],
        selected = index == 1,
        rules = rules,
        wibar = tag.wibar
      }
    )
  end
  s.mytaglist =
    awful.widget.taglist {
    screen = s,
    filter = awful.widget.taglist.filter.all,
    buttons = awful.util.taglist_buttons,
    layout = {
      layout = wibox.layout.fixed.horizontal
    },
    update_function = require("widgets.taglist")(theme)
  }

  -- Prompt
  s.mypromptbox = awful.widget.prompt()

  -- Layout Box
  local layoutbox = awful.widget.layoutbox(s)
  layoutbox.forced_height = 16
  layoutbox.forced_width = 16
  s.mylayoutbox = margin(wibox.container.place(layoutbox), 22, 20, 0, 0)
  s.mylayoutbox:buttons(
    my_table.join(
      awful.button(
        {},
        1,
        function()
          awful.layout.inc(1)
        end
      ),
      awful.button(
        {},
        2,
        function()
          awful.layout.set(awful.layout.layouts[1])
        end
      ),
      awful.button(
        {},
        3,
        function()
          awful.layout.inc(-1)
        end
      ),
      awful.button(
        {},
        4,
        function()
          awful.layout.inc(1)
        end
      ),
      awful.button(
        {},
        5,
        function()
          awful.layout.inc(-1)
        end
      )
    )
  )

  -- Task List
  s.mytasklist =
    awful.widget.tasklist {
    screen = s,
    filter = awful.widget.tasklist.filter.allscreen,
    buttons = awful.util.tasklist_buttons,
    layout = {layout = wibox.layout.fixed.horizontal},
    update_function = require("widgets.tasklist")
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
          background(
            {
              s.mylayoutbox,
              wibox.container.background(wibox.container.margin(wibox.widget {}, 1), "#292929"),
              layout = wibox.layout.fixed.horizontal
            },
            "#1f1f1f"
          ),
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
          volume,
          bat,
          keyboard,
          network_menu_widget.indicator_widget,
          clock,
          notification_count,
          line,
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

awful.util.theme_functions.at_screen_connect = theme.at_screen_connect
return theme
