local gears = require("gears")

local function debounce(func, wait)
  local timer
  return function(...)
    local args = {...}
    if timer then
      timer:stop()
      timer = nil
    end

    timer =
      gears.timer.start_new(
      wait,
      function()
        func(table.unpack(args))
        timer = nil
      end
    )
  end
end

return debounce
