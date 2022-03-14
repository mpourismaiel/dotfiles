local awful = require("awful")

local tasklist = {mt = {}}

function tasklist.new()
  return awful.widget.keyboardlayout()
end

function tasklist.mt:__call(...)
  return tasklist.new(...)
end

return setmetatable(tasklist, tasklist.mt)
