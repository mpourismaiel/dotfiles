local capi = {
    awesome = awesome
}
local awful = require("awful")
local gears = require("gears")
local store = require("lib.module.store")
local log = require("lib.module.log")

local keyboard_layout = {}
local instance = nil

function keyboard_layout.get_layouts()
    local layouts = {}
    local handle = io.popen("localectl list-x11-keymap-layouts")
    if handle ~= nil then
        for layout in handle:lines() do
            table.insert(layouts, layout)
        end
        handle:close()
    end

    return layouts
end

function keyboard_layout.get_models()
    local models = {}
    local handle = io.popen("localectl list-x11-keymap-models")
    if handle ~= nil then
        for model in handle:lines() do
            table.insert(models, model)
        end
        handle:close()
    end

    return models
end

function keyboard_layout.get_variants(layout)
    if not layout then
        return nil
    end

    local variants = {}
    local handle = io.popen("localectl list-x11-keymap-variants " .. layout)
    if handle ~= nil then
        for variant in handle:lines() do
            table.insert(variants, variant)
        end
        handle:close()
    end

    return variants
end

keyboard_layout.get_options = {
    ["alt_shift_toggle"] = "grp:alt_shift_toggle",
    ["caps_toggle"] = "grp:caps_toggle"
}

function keyboard_layout.check_table(tbl, find)
    for _, value in ipairs(tbl) do
        if value == find then
            return true
        end
    end
end

keyboard_layout.xkeyboard_country_code = {
    ["ad"] = true, -- Andorra
    ["af"] = true, -- Afganistan
    ["al"] = true, -- Albania
    ["am"] = true, -- Armenia
    ["ara"] = true, -- Arabic
    ["at"] = true, -- Austria
    ["az"] = true, -- Azerbaijan
    ["ba"] = true, -- Bosnia and Herzegovina
    ["bd"] = true, -- Bangladesh
    ["be"] = true, -- Belgium
    ["bg"] = true, -- Bulgaria
    ["br"] = true, -- Brazil
    ["bt"] = true, -- Bhutan
    ["bw"] = true, -- Botswana
    ["by"] = true, -- Belarus
    ["ca"] = true, -- Canada
    ["cd"] = true, -- Congo
    ["ch"] = true, -- Switzerland
    ["cm"] = true, -- Cameroon
    ["cn"] = true, -- China
    ["cz"] = true, -- Czechia
    ["de"] = true, -- Germany
    ["dk"] = true, -- Denmark
    ["ee"] = true, -- Estonia
    ["epo"] = true, -- Esperanto
    ["es"] = true, -- Spain
    ["et"] = true, -- Ethiopia
    ["eu"] = true, -- EurKey
    ["fi"] = true, -- Finland
    ["fo"] = true, -- Faroe Islands
    ["fr"] = true, -- France
    ["gb"] = true, -- United Kingdom
    ["ge"] = true, -- Georgia
    ["gh"] = true, -- Ghana
    ["gn"] = true, -- Guinea
    ["gr"] = true, -- Greece
    ["hr"] = true, -- Croatia
    ["hu"] = true, -- Hungary
    ["ie"] = true, -- Ireland
    ["il"] = true, -- Israel
    ["in"] = true, -- India
    ["iq"] = true, -- Iraq
    ["ir"] = true, -- Iran
    ["is"] = true, -- Iceland
    ["it"] = true, -- Italy
    ["jp"] = true, -- Japan
    ["ke"] = true, -- Kenya
    ["kg"] = true, -- Kyrgyzstan
    ["kh"] = true, -- Cambodia
    ["kr"] = true, -- Korea
    ["kz"] = true, -- Kazakhstan
    ["la"] = true, -- Laos
    ["latam"] = true, -- Latin America
    ["latin"] = true, -- Latin
    ["lk"] = true, -- Sri Lanka
    ["lt"] = true, -- Lithuania
    ["lv"] = true, -- Latvia
    ["ma"] = true, -- Morocco
    ["mao"] = true, -- Maori
    ["me"] = true, -- Montenegro
    ["mk"] = true, -- Macedonia
    ["ml"] = true, -- Mali
    ["mm"] = true, -- Myanmar
    ["mn"] = true, -- Mongolia
    ["mt"] = true, -- Malta
    ["mv"] = true, -- Maldives
    ["ng"] = true, -- Nigeria
    ["nl"] = true, -- Netherlands
    ["no"] = true, -- Norway
    ["np"] = true, -- Nepal
    ["ph"] = true, -- Philippines
    ["pk"] = true, -- Pakistan
    ["pl"] = true, -- Poland
    ["pt"] = true, -- Portugal
    ["ro"] = true, -- Romania
    ["rs"] = true, -- Serbia
    ["ru"] = true, -- Russia
    ["se"] = true, -- Sweden
    ["si"] = true, -- Slovenia
    ["sk"] = true, -- Slovakia
    ["sn"] = true, -- Senegal
    ["sy"] = true, -- Syria
    ["th"] = true, -- Thailand
    ["tj"] = true, -- Tajikistan
    ["tm"] = true, -- Turkmenistan
    ["tr"] = true, -- Turkey
    ["tw"] = true, -- Taiwan
    ["tz"] = true, -- Tanzania
    ["ua"] = true, -- Ukraine
    ["us"] = true, -- USA
    ["uz"] = true, -- Uzbekistan
    ["vn"] = true, -- Vietnam
    ["za"] = true -- South Africa
}

-- Callback for updating current layout.
local function update_status(self)
    self._current = capi.awesome.xkb_get_layout_group()
    local text = ""
    if #self._layout > 0 then
        -- Please note that the group number reported by xkb_get_layout_group
        -- is lower by one than the group numbers reported by xkb_get_group_names.
        local name = self._layout[self._current + 1]
        if name then
            text = name
        end
    end
    self:emit_signal("update", text)
end

--- Auxiliary function for the local function update_layout().
-- Create an array whose element is a table consisting of the four fields:
-- vendor, file, section and group_idx, which all correspond to the
-- xkb_symbols pattern "vendor/file(section):group_idx".
-- @tparam string group_names The string `awesome.xkb_get_group_names()` returns.
-- @treturn table An array of tables whose keys are vendor, file, section, and group_idx.
-- @staticfct awful.keyboard_layout.get_groups_from_group_names
function keyboard_layout.get_groups_from_group_names(group_names)
    if group_names == nil then
        return nil
    end

    -- Pattern elements to be captured.
    local word_pat = "([%w_]+)"
    local sec_pat = "(%b())"
    local idx_pat = ":(%d)"
    -- Pairs of a pattern and its callback.  In callbacks, set 'group_idx' to 1
    -- and return it if there's no specification on 'group_idx' in the given
    -- pattern.
    local pattern_and_callback_pairs = {
        -- vendor/file(section):group_idx
        ["^" .. word_pat .. "/" .. word_pat .. sec_pat .. idx_pat .. "$"] = function(token, pattern)
            local vendor, file, section, group_idx = string.match(token, pattern)
            return vendor, file, section, group_idx
        end,
        -- vendor/file(section)
        ["^" .. word_pat .. "/" .. word_pat .. sec_pat .. "$"] = function(token, pattern)
            local vendor, file, section = string.match(token, pattern)
            return vendor, file, section, 1
        end,
        -- vendor/file:group_idx
        ["^" .. word_pat .. "/" .. word_pat .. idx_pat .. "$"] = function(token, pattern)
            local vendor, file, group_idx = string.match(token, pattern)
            return vendor, file, nil, group_idx
        end,
        -- vendor/file
        ["^" .. word_pat .. "/" .. word_pat .. "$"] = function(token, pattern)
            local vendor, file = string.match(token, pattern)
            return vendor, file, nil, 1
        end,
        --  file(section):group_idx
        ["^" .. word_pat .. sec_pat .. idx_pat .. "$"] = function(token, pattern)
            local file, section, group_idx = string.match(token, pattern)
            return nil, file, section, group_idx
        end,
        -- file(section)
        ["^" .. word_pat .. sec_pat .. "$"] = function(token, pattern)
            local file, section = string.match(token, pattern)
            return nil, file, section, 1
        end,
        -- file:group_idx
        ["^" .. word_pat .. idx_pat .. "$"] = function(token, pattern)
            local file, group_idx = string.match(token, pattern)
            return nil, file, nil, group_idx
        end,
        -- file
        ["^" .. word_pat .. "$"] = function(token, pattern)
            local file = string.match(token, pattern)
            return nil, file, nil, 1
        end
    }

    -- Split 'group_names' into 'tokens'.  The separator is "+".
    local tokens = {}
    string.gsub(
        group_names,
        "[^+]+",
        function(match)
            table.insert(tokens, match)
        end
    )

    -- For each token in 'tokens', check if it matches one of the patterns in
    -- the array 'pattern_and_callback_pairs', where the patterns are used as
    -- key.  If a match is found, extract captured strings using the
    -- corresponding callback function.  Check if those extracted is country
    -- specific part of a layout.  If so, add it to 'layout_groups'; otherwise,
    -- ignore it.
    local layout_groups = {}
    for i = 1, #tokens do
        for pattern, callback in pairs(pattern_and_callback_pairs) do
            local vendor, file, section, group_idx = callback(tokens[i], pattern)
            if file then
                if not keyboard_layout.xkeyboard_country_code[file] then
                    break
                end

                if section then
                    section = string.gsub(section, "%(([%w-_]+)%)", "%1")
                end

                table.insert(
                    layout_groups,
                    {
                        vendor = vendor,
                        file = file,
                        section = section,
                        group_idx = tonumber(group_idx)
                    }
                )
                break
            end
        end
    end

    return layout_groups
end

-- Callback for updating list of layouts
local function update_layout(self)
    self._layout = {}
    local layouts = keyboard_layout.get_groups_from_group_names(capi.awesome.xkb_get_group_names())
    if layouts == nil or layouts[1] == nil then
        return
    end
    if #layouts == 1 then
        layouts[1].group_idx = 1
    end
    for _, v in ipairs(layouts) do
        self._layout[v.group_idx] = self.layout_name(v)
    end
    update_status(self)
end

function keyboard_layout:update_settings(layouts, variants, options, model)
    if not layouts then
        return error("no layouts provided")
    end

    variants = variants or {}
    options = options or {}
    model = model or nil

    local valid_layouts = keyboard_layout.get_layouts()
    local valid_variants = {}
    for _, layout in ipairs(layouts) do
        valid_variants[layout] = keyboard_layout.get_variants(layout)
    end
    local valid_models = keyboard_layout.get_models()
    local valid_options = keyboard_layout.get_options

    for _, layout in ipairs(layouts) do
        if keyboard_layout.check_table(valid_layouts, layout) == nil then
            return error("layout: " .. layout .. " was not found in valid_layouts list.")
        end
    end

    for layout, variant in pairs(variants) do
        if
            variant ~= nil and valid_variants[layout] ~= nil and
                keyboard_layout.check_table(valid_variants[layout], variant) == nil
         then
            return error(
                "variant: " .. variant .. " was not found in valid_variants list for layout: " .. layout .. "."
            )
        end
    end

    for _, option in ipairs(options) do
        if valid_options[option] == nil then
            return error("option: " .. option .. " was not found in valid_options list.")
        end
    end

    if model ~= nil and keyboard_layout.check_table(valid_models, model) == nil then
        return error("model: " .. model .. " was not found in valid_models list.")
    end

    self._private.settings:set("layouts", layouts)
    self._private.settings:set("variants", variants)
    self._private.settings:set("options", options)
    self._private.settings:set("model", model)

    local command = "setxkbmap -option"
    if model ~= nil then
        command = command .. " -model " .. model
    end

    if #options > 0 then
        local options_arg = "grp:switch"
        for i, option in ipairs(options) do
            options_arg = options_arg .. "," .. valid_options[option]
        end

        command = command .. " -option " .. options_arg
    end

    local layouts_arg = ""
    local variants_arg = ""
    for i, layout in ipairs(layouts) do
        layouts_arg = i == 1 and layout or layouts_arg .. "," .. layout
        variants_arg = i == 1 and (variants[layout] or "") or variants_arg .. "," .. (variants[layout] or "")
    end

    command = command .. " -layout " .. layouts_arg
    if variants_arg ~= "" then
        command = command .. " -variant " .. variants_arg
    end

    awful.spawn(command)
end

function keyboard_layout:load_settings()
    local settings = self._private.settings
    if settings == nil then
        return
    end

    self:update_settings(
        settings:get("layouts"),
        settings:get("variants"),
        settings:get("options"),
        settings:get("model")
    )
end

local function new()
    local ret = gears.object {}
    gears.table.crush(ret, keyboard_layout, true)

    ret._private = {
        settings = store(
            "keyboard-settings",
            {
                model = nil,
                layouts = {"us"},
                variants = {},
                options = {"alt_shift_toggle"}
            }
        )
    }

    ret.layout_name = function(v)
        local name = v.file
        if v.section ~= nil then
            name = name
        end
        return name
    end

    ret.next_layout = function()
        ret.set_layout((ret._current + 1) % (#ret._layout + 1))
    end

    ret.set_layout = function(group_number)
        if (0 > group_number) or (group_number > #ret._layout) then
            error("Invalid group number: " .. group_number .. "expected number from 0 to " .. #ret._layout)
            return
        end
        capi.awesome.xkb_set_layout_group(group_number)
    end

    update_layout(ret)

    capi.awesome.connect_signal(
        "awesome::settings::language",
        function(layouts, variants, options, model)
            xpcall(
                function()
                    return ret:update_settings(layouts, variants, options, model)
                end,
                function(err)
                    log("Something happened: " .. err)
                end
            )
        end
    )

    capi.awesome.connect_signal(
        "xkb::map_changed",
        function()
            update_layout(ret)
        end
    )

    capi.awesome.connect_signal(
        "xkb::group_changed",
        function()
            update_status(ret)
        end
    )

    return ret
end

if not instance then
    instance = new()
end

return instance
