local config = require("lib.configuration")

local log = {mt = {}}
local log_file = config.data_dir .. "/" .. os.date("%Y-%m-%d.log")

function print(str)
  local file = io.open(log_file, "a")
  if not file then
    file = io.open(log_file, "w")
  end

  if not file then
    return
  end

  file:write(os.date("%Y-%m-%d %H:%M:%S.log") .. "\t" .. str .. "\n")
  file:close()
end

function log.mt:__call(...)
  return print(...)
end

return setmetatable(log, log.mt)
