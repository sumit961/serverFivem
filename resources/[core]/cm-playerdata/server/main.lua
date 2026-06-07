local PlayerData = {}

local function Debug(msg)
    print('[CM-PLAYERDATA] ' .. msg)
end

-- ============================================================
-- LOAD
-- ============================================================
local function LoadPlayerData(src)
    local charId = Player(src).state.charId
    if not charId then
        Debug('SKIP load: charId state bag missing for src=' .. tostring(src))
        return false
    end

    local ok, result = pcall(function()
        return exports['cm-core']:Query(
            'SELECT * FROM characters WHERE id = ? LIMIT 1',
            {charId}
        )
    end)

    if not ok then
        Debug('DB ERROR loading charId=' .. tostring(charId) .. ' | ' .. tostring(result))
        return false
    end

    if not result or #result == 0 then
        Debug('No DB row for charId=' .. tostring(charId))
        return false
    end

    local row = result[1]

    -- Decode JSON safely
    local appearance = {}
    if row.appearance_json and row.appearance_json ~= '' then
        local dOk, dVal = pcall(json.decode, row.appearance_json)
        if dOk then appearance = dVal end
    end

    local lastPos = nil
    if row.last_position and row.last_position ~= '' then
        local dOk, dVal = pcall(json.decode, row.last_position)
        if dOk then lastPos = dVal end
    end

    PlayerData[src] = {
        src          = src,
        charId       = charId,
        accountId    = row.account_id,
        firstName    = row.first_name,
        lastName     = row.last_name,
        dob          = row.dob,
        gender       = row.gender,
        cash         = tonumber(row.cash) or 0,
        bank         = tonumber(row.bank) or 0,
        lastPosition = lastPos,
        appearance   = appearance,
        loaded       = true,
    }

    -- Sync to state bags (client + other resources can read instantly)
    Player(src).state.cash = PlayerData[src].cash
    Player(src).state.bank = PlayerData[src].bank
    Player(src).state.playerDataLoaded = true

    Debug('LOADED src=' .. src ..
          ' | ' .. PlayerData[src].firstName .. ' ' .. PlayerData[src].lastName ..
          ' | Cash:$' .. PlayerData[src].cash .. ' Bank:$' .. PlayerData[src].bank)

    TriggerEvent('cm-playerdata:server:loaded', src, PlayerData[src])
    TriggerClientEvent('cm-playerdata:client:loaded', src, PlayerData[src])
    return true
end

-- ============================================================
-- SAVE
-- ============================================================
local function SavePlayerData(src, reason)
    local data = PlayerData[src]
    if not data or not data.loaded then return false end

    local posJson = data.lastPosition and json.encode(data.lastPosition) or nil

    local ok, err = pcall(function()
        exports['cm-core']:Query(
            'UPDATE characters SET cash = ?, bank = ?, last_position = ? WHERE id = ?',
            {data.cash, data.bank, posJson, data.charId}
        )
    end)

    if not ok then
        Debug('SAVE FAILED src=' .. tostring(src) .. ' reason=' .. tostring(reason) .. ' | ' .. tostring(err))
        return false
    end

    Debug('SAVED src=' .. tostring(src) .. ' reason=' .. tostring(reason))

    if reason == 'drop' then
        PlayerData[src] = nil
        Player(src).state.cash = nil
        Player(src).state.bank = nil
        Player(src).state.playerDataLoaded = nil
    end
    return true
end

-- ============================================================
-- EVENTS
-- ============================================================

-- Triggered by cm-core after character is fully ready
AddEventHandler('cm-core:characterLoaded', function(src)
    if type(src) ~= 'number' then src = tonumber(src) end
    if not src then return end
    -- Small delay so state bags are guaranteed replicated
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
end)

-- ============================================================
-- EXPORTS (Other resources use these)
-- ============================================================

-- Get full data table
exports('GetPlayerData', function(src)
    return PlayerData[src] or nil
end)

-- Get one key
exports('GetPlayerDataByKey', function(src, key)
    if not PlayerData[src] then return nil end
    return PlayerData[src][key]
end)

-- Set any key + notify client
exports('SetPlayerData', function(src, key, value)
    if not PlayerData[src] then return false end
    PlayerData[src][key] = value
    if type(value) == 'number' or type(value) == 'string' or type(value) == 'boolean' then
        Player(src).state[key] = value
    end
    TriggerClientEvent('cm-playerdata:client:update', src, key, value)
    return true
end)

-- CASH
exports('GetCash', function(src)
    return PlayerData[src] and PlayerData[src].cash or 0
end)

exports('AddCash', function(src, amount)
    if not PlayerData[src] or not amount or amount <= 0 then return false end
    PlayerData[src].cash = PlayerData[src].cash + amount
    Player(src).state.cash = PlayerData[src].cash
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', PlayerData[src].cash)
    Debug('AddCash $' .. amount .. ' -> $' .. PlayerData[src].cash .. ' src=' .. src)
    return true
end)

exports('RemoveCash', function(src, amount)
    if not PlayerData[src] or not amount or amount <= 0 then return false end
    if PlayerData[src].cash < amount then return false end
    PlayerData[src].cash = PlayerData[src].cash - amount
    Player(src).state.cash = PlayerData[src].cash
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', PlayerData[src].cash)
    Debug('RemoveCash $' .. amount .. ' -> $' .. PlayerData[src].cash .. ' src=' .. src)
    return true
end)

-- BANK
exports('GetBank', function(src)
    return PlayerData[src] and PlayerData[src].bank or 0
end)

exports('AddBank', function(src, amount)
    if not PlayerData[src] or not amount or amount <= 0 then return false end
    PlayerData[src].bank = PlayerData[src].bank + amount
    Player(src).state.bank = PlayerData[src].bank
    TriggerClientEvent('cm-playerdata:client:update', src, 'bank', PlayerData[src].bank)
    Debug('AddBank $' .. amount .. ' -> $' .. PlayerData[src].bank .. ' src=' .. src)
    return true
end)

exports('RemoveBank', function(src, amount)
    if not PlayerData[src] or not amount or amount <= 0 then return false end
    if PlayerData[src].bank < amount then return false end
    PlayerData[src].bank = PlayerData[src].bank - amount
    Player(src).state.bank = PlayerData[src].bank
    TriggerClientEvent('cm-playerdata:client:update', src, 'bank', PlayerData[src].bank)
    Debug('RemoveBank $' .. amount .. ' -> $' .. PlayerData[src].bank .. ' src=' .. src)
    return true
end)

-- POSITION
exports('SetLastPosition', function(src, coords)
    if not PlayerData[src] or not coords then return false end
    PlayerData[src].lastPosition = coords
    return true
end)

exports('GetLastPosition', function(src)
    return PlayerData[src] and PlayerData[src].lastPosition or nil
end)

-- MANUAL SAVE
exports('Save', function(src)
    return SavePlayerData(src, 'manual')
end)

exports('IsLoaded', function(src)
    return PlayerData[src] and PlayerData[src].loaded == true
end)

-- ============================================================
-- AUTO-SAVE LOOP (every 5 min)
-- ============================================================
CreateThread(function()
    Wait(15000)
    while true do
        Wait(5 * 60 * 1000)
        local count = 0
        for src, data in pairs(PlayerData) do
            if data.loaded then
                SavePlayerData(src, 'auto')
                count = count + 1
            end
        end
        if count > 0 then Debug('Auto-saved ' .. count .. ' players') end
    end
end)

-- ============================================================
-- ADMIN COMMAND
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

Debug('Server module initialized')