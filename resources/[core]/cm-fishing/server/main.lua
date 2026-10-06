local Config = CMFishing.Config
CMFishing.Server = CMFishing.Server or {}

local PLAYERDATA = 'cm-playerdata'
local INVENTORY = 'cm-inventory'
local VEHICLES = 'cm-vehicles'

-- ---------------------------------------------------------------------------
-- Runtime state. EVERYTHING is keyed by the ACTIVE CHARACTER (tostring of the
-- cm-playerdata character id), never by FiveM source. Source is transport
-- only: SrcToChar lets disconnect/unload handlers find what to clean up.
-- ---------------------------------------------------------------------------

local STATE = {
    STARTING = 'STARTING',         -- server validating a cast request
    WAITING_BITE = 'WAITING_BITE',
    MINIGAME = 'MINIGAME',
    RESOLVING = 'RESOLVING',       -- result accepted, reward being issued
    COMPLETE = 'COMPLETE',
    CANCELLED = 'CANCELLED',
}

local Sessions = {}   -- [charKey] = cast session (one per character)
local Rentals = {}    -- [charKey] = { plate, netId, entity, name, src, charId }
local Cooldowns = {}  -- [charKey] = GetGameTimer() expiry
local OpLocks = {}    -- [charKey] = true while a store/boat transaction runs
local SrcToChar = {}  -- [src] = charKey (cleanup lookup only)
local RateHits = {}   -- [src][event] = GetGameTimer() expiry
local TokenSeq = 0
local DebugCharOverride = {} -- [src] = fake character id (Config.Debug test hook only)
local QaState = {}     -- [charKey] = one-shot deterministic setup for the next cast
local PublicWorld = {}       -- [src] = last published routing-bucket-0 state

local function dbg(...)
    if Config.Debug then print('[CM-FISHING]', ...) end
end

local function logWarn(...)
    print('^3[CM-FISHING]^7', ...)
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-fishing:client:notify', src, tostring(message or ''), kind or 'info')
end

-- High-risk / anomalous activity goes to cm-admin's audit log when present
-- (best effort, never blocks gameplay) and always to the server console.
local function auditLog(src, action, data)
    print(('^3[CM-FISHING]^7 %s src=%s %s'):format(action, tostring(src), json.encode(data or {})))
    if GetResourceState('cm-admin') == 'started' then
        pcall(function()
            data = data or {}
            data.category = data.category or 'system'
            exports['cm-admin']:AddLog(src, action, data)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- cm-playerdata bridge
-- ---------------------------------------------------------------------------

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

-- Active character for this source, or nil. Returns (characterId, charKey).
local function charIdOf(src)
    local api = playerData()
    if not api or not src or src <= 0 then return nil end
    if Config.Debug and DebugCharOverride[src] then return DebugCharOverride[src], tostring(DebugCharOverride[src]) end
    local ok, loaded = pcall(function() return api:IsCharacterLoaded(src) end)
    if not ok or loaded ~= true then return nil end
    local ok2, id = pcall(function() return api:GetCharacterId(src) end)
    if not ok2 or id == nil then return nil end
    return id, tostring(id)
end

local function getMeta(src, key, default)
    local api = playerData()
    if not api then return default end
    local ok, value = pcall(function() return api:GetMetadata(src, key) end)
    if ok and value ~= nil then return value end
    return default
end

-- SetMetadataDetailed's first return is the boolean; anything else is a
-- persistence failure the caller must handle.
local function setMeta(src, key, value)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:SetMetadataDetailed(src, key, value) end)
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

-- cm-playerdata is the authority on life state; the isDead state bag is its
-- replicated copy and is the fallback if the export is unavailable.
local function isAlive(src)
    local api = playerData()
    if api then
        local ok, dead = pcall(function() return api:IsDead(src) end)
        if ok then return dead ~= true end
    end
    local ply = Player(src)
    if not ply then return false end
    return ply.state.isDead ~= true
end

-- Normal Fishing gameplay is bucket-0 only. Never move the player -- just
-- refuse/cancel when something else already has.
local function isNormalBucket(src)
    local ok, bucket = pcall(function() return GetPlayerRoutingBucket(src) end)
    return ok and tonumber(bucket) == 0
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
    return has == true, tonumber(count) or 0
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

-- Character-targeted add (cm-inventory:AddItemToCharacter): lands on the given
-- character even if their source now belongs to someone else.
local function addItemToCharacter(characterId, itemName, amount, reason)
    local api = inventoryApi()
    if not api then return false end
    local ok, success = pcall(function() return api:AddItemToCharacter(characterId, itemName, amount or 1, nil, reason) end)
    return ok and success == true
end

-- Character-targeted credit (cm-playerdata:AddMoneyToCharacter).
local function addCashToCharacter(characterId, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, success = pcall(function() return api:AddMoneyToCharacter(characterId, 'cash', amount, reason) end)
    return ok and success == true
end

local rentalAlive

-- Development-only, server-side owner contract. The invoking-resource check is
-- deliberately inside the resource rather than in cm-qa so another resource
-- cannot use the deterministic controls by mistake.
local function qaAllowed()
    if not IsDuplicityVersion() then return false, 'server_only' end
    if GetConvar('cm_environment', 'production') ~= 'development' then return false, 'qa_disabled' end
    if GetConvarInt('cm_qa_enabled', 0) ~= 1 then return false, 'qa_disabled' end
    if GetInvokingResource() ~= 'cm-qa' then return false, 'forbidden' end
    return true
end

local function qaCharacter(data)
    if type(data) ~= 'table' then return false, 'invalid_data' end
    local src = tonumber(data.source)
    if not src or src <= 0 then return false, 'invalid_source' end
    if data.expectedCharacterId == nil then return false, 'expected_character_required' end
    local charId, key = charIdOf(src)
    if not charId then return false, 'character_not_loaded' end
    if tostring(data.expectedCharacterId) ~= tostring(charId) then return false, 'character_mismatch' end
    return true, src, charId, key
end

exports('QaSnapshot', function(src, expectedCharacterId)
    local allowed, reason = qaAllowed()
    if not allowed then return false, reason end

    local ok, sourceId, charId, key = qaCharacter({ source = src, expectedCharacterId = expectedCharacterId })
    if not ok then return false, sourceId end

    local session = Sessions[key]
    local rental = rentalAlive(key)
    local pending = QaState[key]
    return true, {
        characterId = charId,
        castActive = session ~= nil,
        castState = session and session.state or 'IDLE',
        tokenPresent = session ~= nil and session.token ~= nil,
        rod = session and session.rod or nil,
        bait = session and session.bait or nil,
        fish = session and session.fish or nil,
        depth = session and session.depth or nil,
        heavy = session and session.heavy == true or false,
        difficulty = session and session.difficulty or nil,
        cooldownActive = (Cooldowns[key] or 0) > GetGameTimer(),
        rentalActive = rental ~= nil,
        saleLockActive = OpLocks[key] == true,
        qaStatePending = pending ~= nil,
        qaForceNextFish = pending and pending.nextFish or nil,
        qaForceHeavy = pending and pending.forceHeavy or nil,
        qaForceShark = pending and pending.forceShark or nil,
        qaForceBaitSaved = pending and pending.forceBaitSaved or nil,
        qaForceRodBreak = pending and pending.forceRodBreak or nil,
    }
end)

exports('QaControl', function(action, data)
    local allowed, reason = qaAllowed()
    if not allowed then return false, reason end

    local ok, sourceId, charId, key = qaCharacter(data)
    if not ok then return false, sourceId end
    if type(action) ~= 'string' then return false, 'invalid_action' end

    if action == 'clear' then
        QaState[key] = nil
        return true, { characterId = charId, cleared = true }
    end

    local state = QaState[key] or {}
    if action == 'force_next_fish' then
        local fishName = type(data.fish) == 'string' and data.fish or data.name
        if type(fishName) ~= 'string' or not Config.Fish[fishName] then return false, 'invalid_fish' end
        state.nextFish = fishName
    elseif action == 'force_heavy' then
        if type(data.enabled) ~= 'boolean' then return false, 'invalid_enabled' end
        state.forceHeavy = data.enabled
    elseif action == 'force_shark' then
        if type(data.enabled) ~= 'boolean' then return false, 'invalid_enabled' end
        state.forceShark = data.enabled
    elseif action == 'force_bait_saved' then
        if type(data.enabled) ~= 'boolean' then return false, 'invalid_enabled' end
        state.forceBaitSaved = data.enabled
    elseif action == 'force_rod_break' then
        if type(data.enabled) ~= 'boolean' then return false, 'invalid_enabled' end
        state.forceRodBreak = data.enabled
    else
        return false, 'unknown_action'
    end

    QaState[key] = state
    -- This mapping makes a pending QA setup follow the same unload/disconnect
    -- cleanup path as a real cast, without exposing a public network event.
    SrcToChar[sourceId] = key
    return true, { characterId = charId, action = action, pending = true }
end)

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

-- Real quantity owned. HasItem's second return is trusted when present;
-- otherwise the full inventory is read so a truncated multi-return can never
-- turn into "owns 0" or, worse, "owns anything".
local function ownedCount(src, itemName)
    local has, count = hasItem(src, itemName, 1)
    if not has then return 0 end
    if count and count > 0 then return count end
    return getFishCounts(src)[itemName] or 1
end

-- ---------------------------------------------------------------------------
-- cm-vehicles bridge (temporary boat rental)
-- ---------------------------------------------------------------------------

local function vehiclesApi()
    if GetResourceState(VEHICLES) ~= 'started' then return nil end
    return exports[VEHICLES]
end

-- Deletes ONLY the plate this resource itself recorded for that character
-- and only if cm-vehicles still considers it a temporary (admin) vehicle --
-- never an owned/persistent vehicle, never a client-supplied id.
local function deleteRental(key)
    local rec = Rentals[key]
    if not rec then return end
    Rentals[key] = nil
    local api = vehiclesApi()
    if api then
        pcall(function()
            if api:IsAdminVehicle(rec.plate) then api:DeleteAdminVehicle(rec.plate) end
        end)
    end
end

-- A destroyed/streamed-out boat must not block renting forever.
function rentalAlive(key)
    local rec = Rentals[key]
    if not rec then return nil end
    if rec.entity and rec.entity ~= 0 and not DoesEntityExist(rec.entity) then
        Rentals[key] = nil
        local api = vehiclesApi()
        if api then pcall(function() api:DeleteAdminVehicle(rec.plate) end) end
        return nil
    end
    return rec
end

-- ---------------------------------------------------------------------------
-- Rate limiting / per-character operation lock
-- ---------------------------------------------------------------------------

local function rateLimited(src, event)
    local hits = RateHits[src]
    if not hits then hits = {}; RateHits[src] = hits end
    local now = GetGameTimer()
    if (hits[event] or 0) > now then return true end
    hits[event] = now + ((Config.Security.rateMs or {})[event] or 500)
    return false
end

-- Store/boat transactions yield on inventory/money calls, so two packets from
-- the same character could otherwise interleave. One at a time per character.
local function withLock(key, src, fn)
    if OpLocks[key] then
        notify(src, 'Please wait -- your previous request is still being processed.', 'error')
        return
    end
    OpLocks[key] = true
    local ok, err = xpcall(fn, debug.traceback)
    OpLocks[key] = nil
    if not ok then print('^1[CM-FISHING]^7 transaction error: ' .. tostring(err)) end
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

-- cm-playerdata has no atomic multi-key metadata write, so level and xp are
-- two writes. Order + rollback + read-back keep the partial window minimal;
-- a level-up is only ever reported after BOTH values read back correctly.
-- Returns status, leveledUp -- or nil, false, reason.
local function awardXp(src, amount)
    local previousLevel = getLevel(src)
    local previousXp = getXp(src)
    local level = previousLevel
    local xp = previousXp + math.max(0, math.floor(tonumber(amount) or 0))
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

    local function rollback()
        local levelBack = not leveledUp or setMeta(src, 'cmFishingLevel', previousLevel)
        local xpBack = setMeta(src, 'cmFishingXp', previousXp)
        if not levelBack or not xpBack then
            auditLog(src, 'fishing_progress_rollback_failed', {
                previousLevel = previousLevel, previousXp = previousXp, level = level, xp = xp,
            })
        end
    end

    if leveledUp and not setMeta(src, 'cmFishingLevel', level) then
        return nil, false, 'level_persist_failed'
    end
    if not setMeta(src, 'cmFishingXp', xp) then
        rollback()
        return nil, false, 'xp_persist_failed'
    end
    if getLevel(src) ~= level or getXp(src) ~= xp then
        rollback()
        return nil, false, 'progress_verify_failed'
    end

    local status = getStatus(src)
    TriggerClientEvent('cm-fishing:client:status', src, status)
    if leveledUp then
        local charId = charIdOf(src)
        TriggerEvent('cm-fishing:server:levelChanged', src, charId, level, previousLevel)
    end
    return status, leveledUp
end

-- Called by cm-payday when it pays out banked fishing xp. Returns a BOOLEAN
-- first (true = xp applied and verified), then status/leveledUp on success or
-- a reason string on failure. `expectedCharacterId` is optional; when given it
-- must match the source's active character so xp can never land on the wrong
-- character after a switch.
exports('AddXp', function(src, amount, expectedCharacterId)
    src = tonumber(src)
    if not src then return false, 'invalid_source' end
    local charId = charIdOf(src)
    if not charId then return false, 'character_not_loaded' end
    if expectedCharacterId ~= nil and tostring(expectedCharacterId) ~= tostring(charId) then
        return false, 'character_mismatch'
    end
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount <= 0 or amount > 100000 then
        return false, 'invalid_amount'
    end

    local status, leveledUp, reason = awardXp(src, amount)
    if not status then return false, reason end
    if leveledUp then
        notify(src, ('Fishing level up! You are now level %d.'):format(status.level), 'success')
    end
    return true, status, leveledUp
end)

-- XP from a catch. Returns mode, status, leveledUp where mode is:
--   'payday'    banked in cm-payday (applied, level-ups included, at payday)
--   'immediate' applied now (cm-payday not running, or it CONFIRMED a rejection)
--   nil         not recorded (persist failure or ambiguous payday error --
--               deliberately NOT retried so xp can never be double-applied)
local function bankXp(src, charId, amount)
    if GetResourceState('cm-payday') == 'started' then
        local ok, accepted = pcall(function()
            return exports['cm-payday']:AddPendingXp(src, 'fishing', amount)
        end)
        if ok and accepted == true then return 'payday' end
        if not ok then
            auditLog(src, 'fishing_xp_payday_error', { amount = amount, error = tostring(accepted) })
            return nil
        end
        -- payday confirmed it did NOT bank it (returns false + reason) -> the
        -- immediate fallback below cannot double-apply.
    end

    local currentChar = charIdOf(src)
    if currentChar == nil or tostring(currentChar) ~= tostring(charId) then return nil end
    local status, leveledUp = awardXp(src, amount)
    if status then return 'immediate', status, leveledUp end
    return nil
end

-- Sale proceeds. Returns 'payday' | 'cash' | nil (nil = NOTHING was paid, so
-- the caller must restore the fish). A thrown error inside cm-payday is
-- ambiguous, so it is treated as "not paid" and never followed by a cash
-- fallback (no double payout).
local function payJobCash(src, jobName, amount, reason)
    if GetResourceState('cm-payday') == 'started' then
        local ok, result = pcall(function() return exports['cm-payday']:AddPendingCash(src, jobName, amount, reason) end)
        if ok and result == true then return 'payday' end
        if not ok then
            auditLog(src, 'fishing_cash_payday_error', { amount = amount, error = tostring(result) })
            return nil
        end
    end
    if addCash(src, amount, reason) then return 'cash' end
    return nil
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
-- gated client-side (client/main.lua's isFacingWater): it is a UX/immersion
-- requirement, not the economy control. What actually protects the economy is
-- everything below: server gear validation, server session/token, server
-- zone/depth logic, server fish selection, server bait consumption, server
-- reward issuance, server cooldown and the movement/time plausibility checks.

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

local function onCooldown(key)
    local now = GetGameTimer()
    if (Cooldowns[key] or 0) > now then return true end
    Cooldowns[key] = now + (tonumber(Config.Security.castCooldownMs) or 1200)
    return false
end

local function newToken()
    TokenSeq = TokenSeq + 1
    return ('%x%04x%08x%08x'):format(TokenSeq, math.random(0, 0xFFFF), math.random(0, 0x7FFFFFFF), GetGameTimer() % 0x7FFFFFFF)
end

-- Lowest time (ms) a legitimate success can take: the bar must climb from its
-- start to the win value at gainRate/second even with perfect overlap every
-- frame. Derived from the minigame's own settings, scaled down by a safety
-- factor, so no legitimate player is ever rejected.
local function minResultMs(settings)
    local mg = Config.Minigame or { startProgress = 30, winProgress = 100 }
    local gain = math.max(1, tonumber(settings.gainRate) or 45)
    local physical = ((mg.winProgress - mg.startProgress) / gain) * 1000
    return math.floor(physical * (Config.Security.minResultFactor or 0.85))
end

-- ---------------------------------------------------------------------------
-- Cast session lifecycle
-- ---------------------------------------------------------------------------

-- Ends a session exactly once. The session table stays referenced by any
-- stale timer thread, whose `Sessions[key] == session and state == ...`
-- checks then fail harmlessly -- an old timer can never act on a new cast.
local function endSession(session, finalState, reason, tellClient)
    if not session or session.state == STATE.COMPLETE or session.state == STATE.CANCELLED then return end
    session.state = finalState
    session.endReason = reason
    if Sessions[session.key] == session then Sessions[session.key] = nil end
    if tellClient ~= false and session.src and GetPlayerName(session.src) then
        TriggerClientEvent('cm-fishing:client:castEnded', session.src, session.token, reason)
    end
end

local function cancelSession(session, reason)
    endSession(session, STATE.CANCELLED, reason, true)
end

-- Is this session's owner still validly fishing? Returns ok, reason.
local function validateContext(session)
    local src = session.src
    if not GetPlayerName(src) then return false, 'disconnected' end
    local charId = charIdOf(src)
    if charId == nil or tostring(charId) ~= session.key then return false, 'character_changed' end
    if not isNormalBucket(src) then return false, 'bucket' end
    if not isAlive(src) then return false, 'dead' end

    local ped = playerPed(src)
    if not ped then return false, 'no_ped' end
    local coords = GetEntityCoords(ped)

    local occupied = GetVehiclePedIsIn(ped, false)
    if session.vehicle then
        if not DoesEntityExist(session.vehicle) then return false, 'boat_gone' end
        if occupied ~= 0 and occupied ~= session.vehicle then return false, 'other_vehicle' end
        if #(coords - GetEntityCoords(session.vehicle)) > (Config.Security.maxBoatDistance or 10.0) then
            return false, 'left_boat'
        end
    else
        if occupied ~= 0 then return false, 'entered_vehicle' end
        if #(coords - session.origin) > (Config.Security.maxCastMovement or 8.0) then
            return false, 'moved_away'
        end
    end
    return true
end

local CANCEL_TEXT = {
    disconnected = nil,
    character_changed = nil,
    bucket = 'You cannot fish here right now.',
    dead = nil,
    moved_away = 'You moved too far away -- your line was reeled in.',
    left_boat = 'You moved too far from your boat -- your line was reeled in.',
    boat_gone = 'Your boat is gone -- your line was reeled in.',
    entered_vehicle = 'You got into a vehicle -- your line was reeled in.',
    other_vehicle = 'You got into a vehicle -- your line was reeled in.',
    timeout = 'The fish got away.',
    expired = 'The fish got away.',
}

local function cancelWithContext(session, reason)
    local text = CANCEL_TEXT[reason]
    if text and GetPlayerName(session.src) then notify(session.src, text, 'error') end
    cancelSession(session, reason)
end

local function triggerBite(session)
    if Sessions[session.key] ~= session or session.state ~= STATE.WAITING_BITE then return end

    local ok, reason = validateContext(session)
    if not ok then return cancelWithContext(session, reason) end

    local force = Config.Debug and Config.DebugForce or {}
    local qaForce = session.qa or {}

    -- Deep water only: instead of a normal bite, a shark can hit the line.
    -- Ends the cast outright (no catch, no rod risk, no xp) -- the server
    -- decided this; the client only plays the visual.
    if Config.SharkEncounter.enabled and (qaForce.forceShark == true
        or (qaForce.forceShark == nil and ((session.depth == 'deep'
            and math.random() < (Config.SharkEncounter.chancePerDeepBite or 0)) or force.shark == true))) then
        local token = session.token
        endSession(session, STATE.CANCELLED, 'shark', false)
        TriggerClientEvent('cm-fishing:client:sharkEncounter', session.src, token, Config.SharkEncounter.damage, Config.SharkEncounter.models)
        return
    end

    local fishData = Config.Fish[session.fish]
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

    local now = GetGameTimer()
    session.state = STATE.MINIGAME
    session.difficulty = difficulty
    session.settings = settings
    session.biteAt = now
    session.minResultMs = minResultMs(settings)
    session.expiresAt = now + (tonumber(settings.timeLimitMs) or 12000) + (Config.Security.resultGraceMs or 3000)

    TriggerClientEvent('cm-fishing:client:bite', session.src, {
        token = session.token, difficulty = difficulty, settings = settings, heavy = session.heavy,
    })

    -- Server-side deadline: a minigame that never reports back still ends.
    CreateThread(function()
        Wait(session.expiresAt - GetGameTimer() + 500)
        if Sessions[session.key] == session and session.state == STATE.MINIGAME then
            cancelWithContext(session, 'timeout')
        end
    end)
end

-- Lets the client gate the cast prompt on actually owning a rod (inventory
-- contents are server-only, so it can't check this itself).
RegisterNetEvent('cm-fishing:server:checkRod', function()
    local src = source
    if rateLimited(src, 'checkRod') then return end
    if not charIdOf(src) then return end
    local rodName = findOwnedGear(src, ROD_PRIORITY, Config.Rods)
    TriggerClientEvent('cm-fishing:client:rodStatus', src, rodName ~= nil)
end)

-- Authoritative "public world" (routing bucket 0) state for the client, sent
-- only when it changes (plus on request/resource start). The client uses it to
-- show/hide the store NPC, blips and prompts. Never moves the player.
local function publishWorld(src, force)
    local public = isNormalBucket(src)
    if force or PublicWorld[src] ~= public then
        PublicWorld[src] = public
        TriggerClientEvent('cm-fishing:client:publicWorld', src, public)
    end
end

CreateThread(function()
    while true do
        for _, playerId in ipairs(GetPlayers()) do
            publishWorld(tonumber(playerId), false)
        end
        Wait(1000)
    end
end)

RegisterNetEvent('cm-fishing:server:requestWorldState', function()
    local src = source
    if rateLimited(src, 'requestStatus') then return end
    publishWorld(src, true)
end)

RegisterNetEvent('cm-fishing:server:requestStatus', function()
    local src = source
    if rateLimited(src, 'requestStatus') then return end
    if not charIdOf(src) then return end
    TriggerClientEvent('cm-fishing:client:status', src, getStatus(src))
end)

-- ---------------------------------------------------------------------------
-- Casting
-- ---------------------------------------------------------------------------

-- boatNetId is a client HINT only (which boat deck the player claims to
-- stand on). The server validates it is a real boat within reach before using
-- it for the movement policy; if it is invalid it is simply ignored.
RegisterNetEvent('cm-fishing:server:cast', function(boatNetId)
    local src = source
    if rateLimited(src, 'cast') then return end

    local charId, key = charIdOf(src)
    if not charId then return end
    if not isNormalBucket(src) then return end
    if not isAlive(src) then return end
    if Sessions[key] or OpLocks[key] then return end -- duplicate/spam: silently ignored
    if onCooldown(key) then
        notify(src, 'You need to wait before casting again.', 'error')
        return
    end

    local ped = playerPed(src)
    if not ped then return end
    if GetVehiclePedIsIn(ped, false) ~= 0 then
        notify(src, 'Get out of the vehicle to fish.', 'error')
        return
    end
    local coords = GetEntityCoords(ped)

    -- Reserve the character's single cast slot BEFORE anything yields
    -- (inventory calls do), so two racing packets cannot both start a cast.
    local session = {
        key = key, characterId = charId, src = src, token = newToken(),
        state = STATE.STARTING, origin = coords, castStartedAt = GetGameTimer(), qa = QaState[key],
    }
    Sessions[key] = session
    SrcToChar[src] = key
    -- QA controls are one-shot setup for this cast. Once copied into the
    -- authoritative session they cannot affect a later normal cast.
    QaState[key] = nil

    local function alive() return Sessions[key] == session and session.state == STATE.STARTING end
    local function abort(message)
        if message then notify(src, message, 'error') end
        if Sessions[key] == session then Sessions[key] = nil end
        session.state = STATE.CANCELLED
    end

    -- Boat hint validation.
    boatNetId = tonumber(boatNetId)
    if boatNetId and boatNetId > 0 then
        local ok, entity = pcall(NetworkGetEntityFromNetworkId, boatNetId)
        if ok and entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2 then
            local isBoat = false
            local okType, vType = pcall(GetVehicleType, entity)
            if okType and vType == 'boat' then isBoat = true end
            if isBoat and #(coords - GetEntityCoords(entity)) <= (Config.Security.maxBoatDistance or 10.0) then
                session.vehicle = entity
                session.vehicleNetId = boatNetId
            end
        end
    end

    local area = findNearestArea(coords)
    local level = getLevel(src)

    if area then
        if level < (area.minLevel or 0) then
            return abort(('You need fishing level %d to fish here.'):format(area.minLevel))
        end
    elseif not Config.OutsideFishing.enabled then
        return abort('There is no fish to catch here. Find a fishing spot.')
    end

    local rodName, rodData = findOwnedGear(src, ROD_PRIORITY, Config.Rods)
    if not alive() then return end
    if not rodName then return abort('You need a fishing rod to cast a line.') end

    local baitName, baitData = findOwnedGear(src, BAIT_PRIORITY, Config.Bait)
    if not alive() then return end
    if not baitName then return abort('You need bait to cast a line.') end

    local fishList = area and area.fishList or Config.OutsideFishing.fishList
    local depth = computeDepth(coords, area)

    local rarityWeight = {}
    for rarity, mult in pairs(Config.Depth.rarityWeight[depth] or {}) do rarityWeight[rarity] = mult end
    for rarity, mult in pairs(baitData.rarityWeight or {}) do rarityWeight[rarity] = (rarityWeight[rarity] or 1.0) * mult end

    -- Heavy fish: a small chance for a low-level angler in medium/deep water
    -- to hook something above their normal tier. It only counts as "heavy" if
    -- the fish that came out is above the player's real level.
    local force = Config.Debug and Config.DebugForce or {}
    local qaForce = session.qa or {}
    local heavy = false
    local selectedFish = qaForce.nextFish
    local heavyChance = level <= (Config.HeavyFish.maxAnglerLevel or 2) and (Config.HeavyFish.chanceByDepth[depth] or 0) or 0
    if not selectedFish then
        if qaForce.forceHeavy == true or (qaForce.forceHeavy == nil and (force.heavy == true or math.random() < heavyChance)) then
            selectedFish = weightedFish(fishList, math.huge, rarityWeight)
            heavy = Config.Fish[selectedFish].requiredLevel > level
            if (qaForce.forceHeavy == true or force.heavy == true) and not heavy then
                for _, fishName in ipairs(fishList) do
                    local data = Config.Fish[fishName]
                    if data and data.requiredLevel > level then selectedFish, heavy = fishName, true break end
                end
            end
        else
            selectedFish = weightedFish(fishList, level, rarityWeight)
        end
    end
    if qaForce.forceHeavy == true then
        heavy = true
    elseif qaForce.forceHeavy == false then
        heavy = false
    end

    if not canCarryItem(src, selectedFish, 1) then
        return abort('You are carrying too much to catch anything else.')
    end
    if not alive() then return end

    -- Better bait has a chance to not be used up this cast (saveChance), so a
    -- stack tends to last through more casts the higher-tier it is. Rolled and
    -- consumed here, once, on the server -- the result path never touches bait.
    local baitSaved
    if qaForce.forceBaitSaved ~= nil then
        baitSaved = qaForce.forceBaitSaved == true
    else
        baitSaved = math.random() < (tonumber(baitData.saveChance) or 0)
    end
    if not baitSaved and not removeItem(src, baitName, 1, 'fishing_bait_used') then
        return abort('You need bait to cast a line.')
    end
    if not alive() then return end

    local waitTime = area and area.waitTime or Config.OutsideFishing.waitTime
    local speedFactor = math.max(0.15, (rodData.waitDivisor or 1.0) * (baitData.waitDivisor or 1.0))
    local waitMs = math.floor((math.random(waitTime.min, waitTime.max) * 1000) / speedFactor)

    session.rod, session.bait, session.fish = rodName, baitName, selectedFish
    session.depth, session.heavy, session.area = depth, heavy, area and area.key or nil
    session.baitSaved = baitSaved
    session.waitMs = waitMs
    session.state = STATE.WAITING_BITE

    TriggerClientEvent('cm-fishing:client:beginCast', src, session.token, waitMs)
    TriggerEvent('cm-fishing:server:castStarted', src, charId, {
        depth = depth, area = session.area, rod = rodName, bait = baitName, baitSaved = baitSaved,
    })

    -- Delayed bite. The thread re-verifies session identity AND state, so a
    -- timer left over from an earlier cast/cancel/restart does nothing.
    CreateThread(function()
        Wait(waitMs)
        triggerBite(session)
    end)
end)

RegisterNetEvent('cm-fishing:server:catchResult', function(token, success)
    local src = source
    if rateLimited(src, 'catchResult') then return end
    if type(token) ~= 'string' then return end

    local charId, key = charIdOf(src)
    if not charId then return end

    local session = Sessions[key]
    -- Unknown/replayed/foreign token: ignored without touching a live cast.
    if not session or session.token ~= token or session.src ~= src then return end
    if session.state ~= STATE.MINIGAME then return end

    -- Consume the token immediately (no yield has happened yet, so this is
    -- atomic): a second packet with the same token now fails the state check.
    session.state = STATE.RESOLVING

    local ok, reason = validateContext(session)
    if not ok then return cancelWithContext(session, reason) end

    local elapsed = GetGameTimer() - session.biteAt
    if GetGameTimer() > session.expiresAt then
        return cancelWithContext(session, 'expired')
    end

    if success ~= true then
        -- No fish, no xp, no cash; bait was settled at cast time.
        notify(src, 'The fish got away.', 'error')
        TriggerClientEvent('cm-fishing:client:catchLanded', src, { success = false })
        return endSession(session, STATE.COMPLETE, 'failed', false)
    end

    if elapsed < session.minResultMs then
        auditLog(src, 'fishing_result_too_fast', {
            characterId = charId, elapsedMs = elapsed, minMs = session.minResultMs, difficulty = session.difficulty,
        })
        return cancelSession(session, 'implausible')
    end

    local fishName = session.fish
    local fishData = Config.Fish[fishName]

    local function gotAway(message)
        notify(src, message, 'error')
        TriggerClientEvent('cm-fishing:client:catchLanded', src, { success = false })
        endSession(session, STATE.COMPLETE, 'no_room', false)
    end

    if not canCarryItem(src, fishName, 1) then
        return gotAway('The fish got away — you have no room to carry it.')
    end
    if not addItem(src, fishName, 1, 'fishing_catch') then
        return gotAway('The fish got away — you have no room to carry it.')
    end

    -- The fish exists in the inventory from here on: exactly one reward.
    local xpMode, status, leveledUp = bankXp(src, session.key, fishData.xpReward)

    -- Rods never break on a normal catch. The one exception is a heavy fish;
    -- the roll is server-side and removes exactly the rod chosen at cast
    -- start. If the removal fails the rod did NOT break -- and we say so.
    local rodBroke = false
    local qaRodBreak = session.qa and session.qa.forceRodBreak
    if session.heavy and (qaRodBreak == true or (qaRodBreak == nil and (math.random() * 100) < (Config.HeavyFish.rodBreakChance or 0))) then
        rodBroke = removeItem(src, session.rod, 1, 'fishing_rod_broke_heavy_catch')
        if not rodBroke then
            auditLog(src, 'fishing_rod_break_remove_failed', { characterId = charId, rod = session.rod })
        end
    end

    local xpText
    if xpMode == 'payday' then
        xpText = ('%d XP added to City Payday'):format(fishData.xpReward)
    elseif xpMode == 'immediate' then
        xpText = ('+%d XP'):format(fishData.xpReward)
    else
        xpText = 'XP could not be recorded'
    end

    local prefix = session.heavy and 'That was way bigger than expected! ' or ''
    notify(src, ('%sCaught %s — %s.'):format(prefix, fishData.label, xpText), 'success')
    if rodBroke then
        notify(src, 'The fight was too much for your rod -- it snapped.', 'error')
    end
    if leveledUp and status then
        notify(src, ('Fishing level up! You are now level %d.'):format(status.level), 'success')
    end

    TriggerClientEvent('cm-fishing:client:catchLanded', src, {
        success = true,
        fish = fishName,
        label = fishData.label,
        rarity = fishData.rarity,
        xp = fishData.xpReward,
        xpMode = xpMode or 'none',
        xpText = xpText,
        heavy = session.heavy,
        rodBroke = rodBroke,
    })

    endSession(session, STATE.COMPLETE, 'caught', false)
    TriggerEvent('cm-fishing:server:fishCaught', src, charId, {
        fish = fishName, rarity = fishData.rarity, xp = fishData.xpReward, xpMode = xpMode or 'none',
        heavy = session.heavy, rodBroke = rodBroke, depth = session.depth,
    })
end)

-- Reeling in / ESC / death from the client. Only cancels the caller's OWN
-- session and only if the token matches it (a late cancel from an earlier cast
-- can never kill a newer one).
RegisterNetEvent('cm-fishing:server:cancelCast', function(token)
    local src = source
    if rateLimited(src, 'cancelCast') then return end
    local charId, key = charIdOf(src)
    if not charId then return end
    local session = Sessions[key]
    if not session or session.src ~= src then return end
    if type(token) ~= 'string' or session.token ~= token then return end
    if session.state == STATE.RESOLVING then return end
    cancelSession(session, 'manual')
end)

-- ---------------------------------------------------------------------------
-- Cleanup (character switch / disconnect / death / bucket / resource stop)
-- ---------------------------------------------------------------------------

local function cleanupSource(src, reason)
    local key = SrcToChar[src]
    if not key then return end
    SrcToChar[src] = nil
    QaState[key] = nil
    local session = Sessions[key]
    if session then cancelSession(session, reason) end
    deleteRental(key)
    Cooldowns[key] = nil
    OpLocks[key] = nil
end

-- Fires on both a mid-session character switch and a normal logout, so this
-- is the single point that keeps A's cast/boat/cooldown away from B.
AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    cleanupSource(tonumber(src), 'character_changed')
end)

-- Safety net if an unload event was ever missed: a newly loaded character
-- must never inherit whatever the source held before.
AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    src = tonumber(src)
    local _, key = charIdOf(src)
    if SrcToChar[src] and SrcToChar[src] ~= key then
        cleanupSource(src, 'character_changed')
    end
end)

AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, isDead)
    src = tonumber(src)
    if isDead ~= true then return end
    local key = SrcToChar[src]
    local session = key and Sessions[key]
    if session then cancelSession(session, 'dead') end
end)

AddEventHandler('playerDropped', function()
    local src = source
    cleanupSource(src, 'disconnected')
    RateHits[src] = nil
    PublicWorld[src] = nil
    DebugCharOverride[src] = nil
end)

-- Test hook only (Config.Debug): make `src` look like a different character and
-- run the same cleanup a real unload performs.
local function simulateSwitch(src)
    DebugCharOverride[src] = 'debug-other-character'
    cleanupSource(src, 'character_changed')
end

-- Sweep: dead/moved/left-bucket/timed-out casts are cancelled even if the
-- client never says a word. Nothing here moves a player between buckets.
CreateThread(function()
    while true do
        Wait(Config.Security.monitorIntervalMs or 1500)
        local now = GetGameTimer()
        for _, session in pairs(Sessions) do
            if session.state == STATE.WAITING_BITE or session.state == STATE.MINIGAME then
                local ok, reason = validateContext(session)
                if not ok then
                    cancelWithContext(session, reason)
                elseif session.state == STATE.WAITING_BITE and now > (session.castStartedAt + session.waitMs + 15000) then
                    cancelSession(session, 'stale')
                end
            elseif session.state == STATE.STARTING and now > (session.castStartedAt + 15000) then
                -- A start that never finished (error/yield never returned).
                cancelSession(session, 'stale')
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, session in pairs(Sessions) do
        cancelSession(session, 'resource_stop')
    end
    for key in pairs(Rentals) do
        deleteRental(key)
    end
    for key in pairs(QaState) do
        QaState[key] = nil
    end
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

-- Common gate for every store-side action: active character, bucket 0, alive,
-- at the Fishing Store. Returns characterId, charKey or nil.
local function storeGate(src)
    local charId, key = charIdOf(src)
    if not charId then return nil end
    if not isNormalBucket(src) then return nil end
    if not isAlive(src) then return nil end
    if not storeDistanceOk(src) then return nil end
    -- Store transactions yield on inventory/money calls. Keep the source
    -- mapped to the character whose request opened that transaction so the
    -- normal character-unload cleanup can cancel stale state as well.
    SrcToChar[src] = key
    return charId, key
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

local function buildStorePayload(src, key)
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

    local rental = rentalAlive(key)

    return {
        rods = rods,
        bait = bait,
        fish = fish,
        boats = boats,
        rentedBoat = rental and rental.name or nil,
        cash = getCash(src),
        status = getStatus(src),
        levels = LEVEL_INFO,
        zones = ZONE_INFO,
        mechanics = MECHANICS_INFO,
    }
end

local function refreshStore(src, key)
    TriggerClientEvent('cm-fishing:client:openStore', src, buildStorePayload(src, key))
end

RegisterNetEvent('cm-fishing:server:requestStore', function()
    local src = source
    if rateLimited(src, 'requestStore') then return end
    local charId, key = storeGate(src)
    if not charId then return end
    if Sessions[key] then
        notify(src, 'Reel in your line before visiting the store.', 'error')
        return
    end
    refreshStore(src, key)
end)

-- Boat rental. Returning (wantBoat=false) works from anywhere -- the player
-- may be out on the water -- but only ever deletes THIS character's recorded
-- rental. Renting requires the dock, bucket 0, no existing rental, a free
-- spawn point (checked BEFORE charging) and enough cash; charged up front and
-- refunded exactly once if the spawn still fails.

local function spawnPointFree(point, vehicles)
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - vector3(point.x, point.y, point.z)) < 4.0 then
            return false
        end
    end
    return true
end

local function chooseSpawnPoint()
    local points = {}
    for _, point in ipairs(Config.BoatRental.spawnCoords) do points[#points + 1] = point end
    for i = #points, 2, -1 do
        local j = math.random(1, i)
        points[i], points[j] = points[j], points[i]
    end

    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or type(vehicles) ~= 'table' then
        -- Occupancy unknown: let the real spawn attempt be the judge (refund
        -- covers a failure).
        return points[1], false
    end
    for _, point in ipairs(points) do
        if spawnPointFree(point, vehicles) then return point, true end
    end
    return nil, true
end

RegisterNetEvent('cm-fishing:server:requestBoat', function(wantBoat, boatName)
    local src = source
    if rateLimited(src, 'requestBoat') then return end
    local charId, key = charIdOf(src)
    if not charId then return end
    SrcToChar[src] = key
    wantBoat = wantBoat == true

    if not wantBoat then
        if not rentalAlive(key) then
            notify(src, 'You do not have a boat rented.', 'info')
            return
        end
        deleteRental(key)
        notify(src, 'Boat returned.', 'info')
        if storeDistanceOk(src) and isNormalBucket(src) then refreshStore(src, key) end
        return
    end

    if not Config.BoatRental.enabled then return end
    if not isNormalBucket(src) or not isAlive(src) then return end
    if not storeDistanceOk(src) then
        notify(src, 'You are too far from the dock to rent a boat.', 'error')
        return
    end
    if type(boatName) ~= 'string' then return end
    if Sessions[key] then
        notify(src, 'Reel in your line before renting a boat.', 'error')
        return
    end

    withLock(key, src, function()
        if rentalAlive(key) then
            notify(src, 'You already have a boat rented. Return it first.', 'error')
            return
        end

        local boatDef
        for _, boat in ipairs(Config.BoatRental.list) do
            if boat.name == boatName then boatDef = boat break end
        end
        if not boatDef then return end

        local api = vehiclesApi()
        if not api then
            notify(src, 'Boat rental is unavailable.', 'error')
            return
        end

        if getCash(src) < boatDef.price then
            notify(src, 'You cannot afford that boat.', 'error')
            return
        end

        -- Pick a clear spawn BEFORE taking any money.
        local spawn = chooseSpawnPoint()
        if not spawn then
            notify(src, 'The boat launch area is blocked. Try again in a moment.', 'error')
            return
        end

        -- The transaction is bound to the ORIGINAL character (charId), price
        -- and boat definition captured here. Owner is resolved synchronously
        -- inside RemoveCash, so verify the character right before it.
        local preChar = charIdOf(src)
        if preChar == nil or tostring(preChar) ~= key then return end
        if not removeCash(src, boatDef.price, 'fishing_boat_rental') then
            notify(src, 'You cannot afford that boat.', 'error')
            return
        end

        local refunded = false
        local function refund()
            if refunded then return end
            refunded = true
            -- Character-targeted: reaches the original payer even if the
            -- source now belongs to someone else, and never credits anyone else.
            if not addCashToCharacter(charId, boatDef.price, 'fishing_boat_rental_refund') then
                auditLog(src, 'fishing_boat_refund_failed', { characterId = charId, price = boatDef.price })
            end
        end

        local ok, result = pcall(function()
            return api:SpawnAdminVehicle(src, boatDef.name, { x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.w }, {
                placementKind = 'boat',
                label = boatDef.label,
                engineOn = true,
                warp = true,
            })
        end)

        if not ok or type(result) ~= 'table' or result.ok ~= true then
            notify(src, 'The boat could not be spawned. You have not been charged.', 'error')
            refund()
            return
        end

        if Config.Debug and Config.DebugHooks.rent then simulateSwitch(src) end

        -- The character may have switched/left while the spawn yielded: the
        -- boat belongs to nobody then. Delete it, refund the ORIGINAL payer
        -- exactly once, and leave no rental record behind.
        local currentChar = charIdOf(src)
        if currentChar == nil or tostring(currentChar) ~= key then
            pcall(function() if api:IsAdminVehicle(result.plate) then api:DeleteAdminVehicle(result.plate) end end)
            Rentals[key] = nil
            refund()
            auditLog(src, 'fishing_boat_character_changed_refunded', { characterId = charId, plate = result.plate, price = boatDef.price })
            return
        end

        Rentals[key] = { plate = result.plate, netId = result.netId, entity = result.entity, name = boatDef.name, src = src, charId = charId }
        SrcToChar[src] = key
        notify(src, ('%s rented for $%d. Enjoy the water!'):format(boatDef.label, boatDef.price), 'success')
        -- A successful rental closes the store: the boat is already waiting.
        TriggerClientEvent('cm-fishing:client:closeStoreForced', src)
    end)
end)

-- One purchase pipeline for rods and bait (single or cart). `lines` is a list
-- of { name, qty, kind }. Returns nothing; notifies the exact outcome.
--   preflight: level, duplicate rods, cash, capacity  (nothing taken yet)
--   execute:   remove cash once, add every line; on ANY failure every line
--              already added is removed again and the cash refunded.
--   report:    delivered lines and the NET amount actually charged.
local function processPurchase(src, key, lines)
    local total = 0
    local level = getLevel(src)

    for _, line in ipairs(lines) do
        local catalog = line.kind == 'rod' and Config.Rods or Config.Bait
        local data = catalog[line.name]
        line.data = data
        line.cost = data.price * line.qty
        total = total + line.cost

        if line.kind == 'rod' then
            if (data.requiredLevel or 0) > level then
                notify(src, ('You need fishing level %d to buy this.'):format(data.requiredLevel), 'error')
                return
            end
            -- Rods are one-time purchases: refuse BEFORE charging.
            if hasItem(src, line.name, 1) then
                notify(src, ('You already own a %s.'):format(data.label), 'error')
                return
            end
        end
    end

    if getCash(src) < total then
        notify(src, 'You cannot afford that.', 'error')
        return
    end

    for _, line in ipairs(lines) do
        if not canCarryItem(src, line.name, line.qty) then
            notify(src, ('You cannot carry that much %s.'):format(line.data.label), 'error')
            return
        end
    end

    local preChar = charIdOf(src)
    if preChar == nil or tostring(preChar) ~= key then return end
    if not removeCash(src, total, 'fishing_store_purchase') then
        notify(src, 'You cannot afford that.', 'error')
        return
    end

    -- If the source changed hands while the cash was removed, refund the
    -- original character and stop before any item reaches the new one.
    local afterChar = charIdOf(src)
    if afterChar == nil or tostring(afterChar) ~= key then
        if not addCashToCharacter(preChar, total, 'fishing_store_purchase_refund_character_changed') then
            auditLog(src, 'fishing_purchase_refund_failed', { characterId = preChar, total = total })
        end
        return
    end

    local added = {}
    local failed = false
    for _, line in ipairs(lines) do
        if addItem(src, line.name, line.qty, 'fishing_store_purchase') then
            added[#added + 1] = line
        else
            failed = true
            break
        end
    end

    local kept = added
    if failed then
        -- Roll back what was delivered; whatever cannot be taken back stays
        -- delivered AND charged, so the report below is always truthful.
        kept = {}
        for _, line in ipairs(added) do
            if not removeItem(src, line.name, line.qty, 'fishing_store_purchase_rollback') then
                kept[#kept + 1] = line
            end
        end
    end

    local charged = 0
    for _, line in ipairs(kept) do charged = charged + line.cost end

    local refund = total - charged
    if refund > 0 and not addCash(src, refund, 'fishing_store_purchase_refund') then
        auditLog(src, 'fishing_purchase_refund_failed', { refund = refund, total = total, charged = charged })
        notify(src, 'Purchase failed and the refund could not be completed. Please contact staff.', 'error')
        return
    end

    if #kept == 0 then
        notify(src, 'Purchase failed. You have not been charged.', 'error')
    else
        local parts = {}
        for _, line in ipairs(kept) do parts[#parts + 1] = ('%dx %s'):format(line.qty, line.data.label) end
        local text = ('Bought %s for $%d.'):format(table.concat(parts, ', '), charged)
        if failed then text = text .. ' Part of the order failed; the rest was refunded.' end
        notify(src, text, failed and 'info' or 'success')
    end

    refreshStore(src, key)
end

RegisterNetEvent('cm-fishing:server:buyItem', function(kind, name, qty)
    local src = source
    if rateLimited(src, 'buyItem') then return end
    if type(kind) ~= 'string' or type(name) ~= 'string' then return end
    local charId, key = storeGate(src)
    if not charId then return end

    local catalog = kind == 'rod' and Config.Rods or (kind == 'bait' and Config.Bait or nil)
    if not catalog or not catalog[name] then return end

    qty = tonumber(qty) or 1
    if qty ~= qty or qty == math.huge or qty == -math.huge then qty = 1 end
    qty = kind == 'rod' and 1 or math.max(1, math.min(20, math.floor(qty)))

    withLock(key, src, function()
        processPurchase(src, key, { { name = name, qty = qty, kind = kind } })
    end)
end)

-- Bait cart checkout: several bait types/quantities in one request. Uses the
-- same all-or-nothing pipeline as single purchases (see processPurchase).
RegisterNetEvent('cm-fishing:server:buyCart', function(items)
    local src = source
    if rateLimited(src, 'buyCart') then return end
    if type(items) ~= 'table' then return end
    local charId, key = storeGate(src)
    if not charId then return end

    local lines = {}
    for name, qty in pairs(items) do
        local data = type(name) == 'string' and Config.Bait[name] or nil
        qty = tonumber(qty) or 0
        if qty ~= qty or qty == math.huge then qty = 0 end
        qty = math.max(0, math.min(20, math.floor(qty)))
        if data and qty > 0 then
            lines[#lines + 1] = { name = name, qty = qty, kind = 'bait' }
        end
    end
    if #lines == 0 then return end
    table.sort(lines, function(a, b) return a.name < b.name end)

    withLock(key, src, function()
        processPurchase(src, key, lines)
    end)
end)

RegisterNetEvent('cm-fishing:server:sellFish', function(name, amount)
    local src = source
    if rateLimited(src, 'sellFish') then return end
    if type(name) ~= 'string' then return end
    local charId, key = storeGate(src)
    if not charId then return end

    local fishData = Config.Fish[name]
    if not fishData then return end

    withLock(key, src, function()
        local owned = ownedCount(src, name)
        if owned <= 0 then
            notify(src, 'You do not have any of that to sell.', 'error')
            return
        end

        local sellAmount
        if amount == 'all' then
            sellAmount = owned
        else
            local n = tonumber(amount)
            if not n or n ~= n or n == math.huge or n == -math.huge then return end
            sellAmount = math.max(1, math.min(owned, math.floor(n)))
        end

        local unitPrice = Config.RaritySellPrice[fishData.rarity] or 15
        local total = unitPrice * sellAmount

        -- charId/name/sellAmount/total are captured above, BEFORE any mutation.
        -- The owner is resolved synchronously inside RemoveItem, so verifying
        -- the character right before it guarantees the fish leave THIS
        -- character's inventory.
        local preChar = charIdOf(src)
        if preChar == nil or tostring(preChar) ~= key then return end
        if not removeItem(src, name, sellAmount, 'fishing_sell') then
            notify(src, 'You do not have any of that to sell.', 'error')
            return
        end

        if Config.Debug and Config.DebugHooks.sale then simulateSwitch(src) end

        -- The source may now belong to another character. Never pay them and
        -- never give them the fish: restore to the ORIGINAL character.
        local currentChar = charIdOf(src)
        if currentChar == nil or tostring(currentChar) ~= key then
            if addItemToCharacter(charId, name, sellAmount, 'fishing_sell_restore_character_changed') then
                auditLog(src, 'fishing_sell_character_changed_restored', { characterId = charId, fish = name, amount = sellAmount, total = total })
            else
                auditLog(src, 'fishing_sell_restore_failed', { characterId = charId, fish = name, amount = sellAmount, total = total })
            end
            return
        end

        local mode = payJobCash(src, 'fishing', total, 'fishing_sell')
        if not mode then
            -- Nothing was paid: put back exactly what was removed.
            if not addItemToCharacter(charId, name, sellAmount, 'fishing_sell_restore') then
                auditLog(src, 'fishing_sell_restore_failed', { characterId = charId, fish = name, amount = sellAmount, total = total })
                notify(src, 'The sale failed and your fish could not be restored. Please contact staff.', 'error')
            else
                notify(src, 'The sale could not be completed. Your fish were returned.', 'error')
            end
            refreshStore(src, key)
            return
        end

        if mode == 'payday' then
            notify(src, ('Sold %dx %s — $%d added to City Payday.'):format(sellAmount, fishData.label, total), 'success')
        else
            notify(src, ('Sold %dx %s for $%d cash.'):format(sellAmount, fishData.label, total), 'success')
        end
        TriggerEvent('cm-fishing:server:fishSold', src, charId, { fish = name, amount = sellAmount, total = total, paidVia = mode })
        refreshStore(src, key)
    end)
end)

-- ---------------------------------------------------------------------------
-- Public, read-only discovery contract (future Job Center). Static data only.
-- ---------------------------------------------------------------------------

exports('GetJobInfo', function()
    local coords = Config.Store.coords
    return {
        id = 'fishing',
        label = 'Fishing',
        description = 'Buy a rod and bait, catch fish in the coastal zones or open water, and sell your catch at the Fishing Store.',
        location = vector3(coords.x, coords.y, coords.z),
        available = true,
    }
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
    if not charIdOf(targetSrc) then return reply(src, 'That player has no active character.') end

    local previousLevel, previousXp = getLevel(targetSrc), getXp(targetSrc)
    if not setMeta(targetSrc, 'cmFishingLevel', level) or not setMeta(targetSrc, 'cmFishingXp', 0) then
        setMeta(targetSrc, 'cmFishingLevel', previousLevel)
        setMeta(targetSrc, 'cmFishingXp', previousXp)
        return reply(src, 'Could not save the fishing level; nothing was changed.')
    end
    TriggerClientEvent('cm-fishing:client:status', targetSrc, getStatus(targetSrc))
    notify(targetSrc, ('Your fishing level was set to %d.'):format(level), 'info')
    reply(src, ('Set fishing level %d for player %d.'):format(level, targetSrc))
    auditLog(tonumber(src) or 0, 'fishing_set_level', { target = targetSrc, level = level })
end, false)

-- Debug only (Config.Debug = true), SERVER CONSOLE only: force the next casts
-- to roll a heavy fish / shark encounter for manual testing.
RegisterCommand('cmfishing_force', function(src, args)
    if tonumber(src) ~= 0 or not Config.Debug then return end
    local what = tostring(args[1] or ''):lower()
    if what == 'off' then
        Config.DebugForce.heavy, Config.DebugForce.shark = false, false
    elseif what == 'heavy' or what == 'shark' then
        Config.DebugForce[what] = true
    else
        return print('Usage: cmfishing_force heavy|shark|off')
    end
    print(('[CM-FISHING] DebugForce heavy=%s shark=%s'):format(tostring(Config.DebugForce.heavy), tostring(Config.DebugForce.shark)))
end, true)

-- Debug only (Config.Debug = true), SERVER CONSOLE only.
--   cmfishing_hook sale|rent|off   arm/disarm the mid-transaction character switch
--   cmfishing_hook clear <src>     drop a simulated character override
--   cmfishing_hook contracts <characterId> <fishName>
--       offline check of the character-targeted inventory/money contracts
--   cmfishing_hook xp <src>
--       calls AddXp with a WRONG expected character id; must be refused
RegisterCommand('cmfishing_hook', function(src, args)
    if tonumber(src) ~= 0 or not Config.Debug then return end
    local what = tostring(args[1] or ''):lower()
    if what == 'sale' or what == 'rent' then
        Config.DebugHooks[what] = true
    elseif what == 'off' then
        Config.DebugHooks.sale, Config.DebugHooks.rent = false, false
    elseif what == 'clear' then
        DebugCharOverride[tonumber(args[2]) or -1] = nil
    elseif what == 'xp' then
        local target = tonumber(args[2])
        local before = target and getXp(target)
        local ok, reason = exports['cm-fishing']:AddXp(target, 5, 'definitely-not-this-character')
        return print(('[CM-FISHING] xp test: result=%s reason=%s xpBefore=%s xpAfter=%s'):format(
            tostring(ok), tostring(reason), tostring(before), tostring(target and getXp(target))))
    elseif what == 'contracts' then
        local charId, fish = args[2], tostring(args[3] or 'fish')
        local q = 'SELECT COALESCE(SUM(quantity),0) FROM inventory_items WHERE owner_id = ? AND item_name = ?'
        local beforeItems = MySQL.scalar.await(q, { tostring(charId), fish })
        local beforeCash = MySQL.scalar.await('SELECT cash FROM characters WHERE id = ?', { charId })
        local itemOk = addItemToCharacter(charId, fish, 1, 'cmfishing_contract_test')
        local cashOk = addCashToCharacter(charId, 7, 'cmfishing_contract_test')
        local afterItems = MySQL.scalar.await(q, { tostring(charId), fish })
        local afterCash = MySQL.scalar.await('SELECT cash FROM characters WHERE id = ?', { charId })
        local badItem = addItemToCharacter('999999999', fish, 1, 'cmfishing_contract_test')
        local badCash = addCashToCharacter('999999999', 7, 'cmfishing_contract_test')
        return print(('[CM-FISHING] contracts: item ok=%s %s->%s | cash ok=%s %s->%s | unknown char item=%s cash=%s'):format(
            tostring(itemOk), tostring(beforeItems), tostring(afterItems), tostring(cashOk), tostring(beforeCash), tostring(afterCash), tostring(badItem), tostring(badCash)))
    else
        return print('Usage: cmfishing_hook sale|rent|off | clear <src> | xp <src> | contracts <characterId> <fish>')
    end
    print(('[CM-FISHING] DebugHooks sale=%s rent=%s'):format(tostring(Config.DebugHooks.sale), tostring(Config.DebugHooks.rent)))
end, true)
