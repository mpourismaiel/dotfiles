local gears = require("gears")
local benches = {}

local function bench(key)
  if benches[key] == nil then
    benches[key] = os.clock()
    return
  end

  local time = os.clock() - benches[key]
  benches[key] = nil
  gears.debug.dump(time, "==========>> Bench: " .. key .. "")
end

return bench
