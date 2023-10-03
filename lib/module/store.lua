local gears = require("gears")
local json = require("external.json")
local config = require("lib.configuration")
local debounce = require("lib.helpers.debounce")
local console = require("lib.helpers.console")

local store = {mt = {}}
local cache = {}

function store:load()
  local wp = self._private
  local file = io.open(wp.name, "r")
  if not file then
    return false
  end

  local data = file:read("*a")
  wp.value = json.decode(data)
  file:close()
end

function store:save()
  local wp = self._private
  wp.save()
end

function store:_save()
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

function store:get(key, default)
  local wp = self._private
  return wp.value[key] or default
end

function store:set(key, value)
  local wp = self._private
  wp.value[key] = value
  self:save()
end

function store:toggle(key)
  local wp = self._private
  local value = wp.value[key]

  if type(value) ~= "boolean" then
    gears.debug.print_warning("store:toggle() called on non-boolean value, [key]: " .. key)
  end

  if value then
    wp.value[key] = false
  else
    wp.value[key] = true
  end
  self:save()
end

local function new(name, initial_value)
  if cache[name] then
    return cache[name]
  end

  local ret = {_private = {}}
  gears.table.crush(ret, store)

  local wp = ret._private
  wp.name = config.data_dir .. "/store-" .. name .. ".json"
  wp.value = initial_value or {}

  wp.save =
    debounce(
    function()
      ret:_save()
    end,
    0.5
  )

  if ret:load() == false then
    ret:_save()
  end

  cache[name] = ret
  return ret
end

function store.mt:__call(...)
  return new(...)
end

return setmetatable(store, store.mt)
