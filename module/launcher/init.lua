local Gio = require("lgi").Gio
local awful = require("awful")
local gears = require("gears")
local gtable = require("gears.table")
local gobject = require("gears.object")
local icon_theme = require("bling.helpers.icon_theme")
local path = ...

local function case_insensitive_pattern(pattern)
  -- find an optional '%' (group 1) followed by any character (group 2)
  local p =
    pattern:gsub(
    "(%%?)(.)",
    function(percent, letter)
      if percent ~= "" or not letter:match("%a") then
        -- if the '%' matched, or `letter` is not a letter, return "as is"
        return percent .. letter
      else
        -- else, return a case-insensitive character class of the matched letter
        return string.format("[%s%s]", letter:lower(), letter:upper())
      end
    end
  )

  return p
end

local function has_value(tab, val)
  for index, value in pairs(tab) do
    if val:find(case_insensitive_pattern(value)) then
      return true
    end
  end
  return false
end

local function generate_apps(self)
  self._private.all_entries = {}
  self._private.matched_entries = {}

  local app_info = Gio.AppInfo
  local apps = app_info.get_all()
  if self.sort_alphabetically then
    table.sort(
      apps,
      function(a, b)
        local app_a_score = app_info.get_name(a):lower()
        if has_value(self.favorites, app_info.get_name(a)) then
          app_a_score = "aaaaaaaaaaa" .. app_a_score
        end
        local app_b_score = app_info.get_name(b):lower()
        if has_value(self.favorites, app_info.get_name(b)) then
          app_b_score = "aaaaaaaaaaa" .. app_b_score
        end

        return app_a_score < app_b_score
      end
    )
  elseif self.reverse_sort_alphabetically then
    table.sort(
      apps,
      function(a, b)
        local app_a_score = app_info.get_name(a):lower()
        if has_value(self.favorites, app_info.get_name(a)) then
          app_a_score = "zzzzzzzzzzz" .. app_a_score
        end
        local app_b_score = app_info.get_name(b):lower()
        if has_value(self.favorites, app_info.get_name(b)) then
          app_b_score = "zzzzzzzzzzz" .. app_b_score
        end

        return app_a_score > app_b_score
      end
    )
  else
    table.sort(
      apps,
      function(a, b)
        local app_a_favorite = has_value(self.favorites, app_info.get_name(a))
        local app_b_favorite = has_value(self.favorites, app_info.get_name(b))

        if app_a_favorite and not app_b_favorite then
          return true
        elseif app_b_favorite and not app_a_favorite then
          return false
        elseif app_a_favorite and app_b_favorite then
          return app_info.get_name(a):lower() < app_info.get_name(b):lower()
        else
          return false
        end
      end
    )
  end

  local icon_theme = icon_theme(self.icon_theme, self.icon_size)

  for _, app in ipairs(apps) do
    if app.should_show(app) then
      local name = app_info.get_name(app)
      local commandline = app_info.get_commandline(app)
      local executable = app_info.get_executable(app)
      local icon = icon_theme:get_gicon_path(app_info.get_icon(app))

      if icon == "" then
        if self.default_app_icon_name ~= nil then
          icon = icon_theme:get_icon_path(self.default_app_icon_name)
        elseif self.default_app_icon_path ~= nil then
          icon = self.default_app_icon_path
        else
          icon = icon_theme:choose_icon({"application-all", "application", "application-default-icon", "app"})
        end
      end

      local desktop_app_info = Gio.DesktopAppInfo.new(app_info.get_id(app))
      local terminal = Gio.DesktopAppInfo.get_string(desktop_app_info, "Terminal") == "true" and true or false
      local generic_name = Gio.DesktopAppInfo.get_string(desktop_app_info, "GenericName") or nil

      table.insert(
        self._private.all_entries,
        {
          name = name,
          generic_name = generic_name,
          commandline = commandline,
          executable = executable,
          terminal = terminal,
          icon = icon
        }
      )
    end
  end
end

local launcher = {mt = {}}

function launcher.new()
  local ret = gobject({})
  ret._private = {}
  ret._private.text = ""
  ret.favorites = {}
  ret.sort_alphabetically = false
  ret.reverse_sort_alphabetically = false

  gtable.crush(ret, launcher)

  local kill_old_inotify_process_script =
    [[ ps x | grep "inotifywait -e modify /usr/share/applications" | grep -v grep | awk '{print $1}' | xargs kill ]]
  local subscribe_script = [[ bash -c "while (inotifywait -e modify /usr/share/applications -qq) do echo; done" ]]

  awful.spawn.easy_async_with_shell(
    kill_old_inotify_process_script,
    function()
      awful.spawn.with_line_callback(
        subscribe_script,
        {
          stdout = function(_)
            generate_apps(ret)
          end
        }
      )
    end
  )

  generate_apps(ret)

  return ret
end

function launcher.mt:__call(...)
  return launcher.new(...)
end

return setmetatable(launcher, launcher.mt)
