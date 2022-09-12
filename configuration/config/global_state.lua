local gears = require("gears")

local global_state = {
  cache = {
    n_id = 0,
    notifications = {},
    notifications_subscribers = {}
  }
}

global_state.cache.notifications_remove = function(id)
  local c = global_state.cache
  for i, n in ipairs(c.notifications) do
    if n.id == id then
      c.notifications[i] = nil
    end
  end

  for _, fn in ipairs(c.notifications_subscribers) do
    fn()
  end
end

global_state.cache.notifications_update = function(n)
  local c = global_state.cache
  c.notifications = gears.table.join({id = c.n_id + 1, n}, c.notifications)
  c.n_id = c.n_id + 1

  for _, fn in ipairs(c.notifications_subscribers) do
    fn()
  end
end

global_state.cache.notifications_subscribe = function(fn)
  global_state.cache.notifications_subscribers = gears.table.join(global_state.cache.notifications_subscribers, {fn})
end

return global_state
