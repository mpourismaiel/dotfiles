local capi = {button = button, client = client}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")

local taglist = {mt = {}}
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
    create_callback = function(self, c3, index, objects)
      self:connect_signal(
        "mouse::enter",
        function()
          awesome.emit_signal("bling::tag_preview::update", c3)
          awesome.emit_signal("bling::tag_preview::visibility", s, true)
        end
      )
      self:connect_signal(
        "mouse::leave",
        function()
          awesome.emit_signal("bling::tag_preview::visibility", s, false)
        end
      )
    end,
    widget = wibox.container.constraint,
    strategy = "exact",
    width = config.dpi(48),
    height = config.dpi(16),
    {
      widget = wibox.container.place,
      {
        id = "indicator",
        widget = wibox.container.background,
        shape = gears.shape.circle,
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(9),
          height = config.dpi(9)
        }
      }
    }
  }
  local l = wibox.widget.base.make_widget_from_value(template)

  return {
    indicator = l:get_children_by_id("indicator")[1],
    primary = l,
    update_callback = l.update_callback,
    create_callback = l.create_callback
  }
end

function taglist.render(w, buttons, label, data, objects, args)
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

    cache.indicator:set_bg("#ffffff44")

    if o.selected then
      cache.indicator:set_bg("#ffffffff")
    end

    w:add(cache.primary)
  end
end

function taglist.new(screen)
  return awful.widget.taglist {
    screen = screen,
    filter = awful.widget.taglist.filter.all,
    update_function = taglist.render,
    layout = {
      layout = wibox.layout.fixed.vertical
    },
    buttons = {
      awful.button(
        {},
        1,
        function(t)
          t:view_only()
        end
      ),
      awful.button(
        {modkey},
        1,
        function(t)
          if client.focus then
            client.focus:move_to_tag(t)
          end
        end
      ),
      awful.button({}, 3, awful.tag.viewtoggle),
      awful.button(
        {modkey},
        3,
        function(t)
          if client.focus then
            client.focus:toggle_tag(t)
          end
        end
      ),
      awful.button(
        {},
        4,
        function(t)
          awful.tag.viewprev(t.screen)
        end
      ),
      awful.button(
        {},
        5,
        function(t)
          awful.tag.viewnext(t.screen)
        end
      )
    }
  }
end

function taglist.mt:__call(...)
  return taglist.new(...)
end

return setmetatable(taglist, taglist.mt)
