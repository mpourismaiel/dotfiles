local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local markup = require("lain.util.markup")
local keygrabber = require("awful.keygrabber")

local margin = wibox.container.margin
local place = wibox.container.place
local background = wibox.container.background
local constraint = wibox.container.constraint
local textbox = wibox.widget.textbox

local backdrop = wibox {type = "dock", x = 0, y = 0}
local recorder_screen_grabber

function createPoint(cornerSize)
  return constraint(
    background(margin(background(textbox(""), "#ffffff66"), 1, 1, 1, 1), awful.util.theme.separator .. "66"),
    "exact",
    cornerSize,
    cornerSize
  )
end

function setSize(cornerSize, x, y, w, h, widgets)
  widgets.rect.point = {x = x, y = y}
  widgets.pointx0y0.point = {x = x - (cornerSize / 2), y = y - (cornerSize / 2)}
  widgets.pointx1y0.point = {x = w + x - (cornerSize / 2), y = y - (cornerSize / 2)}
  widgets.pointx0y1.point = {x = x - (cornerSize / 2), y = h + y - (cornerSize / 2)}
  widgets.pointx1y1.point = {x = w + x - (cornerSize / 2), y = h + y - (cornerSize / 2)}
end

function recorder_screen_show()
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

  recorder_screen_setup(s)
end

function recorder_screen_hide()
  local s = awful.screen.focused()
  backdrop.visible = false
  awful.keygrabber.stop(recorder_screen_grabber)
end

function recorder_screen_setup(s)
  recorder_screen_grabber =
    awful.keygrabber.run(
    function(_, key, event)
      if event ~= "release" and (key == "Escape" or key == "q" or key == "x") then
        recorder_screen_hide()
        return
      end

      if event == "release" then
        return
      end
    end
  )

  local x = 0
  local y = 0
  local w = 200
  local h = 200
  local rect =
    constraint(
    background(margin(background(textbox(""), "#1f1f1f66"), 1, 1, 1, 1), awful.util.theme.separator .. "66"),
    "exact",
    w,
    h
  )

  local cornerSize = 8
  local pointx0y0 = createPoint(cornerSize)
  local pointx1y0 = createPoint(cornerSize)
  local pointx0y1 = createPoint(cornerSize)
  local pointx1y1 = createPoint(cornerSize)
  setSize(
    cornerSize,
    x,
    y,
    w,
    h,
    {
      rect = rect,
      pointx0y0 = pointx0y0,
      pointx1y0 = pointx1y0,
      pointx0y1 = pointx0y1,
      pointx1y1 = pointx1y1
    }
  )

  local debug = textbox("0,0")
  debug.point = {x = awful.screen.focused().geometry.width - 100, y = 20}
  local fucker = textbox("hmm")
  fucker.point = {x = awful.screen.focused().geometry.width - 100, y = 60}

  local isMoving = {
    rect = false
  }

  backdrop:connect_signal(
    "mouse::move",
    function()
      debug:set_text(mouse.coords().x .. "," .. mouse.coords().y)
      if isMoving.rect == true then
        fucker:set_text("Moving Rect")
      else
        fucker:set_text("hmm")
      end
    end
  )

  rect:buttons(
    gears.table.join(
      awful.button(
        {},
        1,
        function()
          isMoving.rect = true
        end,
        function()
          isMoving.rect = false
        end
      )
    )
  )

  backdrop:setup(
    {
      layout = wibox.layout.manual,
      debug,
      fucker,
      rect,
      pointx0y0,
      pointx1y0,
      pointx0y1,
      pointx1y1
    }
  )
end
-- recorder_screen_show()
