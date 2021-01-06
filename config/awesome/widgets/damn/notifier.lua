local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local wibox = require("wibox")
local lain = require("lain")
local system_info = require("widgets.damn.system-info")
local markup = require("lain.util.markup")
local createAnimObject = require("utils.animation").createAnimObject
require "logging.file"
local logger = logging.file("/tmp/log.log")

local textbox = wibox.widget.textbox
local constraint = wibox.container.constraint
local margin = wibox.container.margin
local place = wibox.container.place
local background = wibox.container.background
local layout = wibox.layout
local markup = lain.util.markup

local notfier = {mt = {}}

function notfier.new()
  local icon = wibox.widget.imagebox()
  local title = wibox.widget.textbox()
  local text = wibox.widget.textbox()
  title:set_markup(markup("#ffffff", markup.font("Noto Sans Bold 10", "Hello fuckedhead")))
  text:set_markup(
    markup("#ffffff", markup.font("Noto Sans 10", "This is your friend\nYou suck This is your friend\nYou suck"))
  )

  local extra_info_constraint =
    constraint(
    place(
      wibox.widget {
        layout = wibox.layout.fixed.vertical,
        margin(title, 10, 10, 10, 0),
        margin(text, 10, 10, 5, 10)
      },
      "left",
      "top"
    ),
    "exact",
    260,
    90
  )

  local extra_info = background(extra_info_constraint, awful.util.theme.separator)
  extra_info.opacity = 0
  extra_info_constraint.width = 0
  extra_info_constraint.height = 0

  local component =
    background(
    margin(
      wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        background(
          constraint(place(margin(icon, 10, 10, 10, 10), "left", "top"), "exact", 50, 50),
          awful.util.theme.separator
        ),
        extra_info
      },
      2,
      2,
      2,
      2
    ),
    awful.util.theme.primary
  )

  local popup =
    awful.popup {
    ontop = true,
    visible = false,
    shape = gears.shape.rectangle,
    bg = "#00000000",
    screen = awful.screen.focused(),
    widget = component
  }

  awful.placement.bottom_right(popup, {margins = {parent = awful.screen.focused(), right = 60, bottom = 110}})

  -- popup:connect_signal(
  --   "mouse::enter",
  --   function()
  --     extra_info.opacity = 1
  --     extra_info_constraint.width = 260
  --     extra_info_constraint.height = 90
  --   end
  -- )

  -- popup:connect_signal(
  --   "mouse::leave",
  --   function()
  --     extra_info.opacity = 0
  --     extra_info_constraint.width = 0
  --     extra_info_constraint.height = 0
  --   end
  -- )

  naughty.connect_signal(
    "request::display",
    function(notification, args)
      if notification.icon then
        icon:set_image(notification.icon)
        title:set_markup(markup("#ffffff", markup.font(awful.util.theme.font_base .. " Bold 10", notification.title)))
        text:set_markup(markup("#ffffff", markup.font(awful.util.theme.font_base .. " 10", notification.text)))
        popup.visible = true
        extra_info.opacity = 0
        extra_info_constraint.width = 0
        extra_info_constraint.height = 0

        gears.timer {
          timeout = 3,
          single_shot = true,
          autostart = true,
          callback = function()
            popup.visible = false
          end
        }
      end
    end
  )

  return component.widget
end

function notfier.mt:__call(...)
  return notfier.new(...)
end

return setmetatable(notfier, notfier.mt)
