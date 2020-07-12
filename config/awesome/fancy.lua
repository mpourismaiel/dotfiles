local awful = require("awful")
local wibox = require("wibox")

local module = {}

local generate_filter = function(i)
	return function(c, scr)
		local t = scr.tags[i]
		local ctags = c:tags()
		for _, v in ipairs(ctags) do
			if v == t then
				return true
			end
		end
		return false
	end
end

local fancytasklist = function(cfg, tag_index)
	return awful.widget.tasklist{
		screen = cfg.screen or awful.screen.focused(),
		filter = generate_filter(tag_index),
		buttons = awful.util.tasklist_buttons,
		widget_template = {
      {
        {
          id = "clienticon",
          widget = awful.widget.clienticon
        },
        widget = wibox.container.margin,
        top = 15,
        bottom = 15,
        left = 5,
        right = 5
      },
			layout = wibox.layout.stack,
			create_callback = function(self, c, _, _)
				self:get_children_by_id("clienticon")[1].client = c
				awful.tooltip{
					objects = { self },
					timer_function = function()
						return c.name
					end
				}
			end
		}
	}
end

function module.new(config)
	local cfg = config or {}

	local s = cfg.screen or awful.screen.focused()
	local taglist_buttons = cfg.taglist_buttons

	return awful.widget.taglist{
		screen = s,
		filter = awful.widget.taglist.filter.noempty,
		widget_template = {
			{
        {
          {
            -- tag
            {
              id = "text_role",
              widget = wibox.widget.textbox,
              align = "center"
            },
            -- tasklist
            {
              id = "tasklist_placeholder",
              layout = wibox.layout.fixed.horizontal
            },
            layout = wibox.layout.fixed.horizontal
          },
          widget = wibox.container.margin,
          left = 15,
          right = 15
        },
				id = "background_role",
				widget = wibox.container.background,
			},
			layout = wibox.layout.fixed.horizontal,
			create_callback = function(self, _, index, _)
				self:get_children_by_id("tasklist_placeholder")[1]:add(
          wibox.widget {
            fancytasklist(cfg, index),
            widget = wibox.container.margin,
            left = 10,
          }
        )
			end
    },
    buttons = awful.util.taglist_buttons,
	}
end

return module
