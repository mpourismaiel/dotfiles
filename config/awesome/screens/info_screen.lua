local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")
local secrets = require("secrets")
local markup = require("lain.util.markup")
local helpers = require("utils.helpers")
local my_table = awful.util.table or gears.table
local pad = helpers.pad
local theme_pad = beautiful.pad_fn
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("utils.animation").createAnimObject

local margin = wibox.container.margin
local background = wibox.container.background
local text = wibox.widget.textbox
local icon = function(ic, size, solid, fontawesome, string)
  if string == true then
    return beautiful.icon_fn(ic, size, solid, fontawesome)
  end

  return text(markup("#FFFFFF", beautiful.icon_fn(ic, size, solid, fontawesome)))
end
local font = beautiful.font_fn

local info_screen =
  wibox {
  visible = false,
  screen = nil
}
local backdrop = wibox {type = "dock", x = 0, y = 0}
local info_screen_grabber

function info_screen_show(show_rofi)
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
  backdrop =
    wibox(
    {
      type = "dock",
      height = screen_height,
      width = screen_width,
      x = 0,
      y = 0,
      screen = s,
      ontop = true,
      visible = true,
      opacity = 0,
      bg = beautiful.wibar_bg .. "cc"
    }
  )
  info_screen =
    wibox(
    {
      x = -400,
      y = 0,
      visible = true,
      ontop = true,
      screen = s,
      type = "dock",
      height = screen_height,
      width = 450,
      opacity = 0,
      bg = beautiful.wibar_bg
    }
  )
  createAnimObject(0.6, info_screen, {x = 0, opacity = 1}, "outCubic")
  createAnimObject(0.6, backdrop, {opacity = 1}, "outCubic")

  backdrop:buttons(
    awful.util.table.join(
      awful.button(
        {},
        1,
        function()
          info_screen_hide()
        end
      )
    )
  )

  info_screen_setup(s, show_rofi)
end

function info_screen_hide()
  local s = awful.screen.focused()
  backdrop.visible = false
  createAnimObject(
    0.6,
    info_screen,
    {x = -400, opacity = 0},
    "outCubic",
    function()
      info_screen.visible = false
    end
  )
  awful.keygrabber.stop(info_screen_grabber)
end

local time_text = wibox.widget.textclock(markup("#FFFFFF", markup.font("FiraCode 30", "%H:%M")))
local date_text = wibox.widget.textclock(markup("#838790", markup.font("FiraCode 12", "%A, %B %d, %Y")))

function title(txt)
  return text(markup("#FFFFFF", markup.font("FiraCode Bold 14", txt)))
end

function widget_info(w1, w2, w3)
  local marginalizedW2 = margin(w2)
  local ret =
    wibox.widget {
    {
      {
        w1,
        marginalizedW2,
        layout = wibox.layout.fixed.horizontal
      },
      nil,
      w3,
      layout = wibox.layout.align.horizontal
    },
    widget = margin,
    left = 40,
    right = 40,
    top = 10,
    bottom = 10
  }
  ret:connect_signal(
    "mouse::enter",
    function()
      createAnimObject(1, marginalizedW2, {left = 10}, "outCubic")
    end
  )
  ret:connect_signal(
    "mouse::leave",
    function()
      createAnimObject(1, marginalizedW2, {left = 0}, "outCubic")
    end
  )
  return ret
end

function widget_button(w, action)
  local bg_normal = beautiful.widget_bg .. "00"
  local bg_hover = beautiful.widget_bg .. "ff"

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

  w:buttons(my_table.join(awful.button({}, 1, action)))

  return w
end

local cpu =
  widget_info(
  beautiful.cpu(
    function(ic, usage)
      return markup(beautiful.white, ic .. theme_pad(3) .. "CPU")
    end
  ),
  nil,
  beautiful.cpu(
    function(_, usage)
      return usage .. "%"
    end
  )
)

local mem =
  widget_info(
  beautiful.mem(
    function(ic, usage)
      return markup(beautiful.white, ic .. theme_pad(3) .. "Memory")
    end
  ),
  nil,
  beautiful.mem(
    function(_, usage)
      return usage .. "%"
    end
  )
)

local root_used = text()
local fs_root_used = widget_info(icon("", 10, true, true), text(markup("#FFFFFF", theme_pad(3) .. "/")), root_used)

local home_used = text()
local fs_home_used = widget_info(icon("", 10, true, true), text(markup("#FFFFFF", theme_pad(3) .. "/Home")), home_used)

for _, s in ipairs {{partition = "sdb3", widget = root_used}, {partition = "sdb4", widget = home_used}} do
  awful.widget.watch(
    string.format('bash -c "df -hl | grep \'%s\' | awk \'{print $5}\'"', s.partition),
    120,
    function(w, stdout)
      s.widget:set_markup(string.gsub(stdout, "^%s*(.-)%s*$", "%1"))
    end
  )
end

local uptime = text()
local uptime_widget = widget_info(icon("", 10, true, true), text(markup("#FFFFFF", theme_pad(3) .. "Uptime")), uptime)

awful.widget.watch(
  'bash -c "echo $(uptime) | sed \'s/\\sup.*//g\'"',
  60,
  function(w, stdout)
    uptime:set_markup(string.gsub(stdout, "^%s*(.-)%s*$", "%1"))
  end
)

local packages_number =
  awful.widget.watch(
  string.format("sh %s/bin/get_packages_with_update.sh", os.getenv("HOME")),
  3600,
  function(widget, stdout, stderr)
    widget:set_markup(string.gsub(stdout, "^%s*(.-)%s*$", "%1"))
  end,
  text()
)

local packages =
  widget_info(icon("", 10, true, true), text(markup("#FFFFFF", theme_pad(3) .. "New Updates")), packages_number)
packages:buttons(
  awful.util.table.join(
    awful.button(
      {},
      1,
      function()
        awful.spawn("xterm -e 'yay -Syyu'")
      end
    )
  )
)

awful.util.disable_notification = 0
local disable_notification_icon = icon("", 10, true, true)
local disable_notification_text = text(markup("#FFFFFF", theme_pad(2) .. "Disable Notifications"))
local disable_notification =
  widget_button(
  widget_info(disable_notification_icon, disable_notification_text, nil),
  function()
    if awful.util.disable_notification == 0 then
      awful.util.disable_notification = 1
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(2) .. "Disable All Notifications"))
    elseif awful.util.disable_notification == 1 then
      awful.util.disable_notification = 2
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(2) .. "Enable Notifications"))
    elseif awful.util.disable_notification == 2 then
      awful.util.disable_notification = 0
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(2) .. "Disable Notifications"))
    end
  end
)

local sound_output_icon = icon("", 10, true, true)
local sound_output_text = text(markup("#FFFFFF", theme_pad(3) .. "Output: Local"))
local sound_output =
  widget_button(
  widget_info(sound_output_icon, sound_output_text, nil),
  function()
    awful.spawn.easy_async(
      string.format("bash %s/bin/sound_toggle toggle", os.getenv("HOME")),
      function(stdout)
        local text = string.gsub(stdout, "^%s*(.-)%s*$", "%1")
        sound_output_text:set_markup(
          markup("#FFFFFF", theme_pad(3) .. "Output: " .. (text == "" and "Local" or text))
        )
      end
    )
  end
)
awful.spawn.easy_async(
  string.format("bash %s/bin/sound_toggle toggle", os.getenv("HOME")),
  function(stdout)
    local text = string.gsub(stdout, "^%s*(.-)%s*$", "%1")
    sound_output_text:set_markup(
      markup("#FFFFFF", theme_pad(3) .. "Output: " .. (text == "" and "Local" or text))
    )
  end
)

local github_icon = icon("", 10, true, true)
local github_text = text(markup("#FFFFFF", theme_pad(3) .. "Github Notifications"))
local github_notifications = text(markup("#FFFFFF", theme_pad(3) .. "Loading notifications"))
local github =
  widget_button(
  widget_info(github_icon, github_text, github_notifications),
  function()
    awful.spawn.with_shell("google-chrome-beta https://github.com/notifications")
  end
)

beautiful.set_github_listener(
  function(text)
    github_notifications:set_markup(markup("#FFFFFF", theme_pad(3) .. (text == "" and "0" or text)))
  end
)

local toggl_icon = icon("", 10, true, true)
local toggl_text = text(markup("#FFFFFF", theme_pad(3) .. "Toggl"))
local toggl_active = text(markup("#FFFFFF", theme_pad(3) .. "Loading active task"))
local toggl =
  widget_button(
  widget_info(toggl_icon, toggl_text, toggl_active),
  function()
    awful.spawn.with_shell("google-chrome-beta https://www.toggl.com/app/timer")
  end
)

awful.widget.watch(
  string.format("sh %s/.config/polybar/scripts/toggl.sh description", os.getenv("HOME")),
  60,
  function(widget, stdout)
    local text = string.gsub(stdout, "^%s*(.-)%s*$", "%1")
    toggl_text:set_markup(markup("#FFFFFF", theme_pad(3) .. (text == "" and "No Task" or text)))
  end
)

awful.widget.watch(
  string.format("sh %s/.config/polybar/scripts/toggl.sh duration", os.getenv("HOME")),
  60,
  function(widget, stdout)
    local text = string.gsub(stdout, "^%s*(.-)%s*$", "%1")
    toggl_active:set_markup(markup("#FFFFFF", theme_pad(3) .. (text == "-m" and "" or text)))
  end
)

local toggl_reports_icon = icon("", 10, true, true)
local toggl_reports_text = text(markup("#FFFFFF", theme_pad(3) .. "Reports"))
local toggl_reports = widget_info(toggl_reports_icon, toggl_reports_text, text())

local toggl_syna_icon = icon("", 10, true, true)
local toggl_syna_text = text(markup("#FFFFFF", theme_pad(3) .. "Syna"))
local toggl_syna_active = text(markup("#FFFFFF", theme_pad(3) .. "Loading Report"))
local toggl_syna =
  widget_button(
  widget_info(toggl_syna_icon, toggl_syna_text, toggl_syna_active),
  function()
    awful.spawn.with_shell("google-chrome-beta https://www.toggl.com/app/reports/summary/2623050")
  end
)

awful.widget.watch(
  string.format("sh %s/bin/toggl-report", os.getenv("HOME")),
  60,
  function(widget, stdout)
    local text = string.gsub(stdout, "^%s*(.-)%s*$", "%1")
    toggl_syna_active:set_markup(markup("#FFFFFF", theme_pad(3) .. (text == "m" and "" or text)))
  end
)

local feedly = text()
local feedly_timer = gears.timer({timeout = 3600})

local resp = {}
feedly_timer:connect_signal(
  "timeout",
  function()
    local result, status =
      http.request {
      method = "GET",
      url = "https://cloud.feedly.com/v3/streams/contents?streamId=" ..
        secrets.feedly_stream .. "&count=20&unreadOnly=true&ranked=newest",
      headers = {
        Authorization = "Bearer " .. secrets.feedly
      },
      sink = ltn12.sink.table(resp)
    }
    if (status == 200) then
      resp_json = json.decode(table.concat(resp))
      gears.debug.dump(resp_json)
    end
  end
)
-- feedly_timer:start()
-- feedly_timer:emit_signal("timeout")

local clipboard_timer = gears.timer({timeout = 5})
local clipboard_table = {
  layout = wibox.layout.fixed.vertical
}
local clipboard_items_widget = wibox.widget(clipboard_table)
local clipboard_widgets = {
  layout = wibox.layout.fixed.vertical,
  margin(pad(0), 0, 0, 0, 16),
  background(margin(title("Clipboard"), 40, 40, 10, 10), "#1c1c1c"),
  margin(pad(0), 0, 0, 0, 16),
  clipboard_items_widget
}
local clipboard = wibox.widget(clipboard_widgets)

local resp = {}
clipboard_timer:connect_signal(
  "timeout",
  function()
    local result, status =
      http.request {
      method = "GET",
      url = "http://localhost:9102/read/3/40",
      sink = ltn12.sink.table(resp)
    }
    if (status == 200) then
      resp_json = json.decode(table.concat(resp))

      local clipboard_table = {layout = wibox.layout.fixed.vertical}
      clipboard_items_widget:setup({layout = wibox.layout.fixed.vertical, text("shit")})
      for _, item in ipairs(resp_json) do
        local w = widget_info(text(), text(string.gsub(item.input, "^%s*(.-)%s*$", "%1")), text())
        w.id = item.id
        w:buttons(
          awful.util.table.join(
            awful.button(
              {},
              1,
              function()
                awful.spawn.easy_async(
                  string.format("curl http://localhost:9102/copy/%s", item.id),
                  function(stdout, stderr, reason, exit_code)
                    naughty.notification {message = "Copied to clipboard!"}
                  end
                )
                info_screen_hide()
              end
            )
          )
        )
        table.insert(clipboard_table, w)
      end
      clipboard_items_widget:setup(clipboard_table)
    end
  end
)

-- clipboard_timer:start()
-- clipboard_timer:emit_signal("timeout")

local power_button = background(margin(title(icon("", 12, true, true, true) .. " Power"), 40, 40, 20, 20), "#1c1c1c")

power_button:connect_signal(
  "mouse::enter",
  function()
    power_button.bg = beautiful.widget_bg
  end
)

power_button:connect_signal(
  "mouse::leave",
  function()
    power_button.bg = beautiful.wibar_bg
  end
)

power_button:buttons(
  awful.util.table.join(
    awful.button(
      {},
      1,
      function()
        info_screen_hide()
        exit_screen_show()
      end
    )
  )
)

local notification_list = naughty.list.notifications {
  base_layout = wibox.widget {
    -- spacing_widget = wibox.widget {
      -- orientation = 'horizontal',
      -- span_ratio  = 0.5,
      -- widget      = wibox.widget.separator,
    -- },
    forced_height = screen_height,
    spacing       = 3,
    layout        = wibox.layout.fixed.vertical
  },
  widget_template = {
    {
      {
        {
          widget = naughty.widget.icon
        },
        widget = wibox.container.constraint,
        strategy = "exact",
        width = 48,
        height = 48
      },
      {
        {
          naughty.widget.title,
          margin(text(''), 0, 0, 10),
          naughty.widget.message,
          {
            layout = wibox.widget {
              -- Adding the wibox.widget allows to share a
              -- single instance for all spacers.
              spacing_widget = wibox.widget {
                orientation = 'vertical',
                span_ratio  = 0.9,
                widget      = wibox.widget.separator,
              },
              spacing = 3,
              layout  = wibox.layout.flex.vertical
            },
            widget = naughty.list.widgets,
          },
          layout = wibox.layout.fixed.vertical
        },
        widget = wibox.container.constraint,
        strategy = "exact",
        width = 259,
        height = 48
      },
      {
        {
          {
            widget = icon("", 10, true, true)
          },
          widget = wibox.container.place,
          valign = "center",
          halign = "center"
        },
        widget = wibox.container.constraint,
        strategy = "exact",
        width = 20,
        height = 48
      },
      spacing = 10,
      fill_space = true,
      layout  = wibox.layout.fixed.horizontal
    },
    widget = margin,
    left = 40,
    right = 20,
    top = 0,
    bottom = 0
  }
}

local notification_list_with_title = wibox.widget {
  visible  = #naughty.active > 0,
  layout = wibox.layout.fixed.vertical,
  background(margin(title("Notifications"), 40, 40, 10, 10), "#1c1c1c"),
  notification_list,
}

naughty.connect_signal('property::active', function()
  notification_list_with_title.visible = #naughty.active > 0
end)

local widgets = {
  {
    {
      layout = wibox.layout.fixed.vertical,
      margin(pad(0), 0, 0, 32),
      margin(time_text, 40, 40),
      margin(date_text, 40, 40, 0, 20),
      notification_list_with_title,
      margin(pad(0), 0, 0, 0, 32),
      background(margin(title("Work Information"), 40, 40, 10, 10), "#1c1c1c"),
      margin(pad(0), 0, 0, 0, 16),
      toggl,
      github,
      toggl_reports,
      toggl_syna,
      margin(pad(0), 0, 0, 0, 32),
      background(margin(title("Information"), 40, 40, 10, 10), "#1c1c1c"),
      margin(pad(0), 0, 0, 0, 16),
      uptime_widget,
      packages,
      cpu,
      mem,
      fs_root_used,
      fs_home_used,
      margin(pad(0), 0, 0, 0, 32),
      -- background(margin(title("Feed"), 40, 40, 10, 10), '#050505'),
      -- margin(pad(0), 0, 0, 0, 16),
      -- feedly,
      -- margin(pad(0), 0, 0, 0, 32),
      background(margin(title("Settings"), 40, 40, 10, 10), "#1c1c1c"),
      margin(pad(0), 0, 0, 0, 16),
      disable_notification,
      sound_output,
      clipboard
    },
    nil,
    power_button,
    layout = wibox.layout.align.vertical
  },
  widget = wibox.container.background,
  bg = "#1a1a1a"
}

local close_button = widget_button(wibox.container.constraint(wibox.container.place(icon("", 12)), "exact", 50, 50))
close_button:buttons(
  awful.util.table.join(
    awful.button(
      {},
      1,
      function()
        info_screen_hide()
      end
    )
  )
)

function info_screen_setup(s, show_rofi)
  if show_rofi ~= true then
    info_screen_grabber =
      awful.keygrabber.run(
      function(_, key, event)
        if event == "release" then
          return
        end
        if key == "Escape" or key == "q" or key == "x" then
          info_screen_hide()
        end
      end
    )

    info_screen:setup(
      {
        layout = wibox.layout.align.horizontal,
        nil,
        widgets,
        beautiful.statusbar(
          s,
          false,
          close_button,
          gears.color(
            {
              type = "linear",
              from = {20, 0},
              to = {70, 0},
              stops = {{0, "#1a1a1a"}, {1, "#050505"}}
            }
          )
        )
      }
    )
    return
  end

  awful.spawn.easy_async(
    "rofi -show drun",
    function(stdout, stderr, reason, exit_code)
      info_screen_hide()
    end
  )

  info_screen:setup(
    {
      layout = wibox.layout.align.horizontal,
      nil,
      nil,
      beautiful.statusbar(
        s,
        false,
        close_button,
        gears.color(
          {
            type = "linear",
            from = {20, 0},
            to = {70, 0},
            stops = {{0, "#1a1a1a"}, {1, "#050505"}}
          }
        )
      )
    }
  )
end
