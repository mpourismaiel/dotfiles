local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local markup = require("lain.util.markup")
local helpers = require("utils.helpers")
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("utils.animation").createAnimObject

local pad = helpers.pad
local icon = helpers.icon
local font = helpers.font
local text = wibox.widget.textbox
local margin = wibox.container.margin
local background = wibox.container.background
local constraint = wibox.container.constraint
local place = wibox.container.place

local workstation = {
  keygrabber = nil,
  widget = wibox {
    visible = false
  }
}

function workstation_show()
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height

  workstation.widget =
    wibox {
    width = screen_width,
    height = screen_height,
    visible = true,
    x = 0,
    y = 0,
    bg = beautiful.wibar_bg .. "ff",
    type = "desktop",
    ontop = true,
    opacity = 0,
    screen = s
  }
  createAnimObject(0.6, workstation.widget, {opacity = 1}, "outCubic")

  workstation.setup()

  workstation.keygrabber =
    awful.keygrabber.run(
    function(_, key, event)
      if event == "release" then
        return
      end
      if key == "Escape" or key == "q" or key == "x" then
        workstation_hide()
      end
    end
  )
end

function workstation_hide()
  createAnimObject(
    0.6,
    workstation.widget,
    {opacity = 0},
    "outCubic",
    function()
      workstation.widget.visible = false
    end
  )
  awful.keygrabber.stop(workstation.keygrabber)
end

local separator =
  place(margin(text(markup(beautiful.widget_bg .. "99", font("/", "FireCode Bold 100"))), 30, 30), "left", "top")
local title = function(w)
  return margin((place(text(markup(beautiful.widget_bg, font(w, "FireCode Bold 100"))), "left", "top")), 200, 0)
end

local button = function(w, action)
  w:buttons(gears.table.join(awful.button({}, 1, action)))

  local old_cursor = nil

  w:connect_signal(
    "mouse::enter",
    function()
      w.cursor = "cross"
    end
  )

  w:connect_signal(
    "mouse::leave",
    function()
      if old_cursor ~= nil then
        w.cursor = old_cursor
      end
    end
  )

  return w
end

local back_button =
  button(margin(text(markup(beautiful.widget_bg, icon("", 60, true, true, true))), 200, 0, 20), workstation_hide)

local environment = function(w, action)
  return button(margin(text(font(w, "FireCode Bold 60")), 0, 0, 20, 20), action)
end

function workstation.setup()
  workstation.widget:setup {
    layout = wibox.layout.fixed.vertical,
    back_button,
    margin(
      wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        title("Work"),
        separator,
        wibox.widget {
          layout = wibox.layout.fixed.vertical,
          environment("Okkur Labs"),
          environment("Freelancer"),
          environment("Fun")
        }
      },
      0,
      0,
      100,
      50
    ),
    {
      layout = wibox.layout.fixed.horizontal,
      title("Entertainment"),
      separator,
      {
        layout = wibox.layout.fixed.vertical,
        environment("Movies"),
        environment("Youtube"),
        environment("Surfing")
      }
    }
  }
end
