-- cm-trucking/server/main.lua
-- Authoritative Commercial Freight Trucking Server Lifecycle.
--
-- Integrates with:
--   cm-contracts: Broker for contract publication, claims, leases, and completion.
--   cm-playerdata: Character ID and metadata authority.
--   cm-vehicles: Physical vehicle spawning and verification.
--   cm-vehiclekeys: Temporary driver key assignment.
--   cm-payday: Bounded wage and pending payout held for payday cycles.
--   cm-hud / cm-ui: Player notifications and interaction feedback.
--
-- Security & Integrity:
--   All client inputs are untrusted. Character ID, locations, proximity,
--   driving times, cargo manifest, and completion state are validated server-side.
--   Every displayed contract must have an authentic source owner (cm-commercial-ownership
--   publishing 'business_supply' via cm-contracts). No mock/fictional routes are generated.
--
-- Durable Reward Recovery:
--   Earned rewards are persisted as durable payout intents in SQL (cm_trucking_payout_intents)
--   keyed by (character_id, contract_reference) immediately upon verified broker completion
--   (rewardable == true) BEFORE any session or vehicle state is cleared.
--   Returning a truck, disconnecting, or server restarts will never delete an unpaid reward.

local Config = CMTrucking.Config
CMTrucking = CMTrucking or {}
CMTrucking.Server = CMTrucking.Server or {}
local Server = CMTrucking.Server

local Adapter = CMTrucking.BusinessAdapter

local PLAYERDATA = 'cm-playerdata'
local VEHICLES = 'cm-vehicles'
local VEHICLEKEYS = 'cm-vehiclekeys'
local PAYDAY = 'cm-payday'
local HUD = 'cm-hud'

-- Authoritative server-side state
-- Sessions[src] = {
--     src = number,
--     charId = string,
--     contract = table,
--     state = string,
--     truckNetId = number|nil,
--     truckPlate = string|nil,
--     truckEntity = entity|nil,
--     isPlayerVehicle = boolean,
--     loadingStartedAt = number|nil,
--     transitStartedAt = number|nil,
--     deliveredAt = number|nil,
--     pendingReward = number,
--     rewardAuthorized = boolean,
--     payrollSettled = boolean,
-- }
local Sessions = {}
local jobVehicles = {}       -- [src] = { plate = string, netId = number, entity = entity }
local cooldowns = {}         -- [src] = timestamp
local payoutLocks = {}       -- [lockKey] = boolean
local transitStartTimes = {}  -- [src] = timestamp

local function dbg(...)
    if Config.Debug then print('[CM-TRUCKING]', ...) end
end

local function notify(src, message, kind)
    if GetResourceState(HUD) == 'started' then
        pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
    else
        TriggerClientEvent('cm-trucking:client:notify', src, message, kind or 'info')
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
-- Durable Payout Intent Storage Schema & Backward-Compatible Migration
-- =========================================================================

local schemaReady = false
local schemaError = nil
local schemaPromise = nil

-- Non-destructive, idempotent migration supporting both earlier and newer schema layouts.
-- Layout 1 (Earlier): INT pk, INT character_id, VARCHAR(64) contract_reference, ENUM status,
--                     missing broker_completed_at, missing settled_at, idx_trucking_char_status.
-- Layout 2 (Newer):   BIGINT pk, VARCHAR(50) character_id, VARCHAR(32) contract_reference,
--                     BIGINT NOT NULL broker_completed_at, BIGINT NULL settled_at, idx_trucking_pending_payout.
local function runSchemaMigration()
    -- 1. Check if cm_trucking_payout_intents table exists
    local okTable, tableRows = pcall(function()
        return MySQL.query.await([[
            SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_trucking_payout_intents'
        ]])
    end)

    if not okTable or type(tableRows) ~= 'table' then
        return false, 'failed_to_query_tables: ' .. tostring(tableRows)
    end

    if #tableRows == 0 then
        -- Table does not exist: create unified target schema directly
        local okCreate, createErr = pcall(function()
            return MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS cm_trucking_payout_intents (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    character_id VARCHAR(50) NOT NULL,
                    contract_reference VARCHAR(64) NOT NULL,
                    amount INT NOT NULL,
                    status VARCHAR(32) NOT NULL DEFAULT 'earned',
                    broker_completed_at BIGINT NULL,
                    settled_at BIGINT NULL,
                    settle_attempts INT NOT NULL DEFAULT 0,
                    last_error VARCHAR(255) NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_trucking_char_contract (character_id, contract_reference),
                    INDEX idx_trucking_pending_payout (character_id, status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            ]])
        end)

        if not okCreate then
            return false, 'create_table_failed: ' .. tostring(createErr)
        end
    else
        -- Table exists: perform non-destructive introspection and column alignment
        local okCols, colRows = pcall(function()
            return MySQL.query.await([[
                SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_trucking_payout_intents'
            ]])
        end)

        if not okCols or type(colRows) ~= 'table' then
            return false, 'inspect_columns_failed: ' .. tostring(colRows)
        end

        local existingCols = {}
        for _, col in ipairs(colRows) do
            local name = tostring(col.COLUMN_NAME or col.column_name or ''):lower()
            local dataType = tostring(col.DATA_TYPE or col.data_type or ''):lower()
            local maxLen = tonumber(col.CHARACTER_MAXIMUM_LENGTH or col.character_maximum_length)
            local isNull = tostring(col.IS_NULLABLE or col.is_nullable or 'NO'):upper()
            existingCols[name] = {
                name = name,
                dataType = dataType,
                maxLen = maxLen,
                isNullable = isNull,
            }
        end

        -- Safe column modifications:
        -- 1. id: widen INT -> BIGINT if needed
        if existingCols.id and existingCols.id.dataType == 'int' then
            local okMod, errMod = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents MODIFY COLUMN id BIGINT AUTO_INCREMENT')
            end)
            if not okMod then return false, 'alter_id_failed: ' .. tostring(errMod) end
        end

        -- 2. character_id: widen INT -> VARCHAR(50) if needed
        if existingCols.character_id and (existingCols.character_id.dataType ~= 'varchar' or (existingCols.character_id.maxLen or 0) < 50) then
            local okMod, errMod = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents MODIFY COLUMN character_id VARCHAR(50) NOT NULL')
            end)
            if not okMod then return false, 'alter_character_id_failed: ' .. tostring(errMod) end
        end

        -- 3. contract_reference: widen to VARCHAR(64) without truncation
        if existingCols.contract_reference and (existingCols.contract_reference.maxLen or 0) < 64 then
            local okMod, errMod = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents MODIFY COLUMN contract_reference VARCHAR(64) NOT NULL')
            end)
            if not okMod then return false, 'alter_contract_reference_failed: ' .. tostring(errMod) end
        end

        -- 4. status: convert ENUM -> VARCHAR(32) non-destructively
        if existingCols.status and (existingCols.status.dataType == 'enum' or (existingCols.status.maxLen or 0) < 32) then
            local okMod, errMod = pcall(function()
                return MySQL.query.await("ALTER TABLE cm_trucking_payout_intents MODIFY COLUMN status VARCHAR(32) NOT NULL DEFAULT 'earned'")
            end)
            if not okMod then return false, 'alter_status_failed: ' .. tostring(errMod) end
        end

        -- 5. broker_completed_at: add BIGINT NULL if missing; if existing ensure it allows NULL
        if not existingCols.broker_completed_at then
            local okAdd, errAdd = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD COLUMN broker_completed_at BIGINT NULL AFTER status')
            end)
            if not okAdd then return false, 'add_broker_completed_at_failed: ' .. tostring(errAdd) end
        elseif existingCols.broker_completed_at.isNullable == 'NO' then
            local okMod, errMod = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents MODIFY COLUMN broker_completed_at BIGINT NULL')
            end)
            if not okMod then return false, 'modify_broker_completed_at_nullable_failed: ' .. tostring(errMod) end
        end

        -- 6. settled_at: add BIGINT NULL if missing
        if not existingCols.settled_at then
            local okAdd, errAdd = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD COLUMN settled_at BIGINT NULL AFTER broker_completed_at')
            end)
            if not okAdd then return false, 'add_settled_at_failed: ' .. tostring(errAdd) end
        end

        -- 7. settle_attempts: add INT NOT NULL DEFAULT 0 if missing
        if not existingCols.settle_attempts then
            local okAdd, errAdd = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD COLUMN settle_attempts INT NOT NULL DEFAULT 0 AFTER settled_at')
            end)
            if not okAdd then return false, 'add_settle_attempts_failed: ' .. tostring(errAdd) end
        end

        -- 8. last_error: add or widen to VARCHAR(255) NULL
        if not existingCols.last_error then
            local okAdd, errAdd = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD COLUMN last_error VARCHAR(255) NULL AFTER settle_attempts')
            end)
            if not okAdd then return false, 'add_last_error_failed: ' .. tostring(errAdd) end
        elseif existingCols.last_error.dataType == 'varchar' and (existingCols.last_error.maxLen or 0) < 255 then
            local okMod, errMod = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents MODIFY COLUMN last_error VARCHAR(255) NULL')
            end)
            if not okMod then return false, 'widen_last_error_failed: ' .. tostring(errMod) end
        end

        -- 9. created_at & updated_at: add if missing
        if not existingCols.created_at then
            local okAdd, errAdd = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP')
            end)
            if not okAdd then return false, 'add_created_at_failed: ' .. tostring(errAdd) end
        end

        if not existingCols.updated_at then
            local okAdd, errAdd = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP')
            end)
            if not okAdd then return false, 'add_updated_at_failed: ' .. tostring(errAdd) end
        end

        -- 10. Safe index verification
        local okStats, statRows = pcall(function()
            return MySQL.query.await([[
                SELECT INDEX_NAME, COLUMN_NAME, NON_UNIQUE
                FROM INFORMATION_SCHEMA.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_trucking_payout_intents'
            ]])
        end)

        if not okStats or type(statRows) ~= 'table' then
            return false, 'inspect_statistics_failed: ' .. tostring(statRows)
        end

        local existingIndexes = {}
        for _, s in ipairs(statRows) do
            local idxName = tostring(s.INDEX_NAME or s.index_name or ''):lower()
            existingIndexes[idxName] = true
        end

        -- Ensure unique key uq_trucking_char_contract
        if not existingIndexes['uq_trucking_char_contract'] then
            local okIdx, errIdx = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD UNIQUE KEY uq_trucking_char_contract (character_id, contract_reference)')
            end)
            if not okIdx then return false, 'add_unique_key_failed: ' .. tostring(errIdx) end
        end

        -- Ensure index on (character_id, status)
        if not existingIndexes['idx_trucking_pending_payout'] and not existingIndexes['idx_trucking_char_status'] then
            local okIdx, errIdx = pcall(function()
                return MySQL.query.await('ALTER TABLE cm_trucking_payout_intents ADD INDEX idx_trucking_pending_payout (character_id, status)')
            end)
            if not okIdx then return false, 'add_status_index_failed: ' .. tostring(errIdx) end
        end
    end

    -- Startup Crash / Restart Recovery:
    -- Runs strictly AFTER schema migration has successfully completed.
    -- If FXServer or cm-trucking restarted while a settlement was in-flight ('settling'),
    -- we cannot verify whether the external payroll ledger processed it or not.
    -- Move any orphaned 'settling' rows to 'pending_reconciliation' so they are NEVER
    -- blindly retried through a non-idempotent API.
    local okSweep, errSweep = pcall(function()
        return MySQL.query.await([[
            UPDATE cm_trucking_payout_intents
            SET status = 'pending_reconciliation', last_error = 'server_restarted_during_settlement'
            WHERE status = 'settling'
        ]])
    end)

    if not okSweep then
        return false, 'startup_sweep_failed: ' .. tostring(errSweep)
    end

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
        print(('[CM-TRUCKING] CRITICAL: Schema migration failed: %s. Payout operations disabled (fail-closed).'):format(schemaError))
        return false, schemaError
    end

    dbg('Schema migration and backward-compatibility verification complete.')
    return true, nil
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(100)
    end
    ensureSchemaReady()
end)

-- Atomically record an earned payout intent upon broker reward authorization (rewardable == true)
local function recordEarnedPayoutIntent(characterId, contractRef, amount)
    local ready, err = ensureSchemaReady()
    if not ready then
        print(('[CM-TRUCKING] ERROR: Cannot persist payout intent (cid=%s ref=%s): schema not ready (%s)'):format(
            tostring(characterId), tostring(contractRef), tostring(err)
        ))
        return false, 'schema_not_ready'
    end

    characterId = tostring(characterId)
    contractRef = tostring(contractRef)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local now = os.time()
    local ok, res = pcall(function()
        return MySQL.query.await([[
            INSERT INTO cm_trucking_payout_intents (character_id, contract_reference, amount, status, broker_completed_at)
            VALUES (?, ?, ?, 'earned', ?)
            ON DUPLICATE KEY UPDATE amount = VALUES(amount), broker_completed_at = COALESCE(VALUES(broker_completed_at), broker_completed_at)
        ]], { characterId, contractRef, amount, now })
    end)

    if not ok then
        print(('[CM-TRUCKING] ERROR persisting payout intent for cid=%s ref=%s: %s'):format(characterId, contractRef, tostring(res)))
        return false, 'db_error'
    end
    return true
end

-- Fail-closed verification of cm-payday's settlement capabilities.
-- Verified against resources/[core]/cm-payday/server/main.lua:
-- cm-payday exports: AddPendingCash, AddPendingXp, GetPending, GetPlaytimeSeconds, GetSecondsUntilNextPayday.
-- AddPendingCash(src, jobName, amount, reason) increments data.cash directly and discards the reason.
-- It does NOT check or store an idempotency token, transaction hash, or unique reference.
-- Calling it multiple times with the same parameters causes duplicate payments.
-- cm-payday does NOT provide an explicit idempotent payout export or capability.
-- Per project rules, we do not invent or assume an unverified capability name or signature.
local function verifyPaydayIdempotencyCapability()
    if GetResourceState(PAYDAY) ~= 'started' then
        return false, 'payday_offline'
    end

    -- cm-payday currently has no verified idempotent API or capability
    return false, 'no_idempotent_api'
end

-- Settle or safely hold an earned payout intent.
-- Enforces strict fail-closed settlement:
-- 1. Never retries an ambiguous payout through a non-idempotent API.
-- 2. Preserves every earned payout durably in SQL until safe settlement is possible.
-- 3. If cm-payday has no verified idempotent API, leaves the intent durable and
--    visibly blocked for reconciliation in 'pending_reconciliation'.
-- 4. Startup/login recovery cannot turn an accepted-but-unrecorded payment into a duplicate.
local function settlePayoutIntent(src, characterId, intent)
    src = tonumber(src)
    if not src or not intent then return false, 'invalid_args' end
    characterId = tostring(characterId)
    local contractRef = tostring(intent.contract_reference)
    local amount = tonumber(intent.amount) or 0
    if amount <= 0 then return false, 'invalid_amount' end

    -- Verify schema migration is ready before executing queries
    local ready, err = ensureSchemaReady()
    if not ready then
        dbg(('Payout settlement blocked for cid=%s ref=%s: schema not ready (%s)'):format(
            characterId, contractRef, tostring(err)
        ))
        return false, 'schema_not_ready'
    end

    -- Already settled: nothing more to do
    if intent.status == 'settled' then
        return true, 'already_settled'
    end

    -- Already blocked for reconciliation: do not re-attempt automatic settlement
    if intent.status == 'pending_reconciliation' then
        dbg(('Payout intent cid=%s ref=%s is pending_reconciliation; automatic retry blocked'):format(characterId, contractRef))
        return false, 'pending_payroll_integration'
    end

    -- Require an explicit, verified idempotency capability from cm-payday before making an automatic payout call
    local hasIdempotency, capErr = verifyPaydayIdempotencyCapability()
    if not hasIdempotency then
        -- Fail closed: cm-payday has no verified idempotent API.
        -- Update status to 'pending_reconciliation' with reason 'pending_payroll_integration'.
        -- Retains the record durably in SQL, completely eliminating duplicate payment risks.
        pcall(function()
            MySQL.update.await([[
                UPDATE cm_trucking_payout_intents
                SET status = 'pending_reconciliation', last_error = 'pending_payroll_integration'
                WHERE character_id = ? AND contract_reference = ? AND status = 'earned'
            ]], { characterId, contractRef })
        end)

        dbg(('Payout intent cid=%s ref=%s held in pending_reconciliation: cm-payday lacks verified idempotent API (%s)'):format(
            characterId, contractRef, tostring(capErr)
        ))
        return false, 'pending_payroll_integration'
    end

    -- Guard against duplicate concurrent attempts
    local lockKey = ('%s:%s'):format(characterId, contractRef)
    if payoutLocks[lockKey] then
        return false, 'settlement_in_progress'
    end
    payoutLocks[lockKey] = true

    -- Atomic compare-and-swap state transition in SQL: earned -> settling
    local casOk, casRes = pcall(function()
        return MySQL.update.await([[
            UPDATE cm_trucking_payout_intents
            SET status = 'settling', settle_attempts = settle_attempts + 1
            WHERE character_id = ? AND contract_reference = ? AND status = 'earned'
        ]], { characterId, contractRef })
    end)

    if not casOk or not casRes or tonumber(casRes) == 0 then
        payoutLocks[lockKey] = nil
        return false, 'state_conflict'
    end

    -- (If a verified idempotent export is introduced in the future by cm-payday, the call would be placed here)
    payoutLocks[lockKey] = nil
    return false, 'unreachable'
end

-- Recover pending earned payouts for a character (e.g. on character load, dispatcher interact, or depot return)
local function recoverPendingPayoutsForCharacter(src, characterId)
    if not characterId or not src then return end
    characterId = tostring(characterId)

    local ready, err = ensureSchemaReady()
    if not ready then
        dbg(('Payout recovery skipped for cid=%s: schema not ready (%s)'):format(characterId, tostring(err)))
        return
    end

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT id, character_id, contract_reference, amount, status, settle_attempts, last_error
            FROM cm_trucking_payout_intents
            WHERE character_id = ? AND status IN ('earned', 'pending_reconciliation')
        ]], { characterId })
    end)

    if not ok or not rows or #rows == 0 then return end

    local totalPending = 0
    for _, row in ipairs(rows) do
        if row.status == 'earned' then
            -- Transition any un-transitioned 'earned' row to 'pending_reconciliation' fail-closed
            settlePayoutIntent(src, characterId, row)
        end
        totalPending = totalPending + tonumber(row.amount or 0)
    end

    if totalPending > 0 then
        notify(src, ('You have $%d in earned freight payouts stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(totalPending), 'info')
    end
end

-- Listen for character load to automatically notify player of held earnings without retry risk
AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    if not src or not data then return end
    local charId = data.charId or data.characterId
    if charId then
        recoverPendingPayoutsForCharacter(src, charId)
    end
end)

-- =========================================================================
-- Session Queries & Broker Event Handlers
-- =========================================================================

function Server.HasActiveSessionForCharacter(charId)
    charId = tostring(charId)
    for _, session in pairs(Sessions) do
        if session.charId == charId then return true end
    end
    return false
end

function Server.HandleBrokerEvent(reference, characterId, event, reason)
    characterId = tostring(characterId)
    for src, session in pairs(Sessions) do
        if session.charId == characterId and session.contract and session.contract.brokerRef == reference then
            if event == 'lease_expired' or event == 'fallback' or event == 'cancelled' then
                notify(src, ('Freight contract %s ended by broker (%s).'):format(tostring(reference), tostring(reason or event)), 'warning')
                Server.EndShift(src, 'broker_' .. tostring(event))
            end
            break
        end
    end
end

-- =========================================================================
-- Vehicle Management (cm-vehicles & eligible truck detection)
-- =========================================================================

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

local function isEligibleTruckModel(modelHashOrName)
    local models = Config.Vehicle.eligibleModels or {}
    for name, _ in pairs(models) do
        if joaat(name) == modelHashOrName or tostring(name):lower() == tostring(modelHashOrName):lower() then
            return true
        end
    end
    return false
end

local function resolveOrSpawnTruck(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'invalid_player_ped' end

    -- Check if player is already seated in an eligible commercial truck
    local currentVeh = GetVehiclePedIsIn(ped, false)
    if currentVeh and currentVeh ~= 0 and DoesEntityExist(currentVeh) then
        local model = GetEntityModel(currentVeh)
        if isEligibleTruckModel(model) then
            local plate = GetVehicleNumberPlateText(currentVeh)
            local netId = NetworkGetNetworkIdFromEntity(currentVeh)
            return true, {
                entity = currentVeh,
                netId = netId,
                plate = plate,
                isPlayerVehicle = true,
            }
        end
    end

    -- Attempt to check out a depot commercial truck via cm-vehicles
    local api = vehiclesApi()
    if not api then
        return false, 'Vehicle system is offline.'
    end

    local spawns = Config.Depot.truckSpawns
    local chosenSpawn = spawns[1]
    for _, s in ipairs(spawns) do
        chosenSpawn = s
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

    if ok and type(result) == 'table' and result.ok == true and result.entity then
        jobVehicles[src] = {
            plate = result.plate,
            netId = result.netId,
            entity = result.entity,
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

    -- If depot vehicle checkout is rejected (e.g. cm-trucking awaiting authorizedResources allowlist),
    -- inspect nearby player vehicles at the depot
    local pCoords = GetEntityCoords(ped)
    local vehicles = GetAllVehicles()
    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            local vCoords = GetEntityCoords(veh)
            if #(pCoords - vCoords) <= 25.0 and isEligibleTruckModel(GetEntityModel(veh)) then
                local plate = GetVehicleNumberPlateText(veh)
                local netId = NetworkGetNetworkIdFromEntity(veh)
                return true, {
                    entity = veh,
                    netId = netId,
                    plate = plate,
                    isPlayerVehicle = true,
                }
            end
        end
    end

    local why = (ok and type(result) == 'table' and result.error) or 'checkout_unavailable'
    return false, ('Depot truck checkout unavailable (%s). Please drive an eligible commercial hauler to the depot.'):format(tostring(why))
end

-- =========================================================================
-- Session Lifecycle & Cleanup
-- =========================================================================

function Server.EndShift(src, reason)
    local session = Sessions[src]
    if not session then return end

    Sessions[src] = nil
    transitStartTimes[src] = nil

    -- Truck cleanup never deletes or alters durable payout intents in SQL
    if not session.isPlayerVehicle then
        deleteJobVehicle(src)
    end

    TriggerClientEvent('cm-trucking:client:shiftEnded', src, reason or 'shift_concluded')
end

-- =========================================================================
-- Commercial Order Evaluation & Availability Rules
-- =========================================================================
-- A commercial order is claimable ONLY when:
-- 1. Its source publisher provides an authoritative driver payout (> 0).
-- 2. It provides complete cycle timing data (destination coords or route distance)
--    to calculate the complete work cycle (fixed overhead + outbound laden + return unladen).
-- 3. Its effective hourly rate strictly exceeds the municipal baseline ($37,500/hr).
-- Unpaid work is never accepted and deferred to delivery. Missing or sub-baseline
-- orders are shown as unavailable with an explicit reason and cannot be claimed.
local function evaluateCommercialOrder(contract, meta)
    if type(contract) ~= 'table' then
        return false, nil, 'Invalid contract data'
    end
    meta = type(meta) == 'table' and meta or {}

    -- 1. Authoritative Driver Payout Check
    local payout = tonumber(meta.payout or meta.driverPayout or meta.wage or contract.payout)
    if not payout or payout <= 0 then
        return false, nil, 'Awaiting authoritative driver payout tariff from business owner.'
    end
    payout = math.floor(payout)

    -- 2. Complete Work-Cycle Timing Data Check
    local destCoords = meta.destinationCoords
    if not destCoords and contract.destinationCoords then
        destCoords = vector3(contract.destinationCoords.x, contract.destinationCoords.y, contract.destinationCoords.z)
    end

    local distanceMeters = nil
    if destCoords and type(destCoords) == 'vector3' then
        local pickupCoords = meta.pickupCoords or Config.Depot.pickupBay.coords
        distanceMeters = #(destCoords - pickupCoords)
    elseif type(destCoords) == 'table' and destCoords.x and destCoords.y and destCoords.z then
        local pickupCoords = meta.pickupCoords or Config.Depot.pickupBay.coords
        distanceMeters = #(vector3(destCoords.x, destCoords.y, destCoords.z) - vector3(pickupCoords.x, pickupCoords.y, pickupCoords.z))
    elseif tonumber(meta.distanceKm or contract.distanceKm) then
        distanceMeters = tonumber(meta.distanceKm or contract.distanceKm) * 1000.0
    end

    local fullCycleSec = nil
    if tonumber(meta.estimatedCycleSeconds or contract.estimatedCycleSeconds) then
        fullCycleSec = tonumber(meta.estimatedCycleSeconds or contract.estimatedCycleSeconds)
    elseif distanceMeters and distanceMeters > 0 then
        -- 95 sec fixed overhead: dispatch manifest (20s) + depot coupling/brake test (30s) + destination uncoupling/staging (30s) + depot return/sign-off (15s)
        local fixedOverheadSec = 95
        -- Freight speeds: 19.4 m/s laden outbound (~70 km/h), 20.8 m/s unladen return (~75 km/h)
        local outboundSec = distanceMeters / 19.4
        local returnSec = distanceMeters / 20.8
        fullCycleSec = math.ceil(fixedOverheadSec + outboundSec + returnSec)
    end

    if not fullCycleSec or fullCycleSec <= 0 then
        return false, nil, 'Awaiting verified delivery coordinates or route distance from publisher to calculate work-cycle duration.'
    end

    -- 3. Rate Calculation & Baseline Comparison
    local effectiveHourlyRate = (payout / fullCycleSec) * 3600.0
    local baselineHourly = (Config.Economy and Config.Economy.targetHourly) or 37500

    if effectiveHourlyRate <= baselineHourly then
        return false, nil, ('Offered compensation ($%d, ~$%.0f/hr) does not exceed the municipal freight baseline of $%d/hr.'):format(
            payout, effectiveHourlyRate, baselineHourly
        )
    end

    return true, {
        payout = payout,
        cycleDurationSec = fullCycleSec,
        effectiveHourlyRate = math.floor(effectiveHourlyRate + 0.5),
        distanceKm = distanceMeters and (distanceMeters / 1000.0) or nil,
        destinationCoords = destCoords,
    }, 'Valid commercial order'
end

-- =========================================================================
-- Net Events
-- =========================================================================

-- Player interacts with dispatcher Arthur Briggs: fetch real published broker contracts
RegisterNetEvent('cm-trucking:server:openDispatcher', function()
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
    local brokerCoords = vector3(Config.Depot.broker.coords.x, Config.Depot.broker.coords.y, Config.Depot.broker.coords.z)
    if #(pCoords - brokerCoords) > (Config.Security.brokerDistance or 3.2) + 2.0 then
        notify(src, 'You are too far from the freight dispatcher.', 'error')
        return
    end

    local session = Sessions[src]
    local choices = {}
    local quote = ''

    if not session then
        -- Automatically recover any pending earned payouts first
        recoverPendingPayoutsForCharacter(src, charId)

        -- Query real published business supply contracts from cm-contracts
        local okBroker, brokerContracts = Adapter.ListAvailableContracts(charId, { contractType = 'business_supply' })
        local publishedCount = 0
        local availableCommercialCount = 0

        if okBroker and type(brokerContracts) == 'table' then
            for _, bc in ipairs(brokerContracts) do
                -- Enforce real contract source: must be business_supply from broker
                if bc.reference and bc.contractType == 'business_supply' then
                    publishedCount = publishedCount + 1
                    local meta = bc.metadata or {}
                    local isClaimable, evalInfo, evalReason = evaluateCommercialOrder(bc, meta)

                    if isClaimable then
                        availableCommercialCount = availableCommercialCount + 1
                        choices[#choices + 1] = {
                            id = bc.reference,
                            label = ('[PREMIUM - BUSINESS ORDER] %s'):format(bc.title or ('Supply Delivery: ' .. tostring(bc.reference))),
                            description = ('Commercial Freight Manifest - Broker Ref: %s - Payout: $%d (~$%d/hr) - Claimable'):format(
                                bc.reference, evalInfo.payout, evalInfo.effectiveHourlyRate
                            ),
                            event = 'cm-trucking:client:dialogueChoice',
                            payload = { action = 'select_contract', contractId = bc.reference, isBroker = true },
                        }
                    else
                        -- Show as UNAVAILABLE with clear, authoritative reason (prevent claiming)
                        choices[#choices + 1] = {
                            id = 'unavail_' .. bc.reference,
                            label = ('[COMMERCIAL ORDER - UNAVAILABLE] %s'):format(bc.title or ('Supply Delivery: ' .. tostring(bc.reference))),
                            description = ('Broker Ref: %s - UNAVAILABLE: %s'):format(bc.reference, evalReason),
                            event = 'cm-trucking:client:dialogueChoice',
                            payload = {
                                action = 'commercial_unavailable',
                                contractRef = bc.reference,
                                reason = ('Commercial order %s is currently unavailable: %s'):format(bc.reference, evalReason),
                            },
                        }
                    end
                end
            end
        end

        if publishedCount == 0 then
            -- Section clearly shown and marked unavailable when no commercial contracts exist
            choices[#choices + 1] = {
                id = 'premium_none_published',
                label = '[PREMIUM - COMMERCIAL FREIGHT CONTRACTS] (No Active Contracts)',
                description = 'No private commercial freight or business supply contracts are currently published. Municipal city freight routes are available.',
                event = 'cm-trucking:client:dialogueChoice',
                payload = { action = 'commercial_unavailable', reason = 'No commercial supply contracts are currently published by private businesses.' },
            }
        end

        -- Always-available repeatable municipal freight routes (City / NPC Work)
        if Config.CityRoutes and type(Config.CityRoutes) == 'table' then
            for _, route in ipairs(Config.CityRoutes) do
                choices[#choices + 1] = {
                    id = route.id,
                    label = route.title or ('[CITY FREIGHT] Municipal Route ' .. route.id),
                    description = ('%s (%s km) - Cargo: %s - Payout: $%d [Held in durable ledger; cash cannot currently be collected in-game]'):format(
                        route.description or 'Municipal delivery', tostring(route.distanceKm or 0), route.cargo or 'General Cargo', route.basePayout or 2865
                    ),
                    event = 'cm-trucking:client:dialogueChoice',
                    payload = { action = 'select_contract', contractId = route.id, isCityFreight = true },
                }
            end
        end

        if availableCommercialCount > 0 then
            quote = ('Terminal Island Logistics has %d active commercial business order(s) available with verified driver wages, alongside ongoing municipal city routes (payout stored in durable ledger; cash cannot currently be collected in-game). Select an assignment.'):format(availableCommercialCount)
        elseif publishedCount > 0 then
            quote = ('Terminal Island Logistics has %d commercial order(s) listed, but they are currently unavailable due to missing driver tariffs or route data. Municipal city routes are fully operational (payout stored in durable ledger; cash cannot currently be collected in-game).'):format(publishedCount)
        else
            quote = 'No player or business broker contracts are currently published. Municipal city freight routes are available on the dispatch board (payout stored in durable ledger; cash cannot currently be collected in-game).'
        end
    else
        quote = 'How is the haul progressing, driver? Keep that cargo strapped down and watch your speed on the highway.'
        choices[#choices + 1] = {
            id = 'cancel',
            label = 'Abort Contract & Hand in Truck',
            description = 'Cancel your active freight assignment and return truck to the yard',
            event = 'cm-trucking:client:dialogueChoice',
            payload = { action = 'cancel' },
        }
    end

    choices[#choices + 1] = {
        id = 'info',
        label = 'Commercial Freight Regulations',
        description = 'Learn about loading docks, securing cargo, delivery protocols, and payroll settlement',
        event = 'cm-trucking:client:dialogueChoice',
        payload = { action = 'info' },
    }

    TriggerClientEvent('cm-trucking:client:receiveDispatcherChoices', src, choices, quote)
end)

-- Player selects a contract to begin shift
RegisterNetEvent('cm-trucking:server:selectContract', function(contractId)
    local src = source
    if onCooldown(src, 2000) then return end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Character identity not loaded.', 'error')
        return
    end

    if Sessions[src] then
        notify(src, 'You already have an active freight contract in progress.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)
    local brokerCoords = vector3(Config.Depot.broker.coords.x, Config.Depot.broker.coords.y, Config.Depot.broker.coords.z)
    if #(pCoords - brokerCoords) > (Config.Security.brokerDistance or 3.2) + 2.0 then
        notify(src, 'You must be at the Terminal Island dispatcher desk to select a contract.', 'error')
        return
    end

    -- Support both always-available City Routes and authentic Broker Contracts
    local contract = nil

    if type(contractId) == 'string' and contractId:sub(1, 11) == 'CITY-ROUTE-' then
        local cityRoute = nil
        if Config.CityRoutes then
            for _, route in ipairs(Config.CityRoutes) do
                if route.id == contractId then
                    cityRoute = route
                    break
                end
            end
        end

        if not cityRoute then
            notify(src, 'Invalid municipal freight route selected.', 'error')
            return
        end

        contract = {
            id = cityRoute.id,
            brokerRef = nil,
            isBroker = false,
            isCityFreight = true,
            label = cityRoute.title,
            cargo = cityRoute.cargo,
            cargoClass = cityRoute.cargoClass or 'Municipal Supply',
            tier = 'established',
            distanceKm = cityRoute.distanceKm or 5.0,
            payout = cityRoute.basePayout or 2865,
            pickupCoords = Config.Depot.pickupBay.coords,
            destinationCoords = cityRoute.destinationCoords,
            destinationLabel = cityRoute.destinationLabel,
            manifestLines = nil,
        }
    elseif type(contractId) == 'string' and contractId:sub(1, 3) == 'CT-' then
        local okClaim, claimResult = Adapter.ClaimContract(contractId, charId, { providerRef = 'trucking_' .. src })
        if not okClaim then
            notify(src, ('Unable to claim contract: %s'):format(tostring(claimResult or 'rejected')), 'error')
            return
        end

        local brokerRef = claimResult.reference
        local meta = claimResult.metadata or {}

        -- Evaluate authoritative payout and complete work-cycle duration
        local isClaimable, evalInfo, evalReason = evaluateCommercialOrder(claimResult, meta)
        if not isClaimable then
            -- Safely release the contract so it remains on the broker board
            Adapter.ReleaseContract(brokerRef, charId, 'unmet_commercial_criteria')
            notify(src, ('Commercial contract cannot be claimed: %s'):format(evalReason), 'error')
            return
        end

        contract = {
            id = brokerRef,
            brokerRef = brokerRef,
            isBroker = true,
            isCityFreight = false,
            label = claimResult.title or 'Business Supply Order',
            cargo = claimResult.description or 'Commercial Stock Delivery',
            cargoClass = claimResult.cargoClass or 'general',
            tier = 'established',
            distanceKm = evalInfo.distanceKm or 5.0,
            payout = evalInfo.payout,
            payoutHeld = false,
            pickupCoords = meta.pickupCoords or Config.Depot.pickupBay.coords,
            destinationCoords = evalInfo.destinationCoords,
            destinationLabel = claimResult.destinationHint or 'Commercial Business Location',
            manifestLines = meta.manifest or nil,
        }
    else
        notify(src, 'Invalid contract selection. Only verified published business contracts or municipal routes are available.', 'error')
        return
    end

    local okVeh, vehInfo = resolveOrSpawnTruck(src)
    if not okVeh then
        if contract.isBroker and contract.brokerRef then
            Adapter.ReleaseContract(contract.brokerRef, charId, 'vehicle_unavailable')
        end
        notify(src, tostring(vehInfo), 'error')
        return
    end

    Sessions[src] = {
        src = src,
        charId = charId,
        contract = contract,
        state = Config.ContractState.Selected,
        truckNetId = vehInfo.netId,
        truckPlate = vehInfo.plate,
        truckEntity = vehInfo.entity,
        isPlayerVehicle = vehInfo.isPlayerVehicle,
        loadingStartedAt = nil,
        transitStartedAt = nil,
        deliveredAt = nil,
        pendingReward = contract.payout or 0,
        rewardAuthorized = false,
        payrollSettled = false,
    }

    notify(src, ('Manifest assigned: %s ($%d earned upon return, payout stored in durable ledger; cash cannot currently be collected in-game). Drive to loading dock.'):format(contract.label, contract.payout or 0), 'info')

    TriggerClientEvent('cm-trucking:client:contractStarted', src, {
        contract = contract,
        truckNetId = vehInfo.netId,
        truckPlate = vehInfo.plate,
        state = Config.ContractState.Selected,
        hasPendingDelivery = false,
    })
end)

-- Player arrives at container loading dock and secures cargo
RegisterNetEvent('cm-trucking:server:loadCargo', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local session = Sessions[src]
    if not session or session.state ~= Config.ContractState.Selected then
        notify(src, 'No active contract pending cargo loading.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)

    local pickupCoords = session.contract.pickupCoords or Config.Depot.pickupBay.coords
    local distPed = #(pCoords - pickupCoords)

    local truck = session.truckEntity
    local truckDist = 999.0
    if truck and DoesEntityExist(truck) then
        truckDist = #(GetEntityCoords(truck) - pickupCoords)
    end

    if distPed > (Config.Security.pickupBayDistance or 14.0) and truckDist > (Config.Security.pickupBayDistance or 14.0) then
        notify(src, 'You must position the commercial hauler inside the cargo loading dock.', 'error')
        return
    end

    session.state = Config.ContractState.Loading
    session.loadingStartedAt = GetGameTimer()

    TriggerClientEvent('cm-trucking:client:startCargoLoading', src, {})

    SetTimeout(Config.Depot.pickupBay.loadDurationMs or 8000, function()
        local currentSession = Sessions[src]
        if not currentSession or currentSession.state ~= Config.ContractState.Loading then return end

        currentSession.state = Config.ContractState.InTransit
        currentSession.transitStartedAt = GetGameTimer()
        transitStartTimes[src] = GetGameTimer()

        -- Advance broker contract to 'active' state
        if currentSession.contract.isBroker and currentSession.contract.brokerRef then
            Adapter.MarkContractActive(currentSession.contract.brokerRef, currentSession.charId, {
                providerRef = 'trucking_' .. src
            })
        end

        notify(src, 'Cargo containers locked and secured. Transport to the delivery destination.', 'success')

        TriggerClientEvent('cm-trucking:client:cargoLoaded', src, {
            contract = currentSession.contract,
            destinationCoords = currentSession.contract.destinationCoords,
            destinationLabel = currentSession.contract.destinationLabel,
        })
    end)
end)

-- Player arrives at delivery destination and unloads cargo
RegisterNetEvent('cm-trucking:server:deliverCargo', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local session = Sessions[src]
    if not session or session.state ~= Config.ContractState.InTransit then
        notify(src, 'No active haul in transit to deliver.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)

    local destCoords = session.contract.destinationCoords
    local distPed = #(pCoords - destCoords)

    local truck = session.truckEntity
    local truckDist = 999.0
    if truck and DoesEntityExist(truck) then
        truckDist = #(GetEntityCoords(truck) - destCoords)
    end

    if distPed > (Config.Security.destinationBayDistance or 14.0) and truckDist > (Config.Security.destinationBayDistance or 14.0) then
        notify(src, 'Your truck is not at the verified destination unloading bay.', 'error')
        return
    end

    local transitTime = GetGameTimer() - (session.transitStartedAt or 0)
    if transitTime < (Config.Security.minimumTransitTimeMs or 25000) then
        dbg(('Suspicious rapid delivery from src %s: transit time %d ms'):format(tostring(src), transitTime))
        notify(src, 'Transit time too brief. Ensure complete route transit.', 'warning')
        return
    end

    TriggerClientEvent('cm-trucking:client:startCargoUnloading', src, {})

    local unloadMs = session.contract.unloadDurationMs or 6000
    SetTimeout(unloadMs, function()
        local currentSession = Sessions[src]
        if not currentSession or currentSession.state ~= Config.ContractState.InTransit then return end

        currentSession.state = Config.ContractState.Delivered
        currentSession.deliveredAt = GetGameTimer()

        if currentSession.contract.isCityFreight then
            -- Server-authoritative transit time and distance checks already passed above
            currentSession.rewardAuthorized = true
            currentSession.pendingReward = currentSession.contract.payout or 2865

            -- Generate unique municipal ledger reference: CITY-<route_id>-<charId>-<timestamp>
            local cityRef = ('%s-%s-%s'):format(currentSession.contract.id, tostring(currentSession.charId), tostring(os.time()))
            currentSession.contract.brokerRef = cityRef -- Used as ledger reference in cm_trucking_payout_intents

            -- DURABLE REWARD PERSISTENCE:
            -- Record earned payout intent in SQL immediately before any session or vehicle state changes
            recordEarnedPayoutIntent(currentSession.charId, cityRef, currentSession.pendingReward)

            notify(src, 'Municipal delivery confirmed. Return to Terminal Island to check in manifest.', 'success')
        else
            -- Execute CompleteContract through the broker
            local payload = nil
            if currentSession.contract.manifestLines then
                payload = { lines = currentSession.contract.manifestLines }
            end

            local okComplete, completeRes = Adapter.CompleteContract(
                currentSession.contract.brokerRef,
                currentSession.charId,
                payload
            )

            if okComplete and type(completeRes) == 'table' and completeRes.rewardable == true then
                local approvedPayout = currentSession.contract.payout
                if approvedPayout and approvedPayout > 0 then
                    currentSession.rewardAuthorized = true
                    currentSession.pendingReward = approvedPayout

                    -- DURABLE REWARD PERSISTENCE:
                    recordEarnedPayoutIntent(currentSession.charId, currentSession.contract.brokerRef, currentSession.pendingReward)
                    notify(src, 'Commercial delivery receipt confirmed by broker. Return to Terminal Island to check in manifest.', 'success')
                else
                    -- No approved premium driver reward rule published by business owner: hold fail-closed
                    currentSession.rewardAuthorized = false
                    currentSession.pendingReward = 0
                    currentSession.payoutHeld = true
                    notify(src, 'Commercial delivery confirmed by broker. Driver payout is held pending economy owner decision on wholesale freight compensation.', 'info')
                end
            elseif okComplete and type(completeRes) == 'table' and completeRes.replayed == true then
                currentSession.rewardAuthorized = false
                notify(src, 'Delivery already recorded. Return to depot.', 'info')
            else
                currentSession.rewardAuthorized = false
                local err = (type(completeRes) == 'string' and completeRes) or 'source_rejected'
                notify(src, ('Delivery verification failed: %s'):format(err), 'error')
                TriggerClientEvent('cm-trucking:client:contractFailed', src, { error = err })
                return
            end
        end

        TriggerClientEvent('cm-trucking:client:cargoDelivered', src, {
            contract = currentSession.contract,
            returnBayCoords = Config.Depot.returnBay.coords,
        })
    end)
end)

-- Player returns to Terminal Island depot return bay to check in manifest and conclude shift
RegisterNetEvent('cm-trucking:server:completeContract', function()
    local src = source
    if onCooldown(src, 2000) then return end

    local session = Sessions[src]
    if not session or session.state ~= Config.ContractState.Delivered then
        notify(src, 'No delivered contract awaiting manifest check-in.', 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pCoords = GetEntityCoords(ped)

    local returnBay = Config.Depot.returnBay.coords
    local distPed = #(pCoords - returnBay)

    local truck = session.truckEntity
    local truckDist = 999.0
    if truck and DoesEntityExist(truck) then
        truckDist = #(GetEntityCoords(truck) - returnBay)
    end

    if distPed > (Config.Security.depotReturnDistance or 14.0) and truckDist > (Config.Security.depotReturnDistance or 14.0) then
        notify(src, 'You must park the truck at the Terminal Island return bay.', 'error')
        return
    end

    local charId = session.charId
    local contractRef = session.contract.brokerRef or session.contract.id
    local payout = session.pendingReward or 0

    -- Attempt payday settlement for this contract's earned intent
    local intent = {
        contract_reference = contractRef,
        amount = payout,
        status = 'earned',
    }
    local settled, settleErr = settlePayoutIntent(src, charId, intent)

    session.state = Config.ContractState.Completed

    -- Cleanup job truck: deleting the truck does NOT delete or alter the SQL payout intent row
    if not session.isPlayerVehicle then
        deleteJobVehicle(src)
    end

    TriggerClientEvent('cm-trucking:client:contractCompleted', src, {
        payout = payout,
        payoutSuccessful = settled,
        status = settleErr or (settled and 'settled' or 'pending'),
    })

    Sessions[src] = nil
    transitStartTimes[src] = nil

    if session.payoutHeld then
        notify(src, ('Work completed [Ref: %s] — driver payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(contractRef), 'info')
    elseif settled then
        notify(src, ('Work completed [Ref: %s] — $%d recorded in durable ledger (ledger record only; cash payment is not confirmed by this job).'):format(contractRef, payout), 'info')
    elseif settleErr == 'pending_payroll_integration' or settleErr == 'pending_reconciliation' then
        notify(src, ('Work completed [Ref: %s] — $%d payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(contractRef, payout), 'info')
    else
        notify(src, ('Work completed [Ref: %s] — payout stored in durable ledger (cash cannot currently be collected in-game pending safe payroll integration).'):format(contractRef), 'info')
    end
end)

-- Player cancels shift voluntarily at Arthur Briggs
RegisterNetEvent('cm-trucking:server:cancelShift', function()
    local src = source
    local session = Sessions[src]
    if not session then
        notify(src, 'You are not currently on shift.', 'info')
        return
    end

    if session.contract and session.contract.isBroker and session.contract.brokerRef then
        Adapter.ReleaseContract(session.contract.brokerRef, session.charId, 'player_cancelled')
    end

    notify(src, 'Freight contract aborted. Truck returned to depot yard.', 'info')
    Server.EndShift(src, 'player_cancelled')
end)

-- Player disconnect handling
AddEventHandler('playerDropped', function()
    local src = source
    local session = Sessions[src]
    if not session then return end

    if session.contract and session.contract.isBroker and session.charId then
        Adapter.ReportWorkerDisconnected(session.charId)
    end

    if not session.isPlayerVehicle then
        deleteJobVehicle(src)
    end

    Sessions[src] = nil
    transitStartTimes[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, _ in pairs(Sessions) do
        deleteJobVehicle(src)
    end
end)

