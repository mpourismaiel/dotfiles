local capi = {
  awesome = awesome
}
local gears = require("gears")

local console = {mt = {}}

function console:log(...)
  local args = {...}
  local str = ""
  for i, v in ipairs(args) do
    if type(v) == "table" then
      for k, v in pairs(v) do
        local keyFormatted = string.format("\27[1;30m%s\27[0m", k) -- Bold and gray key
        local valueFormatted = string.format("\27[1;37m%s\27[0m", v) -- Normal and white value
        local output = string.format("%s: %s\n", keyFormatted, valueFormatted)
        str = str .. output
      end
    else
      str = str .. gears.debug.dump_return(v)
    end

    if i ~= #args then
      str = str .. "\n"
    end
  end

  if self._private.divider then
    gears.debug.dump(self._private.divider)
  end

  if self._private.title then
    local title_formatted = string.format("\27[1;37m%s\27[0m", self._private.title)
    gears.debug.dump(title_formatted)
  end

  gears.debug.dump(str)

  if self._private.with_trace then
    gears.debug.dump("\n" .. _G.debug.traceback() .. "\n")
  end
end

function console:with_trace()
  self._private.with_trace = true
  return self
end

function console:title(title)
  self._private.title = title
  return self
end

function console:disable_divider()
  self._private.divider = nil
  return self
end

local function new()
  local ret = {
    _private = {
      title = "",
      with_trace = false,
      divider = "================================================"
    }
  }
  gears.table.crush(ret, console, true)
  return ret
end

capi.awesome.connect_signal(
  "debug::console",
  function(title, value, with_trace)
    if with_trace then
      console():title(title):with_trace():log(value)
      return
    end

    console():title(title):log(value)
  end
)

function console.mt:__call(...)
  return new(...)
end

return setmetatable(console, console.mt)
