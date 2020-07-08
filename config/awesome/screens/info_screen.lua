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
local theme_pad = awful.util.theme_functions.pad_fn
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("utils.animation").createAnimObject

local margin = wibox.container.margin
local background = wibox.container.background
local text = wibox.widget.textbox
local icon = awful.util.theme_functions.icon_fn()
local font = awful.util.theme_functions.font_fn

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
      opacity = 1,
      bg = beautiful.wibar_bg .. "cc"
    }
  )
  info_screen =
    wibox(
    {
      x = 0,
      y = 0,
      visible = true,
      ontop = true,
      screen = s,
      type = "dock",
      height = screen_height,
      width = 450,
      opacity = 1,
      bg = beautiful.wibar_bg
    }
  )
  -- createAnimObject(0.6, info_screen, {x = 0, opacity = 1}, "outCubic")
  -- createAnimObject(0.6, backdrop, {opacity = 1}, "outCubic")

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
  info_screen.opacity = 0
  info_screen.x = -400
  info_screen.visible = false
  -- createAnimObject(
  --   0.6,
  --   info_screen,
  --   {x = -400, opacity = 0},
  --   "outCubic",
  --   function()
  --     info_screen.visible = false
  --   end
  -- )
  gears.timer {
    autostart = true,
    timeout = 0.3,
    callback = function()
      awful.keygrabber.stop(info_screen_grabber)
    end
  }
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
  local bg_normal = awful.util.theme_functions.widget_bg .. "00"
  local bg_hover = awful.util.theme_functions.widget_bg .. "ff"

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
  awful.util.theme_functions.cpu(
    function(ic, usage)
      return markup(beautiful.white, ic .. theme_pad(3) .. "CPU")
    end
  ),
  nil,
  awful.util.theme_functions.cpu(
    function(_, usage)
      return usage .. "%"
    end
  )
)

local mem =
  widget_info(
  awful.util.theme_functions.mem(
    function(ic, usage)
      return markup(beautiful.white, ic .. theme_pad(3) .. "Memory")
    end
  ),
  nil,
  awful.util.theme_functions.mem(
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
  'bash -c "uptime | grep -ohe \'up .*\' | sed \'s/,//g\' | awk \'{ print $2 }\'"',
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

local network_connectivity = text("Not Connected")

local network =
  widget_info(icon("", 10, true, true), margin(text(markup("#FFFFFF", "Network")), 20), network_connectivity)

gears.timer {
  timeout = 5,
  autostart = true,
  callnow = true,
  callback = function()
    if awful.util.theme_functions.is_network_connected == true then
      network_connectivity:set_markup("Connected")
    else
      network_connectivity:set_markup("Not Connected")
    end
  end
}

local system_information_collapse_icon = text("")
local system_information_title =
  widget_info(
  icon("", 10, true, true),
  text(markup("#FFFFFF", theme_pad(3) .. "System")),
  system_information_collapse_icon
)

local system_information_collapse =
  wibox.container.constraint(
  wibox.container.background(
    wibox.widget {
      layout = wibox.layout.fixed.vertical,
      uptime_widget,
      cpu,
      mem,
      fs_root_used,
      fs_home_used
    },
    "#1c1c1c"
  ),
  "exact",
  450,
  0
)

system_information_title:buttons(
  awful.util.table.join(
    awful.button(
      {},
      1,
      function()
        if system_information_collapse.height == 0 then
          system_information_collapse.height = 190
          system_information_collapse_icon:set_markup("")
        elseif system_information_collapse.height == 140 then
          system_information_collapse.height = 0
          system_information_collapse_icon:set_markup("")
        end
      end
    )
  )
)

local system_information =
  wibox.widget {
  layout = wibox.layout.fixed.vertical,
  system_information_title,
  system_information_collapse
}

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
        sound_output_text:set_markup(markup("#FFFFFF", theme_pad(3) .. "Output: " .. (text == "" and "Local" or text)))
      end
    )
  end
)
awful.spawn.easy_async(
  string.format("bash %s/bin/sound_toggle", os.getenv("HOME")),
  function(stdout)
    local text = string.gsub(stdout, "^%s*(.-)%s*$", "%1")
    sound_output_text:set_markup(markup("#FFFFFF", theme_pad(3) .. "Output: " .. (text == "" and "Local" or text)))
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

if awful.util.theme_functions.set_github_listener then
  awful.util.theme_functions.set_github_listener(
    function(text)
      github_notifications:set_markup(markup("#FFFFFF", theme_pad(3) .. (text == "" and "0" or text)))
    end
  )
end

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
local toggl_syna_reload = icon("", 10, true, true)
local toggl_syna =
  widget_button(
  widget_info(toggl_syna_icon, toggl_syna_text, wibox.widget {toggl_syna_active, wibox.container.margin(toggl_syna_reload, 10), layout = wibox.layout.fixed.horizontal}),
  function()
    awful.spawn.with_shell("google-chrome-beta https://www.toggl.com/app/reports/summary/2623050")
  end
)

local prev_toggl_syna_text = ""
function fetch_toggle_syna()
  awful.widget.watch(
    string.format("sh %s/bin/toggl-report diff", os.getenv("HOME")),
    60,
    function(widget, stdout)
      local text = string.gsub(stdout, "^%s*(.-)%s*$", "%1")
      if text ~= "m" then
        toggl_syna_active:set_markup(markup("#FFFFFF", theme_pad(3) .. "-" .. text))
        prev_toggl_syna_text = text
      elseif prev_toggl_syna_text == "" then
        toggl_syna_active:set_markup(markup("#FFFFFF", theme_pad(3) .. "Failed"))
      end
    end
  )
end
fetch_toggle_syna()
toggl_syna_reload:buttons(my_table.join(awful.button({}, 1, fetch_toggle_syna)))

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

local clipboard_buttons =
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

-- local clipboard_widget_template = widget_info(text(), text(string.gsub(item.input, "^%s*(.-)%s*$", "%1")), text())

local clipboard_timer = gears.timer({timeout = 5})
local clipboard_items_widget =
  wibox.widget {
  layout = wibox.layout.fixed.vertical
}
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

      clipboard_items_widget:reset()
      for _, item in ipairs(resp_json) do
        clipboard_items_widget:add(w)
      end
    end
  end
)

-- clipboard_timer:start()
-- clipboard_timer:emit_signal("timeout")

local power_button = background(margin(title(icon("", 12, true, true, true) .. " Power"), 40, 40, 20, 20), "#1c1c1c")

power_button:connect_signal(
  "mouse::enter",
  function()
    power_button.bg = awful.util.theme_functions.widget_bg
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

local widgets = {
  {
    {
      layout = wibox.layout.fixed.vertical,
      margin(pad(0), 0, 0, 32),
      margin(time_text, 40, 40),
      margin(date_text, 40, 40, 0, 20),
      background(margin(title("Work Information"), 40, 40, 10, 10), "#1c1c1c"),
      margin(pad(0), 0, 0, 0, 16),
      toggl,
      github,
      toggl_reports,
      toggl_syna,
      margin(pad(0), 0, 0, 0, 32),
      background(margin(title("Information"), 40, 40, 10, 10), "#1c1c1c"),
      margin(pad(0), 0, 0, 0, 16),
      packages,
      network,
      system_information,
      -- background(margin(text('hello'), 40, 40, 10, 10), "#ff0000"),
      margin(pad(0), 0, 0, 0, 32),
      -- background(margin(title("Feed"), 40, 40, 10, 10), '#050505'),
      -- margin(pad(0), 0, 0, 0, 16),
      -- feedly,
      -- margin(pad(0), 0, 0, 0, 32),
      background(margin(title("Settings"), 40, 40, 10, 10), "#1c1c1c"),
      margin(pad(0), 0, 0, 0, 16),
      sound_output
      -- clipboard
    },
    nil,
    power_button,
    layout = wibox.layout.align.vertical
  },
  widget = wibox.container.background,
  bg = awful.util.theme_functions.bg_panel
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
        -- beautiful.statusbar(
        --   s,
        --   false,
        --   close_button,
        --   gears.color(
        --     {
        --       type = "linear",
        --       from = {20, 0},
        --       to = {70, 0},
        --       stops = {{0, awful.util.theme_functions.bg_panel}, {1, "#050505"}}
        --     }
        --   )
        -- )
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
      -- beautiful.statusbar(
      --   s,
      --   false,
      --   close_button,
      --   gears.color(
      --     {
      --       type = "linear",
      --       from = {20, 0},
      --       to = {70, 0},
      --       stops = {{0, awful.util.theme_functions.bg_panel}, {1, "#050505"}}
      --     }
      --   )
      -- )
    }
  )
end
