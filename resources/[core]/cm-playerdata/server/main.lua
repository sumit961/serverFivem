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

    Debug('LOADED src=' .. src .. ' HP=' .. PlayerData[src].health .. ' Dead=' .. tostring(PlayerData[src].isDead) ..
          ' $' .. PlayerData[src].cash .. '/$' .. PlayerData[src].bank .. ' Pos=' .. tostring(r.last_position))

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

-- ============================================================
-- SAVE POSITION ONLY (lightweight, frequent)
-- ============================================================
local function SavePositionOnly(src)
    local data = PlayerData[src]
    if not data or not data.loaded or not data.lastPosition then return false end

    local ok, err = pcall(function()
        exports['cm-core']:Query(
            'UPDATE characters SET last_position = ? WHERE id = ?',
            {json.encode(data.lastPosition), data.charId}
        )
    end)

    if ok then
        Debug('POS-SAVED src=' .. src .. ' pos=' .. json.encode(data.lastPosition))
        return true
    else
        Debug('POS-SAVE FAIL src=' .. src .. ' | ' .. tostring(err))
        return false
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
AddEventHandler('cm-core:characterLoaded', function(src, charId)
    SetTimeout(500, function()
        LoadPlayerData(src)
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    SavePlayerData(src, 'drop')
end)

-- Client sends position every 30s
RegisterNetEvent('cm-playerdata:server:updatePosition', function(coords)
    local src = source
    if not coords or not PlayerData[src] then return end
    PlayerData[src].lastPosition = coords
    -- Don't print every update to avoid log spam
end)

-- Client reports health/armor every 30s (if alive)
RegisterNetEvent('cm-playerdata:server:updateHealth', function(health, armor)
    local src = source
    local data = PlayerData[src]
    if not data or data.isDead then return end
    if type(health) == 'number' and health > 100 then
        data.health = health
        data.armor = armor or 0
        Player(src).state.health = data.health
        Player(src).state.armor = data.armor
    end
end)

-- Client reports death
RegisterNetEvent('cm-playerdata:server:playerDied', function(killerSrc, weaponHash)
    local src = source
    
    if not src or src <= 0 then
        Debug('DEATH FAIL: Invalid source')
        return
    end
    
    local data = PlayerData[src]
    
    if not data then
        Debug('Death reported but data not loaded for src=' .. tostring(src) .. '. Attempting load...')
        local loaded = LoadPlayerData(src)
        if not loaded then
            Debug('DEATH FAIL: Cannot load data for src=' .. tostring(src))
            return
        end
        data = PlayerData[src]
    end
    
    if not data then
        Debug('DEATH FAIL: Still no data after load for src=' .. tostring(src))
        return
    end
    
    if data.isDead then
        Debug('Already dead, ignoring duplicate death for src=' .. tostring(src))
        return
    end

    data.isDead = true
    data.health = 0
    data.armor = 0
    data.deathCount = data.deathCount + 1

    Player(src).state.isDead = true
    Player(src).state.health = 0
    Player(src).state.armor = 0

    SavePlayerData(src, 'death')

    exports['cm-core']:Log('cm-playerdata', 'WARN', 'Player died', {
        src = src, charId = data.charId, killer = killerSrc,
        weapon = weaponHash, totalDeaths = data.deathCount
    })

    TriggerEvent('cm-playerdata:server:playerDied', src, killerSrc, weaponHash)
    TriggerClientEvent('cm-playerdata:client:playerDied', src, killerSrc, weaponHash)

    SetTimeout(Config.RespawnTime, function()
        if PlayerData[src] and PlayerData[src].isDead then
            TriggerClientEvent('cm-playerdata:client:canRespawn', src)
        end
    end)

    Debug('DEAD src=' .. src .. ' deaths=' .. data.deathCount)
end)

-- Client requests respawn
RegisterNetEvent('cm-playerdata:server:requestRespawn', function()
    local src = source
    Debug('Respawn requested by src=' .. tostring(src))
    
    if not PlayerData[src] then
        Debug('RESPAWN FAIL: No data for src=' .. tostring(src))
        return
    end
    
    if not PlayerData[src].isDead then
        Debug('RESPAWN FAIL: Player not dead src=' .. tostring(src))
        return
    end
    
    local success = exports['cm-playerdata']:Respawn(src)
    Debug('Respawn result for src=' .. tostring(src) .. ': ' .. tostring(success))
end)

-- ============================================================
-- EXPORTS: CASH / BANK
-- ============================================================
exports('GetCash', function(src)
    return PlayerData[src] and PlayerData[src].cash or 0
end)

exports('GetBank', function(src)
    return PlayerData[src] and PlayerData[src].bank or 0
end)

exports('AddCash', function(src, amount)
    if not amount or amount <= 0 then return false end
    local data = PlayerData[src]
    if not data then return false end
    data.cash = data.cash + amount
    Player(src).state.cash = data.cash
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', data.cash)
    Debug('AddCash $' .. amount .. ' -> $' .. data.cash .. ' src=' .. src)
    return true
end)

exports('RemoveCash', function(src, amount)
    if not amount or amount <= 0 then return false end
    local data = PlayerData[src]
    if not data or data.cash < amount then return false end
    data.cash = data.cash - amount
    Player(src).state.cash = data.cash
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', data.cash)
    Debug('RemoveCash $' .. amount .. ' -> $' .. data.cash .. ' src=' .. src)
    return true
end)

exports('AddBank', function(src, amount)
    if not amount or amount <= 0 then return false end
    local data = PlayerData[src]
    if not data then return false end
    data.bank = data.bank + amount
    Player(src).state.bank = data.bank
    TriggerClientEvent('cm-playerdata:client:update', src, 'bank', data.bank)
    Debug('AddBank $' .. amount .. ' -> $' .. data.bank .. ' src=' .. src)
    return true
end)

exports('RemoveBank', function(src, amount)
    if not amount or amount <= 0 then return false end
    local data = PlayerData[src]
    if not data or data.bank < amount then return false end
    data.bank = data.bank - amount
    Player(src).state.bank = data.bank
    TriggerClientEvent('cm-playerdata:client:update', src, 'bank', data.bank)
    Debug('RemoveBank $' .. amount .. ' -> $' .. data.bank .. ' src=' .. src)
    return true
end)

-- ============================================================
-- EXPORTS: HEALTH / DEATH
-- ============================================================
exports('GetHealth', function(src)
    local data = PlayerData[src]
    if not data then return nil end
    return {health = data.health, armor = data.armor, isDead = data.isDead}
end)

exports('IsDead', function(src)
    return PlayerData[src] and PlayerData[src].isDead or false
end)

exports('SetHealth', function(src, health, armor)
    local data = PlayerData[src]
    if not data then return false end
    data.health = health or 200
    data.armor = armor or 0
    Player(src).state.health = data.health
    Player(src).state.armor = data.armor
    TriggerClientEvent('cm-playerdata:client:setHealth', src, data.health, data.armor)
    SavePlayerData(src, 'set-health')
    return true
end)

exports('Heal', function(src, amount)
    local data = PlayerData[src]
    if not data or data.isDead then return false end
    data.health = math.min(200, data.health + amount)
    Player(src).state.health = data.health
    TriggerClientEvent('cm-playerdata:client:setHealth', src, data.health, data.armor)
    return true
end)

exports('Damage', function(src, amount)
    local data = PlayerData[src]
    if not data or data.isDead then return false end
    data.health = math.max(0, data.health - amount)
    Player(src).state.health = data.health
    TriggerClientEvent('cm-playerdata:client:setHealth', src, data.health, data.armor)
    if data.health <= 0 then
        data.isDead = true
        data.health = 0
        data.armor = 0
        data.deathCount = data.deathCount + 1
        Player(src).state.isDead = true
        SavePlayerData(src, 'death-zero')
        TriggerClientEvent('cm-playerdata:client:playerDied', src, nil, nil)
    end
    return true
end)

exports('Revive', function(src)
    local data = PlayerData[src]
    if not data or not data.isDead then return false end
    data.isDead = false
    data.health = 200
    data.armor = 0
    Player(src).state.isDead = false
    Player(src).state.health = 200
    Player(src).state.armor = 0
    SavePlayerData(src, 'revive')
    TriggerClientEvent('cm-playerdata:client:revive', src, 'system')
    return true
end)

exports('Respawn', function(src, spawnCoords, cost)
    local data = PlayerData[src]
    if not data then 
        Debug('RESPAWN FAIL: No data for src=' .. tostring(src))
        return false 
    end

    spawnCoords = spawnCoords or Config.HospitalSpawn
    cost = cost or Config.RespawnCost

    if cost > 0 then
        if data.bank >= cost then
            data.bank = data.bank - cost
            Player(src).state.bank = data.bank
            TriggerClientEvent('cm-playerdata:client:update', src, 'bank', data.bank)
        else
            data.cash = data.cash - cost
            Player(src).state.cash = data.cash
            TriggerClientEvent('cm-playerdata:client:update', src, 'cash', data.cash)
        end
    end

    data.isDead = false
    data.health = 200
    data.armor = 0
    Player(src).state.isDead = false
    Player(src).state.health = 200
    Player(src).state.armor = 0

    SavePlayerData(src, 'respawn')

    TriggerClientEvent('cm-playerdata:client:respawn', src, spawnCoords)
    TriggerEvent('cm-playerdata:server:playerRespawned', src, spawnCoords)

    Debug('RESPAWNED src=' .. src .. ' cost=$' .. cost)
    return true
end)

exports('GetDeathCount', function(src)
    return PlayerData[src] and PlayerData[src].deathCount or 0
end)

-- ============================================================
-- EXPORTS: POSITION
-- ============================================================
exports('GetLastPosition', function(src)
    return PlayerData[src] and PlayerData[src].lastPosition or nil
end)

exports('SetLastPosition', function(src, coords)
    local data = PlayerData[src]
    if not data then return false end
    data.lastPosition = coords
    return true
end)

-- ============================================================
-- EXPORTS: UTILS
-- ============================================================
exports('IsLoaded', function(src)
    return PlayerData[src] and PlayerData[src].loaded == true
end)

exports('Save', function(src)
    return SavePlayerData(src, 'manual')
end)

-- ============================================================
-- AUTO-SAVE: FULL DATA (every 3 min)
-- ============================================================
CreateThread(function()
    Wait(20000)
    while true do
        Wait(Config.FullSaveInterval)
        local count = 0
        for src, data in pairs(PlayerData) do
            if data.loaded then
                SavePlayerData(src, 'auto')
                count = count + 1
            end
        end
        if count > 0 then Debug('Auto-saved ' .. count .. ' players (full)') end
    end
end)

-- ============================================================
-- AUTO-SAVE: POSITION ONLY (every 10 sec)
-- ============================================================
CreateThread(function()
    Wait(10000)
    while true do
        Wait(Config.PosSaveInterval)
        for src, data in pairs(PlayerData) do
            if data.loaded and data.lastPosition then
                SavePositionOnly(src)
            end
        end
    end
end)

-- ============================================================
-- ADMIN COMMANDS
-- ============================================================
RegisterCommand('saveallplayers', function(source, args, raw)
    local adminSrc = source
    local count = 0
    for src, data in pairs(PlayerData) do
        if data.loaded then
            SavePlayerData(src, 'admin-cmd')
            count = count + 1
        end
    end
    Debug('Admin (' .. tostring(adminSrc) .. ') saved ' .. count .. ' players')
    if adminSrc > 0 then
        TriggerClientEvent('chat:addMessage', adminSrc, {
            color = {0, 255, 0},
            args = {'[CM-PLAYERDATA]', 'Saved ' .. count .. ' players to database.'}
        })
    end
end, true)

-- TEMP: Check saved position
RegisterCommand('checkmyloc', function(source)
    local src = source
    local charId = Player(src).state.charId
    if not charId then 
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            args = {'[CM-PLAYERDATA]', 'Not logged in!'}
        })
        return 
    end
    
    local row = exports['cm-core']:Query('SELECT last_position FROM characters WHERE id = ?', {charId})
    if row and #row > 0 then
        local pos = row[1].last_position or 'NOT SET'
        print('[CM-PLAYERDATA] Saved position for src=' .. src .. ': ' .. tostring(pos))
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 255, 0},
            args = {'[CM-PLAYERDATA]', 'DB Position: ' .. tostring(pos)}
        })
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            args = {'[CM-PLAYERDATA]', 'No position found in DB!'}
        })
    end
end, false)

Debug('Server initialized | v1.0.0')