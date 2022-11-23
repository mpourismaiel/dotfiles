local textbox = require("wibox.widget.textbox")
local gtable = require("gears.table")
local beautiful = require("beautiful")
local markup = require("naughty.widget._markup").set_markup

local title = {}

function title:set_notification(notif)
  local old = self._private.notification[1]

  if old == notif then
    return
  end

  if old then
    old:disconnect_signal("property::message", self._private.title_changed_callback)
    old:disconnect_signal("property::fg", self._private.title_changed_callback)
  end

  markup(self, notif.title, notif.fg, notif.font)

  self._private.notification = setmetatable({notif}, {__mode = "v"})
  self._private.title_changed_callback()

  notif:connect_signal("property::title", self._private.title_changed_callback)
  notif:connect_signal("property::fg", self._private.title_changed_callback)
  self:emit_signal("property::notification", notif)
end

local function new(args)
  args = args or {}
  local tb = textbox()
  tb:set_wrap("word")
  tb:set_font("Inter bold 11")
  tb._private.notification = {}

  gtable.crush(tb, title, true)

  function tb._private.title_changed_callback()
    local n = tb._private.notification[1]

    if n then
      markup(tb, n.title, n.fg, "Inter bold 11")
    else
      markup("", nil, nil)
    end
  end

  if args.notification then
    tb:set_notification(args.notification)
  end

  return tb
end

return setmetatable(
  title,
  {
    __call = function(_, ...)
      return new(...)
    end
  }
)
