-- cm-courier/server/main.lua
-- Authoritative Server Controller for Municipal Courier Delivery & Parcel Logistics.

local Config = CMCourier.Config

local PLAYERDATA = 'cm-playerdata'
local VEHICLES = 'cm-vehicles'
local PAYDAY = 'cm-payday'
local HUD = 'cm-hud'
local VEHICLEKEYS = 'cm-vehiclekeys'

-- Authoritative server-side state
local Sessions = {}    -- [src] = session table
local jobVehicles = {} -- [src] = { plate = string, netId = number, entity = entity, isPlayerVehicle = bool }
local cooldowns = {}   -- [src] = timestamp
local payoutLocks = {} -- [charId] = bool

local schemaReady = false
local schemaError = nil
local schemaPromise = nil

local function dbg(...)
    if Config.Debug then print('[CM-COURIER]', ...) end
end

local function notify(src, message, kind)
    if GetResourceState(HUD) == 'started' then
        pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
    else
        TriggerClientEvent('cm-courier:client:notify', src, message, kind or 'info')
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

local function onCooldown(src, ms)
    local now = GetGameTimer()
    if (cooldowns[src] or 0) > now then return true end
    cooldowns[src] = now + (tonumber(ms) or Config.Security.actionCooldownMs or 1500)
    return false
end

-- =========================================================================
-- SQL Schema Migration & Durable Payout Ledger
-- =========================================================================

local function runSchemaMigration()
    if GetResourceState('oxmysql') ~= 'started' then
        return false, 'oxmysql_not_started'
    end

    local okCreate, errCreate = pcall(function()
        return MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cm_courier_payout_intents (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                character_id VARCHAR(50) NOT NULL,
                manifest_ref VARCHAR(64) NOT NULL,
                route_id VARCHAR(64) NOT NULL,
                amount INT NOT NULL,
                status VARCHAR(32) NOT NULL DEFAULT 'earned',
                cycle_time_sec INT NOT NULL DEFAULT 0,
                completed_at BIGINT NULL,
                settled_at BIGINT NULL,
                settle_attempts INT NOT NULL DEFAULT 0,
                last_error VARCHAR(255) NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY uq_courier_char_manifest (character_id, manifest_ref),
                INDEX idx_courier_char_status (character_id, status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])
    end)

    if not okCreate then
        return false, 'create_table_failed: ' .. tostring(errCreate)
    end

    -- Startup Crash / Restart Recovery:
    -- Orphaned 'settling' rows are transitioned to 'pending_reconciliation'
    pcall(function()
        MySQL.query.await([[
            UPDATE cm_courier_payout_intents
            SET status = 'pending_reconciliation', last_error = 'server_restarted_during_settlement'
            WHERE status = 'settling'
        ]])
    end)

    return true, nil
end

local function ensureSchemaReady()
    if schemaReady then return true, nil end
    if schemaError then return false, schemaError end

    if schemaPromise then
        return Citizen.Await(schemaPromise)
    end

    schemaPromise = promise.new()
    local ok, err = runSchemaMigration()
    schemaReady = (ok == true)
    schemaError = not schemaReady and (tostring(err or 'migration_failed')) or nil

    local p = schemaPromise
    schemaPromise = nil
    p:resolve(schemaReady)

    if not schemaReady then
        print(('[CM-COURIER] CRITICAL: Schema migration failed: %s. Payout operations disabled (fail-closed).'):format(schemaError))
        return false, schemaError
    end

    dbg('Schema migration complete.')
    return true, nil
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(100)
    end
    ensureSchemaReady()
end)

-- Atomically record an earned payout intent upon verified completion
local function recordEarnedPayoutIntent(characterId, manifestRef, routeId, amount, cycleTimeSec)
    local ready, err = ensureSchemaReady()
    if not ready then
        print(('[CM-COURIER] ERROR: Cannot persist payout intent (cid=%s ref=%s): schema not ready (%s)'):format(
            tostring(characterId), tostring(manifestRef), tostring(err)
        ))
        return false, 'schema_not_ready'
    end

    characterId = tostring(characterId)
    manifestRef = tostring(manifestRef)
    routeId = tostring(routeId)
    amount = math.floor(tonumber(amount) or 0)
    cycleTimeSec = math.floor(tonumber(cycleTimeSec) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local now = os.time()
    local ok, res = pcall(function()
        return MySQL.query.await([[
            INSERT INTO cm_courier_payout_intents (character_id, manifest_ref, route_id, amount, status, cycle_time_sec, completed_at)
            VALUES (?, ?, ?, ?, 'earned', ?, ?)
            ON DUPLICATE KEY UPDATE amount = VALUES(amount), completed_at = COALESCE(VALUES(completed_at), completed_at)
        ]], { characterId, manifestRef, routeId, amount, cycleTimeSec, now })
    end)

    if not ok then
        print(('[CM-COURIER] ERROR persisting payout intent for cid=%s ref=%s: %s'):format(characterId, manifestRef, tostring(res)))
        return false, 'db_error'
    end
    return true
end

-- Fail-closed verification of cm-payday settlement capability.
-- cm-payday has no verified idempotent payout API (and does not configure courier in Config.Jobs).
local function verifyPaydayIdempotencyCapability()
    if GetResourceState(PAYDAY) ~= 'started' then
        return false, 'payday_offline'
    end
    -- Verified: cm-payday has no idempotent payout API. Fail-closed.
    return false, 'no_idempotent_api'
end

-- Settle or safely hold an earned payout intent.
local function settlePayoutIntent(src, characterId, intent)
    src = tonumber(src)
    if not src or not intent then return false, 'invalid_args' end
    characterId = tostring(characterId)
    local manifestRef = tostring(intent.manifest_ref)
    local amount = tonumber(intent.amount) or 0
    if amount <= 0 then return false, 'invalid_amount' end

    local ready, err = ensureSchemaReady()
    if not ready then
        return false, 'schema_not_ready'
    end

    if intent.status == 'settled' then
        return true, 'already_settled'
    end

    if intent.status == 'pending_reconciliation' then
        return false, 'pending_payroll_integration'
    end

    local hasIdempotency = verifyPaydayIdempotencyCapability()
    if not hasIdempotency then
        -- Fail closed: Store intent in durable ledger as pending_reconciliation.
        pcall(function()
            MySQL.query.await([[
                UPDATE cm_courier_payout_intents
                SET status = 'pending_reconciliation', last_error = 'pending_payroll_integration'
                WHERE character_id = ? AND manifest_ref = ?
            ]], { characterId, manifestRef })
        end)
        return false, 'pending_payroll_integration'
    end

    return false, 'unhandled_settlement'
end

local function recoverPendingPayoutsForCharacter(src, characterId)
    src = tonumber(src)
    characterId = tostring(characterId)
    if not src or not characterId or characterId == '' then return end

    local ready = ensureSchemaReady()
    if not ready then return end

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT manifest_ref, amount, status
            FROM cm_courier_payout_intents
            WHERE character_id = ? AND status IN ('earned', 'pending_reconciliation')
        ]], { characterId })
    end)

    if not ok or type(rows) ~= 'table' or #rows == 0 then return end

    local totalPending = 0
    for _, row in ipairs(rows) do
        if row.status == 'earned' then
            settlePayoutIntent(src, characterId, row)
        end
        totalPending = totalPending + tonumber(row.amount or 0)
    end

    if totalPending > 0 then
        notify(src, ('You have $%d in earned courier payouts stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(totalPending), 'info')
    end
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    if not src or not data then return end
    local charId = data.charId or data.characterId
    if charId then
        recoverPendingPayoutsForCharacter(src, charId)
    end
end)

-- =========================================================================
-- Vehicle Management (via cm-vehicles)
-- =========================================================================

local function vehiclesApi()
    if GetResourceState(VEHICLES) ~= 'started' then return nil end
    return exports[VEHICLES]
end

local function deleteJobVehicle(src)
    local rec = jobVehicles[src]
    if not rec then return end
    jobVehicles[src] = nil

    if rec.isPlayerVehicle then return end

    local api = vehiclesApi()
    if api and rec.plate then
        pcall(function() api:DeleteAdminVehicle(rec.plate) end)
    end
    if rec.entity and DoesEntityExist(rec.entity) then
        DeleteEntity(rec.entity)
    end
end

local function isEligibleCourierVehicle(modelHash)
    for _, h in ipairs(Config.Vehicle.eligibleModels) do
        if modelHash == h then return true end
    end
    return false
end

local function resolveOrSpawnCourierVan(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Player ped not found.' end

    local api = vehiclesApi()
    local spawns = Config.Facility.vehicleSpawns
    local chosenSpawn = spawns[1]

    -- Check if spawn 1 is occupied, pick next available
    local allVehs = GetAllVehicles()
    for _, sp in ipairs(spawns) do
        local occupied = false
        local sCoords = vector3(sp.x, sp.y, sp.z)
        for _, veh in ipairs(allVehs) do
            if DoesEntityExist(veh) and #(GetEntityCoords(veh) - sCoords) < 3.5 then
                occupied = true
                break
            end
        end
        if not occupied then
            chosenSpawn = sp
            break
        end
    end

    local ok, result = false, nil
    if api then
        ok, result = pcall(function()
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
    end

    if ok and type(result) == 'table' and result.ok == true and result.entity then
        jobVehicles[src] = {
            plate = result.plate,
            netId = result.netId,
            entity = result.entity,
            isPlayerVehicle = false,
        }

        if GetResourceState(VEHICLEKEYS) == 'started' and result.plate then
            pcall(function()
                exports[VEHICLEKEYS]:GiveTempKey(0, src, result.plate, {})
            end)
        end

        return true, {
            entity = result.entity,
            netId = result.netId,
            plate = result.plate,
            isPlayerVehicle = false,
        }
    end

    -- Fallback: inspect nearby player vehicles at the depot yard
    local pCoords = GetEntityCoords(ped)
    for _, veh in ipairs(allVehs) do
        if DoesEntityExist(veh) then
            local vCoords = GetEntityCoords(veh)
            if #(pCoords - vCoords) <= 30.0 and isEligibleCourierVehicle(GetEntityModel(veh)) then
                local plate = GetVehicleNumberPlateText(veh)
                local netId = NetworkGetNetworkIdFromEntity(veh)
                jobVehicles[src] = {
                    plate = plate,
                    netId = netId,
                    entity = veh,
                    isPlayerVehicle = true,
                }
                return true, {
                    entity = veh,
                    netId = netId,
                    plate = plate,
                    isPlayerVehicle = true,
                }
            end
        end
    end

    return false, 'Could not spawn courier vehicle and no eligible van found in depot.'
end

-- =========================================================================
-- Session Lifecycle & Cleanup
-- =========================================================================

local function endShift(src, reason)
    src = tonumber(src)
    if not src then return end

    local session = Sessions[src]
    if not session then return end

    payoutLocks[session.charId] = nil
    Sessions[src] = nil
    deleteJobVehicle(src)
    TriggerClientEvent('cm-courier:client:shiftEnded', src, reason or 'shift_concluded')
    dbg(('Shift ended for src %s (reason: %s)'):format(src, tostring(reason)))
end

-- =========================================================================
-- Net Events
-- =========================================================================

-- Player interacts with Dispatcher NPC (Sal Moreno)
RegisterNetEvent('cm-courier:server:openWorkBoard', function()
    local src = source
    if onCooldown(src, 1000) then return end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Character identity not loaded.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local supCoords = vector3(Config.Facility.supervisor.coords.x, Config.Facility.supervisor.coords.y, Config.Facility.supervisor.coords.z)
    if #(pCoords - supCoords) > (Config.Security.supervisorDistance or 3.5) + 2.0 then
        notify(src, 'You are too far from the courier dispatcher.', 'error')
        return
    end

    local session = Sessions[src]
    local choices = {}
    local quote = ''

    if not session then
        -- Automatically notify player of any pending earned payouts held in ledger
        recoverPendingPayoutsForCharacter(src, charId)

        -- No authoritative commercial courier source exists (see server/contracts.lua): fixed,
        -- non-selectable notice only. Nothing is queried, fabricated or claimable.
        choices[#choices + 1] = {
            id = 'premium_unavailable',
            label = '[PREMIUM - COMMERCIAL ORDERS] (No Active Contracts)',
            description = 'No private enterprise or business parcel deliveries are currently published with verified worker tariffs (> $37,500/hr). Municipal courier routes are available.',
            event = 'cm-courier:client:dialogueChoice',
            payload = { action = 'commercial_unavailable', reason = 'No private enterprise courier contracts are currently published with verified worker wage tariffs (> $37,500/hr).' },
        }

        -- Always-available Municipal City Courier Routes
        for _, route in ipairs(Config.Routes) do
            local numStops = route.stops and #route.stops or 0
            choices[#choices + 1] = {
                id = route.id,
                label = route.title,
                description = ('%s (%d stops) - Payout: $%d [Held in durable ledger; cash cannot currently be collected in-game]'):format(
                    route.description or '', numStops, route.payout or 0
                ),
                event = 'cm-courier:client:dialogueChoice',
                payload = { action = 'select_route', routeId = route.id },
            }
        end

        quote = 'City Courier Dispatch has municipal delivery manifests ready for pickup. Note: municipal payouts are recorded in durable ledger (cash cannot currently be collected in-game pending safe payroll integration). Select an assignment.'
    else
        if session.state == 'delivered_all' or session.state == 'returned_to_depot' then
            quote = 'All parcels delivered! Sign off the manifest to file your shift completion and store your earnings in the durable ledger.'
            choices[#choices + 1] = {
                id = 'sign_off',
                label = 'Sign Off & Conclude Shift',
                description = ('Submit delivery signatures and record earnings ($%d) into durable ledger'):format(session.payout or 0),
                event = 'cm-courier:client:dialogueChoice',
                payload = { action = 'sign_off' },
            }
        else
            quote = ('How is route manifest %s progressing? You have delivered %d of %d parcels. Complete all drops before signing off.'):format(
                session.routeTitle or 'Courier Route', session.parcelsDelivered or 0, session.parcelsTotal or 0
            )
        end

        choices[#choices + 1] = {
            id = 'abort',
            label = 'Clock Out & Abort Manifest',
            description = 'Return vehicle and cancel the active courier delivery run',
            event = 'cm-courier:client:dialogueChoice',
            payload = { action = 'abort' },
        }
    end

    choices[#choices + 1] = {
        id = 'info',
        label = 'Courier Safety & Delivery Protocols',
        description = 'Review vehicle operation, parcel dock loading, recipient signature verification, and return procedures',
        event = 'cm-courier:client:dialogueChoice',
        payload = { action = 'info' },
    }

    TriggerClientEvent('cm-courier:client:receiveWorkBoardChoices', src, choices, quote)
end)

-- Player selects a delivery route
RegisterNetEvent('cm-courier:server:selectRoute', function(routeId)
    local src = source
    if onCooldown(src, 2000) then return end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Character identity not loaded.', 'error')
        return
    end

    if Sessions[src] then
        notify(src, 'You already have an active courier run in progress.', 'error')
        return
    end

    local ready, schemaErr = ensureSchemaReady()
    if not ready then
        notify(src, 'Courier dispatch ledger is offline. Try again later.', 'error')
        return
    end

    local chosenRoute = nil
    for _, r in ipairs(Config.Routes) do
        if r.id == routeId then
            chosenRoute = r
            break
        end
    end

    if not chosenRoute then
        notify(src, 'Selected delivery route is invalid or expired.', 'error')
        return
    end

    local vehOk, vehData = resolveOrSpawnCourierVan(src)
    if not vehOk then
        notify(src, 'Could not stage courier van: ' .. tostring(vehData), 'error')
        return
    end

    local now = os.time()
    local manifestRef = ('courier_%s_%s_%d'):format(charId, chosenRoute.id, now)

    Sessions[src] = {
        charId = charId,
        routeId = chosenRoute.id,
        routeTitle = chosenRoute.title,
        route = chosenRoute,
        manifestRef = manifestRef,
        payout = chosenRoute.payout,
        cycleSeconds = chosenRoute.cycleSeconds,
        minCompletionSeconds = chosenRoute.minCompletionSeconds,
        parcelsTotal = #chosenRoute.stops,
        parcelsLoaded = 0,
        parcelsDelivered = 0,
        currentStopIndex = 1,
        startTime = now,
        lastActionTime = GetGameTimer(),
        state = 'awaiting_loading',
        vehicleNetId = vehData.netId,
        vehiclePlate = vehData.plate,
        vehicleEntity = vehData.entity,
        isPlayerVehicle = vehData.isPlayerVehicle,
    }

    TriggerClientEvent('cm-courier:client:routeStarted', src, {
        routeId = chosenRoute.id,
        routeTitle = chosenRoute.title,
        payout = chosenRoute.payout,
        stops = chosenRoute.stops,
        parcelsTotal = #chosenRoute.stops,
        manifestRef = manifestRef,
        vehicleNetId = vehData.netId,
        vehiclePlate = vehData.plate,
    })

    notify(src, ('Assigned %s. Proceed to the loading dock to load your parcels.'):format(chosenRoute.title), 'success')
    dbg(('Started route %s for src %s (charId: %s)'):format(chosenRoute.id, src, charId))
end)

-- Player loads parcels at depot loading dock
RegisterNetEvent('cm-courier:server:loadParcels', function()
    local src = source
    if onCooldown(src, 2500) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'No active courier run found.', 'error')
        return
    end

    if session.state ~= 'awaiting_loading' then
        notify(src, 'Parcels are already loaded into your courier van.', 'warning')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)

    local dockCoords = Config.Facility.loadingDock.coords
    if #(pCoords - dockCoords) > (Config.Security.loadingDockDistance or 6.0) then
        notify(src, 'You must be at the depot loading dock to load parcels.', 'error')
        return
    end

    -- Verify courier vehicle proximity to loading dock
    if session.vehicleEntity and DoesEntityExist(session.vehicleEntity) then
        local vCoords = GetEntityCoords(session.vehicleEntity)
        if #(pCoords - vCoords) > (Config.Security.vehicleProximityToLoading or 18.0) then
            notify(src, 'Your courier van must be parked near the loading dock.', 'error')
            return
        end
    end

    session.parcelsLoaded = session.parcelsTotal
    session.state = 'in_transit'
    session.lastActionTime = GetGameTimer()

    TriggerClientEvent('cm-courier:client:parcelsLoaded', src, {
        parcelsLoaded = session.parcelsLoaded,
        currentStopIndex = 1,
    })

    notify(src, ('Manifest parcels (%d/%d) loaded into your van. Depart for Stop 1: %s.'):format(
        session.parcelsLoaded, session.parcelsTotal, session.route.stops[1].label
    ), 'success')
    dbg(('Parcels loaded for src %s'):format(src))
end)

-- Player confirms delivery at an individual route stop
RegisterNetEvent('cm-courier:server:deliverParcel', function(stopIndex)
    local src = source
    if onCooldown(src, 2000) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'No active courier run found.', 'error')
        return
    end

    if session.state ~= 'in_transit' then
        notify(src, 'You are not currently in transit delivering parcels.', 'error')
        return
    end

    stopIndex = tonumber(stopIndex)
    if not stopIndex or stopIndex ~= session.currentStopIndex then
        notify(src, 'Delivery out of sequence. Deliver to your designated stop first.', 'error')
        return
    end

    local stop = session.route.stops[stopIndex]
    if not stop then
        notify(src, 'Invalid stop index on route manifest.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)

    -- Proximity to designated stop
    local stopCoords = vector3(stop.coords.x, stop.coords.y, stop.coords.z)
    if #(pCoords - stopCoords) > (Config.Security.deliveryDistance or 15.0) then
        notify(src, 'You are too far from the delivery drop-off point.', 'error')
        return
    end

    -- Proximity to courier vehicle (validates they drove van to the stop)
    if session.vehicleEntity and DoesEntityExist(session.vehicleEntity) then
        local vCoords = GetEntityCoords(session.vehicleEntity)
        if #(pCoords - vCoords) > (Config.Security.vehicleProximityToStop or 45.0) then
            notify(src, 'Your courier van is too far away. Park closer to the recipient.', 'error')
            return
        end
    end

    -- Minimum transit time check between stops
    local nowMs = GetGameTimer()
    local elapsedSinceLastAction = (nowMs - (session.lastActionTime or 0)) / 1000.0
    if elapsedSinceLastAction < (Config.Security.minSecondsPerStop or 18) then
        notify(src, 'Delivery verification rejected: transit time between stops is abnormally fast.', 'error')
        return
    end

    session.lastActionTime = nowMs
    session.parcelsDelivered = session.parcelsDelivered + 1
    session.currentStopIndex = session.currentStopIndex + 1

    local allDelivered = session.parcelsDelivered >= session.parcelsTotal
    if allDelivered then
        session.state = 'delivered_all'
    end

    TriggerClientEvent('cm-courier:client:stopCompleted', src, {
        completedStopIndex = stopIndex,
        parcelsDelivered = session.parcelsDelivered,
        parcelsTotal = session.parcelsTotal,
        nextStopIndex = session.currentStopIndex,
        allDelivered = allDelivered,
    })

    if allDelivered then
        notify(src, 'All parcels delivered! Return the courier van to the Depot Return Bay to sign off.', 'success')
    else
        local nextStop = session.route.stops[session.currentStopIndex]
        notify(src, ('Delivery confirmed (%d/%d). Next stop: %s.'):format(
            session.parcelsDelivered, session.parcelsTotal, nextStop and nextStop.label or 'Next Location'
        ), 'info')
    end

    dbg(('Stop %d delivered for src %s (%d/%d)'):format(stopIndex, src, session.parcelsDelivered, session.parcelsTotal))
end)

-- Player parks vehicle in depot return bay
RegisterNetEvent('cm-courier:server:returnToDepot', function()
    local src = source
    if onCooldown(src, 1500) then return end

    local session = Sessions[src]
    if not session then return end

    if session.state ~= 'delivered_all' and session.state ~= 'returned_to_depot' then
        notify(src, 'You must deliver all parcels before returning to depot.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)

    local returnBayCoords = Config.Facility.returnBay.coords
    if #(pCoords - returnBayCoords) > (Config.Security.depotReturnDistance or 15.0) then
        notify(src, 'You must be inside the Depot Return Bay.', 'error')
        return
    end

    if session.vehicleEntity and DoesEntityExist(session.vehicleEntity) then
        local vCoords = GetEntityCoords(session.vehicleEntity)
        if #(vCoords - returnBayCoords) > (Config.Security.depotReturnDistance or 15.0) then
            notify(src, 'Your courier van must be parked inside the Depot Return Bay.', 'error')
            return
        end
    end

    session.state = 'returned_to_depot'
    TriggerClientEvent('cm-courier:client:vanReturned', src)
    notify(src, 'Courier van safely staged. Talk to Dispatcher Sal Moreno to sign off and file your earnings.', 'success')
end)

-- Player signs off with Sal Moreno and records earnings in durable ledger
RegisterNetEvent('cm-courier:server:signOff', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Character identity not loaded.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'No active courier run found to sign off.', 'error')
        return
    end

    if session.charId ~= charId then
        notify(src, 'Character identity mismatch.', 'error')
        return
    end

    if session.state ~= 'delivered_all' and session.state ~= 'returned_to_depot' then
        notify(src, 'You have not completed all parcel deliveries on this manifest.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local supCoords = vector3(Config.Facility.supervisor.coords.x, Config.Facility.supervisor.coords.y, Config.Facility.supervisor.coords.z)
    if #(pCoords - supCoords) > (Config.Security.supervisorDistance or 3.5) + 2.0 then
        notify(src, 'You must be at the dispatcher desk to sign off.', 'error')
        return
    end

    -- Verify courier van is at depot return bay
    local returnBayCoords = Config.Facility.returnBay.coords
    if session.vehicleEntity and DoesEntityExist(session.vehicleEntity) then
        local vCoords = GetEntityCoords(session.vehicleEntity)
        if #(vCoords - returnBayCoords) > (Config.Security.depotReturnDistance or 15.0) then
            notify(src, 'Return your courier van to the Depot Return Bay before signing off.', 'error')
            return
        end
    end

    -- Minimum cycle completion time validation (protects against speedhacking/teleporting)
    local now = os.time()
    local elapsedSec = now - session.startTime
    local minRequired = session.minCompletionSeconds or math.floor(session.cycleSeconds * 0.65)
    if elapsedSec < minRequired then
        notify(src, ('Sign-off rejected: route completed in %ds, which is faster than the physical minimum threshold of %ds.'):format(
            elapsedSec, minRequired
        ), 'error')
        print(('[CM-COURIER] WARNING: Speed check failed for src %s (elapsed %ds < min %ds)'):format(src, elapsedSec, minRequired))
        return
    end

    -- Acquire payout lock to prevent duplicate sign-off race conditions
    if payoutLocks[charId] then
        notify(src, 'Payout processing in progress.', 'error')
        return
    end
    payoutLocks[charId] = true

    local payoutAmount = session.payout
    local manifestRef = session.manifestRef
    local routeId = session.routeId

    local recorded, recErr = recordEarnedPayoutIntent(charId, manifestRef, routeId, payoutAmount, elapsedSec)
    if not recorded then
        payoutLocks[charId] = nil
        notify(src, 'Could not persist payout intent in durable ledger: ' .. tostring(recErr), 'error')
        return
    end

    -- Settle or safely transition into durable ledger
    settlePayoutIntent(src, charId, {
        manifest_ref = manifestRef,
        amount = payoutAmount,
        status = 'earned',
    })

    payoutLocks[charId] = nil

    -- Clean up vehicle & session
    deleteJobVehicle(src)
    Sessions[src] = nil

    TriggerClientEvent('cm-courier:client:shiftEnded', src, 'completed')

    notify(src, ('Shift completed [Ref: %s] — $%d recorded in durable ledger (cash is held and cannot currently be collected in-game pending safe payroll integration).'):format(manifestRef, payoutAmount), 'info')
    dbg(('Successfully signed off route %s for src %s (charId: %s, amount: $%d)'):format(routeId, src, charId, payoutAmount))
end)

-- Player cancels or aborts the active shift
RegisterNetEvent('cm-courier:server:cancelShift', function()
    local src = source
    if onCooldown(src, 1500) then return end
    endShift(src, 'player_cancelled')
    notify(src, 'Courier shift clocked out. Equipment and route manifest returned.', 'info')
end)

-- Clean up on player disconnect or character unload
AddEventHandler('playerDropped', function(reason)
    local src = source
    endShift(src, 'player_dropped')
end)

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    endShift(src, 'character_unloaded')
end)

-- Clean up if character dies during delivery run
AddEventHandler('cm-playerdata:server:characterDied', function(src)
    local session = Sessions[src]
    if session then
        endShift(src, 'character_incapacitated')
        notify(src, 'Courier shift terminated due to severe incapacitation.', 'error')
    end
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, _ in pairs(Sessions) do
        deleteJobVehicle(src)
    end
    Sessions = {}
    jobVehicles = {}
end)

