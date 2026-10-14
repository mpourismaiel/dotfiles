--[[ shelf — media library grid + top-left Actions dropdown for mpv

Two mouse-first surfaces drawn with ASS overlays (uosc stays in charge of the
timeline/controls/menus):

  Library  — shown when mpv is idle (bare `mpv`), at playlist end, or on
             Tab / middle click / the uosc "Library" button. Every configured
             directory (script-opts/shelf.conf `dirs`, default ~/Videos) and
             each of its subfolders is a collapsible section titled by the
             folder name (root open, subfolders closed by default; a "One
             folder at a time" checkbox makes them an accordion — both
             persisted in ~/.local/state/mpv/shelf.json), its media laid out
             as a grid of thumbnail cards. Thumbnails are rendered by ffmpeg
             into ~/.cache/mpv/shelf/*.bgra and displayed with `overlay-add`.
             The same grid doubles as the playlist view (shelf/playlist, the
             uosc playlist button, Ctrl+P): sections per directory, current
             item marked, click = playlist-play-index.
  Actions  — a ☰ button in the top-left strip (F1) that drops down a cascading
             menu of every binding in input.conf, grouped by the `#! Section >
             Item` comments (same convention uosc's menu reads). Clicking an
             item runs its command, so every hotkey has a button.

Script bindings: shelf/toggle-library, shelf/playlist, shelf/toggle-actions, shelf/rescan.
]]

local mp = require('mp')
local utils = require('mp.utils')
local msg = require('mp.msg')
local options = require('mp.options')

-- ---------------------------------------------------------------- options --
local o = {
	dirs = '~/Videos',
	depth = 2,
	sort = 'mtime',
	show_on_idle = true,
	show_on_eof = true,
	card_width = 236,
	scale = 1,
	thumb_position = 0.2,
	jobs = 3,
	cache_dir = '~~cache/shelf',
	video_types = '3g2,3gp,asf,avi,f4v,flv,h264,h265,m2ts,m4v,mkv,mov,mp4,mp4v,mpeg,mpg,ogm,ogv,rm,rmvb,ts,vob,webm,wmv,y4m',
	audio_types = 'aac,ac3,aiff,ape,au,dsf,dts,flac,m4a,mka,mp3,mp4a,oga,ogg,opus,wav,weba,wma,wv',
	image_types = 'avif,bmp,gif,jpeg,jpg,jxl,png,tif,tiff,webp',
	top_reveal = 120,
	click_to_pause = false,
	click_threshold = 250,
	state_file = '~~state/shelf.json',
}
options.read_options(o, 'shelf')

-- ------------------------------------------------------------------ theme --
-- Mirrors quickshell/pill Theme.qml (Terminal 79): clay surfaces, cream text,
-- gold accents, IBM Plex + DM Serif Display + Material Symbols.
local T = {
	bg = '1b1712', surface = '221d16', surface2 = '2a241c', hover = '3a271c',
	line = 'ece4d6', text = 'efe9dd', dim = 'a89e8c', faint = '6f6557',
	gold = 'd9a441', accent = 'cf4636', black = '000000', thumb_bg = '14110c',
	font = 'IBM Plex Sans', serif = 'DM Serif Display', mono = 'IBM Plex Mono',
	icon = 'Material Symbols Rounded',
}

-- -------------------------------------------------------------- ass utils --
local function bgr(hex) return hex:sub(5, 6) .. hex:sub(3, 4) .. hex:sub(1, 2) end
local function alpha_hex(opacity)
	local a = math.floor((1 - math.max(0, math.min(1, opacity))) * 255 + 0.5)
	return string.format('%02X', a)
end
local function round(n) return math.floor(n + 0.5) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function esc(s)
	s = tostring(s or '')
	s = s:gsub('\\', '\\\226\129\160'):gsub('{', '\\{'):gsub('}', '\\}'):gsub('\n', ' ')
	s = s:gsub('^ ', '\\h')
	return s
end

local function rrect_path(x1, y1, x2, y2, r)
	r = math.min(r or 0, (x2 - x1) / 2, (y2 - y1) / 2)
	if r <= 0.5 then
		return string.format('m %.1f %.1f l %.1f %.1f %.1f %.1f %.1f %.1f', x1, y1, x2, y1, x2, y2, x1, y2)
	end
	local k = 0.5523 * r
	return string.format(
		'm %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f',
		x1 + r, y1, x2 - r, y1,
		x2 - r + k, y1, x2, y1 + r - k, x2, y1 + r,
		x2, y2 - r,
		x2, y2 - r + k, x2 - r + k, y2, x2 - r, y2,
		x1 + r, y2,
		x1 + r - k, y2, x1, y2 - r + k, x1, y2 - r,
		x1, y1 + r,
		x1, y1 + r - k, x1 + r - k, y1, x1 + r, y1)
end

local Ass = {}
Ass.__index = Ass
function Ass.new() return setmetatable({ buf = {} }, Ass) end
function Ass:raw(s) self.buf[#self.buf + 1] = s end
-- p: color, opacity, radius, border, border_color, border_opacity, clip
function Ass:rect(x1, y1, x2, y2, p)
	p = p or {}
	local border = p.border or 0
	local tags = string.format('{\\an7\\pos(0,0)\\bord%s\\shad0\\1c&H%s&\\1a&H%s&\\3c&H%s&\\3a&H%s&%s\\p1}',
		border, bgr(p.color or T.surface), alpha_hex(p.opacity == nil and 1 or p.opacity),
		bgr(p.border_color or T.line), alpha_hex(p.border_opacity == nil and 1 or p.border_opacity),
		p.clip and ('\\clip(' .. p.clip .. ')') or '')
	self:raw(tags .. rrect_path(x1, y1, x2, y2, p.radius) .. '{\\p0}\n')
end
-- p: size, font, color, opacity, bold, italic, border, border_color, clip, spacing
function Ass:text(x, y, align, str, p)
	p = p or {}
	local tags = string.format('{\\an%d\\pos(%.1f,%.1f)\\fn%s\\fs%.1f\\b%d\\i%d\\bord%s\\shad0\\1c&H%s&\\1a&H%s&\\3c&H%s&\\3a&H%s&\\q2%s%s}',
		align, x, y, p.font or T.font, p.size or 16, p.bold and 1 or 0, p.italic and 1 or 0,
		p.border or 0, bgr(p.color or T.text), alpha_hex(p.opacity == nil and 1 or p.opacity),
		bgr(p.border_color or T.bg), alpha_hex(p.opacity == nil and 1 or p.opacity),
		p.spacing and ('\\fsp' .. p.spacing) or '',
		p.clip and ('\\clip(' .. p.clip .. ')') or '')
	self:raw(tags .. esc(str) .. '\n')
end
function Ass:icon(x, y, align, name, p)
	p = p or {}
	p.font = T.icon
	self:text(x, y, align, name, p)
end
function Ass:render() return table.concat(self.buf) end

-- Rough text width (IBM Plex Sans averages ~0.53em per glyph) used for
-- ellipsizing; drawing also clips so a mis-estimate never overflows.
local function text_width(str, size, factor)
	local n = 0
	for _ in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do n = n + 1 end
	return n * size * (factor or 0.53)
end
local function ellipsize(str, size, max_w, factor)
	if text_width(str, size, factor) <= max_w then return str end
	local chars = {}
	for ch in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars + 1] = ch end
	local per = size * (factor or 0.53)
	local keep = math.max(1, math.floor(max_w / per) - 1)
	return table.concat(chars, '', 1, math.min(keep, #chars)) .. '…'
end

-- ------------------------------------------------------------------ state --
local display = { w = 1280, h = 720, hidpi = 1 }
local function S() return o.scale * display.hidpi end
local mouse = { x = -1, y = -1, hover = false }
local state = { idle = true, paused = false, title = '', uosc_menu = false, file_loaded = false, pl_pos = 0, pl_count = 0, fullscreen = false }

-- Actions dropdown state (declared early: the library's click handler checks dd.button)
local dd = { open = false, root = nil, hover_row = nil, open_cat = nil, hover_sub = nil, sel_col = 1, sel = nil, sel_sub = nil,
	rows = {}, subrows = {}, rect = nil, subrect = nil, button = nil, hover_button = false }

local lib_osd = mp.create_osd_overlay('ass-events')
lib_osd.z = -5 -- below uosc so its menus (open-file, …) draw on top of the grid
local top_osd = mp.create_osd_overlay('ass-events')
top_osd.z = 50 -- above uosc's elements

local render_pending = false
local render -- forward
local function request_render()
	if render_pending then return end
	render_pending = true
	mp.add_timeout(0.016, function()
		render_pending = false
		render()
	end)
end

-- ------------------------------------------------------------- key groups --
-- Forced bindings only exist while a surface is open, so during normal
-- playback input.conf/uosc keep every key.
local function make_keygroup(prefix)
	local group = { names = {}, on = false }
	function group:bind(key, fn, flags)
		local name = prefix .. '-' .. key:gsub('[^%w]', '_')
		self.names[#self.names + 1] = name
		mp.add_forced_key_binding(key, name, fn, flags)
	end
	function group:clear()
		for _, name in ipairs(self.names) do mp.remove_key_binding(name) end
		self.names = {}
	end
	return group
end

-- ----------------------------------------------------------------- thumbs --
local thumbs = { dir = nil, state = {}, queue = {}, running = 0 }

local function djb2(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return h
end

local function thumb_dims()
	local w = round(o.card_width * S())
	local h = round(w * 9 / 16)
	return w, h
end

local function ensure_cache_dir()
	if thumbs.dir then return thumbs.dir end
	local dir = mp.command_native({ 'expand-path', o.cache_dir })
	local info = utils.file_info(dir)
	if not info then
		mp.command_native({ name = 'subprocess', args = { 'mkdir', '-p', dir }, playback_only = false })
	end
	thumbs.dir = dir
	return dir
end

local function thumb_key(item)
	local w, h = thumb_dims()
	local base = item.name:gsub('%.[^.]+$', ''):gsub('[^%w%-]', '_'):sub(1, 40)
	return string.format('%s-%08x-%dx%d', base, djb2(item.path .. '|' .. item.mtime .. '|' .. item.size), w, h)
end

local function read_file(path)
	local f = io.open(path, 'r')
	if not f then return nil end
	local s = f:read('*a')
	f:close()
	return s
end

-- Returns the thumb record for an item, consulting the cache on first sight.
local function thumb_for(item)
	local rec = thumbs.state[item.path]
	if rec then return rec end
	local w, h = thumb_dims()
	if item.is_url then
		rec = { status = 'failed', w = w, h = h }
		thumbs.state[item.path] = rec
		return rec
	end
	local dir = ensure_cache_dir()
	local key = thumb_key(item)
	rec = { file = dir .. '/' .. key .. '.bgra', dur_file = dir .. '/' .. key .. '.dur',
		fail_file = dir .. '/' .. key .. '.fail', w = w, h = h, status = 'pending' }
	local info = utils.file_info(rec.file)
	if info and info.size == w * h * 4 then
		rec.status = 'ready'
	elseif utils.file_info(rec.fail_file) then
		rec.status = 'failed'
	end
	local dur = read_file(rec.dur_file)
	if dur then item.duration = tonumber(dur) end
	thumbs.state[item.path] = rec
	return rec
end

local pump_queue

local function run_thumb_job(item, rec)
	rec.status = 'running'
	thumbs.running = thumbs.running + 1
	local function finish(ok)
		thumbs.running = thumbs.running - 1
		rec.status = ok and 'ready' or 'failed'
		if not ok then
			local f = io.open(rec.fail_file, 'w')
			if f then f:write('x') f:close() end
		end
		request_render()
		pump_queue()
	end
	local function make_thumb(seek)
		local tmp = rec.file .. '.tmp'
		local vf = string.format('scale=%d:%d:force_original_aspect_ratio=decrease:flags=lanczos,pad=%d:%d:-1:-1:color=#%s,format=bgra',
			rec.w, rec.h, rec.w, rec.h, T.thumb_bg)
		local args = { 'ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y' }
		if seek > 0 then
			args[#args + 1] = '-ss'
			args[#args + 1] = string.format('%.2f', seek)
		end
		for _, a in ipairs({ '-i', item.path, '-map', '0:v:0', '-frames:v', '1', '-vf', vf, '-f', 'rawvideo', '-pix_fmt', 'bgra', tmp }) do
			args[#args + 1] = a
		end
		mp.command_native_async({ name = 'subprocess', args = args, playback_only = false, capture_stdout = true, capture_stderr = true },
			function(ok, res)
				local info = utils.file_info(tmp)
				if ok and res and res.status == 0 and info and info.size == rec.w * rec.h * 4 then
					os.rename(tmp, rec.file)
					finish(true)
				elseif seek > 0 then
					os.remove(tmp)
					make_thumb(0) -- short file / seek past the end: retry from the start
				else
					os.remove(tmp)
					msg.verbose('thumbnail failed for ' .. item.path .. ': ' .. ((res and res.stderr) or ''))
					finish(false)
				end
			end)
	end
	local probe = { 'ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', item.path }
	mp.command_native_async({ name = 'subprocess', args = probe, playback_only = false, capture_stdout = true, capture_stderr = true },
		function(ok, res)
			local dur = ok and res and res.status == 0 and tonumber((res.stdout or ''):match('[%d%.]+')) or nil
			if dur then
				item.duration = dur
				local f = io.open(rec.dur_file, 'w')
				if f then f:write(tostring(dur)) f:close() end
			end
			local seek = (dur and item.kind ~= 'image') and (dur * o.thumb_position) or 0
			make_thumb(seek)
		end)
end

pump_queue = function()
	while thumbs.running < o.jobs and #thumbs.queue > 0 do
		local item = table.remove(thumbs.queue, 1)
		local rec = thumbs.state[item.path]
		if rec and rec.status == 'pending' then run_thumb_job(item, rec) end
	end
end

local function queue_thumb(item, front)
	local rec = thumb_for(item)
	if rec.status ~= 'pending' or rec.queued then return end
	rec.queued = true
	if front then table.insert(thumbs.queue, 1, item) else thumbs.queue[#thumbs.queue + 1] = item end
end

-- Bitmap overlays sit above every ASS layer, so cards that collide with the
-- dropdown or a uosc menu drop their picture for the duration.
local overlays = { used = {}, free = {} }
-- Overlay commands go through the async queue on purpose: a synchronous
-- `overlay-add` returns only after mpv's core ran a playloop iteration, which
-- redraws (and waits for vsync) once per command. Thirty visible thumbnails
-- would cost thirty frames per scroll step. Queued async commands are all
-- processed before the next redraw, so a scroll step costs one frame.
local function ov(...) mp.command_native_async({ ... }, function() end) end
for id = 63, 0, -1 do if id ~= 42 then overlays.free[#overlays.free + 1] = id end end -- 42 belongs to thumbfast

local function overlays_clear()
	for id, _ in pairs(overlays.used) do
		ov('overlay-remove', id)
		overlays.free[#overlays.free + 1] = id
	end
	overlays.used = {}
end

local function overlays_sync(wanted) -- wanted: list of {path=file, x, y, w, h}
	local keep = {}
	for _, w in ipairs(wanted) do keep[w.file] = w end
	local by_file = {}
	for id, cur in pairs(overlays.used) do
		local w = keep[cur.file]
		if not w then
			ov('overlay-remove', id)
			overlays.used[id] = nil
			overlays.free[#overlays.free + 1] = id
		else
			by_file[cur.file] = id
			if cur.x ~= w.x or cur.y ~= w.y then
				ov('overlay-add', id, w.x, w.y, w.file, 0, 'bgra', w.w, w.h, w.w * 4)
				cur.x, cur.y = w.x, w.y
			end
		end
	end
	for _, w in ipairs(wanted) do
		if not by_file[w.file] and #overlays.free > 0 then
			local id = table.remove(overlays.free)
			ov('overlay-add', id, w.x, w.y, w.file, 0, 'bgra', w.w, w.h, w.w * 4)
			overlays.used[id] = { file = w.file, x = w.x, y = w.y }
		end
	end
end

-- ---------------------------------------------------------------- library --
local lib = { visible = false, mode = 'library', sections = {}, scanned = nil, items = {}, scroll = 0, max_scroll = 0,
	hover = nil, sel = nil, hover_header = nil, layout = nil, buttons = {}, hover_button = nil, focus_current = false }

-- Persisted UI state: accordion flag + per-section expanded overrides.
local persist = { accordion = false, expanded = {} }
local persist_path
local function persist_load()
	persist_path = mp.command_native({ 'expand-path', o.state_file })
	local raw = read_file(persist_path)
	if not raw then return end
	local data = utils.parse_json(raw)
	if type(data) == 'table' then
		persist.accordion = data.accordion and true or false
		persist.expanded = type(data.expanded) == 'table' and data.expanded or {}
	end
end
local function persist_save()
	if not persist_path then return end
	local dir = persist_path:match('^(.*)/[^/]+$')
	if dir and not utils.file_info(dir) then
		mp.command_native({ name = 'subprocess', args = { 'mkdir', '-p', dir }, playback_only = false })
	end
	local f = io.open(persist_path, 'w')
	if f then f:write(utils.format_json(persist)) f:close() end
end
persist_load()

local function section_expanded(section)
	local v = persist.expanded[section.path]
	if v ~= nil then return v end
	return section.default_open
end

local type_sets = {}
local function build_type_sets()
	for _, kind in ipairs({ 'video', 'audio', 'image' }) do
		type_sets[kind] = {}
		for ext in (o[kind .. '_types'] or ''):gmatch('[^,%s]+') do type_sets[kind][ext:lower()] = true end
	end
end
build_type_sets()

local function kind_of(name)
	local ext = name:match('%.([^.]+)$')
	if not ext then return nil end
	ext = ext:lower()
	for _, kind in ipairs({ 'video', 'audio', 'image' }) do
		if type_sets[kind][ext] then return kind end
	end
	return nil
end

local function join(a, b)
	if a:sub(-1) == '/' then return a .. b end
	return a .. '/' .. b
end

local function scan_dir(path, title, crumbs, depth, out)
	local files = utils.readdir(path, 'files') or {}
	local items = {}
	for _, name in ipairs(files) do
		if name:sub(1, 1) ~= '.' then
			local kind = kind_of(name)
			if kind then
				local full = join(path, name)
				local info = utils.file_info(full)
				if info and info.is_file then
					items[#items + 1] = { name = name, path = full, kind = kind, mtime = info.mtime or 0, size = info.size or 0 }
				end
			end
		end
	end
	if o.sort == 'name' then
		table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
	else
		table.sort(items, function(a, b)
			if a.mtime ~= b.mtime then return a.mtime > b.mtime end
			return a.name:lower() < b.name:lower()
		end)
	end
	if #items > 0 then
		out[#out + 1] = { title = title, crumbs = crumbs, path = path, items = items, default_open = crumbs == nil }
	end
	if depth > 0 then
		local dirs = utils.readdir(path, 'dirs') or {}
		table.sort(dirs, function(a, b) return a:lower() < b:lower() end)
		for _, d in ipairs(dirs) do
			if d:sub(1, 1) ~= '.' then
				scan_dir(join(path, d), d, (crumbs and (crumbs .. ' / ') or '') .. title, depth - 1, out)
			end
		end
	end
end

-- Installs a section list as the visible one and warms the thumbnail cache index.
local function use_sections(sections)
	lib.sections = sections
	lib.items = {}
	for _, section in ipairs(sections) do
		for _, item in ipairs(section.items) do
			lib.items[#lib.items + 1] = item
			thumb_for(item)
		end
	end
	lib.layout = nil
	lib.hover, lib.sel, lib.hover_header = nil, nil, nil
	lib.scroll = 0
end

-- Playlist view: one section per directory of the current playlist, in playlist order.
local function build_playlist_sections()
	local entries = mp.get_property_native('playlist') or {}
	local cwd = mp.get_property('working-directory') or ''
	local by_dir, order = {}, {}
	for idx, e in ipairs(entries) do
		local path = e.filename or ''
		local is_url = path:find('^%a[%w+.-]*://') ~= nil
		local dir, name
		if is_url then
			dir, name = '', e.title or path
		else
			if path:sub(1, 1) ~= '/' then path = join(cwd, path) end
			dir = path:match('^(.*)/[^/]+$') or '/'
			name = path:match('([^/]+)$') or path
		end
		local section = by_dir[dir]
		if not section then
			section = { title = is_url and 'Streams' or (dir:match('([^/]+)$') or dir), crumbs = (not is_url) and dir or nil,
				path = 'playlist:' .. dir, items = {}, default_open = true }
			by_dir[dir] = section
			order[#order + 1] = section
		end
		local info = (not is_url) and utils.file_info(path) or nil
		section.items[#section.items + 1] = { name = name, path = path, kind = kind_of(name) or 'video',
			mtime = info and info.mtime or 0, size = info and info.size or 0, pl_index = idx - 1,
			current = e.current and true or false, is_url = is_url }
	end
	return order
end

local function rescan()
	lib.scanned = {}
	lib.roots = {}
	for raw_dir in o.dirs:gmatch('[^,]+') do
		local raw = raw_dir:gsub('^%s+', ''):gsub('%s+$', '')
		if raw ~= '' then
			local path = mp.command_native({ 'expand-path', raw })
			path = path:gsub('/+$', '')
			lib.roots[#lib.roots + 1] = path
			local title = path:match('([^/]+)$') or path
			local info = utils.file_info(path)
			if info and info.is_dir then
				scan_dir(path, title, nil, o.depth, lib.scanned)
			else
				msg.warn('library dir not found: ' .. path)
			end
		end
	end
	if lib.mode ~= 'playlist' then use_sections(lib.scanned) end
	request_render()
end

local function toggle_section(section)
	local open = not section_expanded(section)
	if open and persist.accordion then
		for _, other in ipairs(lib.sections) do
			if other ~= section and section_expanded(other) then persist.expanded[other.path] = false end
		end
	end
	persist.expanded[section.path] = open
	persist_save()
	lib.layout = nil
	lib.hover, lib.sel = nil, nil
	request_render()
end

local function set_accordion(on)
	persist.accordion = on and true or false
	if persist.accordion then -- keep only the first open section
		local kept = false
		for _, section in ipairs(lib.sections) do
			if section_expanded(section) then
				if kept then persist.expanded[section.path] = false else kept = true end
			end
		end
	end
	persist_save()
	lib.layout = nil
	request_render()
end

local function fmt_duration(sec)
	if not sec then return nil end
	sec = math.floor(sec + 0.5)
	local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
	if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
	return string.format('%d:%02d', m, s)
end
local function fmt_size(bytes)
	if bytes >= 1024 ^ 3 then return string.format('%.1f GB', bytes / 1024 ^ 3) end
	if bytes >= 1024 ^ 2 then return string.format('%.0f MB', bytes / 1024 ^ 2) end
	return string.format('%.0f KB', bytes / 1024)
end
local function fmt_date(ts) return os.date('%Y-%m-%d', ts) end

local kind_icon = { video = 'movie', audio = 'music_note', image = 'image' }

-- Layout in content coordinates (y grows with scroll). Recomputed on resize.
local function layout_library()
	local s = S()
	local W, H = display.w, display.h
	local top = round(44 * s) -- actions strip
	local margin = round(28 * s)
	local gap = round(16 * s)
	local card_w = round(o.card_width * s)
	local thumb_w, thumb_h = thumb_dims()
	local card_h = thumb_h + round(58 * s)
	local inner_w = W - margin * 2
	local cols = math.max(1, math.floor((inner_w + gap) / (card_w + gap)))
	local grid_w = cols * card_w + (cols - 1) * gap
	local x0 = margin + math.floor((inner_w - grid_w) / 2)
	local y = top + round(72 * s) -- library header
	local section_h = round(44 * s)
	local cards = {}
	local sections = {}
	for si, section in ipairs(lib.sections) do
		local open = section_expanded(section)
		local sy = y
		y = y + section_h
		local first = #cards + 1
		if open then
			for i, item in ipairs(section.items) do
				local col = (i - 1) % cols
				local row = math.floor((i - 1) / cols)
				local cx = x0 + col * (card_w + gap)
				local cy = y + row * (card_h + gap)
				cards[#cards + 1] = { item = item, x = cx, y = cy, w = card_w, h = card_h, section = si, col = col, row = row }
			end
			local rows = math.ceil(#section.items / cols)
			y = y + rows * (card_h + gap) - gap + round(28 * s)
		else
			y = y + round(8 * s)
		end
		sections[#sections + 1] = { section = section, y = sy, h = section_h, x1 = x0, x2 = x0 + grid_w, first = first, open = open }
	end
	local content_h = y + margin
	local view_h = H
	lib.layout = { top = top, margin = margin, gap = gap, card_w = card_w, card_h = card_h, thumb_w = thumb_w, thumb_h = thumb_h,
		cols = cols, x0 = x0, grid_w = grid_w, cards = cards, sections = sections, content_h = content_h, view_h = view_h, header_y = top }
	lib.max_scroll = math.max(0, content_h - view_h)
	lib.scroll = clamp(lib.scroll, 0, lib.max_scroll)
end

local function card_at(mx, my)
	if not lib.layout then return nil end
	local L = lib.layout
	if my < L.top + round(60 * S()) then return nil end
	for i, c in ipairs(L.cards) do
		local y = c.y - lib.scroll
		if mx >= c.x and mx < c.x + c.w and my >= y and my < y + c.h then return i end
	end
	return nil
end

local function header_at(mx, my)
	local L = lib.layout
	if not L then return nil end
	if my < L.top + round(64 * S()) then return nil end
	for i, sec in ipairs(L.sections) do
		local y = sec.y - lib.scroll
		if mx >= sec.x1 - round(10 * S()) and mx < sec.x2 and my >= y and my < y + sec.h then return i end
	end
	return nil
end

local function button_at(mx, my)
	for _, b in ipairs(lib.buttons) do
		if mx >= b.x1 and mx < b.x2 and my >= b.y1 and my < b.y2 then return b end
	end
	return nil
end

local function scroll_to_card(i)
	local L = lib.layout
	local c = L.cards[i]
	if not c then return end
	local s = S()
	local min_y = L.top + round(72 * s) + round(44 * s)
	if c.y - lib.scroll < min_y then lib.scroll = c.y - min_y - round(8 * s) end
	if c.y + c.h - lib.scroll > L.view_h - round(16 * s) then lib.scroll = c.y + c.h - L.view_h + round(16 * s) end
	lib.scroll = clamp(lib.scroll, 0, lib.max_scroll)
end

local function play_card(i)
	local c = lib.layout and lib.layout.cards[i]
	if not c then return end
	if c.item.pl_index then
		if c.item.current then
			hide_library()
			mp.set_property_bool('pause', false)
		else
			mp.commandv('playlist-play-index', c.item.pl_index)
		end
	else
		mp.commandv('loadfile', c.item.path, 'replace')
	end
end

local hide_library, show_library, toggle_dropdown, ui_sync, top_button_at, topbar_opacity

local function lib_move(dx, dy)
	local L = lib.layout
	if not L or #L.cards == 0 then return end
	local i = lib.sel or lib.hover
	if not i then
		lib.sel = 1
	elseif dx ~= 0 then
		lib.sel = clamp(i + dx, 1, #L.cards)
	else
		local c = L.cards[i]
		local target = c.col
		local best
		local j = i
		while true do
			j = j + (dy > 0 and 1 or -1)
			local n = L.cards[j]
			if not n then break end
			if n.section ~= c.section or n.row ~= c.row then
				-- first card in a different row/section: prefer same column
				if n.col == target then best = j break end
				if not best then best = j end
				local nn = L.cards[j + (dy > 0 and 1 or -1)]
				if not nn or nn.section ~= n.section or nn.row ~= n.row then break end
			end
		end
		if best then lib.sel = best end
	end
	lib.hover = nil
	scroll_to_card(lib.sel)
	request_render()
end

local function lib_click()
	local tb = top_button_at(mouse.x, mouse.y)
	if tb then tb.action() return end
	local hb = button_at(mouse.x, mouse.y)
	if hb then hb.action() return end
	local hi = header_at(mouse.x, mouse.y)
	if hi then toggle_section(lib.layout.sections[hi].section) return end
	local i = card_at(mouse.x, mouse.y)
	if i then play_card(i) end
end

local function lib_key(name)
	local L = lib.layout
	if not L then return end
	local step = round(90 * S())
	if name == 'WHEEL_UP' then lib.scroll = clamp(lib.scroll - step, 0, lib.max_scroll) lib.hover = card_at(mouse.x, mouse.y)
	elseif name == 'WHEEL_DOWN' then lib.scroll = clamp(lib.scroll + step, 0, lib.max_scroll) lib.hover = card_at(mouse.x, mouse.y)
	elseif name == 'UP' then return lib_move(0, -1)
	elseif name == 'DOWN' then return lib_move(0, 1)
	elseif name == 'LEFT' then return lib_move(-1, 0)
	elseif name == 'RIGHT' then return lib_move(1, 0)
	elseif name == 'PGUP' then lib.scroll = clamp(lib.scroll - L.view_h * 0.8, 0, lib.max_scroll)
	elseif name == 'PGDWN' then lib.scroll = clamp(lib.scroll + L.view_h * 0.8, 0, lib.max_scroll)
	elseif name == 'HOME' then lib.scroll = 0 lib.sel = 1
	elseif name == 'END' then lib.scroll = lib.max_scroll lib.sel = #L.cards
	elseif name == 'ENTER' then if lib.sel or lib.hover then play_card(lib.sel or lib.hover) end return
	elseif name == 'ESC' or name == 'MBTN_RIGHT' then if not state.idle then hide_library() end return
	else return end
	request_render()
end

show_library = function(mode)
	mode = mode == 'playlist' and 'playlist' or 'library'
	if lib.visible and lib.mode == mode then return end
	lib.mode = mode
	if mode == 'playlist' then
		use_sections(build_playlist_sections())
		lib.focus_current = true
	elseif not lib.scanned then
		rescan()
	else
		use_sections(lib.scanned)
	end
	if lib.visible then request_render() return end
	lib.visible = true
	lib.layout = nil
	ui_sync()
	mp.commandv('script-message-to', 'uosc', 'disable-elements', 'shelf', 'timeline,controls,volume')
	mp.commandv('script-message-to', 'thumbfast', 'clear')
	request_render()
end

hide_library = function()
	if not lib.visible then return end
	lib.visible = false
	ui_sync()
	overlays_clear()
	mp.commandv('script-message-to', 'uosc', 'disable-elements', 'shelf', '')
	request_render()
end

local function toggle_library()
	if lib.visible and lib.mode == 'library' then hide_library() else show_library('library') end
end

local function toggle_playlist()
	if lib.visible and lib.mode == 'playlist' then hide_library() else show_library('playlist') end
end

-- ---------------------------------------------------------------- actions --

local key_names = {
	SPACE = 'Space', BS = 'Backspace', ENTER = 'Enter', ESC = 'Esc', TAB = 'Tab', SHARP = '#',
	PGUP = 'PgUp', PGDWN = 'PgDn', HOME = 'Home', END = 'End', DEL = 'Del', INS = 'Ins',
	UP = '↑', DOWN = '↓', LEFT = '←', RIGHT = '→', MBTN_LEFT = 'Click', MBTN_RIGHT = 'Right click',
	MBTN_MID = 'Middle click', MBTN_LEFT_DBL = 'Double click', MBTN_BACK = 'Back button', MBTN_FORWARD = 'Forward button',
	WHEEL_UP = 'Wheel up', WHEEL_DOWN = 'Wheel down', WHEEL_LEFT = 'Wheel left', WHEEL_RIGHT = 'Wheel right',
	KP_ENTER = 'Enter', menu = 'Menu',
}
local function pretty_key(key)
	local parts = {}
	local mods = {}
	for part in key:gmatch('[^+]+') do parts[#parts + 1] = part end
	-- a trailing '+' key ("Alt++", "Ctrl++") loses its last token to the split
	if key:sub(-1) == '+' then parts[#parts + 1] = '+' end
	local last = parts[#parts]
	for i = 1, #parts - 1 do
		local m = parts[i]:lower()
		mods[#mods + 1] = m == 'ctrl' and 'Ctrl' or m == 'alt' and 'Alt' or m == 'shift' and 'Shift' or m == 'meta' and 'Meta' or parts[i]
	end
	local disp
	if key_names[last] then
		disp = key_names[last]
	elseif #last == 1 and last:match('%u') then
		mods[#mods + 1] = 'Shift'
		disp = last
	elseif #last == 1 and last:match('%l') then
		disp = last:upper()
	else
		disp = last:sub(1, 1):upper() .. last:sub(2)
	end
	mods[#mods + 1] = disp
	return table.concat(mods, '+')
end

local function split_title(title)
	local parts = {}
	for raw_part in title:gmatch('[^>]+') do
		local part = raw_part:gsub('^%s+', ''):gsub('%s+$', '')
		if part ~= '' then parts[#parts + 1] = part end
	end
	return parts
end

-- Parses input.conf the same way uosc does: `KEY cmd #! Section > Item`.
local function load_actions()
	local root = { items = {}, by_cmd = {} }
	local by_id = {}
	local conf = mp.get_property('input-conf') or ''
	local lines = {}
	if conf:sub(1, 9) == 'memory://' then
		for line in (conf:sub(10) .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
	else
		local path = mp.command_native({ 'expand-path', conf == '' and '~~/input.conf' or conf })
		local f = io.open(path, 'r')
		if f then
			for line in f:lines() do lines[#lines + 1] = line end
			f:close()
		end
	end
	for _, line in ipairs(lines) do
		local key, command, comment = line:match('^%s*(%S+)%s+(.-)%s+#%s*(.-)%s*$')
		if key and comment then
			local title
			for chunk in comment:gmatch('[^#]+') do
				local t = chunk:match('^!%s*(.-)%s*$') or chunk:match('^menu:%s*(.-)%s*$')
				if t and not title then title = t end
			end
			if title and title ~= '' then
				local dummy = key == '#'
				local parts = split_title(title)
				local target = root
				local id = ''
				for i, part in ipairs(parts) do
					if i < #parts then
						id = id .. part .. '>'
						if not by_id[id] then
							by_id[id] = { title = part, items = {}, by_cmd = {} }
							target.items[#target.items + 1] = by_id[id]
						end
						target = by_id[id]
					else
						if part:sub(1, 3) == '---' then
							local last = target.items[#target.items]
							if last then last.separator = true end
						elseif command ~= 'ignore' then
							local hint
							if not dummy then
								hint = pretty_key(key)
							else
								local kp = command:match('^keypress%s+(%S+)$')
								if kp then hint = pretty_key(kp) end
							end
							local existing = command ~= '' and target.by_cmd[command]
							if existing then
								if hint and existing.hint and not existing.hint:find(hint, 1, true) then
									existing.hint = existing.hint .. ' / ' .. hint
								elseif hint and not existing.hint then
									existing.hint = hint
								end
							else
								local item = { title = part, hint = hint, cmd = command ~= '' and command or nil }
								target.items[#target.items + 1] = item
								if command ~= '' then target.by_cmd[command] = item end
							end
						end
					end
				end
			end
		end
	end
	return root
end

local close_dropdown, open_dropdown

local function run_action(item)
	if not item or not item.cmd then return end
	close_dropdown()
	mp.command(item.cmd)
end

local function dd_rows_at(mx, my)
	if dd.subrect and mx >= dd.subrect.x1 and mx < dd.subrect.x2 and my >= dd.subrect.y1 and my < dd.subrect.y2 then
		for i, r in ipairs(dd.subrows) do
			if my >= r.y1 and my < r.y2 then return 'sub', i end
		end
		return 'sub', nil
	end
	if dd.rect and mx >= dd.rect.x1 and mx < dd.rect.x2 and my >= dd.rect.y1 and my < dd.rect.y2 then
		for i, r in ipairs(dd.rows) do
			if my >= r.y1 and my < r.y2 then return 'root', i end
		end
		return 'root', nil
	end
	return nil
end

local function dd_update_hover()
	local where, i = dd_rows_at(mouse.x, mouse.y)
	local changed = false
	if where == 'root' then
		if dd.hover_row ~= i then
			dd.hover_row = i
			changed = true
			local item = i and dd.root.items[i]
			local cat = item and item.items and i or nil
			if cat ~= dd.open_cat then dd.open_cat = cat dd.hover_sub = nil changed = true end
		end
		if dd.hover_sub then dd.hover_sub = nil changed = true end
	elseif where == 'sub' then
		if dd.hover_sub ~= i then dd.hover_sub = i changed = true end
		if dd.hover_row ~= dd.open_cat then dd.hover_row = dd.open_cat changed = true end
	else
		if dd.hover_row ~= nil and dd.hover_row ~= dd.open_cat then dd.hover_row = nil changed = true end
		if dd.hover_sub then dd.hover_sub = nil changed = true end
	end
	if changed then request_render() end
end

local function dd_click()
	local where, i = dd_rows_at(mouse.x, mouse.y)
	if where == 'sub' and i then
		local item = dd.root.items[dd.open_cat].items[i]
		if not item.items then run_action(item) end
	elseif where == 'root' and i then
		local item = dd.root.items[i]
		if item.items then
			dd.open_cat = i
			request_render()
		else
			run_action(item)
		end
	elseif where == nil then
		close_dropdown() -- click on the button or anywhere outside dismisses
	end
end

local function dd_key(name)
	local function sel_move(d)
		local n = #dd.root.items
		if dd.sel_col == 1 then
			dd.sel = ((dd.sel or 0) + d - 1) % n + 1
			dd.hover_row = dd.sel
			local item = dd.root.items[dd.sel]
			dd.open_cat = item.items and dd.sel or nil
			dd.sel_sub = nil
		else
			local items = dd.root.items[dd.open_cat].items
			dd.sel_sub = ((dd.sel_sub or 0) + d - 1) % #items + 1
			dd.hover_sub = dd.sel_sub
		end
		request_render()
	end
	local function enter_sub()
		dd.open_cat = dd.sel
		dd.sel_col = 2
		dd.sel_sub = 1
		dd.hover_sub = 1
		request_render()
	end
	if name == 'ESC' or name == 'MBTN_RIGHT' then close_dropdown()
	elseif name == 'DOWN' then sel_move(1)
	elseif name == 'UP' then sel_move(-1)
	elseif name == 'RIGHT' then
		local item = dd.sel and dd.root.items[dd.sel]
		if item and item.items then enter_sub() end
	elseif name == 'LEFT' then
		if dd.sel_col == 2 then
			dd.sel_col = 1
			dd.sel_sub, dd.hover_sub = nil, nil
			request_render()
		end
	elseif name == 'ENTER' then
		if dd.sel_col == 2 and dd.sel_sub then
			run_action(dd.root.items[dd.open_cat].items[dd.sel_sub])
		elseif dd.sel then
			local item = dd.root.items[dd.sel]
			if item.items then enter_sub() else run_action(item) end
		end
	end
end

open_dropdown = function()
	if dd.open then return end
	dd.root = load_actions()
	dd.open = true
	dd.hover_row, dd.open_cat, dd.hover_sub = nil, nil, nil
	dd.sel_col, dd.sel, dd.sel_sub = 1, nil, nil
	ui_sync()
	dd_update_hover()
	request_render()
end

close_dropdown = function()
	if not dd.open then return end
	dd.open = false
	ui_sync()
	dd.rect, dd.subrect = nil, nil
	request_render()
end

toggle_dropdown = function()
	if dd.open then close_dropdown() else open_dropdown() end
end

-- One forced binding set shared by both surfaces (mpv keeps all of a script's
-- forced bindings in a single input section, so the same key must not be bound
-- twice). Bound while the library or the dropdown is open, cleared otherwise.
local ui = { keys = make_keygroup('shelf-ui'), bound = false }
local ui_key_list = { 'MBTN_RIGHT', 'ESC', 'UP', 'DOWN', 'LEFT', 'RIGHT', 'ENTER', 'KP_ENTER', 'WHEEL_UP', 'WHEEL_DOWN', 'PGUP', 'PGDWN', 'HOME', 'END' }
local function ui_dispatch(name)
	if name == 'KP_ENTER' then name = 'ENTER' end
	if dd.open then
		if name == 'WHEEL_UP' or name == 'WHEEL_DOWN' or name == 'PGUP' or name == 'PGDWN' or name == 'HOME' or name == 'END' then
			if lib.visible then lib_key(name) end
		else
			dd_key(name)
		end
	elseif lib.visible then
		lib_key(name)
	end
end
ui_sync = function()
	local want = lib.visible or dd.open
	if want == ui.bound then return end
	ui.bound = want
	ui.keys:clear()
	if not want then return end
	for _, key in ipairs(ui_key_list) do
		local repeatable = key ~= 'ESC' and key ~= 'ENTER' and key ~= 'KP_ENTER' and key ~= 'MBTN_RIGHT'
		ui.keys:bind(key, function() ui_dispatch(key) end, repeatable and { repeatable = true } or nil)
	end
end

-- Top strip buttons (☰ Actions on the left, window controls on the right).
local top_buttons = {}
top_button_at = function(mx, my)
	for _, b in ipairs(top_buttons) do
		if mx >= b.x1 and mx < b.x2 and my >= b.y1 and my < b.y2 then return b end
	end
	return nil
end

-- Left click lives in its own input section, enabled once and never touched
-- again, so its priority stays below uosc's hover-time sections (uosc wins on
-- its own elements) while every other click reaches us: dropdown, library,
-- top buttons, or a drag/double-click aware click-to-pause on the video.
local click = { down_t = 0, down_x = 0, down_y = 0, timer = nil }
local function on_click_up()
	if dd.open then dd_click() return end
	if lib.visible then lib_click() return end
	local b = top_button_at(mouse.x, mouse.y)
	if b and topbar_opacity() > 0 then b.action() return end
	if not o.click_to_pause or state.idle then return end
	local held = mp.get_time() - click.down_t
	local moved = math.abs(mouse.x - click.down_x) + math.abs(mouse.y - click.down_y)
	if held > o.click_threshold / 1000 or moved > 6 then return end
	-- wait out the double-click window so MBTN_LEFT_DBL (fullscreen) doesn't also toggle pause
	local dbl = (mp.get_property_native('input-doubleclick-time') or 300) / 1000
	if click.timer then click.timer:kill() end
	click.timer = mp.add_timeout(dbl, function()
		click.timer = nil
		mp.command('cycle pause')
		mp.commandv('script-binding', 'uosc/flash-pause-indicator')
	end)
end
local function on_click_down()
	if click.timer then click.timer:kill() click.timer = nil return end -- second press of a double click
	click.down_t, click.down_x, click.down_y = mp.get_time(), mouse.x, mouse.y
end
mp.set_key_bindings({ { 'MBTN_LEFT', on_click_up, on_click_down } }, 'shelf_click', 'force')
mp.enable_key_bindings('shelf_click', 'allow-vo-dragging+allow-hide-cursor')

-- ----------------------------------------------------------------- render --
topbar_opacity = function()
	if state.idle or lib.visible or dd.open or state.paused then return 1 end
	if not mouse.hover then return 0 end
	local reveal = o.top_reveal * S()
	if mouse.y <= reveal then return 1 end
	return clamp(1 - (mouse.y - reveal) / (reveal * 0.6), 0, 1)
end

local function render_topbar(ass)
	local s = S()
	local op = topbar_opacity()
	local h = round(44 * s)
	local pad = round(10 * s)
	top_buttons = {}
	-- ☰ Actions
	local label = 'Actions'
	local fs = round(15 * s)
	local bw = round(16 * s) + round(20 * s) + round(8 * s) + text_width(label, fs, 0.56) + round(16 * s)
	local bx1, by1, bx2, by2 = pad, round(7 * s), pad + bw, h - round(7 * s)
	dd.button = { x1 = bx1, y1 = by1, x2 = bx2, y2 = by2 }
	if op <= 0 then
		dd.hover_button = false
		return
	end
	top_buttons[#top_buttons + 1] = { x1 = bx1, y1 = by1, x2 = bx2, y2 = by2, action = toggle_dropdown }
	-- strip background only when we're over the video (not on the library)
	if not lib.visible and not state.idle then
		ass:rect(0, 0, display.w, h + round(20 * s), { color = T.black, opacity = 0.42 * op, radius = 0 })
	end
	local function over(b) return mouse.hover and mouse.x >= b.x1 and mouse.x < b.x2 and mouse.y >= b.y1 and mouse.y < b.y2 end
	local hovered = over(dd.button)
	dd.hover_button = hovered
	local active = dd.open or hovered
	ass:rect(bx1, by1, bx2, by2, { color = active and T.hover or T.surface, opacity = (active and 1 or 0.92) * op, radius = round(8 * s),
		border = 1, border_color = active and T.gold or T.line, border_opacity = (active and 0.9 or 0.18) * op })
	ass:icon(bx1 + round(12 * s), (by1 + by2) / 2, 4, dd.open and 'close' or 'menu', { size = round(20 * s), color = dd.open and T.gold or T.text, opacity = op })
	ass:text(bx1 + round(12 * s) + round(26 * s), (by1 + by2) / 2, 4, label, { size = fs, color = active and T.gold or T.text, opacity = op })
	-- window controls (uosc's top bar is disabled so the ☰ button owns the strip)
	local wb = round(34 * s)
	local wx = display.w - pad
	local controls = {
		{ icon = 'close', action = function() mp.command('quit') end, hot = T.accent },
		{ icon = state.fullscreen and 'fullscreen_exit' or 'crop_square', action = function()
			if state.fullscreen then mp.set_property_bool('fullscreen', false) else mp.command('cycle window-maximized') end
		end },
		{ icon = 'minimize', action = function() mp.command('cycle window-minimized') end },
	}
	for _, c in ipairs(controls) do
		local b = { x1 = wx - wb, y1 = by1, x2 = wx, y2 = by2, action = c.action }
		top_buttons[#top_buttons + 1] = b
		local hov = over(b)
		if hov then
			ass:rect(b.x1, b.y1, b.x2, b.y2, { color = c.hot or T.hover, opacity = (c.hot and 0.9 or 1) * op, radius = round(8 * s) })
		end
		ass:icon((b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2, 5, c.icon, { size = round(20 * s), color = hov and T.text or T.dim, opacity = op, border = (lib.visible or state.idle) and 0 or 1, border_color = T.bg })
		wx = b.x1 - round(2 * s)
	end
	-- title (media title during playback, library hint on the shelf) + playlist position
	local tx = bx2 + round(14 * s)
	local title = lib.visible and (state.idle and 'Library' or (state.title ~= '' and state.title or 'Library')) or state.title
	if lib.visible and lib.mode == 'playlist' then title = 'Playlist' .. (state.title ~= '' and ('  ·  ' .. state.title) or '') end
	local right_limit = wx - round(16 * s)
	if state.pl_count > 1 and not state.idle then
		local chip = string.format('%d/%d', state.pl_pos, state.pl_count)
		local cw = text_width(chip, round(12 * s), 0.62) + round(16 * s)
		ass:rect(tx, (by1 + by2) / 2 - round(10 * s), tx + cw, (by1 + by2) / 2 + round(10 * s), { color = T.gold, opacity = 0.9 * op, radius = round(6 * s) })
		ass:text(tx + cw / 2, (by1 + by2) / 2, 5, chip, { size = round(12 * s), font = T.mono, color = T.bg, opacity = op, bold = true })
		tx = tx + cw + round(10 * s)
	end
	if title and title ~= '' then
		local max_w = right_limit - tx
		ass:text(tx, h / 2, 4, ellipsize(title, round(15 * s), max_w), { size = round(15 * s), color = lib.visible and T.dim or T.text, opacity = op * (lib.visible and 0.9 or 1), border = lib.visible and 0 or 1.2, border_color = T.bg })
	end
end

local function render_dropdown(ass)
	if not dd.open or not dd.root then return end
	local s = S()
	local row_h = round(32 * s)
	local pad = round(6 * s)
	local fs = round(14 * s)
	local b = dd.button
	local x1 = b.x1
	local y1 = b.y2 + round(6 * s)
	local width = round(230 * s)
	local items = dd.root.items
	local height = pad * 2 + #items * row_h
	for _, it in ipairs(items) do if it.separator then height = height + pad end end
	local x2, y2 = x1 + width, y1 + height
	dd.rect = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
	ass:rect(x1 + 2, y1 + 3, x2 + 2, y2 + 3, { color = T.black, opacity = 0.35, radius = round(10 * s) })
	ass:rect(x1, y1, x2, y2, { color = T.surface, opacity = 0.98, radius = round(10 * s), border = 1, border_color = T.line, border_opacity = 0.16 })
	dd.rows = {}
	local y = y1 + pad
	for i, item in ipairs(items) do
		local ry1, ry2 = y, y + row_h
		dd.rows[i] = { y1 = ry1, y2 = ry2 }
		local active = dd.hover_row == i or dd.open_cat == i or (dd.sel_col == 1 and dd.sel == i)
		if active then
			ass:rect(x1 + pad, ry1 + 1, x2 - pad, ry2 - 1, { color = T.hover, opacity = 1, radius = round(6 * s) })
		end
		ass:text(x1 + pad + round(12 * s), (ry1 + ry2) / 2, 4, item.title, { size = fs, color = active and T.gold or T.text })
		if item.items then
			ass:icon(x2 - pad - round(8 * s), (ry1 + ry2) / 2, 6, 'chevron_right', { size = round(18 * s), color = active and T.gold or T.dim })
		elseif item.hint then
			ass:text(x2 - pad - round(12 * s), (ry1 + ry2) / 2, 6, item.hint, { size = round(12 * s), font = T.mono, color = T.dim })
		end
		y = ry2
		if item.separator then
			ass:rect(x1 + pad + round(8 * s), y + pad / 2 - 0.5, x2 - pad - round(8 * s), y + pad / 2 + 0.5, { color = T.line, opacity = 0.14 })
			y = y + pad
		end
	end
	-- flyout
	dd.subrect, dd.subrows = nil, {}
	local cat = dd.open_cat and items[dd.open_cat]
	if cat and cat.items and #cat.items > 0 then
		local sub = cat.items
		local sw = round(300 * s)
		local sh = pad * 2 + #sub * row_h
		for _, it in ipairs(sub) do if it.separator then sh = sh + pad end end
		local sx1 = x2 + round(4 * s)
		local sy1 = dd.rows[dd.open_cat].y1 - pad
		if sy1 + sh > display.h - round(8 * s) then sy1 = math.max(round(8 * s), display.h - round(8 * s) - sh) end
		local sx2, sy2 = sx1 + sw, sy1 + sh
		dd.subrect = { x1 = sx1, y1 = sy1, x2 = sx2, y2 = sy2 }
		ass:rect(sx1 + 2, sy1 + 3, sx2 + 2, sy2 + 3, { color = T.black, opacity = 0.35, radius = round(10 * s) })
		ass:rect(sx1, sy1, sx2, sy2, { color = T.surface, opacity = 0.98, radius = round(10 * s), border = 1, border_color = T.line, border_opacity = 0.16 })
		local yy = sy1 + pad
		for i, item in ipairs(sub) do
			local ry1, ry2 = yy, yy + row_h
			dd.subrows[i] = { y1 = ry1, y2 = ry2 }
			local active = dd.hover_sub == i or (dd.sel_col == 2 and dd.sel_sub == i)
			if active then
				ass:rect(sx1 + pad, ry1 + 1, sx2 - pad, ry2 - 1, { color = T.hover, opacity = 1, radius = round(6 * s) })
			end
			ass:text(sx1 + pad + round(12 * s), (ry1 + ry2) / 2, 4, item.title, { size = fs, color = active and T.gold or (item.cmd and T.text or T.dim) })
			if item.hint then
				ass:text(sx2 - pad - round(12 * s), (ry1 + ry2) / 2, 6, item.hint, { size = round(12 * s), font = T.mono, color = active and T.text or T.dim, opacity = 0.9 })
			end
			yy = ry2
			if item.separator then
				ass:rect(sx1 + pad + round(8 * s), yy + pad / 2 - 0.5, sx2 - pad - round(8 * s), yy + pad / 2 + 0.5, { color = T.line, opacity = 0.14 })
				yy = yy + pad
			end
		end
	end
end

local function rects_intersect(a, b)
	return a.x1 < b.x2 and a.x2 > b.x1 and a.y1 < b.y2 and a.y2 > b.y1
end

local function render_library(ass)
	if not lib.visible then
		lib_osd.data = ''
		lib_osd:update()
		overlays_clear()
		return
	end
	if not lib.layout then layout_library() end
	local s = S()
	local L = lib.layout
	local W, H = display.w, display.h
	if lib.focus_current then
		lib.focus_current = false
		for i, c in ipairs(L.cards) do
			if c.item.current then lib.sel = i scroll_to_card(i) break end
		end
	end
	-- backdrop
	ass:rect(0, 0, W, H, { color = T.bg, opacity = state.idle and 1 or 0.94, radius = 0 })
	-- header
	local hy = L.top + round(36 * s)
	local playlist_mode = lib.mode == 'playlist'
	local heading = playlist_mode and 'Playlist' or 'Library'
	ass:text(L.x0, hy, 4, heading, { size = round(34 * s), font = T.serif, color = T.text })
	local nfiles, nsections = #lib.items, #lib.sections
	local summary = playlist_mode and string.format('%d %s', nfiles, nfiles == 1 and 'item' or 'items')
		or string.format('%d %s in %d %s', nfiles, nfiles == 1 and 'file' or 'files', nsections, nsections == 1 and 'folder' or 'folders')
	local summary_x = L.x0 + text_width(heading, round(34 * s), 0.5) + round(14 * s)
	local summary_right = summary_x + text_width(summary, round(13 * s), 0.62)
	-- header buttons (right aligned)
	lib.buttons = {}
	local bx = L.x0 + L.grid_w
	local function header_button(label, icon, action, accent)
		local fs = round(13 * s)
		local bw = round(14 * s) + round(20 * s) + round(6 * s) + text_width(label, fs, 0.56) + round(14 * s)
		local x1, x2 = bx - bw, bx
		local y1, y2 = hy - round(16 * s), hy + round(16 * s)
		local hovered = mouse.hover and mouse.x >= x1 and mouse.x < x2 and mouse.y >= y1 and mouse.y < y2
		ass:rect(x1, y1, x2, y2, { color = hovered and T.hover or T.surface, opacity = 1, radius = round(8 * s), border = 1,
			border_color = (hovered or accent) and T.gold or T.line, border_opacity = hovered and 0.9 or (accent and 0.5 or 0.18) })
		ass:icon(x1 + round(12 * s), hy, 4, icon, { size = round(18 * s), color = (hovered or accent) and T.gold or T.text })
		ass:text(x1 + round(12 * s) + round(24 * s), hy, 4, label, { size = fs, color = hovered and T.gold or T.text })
		lib.buttons[#lib.buttons + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, action = action }
		bx = x1 - round(8 * s)
	end
	if not state.idle then header_button('Close', 'close', hide_library) end
	if playlist_mode then
		header_button('Library', 'video_library', function() show_library('library') end)
	else
		header_button('Rescan', 'refresh', rescan)
		header_button('Open file', 'folder_open', function() mp.commandv('script-binding', 'uosc/open-file') end)
		if state.pl_count > 0 and not state.idle then
			header_button('Playlist', 'list_alt', function() show_library('playlist') end)
		end
	end
	if not state.idle and state.file_loaded then
		header_button('Resume', 'play_arrow', function() hide_library() mp.set_property_bool('pause', false) end, true)
	end
	if not playlist_mode then -- accordion checkbox
		local label = 'One folder at a time'
		local fs = round(13 * s)
		local bw = round(10 * s) + round(22 * s) + round(4 * s) + text_width(label, fs, 0.56) + round(10 * s)
		local x1, x2 = bx - bw, bx
		local y1, y2 = hy - round(16 * s), hy + round(16 * s)
		local hovered = mouse.hover and mouse.x >= x1 and mouse.x < x2 and mouse.y >= y1 and mouse.y < y2
		ass:icon(x1 + round(10 * s), hy, 4, persist.accordion and 'check_box' or 'check_box_outline_blank',
			{ size = round(20 * s), color = (persist.accordion or hovered) and T.gold or T.dim })
		ass:text(x1 + round(10 * s) + round(26 * s), hy, 4, label, { size = fs, color = hovered and T.gold or T.dim })
		lib.buttons[#lib.buttons + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, action = function() set_accordion(not persist.accordion) end }
		bx = x1 - round(8 * s)
	end
	if bx - round(16 * s) > summary_right then -- hidden when the buttons would collide with it
		ass:text(summary_x, hy + round(5 * s), 4, summary, { size = round(13 * s), font = T.mono, color = T.dim, spacing = 0.6 })
	end
	-- sections + cards (clipped under the header band)
	local clip_top = L.top + round(64 * s)
	local clip = string.format('%d,%d,%d,%d', 0, clip_top, W, H)
	local wanted = {}
	local blockers = {}
	if dd.open then
		if dd.rect then blockers[#blockers + 1] = dd.rect end
		if dd.subrect then blockers[#blockers + 1] = dd.subrect end
	end
	local hover_i = lib.hover
	for hi, sec in ipairs(L.sections) do
		local y = sec.y - lib.scroll
		if y + sec.h > clip_top and y < H then
			local section = sec.section
			local hovered = lib.hover_header == hi
			if hovered then
				ass:rect(sec.x1 - round(10 * s), y + round(2 * s), sec.x2, y + round(38 * s), { color = T.hover, opacity = 0.7, radius = round(8 * s), clip = clip })
			end
			ass:icon(sec.x1 + round(2 * s), y + round(21 * s), 4, sec.open and 'expand_more' or 'chevron_right',
				{ size = round(22 * s), color = (hovered or sec.open) and T.gold or T.dim, clip = clip })
			local tx = sec.x1 + round(26 * s)
			ass:text(tx, y + round(24 * s), 4, section.title, { size = round(19 * s), color = hovered and T.gold or T.text, bold = true, clip = clip })
			local tw = text_width(section.title, round(19 * s), 0.58)
			local meta = string.format('%d', #section.items)
			if section.crumbs then meta = section.crumbs .. '  ·  ' .. meta end
			meta = ellipsize(meta, round(12 * s), sec.x2 - tx - tw - round(24 * s), 0.62)
			ass:text(tx + tw + round(12 * s), y + round(26 * s), 4, meta, { size = round(12 * s), font = T.mono, color = T.dim, clip = clip, spacing = 0.5 })
			ass:rect(sec.x1, y + round(40 * s), sec.x2, y + round(41 * s), { color = T.line, opacity = sec.open and 0.12 or 0.06, clip = clip })
		end
	end
	for i, c in ipairs(L.cards) do
		local y = c.y - lib.scroll
		if y + c.h > clip_top - round(4 * s) and y < H then
			local item = c.item
			local rec = thumb_for(item)
			local active = hover_i == i or lib.sel == i
			local tx1, ty1, tx2, ty2 = c.x, y, c.x + L.thumb_w, y + L.thumb_h
			if active then
				ass:rect(c.x - round(6 * s), y - round(6 * s), c.x + c.w + round(6 * s), y + c.h + round(2 * s),
					{ color = T.hover, opacity = 0.9, radius = round(10 * s), border = 1.5, border_color = T.gold, border_opacity = 0.95, clip = clip })
			end
			ass:rect(tx1, ty1, tx2, ty2, { color = T.thumb_bg, opacity = 1, radius = round(6 * s), clip = clip })
			if item.current and not active then
				ass:rect(tx1 - round(3 * s), ty1 - round(3 * s), tx2 + round(3 * s), ty2 + round(3 * s), { color = T.gold, opacity = 0, radius = round(8 * s), border = 1.5, border_color = T.gold, border_opacity = 0.8, clip = clip })
			end
			local covered = false
			local trect = { x1 = tx1, y1 = ty1, x2 = tx2, y2 = ty2 }
			for _, b in ipairs(blockers) do if rects_intersect(trect, b) then covered = true end end
			if state.uosc_menu then covered = true end
			-- bitmap overlays can't be clipped by ASS, so a thumb sliding under the header is withheld;
			-- past the bottom edge mpv clips it for us
			if rec.status == 'ready' and not covered and ty1 >= clip_top and ty1 < H then
				wanted[#wanted + 1] = { file = rec.file, x = round(tx1), y = round(ty1), w = rec.w, h = rec.h }
			else
				ass:icon((tx1 + tx2) / 2, (ty1 + ty2) / 2, 5, kind_icon[item.kind] or 'movie', { size = round(40 * s), color = T.faint, clip = clip })
				if rec.status == 'pending' or rec.status == 'running' then
					if ty1 < H and ty2 > clip_top then queue_thumb(item, true) end
				end
			end
			local name = item.name:gsub('%.[^.]+$', '')
			ass:text(c.x, ty2 + round(10 * s), 7, ellipsize(name, round(14 * s), c.w), { size = round(14 * s), color = active and T.gold or T.text, clip = clip })
			local parts = {}
			if item.duration then parts[#parts + 1] = fmt_duration(item.duration) end
			if not item.is_url then
				parts[#parts + 1] = fmt_date(item.mtime)
				parts[#parts + 1] = fmt_size(item.size)
			end
			ass:text(c.x, ty2 + round(32 * s), 7, table.concat(parts, '  ·  '), { size = round(11.5 * s), font = T.mono, color = T.dim, clip = clip })
			if item.current then
				local badge = 'PLAYING'
				local bw = text_width(badge, round(10 * s), 0.7) + round(12 * s)
				ass:rect(c.x + c.w - bw, ty2 + round(24 * s), c.x + c.w, ty2 + round(40 * s), { color = T.gold, opacity = 0.9, radius = round(4 * s), clip = clip })
				ass:text(c.x + c.w - bw / 2, ty2 + round(32 * s), 5, badge, { size = round(10 * s), font = T.mono, color = T.bg, bold = true, clip = clip })
			elseif item.kind ~= 'video' then
				ass:icon(c.x + c.w, ty2 + round(32 * s), 9, kind_icon[item.kind], { size = round(15 * s), color = T.dim, clip = clip })
			end
		end
	end
	-- background job pass: keep the queue warm with the off-screen cards of open sections
	for _, sec in ipairs(L.sections) do
		if sec.open then for _, item in ipairs(sec.section.items) do queue_thumb(item, false) end end
	end
	pump_queue()
	if #lib.items == 0 then
		ass:text(W / 2, H / 2, 5, playlist_mode and 'Playlist is empty' or 'No media found', { size = round(22 * s), font = T.serif, color = T.dim })
		if not playlist_mode then
			ass:text(W / 2, H / 2 + round(30 * s), 5, 'Folders: ' .. table.concat(lib.roots or {}, ', ') .. '   —   edit dirs= in script-opts/shelf.conf', { size = round(13 * s), font = T.mono, color = T.faint })
		end
	end
	-- scrollbar
	if lib.max_scroll > 0 then
		local track_y1, track_y2 = clip_top, H - round(8 * s)
		local track_h = track_y2 - track_y1
		local knob_h = math.max(round(30 * s), track_h * (L.view_h / L.content_h))
		local knob_y = track_y1 + (track_h - knob_h) * (lib.scroll / lib.max_scroll)
		ass:rect(W - round(8 * s), knob_y, W - round(4 * s), knob_y + knob_h, { color = T.gold, opacity = 0.55, radius = round(2 * s) })
	end
	local t0 = mp.get_time()
	lib_osd.data = ass:render()
	lib_osd:update()
	local t1 = mp.get_time()
	overlays_sync(wanted)
	msg.debug(string.format('render: ass %.1fms overlays %.1fms (%d thumbs)', (t1 - t0) * 1000, (mp.get_time() - t1) * 1000, #wanted))
end

render = function()
	for _, osd in ipairs({ lib_osd, top_osd }) do
		osd.res_x, osd.res_y = display.w, display.h
	end
	-- top strip + dropdown first so the library knows which thumbnails they cover
	local top = Ass.new()
	render_topbar(top)
	render_dropdown(top)
	top_osd.data = top:render()
	top_osd:update()
	render_library(Ass.new())
end

-- ------------------------------------------------------------------ input --
local function on_mouse_move()
	local changed = false
	if lib.visible then
		local i = card_at(mouse.x, mouse.y)
		if i ~= lib.hover then lib.hover = i lib.sel = nil changed = true end
		local b = button_at(mouse.x, mouse.y)
		if b ~= lib.hover_button then lib.hover_button = b changed = true end
		local hh = header_at(mouse.x, mouse.y)
		if hh ~= lib.hover_header then lib.hover_header = hh changed = true end
	end
	if dd.open then dd_update_hover() end
	-- top bar reveal / button hover changes
	local tb = top_button_at(mouse.x, mouse.y)
	if tb ~= state.last_top_button then state.last_top_button = tb changed = true end
	if not lib.visible and not state.idle and not dd.open then
		local op = topbar_opacity()
		if op ~= (state.last_top_op or -1) then state.last_top_op = op changed = true end
	end
	if changed then request_render() end
end

mp.observe_property('mouse-pos', 'native', function(_, pos)
	if not pos then return end
	mouse.x, mouse.y, mouse.hover = pos.x, pos.y, pos.hover
	on_mouse_move()
end)

mp.observe_property('osd-dimensions', 'native', function(_, dim)
	if not dim or dim.w == 0 then return end
	if dim.w ~= display.w or dim.h ~= display.h then
		display.w, display.h = dim.w, dim.h
		lib.layout = nil
		request_render()
	end
end)

mp.observe_property('display-hidpi-scale', 'native', function(_, v)
	local nv = v or 1
	if nv ~= display.hidpi then
		display.hidpi = nv
		thumbs.state = {} -- thumbnails are cached per pixel size
		lib.layout = nil
		request_render()
	end
end)

mp.observe_property('idle-active', 'bool', function(_, idle)
	state.idle = idle and true or false
	if state.idle then
		if o.show_on_idle then show_library('library') else request_render() end
	else
		request_render()
	end
end)

mp.observe_property('pause', 'bool', function(_, v)
	state.paused = v and true or false
	request_render()
end)

mp.observe_property('playlist-pos-1', 'number', function(_, v)
	state.pl_pos = v or 0
	if lib.mode == 'playlist' then
		for _, item in ipairs(lib.items) do item.current = item.pl_index == state.pl_pos - 1 end
	end
	request_render()
end)
mp.observe_property('playlist-count', 'number', function(_, v)
	state.pl_count = v or 0
	if lib.visible and lib.mode == 'playlist' then
		local keep_scroll = lib.scroll
		use_sections(build_playlist_sections())
		lib.scroll = keep_scroll
	end
	request_render()
end)
mp.observe_property('fullscreen', 'bool', function(_, v) state.fullscreen = v and true or false request_render() end)

mp.observe_property('media-title', 'string', function(_, v)
	state.title = v or ''
	request_render()
end)

mp.observe_property('eof-reached', 'bool', function(_, v)
	if v and o.show_on_eof and not state.idle then show_library('library') end
end)

mp.observe_property('user-data/uosc/menu/type', 'native', function(_, v)
	local open = v ~= nil
	if open ~= state.uosc_menu then
		state.uosc_menu = open
		if open then close_dropdown() end
		request_render()
	end
end)

mp.register_event('file-loaded', function()
	state.file_loaded = true
	hide_library()
	close_dropdown()
end)

mp.register_event('end-file', function(e)
	if e and e.reason == 'quit' then return end
end)

mp.add_key_binding(nil, 'toggle-library', toggle_library)
mp.add_key_binding(nil, 'playlist', toggle_playlist)
mp.add_key_binding(nil, 'show-library', function() show_library('library') end)
mp.add_key_binding(nil, 'hide-library', hide_library)
mp.add_key_binding(nil, 'toggle-actions', toggle_dropdown)
mp.add_key_binding(nil, 'rescan', function()
	thumbs.state = {}
	rescan()
	if not lib.visible then mp.osd_message('Library rescanned') end
end)

-- external control, e.g. `mpv --idle` + `script-message-to shelf set-dirs /path`
mp.register_script_message('set-dirs', function(dirs)
	o.dirs = dirs
	rescan()
end)
mp.register_script_message('set-accordion', function(v) set_accordion(v == 'yes' or v == 'true' or v == '1') end)

-- initial scan in the background so the idle window shows content right away
mp.add_timeout(0.05, function()
	if not lib.scanned then rescan() end
	request_render()
end)
