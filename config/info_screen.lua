local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local markup = require("lain.util.markup")
local helpers = require("helpers")
local pad = helpers.pad
local keygrabber = require("awful.keygrabber")

local info_screen
local info_screen_grabber

function info_screen_show()
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
  info_screen = wibox({x = 0, y = 0, visible = true, ontop = true, screen = s, type = "dock", height = screen_height, width = screen_width})
  info_screen_grabber = awful.keygrabber.run(
    function(_, key, event)
      if event == 'release' then return end
      if key == 'Escape' or key == 'q' or key == 'x' then
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

local username = os.getenv("USER")
local info_text = wibox.widget.textbox("Hello, " .. username:sub(1, 1):upper() .. username:sub(2) .. ". What's up?")
info_text.font = beautiful.info_screen_font or "sans 50"
info_text_widget = wibox.container.margin(info_text, 0, 0, 0, 50)

local github_info_text = wibox.widget.textbox("Github")
github_info_text.font = beautiful.info_screen_widget_font or "sans 30"
github_info_text_widget = wibox.container.margin(github_info_text, 0, 0, 0, 10)

local github_info_widget = {
  github_info_text_widget,
  layout = wibox.layout.fixed.vertical
}

local time_text = wibox.widget.textclock("%Y-%m-%e %H:%M")
time_text.font = beautiful.info_screen_widget_font or "sans 30"
local time_widget = wibox.container.margin(time_text, 0, 0, 0, 10)
function info_screen_setup()
  info_screen:setup {
    pad(0),
    {
      {
        pad(0),
        info_text_widget,
        pad(0),
        expand = "none",
        layout = wibox.layout.align.horizontal
      },
      {
        github_info_widget,
        time_widget,
        layout = wibox.layout.fixed.horizontal
      },
      layout = wibox.layout.fixed.vertical
    },
    pad(0),
    expand = "none",
    layout = wibox.layout.align.vertical
  }
end
