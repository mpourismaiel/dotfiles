local textbox = require("wibox.widget.textbox")
local gtable = require("gears.table")
local beautiful = require("beautiful")
local markup = require("naughty.widget._markup").set_markup

local message = {}

function message:set_notification(notif)
  local old = self._private.notification[1]

  if old == notif then
    return
  end

  if old then
    old:disconnect_signal("property::message", self._private.message_changed_callback)
    old:disconnect_signal("property::fg", self._private.message_changed_callback)
  end

  markup(self, notif.message, notif.fg, "Inter regular 10")

  self._private.notification = setmetatable({notif}, {__mode = "v"})

  notif:connect_signal("property::message", self._private.message_changed_callback)
  notif:connect_signal("property::fg", self._private.message_changed_callback)
  self:emit_signal("property::notification", notif)
end

local function new(args)
  args = args or {}
  local tb = textbox()
  tb:set_wrap("word")
  tb:set_font("Inter regular 10")
  tb._private.notification = {}

  gtable.crush(tb, message, true)

  function tb._private.message_changed_callback()
    local n = tb._private.notification[1]

    if n then
      markup(tb, n.message, n.fg, "Inter regular 10")
    else
      markup(tb, nil, nil)
    end
  end

  if args.notification then
    tb:set_notification(args.notification)
  end

  return tb
end

return setmetatable(
  message,
  {
    __call = function(_, ...)
      return new(...)
    end
  }
)
