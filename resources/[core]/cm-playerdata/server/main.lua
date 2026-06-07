-- cm-playerdata/server/main.lua

local PlayerData = {}

local Config = {
    FullSaveInterval = 3 * 60 * 1000,  -- 3 minutes (cash, health, death, etc.)
    PosSaveInterval  = 10 * 1000,       -- 10 seconds (position only, lightweight)
    RespawnTime      = 30000,
    RespawnCost      = 500,
    HospitalSpawn    = {x = 341.0, y = -1397.0, z = 33.0, h = 50.0}
}

local function Debug(msg)
    print('[CM-PLAYERDATA] ' .. msg)
end

-- ============================================================
-- LOAD
-- ============================================================
local function LoadPlayerData(src)
    local charId = Player(src).state.charId
    if not charId then
        Debug('SKIP load: charId missing for src=' .. tostring(src))
        return false
    end

    local ok, rows = pcall(function()
        return exports['cm-core']:Query([[
            SELECT cash, bank, health, armor, is_dead, death_count, last_position
            FROM characters WHERE id = ? LIMIT 1
        ]], {charId})
    end)

    if not ok or not rows or #rows == 0 then
        Debug('LOAD FAIL src=' .. tostring(src) .. ' err=' .. tostring(rows))
        return false
    end

    local r = rows[1]

    local lastPos = nil
    if r.last_position and r.last_position ~= '' then
        local dOk, dVal = pcall(json.decode, r.last_position)
        if dOk then lastPos = dVal end
    end

    PlayerData[src] = {
        src          = src,
        charId       = charId,
        cash         = tonumber(r.cash) or 0,
        bank         = tonumber(r.bank) or 0,
        health       = tonumber(r.health) or 200,
        armor        = tonumber(r.armor) or 0,
        isDead       = (tonumber(r.is_dead) or 0) == 1,
        deathCount   = tonumber(r.death_count) or 0,
        lastPosition = lastPos,
        loaded       = true,
    }

    local state = Player(src).state
    state.cash         = PlayerData[src].cash
    state.bank         = PlayerData[src].bank
    state.health       = PlayerData[src].health
    state.armor        = PlayerData[src].armor
    state.isDead       = PlayerData[src].isDead
    state.playerDataLoaded = true

    Debug('LOADED src=' .. src .. ' HP=' .. PlayerData[src].health .. ' Dead=' .. tostring(PlayerData[src].isDead))

    TriggerEvent('cm-playerdata:server:loaded', src, PlayerData[src])
    TriggerClientEvent('cm-playerdata:client:loaded', src, PlayerData[src])
    TriggerEvent('cm-playerdata:server:readyForSpawn', src, PlayerData[src])
    return true
end

-- ============================================================
-- SAVE (full - all fields)
-- ============================================================
local function SavePlayerData(src, reason)
    local data = PlayerData[src]
    if not data or not data.loaded then return false end

    local posJson = data.lastPosition and json.encode(data.lastPosition) or nil

    local ok, err = pcall(function()
        exports['cm-core']:Query([[
            UPDATE characters SET
                cash = ?, bank = ?, health = ?, armor = ?, is_dead = ?,
                death_count = ?, last_position = ?
            WHERE id = ?
        ]], {
            data.cash, data.bank, data.health, data.armor, data.isDead and 1 or 0,
            data.deathCount, posJson, data.charId
        })
    end)

    if not ok then
        Debug('SAVE FAIL src=' .. tostring(src) .. ' reason=' .. tostring(reason) .. ' | ' .. tostring(err))
        return false
    end

    Debug('SAVED src=' .. tostring(src) .. ' reason=' .. tostring(reason))

    if reason == 'drop' then
        PlayerData[src] = nil
        local state = Player(src).state
        state.cash = nil; state.bank = nil; state.health = nil
        state.armor = nil; state.isDead = nil; state.playerDataLoaded = nil
    end
    return true
end

local function SavePositionOnly(src)
    local data = PlayerData[src]
    if not data or not data.loaded or not data.lastPosition then return false end

    local ok, err = pcall(function()
        exports['cm-core']:Query(
            'UPDATE characters SET last_position = ? WHERE id = ?',
            {json.encode(data.lastPosition), data.charId}
        )
    end)
    return ok
end

-- ============================================================
-- SECURE SERVER SYNC EVENTS
-- ============================================================
AddEventHandler('cm-core:characterLoaded', function(src, charId)
    SetTimeout(500, function() LoadPlayerData(src) end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    SavePlayerData(src, 'drop')
end)

RegisterNetEvent('cm-playerdata:server:updatePosition', function(coords)
    local src = source
    if not coords or not PlayerData[src] then return end
    PlayerData[src].lastPosition = coords
end)

-- Secure Sync: Client reports engine vitals to server memory
RegisterNetEvent('cm-playerdata:server:syncVitals', function(clientHealth, clientArmor)
    local src = source
    local data = PlayerData[src]
    if not data or data.isDead then return end

    -- Server-side bounds protection validation filtering
    data.health = math.clamp(clientHealth or 200, 0, 200)
    data.armor  = math.clamp(clientArmor or 0, 0, 100)

    local state = Player(src).state
    state.health = data.health
    state.armor  = data.armor
end)

-- Client reports engine-level death vector detection
RegisterNetEvent('cm-playerdata:server:playerDied', function(killerSrc, weaponHash)
    local src = source
    local data = PlayerData[src]
    if not data or data.isDead then return end

    data.isDead = true
    data.health = 0
    data.armor = 0
    data.deathCount = data.deathCount + 1

    local state = Player(src).state
    state.isDead = true
    state.health = 0
    state.armor = 0

    SavePlayerData(src, 'death')

    TriggerClientEvent('cm-playerdata:client:playerDied', src, killerSrc, weaponHash)

    SetTimeout(Config.RespawnTime, function()
        if PlayerData[src] and PlayerData[src].isDead then
            TriggerClientEvent('cm-playerdata:client:canRespawn', src)
        end
    end)
end)

RegisterNetEvent('cm-playerdata:server:requestRespawn', function()
    local src = source
    if not PlayerData[src] or not PlayerData[src].isDead then return end
    exports['cm-playerdata']:Respawn(src)
end)

-- ============================================================
-- FRAMEWORK BUSINESS EXPORTS: FINANCES
-- ============================================================
exports('GetCash', function(src)
    return PlayerData[src] and PlayerData[src].cash or 0
end)

exports('GetBank', function(src)
    return PlayerData[src] and PlayerData[src].bank or 0
end)

exports('AddCash', function(src, amount)
    if not amount or amount <= 0 or not PlayerData[src] then return false end
    PlayerData[src].cash = PlayerData[src].cash + amount
    Player(src).state.cash = PlayerData[src].cash
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', PlayerData[src].cash)
    return true
end)

exports('RemoveCash', function(src, amount)
    if not amount or amount <= 0 or not PlayerData[src] or PlayerData[src].cash < amount then return false end
    PlayerData[src].cash = PlayerData[src].cash - amount
    Player(src).state.cash = PlayerData[src].cash
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', PlayerData[src].cash)
    return true
end)

-- ============================================================
-- FRAMEWORK BUSINESS EXPORTS: RECOVERY & RESPAWN
-- ============================================================
exports('Respawn', function(src, spawnCoords, cost)
    local data = PlayerData[src]
    if not data then return false end

    spawnCoords = spawnCoords or Config.HospitalSpawn
    cost = cost or Config.RespawnCost

    if data.bank >= cost then
        data.bank = data.bank - cost
    else
        data.cash = math.max(0, data.cash - cost)
    end

    data.isDead = false
    data.health = 200
    data.armor = 0

    local state = Player(src).state
    state.isDead = false; state.health = 200; state.armor = 0
    state.bank = data.bank; state.cash = data.cash

    SavePlayerData(src, 'respawn')
    TriggerClientEvent('cm-playerdata:client:respawn', src, spawnCoords)
    return true
end)

-- ============================================================
-- EXPORTS: FRAMEWORK UTILITIES
-- ============================================================
exports('IsLoaded', function(src)
    return PlayerData[src] and PlayerData[src].loaded == true or false
end)

-- Helper utility mapping logic bounds safely
function math.clamp(val, lower, upper)
    if lower > upper then lower, upper = upper, lower end
    return math.max(lower, math.min(upper, val))
end

-- Loops
CreateThread(function()
    while true do
        Wait(Config.FullSaveInterval)
        for src, data in pairs(PlayerData) do
            if data.loaded then SavePlayerData(src, 'auto') end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.PosSaveInterval)
        for src, data in pairs(PlayerData) do
            if data.loaded and data.lastPosition then SavePositionOnly(src) end
        end
    end
end)