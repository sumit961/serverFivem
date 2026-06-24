-- cm-playerdata/server/main.lua
-- Stable v1.3-safe upgrade for your existing CM framework. No hunger/thirst/stress.
-- Uses oxmysql directly to avoid cm-core export call-style issues.

local Config = CMPlayerData.Config
local PlayerData = {}
local LastEventUse = {}

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
    if not ok then
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

local function HasAce(src, ace)
    if src <= 0 then return true end
    return IsPlayerAceAllowed(src, ace) == true
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

local function GetCharId(src)
    local state = Player(src).state
    return state.charId or state.characterId or state.citizenid
end

local function SetState(src, key, value, replicated)
    Player(src).state:set(key, value, replicated ~= false)
end

local function PushUpdate(src, key, value)
    TriggerClientEvent('cm-playerdata:client:update', src, key, value)
end

local function EnsureSchema()
    local alters = {
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS health INT DEFAULT 200",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS armor INT DEFAULT 0",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS is_dead TINYINT(1) DEFAULT 0",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_count INT DEFAULT 0",
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

local function ApplyState(src)
    local data = PlayerData[src]
    if not data then return end

    SetState(src, 'cash', data.cash)
    SetState(src, 'bank', data.bank)
    SetState(src, 'health', data.health)
    SetState(src, 'armor', data.armor)
    SetState(src, 'isDead', data.isDead)
    SetState(src, 'playerDataLoaded', true)
end

local function NotifyLoaded(src)
    local data = PlayerData[src]
    if not data then return end

    ApplyState(src)
    TriggerEvent('cm-playerdata:server:loaded', src, data)
    TriggerClientEvent('cm-playerdata:client:loaded', src, data)
    TriggerEvent('cm-playerdata:server:readyForSpawn', src, data)
end

local function LoadPlayerData(src)
    local charId = GetCharId(src)
    if not charId then
        Debug('Load skipped, charId missing for src=' .. tostring(src))
        return false
    end

    local row = MySQL.single.await([[
        SELECT cash, bank, health, armor, is_dead, death_count, last_position, metadata
        FROM characters
        WHERE id = ?
        LIMIT 1
    ]], { charId })

    if not row then
        Log('error', 'Load failed: character row not found', { src = src, charId = charId })
        return false
    end

    local defaults = Config.Defaults

    PlayerData[src] = {
        src = src,
        charId = charId,

        cash = tonumber(row.cash) or defaults.cash,
        bank = tonumber(row.bank) or defaults.bank,

        health = Clamp(row.health or defaults.health, 0, Config.Vitals.MaxHealth),
        armor = Clamp(row.armor or defaults.armor, 0, Config.Vitals.MaxArmor),

        isDead = (tonumber(row.is_dead) or 0) == 1,
        deathCount = tonumber(row.death_count) or defaults.death_count,
        lastPosition = DecodeJson(row.last_position),
        metadata = DecodeJson(row.metadata) or {},

        loaded = true,
        dirty = false,
        lastVitalsSync = GetGameTimer()
    }

    Debug(('Loaded src=%s char=%s HP=%s dead=%s'):format(
        src, charId, PlayerData[src].health, tostring(PlayerData[src].isDead)
    ))

    NotifyLoaded(src)
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
    PlayerData[src] = nil
    pcall(function()
        local state = Player(src).state
        state:set('cash', nil, true)
        state:set('bank', nil, true)
        state:set('health', nil, true)
        state:set('armor', nil, true)
        state:set('isDead', nil, true)
        state:set('playerDataLoaded', nil, true)
    end)
    ClearRateLimits(src)
end

local function SetMoney(src, account, value, reason)
    local data = PlayerData[src]
    if not data or (account ~= 'cash' and account ~= 'bank') then return false end

    data[account] = math.max(0, math.floor(tonumber(value) or 0))
    data.dirty = true

    SetState(src, account, data[account])
    PushUpdate(src, account, data[account])
    Audit(src, 'set_' .. account, { amount = data[account], reason = reason })
    return true
end

local function AddMoney(src, account, amount, reason)
    local data = PlayerData[src]
    amount = math.floor(tonumber(amount) or 0)
    if not data or amount <= 0 then return false end
    if account ~= 'cash' and account ~= 'bank' then return false end
    return SetMoney(src, account, data[account] + amount, reason or 'add_money')
end

local function RemoveMoney(src, account, amount, reason)
    local data = PlayerData[src]
    amount = math.floor(tonumber(amount) or 0)
    if not data or amount <= 0 then return false end
    if account ~= 'cash' and account ~= 'bank' then return false end
    if data[account] < amount then return false end
    return SetMoney(src, account, data[account] - amount, reason or 'remove_money')
end

local function SetDead(src, isDead, reason)
    local data = PlayerData[src]
    if not data then return false end

    data.isDead = isDead == true
    if data.isDead then
        data.health = 0
        data.armor = 0
        data.deathCount = (data.deathCount or 0) + 1
    end
    data.dirty = true

    ApplyState(src)
    Audit(src, data.isDead and 'death' or 'revive', { reason = reason })
    SavePlayerData(src, reason or (data.isDead and 'death' or 'revive'))
    return true
end

-- ============================================================
-- Events
-- ============================================================

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(500)
    EnsureSchema()
    Log('info', 'CM PlayerData v1.3-safe started')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for src, data in pairs(PlayerData) do
        if data and data.loaded then
            SavePlayerData(src, 'resource_stop')
        end
    end
end)

AddEventHandler('cm-core:characterLoaded', function(src)
    SetTimeout(500, function()
        LoadPlayerData(src)
    end)
end)

RegisterNetEvent('cm-playerdata:server:load', function()
    LoadPlayerData(source)
end)

AddEventHandler('playerDropped', function()
    local src = source
    SavePlayerData(src, 'drop')
    ClearPlayerData(src)
end)

RegisterNetEvent('cm-playerdata:server:updatePosition', function(coords)
    local src = source
    if not RateLimit(src, 'position', 1000) then return end
    local data = PlayerData[src]
    if not data or type(coords) ~= 'table' then return end

    local x, y, z, h = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z), tonumber(coords.h)
    if not x or not y or not z then return end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or z < -500 or z > 2000 then return end

    data.lastPosition = {
        x = math.floor(x * 100) / 100,
        y = math.floor(y * 100) / 100,
        z = math.floor(z * 100) / 100,
        h = math.floor((h or 0.0) * 100) / 100
    }
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
    local maxPassiveHeal = Config.Vitals.MaxPassiveHealDelta or 5
    if nextHealth > previousHealth + maxPassiveHeal then
        nextHealth = previousHealth
    end

    -- Prefer server-observed ped health when available and lower than the client value.
    if serverHealth and serverHealth < nextHealth then
        nextHealth = Clamp(serverHealth, 0, Config.Vitals.MaxHealth)
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

RegisterNetEvent('cm-playerdata:server:playerDied', function(killerSrc, weaponHash)
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

    SetDead(src, true, 'death')
    TriggerClientEvent('cm-playerdata:client:playerDied', src, killerSrc, weaponHash)

    SetTimeout(Config.Respawn.Time, function()
        if PlayerData[src] and PlayerData[src].isDead then
            TriggerClientEvent('cm-playerdata:client:canRespawn', src)
        end
    end)
end)

RegisterNetEvent('cm-playerdata:server:requestRespawn', function()
    local src = source
    if not RateLimit(src, 'respawn', 2000) then return end
    local data = PlayerData[src]
    if not data or not data.isDead then return end
    exports['cm-playerdata']:Respawn(src)
end)

-- ============================================================
-- Exports
-- ============================================================

exports('Load', LoadPlayerData)
exports('Save', SavePlayerData)

exports('GetPlayerData', function(src)
    return PlayerData[src]
end)

exports('IsLoaded', function(src)
    return PlayerData[src] and PlayerData[src].loaded == true or false
end)

exports('GetCash', function(src)
    return PlayerData[src] and PlayerData[src].cash or 0
end)

exports('GetBank', function(src)
    return PlayerData[src] and PlayerData[src].bank or 0
end)

exports('GetMoney', function(src, account)
    if not PlayerData[src] then return 0 end
    return PlayerData[src][account] or 0
end)

exports('SetMoney', SetMoney)
exports('AddMoney', AddMoney)
exports('RemoveMoney', RemoveMoney)

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

exports('SetDead', SetDead)

exports('Revive', function(src)
    local data = PlayerData[src]
    if not data then return false end

    data.isDead = false
    data.health = Config.Vitals.MaxHealth
    data.armor = 0
    data.dirty = true

    ApplyState(src)
    SavePlayerData(src, 'revive')
    TriggerClientEvent('cm-playerdata:client:revive', src)
    return true
end)

exports('Respawn', function(src, spawnCoords, cost)
    local data = PlayerData[src]
    if not data then return false end

    spawnCoords = spawnCoords or Config.Respawn.HospitalSpawn
    cost = tonumber(cost or Config.Respawn.Cost) or 0

    if cost > 0 then
        if data.bank >= cost then
            RemoveMoney(src, 'bank', cost, 'hospital_respawn')
        else
            local remaining = cost - data.bank
            if data.bank > 0 then RemoveMoney(src, 'bank', data.bank, 'hospital_respawn') end
            if remaining > 0 then
                data.cash = math.max(0, data.cash - remaining)
                data.dirty = true
                SetState(src, 'cash', data.cash)
                PushUpdate(src, 'cash', data.cash)
                Audit(src, 'remove_cash', { amount = remaining, reason = 'hospital_respawn' })
            end
        end
    end

    data.isDead = false
    data.health = Config.Vitals.MaxHealth
    data.armor = 0
    data.dirty = true

    ApplyState(src)
    SavePlayerData(src, 'respawn')
    TriggerClientEvent('cm-playerdata:client:respawn', src, spawnCoords)
    return true
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

RegisterCommand('cash', function(src, args)
    if src <= 0 then
        print('[CM-PLAYERDATA] Use in F8: cash 5000')
        return
    end

    if not HasAce(src, 'cm-playerdata.cash') then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = 'You do not have permission to use this command.'
        })
        return
    end

    local amount = tonumber(args[1]) or 5000
    local ok = exports['cm-playerdata']:AddCash(src, amount, 'dev_cash_command')

    if ok then
        print(('[CM-PLAYERDATA] Added $%s cash to player %s'):format(amount, src))
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            description = ('Added $%s cash'):format(amount)
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = 'Cash add failed. PlayerData not loaded.'
        })
    end
end, false)
