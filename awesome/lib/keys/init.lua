local awful = require("awful")
local gears = require("gears")
local naughty = require("naughty")
local hotkeys_popup = require("awful.hotkeys_popup")
local config = require("lib.configuration")
local machi = require("layout-machi")
local audio_daemon = require("lib.daemons.hardware.audio")
local layout = require("lib.layouts")

require("awful.hotkeys_popup.keys")

awful.keyboard.append_global_keybindings(
	{
		awful.key(
			{config.modkey},
			".",
			function()
				local layout = awful.layout.get(awful.screen.focused())
				if layout.name == "machi" then
					machi.default_editor.start_interactive()
				else
					if layout.start_interactive then
						layout.start_interactive()
					end
				end
			end,
			{description = "edit the current layout if it is a machi layout", group = "layout"}
		),
		awful.key(
			{config.modkey},
			"/",
			function()
				machi.switcher.start(client.focus)
			end,
			{description = "switch between windows for a machi layout", group = "layout"}
		),
		awful.key(
			{config.modkey},
			"b",
			function()
				awesome.emit_signal("widget::bar::toggle")
			end,
			{description = "toggle bars", group = "awesome"}
		),
		awful.key({config.modkey}, "s", hotkeys_popup.show_help, {description = "show help", group = "awesome"}),
		awful.key({config.modkey, "Control"}, "r", awesome.restart, {description = "reload awesome", group = "awesome"}),
		awful.key(
			{
				config.modkey
			},
			"w",
			function()
				awesome.emit_signal("module::debug::toggle")
			end
		),
		awful.key(
			{"Ctrl", "Shift"},
			"Escape",
			function()
				if config.taskManager == nil then
					naughty.notify(
						{
							title = "Task Manager not set",
							text = "Please set config.taskManager in lib/configuration/init.lua",
							preset = naughty.config.presets.critical
						}
					)
					return
				end

				awful.spawn.easy_async_with_shell(
					"command -v " .. config.taskManager,
					function(stdout)
						if stdout ~= "" then
							awful.spawn(config.taskManager)
						else
							-- show notification if not installed
							naughty.notify(
								{
									title = "Task Manager not installed",
									text = "Please install " .. config.taskManager,
									preset = naughty.config.presets.critical
								}
							)
						end
					end
				)
			end,
			{description = "open task manager", groupd = "launcher"}
		),
		awful.key(
			{config.modkey},
			"Return",
			function()
				if config.terminal == nil then
					naughty.notify(
						{
							title = "Terminal not set",
							text = "Please set config.terminal in lib/configuration/init.lua",
							preset = naughty.config.presets.critical
						}
					)
					return
				end

				awful.spawn.easy_async_with_shell(
					"command -v " .. config.terminal,
					function(stdout)
						if stdout ~= "" then
							awful.spawn(config.terminal)
						else
							-- show notification if not installed
							naughty.notify(
								{
									title = "Terminal not installed",
									text = "Please install " .. config.terminal,
									preset = naughty.config.presets.critical
								}
							)
						end
					end
				)
			end,
			{description = "open a terminal", group = "launcher"}
		),
		awful.key(
			{config.modkey},
			"l",
			function()
				awesome.emit_signal("module::lockscreen::show")
			end,
			{description = "lock desktop", group = "launcher"}
		),
		awful.key(
			{config.modkey},
			"d",
			function()
				awesome.emit_signal("module::launcher::show")
			end,
			{description = "open application drawer", group = "launcher"}
		),
		awful.key(
			{config.modkey},
			"Escape",
			function()
				awesome.emit_signal("widget::drawer:toggle")
			end,
			{description = "open application drawer", group = "launcher"}
		),
		awful.key(
			{config.modkey, "Shift"},
			"d",
			function()
				awful.spawn(config.commands.rofi_appmenu, false)
			end,
			{description = "open application drawer", group = "launcher"}
		),
		awful.key(
			{},
			"Print",
			function()
				-- check if config.commands.full_screenshot is set
				if config.commands.full_screenshot == nil then
					naughty.notify(
						{
							title = "Screenshot command not set",
							text = "Please set config.commands.full_screenshot in lib/configuration/init.lua",
							preset = naughty.config.presets.critical
						}
					)
					return
				end

				awful.spawn.easy_async_with_shell(
					"command -v " .. config.commands.full_screenshot,
					function(stdout)
						if stdout ~= "" then
							awful.spawn(config.commands.full_screenshot, false)
						else
							-- show notification if not installed
							naughty.notify(
								{
									title = "Screenshot command not installed",
									text = "Please install " .. config.commands.full_screenshot,
									preset = naughty.config.presets.critical
								}
							)
						end
					end
				)
			end,
			{description = "fullscreen screenshot", group = "Utility"}
		),
		awful.key(
			{"Shift"},
			"Print",
			function()
				if config.commands.area_screenshot == nil then
					naughty.notify(
						{
							title = "Screenshot command not set",
							text = "Please set config.commands.area_screenshot in lib/configuration/init.lua",
							preset = naughty.config.presets.critical
						}
					)
					return
				end

				awful.spawn.easy_async_with_shell(
					"command -v " .. config.commands.area_screenshot,
					function(stdout)
						if stdout ~= "" then
							awful.spawn(config.commands.area_screenshot, false)
						else
							-- show notification if not installed
							naughty.notify(
								{
									title = "Screenshot command not installed",
									text = "Please install " .. config.commands.area_screenshot,
									preset = naughty.config.presets.critical
								}
							)
						end
					end
				)
			end,
			{description = "area/selected screenshot", group = "Utility"}
		),
		awful.key(
			{},
			"XF86AudioRaiseVolume",
			function()
				audio_daemon:default_sink_volume_up(5)
				awesome.emit_signal("widget::volume")
			end,
			{description = "increase volume up by 5%", group = "hotkeys"}
		),
		awful.key(
			{},
			"XF86AudioLowerVolume",
			function()
				audio_daemon:default_sink_volume_down(5)
				awesome.emit_signal("widget::volume")
			end,
			{description = "decrease volume up by 5%", group = "hotkeys"}
		),
		awful.key(
			{},
			"XF86AudioMute",
			function()
				awful.spawn("amixer -D pulse set Master 1+ toggle", false)
			end,
			{description = "toggle mute", group = "hotkeys"}
		),
		awful.key(
			{},
			"XF86AudioNext",
			function()
				awful.spawn("playerctl next", false)
			end,
			{description = "next music", group = "hotkeys"}
		),
		awful.key(
			{},
			"XF86AudioPrev",
			function()
				awful.spawn("playerctl previous", false)
			end,
			{description = "previous music", group = "hotkeys"}
		),
		awful.key(
			{},
			"XF86AudioPlay",
			function()
				awful.spawn("playerctl play-pause", false)
			end,
			{description = "play/pause music", group = "hotkeys"}
		),
		awful.key(
			{},
			"XF86AudioMicMute",
			function()
				awful.spawn("amixer set Capture toggle", false)
			end,
			{description = "mute microphone", group = "hotkeys"}
		)
	}
)

awful.keyboard.append_global_keybindings(
	{
		awful.key(
			{config.modkey},
			"Tab",
			function()
				awful.client.focus.byidx(1)
			end,
			{description = "focus next by index", group = "client"}
		),
		awful.key(
			{config.modkey, "Shift"},
			"Tab",
			function()
				awful.client.focus.byidx(-1)
			end,
			{description = "focus previous by index", group = "client"}
		),
		awful.key(
			{config.modkey},
			"Down",
			function()
				awful.client.focus.global_bydirection("down")
				if client.focus then
					client.focus:raise()
				end
			end,
			{description = "focus down", group = "client"}
		),
		awful.key(
			{config.modkey},
			"Up",
			function()
				awful.client.focus.global_bydirection("up")
				if client.focus then
					client.focus:raise()
				end
			end,
			{description = "focus up", group = "client"}
		),
		awful.key(
			{config.modkey},
			"Left",
			function()
				awful.client.focus.global_bydirection("left")
				if client.focus then
					client.focus:raise()
				end
			end,
			{description = "focus left", group = "client"}
		),
		awful.key(
			{config.modkey},
			"Right",
			function()
				awful.client.focus.global_bydirection("right")
				if client.focus then
					client.focus:raise()
				end
			end,
			{description = "focus right", group = "client"}
		),
		awful.key(
			{config.modkey, "Ctrl"},
			"Left",
			function()
				awful.screen.focus_bydirection("left")
			end,
			{description = "focus the left screen", group = "screen"}
		),
		awful.key(
			{config.modkey, "Ctrl"},
			"Right",
			function()
				awful.screen.focus_bydirection("right")
			end,
			{description = "focus the right screen", group = "screen"}
		),
		awful.key(
			{config.modkey, "Ctrl"},
			"Up",
			function()
				awful.screen.focus_bydirection("up")
			end,
			{description = "focus the upper screen", group = "screen"}
		),
		awful.key(
			{config.modkey, "Ctrl"},
			"Down",
			function()
				awful.screen.focus_bydirection("down")
			end,
			{description = "focus the lower screen", group = "screen"}
		),
		awful.key(
			{config.modkey, "Shift"},
			"Left",
			function()
				local c = client.focus
				if not c then
					return
				end

				awful.screen.focus_bydirection("left")
				local s = awful.screen.focused()

				for _, t in ipairs(s.tags) do
					if t.name == c.first_tag.name then
						t:view_only()
						break
					end
				end

				c:move_to_screen(s)
				c:activate({raise = true})
			end,
			{description = "move client to the left screen", group = "client"}
		),
		awful.key(
			{config.modkey, "Shift"},
			"Right",
			function()
				local c = client.focus
				if not c then
					return
				end

				awful.screen.focus_bydirection("right")
				local s = awful.screen.focused()

				for _, t in ipairs(s.tags) do
					if t.name == c.first_tag.name then
						t:view_only()
						break
					end
				end

				c:move_to_screen(s)
				c:activate({raise = true})
			end,
			{
				description = "move client to the right screen",
				group = "client"
			}
		),
		awful.key(
			{config.modkey, "Shift"},
			"Up",
			function()
				local c = client.focus
				if not c then
					return
				end

				awful.screen.focus_bydirection("up")
				local s = awful.screen.focused()

				for _, t in ipairs(s.tags) do
					if t.name == c.first_tag.name then
						t:view_only()
						break
					end
				end

				c:move_to_screen(s)
				c:activate({raise = true})
			end,
			{description = "move client to the upper screen", group = "client"}
		),
		awful.key(
			{config.modkey, "Shift"},
			"Down",
			function()
				local c = client.focus
				if not c then
					return
				end

				awful.screen.focus_bydirection("down")
				local s = awful.screen.focused()

				for _, t in ipairs(s.tags) do
					if t.name == c.first_tag.name then
						t:view_only()
						break
					end
				end

				c:move_to_screen(s)
				c:activate({raise = true})
			end,
			{description = "move client to the lower screen", group = "client"}
		)
	}
)

awful.keyboard.append_global_keybindings(
	{
		awful.key({config.modkey}, "u", awful.client.urgent.jumpto, {description = "jump to urgent client", group = "client"}),
		awful.key(
			{config.modkey},
			"space",
			function()
				layout.inc(1)
			end,
			{description = "select next", group = "layout"}
		),
		awful.key(
			{config.modkey, "Shift"},
			"space",
			function()
				layout.inc(-1)
			end,
			{description = "select previous", group = "layout"}
		)
	}
)

awful.keyboard.append_global_keybindings(
	{
		awful.key(
			{
				modifiers = {config.modkey},
				keygroup = "numrow",
				description = "only view tag",
				group = "tag",
				on_press = function(index)
					local screen = awful.screen.focused()
					local tag = screen.tags[index]
					if tag then
						tag:view_only()
					end
				end
			}
		),
		awful.key(
			{
				modifiers = {config.modkey, "Shift"},
				keygroup = "numrow",
				description = "move focused client to tag",
				group = "tag",
				on_press = function(index)
					if client.focus then
						local tag = client.focus.screen.tags[index]
						if tag then
							client.focus:move_to_tag(tag)
						end
					end
				end
			}
		)
	}
)

client.connect_signal(
	"request::default_mousebindings",
	function()
		awful.mouse.append_client_mousebindings(
			{
				awful.button(
					{},
					1,
					function(c)
						c:activate({context = "mouse_click"})
					end
				),
				awful.button(
					{config.modkey},
					1,
					function(c)
						c:activate({context = "mouse_click", action = "mouse_move"})
					end
				),
				awful.button(
					{config.modkey},
					3,
					function(c)
						c:activate({context = "mouse_click", action = "mouse_resize"})
					end
				)
			}
		)
	end
)

client.connect_signal(
	"request::default_keybindings",
	function()
		awful.keyboard.append_client_keybindings(
			{
				awful.key(
					{config.modkey},
					"f",
					function(c)
						c.fullscreen = not c.fullscreen
						c:raise()
					end,
					{description = "toggle fullscreen", group = "client"}
				),
				awful.key(
					{config.modkey},
					"q",
					function(c)
						c:kill()
					end,
					{description = "close", group = "client"}
				),
				awful.key({config.modkey}, "c", awful.client.floating.toggle, {description = "toggle floating", group = "client"}),
				awful.key(
					{config.modkey},
					"t",
					function(c)
						c.ontop = not c.ontop
					end,
					{description = "toggle keep on top", group = "client"}
				),
				awful.key(
					{config.modkey},
					"n",
					function(c)
						-- The client currently has the input focus, so it cannot be
						-- minimized, since minimized clients can't have the focus.
						c.minimized = true
					end,
					{description = "minimize", group = "client"}
				),
				awful.key(
					{config.modkey},
					"m",
					function(c)
						c.maximized = not c.maximized
						c:raise()
					end,
					{description = "(un)maximize", group = "client"}
				)
			}
		)
	end
)
