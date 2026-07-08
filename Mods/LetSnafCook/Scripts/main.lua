local MOD = "LetSnafCook"

local MEATBUG_RAGOUT = "/Script/Angelscript.ItFo_Meatbugragout"
local SYRA_STEW = "/Script/Angelscript.ItFo_SyraRecipe"
local SYRA_STEW_DEFAULT = "/Script/Angelscript.Default__ItFo_SyraRecipe"
local SYRA_QUEST_MAIN = "/Script/Angelscript.Quest_OldCamp_OCCHAPTER2_SYRARECIPE"
local SYRA_QUEST_WAIT_SNAF = "/Script/Angelscript.Quest_OldCamp_OCCHAPTER2_SYRARECIPE_SYRARECIPE_OBJ_WAITSNAF"
local SNAF_AFTERSUCCESS = "ChoiceSnafAftersuccess"
local PENDING_SECONDS = 25

local pending_snaf_reward = false
local pending_syra_unlocked = false
local pending_since = 0
local swapping_inventory = false
local suppress_next_syra_hud = 0
local object_cache = {}

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
    local list = try(function()
        if type(FindAllOf) == "function" then return FindAllOf(class_name) end
        return nil
    end)
    if list == nil then return nil end

    local fallback = nil
    for _, obj in ipairs(list) do
        if not_default_object(obj) then
            if string.find(full_name(obj), ".Instance_", 1, true) ~= nil then
                return obj
            end
            fallback = fallback or obj
        end
    end

    if is_valid(fallback) then
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

local function is_syra_stew(item_param)
    return name_contains(unwrap(item_param), "ItFo_SyraRecipe")
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

local function pending_reward()
    if not pending_snaf_reward then return false end
    if os.clock() - pending_since > PENDING_SECONDS then
        pending_snaf_reward = false
        pending_syra_unlocked = false
        return false
    end
    return true
end

local function arm_reward_swap()
    pending_snaf_reward = true
    pending_syra_unlocked = syra_quest_done()
    pending_since = os.clock()
end

local function clear_reward_swap()
    pending_snaf_reward = false
    pending_syra_unlocked = false
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

local function replace_hud_item_with_syra(item_param)
    local syra_default = find_object(SYRA_STEW_DEFAULT)
    if not is_valid(syra_default) then
        log("Could not resolve " .. SYRA_STEW_DEFAULT)
        return false
    end
    return set_param(item_param, syra_default)
end

local function swap_player_inventory_reward(inventory_param, attempt)
    if swapping_inventory or not pending_reward() then return false end

    local inventory = unwrap(inventory_param)
    if not is_valid(inventory) or not is_player_inventory(inventory) then return false end

    local ragout = find_object(MEATBUG_RAGOUT)
    local syra = find_object(SYRA_STEW)
    if not is_valid(ragout) or not is_valid(syra) then
        log("Could not resolve item classes for inventory swap")
        return false
    end

    swapping_inventory = true
    local removed = safe("remove original ragout", function()
        return inventory:RemoveItemOfClass(ragout, 3)
    end)
    local removed_count = tonumber(removed) or 0

    if removed_count > 0 then
        suppress_next_syra_hud = suppress_next_syra_hud + 1
        local added = safe("add Syra stew", function()
            inventory:AddItemOfClass(syra, removed_count)
            return true
        end) == true
        if not added and suppress_next_syra_hud > 0 then
            suppress_next_syra_hud = suppress_next_syra_hud - 1
        end
        swapping_inventory = false

        if added then
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

register_hook("/Script/G1R.GameplayAbilityConversationV2WithUI:ServerRequestStartActingTopic",
    function(context, topic)
        if string.find(full_name(unwrap(topic)), SNAF_AFTERSUCCESS, 1, true) ~= nil then
            arm_reward_swap()
        end
    end)

register_hook("/Script/G1R.InventoryComponent:OnItemAddedForHUD",
    function(_context, item, count)
        if swapping_inventory
            and suppress_next_syra_hud > 0
            and param_count(count) == 3
            and is_syra_stew(item) then
            if set_param(count, 0) then
                suppress_next_syra_hud = suppress_next_syra_hud - 1
            end
            return
        end

        if pending_reward()
            and param_count(count) == 3
            and is_meatbug_ragout(item) then
            if pending_syra_unlocked then
                replace_hud_item_with_syra(item)
            end
        end
    end)

register_hook("/Script/G1R.InventoryComponent:MemorizeItem",
    function(context, item, count)
        if swapping_inventory then return end

        if pending_reward()
            and param_count(count) == 3
            and is_meatbug_ragout(item) then
            if pending_syra_unlocked then
                replace_hud_item_with_syra(item)
                swap_player_inventory_reward(context, 1)
            else
                clear_reward_swap()
            end
        end
    end)
