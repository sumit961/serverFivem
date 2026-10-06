-- cm-warehouse/server/main.lua
-- Port Logistics & Warehouse Freight Operations Server Controller.

local Config = CMWarehouse.Config

local PLAYERDATA = 'cm-playerdata'
local VEHICLES = 'cm-vehicles'
local PAYDAY = 'cm-payday'
local HUD = 'cm-hud'
local VEHICLEKEYS = 'cm-vehiclekeys'

-- Authoritative server-side state
local Sessions = {}
local jobVehicles = {} -- [src] = { plate = string, netId = number, entity = entity, isPlayerVehicle = bool }
local cooldowns = {}   -- [src] = timestamp

local schemaReady = false
local schemaError = nil
local schemaPromise = nil

local function dbg(...)
    if Config.Debug then print('[CM-WAREHOUSE]', ...) end
end

local function notify(src, message, kind)
    if GetResourceState(HUD) == 'started' then
        pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
    else
        TriggerClientEvent('cm-warehouse:client:notify', src, message, kind or 'info')
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
            CREATE TABLE IF NOT EXISTS cm_warehouse_payout_intents (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                character_id VARCHAR(50) NOT NULL,
                manifest_ref VARCHAR(64) NOT NULL,
                shift_id VARCHAR(64) NOT NULL,
                amount INT NOT NULL,
                status VARCHAR(32) NOT NULL DEFAULT 'earned',
                completed_at BIGINT NULL,
                settled_at BIGINT NULL,
                settle_attempts INT NOT NULL DEFAULT 0,
                last_error VARCHAR(255) NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY uq_warehouse_char_manifest (character_id, manifest_ref),
                INDEX idx_warehouse_char_status (character_id, status)
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
            UPDATE cm_warehouse_payout_intents
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
        print(('[CM-WAREHOUSE] CRITICAL: Schema migration failed: %s. Payout operations disabled (fail-closed).'):format(schemaError))
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
local function recordEarnedPayoutIntent(characterId, manifestRef, shiftId, amount)
    local ready, err = ensureSchemaReady()
    if not ready then
        print(('[CM-WAREHOUSE] ERROR: Cannot persist payout intent (cid=%s ref=%s): schema not ready (%s)'):format(
            tostring(characterId), tostring(manifestRef), tostring(err)
        ))
        return false, 'schema_not_ready'
    end

    characterId = tostring(characterId)
    manifestRef = tostring(manifestRef)
    shiftId = tostring(shiftId)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local now = os.time()
    local ok, res = pcall(function()
        return MySQL.query.await([[
            INSERT INTO cm_warehouse_payout_intents (character_id, manifest_ref, shift_id, amount, status, completed_at)
            VALUES (?, ?, ?, ?, 'earned', ?)
            ON DUPLICATE KEY UPDATE amount = VALUES(amount), completed_at = COALESCE(VALUES(completed_at), completed_at)
        ]], { characterId, manifestRef, shiftId, amount, now })
    end)

    if not ok then
        print(('[CM-WAREHOUSE] ERROR persisting payout intent for cid=%s ref=%s: %s'):format(characterId, manifestRef, tostring(res)))
        return false, 'db_error'
    end
    return true
end

-- Fail-closed verification of cm-payday's settlement capabilities.
-- cm-payday currently has no verified idempotent payout export or capability.
local function verifyPaydayIdempotencyCapability()
    if GetResourceState(PAYDAY) ~= 'started' then
        return false, 'payday_offline'
    end
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
        -- Fail closed: cm-payday has no verified idempotent API.
        -- Update status to 'pending_reconciliation' with reason 'pending_payroll_integration'.
        pcall(function()
            MySQL.query.await([[
                UPDATE cm_warehouse_payout_intents
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
            FROM cm_warehouse_payout_intents
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
        notify(src, ('You have $%d in earned warehouse payouts stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(totalPending), 'info')
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

local function isEligibleWarehouseVehicle(modelHash)
    local valid = {
        joaat('forklift'),
        joaat('bison'),
        joaat('bison2'),
        joaat('bison3'),
        joaat('sadler'),
        joaat('caddy'),
        joaat('caddy2'),
    }
    for _, h in ipairs(valid) do
        if modelHash == h then return true end
    end
    return false
end

local function resolveOrSpawnForklift(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Player ped not found.' end

    local api = vehiclesApi()
    local spawns = Config.Facility.vehicleSpawns
    local chosenSpawn = spawns[1]

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

    -- Graceful fallback: inspect nearby player vehicles at the warehouse yard
    local pCoords = GetEntityCoords(ped)
    local vehicles = GetAllVehicles()
    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            local vCoords = GetEntityCoords(veh)
            if #(pCoords - vCoords) <= 25.0 and isEligibleWarehouseVehicle(GetEntityModel(veh)) then
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

    -- Allow pedestrian / foot staging if vehicle spawn is unavailable
    return true, {
        entity = nil,
        netId = nil,
        plate = 'DOCK-CREW',
        isPlayerVehicle = true,
    }
end

-- =========================================================================
-- Session Lifecycle & Cleanup
-- =========================================================================

local function endShift(src, reason)
    local session = Sessions[src]
    if not session then return end

    Sessions[src] = nil
    deleteJobVehicle(src)
    TriggerClientEvent('cm-warehouse:client:shiftEnded', src, reason or 'shift_concluded')
end

-- =========================================================================
-- Commercial warehouse contracts are not supported: cm-contracts has no trusted source or
-- registered 'warehouse' provider, so there is no authoritative contract, wage or cycle data.
-- There is intentionally no evaluate/claim/complete/release path in this resource
-- (server/contracts.lua is a fail-closed stub).

-- =========================================================================
-- Net Events
-- =========================================================================

-- Player interacts with Port Logistics Supervisor Vince "Cargo" Calderon
RegisterNetEvent('cm-warehouse:server:openWorkBoard', function()
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
        notify(src, 'You are too far from the port logistics supervisor.', 'error')
        return
    end

    local session = Sessions[src]
    local choices = {}
    local quote = ''

    if not session then
        -- Automatically notify player of any pending earned payouts held in ledger
        recoverPendingPayoutsForCharacter(src, charId)

        -- No authoritative commercial contract source exists (see note above): fixed, non-selectable
        -- notice only. Nothing is queried, fabricated or claimable.
        choices[#choices + 1] = {
            id = 'premium_unavailable',
            label = '[PREMIUM - COMMERCIAL FREIGHT CONTRACTS] (No Active Contracts)',
            description = 'No private enterprise logistics or commercial supply contracts are currently published with verified worker tariffs. Municipal port logistics shifts are available.',
            event = 'cm-warehouse:client:dialogueChoice',
            payload = { action = 'commercial_unavailable', reason = 'No private enterprise logistics contracts are currently published with verified worker wage tariffs (> $37,500/hr).' },
        }

        -- Always-available Municipal Port Logistics Shifts
        for _, shift in ipairs(Config.Shifts) do
            local numStages = shift.stages and #shift.stages or 0
            choices[#choices + 1] = {
                id = shift.id,
                label = shift.title,
                description = ('%s (%d physical stages: Receiving, Sorting, Staging, Dispatch) - Payout: $%d [Held in durable ledger; cash cannot currently be collected in-game]'):format(
                    shift.description or '', numStages, shift.payout or 0
                ),
                event = 'cm-warehouse:client:dialogueChoice',
                payload = { action = 'select_shift', shiftId = shift.id },
            }
        end

        quote = 'Port Terminal Logistics has municipal cargo manifests ready for processing. Note: municipal payouts are stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration). Select an assignment.'
    else
        quote = 'How is the cargo manifest progressing? Complete all physical receiving, sorting, and dispatch stages before signing off.'
        choices[#choices + 1] = {
            id = 'cancel',
            label = 'Clock Out & Abort Manifest',
            description = 'Return equipment and conclude your warehouse shift',
            event = 'cm-warehouse:client:dialogueChoice',
            payload = { action = 'cancel' },
        }
    end

    choices[#choices + 1] = {
        id = 'info',
        label = 'Warehouse Safety & Cargo Protocols',
        description = 'Review physical receiving, barcode sorting, shrink-wrap pallet staging, and outbound bay dispatch',
        event = 'cm-warehouse:client:dialogueChoice',
        payload = { action = 'info' },
    }

    TriggerClientEvent('cm-warehouse:client:receiveWorkBoardChoices', src, choices, quote)
end)

-- Player selects a municipal shift manifest
RegisterNetEvent('cm-warehouse:server:selectShift', function(shiftId)
    local src = source
    if onCooldown(src, 2000) then return end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Character identity not loaded.', 'error')
        return
    end

    if Sessions[src] then
        notify(src, 'You already have an active warehouse shift in progress.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local supCoords = vector3(Config.Facility.supervisor.coords.x, Config.Facility.supervisor.coords.y, Config.Facility.supervisor.coords.z)
    if #(pCoords - supCoords) > (Config.Security.supervisorDistance or 3.5) + 2.0 then
        notify(src, 'You must be at the supervisor office to sign on.', 'error')
        return
    end

    local selectedShift = nil
    for _, s in ipairs(Config.Shifts) do
        if s.id == shiftId then
            selectedShift = s
            break
        end
    end

    if not selectedShift then
        -- Not a configured municipal shift. No authoritative commercial contract source or provider exists,
        -- so any other id (forged event or fabricated contract id) is rejected without touching state.
        notify(src, 'Invalid or unavailable shift manifest selected.', 'error')
        return
    end

    local okVeh, vehInfo = resolveOrSpawnForklift(src)
    if not okVeh then
        notify(src, tostring(vehInfo), 'error')
        return
    end

    Sessions[src] = {
        src = src,
        charId = charId,
        shift = selectedShift,
        stageIndex = 1,
        stageStartedAt = nil,
        completedStages = {},
        allStagesCompleted = false,
        truckNetId = vehInfo.netId,
        truckPlate = vehInfo.plate,
        truckEntity = vehInfo.entity,
        isPlayerVehicle = vehInfo.isPlayerVehicle,
        startedAt = GetGameTimer(),
        pendingReward = selectedShift.payout or 1440,
        rewardAuthorized = false,
    }

    notify(src, ('Manifest assigned: %s ($%d earned upon completion, payout stored in durable ledger; cash cannot currently be collected in-game). Proceed to Receiving Dock 1.'):format(selectedShift.title, selectedShift.payout or 1440), 'info')

    TriggerClientEvent('cm-warehouse:client:shiftStarted', src, {
        shift = selectedShift,
        truckNetId = vehInfo.netId,
        truckPlate = vehInfo.plate,
    })
end)

-- Player starts physical cargo handling on a specific stage
RegisterNetEvent('cm-warehouse:server:startStageWork', function(shiftId, stageIndex)
    local src = source
    if onCooldown(src, 1000) then return end

    local session = Sessions[src]
    if not session or session.shift.id ~= shiftId or session.stageIndex ~= stageIndex then
        notify(src, 'Invalid stage execution request.', 'error')
        return
    end

    local stage = session.shift.stages and session.shift.stages[stageIndex]
    if not stage then
        notify(src, 'Stage definition not found.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local dist = #(pCoords - stage.coords)

    if dist > (Config.Security.stageInteractDistance or 4.5) + 1.5 then
        notify(src, 'You are too far from the cargo work station.', 'error')
        return
    end

    session.stageStartedAt = GetGameTimer()

    TriggerClientEvent('cm-warehouse:client:stageWorkStarted', src, {
        stageIndex = stageIndex,
        scenario = stage.scenario,
        durationMs = stage.durationMs,
    })
end)

-- Player completes physical cargo handling on a specific stage
RegisterNetEvent('cm-warehouse:server:completeStageWork', function(shiftId, stageIndex)
    local src = source
    if onCooldown(src, 1000) then return end

    local session = Sessions[src]
    if not session or session.shift.id ~= shiftId or session.stageIndex ~= stageIndex then
        notify(src, 'Stage sequence mismatch.', 'error')
        return
    end

    local stage = session.shift.stages and session.shift.stages[stageIndex]
    if not stage then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local dist = #(pCoords - stage.coords)

    if dist > (Config.Security.stageInteractDistance or 4.5) + 2.0 then
        notify(src, 'You moved too far from the work station during cargo handling.', 'error')
        return
    end

    local elapsed = GetGameTimer() - (session.stageStartedAt or 0)
    if elapsed < (stage.minDurationMs or 5000) then
        dbg(('Stage completion too rapid from src %s: %d ms'):format(tostring(src), elapsed))
        notify(src, 'Cargo handling incomplete. Follow full warehouse procedure.', 'warning')
        return
    end

    session.completedStages[stageIndex] = true
    session.stageIndex = stageIndex + 1

    local totalStages = #session.shift.stages
    if session.stageIndex > totalStages then
        session.allStagesCompleted = true
        notify(src, 'All physical stages verified! Return to Supervisor Office to submit the manifest.', 'success')
    else
        notify(src, ('Stage %d complete! Proceed to Stage %d.'):format(stageIndex, session.stageIndex), 'success')
    end

    TriggerClientEvent('cm-warehouse:client:stageCompleted', src, {
        nextStageIndex = session.stageIndex,
    })
end)

-- Player checks in manifest at Port Logistics Office
RegisterNetEvent('cm-warehouse:server:checkInManifest', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local session = Sessions[src]
    if not session or not session.allStagesCompleted then
        notify(src, 'No completed cargo manifest awaiting inspection check-in.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local returnBay = Config.Facility.returnBay.coords
    local dist = #(pCoords - returnBay)

    if dist > (Config.Security.depotReturnDistance or 14.0) + 2.0 then
        notify(src, 'You must park at the supervisor manifest check-in bay.', 'error')
        return
    end

    local charId = session.charId
    local shiftId = session.shift.id
    local payout = session.pendingReward or session.shift.payout or 1440
    local manifestRef = ('MUNI-WH-%s-%s-%s'):format(shiftId, tostring(charId), tostring(os.time()))

    -- DURABLE REWARD PERSISTENCE:
    -- Record earned payout intent in SQL immediately before terminating shift
    recordEarnedPayoutIntent(charId, manifestRef, shiftId, payout)

    -- Settle or hold payout intent fail-closed
    local intent = {
        manifest_ref = manifestRef,
        amount = payout,
        status = 'earned',
    }
    local settled, settleErr = settlePayoutIntent(src, charId, intent)

    -- Cleanup job vehicle
    deleteJobVehicle(src)

    TriggerClientEvent('cm-warehouse:client:shiftCompleted', src, {
        payout = payout,
        settled = settled,
        status = settleErr or (settled and 'settled' or 'pending'),
    })

    Sessions[src] = nil

    if settled then
        notify(src, ('Work completed [Ref: %s] — $%d recorded in durable ledger (ledger record only; cash payment is not confirmed by this job).'):format(manifestRef, payout), 'info')
    elseif settleErr == 'pending_payroll_integration' or settleErr == 'pending_reconciliation' then
        notify(src, ('Work completed [Ref: %s] — $%d payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(manifestRef, payout), 'info')
    else
        notify(src, ('Work completed [Ref: %s] — payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(manifestRef), 'info')
    end
end)

RegisterNetEvent('cm-warehouse:server:cancelShift', function()
    local src = source
    local session = Sessions[src]
    if not session then
        notify(src, 'You are not currently on shift.', 'info')
        return
    end

    notify(src, 'Warehouse shift aborted. Equipment checked in.', 'info')
    endShift(src, 'player_cancelled')
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    endShift(src, 'player_dropped')
end)

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    endShift(src, 'character_unloaded')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, _ in pairs(Sessions) do
        deleteJobVehicle(src)
    end
    Sessions = {}
end)

