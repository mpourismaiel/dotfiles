local wibox = require("wibox")
local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local lain = require("lain")
local helpers = require("utils.helpers")
local clickable_container = require("widgets.clickable-container")
local markup = lain.util.markup
local capi = {
  button = _G.button,
  client = client
}

local function create_buttons(buttons, object)
  if buttons then
    local btns = {}
    for _, b in ipairs(buttons) do
      -- Create a proxy button object: it will receive the real
      -- press and release events, and will propagate them to the
      -- button object the user provided, but with the object as
      -- argument.
      local btn = capi.button {modifiers = b.modifiers, button = b.button}
      btn:connect_signal(
        "press",
        function()
          b:emit_signal("press", object)
        end
      )
      btn:connect_signal(
        "release",
        function()
          b:emit_signal("release", object)
        end
      )
      btns[#btns + 1] = btn
    end

    return btns
  end
end

local function tasklist(theme)
  return function(widget, buttons, label, data, objects)
    -- update the widgets, creating them if needed
    widget:reset()
    for i, object in ipairs(objects) do
      local cache = data[object]
      local close_button,
        title,
        close_button_container,
        bg_clickable_background,
        title_container,
        tooltip,
        task_clickable,
        task_layout,
        bg_clickable

      if cache then
        title = cache.title
        bg_clickable_background = cache.bg_clickable_background
        title_container = cache.title_container
        tooltip = cache.tooltip
      else
        title = wibox.widget.textbox()
        local exit_icon = wibox.widget.textbox()
        exit_icon:set_markup(markup(theme.primary, theme.icon_fn("", 12)))
        close_button = clickable_container(wibox.container.margin(exit_icon, 4, 4, 0, 0))
        close_button.shape = gears.shape.circle
        close_button_container = wibox.container.margin(close_button, 4, 8, 12, 12)
        close_button_container:buttons(
          gears.table.join(
            awful.button(
              {},
              1,
              nil,
              function()
                object.kill(object)
              end
            )
          )
        )
        bg_clickable = clickable_container()
        bg_clickable_background = wibox.container.background()
        local title_constraint = wibox.widget {
          {
            {
              {
                widget = title
              },
              widget = wibox.container.constraint,
              strategy = "exact",
              height = 20
            },
            widget = wibox.container.constraint,
            strategy = "max",
            width = 200
          },
          widget = wibox.container.constraint,
          strategy = "min",
          width = 80
        }
        title_container = wibox.container.margin(wibox.container.place(title_constraint, "left", "center"), 10, 4)
        task_clickable = wibox.layout.fixed.horizontal()
        task_layout = wibox.layout.fixed.horizontal()

        -- All of this is added in a fixed widget
        task_clickable:fill_space(true)
        task_clickable:add(title_container)
        task_layout:add(task_clickable)
        task_layout:add(close_button_container)

        bg_clickable:set_widget(task_layout)
        -- And all of this gets a background
        bg_clickable_background:set_widget(bg_clickable)

        task_clickable:buttons(create_buttons(buttons, object))

        -- Tooltip to display whole title, if it was truncated
        tooltip =
          awful.tooltip(
          {
            objects = {title},
            mode = "outside",
            align = "bottom",
            delay_show = 1
          }
        )

        data[object] = {
          title = title,
          bg_clickable_background = bg_clickable_background,
          title_container = title_container,
          tooltip = tooltip
        }
      end

      local text, bg, bg_image, icon, args = label(object, title)
      args = args or {}

      -- The text might be invalid, so use pcall.
      if text == nil or text == "" then
        title_container:set_margins(0)
      else
        -- truncate when title is too long
        local textOnly = text:match(">(.-)<")
        if (textOnly:len() > 24) then
          text = text:gsub(">(.-)<", ">" .. textOnly:sub(1, 21) .. "...<")
          tooltip:set_text(textOnly)
          tooltip:add_to_object(title)
        else
          tooltip:remove_from_object(title)
        end
        if not title:set_markup_silently(text) then
          title:set_markup("<i>&lt;Invalid text&gt;</i>")
        end
      end
      bg_clickable_background:set_bg(bg)
      if type(bg_image) == "function" then
        -- TODO: Why does this pass nil as an argument?
        bg_image = bg_image(title, object, nil, objects, i)
      end
      bg_clickable_background:set_bgimage(bg_image)

      bg_clickable_background.shape = args.shape
      bg_clickable_background.shape_border_width = args.shape_border_width
      bg_clickable_background.shape_border_color = args.shape_border_color

      local focused = capi.client.focus == object
      if
        not focused and capi.client.focus and capi.client.focus.skip_taskbar and
          capi.client.focus:get_transient_for_matching(
            function(cl)
              return not cl.skip_taskbar
            end
          ) == object
       then
        focused = true
      end

      local widget_children = wibox.layout.fixed.vertical()
      local indicator =
        wibox.container.background(wibox.container.margin(wibox.widget.textbox(), 0, 0, 3), theme.border_normal)
      widget_children:add(indicator)

      if focused then
        indicator.bg = theme.primary
      end

      widget_children:add(bg_clickable_background)
      widget:add(widget_children)
    end
  end
end

return tasklist
