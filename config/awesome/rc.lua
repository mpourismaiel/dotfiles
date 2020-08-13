local awesome, client, mouse, screen, tag = awesome, client, mouse, screen, tag
local ipairs, string, os, table, tostring, tonumber, type = ipairs, string, os, table, tostring, tonumber, type

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local lain = require("lain")
require("awful.autofocus")
require("utils.variables")

-- {{{ Error handling
-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
if awesome.startup_errors then
  naughty.notify(
    {
      preset = naughty.config.presets.critical,
      title = "Oops, there were errors during startup!",
      text = awesome.startup_errors
    }
  )
end

-- Handle runtime errors after startup
do
  local in_error = false
  awesome.connect_signal(
    "debug::error",
    function(err)
      if in_error then
        return
      end
      in_error = true

      naughty.notify(
        {
          preset = naughty.config.presets.critical,
          title = "Oops, an error happened!",
          text = tostring(err)
        }
      )
      in_error = false
    end
  )
end
-- }}}

awful.spawn.with_shell(string.format("sh %s/.config/awesome/autorun.sh", os.getenv("HOME")))

beautiful.init(string.format("%s/.config/awesome/themes/damn/theme.lua", os.getenv("HOME")))

require("screens")

local keys = require("keys")

local map, actions = {
    verbs = {
      m = "move",
      f = "focus",
      d = "delete",
      w = "swap"
    },
    adjectives = {h = "left", j = "down", k = "up", l = "right"},
    nouns = {c = "client", t = "tag", s = "screen", y = "layout"}
  },
  {}

function actions.client(action, adj)
  naughty.notify({text = "IN CLIENT! doing " .. action .. " to " .. adj})
end
function actions.tag(action, adj)
  if action == "focus" then
    if adj == "left" or adj == "up" then
      lain.util.tag_view_nonempty(-1, awful.screen.focused())
    elseif adj == "right" or adj == "down" then
      lain.util.tag_view_nonempty(1, awful.screen.focused())
    end

    return
  end
  naughty.notify({text = "IN TAG! doing " .. action .. " to " .. adj})
end
function actions.screen(action, adj)
  naughty.notify({text = "IN SCREEN! doing " .. action .. " to " .. adj})
end
function actions.layout(action, adj)
  naughty.notify({text = "IN LAYOUT! doing " .. action .. " to " .. adj})
end

local function parse(_, stop_key, _, sequence)
  local parsed, count = {verbs = "", adjectives = "", nouns = ""}, ""
  sequence = sequence .. stop_key

  for i = 1, #sequence do
    local char = sequence:sub(i, i)
    if char >= "0" and char <= "9" then
      count = count .. char
    else
      for kind in pairs(parsed) do
        parsed[kind] = map[kind][char] or parsed[kind]
      end
    end
  end

  if parsed.nouns == "" then
    return
  end
  for _ = 1, count == "" and 1 or tonumber(count) do
    actions[parsed.nouns](parsed.verbs, parsed.adjectives)
  end
end

root.keys(keys.globalkeys)

awful.keygrabber {
  start_callback = function()
    naughty.notify({text = "Is now active!"})
  end,
  stop_callback = parse,
  stop_key = gears.table.keys(map.verbs),
  stop_event = "press",
  export_keybindings = false,
  mask_modkeys = false
  -- root_keybindings = {
  --   {
  --     {awful.util.modkey},
  --     "v",
  --     function()
  --     end
  --   }
  -- }
}

require("rules")(keys)
require("signals")(awesome, screen, client, tag)
