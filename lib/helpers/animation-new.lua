-----------------
-- Modified version of awesome-AnimationFramework by Aire-One (Aire-One@github.com ; Aire-One@gitlab.com)
-----------------

local gears = require("gears")
local glib = require("lgi").GLib
local console = require("lib.helpers.console")

local tween = require("tween-lua/tween")

local time_conversion = {
  micro_to_milli = function(micro)
    return micro / 1000
  end,
  second_to_micro = function(sec)
    return sec * 1000000
  end,
  second_to_milli = function(sec)
    return sec * 1000
  end
}

local EASING_FUNCTIONS = {
  linear = "linear",
  inQuad = "inQuad",
  outQuad = "outQuad",
  inOutQuad = "inOutQuad",
  outInQuad = "outInQuad",
  inCubic = "inCubic",
  outCubic = "outCubic",
  inOutCubic = "inOutCubic",
  outInCubic = "outInCubic",
  inQuart = "inQuart",
  outQuart = "outQuart",
  inOutQuart = "inOutQuart",
  outInQuart = "outInQuart",
  inQuint = "inQuint",
  outQuint = "outQuint",
  inOutQuint = "inOutQuint",
  outInQuint = "outInQuint",
  inSine = "inSine",
  outSine = "outSine",
  inOutSine = "inOutSine",
  outInSine = "outInSine",
  inExpo = "inExpo",
  outExpo = "outExpo",
  inOutExpo = "inOutExpo",
  outInExpo = "outInExpo",
  inCirc = "inCirc",
  outCirc = "outCirc",
  inOutCirc = "inOutCirc",
  outInCirc = "outInCirc",
  inElastic = "inElastic",
  outElastic = "outElastic",
  inOutElastic = "inOutElastic",
  outInElastic = "outInElastic",
  inBack = "inBack",
  outBack = "outBack",
  inOutBack = "inOutBack",
  outInBack = "outInBack",
  inBounce = "inBounce",
  outBounce = "outBounce",
  inOutBounce = "inOutBounce",
  outInBounce = "outInBounce"
}

local Animation = {
  ANIMATION_FRAME_DELAY = 16.7,
  easing = EASING_FUNCTIONS
}
local mt = {}

function Animation:startAnimation(name, args)
  local wp = self._private
  local animation = wp.animations[name]
  if animation == nil then
    return
  end

  if args and args.from_start then
    wp.subject = gears.table.clone(wp.initialSubject)
  end

  glib.timeout_add(
    glib.PRIORITY_DEFAULT,
    0,
    function()
      animation.last_elapsed = glib.get_monotonic_time()
      animation.tween = tween.new(animation.duration, wp.subject, animation.target, animation.easing)
      animation.timer = glib.timeout_add(glib.PRIORITY_DEFAULT, self.ANIMATION_FRAME_DELAY, animation.timer_function)

      if args and args.callback then
        args.callback(
          {
            subject = wp.subject,
            target = animation.target,
            easing = animation.easing,
            duration = animation.duration
          }
        )
      end

      for _, fn in pairs(wp.on_start_listeners) do
        fn(
          name,
          {
            subject = wp.subject,
            target = animation.target,
            easing = animation.easing,
            duration = animation.duration
          }
        )
      end

      return false
    end
  )

  return self
end

function Animation:stopAnimation(name, args)
  local wp = self._private
  local animation = wp.animations[name]
  if animation == nil then
    return
  end

  if args and args.to_start then
    wp.subject = gears.table.clone(wp.initialSubject)
  end

  animation.tween = nil
  if type(animation.timer) == "table" and animation.timer.stared then
    glib.source_remove(animation.timer)
    animation.timer = nil

    for _, fn in pairs(wp.on_stop_listeners) do
      fn(
        name,
        {
          subject = wp.subject,
          target = animation.target,
          easing = animation.easing,
          duration = animation.duration
        }
      )
    end
  end

  return self
end

function Animation:add(name, args)
  local wp = self._private
  local animation = {
    target = args.target,
    duration = args.duration and time_conversion.second_to_micro(args.duration) or wp.duration,
    easing = args.easing or wp.easing,
    tween = nil,
    last_elapsed = 0,
    timer = nil
  }

  animation.timer_function = function()
    if animation.tween == nil then
      return false
    end

    local time = glib.get_monotonic_time()
    local delta = time - animation.last_elapsed
    animation.last_elapsed = time

    local completed = animation.tween:update(delta)

    for _, fn in pairs(wp.on_update_listeners) do
      fn(
        name,
        wp.subject,
        time_conversion.micro_to_milli(delta),
        {
          subject = wp.subject,
          target = animation.target,
          easing = animation.easing,
          duration = animation.duration
        }
      )
    end

    if completed then
      for _, fn in pairs(wp.on_finish_listeners) do
        fn(
          name,
          {
            subject = wp.subject,
            target = animation.target,
            easing = animation.easing,
            duration = animation.duration
          }
        )
      end
      return false
    end

    return true
  end

  wp.animations[name] = animation

  return self
end

function Animation:change(name, args)
  local wp = self._private
  local animation = wp.animations[name]
  if animation == nil then
    return
  end

  animation.target = args.target or animation.target
  animation.duration = args.duration and time_conversion.second_to_micro(args.duration) or animation.duration
  animation.easing = args.easing or animation.easing

  return self
end

function Animation:remove(name)
  local wp = self._private
  wp.animations[name] = nil
  return self
end

function Animation:updateSubject(subject)
  local wp = self._private
  wp.subject = subject
  wp.initialSubject = gears.table.clone(subject)
  return self
end

function Animation:updateDefaults(args)
  local wp = self._private
  wp.duration = args.duration and time_conversion.second_to_micro(args.duration) or wp.duration
  wp.easing = args.easing or wp.easing
  return self
end

function Animation:onStart(fn)
  local wp = self._private
  table.insert(wp.on_start_listeners, fn)
  return self
end

function Animation:onUpdate(fn)
  local wp = self._private
  table.insert(wp.on_update_listeners, fn)
  return self
end

function Animation:onFinish(fn)
  local wp = self._private
  table.insert(wp.on_finish_listeners, fn)
  return self
end

function Animation:onStop(fn)
  local wp = self._private
  table.insert(wp.on_stop_listeners, fn)
  return self
end

local function new(args)
  local self = {_private = {}}
  gears.table.crush(self, Animation)

  local args = args or {}
  local wp = self._private
  self:updateSubject(args.subject)
  if wp.subject == nil then
    console():with_trace():title("Animation"):log("subject is nil")
  end

  wp.duration = time_conversion.second_to_micro(args.duration or 0.2)
  wp.easing = args.easing or Animation.easing.linear

  wp.animations = {}
  wp.on_start_listeners = {}
  wp.on_update_listeners = {}
  wp.on_finish_listeners = {}
  wp.on_stop_listeners = {}

  return self
end

mt.__call = function(self, ...)
  return new(...)
end

return setmetatable(Animation, mt)
