-- cm-lumber/server/main.lua
-- Server-Authoritative Paleto Forest Timber Harvesting & Sawmill Controller.
--
-- Architecture & Integrity:
-- - Server maintains authoritative shift state, tree stand cooldowns, and haul capacities.
-- - Durable Manifests:
--   Closed shift manifests are persisted into MySQL table `cm_lumber_manifests` before session
--   clearing. If persistence fails, the session is retained fail-closed.
--   Duplicate close-out requests are blocked by concurrency locks and database unique constraints.
-- - Sawmill Recipe Authority:
--   cm-crafting owns recipe 'materials:saw_timber'. Since cm-lumber is not an authorized trusted
--   owner in cm-crafting, local 2-log-to-3-timber conversion is strictly DISABLED fail-closed.
--   Raw logs are kept safely held in the mill ledger. No timber is issued.
-- - Value Handling:
--   Catalog reference values are not cash prices or approved rewards. No economic reference values,
--   wages, or material sale prices are calculated or reported in manifests.

local Config = CMLumber.Config
CMLumber = CMLumber or {}
CMLumber.Server = CMLumber.Server or {}
local Server = CMLumber.Server

local PLAYERDATA = 'cm-playerdata'
local HUD = 'cm-hud'

-- Authoritative server state
-- Sessions[src] = {
--     src = number,
--     charId = string,
--     clockInTime = number,
--     logsHarvested = number,
--     timberProcessed = number,
--     haulLogs = number,
--     haulTimber = number,
--     isFelling = boolean,
--     fellingNodeId = number|nil,
--     fellingStartTime = number|nil,
--     isProcessing = boolean,
--     processStartTime = number|nil,
-- }
local Sessions = {}
local NodeCooldowns = {}   -- [nodeId] = gameTimerExpiry
local RateLimits = {}      -- [src] = gameTimerExpiry
local CloseOutLocks = {}   -- [src or charId] = true

local schemaReady = false

-- ---------------------------------------------------------------------------
-- Idempotent Schema Management
-- ---------------------------------------------------------------------------

local function ensureSchema()
    if schemaReady then return true end
    if not MySQL then return false end

    local sql = [[
        CREATE TABLE IF NOT EXISTS cm_lumber_manifests (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            manifest_id VARCHAR(64) NOT NULL,
            character_id BIGINT NOT NULL,
            duration_seconds INT NOT NULL DEFAULT 0,
            logs_harvested INT NOT NULL DEFAULT 0,
            timber_processed INT NOT NULL DEFAULT 0,
            haul_logs_remaining INT NOT NULL DEFAULT 0,
            haul_timber_remaining INT NOT NULL DEFAULT 0,
            status VARCHAR(32) NOT NULL DEFAULT 'HELD_IN_LEDGER',
            notes VARCHAR(255) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_cm_lumber_manifest_id (manifest_id),
            KEY idx_cm_lumber_char (character_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]

    local ok, err = pcall(function()
        MySQL.query.await(sql)
    end)

    if not ok then
        print(('^1[CM-LUMBER] DATABASE NOT READY: manifest schema creation failed: %s^7'):format(tostring(err)))
        return false
    end

    schemaReady = true
    return true
end

CreateThread(function()
    Wait(500)
    ensureSchema()
end)

-- ---------------------------------------------------------------------------
-- Internal Helpers
-- ---------------------------------------------------------------------------

local function dbg(...)
    if Config.Debug then
        print('^3[CM-LUMBER:SERVER]^7', ...)
    end
end

local function notify(src, message, kind)
    if GetResourceState(HUD) == 'started' then
        pcall(function()
            TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info')
        end)
    else
        TriggerClientEvent('cm-lumber:client:notify', src, message, kind or 'info')
    end
end

local function getCharId(src)
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    local ok, charId = pcall(function()
        return exports[PLAYERDATA]:GetCharacterId(src)
    end)
    if ok and charId and tostring(charId) ~= '' then
        return tostring(charId)
    end
    return nil
end

local function isRateLimited(src, ms)
    local now = GetGameTimer()
    if (RateLimits[src] or 0) > now then return true end
    RateLimits[src] = now + (tonumber(ms) or 1000)
    return false
end

local function getPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

local function syncSession(src)
    local session = Sessions[src]
    if not session then
        TriggerClientEvent('cm-lumber:client:syncState', src, nil)
        return
    end

    TriggerClientEvent('cm-lumber:client:syncState', src, {
        onShift = true,
        clockInTime = session.clockInTime,
        logsHarvested = session.logsHarvested,
        timberProcessed = session.timberProcessed,
        haulLogs = session.haulLogs,
        haulTimber = session.haulTimber,
        maxHaulLogs = Config.Harvesting.maxHaulLogCapacity,
    })
end

-- ---------------------------------------------------------------------------
-- Shift Lifecycle: Clock In & Durable Clock Out
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-lumber:server:clockIn', function()
    local src = source
    if isRateLimited(src, 1500) then return end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Unable to verify character identity with forestry services.', 'error')
        return
    end

    if Sessions[src] then
        notify(src, 'You are already clocked in for a forestry shift.', 'warning')
        return
    end

    local coords = getPlayerCoords(src)
    if not coords then return end

    local foremanCoords = vector3(Config.Foreman.coords.x, Config.Foreman.coords.y, Config.Foreman.coords.z)
    local dist = #(coords - foremanCoords)
    if dist > 15.0 then
        notify(src, 'You must be at the Paleto Sawmill office to clock in.', 'error')
        return
    end

    Sessions[src] = {
        src = src,
        charId = charId,
        clockInTime = os.time(),
        logsHarvested = 0,
        timberProcessed = 0,
        haulLogs = 0,
        haulTimber = 0,
        isFelling = false,
        fellingNodeId = nil,
        fellingStartTime = nil,
        isProcessing = false,
        processStartTime = nil,
    }

    dbg(('Worker %s (CID: %s) clocked in at Paleto Sawmill.'):format(src, charId))
    notify(src, 'Clocked in for forestry duty. Fell marked timber stands and haul logs to the mill deck.', 'success')
    syncSession(src)
end)

RegisterNetEvent('cm-lumber:server:clockOut', function()
    local src = source
    if isRateLimited(src, 1500) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You do not have an active forestry shift.', 'warning')
        return
    end

    local charId = session.charId
    if CloseOutLocks[src] or CloseOutLocks[charId] then
        notify(src, 'Shift close-out is already in progress.', 'warning')
        return
    end

    local coords = getPlayerCoords(src)
    if not coords then return end

    local foremanCoords = vector3(Config.Foreman.coords.x, Config.Foreman.coords.y, Config.Foreman.coords.z)
    local dist = #(coords - foremanCoords)
    if dist > 15.0 then
        notify(src, 'Return to the Sawmill office deck to file your shift manifest.', 'error')
        return
    end

    -- Concurrency lock to prevent duplicate manifest creation
    CloseOutLocks[src] = true
    CloseOutLocks[charId] = true

    local function releaseLocks()
        CloseOutLocks[src] = nil
        CloseOutLocks[charId] = nil
    end

    -- Ensure SQL persistence is available before clearing session
    if not schemaReady and not ensureSchema() then
        releaseLocks()
        print(('^1[CM-LUMBER] DATABASE NOT READY: Manifest persistence blocked for worker %s (CID: %s). Session retained.^7'):format(src, charId))
        notify(src, 'Database service is currently unavailable. Shift session retained.', 'error')
        return
    end

    local shiftDuration = os.time() - session.clockInTime
    local logs = session.logsHarvested
    local timber = session.timberProcessed
    local haulLogs = session.haulLogs
    local haulTimber = session.haulTimber

    -- Deterministic, unique manifest identifier
    local manifestId = ('LUMBER-%s-%s'):format(charId, session.clockInTime)

    -- Attempt SQL persistence before clearing session state
    local insertOk, insertRes = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO cm_lumber_manifests
            (manifest_id, character_id, duration_seconds, logs_harvested, timber_processed, haul_logs_remaining, haul_timber_remaining, status, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            manifestId,
            tonumber(charId),
            shiftDuration,
            logs,
            timber,
            haulLogs,
            haulTimber,
            'HELD_IN_LEDGER',
            'Materials and payroll held pending downstream sink and idempotent settlement integration.'
        })
    end)

    if not insertOk or not insertRes then
        local errStr = tostring(insertRes or 'unknown')
        -- Handle idempotent retry if manifest was already recorded
        if errStr:find('Duplicate entry') then
            dbg(('Manifest %s was already persisted. Closing session idempotently.'):format(manifestId))
        else
            releaseLocks()
            print(('^1[CM-LUMBER] DATABASE ERROR: Failed to persist manifest %s for char %s: %s. Session retained fail-closed.^7'):format(
                manifestId, charId, errStr
            ))
            notify(src, 'Database error: Could not persist shift manifest. Session retained. Please try again.', 'error')
            return
        end
    end

    -- Persistence confirmed: safely clear session
    Sessions[src] = nil
    releaseLocks()

    local manifest = {
        manifestId = manifestId,
        charId = charId,
        durationSeconds = shiftDuration,
        logsHarvested = logs,
        timberProcessed = timber,
        haulLogsRemaining = haulLogs,
        haulTimberRemaining = haulTimber,
        status = 'HELD_IN_LEDGER',
        persisted = true,
        timestamp = os.time(),
    }

    dbg(('Worker %s clocked out. Persisted Manifest %s: %d logs, %d timber (HELD_IN_LEDGER).'):format(
        src, manifestId, logs, timber
    ))

    TriggerClientEvent('cm-lumber:client:shiftConcluded', src, manifest)
    notify(src, ('Shift concluded. Felled Logs: %d. Manifest %s securely filed in mill database.'):format(logs, manifestId), 'success')
    syncSession(src)
end)

-- ---------------------------------------------------------------------------
-- Physical Felling Gameplay (Tree Node Harvesting)
-- ---------------------------------------------------------------------------

local function getNodeConfig(nodeId)
    for _, node in ipairs(Config.LoggingNodes) do
        if node.id == nodeId then return node end
    end
    return nil
end

RegisterNetEvent('cm-lumber:server:requestFelling', function(nodeId)
    local src = source
    if isRateLimited(src, 500) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You must clock in with the Foreman before felling trees.', 'error')
        return
    end

    if session.isFelling or session.isProcessing then
        notify(src, 'You are already performing a forestry operation.', 'warning')
        return
    end

    local node = getNodeConfig(tonumber(nodeId))
    if not node then
        notify(src, 'Invalid timber stand location.', 'error')
        return
    end

    local coords = getPlayerCoords(src)
    if not coords then return end

    local dist = #(coords - node.coords)
    if dist > (node.radius + 3.0) then
        notify(src, 'You are too far from the marked timber stand.', 'error')
        return
    end

    local now = GetGameTimer()
    local expiry = NodeCooldowns[node.id] or 0
    if expiry > now then
        local remainingSec = math.ceil((expiry - now) / 1000)
        notify(src, ('This timber stand was recently harvested. Regrowth in %d s.'):format(remainingSec), 'warning')
        return
    end

    if (session.haulLogs + Config.Harvesting.logYieldPerNode) > Config.Harvesting.maxHaulLogCapacity then
        notify(src, 'Haul capacity full! Transport your logs to the sawmill deck before felling more.', 'warning')
        return
    end

    session.isFelling = true
    session.fellingNodeId = node.id
    session.fellingStartTime = now

    dbg(('Worker %s started felling at Stand #%d.'):format(src, node.id))
    TriggerClientEvent('cm-lumber:client:startFellingApproved', src, {
        nodeId = node.id,
        durationMs = Config.Harvesting.durationMs,
    })
end)

RegisterNetEvent('cm-lumber:server:completeFelling', function()
    local src = source
    local session = Sessions[src]
    if not session or not session.isFelling then
        return
    end

    local nodeId = session.fellingNodeId
    local node = getNodeConfig(nodeId)
    local startTime = session.fellingStartTime or 0
    local elapsed = GetGameTimer() - startTime

    session.isFelling = false
    session.fellingNodeId = nil
    session.fellingStartTime = nil

    if not node then return end

    -- Anti-speedhack threshold validation
    if elapsed < Config.Harvesting.minDurationMs then
        dbg(('Worker %s failed anti-speedhack on stand #%d (elapsed %d ms, min %d ms)'):format(
            src, nodeId, elapsed, Config.Harvesting.minDurationMs
        ))
        notify(src, 'Felling interrupted: action duration invalid.', 'error')
        return
    end

    local coords = getPlayerCoords(src)
    if not coords then return end

    local dist = #(coords - node.coords)
    if dist > (node.radius + 4.0) then
        notify(src, 'Felling interrupted: moved too far from the timber stand.', 'error')
        return
    end

    -- Verify capacity constraint
    local yieldAmount = Config.Harvesting.logYieldPerNode
    if (session.haulLogs + yieldAmount) > Config.Harvesting.maxHaulLogCapacity then
        notify(src, 'Haul capacity full! Transport your logs to the sawmill deck.', 'warning')
        return
    end

    -- Apply server-authoritative node cooldown
    NodeCooldowns[node.id] = GetGameTimer() + Config.Harvesting.nodeCooldownMs
    TriggerClientEvent('cm-lumber:client:updateNodeCooldown', -1, node.id, NodeCooldowns[node.id])

    -- Update authoritative shift state
    session.haulLogs = session.haulLogs + yieldAmount
    session.logsHarvested = session.logsHarvested + yieldAmount

    dbg(('Worker %s completed felling Stand #%d. Total logs: %d, Haul: %d/%d.'):format(
        src, node.id, session.logsHarvested, session.haulLogs, Config.Harvesting.maxHaulLogCapacity
    ))

    notify(src, ('Felled timber stand! Acquired %dx Raw Logs. [Haul: %d/%d]'):format(
        yieldAmount, session.haulLogs, Config.Harvesting.maxHaulLogCapacity
    ), 'success')

    syncSession(src)
end)

RegisterNetEvent('cm-lumber:server:cancelFelling', function()
    local src = source
    local session = Sessions[src]
    if session and session.isFelling then
        session.isFelling = false
        session.fellingNodeId = nil
        session.fellingStartTime = nil
        dbg(('Worker %s cancelled felling action.'):format(src))
    end
end)

-- ---------------------------------------------------------------------------
-- Sawmill Processing Governance
-- cm-crafting owns recipe 'materials:saw_timber'. cm-lumber is NOT in cm-crafting
-- TrustedOwners. Therefore, local conversion is strictly DISABLED fail-closed.
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-lumber:server:requestProcessing', function()
    local src = source
    if isRateLimited(src, 500) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You must clock in with the Foreman before accessing sawmill stations.', 'error')
        return
    end

    -- Fail-closed authority check: cm-crafting authorization is pending
    if not Config.Processing.conversionEnabled then
        notify(src, Config.Processing.statusNotice, 'warning')
        dbg(('Worker %s requested sawmill conversion, but recipe execution is unauthorized/held.'):format(src))
        return
    end
end)

RegisterNetEvent('cm-lumber:server:completeProcessing', function()
    -- Disabled fail-closed: do not issue timber or convert logs locally
    local src = source
    local session = Sessions[src]
    if session and session.isProcessing then
        session.isProcessing = false
        session.processStartTime = nil
    end
end)

RegisterNetEvent('cm-lumber:server:cancelProcessing', function()
    local src = source
    local session = Sessions[src]
    if session and session.isProcessing then
        session.isProcessing = false
        session.processStartTime = nil
    end
end)

-- ---------------------------------------------------------------------------
-- Disconnect, Character Unload, and Death Lifecycle Cleanup
-- ---------------------------------------------------------------------------

local function cleanupPlayerSession(src, reason)
    src = tonumber(src)
    if not src then return end

    local session = Sessions[src]
    if session then
        dbg(('Cleaning up in-memory session for worker %s (CID: %s, Reason: %s)'):format(
            src, tostring(session.charId), tostring(reason or 'unknown')
        ))
        Sessions[src] = nil
    end

    CloseOutLocks[src] = nil
    RateLimits[src] = nil
end

AddEventHandler('playerDropped', function(reason)
    cleanupPlayerSession(source, 'player_dropped: ' .. tostring(reason))
end)

RegisterNetEvent('cm-playerdata:server:characterUnloaded', function()
    cleanupPlayerSession(source, 'character_unloaded')
end)

RegisterNetEvent('baseevents:onPlayerDied', function()
    local src = source
    local session = Sessions[src]
    if session then
        session.isFelling = false
        session.fellingNodeId = nil
        session.fellingStartTime = nil
        session.isProcessing = false
        session.processStartTime = nil
        dbg(('Worker %s died during shift. Active operations cancelled.'):format(src))
        syncSession(src)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    Sessions = {}
    NodeCooldowns = {}
    RateLimits = {}
    CloseOutLocks = {}
    dbg('cm-lumber stopped. Server state cleaned up.')
end)

-- ---------------------------------------------------------------------------
-- Public Server Exports
-- ---------------------------------------------------------------------------

exports('IsOnShift', function(src)
    src = tonumber(src)
    return (src and Sessions[src] ~= nil)
end)

exports('GetShiftStatus', function(src)
    src = tonumber(src)
    if not src or not Sessions[src] then return nil end
    local s = Sessions[src]
    return {
        onShift = true,
        charId = s.charId,
        clockInTime = s.clockInTime,
        logsHarvested = s.logsHarvested,
        timberProcessed = s.timberProcessed,
        haulLogs = s.haulLogs,
        haulTimber = s.haulTimber,
        maxHaulLogs = Config.Harvesting.maxHaulLogCapacity,
    }
end)

-- Durable ledger export querying persistent records from MySQL
exports('GetMillLedger', function(limit)
    if not schemaReady and not ensureSchema() then return {} end
    local queryLimit = math.min(100, math.max(1, tonumber(limit) or 50))
    local rows = MySQL.query.await([[
        SELECT manifest_id, character_id, duration_seconds, logs_harvested, timber_processed,
               haul_logs_remaining, status, notes, created_at
        FROM cm_lumber_manifests
        ORDER BY id DESC LIMIT ?
    ]], { queryLimit })
    return rows or {}
end)

-- ---------------------------------------------------------------------------
-- Sawmill Crafting Station Registration Hook
-- ---------------------------------------------------------------------------

local function tryRegisterSawmillStation()
    if GetResourceState('cm-crafting') ~= 'started' then return end

    pcall(function()
        local ok, res = exports['cm-crafting']:RegisterCraftStation({
            id = Config.Sawmill.id,
            type = 'sawmill',
            coords = Config.Sawmill.coords,
            radius = Config.Sawmill.radius,
            shared = true,
        })
        if ok then
            dbg(('Registered sawmill station %s with cm-crafting.'):format(Config.Sawmill.id))
        else
            dbg(('cm-crafting station registration rejected: %s (fail-closed)'):format(tostring(res)))
        end
    end)
end

CreateThread(function()
    Wait(2000)
    tryRegisterSawmillStation()
end)

AddEventHandler('cm-crafting:server:registryReady', function()
    tryRegisterSawmillStation()
end)

