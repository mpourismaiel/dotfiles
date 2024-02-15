local capi = {
	awesome = awesome,
	screen = screen,
}
local collectgarbage = collectgarbage
collectgarbage("incremental", 110, 1000)
pcall(require, "luarocks.loader")

require("awful.autofocus")

local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local gears = require("gears")

local config_dir = gears.filesystem.get_configuration_dir()
package.path = package.path .. ";" .. config_dir .. "/external/?.lua;" .. config_dir .. "/external/?/init.lua"

local helpers = require("lib.module.helpers")

require("lib.tags")
require("lib.keys")
require("lib.ruled")
require("lib.client")
require("lib.notifications")
require("lib.widgets.lockscreen")
require("lib.widgets.volume.osd")

local theme = require("lib.configuration.theme")

naughty.connect_signal("request::display_error", function(message, startup)
	naughty.notification({
		urgency = "critical",
		title = "Oops, an error happened" .. (startup and " during startup!" or "!"),
		message = message,
	})
end)

beautiful.init(theme)

require("lib.module.autostart")
require("lib.module.launcher.dialog")()
require("lib.module.calendar")()
require("lib.module.debug")
require("lib.module.switcher")

require("lib.daemons.system.picom")

local store = require("lib.module.store")
local preferences = store("preferences")
if preferences:get("enable_xkb") == true then
	require("lib.daemons.hardware.keyboard_layout"):load_settings()
end

require("lib.widgets.desktop")
require("lib.widgets.bar")

awful.screen.connect_for_each_screen(function(s)
	require("lib.module.launcher")(s)
end)

if helpers.module_check("liblua_pam") == false then
	naughty.notification({
		title = "Missing dependency!",
		message = "Please install lua-pam library for lockscreen to work",
		timeout = 5,
	})
end

require("lib.daemons.hardware.display")

local _awesome_quit = capi.awesome.quit
capi.awesome.quit = function()
	local xfce_pid = io.popen("pgrep xfce4-session"):read("*a"):gsub("\n", "")
	local gnome_pid = io.popen("pgrep gnome-session"):read("*a"):gsub("\n", "")
	local kde_pid = io.popen("pgrep startkde"):read("*a"):gsub("\n", "")

	if xfce_pid ~= "" then
		awful.spawn("xfce4-session-logout")
	elseif gnome_pid ~= "" then
		awful.spawn("gnome-session-quit")
	elseif kde_pid ~= "" then
		awful.spawn("qdbus org.kde.ksmserver /KSMServer logout 0 0 0")
	else
		_awesome_quit()
	end
end
