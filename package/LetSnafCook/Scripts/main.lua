local MOD = "LetSnafCook"

local MEATBUG_RAGOUT = "/Script/Angelscript.ItFo_Meatbugragout"
local BROCK_STEW = "/Script/Angelscript.ItFo_Ottostew"
local SYRA_STEW = "/Script/Angelscript.ItFo_SyraRecipe"
local BROCK_QUEST_MAIN = "/Script/Angelscript.Quest_OldCamp_OCCHAPTER1_FORGOTEN_RECIPE"
local SYRA_QUEST_MAIN = "/Script/Angelscript.Quest_OldCamp_OCCHAPTER2_SYRARECIPE"
local SYRA_QUEST_WAIT_SNAF = "/Script/Angelscript.Quest_OldCamp_OCCHAPTER2_SYRARECIPE_SYRARECIPE_OBJ_WAITSNAF"
local SNAF_AFTERSUCCESS = "ChoiceSnafAftersuccess"
local PENDING_SECONDS = 25
local CONFIG_FILE_NAME = "LetSnafCook.ini"
local FOOD_KEYS = { "meatbug", "brock", "syra" }
local FOOD_CODES = {
    meatbug = 1,
    brock = 2,
    syra = 3,
}
local DEFAULT_CONFIG = {
    Upgrade1 = { "brock", "brock", "brock" },
    Upgrade2 = { "syra", "syra", "syra" },
}

local pending_snaf_reward = false
local pending_reward_mix = nil
local pending_since = 0
local suppress_original_reward_hud_until = 0
local swapping_inventory = false
local object_cache = {}
local live_instance_cache = {}
local config_cache = nil
local config_file_path = nil
local shared_mod_menu = nil

local function log(message)
    print("[" .. MOD .. "] " .. tostring(message) .. "\n")
end

local function safe(label, fn)
    local ok, result = pcall(fn)
    if not ok then
        log(label .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function try(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function upper(value)
    return string.upper(trim(value))
end

local function script_directory()
    local info = try(function()
        if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
            return nil
        end
        return debug.getinfo(1, "S")
    end)
    if not info or not info.source then
        return nil
    end

    local source = tostring(info.source)
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("^(.*[\\/])[^\\/]*$")
end

local function read_text_file(path)
    local file = try(function()
        if type(io) ~= "table" or type(io.open) ~= "function" then return nil end
        return io.open(path, "r")
    end)
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()
    return content
end

local function write_text_file(path, content)
    local file = try(function()
        if type(io) ~= "table" or type(io.open) ~= "function" then return nil end
        return io.open(path, "w")
    end)
    if not file then
        return false
    end

    file:write(content)
    file:close()
    return true
end

local function config_candidate_paths()
    local paths = {}
    local dir = script_directory()
    if dir then
        table.insert(paths, dir .. "..\\" .. CONFIG_FILE_NAME)
        table.insert(paths, dir .. CONFIG_FILE_NAME)
    end
    table.insert(paths, "Mods\\LetSnafCook\\" .. CONFIG_FILE_NAME)
    table.insert(paths, "ue4ss\\Mods\\LetSnafCook\\" .. CONFIG_FILE_NAME)
    table.insert(paths, CONFIG_FILE_NAME)
    return paths
end

local function parse_ini(content)
    local result = {}
    for line in string.gmatch(tostring(content or ""), "[^\r\n]+") do
        local stripped = trim(line)
        if stripped ~= "" and stripped:sub(1, 1) ~= ";"
            and stripped:sub(1, 1) ~= "#"
            and stripped:sub(1, 1) ~= "["
        then
            local key, value = stripped:match("^([%w_%.%-]+)%s*=%s*(.-)%s*$")
            if key and value then
                result[upper(key)] = trim(value)
            end
        end
    end
    return result
end

local function normalize_food_token(value)
    local token = upper(value)
    token = string.gsub(token, "[%s_%-']", "")
    if token == "BROCK" or token == "BROCKS"
        or token == "BROCKSTEW" or token == "BROCKSSTEW"
        or token == "BROCKEINTOPF" or token == "BROCKSEINTOPF"
    then
        return "brock"
    end
    if token == "SYRA" or token == "SYRAS"
        or token == "SYRASTEW" or token == "SYRASSTEW"
        or token == "SYRAEINTOPF" or token == "SYRASEINTOPF"
    then
        return "syra"
    end
    if token == "MEAT" or token == "MEATBUG" or token == "MEATBUGS"
        or token == "MEATBUGRAGOUT"
        or token == "FLEISCHWANZE" or token == "FLEISCHWANZEN"
        or token == "FLEISCHWANZENRAGOUT"
    then
        return "meatbug"
    end
    return nil
end

local function food_label(key)
    if key == "meatbug" then return "Meatbug Ragout" end
    if key == "brock" then return "Brock's Stew" end
    if key == "syra" then return "Syra's Stew" end
    return tostring(key)
end

local function parse_upgrade(name, value)
    local text = trim(value)
    if text == "" then
        log(name .. " missing in config; using lower available food.")
        return nil
    end

    local upgrade = {}
    for part in string.gmatch(text, "([^,%.]+)") do
        local token = normalize_food_token(part)
        if token == nil then
            log(name .. " has invalid food entry '" .. trim(part)
                .. "'; using lower available food.")
            return nil
        end
        table.insert(upgrade, token)
    end

    if #upgrade ~= 3 then
        log(name .. " must contain exactly 3 portions but has "
            .. tostring(#upgrade) .. "; using lower available food.")
        return nil
    end
    return upgrade
end

local function copy_upgrade(upgrade)
    local copy = {}
    for i, key in ipairs(upgrade or {}) do
        copy[i] = key
    end
    return copy
end

local function default_config_copy()
    return {
        Upgrade1 = copy_upgrade(DEFAULT_CONFIG.Upgrade1),
        Upgrade2 = copy_upgrade(DEFAULT_CONFIG.Upgrade2),
    }
end

local function config_from_ini(ini)
    ini = ini or {}
    return {
        Upgrade1 = parse_upgrade("Upgrade1", ini.UPGRADE1),
        Upgrade2 = parse_upgrade("Upgrade2", ini.UPGRADE2),
    }
end

local function is_valid(obj)
    if obj == nil then return false end
    if type(obj) ~= "userdata" and type(obj) ~= "table" then return false end
    local ok, result = pcall(function()
        if type(obj.IsValid) ~= "function" then return false end
        return obj:IsValid()
    end)
    return ok and result == true
end

local function unwrap(param)
    if param == nil then return nil end
    if type(param) == "number" or type(param) == "string" or type(param) == "boolean" then
        return param
    end
    if type(param) == "userdata" or type(param) == "table" then
        local value = safe("param get", function()
            if type(param.get) == "function" then return param:get() end
            if type(param.Get) == "function" then return param:Get() end
            return param
        end)
        if value ~= nil then return value end
    end
    return param
end

local function set_param(param, value)
    if param == nil or value == nil then return false end
    return safe("param set", function()
        if type(param.set) == "function" then
            param:set(value)
            return true
        end
        if type(param.Set) == "function" then
            param:Set(value)
            return true
        end
        return false
    end) == true
end

local function find_object(path)
    local cached = object_cache[path]
    if cached ~= nil and is_valid(cached) then return cached end

    local obj = safe("StaticFindObject " .. path, function()
        if type(StaticFindObject) == "function" then
            return StaticFindObject(nil, nil, path, false)
        end
        return nil
    end)

    if not is_valid(obj) and type(StaticFindObject) == "function" then
        obj = safe("StaticFindObject legacy " .. path, function()
            return StaticFindObject(path)
        end)
    end

    if is_valid(obj) then
        object_cache[path] = obj
        return obj
    end
    return nil
end

local function full_name(obj)
    if not is_valid(obj) then return "" end
    return safe("GetFullName", function() return obj:GetFullName() end) or ""
end

local function name_contains(obj, needle)
    return string.find(full_name(obj), needle, 1, true) ~= nil
end

local function short_name(path)
    return string.match(path, "%.([^%.]+)$") or string.match(path, "/([^/]+)$") or path
end

local function not_default_object(obj)
    return is_valid(obj) and string.find(full_name(obj), "Default__", 1, true) == nil
end

local function find_live_instance(class_name)
    local cached = live_instance_cache[class_name]
    if cached ~= nil and is_valid(cached) then return cached end

    local list = try(function()
        if type(FindAllOf) == "function" then return FindAllOf(class_name) end
        return nil
    end)
    if list == nil then return nil end

    local fallback = nil
    for _, obj in ipairs(list) do
        if not_default_object(obj) then
            if string.find(full_name(obj), ".Instance_", 1, true) ~= nil then
                live_instance_cache[class_name] = obj
                return obj
            end
            fallback = fallback or obj
        end
    end

    if is_valid(fallback) then
        live_instance_cache[class_name] = fallback
        return fallback
    end
    return nil
end

local function param_count(count_param)
    return tonumber(unwrap(count_param))
end

local function is_meatbug_ragout(item_param)
    return name_contains(unwrap(item_param), "ItFo_Meatbugragout")
end

local function quest_subsystem()
    local subsystem = find_live_instance("QuestSubsystem")
    if is_valid(subsystem) then return subsystem end
    return nil
end

local function quest_instance(quest_path)
    local class_name = short_name(quest_path)
    local quest_class = find_object(quest_path)
    local subsystem = quest_subsystem()

    if is_valid(subsystem) and is_valid(quest_class) then
        local quest = try(function()
            if type(subsystem.GetQuestByClass) ~= "function" then return nil end
            return subsystem:GetQuestByClass(quest_class)
        end)
        if not_default_object(quest) then return quest end
    end

    return find_live_instance(class_name)
end

local function enum_value(value)
    if value == nil then return nil end

    local unwrapped = value
    local resolved = try(function()
        if type(value) == "userdata" or type(value) == "table" then
            if type(value.get) == "function" then return value:get() end
            if type(value.Get) == "function" then return value:Get() end
        end
        return value
    end)
    if resolved ~= nil then unwrapped = resolved end

    local number = try(function() return tonumber(unwrapped) end)
    if number ~= nil then return number end
    local text = tostring(unwrapped)
    if string.find(text, "Succeeded", 1, true) ~= nil then return 4 end
    return nil
end

local function quest_state(quest)
    if not is_valid(quest) then return nil end

    local state = try(function()
        if type(quest.GetState) == "function" then return quest:GetState() end
    end)
    if state == nil then
        state = try(function() return quest.State end)
    end
    return enum_value(state)
end

local function quest_succeeded(quest)
    if not is_valid(quest) then return false end

    local succeeded = try(function()
        if type(quest.HasSucceeded) ~= "function" then return false end
        return quest:HasSucceeded()
    end)
    if succeeded == true or succeeded == 1 then return true end

    return quest_state(quest) == 4
end

local function quest_succeeded_by_path(quest_path)
    return quest_succeeded(quest_instance(quest_path))
end

local function syra_quest_done()
    return quest_succeeded_by_path(SYRA_QUEST_MAIN)
        or quest_succeeded_by_path(SYRA_QUEST_WAIT_SNAF)
end

local function brock_quest_done()
    return quest_succeeded_by_path(BROCK_QUEST_MAIN)
end

local function load_config()
    if config_cache ~= nil then return config_cache end

    config_cache = default_config_copy()
    local loaded_config = false
    local function upgrade_text(upgrade)
        if type(upgrade) ~= "table" then return "<invalid>" end
        return table.concat(upgrade, ",")
    end

    for _, path in ipairs(config_candidate_paths()) do
        local content = read_text_file(path)
        if content then
            config_cache = config_from_ini(parse_ini(content))
            config_file_path = path
            loaded_config = true
            log("Loaded config from " .. path
                .. ": Upgrade1=" .. upgrade_text(config_cache.Upgrade1)
                .. " Upgrade2=" .. upgrade_text(config_cache.Upgrade2))
            break
        end
    end
    if not loaded_config then
        log("Config not found; using defaults.")
    end
    return config_cache
end

local function upgrade_text(upgrade)
    if type(upgrade) ~= "table" then return nil end
    return table.concat(upgrade, ",")
end

local function writable_config_path()
    if config_file_path ~= nil then return config_file_path end
    local paths = config_candidate_paths()
    config_file_path = paths[1] or CONFIG_FILE_NAME
    return config_file_path
end

local function config_file_content(config)
    return table.concat({
        "; Let Snaf Cook",
        "; Snaf starts with his original Meatbug Ragout reward.",
        ";",
        "; Upgrade1 is active after The Forgotten Recipe unlocks Brock's Stew.",
        "; Upgrade2 is active after Snaf's Syra recipe quest unlocks Syra's Stew.",
        ";",
        "; Each upgrade must contain exactly 3 portions.",
        "; Separators: comma or dot",
        "; Allowed values: meatbug/meat, brock, syra",
        ";",
        "; SharedModMenu shows each portion as a number:",
        "; 1 = meatbug, 2 = brock, 3 = syra",
        "",
        "Upgrade1=" .. (upgrade_text(config.Upgrade1) or upgrade_text(DEFAULT_CONFIG.Upgrade1)),
        "Upgrade2=" .. (upgrade_text(config.Upgrade2) or upgrade_text(DEFAULT_CONFIG.Upgrade2)),
        "",
    }, "\n")
end

local function save_config()
    local config = load_config()
    local path = writable_config_path()
    if write_text_file(path, config_file_content(config)) then
        log("Saved config to " .. path
            .. ": Upgrade1=" .. tostring(upgrade_text(config.Upgrade1))
            .. " Upgrade2=" .. tostring(upgrade_text(config.Upgrade2)))
        return true
    end

    log("Could not save config to " .. tostring(path))
    return false
end

local function menu_upgrade(stage_name)
    local config = load_config()
    if type(config[stage_name]) ~= "table" then
        config[stage_name] = copy_upgrade(DEFAULT_CONFIG[stage_name])
    end
    return config[stage_name]
end

local function menu_food_code(stage_name, index)
    local key = menu_upgrade(stage_name)[index]
    return FOOD_CODES[key] or FOOD_CODES.meatbug
end

local function menu_set_food_code(stage_name, index, value)
    local code = math.floor((tonumber(value) or 1) + 0.5)
    if code < 1 then code = 1 end
    if code > #FOOD_KEYS then code = #FOOD_KEYS end

    menu_upgrade(stage_name)[index] = FOOD_KEYS[code]
    log("SharedModMenu set " .. stage_name .. " portion " .. tostring(index)
        .. " to " .. tostring(FOOD_KEYS[code]))
    save_config()
end

local function reset_stage_config(stage_name)
    load_config()[stage_name] = copy_upgrade(DEFAULT_CONFIG[stage_name])
    save_config()
    if shared_mod_menu and type(shared_mod_menu.requestRefresh) == "function" then
        shared_mod_menu.requestRefresh()
    end
end

local function menu_slot(stage_name, index)
    local display_stage = string.gsub(stage_name, "Upgrade", "Upgrade ")
    local slot_stage = stage_name
    local slot_index = index
    return {
        name = display_stage .. " Portion " .. tostring(slot_index),
        kind = "num",
        min = 1,
        max = #FOOD_KEYS,
        step = 1,
        desc = "1 Meatbug, 2 Brock, 3 Syra",
        get = function()
            return menu_food_code(slot_stage, slot_index)
        end,
        set = function(value)
            menu_set_food_code(slot_stage, slot_index, value)
        end,
    }
end

local function register_shared_mod_menu()
    local dir = script_directory()
    if dir then
        package.path = dir .. "?.lua;" .. package.path
    end
    package.loaded["modmenu"] = nil

    local ok, modmenu = pcall(require, "modmenu")
    if not ok or type(modmenu) ~= "table" or type(modmenu.register) ~= "function" then
        log("SharedModMenu bridge unavailable: " .. tostring(modmenu))
        return
    end
    shared_mod_menu = modmenu

    modmenu.register("Let Snaf Cook", {
        {
            title = "Upgrade 1",
            items = {
                menu_slot("Upgrade1", 1),
                menu_slot("Upgrade1", 2),
                menu_slot("Upgrade1", 3),
                {
                    name = "Reset Upgrade 1",
                    kind = "action",
                    desc = "Default: 3x Brock",
                    set = function()
                        reset_stage_config("Upgrade1")
                    end,
                },
            },
        },
        {
            title = "Upgrade 2",
            items = {
                menu_slot("Upgrade2", 1),
                menu_slot("Upgrade2", 2),
                menu_slot("Upgrade2", 3),
                {
                    name = "Reset Upgrade 2",
                    kind = "action",
                    desc = "Default: 3x Syra",
                    set = function()
                        reset_stage_config("Upgrade2")
                    end,
                },
            },
        },
    })
    log("Registered SharedModMenu integration.")
end

local function lower_available_food_for_stage(stage_name, brock_done)
    if stage_name == "Upgrade2" and brock_done then
        return "brock"
    end
    return "meatbug"
end

local function lower_available_upgrade(stage_name, brock_done)
    local key = lower_available_food_for_stage(stage_name, brock_done)
    return { key, key, key }
end

local function recipe_unlocked(key, brock_done, syra_done)
    if key == "meatbug" then return true end
    if key == "brock" then return brock_done end
    if key == "syra" then return syra_done end
    return false
end

local function lower_available_food_for_request(key, brock_done)
    if key == "syra" and brock_done then
        return "brock"
    end
    return "meatbug"
end

local function recipe_path(key)
    if key == "meatbug" then return MEATBUG_RAGOUT end
    if key == "brock" then return BROCK_STEW end
    if key == "syra" then return SYRA_STEW end
    return nil
end

local function append_reward(mix, key, count)
    local path = recipe_path(key)
    if path == nil or count <= 0 then return end
    table.insert(mix, {
        key = key,
        path = path,
        count = count,
    })
end

local function upgrade_contains(stage_config, key)
    for _, configured_key in ipairs(stage_config or {}) do
        if configured_key == key then return true end
    end
    return false
end

local function configured_reward_mix()
    local syra_done = syra_quest_done()
    local stage_name = nil
    local stage_config = nil
    local brock_done = false

    if syra_done then
        stage_name = "Upgrade2"
        stage_config = load_config()[stage_name]
        if stage_config == nil then
            brock_done = brock_quest_done()
            stage_config = lower_available_upgrade(stage_name, brock_done)
            log(stage_name .. " config is invalid; using "
                .. table.concat(stage_config, ",") .. ".")
        elseif upgrade_contains(stage_config, "brock") then
            brock_done = brock_quest_done()
        end
    else
        brock_done = brock_quest_done()
        if not brock_done then return nil end

        stage_name = "Upgrade1"
        stage_config = load_config()[stage_name]
        if stage_config == nil then
            stage_config = lower_available_upgrade(stage_name, brock_done)
            log(stage_name .. " config is invalid; using "
                .. table.concat(stage_config, ",") .. ".")
        end
    end

    local mix = {}
    local counts = {}
    local fallback_counts = {}
    for _, requested_key in ipairs(stage_config) do
        local key = requested_key
        if not recipe_unlocked(key, brock_done, syra_done) then
            fallback_counts[key] = (fallback_counts[key] or 0) + 1
            key = lower_available_food_for_request(key, brock_done)
        end
        counts[key] = (counts[key] or 0) + 1
    end

    for _, key in ipairs({ "syra", "brock", "meatbug" }) do
        local count = fallback_counts[key] or 0
        if count > 0 then
            log(stage_name .. " requested " .. tostring(count) .. "x "
                .. food_label(key) .. " but its quest is not completed; using "
                .. food_label(lower_available_food_for_request(key, brock_done))
                .. " instead.")
        end
    end

    for _, key in ipairs({ "syra", "brock", "meatbug" }) do
        append_reward(mix, key, counts[key] or 0)
    end

    if #mix == 0 then
        return nil
    end
    return mix
end

local function pending_reward()
    if not pending_snaf_reward then return false end
    if os.clock() - pending_since > PENDING_SECONDS then
        pending_snaf_reward = false
        pending_reward_mix = nil
        return false
    end
    return true
end

local function arm_reward_swap()
    if pending_reward() then return end

    pending_snaf_reward = true
    pending_reward_mix = configured_reward_mix()
    pending_since = os.clock()
end

local function clear_reward_swap()
    pending_snaf_reward = false
    pending_reward_mix = nil
end

local function should_suppress_original_reward_hud()
    if pending_reward() and pending_reward_mix ~= nil then return true end
    return os.clock() < suppress_original_reward_hud_until
end

local function is_player_inventory(inventory)
    return string.find(full_name(inventory), "G1RPlayerState", 1, true) ~= nil
end

local function delay_game_thread(ms, fn)
    if type(fn) ~= "function" then return false end
    if type(ExecuteInGameThreadWithDelay) == "function" then
        ExecuteInGameThreadWithDelay(ms, function() safe("delayed swap", fn) end)
        return true
    end
    if type(ExecuteWithDelay) == "function" then
        ExecuteWithDelay(ms, function()
            if type(ExecuteInGameThread) == "function" then
                ExecuteInGameThread(function() safe("delayed swap", fn) end)
            else
                safe("delayed swap", fn)
            end
        end)
        return true
    end
    return false
end

local function add_reward_mix(inventory, total_count)
    local remaining = tonumber(total_count) or 0
    for _, reward in ipairs(pending_reward_mix or {}) do
        if remaining <= 0 then return true end

        local amount = reward.count
        if amount > remaining then amount = remaining end

        local item = find_object(reward.path)
        if not is_valid(item) then
            log("Could not resolve " .. reward.path)
            return false
        end

        local added = safe("add " .. reward.key, function()
            inventory:AddItemOfClass(item, amount)
            return true
        end) == true
        if not added then return false end

        remaining = remaining - amount
    end
    return remaining == 0
end

local function swap_player_inventory_reward(inventory_param, attempt)
    if swapping_inventory or not pending_reward() then return false end

    local inventory = unwrap(inventory_param)
    if not is_valid(inventory) or not is_player_inventory(inventory) then return false end

    local ragout = find_object(MEATBUG_RAGOUT)
    if not is_valid(ragout) then
        log("Could not resolve original ragout class")
        return false
    end

    swapping_inventory = true
    local removed = safe("remove original ragout", function()
        return inventory:RemoveItemOfClass(ragout, 3)
    end)
    local removed_count = tonumber(removed) or 0

    if removed_count > 0 then
        local added = add_reward_mix(inventory, removed_count)
        swapping_inventory = false

        if added then
            suppress_original_reward_hud_until = os.clock() + 2
            clear_reward_swap()
            return true
        end
        return false
    end

    swapping_inventory = false
    local next_attempt = (tonumber(attempt) or 1) + 1
    if next_attempt <= 3 then
        delay_game_thread(150, function()
            swap_player_inventory_reward(inventory, next_attempt)
        end)
    end
    return false
end

local function register_hook(path, handler)
    if type(RegisterHook) ~= "function" then
        log("RegisterHook unavailable")
        return false
    end
    local ok, err = pcall(function()
        RegisterHook(path, handler)
    end)
    if not ok then
        log("Could not register hook " .. path .. ": " .. tostring(err))
        return false
    end
    return true
end

load_config()
register_shared_mod_menu()

register_hook("/Script/G1R.GameplayAbilityConversationV2WithUI:ServerRequestStartActingTopic",
    function(context, topic)
        if string.find(full_name(unwrap(topic)), SNAF_AFTERSUCCESS, 1, true) ~= nil then
            arm_reward_swap()
        end
    end)

register_hook("/Script/G1R.InventoryComponent:OnItemAddedForHUD",
    function(_context, item, count)
        if should_suppress_original_reward_hud()
            and param_count(count) == 3
            and is_meatbug_ragout(item) then
            set_param(count, 0)
        end
    end)

register_hook("/Script/G1R.InventoryComponent:MemorizeItem",
    function(context, item, count)
        if swapping_inventory then return end

        if pending_reward()
            and param_count(count) == 3
            and is_meatbug_ragout(item) then
            if pending_reward_mix ~= nil then
                swap_player_inventory_reward(context, 1)
            else
                clear_reward_swap()
            end
        end
    end)
