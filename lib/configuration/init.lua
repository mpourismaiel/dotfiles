local capi = {
  awesome = awesome
}
local awful = require("awful")
local gears = require("gears")
local bling = require("external.bling")
local filesystem = require("gears.filesystem")
local inotify = require("lib.helpers.inotify")
local xresources = require("beautiful.xresources")
local machi = require("layout-machi")
local debounce = require("lib.helpers.debounce")
local table_helpers = require("lib.helpers.table")

local config_dir = filesystem.get_configuration_dir()
local images_dir = filesystem.get_configuration_dir() .. "/images"
local auto_start_file_name = "/autostart"
local configuration_override_filename = "/configuration.json"
local bling_layouts = {
  "mstab",
  "centered",
  "vertical",
  "horizontal",
  "equalarea",
  "deck"
}

local config = {
  dir = config_dir .. "config",
  terminal = "xfce4-terminal",
  taskManager = "system-monitoring-center",
  modkey = "Mod4",
  dpi = xresources.apply_dpi,
  wallpaper = os.getenv("HOME") .. "/Pictures/wallpaper.jpg",
  profile_image = nil,
  images_dir = images_dir,
  auto_start = {
    debug_mode = false,
    apps = {
      -- Compositor
      "picom --config " .. config_dir .. "/lib/picom.conf",
      -- Polkit and keyring
      "/usr/bin/lxqt-policykit-agent &" .. " eval $(gnome-keyring-daemon -s --components=pkcs11,secrets,ssh,gpg)",
      -- Load X colors
      "xrdb $HOME/.Xresources",
      -- Audio equalizer
      "pulseeffects --gapplication-service",
      -- Lockscreen timer
      [[
      xidlehook --not-when-fullscreen --not-when-audio --timer 600 \
      "awesome-client 'awesome.emit_signal(\"module::lockscreen::show\")'" ""
      ]]
    }
  },
  commands = {
    rofi_appmenu = "bash " .. config_dir .. "lib/rofi/launcher.sh " .. config_dir .. "lib/rofi",
    full_screenshot = "flameshot full -p /home/mahdi/Pictures/Screenshots/ -c",
    area_screenshot = "flameshot gui",
    bluetooth = "blueman-manager"
  },
  available_layouts = {"max", "tile", "floating"},
  tags = {
    {
      name = "1",
      layout = awful.layout.suit.max
    },
    {
      name = "2",
      layout = awful.layout.suit.max
    },
    {
      name = "3",
      layout = awful.layout.suit.tile
    },
    {
      name = "4",
      layout = awful.layout.suit.max
    },
    {
      name = "5",
      layout = awful.layout.suit.max
    },
    {
      name = "6",
      layout = awful.layout.suit.max
    }
  }
}

config.auto_start_extra = config.dir .. auto_start_file_name

local function file_exists(file)
  local f = io.open(file, "rb")
  if f then
    f:close()
  end
  return f ~= nil
end

local function lines_from(file)
  if not file_exists(file) then
    return {}
  end
  local lines = {}
  for line in io.lines(file) do
    if string.sub(line, 1, 1) ~= "#" then
      lines[#lines + 1] = line
    end
  end
  return lines
end

local function handle_nested_config_values(k, v)
  if config[k] == nil then
    config[k] = {}
  end

  if k == "tags" then
    local tags = {}
    for _, tag in pairs(v) do
      if type(tag) == "table" then
        local configured_tag = {}
        for tag_key, tag_name in pairs(tag) do
          if tag_key == "layout" then
            local found = false
            for _, layout in ipairs(bling_layouts) do
              if layout == tag_name then
                found = true
                break
              end
            end

            if found then
              configured_tag[tag_key] = bling.layout[tag_name]
            elseif tag_name == "machi" then
              configured_tag[tag_key] = machi.default_layout
            else
              configured_tag[tag_key] = awful.layout.suit[tag_name]
            end
          else
            configured_tag[tag_key] = tag_name
          end
        end
        table.insert(tags, configured_tag)
      end
    end
    config.tags = tags
  else
    for nested_key, nested_value in pairs(v) do
      config[k][nested_key] = nested_value
    end
  end
end

local function load_layout_functions()
  local available_layouts = {}
  for _, layout in ipairs(config.available_layouts) do
    local found = false
    for _, bling_layout in ipairs(bling_layouts) do
      if bling_layout == layout then
        found = true
        break
      end
    end

    if found then
      table.insert(available_layouts, bling.layout[layout])
    elseif layout == "machi" then
      table.insert(available_layouts, machi.default_layout)
    else
      table.insert(available_layouts, awful.layout.suit[layout])
    end
  end
  config.available_layouts = available_layouts
end

local function initialize_config_file()
  config.initialized = true

  if file_exists(config.dir .. configuration_override_filename) then
    local json = require("external.json")
    local f = io.open(config.dir .. configuration_override_filename, "rb")
    if not f then
      return
    end

    local content = f:read("*all")
    f:close()

    local config_override_table = json.decode(content)
    for k, v in pairs(config_override_table) do
      if type(v) == "table" then
        handle_nested_config_values(k, v)
      else
        config[k] = v
      end
    end
  end

  load_layout_functions()
end

local function watch_changes()
  inotify:watch(
    config.dir .. configuration_override_filename,
    {
      inotify.events.create,
      inotify.events.modify,
      inotify.events.delete,
      inotify.events.moved_from,
      inotify.events.moved_to,
      inotify.events.move_self,
      inotify.events.delete_self,
      inotify.events.attrib
    }
  ):connect_signal(
    "event",
    debounce(
      function()
        local old_config = table_helpers.deepClone(config)
        initialize_config_file()
        capi.awesome.emit_signal("module::config::changed", config)

        local diff = table_helpers.generateTableDiff(old_config, config)
        for k, v in pairs(diff) do
          capi.awesome.emit_signal("module::config::changed_" .. k, v)
        end
      end,
      0.2
    )
  )
end

if config.initialized ~= true then
  if file_exists(config.auto_start_extra) then
    local lines = lines_from(config.auto_start_extra)
    config.auto_start.apps = gears.table.join(config.auto_start.apps, lines)
  end
  initialize_config_file()
  watch_changes()
end

return config
