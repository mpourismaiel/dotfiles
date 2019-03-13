local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local markup = require("lain.util.markup")
local helpers = require("helpers")
local my_table = awful.util.table or gears.table
local pad = helpers.pad
local theme_pad = beautiful.pad_fn
local keygrabber = require("awful.keygrabber")

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

local info_screen
local info_screen_grabber

function info_screen_show()
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
  info_screen =
    wibox(
    {
      x = screen_width - 400,
      y = 0,
      visible = true,
      ontop = true,
      screen = s,
      type = "dock",
      height = screen_height,
      width = 400,
      bg = beautiful.widget_bg .. "d6"
    }
  )
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
  info_screen_setup()
end

function info_screen_hide()
  info_screen.visible = false
  awful.keygrabber.stop(info_screen_grabber)
end

local time_text = wibox.widget.textclock(markup("#FFFFFF", markup.font("FiraCode 30", "%H:%M")))
local date_text = wibox.widget.textclock(markup("#838790", markup.font("FiraCode 12", "%A, %B %d, %Y")))

function title(txt)
  return text(markup("#FFFFFF", markup.font("FiraCode Bold 14", txt)))
end

function widget_info(w1, w2, w3)
  return wibox.widget {
    {
      {
        w1,
        w2,
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
end

function widget_button(w, action)
  local bg_normal = beautiful.widget_bg .. "00"
  local bg_hover = "#1c1c1c"

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
      return ic .. theme_pad(3) .. "CPU"
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
      return ic .. theme_pad(3) .. "Memory"
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

awful.util.disable_notification = 0
local disable_notification_icon = icon("", 10, true, true)
local disable_notification_text = text(markup("#FFFFFF", theme_pad(3) .. "Disable Notifications"))
local disable_notification =
  widget_button(
  widget_info(disable_notification_icon, disable_notification_text, nil),
  function()
    if awful.util.disable_notification == 0 then
      awful.util.disable_notification = 1
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(3) .. "Disable All Notifications"))
    elseif awful.util.disable_notification == 1 then
      awful.util.disable_notification = 2
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(3) .. "Enable Notifications"))
    elseif awful.util.disable_notification == 2 then
      awful.util.disable_notification = 0
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(3) .. "Disable Notifications"))
    end
  end
)

local github_icon = icon("", 10, true, true)
local github_text = text(markup("#FFFFFF", theme_pad(3) .. "Loading notifications"))
local github =
  widget_button(
  widget_info(github_icon, github_text, nil),
  function()
    awful.spawn.with_shell("google-chrome-beta https://github.com/notifications")
  end
)

awful.widget.watch(
  string.format("sh %s/.config/polybar/scripts/inbox-github.sh", os.getenv("HOME")),
  60,
  function(widget, stdout)
    github_text:set_markup(markup("#FFFFFF", theme_pad(3) .. string.gsub(stdout, "^%s*(.-)%s*$", "%1")))
  end
)

function info_screen_setup()
  info_screen:setup {
    margin(pad(0), 0, 0, 32),
    margin(time_text, 40, 40),
    margin(date_text, 40, 40, 0, 20),
    background(margin(title("Information"), 40, 40, 10, 10), "#1c1c1c94"),
    margin(pad(0), 0, 0, 0, 16),
    github,
    margin(pad(0), 0, 0, 0, 32),
    background(margin(title("System Information"), 40, 40, 10, 10), "#1c1c1c94"),
    margin(pad(0), 0, 0, 0, 16),
    uptime_widget,
    cpu,
    mem,
    fs_root_used,
    fs_home_used,
    background(margin(title("Settings"), 40, 40, 10, 10), "#1c1c1c94"),
    margin(pad(0), 0, 0, 0, 16),
    disable_notification,
    layout = wibox.layout.fixed.vertical
  }
end
