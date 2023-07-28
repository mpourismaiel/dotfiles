local gears = require("gears")
local json = require("lib.json")
local config = require("configuration.config")

local store = {mt = {}}

function store:load()
  local wp = self._private
  local file = io.open(wp.name, "r")
  if not file then
    return
  end

  local data = file:read("*a")
  wp.value = json.decode(data)
  file:close()
end

function store:save()
  local wp = self._private
  local file = io.open(wp.name, "w+")
  if not file then
    return
  end
  local data = json.encode(wp.value)
  file:write(data)
  file:close()
end

function store:add(key, update_callback)
  local wp = self._private
  local value = wp.value[key]
  if not value then
    value = update_callback()
    wp.value[key] = value
  else
    value = update_callback(value)
    wp.value[key] = value
  end
  self:save()
end

function store:get(key)
  local wp = self._private
  return wp.value[key]
end

local function new(name, initial_value)
  local ret = {_private = {}}
  gears.table.crush(ret, store)

  local wp = ret._private
  wp.name = config.dir .. "/store-" .. name .. ".json"
  wp.value = initial_value or {}

  ret:load()

  return ret
end

function store.mt:__call(...)
  return new(...)
end

return setmetatable(store, store.mt)
