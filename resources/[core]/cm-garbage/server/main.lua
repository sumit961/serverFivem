local Config = CMGarbage.Config

local PLAYERDATA = 'cm-playerdata'
local VEHICLES = 'cm-vehicles'
local PAYDAY = 'cm-payday'
local HUD = 'cm-hud'

-- Authoritative server-side state
-- Sessions[src] = {
--     src = number,
--     charId = string,
--     truckNetId = number,
--     truckPlate = string,
--     truckEntity = entity,
--     currentStopIndex = number,
--     stopBagsCollected = number,
--     totalBagsInTruck = number,
--     activeBagToken = string|nil,
--     unloading = boolean,
--     startedAt = number,
-- }
local Sessions = {}
local jobVehicles = {} -- [src] = { plate = string, netId = number, entity = entity }
local cooldowns = {}   -- [src] = timestamp
local payoutLocks = {} -- [src] = boolean
local tokenSequence = 0

local function dbg(...)
    if Config.Debug then print('[CM-GARBAGE]', ...) end
end

local function notify(src, message, kind)
    if GetResourceState(HUD) == 'started' then
        pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
    else
        TriggerClientEvent('cm-garbage:client:notify', src, message, kind or 'info')
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
            CREATE TABLE IF NOT EXISTS cm_garbage_operations (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                reference VARCHAR(64) NOT NULL,
                character_id VARCHAR(50) NOT NULL,
                bags INT NOT NULL DEFAULT 0,
                earnings INT NOT NULL DEFAULT 0,
                status VARCHAR(64) NOT NULL DEFAULT 'pending_payroll_integration',
                created_at_ts BIGINT NOT NULL,
                raw_data LONGTEXT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_garbage_reference (reference),
                INDEX idx_garbage_char (character_id),
                INDEX idx_garbage_status (character_id, status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])
    end)

    if ok then
        schemaState = SCHEMA_STATE.READY
        schemaInitError = nil
        schemaInitLock = false
        dbg('Database table cm_garbage_operations initialized successfully.')
        return true
    else
        local errStr = tostring(err)
        if schemaState ~= SCHEMA_STATE.READY and mySeq >= schemaInitSeq then
            schemaState = SCHEMA_STATE.FAILED
            schemaInitError = errStr
            print('^1[CM-GARBAGE] Failed to initialize cm_garbage_operations table: ' .. errStr .. '^7')
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

local function spawnTruck(src)
    local api = vehiclesApi()
    if not api then
        return false, 'Vehicle system is offline.'
    end

    local spawns = Config.Depot.truckSpawns
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
        print(('[CM-GARBAGE] SpawnAdminVehicle rejected for src %s: %s (cm-vehicles authorizedResources integration required)')
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

    if session.totalBagsInTruck > 0 then
        setMeta(src, 'cmGarbageActiveSession', {
            runRef = session.runRef,
            totalBagsInTruck = session.totalBagsInTruck,
            currentStopIndex = session.currentStopIndex,
        })
        local api = playerData()
        if api then pcall(function() api:Save(src, 'cm-garbage-disconnect') end) end
    end

    Sessions[src] = nil
    payoutLocks[src] = nil
    cooldowns[src] = nil

    deleteJobVehicle(src)
    TriggerClientEvent('cm-garbage:client:shiftEnded', src, reason or 'shift_ended')
    dbg(('Shift ended for src %s (reason: %s)'):format(src, tostring(reason)))
end

-- ---------------------------------------------------------------------------
-- Shift Start / Stop Handlers
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-garbage:server:startShift', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local ready, err = awaitSchemaReady(10000)
    if not ready then
        dbg(('Worker src %d rejected at startShift: database schema not ready (%s)'):format(src, tostring(err)))
        notify(src, 'Sanitation service unavailable: database ledger is offline. Contact administration.', 'error')
        return
    end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Character identity is not loaded.', 'error')
        return
    end

    -- Prevent multiple active shifts by source
    if Sessions[src] then
        notify(src, 'You already have an active shift.', 'error')
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
    local npcCoords = Config.Depot.npc.coords
    if #(pCoords - vector3(npcCoords.x, npcCoords.y, npcCoords.z)) > (Config.Security.foremanDistance or 3.5) then
        notify(src, 'You are too far from the sanitation supervisor.', 'error')
        return
    end

    -- Attempt to spawn truck via cm-vehicles
    local spawned, spawnResult = spawnTruck(src)
    if not spawned then
        notify(src, 'Sanitation truck unavailable: vehicle service authorization required. Contact administration.', 'error')
        return
    end

    local restoredSession = getMeta(src, 'cmGarbageActiveSession', nil)
    local hasActiveSession = type(restoredSession) == 'table' and (tonumber(restoredSession.totalBagsInTruck) or 0) > 0
    local runRef = hasActiveSession and restoredSession.runRef or ('GARBAGE-%s-%d'):format(charId, os.time())
    local restoredBags = hasActiveSession and (tonumber(restoredSession.totalBagsInTruck) or 0) or 0
    local restoredStopIndex = hasActiveSession and (tonumber(restoredSession.currentStopIndex) or 1) or 1

    -- Initialize authoritative session
    Sessions[src] = {
        src = src,
        charId = charId,
        runRef = runRef,
        truckNetId = spawnResult.netId,
        truckPlate = spawnResult.plate,
        truckEntity = spawnResult.entity,
        currentStopIndex = restoredStopIndex,
        stopBagsCollected = 0,
        totalBagsInTruck = restoredBags,
        activeBagToken = nil,
        unloading = false,
        startedAt = GetGameTimer(),
    }

    setMeta(src, 'cmGarbageActiveSession', {
        runRef = runRef,
        totalBagsInTruck = restoredBags,
        currentStopIndex = restoredStopIndex,
    })
    local api = playerData()
    if api then pcall(function() api:Save(src, 'cm-garbage-start') end) end

    local initialStop = Config.Route[restoredStopIndex] or Config.Route[1]
    TriggerClientEvent('cm-garbage:client:shiftStarted', src, {
        truckNetId = spawnResult.netId,
        truckPlate = spawnResult.plate,
        stop = initialStop,
        stopIndex = restoredStopIndex,
        totalStops = #Config.Route,
        bagsCollected = 0,
        bagsPerStop = initialStop.bagsRequired or Config.Capacity.bagsPerStop,
        maxCapacity = Config.Capacity.maxBags,
    })

    if hasActiveSession then
        notify(src, ('Resumed sanitation shift with %d bags in compactor. Proceed to collection or depot tipping pit.'):format(restoredBags), 'info')
    else
        notify(src, 'Shift started (payout stored in durable ledger; cash cannot currently be collected in-game). Collect curbside bins and fill your truck compactor.', 'info')
    end
end)

RegisterNetEvent('cm-garbage:server:cancelShift', function()
    local src = source
    if onCooldown(src, 1000) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You do not have an active shift.', 'info')
        return
    end

    -- Unpaid Load Protection: Refuse clock-out if truck contains an unpaid load
    if session.totalBagsInTruck > 0 then
        notify(src, ('Cannot clock out: your truck has an unpaid load of %d bags. Please empty your truck at the depot tipping pit before clocking out.'):format(session.totalBagsInTruck), 'error')
        return
    end

    endShift(src, 'manual_cancelled')
    notify(src, 'Sanitation shift completed. Truck returned to depot.', 'info')
end)

-- ---------------------------------------------------------------------------
-- Collection Events (Pickup & Deposit)
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-garbage:server:pickupBag', function()
    local src = source
    if onCooldown(src, 1500) then return end

    if not isSchemaReady() then
        notify(src, 'Sanitation service unavailable: database ledger is offline. Action aborted.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'You are not on an active shift.', 'error')
        return
    end

    if session.activeBagToken ~= nil then
        notify(src, 'You are already carrying a rubbish bag.', 'error')
        return
    end

    if session.totalBagsInTruck >= Config.Capacity.maxBags then
        notify(src, 'Truck compactor is full! Return to the depot tipping pit.', 'error')
        return
    end

    local stop = Config.Route[session.currentStopIndex]
    if not stop then
        notify(src, 'No active route stop.', 'error')
        return
    end

    if session.stopBagsCollected >= (stop.bagsRequired or Config.Capacity.bagsPerStop) then
        notify(src, 'All rubbish at this stop has been collected. Proceed to next stop.', 'info')
        return
    end

    -- Proximity validation: Player ped must be near the stop's designated binCoords
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local distToBin = #(pCoords - stop.binCoords)
    if distToBin > (Config.Security.binDistance or 3.5) then
        notify(src, 'You are too far from the rubbish bin.', 'error')
        return
    end

    -- Assigned truck validation: Truck must exist and be in the working vicinity
    local truck = session.truckEntity
    if not truck or not DoesEntityExist(truck) then
        notify(src, 'Assigned sanitation truck is missing.', 'error')
        return
    end
    local distToTruck = #(pCoords - GetEntityCoords(truck))
    if distToTruck > (Config.Security.truckMaxDistance or 45.0) then
        notify(src, 'Your assigned truck is too far from this collection stop.', 'error')
        return
    end

    -- Issue single-use token with sequence counter
    tokenSequence = tokenSequence + 1
    local token = ('%s:%d:%d:%d'):format(session.charId, session.currentStopIndex, tokenSequence, GetGameTimer())
    session.activeBagToken = token

    TriggerClientEvent('cm-garbage:client:bagAttached', src, {
        token = token,
        stopIndex = session.currentStopIndex,
    })
    dbg(('Issued pickup token %s for src %s'):format(token, src))
end)

RegisterNetEvent('cm-garbage:server:depositBag', function(token)
    local src = source
    if onCooldown(src, 1500) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You are not on an active shift.', 'error')
        return
    end

    if not isSchemaReady() then
        notify(src, 'Sanitation service unavailable: database ledger is offline. Action aborted.', 'error')
        return
    end

    -- Replay / Token Validation
    if not token or type(token) ~= 'string' or token ~= session.activeBagToken then
        notify(src, 'Invalid or expired rubbish token.', 'error')
        dbg(('Invalid deposit token attempt from src %s: expected %s, got %s')
            :format(src, tostring(session.activeBagToken), tostring(token)))
        return
    end

    -- Assigned vehicle validation
    local truck = session.truckEntity
    if not truck or not DoesEntityExist(truck) then
        notify(src, 'Assigned sanitation truck is missing.', 'error')
        return
    end

    -- Proximity validation: Player ped must be near the rear hopper of their assigned truck
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local truckCoords = GetEntityCoords(truck)
    local fwd = GetEntityForwardVector(truck)
    local rearEstimate = truckCoords + (fwd * -4.5)
    local distToRear = #(pCoords - rearEstimate)

    if distToRear > (Config.Security.hopperDistance or 4.2) and #(pCoords - truckCoords) > 6.0 then
        notify(src, 'You must deposit the rubbish into the rear hopper of your assigned truck.', 'error')
        return
    end

    -- Invalidate token immediately
    session.activeBagToken = nil

    -- Update counts
    session.stopBagsCollected = session.stopBagsCollected + 1
    session.totalBagsInTruck = session.totalBagsInTruck + 1

    setMeta(src, 'cmGarbageActiveSession', {
        runRef = session.runRef,
        totalBagsInTruck = session.totalBagsInTruck,
        currentStopIndex = session.currentStopIndex,
    })

    local stop = Config.Route[session.currentStopIndex]
    local bagsRequired = stop and (stop.bagsRequired or Config.Capacity.bagsPerStop) or 2
    local stopComplete = session.stopBagsCollected >= bagsRequired

    if stopComplete then
        session.currentStopIndex = session.currentStopIndex + 1
        session.stopBagsCollected = 0
    end

    local truckFull = session.totalBagsInTruck >= Config.Capacity.maxBags
    local routeComplete = session.currentStopIndex > #Config.Route

    local nextStop = (not truckFull and not routeComplete) and Config.Route[session.currentStopIndex] or nil

    TriggerClientEvent('cm-garbage:client:bagDeposited', src, {
        totalBags = session.totalBagsInTruck,
        maxCapacity = Config.Capacity.maxBags,
        stopComplete = stopComplete,
        truckFull = truckFull or routeComplete,
        nextStop = nextStop,
        stopIndex = session.currentStopIndex,
        totalStops = #Config.Route,
    })

    if truckFull or routeComplete then
        notify(src, 'Compactor full! Drive to the South LS Depot tipping pit to empty.', 'info')
    else
        if stopComplete then
            notify(src, ('Stop complete. Proceed to stop %d of %d.'):format(session.currentStopIndex, #Config.Route), 'success')
        else
            notify(src, ('Bag compacted (%d/%d for this stop).'):format(session.stopBagsCollected, bagsRequired), 'success')
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Depot Unloading & Payout
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-garbage:server:unloadTruck', function()
    local src = source
    if onCooldown(src, 3000) then return end

    local ready, err = awaitSchemaReady(10000)
    if not ready then
        notify(src, 'Cannot unload truck: database ledger is offline. Truck load retained. Please retry shortly.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'You are not on an active shift.', 'error')
        return
    end

    -- Idempotent payout lock preventing duplicate unload execution
    if payoutLocks[src] then
        notify(src, 'Unload operation already in progress.', 'error')
        return
    end

    local truck = session.truckEntity
    if not truck or not DoesEntityExist(truck) then
        notify(src, 'Assigned sanitation truck is missing.', 'error')
        return
    end

    -- Proximity check to Depot Tipping Pit
    local tCoords = GetEntityCoords(truck)
    local pitCoords = Config.Depot.tippingPit.coords
    if #(tCoords - pitCoords) > (Config.Security.unloadDistance or 8.5) then
        notify(src, 'Your truck must be backed into the depot tipping pit.', 'error')
        return
    end

    if session.totalBagsInTruck <= 0 then
        notify(src, 'The truck compactor is already empty.', 'info')
        return
    end

    payoutLocks[src] = true
    session.unloading = true

    -- Tell client to trigger visual / audio hydraulic unload sequence
    TriggerClientEvent('cm-garbage:client:startUnloading', src, {
        duration = Config.Security.unloadDurationMs or 8000,
    })

    SetTimeout(Config.Security.unloadDurationMs or 8000, function()
        if not Sessions[src] or Sessions[src] ~= session then
            payoutLocks[src] = nil
            return
        end

        local bagsCompacted = session.totalBagsInTruck
        local bagPay = bagsCompacted * (Config.Earnings.perBag or 350)
        local depotBonus = (bagsCompacted >= Config.Capacity.maxBags) and (Config.Earnings.depotBonus or 2200) or 0
        local totalEarnings = bagPay + depotBonus

        local manifestRef = session.runRef or ('GARBAGE-%s-%d'):format(session.charId, os.time())

        local ready, readyErr = awaitSchemaReady(5000)
        if not ready then
            payoutLocks[src] = nil
            session.unloading = false
            notify(src, 'Cannot finalize unload: database ledger is offline. Truck load retained. Please retry shortly.', 'error')
            return
        end

        local dbExisting = nil
        local okDb, row = pcall(function()
            return MySQL.single.await('SELECT reference, bags, earnings, status FROM cm_garbage_operations WHERE reference = ? LIMIT 1', { manifestRef })
        end)
        if not okDb then
            payoutLocks[src] = nil
            session.unloading = false
            dbg(('Database error querying cm_garbage_operations for src %s: %s'):format(src, tostring(row)))
            notify(src, 'Database error during verification. Truck load retained. Please retry tipping.', 'error')
            return
        end
        if row then
            dbExisting = row
        end

        local operations = getMeta(src, 'cmGarbageOperations', {})
        if type(operations) ~= 'table' then operations = {} end
        local metaExisting = operations[manifestRef]

        local alreadyRecorded = (dbExisting ~= nil) or (metaExisting ~= nil)

        if alreadyRecorded then
            local existingBags = dbExisting and tonumber(dbExisting.bags) or (metaExisting and tonumber(metaExisting.bags))
            local existingEarnings = dbExisting and tonumber(dbExisting.earnings) or (metaExisting and tonumber(metaExisting.earnings))

            if existingBags == bagsCompacted and existingEarnings == totalEarnings then
                dbg(('Deduplication: Garbage operation %s already recorded for char %s, idempotent replay confirmed'):format(manifestRef, session.charId))
                payoutLocks[src] = nil
                session.unloading = false

                -- Reset truck compactor load and clear active session
                session.totalBagsInTruck = 0
                session.stopBagsCollected = 0
                session.currentStopIndex = 1
                session.activeBagToken = nil
                session.runRef = ('GARBAGE-%s-%d'):format(session.charId, os.time())

                setMeta(src, 'cmGarbageActiveSession', nil)
                local api = playerData()
                if api then pcall(function() api:Save(src, 'cm-garbage-dedup') end) end

                notify(src, ('Route unloaded [Ref: %s] — $%d payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(manifestRef, totalEarnings), 'info')

                TriggerClientEvent('cm-garbage:client:unloadComplete', src, {
                    stop = Config.Route[1],
                    stopIndex = 1,
                    totalStops = #Config.Route,
                    bagsCollected = 0,
                    bagsPerStop = Config.Capacity.bagsPerStop,
                    maxCapacity = Config.Capacity.maxBags,
                    earnings = totalEarnings,
                    manifestRef = manifestRef,
                })
                return
            else
                dbg(('Conflict: Garbage operation %s amounts do not match existing record'):format(manifestRef))
                payoutLocks[src] = nil
                session.unloading = false
                notify(src, 'Operation conflict detected. Truck load retained.', 'error')
                return
            end
        end

        local okInsert, insertErr = pcall(function()
            return MySQL.insert.await([[
                INSERT INTO cm_garbage_operations
                    (reference, character_id, bags, earnings, status, created_at_ts, raw_data)
                VALUES (?, ?, ?, ?, 'pending_payroll_integration', ?, ?)
            ]], {
                manifestRef,
                tostring(session.charId),
                bagsCompacted,
                totalEarnings,
                os.time(),
                json.encode({
                    reference = manifestRef,
                    charId = session.charId,
                    bags = bagsCompacted,
                    earnings = totalEarnings,
                    createdAt = os.time(),
                    status = 'pending_payroll_integration'
                })
            })
        end)

        if not okInsert then
            payoutLocks[src] = nil
            session.unloading = false
            dbg(('Failed to persist garbage operation to SQL for src %s (ref %s): %s'):format(src, manifestRef, tostring(insertErr)))
            notify(src, 'Failed to store payout in durable ledger. Truck load retained. Please retry tipping.', 'error')
            return
        end

        operations[manifestRef] = {
            reference = manifestRef,
            charId = session.charId,
            bags = bagsCompacted,
            earnings = totalEarnings,
            createdAt = os.time(),
            status = 'pending_payroll_integration'
        }

        operations = pruneSettledOperationsIfNeeded(operations, 45000)

        local derivedPending = 0
        local derivedBags = 0
        local derivedRuns = 0
        for _, op in pairs(operations) do
            if type(op) == 'table' then
                if op.status == 'pending_payroll_integration' then
                    derivedPending = derivedPending + (tonumber(op.earnings) or 0)
                end
                derivedBags = derivedBags + (tonumber(op.bags) or 0)
                derivedRuns = derivedRuns + 1
            end
        end

        local okOps = setMeta(src, 'cmGarbageOperations', operations)
        local okPending = setMeta(src, 'cmGarbagePendingPayout', derivedPending)
        local okBags = setMeta(src, 'cmGarbageBags', derivedBags)
        local okRuns = setMeta(src, 'cmGarbageRuns', derivedRuns)
        local okActive = setMeta(src, 'cmGarbageActiveSession', nil)

        local api = playerData()
        local okSave = false
        if api then
            local ok, res = pcall(function() return api:Save(src, 'cm-garbage-unload') end)
            okSave = ok and res == true
        end

        if not okOps or not okPending or not okSave then
            payoutLocks[src] = nil
            session.unloading = false
            setMeta(src, 'cmGarbageActiveSession', {
                runRef = manifestRef,
                totalBagsInTruck = bagsCompacted,
                currentStopIndex = session.currentStopIndex,
            })
            dbg(('Failed to persist garbage unload record for src %s (ref %s)'):format(src, manifestRef))
            notify(src, 'Failed to store payout in durable ledger. Please retry tipping.', 'error')
            return
        end

        payoutLocks[src] = nil
        session.unloading = false

        -- Reset truck compactor load and route stops
        session.totalBagsInTruck = 0
        session.stopBagsCollected = 0
        session.currentStopIndex = 1
        session.activeBagToken = nil
        session.runRef = ('GARBAGE-%s-%d'):format(session.charId, os.time())

        notify(src, ('Route unloaded [Ref: %s] — $%d payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(manifestRef, totalEarnings), 'info')
        dbg(('Stored $%d pending payout for src %s (char %s, ref %s)'):format(totalEarnings, src, session.charId, manifestRef))

        TriggerClientEvent('cm-garbage:client:unloadComplete', src, {
            stop = Config.Route[1],
            stopIndex = 1,
            totalStops = #Config.Route,
            bagsCollected = 0,
            bagsPerStop = Config.Capacity.bagsPerStop,
            maxCapacity = Config.Capacity.maxBags,
            earnings = totalEarnings,
            manifestRef = manifestRef,
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
        local pendingCash = math.max(0, math.floor(tonumber(getMeta(src, 'cmGarbagePendingPayout', 0)) or 0))
        if pendingCash > 0 then
            notify(src, ('You have $%d in earned sanitation payouts stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(pendingCash), 'info')
        end

        local activeSession = getMeta(src, 'cmGarbageActiveSession', nil)
        if type(activeSession) == 'table' and (tonumber(activeSession.totalBagsInTruck) or 0) > 0 then
            notify(src, ('You have an active sanitation load with %d compacted bags. Speak to the supervisor to resume.'):format(tonumber(activeSession.totalBagsInTruck)), 'info')
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
        notify(src, 'Sanitation shift cancelled due to incapacitation.', 'error')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, session in pairs(Sessions) do
        if session.totalBagsInTruck > 0 then
            setMeta(src, 'cmGarbageActiveSession', {
                runRef = session.runRef,
                totalBagsInTruck = session.totalBagsInTruck,
                currentStopIndex = session.currentStopIndex,
            })
            local api = playerData()
            if api then pcall(function() api:Save(src, 'cm-garbage-resource-stop') end) end
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
        totalBagsInTruck = s.totalBagsInTruck,
        maxCapacity = Config.Capacity.maxBags,
        truckPlate = s.truckPlate,
        truckNetId = s.truckNetId,
    }
end)

exports('IsSchemaReady', function() return isSchemaReady() end)
exports('GetSchemaState', function() return getSchemaState() end)
exports('AwaitSchemaReady', function(timeoutMs) return awaitSchemaReady(timeoutMs) end)

