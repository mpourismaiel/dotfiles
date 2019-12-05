local json = require("json")
local gears = require("gears")
local lain = require("lain")
local awful = require("awful")
local naughty = require("naughty")
local wibox = require("wibox")
local layout_indicator = require("widgets.layout-indicator")
local brightness = require("widgets.brightness")
local string, os = string, os

-- Helpers
local my_table = awful.util.table or gears.table
local margin = wibox.container.margin
local background = wibox.container.background
local markup = lain.util.markup

local default_dir = require("awful.util").get_themes_dir() .. "default"
local icon_dir = os.getenv("HOME") .. "/.config/awesome/themes/holo/icons"
local clean_icons = os.getenv("HOME") .. "/.config/awesome/themes/icons"

local theme = {
  default_dir = default_dir,
  icon_dir = icon_dir,
  wallpaper = os.getenv("HOME") .. "/Pictures/Wallpapers/world-of-warcraft-battle-for-azeroth-teldrassil.jpg",
  font_only = "FiraCode Bold",
  font = "FiraCode Bold 10",
  hotkeys_font = "FiraCode 10",
  font_icon = "fontello",
  useless_gap = 0,
  primary = "#FC4384",
  white = "#ffffff",
  sidebar_bg = gears.color(
    {
      type = "linear",
      from = {20, 0},
      to = {70, 0},
      stops = {{0, "#1a1a1a"}, {1, "#050505"}}
    }
  ),
  -- boxes
  exit_screen_font = "FiraCode Bold 14",
  exit_screen_goodbye_font = "FiraCode Bold 50",
  -- colors
  bg_systray = "#171520",
  fg_normal = "#ffffff33",
  fg_focus = "#86848a",
  bg_focus = "#151515",
  bg_normal = "#151515",
  fg_urgent = "#CC9393",
  bg_urgent = "#006B8E",
  -- systray
  systray_icon_spacing = 15,
  -- border styles
  border_width = 3,
  border_normal = "#252525",
  border_focus = "#FC4384",
  hotkeys_border_width = 3,
  hotkeys_border_color = "#252525",
  -- tag list styles
  taglist_fg_focus = "#86848a",
  taglist_bg_focus = gears.color(
    {
      type = "linear",
      from = {20, 0},
      to = {70, 0},
      stops = {{0, "#241b2f66"}, {1, "#050505"}}
    }
  ),
  taglist_bg_urgent = "#FC4384",
  taglist_fg_urgent = "#86848a",
  taglist_font = "Font Awesome 5 Free Solid 12",
  -- wibar styles
  widget_bg = "#241b2f",
  wibar_bg = "#171520",
  -- menu styles
  menu_height = 20,
  menu_width = 160,
  menu_icon_size = 32,
  -- notification styles
  notification_border_color = "#FC4384",
  notification_border_width = 2,
  notification_width = 300,
  notification_margin = 16,
  -- layout box styles
  layout_tile = clean_icons .. "/tiled.svg",
  layout_max = clean_icons .. "/maximized.svg",
  layout_floating = clean_icons .. "/float.svg",
  -- task list styles
  tasklist_bg_normal = "#171520",
  tasklist_bg_focus = gears.color(
    {
      type = "linear",
      from = {0, 20},
      to = {0, 70},
      stops = {{0, "#241b2f66"}, {1, "#050505"}}
    }
  ),
  tasklist_fg_focus = "#86848a",
  tasklist_plain_task_name = true,
  tasklist_disable_icon = false,
  -- title bar styles
  titlebar_bg = "#171520",
  titlebar_fg = "#86848a",
  titlebar_fg_focus = "#86848a",
  titlebar_height = 32,
  titlebar_close_button_normal = default_dir .. "/titlebar/close_normal.png",
  titlebar_close_button_focus = default_dir .. "/titlebar/close_focus.png",
  titlebar_minimize_button_normal = default_dir .. "/titlebar/minimize_normal.png",
  titlebar_minimize_button_focus = default_dir .. "/titlebar/minimize_focus.png",
  titlebar_sticky_button_normal_inactive = default_dir .. "/titlebar/sticky_normal_inactive.png",
  titlebar_sticky_button_focus_inactive = default_dir .. "/titlebar/sticky_focus_inactive.png",
  titlebar_sticky_button_normal_active = default_dir .. "/titlebar/sticky_normal_active.png",
  titlebar_sticky_button_focus_active = default_dir .. "/titlebar/sticky_focus_active.png",
  titlebar_floating_button_normal_inactive = default_dir .. "/titlebar/floating_normal_inactive.png",
  titlebar_floating_button_focus_inactive = default_dir .. "/titlebar/floating_focus_inactive.png",
  titlebar_floating_button_normal_active = default_dir .. "/titlebar/floating_normal_active.png",
  titlebar_floating_button_focus_active = default_dir .. "/titlebar/floating_focus_active.png",
  titlebar_maximized_button_normal_inactive = default_dir .. "/titlebar/maximized_normal_inactive.png",
  titlebar_maximized_button_focus_inactive = default_dir .. "/titlebar/maximized_focus_inactive.png",
  titlebar_maximized_button_normal_active = default_dir .. "/titlebar/maximized_normal_active.png",
  titlebar_maximized_button_focus_active = default_dir .. "/titlebar/maximized_focus_active.png"
}

function icon(ic, size, solid, font_awesome)
  return markup.font(
    string.format(
      "%s %s%s",
      font_awesome and "Font Awesome 5 Free" or theme.font_icon,
      solid and "solid " or "",
      size or 10
    ),
    ic
  )
end

function font(text)
  return markup.font(theme.font, text)
end

function pad(size)
  local str = ""
  for i = 1, size or 1 do
    str = str .. " "
  end
  return font(str)
end

function bar_widget(w)
  return background(margin(wibox.container.place(w), 0, 0, 10, 10), theme.sidebar_bg, gears.shape.rectangle)
end

function titlebar_widget(w)
  return {
    {widget = w},
    widget = margin,
    left = 8,
    right = 8,
    top = 4,
    bottom = 4
  }
end

theme.font_fn = font
theme.icon_fn = icon
theme.pad_fn = pad
theme.bar_widget_fn = bar_widget
theme.titlebar_widget_fn = titlebar_widget

theme.lock_bg = string.format("%s/Pictures/Lockscreen/wallpaper.jpg", os.getenv("HOME"))
theme.lock_cmd = string.format("sh %s/.config/i3/i3lock %s", os.getenv("HOME"), theme.lock_bg)

local toggl =
  awful.widget.watch(
  string.format("sh %s/.config/polybar/scripts/toggl.sh", os.getenv("HOME")),
  60,
  function(widget, stdout)
    widget:set_markup(markup(theme.fg_normal, pad(1) .. font(stdout)))
  end
)

local toggl_report =
  awful.widget.watch(
  string.format("sh %s/.config/polybar/scripts/toggl-report.sh hide", os.getenv("HOME")),
  99999,
  function(widget, stdout)
    widget:set_markup(markup(theme.fg_normal, icon("")))
  end
)

-- Ping
local ping =
  bar_widget(
  awful.widget.watch(
    string.format("sh %s/bin/show-ping.sh", os.getenv("HOME")),
    1,
    function(widget, stdout)
      if stdout == "" then
        widget:set_markup("")
      else
        widget:set_markup(markup(theme.fg_normal, icon("", 9, true, true) .. pad(1) .. font(stdout)))
      end
    end
  )
)

-- System Tray - Systray
local systray_widget = wibox.widget.systray(true)
systray_widget:set_horizontal(false)
systray_widget:set_base_size(16)
local systray = margin(wibox.container.place(systray_widget), 5, 0, 10, 25)

-- Clock
local clock = bar_widget(wibox.widget.textclock(markup(theme.fg_normal, markup.font("FiraCode Bold 16", "%H\n%M"))))

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
        widget:set_markup(icon(bat_icon, 12))
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
        local volume_icon = ""
        local level = tonumber(volume_now.level)

        if level <= 35 then
          volume_icon = icon("", 12)
        elseif level <= 65 then
          volume_icon = icon("", 12)
        elseif level <= 100 then
          volume_icon = icon("", 12)
        end

        vlevel = volume_icon
      else
        vlevel = icon("", 12)
      end
      widget:set_markup(markup(theme.fg_normal, vlevel))
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

-- CPU
local cpu = function(format)
  return lain.widget.cpu(
    {
      settings = function()
        widget:set_markup(
          format and format(icon("", 9, true, true), cpu_now.usage) or
            (icon("") .. pad(1) .. font(cpu_now.usage .. "%"))
        )
      end
    }
  )
end
theme.cpu = cpu

-- MEM
local mem = function(format)
  return lain.widget.mem(
    {
      timeout = 1,
      settings = function()
        widget:set_markup(
          format and format(icon("", 9, true, true), mem_now.perc) or
            (icon("", 9, true, true) .. pad(1) .. font(mem_now.perc .. "%"))
        )
      end
    }
  )
end
theme.mem = mem

-- Brightness
local backlight =
  bar_widget(
  brightness(
    {
      markup = "",
      level1 = icon("", 12),
      level2 = icon("", 12),
      level3 = icon("", 12),
      level4 = icon("", 12)
    }
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
              widget = wibox.widget.textbox,
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

function set_github_listener(fn)
  awful.widget.watch(
    string.format("sh %s/.config/polybar/scripts/inbox-github.sh", os.getenv("HOME")),
    60,
    function(widget, stdout)
      fn(string.gsub(stdout, "^%s*(.-)%s*$", "%1"))
    end
  )
end

theme.set_github_listener = set_github_listener

local music_box =
  wibox {
  visible = false,
  screen = nil
}
local margin = wibox.container.margin
local background = wibox.container.background
local text = wibox.widget.textbox

function widget_button(w, action)
  local bg_normal = theme.widget_bg .. "00"
  local bg_hover = "#1c1c1c"

  w = background(margin(w, 5, 5, 5, 5), bg_normal)
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

  w:buttons(my_table.join(awful.button({}, 1, action)))

  return wibox.container.place({widget = w, forced_height = 50, forced_width = 50})
end

function music_action(action)
  awful.spawn.with_shell(string.format("node %s/bin/headset-track-info.js %s", os.getenv("HOME"), action))
end

theme.statusbar = function(s, display_systray, top_widget, bg_color)
  return wibox.container.constraint(
    wibox.widget(
      {
        widget = wibox.container.background,
        bg = bg_color or theme.sidebar_bg,
        {
          layout = wibox.layout.align.vertical,
          {
            {
              top_widget or nil,
              s.mytaglist,
              layout = wibox.layout.align.vertical
            },
            layout = wibox.layout.align.vertical
          },
          nil,
          {
            layout = wibox.layout.fixed.vertical,
            {
              display_systray and systray or nil,
              volume,
              supports_backlight,
              bat,
              keyboard,
              clock,
              layout = wibox.layout.fixed.vertical
            }
          }
        }
      }
    ),
    "exact",
    50
  )
end

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

function theme.at_screen_connect(s)
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height

  music_box =
    wibox {
    x = 50,
    y = screen_height - 135,
    width = 400,
    height = 130,
    visible = false,
    ontop = true,
    screen = s,
    bg = theme.widget_bg .. "d6",
    opacity = 0,
    type = "desktop",
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, 5)
    end
  }
  local music_artist = text("")
  local music_title = text("")
  music_box:setup {
    {
      layout = wibox.layout.fixed.vertical,
      {
        layout = wibox.layout.fixed.horizontal,
        music_title,
        music_artist
      },
      margin(text(""), 0, 0, 10, 0),
      {
        layout = wibox.layout.flex.horizontal,
        spacing = 25,
        widget_button(
          text(icon("")),
          function()
            music_action("prev")
          end
        ),
        widget_button(
          text(icon("")),
          function()
            music_action("stop")
          end
        ),
        widget_button(
          text(icon("")),
          function()
            music_action("pause")
          end
        ),
        widget_button(
          text(icon("")),
          function()
            music_action("play")
          end
        ),
        widget_button(
          text(icon("")),
          function()
            music_action("next")
          end
        )
      }
    },
    widget = margin,
    left = 15,
    right = 15,
    top = 15,
    bottom = 15
  }

  -- If wallpaper is a function, call it with the screen
  local wallpaper = theme.wallpaper
  if type(wallpaper) == "function" then
    wallpaper = wallpaper(s)
  end
  gears.wallpaper.maximized(wallpaper, s, true)

  awful.spawn.with_line_callback(
    string.format("node %s/bin/headset-track-info.js", os.getenv("HOME")),
    {
      stdout = function(info)
        resp_json = json.decode(info)
        music_title:set_markup(
          markup.font(theme.font, resp_json.title) .. markup.font(theme.hotkeys_font, " - " .. resp_json.artist)
        )
        music_box.opacity = 1
        music_box.visible = true
        gears.timer {
          timeout = 5,
          autostart = true,
          callback = function()
            music_box.opacity = 0
            music_box.visible = false
          end
        }
      end
    }
  )

  -- Tag List
  for index, tag in pairs(awful.util.tags) do
    awful.tag.add(
      tag.text,
      {
        screen = s,
        layout = tag.layout or awful.layout.layouts[1],
        selected = index == 1
      }
    )
  end
  s.mytaglist =
    awful.widget.taglist {
    screen = s,
    filter = awful.widget.taglist.filter.noempty,
    buttons = awful.util.taglist_buttons,
    layout = {
      layout = wibox.layout.fixed.vertical
    },
    update_function = require("widgets.taglist")(theme)
  }

  local supports_backlight = nil
  for k, v in pairs(s.outputs) do
    if k == "eDP1" then
      supports_backlight = backlight
    end
  end

  -- Prompt
  s.mypromptbox = awful.widget.prompt()

  -- Layout Box
  local layoutbox = awful.widget.layoutbox(s)
  layoutbox.forced_height = 16
  layoutbox.forced_width = 16
  s.mylayoutbox = margin(wibox.container.place(layoutbox), 18, 16, 0, 0)
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

  -- Bar
  s.mytagbar = awful.wibar({position = "left", screen = s, width = 50, bg = theme.wibar_bg})
  s.mytagbar:setup {
    bg = theme.wibar_bg,
    layout = wibox.layout.align.horizontal,
    nil,
    nil,
    theme.statusbar(s, true)
  }

  -- Task List
  s.mytasklist =
    awful.widget.tasklist {
    screen = s,
    filter = awful.widget.tasklist.filter.currenttags,
    buttons = awful.util.tasklist_buttons,
    update_function = require("widgets.tasklist")(theme)
  }

  s.mytasklistbar = awful.wibar({position = "top", screen = s, height = 45, bg = "#1a1a1a"})
  s.mytasklistbar:setup {
    layout = wibox.layout.align.horizontal,
    {
      create_button(
        wibox.container.constraint(wibox.container.place(text(icon("", 12, true, true))), "exact", 50),
        function()
          info_screen_show()
        end,
        nil,
        theme.sidebar_bg
      ),
      s.mytasklist,
      layout = wibox.layout.align.horizontal
    },
    nil,
    create_button(s.mylayoutbox, nil, true)
  }

  s.mywibox = awful.wibar({position = "bottom", screen = s, height = 45, bg = theme.wibar_bg, visible = false})
end

theme.titlebar_fun = function(c)
  theme.mytitlebar =
    awful.titlebar(
    c,
    {
      size = 40,
      position = "top",
      buttons = my_table.join(
        awful.button(
          {},
          1,
          function()
            client.focus = c
            c:raise()
            awful.mouse.client.move(c)
          end
        ),
        awful.button(
          {},
          3,
          function()
            client.focus = c
            c:raise()
            awful.mouse.client.resize(c)
          end
        )
      )
    }
  )

  theme.mytitlebar:setup {
    {
      {
        {
          {
            {
              -- {
              widget = awful.titlebar.widget.titlewidget(c)
              -- },
              -- widget = wibox.container.rotate,
              -- direction = "east"
            },
            widget = margin,
            top = 5,
            bottom = 5,
            left = 8,
            right = 8
          },
          widget = background,
          bg = theme.widget_bg
        },
        layout = wibox.layout.flex.horizontal
      },
      widget = margin,
      top = 5,
      bottom = 5
    },
    nil,
    {
      {
        {
          {
            titlebar_widget(awful.titlebar.widget.maximizedbutton(c)),
            titlebar_widget(awful.titlebar.widget.closebutton(c)),
            layout = wibox.layout.fixed.horizontal
          },
          widget = background,
          bg = theme.widget_bg
        },
        widget = margin,
        top = 5,
        bottom = 5
      },
      layout = wibox.layout.fixed.horizontal
    },
    layout = wibox.layout.align.horizontal
  }
end

theme.zen_mode = function(c)
  local s = awful.screen.focused()
  if s.mytagbar.visible == true then
    s.mytagbar.visible = false
    s.mywibox.bg = theme.wibar_bg
    s.mytasklistbar.bg = theme.wibar_bg
    awful.screen.focused().selected_tag.gap = 0
    awful.layout.arrange(scr)
  else
    s.mytagbar.visible = true
    s.mywibox.bg = "#241b2f"
    s.mytasklistbar.bg = "#241b2f"
    awful.screen.focused().selected_tag.gap = 10
    awful.layout.arrange(scr)
  end
end

return theme
