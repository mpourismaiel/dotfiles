local wibox     = require("wibox")
local gears     = require("gears")
local beautiful = require("beautiful")

local interfaces = { "eth0", "wlan0", "eno1", "lo" }
local ip

for i = 1, 4 do
    local fd     = io.popen("ifconfig " .. interfaces[i])
    local output = fd:read("*all")
    fd:close()

    ip = string.match(output, "addr:(%d+%.%d+%.%d+%.%d+)")
    if ip then break end
end

if not ip then
    ip = "offline"
end

return ip
