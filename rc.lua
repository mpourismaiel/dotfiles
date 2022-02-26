local gears = require("gears")
local beautiful = require("beautiful")
local awful = require("awful")

awful.util.shell = "sh"

beautiful.init(require("theme"))

require("layout")

require("configuration.client")
require("configuration.root")
require("configuration.tags")
root.keys(require("configuration.keys.global"))

require("module.notifications")
require("module.auto-start")
require("module.exit-screen")
require("module.menu")
require("module.titlebar")
require("module.brightness-osd")
require("module.volume-osd")
require("module.lockscreen")
require("module.dynamic-wallpaper")

screen.connect_signal(
	"request::wallpaper",
	function(s)
		-- If wallpaper is a function, call it with the screen
		if beautiful.wallpaper then
			if type(beautiful.wallpaper) == "string" then
				if beautiful.wallpaper:sub(1, #"/") == "/" then
					gears.wallpaper.maximized(beautiful.wallpaper, s)
				end
			else
				beautiful.wallpaper(s)
			end
		end
	end
)
