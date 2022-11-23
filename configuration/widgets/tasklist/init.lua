local capi = {button = button, client = client}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local tasklist_override = require("configuration.widgets.tasklist.override")
local config = require("configuration.config")

local tasklist = {mt = {}}

local function create_buttons(buttons, items, widgetCache)
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
            b:emit_signal("press", items, widgetCache)
          end
        )
        btn:connect_signal(
          "release",
          function()
            b:emit_signal("release", items, widgetCache)
          end
        )
        btns[#btns + 1] = btn
      end
    end

    return btns
  end
end

local function custom_template()
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

function tasklist.render(w, buttons, label, previous_cache, items)
  -- update the widgets, creating them if needed
  w:reset()

  -- o is the group of clients with the same class
  for i, o in pairs(items) do
    local cache = previous_cache[i]
    local firstItemInGroup = o[1]

    -- Allow the buttons to be replaced.
    if cache and cache._buttons ~= buttons then
      cache = nil
    end

    if not cache then
      cache = custom_template()

      cache.primary.buttons = {create_buttons(buttons, o, cache)}

      if cache.create_callback then
        cache.create_callback(cache.primary, o, i, items)
      end

      cache._buttons = buttons
      previous_cache[i] = cache
    elseif cache.update_callback then
      cache.update_callback(cache.primary, o, i, items)
    end

    if firstItemInGroup.icon then
      cache.icon:set_image(firstItemInGroup.icon)
    end

    cache.indicator.bg = "#ffffff00"

    local groupHasActive = false
    for _, c in ipairs(o) do
      if
        c.active or
          (capi.client.focus and capi.client.focus.skip_taskbar and
            capi.client.focus:get_transient_for_matching(
              function(cl)
                return not cl.skip_taskbar
              end
            ) == c)
       then
        groupHasActive = true
        break
      end
    end
    if groupHasActive then
      cache.indicator.bg = "#ffffff88"
    end

    local groupHasFocus = false
    for _, c in ipairs(o) do
      if c.urgent then
        groupHasFocus = true
        break
      end
    end
    if groupHasFocus then
      cache.indicator.bg = "#ff000088"
    end

    w:add(cache.primary)
  end
end

function tasklist.new(screen)
  return tasklist_override {
    screen = screen,
    filter = tasklist_override.filter.allscreen,
    update_function = tasklist.render,
    source = function(s)
      local list = {}
      local tags = s.tags
      for k, v in ipairs(tags) do
        for i, c in ipairs(v:clients()) do
          if not (c.skip_taskbar or c.hidden or c.type == "splash" or c.type == "dock" or c.type == "desktop") then
            if c ~= nil and c.class ~= nil then
              if list[c.class] == nil then
                list[c.class] = {}
              end
              table.insert(list[c.class], c)
            end
          end
        end
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
        function(items, widgetCache)
          local groupHasFocus = nil
          for _, c in ipairs(items) do
            if c == client.focus then
              groupHasFocus = c
              break
            end
          end

          if groupHasFocus ~= nil then
            for _, c in ipairs(items) do
              c.minimized = true
            end
          else
            items[1].minimized = false
            if not items[1]:isvisible() and items[1].first_tag then
              items[1].first_tag:view_only()
            end
            client.focus = items[1]
            items[1]:raise()
          end
        end
      ),
      awful.button(
        {awful.util.modkey},
        2,
        function(items, widgetCache)
          for _, c in ipairs(items) do
            if c == client.focus then
              c:kill()
            end
          end
        end
      ),
      awful.button(
        {},
        4,
        function(items)
          local activeIndex = 0
          for i, c in pairs(items) do
            if c.active then
              activeIndex = i
              break
            end
          end

          if activeIndex == 0 then
            return
          end

          if activeIndex == #items then
            activeIndex = 1
          else
            activeIndex = activeIndex + 1
          end

          items[activeIndex]:activate {
            switch_to_tag = true,
            raise = true
          }
        end
      ),
      awful.button(
        {},
        5,
        function(items)
          local activeIndex = 0
          for i, c in pairs(items) do
            if c.active then
              activeIndex = i
              break
            end
          end

          if activeIndex == 0 then
            return
          end

          if activeIndex == 1 then
            activeIndex = #items
          else
            activeIndex = activeIndex - 1
          end

          items[activeIndex]:activate {
            switch_to_tag = true,
            raise = true
          }
        end
      )
    }
  }
end

function tasklist.mt:__call(...)
  return tasklist.new(...)
end

return setmetatable(tasklist, tasklist.mt)
