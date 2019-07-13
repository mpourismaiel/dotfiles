local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local lain = require("lain")
local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12");
local secrets = require("secrets")
local markup = require("lain.util.markup")
local helpers = require("helpers")
local my_table = awful.util.table or gears.table
local pad = helpers.pad
local theme_pad = beautiful.pad_fn
local keygrabber = require("awful.keygrabber")
local layout_indicator = require("keyboard-layout-indicator")

local margin = wibox.container.margin
local background = wibox.container.background
local text = wibox.widget.textbox
local textclock = wibox.widget.textclock
local place = wibox.container.place
local constraint = wibox.container.constraint
local imagebox = wibox.widget.imagebox

local icon = function(ic, size, solid, fontawesome, string)
  if string == true then
    return beautiful.icon_fn(ic, size, solid, fontawesome)
  end

  return text(markup("#ffffffcc", beautiful.icon_fn(ic, size, solid, fontawesome)))
end
local info_image = function(icon)
  return margin(place(constraint(imagebox(beautiful.icon_dir .. "/" .. icon), 'max', 24, 24)), 0, 0, 0, 10)
end
local font = beautiful.font_fn

local lock_image = imagebox(beautiful.icon_dir .. '/lock.svg')
local lock_icon = background(margin(wibox.widget {
  layout = wibox.layout.align.horizontal,
  constraint(lock_image, 'max', 50, 50)
}, 30, 30, 20, 20), "#000000", function(cr, width, height)
  gears.shape.rounded_rect(cr, width, height, 8)
end)

local info_screen = wibox {
  visible = false,
  screen = nil,
}

local press_indicator = function()
  if lock_icon.bg == "#000000" then
    lock_icon.bg = "#ffffff"
    -- lock_image.image = beautiful.icon_dir .. '/lock-press.svg'
  else
    lock_icon.bg = "#000000"
    -- lock_image.image = beautiful.icon_dir .. '/lock.svg'
  end
end

function reset_indicator()
  lock_image.image = beautiful.icon_dir .. '/lock.svg'
  lock_icon.bg = "#000000"
end

local reset_indicator_timer = gears.timer {
  timeout = 2,
  callback = reset_indicator
}

local has_extra_char = true

local lock_screen_grabber = awful.keygrabber {
  start_callback = function()
    has_extra_char = true
    reset_indicator()
  end,
}

function authenticate()
  local sequence = lock_screen_grabber.sequence
  local username = os.getenv("USER")

  reset_indicator_timer:stop()

  -- lock_screen_hide()
  if string.len(sequence) <= 1 then
    lock_screen_grabber.sequence = ""
    has_extra_char = false
    return
  end

  local password = string.sub(sequence, has_extra_char and 2 or 1)
  local cmd = os.getenv('HOME') .. '/bin/auth ' .. username .. ' ' .. password

  lock_icon.bg = "#ffffff44"
  awful.spawn.with_line_callback(cmd, {
    exit = function(_, code)
      if code == 0 then
        lock_screen_grabber:stop()
        lock_screen_hide()
      else
        lock_screen_grabber.sequence = ""
        has_extra_char = false
        reset_indicator_timer:again()
        lock_icon.bg = "#000000"
      end
    end
  })
end

lock_screen_grabber:add_keybinding({}, 'Return', authenticate)
lock_screen_grabber:add_keybinding({}, 'Escape', function()
  lock_screen_grabber.sequence = ""
  has_extra_char = false
end)
lock_screen_grabber:add_keybinding({ awful.util.altkey }, "m", awful.util.myaudio.mute)

lock_screen_grabber.keyreleased_callback = function()
  reset_indicator_timer:again()
  press_indicator()

  if (lock_screen_grabber.sequence == "") then
    has_extra_char = false
  end
end

function lock_screen_show()
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
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
      width = screen_width,
      bgimage = os.getenv("HOME") .. "/Pictures/Wallpapers/jonah_dinges_elephant.jpg"
    }
  )
  lock_screen_grabber:start()

  lock_screen_setup()
end

function lock_screen_hide()
  info_screen.visible = false
end

local time_text = textclock(markup("#000000", markup.font("SourceCodePro Semibold 110", "%H:%M")))
local date_text = textclock(markup("#000000", markup.font("SourceCodePro 21", "%a\n%B %d\n%Y")))

local time = wibox.widget {
  layout = wibox.layout.stack,
  margin(background(margin(pad(0), 400, 0, 137), "#ffffff", function(cr, width, height)
    gears.shape.rounded_rect(cr, width, 137, 8)
  end), 0, 0, 40),
  {
    layout = wibox.layout.align.horizontal,
    margin(wibox.widget {
      layout = wibox.layout.align.horizontal,
      time_text,
      margin(date_text, 10, 0, 10)
    }, 25, 25, 10, 0)
  }
}

local battery_text = lain.widget.bat(
  {
    notify = "off",
    settings = function()
      widget:set_markup(markup.font("SourceCodePro 12", bat_now.perc .. "%"))
    end
  }
).widget

local battery = wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("battery.svg"),
  place(battery_text)
}

local keyboard_layout = wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("keyboard.svg"),
  place(layout_indicator:new({ markup = function(text)
    markup("#FFFFFF", markup.font("SourceCodePro 12", string.upper(text)))
  end }))
}

local github_notification_count = text(markup("#FFFFFF", markup.font("SourceCodePro 12", "...")))

beautiful.set_github_listener(function(text)
  github_notification_count:set_markup(markup("#FFFFFF", markup.font("SourceCodePro 12", text)))
end)

local github_notifications = wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("github.svg"),
  place(github_notification_count)
}

local cpu = lain.widget.cpu({
  settings = function() widget:set_markup(markup.font("SourceCodePro 12", cpu_now.usage .. "%")) end
})

local cpu_info = wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("cpu.svg"),
  place(cpu.widget)
}

local mem = lain.widget.mem({
  timeout = 1,
  settings = function() widget:set_markup(markup.font("SourceCodePro 12", mem_now.perc .. "%")) end
})

local mem_info = wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("ram.svg"),
  place(mem.widget)
}

local audio_volume = lain.widget.alsa(
  {
    settings = function()
      local vlevel = ""
      if volume_now.status == "on" then
        vlevel = markup.font("SourceCodePro 12", volume_now.level .. "%")
      else
        vlevel = markup.font("SourceCodePro 12", "0%")
      end
      widget:set_markup(markup("#FFFFFF", vlevel))
    end
  }
).widget

local audio = wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("speaker.svg"),
  place(audio_volume)
}

audio:connect_signal("button::press", awful.util.myaudio.mute)

local widgets = {
  layout = wibox.layout.flex.vertical,
  background(wibox.widget {
    layout = wibox.layout.flex.horizontal,
    place(
      wibox.widget {
        layout = wibox.layout.align.vertical,
        time,
        {
          layout = wibox.layout.align.horizontal,
          margin(lock_icon, 0, 10),
          background(margin(wibox.widget {
            layout = wibox.layout.flex.horizontal,
            battery,
            keyboard_layout,
            github_notifications,
            audio,
            cpu_info,
            mem_info
          }, 40, 40, 20, 20), "#000000", function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, 8)
          end),
        }
      },
      "center",
      "center"
    )
  }, "#000000b3")
}

function lock_screen_setup()
  info_screen:setup(widgets)
end
