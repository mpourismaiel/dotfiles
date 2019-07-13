local tween = require("tween")

function createAnimObject(duration, subject, target, easing, end_callback)
  -- check if animation is running
  if subject.anim then subject:emit_signal("interrupt", subject) end
  -- create timer at 60 fps
  local t = timer({timeout = 0.0167})
  -- determine variable name to animate
  local val = nil
  for k,v in pairs(target) do -- only need to iterate once for our purposes
      val = k -- we will only watch one value per object
  end
  -- create self-destructing animation-stop callback function
  cback = function(subject)
      t:stop()
      subject:disconnect_signal("interrupt", cback)
  end
  -- create tween
  local twob = tween.new(duration, subject, target, easing)
  -- create timeout signal
  subject.dt = 0
  t:connect_signal("timeout", function()
      subject.dt = subject.dt + 0.0167
      twob:update(subject.dt)
      subject:emit_signal("widget::redraw_needed")
      if subject[val] == target[val] then
          t:stop()
          cback(subject)
          subject.anim = false
          if end_callback then end_callback() end
      end
  end)
  -- start animation
  subject:connect_signal("interrupt", cback)
  subject.anim = true
  t:start()
end

return createAnimObject
