-- cm-playerdata/server/main.lua
-- Foundation clean upgrade for CM Framework. No hunger/thirst/stress.
-- Owns loaded character state, visible database character ID, cash/bank, vitals, death state, and player identity interactions.
-- Admin UI/tools stay in cm-admin. Prices/payout rules stay in cm-economy.
-- Uses oxmysql directly to avoid cm-core export call-style issues.

local Config = CMPlayerData.Config
local PlayerData = {}
local PendingHandshakes = {} -- [targetSrc] = { from = src, expires = ms }
local PendingTreatments = {} -- [treaterSrc] = { target = src, startedAt = ms, duration = ms }
local PendingTreatmentOffers = {} -- [targetSrc] = { from = src, expires = ms }
local LastEventUse = {}
local ExtensionInteractionActions = {} -- [actionId] = { event = serverEventName, allowDeadTarget = bool, deadOnly = bool }

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
        return tonumber(data.charId)
    end

    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end

    return tonumber(state.charId or state.characterId or state.rpId)
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
    if not data then return end
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
    data.dirty = true
    PushUpdate(src, 'wantedStars', stars)
    local persisted, persistError = pcall(function()
        MySQL.update.await('UPDATE characters SET metadata = ? WHERE id = ?', {
            EncodeJson(data.metadata), data.charId
        })
    end)
    if not persisted then
        Log('error', 'Wanted state persistence failed', { src = src, error = tostring(persistError) })
    end
    pcall(function() exports['cm-police']:SyncWantedStars(data.charId, stars) end)
    -- Auto-generated arrest warrant the moment max wanted is first reached
    -- (not on every subsequent tick while already at max). pcall-guarded,
    -- no fxmanifest dependency added -- cm-police already depends on
    -- cm-playerdata, so the reverse would be a circular dependency.
    if stars >= maxStars and (previous or 0) < maxStars then
        pcall(function() exports['cm-police']:AutoIssueWarrant(data.charId, 'Reached maximum wanted level (6 stars)') end)
    end
end

local function EnsureSchema()
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
        pcall(function()
            MySQL.query.await(sql)
        end)
    end

    pcall(function()
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
    end)

    -- Transaction log for cash/bank changes. cm-playerdata owns balances;
    -- cm-economy decides prices/payouts and calls these exports.
    pcall(function()
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
    end)

    Debug('Schema checked')
end

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
        deathLocation = DecodeJson(EncodeJson(data.deathLocation)) or data.deathLocation,
        lastPosition = DecodeJson(EncodeJson(data.lastPosition)) or data.lastPosition,
        metadata = DecodeJson(EncodeJson(data.metadata)) or data.metadata,
        loaded = data.loaded == true
    }
end

local function ApplyState(src)
    local data = PlayerData[src]
    if not data then return end

    local charId = tonumber(data.charId)
    if charId then
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

local function LoadPlayerData(src)
    local charId = GetCharId(src)
    if not charId then
        Debug('Load skipped, charId missing for src=' .. tostring(src))
        return false
    end

    local row = MySQL.single.await([[
        SELECT first_name, last_name, cash, bank, health, armor, is_dead, death_count, death_deadline_at, death_location, ambulance_called, death_reason, last_position, metadata
        FROM characters
        WHERE id = ?
        LIMIT 1
    ]], { charId })

    if not row then
        Log('error', 'Load failed: character row not found', { src = src, charId = charId })
        return false
    end

    local defaults = Config.Defaults

    if PlayerData[src] and PlayerData[src].loaded and tonumber(PlayerData[src].charId) ~= tonumber(charId) then
        -- Character switched while this resource stayed alive. The old record will
        -- be saved by the normal save loop/drop hook if needed; replace cache now.
        PlayerData[src] = nil
    end

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
            -- They were dead long enough while offline. Let the client finish
            -- spawn, show the death state briefly, then the server respawns them.
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

    PlayerData[src] = {
        src = src,
        charId = charId,
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
        lastPosition = NormalizeCoords(DecodeJson(row.last_position)),
        metadata = persistedMetadata,

        wantedStars = wantedStars,
        wantedStarChangedAt = GetGameTimer(),

        loaded = true,
        dirty = dirtyAfterLoad,
        lastVitalsSync = GetGameTimer()
    }

    if PlayerData[src].isDead and not PlayerData[src].deathLocation then
        PlayerData[src].deathLocation = NormalizeCoords(PlayerData[src].lastPosition) or NormalizeCoords(Config.Respawn and Config.Respawn.HospitalSpawn)
        PlayerData[src].dirty = true
    end

    Debug(('Loaded src=%s char=%s HP=%s dead=%s'):format(
        src, charId, PlayerData[src].health, tostring(PlayerData[src].isDead)
    ))

    NotifyLoaded(src)
    pcall(function() exports['cm-police']:SyncWantedStars(charId, wantedStars) end)

    if PlayerData[src].isDead and PlayerData[src].deathDeadline then
        ScheduleBleedOut(src)
        if PlayerData[src].dirty then
            SavePlayerData(src, 'dead_rejoin_deadline_restore')
        end
    end

    return true
end

local function SavePlayerData(src, reason)
    local data = PlayerData[src]
    if not data or not data.loaded then return false end

    local ok, err = pcall(function()
        MySQL.update.await([[
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
            data.cash,
            data.bank,
            data.health,
            data.armor,
            data.isDead and 1 or 0,
            data.deathCount,
            data.deathDeadlineAt,
            EncodeJson(data.deathLocation),
            data.ambulanceCalled and 1 or 0,
            data.deathReason,
            EncodeJson(data.lastPosition),
            EncodeJson(data.metadata or {}),
            data.charId
        })
    end)

    if not ok then
        Log('error', 'Save failed', { src = src, reason = reason, error = tostring(err) })
        return false
    end

    data.dirty = false
    Debug(('Saved src=%s reason=%s'):format(src, reason or 'manual'))
    return true
end

local function SavePositionOnly(src)
    local data = PlayerData[src]
    if not data or not data.loaded or not data.lastPosition then return false end

    local ok = pcall(function()
        MySQL.update.await(
            'UPDATE characters SET last_position = ? WHERE id = ?',
            { EncodeJson(data.lastPosition), data.charId }
        )
    end)

    return ok
end

local function ClearPlayerData(src)
    local oldData = PlayerData[src]
    if oldData then
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

local function SetMoney(src, account, value, reason, metadata)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    account = NormalizeAccount(account)
    if not data or not data.loaded or not account then return false end

    local before = tonumber(data[account]) or 0
    local after = math.max(0, math.floor(tonumber(value) or 0))
    local delta = after - before
    if before == after then return true end

    data[account] = after
    data.dirty = true

    SetState(src, account, data[account])
    PushUpdate(src, account, data[account])
    TriggerEvent('cm-playerdata:server:moneyChanged', src, account, before, after, reason or 'set_money')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, account, before, after, reason or 'set_money')

    RecordMoneyTransaction(src, account, delta, 'set', reason or 'set_money', before, after, metadata)
    -- Persisted by the async batch saver (data.dirty). No blocking write here.
    return true
end

local function AddMoney(src, account, amount, reason, metadata)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    account = NormalizeAccount(account)
    amount = NormalizeAmount(amount)
    if not data or not data.loaded or not account or not amount then return false end

    local before = tonumber(data[account]) or 0
    local after = before + amount

    data[account] = after
    data.dirty = true

    SetState(src, account, after)
    PushUpdate(src, account, after)
    TriggerEvent('cm-playerdata:server:moneyChanged', src, account, before, after, reason or 'add_money')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, account, before, after, reason or 'add_money')

    RecordMoneyTransaction(src, account, amount, 'add', reason or 'add_money', before, after, metadata)
    -- Persisted by the async batch saver (data.dirty). No blocking write here.
    return true
end

local function RemoveMoney(src, account, amount, reason, metadata)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    account = NormalizeAccount(account)
    amount = NormalizeAmount(amount)
    if not data or not data.loaded or not account or not amount then return false end

    local before = tonumber(data[account]) or 0
    if before < amount then return false end
    local after = before - amount

    data[account] = after
    data.dirty = true

    SetState(src, account, after)
    PushUpdate(src, account, after)
    TriggerEvent('cm-playerdata:server:moneyChanged', src, account, before, after, reason or 'remove_money')
    TriggerClientEvent('cm-playerdata:client:moneyChanged', src, account, before, after, reason or 'remove_money')

    RecordMoneyTransaction(src, account, -amount, 'remove', reason or 'remove_money', before, after, metadata)
    -- Persisted by the async batch saver (data.dirty). No blocking write here.
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
    fromAccount = NormalizeAccount(fromAccount)
    toAccount = NormalizeAccount(toAccount)
    amount = NormalizeAmount(amount)
    if not fromAccount or not toAccount or not amount or fromAccount == toAccount then return false end
    if not CanAfford(src, fromAccount, amount) then return false end
    if not RemoveMoney(src, fromAccount, amount, reason or 'transfer_out', metadata) then return false end
    if not AddMoney(src, toAccount, amount, reason or 'transfer_in', metadata) then
        AddMoney(src, fromAccount, amount, 'transfer_refund', { originalReason = reason })
        return false
    end
    return true
end

local function SyncInventoryDeathState(src, dead)
    if GetResourceState('cm-inventory') ~= 'started' then return end

    local ok, err = pcall(function()
        if dead then
            exports['cm-inventory']:DropEquippedWeaponsOnDeath(src)
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
    if not data then return false end

    local wasDead = data.isDead == true
    data.isDead = isDead == true
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
    data.dirty = true

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
    EnsureSchema()
    Log('info', 'CM PlayerData v1.8.5 started')

    -- Restart resilience: if this resource was live-restarted with players
    -- online, rebuild their state from the database instead of leaving them broken.
    for _, playerSrc in ipairs(GetPlayers()) do
        local src = tonumber(playerSrc)
        if src then
            SetTimeout(750, function()
                if GetPlayerName(src) then
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
            SavePlayerData(src, 'resource_stop')
        end
    end
end)

AddEventHandler('cm-core:characterLoaded', function(src, charId)
    src = tonumber(src)
    if not src then return end

    charId = tonumber(charId) or GetCharId(src)
    if charId then
        local ok, state = pcall(function() return Player(src).state end)
        if ok and state then
            state:set('charId', charId, true)
            state:set('characterId', charId, true)
            state:set('rpId', charId, true)
        end
    end

    SetTimeout(500, function()
        LoadPlayerData(src)
    end)
end)

RegisterNetEvent('cm-playerdata:server:load', function()
    LoadPlayerData(source)
end)

-- Clean server-side handoff event for cm-characters/cm-spawn.
-- charId may be passed by a trusted server event, or already set in the player's state bag.
AddEventHandler('cm-playerdata:server:loadCharacter', function(src, charId)
    src = tonumber(src)
    if not src then return end
    charId = tonumber(charId)
    if charId then
        pcall(function()
            local state = Player(src).state
            state:set('charId', charId, true)
            state:set('characterId', charId, true)
            state:set('rpId', charId, true)
        end)
    end
    LoadPlayerData(src)
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
                state:set('charId', tonumber(charId), true)
                state:set('characterId', tonumber(charId), true)
                state:set('rpId', tonumber(charId), true)
            end)
        end
        LoadPlayerData(src)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    SavePlayerData(src, 'drop')
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
    if not data or type(coords) ~= 'table' then return end
    -- Never overwrite the saved body/death location while the character is dead.
    -- cm-spawn may temporarily resurrect/move the ped for placement, but the RP
    -- death location must remain the place where SetDead captured it.
    if data.isDead == true then return end
    -- Never save the fixed character-selector/creation preview coordinates as
    -- the player's last position (docs/V1_4_1_FIXED_PREVIEW_COORDS.md's
    -- documented contract: cm-playerdata ignores position updates while
    -- skipPositionSave or isInCharacterSelector is true). cm-characters and
    -- cm-spawn already set these state bags; this event handler simply never
    -- checked them, so a position sample taken during selector preview could
    -- overwrite last_position and cause the next "spawn at last location" to
    -- place the player back at the selector scene.
    local ok, state = pcall(function() return Player(src).state end)
    if ok and state and (state.skipPositionSave == true or state.isInCharacterSelector == true) then
        return
    end

    local x, y, z, h = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z), tonumber(coords.h)
    if not x or not y or not z then return end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or z < -500 or z > 2000 then return end

    -- Movement sanity logging (log only, never auto-punish: admin teleports,
    -- respawns and lag spikes are legitimate causes of big jumps).
    local logCfg = Config.Logging or {}
    if logCfg.LogMovementAnomalies ~= false and data.lastPosSample and not data.isDead then
        local now = os.clock()
        local dt = now - (data.lastPosSampleTime or now)
        if dt > 0.5 then
            local dx = x - data.lastPosSample.x
            local dy = y - data.lastPosSample.y
            local dz = z - data.lastPosSample.z
            local dist2d = math.sqrt(dx * dx + dy * dy)
            local speed = dist2d / dt

            local inVehicle = false
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local ok, veh = pcall(GetVehiclePedIsIn, ped, false)
                inVehicle = ok and veh ~= 0
            end

            local falling = dz <= (logCfg.FallZDelta or -9.0)

            if dist2d >= (logCfg.TeleportDistance or 300.0) then
                Audit(src, 'movement_teleport', {
                    from = data.lastPosSample, to = { x = x, y = y, z = z },
                    distance = math.floor(dist2d), seconds = math.floor(dt * 10) / 10
                })
            elseif not inVehicle and not falling and speed > (logCfg.MaxOnFootSpeed or 11.0) then
                Audit(src, 'movement_speed_anomaly', {
                    speed_ms = math.floor(speed * 10) / 10,
                    distance = math.floor(dist2d * 10) / 10,
                    seconds = math.floor(dt * 10) / 10,
                    at = { x = x, y = y, z = z }
                })
            end
        end
    end

    data.lastPosSample = { x = x, y = y, z = z }
    data.lastPosSampleTime = os.clock()

    data.lastPosition = NormalizeCoords({ x = x, y = y, z = z, h = h })
end)

RegisterNetEvent('cm-playerdata:server:syncVitals', function(clientHealth, clientArmor)
    local src = source
    if not RateLimit(src, 'vitals', 1000) then return end
    local data = PlayerData[src]
    if not data or not data.loaded or data.isDead then return end

    local previousHealth = tonumber(data.health) or Config.Vitals.MaxHealth
    local serverHealth = GetServerPedHealth(src)
    local nextHealth = Clamp(clientHealth or previousHealth, 0, Config.Vitals.MaxHealth)
    local nextArmor = Clamp(clientArmor or 0, 0, Config.Vitals.MaxArmor)

    -- The client may report damage quickly, but never trust a huge healing jump from the client.
    -- Healing/revive should come from server exports so jobs/admin/hospital scripts stay authoritative.
    local maxPassiveHeal = math.max(0, tonumber(Config.Vitals.MaxPassiveHealDelta) or 0)
    if nextHealth > previousHealth + maxPassiveHeal then
        nextHealth = previousHealth
    end

    -- Prefer server-observed ped health when available and lower than the client value.
    if serverHealth and serverHealth < nextHealth then
        nextHealth = Clamp(serverHealth, 0, Config.Vitals.MaxHealth)
    end

    -- Right after a revive/heal, a lower reading here is almost always one
    -- stale sync still in flight from before the client actually applied the
    -- new health, not real new damage -- see GuardVitalsAfterRevive.
    if data.vitalsGuardUntil and GetGameTimer() < data.vitalsGuardUntil and nextHealth < previousHealth then
        nextHealth = previousHealth
    end

    if nextHealth ~= data.health or nextArmor ~= data.armor then
        data.health = nextHealth
        data.armor = nextArmor
        data.dirty = true
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
        victimData.metadata = victimData.metadata or {}
        local known = victimData.metadata.knownIdentities or {}
        local entry = known[tostring(killerData.charId)]
        if entry and entry.name then
            label = entry.name
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
    if not data or not data.loaded or data.isDead then return end

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
    if not data or not data.isDead or not data.deathDeadline then return false, 'not_dead' end
    if data.ambulanceCalled then return false, 'already_called' end

    data.ambulanceCalled = true
    local extra = (Config.Respawn and Config.Respawn.AmbulanceExtraTime) or 120000
    data.deathDeadline = data.deathDeadline + extra
    data.deathDeadlineAt = (data.deathDeadlineAt or NowMs()) + extra
    data.dirty = true
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
    if not data or not data.loaded or not data.isDead or not data.deathDeadline then
        return false, 'not_dead'
    end

    local nowGame, nowReal = GetGameTimer(), NowMs()
    local currentRemaining = math.max(0, data.deathDeadline - nowGame)
    if currentRemaining < minimumRemainingMs then
        data.deathDeadline = nowGame + minimumRemainingMs
        data.deathDeadlineAt = nowReal + minimumRemainingMs
        data.dirty = true
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
    if not data or not data.emsProtection then return false end
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
    if not data or not data.isDead then return end

    -- Per design: no time change, the death screen stays until bleed-out ends.
    data.dieChosen = true
    data.dirty = true
    SavePlayerData(src, 'death_give_up')
    Audit(src, 'death_give_up', {})
end)

RegisterNetEvent('cm-playerdata:server:requestRespawn', function()
    local src = source
    if not RateLimit(src, 'respawn', 2000) then return end
    local data = PlayerData[src]
    if not data or not data.isDead then return end

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
    if not data or not data.isDead then return end

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

local function IsKnownByMemory(viewerData, targetData)
    if not viewerData or not targetData then return false end
    local metadata = viewerData.metadata or {}
    local known = metadata.knownIdentities or metadata.knownPlayers or {}
    local targetCharId = tostring(targetData.charId or '')
    if targetCharId == '' then return false end
    return known[targetCharId] ~= nil or known[tonumber(targetCharId)] ~= nil
end

local function EnsureKnownTable(data)
    data.metadata = data.metadata or {}
    data.metadata.knownIdentities = data.metadata.knownIdentities or {}
    return data.metadata.knownIdentities
end

local function MarkIdentityKnown(viewerSrc, targetSrc, reason)
    viewerSrc = tonumber(viewerSrc)
    targetSrc = tonumber(targetSrc)
    if not viewerSrc or not targetSrc then return false end

    local viewerData = PlayerData[viewerSrc]
    local targetData = PlayerData[targetSrc]
    if not viewerData or not targetData then return false end

    local known = EnsureKnownTable(viewerData)
    known[tostring(targetData.charId)] = {
        characterId = tonumber(targetData.charId),
        name = GetFullName(targetData),
        reason = reason or 'known',
        time = os.time()
    }

    viewerData.dirty = true
    return true
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
        local viewerOrg = GetOrgTag(viewerSrc, viewerData)
        local targetOrg = GetOrgTag(targetSrc, targetData)
        if viewerOrg and targetOrg and viewerOrg == targetOrg then
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

local function ValidatePlayerInteraction(src, targetSrc, rateKey, rateMs, allowVehicleTarget)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc <= 0 or src == targetSrc then
        return false, nil, 'Invalid target.'
    end

    if not RateLimit(src, rateKey or 'player_interaction', tonumber(rateMs) or 750) then
        return false, targetSrc, 'Please slow down.'
    end

    if not PlayerData[src] or not PlayerData[src].loaded then
        return false, targetSrc, 'Your player data is not loaded yet.'
    end

    if PlayerData[src].isDead then
        return false, targetSrc, 'You cannot do this while unconscious.'
    end

    if not GetPlayerName(targetSrc) then
        return false, targetSrc, 'Target player is no longer online.'
    end

    if not PlayerData[targetSrc] or not PlayerData[targetSrc].loaded then
        return false, targetSrc, 'Target player data is not loaded yet.'
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

    if not RemoveMoney(src, 'cash', amount, 'player_give_cash') then
        NotifyPlayer(src, 'You do not have enough cash.', 'error')
        return
    end

    AddMoney(target, 'cash', amount, 'player_receive_cash')
    Audit(src, 'give_cash_to_player', { target_character_id = GetPublicCharacterId(target), amount = amount })
    Audit(target, 'receive_cash_from_player', { from_character_id = GetPublicCharacterId(src), amount = amount })

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
        MarkIdentityKnown(target, src, 'shared_id')
        SavePlayerData(target, 'identity_shared_id')
        PushIdentityUpdate(target, src)
        NotifyPlayer(src, ('You showed your ID to %s.'):format(GetPublicPlayerLabel(target)), 'success')

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
    if not src or not GetPlayerName(src) or not PlayerData[src] or not PlayerData[target] then return end
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
    if not targetData or not targetData.loaded then
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
    targetData.dirty = true

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
    if not GetPlayerName(from) or not PlayerData[from] or not PlayerData[from].loaded then
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

    MarkIdentityKnown(src, from, 'handshake')
    MarkIdentityKnown(from, src, 'handshake')
    SavePlayerData(src, 'identity_handshake')
    SavePlayerData(from, 'identity_handshake')
    PushIdentityUpdate(src, from)
    PushIdentityUpdate(from, src)
    NotifyPlayer(src, ('You shook hands with %s. Their name is now visible to you.'):format(GetFullName(PlayerData[from])), 'success')
    NotifyPlayer(from, ('You shook hands with %s. Their name is now visible to you.'):format(GetFullName(PlayerData[src])), 'success')
    -- Paired handshake emote, each facing the other.
    TriggerClientEvent('cm-playerdata:client:interactionAnim', from, 'handshake', src)
    TriggerClientEvent('cm-playerdata:client:interactionAnim', src, 'handshake_b', from)
    Audit(src, 'handshake_accept', { with_character_id = GetPublicCharacterId(from) })
end)

exports('KnowPlayerIdentity', function(viewerSrc, targetSrc, reason)
    local ok = MarkIdentityKnown(viewerSrc, targetSrc, reason or 'export')
    if ok then
        SavePlayerData(viewerSrc, 'identity_export')
        PushIdentityUpdate(viewerSrc, targetSrc)
    end
    return ok
end)

exports('SetOrganization', function(src, orgId, orgName)
    local data = PlayerData[src]
    if not data then return false end
    data.metadata = data.metadata or {}
    data.metadata.organization_id = orgId
    data.metadata.organization = orgName or orgId
    data.dirty = true
    return true
end)

exports('SetFamily', function(src, familyId, familyName, identity)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data then return false end
    data.metadata = data.metadata or {}
    data.metadata.family_id = familyId
    data.metadata.family = familyName or familyId
    data.metadata.family_identity = type(identity) == 'table' and identity or nil
    data.dirty = true

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

exports('GetPlayerData', function(src)
    return ClonePlayerData(PlayerData[tonumber(src)])
end)

exports('GetCharacterData', function(src)
    return ClonePlayerData(PlayerData[tonumber(src)])
end)

exports('GetRawPlayerData', function(src)
    -- Internal/server-only compatibility export. Prefer GetPlayerData/GetCharacterData.
    return PlayerData[tonumber(src)]
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
    if not data or (data.wantedStars or 0) ~= ((Config.WantedStars and Config.WantedStars.Max) or 6) then return end
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

exports('SetMetadata', function(src, key, value)
    local data = PlayerData[src]
    if not data then return false end
    data.metadata = data.metadata or {}
    data.metadata[key] = value
    data.dirty = true
    return true
end)

exports('GetMetadata', function(src, key)
    local data = PlayerData[src]
    if not data or not data.metadata then return nil end
    if key == nil then return data.metadata end
    return data.metadata[key]
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
    if not data or not data.loaded then return false end
    data.health = Clamp(health or Config.Vitals.MaxHealth, 0, Config.Vitals.MaxHealth)
    data.dirty = true
    SetState(src, 'health', data.health)
    TriggerClientEvent('cm-playerdata:client:setHealth', src, data.health)
    Audit(src, 'set_health', { health = data.health, reason = reason })
    return true
end)

exports('SetArmor', function(src, armor, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data or not data.loaded then return false end
    data.armor = Clamp(armor or 0, 0, Config.Vitals.MaxArmor)
    data.dirty = true
    SetState(src, 'armor', data.armor)
    PushUpdate(src, 'armor', data.armor)
    Audit(src, 'set_armor', { armor = data.armor, reason = reason })
    return true
end)

exports('Heal', function(src, amountOrPercent, reason)
    src = tonumber(src)
    local data = src and PlayerData[src] or nil
    if not data or not data.loaded then return false end

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
        data.dirty = true
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
    data.dirty = true
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
    if not data or not data.loaded then return false end

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
    data.dirty = true
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
    if not data then return false end

    ResolveAmbulanceRequest(src, data, 'revived')
    data.isDead = false
    data.health = Config.Vitals.MaxHealth
    data.armor = 0
    data.deathDeadline = nil
    data.deathDeadlineAt = nil
    data.ambulanceCalled = false
    data.dieChosen = false
    data.deathReason = nil
    data.dirty = true
    GuardVitalsAfterRevive(data)

    ApplyState(src)
    SyncInventoryDeathState(src, false)
    SavePlayerData(src, 'revive')
    TriggerClientEvent('cm-playerdata:client:revive', src)
    return true
end)

exports('Respawn', function(src, spawnCoords, cost)
    local data = PlayerData[src]
    if not data then return false end

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

    ResolveAmbulanceRequest(src, data, 'hospital_respawn')
    data.isDead = false
    data.health = GetRespawnHealth()
    data.armor = 0
    data.deathDeadline = nil
    data.deathDeadlineAt = nil
    data.ambulanceCalled = false
    data.dieChosen = false
    data.deathReason = nil
    data.dirty = true

    ApplyState(src)
    SyncInventoryDeathState(src, false)
    SavePlayerData(src, 'respawn')
    Audit(src, 'hospital_respawn', {
        health = data.health, cost = cost,
        hospital = hospitalReservation and hospitalReservation.hospitalId or 'fallback',
        bed = hospitalReservation and hospitalReservation.bedId or nil,
    })
    TriggerClientEvent('cm-playerdata:client:respawn', src, spawnCoords, data.health)
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
