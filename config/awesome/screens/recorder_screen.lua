local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local markup = require("lain.util.markup")
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("utils.animation").createAnimObject

local margin = wibox.container.margin
local place = wibox.container.place
local background = wibox.container.background
local constraint = wibox.container.constraint
local textbox = wibox.widget.textbox

local backdrop = wibox {type = "dock", x = 0, y = 0}
local recorder_screen_grabber

local isMoving = {
  rect = false
}

function createPoint(cornerSize, pointName)
  local point =
    constraint(
    background(
      margin(background(textbox(""), "#ffffff66"), 1, 1, 1, 1),
      awful.util.theme.separator .. "66",
      gears.shape.circle
    ),
    "exact",
    cornerSize,
    cornerSize
  )
  return point
end

function setButtons(widgets, widget, pointName)
  widget:buttons(
    gears.table.join(
      awful.button(
        {},
        1,
        function()
          isMoving[pointName] = true
        end,
        function()
          isMoving[pointName] = false
          calculateRect(widgets, pointName, mouse.coords())
        end
      )
    )
  )
end

function setSize(s, cornerSize, x, y, w, h, widgets)
  widgets.rectTop.point = {x = 0, y = 0}
  widgets.rectTop.width = s.geometry.width
  widgets.rectTop.height = y
  widgets.rectLeft.point = {x = 0, y = y}
  widgets.rectLeft.width = x
  widgets.rectLeft.height = h
  widgets.rectBottom.point = {x = 0, y = y + h}
  widgets.rectBottom.width = s.geometry.width
  widgets.rectBottom.height = s.geometry.height - y - h
  widgets.rectRight.point = {x = x + w, y = y}
  widgets.rectRight.width = s.geometry.width - x - w
  widgets.rectRight.height = h
  widgets.pointx0y0.point = {x = x - (cornerSize / 2), y = y - (cornerSize / 2)}
  widgets.pointx1y0.point = {x = w + x - (cornerSize / 2), y = y - (cornerSize / 2)}
  widgets.pointx0y1.point = {x = x - (cornerSize / 2), y = h + y - (cornerSize / 2)}
  widgets.pointx1y1.point = {x = w + x - (cornerSize / 2), y = h + y - (cornerSize / 2)}
end

function calculateRect(widgets, currentPoint, mouse)
  local s = awful.screen.focused()

  local x0, y0, x1, y1
  if currentPoint == "pointx0y0" then
    x0 = mouse.x
    x1 = widgets.pointx1y1.point.x
    y0 = mouse.y
    y1 = widgets.pointx1y1.point.y
  elseif currentPoint == "pointx0y1" then
    x0 = mouse.x
    x1 = widgets.pointx1y0.point.x
    y0 = widgets.pointx0y0.point.y
    y1 = mouse.y
  elseif currentPoint == "pointx1y0" then
    x0 = widgets.pointx0y1.point.x
    x1 = mouse.x
    y0 = mouse.y
    y1 = widgets.pointx0y1.point.x
  elseif currentPoint == "pointx1y1" then
    x0 = widgets.pointx0y1.point.x
    x1 = mouse.x
    y0 = widgets.pointx0y0.point.y
    y1 = mouse.y
  else
    return
  end

  if x0 > x1 then
    local tmp = x1
    x1 = x0
    x0 = tmp
  end
  if y0 > y1 then
    local tmp = y1
    y1 = y0
    y0 = tmp
  end

  local x = x0
  local y = y0
  local w = x1 - x0
  local h = y1 - y0

  widgets.pointx0y0.point.x = x0
  widgets.pointx0y0.point.y = y0
  widgets.pointx0y1.point.x = x0
  widgets.pointx0y1.point.y = y1
  widgets.pointx1y0.point.x = x1
  widgets.pointx1y0.point.y = y0
  widgets.pointx1y1.point.x = x1
  widgets.pointx1y1.point.y = y1
  widgets.rectTop.point.x = 0
  widgets.rectTop.point.y = 0
  widgets.rectTop.width = s.geometry.width
  widgets.rectTop.height = y
  widgets.rectLeft.point.x = 0
  widgets.rectLeft.point.y = y
  widgets.rectLeft.width = x
  widgets.rectLeft.height = h
  widgets.rectBottom.point.x = 0
  widgets.rectBottom.point.y = y + h
  widgets.rectBottom.width = s.geometry.width
  widgets.rectBottom.height = s.geometry.height - y - h
  widgets.rectRight.point.x = x + w
  widgets.rectRight.point.y = y
  widgets.rectRight.width = s.geometry.width - x - w
  widgets.rectRight.height = h

  backdrop:emit_signal("widget::redraw_needed")
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
      bg = "#00000000"
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
  local screen_height = s.geometry.height
  local screen_width = s.geometry.width

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

  local x = 200
  local y = 200
  local w = 200
  local h = 200

  local rectTop = constraint(background(margin(textbox(""), 1, 1, 1, 1), beautiful.wibar_bg .. "cc"), "exact", w, h)
  local rectLeft = constraint(background(margin(textbox(""), 1, 1, 1, 1), beautiful.wibar_bg .. "cc"), "exact", w, h)
  local rectBottom = constraint(background(margin(textbox(""), 1, 1, 1, 1), beautiful.wibar_bg .. "cc"), "exact", w, h)
  local rectRight = constraint(background(margin(textbox(""), 1, 1, 1, 1), beautiful.wibar_bg .. "cc"), "exact", w, h)

  local cornerSize = 12
  local record =
    background(
    margin(
      constraint(
        place(
          textbox(
            awful.util.theme_functions.icon_string(
              {icon = "", size = 16, font = "Font Awesome 5 Free", font_weight = "Solid"}
            )
          )
        ),
        "exact",
        48,
        48
      )
    ),
    awful.util.theme.primary,
    gears.shape.circle
  )

  local cancel =
    margin(
    constraint(
      place(
        textbox(
          markup(
            awful.util.theme.separator .. "cc",
            awful.util.theme_functions.icon_string(
              {icon = "", size = 14, font = "Font Awesome 5 Free", font_weight = "Light"}
            )
          )
        )
      ),
      "exact",
      36,
      36
    )
  )

  local settings =
    wibox.widget {
    layout = wibox.layout.fixed.horizontal,
    background(
      margin(
        {
          layout = wibox.layout.fixed.horizontal,
          margin(record, 10, 10),
          margin(cancel, 10, 10, 6, 6)
        },
        10,
        10,
        10,
        10
      ),
      "#ffffff",
      function(cr, w, h)
        return gears.shape.rounded_rect(cr, w, h, 10)
      end
    )
  }
  local pointx0y0 = createPoint(cornerSize, "pointx0y0")
  local pointx1y0 = createPoint(cornerSize, "pointx1y0")
  local pointx0y1 = createPoint(cornerSize, "pointx0y1")
  local pointx1y1 = createPoint(cornerSize, "pointx1y1")
  local widgets = {
    rectTop = rectTop,
    rectLeft = rectLeft,
    rectBottom = rectBottom,
    rectRight = rectRight,
    pointx0y0 = pointx0y0,
    pointx1y0 = pointx1y0,
    pointx0y1 = pointx0y1,
    pointx1y1 = pointx1y1,
    record = record,
    cancel = cancel,
    settings = settings
  }
  setButtons(widgets, pointx0y0, "pointx0y0")
  setButtons(widgets, pointx1y0, "pointx1y0")
  setButtons(widgets, pointx0y1, "pointx0y1")
  setButtons(widgets, pointx1y1, "pointx1y1")

  setSize(s, cornerSize, x, y, w, h, widgets)

  backdrop:connect_signal(
    "mouse::move",
    function()
      local isChangingRect = true
      if isMoving.pointx0y0 then
        calculateRect(widgets, "pointx0y0", mouse.coords())
      elseif isMoving.pointx1y0 then
        calculateRect(widgets, "pointx1y0", mouse.coords())
      elseif isMoving.pointx0y1 then
        calculateRect(widgets, "pointx0y1", mouse.coords())
      elseif isMoving.pointx1y1 then
        calculateRect(widgets, "pointx1y1", mouse.coords())
      else
        isChangingRect = false
      end
    end
  )

  record:buttons(
    gears.table.join(
      awful.button(
        {},
        1,
        function()
          local width = math.floor(widgets.pointx1y0.point.x - widgets.pointx0y0.point.x - 5)
          local height = math.floor(widgets.pointx0y1.point.y - widgets.pointx0y0.point.y - 5)
          if width - math.floor(width / 2) * 2 == 1 then
            width = width - 1
          end
          if height - math.floor(height / 2) * 2 == 1 then
            height = height - 1
          end
          local size =
            width ..
            ":" ..
              height ..
                ":" .. math.floor(widgets.pointx0y0.point.x + 6) .. ":" .. math.floor(widgets.pointx0y0.point.y + 6)

          recorder_screen_hide()
          local script =
            "ffmpeg -y -video_size " ..
            width ..
              "x" .. height .. " -r 30 -f x11grab -i :0 -vf crop=" .. size .. " -t 5 -pix_fmt yuv420p /tmp/test.mp4"
          awful.spawn.with_shell(script)
        end
      )
    )
  )

  cancel:buttons(gears.table.join(awful.button({}, 1, recorder_screen_hide)))
  settings.point = {x = (screen_width / 2) - 100, y = screen_height}

  createAnimObject(
    1,
    settings.point,
    {y = screen_height - 90},
    "outCubic",
    nil,
    0.2,
    backdrop,
    function()
      backdrop:setup(
        {
          layout = wibox.layout.manual,
          rectTop,
          rectLeft,
          rectBottom,
          rectRight,
          pointx0y0,
          pointx1y0,
          pointx0y1,
          pointx1y1,
          settings
        }
      )
    end
  )
end
-- recorder_screen_show()
