local Config = CMFishing.Config
CMFishing.Server = CMFishing.Server or {}

local PLAYERDATA = 'cm-playerdata'
local INVENTORY = 'cm-inventory'
local VEHICLES = 'cm-vehicles'

local sessions = {}    -- [src] = { fish, rod, bait, difficulty, biteAt }
local cooldowns = {}   -- [src] = GetGameTimer() expiry
local rentedBoats = {} -- [src] = { plate, netId, name }

local function dbg(...)
    if Config.Debug then print('[CM-FISHING]', ...) end
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-fishing:client:notify', src, tostring(message or ''), kind or 'info')
end

-- ---------------------------------------------------------------------------
-- cm-playerdata bridge
-- ---------------------------------------------------------------------------

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

local function getMeta(src, key, default)
    local api = playerData()
    if not api then return default end
    local ok, value = pcall(function() return api:GetMetadata(src, key) end)
    if ok and value ~= nil then return value end
    return default
end

local function setMeta(src, key, value)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:SetMetadata(src, key, value) end)
    return ok and result == true
end

local function addCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:AddCash(src, amount, reason) end)
    return ok and result == true
end

local function removeCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:RemoveCash(src, amount, reason) end)
    return ok and result == true
end

local function getCash(src)
    local api = playerData()
    if not api then return 0 end
    local ok, amount = pcall(function() return api:GetCash(src) end)
    if ok and type(amount) == 'number' then return math.floor(amount) end
    return 0
end

-- ---------------------------------------------------------------------------
-- cm-inventory bridge
-- ---------------------------------------------------------------------------

local function inventoryApi()
    if GetResourceState(INVENTORY) ~= 'started' then return nil end
    return exports[INVENTORY]
end

local function hasItem(src, itemName, amount)
    local api = inventoryApi()
    if not api then return false, 0 end
    local ok, has, count = pcall(function() return api:HasItem(src, itemName, amount or 1) end)
    if not ok then return false, 0 end
    return has == true, count or 0
end

local function canCarryItem(src, itemName, amount)
    local api = inventoryApi()
    if not api then return false end
    local ok, can = pcall(function() return api:CanCarryItem(src, itemName, amount or 1) end)
    return ok and can == true
end

local function addItem(src, itemName, amount, reason)
    local api = inventoryApi()
    if not api then return false end
    local ok, success = pcall(function() return api:AddItem(src, itemName, amount or 1, nil, reason) end)
    return ok and success == true
end

local function removeItem(src, itemName, amount, reason)
    local api = inventoryApi()
    if not api then return false end
    local ok, success = pcall(function() return api:RemoveItem(src, itemName, amount or 1, nil, reason) end)
    return ok and success == true
end

local function getFishCounts(src)
    local api = inventoryApi()
    if not api then return {} end
    local ok, inventory = pcall(function() return api:GetInventory(src) end)
    if not ok or type(inventory) ~= 'table' then return {} end

    local counts = {}
    for _, item in ipairs(inventory.items or {}) do
        if Config.Fish[item.item_name] then
            counts[item.item_name] = (counts[item.item_name] or 0) + (tonumber(item.quantity) or 0)
        end
    end
    return counts
end

-- ---------------------------------------------------------------------------
-- cm-vehicles bridge (boat rental)
-- ---------------------------------------------------------------------------

local function vehiclesApi()
    if GetResourceState(VEHICLES) ~= 'started' then return nil end
    return exports[VEHICLES]
end

local function deleteRentedBoat(src)
    local rec = rentedBoats[src]
    if not rec then return end
    rentedBoats[src] = nil
    local api = vehiclesApi()
    if api then pcall(function() api:DeleteAdminVehicle(rec.plate) end) end
end

-- ---------------------------------------------------------------------------
-- Player progress (level/xp stored as cm-playerdata metadata)
-- ---------------------------------------------------------------------------

local function getLevel(src)
    return math.max(0, math.floor(tonumber(getMeta(src, 'cmFishingLevel', 0)) or 0))
end

local function getXp(src)
    return math.max(0, math.floor(tonumber(getMeta(src, 'cmFishingXp', 0)) or 0))
end

local function getStatus(src)
    local level = getLevel(src)
    return {
        level = level,
        xp = getXp(src),
        xpForNext = Config.LevelXP[level + 1],
        maxLevel = level >= 5,
    }
end

local function awardXp(src, amount)
    local level = getLevel(src)
    local xp = getXp(src) + math.max(0, math.floor(tonumber(amount) or 0))
    local leveledUp = false

    while true do
        local needed = Config.LevelXP[level + 1]
        if needed and xp >= needed then
            xp = xp - needed
            level = level + 1
            leveledUp = true
        else
            break
        end
    end

    setMeta(src, 'cmFishingXp', xp)
    if leveledUp then setMeta(src, 'cmFishingLevel', level) end

    local status = getStatus(src)
    TriggerClientEvent('cm-fishing:client:status', src, status)
    return status, leveledUp
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function playerPed(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function playerCoords(src)
    local ped = playerPed(src)
    if not ped then return nil end
    return GetEntityCoords(ped)
end

local function findNearestArea(coords)
    for _, area in ipairs(Config.FishingAreas) do
        if #(coords - area.coords) <= area.radius then
            return area
        end
    end
    return nil
end

-- 'shallow' | 'medium' | 'deep', based on distance from the nearest zone's
-- anchor point (which sits at the dock/coastline) relative to that zone's
-- radius. Outside any configured zone -- open ocean, out on a boat -- is
-- always 'deep', since that is necessarily further out than every zone's
-- own radius.
local function computeDepth(coords, area)
    local anchor, radius

    if area then
        anchor, radius = area.coords, area.radius
    else
        local nearest, nearestDist
        for _, candidate in ipairs(Config.FishingAreas) do
            local dist = #(coords - candidate.coords)
            if not nearestDist or dist < nearestDist then
                nearest, nearestDist = candidate, dist
            end
        end
        anchor = nearest and nearest.coords or coords
    end

    local distance = #(coords - anchor)
    local shallowMax = radius and (radius * Config.Depth.shallowRadiusFactor) or Config.Depth.fallbackShallow
    local mediumMax = radius and (radius * Config.Depth.mediumRadiusFactor) or Config.Depth.fallbackMedium

    if distance <= shallowMax then return 'shallow' end
    if distance <= mediumMax then return 'medium' end
    return 'deep'
end

-- NOTE: there is no server-side equivalent of the client's water probe.
-- GetWaterHeight/TestProbeAgainstWater and friends require the streamed
-- collision/water-quad world the server never loads, so calling them here
-- throws "attempt to call a nil value". Water proximity is therefore only
-- gated client-side (client/main.lua's isFacingWater), which is fine: it is
-- a UX/immersion requirement, not something a modified client could abuse
-- for real gain -- cooldown, level gates, and rod/bait consumption below are
-- what actually protect the economy.

-- Picks the best rod/bait the player owns, checked in config-declared
-- priority (rods/bait tables are unordered, so a small priority list keeps
-- the "best gear auto-used" behaviour deterministic).
local ROD_PRIORITY = { 'rod_3', 'rod_2', 'basic_rod' }
local BAIT_PRIORITY = { 'artificial_bait', 'commonbait', 'worms' }

local function findOwnedGear(src, priority, configTable)
    for _, name in ipairs(priority) do
        if configTable[name] then
            local has = hasItem(src, name, 1)
            if has then return name, configTable[name] end
        end
    end
    return nil
end

-- Lets the client gate the cast prompt on actually owning a rod (inventory
-- contents are server-only, so it can't check this itself).
RegisterNetEvent('cm-fishing:server:checkRod', function()
    local src = source
    local rodName = findOwnedGear(src, ROD_PRIORITY, Config.Rods)
    TriggerClientEvent('cm-fishing:client:rodStatus', src, rodName ~= nil)
end)

-- rarityWeight (from the bait used, see shared/config.lua) multiplies a
-- fish's base weight when it matches that rarity, so better bait actually
-- biases toward better fish instead of just changing the wait time.
local function weightedFish(fishList, level, rarityWeight)
    rarityWeight = rarityWeight or {}
    local eligible, weightByFish, totalWeight = {}, {}, 0.0

    for _, fishName in ipairs(fishList) do
        local data = Config.Fish[fishName]
        if data and level >= (data.requiredLevel or 0) then
            local weight = data.chance * (rarityWeight[data.rarity] or 1.0)
            eligible[#eligible + 1] = fishName
            weightByFish[fishName] = weight
            totalWeight = totalWeight + weight
        end
    end

    if #eligible == 0 then return fishList[1] end
    if totalWeight <= 0 then return eligible[1] end

    local roll = math.random() * totalWeight
    local accumulated = 0.0
    for _, fishName in ipairs(eligible) do
        accumulated = accumulated + weightByFish[fishName]
        if roll <= accumulated then return fishName end
    end
    return eligible[#eligible]
end

local function onCooldown(src)
    local now = GetGameTimer()
    if (cooldowns[src] or 0) > now then return true end
    cooldowns[src] = now + (tonumber(Config.Security.castCooldownMs) or 1200)
    return false
end

local function clearSession(src)
    sessions[src] = nil
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-fishing:server:requestStatus', function()
    local src = source
    TriggerClientEvent('cm-fishing:client:status', src, getStatus(src))
end)

-- ---------------------------------------------------------------------------
-- Casting flow
-- ---------------------------------------------------------------------------

local function triggerBite(src, fishName)
    local session = sessions[src]
    if not session or session.fish ~= fishName then return end

    -- Deep water only: instead of a normal bite, a shark can hit the line
    -- instead. Ends the cast outright (no catch, no rod risk -- the fright
    -- is the cost) rather than feeding into the minigame.
    if session.depth == 'deep' and Config.SharkEncounter.enabled
        and math.random() < (Config.SharkEncounter.chancePerDeepBite or 0) then
        clearSession(src)
        TriggerClientEvent('cm-fishing:client:sharkEncounter', src, Config.SharkEncounter.damage, Config.SharkEncounter.models)
        return
    end

    local fishData = Config.Fish[fishName]
    local difficulty
    if session.heavy then
        -- Forced 'heavy' tier regardless of the fish's own skillcheck list --
        -- something well above the angler's gear/level tier fights harder.
        difficulty = 'heavy'
    else
        local difficulties = fishData.skillcheck or { 'easy' }
        difficulty = difficulties[math.random(1, #difficulties)]
    end
    local settings = Config.MinigameSettings[difficulty] or Config.MinigameSettings.easy

    session.difficulty = difficulty
    session.biteAt = GetGameTimer()

    TriggerClientEvent('cm-fishing:client:bite', src, { difficulty = difficulty, settings = settings, heavy = session.heavy })
end

RegisterNetEvent('cm-fishing:server:cast', function()
    local src = source
    if sessions[src] then return end
    if onCooldown(src) then
        notify(src, 'You need to wait before casting again.', 'error')
        return
    end

    local ped = playerPed(src)
    if not ped then return end
    local coords = GetEntityCoords(ped)

    local area = findNearestArea(coords)
    local level = getLevel(src)

    if area then
        if level < (area.minLevel or 0) then
            notify(src, ('You need fishing level %d to fish here.'):format(area.minLevel), 'error')
            return
        end
    elseif not Config.OutsideFishing.enabled then
        notify(src, 'There is no fish to catch here. Find a fishing spot.', 'error')
        return
    end

    local rodName, rodData = findOwnedGear(src, ROD_PRIORITY, Config.Rods)
    if not rodName then
        notify(src, 'You need a fishing rod to cast a line.', 'error')
        return
    end

    local baitName, baitData = findOwnedGear(src, BAIT_PRIORITY, Config.Bait)
    if not baitName then
        notify(src, 'You need bait to cast a line.', 'error')
        return
    end

    local fishList = area and area.fishList or Config.OutsideFishing.fishList
    local depth = computeDepth(coords, area)

    local rarityWeight = {}
    for rarity, mult in pairs(Config.Depth.rarityWeight[depth] or {}) do rarityWeight[rarity] = mult end
    for rarity, mult in pairs(baitData.rarityWeight or {}) do rarityWeight[rarity] = (rarityWeight[rarity] or 1.0) * mult end

    -- Heavy fish: a small chance for a low-level angler in medium/deep
    -- water to hook something above their normal tier entirely. Re-rolls
    -- the fish ignoring the level filter (weightedFish's level=math.huge
    -- makes every fish on this zone's list eligible); it only actually
    -- counts as "heavy" if what came out is above the player's real level,
    -- since the bypass could still land on something they already qualify
    -- for anyway.
    local heavy = false
    local selectedFish
    local heavyChance = level <= (Config.HeavyFish.maxAnglerLevel or 2) and (Config.HeavyFish.chanceByDepth[depth] or 0) or 0
    if math.random() < heavyChance then
        selectedFish = weightedFish(fishList, math.huge, rarityWeight)
        heavy = Config.Fish[selectedFish].requiredLevel > level
    else
        selectedFish = weightedFish(fishList, level, rarityWeight)
    end

    if not canCarryItem(src, selectedFish, 1) then
        notify(src, 'You are carrying too much to catch anything else.', 'error')
        return
    end

    -- Better bait has a chance to not be used up this cast (see
    -- shared/config.lua's saveChance), so a stack tends to last through
    -- more casts the higher-tier it is.
    local baitSaved = math.random() < (tonumber(baitData.saveChance) or 0)
    if not baitSaved and not removeItem(src, baitName, 1, 'fishing_bait_used') then
        notify(src, 'You need bait to cast a line.', 'error')
        return
    end

    sessions[src] = { fish = selectedFish, rod = rodName, bait = baitName, depth = depth, heavy = heavy }

    local waitTime = area and area.waitTime or Config.OutsideFishing.waitTime
    local speedFactor = math.max(0.15, (rodData.waitDivisor or 1.0) * (baitData.waitDivisor or 1.0))
    local waitMs = math.floor((math.random(waitTime.min, waitTime.max) * 1000) / speedFactor)

    TriggerClientEvent('cm-fishing:client:beginCast', src, waitMs)

    CreateThread(function()
        Wait(waitMs)
        triggerBite(src, selectedFish)
    end)
end)

RegisterNetEvent('cm-fishing:server:catchResult', function(success)
    local src = source
    local session = sessions[src]
    if not session or not session.difficulty then return end

    success = success == true

    if success then
        local fishData = Config.Fish[session.fish]

        if not canCarryItem(src, session.fish, 1) then
            notify(src, 'The fish got away — you have no room to carry it.', 'error')
            clearSession(src)
            return
        end

        if not addItem(src, session.fish, 1, 'fishing_catch') then
            notify(src, 'The fish got away — you have no room to carry it.', 'error')
            clearSession(src)
            return
        end

        local status, leveledUp = awardXp(src, fishData.xpReward)

        -- Rods never break on a normal catch -- the one exception is a
        -- "heavy fish" (see the cast handler's HeavyFish roll): something
        -- above the angler's own level tier that got hooked anyway. Landing
        -- it still counts, but risks snapping the rod on the way in.
        local rodBroke = false
        if session.heavy then
            local roll = math.random(0, 100)
            if roll <= (Config.HeavyFish.rodBreakChance or 0) then
                rodBroke = removeItem(src, session.rod, 1, 'fishing_rod_broke_heavy_catch')
            end
        end

        if session.heavy then
            notify(src, ('That was way bigger than expected! You caught a %s! (+%d XP)'):format(fishData.label, fishData.xpReward), 'success')
        else
            notify(src, ('You caught a %s! (+%d XP)'):format(fishData.label, fishData.xpReward), 'success')
        end
        if rodBroke then
            notify(src, 'The fight was too much for your rod -- it snapped.', 'error')
        end
        if leveledUp then
            notify(src, ('Fishing level up! You are now level %d.'):format(status.level), 'success')
        end

        TriggerClientEvent('cm-fishing:client:catchLanded', src, {
            success = true,
            fish = session.fish,
            label = fishData.label,
            rarity = fishData.rarity,
            xp = fishData.xpReward,
            heavy = session.heavy,
            rodBroke = rodBroke,
        })
    else
        -- Rods never break on a missed/escaped normal catch -- only bait is
        -- spent, and that already happened (or was saved) back in the cast
        -- handler. A snapped rod is only ever the heavy-fish success path
        -- above.
        notify(src, 'The fish got away.', 'error')
        TriggerClientEvent('cm-fishing:client:catchLanded', src, { success = false })
    end

    clearSession(src)
end)

-- Cancelling while still waiting for a bite (session exists, but
-- session.difficulty is nil since triggerBite hasn't fired yet) has to be a
-- separate path from catchResult: catchResult bails out early when
-- difficulty is unset, which used to leave the session stuck forever --
-- sessions[src] never cleared, so every future cast attempt silently
-- no-op'd on the "already fishing" guard. This always clears it.
RegisterNetEvent('cm-fishing:server:cancelCast', function()
    local src = source
    clearSession(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    sessions[src] = nil
    cooldowns[src] = nil
    deleteRentedBoat(src)
end)

-- ---------------------------------------------------------------------------
-- Store / exchange
-- ---------------------------------------------------------------------------

local function storeDistanceOk(src)
    local coords = playerCoords(src)
    if not coords then return false end
    local storeCoords = Config.Store.coords
    return #(coords - vector3(storeCoords.x, storeCoords.y, storeCoords.z)) <= (Config.Store.interactDistance + Config.Security.actionRangeSlack)
end

-- Static, config-derived "what unlocks at each level" summary, computed once
-- at startup rather than per request. Sent to the NUI so the store's level
-- panel always reflects shared/config.lua instead of a hand-maintained list
-- that can drift out of sync with it.
local LEVEL_INFO = (function()
    local byLevel = {}
    for level = 0, 5 do
        byLevel[level] = { level = level, xpForNext = Config.LevelXP[level + 1], rods = {}, zones = {}, fish = {} }
    end

    for _, rod in pairs(Config.Rods) do
        local entry = byLevel[rod.requiredLevel or 0]
        if entry then entry.rods[#entry.rods + 1] = rod.label end
    end

    for _, area in ipairs(Config.FishingAreas) do
        local entry = byLevel[area.minLevel or 0]
        if entry then entry.zones[#entry.zones + 1] = area.label end
    end

    for _, fish in pairs(Config.Fish) do
        local entry = byLevel[fish.requiredLevel or 0]
        if entry then entry.fish[#entry.fish + 1] = { label = fish.label, rarity = fish.rarity } end
    end

    local ordered = {}
    for level = 0, 5 do
        table.sort(byLevel[level].fish, function(a, b) return a.label < b.label end)
        ordered[#ordered + 1] = byLevel[level]
    end
    return ordered
end)()

-- Zone summary for the Info tab, computed once from config.
local ZONE_INFO = (function()
    local zones = {}
    for _, area in ipairs(Config.FishingAreas) do
        zones[#zones + 1] = {
            label = area.label,
            minLevel = area.minLevel or 0,
            fishCount = #area.fishList,
            shallowMax = math.floor(area.radius * Config.Depth.shallowRadiusFactor),
            mediumMax = math.floor(area.radius * Config.Depth.mediumRadiusFactor),
        }
    end
    if Config.OutsideFishing.enabled then
        zones[#zones + 1] = {
            label = 'Open water (anywhere else, near water)',
            minLevel = 0,
            fishCount = #Config.OutsideFishing.fishList,
            shallowMax = nil,
            mediumMax = nil,
        }
    end
    return zones
end)()

-- Live numeric values for the Info tab's mechanics explanations, read
-- straight from config so the text can never drift out of sync with actual
-- behaviour after a balance tweak.
local MECHANICS_INFO = {
    heavyMaxLevel = Config.HeavyFish.maxAnglerLevel,
    heavyChanceMedium = math.floor((Config.HeavyFish.chanceByDepth.medium or 0) * 100 + 0.5),
    heavyChanceDeep = math.floor((Config.HeavyFish.chanceByDepth.deep or 0) * 100 + 0.5),
    heavyRodBreakChance = Config.HeavyFish.rodBreakChance,
    sharkEnabled = Config.SharkEncounter.enabled,
    sharkChance = math.floor((Config.SharkEncounter.chancePerDeepBite or 0) * 100 + 0.5),
    sharkDamage = Config.SharkEncounter.damage,
    castCooldownSeconds = math.floor((Config.Security.castCooldownMs or 0) / 1000),
}

-- Short, human-readable perk tags for the store cards, derived once from
-- config so the UI never has to reverse-engineer what a waitDivisor or
-- saveChance number actually means.
local function rodPerks(data)
    local speedPct = math.floor(((data.waitDivisor or 1.0) - 1.0) * 100 + 0.5)
    return {
        'NEVER BREAKS',
        speedPct > 0 and ('+%d%% BITE SPEED'):format(speedPct) or 'NORMAL BITE SPEED',
    }
end

local function baitPerks(data)
    local savePct = math.floor((tonumber(data.saveChance) or 0) * 100 + 0.5)
    local hasBias = next(data.rarityWeight or {}) ~= nil
    return {
        savePct > 0 and ('%d%% CHANCE TO SAVE BAIT'):format(savePct) or 'ALWAYS CONSUMED',
        hasBias and 'BETTER FISH ODDS' or 'NO ODDS BONUS',
    }
end

local function buildStorePayload(src)
    local rods, bait, fish = {}, {}, {}

    for name, data in pairs(Config.Rods) do
        rods[#rods + 1] = {
            name = name, label = data.label, price = data.price, image = data.image,
            requiredLevel = data.requiredLevel, description = data.description, perks = rodPerks(data),
        }
    end
    for name, data in pairs(Config.Bait) do
        bait[#bait + 1] = {
            name = name, label = data.label, price = data.price, image = data.image,
            description = data.description, perks = baitPerks(data),
        }
    end

    local owned = getFishCounts(src)
    for name, data in pairs(Config.Fish) do
        local count = owned[name] or 0
        if count > 0 then
            fish[#fish + 1] = {
                name = name,
                label = data.label,
                rarity = data.rarity,
                price = Config.RaritySellPrice[data.rarity] or 15,
                xp = data.xpReward,
                count = count,
                image = name .. '.png',
                description = data.description,
            }
        end
    end

    table.sort(rods, function(a, b) return a.price < b.price end)
    table.sort(bait, function(a, b) return a.price < b.price end)
    table.sort(fish, function(a, b) return a.label < b.label end)

    local boats = {}
    if Config.BoatRental.enabled then
        for _, boat in ipairs(Config.BoatRental.list) do
            boats[#boats + 1] = { name = boat.name, label = boat.label, price = boat.price, image = boat.image }
        end
    end

    return {
        rods = rods,
        bait = bait,
        fish = fish,
        boats = boats,
        rentedBoat = rentedBoats[src] and rentedBoats[src].name or nil,
        cash = getCash(src),
        status = getStatus(src),
        levels = LEVEL_INFO,
        zones = ZONE_INFO,
        mechanics = MECHANICS_INFO,
    }
end

RegisterNetEvent('cm-fishing:server:requestStore', function()
    local src = source
    if not storeDistanceOk(src) then return end
    TriggerClientEvent('cm-fishing:client:openStore', src, buildStorePayload(src))
end)

-- wantBoat=false always succeeds (returning/cleaning up must work regardless
-- of distance -- the player may be out on the water when they ask for it
-- back). wantBoat=true requires being at the dock, no boat already rented,
-- and enough cash; charged up front so a spawn failure can't leave the
-- player billed with nothing to show for it (refunded via addCash below).
RegisterNetEvent('cm-fishing:server:requestBoat', function(wantBoat, boatName)
    local src = source
    wantBoat = wantBoat == true

    if not wantBoat then
        if not rentedBoats[src] then return end
        deleteRentedBoat(src)
        notify(src, 'Boat returned.', 'info')
        TriggerClientEvent('cm-fishing:client:openStore', src, buildStorePayload(src))
        return
    end

    if not Config.BoatRental.enabled then return end
    if not storeDistanceOk(src) then
        notify(src, 'You are too far from the dock to rent a boat.', 'error')
        return
    end
    if rentedBoats[src] then
        notify(src, 'You already have a boat rented. Return it first.', 'error')
        return
    end

    local boatDef
    for _, boat in ipairs(Config.BoatRental.list) do
        if boat.name == boatName then
            boatDef = boat
            break
        end
    end
    if not boatDef then return end

    if getCash(src) < boatDef.price then
        notify(src, 'You cannot afford that boat.', 'error')
        return
    end

    local api = vehiclesApi()
    if not api then
        notify(src, 'Boat rental is unavailable.', 'error')
        return
    end

    if not removeCash(src, boatDef.price, 'fishing_boat_rental') then
        notify(src, 'You cannot afford that boat.', 'error')
        return
    end

    local spawnPoints = Config.BoatRental.spawnCoords
    local spawn = spawnPoints[math.random(1, #spawnPoints)]

    local ok, result = pcall(function()
        return api:SpawnAdminVehicle(src, boatDef.name, { x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.w }, {
            placementKind = 'boat',
            label = boatDef.label,
            engineOn = true,
            warp = true,
        })
    end)

    if not ok or type(result) ~= 'table' or result.ok ~= true then
        notify(src, 'The boat could not be spawned.', 'error')
        addCash(src, boatDef.price, 'fishing_boat_rental_refund')
        return
    end

    rentedBoats[src] = { plate = result.plate, netId = result.netId, name = boatDef.name }
    notify(src, ('%s rented for $%d. Enjoy the water!'):format(boatDef.label, boatDef.price), 'success')
    -- Unlike buyItem/sellFish/returnBoat, a successful rental closes the
    -- store instead of refreshing it -- the boat is already waiting at the
    -- dock, so there is nothing left to do in the menu.
    TriggerClientEvent('cm-fishing:client:closeStoreForced', src)
end)

RegisterNetEvent('cm-fishing:server:buyItem', function(kind, name, qty)
    local src = source
    if not storeDistanceOk(src) then return end

    qty = math.max(1, math.min(20, math.floor(tonumber(qty) or 1)))

    local catalog = kind == 'rod' and Config.Rods or (kind == 'bait' and Config.Bait or nil)
    local data = catalog and catalog[name]
    if not data then return end

    if kind == 'rod' and (data.requiredLevel or 0) > getLevel(src) then
        notify(src, ('You need fishing level %d to buy this.'):format(data.requiredLevel), 'error')
        return
    end

    local totalPrice = data.price * qty
    if getCash(src) < totalPrice then
        notify(src, 'You cannot afford that.', 'error')
        return
    end

    if not canCarryItem(src, name, qty) then
        notify(src, 'You cannot carry that much.', 'error')
        return
    end

    if not removeCash(src, totalPrice, 'fishing_store_purchase') then
        notify(src, 'You cannot afford that.', 'error')
        return
    end

    if not addItem(src, name, qty, 'fishing_store_purchase') then
        addCash(src, totalPrice, 'fishing_store_purchase_refund')
        notify(src, 'Purchase failed.', 'error')
        return
    end

    notify(src, ('Bought %dx %s for $%d.'):format(qty, data.label, totalPrice), 'success')
    TriggerClientEvent('cm-fishing:client:openStore', src, buildStorePayload(src))
end)

-- Bait cart checkout: buys several bait types/quantities in a single
-- transaction instead of one buyItem round trip per type. `items` is a
-- {[baitName] = qty} table from the NUI cart. Validated and charged as one
-- lump sum up front (matching buyItem's charge-before-give ordering) so a
-- partial failure can't leave the player billed for items they never got.
RegisterNetEvent('cm-fishing:server:buyCart', function(items)
    local src = source
    if not storeDistanceOk(src) then return end
    if type(items) ~= 'table' then return end

    local purchases, totalPrice = {}, 0
    for name, qty in pairs(items) do
        qty = math.max(0, math.min(20, math.floor(tonumber(qty) or 0)))
        local data = Config.Bait[name]
        if qty > 0 and data then
            purchases[#purchases + 1] = { name = name, qty = qty, price = data.price, label = data.label }
            totalPrice = totalPrice + data.price * qty
        end
    end

    if #purchases == 0 then return end

    if getCash(src) < totalPrice then
        notify(src, 'You cannot afford your cart.', 'error')
        return
    end

    for _, purchase in ipairs(purchases) do
        if not canCarryItem(src, purchase.name, purchase.qty) then
            notify(src, ('You cannot carry that much %s.'):format(purchase.label), 'error')
            return
        end
    end

    if not removeCash(src, totalPrice, 'fishing_store_purchase') then
        notify(src, 'You cannot afford your cart.', 'error')
        return
    end

    local itemCount = 0
    for _, purchase in ipairs(purchases) do
        if addItem(src, purchase.name, purchase.qty, 'fishing_store_purchase') then
            itemCount = itemCount + purchase.qty
        else
            -- Best-effort partial refund: this one bait type failed to add
            -- (e.g. a slot/weight edge case CanCarryItem didn't catch), so
            -- give back just what it would have cost rather than the whole
            -- cart -- everything that already succeeded stays given.
            addCash(src, purchase.price * purchase.qty, 'fishing_store_purchase_refund')
        end
    end

    notify(src, ('Bought %dx bait for $%d.'):format(itemCount, totalPrice), 'success')
    TriggerClientEvent('cm-fishing:client:openStore', src, buildStorePayload(src))
end)

RegisterNetEvent('cm-fishing:server:sellFish', function(name, amount)
    local src = source
    if not storeDistanceOk(src) then return end

    local fishData = Config.Fish[name]
    if not fishData then return end

    local _, owned = hasItem(src, name, 1)
    if owned <= 0 then
        notify(src, 'You do not have any of that to sell.', 'error')
        return
    end

    local sellAmount = amount == 'all' and owned or math.max(1, math.min(owned, math.floor(tonumber(amount) or 1)))
    local unitPrice = Config.RaritySellPrice[fishData.rarity] or 15
    local total = unitPrice * sellAmount

    if not removeItem(src, name, sellAmount, 'fishing_sell') then
        notify(src, 'You do not have any of that to sell.', 'error')
        return
    end

    addCash(src, total, 'fishing_sell')
    notify(src, ('Sold %dx %s for $%d.'):format(sellAmount, fishData.label, total), 'success')
    TriggerClientEvent('cm-fishing:client:openStore', src, buildStorePayload(src))
end)

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------

local function isAdminAllowed(src, permission)
    if tonumber(src) == 0 then return true end
    if GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
    return ok and allowed == true
end

local function reply(src, message)
    if tonumber(src) == 0 then
        print('[CM-FISHING] ' .. tostring(message))
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '[CM-FISHING]', tostring(message) } })
    end
end

RegisterCommand('setfishinglevel', function(src, args)
    if not isAdminAllowed(src, 'fishing.admin.setlevel') then
        return reply(src, 'You do not have permission to do that.')
    end

    local level = math.floor(tonumber(args[1]) or -1)
    if level < 0 or level > 5 then
        return reply(src, 'Usage: /setfishinglevel <0-5> [playerId]')
    end

    local targetSrc = tonumber(args[2])
    if not targetSrc then
        if tonumber(src) == 0 then return reply(src, 'Usage from console: /setfishinglevel <0-5> <playerId>') end
        targetSrc = tonumber(src)
    end
    if not GetPlayerName(targetSrc) then return reply(src, 'That player is not online.') end

    setMeta(targetSrc, 'cmFishingLevel', level)
    setMeta(targetSrc, 'cmFishingXp', 0)
    TriggerClientEvent('cm-fishing:client:status', targetSrc, getStatus(targetSrc))
    notify(targetSrc, ('Your fishing level was set to %d.'):format(level), 'info')
    reply(src, ('Set fishing level %d for player %d.'):format(level, targetSrc))
end, false)
