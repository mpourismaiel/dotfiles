local animation_library = require("awesome-AnimationFramework.Animation")

local animation = {mt = {}}

function animation.new(args)
  if not args.targets then
    error("No targets specified")
  end

  local animations = {}
  for k, v in pairs(args.targets) do
    animations[k] =
      animation_library {
      subject = args.subject,
      target = v,
      easing = args.easing,
      duration = args.duration,
      delay = args.delay,
      signals = args.signals
    }
  end

  return animations
end

function animation.mt:__call(...)
  return animation.new(...)
end

return setmetatable(animation, animation.mt)
