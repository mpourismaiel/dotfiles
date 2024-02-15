local capi = {
	screen = screen,
	client = client,
	tag = tag,
	root = root
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local woverflow = require("wibox.layout.overflow")
local animation_new = require("lib.helpers.animation-new")
local colors = require("lib.helpers.color")
local console = require("lib.helpers.console")

local mylayout = {}
mylayout.name = "tabbed"

local function get_screen(s)
	return s and capi.screen[s]
end

for idx, tag in ipairs(capi.root.tags()) do
	tag.master_top_idx = 1
	tag.slave_top_idx = 1
end

capi.tag.connect_signal(
	"property::selected",
	function(t)
		if not t.master_top_idx then
			t.master_top_idx = 1
		end
		if not t.slave_top_idx then
			t.slave_top_idx = 1
		end
	end
)

local function create_tabbar(s, tag, section, clients, area)
	if not tag.tabbar then
		tag.tabbar = {}
	end

	if not tag.tabbar[section] then
		tag.tabbar[section] =
			wibox {
			ontop = true,
			visible = true,
			height = config.dpi(36),
			bg = theme.bg_primary,
			widget = wibox.widget {
				widget = wibox.container.margin,
				left = config.dpi(16),
				{
					layout = woverflow.horizontal,
					scrollbar_spacing = 0,
					scrollbar_width = 0,
					step = 100,
					id = "clients_list"
				}
			}
		}

		local function adjust_visibility()
			for screen in capi.screen do
				for _, t in ipairs(screen.tags) do
					if t == tag then
						if t.selected and t.layout.name == mylayout.name then
							tag.tabbar[section].visible = true
						else
							tag.tabbar[section].visible = false
						end
					end
				end
			end
		end

		capi.tag.connect_signal("property::selected", adjust_visibility)
		capi.tag.connect_signal("property::layout", adjust_visibility)
		capi.tag.connect_signal("tagged", adjust_visibility)
		capi.tag.connect_signal("untagged", adjust_visibility)
		capi.tag.connect_signal("property::master_count", adjust_visibility)
		capi.client.connect_signal("property::minimized", adjust_visibility)
		capi.client.connect_signal("property::fullscreen", adjust_visibility)
		capi.client.connect_signal("focus", adjust_visibility)
		capi.client.connect_signal("unfocus", adjust_visibility)
	end

	local tabbar = tag.tabbar[section]
	tabbar.visible = true
	tabbar.x = area.x
	tabbar.y = area.y
	tabbar.width = area.width
	tabbar.height = area.height

	local clients_list = tabbar:get_children_by_id("clients_list")[1]
	clients_list:reset()
	for _, c in ipairs(clients) do
		local client_button = c.tabbar_button
		if not client_button then
			client_button =
				wibox.widget {
				widget = wbutton,
				strategy = "exact",
				width = config.dpi(250),
				height = config.dpi(36),
				margin_top = config.dpi(4),
				halign = "left",
				shape = "tab",
				callback = function()
					c:raise()
					capi.client.focus = c
				end,
				middle_click_callback = function()
					c:kill()
				end,
				right_click_callback = function()
					c.minimized = true
				end,
				{
					layout = wibox.layout.fixed.horizontal,
					{
						widget = wibox.container.constraint,
						strategy = "exact",
						width = config.dpi(16),
						height = config.dpi(16),
						{
							widget = wibox.widget.imagebox,
							id = "client_icon",
							image = c.icon
						}
					},
					{
						widget = wibox.container.margin,
						left = config.dpi(12),
						right = config.dpi(12),
						{
							widget = wibox.widget.textbox,
							id = "client_name",
							text = c.name or c.class or "-",
							ellipsize = "end"
						}
					}
				}
			}
			c.tabbar_button = client_button

			function c.update_tabbar_focus()
				if c == capi.client.focus then
					client_button.bg_normal = theme.bg_normal
					client_button.bg_hover = theme.bg_normal
					client_button.fg_normal = theme.fg_focus
				else
					client_button.bg_normal = theme.bg_primary
					client_button.bg_hover = theme.bg_hover
					client_button.fg_normal = theme.fg_normal
				end
			end

			c:connect_signal("focus", c.update_tabbar_focus)
			c:connect_signal("unfocus", c.update_tabbar_focus)
			c:connect_signal(
				"property::name",
				function()
					client_button:get_children_by_id("client_name")[1].text = c.name or c.class or "-"
				end
			)
			c:connect_signal(
				"property::icon",
				function()
					client_button:get_children_by_id("client_icon")[1].image = c.icon
				end
			)
		end

		c.update_tabbar_focus()

		clients_list:add(client_button)
	end

	return tabbar
end

local function hide_tabbar(s, tag, section)
	if not tag.tabbar then
		return
	end

	if not tag.tabbar[section] then
		return
	end

	tag.tabbar[section].visible = false
end

function mylayout.start_interactive()
	local screen = awful.screen.focused()
	local tag = screen.selected_tag
	local editor =
		wibox {
		ontop = true,
		screen = screen,
		visible = true,
		bg = colors.helpers.change_opacity(theme.bg_normal, 0.75),
		widget = wibox.widget {
			widget = wibox.container.place,
			{
				layout = wibox.layout.fixed.vertical,
				spacing = config.dpi(16),
				{
					widget = wtext,
					halign = "center",
					text = "Interactive layout editor",
					font_size = 16,
					bold = true
				},
				{
					layout = wibox.layout.fixed.horizontal,
					spacing = config.dpi(16),
					{
						widget = wbutton,
						callback = function()
							awful.tag.incnmaster(1, tag)
						end,
						label = "Add master"
					},
					{
						widget = wbutton,
						callback = function()
							if tag.master_count > 1 then
								awful.tag.incnmaster(-1, tag)
							end
						end,
						label = "Remove master"
					}
				}
			}
		}
	}

	awful.placement.maximize(
		editor,
		{
			honor_workarea = false,
			honor_padding = false
		}
	)

	local animation =
		animation_new(
		{
			subject = {opacity = 0},
			duration = 0.2
		}
	):add("visible", {target = {opacity = 1}}):add("invisible", {target = {opacity = 0}}):onUpdate(
		function(_, subject)
			editor.opacity = subject.opacity
		end
	):startAnimation("visible")

	local keygrabber =
		awful.keygrabber {
		keybindings = {},
		stop_key = "Escape",
		stop_callback = function(self)
			animation:startAnimation("invisible")
		end
	}

	animation:onFinish(
		function(animation)
			if animation == "invisible" then
				editor.visible = false
			end
		end
	)
	keygrabber:start()
end

function mylayout.arrange(p)
	local area = p.workarea
	local t = p.tag or capi.screen[p.screen].selected_tag
	local s = t.screen
	local mwfact = t.master_width_factor
	local nmaster = math.min(t.master_count, #p.clients)
	local nslaves = #p.clients - nmaster

	local master_area_width = area.width * mwfact
	if nslaves <= 0 then
		master_area_width = area.width
	end
	local slave_area_width = area.width - master_area_width

	local master_clients = {}
	local master_tabbar_size = config.dpi(36)
	local master_tabbar_area = {}
	if nmaster <= 1 then
		master_tabbar_size = 0
	end
	for idx = 1, nmaster do
		local c = p.clients[idx]
		master_clients[#master_clients + 1] = c

		if c == capi.client.focus then
			t.master_top_idx = #master_clients
		end

		local g = {
			x = area.x,
			y = area.y + master_tabbar_size,
			width = master_area_width,
			height = area.height - master_tabbar_size
		}
		master_tabbar_area = gears.table.clone(g)
		master_tabbar_area.y = area.y
		master_tabbar_area.height = master_tabbar_size
		p.geometries[c] = g
	end

	local slave_clients = {}
	local slave_tabbar_size = config.dpi(36)
	local slave_tabbar_area = {}
	if nslaves <= 1 then
		slave_tabbar_size = 0
	end
	for idx = 1, nslaves do
		local c = p.clients[idx + nmaster]
		slave_clients[#slave_clients + 1] = c

		if c == capi.client.focus then
			t.slave_top_idx = #slave_clients
		end

		local g = {
			x = area.x + master_area_width,
			y = area.y + slave_tabbar_size,
			width = slave_area_width,
			height = area.height - slave_tabbar_size
		}
		slave_tabbar_area = gears.table.clone(g)
		slave_tabbar_area.y = area.y
		slave_tabbar_area.height = slave_tabbar_size

		p.geometries[c] = g
	end

	for idx = 1, nmaster do
		local c = p.clients[idx]
		if idx == t.master_top_idx then
			c.opacity = 1
		else
			c.opacity = 0
		end
	end

	for idx = 1, nslaves do
		local c = p.clients[idx + nmaster]
		if idx == t.slave_top_idx then
			c.opacity = 1
		else
			c.opacity = 0
		end
	end

	if nmaster >= 2 then
		create_tabbar(s, t, "master", master_clients, master_tabbar_area)
	else
		hide_tabbar(s, t, "master")
	end

	if nslaves >= 2 then
		create_tabbar(s, t, "slave", slave_clients, slave_tabbar_area)
	else
		hide_tabbar(s, t, "slave")
	end
end

function mylayout.exit()
	local screen = get_screen(awful.screen.focused())
	if not screen then
		return
	end

	local p = awful.layout.parameters(nil, screen)
	if not p or not p.clients then
		return
	end

	for _, c in pairs(p.clients) do
		c.opacity = 1
	end
end

return mylayout
