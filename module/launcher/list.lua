local capi = {
  screen = screen,
  awesome = awesome,
  client = client
}
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local table = table
local common = require("awful.widget.common")
local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local surface = require("gears.surface")
local timer = require("gears.timer")
local gcolor = require("gears.color")
local gstring = require("gears.string")
local gdebug = require("gears.debug")
local filesystem = require("gears.filesystem")
local base = require("wibox.widget.base")
local json = require("lib.json")
local fuzzy = require("lib.fuzzy")
local config = require("configuration.config")
local helpers = require("module.helpers")
local open = io.open
local config_dir = filesystem.get_configuration_dir()

local function read_file(path)
  local file = open(path, "rb")
  if not file then
    return nil
  end
  local content = file:read "*a"
  file:close()
  return content
end

local function read_app_list()
  return json.decode(read_file(os.getenv("HOME") .. "/.config/awesome/module/launcher/list.json")).list
end

local function get_screen(s)
  return s and capi.screen[s]
end

local launcher = {mt = {}}
launcher.filter, launcher.source = {}, {}

local function create_callback(w, app)
  common._set_common_property(w, "app", app)
end

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

local function template(args)
  local template = {
    widget = wibox.container.background,
    bg = "#00000000",
    shape = gears.shape.rounded_rect,
    id = "select_indicator",
    {
      widget = wibox.container.margin,
      margins = config.dpi(16),
      {
        layout = wibox.layout.fixed.vertical,
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(72),
          height = config.dpi(72),
          {
            widget = wibox.container.place,
            halign = "center",
            {
              id = "icon",
              widget = wibox.widget.imagebox
            }
          }
        },
        {
          widget = wibox.container.margin,
          top = config.dpi(16),
          {
            widget = wibox.container.constraint,
            strategy = "exact",
            width = config.dpi(110),
            height = config.dpi(24),
            {
              widget = wibox.container.place,
              halign = "center",
              {
                id = "label",
                widget = wibox.widget.textbox
              }
            }
          }
        }
      }
    }
  }
  local l = wibox.widget.base.make_widget_from_value(template)

  return {
    icon = l:get_children_by_id("icon")[1],
    label = l:get_children_by_id("label")[1],
    select_indicator = l:get_children_by_id("select_indicator")[1],
    primary = l,
    update_callback = l.update_callback,
    create_callback = l.create_callback
  }
end

function launcher.renderApps(w, buttons, data, objects, args)
  w:reset()
  w.spacing = config.dpi(12)
  local row = nil
  for i, o in ipairs(objects) do
    if o.icon ~= "" then
      if i % 7 == 1 then
        row = wibox.layout.fixed.horizontal()
        row.spacing = config.dpi(24)
        w:add(row)
      end
      local cache = data[o]

      -- Allow the buttons to be replaced.
      if cache and cache._buttons ~= buttons then
        cache = nil
      end

      if not cache then
        cache = template()

        cache.primary.buttons = {create_buttons(buttons, o)}

        if cache.create_callback then
          cache.create_callback(cache.primary, o)
        end

        cache._buttons = buttons
        data[o] = cache
      elseif cache.update_callback then
        cache.update_callback(cache.primary, o, i, objects)
      end

      cache.icon:set_image(o.icon)
      cache.label:set_markup("<span color='#ffffff' font='Inter Bold 10'><b>" .. o.name .. "</b></span>")
      cache.select_indicator.bg = o.selected and "#ffffff33" or "#00000000"

      row:add(cache.primary)
    end
  end
end

local function source(list, query, page, selected)
  local apps = {}

  for _, app in ipairs(list) do
    if app.name ~= nil and (query == "" or fuzzy.has_match(query == nil and "" or query, app.name)) then
      app.selected = false
      table.insert(apps, app)
    end
  end

  apps = helpers.table.slice(apps, page * 28, (page + 1) * 28)
  if selected < 1 then
    selected = 1
    awesome.emit_signal("launcher:update:selected", selected)
  elseif selected > #apps then
    selected = #apps
    awesome.emit_signal("launcher:update:selected", selected)
  end
  if #apps > 0 then
    apps[selected].selected = true
  end

  return apps
end

local function launcher_update(s, w, list, query, page, selected, data, args)
  local apps = source(list, query, page, selected)

  launcher.renderApps(
    w,
    nil,
    data,
    apps,
    {
      widget_template = args.widget_template,
      create_callback = create_callback
    }
  )
end

function launcher.new(args)
  local screen = get_screen(args.screen)

  local w = base.make_widget_from_value(wibox.layout.fixed.vertical)

  local data = setmetatable({}, {__mode = "k"})

  local queued_update = {}
  local list = read_app_list()

  function w._do_launcher_update_now(query, page, selected)
    if screen.valid then
      local q = query == nil and "" or query
      local p = page == nil and 0 or page
      local s = selected == nil and 1 or selected
      launcher_update(screen, w, list, q, p, s, data, args)
    end
    queued_update[screen] = false
  end

  function w._do_launcher_update(query, page, selected)
    -- Add a delayed callback for the first update.
    if not queued_update[screen] then
      timer.delayed_call(
        function()
          w._do_launcher_update_now(query, page, selected)
        end
      )
      queued_update[screen] = true
    end
  end

  w._do_launcher_update("", 0)
  w:connect_signal(
    "launcher:list:update",
    function(w, query, page, selected)
      w._do_launcher_update(query, page, selected)
    end
  )
  w:connect_signal(
    "launcher:exec_object",
    function(w, parent, object)
      awful.spawn((parent == nil and "mullvad-exclude " or parent .. " ") .. object.executable)
      awful.spawn("node " .. config_dir .. "module/launcher/list.js score " .. object.desktop)
    end
  )
  w:connect_signal(
    "launcher:exec",
    function(w, parent, query, page, selected)
      local q = query == nil and "" or query
      local p = page == nil and 0 or page
      local s = selected == nil and 1 or selected
      local apps = source(list, q, p, s)
      if #apps > 0 then
        w:emit_signal("launcher:exec_object", parent == "" and nil or parent, apps[s])
        list = read_app_list()
      end
    end
  )
  return w
end

function launcher.mt:__call(...)
  return launcher.new(...)
end

return setmetatable(launcher, launcher.mt)
