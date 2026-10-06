local Config = CMRecycling.Config

local PLAYERDATA = 'cm-playerdata'
local VEHICLES = 'cm-vehicles'
local PAYDAY = 'cm-payday'
local INVENTORY = 'cm-inventory'
local HUD = 'cm-hud'

-- Authoritative server-side state
-- Sessions[src] = {
--     src = number,
--     charId = string,
--     truckNetId = number,
--     truckPlate = string,
--     truckEntity = entity,
--     currentStopIndex = number,
--     bundlesCollectedAtStop = number,
--     totalBundlesInTruck = number,
--     maxBundles = number,
--     activeBundleToken = string|nil,
--     allPickupsComplete = boolean,
--     unloadedAtFacility = boolean,
--     sortingInProgress = boolean,
--     activeBatch = table|nil,
--     startedAt = number,
-- }
local Sessions = {}
local jobVehicles = {} -- [src] = { plate = string, netId = number, entity = entity }
local cooldowns = {}   -- [src] = timestamp
local payoutLocks = {} -- [src] = boolean
local tokenSequence = 0

local function dbg(...)
    if Config.Debug then print('[CM-RECYCLING]', ...) end
end

local function notify(src, message, kind)
    if GetResourceState(HUD) == 'started' then
        pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
    else
        TriggerClientEvent('cm-recycling:client:notify', src, message, kind or 'info')
    end
end

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

local function getCharId(src)
    local api = playerData()
    if not api then return nil end
    local ok, result = pcall(function() return api:GetCharacterId(src) end)
    if ok and result and tostring(result) ~= '' then return tostring(result) end
    return nil
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
    local ok, result = pcall(function() return api:SetMetadataDetailed(src, key, value) end)
    return ok and result == true
end

local SCHEMA_STATE = {
    UNINITIALIZED = 'uninitialized',
    INITIALIZING = 'initializing',
    READY = 'ready',
    FAILED = 'failed',
}

local schemaState = SCHEMA_STATE.UNINITIALIZED
local schemaInitError = nil
local schemaInitLock = false
local schemaInitSeq = 0

local function isSchemaReady()
    return schemaState == SCHEMA_STATE.READY
end

local function getSchemaState()
    return schemaState, schemaInitError
end

local function initDatabase()
    if schemaState == SCHEMA_STATE.READY then return true end

    -- Single-flight serialization: if another thread is currently initializing, wait for it
    if schemaInitLock then
        local waitStart = GetGameTimer()
        while schemaInitLock and (GetGameTimer() - waitStart) < 15000 do
            Wait(50)
        end
        if schemaState == SCHEMA_STATE.READY then
            return true
        end
        if schemaInitLock then
            return false, 'init_lock_timeout'
        end
        return schemaState == SCHEMA_STATE.READY, schemaInitError or 'schema_not_ready'
    end

    schemaInitLock = true
    schemaInitSeq = schemaInitSeq + 1
    local mySeq = schemaInitSeq
    schemaState = SCHEMA_STATE.INITIALIZING
    schemaInitError = nil

    local ok, err = pcall(function()
        local startWait = GetGameTimer()
        while GetResourceState('oxmysql') ~= 'started' do
            if (GetGameTimer() - startWait) > 15000 then
                error('oxmysql resource failed to start within 15s timeout')
            end
            Wait(50)
        end

        if MySQL and MySQL.ready then
            if type(MySQL.ready.await) == 'function' then
                MySQL.ready.await()
            elseif type(MySQL.ready) == 'function' then
                local p = promise.new()
                MySQL.ready(function() p:resolve(true) end)
                Citizen.Await(p)
            end
        end

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cm_recycling_operations (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                reference VARCHAR(64) NOT NULL,
                character_id VARCHAR(50) NOT NULL,
                bundles INT NOT NULL DEFAULT 0,
                earnings INT NOT NULL DEFAULT 0,
                status VARCHAR(64) NOT NULL DEFAULT 'pending_payroll_integration',
                created_at_ts BIGINT NOT NULL,
                raw_data LONGTEXT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_recycling_reference (reference),
                INDEX idx_recycling_char (character_id),
                INDEX idx_recycling_status (character_id, status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])
    end)

    if ok then
        schemaState = SCHEMA_STATE.READY
        schemaInitError = nil
        schemaInitLock = false
        dbg('Database table cm_recycling_operations initialized successfully.')
        return true
    else
        local errStr = tostring(err)
        if schemaState ~= SCHEMA_STATE.READY and mySeq >= schemaInitSeq then
            schemaState = SCHEMA_STATE.FAILED
            schemaInitError = errStr
            print('^1[CM-RECYCLING] Failed to initialize cm_recycling_operations table: ' .. errStr .. '^7')
        end
        schemaInitLock = false
        return false, schemaInitError
    end
end

local function awaitSchemaReady(timeoutMs)
    if schemaState == SCHEMA_STATE.READY then return true end

    local maxWait = timeoutMs or 10000

    -- 1. If currently initializing (or locked by another thread), wait for the in-flight attempt to resolve
    if schemaInitLock or schemaState == SCHEMA_STATE.INITIALIZING then
        local started = GetGameTimer()
        while (schemaInitLock or schemaState == SCHEMA_STATE.INITIALIZING) and (GetGameTimer() - started) < maxWait do
            Wait(50)
        end
        if schemaState == SCHEMA_STATE.READY then
            return true
        end
        return false, schemaInitError or (schemaState == SCHEMA_STATE.FAILED and 'schema_init_failed' or 'schema_init_timeout')
    end

    -- 2. If uninitialized, or previously failed and oxmysql is now started, execute serialized initialization
    if schemaState == SCHEMA_STATE.UNINITIALIZED or (schemaState == SCHEMA_STATE.FAILED and GetResourceState('oxmysql') == 'started') then
        local ok, err = initDatabase()
        if ok and schemaState == SCHEMA_STATE.READY then
            return true
        end
        return false, err or schemaInitError or 'schema_init_failed'
    end

    -- 3. Fail closed if not ready and oxmysql is not started
    return false, schemaInitError or 'schema_not_ready'
end

CreateThread(function()
    initDatabase()
end)

local function pruneSettledOperationsIfNeeded(operations, maxAllowedBytes)
    maxAllowedBytes = maxAllowedBytes or 45000
    local encoded = json.encode(operations)
    if not encoded or #encoded <= maxAllowedBytes then
        return operations
    end

    local trimmed = {}
    for ref, op in pairs(operations) do
        local isUnresolved = (op.status == 'pending_payroll_integration')
            or (op.payrollStatus == 'pending_reconciliation')
            or (op.status ~= 'settled' and op.status ~= 'paid')

        if isUnresolved then
            trimmed[ref] = op
        else
            local currentEncoded = json.encode(trimmed)
            if currentEncoded and #currentEncoded < maxAllowedBytes then
                trimmed[ref] = op
            end
        end
    end
    return trimmed
end

local function onCooldown(src, ms)
    local now = GetGameTimer()
    if (cooldowns[src] or 0) > now then return true end
    cooldowns[src] = now + (tonumber(ms) or Config.Security.actionCooldownMs or 1200)
    return false
end

-- ---------------------------------------------------------------------------
-- Vehicle Management (via cm-vehicles)
-- ---------------------------------------------------------------------------

local function vehiclesApi()
    if GetResourceState(VEHICLES) ~= 'started' then return nil end
    return exports[VEHICLES]
end

local function deleteJobVehicle(src)
    local rec = jobVehicles[src]
    if not rec then return end
    jobVehicles[src] = nil

    local api = vehiclesApi()
    if api and rec.plate then
        pcall(function() api:DeleteAdminVehicle(rec.plate) end)
    end
    if rec.entity and DoesEntityExist(rec.entity) then
        DeleteEntity(rec.entity)
    end
end

local function spawnSalvageTruck(src)
    local api = vehiclesApi()
    if not api then
        return false, 'Vehicle system is offline.'
    end

    local spawns = Config.Facility.truckSpawns
    local chosenSpawn = spawns[1]
    for _, spawn in ipairs(spawns) do
        chosenSpawn = spawn
        break
    end

    local ok, result = pcall(function()
        return api:SpawnAdminVehicle(src, Config.Vehicle.model, {
            x = chosenSpawn.x,
            y = chosenSpawn.y,
            z = chosenSpawn.z,
            h = chosenSpawn.w,
        }, {
            placementKind = 'car',
            label = Config.Vehicle.label,
            engineOn = true,
            warp = false,
        })
    end)

    if not ok or type(result) ~= 'table' or result.ok ~= true then
        local err = ok and type(result) == 'table' and result.error or 'vehicle_spawn_rejected'
        print(('[CM-RECYCLING] SpawnAdminVehicle rejected for src %s: %s (cm-vehicles authorizedResources integration required)')
            :format(tostring(src), tostring(err)))
        return false, tostring(err)
    end

    jobVehicles[src] = {
        plate = result.plate,
        netId = result.netId,
        entity = result.entity,
    }

    return true, result
end

-- ---------------------------------------------------------------------------
-- Session Lifecycle & Cleanup
-- ---------------------------------------------------------------------------

local function endShift(src, reason)
    src = tonumber(src)
    if not src then return end

    local session = Sessions[src]
    if not session then return end

    if session.totalBundlesInTruck > 0 and not session.unloadedAtFacility then
        setMeta(src, 'cmRecyclingActiveSession', {
            runRef = session.runRef,
            totalBundlesInTruck = session.totalBundlesInTruck,
            currentStopIndex = session.currentStopIndex,
            allPickupsComplete = session.allPickupsComplete,
        })
        local api = playerData()
        if api then pcall(function() api:Save(src, 'cm-recycling-disconnect') end) end
    elseif session.totalBundlesInTruck == 0 then
        setMeta(src, 'cmRecyclingActiveSession', nil)
    end

    Sessions[src] = nil
    payoutLocks[src] = nil
    cooldowns[src] = nil

    deleteJobVehicle(src)
    TriggerClientEvent('cm-recycling:client:shiftEnded', src, reason or 'shift_ended')
    dbg(('Shift ended for src %s (reason: %s)'):format(src, tostring(reason)))
end

-- ---------------------------------------------------------------------------
-- Shift Start / Stop Handlers
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-recycling:server:startShift', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local ready, err = awaitSchemaReady(10000)
    if not ready then
        dbg(('Worker src %d rejected at startShift: database schema not ready (%s)'):format(src, tostring(err)))
        notify(src, 'Salvage & recycling service unavailable: database ledger is offline. Contact administration.', 'error')
        return
    end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Character identity is not loaded.', 'error')
        return
    end

    -- Prevent multiple active shifts on the same source
    if Sessions[src] then
        notify(src, 'You are already on an active salvage & recycling shift.', 'error')
        return
    end

    -- Prevent multiple active shifts by character across reconnects/sources
    for otherSrc, otherSession in pairs(Sessions) do
        if otherSession.charId == charId then
            notify(src, 'This character already has an active shift.', 'error')
            return
        end
    end

    -- Proximity check to supervisor NPC
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local supCoords = Config.Facility.supervisor.coords
    if #(pCoords - vector3(supCoords.x, supCoords.y, supCoords.z)) > (Config.Security.supervisorDistance or 3.2) then
        notify(src, 'You are too far from the salvage supervisor.', 'error')
        return
    end

    -- Attempt to spawn salvage truck
    local spawned, spawnResult = spawnSalvageTruck(src)
    if not spawned then
        notify(src, 'Salvage truck unavailable: vehicle service authorization required. Contact administration.', 'error')
        return
    end

    local maxBundles = Config.Capacity.maxBundles or 10

    -- Check if character has a durable pending batch awaiting retry
    local restoredBatch = getMeta(src, 'cmRecyclingActiveBatch', nil)
    local hasPendingBatch = type(restoredBatch) == 'table' and restoredBatch.state ~= Config.BatchState.Completed

    -- Check if character has an uncompleted truck load from disconnect
    local restoredSession = getMeta(src, 'cmRecyclingActiveSession', nil)
    local hasActiveSession = (not hasPendingBatch) and type(restoredSession) == 'table' and (tonumber(restoredSession.totalBundlesInTruck) or 0) > 0

    local runRef = hasPendingBatch and (restoredBatch.id or ('RECYCLING-%s-%d'):format(charId, os.time()))
        or (hasActiveSession and restoredSession.runRef or ('RECYCLING-%s-%d'):format(charId, os.time()))

    local restoredBundles = hasPendingBatch and (restoredBatch.bundles or maxBundles)
        or (hasActiveSession and (tonumber(restoredSession.totalBundlesInTruck) or 0) or 0)

    local restoredStopIndex = hasActiveSession and (tonumber(restoredSession.currentStopIndex) or 1) or 1
    local restoredPickupsComplete = hasPendingBatch or (hasActiveSession and restoredSession.allPickupsComplete == true) or false

    -- Initialize authoritative session
    Sessions[src] = {
        src = src,
        charId = charId,
        runRef = runRef,
        truckNetId = spawnResult.netId,
        truckPlate = spawnResult.plate,
        truckEntity = spawnResult.entity,
        currentStopIndex = restoredStopIndex,
        bundlesCollectedAtStop = 0,
        totalBundlesInTruck = restoredBundles,
        maxBundles = maxBundles,
        activeBundleToken = nil,
        allPickupsComplete = restoredPickupsComplete,
        unloadedAtFacility = hasPendingBatch,
        sortingInProgress = false,
        activeBatch = hasPendingBatch and restoredBatch or nil,
        startedAt = GetGameTimer(),
    }

    if not hasPendingBatch then
        setMeta(src, 'cmRecyclingActiveSession', {
            runRef = runRef,
            totalBundlesInTruck = restoredBundles,
            currentStopIndex = restoredStopIndex,
            allPickupsComplete = restoredPickupsComplete,
        })
        local api = playerData()
        if api then pcall(function() api:Save(src, 'cm-recycling-start') end) end
    end

    local currentStop = Config.Route[restoredStopIndex] or Config.Route[1]
    TriggerClientEvent('cm-recycling:client:shiftStarted', src, {
        truckNetId = spawnResult.netId,
        truckPlate = spawnResult.plate,
        stop = currentStop,
        stopIndex = restoredStopIndex,
        totalStops = #Config.Route,
        bundlesInTruck = Sessions[src].totalBundlesInTruck,
        maxBundles = maxBundles,
        bundlesPerStop = Config.Capacity.bundlesPerStop or 2,
        hasPendingBatch = hasPendingBatch,
    })

    if hasPendingBatch then
        notify(src, 'Restored uncompleted batch. Proceed to Rogers Salvage sorting station to process.', 'info')
    elseif hasActiveSession then
        notify(src, ('Resumed salvage shift with %d bundles in truck bed. Proceed to collection or facility unload bay.'):format(restoredBundles), 'info')
    else
        notify(src, 'Salvage shift started (payout stored in durable ledger; cash cannot currently be collected in-game). Recover recyclable material and return for processing.', 'info')
    end
end)

RegisterNetEvent('cm-recycling:server:cancelShift', function()
    local src = source
    if onCooldown(src, 1000) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You do not have an active salvage shift.', 'info')
        return
    end

    -- Unpaid or Active Run Protection: Do not silently discard uncollected or unprocessed loads
    if session.totalBundlesInTruck > 0 and not session.unloadedAtFacility then
        notify(src, ('Cannot clock out: your truck has %d bundles of unprocessed salvage. Return to the facility to unload.'):format(session.totalBundlesInTruck), 'error')
        return
    end

    if session.activeBatch and session.activeBatch.state ~= Config.BatchState.Completed then
        notify(src, 'Cannot clock out: you have an active uncompleted salvage batch. Finish processing at Rogers Salvage.', 'error')
        return
    end

    endShift(src, 'manual_cancelled')
    notify(src, 'Salvage shift completed. Truck returned to Rogers Salvage depot.', 'info')
end)

-- ---------------------------------------------------------------------------
-- Salvage Collection & Loading Events
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-recycling:server:collectBundle', function()
    local src = source
    if onCooldown(src, 1200) then return end

    if not isSchemaReady() then
        notify(src, 'Salvage collection unavailable: database ledger is offline. Action aborted.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'You are not on an active shift.', 'error')
        return
    end

    if session.activeBundleToken ~= nil then
        notify(src, 'You are already carrying a salvage bundle.', 'error')
        return
    end

    if session.totalBundlesInTruck >= session.maxBundles then
        notify(src, 'Truck bed is at maximum capacity. Return to the facility.', 'info')
        return
    end

    local stop = Config.Route[session.currentStopIndex]
    if not stop then
        notify(src, 'Invalid salvage pickup destination.', 'error')
        return
    end

    -- Proximity validation: Player ped must be near the salvageCoords
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local distToSalvage = #(pCoords - stop.salvageCoords)

    if distToSalvage > (Config.Security.salvageDistance or 3.2) then
        notify(src, 'You are too far from the salvage pile.', 'error')
        return
    end

    -- Proximity to assigned truck validation
    local truck = session.truckEntity
    if not truck or not DoesEntityExist(truck) then
        notify(src, 'Assigned salvage truck is missing.', 'error')
        return
    end
    if #(pCoords - GetEntityCoords(truck)) > (Config.Security.truckMaxDistance or 45.0) then
        notify(src, 'Your salvage truck is parked too far away.', 'error')
        return
    end

    -- Issue single-use token with sequence counter
    tokenSequence = tokenSequence + 1
    local token = ('recycling_%s:%d:%d:%d'):format(session.charId, session.currentStopIndex, tokenSequence, GetGameTimer())
    session.activeBundleToken = token

    TriggerClientEvent('cm-recycling:client:bundleCollected', src, {
        token = token,
        stopIndex = session.currentStopIndex,
    })
    dbg(('Issued salvage token %s for src %s'):format(token, src))
end)

RegisterNetEvent('cm-recycling:server:loadBundleIntoTruck', function(token)
    local src = source
    if onCooldown(src, 1200) then return end

    if not isSchemaReady() then
        notify(src, 'Salvage loading unavailable: database ledger is offline. Action aborted.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'You are not on an active shift.', 'error')
        return
    end

    -- Replay / Token Validation
    if not token or type(token) ~= 'string' or token ~= session.activeBundleToken then
        notify(src, 'Invalid or expired salvage token.', 'error')
        dbg(('Invalid load token attempt from src %s: expected %s, got %s')
            :format(src, tostring(session.activeBundleToken), tostring(token)))
        return
    end

    local truck = session.truckEntity
    if not truck or not DoesEntityExist(truck) then
        notify(src, 'Assigned salvage truck is missing.', 'error')
        return
    end

    -- Proximity validation: Player ped must be near the rear bed of the truck
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local truckCoords = GetEntityCoords(truck)
    local fwd = GetEntityForwardVector(truck)
    local bedOffset = Config.Vehicle.truckBedOffset or vector3(0.0, -2.4, 0.0)
    local bedCoords = truckCoords + (fwd * bedOffset.y)
    local distToBed = #(pCoords - bedCoords)

    if distToBed > (Config.Security.truckBedDistance or 3.8) and #(pCoords - truckCoords) > 4.5 then
        notify(src, 'You must be at the bed of your salvage truck to secure the load.', 'error')
        return
    end

    -- Invalidate token immediately
    session.activeBundleToken = nil

    -- Update counts
    session.bundlesCollectedAtStop = session.bundlesCollectedAtStop + 1
    session.totalBundlesInTruck = session.totalBundlesInTruck + 1

    local stopMax = Config.Capacity.bundlesPerStop or 2
    local stopComplete = session.bundlesCollectedAtStop >= stopMax
    local isLastStop = session.currentStopIndex >= #Config.Route

    if stopComplete then
        session.bundlesCollectedAtStop = 0
        if not isLastStop then
            session.currentStopIndex = session.currentStopIndex + 1
        else
            session.allPickupsComplete = true
        end
    end

    setMeta(src, 'cmRecyclingActiveSession', {
        runRef = session.runRef,
        totalBundlesInTruck = session.totalBundlesInTruck,
        currentStopIndex = session.currentStopIndex,
        allPickupsComplete = session.allPickupsComplete,
    })

    local nextStop = (not session.allPickupsComplete) and Config.Route[session.currentStopIndex] or nil

    TriggerClientEvent('cm-recycling:client:bundleLoaded', src, {
        totalBundlesInTruck = session.totalBundlesInTruck,
        maxBundles = session.maxBundles,
        stopComplete = stopComplete,
        allPickupsComplete = session.allPickupsComplete,
        nextStop = nextStop,
        stopIndex = session.currentStopIndex,
        totalStops = #Config.Route,
    })

    if session.allPickupsComplete or session.totalBundlesInTruck >= session.maxBundles then
        notify(src, 'Truck bed loaded to capacity! Return to Rogers Salvage to unload into the intake hopper.', 'info')
    elseif stopComplete then
        notify(src, ('Site cleared! Proceed to salvage location %d of %d.'):format(session.currentStopIndex, #Config.Route), 'success')
    else
        notify(src, ('Salvage secured in truck bed (%d/%d for this site).'):format(session.bundlesCollectedAtStop, stopMax), 'success')
    end
end)

-- ---------------------------------------------------------------------------
-- Facility Unload & Processing Events
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-recycling:server:unloadTruck', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local ready, err = awaitSchemaReady(10000)
    if not ready then
        dbg(('Cannot unload salvage truck: database not ready for src %s (%s)'):format(src, tostring(err)))
        notify(src, 'Salvage unloading unavailable: database ledger is offline. Please wait or contact staff.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'You are not on an active shift.', 'error')
        return
    end

    if session.unloadedAtFacility then
        notify(src, 'Salvage has already been unloaded. Proceed to the sorting station.', 'info')
        return
    end

    if session.totalBundlesInTruck <= 0 then
        notify(src, 'You have no salvage in your truck bed to unload.', 'error')
        return
    end

    local truck = session.truckEntity
    if not truck or not DoesEntityExist(truck) then
        notify(src, 'Assigned salvage truck is missing.', 'error')
        return
    end

    -- Proximity check to Facility Unload Bay
    local tCoords = GetEntityCoords(truck)
    local bayCoords = Config.Facility.unloadBay.coords
    if #(tCoords - bayCoords) > (Config.Security.facilityUnloadDistance or 8.5) then
        notify(src, 'Your truck must be parked in the salvage unloading bay.', 'error')
        return
    end

    session.unloadedAtFacility = true

    -- Initialize durable batch state: 'ready' with stable timestamped reference
    local batchId = session.runRef or ('RECYCLING-%s-%d'):format(session.charId, os.time())
    local totalStops = #Config.Route
    local stopsPay = totalStops * (Config.Earnings.perStop or 1200)
    local procBonus = Config.Earnings.processingBonus or 2400
    local totalCash = stopsPay + procBonus

    session.activeBatch = {
        id = batchId,
        reference = batchId,
        state = Config.BatchState.Ready,
        bundles = session.totalBundlesInTruck,
        materialsGranted = false,
        payrollAccepted = false,
        cashReward = totalCash,
        createdAt = os.time(),
    }

    -- Clear active truck session and persist active batch to character metadata
    setMeta(src, 'cmRecyclingActiveSession', nil)
    setMeta(src, 'cmRecyclingActiveBatch', session.activeBatch)
    local api = playerData()
    if api then pcall(function() api:Save(src, 'cm-recycling-active-batch') end) end

    TriggerClientEvent('cm-recycling:client:truckUnloaded', src, {
        unloadedBundles = session.totalBundlesInTruck,
        sortingCoords = Config.Facility.sortingStation.coords,
    })

    notify(src, 'Salvage unloaded into intake hopper. Proceed to Sorting Station to process the batch.', 'success')
end)

RegisterNetEvent('cm-recycling:server:processMaterials', function()
    local src = source
    if onCooldown(src, 3000) then return end

    local ready, err = awaitSchemaReady(10000)
    if not ready then
        dbg(('Cannot process salvage materials: database not ready for src %s (%s)'):format(src, tostring(err)))
        notify(src, 'Material processing unavailable: database ledger is offline. Please wait or contact staff.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'You are not on an active shift.', 'error')
        return
    end

    if not session.unloadedAtFacility or not session.activeBatch then
        notify(src, 'You must unload your truck at the bay before sorting materials.', 'error')
        return
    end

    -- Idempotency lock
    if payoutLocks[src] or session.sortingInProgress then
        notify(src, 'Material sorting is already in progress.', 'error')
        return
    end

    local batch = session.activeBatch
    if batch.state == Config.BatchState.Completed then
        notify(src, 'This batch has already been fully processed and its payout recorded in the durable ledger.', 'info')
        return
    end

    -- Proximity validation: Player ped must be at the Sorting Station
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local stationCoords = Config.Facility.sortingStation.coords
    if #(pCoords - stationCoords) > (Config.Security.sortingStationDistance or 3.0) then
        notify(src, 'You must be standing at the Material Sorting Station.', 'error')
        return
    end

    payoutLocks[src] = true
    session.sortingInProgress = true

    local duration = Config.Facility.sortingStation.processDurationMs or 7000
    TriggerClientEvent('cm-recycling:client:startSorting', src, {
        duration = duration,
    })

    SetTimeout(duration, function()
        if not Sessions[src] or Sessions[src] ~= session then
            payoutLocks[src] = nil
            return
        end

        local currentBatch = session.activeBatch
        if not currentBatch or currentBatch.state == Config.BatchState.Completed then
            payoutLocks[src] = nil
            session.sortingInProgress = false
            return
        end

        -- =====================================================================
        -- STEP 1: Material Grant Phase (Retry-Safe)
        -- If materials were already granted in an earlier attempt, DO NOT RE-GRANT!
        -- =====================================================================
        local matsGrantedList = {}
        local materialsReady = currentBatch.materialsGranted == true

        if not materialsReady then
            if Config.Earnings.materialsEnabled == true and Config.Earnings.materials then
                local invReady = GetResourceState(INVENTORY) == 'started'
                if invReady then
                    -- Verify inventory capacity before granting any material
                    local canCarryAll = true
                    for _, mat in ipairs(Config.Earnings.materials) do
                        local canCarry = false
                        pcall(function() canCarry = exports[INVENTORY]:CanCarryItem(src, mat.item, mat.amount) end)
                        if not canCarry then
                            canCarryAll = false
                            break
                        end
                    end

                    if not canCarryAll then
                        -- Inventory full: fail closed, preserve batch state as 'ready', retryable later
                        payoutLocks[src] = nil
                        session.sortingInProgress = false
                        notify(src, 'Inventory full: cannot carry recyclable materials. Free space and retry at sorting table.', 'error')
                        TriggerClientEvent('cm-recycling:client:processingFailed', src, {
                            reason = 'inventory_full',
                            earnings = currentBatch.cashReward,
                        })
                        return
                    end

                    -- Add materials to inventory
                    for _, mat in ipairs(Config.Earnings.materials) do
                        local added = false
                        pcall(function()
                            added = exports[INVENTORY]:AddItem(src, mat.item, mat.amount, nil, 'recycling_material_yield')
                        end)
                        if added then
                            matsGrantedList[#matsGrantedList + 1] = ('%dx %s'):format(mat.amount, mat.label or mat.item)
                        end
                    end
                end
            end

            -- Advance state to materials_granted
            currentBatch.materialsGranted = true
            currentBatch.state = Config.BatchState.MaterialsGranted
            setMeta(src, 'cmRecyclingActiveBatch', currentBatch)
            local api = playerData()
            if api then pcall(function() api:Save(src, 'cm-recycling-mats') end) end
        end

        -- =====================================================================
        -- STEP 2: Durable Persistence & Deduplication Phase
        -- Check database table cm_recycling_operations and metadata for existing record
        -- =====================================================================
        local batchRef = currentBatch.id or currentBatch.reference or ('RECYCLING-%s-%d'):format(session.charId, os.time())
        local totalCash = currentBatch.cashReward or (Config.Earnings.perStop * #Config.Route + Config.Earnings.processingBonus)

        local ready, readyErr = awaitSchemaReady(5000)
        if not ready then
            payoutLocks[src] = nil
            session.sortingInProgress = false
            setMeta(src, 'cmRecyclingActiveBatch', currentBatch)
            dbg(('Failed to persist recycling operation: database not ready for src %s (batch %s): %s'):format(src, batchRef, tostring(readyErr)))
            notify(src, 'Database ledger is offline. Your salvage batch has been preserved. Please retry sorting once the service reconnects.', 'error')
            return
        end

        local dbExisting = nil
        local okDb, row = pcall(function()
            return MySQL.single.await('SELECT reference, bundles, earnings, status FROM cm_recycling_operations WHERE reference = ? LIMIT 1', { batchRef })
        end)
        if not okDb then
            payoutLocks[src] = nil
            session.sortingInProgress = false
            setMeta(src, 'cmRecyclingActiveBatch', currentBatch)
            dbg(('Failed to query cm_recycling_operations for src %s (ref %s): %s'):format(src, batchRef, tostring(row)))
            notify(src, 'Database ledger query failed. Your salvage batch has been preserved. Please retry sorting.', 'error')
            return
        end
        if row then
            dbExisting = row
        end

        local operations = getMeta(src, 'cmRecyclingOperations', {})
        if type(operations) ~= 'table' then operations = {} end
        local metaExisting = operations[batchRef]

        local alreadyRecorded = (dbExisting ~= nil) or (metaExisting ~= nil)

        if alreadyRecorded then
            local existingBundles = dbExisting and tonumber(dbExisting.bundles) or (metaExisting and tonumber(metaExisting.bundles))
            local existingEarnings = dbExisting and tonumber(dbExisting.earnings) or (metaExisting and tonumber(metaExisting.earnings))

            if existingBundles == currentBatch.bundles and existingEarnings == totalCash then
                dbg(('Deduplication: Recycling operation %s already recorded for char %s, idempotent replay confirmed'):format(batchRef, session.charId))
                payoutLocks[src] = nil
                session.sortingInProgress = false

                -- Mark batch completed
                currentBatch.payrollAccepted = false
                currentBatch.payrollStatus = 'pending_reconciliation'
                currentBatch.state = Config.BatchState.Completed

                -- Reset session for next run
                session.bundlesCollectedAtStop = 0
                session.totalBundlesInTruck = 0
                session.currentStopIndex = 1
                session.allPickupsComplete = false
                session.unloadedAtFacility = false
                session.activeBatch = nil
                session.activeBundleToken = nil
                session.runRef = ('RECYCLING-%s-%d'):format(session.charId, os.time())

                -- Clear active batch only after confirming durable match
                setMeta(src, 'cmRecyclingActiveBatch', nil)
                setMeta(src, 'cmRecyclingActiveSession', nil)
                local api = playerData()
                if api then pcall(function() api:Save(src, 'cm-recycling-dedup') end) end

                local matSummary = #matsGrantedList > 0 and (' + Materials: %s'):format(table.concat(matsGrantedList, ', ')) or ''
                notify(src, ('Processing complete [Batch: %s] — $%d payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration)%s'):format(batchRef, totalCash, matSummary), 'info')

                TriggerClientEvent('cm-recycling:client:processingComplete', src, {
                    stop = Config.Route[1],
                    stopIndex = 1,
                    totalStops = #Config.Route,
                    earnings = totalCash,
                    materials = matsGrantedList,
                    batchId = batchRef,
                })
                return
            else
                dbg(('Conflict: Recycling operation %s amounts do not match existing record'):format(batchRef))
                payoutLocks[src] = nil
                session.sortingInProgress = false
                notify(src, 'Operation conflict detected. Batch preserved for review.', 'error')
                return
            end
        end

        local okInsert, insertErr = pcall(function()
            return MySQL.insert.await([[
                INSERT INTO cm_recycling_operations
                    (reference, character_id, bundles, earnings, status, created_at_ts, raw_data)
                VALUES (?, ?, ?, ?, 'pending_payroll_integration', ?, ?)
            ]], {
                batchRef,
                tostring(session.charId),
                currentBatch.bundles,
                totalCash,
                os.time(),
                json.encode({
                    reference = batchRef,
                    charId = session.charId,
                    bundles = currentBatch.bundles,
                    earnings = totalCash,
                    materials = matsGrantedList,
                    createdAt = os.time(),
                    status = 'pending_payroll_integration',
                    payrollStatus = 'pending_reconciliation',
                })
            })
        end)

        if not okInsert then
            payoutLocks[src] = nil
            session.sortingInProgress = false
            -- Preserve active batch so it can be retried without losing salvage
            setMeta(src, 'cmRecyclingActiveBatch', currentBatch)
            dbg(('Failed to persist recycling operation to SQL for src %s (ref %s): %s'):format(src, batchRef, tostring(insertErr)))
            notify(src, 'Failed to store recycling payout in durable ledger. Your salvage batch has been preserved. Please retry sorting.', 'error')
            return
        end

        operations[batchRef] = {
            reference = batchRef,
            charId = session.charId,
            bundles = currentBatch.bundles,
            earnings = totalCash,
            createdAt = os.time(),
            status = 'pending_payroll_integration',
            payrollStatus = 'pending_reconciliation',
        }

        -- Prune settled records only; unresolved records are NEVER pruned
        operations = pruneSettledOperationsIfNeeded(operations, 45000)

        -- Re-derive totals from operations to prevent drift or desync
        local derivedPending = 0
        local derivedColls = 0
        local derivedRuns = 0
        for _, op in pairs(operations) do
            if type(op) == 'table' then
                if op.status == 'pending_payroll_integration' or op.payrollStatus == 'pending_reconciliation' then
                    derivedPending = derivedPending + (tonumber(op.earnings) or 0)
                end
                derivedColls = derivedColls + (tonumber(op.bundles) or 0)
                derivedRuns = derivedRuns + 1
            end
        end

        local okOps = setMeta(src, 'cmRecyclingOperations', operations)
        local okPending = setMeta(src, 'cmRecyclingPendingPayout', derivedPending)
        local okColls = setMeta(src, 'cmRecyclingCollections', derivedColls)
        local okRuns = setMeta(src, 'cmRecyclingRuns', derivedRuns)
        local okBatch = setMeta(src, 'cmRecyclingActiveBatch', nil)
        local okSession = setMeta(src, 'cmRecyclingActiveSession', nil)

        local api = playerData()
        local okSave = false
        if api then
            local ok, res = pcall(function() return api:Save(src, 'cm-recycling-complete') end)
            okSave = ok and res == true
        end

        if not okOps or not okPending or not okSave then
            payoutLocks[src] = nil
            session.sortingInProgress = false
            -- Restore active batch on failure so player does not lose batch
            setMeta(src, 'cmRecyclingActiveBatch', currentBatch)
            dbg(('Failed to persist recycling settlement to metadata for src %s (batch %s)'):format(src, batchRef))
            notify(src, 'Failed to store recycling payout in durable ledger. Please retry sorting.', 'error')
            return
        end

        payoutLocks[src] = nil
        session.sortingInProgress = false

        -- Mark batch completed
        currentBatch.payrollAccepted = false
        currentBatch.payrollStatus = 'pending_reconciliation'
        currentBatch.state = Config.BatchState.Completed

        -- Reset session for next run
        session.bundlesCollectedAtStop = 0
        session.totalBundlesInTruck = 0
        session.currentStopIndex = 1
        session.allPickupsComplete = false
        session.unloadedAtFacility = false
        session.activeBatch = nil
        session.activeBundleToken = nil
        session.runRef = ('RECYCLING-%s-%d'):format(session.charId, os.time())

        local matSummary = #matsGrantedList > 0 and (' + Materials: %s'):format(table.concat(matsGrantedList, ', ')) or ''
        notify(src, ('Processing complete [Batch: %s] — $%d payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration)%s'):format(batchRef, totalCash, matSummary), 'info')
        dbg(('Stored $%d pending payout for src %s (batch %s)'):format(totalCash, src, batchRef))

        TriggerClientEvent('cm-recycling:client:processingComplete', src, {
            stop = Config.Route[1],
            stopIndex = 1,
            totalStops = #Config.Route,
            earnings = totalCash,
            materials = matsGrantedList,
            batchId = batchRef,
        })
    end)
end)

-- ---------------------------------------------------------------------------
-- Disconnect, Death & Unload Handlers
-- ---------------------------------------------------------------------------

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    src = tonumber(src)
    if not src then return end
    CreateThread(function()
        awaitSchemaReady(5000)
        local pendingCash = math.max(0, math.floor(tonumber(getMeta(src, 'cmRecyclingPendingPayout', 0)) or 0))
        if pendingCash > 0 then
            notify(src, ('You have $%d in earned recycling payouts stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(pendingCash), 'info')
        end

        local activeBatch = getMeta(src, 'cmRecyclingActiveBatch', nil)
        if type(activeBatch) == 'table' and activeBatch.state ~= Config.BatchState.Completed then
            notify(src, ('Notice: You have an unprocessed salvage batch (%d bundles) waiting at the Rogers Salvage sorting station.'):format(activeBatch.bundles or 0), 'info')
        end

        local activeSession = getMeta(src, 'cmRecyclingActiveSession', nil)
        if type(activeSession) == 'table' and (tonumber(activeSession.totalBundlesInTruck) or 0) > 0 then
            notify(src, ('Notice: You have an active salvage truck load (%d bundles) waiting to be unloaded at Rogers Salvage.'):format(tonumber(activeSession.totalBundlesInTruck) or 0), 'info')
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Sessions[src] then
        endShift(src, 'player_dropped')
    end
end)

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    src = tonumber(src)
    if src and Sessions[src] then
        endShift(src, 'character_unloaded')
    end
end)

AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, dead)
    if dead ~= true then return end
    src = tonumber(src)
    if src and Sessions[src] then
        endShift(src, 'player_died')
        notify(src, 'Salvage shift cancelled due to incapacitation.', 'error')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, session in pairs(Sessions) do
        if session.totalBundlesInTruck > 0 and not session.unloadedAtFacility then
            setMeta(src, 'cmRecyclingActiveSession', {
                runRef = session.runRef,
                totalBundlesInTruck = session.totalBundlesInTruck,
                currentStopIndex = session.currentStopIndex,
                allPickupsComplete = session.allPickupsComplete,
            })
            local api = playerData()
            if api then pcall(function() api:Save(src, 'cm-recycling-stop') end) end
        end
        deleteJobVehicle(src)
    end
    Sessions = {}
    jobVehicles = {}
end)

-- ---------------------------------------------------------------------------
-- Public Exports
-- ---------------------------------------------------------------------------

exports('IsOnShift', function(src)
    src = tonumber(src)
    return (src and Sessions[src] ~= nil) or false
end)

exports('GetShiftData', function(src)
    src = tonumber(src)
    local s = src and Sessions[src]
    if not s then return nil end
    return {
        charId = s.charId,
        currentStopIndex = s.currentStopIndex,
        bundlesCollectedAtStop = s.bundlesCollectedAtStop,
        totalBundlesInTruck = s.totalBundlesInTruck,
        allPickupsComplete = s.allPickupsComplete,
        unloadedAtFacility = s.unloadedAtFacility,
        activeBatchState = s.activeBatch and s.activeBatch.state or nil,
        truckPlate = s.truckPlate,
        truckNetId = s.truckNetId,
    }
end)

exports('IsSchemaReady', function()
    return isSchemaReady()
end)

exports('GetSchemaState', function()
    return getSchemaState()
end)

exports('AwaitSchemaReady', function(timeoutMs)
    return awaitSchemaReady(timeoutMs)
end)


