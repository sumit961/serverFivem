local Config = CMElectrician.Config
CMElectrician.Server = CMElectrician.Server or {}

local PLAYERDATA = 'cm-playerdata'
local VEHICLES = 'cm-vehicles'

-- Sessions[src] = {
--     src, charId, startedAt,
--     panelTargets = {index, ...},   -- server-assigned, authoritative
--     plateTargets = {index, ...},   -- server-assigned, authoritative
--     repair = nil | RepairSession,
-- }
-- Existence of Sessions[src] IS "on shift". Never persisted -- rebuilt fresh
-- every time a shift starts, so duty never survives a reconnect/switch.
local Sessions = {}

local cooldowns = {}
local jobVehicles = {} -- [src] = { plate = ..., netId = ... }
local jobVehicleLocks = {} -- [src] = true while a rental transaction is in flight
local RepairTokenSeq = 0
local qaFixtures = {} -- [src] = metadata captured by the development-only QA contract

-- Outage is single global state shared by every level-3+ electrician.
-- state: 'inactive' | 'active' | 'processing'
local Outage = { id = 0, state = 'inactive', location = nil, claimSrc = nil, claimSeq = 0 }

local function dbg(...)
    if Config.Debug then print('[CM-ELECTRICIAN]', ...) end
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-electrician:client:notify', src, tostring(message or ''), kind or 'info')
end

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

-- Uses SetMetadataDetailed so a persistence failure (character mid-switch,
-- not authenticated, validation rejection) is reported back as `false`
-- instead of silently pretending to succeed -- callers must not pay/advance
-- progression unless this returns true. See AGENTS.md "Progression write
-- failure" rule.
local function setMeta(src, key, value)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:SetMetadataDetailed(src, key, value) end)
    return ok and result == true
end

local function getCharId(src)
    local api = playerData()
    if not api then return nil end
    local ok, result = pcall(function() return api:GetCharacterId(src) end)
    if ok and result then return result end
    return nil
end

local function addCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:AddCash(src, amount, reason) end)
    return ok and result == true
end

local function addCashToCharacter(characterId, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function()
        return api:AddMoneyToCharacter(characterId, 'cash', amount, reason)
    end)
    return ok and result == true
end

-- Repair earnings bank into cm-payday's hourly payout when it's running
-- (salary paid at the top of every hour instead of per repair); falls back
-- to the old instant pay if cm-payday isn't started. Panel/plate counters
-- and level-ups stay instant since they gate job unlocks, not pay.
local function payJobCash(src, amount, reason)
    if GetResourceState('cm-payday') == 'started' then
        local ok, result = pcall(function() return exports['cm-payday']:AddPendingCash(src, 'electrician', amount, reason) end)
        if ok and result == true then return true end
    end
    return addCash(src, amount, reason)
end

local function getStatus(src)
    return {
        level = math.max(1, math.floor(tonumber(getMeta(src, 'cmElectricianLevel', 1)) or 1)),
        panels = math.max(0, math.floor(tonumber(getMeta(src, 'cmElectricianPanels', 0)) or 0)),
        plates = math.max(0, math.floor(tonumber(getMeta(src, 'cmElectricianPlates', 0)) or 0)),
    }
end

local function qaInvokerAllowed()
    if GetConvar('cm_environment', 'production') ~= 'development' then
        return false, 'environment_not_development'
    end
    if GetConvarInt('cm_qa_enabled', 0) ~= 1 then
        return false, 'qa_disabled'
    end
    if GetInvokingResource() ~= 'cm-qa' then
        return false, 'forbidden'
    end
    return true
end

local function qaSource(data)
    if type(data) ~= 'table' then return nil end
    local src = tonumber(data.source)
    if not src or not GetPlayerName(src) then return nil end
    return src
end

local function copyList(list)
    local copy = {}
    for i, value in ipairs(list or {}) do copy[i] = value end
    return copy
end

local function qaPendingCash(src)
    if GetResourceState('cm-payday') ~= 'started' then return nil end
    local ok, pending = pcall(function() return exports['cm-payday']:GetPending(src) end)
    if not ok or type(pending) ~= 'table' then return nil end
    return {
        cash = math.max(0, math.floor(tonumber(pending.cash) or 0)),
        electrician = pending.cashByJob and math.max(0, math.floor(tonumber(pending.cashByJob.electrician) or 0)) or 0,
    }
end

local function onCooldown(src)
    local now = GetGameTimer()
    if (cooldowns[src] or 0) > now then return true end
    cooldowns[src] = now + (tonumber(Config.Security.actionCooldownMs) or 900)
    return false
end

local function pickRandomLocation(list, exclude)
    if #list <= 1 then return list[1] end
    local pick
    repeat
        pick = list[math.random(1, #list)]
    until pick ~= exclude
    return pick
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

-- IsEntityDead is not available server-side on this FXServer build (it's the
-- native that was erroring here). cm-playerdata already tracks death
-- authoritatively itself (server/main.lua uses GetEntityHealth, never
-- IsEntityDead, for exactly this reason) and replicates it as the standard
-- 'isDead' player state bag -- read that instead rather than re-deriving it
-- from a native that doesn't exist in this context.
local function isAlive(src)
    local ply = Player(src)
    if not ply then return false end
    return ply.state.isDead ~= true
end

local function isOnFoot(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    return not IsPedInAnyVehicle(ped, false)
end

-- Normal civilian job gameplay is bucket-0 only. Never move the player
-- ourselves -- just refuse to start/continue the job if something else has
-- already moved them into a private/selector bucket.
local function isNormalBucket(src)
    local ok, bucket = pcall(function() return GetPlayerRoutingBucket(src) end)
    return ok and tonumber(bucket) == 0
end

-- Best-effort pre-check so a blocked spawn point is caught before charging
-- the player. Falls back to "not blocked" (letting the real spawn attempt be
-- the judge) if the native isn't available for any reason -- never treated
-- as fatal.
local function spawnAreaBlocked(coords)
    local ok, occupied = pcall(function()
        return IsPositionOccupied(coords.x, coords.y, coords.z, 2.5, false, true, true, false, false, 0)
    end)
    return ok and occupied == true
end

local function tableContains(list, value)
    if type(list) ~= 'table' then return false end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function vehiclesApi()
    if GetResourceState(VEHICLES) ~= 'started' then return nil end
    return exports[VEHICLES]
end

local function deleteJobVehicle(src)
    local rec = jobVehicles[src]
    if not rec then return end
    jobVehicles[src] = nil
    local api = vehiclesApi()
    if api then pcall(function() api:DeleteAdminVehicle(rec.plate) end) end
end

local function withVehicleLock(src, fn)
    if jobVehicleLocks[src] then return false end
    jobVehicleLocks[src] = true
    local ok, err = xpcall(fn, debug.traceback)
    jobVehicleLocks[src] = nil
    if not ok then
        print('[CM-ELECTRICIAN] service vehicle transaction failed: ' .. tostring(err))
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- Server-owned panel/deposit-plate target assignment. The client only ever
-- renders whatever indices the server hands it -- it never picks its own.
-- ---------------------------------------------------------------------------

local function chooseTargets(list, count)
    count = math.max(0, math.min(math.floor(tonumber(count) or 0), #list))
    local pool = {}
    for i = 1, #list do pool[i] = i end
    local chosen = {}
    for _ = 1, count do
        local pick = table.remove(pool, math.random(1, #pool))
        chosen[#chosen + 1] = pick
    end
    return chosen
end

local function replaceOneTarget(list, active, fixedIndex)
    for i, idx in ipairs(active) do
        if idx == fixedIndex then
            table.remove(active, i)
            break
        end
    end
    local activeSet = {}
    for _, idx in ipairs(active) do activeSet[idx] = true end
    local pool = {}
    for i = 1, #list do
        if not activeSet[i] then pool[#pool + 1] = i end
    end
    if #pool > 0 then
        active[#active + 1] = pool[math.random(1, #pool)]
    end
end

local function refreshServerPanelTargets(session)
    if #session.panelTargets == 0 then
        session.panelTargets = chooseTargets(Config.Panels, tonumber(Config.TaskCount.panels) or 3)
    end
end

local function refreshServerPlateTargets(session)
    if #session.plateTargets == 0 then
        session.plateTargets = chooseTargets(Config.Plates, tonumber(Config.TaskCount.plates) or 2)
    end
end

local function sendAssignments(src, session)
    TriggerClientEvent('cm-electrician:client:assignments', src, {
        panels = session.panelTargets,
        plates = session.plateTargets,
    })
end

-- ---------------------------------------------------------------------------
-- Outage claim -- ACTIVE -> PROCESSING -> (resolved / back to ACTIVE).
-- Lua/FiveM event handlers and threads never run concurrently (only
-- cooperative yielding at Wait()), so a check-then-set with no yield in
-- between is inherently atomic -- no extra locking needed.
-- ---------------------------------------------------------------------------

local function claimOutage(id, src)
    if Outage.id ~= id then return false end
    if Outage.state ~= 'active' then return false end
    Outage.claimSeq = Outage.claimSeq + 1
    Outage.state = 'processing'
    Outage.claimSrc = src
    return true, Outage.claimSeq
end

local function releaseOutageClaim(id, src, claimSeq)
    if Outage.id ~= id then return end
    if Outage.state ~= 'processing' then return end
    if src and Outage.claimSrc ~= src then return end
    if claimSeq and Outage.claimSeq ~= claimSeq then return end
    Outage.state = 'active'
    Outage.claimSrc = nil
end

-- Safety net: if whoever claimed the outage never completes or cancels
-- (disconnect edge case, stuck client), release the claim so it isn't stuck
-- PROCESSING forever with nobody able to retry it.
local function scheduleClaimWatchdog(id, src, claimSeq, holdMs)
    local graceMs = tonumber(Config.Hold.tokenGraceMs) or 6000
    CreateThread(function()
        Wait(holdMs + graceMs + 5000)
        releaseOutageClaim(id, src, claimSeq)
    end)
end

-- ---------------------------------------------------------------------------
-- Shift lifecycle.
-- ---------------------------------------------------------------------------

local function checkOutageAlert(src, status)
    if Sessions[src] and Outage.state ~= 'inactive' and status.level >= (tonumber(Config.PowerOutage.unlockLevel) or 3) then
        TriggerClientEvent('cm-electrician:client:outageAlert', src, Outage.location)
    end
end

local function beginShift(src)
    if Sessions[src] then return true end

    if not isNormalBucket(src) then
        return false, 'You cannot start a shift here.'
    end

    local coords = playerCoords(src)
    if not coords then return false, 'Could not verify your position.' end

    local maxDistance = (tonumber(Config.Security.employmentDistance) or 3.0) + (tonumber(Config.Employment.interactDistance) or 1.4)
    if #(coords - Config.Employment.coords) > maxDistance then
        return false, 'You are too far from the switchboard.'
    end

    local charId = getCharId(src)
    if not charId then
        return false, 'Your character data is not ready yet.'
    end

    local status = getStatus(src)
    local session = {
        src = src,
        charId = charId,
        startedAt = GetGameTimer(),
        panelTargets = {},
        plateTargets = {},
        repair = nil,
    }
    Sessions[src] = session

    refreshServerPanelTargets(session)
    if status.level >= 2 then refreshServerPlateTargets(session) end
    sendAssignments(src, session)

    TriggerEvent('cm-electrician:server:shiftStarted', src, charId)
    return true
end

-- Single cleanup point for every forced-end path (manual resign, character
-- switch, disconnect, death, bucket change, resource stop). Idempotent --
-- safe to call on a src with no active session.
local function endShift(src, reason)
    local session = Sessions[src]
    if not session then return end
    Sessions[src] = nil
    cooldowns[src] = nil

    if session.repair and session.repair.taskType == 'outage' and session.repair.outageId then
        releaseOutageClaim(session.repair.outageId, src, session.repair.claimSeq)
    end

    deleteJobVehicle(src)
    TriggerClientEvent('cm-electrician:client:employedSet', src, false, reason)
end

RegisterNetEvent('cm-electrician:server:requestStatus', function()
    local src = source
    local status = getStatus(src)
    TriggerClientEvent('cm-electrician:client:status', src, status)
    checkOutageAlert(src, status)
end)

RegisterNetEvent('cm-electrician:server:setEmployed', function(wantEmployed)
    local src = source
    wantEmployed = wantEmployed == true

    if wantEmployed then
        local ok, err = beginShift(src)
        TriggerClientEvent('cm-electrician:client:employedSet', src, ok == true, ok and nil or err)
        return
    end

    if not Sessions[src] then
        TriggerClientEvent('cm-electrician:client:employedSet', src, false)
        return
    end
    endShift(src, nil)
end)

-- ---------------------------------------------------------------------------
-- Service truck rental. Spawned through cm-vehicles' trusted-placement
-- bridge (see its Config.Placement.authorizedResources), which auto-assigns
-- owner access tied to the requesting player's own character -- the truck
-- behaves like a normal owned vehicle (locks, keys, engine) instead of a
-- bare admin prop. Strictly temporary: never stored, sold or transferred.
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-electrician:server:requestServiceTruck', function(wantVehicle)
    local src = source
    wantVehicle = wantVehicle == true

    -- Returning/cleaning up a truck must work regardless of employment state
    -- or location -- e.g. the level-1 job-area leash or a manual resignation
    -- can fire while the player is off driving it somewhere else entirely.
    if not wantVehicle then
        if jobVehicleLocks[src] then
            notify(src, 'Please wait -- the service truck request is still being processed.', 'error')
            return
        end
        if not jobVehicles[src] then return end
        deleteJobVehicle(src)
        TriggerClientEvent('cm-electrician:client:serviceTruck', src, false)
        notify(src, 'Service truck returned.', 'info')
        return
    end

    withVehicleLock(src, function()
        local session = Sessions[src]
        if not session then return end
        local rent = Config.RentVehicle
        local status = getStatus(src)
        if status.level < (tonumber(rent.unlockLevel) or 2) then return end

    -- Rental is requested by talking to the switchboard NPC rather than
    -- walking to a separate point, so the proximity check is against the
    -- NPC's own location.
        local coords = playerCoords(src)
        if not coords then return end
    local npc = Config.NPC or {}
    local npcCoords = npc.coords or Config.Employment.coords
    local maxDistance = (tonumber(Config.Security.employmentDistance) or 3.0) + (tonumber(npc.interactDistance) or 3.0)
        if #(coords - vector3(npcCoords.x, npcCoords.y, npcCoords.z)) > maxDistance then
            notify(src, 'You are too far from the electrician foreman.', 'error')
            return
        end

    -- Server owns this -- a client can never fake "no truck active" to get a
    -- second one; one active truck per src, period.
        if jobVehicles[src] then return end

        local spawn = rent.spawnCoords
        if spawnAreaBlocked(spawn) then
            notify(src, 'SERVICE VEHICLE AREA BLOCKED', 'error')
            return
        end

    -- Charged up front so a spawn failure or the vehicle bridge being
    -- offline can't leave the player billed with nothing to show for it --
    -- RemoveCash itself fails atomically if they can't afford it, and any
    -- failure past this point refunds exactly once via addCash.
        local rentCost = math.max(0, math.floor(tonumber(rent.cost) or 0))
        local billingApi = rentCost > 0 and playerData() or nil
        if rentCost > 0 then
            if not billingApi then
                notify(src, 'Vehicle service is unavailable.', 'error')
                return
            end
            local ok, removed = pcall(function() return billingApi:RemoveCash(src, rentCost, 'electrician_truck_rental') end)
            if not ok or removed ~= true then
                notify(src, ('You need $%d to rent the service truck.'):format(rentCost), 'error')
                return
            end
        end

        local api = vehiclesApi()
        if not api then
            notify(src, 'Vehicle service is unavailable.', 'error')
            if rentCost > 0 then addCash(src, rentCost, 'electrician_truck_rental_refund') end
            return
        end

        local ok, result = pcall(function()
            return api:SpawnAdminVehicle(src, rent.model, { x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.w }, {
                placementKind = 'car',
                label = 'Electrician Service Truck',
                engineOn = true,
                warp = true,
            })
        end)

        if not ok or type(result) ~= 'table' or result.ok ~= true then
            local err = ok and type(result) == 'table' and result.error or nil
            if err and tostring(err):find('failed to spawn', 1, true) then
                notify(src, 'SERVICE VEHICLE AREA BLOCKED', 'error')
            else
                notify(src, 'The service truck could not be spawned.', 'error')
            end
            if rentCost > 0 then addCash(src, rentCost, 'electrician_truck_rental_refund') end
            return
        end

        local currentCharId = getCharId(src)
        if currentCharId == nil or tostring(currentCharId) ~= tostring(session.charId) or Sessions[src] ~= session then
            pcall(function()
                if api:IsAdminVehicle(result.plate) then api:DeleteAdminVehicle(result.plate) end
            end)
            if rentCost > 0 and not addCashToCharacter(session.charId, rentCost, 'electrician_truck_rental_refund_character_changed') then
                print(('[CM-ELECTRICIAN] service-truck refund failed for character %s'):format(tostring(session.charId)))
            end
            return
        end

        jobVehicles[src] = { plate = result.plate, netId = result.netId }
        TriggerClientEvent('cm-electrician:client:serviceTruck', src, true)
        notify(src, rentCost > 0
            and ('Service truck rented for $%d. Drive safe.'):format(rentCost)
            or 'Service truck ready. Drive safe.', 'success')
    end)
end)

-- ---------------------------------------------------------------------------
-- Repair session security. BEGIN validates everything and hands back a
-- single-use token; COMPLETE only trusts the token, never the client's
-- account of what happened. The server rolls shock at BEGIN time and simply
-- tells the client when to play the effect -- COMPLETE independently
-- rechecks against that same server-held value, so a client can never claim
-- "I wasn't shocked".
-- ---------------------------------------------------------------------------

local function newToken(src)
    RepairTokenSeq = RepairTokenSeq + 1
    return ('%d-%d-%d'):format(src, RepairTokenSeq, GetGameTimer())
end

local function taskConfig(taskType)
    if taskType == 'panel' then
        return { holdMs = Config.Hold.panelMs, shockChance = Config.ShockChance.panel, distance = Config.Security.panelDistance, minLevel = 1 }
    elseif taskType == 'plate' then
        return { holdMs = Config.Hold.plateMs, shockChance = Config.ShockChance.plate, distance = Config.Security.plateDistance, minLevel = 2 }
    elseif taskType == 'outage' then
        return { holdMs = Config.Hold.outageMs, shockChance = Config.ShockChance.outage, distance = Config.Security.outageDistance, minLevel = tonumber(Config.PowerOutage.unlockLevel) or 3 }
    end
    return nil
end

RegisterNetEvent('cm-electrician:server:beginRepair', function(taskType, index)
    local src = source
    dbg(('begin_repair src=%s char=%s type=%s index=%s'):format(
        tostring(src), tostring(Sessions[src] and Sessions[src].charId), tostring(taskType), tostring(index)))

    local session = Sessions[src]
    if not session then
        dbg('begin_repair rejected reason=not_on_shift')
        return
    end
    if session.repair then
        dbg('begin_repair rejected reason=repair_active')
        return
    end -- one hold at a time

    local cfg = taskConfig(taskType)
    if not cfg then
        dbg('begin_repair rejected reason=invalid_target')
        return
    end

    if not isNormalBucket(src) then
        dbg('begin_repair rejected reason=wrong_bucket')
        endShift(src, 'You cannot work here.')
        return
    end

    local status = getStatus(src)
    if status.level < cfg.minLevel then
        dbg('begin_repair rejected reason=level_too_low')
        notify(src, 'You are not yet certified for this task.', 'error')
        return
    end

    if onCooldown(src) then
        dbg('begin_repair rejected reason=cooldown')
        return
    end
    if not isAlive(src) then
        dbg('begin_repair rejected reason=dead')
        return
    end
    if not isOnFoot(src) then
        dbg('begin_repair rejected reason=in_vehicle')
        notify(src, 'You must be on foot to do this.', 'error')
        return
    end

    local point
    if taskType == 'panel' then
        index = tonumber(index)
        point = index and Config.Panels[index]
        if not point then
            dbg('begin_repair rejected reason=invalid_target')
            return
        end
        if not tableContains(session.panelTargets, index) then
            dbg(('begin_repair rejected reason=not_assigned index=%s'):format(tostring(index)))
            notify(src, 'That panel is not assigned to you.', 'error')
            return
        end
    elseif taskType == 'plate' then
        index = tonumber(index)
        point = index and Config.Plates[index]
        if not point then
            dbg('begin_repair rejected reason=invalid_target')
            return
        end
        if not tableContains(session.plateTargets, index) then
            dbg(('begin_repair rejected reason=not_assigned index=%s'):format(tostring(index)))
            notify(src, 'That deposit plate is not assigned to you.', 'error')
            return
        end
    else -- outage
        index = nil
        if Outage.state ~= 'active' then
            dbg('begin_repair rejected reason=outage_not_active')
            notify(src, 'This power outage has already been restored.', 'info')
            return
        end
        point = Outage.location
    end
    if not point then
        dbg('begin_repair rejected reason=invalid_target')
        return
    end

    local coords = playerCoords(src)
    if not coords or #(coords - point) > (tonumber(cfg.distance) or 2.0) then
        dbg(('begin_repair rejected reason=too_far distance=%s'):format(coords and tostring(#(coords - point)) or 'nil'))
        notify(src, 'You are too far away.', 'error')
        return
    end

    local outageClaimId, outageClaimSeq = nil, nil
    if taskType == 'outage' then
        local claimed, claimSeq = claimOutage(Outage.id, src)
        if not claimed then
            dbg('begin_repair rejected reason=outage_claimed')
            notify(src, 'This power outage has already been restored.', 'info')
            return
        end
        outageClaimId = Outage.id
        outageClaimSeq = claimSeq
        scheduleClaimWatchdog(outageClaimId, src, outageClaimSeq, cfg.holdMs)
    end

    local now = GetGameTimer()
    local graceMs = tonumber(Config.Hold.tokenGraceMs) or 6000
    local forcedShock = session.qaForceShock == true
    session.qaForceShock = nil
    local shockAtMs = forcedShock and math.min(300, cfg.holdMs)
        or ((math.random() < (tonumber(cfg.shockChance) or 0))
            and math.random(300, math.max(300, cfg.holdMs)) or nil)

    session.repair = {
        token = newToken(src),
        taskType = taskType,
        index = index,
        outageId = outageClaimId,
        claimSeq = outageClaimSeq,
        startedAt = now,
        earliestFinishAt = now + cfg.holdMs,
        expiresAt = now + cfg.holdMs + graceMs,
        shockAtMs = shockAtMs,
    }
    session.lastRepairOutcome = nil

    dbg(('begin_repair accepted src=%s type=%s index=%s token_present=true'):format(
        tostring(src), taskType, tostring(index)))

    TriggerClientEvent('cm-electrician:client:repairBegin', src, {
        token = session.repair.token,
        type = taskType,
        index = index,
        durationMs = cfg.holdMs,
        shockAtMs = shockAtMs,
    })
end)

RegisterNetEvent('cm-electrician:server:cancelRepair', function(token)
    local src = source
    local session = Sessions[src]
    if not session or not session.repair or session.repair.token ~= token then return end
    local repair = session.repair
    session.repair = nil
    session.lastRepairOutcome = repair.shockAtMs and 'shock'
        or ((GetGameTimer() < repair.earliestFinishAt) and 'early_release' or 'cancelled')
    if repair.taskType == 'outage' and repair.outageId then
        releaseOutageClaim(repair.outageId, src, repair.claimSeq)
    end
end)

local function awardPanelRepair(src, session, index)
    local status = getStatus(src)
    local panels = status.panels + 1
    if not setMeta(src, 'cmElectricianPanels', panels) then
        notify(src, 'Repair could not be saved. Try again.', 'error')
        return
    end

    local level, leveledUp = status.level, false
    if level < 2 and panels >= (tonumber(Config.LevelUp.panelsForLevel2) or 50) then
        if setMeta(src, 'cmElectricianLevel', 2) then
            level, leveledUp = 2, true
        end
        -- If this particular write fails, panels are already saved and the
        -- next successful panel repair will retry the same threshold check
        -- (idempotent) -- no duplicate reward is issued either way.
    end

    replaceOneTarget(Config.Panels, session.panelTargets, index)
    if leveledUp then refreshServerPlateTargets(session) end
    sendAssignments(src, session)

    payJobCash(src, Config.Earnings.perPanel, 'electrician_panel_repair')
    notify(src, ('Panel repaired. Earned $%d.'):format(Config.Earnings.perPanel), 'success')
    if leveledUp then
        notify(src, 'Level up! You can now rent a service truck and repair deposit plates.', 'success')
    end

    TriggerClientEvent('cm-electrician:client:panelResult', src, {
        index = index, panels = panels, level = level, leveledUp = leveledUp,
    })
    TriggerEvent('cm-electrician:server:taskCompleted', {
        src = src, characterId = session.charId, taskType = 'panel', reward = Config.Earnings.perPanel,
    })
    if leveledUp then
        TriggerEvent('cm-electrician:server:levelChanged', src, session.charId, level)
    end
end

local function awardPlateRepair(src, session, index)
    local status = getStatus(src)
    local plates = status.plates + 1
    if not setMeta(src, 'cmElectricianPlates', plates) then
        notify(src, 'Repair could not be saved. Try again.', 'error')
        return
    end

    local level, leveledUp = status.level, false
    if level < 3 and plates >= (tonumber(Config.LevelUp.platesForLevel3) or 500) then
        if setMeta(src, 'cmElectricianLevel', 3) then
            level, leveledUp = 3, true
        end
    end

    replaceOneTarget(Config.Plates, session.plateTargets, index)
    sendAssignments(src, session)

    payJobCash(src, Config.Earnings.perPlate, 'electrician_plate_repair')
    notify(src, ('Deposit plate repaired. Earned $%d.'):format(Config.Earnings.perPlate), 'success')
    if leveledUp then
        notify(src, 'Level up! You will now be dispatched to city power outages.', 'success')
        if Outage.state ~= 'inactive' then
            TriggerClientEvent('cm-electrician:client:outageAlert', src, Outage.location)
        end
    end

    TriggerClientEvent('cm-electrician:client:plateResult', src, {
        index = index, plates = plates, level = level, leveledUp = leveledUp,
    })
    TriggerEvent('cm-electrician:server:taskCompleted', {
        src = src, characterId = session.charId, taskType = 'plate', reward = Config.Earnings.perPlate,
    })
    if leveledUp then
        TriggerEvent('cm-electrician:server:levelChanged', src, session.charId, level)
    end
end

local scheduleOutage -- forward declaration; scheduleOutage/scheduleAutoFix call each other

local function awardOutageRepair(src, outageId, claimSeq)
    if Outage.id ~= outageId or Outage.state ~= 'processing' or Outage.claimSrc ~= src then return end
    if claimSeq and Outage.claimSeq ~= claimSeq then return end
    Outage.state = 'inactive'
    Outage.location = nil
    Outage.claimSrc = nil
    TriggerClientEvent('cm-electrician:client:outageState', -1, false, nil)

    local session = Sessions[src]
    payJobCash(src, Config.Earnings.perOutageFix, 'electrician_outage_repair')
    TriggerClientEvent('cm-electrician:client:notify', -1,
        'Electricians responded to the city power outage and restored power.', 'success')
    TriggerEvent('cm-electrician:server:taskCompleted', {
        src = src, characterId = session and session.charId or nil, taskType = 'outage', reward = Config.Earnings.perOutageFix,
    })
    scheduleOutage()
end

RegisterNetEvent('cm-electrician:server:completeRepair', function(token)
    local src = source
    local session = Sessions[src]
    if not session or not session.repair then return end
    local repair = session.repair
    if repair.token ~= token then return end

    -- Single-use: consumed here regardless of outcome below.
    session.repair = nil
    session.lastRepairOutcome = 'completed'

    local function releaseIfOutage()
        if repair.taskType == 'outage' and repair.outageId then
            releaseOutageClaim(repair.outageId, src, repair.claimSeq)
        end
    end

    if repair.taskType == 'outage' then
        if not (Outage.state == 'processing' and Outage.claimSrc == src and Outage.id == repair.outageId) then
            notify(src, 'This power outage has already been restored.', 'info')
            return
        end
    end

    -- shockAtMs is always <= the hold duration, so by the time COMPLETE can
    -- legitimately fire (elapsed >= earliestFinishAt) a shocked attempt has
    -- already crossed its shock point -- this rejects it unconditionally,
    -- independent of anything the client claims.
    if repair.shockAtMs then
        releaseIfOutage()
        notify(src, 'You got shocked! The repair failed.', 'error')
        return
    end

    local now = GetGameTimer()
    if now < repair.earliestFinishAt or now > repair.expiresAt then
        releaseIfOutage()
        notify(src, 'The repair was interrupted.', 'error')
        return
    end

    if not isAlive(src) or not isOnFoot(src) then
        releaseIfOutage()
        return
    end

    local point
    if repair.taskType == 'panel' then point = Config.Panels[repair.index]
    elseif repair.taskType == 'plate' then point = Config.Plates[repair.index]
    else point = Outage.location end
    if not point then
        releaseIfOutage()
        return
    end

    local coords = playerCoords(src)
    local cfg = taskConfig(repair.taskType)
    if not coords or #(coords - point) > (tonumber(cfg.distance) or 2.0) then
        releaseIfOutage()
        notify(src, 'You moved too far away.', 'error')
        return
    end

    if repair.taskType == 'panel' then
        awardPanelRepair(src, session, repair.index)
    elseif repair.taskType == 'plate' then
        awardPlateRepair(src, session, repair.index)
    else
        awardOutageRepair(src, repair.outageId, repair.claimSeq)
    end
end)

-- ---------------------------------------------------------------------------
-- Power outage scheduling.
-- ---------------------------------------------------------------------------

-- No point blacking out a fault (and running its auto-fix countdown) when
-- nobody currently on duty could even respond to it.
local function hasOnlineResponder()
    local unlockLevel = tonumber(Config.PowerOutage.unlockLevel) or 3
    for src in pairs(Sessions) do
        if getStatus(src).level >= unlockLevel then return true end
    end
    return false
end

-- Tells bystanders near the fault the power just went out -- NOT the whole
-- city, only whoever happens to already be within the same radius the
-- blackout effect itself uses. Level-3+ electricians on shift are skipped
-- since checkOutageAlert gives them their own "head to your GPS" message.
local function notifyOutageStart()
    if not Outage.location then return end
    local unlockLevel = tonumber(Config.PowerOutage.unlockLevel) or 3
    local radius = tonumber(Config.PowerOutage.blackoutExitRadius) or 60.0

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local respondingElectrician = Sessions[src] and getStatus(src).level >= unlockLevel
        if not respondingElectrician then
            local coords = playerCoords(src)
            if coords and #(coords - Outage.location) <= radius then
                TriggerClientEvent('cm-electrician:client:notify', src,
                    'The power just went out around here.', 'info')
            end
        end
    end
end

-- If nobody fixes the outage within autoFixMinutes, the utility company
-- resolves it for free. If a player is actively PROCESSING it right at that
-- moment, retry briefly before force-resolving, so a normal in-progress
-- repair isn't stolen out from under someone -- but it still never sits
-- unattended forever.
local function scheduleAutoFix(id)
    CreateThread(function()
        local minutes = tonumber(Config.PowerOutage.autoFixMinutes) or 10
        Wait(minutes * 60000)
        if Outage.id ~= id then return end

        local attempts = 0
        while Outage.id == id and Outage.state == 'processing' and attempts < 6 do
            Wait(15000)
            attempts = attempts + 1
        end
        if Outage.id ~= id or Outage.state == 'inactive' then return end -- already resolved by a player

        Outage.state = 'inactive'
        Outage.location = nil
        Outage.claimSrc = nil
        TriggerClientEvent('cm-electrician:client:outageState', -1, false, nil)
        TriggerClientEvent('cm-electrician:client:notify', -1,
            'The city outage was resolved automatically after going unattended too long.', 'info')
        scheduleOutage()
    end)
end

scheduleOutage = function()
    CreateThread(function()
        local minWait = tonumber(Config.PowerOutage.minWaitMs) or 300000
        local maxWait = tonumber(Config.PowerOutage.maxWaitMs) or 9000000
        Wait(math.random(minWait, maxWait))
        if Outage.state ~= 'inactive' then return end

        -- Nobody who could respond is even on duty -- wait for a level-3
        -- electrician to clock in instead of blacking out an area that can
        -- only ever resolve via the unattended auto-fix timer.
        while not hasOnlineResponder() do
            Wait(30000)
            if Outage.state ~= 'inactive' then return end
        end

        Outage.id = Outage.id + 1
        Outage.state = 'active'
        Outage.location = pickRandomLocation(Config.PowerOutage.locations, Outage.location)
        Outage.claimSrc = nil

        TriggerClientEvent('cm-electrician:client:outageState', -1, true, Outage.location)
        scheduleAutoFix(Outage.id)
        notifyOutageStart()

        for src in pairs(Sessions) do
            checkOutageAlert(src, getStatus(src))
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Character switch / disconnect / death / bucket cleanup.
-- ---------------------------------------------------------------------------

-- Fires on both a mid-session character switch and a normal logout (the
-- disconnect path routes through the same cm-playerdata teardown), so this
-- is the single point that guarantees no Electrician runtime state ever
-- crosses from one character to another.
AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    src = tonumber(src)
    qaFixtures[src] = nil
    endShift(src, nil)
end)

AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, isDead)
    src = tonumber(src)
    if not isDead then return end
    local session = Sessions[src]
    if not session then return end
    if session.repair and session.repair.taskType == 'outage' and session.repair.outageId then
        releaseOutageClaim(session.repair.outageId, src, session.repair.claimSeq)
    end
    endShift(src, 'You were taken off duty after dying.')
end)

AddEventHandler('playerDropped', function()
    qaFixtures[source] = nil
    endShift(source, nil)
end)

-- Nothing here moves a player between buckets -- this only reacts if some
-- other system (house/selector/etc.) already has.
CreateThread(function()
    while true do
        Wait(8000)
        for src in pairs(Sessions) do
            if not isNormalBucket(src) then
                endShift(src, 'You were moved to a different instance and taken off duty.')
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Admin commands.
-- ---------------------------------------------------------------------------

local function isAdminAllowed(src, permission)
    if tonumber(src) == 0 then return true end
    if GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
    return ok and allowed == true
end

local function reply(src, message)
    if tonumber(src) == 0 then
        print('[CM-ELECTRICIAN] ' .. tostring(message))
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '[CM-ELECTRICIAN]', tostring(message) } })
    end
end

RegisterCommand('setelectricianlevel', function(src, args)
    if not isAdminAllowed(src, 'electrician.admin.setlevel') then
        return reply(src, 'You do not have permission to do that.')
    end

    local level = math.floor(tonumber(args[1]) or -1)
    if level < 1 or level > 3 then
        return reply(src, 'Usage: /setelectricianlevel <1-3> [playerId]')
    end

    local targetSrc = tonumber(args[2])
    if not targetSrc then
        if tonumber(src) == 0 then return reply(src, 'Usage from console: /setelectricianlevel <1-3> <playerId>') end
        targetSrc = tonumber(src)
    end
    if not GetPlayerName(targetSrc) then return reply(src, 'That player is not online.') end

    if not setMeta(targetSrc, 'cmElectricianLevel', level) then
        return reply(src, 'Failed to save the new level -- the target character may not be fully loaded.')
    end
    local status = getStatus(targetSrc)
    TriggerClientEvent('cm-electrician:client:status', targetSrc, status)
    checkOutageAlert(targetSrc, status)
    notify(targetSrc, ('Your electrician level was set to %d.'):format(level), 'info')
    reply(src, ('Set electrician level %d for player %d.'):format(level, targetSrc))
end, false)

RegisterCommand('triggerelectricianoutage', function(src)
    if not isAdminAllowed(src, 'electrician.admin.setlevel') then
        return reply(src, 'You do not have permission to do that.')
    end
    if Outage.state ~= 'inactive' then return reply(src, 'A power outage is already active.') end

    Outage.id = Outage.id + 1
    Outage.state = 'active'
    Outage.location = pickRandomLocation(Config.PowerOutage.locations, Outage.location)
    Outage.claimSrc = nil

    TriggerClientEvent('cm-electrician:client:outageState', -1, true, Outage.location)
    scheduleAutoFix(Outage.id)
    notifyOutageStart()
    for employedSrc in pairs(Sessions) do
        checkOutageAlert(employedSrc, getStatus(employedSrc))
    end
    reply(src, 'Power outage triggered.')
end, false)

-- ---------------------------------------------------------------------------
-- Development-only CM-QA owner contract.
--
-- These exports are intentionally server-side and narrow.  They are not a
-- gameplay/admin API: the caller must be the development-only cm-qa resource,
-- the target must be an online player, and every mutation is restored by the
-- cleanup action.  Physical repair scenarios still enter duty and use the
-- normal beginRepair/completeRepair/cancelRepair network path.
-- ---------------------------------------------------------------------------

local function qaSnapshot(src, expectedCharacterId)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'source_unavailable' end

    local characterId = getCharId(src)
    if not characterId then return false, 'character_not_ready' end
    expectedCharacterId = tonumber(expectedCharacterId)
    if expectedCharacterId and characterId ~= expectedCharacterId then
        return false, 'character_mismatch'
    end

    local session = Sessions[src]
    local status = getStatus(src)
    local repair = session and session.repair
    local activeRepair = nil
    if repair then
        activeRepair = {
            taskType = repair.taskType,
            index = repair.index,
            tokenPresent = repair.token ~= nil,
            startedAt = repair.startedAt,
            earliestFinishAt = repair.earliestFinishAt,
            expiresAt = repair.expiresAt,
            shocked = repair.shockAtMs ~= nil,
        }
    end

    local target = nil
    if session and session.panelTargets and session.panelTargets[1] then
        local point = Config.Panels[session.panelTargets[1]]
        if point then target = { x = point.x, y = point.y, z = point.z } end
    end

    return true, {
        characterId = characterId,
        onShift = session ~= nil,
        level = status.level,
        panels = status.panels,
        plates = status.plates,
        assignedPanels = session and session.panelTargets or {},
        assignedPlates = session and session.plateTargets or {},
        activeRepair = activeRepair,
        repair = activeRepair,
        target = target,
        employment = { x = Config.Employment.coords.x, y = Config.Employment.coords.y, z = Config.Employment.coords.z },
        serviceVehicleActive = jobVehicles[src] ~= nil,
        pendingCash = qaPendingCash(src),
        rewardPerPanel = tonumber(Config.Earnings.perPanel) or 0,
        lastRepairOutcome = session and session.lastRepairOutcome or nil,
        outage = {
            state = Outage.state,
            active = Outage.state ~= 'inactive',
        },
    }
end

local function captureQaFixture(src)
    if qaFixtures[src] then return qaFixtures[src] end
    local session = Sessions[src]
    qaFixtures[src] = {
        level = getMeta(src, 'cmElectricianLevel', 1),
        panels = getMeta(src, 'cmElectricianPanels', 0),
        plates = getMeta(src, 'cmElectricianPlates', 0),
        wasOnShift = session ~= nil,
        charId = session and session.charId or getCharId(src),
        panelTargets = session and copyList(session.panelTargets) or {},
        plateTargets = session and copyList(session.plateTargets) or {},
        qaForceShock = session and session.qaForceShock == true or false,
    }
    return qaFixtures[src]
end

local function restoreQaFixture(src)
    local fixture = qaFixtures[src]
    if not fixture then return true end

    local restored = true
    restored = setMeta(src, 'cmElectricianLevel', fixture.level) and restored
    restored = setMeta(src, 'cmElectricianPanels', fixture.panels) and restored
    restored = setMeta(src, 'cmElectricianPlates', fixture.plates) and restored

    if Sessions[src] then endShift(src, 'qa_cleanup') end
    if fixture.wasOnShift and getCharId(src) == fixture.charId then
        Sessions[src] = {
            src = src,
            charId = fixture.charId,
            startedAt = GetGameTimer(),
            panelTargets = copyList(fixture.panelTargets),
            plateTargets = copyList(fixture.plateTargets),
            repair = nil,
            qaForceShock = fixture.qaForceShock,
        }
        sendAssignments(src, Sessions[src])
        TriggerClientEvent('cm-electrician:client:employedSet', src, true)
    end
    qaFixtures[src] = nil
    return restored
end

local function qaControl(action, data)
    if type(action) ~= 'string' then return false, 'invalid_action' end
    local src = qaSource(data)
    if not src then return false, 'invalid_source' end
    local charId = getCharId(src)
    if not charId then return false, 'character_not_ready' end
    local expectedCharacterId = tonumber(data.expectedCharacterId)
    if expectedCharacterId and charId ~= expectedCharacterId then return false, 'character_mismatch' end

    if action == 'prepare_level' or action == 'set_level' then
        local level = math.floor(tonumber(data.level) or -1)
        if level < 1 or level > 3 then return false, 'invalid_level' end
        captureQaFixture(src)
        if not setMeta(src, 'cmElectricianLevel', level) then return false, 'metadata_write_failed' end
        local session = Sessions[src]
        if session then
            sendAssignments(src, session)
            TriggerClientEvent('cm-electrician:client:status', src, getStatus(src))
        end
        return true
    end

    local session = Sessions[src]
    if action == 'assign_panel' then
        if not session then return false, 'not_on_shift' end
        local index = math.floor(tonumber(data.index) or -1)
        if not Config.Panels[index] then return false, 'invalid_panel' end
        session.panelTargets = { index }
        session.plateTargets = {}
        session.repair = nil
        sendAssignments(src, session)
        return true
    elseif action == 'force_next_shock' then
        if not session then return false, 'not_on_shift' end
        session.qaForceShock = data.enabled == true
        return true
    elseif action == 'cleanup' then
        local restored = restoreQaFixture(src)
        TriggerClientEvent('cm-electrician:client:status', src, getStatus(src))
        return restored, restored and nil or 'metadata_restore_failed'
    end

    return false, 'unsupported_action'
end

exports('QaSnapshot', function(src, expectedCharacterId)
    local allowed, reason = qaInvokerAllowed()
    if not allowed then return false, reason end
    local ok, snapshotOrReason = qaSnapshot(src, expectedCharacterId)
    if not ok then return false, snapshotOrReason end
    return true, snapshotOrReason
end)

exports('QaControl', function(action, data)
    local allowed, reason = qaInvokerAllowed()
    if not allowed then return false, reason end
    return qaControl(action, data)
end)

-- ---------------------------------------------------------------------------
-- Future Job Center contract -- presentation-only static data. No reward,
-- progress mutation or shift-start capability is exposed here.
-- ---------------------------------------------------------------------------

exports('GetJobInfo', function()
    return {
        id = 'electrician',
        label = Config.JobTitle,
        description = Config.Description,
        location = { x = Config.Employment.coords.x, y = Config.Employment.coords.y, z = Config.Employment.coords.z },
        available = true,
    }
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src, fixture in pairs(qaFixtures) do
        setMeta(src, 'cmElectricianLevel', fixture.level)
        setMeta(src, 'cmElectricianPanels', fixture.panels)
        setMeta(src, 'cmElectricianPlates', fixture.plates)
        qaFixtures[src] = nil
    end
    for src in pairs(Sessions) do
        endShift(src, nil)
    end
end)

CreateThread(function()
    math.randomseed(os.time())
    scheduleOutage()
end)
