local setmetatable = setmetatable
local os = os
local wtext = require("lib.widgets.text")
local timer = require("gears.timer")
local gtable = require("gears.table")
local glib = require("lgi").GLib
local DateTime = glib.DateTime
local TimeZone = glib.TimeZone

local textclock = {mt = {}}

local DateTime_new_now = DateTime.new_now

-- When $SOURCE_DATE_EPOCH and $SOURCE_DIRECTORY are both set, then this code is
-- most likely being run by the test runner. Ensure reproducible dates.
local source_date_epoch = tonumber(os.getenv("SOURCE_DATE_EPOCH"))
if source_date_epoch and os.getenv("SOURCE_DIRECTORY") then
  DateTime_new_now = function()
    return DateTime.new_from_unix_utc(source_date_epoch)
  end
end

function textclock:set_format(format)
  self._private.format = format
  self:force_update()
end

function textclock:get_format()
  return self._private.format
end

function textclock:set_timezone(tzid)
  self._private.tzid = tzid
  self._private.timezone = tzid and TimeZone.new(tzid)
  self:force_update()
end

function textclock:get_timezone()
  return self._private.tzid
end

function textclock:set_refresh(refresh)
  self._private.refresh = refresh or self._private.refresh
  self:force_update()
end

function textclock:get_refresh()
  return self._private.refresh
end

function textclock:force_update()
  self._timer:emit_signal("timeout")
end

local function calc_timeout(real_timeout)
  return real_timeout - os.time() % real_timeout
end

local function new(format, refresh, tzid)
  local w = wtext()
  gtable.crush(w, textclock, true)

  w._private.format = format or " %a %b %d, %H:%M "
  w._private.refresh = refresh or 60
  w._private.tzid = tzid
  w._private.timezone = tzid and TimeZone.new(tzid)

  function w._private.textclock_update_cb()
    local str = DateTime_new_now(w._private.timezone or TimeZone.new_local()):format(w._private.format)
    w:set_text(str)
    w._timer.timeout = calc_timeout(w._private.refresh)
    w._timer:again()
    return true
  end

  w._timer = timer.weak_start_new(refresh, w._private.textclock_update_cb)
  w:force_update()
  return w
end

function textclock.mt:__call(...)
  return new(...)
end

return setmetatable(textclock, textclock.mt)
