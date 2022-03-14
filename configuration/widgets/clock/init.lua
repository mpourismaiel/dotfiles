local wibox = require("wibox")

local tasklist = {mt = {}}

function tasklist.new()
  return wibox.widget.textclock()
end

function tasklist.mt:__call(...)
  return tasklist.new(...)
end

return setmetatable(tasklist, tasklist.mt)
