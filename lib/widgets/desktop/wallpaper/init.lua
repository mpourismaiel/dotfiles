local capi = {
	awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local theme = require("lib.configuration.theme")

local wallpaper = {mt = {}}

function wallpaper:set_callback(callback)
	local wp = self._private
	wp.callback = callback
end

function wallpaper:get_callback()
	local wp = self._private
	return wp.callback
end

local function new()
	local widget =
		wibox.widget(
		{
			widget = wibox.widget.imagebox,
			resize = true,
			horizontal_fit_policy = "fit",
			vertical_fit_policy = "fit",
			image = theme.wallpaper
		}
	)

	gears.table.crush(widget, wallpaper)
	local wp = widget._private

	capi.awesome.connect_signal(
		"module::config::changed_wallpaper",
		function(path)
			if path then
				local f = io.open(path, "rb")
				if f then
					f:close()
				end
				if f == nil then
					naughty.notify(
						{
							title = "Configuration error",
							text = "Wallpaper not found: " .. path
						}
					)
					return
				end

				widget:set_image(path)
				if wp.callback then
					wp.callback()
				end
			end
		end
	)

	return widget
end

function wallpaper.mt:__call(...)
	return new(...)
end

return setmetatable(wallpaper, wallpaper.mt)
