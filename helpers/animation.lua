local animation_library = require("awesome-AnimationFramework.Animation")

local animation = {mt = {}}

function animation.new(args)
  if not args.targets then
    error("No targets specified")
  end

  local animations = {}
  for k, v in pairs(args.targets) do
    local a =
      animation_library {
      subject = args.subject,
      target = v,
      easing = args.easing,
      duration = args.duration,
      delay = args.delay,
      signals = args.signals
    }

    a:connect_signal(
      "anim::animation_started",
      function(s)
        s.animating = true
      end
    )
    a:connect_signal(
      "anim::animation_stopped",
      function(s)
        s.animating = false
      end
    )
    a:connect_signal(
      "anim::animation_finished",
      function(s)
        s.animating = false
      end
    )
    animations[k] = a
  end

  return animations
end

function animation.mt:__call(...)
  return animation.new(...)
end

return setmetatable(animation, animation.mt)
