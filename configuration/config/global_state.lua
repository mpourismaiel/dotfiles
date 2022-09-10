local gears = require("gears")

local global_state = {
  cache = {
    notifications = {},
    notifications_subscribers = {}
  }
}

global_state.cache.notifications_update = function(n)
  global_state.cache.notifications = gears.table.join(global_state.cache.notifications, {n})
  gears.debug.dump(n.actions, "actions")

  for _, fn in ipairs(global_state.cache.notifications_subscribers) do
    fn()
  end
end

global_state.cache.notifications_subscribe = function(fn)
  global_state.cache.notifications_subscribers = gears.table.join(global_state.cache.notifications_subscribers, {fn})
  gears.debug.dump()
end

return global_state
