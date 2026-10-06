-- cm-mining/server/main.lua
-- Server-Authoritative Davis Quartz Mining & Mineral Processing Controller.
--
-- Architecture & Integrity:
-- - Server maintains authoritative shift state, rock node cooldowns, and batch capacities.
-- - All client actions (clock-in, extraction, smelting, clock-out) are strictly validated for:
--   1. Valid character identity (via cm-playerdata)
--   2. Proximity to physical world anchors (foreman, rock node, industrial furnace)
--   3. Anti-speedhack minimum elapsed action timers
--   4. Cart batch capacity constraints
-- - Fail-Closed Custody & Settlement:
--   Downstream sink (cm-construction) is currently unpopulated, and cm-payday has no
--   registered mining job or idempotent wage settlement. Shift production is recorded
--   in the authoritative quarry ledger and held fail-closed. No un-sinkable loose items
--   are minted into player inventory and no non-idempotent wage requests are made.

local Config = CMMining.Config
CMMining = CMMining or {}
CMMining.Server = CMMining.Server or {}
local Server = CMMining.Server

local PLAYERDATA = 'cm-playerdata'
local HUD = 'cm-hud'

-- Authoritative server state
-- Sessions[src] = {
--     src = number,
--     charId = string,
--     clockInTime = number,
--     oreMined = number,
--     ingotsSmelted = number,
--     cartOre = number,
--     cartIngots = number,
--     isExtracting = boolean,
--     extractNodeId = number|nil,
--     extractStartTime = number|nil,
--     isSmelting = boolean,
--     smeltStartTime = number|nil,
-- }
local Sessions = {}
local NodeCooldowns = {} -- [nodeId] = gameTimerExpiry
local RateLimits = {}    -- [src] = gameTimerExpiry
local ShiftManifests = {} -- Historic recorded shift manifests for audit

-- ---------------------------------------------------------------------------
-- Internal Helpers
-- ---------------------------------------------------------------------------

local function dbg(...)
    if Config.Debug then
        print('^3[CM-MINING:SERVER]^7', ...)
    end
end

local function notify(src, message, kind)
    if GetResourceState(HUD) == 'started' then
        pcall(function()
            TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info')
        end)
    else
        TriggerClientEvent('cm-mining:client:notify', src, message, kind or 'info')
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

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

local function getMeta(src, key, default)
    local pd = playerData()
    if not pd then return default end
    local ok, value = pcall(function() return pd:GetMetadata(src, key) end)
    if ok and value ~= nil then return value end
    return default
end

local function setMeta(src, key, value)
    local pd = playerData()
    if not pd then return false, 'playerdata_unavailable' end
    local ok, result = pcall(function() return pd:SetMetadataDetailed(src, key, value) end)
    if not ok then return false, 'pcall_failed' end
    return result == true, result
end

local function savePlayerData(src, reason)
    local pd = playerData()
    if not pd then return false end
    local ok, result = pcall(function() return pd:Save(src, reason or 'cm-mining') end)
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
            CREATE TABLE IF NOT EXISTS cm_mining_manifests (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                reference VARCHAR(64) NOT NULL,
                character_id VARCHAR(50) NOT NULL,
                duration_seconds INT NOT NULL DEFAULT 0,
                ore_mined INT NOT NULL DEFAULT 0,
                ingots_smelted INT NOT NULL DEFAULT 0,
                cart_ore_remaining INT NOT NULL DEFAULT 0,
                cart_ingots_total INT NOT NULL DEFAULT 0,
                pending_payout INT NOT NULL DEFAULT 0,
                custody_status VARCHAR(64) NOT NULL DEFAULT 'HELD_FAIL_CLOSED_NO_DOWNSTREAM_SINK',
                payroll_status VARCHAR(64) NOT NULL DEFAULT 'HELD_FAIL_CLOSED_NON_IDEMPOTENT_PAYDAY',
                closed_at BIGINT NOT NULL,
                reason VARCHAR(64) NULL,
                raw_data LONGTEXT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_mining_reference (reference),
                INDEX idx_mining_char (character_id),
                INDEX idx_mining_custody (character_id, custody_status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])
    end)

    if ok then
        schemaState = SCHEMA_STATE.READY
        schemaInitError = nil
        schemaInitLock = false
        dbg('Database table cm_mining_manifests initialized successfully.')
        return true
    else
        local errStr = tostring(err)
        if schemaState ~= SCHEMA_STATE.READY and mySeq >= schemaInitSeq then
            schemaState = SCHEMA_STATE.FAILED
            schemaInitError = errStr
            print('^1[CM-MINING] Failed to initialize cm_mining_manifests table: ' .. errStr .. '^7')
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

local function pruneSettledManifestsIfNeeded(manifests, maxAllowedBytes)
    maxAllowedBytes = maxAllowedBytes or 45000
    local encoded = json.encode(manifests)
    if not encoded or #encoded <= maxAllowedBytes then
        return manifests
    end

    local trimmed = {}
    for _, m in ipairs(manifests) do
        local isUnresolved = (m.custodyStatus == 'HELD_FAIL_CLOSED_NO_DOWNSTREAM_SINK')
            or (m.payrollStatus == 'HELD_FAIL_CLOSED_NON_IDEMPOTENT_PAYDAY')
            or (m.custodyStatus ~= 'SETTLED' and m.custodyStatus ~= 'RELEASED')
            or (m.payrollStatus ~= 'SETTLED' and m.payrollStatus ~= 'PAID')

        if isUnresolved then
            trimmed[#trimmed + 1] = m
        else
            local currentEncoded = json.encode(trimmed)
            if currentEncoded and #currentEncoded < maxAllowedBytes then
                trimmed[#trimmed + 1] = m
            end
        end
    end
    return trimmed
end

local function persistActiveShift(src, session)
    if not session then return end
    setMeta(src, 'cmMiningActiveShift', {
        reference = session.shiftRef,
        charId = session.charId,
        clockInTime = session.clockInTime,
        oreMined = session.oreMined,
        ingotsSmelted = session.ingotsSmelted,
        cartOre = session.cartOre,
        cartIngots = session.cartIngots,
    })
end

local function persistMiningManifest(src, manifest)
    local pd = playerData()
    if not pd then return false, 'playerdata_unavailable' end

    local charId = manifest.charId or getCharId(src)
    if not charId then return false, 'character_identity_missing' end

    local ref = manifest.reference
    if not ref or ref == '' then return false, 'invalid_reference' end

    local ready, readyErr = awaitSchemaReady(10000)
    if not ready then
        print(('[CM-MINING] Refusing manifest persistence: database schema is not ready (%s)'):format(tostring(readyErr)))
        return false, 'database_schema_not_ready'
    end

    local dbExisting = nil
    local okDb, row = pcall(function()
        return MySQL.single.await('SELECT reference, ore_mined, ingots_smelted, pending_payout FROM cm_mining_manifests WHERE reference = ? LIMIT 1', { ref })
    end)
    if not okDb then
        print('^1[CM-MINING] Failed to query cm_mining_manifests: ' .. tostring(row) .. '^7')
        return false, 'db_query_failed'
    end
    if row then
        dbExisting = row
    end

    local currentMeta = getMeta(src, 'cmMining', nil)
    if type(currentMeta) ~= 'table' then
        currentMeta = {
            manifests = {},
            pendingPayout = 0,
            totalOreMined = 0,
            totalIngotsSmelted = 0,
        }
    end
    currentMeta.manifests = type(currentMeta.manifests) == 'table' and currentMeta.manifests or {}

    local metaExisting = nil
    for _, existing in ipairs(currentMeta.manifests) do
        if existing.reference == ref then
            metaExisting = existing
            break
        end
    end

    local alreadyRecorded = (dbExisting ~= nil) or (metaExisting ~= nil)

    if alreadyRecorded then
        local existingOre = dbExisting and tonumber(dbExisting.ore_mined) or (metaExisting and tonumber(metaExisting.oreMined))
        local existingIngots = dbExisting and tonumber(dbExisting.ingots_smelted) or (metaExisting and tonumber(metaExisting.ingotsSmelted))
        if existingOre == tonumber(manifest.oreMined) and existingIngots == tonumber(manifest.ingotsSmelted) then
            dbg(('Manifest %s already durably recorded, idempotent replay confirmed'):format(ref))
            return true, 'replayed'
        else
            dbg(('Manifest %s conflict: amounts do not match existing record'):format(ref))
            return false, 'idempotency_conflict'
        end
    end

    local okInsert, insertErr = pcall(function()
            return MySQL.insert.await([[
                INSERT INTO cm_mining_manifests
                    (reference, character_id, duration_seconds, ore_mined, ingots_smelted,
                     cart_ore_remaining, cart_ingots_total, pending_payout, custody_status,
                     payroll_status, closed_at, reason, raw_data)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                ref,
                tostring(charId),
                tonumber(manifest.durationSeconds) or 0,
                tonumber(manifest.oreMined) or 0,
                tonumber(manifest.ingotsSmelted) or 0,
                tonumber(manifest.cartOreRemaining) or 0,
                tonumber(manifest.cartIngotsTotal) or 0,
                tonumber(manifest.pendingPayout) or 0,
                tostring(manifest.custodyStatus or 'HELD_FAIL_CLOSED_NO_DOWNSTREAM_SINK'),
                tostring(manifest.payrollStatus or 'HELD_FAIL_CLOSED_NON_IDEMPOTENT_PAYDAY'),
                tonumber(manifest.closedAt) or os.time(),
                manifest.reason and tostring(manifest.reason) or nil,
                json.encode(manifest)
            })
        end)

        if not okInsert then
            print('^1[CM-MINING] Failed to insert manifest into cm_mining_manifests: ' .. tostring(insertErr) .. '^7')
            return false, 'sql_insert_failed'
        end

    table.insert(currentMeta.manifests, 1, manifest)
    currentMeta.manifests = pruneSettledManifestsIfNeeded(currentMeta.manifests, 45000)

    local totalOre = 0
    local totalIngots = 0
    local totalPayout = 0
    for _, m in ipairs(currentMeta.manifests) do
        totalOre = totalOre + (tonumber(m.oreMined) or 0)
        totalIngots = totalIngots + (tonumber(m.ingotsSmelted) or 0)
        totalPayout = totalPayout + (tonumber(m.pendingPayout) or 0)
    end
    currentMeta.totalOreMined = totalOre
    currentMeta.totalIngotsSmelted = totalIngots
    currentMeta.pendingPayout = totalPayout

    local okSet, errSet = setMeta(src, 'cmMining', currentMeta)
    if not okSet then
        return false, errSet or 'set_metadata_failed'
    end

    local okSave = savePlayerData(src, 'cm-mining-manifest')
    if not okSave then
        return false, 'save_playerdata_failed'
    end

    return true, 'persisted'
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
        TriggerClientEvent('cm-mining:client:syncState', src, nil)
        return
    end

    TriggerClientEvent('cm-mining:client:syncState', src, {
        onShift = true,
        clockInTime = session.clockInTime,
        oreMined = session.oreMined,
        ingotsSmelted = session.ingotsSmelted,
        cartOre = session.cartOre,
        cartIngots = session.cartIngots,
        maxCartOreCapacity = Config.Extraction.maxCartOreCapacity,
        isExtracting = session.isExtracting,
        isSmelting = session.isSmelting,
    })
end

-- ---------------------------------------------------------------------------
-- Shift Lifecycle: Clock In & Clock Out
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-mining:server:clockIn', function()
    local src = source
    if isRateLimited(src, 1500) then return end

    local ready, err = awaitSchemaReady(10000)
    if not ready then
        dbg(('Worker src %d rejected at clockIn: database schema not ready (%s)'):format(src, tostring(err)))
        notify(src, 'Quarry operations unavailable: database ledger is offline. Contact administration.', 'error')
        return
    end

    local charId = getCharId(src)
    if not charId then
        notify(src, 'Unable to verify character identity. Please relog.', 'error')
        return
    end

    if Sessions[src] then
        notify(src, 'You are already clocked in for a mining shift at Davis Quartz.', 'warning')
        return
    end

    -- Proximity validation: must be near Foreman Hal Vance
    local coords = getPlayerCoords(src)
    if not coords then return end

    local foremanPos = vector3(Config.Foreman.coords.x, Config.Foreman.coords.y, Config.Foreman.coords.z)
    local dist = #(coords - foremanPos)
    if dist > 6.0 then
        notify(src, 'You must be near Foreman Vance to clock in.', 'error')
        return
    end

    local existingShift = getMeta(src, 'cmMiningActiveShift', nil)
    if type(existingShift) == 'table' and existingShift.reference then
        Sessions[src] = {
            src = src,
            charId = charId,
            shiftRef = existingShift.reference,
            clockInTime = tonumber(existingShift.clockInTime) or os.time(),
            oreMined = tonumber(existingShift.oreMined) or 0,
            ingotsSmelted = tonumber(existingShift.ingotsSmelted) or 0,
            cartOre = tonumber(existingShift.cartOre) or 0,
            cartIngots = tonumber(existingShift.cartIngots) or 0,
            isExtracting = false,
            extractNodeId = nil,
            extractStartTime = nil,
            isSmelting = false,
            smeltStartTime = nil,
        }
        dbg(('Worker %s (src %d) resumed existing active shift from metadata'):format(charId, src))
        notify(src, ('Resumed active quarry shift (%d ore in cart, %d ingots). Collect your pickaxe.').format(Sessions[src].cartOre, Sessions[src].cartIngots), 'info')
        syncSession(src)
        return
    end

    local shiftRef = ('MINING-%s-%d'):format(charId, os.time())
    Sessions[src] = {
        src = src,
        charId = charId,
        shiftRef = shiftRef,
        clockInTime = os.time(),
        oreMined = 0,
        ingotsSmelted = 0,
        cartOre = 0,
        cartIngots = 0,
        isExtracting = false,
        extractNodeId = nil,
        extractStartTime = nil,
        isSmelting = false,
        smeltStartTime = nil,
    }

    persistActiveShift(src, Sessions[src])
    savePlayerData(src, 'cm-mining-clockin')

    dbg(('Worker %s (src %d) clocked in at Davis Quartz Quarry'):format(charId, src))
    notify(src, 'Clocked in at Davis Quartz Quarry. Collect your pickaxe and head to the extraction pit.', 'success')
    syncSession(src)
end)

RegisterNetEvent('cm-mining:server:clockOut', function()
    local src = source
    if isRateLimited(src, 1500) then return end

    local ready, err = awaitSchemaReady(10000)
    if not ready then
        dbg(('Worker src %d rejected at clockOut: database schema not ready (%s)'):format(src, tostring(err)))
        notify(src, 'Cannot clock out: database ledger is offline. Your shift has been preserved. Please retry shortly.', 'error')
        return
    end

    local session = Sessions[src]
    if not session then
        notify(src, 'You do not have an active quarry shift.', 'error')
        return
    end

    local coords = getPlayerCoords(src)
    if not coords then return end

    local foremanPos = vector3(Config.Foreman.coords.x, Config.Foreman.coords.y, Config.Foreman.coords.z)
    local dist = #(coords - foremanPos)
    if dist > 6.0 then
        notify(src, 'You must return to Foreman Vance to submit your shift manifest and clock out.', 'error')
        return
    end

    local shiftDuration = os.time() - session.clockInTime
    local manifestRef = session.shiftRef or ('MINING-%s-%d'):format(session.charId, session.clockInTime)
    local manifest = {
        reference = manifestRef,
        charId = session.charId,
        durationSeconds = shiftDuration,
        oreMined = session.oreMined,
        ingotsSmelted = session.ingotsSmelted,
        cartOreRemaining = session.cartOre,
        cartIngotsTotal = session.cartIngots,
        closedAt = os.time(),
        pendingPayout = 0,
        custodyStatus = 'HELD_FAIL_CLOSED_NO_DOWNSTREAM_SINK',
        payrollStatus = 'HELD_FAIL_CLOSED_NON_IDEMPOTENT_PAYDAY',
    }

    local okDurable, statusOrErr = persistMiningManifest(src, manifest)
    if not okDurable then
        dbg(('Failed to persist manifest for worker %s: %s'):format(session.charId, tostring(statusOrErr)))
        notify(src, 'Failed to record shift manifest in durable ledger. Please try again.', 'error')
        return
    end

    -- Clear active shift record now that manifest persistence is confirmed durable!
    setMeta(src, 'cmMiningActiveShift', nil)
    savePlayerData(src, 'cm-mining-clockout')

    local existsInCache = false
    for _, existing in ipairs(ShiftManifests) do
        if existing.reference == manifest.reference then
            existsInCache = true
            break
        end
    end
    if not existsInCache then
        table.insert(ShiftManifests, manifest)
    end

    dbg(('Worker %s completed shift. Mined: %d ore, Smelted: %d ingots. Manifest held.'):format(
        session.charId, session.oreMined, session.ingotsSmelted
    ))

    Sessions[src] = nil
    TriggerClientEvent('cm-mining:client:syncState', src, nil)

    -- Explicitly notify worker of the shift completion and held custody status
    local feedback = ('Shift closed! Recorded manifest: %d ore mined, %d ingots smelted. Notice: %s'):format(
        manifest.oreMined, manifest.ingotsSmelted, Config.Custody.holdingNotice
    )
    notify(src, feedback, 'info')
end)

-- ---------------------------------------------------------------------------
-- Quarry Rock Extraction Lifecycle
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-mining:server:startExtraction', function(nodeId)
    local src = source
    if isRateLimited(src, 800) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You must clock in with Foreman Vance before extracting minerals.', 'error')
        return
    end

    if not isSchemaReady() then
        notify(src, 'Quarry vein extraction unavailable: database ledger is offline. Contact administration.', 'error')
        return
    end

    if session.isExtracting then
        notify(src, 'You are already actively mining a rock vein.', 'warning')
        return
    end

    if session.isSmelting then
        notify(src, 'You cannot mine while operating the industrial furnace.', 'warning')
        return
    end

    local node = Config.ExtractionNodes[tonumber(nodeId)]
    if not node then
        notify(src, 'Invalid mineral vein target.', 'error')
        return
    end

    -- Capacity check
    if (session.cartOre + Config.Extraction.oreYieldPerNode) > Config.Extraction.maxCartOreCapacity then
        notify(src, ('Your quarry cart is full (%d/%d ore). Smelt your ore at the furnace or conclude your shift.'):format(
            session.cartOre, Config.Extraction.maxCartOreCapacity
        ), 'warning')
        return
    end

    -- Cooldown check
    local now = GetGameTimer()
    local expiry = NodeCooldowns[node.id] or 0
    if expiry > now then
        local remainingSec = math.ceil((expiry - now) / 1000)
        notify(src, ('This vein has been depleted. Regenerating in %d seconds.'):format(remainingSec), 'warning')
        return
    end

    -- Proximity check
    local coords = getPlayerCoords(src)
    if not coords then return end
    local dist = #(coords - node.coords)
    if dist > (node.radius + 2.0) then
        notify(src, 'You are too far from the mineral vein.', 'error')
        return
    end

    -- Authorize extraction start
    session.isExtracting = true
    session.extractNodeId = node.id
    session.extractStartTime = now

    TriggerClientEvent('cm-mining:client:startExtractionApproved', src, {
        nodeId = node.id,
        durationMs = Config.Extraction.durationMs,
    })
end)

RegisterNetEvent('cm-mining:server:completeExtraction', function(nodeId)
    local src = source
    local session = Sessions[src]
    if not session or not session.isExtracting then
        return
    end

    local node = Config.ExtractionNodes[tonumber(nodeId)]
    if not node or node.id ~= session.extractNodeId then
        session.isExtracting = false
        session.extractNodeId = nil
        session.extractStartTime = nil
        notify(src, 'Extraction vein mismatch. Action cancelled.', 'error')
        syncSession(src)
        return
    end

    -- Anti-speedhack validation
    local now = GetGameTimer()
    local elapsed = now - (session.extractStartTime or 0)
    if elapsed < Config.Extraction.minDurationMs then
        dbg(('Anti-speedhack triggered for worker %s (elapsed %d ms < %d ms)'):format(
            session.charId, elapsed, Config.Extraction.minDurationMs
        ))
        session.isExtracting = false
        session.extractNodeId = nil
        session.extractStartTime = nil
        notify(src, 'Extraction cycle interrupted or completed too quickly.', 'error')
        syncSession(src)
        return
    end

    -- Proximity validation
    local coords = getPlayerCoords(src)
    if not coords or #(coords - node.coords) > (node.radius + 3.0) then
        session.isExtracting = false
        session.extractNodeId = nil
        session.extractStartTime = nil
        notify(src, 'You moved too far from the vein during extraction.', 'error')
        syncSession(src)
        return
    end

    -- Apply node cooldown
    NodeCooldowns[node.id] = now + Config.Extraction.nodeCooldownMs

    -- Update session yields
    session.isExtracting = false
    session.extractNodeId = nil
    session.extractStartTime = nil
    session.oreMined = session.oreMined + Config.Extraction.oreYieldPerNode
    session.cartOre = session.cartOre + Config.Extraction.oreYieldPerNode
    persistActiveShift(src, session)

    -- Broadcast node cooldown expiry to all clients so UI/markers update
    TriggerClientEvent('cm-mining:client:updateNodeCooldown', -1, node.id, NodeCooldowns[node.id])

    notify(src, ('Extracted +%d Raw Iron Ore into cart (%d/%d).'):format(
        Config.Extraction.oreYieldPerNode, session.cartOre, Config.Extraction.maxCartOreCapacity
    ), 'success')

    syncSession(src)
end)

RegisterNetEvent('cm-mining:server:cancelExtraction', function()
    local src = source
    local session = Sessions[src]
    if session and session.isExtracting then
        session.isExtracting = false
        session.extractNodeId = nil
        session.extractStartTime = nil
        syncSession(src)
    end
end)

-- ---------------------------------------------------------------------------
-- Industrial Smelting Lifecycle
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-mining:server:startSmelting', function()
    local src = source
    if isRateLimited(src, 1000) then return end

    local session = Sessions[src]
    if not session then
        notify(src, 'You must clock in with Foreman Vance before operating quarry machinery.', 'error')
        return
    end

    if not isSchemaReady() then
        notify(src, 'Quarry industrial furnace unavailable: database ledger is offline. Contact administration.', 'error')
        return
    end

    if session.isSmelting then
        notify(src, 'The smelting furnace is already processing your batch.', 'warning')
        return
    end

    if session.isExtracting then
        notify(src, 'You cannot operate the smelting furnace while extracting rock veins.', 'warning')
        return
    end

    -- Verify raw ore inventory in cart
    if session.cartOre < Config.Smelting.inputAmount then
        notify(src, ('You need at least %d Raw Iron Ore to smelt an ingot (Current: %d).'):format(
            Config.Smelting.inputAmount, session.cartOre
        ), 'warning')
        return
    end

    -- Proximity validation: must be near furnace
    local coords = getPlayerCoords(src)
    if not coords then return end
    local dist = #(coords - Config.Furnace.coords)
    if dist > (Config.Furnace.radius + 2.0) then
        notify(src, 'You must be standing directly at the industrial furnace.', 'error')
        return
    end

    -- Authorize smelting start
    local now = GetGameTimer()
    session.isSmelting = true
    session.smeltStartTime = now

    TriggerClientEvent('cm-mining:client:startSmeltingApproved', src, {
        durationMs = Config.Smelting.durationMs,
    })
end)

RegisterNetEvent('cm-mining:server:completeSmelting', function()
    local src = source
    local session = Sessions[src]
    if not session or not session.isSmelting then
        return
    end

    -- Anti-speedhack validation
    local now = GetGameTimer()
    local elapsed = now - (session.smeltStartTime or 0)
    if elapsed < Config.Smelting.minDurationMs then
        dbg(('Anti-speedhack triggered during smelting for worker %s (elapsed %d ms < %d ms)'):format(
            session.charId, elapsed, Config.Smelting.minDurationMs
        ))
        session.isSmelting = false
        session.smeltStartTime = nil
        notify(src, 'Smelting sequence interrupted or completed too quickly.', 'error')
        syncSession(src)
        return
    end

    -- Proximity validation
    local coords = getPlayerCoords(src)
    if not coords or #(coords - Config.Furnace.coords) > (Config.Furnace.radius + 3.0) then
        session.isSmelting = false
        session.smeltStartTime = nil
        notify(src, 'You moved too far from the furnace during smelting.', 'error')
        syncSession(src)
        return
    end

    -- Re-validate ore
    if session.cartOre < Config.Smelting.inputAmount then
        session.isSmelting = false
        session.smeltStartTime = nil
        notify(src, 'Insufficient raw ore to complete smelting.', 'error')
        syncSession(src)
        return
    end

    -- Complete smelting batch
    session.isSmelting = false
    session.smeltStartTime = nil
    session.cartOre = session.cartOre - Config.Smelting.inputAmount
    session.ingotsSmelted = session.ingotsSmelted + Config.Smelting.outputAmount
    session.cartIngots = session.cartIngots + Config.Smelting.outputAmount
    persistActiveShift(src, session)

    notify(src, ('Smelted %dx Raw Iron Ore into +%dx Iron Ingot (Cart: %d ore, %d ingots).'):format(
        Config.Smelting.inputAmount, Config.Smelting.outputAmount, session.cartOre, session.cartIngots
    ), 'success')

    syncSession(src)
end)

RegisterNetEvent('cm-mining:server:cancelSmelting', function()
    local src = source
    local session = Sessions[src]
    if session and session.isSmelting then
        session.isSmelting = false
        session.smeltStartTime = nil
        syncSession(src)
    end
end)

-- ---------------------------------------------------------------------------
-- Query Status Notice
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-mining:server:requestQuarryStatus', function()
    local src = source
    local session = Sessions[src]
    local response = {
        onShift = session ~= nil,
        charId = session and session.charId or getCharId(src),
        oreMined = session and session.oreMined or 0,
        ingotsSmelted = session and session.ingotsSmelted or 0,
        cartOre = session and session.cartOre or 0,
        cartIngots = session and session.cartIngots or 0,
        holdingNotice = Config.Custody.holdingNotice,
    }
    TriggerClientEvent('cm-mining:client:receiveQuarryStatus', src, response)
end)

-- ---------------------------------------------------------------------------
-- Cleanup & Disconnect Handlers
-- ---------------------------------------------------------------------------

local function handleWorkerCleanup(src, reason)
    local session = Sessions[src]
    if not session then return end

    dbg(('Cleaning up mining session for worker %s (src %d), reason: %s'):format(
        session.charId, src, tostring(reason)
    ))

    persistActiveShift(src, session)
    savePlayerData(src, 'cm-mining-disconnect')

    Sessions[src] = nil
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    src = tonumber(src)
    if not src then return end

    local activeShift = getMeta(src, 'cmMiningActiveShift', nil)
    if type(activeShift) == 'table' and activeShift.reference and not Sessions[src] then
        CreateThread(function()
            local ready, err = awaitSchemaReady(5000)
            if not ready then
                dbg(('Character %s loaded with active shift but database schema not ready: %s'):format(tostring(activeShift.charId), tostring(err)))
                return
            end
            if not Sessions[src] then
                local charId = getCharId(src)
                if charId and tostring(charId) == tostring(activeShift.charId) then
                    Sessions[src] = {
                        src = src,
                        charId = charId,
                        shiftRef = activeShift.reference,
                        clockInTime = tonumber(activeShift.clockInTime) or os.time(),
                        oreMined = tonumber(activeShift.oreMined) or 0,
                        ingotsSmelted = tonumber(activeShift.ingotsSmelted) or 0,
                        cartOre = tonumber(activeShift.cartOre) or 0,
                        cartIngots = tonumber(activeShift.cartIngots) or 0,
                        isExtracting = false,
                        extractNodeId = nil,
                        extractStartTime = nil,
                        isSmelting = false,
                        smeltStartTime = nil,
                    }
                    dbg(('Restored active mining shift for worker %s (ore: %d, ingots: %d)'):format(charId, Sessions[src].cartOre, Sessions[src].cartIngots))
                    notify(src, ('Resumed active quarry shift (%d ore in cart, %d ingots).'):format(Sessions[src].cartOre, Sessions[src].cartIngots), 'info')
                    syncSession(src)
                end
            end
        end)
    end

    local meta = getMeta(src, 'cmMining', nil)
    if type(meta) == 'table' and type(meta.manifests) == 'table' then
        for _, manifest in ipairs(meta.manifests) do
            if type(manifest) == 'table' and manifest.reference then
                local found = false
                for _, existing in ipairs(ShiftManifests) do
                    if existing.reference == manifest.reference then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(ShiftManifests, manifest)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function(reason)
    handleWorkerCleanup(source, ('playerDropped: %s'):format(tostring(reason)))
end)

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    handleWorkerCleanup(src, 'characterUnloaded')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, session in pairs(Sessions) do
        persistActiveShift(src, session)
        savePlayerData(src, 'cm-mining-resource-stop')
    end
    Sessions = {}
    NodeCooldowns = {}
    RateLimits = {}
end)

-- ---------------------------------------------------------------------------
-- Public Server Exports
-- ---------------------------------------------------------------------------

Server.IsWorkerOnShift = function(src)
    return Sessions[src] ~= nil
end

Server.GetWorkerSession = function(src)
    local s = Sessions[src]
    if not s then return nil end
    return {
        src = s.src,
        charId = s.charId,
        clockInTime = s.clockInTime,
        oreMined = s.oreMined,
        ingotsSmelted = s.ingotsSmelted,
        cartOre = s.cartOre,
        cartIngots = s.cartIngots,
        isExtracting = s.isExtracting,
        isSmelting = s.isSmelting,
    }
end

Server.GetQuarryManifests = function()
    return ShiftManifests
end

exports('IsWorkerOnShift', Server.IsWorkerOnShift)
exports('GetWorkerSession', Server.GetWorkerSession)
exports('GetQuarryManifests', Server.GetQuarryManifests)
exports('IsSchemaReady', function() return isSchemaReady() end)
exports('GetSchemaState', function() return getSchemaState() end)
exports('AwaitSchemaReady', function(timeoutMs) return awaitSchemaReady(timeoutMs) end)

