local MOD = "LetSnafCook"

local pleasureLib = require("pleasure_lib_loader").new(MOD)
if type(pleasureLib) ~= "table" then return end

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
local FOOD_SETTING_VALUES = {
    "Meatbug Ragout",
    "Brock's Stew",
    "Syra's Stew",
}
local FOOD_SETTING_VALUE_TRANSLATIONS = {
    en = FOOD_SETTING_VALUES,
    de = {
        "Fleischwanzenragout",
        "Brocks Eintopf",
        "Syras Eintopf",
    },
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
local live_instance_cache = {}
local config_cache = nil
local config_file_path = nil
local shared_mod_menu = nil

local function config_candidate_paths()
    local paths = {}
    local dir = pleasureLib:script_directory()
    if dir then
        table.insert(paths, dir .. "..\\" .. CONFIG_FILE_NAME)
        table.insert(paths, dir .. CONFIG_FILE_NAME)
    end
    table.insert(paths, "Mods\\LetSnafCook\\" .. CONFIG_FILE_NAME)
    table.insert(paths, "ue4ss\\Mods\\LetSnafCook\\" .. CONFIG_FILE_NAME)
    table.insert(paths, CONFIG_FILE_NAME)
    return paths
end

local function normalize_food_token(value)
    local token = pleasureLib:upper(value)
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
    local text = pleasureLib:trim(value)
    if text == "" then
        pleasureLib:log(name .. " missing in config; using lower available food.")
        return nil
    end

    local upgrade = {}
    for part in string.gmatch(text, "([^,%.]+)") do
        local token = normalize_food_token(part)
        if token == nil then
            pleasureLib:log(name .. " has invalid food entry '" .. pleasureLib:trim(part)
                .. "'; using lower available food.")
            return nil
        end
        table.insert(upgrade, token)
    end

    if #upgrade ~= 3 then
        pleasureLib:log(name .. " must contain exactly 3 portions but has "
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

local function set_param(param, value)
    if param == nil or value == nil then return false end
    return pleasureLib:safe("param set", function()
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

local function name_contains(obj, needle)
    return string.find(pleasureLib:full_name(obj), needle, 1, true) ~= nil
end

local function short_name(path)
    return string.match(path, "%.([^%.]+)$") or string.match(path, "/([^/]+)$") or path
end

local function not_default_object(obj)
    return pleasureLib:is_valid(obj) and string.find(pleasureLib:full_name(obj), "Default__", 1, true) == nil
end

local function find_live_instance(class_name)
    local cached = live_instance_cache[class_name]
    if cached ~= nil and pleasureLib:is_valid(cached) then return cached end

    local list = pleasureLib:find_all_of(class_name)
    if list == nil then return nil end

    local fallback = nil
    for _, obj in ipairs(list) do
        if not_default_object(obj) then
            if string.find(pleasureLib:full_name(obj), ".Instance_", 1, true) ~= nil then
                live_instance_cache[class_name] = obj
                return obj
            end
            fallback = fallback or obj
        end
    end

    if pleasureLib:is_valid(fallback) then
        live_instance_cache[class_name] = fallback
        return fallback
    end
    return nil
end

local function param_count(count_param)
    return tonumber(pleasureLib:unwrap(count_param))
end

local function is_meatbug_ragout(item_param)
    return name_contains(pleasureLib:unwrap(item_param), "ItFo_Meatbugragout")
end

local function quest_subsystem()
    local subsystem = find_live_instance("QuestSubsystem")
    if pleasureLib:is_valid(subsystem) then return subsystem end
    return nil
end

local function quest_instance(quest_path)
    local class_name = short_name(quest_path)
    local quest_class = pleasureLib:find_object(quest_path)
    local subsystem = quest_subsystem()

    if pleasureLib:is_valid(subsystem) and pleasureLib:is_valid(quest_class) then
        local quest = pleasureLib:try(function()
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
    local resolved = pleasureLib:try(function()
        if type(value) == "userdata" or type(value) == "table" then
            if type(value.get) == "function" then return value:get() end
            if type(value.Get) == "function" then return value:Get() end
        end
        return value
    end)
    if resolved ~= nil then unwrapped = resolved end

    local number = pleasureLib:try(function() return tonumber(unwrapped) end)
    if number ~= nil then return number end
    local text = tostring(unwrapped)
    if string.find(text, "Succeeded", 1, true) ~= nil then return 4 end
    return nil
end

local function quest_state(quest)
    if not pleasureLib:is_valid(quest) then return nil end

    local state = pleasureLib:try(function()
        if type(quest.GetState) == "function" then return quest:GetState() end
    end)
    if state == nil then
        state = pleasureLib:try(function() return quest.State end)
    end
    return enum_value(state)
end

local function quest_succeeded(quest)
    if not pleasureLib:is_valid(quest) then return false end

    local succeeded = pleasureLib:try(function()
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
        local content = pleasureLib:read_text_file(path)
        if content then
            config_cache = config_from_ini(pleasureLib:parse_ini(content))
            config_file_path = path
            loaded_config = true
            pleasureLib:log("Loaded config from " .. path
                .. ": Upgrade1=" .. upgrade_text(config_cache.Upgrade1)
                .. " Upgrade2=" .. upgrade_text(config_cache.Upgrade2))
            break
        end
    end
    if not loaded_config then
        pleasureLib:log("Config not found; using defaults.")
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
    if pleasureLib:write_text_file(path, config_file_content(config)) then
        pleasureLib:log("Saved config to " .. path
            .. ": Upgrade1=" .. tostring(upgrade_text(config.Upgrade1))
            .. " Upgrade2=" .. tostring(upgrade_text(config.Upgrade2)))
        return true
    end

    pleasureLib:log("Could not save config to " .. tostring(path))
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
    pleasureLib:log("SharedModMenu set " .. stage_name .. " portion " .. tostring(index)
        .. " to " .. tostring(FOOD_KEYS[code]))
    save_config()
end

local function native_setting_translations(stage_number, portion)
    return {
        en = {
            name = "Upgrade " .. tostring(stage_number)
                .. " - portion " .. tostring(portion),
            description = "Selects the food for this reward portion. Locked recipes use the next lower available food.",
        },
        de = {
            name = "Upgrade " .. tostring(stage_number)
                .. " - Portion " .. tostring(portion),
            description = "Waehlt das Essen fuer diese Belohnungsportion. Gesperrte Rezepte verwenden das naechstniedrigere verfuegbare Essen.",
        },
    }
end

local function set_native_food_code(stage_name, index, value)
    local code = math.floor(tonumber(value) or 0) + 1
    if code < 1 then code = 1 end
    if code > #FOOD_KEYS then code = #FOOD_KEYS end

    menu_upgrade(stage_name)[index] = FOOD_KEYS[code]
    pleasureLib:log("Native settings set " .. stage_name
        .. " portion " .. tostring(index)
        .. " to " .. tostring(FOOD_KEYS[code]))
    return save_config()
end

local function register_native_settings()
    if type(pleasureLib.register_game_enum_setting) ~= "function" then
        pleasureLib:log(
            "PleasureLib 0.5.0 enum settings API unavailable")
        return false
    end

    local stages = {
        { name = "Upgrade1", number = 1 },
        { name = "Upgrade2", number = 2 },
    }
    for _, stage in ipairs(stages) do
        for portion = 1, 3 do
            local stage_name = stage.name
            local stage_number = stage.number
            local portion_index = portion
            pleasureLib:register_game_enum_setting({
                id = "LetSnafCook." .. stage_name
                    .. ".Portion" .. tostring(portion_index),
                section = "Let Snaf Cook",
                values = FOOD_SETTING_VALUES,
                value_translations = FOOD_SETTING_VALUE_TRANSLATIONS,
                widget = "spinner",
                wrap_around = true,
                default = (FOOD_CODES[
                    DEFAULT_CONFIG[stage_name][portion_index]] or 1) - 1,
                get = function()
                    return menu_food_code(stage_name, portion_index) - 1
                end,
                set = function(value)
                    return set_native_food_code(
                        stage_name, portion_index, value)
                end,
                translations = native_setting_translations(
                    stage_number, portion_index),
            })
        end
    end
    return true
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
    local dir = pleasureLib:script_directory()
    if dir then
        package.path = dir .. "?.lua;" .. package.path
    end
    package.loaded["modmenu"] = nil

    local ok, modmenu = pcall(require, "modmenu")
    if not ok or type(modmenu) ~= "table" or type(modmenu.register) ~= "function" then
        pleasureLib:log("SharedModMenu bridge unavailable: " .. tostring(modmenu))
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
    pleasureLib:log("Registered SharedModMenu integration.")
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
            pleasureLib:log(stage_name .. " config is invalid; using "
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
            pleasureLib:log(stage_name .. " config is invalid; using "
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
            pleasureLib:log(stage_name .. " requested " .. tostring(count) .. "x "
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
    return string.find(pleasureLib:full_name(inventory), "G1RPlayerState", 1, true) ~= nil
end

local function add_reward_mix(inventory, total_count)
    local remaining = tonumber(total_count) or 0
    for _, reward in ipairs(pending_reward_mix or {}) do
        if remaining <= 0 then return true end

        local amount = reward.count
        if amount > remaining then amount = remaining end

        local item = pleasureLib:find_object(reward.path)
        if not pleasureLib:is_valid(item) then
            pleasureLib:log("Could not resolve " .. reward.path)
            return false
        end

        local added = pleasureLib:safe("add " .. reward.key, function()
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

    local inventory = pleasureLib:unwrap(inventory_param)
    if not pleasureLib:is_valid(inventory) or not is_player_inventory(inventory) then return false end

    local ragout = pleasureLib:find_object(MEATBUG_RAGOUT)
    if not pleasureLib:is_valid(ragout) then
        pleasureLib:log("Could not resolve original ragout class")
        return false
    end

    swapping_inventory = true
    local removed = pleasureLib:safe("remove original ragout", function()
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
        pleasureLib:delay_game_thread(150, function()
            swap_player_inventory_reward(inventory, next_attempt)
        end)
    end
    return false
end

load_config()
register_shared_mod_menu()
register_native_settings()

pleasureLib:register_hook("/Script/G1R.GameplayAbilityConversationV2WithUI:ServerRequestStartActingTopic",
    function(context, topic)
        if string.find(pleasureLib:full_name(pleasureLib:unwrap(topic)), SNAF_AFTERSUCCESS, 1, true) ~= nil then
            arm_reward_swap()
        end
    end)

pleasureLib:register_hook("/Script/G1R.InventoryComponent:OnItemAddedForHUD",
    function(_context, item, count)
        if should_suppress_original_reward_hud()
            and param_count(count) == 3
            and is_meatbug_ragout(item) then
            set_param(count, 0)
        end
    end)

pleasureLib:register_hook("/Script/G1R.InventoryComponent:MemorizeItem",
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
