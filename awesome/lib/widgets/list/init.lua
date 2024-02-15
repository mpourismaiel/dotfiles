local capi = {
  screen = screen,
  awesome = awesome,
  client = client
}
local setmetatable = setmetatable
local ipairs = ipairs
local wibox = require("wibox")
local timer = require("gears.timer")
local base = require("wibox.widget.base")

local list = {mt = {}}

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

function list.render_list(w, template, render_template, buttons, data, source)
  w:reset()
  for i, o in ipairs(source) do
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
      cache.update_callback(cache.primary, o, i, source)
    end

    render_template(cache, o, i)

    w:add(cache.primary)
  end
end

local function render_empty(w, empty_widget)
  w:reset()

  if empty_widget == nil then
    empty_widget = wibox.widget.textbox("")
  end

  w:add(wibox.widget.base.make_widget_from_value(empty_widget))
end

local function list_update(w, render_list, template, render_template, source, data, empty_widget)
  if #source == 0 then
    render_empty(w, empty_widget)
  else
    render_list(w, template, render_template, buttons, data, source)
  end
end

-- args             table with the following fields
--   .layout           function required layout of the list
--   .render_list      function optional to generate the item template, fill the
--                       template with data and append it to the list
--   .template         function required to generate item template
--   .render_template  function required to fill the data in the item template
--   .source           function required that will return an array of data to be
--                       used for generating items
-- sample =
--   list.new(
--   {
--     layout = wibox.layout.fixed.horizontal,
--     render_list = list.render_list,
--     template = function()
--       return wibox.widget.textbox()
--     end,
--     render_template = function(widget_from_cache, data)
--       widget_from_cache:set_markup(data.title)
--     end,
--     source = function()
--       local list = {}
--       list[1] = {}
--       list[1].title = "sample"
--       return list
--     end
--   }
-- )
function list.new(args)
  local w = base.make_widget_from_value(args.layout == nil and wibox.layout.fixed.vertical or args.layout)
  if args.buttons ~= nil then
    w:buttons(args.buttons)
  end

  local data = setmetatable({}, {__mode = "k"})
  local queued_update = false

  function w._do_list_update_now()
    list_update(
      w,
      args.render_list == nil and list.render_list or args.render_list,
      args.template,
      args.render_template,
      args.source(w.start, w.finish),
      data,
      args.empty_widget
    )
    queued_update = false
  end

  function w._do_list_update()
    -- Add a delayed callback for the first update.
    if not queued_update then
      timer.delayed_call(
        function()
          w._do_list_update_now()
        end
      )
      queued_update = true
    end
  end

  w._do_list_update("", 0)
  w:connect_signal(
    "update",
    function(w)
      w._do_list_update()
      w:emit_signal("updated")
    end
  )
  return w
end

function list.mt:__call(...)
  return list.new(...)
end

return setmetatable(list, list.mt)
