local tween = require("utils.tween")
local gears = require("gears")
require "logging.file"
local logger = logging.file("/tmp/log.log")

function createAnimObject(duration, subject, target, easing, end_callback, delay)
  -- check if animation is running
  if subject.anim then
    subject:emit_signal("interrupt", subject)
  end
  -- create timer at 60 fps
  subject.timer = gears.timer({timeout = 0.0167})
  -- create self-destructing animation-stop callback function
  cback = function(subject)
    if subject.timer and subject.timer.started then
      subject.timer:stop()
    end
    subject:disconnect_signal("interrupt", cback)
  end
  -- create tween
  local twob = tween.new(duration, subject, target, easing)
  -- create timeout signal
  subject.dt = 0
  subject.timer:connect_signal(
    "timeout",
    function()
      subject.dt = subject.dt + 0.0167
      local complete = twob:update(subject.dt)
      subject:emit_signal("widget::redraw_needed")
      if complete then
        subject.timer:stop()
        cback(subject)
        subject.anim = false
        if end_callback then
          end_callback()
        end
      end
    end
  )
  -- start animation
  subject:connect_signal("interrupt", cback)
  subject.anim = true
  if delay ~= nil then
    gears.timer {
      autostart = true,
      single_shot = true,
      timeout = delay,
      callback = function()
        subject.timer:start()
      end
    }
  else
    subject.timer:start()
  end
end

return {createAnimObject = createAnimObject}
