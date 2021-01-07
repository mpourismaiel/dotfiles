local tween = require("utils.tween")
local gears = require("gears")
local naughty = require("naughty")
require "logging.file"
local logger = logging.file("/tmp/log.log")

function createAnimObject(duration, subject, target, easing, end_callback, delay, widget, tween_callback)
  widget = widget and widget or subject
  -- check if animation is running
  if widget.anim then
    widget:emit_signal("interrupt", widget)
  end
  -- create timer at 60 fps
  widget.timer = gears.timer({timeout = 0.0167})
  -- create self-destructing animation-stop callback function
  cback = function(widget)
    if widget.timer and widget.timer.started then
      widget.timer:stop()
    end
    widget:disconnect_signal("interrupt", cback)
  end
  -- create tween
  local twob = tween.new(duration, subject, target, easing)
  -- create timeout signal
  widget.dt = 0
  widget.timer:connect_signal(
    "timeout",
    function()
      widget.dt = widget.dt + 0.0167
      local complete = twob:update(widget.dt)
      if tween_callback == nil then
        widget:emit_signal("widget::redraw_needed")
      else
        tween_callback()
      end
      if complete then
        widget.timer:stop()
        cback(widget)
        widget.anim = false
        if end_callback then
          end_callback()
        end
      end
    end
  )
  -- start animation
  widget:connect_signal("interrupt", cback)
  widget.anim = true
  if delay ~= nil then
    gears.timer {
      autostart = true,
      single_shot = true,
      timeout = delay,
      callback = function()
        widget.timer:start()
      end
    }
  else
    widget.timer:start()
  end
end

return {createAnimObject = createAnimObject}
