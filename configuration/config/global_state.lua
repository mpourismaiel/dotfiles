local gears = require("gears")

function table.slice(tbl, first, last, step)
  local sliced = {}

  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced + 1] = tbl[i]
  end

  return sliced
end

local global_state = {
  cache = {
    n_id = 0,
    notifications = {},
    notifications_subscribers = {}
  }
}

global_state.cache.notifications_remove = function(id)
  local c = global_state.cache
  local found = 0
  for i, n in ipairs(c.notifications) do
    if n.id == id then
      found = i
      break
    end
  end

  if found == 1 then
    c.notifications = table.slice(c.notifications, 2)
  elseif found == #c.notifications then
    c.notifications = table.slice(c.notifications, 1, found - 1)
  elseif found > 0 then
    c.notifications =
      gears.table.join(table.slice(c.notifications, 1, found - 1), table.slice(c.notifications, found + 1))
  end

  global_state.cache.notifications_emit()
end

global_state.cache.notifications_clear = function()
  global_state.cache.notifications = {}
  global_state.cache.notifications_emit()
end

global_state.cache.notifications_update = function(n)
  local c = global_state.cache
  c.notifications = gears.table.join({id = c.n_id + 1, n}, c.notifications)
  c.n_id = c.n_id + 1

  global_state.cache.notifications_emit()
end

global_state.cache.notifications_emit = function()
  for _, fn in ipairs(global_state.cache.notifications_subscribers) do
    fn()
  end
end

global_state.cache.notifications_subscribe = function(fn)
  global_state.cache.notifications_subscribers = gears.table.join(global_state.cache.notifications_subscribers, {fn})
end

return global_state
