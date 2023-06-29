local capi = {button = button, client = client}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")
local bench = require("helpers.bench")
local lgi = require("lgi")
local GLib = lgi.GLib
local icon_theme = require("helpers.icon_theme")()

local tasklist = {mt = {}}

local function get_current_focused_client(cache)
  local current_focused_client = client.focus
  local client_index_in_cache
  for i, c in ipairs(cache.clients) do
    if c == current_focused_client then
      client_index_in_cache = i
      break
    end
  end

  return client_index_in_cache
end

local function create_buttons(buttons, object)
  local btns = {}
  for _, src in ipairs(buttons) do
    for _, b in ipairs(src) do
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

local function set_markup_safely(tb, markup, backup_markup)
  local status, err =
    pcall(
    function()
      tb:set_markup(markup)
    end
  )
  if not status then
    tb:set_markup(backup_markup)
  end
end

local function set_title(c, tb)
  local escaped_text = GLib.markup_escape_text(c.name, -1)
  set_markup_safely(
    tb,
    string.format("<span color='#ffffff' font='Inter Medium 11'>%s</span>", escaped_text),
    string.format("<span color='#ffffff' font='Inter Medium 11'>%s</span>", c.class)
  )
end

local function custom_template(client_count)
  local l =
    wibox.widget {
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
              id = "indicator_list",
              layout = wibox.layout.fixed.vertical,
              spacing = config.dpi(3)
            }
          }
        }
      }
    }
  }

  local indicator_list = l:get_children_by_id("indicator_list")[1]
  for i = 1, client_count do
    indicator_list:add(
      wibox.widget.base.make_widget_from_value {
        widget = wibox.container.background,
        shape = gears.shape.rounded_rect,
        {
          widget = wibox.container.constraint,
          id = "size",
          strategy = "exact",
          width = config.dpi(3),
          height = config.dpi(6),
          {
            widget = wibox.widget.textbox
          }
        }
      }
    )
  end

  return {
    primary = l,
    background = l:get_children_by_id("background")[1],
    icon = l:get_children_by_id("icon")[1],
    indicator = indicator_list.children,
    update_callback = l.update_callback,
    create_callback = l.create_callback
  }
end

function tasklist.render(w, buttons, label, widgets_cache, objects, args)
  w:reset()
  for i, o in ipairs(objects) do
    local minKey = math.huge
    for k in pairs(o.clients) do
      minKey = math.min(k, minKey)
    end
    local first_client = o.clients[minKey]
    local cache = widgets_cache[o.class:lower()]
    if cache then
      cache.touched = true
      if cache.length ~= #o.clients then
        cache = nil
      elseif cache.buttons ~= buttons then
        cache = nil
      end
    end

    if not cache then
      cache = {
        w = custom_template(#o.clients),
        children = {},
        length = #o.clients,
        class = o.class,
        clients = o.clients,
        buttons = buttons,
        popup = nil,
        touched = true
      }

      if cache.length == 1 then
        cache.w.primary.buttons = {create_buttons(buttons.client, first_client)}
      else
        cache.w.primary.buttons = {create_buttons(buttons.group, cache)}
      end

      if cache.w.create_callback then
        cache.w.create_callback(cache.w.primary, o, i, objects)
      end

      cache._buttons = buttons

      local icon = icon_theme:get_client_icon_path(first_client)
      if icon == nil or icon == "" then
        icon = first_client.icon
      end
      if icon then
        cache.w.icon:set_image(icon)
      end

      cache.children = wibox.layout.fixed.vertical()
      cache.children.spacing = config.dpi(1)

      widgets_cache[first_client.class:lower()] = cache

      cache.popup =
        awful.popup {
        widget = cache.children,
        maximum_width = config.dpi(300),
        ontop = true,
        visible = false,
        bg = "#11111166",
        shape = function(cr, width, height)
          return gears.shape.rounded_rect(cr, width, height, config.dpi(4))
        end
      }
      cache.open_popup = function()
        local s = awful.screen.focused()
        cache.popup.visible = true
        cache.popup.screen = s
        cache.popup:geometry(
          {
            x = config.dpi(54),
            y = s.geometry.height / 2 - ((#objects * config.dpi(48)) / 2) + ((i - 1) * config.dpi(48))
          }
        )
      end

      cache.close_popup = function()
        cache.popup.visible = false
      end
    end

    cache.children:reset()
    for i, c in ipairs(o.clients) do
      local w =
        wibox.widget {
        widget = wibox.container.background,
        bg = "#11111166",
        {
          widget = wibox.container.margin,
          left = config.dpi(15),
          right = config.dpi(10),
          top = config.dpi(10),
          bottom = config.dpi(10),
          {
            layout = wibox.layout.fixed.horizontal,
            cache.w.icon,
            {
              widget = wibox.container.margin,
              left = config.dpi(10),
              {
                widget = wibox.widget.textbox,
                id = "title",
                markup = "<span color='#dddddd' font='Inter Medium 11'>" .. c.class .. "</span>"
              }
            }
          }
        }
      }
      set_title(c, w:get_children_by_id("title")[1])

      w.buttons = create_buttons(buttons.client, c)
      cache.children:add(w)
    end
    if cache.popup.visible then
      cache.close_popup()
      cache.open_popup()
    end

    for i, c in ipairs(o.clients) do
      local is_focused, is_urgent = false, false
      cache.w.indicator[i].bg = "#ffffff44"
      cache.children.children[i].bg = "#11111166"
      if
        c.active or
          (capi.client.focus and capi.client.focus.skip_taskbar and
            capi.client.focus:get_transient_for_matching(
              function(cl)
                return not cl.skip_taskbar
              end
            ) == c)
       then
        is_focused = true
        cache.w.indicator[i].bg = "#ffffff88"
        cache.children.children[i].bg = "#111111ff"
      end

      if c.urgent then
        is_urgent = true
        cache.w.indicator[i].bg = "#ff000088"
      end

      if is_focused or is_urgent then
        cache.w.indicator[i]:get_children_by_id("size")[1].height = config.dpi(12)
      else
        cache.w.indicator[i]:get_children_by_id("size")[1].height = config.dpi(5)
      end

      set_title(c, cache.children.children[i]:get_children_by_id("title")[1])
    end

    w:add(cache.w.primary)
  end

  for i, o in pairs(widgets_cache) do
    if not o.touched then
      widgets_cache[i] = nil
    else
      o.touched = false
    end
  end
end

function tasklist.new(screen)
  local backdrop =
    wibox {
    ontop = true,
    screen = screen,
    bg = "#ffffff00",
    type = "utility",
    x = screen.geometry.x,
    y = screen.geometry.y,
    width = screen.geometry.width,
    height = screen.geometry.height
  }

  return awful.widget.tasklist {
    screen = screen,
    filter = awful.widget.tasklist.filter.allscreen,
    update_function = tasklist.render,
    source = function(s, args)
      local list = {}
      local tags = s.tags
      for k, v in ipairs(tags) do
        for i, c in ipairs(v:clients()) do
          local class = c.class

          local found_group = nil
          for _, v in ipairs(list) do
            if v.class == class then
              found_group = v
              break
            end
          end

          if found_group ~= nil then
            table.insert(found_group.clients, c)
          else
            -- create group
            table.insert(list, {class = class, clients = {c}})
          end
        end
      end
      return list
    end,
    layout = {
      layout = wibox.layout.fixed.vertical
    },
    buttons = {
      client = {
        awful.button(
          {},
          1,
          function(c)
            if c == nil then
              return
            end
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
      },
      group = {
        awful.button(
          {},
          1,
          function(group)
            backdrop.visible = true
            backdrop.screen = awful.screen.focused()
            backdrop:buttons(
              awful.util.table.join(
                awful.button(
                  {},
                  1,
                  function()
                    backdrop.visible = false
                    group.close_popup()
                  end
                )
              )
            )
            group.open_popup()
          end
        ),
        awful.button(
          {},
          4,
          function(cache)
            local client_index_in_cache = get_current_focused_client(cache) or 2
            local prev_client = cache.clients[client_index_in_cache - 1]
            if not prev_client then
              prev_client = cache.clients[#cache.clients]
            end
            client.focus = prev_client
            prev_client:raise()
            prev_client.first_tag:view_only()
          end
        ),
        awful.button(
          {},
          5,
          function(cache)
            local client_index_in_cache = get_current_focused_client(cache) or 0
            local next_client = cache.clients[client_index_in_cache + 1]
            if not next_client then
              next_client = cache.clients[1]
            end
            client.focus = next_client
            next_client:raise()
            next_client.first_tag:view_only()
          end
        )
      }
    }
  }
end

function tasklist.mt:__call(...)
  return tasklist.new(...)
end

return setmetatable(tasklist, tasklist.mt)
