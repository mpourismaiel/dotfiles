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
    data = {}
  }
}

global_state.cache.set = function(key, value)
  global_state.cache.data[key] = {
    key = key,
    value = value,
    last_id = 0,
    listeners = {}
  }

  global_state.cache.emit(key)
end

global_state.cache.update = function(key, value)
  global_state.cache.data[key].value = value

  global_state.cache.emit(key)
end

global_state.cache.add = function(key, value)
  if global_state.cache.data[key] == nil then
    global_state.cache.set(key, {})
  end

  global_state.cache.data[key].value =
    gears.table.join(
    {
      id = id == nil and global_state.cache.data[key].last_id + 1,
      value
    },
    global_state.cache.get(key)
  )
  global_state.cache.data[key].last_id = global_state.cache.data[key].last_id + 1

  global_state.cache.emit(key)
end

global_state.cache.remove = function(key, id)
  local c = global_state.cache
  local found = 0
  for i, n in ipairs(c.get(key)) do
    if n.id == id then
      found = i
      break
    end
  end

  if found == 1 then
    c.data[key].value = table.slice(c.get(key), 2)
  elseif found == #c.get(key) then
    c.data[key].value = table.slice(c.get(key), 1, found - 1)
  elseif found > 0 then
    c.data[key].value = gears.table.join(table.slice(c.get(key), 1, found - 1), table.slice(c.get(key), found + 1))
  end

  c.emit(key)
end

global_state.cache.get = function(key)
  return global_state.cache.data[key].value
end

global_state.cache.listen = function(key, fn)
  if global_state.cache.data[key] == nil then
    global_state.cache.set(key, {})
  end
  global_state.cache.data[key].listeners = gears.table.join(global_state.cache.data[key].listeners, {fn})
end

global_state.cache.emit = function(key)
  for _, fn in ipairs(global_state.cache.data[key].listeners) do
    fn()
  end
end

return global_state
