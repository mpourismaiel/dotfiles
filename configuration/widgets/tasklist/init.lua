local capi = {button = button, client = client}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")

local tasklist = {mt = {}}

local function create_buttons(buttons, object)
  local is_formatted = buttons and buttons[1] and (type(buttons[1]) == "button" or buttons[1]._is_capi_button) or false

  if buttons then
    local btns = {}
    for _, src in ipairs(buttons) do
      --TODO v6 Remove this legacy overhead
      for _, b in ipairs(is_formatted and {src} or src) do
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
    end

    return btns
  end
end

local function custom_template(args)
  local template = {
    id = "background",
    border_strategy = "inner",
    widget = wibox.container.background,
    {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(48),
      height = config.dpi(48),
      {
        widget = wibox.layout.stack,
        {
          widget = wibox.container.place,
          {
            id = "icon",
            widget = wibox.widget.imagebox,
            forced_height = config.dpi(24),
            forced_width = config.dpi(24)
          }
        },
        {
          widget = wibox.container.margin,
          left = config.dpi(2),
          {
            widget = wibox.container.place,
            halign = "left",
            {
              id = "indicator",
              widget = wibox.container.background,
              shape = gears.shape.rounded_rect,
              {
                widget = wibox.container.constraint,
                strategy = "exact",
                width = config.dpi(3),
                height = config.dpi(12),
                {
                  widget = wibox.widget.textbox
                }
              }
            }
          }
        }
      }
    }
  }
  local l = wibox.widget.base.make_widget_from_value(template)

  return {
    background = l:get_children_by_id("background")[1],
    icon = l:get_children_by_id("icon")[1],
    indicator = l:get_children_by_id("indicator")[1],
    primary = l,
    update_callback = l.update_callback,
    create_callback = l.create_callback
  }
end

function tasklist.render(w, buttons, label, data, objects, args)
  -- update the widgets, creating them if needed
  w:reset()
  for i, o in ipairs(objects) do
    local cache = data[o]

    -- Allow the buttons to be replaced.
    if cache and cache._buttons ~= buttons then
      cache = nil
    end

    if not cache then
      cache = custom_template()

      cache.primary.buttons = {create_buttons(buttons, o)}

      if cache.create_callback then
        cache.create_callback(cache.primary, o, i, objects)
      end

      cache._buttons = buttons
      data[o] = cache
    elseif cache.update_callback then
      cache.update_callback(cache.primary, o, i, objects)
    end

    if o.icon then
      cache.icon:set_image(o.icon)
    end

    cache.indicator.bg = "#ffffff00"
    if
      o.active or
        (capi.client.focus and capi.client.focus.skip_taskbar and
          capi.client.focus:get_transient_for_matching(
            function(cl)
              return not cl.skip_taskbar
            end
          ) == o)
     then
      cache.indicator.bg = "#ffffff88"
    end

    if o.urgent then
      cache.indicator.bg = "#ff000088"
    end

    w:add(cache.primary)
  end
end

function tasklist.new(screen)
  return awful.widget.tasklist {
    screen = screen,
    filter = awful.widget.tasklist.filter.allscreen,
    update_function = tasklist.render,
    source = function(s, args)
      local list = {}
      local tags = s.tags
      for k, v in ipairs(tags) do
        list = gears.table.join(list, v:clients())
      end
      return list
    end,
    layout = {
      layout = wibox.layout.fixed.vertical
    },
    buttons = {
      awful.button(
        {},
        1,
        function(c)
          if c == client.focus then
            c.minimized = true
          else
            c.minimized = false
            if not c:isvisible() and c.first_tag then
              c.first_tag:view_only()
            end
            client.focus = c
            c:raise()
          end
        end
      ),
      awful.button(
        {awful.util.modkey},
        2,
        function(c)
          c:kill()
        end
      ),
      awful.button(
        {},
        4,
        function()
          awful.client.focus.byidx(1)
        end
      ),
      awful.button(
        {},
        5,
        function()
          awful.client.focus.byidx(-1)
        end
      )
    }
  }
end

function tasklist.mt:__call(...)
  return tasklist.new(...)
end

return setmetatable(tasklist, tasklist.mt)
