-- delete-marker.lua
-- Mark files for deletion during the current mpv session and delete them in bulk.
--
--   ctrl+shift+d  toggle the "to delete" mark on the current file
--   ctrl+shift+x  delete every marked file (asks for confirmation first)
--   ctrl+shift+c  unmark all files
--
-- Marks live only in this session's memory: they are never written to disk, so
-- reopening mpv or launching a second instance starts with an empty list, and
-- quitting forgets everything.

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

-- set of absolute paths flagged for deletion (path -> true)
local marked = {}
local confirming = false

-- persistent overlays: the top banner and the confirmation dialog
local banner = mp.create_osd_overlay("ass-events")
local dialog = mp.create_osd_overlay("ass-events")

-- Resolve a (possibly relative) path to an absolute one so the same file is
-- identified consistently whether it came from an argument or a playlist entry.
local function normalize(path)
    if not path then return nil end
    -- protocols (http://, etc.) and already-absolute paths are left as-is
    if path:find("://") or path:find("^/") or path:find("^%a:[/\\]") then
        return path
    end
    local cwd = mp.get_property("working-directory")
    if cwd then
        return utils.join_path(cwd, path)
    end
    return path
end

local function current_path()
    return normalize(mp.get_property("path"))
end

local function count_marked()
    local n = 0
    for _ in pairs(marked) do n = n + 1 end
    return n
end

-- Show/hide the persistent "TO DELETE" banner just under the top edge
-- (where a title bar would sit) whenever the current file is marked.
local function update_banner()
    local path = current_path()
    if path and marked[path] then
        banner.data = "{\\an8\\pos(0,52)\\fs34\\bord2\\shad1\\3c&H000000&\\c&H0000FF&\\b1}TO DELETE"
        banner:update()
    else
        banner.data = ""
        banner:update()
    end
end

local function toggle_mark()
    local path = current_path()
    if not path then
        mp.osd_message("Nothing to mark")
        return
    end
    if marked[path] then
        marked[path] = nil
        mp.osd_message("Unmarked (" .. count_marked() .. " marked)")
    else
        marked[path] = true
        mp.osd_message("Marked for deletion (" .. count_marked() .. " marked)")
    end
    update_banner()
end

local function unmark_all()
    local n = count_marked()
    if n == 0 then
        mp.osd_message("No files marked")
        return
    end
    marked = {}
    update_banner()
    mp.osd_message("Cleared " .. n .. " mark" .. (n == 1 and "" or "s"))
end

-- Remove marked entries from the current playlist so deleted files don't get
-- played, then unlink them from disk. Returns counts of deleted / failed.
local function perform_deletion()
    local playlist = mp.get_property_native("playlist") or {}
    for i = #playlist, 1, -1 do
        local fname = normalize(playlist[i].filename)
        if fname and marked[fname] then
            mp.commandv("playlist-remove", tostring(i - 1))
        end
    end

    local deleted, failed = 0, {}
    for path in pairs(marked) do
        local ok, err = os.remove(path)
        if ok then
            deleted = deleted + 1
        else
            table.insert(failed, path .. " (" .. tostring(err) .. ")")
            msg.error("failed to delete " .. path .. ": " .. tostring(err))
        end
    end

    marked = {}
    update_banner()
    return deleted, failed
end

local function end_confirmation()
    confirming = false
    mp.remove_key_binding("delete-marker-confirm-yes")
    mp.remove_key_binding("delete-marker-confirm-no")
    mp.remove_key_binding("delete-marker-confirm-esc")
    dialog.data = ""
    dialog:update()
end

local function confirm_yes()
    end_confirmation()
    local deleted, failed = perform_deletion()
    if #failed > 0 then
        mp.osd_message("Deleted " .. deleted .. ", " .. #failed .. " failed (see console)", 4)
    else
        mp.osd_message("Deleted " .. deleted .. " file" .. (deleted == 1 and "" or "s"), 3)
    end
end

local function confirm_no()
    end_confirmation()
    mp.osd_message("Deletion cancelled")
end

-- ASS-escape a string so filenames with braces/backslashes render literally.
local function ass_escape(s)
    return s:gsub("\\", "\\\239\187\191"):gsub("{", "\\{"):gsub("}", "\\}")
end

local function basename(path)
    return (path:gsub("[/\\]+$", ""):match("[^/\\]+$")) or path
end

local function request_delete()
    if confirming then return end
    local n = count_marked()
    if n == 0 then
        mp.osd_message("No files marked for deletion")
        return
    end

    -- build the confirmation dialog listing every marked file
    local lines = {
        "{\\b1\\c&H0000FF&}Delete " .. n .. " marked file" .. (n == 1 and "" or "s") .. "?{\\r}",
        "",
    }
    for path in pairs(marked) do
        table.insert(lines, "{\\c&HFFFFFF&}\\h\\h• " .. ass_escape(basename(path)))
    end
    table.insert(lines, "")
    table.insert(lines, "{\\c&H00FF00&}[y]{\\r} confirm    {\\c&H8080FF&}[n / ESC]{\\r} cancel")

    dialog.data = "{\\an5\\pos(" .. math.floor(1280 / 2) .. ",360)\\fs26\\bord2\\shad1\\3c&H000000&}"
        .. table.concat(lines, "\\N")
    dialog.res_x = 1280
    dialog.res_y = 720
    dialog:update()

    confirming = true
    mp.add_forced_key_binding("y", "delete-marker-confirm-yes", confirm_yes)
    mp.add_forced_key_binding("n", "delete-marker-confirm-no", confirm_no)
    mp.add_forced_key_binding("ESC", "delete-marker-confirm-esc", confirm_no)
end

-- keep the banner in sync as the playlist advances between files
mp.register_event("file-loaded", update_banner)

mp.add_key_binding("ctrl+shift+d", "toggle-delete-mark", toggle_mark)
mp.add_key_binding("ctrl+shift+x", "delete-marked-files", request_delete)
mp.add_key_binding("ctrl+shift+c", "unmark-all-files", unmark_all)
