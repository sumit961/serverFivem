-- cm-playerdata/server/main.lua
-- Foundation clean upgrade for CM Framework. No hunger/thirst/stress.
-- Owns loaded character state, visible database character ID, cash/bank, vitals, death state, and player identity interactions.
-- Admin UI/tools stay in cm-admin. Prices/payout rules stay in cm-economy.
-- Uses oxmysql directly to avoid cm-core export call-style issues.

local Config = CMPlayerData.Config
local PlayerData = {}
local LoadLocks = {}
local ActiveSaves = {}
local CharacterSwitchLocks = {}
local SavePlayerData -- pre-declared for forward references
local KnownIdentityCache = {} -- [ownerCharId] = { [knownCharId] = true }
local PendingHandshakes = {} -- [targetSrc] = { from = src, expires = ms }
local PendingTreatments = {} -- [treaterSrc] = { target = src, startedAt = ms, duration = ms }
local PendingTreatmentOffers = {} -- [targetSrc] = { from = src, expires = ms }
local LastEventUse = {}
local ExtensionInteractionActions = {} -- [actionId] = { event = serverEventName, allowDeadTarget = bool, deadOnly = bool }
local SupplyWarDeathContexts = {} -- [characterId] = { source, eventId, expiresAt }
local SUPPLY_WAR_DEATH_CONTEXT_SECONDS = 60

local function CaptureSupplyWarDeathContext(src,eventId)
    src=tonumber(src);local data=src and PlayerData[src];if not data or not data.charId then return false end
    local equipped
    if GetResourceState('cm-inventory')=='started'then local ok,value=pcall(function()return exports['cm-inventory']:GetEquippedWeaponState(src)end);if ok and type(value)=='table'then equipped=value end end
    local existing=SupplyWarDeathContexts[tostring(data.charId)]or{}
    SupplyWarDeathContexts[tostring(data.charId)]={source=src,eventId=tostring(eventId or existing.eventId or''),expiresAt=os.time()+SUPPLY_WAR_DEATH_CONTEXT_SECONDS,equippedWeapon=equipped and equipped.weapon or existing.equippedWeapon,equippedAmmo=equipped and equipped.ammo or existing.equippedAmmo,equippedAmmoQuantity=equipped and equipped.ammoQuantity or existing.equippedAmmoQuantity}
    if Config.Debug then print(('[CM-PLAYERDATA] LOADOUT_PRESERVE character=%s weapon=%s ammo=%s'):format(tostring(data.charId),tostring(SupplyWarDeathContexts[tostring(data.charId)].equippedWeapon),tostring(SupplyWarDeathContexts[tostring(data.charId)].equippedAmmoQuantity))) end
    return true
end

local function Debug(msg)
    if Config.Debug then
        print('[CM-PLAYERDATA] ' .. tostring(msg))
    end
end

local function Log(level, message, metadata)
    metadata = metadata or {}
    local ok = pcall(function()
        exports['cm-core']:Log('cm-playerdata', level, message, metadata)
    end)
    if not ok and (Config.Debug == true or level == 'warn' or level == 'error') then
        print(('[CM-PLAYERDATA] %s: %s'):format(level or 'info', message or ''))
    end
end

local function Clamp(value, min, max)
    value = tonumber(value) or min
    if value < min then return min end
    if value > max then return max end
    return value
end

local function RateLimit(src, key, ms)
    local now = GetGameTimer()
    local id = tostring(src) .. ':' .. key
    if LastEventUse[id] and (now - LastEventUse[id]) < ms then
        return false
    end
    LastEventUse[id] = now
    return true
end

local function ClearRateLimits(src)
    local prefix = tostring(src) .. ':'
    for key in pairs(LastEventUse) do
        if key:sub(1, #prefix) == prefix then
            LastEventUse[key] = nil
        end
    end
end

local function NormalizeInteractionActionId(value)
    if value == nil then return nil end
    local id = tostring(value):lower():gsub('%s+', '_')
    id = id:gsub('[^%w_:%.-]', '')
    if id == '' then return nil end
    return id
end

local function RegisterInteractionAction(meta)
    if type(meta) ~= 'table' then return false, 'invalid_meta' end

    local id = NormalizeInteractionActionId(meta.id or meta.action)
    local eventName = meta.event and tostring(meta.event) or ''
    if not id then return false, 'invalid_action_id' end
    if eventName == '' then return false, 'missing_server_event' end

    ExtensionInteractionActions[id] = {
        id = id,
        event = eventName,
        allowDeadTarget = meta.allowDeadTarget == true,
        deadOnly = meta.deadOnly == true,
        -- Opt-in only: the default (false) preserves the existing "use the
        -- vehicle interaction menu instead" block for every action that
        -- doesn't explicitly need a target who IS in a vehicle (e.g. an
        -- action whose entire purpose is acting on someone already seated).
        allowVehicleTarget = meta.allowVehicleTarget == true,
        resource = meta.resource and tostring(meta.resource) or 'unknown'
    }

    return true
end

local function UnregisterInteractionAction(action)
    local id = NormalizeInteractionActionId(action)
    if not id then return false end
    ExtensionInteractionActions[id] = nil
    return true
end

exports('RegisterInteractionAction', RegisterInteractionAction)
exports('UnregisterInteractionAction', UnregisterInteractionAction)

AddEventHandler('cm-playerdata:server:registerInteractionAction', function(meta)
    RegisterInteractionAction(meta)
end)

AddEventHandler('cm-playerdata:server:unregisterInteractionAction', function(action)
    UnregisterInteractionAction(action)
end)

local function HasAdminPermission(src, permission)
    src = tonumber(src) or 0
    if src <= 0 then return true end

    -- cm-admin owns all staff permissions. Keep ACE as a last-resort dev fallback
    -- only for existing servers that have not finished moving tools into cm-admin.
    if GetResourceState('cm-admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports['cm-admin']:HasPermission(src, permission)
        end)
        if ok then return allowed == true end
    end

    return IsPlayerAceAllowed(src, permission) == true
end

local function GetServerPedHealth(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local health = GetEntityHealth(ped)
    if not health or health <= 0 then return nil end
    return health
end

local function EncodeJson(value)
    if value == nil then return nil end
    local ok, encoded = pcall(json.encode, value)
    return ok and encoded or nil
end

local function DecodeJson(value)
    if not value or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
end

local function DeepCopy(val, visited)
    if type(val) ~= 'table' then return val end
    visited = visited or {}
    if visited[val] then return visited[val] end
    local copy = {}
    visited[val] = copy
    for k, v in pairs(val) do
        copy[DeepCopy(k, visited)] = DeepCopy(v, visited)
    end
    return copy
end

local function ValidateAndCopyMetadataValue(val, depth, visited, nodeState)
    depth = depth or 1
    visited = visited or {}
    nodeState = nodeState or { count = 0 }

    nodeState.count = nodeState.count + 1
    local maxNodes = (Config.Metadata and Config.Metadata.MaxNodes) or 2048
    if nodeState.count > maxNodes then
        return false, 'max_nodes_exceeded'
    end

    if val == nil then
        return true, nil
    end

    local valType = type(val)
    if valType == 'boolean' then
        return true, val
    elseif valType == 'number' then
        if val ~= val or val == math.huge or val == -math.huge then
            return false, 'invalid_number'
        end
        return true, val
    elseif valType == 'string' then
        local maxLen = (Config.Metadata and Config.Metadata.MaxStringLength) or 4096
        if #val > maxLen then
            return false, 'string_too_long'
        end
        return true, val
    elseif valType == 'table' then
        local maxDepth = (Config.Metadata and Config.Metadata.MaxDepth) or 8
        if depth > maxDepth then
            return false, 'max_depth_exceeded'
        end
        if visited[val] then
            return false, 'cyclic_reference'
        end
        visited[val] = true

        local copy = {}
        for k, v in pairs(val) do
            local kType = type(k)
            if kType ~= 'string' and kType ~= 'number' then
                visited[val] = nil
                return false, 'invalid_key_type'
            end
            if kType == 'string' and #k > 128 then
                visited[val] = nil
                return false, 'key_too_long'
            end
            local okVal, copiedVal = ValidateAndCopyMetadataValue(v, depth + 1, visited, nodeState)
            if not okVal then
                visited[val] = nil
                return false, copiedVal
            end
            copy[k] = copiedVal
        end

        visited[val] = nil
        return true, copy
    else
        return false, 'unsupported_type_' .. valType
    end
end

local function NowMs()
    return (os.time() * 1000) + math.floor((GetGameTimer() or 0) % 1000)
end


local function NormalizeCoords(value)
    if not value then return nil end
    if type(value) == 'string' then
        value = DecodeJson(value)
    end
    if type(value) ~= 'table' then return nil end

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    local h = tonumber(value.h or value.heading or value.w or value[4]) or 0.0
    if not x or not y or not z then return nil end

    return {
        x = math.floor(x * 100) / 100,
        y = math.floor(y * 100) / 100,
        z = math.floor(z * 100) / 100,
        h = math.floor(h * 100) / 100
    }
end

local function GetPedCoordsTable(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    local ok, coords = pcall(GetEntityCoords, ped)
    if not ok or not coords then return nil end

    local heading = 0.0
    pcall(function() heading = GetEntityHeading(ped) or 0.0 end)

    return NormalizeCoords({ x = coords.x, y = coords.y, z = coords.z, h = heading })
end

local function GetDeadLocation(data)
    if not data or data.isDead ~= true then return nil end
    -- Use the saved body/death location first. lastPosition is normal gameplay
    -- location and can be updated by spawn/selector recovery; deathLocation is
    -- the authoritative RP downed body position after reconnect.
    return NormalizeCoords(data.deathLocation)
        or NormalizeCoords(data.lastPosition)
        or NormalizeCoords(Config.Respawn and Config.Respawn.HospitalSpawn)
end

local function GetHealthFromPercent(percent)
    percent = tonumber(percent) or 20
    percent = Clamp(percent, 1, 100)

    -- GTA/FiveM peds are effectively dead around 100 HP. Treat percent as
    -- percent of usable health above the downed threshold, so 20% becomes a
    -- weak but alive value instead of a native-dead value like 40.
    local aliveMin = (Config.Vitals and Config.Vitals.DamageThreshold or 101) + 1
    local maxHealth = (Config.Vitals and Config.Vitals.MaxHealth) or 200
    if aliveMin >= maxHealth then return maxHealth end

    return math.floor(aliveMin + ((maxHealth - aliveMin) * (percent / 100)))
end

local function GetRespawnHealth()
    local respawn = Config.Respawn or {}
    if respawn.Health then
        return Clamp(respawn.Health, (Config.Vitals.DamageThreshold or 101) + 1, Config.Vitals.MaxHealth or 200)
    end
    return GetHealthFromPercent(respawn.HealthPercent or 20)
end

local function BuildDisplayName(firstName, lastName)
    local first = tostring(firstName or '')
    local last = tostring(lastName or '')
    local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if name == '' then return 'Unknown' end
    return name
end


local function GetCharId(src)
    src = tonumber(src)
    if not src then return nil end

    local data = PlayerData[src]
    if data and data.charId then
        return tostring(data.charId)
    end

    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end

    local charId = state.charId or state.characterId or state.rpId
    return charId and tostring(charId) or nil
end

local function MarkDirty(data)
    if not data then return 0 end
    data.revision = (tonumber(data.revision) or 0) + 1
    data.dirty = true
    return data.revision
end

local function CanMutate(data)
    if not data or data.loaded ~= true or data.switching == true then
        return false
    end

    local src = tonumber(data.src)
    if not src then return false end

    -- Fail closed if cm-auth is not started
    if GetResourceState('cm-auth') ~= 'started' then
        return false
    end

    local authenticatedAccountId = nil
    local ok, authId = pcall(function()
        if exports['cm-auth'].GetAuthenticatedAccountId then
            return exports['cm-auth']:GetAuthenticatedAccountId(src)
        end
        return exports['cm-auth']:GetAccountId(src)
    end)
    if ok and authId then
        authenticatedAccountId = tostring(authId)
    end

    if not authenticatedAccountId or authenticatedAccountId == '' then
        return false
    end

    return tostring(authenticatedAccountId) == tostring(data.accountId or '')
end

local function ValidateCharacterOwnership(src, charId)
    src = tonumber(src)
    charId = tostring(charId or '')
    if not src or src <= 0 or charId == '' then
        return false, 'invalid_parameters'
    end

    -- 1. Check via cm-characters export if running (authoritative check backed by cm-auth server memory)
    if GetResourceState('cm-characters') == 'started' then
        local ok, char, accountId, err = pcall(function()
            return exports['cm-characters']:GetOwnedCharacter(src, charId)
        end)
        if ok then
            if char and tostring(char.id) == charId then
                local resolvedAccountId = accountId or (char and char.account_id)
                return true, char, resolvedAccountId and tostring(resolvedAccountId) or nil
            end
            return false, err or 'not_owned'
        end
    end

    -- 2. Fallback direct validation using authenticated accountId strictly from cm-auth server memory
    local accountId = nil
    if GetResourceState('cm-auth') == 'started' then
        local okAuth, authId = pcall(function()
            if exports['cm-auth'].GetAuthenticatedAccountId then
                return exports['cm-auth']:GetAuthenticatedAccountId(src)
            end
            return exports['cm-auth']:GetAccountId(src)
        end)
        if okAuth and authId then
            accountId = tostring(authId)
        end
    end

    -- Fail closed! Never trust client state bags for authentication authority.
    if not accountId or accountId == '' then
        return false, 'no_authenticated_account'
    end

    local row = MySQL.single.await([[
        SELECT id, account_id FROM characters WHERE id = ? LIMIT 1
    ]], { charId })

    if not row then
        return false, 'character_not_found'
    end

    if tostring(row.account_id) ~= tostring(accountId) then
        return false, 'account_mismatch'
    end

    return true, row, tostring(accountId)
end

local function SetState(src, key, value, replicated)
    Player(src).state:set(key, value, replicated ~= false)
end

-- Revive/Heal/RevivePartial set data.health authoritatively and tell the
-- client to apply it, but the client's own periodic health sync (syncVitals)
-- can still have one stale reading in flight from before the ped's health was
-- actually changed locally -- e.g. a still-unconscious-level health captured
-- moments before SetEntityHealth ran. If that stale sync lands after the
-- server-side revive, it silently overwrites the fresh full-health value with
-- the old low one. Guarding downward syncs for a short window after any
-- revive/heal skips exactly that one stale reading without meaningfully
-- delaying real damage taken afterward.
local function GuardVitalsAfterRevive(data)
    data.vitalsGuardUntil = GetGameTimer() + 4500
end

local function PushUpdate(src, key, value)
    TriggerClientEvent('cm-playerdata:client:update', src, key, value)
end

-- Wanted stars: clamp, store, and push -- same one path used by every
-- gain (unmasked kill), clear (death/busted), and decay tick below, so
-- none of those call sites can drift out of sync with each other.
local function SetWantedStars(src, stars)
    local data = PlayerData[src]
    if not CanMutate(data) then return end
    local maxStars = (Config.WantedStars and Config.WantedStars.Max) or 6
    stars = math.max(0, math.min(maxStars, math.floor(tonumber(stars) or 0)))
    if data.wantedStars == stars then return end
    local previous = data.wantedStars
    data.wantedStars = stars
    data.metadata = data.metadata or {}
    data.metadata.cmWanted = data.metadata.cmWanted or {}
    data.metadata.cmWanted.stars = stars
    data.metadata.cmWanted.nextDecayAt = stars > 0
        and (os.time() + math.max(60, math.floor(((Config.WantedStars and Config.WantedStars.DecayIntervalMs) or 3600000) / 1000))) or 0
    data.wantedStarChangedAt = GetGameTimer()
    MarkDirty(data)
    PushUpdate(src, 'wantedStars', stars)
    SavePlayerData(src, 'wanted_stars')
    pcall(function() exports['cm-police']:SyncWantedStars(data.charId, stars) end)
    -- Auto-generated arrest warrant the moment max wanted is first reached
    -- (not on every subsequent tick while already at max). pcall-guarded,
    -- no fxmanifest dependency added -- cm-police already depends on
    -- cm-playerdata, so the reverse would be a circular dependency.
    if stars >= maxStars and (previous or 0) < maxStars then
        pcall(function() exports['cm-police']:AutoIssueWarrant(data.charId, 'Reached maximum wanted level (6 stars)') end)
    end
end

local MigrationsReady = false
local MigrationPromise = nil

local Migrations = {
    {
        version = 1,
        name = '001_base_character_columns',
        run = function()
            local alters = {
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS health INT DEFAULT 200",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS armor INT DEFAULT 0",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS is_dead TINYINT(1) DEFAULT 0",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_count INT DEFAULT 0",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_deadline_at BIGINT NULL",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_location LONGTEXT NULL",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS ambulance_called TINYINT(1) DEFAULT 0",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_reason VARCHAR(100) NULL",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS last_position LONGTEXT NULL",
                "ALTER TABLE characters ADD COLUMN IF NOT EXISTS metadata LONGTEXT NULL"
            }
            for _, sql in ipairs(alters) do
                MySQL.query.await(sql)
            end
            return true
        end
    },
    {
        version = 2,
        name = '002_playerdata_audit_table',
        run = function()
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS playerdata_audit (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    character_id VARCHAR(64) NULL,
                    action VARCHAR(64) NOT NULL,
                    data LONGTEXT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_character_id (character_id),
                    INDEX idx_action (action)
                )
            ]])
            return true
        end
    },
    {
        version = 3,
        name = '003_economy_transactions_table',
        run = function()
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS economy_transactions (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    character_id INT NULL,
                    account_type VARCHAR(30) NOT NULL,
                    amount BIGINT NOT NULL,
                    action VARCHAR(30) NOT NULL,
                    reason VARCHAR(100) NOT NULL,
                    resource_name VARCHAR(100) NULL,
                    balance_before BIGINT NOT NULL DEFAULT 0,
                    balance_after BIGINT NOT NULL DEFAULT 0,
                    metadata LONGTEXT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_character_account (character_id, account_type),
                    INDEX idx_reason (reason),
                    INDEX idx_created_at (created_at)
                )
            ]])
            return true
        end
    },
    {
        version = 4,
        name = '004_known_identities_table',
        run = function()
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS cm_known_identities (
                    owner_character_id BIGINT NOT NULL,
                    known_character_id BIGINT NOT NULL,
                    reason VARCHAR(32) NOT NULL DEFAULT 'met',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (owner_character_id, known_character_id),
                    INDEX idx_owner (owner_character_id)
                )
            ]])
            return true
        end
    },
    {
        version = 5,
        name = '005_migrate_metadata_known_identities',
        run = function()
            local rows = MySQL.query.await([[
                SELECT id, metadata FROM characters
                WHERE metadata LIKE '%knownIdentities%' OR metadata LIKE '%knownPlayers%'
            ]]) or {}

            for _, r in ipairs(rows) do
                local charId = tonumber(r.id)
                local meta = DecodeJson(r.metadata)
                if charId and type(meta) == 'table' then
                    local legacy = meta.knownIdentities or meta.knownPlayers
                    if type(legacy) == 'table' then
                        for k, v in pairs(legacy) do
                            local knownId = tonumber(type(v) == 'table' and (v.characterId or v.charId) or k)
                            local reason = type(v) == 'table' and v.reason or 'met'
                            if knownId and knownId ~= charId then
                                MySQL.query.await([[
                                    INSERT INTO cm_known_identities (owner_character_id, known_character_id, reason)
                                    VALUES (?, ?, ?)
                                    ON DUPLICATE KEY UPDATE reason = VALUES(reason)
                                ]], { charId, knownId, tostring(reason or 'met'):sub(1, 32) })
                            end
                        end
                    end
                    meta.knownIdentities = nil
                    meta.knownPlayers = nil
                    MySQL.update.await('UPDATE characters SET metadata = ? WHERE id = ?', {
                        EncodeJson(meta), charId
                    })
                end
            end
            return true
        end
    },
    {
        version = 6,
        name = '006_reconcile_legacy_known_players',
        run = function()
            local rows = MySQL.query.await([[
                SELECT id, metadata FROM characters
                WHERE metadata LIKE '%knownIdentities%' OR metadata LIKE '%knownPlayers%'
            ]]) or {}

            for _, r in ipairs(rows) do
                local charId = tonumber(r.id)
                local meta = DecodeJson(r.metadata)
                if charId and type(meta) == 'table' then
                    local edges = {}

                    local function extractEdges(legacyTable)
                        if type(legacyTable) == 'table' then
                            for k, v in pairs(legacyTable) do
                                local knownId = tonumber(type(v) == 'table' and (v.characterId or v.charId) or k)
                                local reason = type(v) == 'table' and v.reason or 'met'
                                if knownId and knownId ~= charId then
                                    edges[knownId] = tostring(reason or 'met'):sub(1, 32)
                                end
                            end
                        end
                    end

                    -- Reconcile BOTH legacy metadata tables independently! Never 'or'!
                    extractEdges(meta.knownIdentities)
                    extractEdges(meta.knownPlayers)

                    local allSaved = true
                    for knownId, reason in pairs(edges) do
                        local okInsert = pcall(function()
                            MySQL.query.await([[
                                INSERT INTO cm_known_identities (owner_character_id, known_character_id, reason)
                                VALUES (?, ?, ?)
                                ON DUPLICATE KEY UPDATE reason = VALUES(reason)
                            ]], { charId, knownId, reason })
                        end)
                        if not okInsert then
                            allSaved = false
                            Log('error', 'Migration 006 failed to persist edge', { owner = charId, known = knownId })
                            break
                        end
                    end

                    -- Only remove legacy keys if all valid edges were successfully persisted!
                    if allSaved then
                        if meta.knownIdentities ~= nil or meta.knownPlayers ~= nil then
                            meta.knownIdentities = nil
                            meta.knownPlayers = nil
                            local okUpdate = pcall(function()
                                MySQL.update.await('UPDATE characters SET metadata = ? WHERE id = ?', {
                                    EncodeJson(meta), charId
                                })
                            end)
                            if not okUpdate then
                                Log('error', 'Migration 006 failed to update cleaned metadata', { charId = charId })
                            end
                        end
                    end
                end
            end
            return true
        end
    }
}

local function RunMigrations()
    if MigrationsReady then return true end
    if MigrationPromise then
        return Citizen.Await(MigrationPromise)
    end

    MigrationPromise = promise.new()

    local function fail(err)
        MigrationsReady = false
        local p = MigrationPromise
        MigrationPromise = nil
        p:resolve(false)
        return false
    end

    local okTable, errTable = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cm_playerdata_migrations (
                version INT NOT NULL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ]])
    end)

    if not okTable then
        Log('error', 'CRITICAL: Failed to initialize cm_playerdata_migrations table', { error = tostring(errTable) })
        return fail('table_init')
    end

    local applied = {}
    local okSelect, rows = pcall(function()
        return MySQL.query.await('SELECT version FROM cm_playerdata_migrations')
    end)
    if not okSelect or type(rows) ~= 'table' then
        Log('error', 'CRITICAL: Failed to query cm_playerdata_migrations', { error = tostring(rows) })
        return fail('query_applied')
    end

    for _, r in ipairs(rows) do
        applied[tonumber(r.version)] = true
    end

    for _, m in ipairs(Migrations) do
        if not applied[m.version] then
            print(('[CM-PLAYERDATA] Running migration %03d: %s...'):format(m.version, m.name))
            local okRun, runErr = pcall(m.run)
            if not okRun or runErr == false then
                Log('error', ('CRITICAL: Migration %03d (%s) failed!'):format(m.version, m.name), { error = tostring(runErr) })
                return fail('migration_run_' .. tostring(m.version))
            end

            local okRecord, recErr = pcall(function()
                MySQL.insert.await('INSERT INTO cm_playerdata_migrations (version, name) VALUES (?, ?)', { m.version, m.name })
            end)
            if not okRecord then
                Log('error', ('CRITICAL: Failed to record migration %03d (%s)'):format(m.version, m.name), { error = tostring(recErr) })
                return fail('migration_record_' .. tostring(m.version))
            end
            print(('[CM-PLAYERDATA] Migration %03d (%s) applied successfully.'):format(m.version, m.name))
        end
    end

    pcall(function()
        local legacyCount = MySQL.scalar.await("SELECT COUNT(*) FROM characters WHERE metadata LIKE '%knownIdentities%' OR metadata LIKE '%knownPlayers%'") or 0
        local relationCount = MySQL.scalar.await("SELECT COUNT(*) FROM cm_known_identities") or 0
        print(('[CM-PLAYERDATA] DB counts: legacy metadata rows remaining=%s, relational identity rows=%s'):format(legacyCount, relationCount))
    end)

    MigrationsReady = true
    Debug('Database migrations verified and up to date')
    local p = MigrationPromise
    MigrationPromise = nil
    p:resolve(true)
    return true
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(100)
    end
    RunMigrations()
end)

local function Audit(src, action, data)
    local charId = GetCharId(src)
    pcall(function()
        MySQL.insert.await(
            'INSERT INTO playerdata_audit (character_id, action, data) VALUES (?, ?, ?)',
            { charId, action, EncodeJson(data or {}) }
        )
    end)
end

local ValidMoneyAccounts = { cash = true, bank = true }
local MoneyMutationLocks = {}
local TransferLocks = {}

local function NormalizeAccount(account)
    account = tostring(account or 'cash'):lower()
    if account == 'money' then account = 'cash' end
    if account == 'wallet' then account = 'cash' end
    if account == 'account' then account = 'bank' end
    if not ValidMoneyAccounts[account] then return nil end
    return account
end

local function NormalizeAmount(amount)
    amount = tonumber(amount)
    if not amount then return nil end
    amount = math.floor(amount)
    if amount <= 0 then return nil end
    -- Prevent accidental overflow/cheat values from one call. Economy/admin can split if truly needed.
    if amount > ((Config.Money and Config.Money.MaxSingleChange) or 1000000000) then return nil end
    return amount
end

local function GetCallingResourceName()
    local invoking = GetInvokingResource and GetInvokingResource() or nil
    if invoking and invoking ~= '' then return invoking end
    return GetCurrentResourceName()
end

local function RecordMoneyTransaction(src, account, delta, action, reason, before, after, metadata)
    local charId = GetCharId(src)
    if not charId then return end

    local tx = {
        account = account,
        amount = delta,
        action = action,
        reason = reason,
        before = before,
        after = after,
        resource = GetCallingResourceName(),
        metadata = metadata or {}
    }

    pcall(function()
        MySQL.insert.await([[
            INSERT INTO economy_transactions
                (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            charId,
            account,
            delta,
            action,
            tostring(reason or action):sub(1, 100),
            tx.resource,
            before or 0,
            after or 0,
            EncodeJson(metadata or {})
        })
    end)

    Audit(src, 'money_' .. action, tx)
end

local function SaveMoneyOnly(src, reason)
    local data = PlayerData[src]
    if not data or not data.loaded then return false end

    local ok, err = pcall(function()
        MySQL.update.await('UPDATE characters SET cash = ?, bank = ? WHERE id = ?', {
            tonumber(data.cash) or 0,
            tonumber(data.bank) or 0,
            data.charId
        })
    end)

    if not ok then
        Log('error', 'Money save failed', { src = src, reason = reason, error = tostring(err) })
        return false
    end

    return true
end

local function ClonePlayerData(data)
    if not data then return nil end
    return {
        src = data.src,
        source = data.src,
        charId = data.charId,
        characterId = data.charId,
        firstName = data.firstName,
        lastName = data.lastName,
        fullName = BuildDisplayName(data.firstName, data.lastName),
        cash = data.cash,
        bank = data.bank,
        health = data.health,
        armor = data.armor,
        isDead = data.isDead,
        deathCount = data.deathCount,
        deathRemainingMs = data.deathDeadline and math.max(0, data.deathDeadline - GetGameTimer()) or nil,
        deathDeadlineAt = data.deathDeadlineAt,
        ambulanceCalled = data.ambulanceCalled == true,
        emsProtected = data.emsProtection ~= nil,
        emsEtaMs = data.emsProtection and math.max(0, (data.emsProtection.etaDeadline or GetGameTimer()) - GetGameTimer()) or nil,
        deathReason = data.deathReason,
        deathLocation = DeepCopy(data.deathLocation),
        lastPosition = DeepCopy(data.lastPosition),
        metadata = DeepCopy(data.metadata),
        loaded = data.loaded == true
    }
end

local function ApplyState(src)
    local data = PlayerData[src]
    if not data then return end

    local charId = tostring(data.charId or '')
    if charId ~= '' then
        SetState(src, 'charId', charId)
        SetState(src, 'characterId', charId)
        SetState(src, 'rpId', charId)
    end
    SetState(src, 'firstName', data.firstName or '')
    SetState(src, 'lastName', data.lastName or '')
    SetState(src, 'charName', BuildDisplayName(data.firstName, data.lastName))

    SetState(src, 'cash', data.cash)
    SetState(src, 'bank', data.bank)
    SetState(src, 'health', data.health)
    SetState(src, 'armor', data.armor)
    SetState(src, 'isDead', data.isDead)
    SetState(src, 'deathRemainingMs', data.deathDeadline and math.max(0, data.deathDeadline - GetGameTimer()) or nil)
    SetState(src, 'emsProtected', data.emsProtection ~= nil)
    SetState(src, 'deathLocation', data.isDead and NormalizeCoords(data.deathLocation) or nil)
    SetState(src, 'playerDataLoaded', true)
    SetState(src, 'identityReady', true)
end

local ScheduleBleedOut

local function NotifyLoaded(src)
    local data = PlayerData[src]
    if not data then return end

    ApplyState(src)
    local safeData = ClonePlayerData(data)

    -- New clean events. Legacy events are kept for existing resources.
    TriggerEvent('cm-playerdata:server:characterLoaded', src, safeData)
    TriggerClientEvent('cm-playerdata:client:characterLoaded', src, safeData)
    TriggerEvent('cm-playerdata:server:loaded', src, safeData)
    TriggerClientEvent('cm-playerdata:client:loaded', src, safeData)
    TriggerEvent('cm-playerdata:server:readyForSpawn', src, safeData)
end

local SaveWaiters = {} -- charId -> array of promise objects

local function CharacterRowExists(charId)
    local ok, value = pcall(function()
        return MySQL.scalar.await(
            'SELECT id FROM characters WHERE id = ? LIMIT 1',
            { tostring(charId) }
        )
    end)

    if not ok then
        return nil, 'query_failed'
    end

    return value ~= nil, nil
end

local function FinishSave(charId, success)
    ActiveSaves[charId] = nil

    local waiters = SaveWaiters[charId]
    SaveWaiters[charId] = nil

    if waiters then
        for _, waiter in ipairs(waiters) do
            waiter:resolve(success == true)
        end
    end
end

SavePlayerData = function(src, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data or not data.loaded or not data.charId then return false end

    local expectedData = data
    local expectedCharId = tostring(data.charId)
    local charId = expectedCharId

    -- If a save is already in progress for this character, await that save's completion
    if ActiveSaves[charId] then
        data.saveQueued = true
        Debug(('Save already active for char=%s; queuing and awaiting result'):format(charId))
        local p = promise.new()
        SaveWaiters[charId] = SaveWaiters[charId] or {}
        table.insert(SaveWaiters[charId], p)
        return Citizen.Await(p)
    end

    ActiveSaves[charId] = true

    -- Pre-encode immutable snapshot data BEFORE yielding to MySQL.
    -- Fail closed if JSON encoding of required tables fails; never silently persist corrupted/null state.
    local metadataJson = EncodeJson(data.metadata or {})
    if data.metadata ~= nil and not metadataJson then
        FinishSave(charId, false)
        Log('error', 'Save aborted: metadata JSON encoding failed', { src = src, charId = charId })
        if PlayerData[src] == expectedData and tostring(PlayerData[src].charId or '') == charId then
            PlayerData[src].dirty = true
        end
        return false
    end

    local deathLocationJson = nil
    if data.deathLocation ~= nil then
        deathLocationJson = EncodeJson(data.deathLocation)
        if not deathLocationJson then
            FinishSave(charId, false)
            Log('error', 'Save aborted: deathLocation JSON encoding failed', { src = src, charId = charId })
            if PlayerData[src] == expectedData and tostring(PlayerData[src].charId or '') == charId then
                PlayerData[src].dirty = true
            end
            return false
        end
    end

    local lastPositionJson = nil
    if data.lastPosition ~= nil then
        lastPositionJson = EncodeJson(data.lastPosition)
        if not lastPositionJson then
            FinishSave(charId, false)
            Log('error', 'Save aborted: lastPosition JSON encoding failed', { src = src, charId = charId })
            if PlayerData[src] == expectedData and tostring(PlayerData[src].charId or '') == charId then
                PlayerData[src].dirty = true
            end
            return false
        end
    end

    local savedRevision = tonumber(data.revision) or 1
    local snapshot = {
        charId = charId,
        cash = tonumber(data.cash) or 0,
        bank = tonumber(data.bank) or 0,
        health = tonumber(data.health) or Config.Vitals.MaxHealth,
        armor = tonumber(data.armor) or 0,
        isDead = data.isDead == true,
        deathCount = tonumber(data.deathCount) or 0,
        deathDeadlineAt = data.deathDeadlineAt,
        deathLocation = data.deathLocation,
        deathLocationJson = deathLocationJson,
        ambulanceCalled = data.ambulanceCalled == true,
        deathReason = data.deathReason,
        lastPosition = data.lastPosition,
        lastPositionJson = lastPositionJson,
        metadataJson = metadataJson or '{}',
        revision = savedRevision
    }

    -- OPTION A: When Config.Money.ImmediateSave is enabled (default), cash and bank
    -- are already persisted synchronously via authoritative atomic transactions.
    -- Ordinary full SavePlayerData EXCLUDES cash and bank to guarantee a long-running
    -- full save can NEVER overwrite a newer balance updated during MySQL yield.
    local immediateMoney = (Config.Money and Config.Money.ImmediateSave) ~= false
    local ok, updateResult

    if immediateMoney then
        ok, updateResult = pcall(function()
            return MySQL.update.await([[
                UPDATE characters SET
                    health = ?,
                    armor = ?,
                    is_dead = ?,
                    death_count = ?,
                    death_deadline_at = ?,
                    death_location = ?,
                    ambulance_called = ?,
                    death_reason = ?,
                    last_position = ?,
                    metadata = ?
                WHERE id = ?
            ]], {
                snapshot.health,
                snapshot.armor,
                snapshot.isDead and 1 or 0,
                snapshot.deathCount,
                snapshot.deathDeadlineAt,
                snapshot.deathLocationJson,
                snapshot.ambulanceCalled and 1 or 0,
                snapshot.deathReason,
                snapshot.lastPositionJson,
                snapshot.metadataJson,
                snapshot.charId
            })
        end)
    else
        ok, updateResult = pcall(function()
            return MySQL.update.await([[
                UPDATE characters SET
                    cash = ?,
                    bank = ?,
                    health = ?,
                    armor = ?,
                    is_dead = ?,
                    death_count = ?,
                    death_deadline_at = ?,
                    death_location = ?,
                    ambulance_called = ?,
                    death_reason = ?,
                    last_position = ?,
                    metadata = ?
                WHERE id = ?
            ]], {
                snapshot.cash,
                snapshot.bank,
                snapshot.health,
                snapshot.armor,
                snapshot.isDead and 1 or 0,
                snapshot.deathCount,
                snapshot.deathDeadlineAt,
                snapshot.deathLocationJson,
                snapshot.ambulanceCalled and 1 or 0,
                snapshot.deathReason,
                snapshot.lastPositionJson,
                snapshot.metadataJson,
                snapshot.charId
            })
        end)
    end

    local rowsAffected = ok and tonumber(updateResult) or 0
    local saveSuccess = false
    if ok == true then
        if rowsAffected == 1 then
            saveSuccess = true
        elseif rowsAffected == 0 then
            local exists, err = CharacterRowExists(charId)
            if exists == true then
                saveSuccess = true
            elseif exists == false then
                Log('error', 'SavePlayerData failed: character row missing in database', { src = src, charId = charId })
            else
                Log('error', 'SavePlayerData failed: database verification query failed', { src = src, charId = charId, error = tostring(err) })
            end
        end
    end

    FinishSave(charId, saveSuccess)

    if not saveSuccess then
        Log('error', 'SavePlayerData failed or affected row count mismatch', {
            src = src,
            charId = charId,
            reason = reason,
            ok = ok,
            affectedRows = tostring(updateResult)
        })
        if PlayerData[src] == expectedData and tostring(PlayerData[src].charId or '') == charId then
            PlayerData[src].dirty = true
        end
        return false
    end

    -- Confirm character and source reuse safety before mutating runtime state
    local current = PlayerData[src]
    if current == expectedData and tostring(current.charId or '') == expectedCharId then
        current.persistedPosition = snapshot.lastPosition
        current.persistedRevision = savedRevision
        if current.revision == savedRevision and not current.saveQueued then
            current.dirty = false
        else
            current.dirty = true
            if current.saveQueued then
                current.saveQueued = nil
                SetTimeout(50, function()
                    if PlayerData[src] == expectedData and PlayerData[src].loaded and tostring(PlayerData[src].charId) == expectedCharId and PlayerData[src].dirty then
                        SavePlayerData(src, 'queued_save')
                    end
                end)
            end
        end
    end

    Debug(('Saved src=%s char=%s rev=%s reason=%s'):format(src, charId, savedRevision, reason or 'manual'))
    return true
end

local function SavePositionOnly(src)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data or not data.loaded or not data.charId or not data.lastPosition then return false end

    -- Optimization: Check Config.Save.MinimumPositionMove
    local minMove = (Config.Save and Config.Save.MinimumPositionMove) or 1.5
    local current = data.lastPosition
    local persisted = data.persistedPosition

    if persisted and current then
        local dx = (current.x or 0) - (persisted.x or 0)
        local dy = (current.y or 0) - (persisted.y or 0)
        local dz = (current.z or 0) - (persisted.z or 0)
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        local dh = math.abs((current.h or 0) - (persisted.h or 0))
        if dh > 180 then dh = 360 - dh end

        if dist < minMove and dh < 30.0 then
            -- Movement below threshold, skip write!
            return true
        end
    end

    local charId = tostring(data.charId)
    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE characters SET last_position = ? WHERE id = ?',
            { EncodeJson(current), charId }
        )
    end)

    local rowsAffected = ok and tonumber(affected) or 0
    local positionSuccess = false
    if ok == true then
        if rowsAffected == 1 then
            positionSuccess = true
        elseif rowsAffected == 0 then
            local exists, err = CharacterRowExists(charId)
            if exists == true then
                positionSuccess = true
            elseif exists == false then
                Log('error', 'SavePositionOnly failed: character row missing in database', { src = src, charId = charId })
            else
                Log('error', 'SavePositionOnly failed: database verification query failed', { src = src, charId = charId, error = tostring(err) })
            end
        end
    end

    if positionSuccess then
        data.persistedPosition = current
        return true
    else
        Log('error', 'Position save failed or affected rows mismatch', {
            src = src, charId = charId, ok = ok, affectedRows = tostring(affected)
        })
        return false
    end
end

local function FlushPlayerData(src, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data or not data.loaded or not data.charId then return true end

    local charId = tostring(data.charId)
    local maxRetries = 20
    local retries = 0

    while retries < maxRetries do
        if not ActiveSaves[charId] and not data.dirty and (tonumber(data.persistedRevision) == tonumber(data.revision)) then
            return true
        end

        if ActiveSaves[charId] then
            local p = promise.new()
            SaveWaiters[charId] = SaveWaiters[charId] or {}
            table.insert(SaveWaiters[charId], p)
            local ok = Citizen.Await(p)
            if not ok and (not ActiveSaves[charId] and data.dirty) then
                Citizen.Wait(100)
            end
        else
            local saved = SavePlayerData(src, reason or 'flush')
            if not saved then
                Citizen.Wait(100)
            end
        end

        retries = retries + 1
    end

    local flushed = (not ActiveSaves[charId] and not data.dirty and (tonumber(data.persistedRevision) == tonumber(data.revision)))
    if not flushed then
        Log('error', 'FlushPlayerData timeout / incomplete flush', {
            src = src,
            charId = charId,
            reason = reason,
            dirty = data.dirty,
            activeSave = ActiveSaves[charId] == true,
            revision = data.revision,
            persistedRevision = data.persistedRevision
        })
    end
    return flushed
end

local function ClearPlayerData(src)
    local oldData = PlayerData[src]
    if oldData then
        if oldData.charId then
            ClearIdentityCache(oldData.charId)
        end
        local safeData = ClonePlayerData(oldData)
        TriggerEvent('cm-playerdata:server:characterUnloaded', src, safeData)
        TriggerClientEvent('cm-playerdata:client:characterUnloaded', src, safeData)
        TriggerEvent('cm-playerdata:server:unloaded', src, safeData)
        TriggerClientEvent('cm-playerdata:client:unloaded', src, safeData)
    end

    PlayerData[src] = nil
    pcall(function()
        local state = Player(src).state
        state:set('cash', nil, true)
        state:set('bank', nil, true)
        state:set('health', nil, true)
        state:set('armor', nil, true)
        state:set('isDead', nil, true)
        state:set('deathRemainingMs', nil, true)
        state:set('playerDataLoaded', nil, true)
        state:set('identityReady', nil, true)
        state:set('charId', nil, true)
        state:set('characterId', nil, true)
        state:set('rpId', nil, true)
        state:set('charName', nil, true)
        state:set('firstName', nil, true)
        state:set('lastName', nil, true)
    end)
    ClearRateLimits(src)
end

local function LoadPlayerData(src, explicitCharId)
    src = tonumber(src)
    if not src or src <= 0 then return false end

    local waitCount = 0
    while not MigrationsReady and waitCount < 50 do
        Wait(100)
        waitCount = waitCount + 1
    end
    if not MigrationsReady then
        Log('error', 'LoadPlayerData rejected: database migrations not ready', { src = src })
        return false, 'database_not_ready'
    end

    if LoadLocks[src] then
        Debug(('Load already in progress for src=%s'):format(src))
        return false
    end
    LoadLocks[src] = true

    local function unlock()
        LoadLocks[src] = nil
    end

    local charId = explicitCharId and tostring(explicitCharId) or GetCharId(src)
    if not charId or charId == '' then
        Debug('Load skipped, charId missing for src=' .. tostring(src))
        unlock()
        return false
    end

    -- Authoritative ownership check: playerdata must never load an arbitrary character
    local valid, ownerOrErr, validatedAccountId = ValidateCharacterOwnership(src, charId)
    if not valid then
        Log('warn', 'Character load rejected: ownership validation failed', { src = src, charId = charId, reason = tostring(ownerOrErr) })
        Audit(src, 'character_load_denied', { charId = charId, reason = tostring(ownerOrErr) })
        unlock()
        return false
    end

    -- Character switch: if existing loaded character is different
    if PlayerData[src] and PlayerData[src].loaded then
        local oldCharId = tostring(PlayerData[src].charId or '')
        if oldCharId ~= '' and oldCharId ~= tostring(charId) then
            Debug(('Character switch initiated for src=%s: %s -> %s'):format(src, oldCharId, charId))
            CharacterSwitchLocks[src] = true

            local oldData = PlayerData[src]
            oldData.switching = true -- block concurrent mutations for old character

            -- Authoritatively flush old character to DB
            local flushOk = FlushPlayerData(src, 'character_switch')

            if not flushOk or oldData.dirty or (tonumber(oldData.persistedRevision) ~= tonumber(oldData.revision)) then
                -- CRITICAL: Fail closed! Do NOT discard old character if persistence failed.
                Log('error', 'Character switch ABORTED: failed to flush character A', {
                    src = src,
                    oldCharId = oldCharId,
                    newCharId = charId,
                    flushOk = flushOk,
                    dirty = oldData.dirty,
                    revision = oldData.revision,
                    persistedRevision = oldData.persistedRevision
                })
                oldData.switching = nil
                CharacterSwitchLocks[src] = nil
                unlock()
                return false, 'character_switch_save_failed'
            end

            -- Persistence verified! Old character state safely persisted to DB.
            ClearPlayerData(src)
            CharacterSwitchLocks[src] = nil
        elseif oldCharId == tostring(charId) then
            -- Already loaded for this character
            Debug(('Character %s already loaded for src=%s'):format(charId, src))
            NotifyLoaded(src)
            unlock()
            return true
        end
    end

    local row = MySQL.single.await([[
        SELECT first_name, last_name, cash, bank, health, armor, is_dead, death_count, death_deadline_at, death_location, ambulance_called, death_reason, last_position, metadata
        FROM characters
        WHERE id = ?
        LIMIT 1
    ]], { charId })

    if not row then
        Log('error', 'Load failed: character row not found', { src = src, charId = charId })
        unlock()
        return false
    end

    local defaults = Config.Defaults

    local dirtyAfterLoad = false
    local persistedMetadata = DecodeJson(row.metadata) or {}
    local persistedWanted = type(persistedMetadata.cmWanted) == 'table' and persistedMetadata.cmWanted or {}
    local wantedStars = math.max(0, math.min((Config.WantedStars and Config.WantedStars.Max) or 6,
        math.floor(tonumber(persistedWanted.stars) or 0)))
    local decaySeconds = math.max(60, math.floor(((Config.WantedStars and Config.WantedStars.DecayIntervalMs) or 3600000) / 1000))
    local nextDecayAt = tonumber(persistedWanted.nextDecayAt) or 0
    if wantedStars > 0 and nextDecayAt <= 0 then
        nextDecayAt = os.time() + decaySeconds
        persistedWanted.nextDecayAt = nextDecayAt
        persistedMetadata.cmWanted = persistedWanted
        dirtyAfterLoad = true
    elseif wantedStars > 0 and os.time() >= nextDecayAt then
        local elapsedIntervals = math.floor((os.time() - nextDecayAt) / decaySeconds) + 1
        wantedStars = math.max(0, wantedStars - elapsedIntervals)
        nextDecayAt = wantedStars > 0 and (nextDecayAt + elapsedIntervals * decaySeconds) or 0
        persistedWanted.stars, persistedWanted.nextDecayAt = wantedStars, nextDecayAt
        persistedMetadata.cmWanted = persistedWanted
        dirtyAfterLoad = true
    end

    local isDead = (tonumber(row.is_dead) or 0) == 1
    local deathDeadlineAt = tonumber(row.death_deadline_at)
    local deathDeadline = nil

    if isDead then
        local now = NowMs()
        local bleedMs = (Config.Respawn and Config.Respawn.BleedOutTime) or 120000
        local minRejoin = (Config.Respawn and Config.Respawn.MinimumRejoinBleedOut) or 15000

        if not deathDeadlineAt or deathDeadlineAt <= 0 then
            deathDeadlineAt = now + bleedMs
            dirtyAfterLoad = true
        end

        local remaining = deathDeadlineAt - now
        if remaining <= 0 then
            remaining = 1500
            deathDeadlineAt = now + remaining
            dirtyAfterLoad = true
        elseif remaining < minRejoin then
            remaining = minRejoin
            deathDeadlineAt = now + remaining
            dirtyAfterLoad = true
        end

        deathDeadline = GetGameTimer() + remaining
    end

    local initialPosition = NormalizeCoords(DecodeJson(row.last_position))

    PlayerData[src] = {
        src = src,
        charId = charId,
        accountId = tostring(validatedAccountId or ''),
        firstName = row.first_name or '',
        lastName = row.last_name or '',

        cash = tonumber(row.cash) or defaults.cash,
        bank = tonumber(row.bank) or defaults.bank,

        health = isDead and (Config.Vitals.DamageThreshold or 101) or Clamp(row.health or defaults.health, 0, Config.Vitals.MaxHealth),
        armor = Clamp(row.armor or defaults.armor, 0, Config.Vitals.MaxArmor),

        isDead = isDead,
        deathCount = tonumber(row.death_count) or defaults.death_count,
        deathDeadline = deathDeadline,
        deathDeadlineAt = deathDeadlineAt,
        ambulanceCalled = (tonumber(row.ambulance_called) or 0) == 1,
        deathReason = row.death_reason,
        deathLocation = NormalizeCoords(DecodeJson(row.death_location)),
        lastPosition = initialPosition,
        persistedPosition = initialPosition,
        metadata = persistedMetadata,

        wantedStars = wantedStars,
        wantedStarChangedAt = GetGameTimer(),

        loaded = true,
        dirty = dirtyAfterLoad,
        revision = dirtyAfterLoad and 2 or 1,
        persistedRevision = 1,
        lastVitalsSync = GetGameTimer(),
        armorGuardUntil = GetGameTimer() + 5000
    }

    if PlayerData[src].isDead and not PlayerData[src].deathLocation then
        PlayerData[src].deathLocation = NormalizeCoords(PlayerData[src].lastPosition) or NormalizeCoords(Config.Respawn and Config.Respawn.HospitalSpawn)
        MarkDirty(PlayerData[src])
    end

    Debug(('Loaded src=%s char=%s HP=%s armor=%s dead=%s'):format(
        src, charId, PlayerData[src].health, PlayerData[src].armor, tostring(PlayerData[src].isDead)
    ))

    local okWarm = WarmIdentityCache(charId)
    if not okWarm then
        local expectedSrc = src
        local expectedCharId = tostring(charId)
        CreateThread(function()
            local attempts = 0
            local maxAttempts = 3
            while attempts < maxAttempts do
                Wait(2000 * (attempts + 1))
                local curData = PlayerData[expectedSrc]
                if not curData or tostring(curData.charId or '') ~= expectedCharId or not curData.loaded then
                    break
                end
                local okRetry = WarmIdentityCache(expectedCharId)
                if okRetry then
                    Debug(('Identity cache successfully hydrated on retry %d for src=%s char=%s'):format(attempts + 1, expectedSrc, expectedCharId))
                    for otherSrc, otherData in pairs(PlayerData) do
                        if otherData.loaded and otherSrc ~= expectedSrc then
                            PushIdentityUpdate(expectedSrc, otherSrc)
                        end
                    end
                    break
                end
                attempts = attempts + 1
            end
        end)
    end
    NotifyLoaded(src)
    pcall(function() exports['cm-police']:SyncWantedStars(charId, wantedStars) end)

    if PlayerData[src].isDead and PlayerData[src].deathDeadline then
        ScheduleBleedOut(src)
        if PlayerData[src].dirty then
            SavePlayerData(src, 'dead_rejoin_deadline_restore')
        end
    end

    unlock()
    return true
end

local function TransferMoneyBetweenPlayersAuthoritative(fromSrc, toSrc, account, amount, reason, metadata)
    fromSrc = tonumber(fromSrc)
    toSrc = tonumber(toSrc)
    account = NormalizeAccount(account)
    amount = NormalizeAmount(amount)

    if not fromSrc or not toSrc then return false, 'invalid_players' end
    if fromSrc == toSrc then return false, 'same_player' end
    if not account then return false, 'invalid_account' end
    if not amount or amount <= 0 then return false, 'invalid_amount' end

    local fromData = PlayerData[fromSrc]
    local toData = PlayerData[toSrc]
    if not fromData or not fromData.loaded or not toData or not toData.loaded then
        return false, 'player_not_loaded'
    end
    if not CanMutate(fromData) or not CanMutate(toData) then
        return false, 'character_switching'
    end

    local fromCharId = tostring(fromData.charId or '')
    local toCharId = tostring(toData.charId or '')
    if fromCharId == '' or toCharId == '' or fromCharId == toCharId then
        return false, 'same_character'
    end

    -- Deterministic lock acquisition on character IDs to eliminate deadlocks
    local charNumA = tonumber(fromCharId) or 0
    local charNumB = tonumber(toCharId) or 0
    local lock1 = (charNumA < charNumB) and fromCharId or toCharId
    local lock2 = (charNumA < charNumB) and toCharId or fromCharId

    if TransferLocks[lock1] or TransferLocks[lock2] or MoneyMutationLocks[fromSrc] or MoneyMutationLocks[toSrc] then
        return false, 'money_busy'
    end
    TransferLocks[lock1] = true
    TransferLocks[lock2] = true
    MoneyMutationLocks[fromSrc] = true
    MoneyMutationLocks[toSrc] = true

    local function releaseLocks()
        TransferLocks[lock1] = nil
        TransferLocks[lock2] = nil
        MoneyMutationLocks[fromSrc] = nil
        MoneyMutationLocks[toSrc] = nil
    end

    -- Verify balances inside lock
    local fromBefore = tonumber(fromData[account]) or 0
    if fromBefore < amount then
        releaseLocks()
        return false, 'insufficient_funds'
    end

    local toBefore = tonumber(toData[account]) or 0
    local fromAfter = fromBefore - amount
    local toAfter = toBefore + amount

    -- Single atomic self-join UPDATE query:
    -- In MySQL/MariaDB, updating joined rows in a single statement guarantees atomicity.
    -- We verify BOTH sender and recipient database balances equal expected runtime balances.
    -- If either sender or recipient balance is stale in the DB, 0 rows match the join/where condition.
    -- If and ONLY IF both exist and both DB balances match expected runtime balances, affectedRows is EXACTLY 2.
    local query = ('UPDATE characters c1 JOIN characters c2 ON c2.id = ? AND c2.%s = ? SET c1.%s = ?, c2.%s = ? WHERE c1.id = ? AND c1.%s = ?'):format(account, account, account, account)
    local updateOk, affectedRows = pcall(function()
        return MySQL.update.await(query, { toCharId, toBefore, fromAfter, toAfter, fromCharId, fromBefore })
    end)

    if not updateOk or tonumber(affectedRows) ~= 2 then
        releaseLocks()
        Log('error', 'Authoritative P2P money transfer failed: balance mismatch, missing row, or SQL error', {
            from = fromCharId, to = toCharId, account = account, amount = amount,
            fromBefore = fromBefore, toBefore = toBefore,
            updateOk = updateOk, affectedRows = tostring(affectedRows)
        })
        return false, 'stale_balance'
    end

    -- Atomic persistence proven! Update in-memory balances and revision tracking:
    fromData[account] = fromAfter
    toData[account] = toAfter
    MarkDirty(fromData)
    MarkDirty(toData)

    SetState(fromSrc, account, fromAfter)
    SetState(toSrc, account, toAfter)
    PushUpdate(fromSrc, account, fromAfter)
    PushUpdate(toSrc, account, toAfter)

    releaseLocks()

    -- Insert confirmed audit records in economy_transactions
    local callingResource = GetCallingResourceName()
    local safeMeta = type(metadata) == 'table' and metadata or {}
    local fromMeta = DecodeJson(EncodeJson(safeMeta)) or {}
    local toMeta = DecodeJson(EncodeJson(safeMeta)) or {}
    fromMeta.counterparty_character_id = toCharId
    fromMeta.counterparty_source = toSrc
    toMeta.counterparty_character_id = fromCharId
    toMeta.counterparty_source = fromSrc

    local auditOk, auditErr = pcall(function()
        MySQL.query.await([[
            INSERT INTO economy_transactions
                (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?),
                (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            fromCharId, account, -amount, 'transfer_out',
            tostring(reason or 'p2p_transfer_out'):sub(1, 100),
            callingResource, fromBefore, fromAfter, EncodeJson(fromMeta),
            toCharId, account, amount, 'transfer_in',
            tostring(reason or 'p2p_transfer_in'):sub(1, 100),
            callingResource, toBefore, toAfter, EncodeJson(toMeta)
        })
    end)
    if not auditOk then
        Log('error', 'CRITICAL AUDIT FAILURE: money transferred but audit record failed', {
            from = fromCharId, to = toCharId, account = account, amount = amount, error = tostring(auditErr)
        })
    end

    TriggerEvent('cm-playerdata:server:moneyChanged', fromSrc, account, fromBefore, fromAfter, reason or 'p2p_transfer_out')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', fromSrc, account, fromBefore, fromAfter, reason or 'p2p_transfer_out')
    TriggerEvent('cm-playerdata:server:moneyChanged', toSrc, account, toBefore, toAfter, reason or 'p2p_transfer_in')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', toSrc, account, toBefore, toAfter, reason or 'p2p_transfer_in')

    Audit(fromSrc, 'transfer_p2p_out', { to = toCharId, account = account, amount = amount, reason = reason })
    Audit(toSrc, 'transfer_p2p_in', { from = fromCharId, account = account, amount = amount, reason = reason })

    return true, nil
end

local function SetMoney(src, account, value, reason, metadata)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    account = NormalizeAccount(account)
    if not CanMutate(data) or not account or MoneyMutationLocks[src] then return false end

    local before = tonumber(data[account]) or 0
    local after = math.max(0, math.floor(tonumber(value) or 0))
    local delta = after - before
    if before == after then return true end

    MoneyMutationLocks[src] = true

    if Config.Money and Config.Money.ImmediateSave then
        local queries = {
            {
                query = 'UPDATE characters SET ' .. account .. ' = ? WHERE id = ?',
                values = { after, data.charId }
            }
        }
        if (Config.Money and Config.Money.TransactionLog) ~= false then
            queries[#queries + 1] = {
                query = [[
                    INSERT INTO economy_transactions
                        (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ]],
                values = {
                    data.charId, account, delta, 'set',
                    tostring(reason or 'set_money'):sub(1, 100),
                    GetCallingResourceName(), before, after,
                    EncodeJson(metadata or {})
                }
            }
        end

        local ok, err = pcall(function() return MySQL.transaction.await(queries) end)
        MoneyMutationLocks[src] = nil
        if not ok or err ~= true then
            Log('error', 'SetMoney persistence failed', { src = src, charId = data.charId, error = tostring(err) })
            return false
        end
    else
        MoneyMutationLocks[src] = nil
        MarkDirty(data)
        if (Config.Money and Config.Money.TransactionLog) ~= false then
            RecordMoneyTransaction(src, account, delta, 'set', reason or 'set_money', before, after, metadata)
        end
    end

    data[account] = after
    data.revision = (data.revision or 1) + 1

    SetState(src, account, after)
    PushUpdate(src, account, after)
    TriggerEvent('cm-playerdata:server:moneyChanged', src, account, before, after, reason or 'set_money')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, account, before, after, reason or 'set_money')
    Audit(src, 'money_set', { account = account, before = before, after = after, reason = reason })

    return true
end

local function AddMoney(src, account, amount, reason, metadata)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    account = NormalizeAccount(account)
    amount = NormalizeAmount(amount)
    if not CanMutate(data) or not account or not amount or MoneyMutationLocks[src] then return false end

    local before = tonumber(data[account]) or 0
    local after = before + amount

    MoneyMutationLocks[src] = true

    if Config.Money and Config.Money.ImmediateSave then
        local queries = {
            {
                query = 'UPDATE characters SET ' .. account .. ' = ? WHERE id = ?',
                values = { after, data.charId }
            }
        }
        if (Config.Money and Config.Money.TransactionLog) ~= false then
            queries[#queries + 1] = {
                query = [[
                    INSERT INTO economy_transactions
                        (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ]],
                values = {
                    data.charId, account, amount, 'add',
                    tostring(reason or 'add_money'):sub(1, 100),
                    GetCallingResourceName(), before, after,
                    EncodeJson(metadata or {})
                }
            }
        end

        local ok, err = pcall(function() return MySQL.transaction.await(queries) end)
        MoneyMutationLocks[src] = nil
        if not ok or err ~= true then
            Log('error', 'AddMoney persistence failed', { src = src, charId = data.charId, error = tostring(err) })
            return false
        end
    else
        MoneyMutationLocks[src] = nil
        MarkDirty(data)
        if (Config.Money and Config.Money.TransactionLog) ~= false then
            RecordMoneyTransaction(src, account, amount, 'add', reason or 'add_money', before, after, metadata)
        end
    end

    data[account] = after
    data.revision = (data.revision or 1) + 1

    SetState(src, account, after)
    PushUpdate(src, account, after)
    TriggerEvent('cm-playerdata:server:moneyChanged', src, account, before, after, reason or 'add_money')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, account, before, after, reason or 'add_money')
    Audit(src, 'money_add', { account = account, amount = amount, before = before, after = after, reason = reason })

    return true
end

local function RemoveMoney(src, account, amount, reason, metadata)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    account = NormalizeAccount(account)
    amount = NormalizeAmount(amount)
    if not CanMutate(data) or not account or not amount or MoneyMutationLocks[src] then return false end

    local before = tonumber(data[account]) or 0
    if before < amount then return false end
    local after = before - amount

    MoneyMutationLocks[src] = true

    if Config.Money and Config.Money.ImmediateSave then
        local queries = {
            {
                query = 'UPDATE characters SET ' .. account .. ' = ? WHERE id = ? AND ' .. account .. ' >= ?',
                values = { after, data.charId, amount }
            }
        }
        if (Config.Money and Config.Money.TransactionLog) ~= false then
            queries[#queries + 1] = {
                query = [[
                    INSERT INTO economy_transactions
                        (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ]],
                values = {
                    data.charId, account, -amount, 'remove',
                    tostring(reason or 'remove_money'):sub(1, 100),
                    GetCallingResourceName(), before, after,
                    EncodeJson(metadata or {})
                }
            }
        end

        local ok, err = pcall(function() return MySQL.transaction.await(queries) end)
        MoneyMutationLocks[src] = nil
        if not ok or err ~= true then
            Log('error', 'RemoveMoney persistence failed', { src = src, charId = data.charId, error = tostring(err) })
            return false
        end
    else
        MoneyMutationLocks[src] = nil
        MarkDirty(data)
        if (Config.Money and Config.Money.TransactionLog) ~= false then
            RecordMoneyTransaction(src, account, -amount, 'remove', reason or 'remove_money', before, after, metadata)
        end
    end

    data[account] = after
    data.revision = (data.revision or 1) + 1

    SetState(src, account, after)
    PushUpdate(src, account, after)
    TriggerEvent('cm-playerdata:server:moneyChanged', src, account, before, after, reason or 'remove_money')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, account, before, after, reason or 'remove_money')
    Audit(src, 'money_remove', { account = account, amount = amount, before = before, after = after, reason = reason })

    return true
end

local function CanAfford(src, account, amount)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    account = NormalizeAccount(account)
    amount = NormalizeAmount(amount)
    if not data or not data.loaded or not account or not amount then return false end
    return (tonumber(data[account]) or 0) >= amount
end

local function TransferMoney(src, fromAccount, toAccount, amount, reason, metadata)
    src = tonumber(src)
    fromAccount = NormalizeAccount(fromAccount)
    toAccount = NormalizeAccount(toAccount)
    amount = NormalizeAmount(amount)
    if not src or not fromAccount or not toAccount or not amount or fromAccount == toAccount then return false end

    local data = PlayerData[src]
    if not CanMutate(data) then return false end

    if MoneyMutationLocks[src] then return false end
    MoneyMutationLocks[src] = true

    local function release()
        MoneyMutationLocks[src] = nil
    end

    local fromBefore = tonumber(data[fromAccount]) or 0
    if fromBefore < amount then
        release()
        return false
    end

    local toBefore = tonumber(data[toAccount]) or 0
    local fromAfter = fromBefore - amount
    local toAfter = toBefore + amount

    local callingResource = GetCallingResourceName()
    local safeMeta = type(metadata) == 'table' and metadata or {}

    local queries = {
        {
            query = 'UPDATE characters SET ' .. fromAccount .. ' = ?, ' .. toAccount .. ' = ? WHERE id = ? AND ' .. fromAccount .. ' >= ?',
            values = { fromAfter, toAfter, data.charId, amount }
        },
        {
            query = [[
                INSERT INTO economy_transactions
                    (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                data.charId, fromAccount, -amount, 'transfer_out',
                tostring(reason or 'transfer_between_accounts'):sub(1, 100),
                callingResource, fromBefore, fromAfter, EncodeJson(safeMeta)
            }
        },
        {
            query = [[
                INSERT INTO economy_transactions
                    (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                data.charId, toAccount, amount, 'transfer_in',
                tostring(reason or 'transfer_between_accounts'):sub(1, 100),
                callingResource, toBefore, toAfter, EncodeJson(safeMeta)
            }
        }
    }

    local ok, err = pcall(function() return MySQL.transaction.await(queries) end)
    release()

    if not ok or err ~= true then
        Log('error', 'Same-player transfer transaction failed', { src = src, charId = data.charId, error = tostring(err) })
        return false
    end

    data[fromAccount] = fromAfter
    data[toAccount] = toAfter
    data.revision = (data.revision or 1) + 1

    SetState(src, fromAccount, fromAfter)
    SetState(src, toAccount, toAfter)
    PushUpdate(src, fromAccount, fromAfter)
    PushUpdate(src, toAccount, toAfter)

    TriggerEvent('cm-playerdata:server:moneyChanged', src, fromAccount, fromBefore, fromAfter, reason or 'transfer_out')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, fromAccount, fromBefore, fromAfter, reason or 'transfer_out')
    TriggerEvent('cm-playerdata:server:moneyChanged', src, toAccount, toBefore, toAfter, reason or 'transfer_in')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, toAccount, toBefore, toAfter, reason or 'transfer_in')

    Audit(src, 'transfer_accounts', { from = fromAccount, to = toAccount, amount = amount, reason = reason })
    return true
end

local function TransferCashBetweenCharactersAtomic(fromSrc, toSrc, amount, reason, metadata)
    return TransferMoneyBetweenPlayersAuthoritative(fromSrc, toSrc, 'cash', amount, reason or 'atomic_cash_transfer', metadata)
end

local function SyncInventoryDeathState(src, dead)
    if GetResourceState('cm-inventory') ~= 'started' then return end

    local ok, err = pcall(function()
        if dead then
            local data=PlayerData[tonumber(src)];local characterId=data and tostring(data.charId or'')or'';local context=characterId~=''and SupplyWarDeathContexts[characterId]or nil
            local suppress=context~=nil and context.source==tonumber(src) and context.expiresAt>os.time()
            if not suppress and GetResourceState('cm-gang')=='started'then local participantOk,value=pcall(function()return exports['cm-gang']:IsSupplyWarParticipant(src)end);suppress=participantOk and value==true end
            if not suppress then exports['cm-inventory']:DropEquippedWeaponsOnDeath(src)end
        else
            exports['cm-inventory']:ResetDeathDropState(src)
        end
    end)

    if not ok then
        Log('warn', 'Inventory death-state sync failed', { src = src, dead = dead == true, error = tostring(err) })
    end
end

local function SetDead(src, isDead, reason)
    local data = PlayerData[src]
    if not CanMutate(data) then return false end

    local wasDead = data.isDead == true
    data.isDead = isDead == true
    if data.isDead and not wasDead and GetResourceState('cm-gang')=='started' then
        local participantOk,participant=pcall(function()return exports['cm-gang']:IsSupplyWarParticipant(src)end)
        if participantOk and participant==true then
            CaptureSupplyWarDeathContext(src,nil)
        end
    end
    if data.isDead then
        data.health = Config.Vitals.DamageThreshold or 101
        data.armor = 0
        data.deathCount = (data.deathCount or 0) + 1
        data.deathReason = reason or 'death'
        -- Save the real death/body location immediately. If the player reconnects
        -- while dead, cm-spawn must return them here no matter which spawn card
        -- they click, then cm-playerdata shows the death screen after spawn.
        local deathCoords = GetPedCoordsTable(src) or NormalizeCoords(data.deathLocation) or NormalizeCoords(data.lastPosition)
        data.deathLocation = deathCoords
        data.lastPosition = deathCoords
    else
        data.deathLocation = nil
        data.deathDeadline = nil
        data.deathDeadlineAt = nil
        data.ambulanceCalled = false
        data.emsProtection = nil
        data.dieChosen = false
        data.deathReason = nil
    end
    MarkDirty(data)

    ApplyState(src)
    SyncInventoryDeathState(src, data.isDead)
    Audit(src, data.isDead and 'death' or 'revive', { reason = reason })
    SavePlayerData(src, reason or (data.isDead and 'death' or 'revive'))
    if data.isDead and not wasDead then
        -- Local-only authoritative lifecycle signal. Consumers must not expose
        -- a network event that lets clients spoof this state transition.
        TriggerEvent('cm-playerdata:server:deathStateChanged', src, true, reason or 'death')
    end
    return true
end

-- ============================================================
-- Events
-- ============================================================

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(500)
    local ok = RunMigrations()
    if not ok or not MigrationsReady then
        Log('error', 'CRITICAL: cm-playerdata startup aborted - database migrations failed')
        return
    end
    Log('info', 'CM PlayerData v1.8.5 started')

    -- Restart resilience: if this resource was live-restarted with players
    -- online, rebuild their state from the database instead of leaving them broken.
    for _, playerSrc in ipairs(GetPlayers()) do
        local src = tonumber(playerSrc)
        if src then
            SetTimeout(750, function()
                if GetPlayerName(src) and MigrationsReady then
                    LoadPlayerData(src)
                end
            end)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for src, data in pairs(PlayerData) do
        if data and data.loaded then
            FlushPlayerData(src, 'resource_stop')
        end
    end
end)

AddEventHandler('cm-core:characterLoaded', function(src, charId)
    src = tonumber(src)
    if not src then return end

    charId = tostring(charId or GetCharId(src) or '')
    if charId ~= '' then
        local ok, state = pcall(function() return Player(src).state end)
        if ok and state then
            state:set('charId', charId, true)
            state:set('characterId', charId, true)
            state:set('rpId', charId, true)
        end
    end

    SetTimeout(500, function()
        LoadPlayerData(src, charId)
    end)
end)

RegisterNetEvent('cm-playerdata:server:load', function()
    local src = source
    if PlayerData[src] and PlayerData[src].loaded then
        -- Already loaded for this source: re-sync safe client state
        NotifyLoaded(src)
        return
    end

    local charId = GetCharId(src)
    if not charId then
        Log('warn', 'Rejected unauthenticated cm-playerdata:server:load (missing charId)', { src = src })
        return
    end

    local valid, err = ValidateCharacterOwnership(src, charId)
    if not valid then
        Log('warn', 'Security violation: unowned character load blocked via net event', { src = src, charId = charId, reason = tostring(err) })
        Audit(src, 'security_blocked_load', { charId = charId, reason = tostring(err) })
        return
    end

    LoadPlayerData(src, charId)
end)

-- Clean server-side handoff event for cm-characters/cm-spawn.
-- charId may be passed by a trusted server event, or already set in the player's state bag.
AddEventHandler('cm-playerdata:server:loadCharacter', function(src, charId)
    src = tonumber(src)
    if not src then return end
    charId = tostring(charId or '')
    if charId ~= '' then
        pcall(function()
            local state = Player(src).state
            state:set('charId', charId, true)
            state:set('characterId', charId, true)
            state:set('rpId', charId, true)
        end)
    end
    LoadPlayerData(src, charId)
end)

-- Compatibility event names used by some CM resources.
AddEventHandler('cm-characters:server:characterSelected', function(src, charId)
    TriggerEvent('cm-playerdata:server:loadCharacter', src, charId)
end)

-- Mark this event name net-safe because cm-spawn clients trigger it to the
-- cm-spawn resource. Do not trust it inside playerdata; the authoritative
-- internal completion event is cm-spawn:server:spawned below.
RegisterNetEvent('cm-spawn:server:spawnComplete', function()
    -- no-op on purpose
end)

AddEventHandler('cm-spawn:server:spawned', function(src, charId)
    src = tonumber(src) or source
    if src and not (PlayerData[src] and PlayerData[src].loaded) then
        if charId then
            pcall(function()
                local state = Player(src).state
                state:set('charId', tostring(charId), true)
                state:set('characterId', tostring(charId), true)
                state:set('rpId', tostring(charId), true)
            end)
        end
        LoadPlayerData(src, charId)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local data = PlayerData[src]
    if data and data.charId then
        SupplyWarDeathContexts[tostring(data.charId)] = nil
        data.switching = true
        FlushPlayerData(src, 'drop')
    end
    ClearPlayerData(src)
    PendingHandshakes[src] = nil
    PendingTreatments[src] = nil
    PendingTreatmentOffers[src] = nil
    for target, offer in pairs(PendingTreatmentOffers) do
        if offer.from == src then PendingTreatmentOffers[target] = nil end
    end
    -- Server IDs are recycled: tell every client to forget this identity so a
    -- future player reusing the ID never inherits the old name/character ID.
    TriggerClientEvent('cm-playerdata:client:identityRemove', -1, src)
end)

RegisterNetEvent('cm-playerdata:server:updatePosition', function(coords)
    local src = source
    if not RateLimit(src, 'position', 1000) then return end
    local data = PlayerData[src]
    if not CanMutate(data) or data.isDead == true then return end

    -- Routing bucket check: ignore updates while in isolated dimensions (e.g. selector bucket)
    local bucket = GetPlayerRoutingBucket(src)
    if bucket ~= 0 then return end

    -- Never save position during character selector, scene preview, or spawn transitions
    local ok, state = pcall(function() return Player(src).state end)
    if ok and state and (state.skipPositionSave == true or state.isInCharacterSelector == true or (state.selectorBucket and state.selectorBucket ~= 0)) then
        return
    end

    -- Server-authoritative ped coordinates:
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local pedCoords = GetEntityCoords(ped)
    local pedHeading = GetEntityHeading(ped) or 0.0

    -- Sanity check: valid world coords (not 0,0,0 unspawned ped)
    if math.abs(pedCoords.x) < 0.1 and math.abs(pedCoords.y) < 0.1 and math.abs(pedCoords.z) < 0.1 then
        return
    end
    if math.abs(pedCoords.x) > 10000 or math.abs(pedCoords.y) > 10000 or pedCoords.z < -500 or pedCoords.z > 2000 then
        return
    end

    local serverCoords = NormalizeCoords({
        x = pedCoords.x,
        y = pedCoords.y,
        z = pedCoords.z,
        h = pedHeading
    })
    if not serverCoords then return end

    -- Movement sanity logging based on server-observed coordinates
    local logCfg = Config.Logging or {}
    if logCfg.LogMovementAnomalies ~= false and data.lastPosSample and not data.isDead then
        local now = os.clock()
        local dt = now - (data.lastPosSampleTime or now)
        if dt > 0.5 then
            local dx = serverCoords.x - data.lastPosSample.x
            local dy = serverCoords.y - data.lastPosSample.y
            local dz = serverCoords.z - data.lastPosSample.z
            local dist2d = math.sqrt(dx * dx + dy * dy)
            local speed = dist2d / dt

            local inVehicle = false
            local vehOk, veh = pcall(GetVehiclePedIsIn, ped, false)
            inVehicle = vehOk and veh ~= 0

            local falling = dz <= (logCfg.FallZDelta or -9.0)

            if dist2d >= (logCfg.TeleportDistance or 300.0) then
                Audit(src, 'movement_teleport', {
                    from = data.lastPosSample, to = serverCoords,
                    distance = math.floor(dist2d), seconds = math.floor(dt * 10) / 10
                })
            elseif not inVehicle and not falling and speed > (logCfg.MaxOnFootSpeed or 11.0) then
                Audit(src, 'movement_speed_anomaly', {
                    speed_ms = math.floor(speed * 10) / 10,
                    distance = math.floor(dist2d * 10) / 10,
                    seconds = math.floor(dt * 10) / 10,
                    at = serverCoords
                })
            end
        end
    end

    data.lastPosSample = { x = serverCoords.x, y = serverCoords.y, z = serverCoords.z }
    data.lastPosSampleTime = os.clock()

    local prevPos = data.lastPosition
    data.lastPosition = serverCoords

    if not prevPos or math.abs(serverCoords.x - prevPos.x) > 0.5 or math.abs(serverCoords.y - prevPos.y) > 0.5 then
        MarkDirty(data)
    end
end)

RegisterNetEvent('cm-playerdata:server:syncVitals', function(clientHealth, clientArmor)
    local src = source
    if not RateLimit(src, 'vitals', 1000) then return end
    local data = PlayerData[src]
    if not CanMutate(data) or data.isDead then return end

    local previousHealth = tonumber(data.health) or Config.Vitals.MaxHealth
    local previousArmor = tonumber(data.armor) or 0

    local ped = GetPlayerPed(src)
    local serverHealth = GetServerPedHealth(src)
    local serverArmor = nil
    if ped and ped ~= 0 then
        local ok, arm = pcall(GetPedArmour, ped)
        if ok and arm then serverArmor = Clamp(arm, 0, Config.Vitals.MaxArmor) end
    end

    local nextHealth = Clamp(clientHealth or previousHealth, 0, Config.Vitals.MaxHealth)
    local nextArmor = Clamp(clientArmor or previousArmor, 0, Config.Vitals.MaxArmor)

    -- HEALTH RULES:
    -- Never trust client healing jumps. Healing/revive must come from server exports.
    local maxPassiveHeal = math.max(0, tonumber(Config.Vitals.MaxPassiveHealDelta) or 0)
    if nextHealth > previousHealth + maxPassiveHeal then
        nextHealth = previousHealth
    end

    -- Prefer server-observed ped health when available and lower than client reported
    if serverHealth and serverHealth < nextHealth then
        nextHealth = Clamp(serverHealth, 0, Config.Vitals.MaxHealth)
    end

    -- Revive guard window: skip stale downward sync readings right after revive/heal
    if data.vitalsGuardUntil and GetGameTimer() < data.vitalsGuardUntil and nextHealth < previousHealth then
        nextHealth = previousHealth
    end

    -- ARMOR RULES:
    -- Server authority: Client sync may ONLY report armor damage/decrease.
    -- Armor INCREASE can only occur through server SetArmor/items/admin logic.
    if nextArmor > previousArmor then
        nextArmor = previousArmor
    end

    -- Prefer server-observed ped armor if lower
    if serverArmor and serverArmor < nextArmor then
        nextArmor = serverArmor
    end

    -- Armor guard window: skip stale downward sync readings right after SetArmor
    if data.armorGuardUntil and GetGameTimer() < data.armorGuardUntil and nextArmor < previousArmor then
        nextArmor = previousArmor
    end

    if nextHealth ~= data.health or nextArmor ~= data.armor then
        data.health = nextHealth
        data.armor = nextArmor
        MarkDirty(data)
        data.lastVitalsSync = GetGameTimer()

        SetState(src, 'health', data.health)
        SetState(src, 'armor', data.armor)
    end
end)

-- Weapon hash -> readable name for death logs. Built once at startup.
local WeaponNames = {}
do
    local names = {
        'WEAPON_UNARMED','WEAPON_KNIFE','WEAPON_NIGHTSTICK','WEAPON_HAMMER','WEAPON_BAT','WEAPON_CROWBAR',
        'WEAPON_GOLFCLUB','WEAPON_BOTTLE','WEAPON_DAGGER','WEAPON_HATCHET','WEAPON_MACHETE','WEAPON_SWITCHBLADE',
        'WEAPON_PISTOL','WEAPON_PISTOL_MK2','WEAPON_COMBATPISTOL','WEAPON_APPISTOL','WEAPON_PISTOL50',
        'WEAPON_SNSPISTOL','WEAPON_HEAVYPISTOL','WEAPON_VINTAGEPISTOL','WEAPON_REVOLVER','WEAPON_CERAMICPISTOL',
        'WEAPON_MICROSMG','WEAPON_SMG','WEAPON_SMG_MK2','WEAPON_ASSAULTSMG','WEAPON_MINISMG','WEAPON_MACHINEPISTOL',
        'WEAPON_PUMPSHOTGUN','WEAPON_SAWNOFFSHOTGUN','WEAPON_ASSAULTSHOTGUN','WEAPON_BULLPUPSHOTGUN',
        'WEAPON_HEAVYSHOTGUN','WEAPON_DBSHOTGUN','WEAPON_AUTOSHOTGUN','WEAPON_COMBATSHOTGUN',
        'WEAPON_ASSAULTRIFLE','WEAPON_ASSAULTRIFLE_MK2','WEAPON_CARBINERIFLE','WEAPON_CARBINERIFLE_MK2',
        'WEAPON_ADVANCEDRIFLE','WEAPON_SPECIALCARBINE','WEAPON_BULLPUPRIFLE','WEAPON_COMPACTRIFLE','WEAPON_MILITARYRIFLE',
        'WEAPON_MG','WEAPON_COMBATMG','WEAPON_GUSENBERG',
        'WEAPON_SNIPERRIFLE','WEAPON_HEAVYSNIPER','WEAPON_HEAVYSNIPER_MK2','WEAPON_MARKSMANRIFLE',
        'WEAPON_RPG','WEAPON_GRENADELAUNCHER','WEAPON_MINIGUN','WEAPON_GRENADE','WEAPON_STICKYBOMB','WEAPON_MOLOTOV',
        'WEAPON_STUNGUN','WEAPON_FLARE','WEAPON_PETROLCAN','WEAPON_FIREEXTINGUISHER',
        'WEAPON_FALL','WEAPON_DROWNING','WEAPON_DROWNING_IN_VEHICLE','WEAPON_EXPLOSION','WEAPON_FIRE',
        'WEAPON_BLEEDING','WEAPON_ELECTRIC_FENCE','WEAPON_EXHAUSTION','WEAPON_HIT_BY_WATER_CANNON',
        'WEAPON_RAMMED_BY_CAR','WEAPON_RUN_OVER_BY_CAR','WEAPON_HELI_CRASH','WEAPON_ANIMAL','WEAPON_COUGAR'
    }
    for _, name in ipairs(names) do
        WeaponNames[GetHashKey(name)] = name
    end
end

local function ResolveWeaponName(hash)
    hash = tonumber(hash)
    if not hash then return 'unknown' end
    return WeaponNames[hash] or ('hash_%s'):format(hash)
end

-- Who killed you, from the victim's point of view: real name only if the victim
-- already knows the killer (handshake/org/family/ID). Otherwise Stranger + char ID.
local function GetKilledByInfo(victimSrc, killerSrc)
    killerSrc = tonumber(killerSrc)
    if not killerSrc then return nil end

    local victimData = PlayerData[victimSrc]
    local killerData = PlayerData[killerSrc]
    if not victimData or not killerData or not killerData.charId then return nil end

    local stranger = (Config.Interactions and Config.Interactions.StrangerName) or 'Stranger'
    local label = stranger

    local privacyMode = not (Config.Interactions and Config.Interactions.PrivacyMode == false)
    if not privacyMode then
        label = ('%s %s'):format(killerData.firstName or '', killerData.lastName or '')
    else
        if IsKnownByMemory(victimData, killerData) then
            label = ('%s %s'):format(killerData.firstName or '', killerData.lastName or '')
        end
    end

    return { label = label, charId = tonumber(killerData.charId) }
end

-- Bleed-out: when the deadline passes and the player is still dead, they respawn
-- at the hospital automatically. Calling an ambulance pushes the deadline back.
ScheduleBleedOut = function(src)
    local data = PlayerData[src]
    if not data or not data.deathDeadline then return end

    local remaining = data.deathDeadline - GetGameTimer()
    if remaining < 0 then remaining = 0 end

    SetTimeout(remaining + 100, function()
        local current = PlayerData[src]
        if not current or not current.isDead then return end
        if not current.deathDeadline then return end
        -- An ambulance call may have moved the deadline; only respawn if passed.
        if GetGameTimer() >= current.deathDeadline then
            current.deathDeadline = nil
            exports['cm-playerdata']:Respawn(src)
        end
    end)
end

RegisterNetEvent('cm-playerdata:server:playerDied', function(killerSrc, weaponHash, killerType)
    local src = source
    if not RateLimit(src, 'death', 1000) then return end

    local data = PlayerData[src]
    if not CanMutate(data) or data.isDead then return end

    local serverHealth = GetServerPedHealth(src)
    local reportedHealth = tonumber(data.health) or Config.Vitals.MaxHealth

    -- Server-side sanity check. This is not a full anticheat, but blocks easy fake death events.
    if serverHealth and serverHealth > Config.Vitals.DamageThreshold and reportedHealth > Config.Vitals.DamageThreshold then
        Log('warn', 'Rejected suspicious death event', { src = src, serverHealth = serverHealth, storedHealth = reportedHealth })
        return
    end

    -- Validate the client-reported killer against server state; never trust it blindly.
    local killerRecord = nil
    killerSrc = tonumber(killerSrc)
    if killerSrc and killerSrc > 0 and killerSrc ~= src and GetPlayerName(killerSrc) then
        local dist = nil
        local myPed = GetPlayerPed(src)
        local killerPed = GetPlayerPed(killerSrc)
        if myPed ~= 0 and killerPed ~= 0 then
            local ok, d = pcall(function()
                return #(GetEntityCoords(myPed) - GetEntityCoords(killerPed))
            end)
            if ok then dist = d end
        end
        killerRecord = {
            character_id = GetCharId(killerSrc),
            distance = dist and math.floor(dist * 10) / 10 or nil,
            plausible = dist ~= nil and dist <= 400.0 -- beyond sniper range = flagged, still logged
        }
    end

    SetDead(src, true, 'death')

    -- Local-only authoritative integration seam. Consumers must still enforce
    -- their own instance/participant rules; no client can trigger this event.
    TriggerEvent('cm-playerdata:server:deathDetail', src, {
        victimCharacterId = data.charId,
        killerSource = killerRecord and killerSrc or nil,
        killerCharacterId = killerRecord and killerRecord.character_id or nil,
        killerPlausible = killerRecord and killerRecord.plausible == true or false,
        weapon = ResolveWeaponName(weaponHash),
        weaponHash = tonumber(weaponHash),
        killerType = tostring(killerType or 'unknown'),
    })

    -- Bleed-out clock: base window, extendable once by calling an ambulance.
    local bleedMs = (Config.Respawn and Config.Respawn.BleedOutTime) or 120000
    data.deathDeadline = GetGameTimer() + bleedMs
    data.deathDeadlineAt = NowMs() + bleedMs
    data.ambulanceCalled = false
    data.emsProtection = nil
    data.dieChosen = false
    ScheduleBleedOut(src)
    SavePlayerData(src, 'death_deadline')

    local killedBy = GetKilledByInfo(src, killerSrc)

    if (Config.Logging and Config.Logging.LogDeaths) ~= false then
        local pos = data.lastPosition or {}
        Audit(src, 'death_detail', {
            killer = killerRecord,
            killer_type = tostring(killerType or 'unknown'),
            weapon = ResolveWeaponName(weaponHash),
            coords = { x = pos.x, y = pos.y, z = pos.z },
            death_count = data.deathCount
        })
        if killerRecord and killerRecord.character_id then
            Audit(killerSrc, 'kill_detail', {
                victim_character_id = GetCharId(src),
                weapon = ResolveWeaponName(weaponHash),
                distance = killerRecord.distance
            })
        end
    end

    -- GTA5-style wanted stars: gained here, deliberately OUTSIDE the
    -- Config.Logging.LogDeaths gate above -- disabling death audit logging
    -- shouldn't silently disable the wanted system too. killerRecord is
    -- only ever populated for a real, currently-connected killing player
    -- (see validation above), so this can never fire for an NPC/suicide/
    -- environmental death.
    if killerRecord and killerRecord.character_id and PlayerData[killerSrc] then
        if Player(killerSrc).state.cm_masked ~= true then
            SetWantedStars(killerSrc, (PlayerData[killerSrc].wantedStars or 0) + 1)
        end
    end
    -- Dying clears your OWN wanted level -- matches vanilla GTA5's "wasted" reset.
    if data.wantedStars and data.wantedStars > 0 then
        SetWantedStars(src, 0)
    end

    TriggerClientEvent('cm-playerdata:client:playerDied', src, killerSrc, weaponHash, killedBy, bleedMs)
end)

local function RequestAmbulance(src, reason, metadata)
    src = tonumber(src)
    if not src then return false, 'invalid_source' end
    if not RateLimit(src, 'ambulance', 2000) then return false, 'rate_limited' end

    local data = PlayerData[src]
    if not CanMutate(data) or not data.isDead or not data.deathDeadline then return false, 'not_dead' end
    if data.ambulanceCalled then return false, 'already_called' end

    data.ambulanceCalled = true
    local extra = (Config.Respawn and Config.Respawn.AmbulanceExtraTime) or 120000
    data.deathDeadline = data.deathDeadline + extra
    data.deathDeadlineAt = (data.deathDeadlineAt or NowMs()) + extra
    MarkDirty(data)
    ScheduleBleedOut(src)
    SavePlayerData(src, 'ambulance_called')

    local payload = metadata or {}
    payload.extra_ms = extra
    payload.reason = reason or 'player_called'
    Audit(src, 'ambulance_called', payload)

    -- Bridge for the future EMS/doctor resource: dispatch, blips, job notifications.
    TriggerEvent('cm-playerdata:server:ambulanceCalled', src, data.lastPosition)
    TriggerEvent('cm-playerdata:server:ambulanceRequested', src, {
        characterId = data.charId,
        name = BuildDisplayName(data.firstName, data.lastName),
        coords = data.lastPosition,
        remainingMs = math.max(0, data.deathDeadline - GetGameTimer()),
        reason = reason or 'player_called',
        metadata = metadata or {}
    })

    local remaining = data.deathDeadline - GetGameTimer()
    TriggerClientEvent('cm-playerdata:client:ambulanceConfirmed', src, remaining)
    return true, remaining
end

-- Trusted server-resource contract used by an assigned medical responder.
-- It never shortens the bleed-out clock: it only guarantees enough time for
-- the promised ETA plus treatment, then keeps the client's timers in sync.
local function ProtectDeathTimer(src, minimumRemainingMs, etaMs, label, token)
    src = tonumber(src)
    minimumRemainingMs = math.max(0, math.floor(tonumber(minimumRemainingMs) or 0))
    etaMs = math.max(0, math.floor(tonumber(etaMs) or 0))
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) or not data.isDead or not data.deathDeadline then
        return false, 'not_dead'
    end

    local nowGame, nowReal = GetGameTimer(), NowMs()
    local currentRemaining = math.max(0, data.deathDeadline - nowGame)
    if currentRemaining < minimumRemainingMs then
        data.deathDeadline = nowGame + minimumRemainingMs
        data.deathDeadlineAt = nowReal + minimumRemainingMs
        MarkDirty(data)
        ScheduleBleedOut(src)
        SavePlayerData(src, 'ems_timer_protected')
        currentRemaining = minimumRemainingMs
    end

    data.emsProtection = {
        token = tostring(token or 'medical_response'),
        label = tostring(label or 'AI EMS RESPONDING'),
        etaDeadline = nowGame + etaMs,
    }
    ApplyState(src)
    TriggerClientEvent('cm-playerdata:client:emsProtectionUpdated', src, {
        remainingMs = currentRemaining,
        etaMs = etaMs,
        label = data.emsProtection.label,
        protected = true,
    })
    return true, currentRemaining
end

local function ReleaseDeathTimerProtection(src, token, label)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) or not data.emsProtection then return false end
    if token and tostring(token) ~= tostring(data.emsProtection.token) then return false end
    data.emsProtection = nil
    ApplyState(src)
    if data.isDead and data.deathDeadline then
        TriggerClientEvent('cm-playerdata:client:emsProtectionUpdated', src, {
            remainingMs = math.max(0, data.deathDeadline - GetGameTimer()),
            etaMs = 0,
            label = tostring(label or 'EMS CALLED'),
            protected = false,
        })
    end
    return true
end

-- Local server contract for medical resources. Always emitted on death
-- resolution (not gated on data.ambulanceCalled, which only tracks the
-- death-screen "Call Ambulance" button) so a call placed through another
-- path — e.g. cm-ems's own /ambulance command — still gets cleaned up here.
-- The receiving side (cm-ems) already no-ops when it has no active call for
-- this character, so this is safe to fire unconditionally.
local function ResolveAmbulanceRequest(src, data, reason)
    if not data then return end
    data.emsProtection = nil
    TriggerEvent('cm-playerdata:server:ambulanceResolved', tonumber(src), {
        characterId = data.charId,
        reason = tostring(reason or 'revived')
    })
end

RegisterNetEvent('cm-playerdata:server:callAmbulance', function()
    RequestAmbulance(source, 'player_called')
end)

RegisterNetEvent('cm-playerdata:server:chooseDie', function()
    local src = source
    if not RateLimit(src, 'choose_die', 2000) then return end

    local data = PlayerData[src]
    if not CanMutate(data) or not data.isDead then return end

    -- Per design: no time change, the death screen stays until bleed-out ends.
    data.dieChosen = true
    MarkDirty(data)
    SavePlayerData(src, 'death_give_up')
    Audit(src, 'death_give_up', {})
end)

RegisterNetEvent('cm-playerdata:server:requestRespawn', function()
    local src = source
    if not RateLimit(src, 'respawn', 2000) then return end
    local data = PlayerData[src]
    if not CanMutate(data) or not data.isDead then return end

    -- Client can request respawn when its UI reaches 00:00, but the server
    -- remains authoritative. Ignore early client-triggered respawn attempts.
    if data.deathDeadline and GetGameTimer() + 1000 < data.deathDeadline then
        return
    end

    exports['cm-playerdata']:Respawn(src)
end)

-- The unconscious body was finished off (extra damage drained the finishing
-- buffer). Straight to hospital respawn, no bleed-out wait.
RegisterNetEvent('cm-playerdata:server:finishedOff', function()
    local src = source
    if not RateLimit(src, 'finished_off', 1000) then return end
    local data = PlayerData[src]
    if not CanMutate(data) or not data.isDead then return end

    data.deathDeadline = nil
    data.deathDeadlineAt = nil
    Audit(src, 'finished_off', {})
    exports['cm-playerdata']:Respawn(src)
end)



-- ============================================================
-- Player Identity + Interaction Events
-- ============================================================

local function GetPlayerDistance(src, targetSrc)
    src = tonumber(src)
    targetSrc = tonumber(targetSrc)
    if not src or not targetSrc then return nil end

    local ped = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if not ped or ped == 0 or not targetPed or targetPed == 0 then return nil end

    local coords = GetEntityCoords(ped)
    local targetCoords = GetEntityCoords(targetPed)
    if not coords or not targetCoords then return nil end

    return #(coords - targetCoords)
end

local function IsServerPlayerInVehicle(src)
    src = tonumber(src)
    if not src then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local inVehicle = false
    pcall(function()
        if type(IsPedInAnyVehicle) == 'function' then
            inVehicle = IsPedInAnyVehicle(ped, false) == true
        elseif type(GetVehiclePedIsIn) == 'function' then
            local veh = GetVehiclePedIsIn(ped, false)
            inVehicle = veh ~= nil and veh ~= 0
        end
    end)

    return inVehicle == true
end


local function NotifyPlayer(src, message, msgType)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', src, message, msgType or 'inform')
end

local function GetFullName(data)
    if not data then return 'Unknown' end
    return BuildDisplayName(data.firstName or data.first_name, data.lastName or data.last_name)
end

local function CleanTag(value)
    if value == nil then return nil end
    value = tostring(value)
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    local lower = value:lower()
    if lower == 'none' or lower == 'nil' or lower == 'false' or lower == '0' or lower == 'unemployed' then
        return nil
    end
    return lower
end

local function GetNestedValue(root, path)
    if type(root) ~= 'table' then return nil end
    local current = root
    for part in tostring(path):gmatch('[^%.]+') do
        if type(current) ~= 'table' then return nil end
        current = current[part]
        if current == nil then return nil end
    end
    return current
end

local function GetStateValue(src, keys)
    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end

    for _, key in ipairs(keys) do
        local value = state[key]
        local tag = CleanTag(value)
        if tag then return tag end
    end

    return nil
end

local function GetMetadataValue(data, keys)
    local metadata = data and data.metadata or {}
    for _, key in ipairs(keys) do
        local value = GetNestedValue(metadata, key)
        if type(value) == 'table' then
            value = value.id or value.name or value.label
        end
        local tag = CleanTag(value)
        if tag then return tag end
    end
    return nil
end

local OrgKeys = {
    'organization_id', 'organizationId', 'organization', 'org_id', 'orgId', 'org',
    'faction_id', 'factionId', 'faction', 'business_id', 'businessId', 'business'
}

local FamilyKeys = {
    'family_id', 'familyId', 'family', 'family.name', 'family.id'
}

local function GetOrgTag(src, data)
    return GetMetadataValue(data, OrgKeys) or GetStateValue(src, OrgKeys)
end

local function GetFamilyTag(src, data)
    return GetMetadataValue(data, FamilyKeys) or GetStateValue(src, FamilyKeys)
end

local function GetGangTag(src)
    local ok, state = pcall(function() return Player(tonumber(src)).state end)
    local gang = ok and state and state.cmGang or nil
    return type(gang) == 'table' and CleanTag(gang.gangId) or nil
end

local function WarmIdentityCache(charId)
    charId = tonumber(charId)
    if not charId then return false, 'invalid_char_id' end

    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT known_character_id FROM cm_known_identities WHERE owner_character_id = ?', { charId })
    end)
    if not ok or type(rows) ~= 'table' then
        Log('warn', 'Failed to warm identity cache from database', { charId = charId, error = tostring(rows) })
        return false, 'query_failed'
    end

    local cache = {}
    for _, row in ipairs(rows) do
        local targetId = tonumber(row.known_character_id)
        if targetId then
            cache[targetId] = true
        end
    end
    KnownIdentityCache[charId] = cache
    return true, nil
end

local function ClearIdentityCache(charId)
    charId = tonumber(charId)
    if charId then
        KnownIdentityCache[charId] = nil
    end
end

local function PersistKnownIdentityRelation(ownerCharId, knownCharId, reason)
    ownerCharId = tonumber(ownerCharId)
    knownCharId = tonumber(knownCharId)
    if not ownerCharId or not knownCharId or ownerCharId == knownCharId then
        return false, 'invalid_ids'
    end

    local ok, err = pcall(function()
        return MySQL.query.await([[
            INSERT INTO cm_known_identities (owner_character_id, known_character_id, reason)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE reason = VALUES(reason)
        ]], { ownerCharId, knownCharId, tostring(reason or 'met'):sub(1, 32) })
    end)

    if not ok then
        Log('error', 'Failed to persist known identity relation', {
            owner = ownerCharId, known = knownCharId, error = tostring(err)
        })
        return false, 'database_error'
    end

    if not KnownIdentityCache[ownerCharId] then
        KnownIdentityCache[ownerCharId] = {}
    end
    KnownIdentityCache[ownerCharId][knownCharId] = true

    return true, nil
end

local function PersistMutualIdentityRelation(charA, charB, reason)
    charA = tonumber(charA)
    charB = tonumber(charB)
    if not charA or not charB or charA == charB then
        return false, 'invalid_character_ids'
    end

    local cleanReason = tostring(reason or 'handshake'):sub(1, 32)
    local ok, err = pcall(function()
        return MySQL.query.await([[
            INSERT INTO cm_known_identities (owner_character_id, known_character_id, reason)
            VALUES (?, ?, ?), (?, ?, ?)
            ON DUPLICATE KEY UPDATE reason = VALUES(reason)
        ]], { charA, charB, cleanReason, charB, charA, cleanReason })
    end)

    if not ok then
        Log('error', 'Failed to persist mutual identity relation', {
            charA = charA, charB = charB, error = tostring(err)
        })
        return false, 'database_error'
    end

    if not KnownIdentityCache[charA] then KnownIdentityCache[charA] = {} end
    if not KnownIdentityCache[charB] then KnownIdentityCache[charB] = {} end
    KnownIdentityCache[charA][charB] = true
    KnownIdentityCache[charB][charA] = true

    return true, nil
end

local function IsKnownByMemory(viewerData, targetData)
    if not viewerData or not targetData then return false end
    local viewerCharId = tonumber(viewerData.charId)
    local targetCharId = tonumber(targetData.charId)
    if not viewerCharId or not targetCharId then return false end

    local cache = KnownIdentityCache[viewerCharId]
    if cache and cache[targetCharId] == true then
        return true
    end
    return false
end

local function MarkIdentityKnown(viewerSrc, targetSrc, reason)
    viewerSrc = tonumber(viewerSrc)
    targetSrc = tonumber(targetSrc)
    if not viewerSrc or not targetSrc then return false, 'invalid_sources' end

    local viewerData = PlayerData[viewerSrc]
    local targetData = PlayerData[targetSrc]
    if not CanMutate(viewerData) or not targetData then
        return false, 'invalid_state'
    end

    local ownerCharId = tonumber(viewerData.charId)
    local knownCharId = tonumber(targetData.charId)
    if not ownerCharId or not knownCharId then return false, 'missing_char_id' end

    local success, err = PersistKnownIdentityRelation(ownerCharId, knownCharId, reason)
    if not success then
        return false, err
    end

    return true, nil
end

local function BuildIdentityForViewer(viewerSrc, targetSrc)
    viewerSrc = tonumber(viewerSrc)
    targetSrc = tonumber(targetSrc)

    local targetData = PlayerData[targetSrc]
    local viewerData = PlayerData[viewerSrc]
    local stranger = (Config.Interactions and Config.Interactions.StrangerName) or 'Stranger'

    if not targetData then
        return {
            id = targetSrc or 0,       -- internal cache key only
            serverId = targetSrc or 0, -- internal event target only, never shown in UI
            displayName = stranger,
            known = false,
            reason = 'not_loaded',
            identityId = nil,
            characterId = nil
        }
    end

    local privacyMode = not (Config.Interactions and Config.Interactions.PrivacyMode == false)
    local known = false
    local reason = 'stranger'

    if not privacyMode then
        known = true
        reason = 'privacy_disabled'
    elseif viewerSrc == targetSrc and (Config.Interactions and Config.Interactions.ShowRealNameToSelf ~= false) then
        known = true
        reason = 'self'
    elseif viewerData and targetData then
        local viewerGang = GetGangTag(viewerSrc)
        local targetGang = GetGangTag(targetSrc)
        if viewerGang and targetGang and viewerGang == targetGang then
            known = true
            reason = 'same_gang'
        end

        local viewerOrg = GetOrgTag(viewerSrc, viewerData)
        local targetOrg = GetOrgTag(targetSrc, targetData)
        if not known and viewerOrg and targetOrg and viewerOrg == targetOrg then
            known = true
            reason = 'same_org'
        end

        local viewerFamily = GetFamilyTag(viewerSrc, viewerData)
        local targetFamily = GetFamilyTag(targetSrc, targetData)
        if not known and viewerFamily and targetFamily and viewerFamily == targetFamily then
            known = true
            reason = 'same_family'
        end

        if not known and IsKnownByMemory(viewerData, targetData) then
            known = true
            reason = 'known_identity'
        end
    end

    return {
        id = targetSrc,       -- internal cache key only
        serverId = targetSrc, -- internal event target only, never shown in UI
        displayName = known and GetFullName(targetData) or stranger,
        known = known,
        reason = reason,
        identityId = tonumber(targetData.charId),
        characterId = tonumber(targetData.charId)
    }
end

local function PushIdentityUpdate(viewerSrc, targetSrc)
    TriggerClientEvent('cm-playerdata:client:identityUpdate', viewerSrc, BuildIdentityForViewer(viewerSrc, targetSrc))
end

AddEventHandler('cm-playerdata:server:affiliationIdentityChanged', function(changedSrc)
    changedSrc = tonumber(changedSrc)
    if not changedSrc or not PlayerData[changedSrc] then return end
    for _, rawViewer in ipairs(GetPlayers()) do
        local viewerSrc = tonumber(rawViewer)
        if viewerSrc and PlayerData[viewerSrc] then
            PushIdentityUpdate(viewerSrc, changedSrc)
            if viewerSrc ~= changedSrc then PushIdentityUpdate(changedSrc, viewerSrc) end
        end
    end
end)

exports('MarkSupplyWarDeathContext',function(src,eventId)
    if GetInvokingResource()~='cm-gang'then return false,'trusted_resource_required'end
    src=tonumber(src);local data=src and PlayerData[src];if not data or not data.charId then return false,'player_not_loaded'end
    return CaptureSupplyWarDeathContext(src,eventId)
end)

exports('HasSupplyWarDeathContext',function(src)
    src=tonumber(src);local data=src and PlayerData[src];local characterId=data and tostring(data.charId or'')or'';local context=characterId~=''and SupplyWarDeathContexts[characterId]or nil
    if not context or context.source~=src or context.expiresAt<=os.time()then if characterId~=''then SupplyWarDeathContexts[characterId]=nil end;return false end
    return true
end)

local function ValidatePlayerInteraction(src, targetSrc, rateKey, rateMs, allowVehicleTarget)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc <= 0 or src == targetSrc then
        return false, nil, 'Invalid target.'
    end

    if not RateLimit(src, rateKey or 'player_interaction', tonumber(rateMs) or 750) then
        return false, targetSrc, 'Please slow down.'
    end

    if not CanMutate(PlayerData[src]) then
        return false, targetSrc, 'Your player data is not available.'
    end

    if PlayerData[src].isDead then
        return false, targetSrc, 'You cannot do this while unconscious.'
    end

    if not GetPlayerName(targetSrc) then
        return false, targetSrc, 'Target player is no longer online.'
    end

    if not CanMutate(PlayerData[targetSrc]) then
        return false, targetSrc, 'Target player data is not available.'
    end

    local dist = GetPlayerDistance(src, targetSrc)
    local maxDistance = (Config.Interactions and Config.Interactions.ServerMaxDistance) or 5.0
    if not dist or dist > maxDistance then
        return false, targetSrc, 'Target player is too far away.'
    end

    if not allowVehicleTarget and Config.Interactions and Config.Interactions.BlockInteractionWhenTargetInVehicle ~= false and IsServerPlayerInVehicle(targetSrc) then
        return false, targetSrc, 'Use the vehicle interaction menu for players inside vehicles.'
    end

    return true, targetSrc, nil
end

local function GetPublicCharacterId(src)
    local data = PlayerData[tonumber(src)]
    return data and tonumber(data.charId) or nil
end

local function GetPublicPlayerLabel(src)
    local charId = GetPublicCharacterId(src)
    if charId then
        return ('Character ID %s'):format(charId)
    end
    return 'Character ID Loading'
end


local function SanitizeExtensionPayload(payload)
    if type(payload) ~= 'table' then return {} end
    local cleaned = {}
    local count = 0

    for key, value in pairs(payload) do
        if count >= 20 then break end
        if type(key) == 'string' and #key <= 48 then
            local vt = type(value)
            if vt == 'string' then
                cleaned[key] = value:sub(1, 160)
                count = count + 1
            elseif vt == 'number' or vt == 'boolean' then
                cleaned[key] = value
                count = count + 1
            end
        end
    end

    return cleaned
end

-- Note: a duplicate `exports('GetCharacterId', ...)` used to also be
-- registered further below (using GetCharId instead of
-- GetPublicCharacterId) -- the second registration silently wins in
-- FiveM's export system, shadowing this one entirely. Removed this one
-- since cm-police and others depend on this exact export name; keeping two
-- divergent definitions around risked one drifting from the other with no
-- warning.

exports('ValidateInteractionTarget', function(src, targetSrc, rateKey, rateMs)
    return ValidatePlayerInteraction(tonumber(src), targetSrc, rateKey or 'export_validate_interaction', rateMs)
end)

RegisterNetEvent('cm-playerdata:server:extensionInteraction', function(targetSrc, action, payload)
    local src = source
    local actionId = NormalizeInteractionActionId(action)
    if not actionId then
        NotifyPlayer(src, 'Invalid interaction action.', 'error')
        return
    end

    local registered = ExtensionInteractionActions[actionId]
    if not registered then
        NotifyPlayer(src, 'That menu action is not connected yet.', 'error')
        return
    end

    local ok, target, errorMessage = ValidatePlayerInteraction(src, targetSrc, 'ext_' .. actionId, 750, registered.allowVehicleTarget)
    if not ok then
        NotifyPlayer(src, errorMessage or 'Interaction failed.', 'error')
        return
    end

    if PlayerData[target].isDead and not registered.allowDeadTarget then
        NotifyPlayer(src, 'That player is unconscious. This action is not available.', 'error')
        return
    end

    if registered.deadOnly and not PlayerData[target].isDead then
        NotifyPlayer(src, 'This action is only available on an unconscious player.', 'error')
        return
    end

    local safePayload = SanitizeExtensionPayload(payload)
    local context = {
        source = src,
        target = target,
        sourceCharacterId = GetPublicCharacterId(src),
        targetCharacterId = GetPublicCharacterId(target),
        distance = GetPlayerDistance(src, target)
    }

    TriggerEvent(registered.event, src, target, actionId, safePayload, context)
    TriggerEvent('cm-playerdata:server:extensionInteractionSelected', src, target, actionId, safePayload, context)
end)

RegisterNetEvent('cm-playerdata:server:requestIdentityBatch', function(ids)
    local src = source
    if not RateLimit(src, 'identity_batch', 900) then return end
    if type(ids) ~= 'table' then return end

    local items = {}
    local used = {}

    for _, rawId in ipairs(ids) do
        local target = tonumber(rawId)
        if target and target > 0 and target ~= src and GetPlayerName(target) and not used[target] then
            used[target] = true
            items[#items + 1] = BuildIdentityForViewer(src, target)
            if #items >= 32 then break end
        end
    end

    if #items > 0 then
        TriggerClientEvent('cm-playerdata:client:identityBatch', src, items)
    end
end)

RegisterNetEvent('cm-playerdata:server:giveCashToPlayer', function(targetSrc, amount)
    local src = source
    local ok, target, errorMessage = ValidatePlayerInteraction(src, targetSrc, 'give_cash')
    if not ok then
        NotifyPlayer(src, errorMessage or 'Cash transfer failed.', 'error')
        return
    end

    amount = math.floor(tonumber(amount) or 0)
    local maxGift = (Config.Interactions and Config.Interactions.MaxCashGift) or 1000
    if amount <= 0 or amount > maxGift then
        NotifyPlayer(src, ('Cash gift must be between $1 and $%s.'):format(maxGift), 'error')
        return
    end

    local success, errCode = TransferMoneyBetweenPlayersAuthoritative(src, target, 'cash', amount, 'player_give_cash', {
        interaction = 'give_cash',
        maxGift = maxGift
    })

    if not success then
        local msg = 'Cash transfer failed.'
        if errCode == 'insufficient_funds' then
            msg = 'You do not have enough cash.'
        elseif errCode == 'money_busy' then
            msg = 'A transaction is already in progress. Please wait.'
        end
        NotifyPlayer(src, msg, 'error')
        return
    end

    NotifyPlayer(src, ('You gave $%s cash to %s.'):format(amount, GetPublicPlayerLabel(target)), 'success')
    NotifyPlayer(target, ('%s gave you $%s cash.'):format(GetPublicPlayerLabel(src), amount), 'success')
end)

local function FindPatchItem(src)
    local medCfg = Config.Medical or {}
    if medCfg.RequireTreatmentItem == false then return true, nil end
    local items = medCfg.TreatmentItems or { 'medikit', 'medkit' }
    for _, itemName in ipairs(items) do
        local hasItem = false
        local ok = pcall(function() hasItem = exports['cm-inventory']:HasItem(src, itemName, 1) == true end)
        if ok and hasItem then return true, tostring(itemName) end
    end
    return false, nil
end

local function BeginPatchTreatment(src, target)
    if PendingTreatments[src] then return false, 'You are already treating someone.' end
    local hasItem, itemName = FindPatchItem(src)
    if not hasItem then return false, 'You need a medikit to patch or treat a player.' end
    local duration = (Config.Medical and Config.Medical.TreatDuration) or 8000
    PendingTreatments[src] = { target = target, startedAt = GetGameTimer(), duration = duration, itemName = itemName }
    NotifyPlayer(src, ('You are patching up %s.'):format(GetPublicPlayerLabel(target)), 'inform')
    NotifyPlayer(target, ('%s is treating you.'):format(GetPublicPlayerLabel(src)), 'inform')
    TriggerClientEvent('cm-playerdata:client:startTreatment', src, duration)
    TriggerClientEvent('cm-playerdata:client:treatmentProgress', target, 'started', duration, GetPublicPlayerLabel(src))
    TriggerEvent('cm-playerdata:server:treatRequested', src, target)
    return true
end

RegisterNetEvent('cm-playerdata:server:playerInteraction', function(targetSrc, action)
    local src = source
    action = tostring(action or 'unknown')

    local ok, target, errorMessage = ValidatePlayerInteraction(src, targetSrc, 'interaction_' .. action)
    if not ok then
        NotifyPlayer(src, errorMessage or 'Interaction failed.', 'error')
        return
    end

    -- Dead targets: only treatment-type actions are allowed on a body.
    local DeadAllowedActions = { treat_player = true }
    if PlayerData[target].isDead and not DeadAllowedActions[action] then
        NotifyPlayer(src, 'That player is unconscious. You can only treat them.', 'error')
        return
    end

    if action == 'treat_player' then
        local medCfg = Config.Medical or {}
        local hasItem = FindPatchItem(src)
        if not hasItem then return NotifyPlayer(src, 'You need a medikit to patch or treat a player.', 'error') end
        if PlayerData[target].isDead then
            local started, reason = BeginPatchTreatment(src, target)
            if not started then NotifyPlayer(src, reason, 'error') end
        else
            local existing = PendingTreatmentOffers[target]
            if existing and GetGameTimer() < existing.expires then
                return NotifyPlayer(src, 'That player already has a treatment request.', 'error')
            end
            local timeout = tonumber(medCfg.TreatmentRequestTimeout) or 15000
            PendingTreatmentOffers[target] = { from = src, expires = GetGameTimer() + timeout }
            NotifyPlayer(src, ('Treatment request sent to %s.'):format(GetPublicPlayerLabel(target)), 'inform')
            TriggerClientEvent('cm-playerdata:client:treatmentRequest', target, GetPublicPlayerLabel(src), timeout)
        end
    elseif action == 'handshake' then
        -- Consent flow: the target must accept before names are exchanged.
        PendingHandshakes[target] = {
            from = src,
            expires = GetGameTimer() + ((Config.Interactions and Config.Interactions.HandshakeTimeout) or 15000)
        }
        NotifyPlayer(src, ('You offered a handshake to %s.'):format(GetPublicPlayerLabel(target)), 'inform')
        TriggerClientEvent('cm-playerdata:client:handshakeRequest', target,
            GetPublicPlayerLabel(src),
            (Config.Interactions and Config.Interactions.HandshakeTimeout) or 15000)
    elseif action == 'share_id' then
        local knownOk, knownErr = MarkIdentityKnown(target, src, 'shared_id')

        if not knownOk then
            Log('error', 'Share ID identity persistence failed', {
                from = src,
                target = target,
                reason = tostring(knownErr)
            })

            NotifyPlayer(src, 'Unable to share your ID right now.', 'error')
            NotifyPlayer(target, 'Unable to save that identity right now.', 'error')
            return
        end

        PushIdentityUpdate(target, src)

        NotifyPlayer(
            src,
            ('You showed your ID to %s.'):format(GetPublicPlayerLabel(target)),
            'success'
        )

        -- Passport-style ID card on the target's screen. DOB/licenses read from
        -- metadata when present (cm-characters can set these later).
        local srcData = PlayerData[src]
        local meta = srcData.metadata or {}
        TriggerClientEvent('cm-playerdata:client:showIdCard', target, {
            name = GetFullName(srcData),
            charId = tonumber(srcData.charId),
            dob = meta.dob or srcData.dob or nil,
            licenses = meta.licenses or nil
        })
    elseif action == 'greet' then
        NotifyPlayer(src, ('You greeted %s.'):format(GetPublicPlayerLabel(target)), 'success')
        NotifyPlayer(target, ('%s greeted you.'):format(GetPublicPlayerLabel(src)), 'inform')
        TriggerClientEvent('cm-playerdata:client:interactionAnim', src, 'greet', target)
    elseif action == 'show_license' then
        NotifyPlayer(src, 'License sharing selected. Connect this to your license/document system when ready.', 'inform')
        NotifyPlayer(target, ('%s wants to show a license.'):format(GetPublicPlayerLabel(src)), 'inform')
    elseif action == 'show_documents' then
        NotifyPlayer(src, 'Document sharing selected. Connect this to your document system when ready.', 'inform')
        NotifyPlayer(target, ('%s wants to show documents.'):format(GetPublicPlayerLabel(src)), 'inform')
    elseif action == 'search_player' then
        NotifyPlayer(src, 'Search action selected. Connect this event to your inventory/police script when ready.', 'inform')
        NotifyPlayer(target, ('%s is trying to search/interact with you.'):format(GetPublicPlayerLabel(src)), 'inform')
        TriggerClientEvent('cm-playerdata:client:interactionAnim', src, 'frisk', target)
    elseif action == 'escort_player' then
        NotifyPlayer(src, 'Escort/carry action selected. Connect this event to your carry/escort script when ready.', 'inform')
        NotifyPlayer(target, ('%s selected escort/carry interaction.'):format(GetPublicPlayerLabel(src)), 'inform')
    elseif action == 'org_invite' or action == 'org_rank' then
        NotifyPlayer(src, 'Organization action selected. Connect this to your organization resource when ready.', 'inform')
    elseif action == 'family_invite' or action == 'family_info' then
        NotifyPlayer(src, 'Family action selected. Connect this to your family resource when ready.', 'inform')
    else
        NotifyPlayer(src, ('Selected %s on %s.'):format(action, GetPublicPlayerLabel(target)), 'inform')
    end

    -- Bridge event for future resources: inventory, police, carry, animations, org/family, documents, etc.
    TriggerEvent('cm-playerdata:server:interactionSelected', src, target, action)
end)

RegisterNetEvent('cm-playerdata:server:treatmentResponse', function(accepted)
    local target = source
    if not RateLimit(target, 'treatment_response', 700) then return end
    local offer = PendingTreatmentOffers[target]
    PendingTreatmentOffers[target] = nil
    if not offer or GetGameTimer() >= offer.expires then return end
    local src = tonumber(offer.from)
    if not src or not GetPlayerName(src) or not CanMutate(PlayerData[src]) or not CanMutate(PlayerData[target]) then return end
    if accepted ~= true then return NotifyPlayer(src, ('%s declined your treatment request.'):format(GetPublicPlayerLabel(target)), 'error') end
    local dist = GetPlayerDistance(src, target)
    local maxDistance = ((Config.Interactions and Config.Interactions.ServerMaxDistance) or 5.0) + 2.0
    if not dist or dist > maxDistance then
        NotifyPlayer(src, 'Treatment failed: the player moved too far away.', 'error')
        return NotifyPlayer(target, 'Treatment failed because you moved too far away.', 'error')
    end
    local started, reason = BeginPatchTreatment(src, target)
    if not started then
        NotifyPlayer(src, reason, 'error')
        NotifyPlayer(target, reason, 'error')
    end
end)

RegisterNetEvent('cm-playerdata:server:treatComplete', function(finished)
    local src = source
    local pending = PendingTreatments[src]
    PendingTreatments[src] = nil
    if not pending then return end

    if finished ~= true then
        NotifyPlayer(src, 'Treatment cancelled.', 'error')
        if GetPlayerName(pending.target) then TriggerClientEvent('cm-playerdata:client:treatmentProgress', pending.target, 'cancelled') end
        return
    end

    -- The progress bar cannot legitimately finish early.
    local elapsed = GetGameTimer() - pending.startedAt
    if elapsed < math.floor(pending.duration * 0.85) then
        Log('warn', 'Rejected suspicious treatComplete (too fast)', { src = src, elapsed = elapsed })
        if GetPlayerName(pending.target) then TriggerClientEvent('cm-playerdata:client:treatmentProgress', pending.target, 'cancelled') end
        return
    end

    local target = pending.target
    local targetData = PlayerData[target]
    if not CanMutate(targetData) or not CanMutate(PlayerData[src]) then
        NotifyPlayer(src, 'They no longer need treatment.', 'error')
        return
    end

    -- Both must still be next to each other.
    local dist = GetPlayerDistance(src, target)
    local maxDistance = ((Config.Interactions and Config.Interactions.ServerMaxDistance) or 5.0) + 2.0
    if not dist or dist > maxDistance then
        NotifyPlayer(src, 'You moved too far away from them.', 'error')
        TriggerClientEvent('cm-playerdata:client:treatmentProgress', target, 'cancelled')
        return
    end

    local medCfg = Config.Medical or {}
    if medCfg.RequireTreatmentItem ~= false then
        local stillHas = false
        pcall(function() stillHas = exports['cm-inventory']:HasItem(src, pending.itemName, 1) == true end)
        if not stillHas then
            TriggerClientEvent('cm-playerdata:client:treatmentProgress', target, 'cancelled')
            return NotifyPlayer(src, 'You no longer have the medikit.', 'error')
        end
        local removed = false
        pcall(function() removed = exports['cm-inventory']:RemoveItem(src, pending.itemName, 1, nil, 'player_patch') == true end)
        if not removed then
            TriggerClientEvent('cm-playerdata:client:treatmentProgress', target, 'cancelled')
            return NotifyPlayer(src, 'The medikit could not be consumed.', 'error')
        end
    end

    -- Street patch: fully revive in place ("back from death"). Set
    -- Medical.PatchFullHeal = false to fall back to the old weak partial revive.
    local fullPatch = medCfg.PatchFullHeal ~= false
    local health = fullPatch and (Config.Vitals.MaxHealth or 200)
        or GetHealthFromPercent(medCfg.StreetPatchHealthPercent or 30)

    local wasDead = targetData.isDead == true
    if wasDead then ResolveAmbulanceRequest(target, targetData, 'treated') end
    targetData.isDead = false
    targetData.health = health
    targetData.armor = 0
    targetData.deathDeadline = nil
    targetData.deathDeadlineAt = nil
    targetData.ambulanceCalled = false
    targetData.dieChosen = false
    targetData.deathReason = nil
    MarkDirty(targetData)

    ApplyState(target)
    SyncInventoryDeathState(target, false)
    SavePlayerData(target, wasDead and 'street_patch' or 'player_treatment')
    if wasDead and fullPatch then
        TriggerClientEvent('cm-playerdata:client:revive', target)
    elseif wasDead then
        TriggerClientEvent('cm-playerdata:client:revivePartial', target, health)
    else
        TriggerClientEvent('cm-playerdata:client:setHealth', target, health)
    end

    NotifyPlayer(src, wasDead and ('You revived %s with a medikit.'):format(GetPublicPlayerLabel(target)) or ('You treated %s.'):format(GetPublicPlayerLabel(target)), 'success')
    NotifyPlayer(target, wasDead and ('%s revived you with a medikit.'):format(GetPublicPlayerLabel(src)) or ('%s treated you.'):format(GetPublicPlayerLabel(src)), 'success')
    TriggerClientEvent('cm-playerdata:client:treatmentProgress', target, 'completed')
    Audit(src, 'treat_success', { target_character_id = GetPublicCharacterId(target), health = health, full = fullPatch, revived = wasDead, item = pending.itemName })
    TriggerEvent('cm-playerdata:server:treatCompleted', src, target, {
        revived = wasDead, item = pending.itemName, targetCharacterId = GetPublicCharacterId(target)
    })
end)

RegisterNetEvent('cm-playerdata:server:handshakeResponse', function(accepted)
    local src = source -- src is the player who RECEIVED the handshake offer
    if not RateLimit(src, 'handshake_response', 1000) then return end

    local pending = PendingHandshakes[src]
    PendingHandshakes[src] = nil
    if not pending then return end

    if GetGameTimer() > pending.expires then
        NotifyPlayer(src, 'That handshake offer has expired.', 'error')
        return
    end

    local from = pending.from
    if not GetPlayerName(from) or not CanMutate(PlayerData[from]) or not CanMutate(PlayerData[src]) then
        NotifyPlayer(src, 'That player is no longer online.', 'error')
        return
    end

    if accepted ~= true then
        NotifyPlayer(from, ('%s declined your handshake.'):format(GetPublicPlayerLabel(src)), 'error')
        return
    end

    -- Re-check distance at accept time: they must still be next to each other.
    local dist = GetPlayerDistance(src, from)
    local maxDistance = ((Config.Interactions and Config.Interactions.ServerMaxDistance) or 5.0) + 2.0
    if not dist or dist > maxDistance then
        NotifyPlayer(src, 'You are too far away to shake hands now.', 'error')
        NotifyPlayer(from, 'Handshake failed: target moved away.', 'error')
        return
    end

    local fromData = PlayerData[from]
    local srcData = PlayerData[src]
    local charFrom = tonumber(fromData.charId)
    local charSrc = tonumber(srcData.charId)

    local okPersist, errPersist = PersistMutualIdentityRelation(charSrc, charFrom, 'handshake')
    if not okPersist then
        Log('error', 'Handshake mutual persistence failed', {
            src = src, from = from, error = tostring(errPersist)
        })
        NotifyPlayer(src, 'Unable to complete handshake at this time.', 'error')
        NotifyPlayer(from, 'Unable to complete handshake at this time.', 'error')
        return
    end

    PushIdentityUpdate(src, from)
    PushIdentityUpdate(from, src)
    NotifyPlayer(src, ('You shook hands with %s. Their name is now visible to you.'):format(GetFullName(fromData)), 'success')
    NotifyPlayer(from, ('You shook hands with %s. Their name is now visible to you.'):format(GetFullName(srcData)), 'success')
    -- Paired handshake emote, each facing the other.
    TriggerClientEvent('cm-playerdata:client:interactionAnim', from, 'handshake', src)
    TriggerClientEvent('cm-playerdata:client:interactionAnim', src, 'handshake_b', from)
    Audit(src, 'handshake_accept', { with_character_id = GetPublicCharacterId(from) })
end)

exports('KnowPlayerIdentity', function(viewerSrc, targetSrc, reason)
    local ok, err = MarkIdentityKnown(viewerSrc, targetSrc, reason or 'export')
    if ok then
        PushIdentityUpdate(viewerSrc, targetSrc)
    end
    return ok == true
end)

exports('KnowPlayerIdentityPersistent', function(viewerSrc, targetSrc, reason)
    local ok, err = MarkIdentityKnown(viewerSrc, targetSrc, reason or 'export')
    if ok then
        PushIdentityUpdate(viewerSrc, targetSrc)
    end
    return ok == true, err
end)

exports('PersistKnownIdentity', function(ownerCharId, knownCharId, reason)
    return PersistKnownIdentityRelation(ownerCharId, knownCharId, reason)
end)

exports('GetKnownIdentities', function(characterId)
    local charId = tonumber(characterId)
    if not charId then return {} end
    local cache = KnownIdentityCache[charId]
    if cache then
        local copy = {}
        for k, v in pairs(cache) do copy[k] = v end
        return copy
    end
    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT known_character_id FROM cm_known_identities WHERE owner_character_id = ?', { charId })
    end)
    local result = {}
    if ok and type(rows) == 'table' then
        for _, r in ipairs(rows) do
            local id = tonumber(r.known_character_id)
            if id then result[id] = true end
        end
    end
    return result
end)

exports('GetKnownIdentitiesForSource', function(src)
    src = tonumber(src)
    local data = src and PlayerData[src]
    local charId = data and tonumber(data.charId)
    if not charId then return {} end
    return exports['cm-playerdata']:GetKnownIdentities(charId)
end)

exports('SetOrganization', function(src, orgId, orgName)
    local data = PlayerData[src]
    if not CanMutate(data) then return false end
    data.metadata = data.metadata or {}
    data.metadata.organization_id = orgId
    data.metadata.organization = orgName or orgId
    MarkDirty(data)
    return true
end)

exports('SetFamily', function(src, familyId, familyName, identity)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) then return false end
    data.metadata = data.metadata or {}
    data.metadata.family_id = familyId
    data.metadata.family = familyName or familyId
    data.metadata.family_identity = type(identity) == 'table' and identity or nil
    MarkDirty(data)

    -- cm-family is authoritative, but playerdata mirrors the sanitized identity
    -- in a replicated state bag so overhead labels and the G menu need no DB polling.
    local replicated = type(identity) == 'table' and identity or false
    Player(src).state:set('cmFamily', replicated, true)
    TriggerClientEvent('cm-playerdata:client:familyIdentityChanged', src)
    return true
end)

-- ============================================================
-- Exports
-- ============================================================

exports('Load', LoadPlayerData)
exports('Save', SavePlayerData)
exports('SavePlayerData', SavePlayerData)
exports('SavePlayer', SavePlayerData)
exports('FlushPlayerData', FlushPlayerData)
exports('Flush', FlushPlayerData)

exports('GetPlayerData', function(src)
    return ClonePlayerData(PlayerData[tonumber(src)])
end)

exports('GetCharacterData', function(src)
    return ClonePlayerData(PlayerData[tonumber(src)])
end)

exports('GetRawPlayerData', function(src)
    -- Defensive clone to prevent external mutation of live PlayerData
    return ClonePlayerData(PlayerData[tonumber(src)])
end)

exports('GetCharId', function(src)
    return GetCharId(src)
end)

exports('GetCharacterId', function(src)
    return GetCharId(src)
end)

exports('GetCharacterFullName', function(src)
    local data = PlayerData[tonumber(src)]
    return data and BuildDisplayName(data.firstName, data.lastName) or nil
end)

exports('GetSourceByCharId', function(charId)
    charId = tonumber(charId)
    if not charId then return nil end
    for src, data in pairs(PlayerData) do
        if data and tonumber(data.charId) == charId then
            return src
        end
    end
    return nil
end)

exports('IsLoaded', function(src)
    src = tonumber(src)
    return PlayerData[src] and PlayerData[src].loaded == true or false
end)

exports('IsCharacterLoaded', function(src)
    src = tonumber(src)
    return PlayerData[src] and PlayerData[src].loaded == true or false
end)

exports('GetCash', function(src)
    src = tonumber(src)
    return PlayerData[src] and PlayerData[src].cash or 0
end)

exports('GetBank', function(src)
    src = tonumber(src)
    return PlayerData[src] and PlayerData[src].bank or 0
end)

exports('GetWantedStars', function(src)
    src = tonumber(src)
    return PlayerData[src] and PlayerData[src].wantedStars or 0
end)

-- "Busted" reset (GTA5-style) -- called by cm-police's booking flow once a
-- suspect is successfully jailed. pcall-wrapped by the caller, same as
-- every other cross-resource export call in this codebase.
exports('ClearWantedStars', function(src)
    src = tonumber(src)
    if not src or not PlayerData[src] then return end
    SetWantedStars(src, 0)
end)

-- Arbitrary-value setter, unlike ClearWantedStars above (always 0) -- lets
-- cm-police's MDT "Mark Wanted" action push its stars rating straight onto
-- the target's live HUD wanted level, reusing this same clamp/store/push
-- path every other gain/clear/decay call site already goes through.
exports('SetWantedStars', function(src, stars)
    src = tonumber(src)
    if not src or not PlayerData[src] then return end
    SetWantedStars(src, stars)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= 'cm-police' then return end
    CreateThread(function()
        Wait(500)
        for _, data in pairs(PlayerData) do
            if data.loaded then
                pcall(function() exports['cm-police']:SyncWantedStars(data.charId, data.wantedStars or 0) end)
            end
        end
    end)
end)

-- Passive decay -- the "wait it out" path. Only ticks players who haven't
-- gained a new star since the last check, same "periodic sweep over
-- currently-loaded players" shape used elsewhere in this codebase (e.g.
-- cm-police's dispatch auto-expire sweep).
CreateThread(function()
    while true do
        Wait(60000)
        local decaySeconds = math.max(60, math.floor(((Config.WantedStars and Config.WantedStars.DecayIntervalMs) or 3600000) / 1000))
        local now = os.time()
        for src, data in pairs(PlayerData) do
            local wanted = data.metadata and data.metadata.cmWanted
            if data.loaded and (data.wantedStars or 0) > 0 and wanted
                and now >= (tonumber(wanted.nextDecayAt) or (now + decaySeconds)) then
                SetWantedStars(src, data.wantedStars - 1)
            end
        end
    end
end)

RegisterNetEvent('cm-playerdata:server:aiWantedChaseEscaped', function()
    local src = source
    local data = PlayerData[src]
    local minimumMs = (Config.WantedStars and Config.WantedStars.AiEscapeMinimumMs) or 120000
    if not CanMutate(data) or (data.wantedStars or 0) ~= ((Config.WantedStars and Config.WantedStars.Max) or 6) then return end
    if GetGameTimer() - (data.wantedStarChangedAt or GetGameTimer()) < minimumMs then return end
    SetWantedStars(src, data.wantedStars - 1)
end)

exports('GetMoney', function(src, account)
    src = tonumber(src)
    account = NormalizeAccount(account)
    if not src or not account or not PlayerData[src] then return 0 end
    return PlayerData[src][account] or 0
end)

exports('GetAccounts', function(src)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    return { cash = data and data.cash or 0, bank = data and data.bank or 0 }
end)

exports('SetMoney', SetMoney)
exports('AddMoney', AddMoney)
exports('RemoveMoney', RemoveMoney)
exports('CanAfford', CanAfford)
exports('TransferMoney', TransferMoney)
exports('TransferCashBetweenCharactersAtomic', function(fromSrc, toSrc, amount, reason, metadata)
    return TransferCashBetweenCharactersAtomic(fromSrc, toSrc, amount, reason, metadata)
end)

exports('TransferMoneyBetweenAuthoritative', function(fromSrc, toSrc, account, amount, reason, metadata)
    return TransferMoneyBetweenPlayersAuthoritative(fromSrc, toSrc, account, amount, reason, metadata)
end)

exports('TransferMoneyBetween', function(fromSrc, toSrc, account, amount, reason, metadata)
    local ok, err = TransferMoneyBetweenPlayersAuthoritative(fromSrc, toSrc, account, amount, reason, metadata)
    return ok
end)

exports('TransferMoneyBetweenDetailed', function(fromSrc, toSrc, account, amount, reason, metadata)
    return TransferMoneyBetweenPlayersAuthoritative(fromSrc, toSrc, account, amount, reason, metadata)
end)

exports('AddCash', function(src, amount, reason)
    return AddMoney(src, 'cash', amount, reason or 'add_cash')
end)

exports('RemoveCash', function(src, amount, reason)
    return RemoveMoney(src, 'cash', amount, reason or 'remove_cash')
end)

exports('AddBank', function(src, amount, reason)
    return AddMoney(src, 'bank', amount, reason or 'add_bank')
end)

exports('RemoveBank', function(src, amount, reason)
    return RemoveMoney(src, 'bank', amount, reason or 'remove_bank')
end)

local function SetMetadataInternal(src, key, value)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) then
        return false, 'cannot_mutate'
    end

    if type(key) ~= 'string' or key == '' or #key > 128 then
        return false, 'invalid_key'
    end

    local okVal, cleanedValue = ValidateAndCopyMetadataValue(value, 1, {})
    if not okVal then
        return false, cleanedValue
    end

    local tempMeta = DeepCopy(data.metadata or {})
    tempMeta[key] = cleanedValue
    local serialized = EncodeJson(tempMeta)
    local maxBytes = (Config.Metadata and Config.Metadata.MaxSerializedBytes) or 65536
    if not serialized or #serialized > maxBytes then
        return false, 'max_bytes_exceeded'
    end

    data.metadata = tempMeta
    MarkDirty(data)
    return true, nil
end

exports('SetMetadata', function(src, key, value)
    local ok = SetMetadataInternal(src, key, value)
    return ok == true
end)

exports('SetMetadataDetailed', function(src, key, value)
    return SetMetadataInternal(src, key, value)
end)

exports('GetMetadata', function(src, key)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data or not data.metadata then return nil end
    if key == nil then
        return DeepCopy(data.metadata)
    end
    return DeepCopy(data.metadata[key])
end)

exports('IsDead', function(src)
    return PlayerData[src] and PlayerData[src].isDead or false
end)

exports('GetDeathCount', function(src)
    return PlayerData[src] and PlayerData[src].deathCount or 0
end)

exports('GetDeathInfo', function(src)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data then return nil end
    return {
        isDead = data.isDead == true,
        deathCount = data.deathCount or 0,
        remainingMs = data.deathDeadline and math.max(0, data.deathDeadline - GetGameTimer()) or nil,
        ambulanceCalled = data.ambulanceCalled == true,
        reason = data.deathReason,
        lastPosition = NormalizeCoords(data.lastPosition),
        deathLocation = NormalizeCoords(data.deathLocation),
        spawnOverride = data.isDead and GetDeadLocation(data) or nil
    }
end)

exports('GetDeathSpawn', function(src)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    return GetDeadLocation(data)
end)

exports('GetSpawnOverride', function(src, requestedSpawnKey)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data or data.loaded ~= true or data.isDead ~= true then return nil end

    local coords = GetDeadLocation(data)
    if not coords then return nil end

    return {
        forced = true,
        reason = 'dead_character',
        key = 'dead_location',
        requestedKey = requestedSpawnKey,
        label = 'LAST BODY LOCATION',
        description = 'You are still down. You will return to where you died.',
        coords = coords,
        isDead = true,
        remainingMs = data.deathDeadline and math.max(0, data.deathDeadline - GetGameTimer()) or nil
    }
end)

exports('RequestAmbulance', RequestAmbulance)
exports('CallAmbulance', RequestAmbulance)
exports('ProtectDeathTimer', ProtectDeathTimer)
exports('ReleaseDeathTimerProtection', ReleaseDeathTimerProtection)

exports('SetDead', SetDead)

exports('SetHealth', function(src, health, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) then return false end
    data.health = Clamp(health or Config.Vitals.MaxHealth, 0, Config.Vitals.MaxHealth)
    MarkDirty(data)
    SetState(src, 'health', data.health)
    TriggerClientEvent('cm-playerdata:client:setHealth', src, data.health)
    Audit(src, 'set_health', { health = data.health, reason = reason })
    return true
end)

local function SetArmor(src, armor, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) then return false end
    data.armor = Clamp(armor or 0, 0, Config.Vitals.MaxArmor)
    MarkDirty(data)
    data.armorGuardUntil = GetGameTimer() + 4500
    SetState(src, 'armor', data.armor)
    PushUpdate(src, 'armor', data.armor)
    TriggerClientEvent('cm-playerdata:client:setArmor', src, data.armor)
    Audit(src, 'set_armor', { armor = data.armor, reason = reason })
    return true
end

exports('SetArmor', SetArmor)

exports('Heal', function(src, amountOrPercent, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) then return false end

    local amount = tonumber(amountOrPercent) or 0
    local targetHealth
    if amount > 0 and amount <= 100 then
        targetHealth = GetHealthFromPercent(amount)
    else
        targetHealth = Clamp((data.health or Config.Vitals.MaxHealth) + amount, (Config.Vitals.DamageThreshold or 101) + 1, Config.Vitals.MaxHealth)
    end

    -- Healing an unconscious player brings them back from death, in place: no
    -- teleport, no hospital. Full heal -> full revive; a partial heal gets them
    -- up weak at the same spot.
    if data.isDead then
        ResolveAmbulanceRequest(src, data, reason or 'healed')
        data.isDead = false
        data.health = targetHealth
        data.armor = 0
        data.deathDeadline = nil
        data.deathDeadlineAt = nil
        data.ambulanceCalled = false
        data.dieChosen = false
        data.deathReason = nil
        MarkDirty(data)
        GuardVitalsAfterRevive(data)

        ApplyState(src)
        SyncInventoryDeathState(src, false)
        SavePlayerData(src, reason or 'heal_revive')
        if targetHealth >= (Config.Vitals.MaxHealth or 200) then
            TriggerClientEvent('cm-playerdata:client:revive', src)
        else
            TriggerClientEvent('cm-playerdata:client:revivePartial', src, targetHealth)
        end
        Audit(src, 'heal_revive', { health = targetHealth, reason = reason })
        return true
    end

    data.health = targetHealth
    MarkDirty(data)
    GuardVitalsAfterRevive(data)
    SetState(src, 'health', data.health)
    SavePlayerData(src, reason or 'heal')
    TriggerClientEvent('cm-playerdata:client:setHealth', src, data.health)
    Audit(src, 'heal', { health = data.health, reason = reason })
    return true
end)

exports('RevivePartial', function(src, percent, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not CanMutate(data) then return false end

    local health = GetHealthFromPercent(percent or (Config.Medical and Config.Medical.StreetPatchHealthPercent) or 30)
    ResolveAmbulanceRequest(src, data, reason or 'revived_partial')
    data.isDead = false
    data.health = health
    data.armor = 0
    data.deathDeadline = nil
    data.deathDeadlineAt = nil
    data.ambulanceCalled = false
    data.dieChosen = false
    data.deathReason = nil
    MarkDirty(data)
    GuardVitalsAfterRevive(data)

    ApplyState(src)
    SyncInventoryDeathState(src, false)
    SavePlayerData(src, reason or 'revive_partial')
    TriggerClientEvent('cm-playerdata:client:revivePartial', src, health)
    Audit(src, 'revive_partial', { health = health, reason = reason })
    return true
end)

exports('Revive', function(src)
    local data = PlayerData[src]
    if not CanMutate(data) then return false end

    ResolveAmbulanceRequest(src, data, 'revived')
    data.isDead = false
    data.health = Config.Vitals.MaxHealth
    data.armor = 0
    data.deathDeadline = nil
    data.deathDeadlineAt = nil
    data.ambulanceCalled = false
    data.dieChosen = false
    data.deathReason = nil
    MarkDirty(data)
    GuardVitalsAfterRevive(data)

    ApplyState(src)
    SyncInventoryDeathState(src, false)
    SavePlayerData(src, 'revive')
    TriggerClientEvent('cm-playerdata:client:revive', src)
    return true
end)

exports('Respawn', function(src, spawnCoords, cost)
    local data = PlayerData[src]
    if not CanMutate(data) then return false end

    local hospitalReservation
    if not spawnCoords and GetResourceState('cm-doctor') == 'started' then
        local callOk, reserved, result = pcall(function()
            return exports['cm-doctor']:ReserveRespawnBed(src, GetDeadLocation(data))
        end)
        if callOk and reserved == true and type(result) == 'table' and type(result.spawn) == 'table' then
            hospitalReservation = result
            spawnCoords = result.spawn
            if cost == nil then cost = tonumber(result.bill) end
        elseif callOk and reserved == false and tostring(result or ''):find('occupied', 1, true) then
            -- Keep the patient in the death state until one of the 11 real beds
            -- becomes free. Never overlap them on a fallback coordinate.
            local retryMs = 5000
            data.deathDeadline = GetGameTimer() + retryMs
            data.deathDeadlineAt = NowMs() + retryMs
            ScheduleBleedOut(src)
            TriggerClientEvent('cm-playerdata:client:emsProtectionUpdated', src, {
                remainingMs = retryMs, etaMs = retryMs,
                label = 'WAITING FOR HOSPITAL BED', protected = true,
            })
            return false
        end
    end

    spawnCoords = spawnCoords or Config.Respawn.HospitalSpawn
    cost = tonumber(cost ~= nil and cost or Config.Respawn.Cost) or 0

    if cost > 0 then
        local bankBalance = tonumber(data.bank) or 0
        local cashBalance = tonumber(data.cash) or 0
        if bankBalance >= cost then
            RemoveMoney(src, 'bank', cost, 'hospital_respawn')
        elseif bankBalance + cashBalance >= cost then
            if bankBalance > 0 then RemoveMoney(src, 'bank', bankBalance, 'hospital_respawn') end
            local remaining = cost - bankBalance
            if remaining > 0 then RemoveMoney(src, 'cash', remaining, 'hospital_respawn') end
        else
            -- Beginner-friendly: if they cannot afford hospital, take what exists and still respawn.
            if bankBalance > 0 then RemoveMoney(src, 'bank', bankBalance, 'hospital_respawn_partial') end
            if cashBalance > 0 then RemoveMoney(src, 'cash', cashBalance, 'hospital_respawn_partial') end
        end
    end

    local supplyWarDeathContext=SupplyWarDeathContexts[tostring(data.charId)]
    ResolveAmbulanceRequest(src, data, 'hospital_respawn')
    data.isDead = false
    data.health = GetRespawnHealth()
    data.armor = 0
    data.deathDeadline = nil
    data.deathDeadlineAt = nil
    data.ambulanceCalled = false
    data.dieChosen = false
    data.deathReason = nil
    MarkDirty(data)

    ApplyState(src)
    SyncInventoryDeathState(src, false)
    SupplyWarDeathContexts[tostring(data.charId)]=nil
    SavePlayerData(src, 'respawn')
    Audit(src, 'hospital_respawn', {
        health = data.health, cost = cost,
        hospital = hospitalReservation and hospitalReservation.hospitalId or 'fallback',
        bed = hospitalReservation and hospitalReservation.bedId or nil,
    })
    TriggerClientEvent('cm-playerdata:client:respawn', src, spawnCoords, data.health)
    if supplyWarDeathContext and supplyWarDeathContext.source==tonumber(src)and supplyWarDeathContext.expiresAt>os.time()then SetTimeout(2200,function()if GetPlayerName(src)and GetResourceState('cm-inventory')=='started'then local ok,resynced=pcall(function()return exports['cm-inventory']:ResyncAuthoritativeEquipment(src)end);if not ok or resynced~=true then Log('warn','Supply War loadout re-sync failed',{src=src,characterId=data.charId})elseif Config.Debug then Debug(('LOADOUT_RESYNC character=%s weapon=%s ammo=%s'):format(tostring(data.charId),tostring(supplyWarDeathContext.equippedWeapon),tostring(supplyWarDeathContext.equippedAmmoQuantity)))end end end)end
    return true
end)

-- Admin preview exports for cm-admin. These are read-only and permission-gated.
local function CanReadLogs(adminSrc)
    return HasAdminPermission(adminSrc, 'logs.view') or HasAdminPermission(adminSrc, 'playerdata.logs.view')
end

exports('AdminGetAuditLogs', function(adminSrc, characterId, action, limit)
    adminSrc = tonumber(adminSrc) or 0
    if not CanReadLogs(adminSrc) then return {} end

    limit = Clamp(limit or 50, 1, 200)
    local where = {}
    local params = {}

    if characterId then
        where[#where + 1] = 'character_id = ?'
        params[#params + 1] = tostring(characterId)
    end
    if action and tostring(action) ~= '' then
        where[#where + 1] = 'action = ?'
        params[#params + 1] = tostring(action)
    end

    local sql = 'SELECT id, character_id, action, data, created_at FROM playerdata_audit'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY id DESC LIMIT ?'
    params[#params + 1] = limit

    return MySQL.query.await(sql, params) or {}
end)

exports('AdminGetMoneyTransactions', function(adminSrc, characterId, limit)
    adminSrc = tonumber(adminSrc) or 0
    if not CanReadLogs(adminSrc) then return {} end

    limit = Clamp(limit or 50, 1, 200)
    local params = {}
    local sql = [[
        SELECT id, character_id, account_type, amount, action, reason, resource_name,
               balance_before, balance_after, metadata, created_at
        FROM economy_transactions
    ]]

    if characterId then
        sql = sql .. ' WHERE character_id = ?'
        params[#params + 1] = tonumber(characterId)
    end

    sql = sql .. ' ORDER BY id DESC LIMIT ?'
    params[#params + 1] = limit

    return MySQL.query.await(sql, params) or {}
end)

exports('AdminGetDeathLogs', function(adminSrc, characterId, limit)
    adminSrc = tonumber(adminSrc) or 0
    if not CanReadLogs(adminSrc) then return {} end

    limit = Clamp(limit or 50, 1, 200)
    local params = {}
    local sql = [[
        SELECT id, character_id, action, data, created_at
        FROM playerdata_audit
        WHERE action IN ('death', 'death_detail', 'kill_detail', 'ambulance_called', 'death_give_up', 'hospital_respawn', 'revive', 'revive_partial', 'treat_success')
    ]]

    if characterId then
        sql = sql .. ' AND character_id = ?'
        params[#params + 1] = tostring(characterId)
    end

    sql = sql .. ' ORDER BY id DESC LIMIT ?'
    params[#params + 1] = limit

    return MySQL.query.await(sql, params) or {}
end)

-- ============================================================
-- Loops
-- ============================================================

CreateThread(function()
    while true do
        Wait(Config.Save.FullSaveInterval)
        for src, data in pairs(PlayerData) do
            if data.loaded and data.dirty then
                SavePlayerData(src, 'auto')
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Save.PositionSaveInterval)
        for src, data in pairs(PlayerData) do
            if data.loaded and data.lastPosition then
                SavePositionOnly(src)
            end
        end
    end
end)
