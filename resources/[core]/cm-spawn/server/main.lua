-- cm-spawn/server/main.lua

local PendingSpawns = {}

local function GetSpawnByKey(key)
    for _, spawn in ipairs(SpawnPoints) do
        if spawn.key == key then return spawn end
    end
    return nil
end

local function IsHasSpawned(value)
    -- oxmysql/MySQL can return TINYINT as number, string, or boolean depending on config.
    -- Treat only real 0/nil/false as first-time. Everything representing 1 is returning player.
    if value == true then return true end
    if value == false or value == nil then return false end
    local n = tonumber(value)
    if n ~= nil then return n == 1 end
    local text = tostring(value):lower()
    return text == '1' or text == 'true' or text == 'yes'
end

local function ensureHasSpawnedColumn()
    pcall(function()
        exports['cm-core']:Query('ALTER TABLE characters ADD COLUMN IF NOT EXISTS has_spawned TINYINT(1) NOT NULL DEFAULT 0')
    end)
end

CreateThread(function()
    Wait(1000)
    ensureHasSpawnedColumn()
end)

local function markSpawned(charId)
    if not charId then return end
    pcall(function()
        exports['cm-core']:Query('UPDATE characters SET has_spawned = 1 WHERE id = ?', {charId})
    end)
end

local function resetPlayerWorldState(src, complete)
    src = tonumber(src)
    if not src or src <= 0 then return end

    -- Bucket 0 is the main live world. Character selector uses private buckets,
    -- so forgetting this reset makes players unable to hit/interact with each other.
    SetPlayerRoutingBucket(src, 0)

    local ply = Player(src)
    if ply and ply.state then
        ply.state:set('selectorBucket', 0, true)
        ply.state:set('isInCharacterSelector', false, true)

        if complete == true then
            -- Now the ped is visible/controllable at the final spawn, so position saving can resume.
            ply.state:set('characterFullySpawned', true, true)
            ply.state:set('skipPositionSave', false, true)
            ply.state:set('cmSpawnActive', false, true)
        else
            -- During teleport/camera we keep saving blocked so selector/transition coords are not stored.
            ply.state:set('characterFullySpawned', false, true)
            ply.state:set('skipPositionSave', true, true)
            ply.state:set('cmSpawnActive', true, true)
        end
    end
end

AddEventHandler('cm-core:characterLoaded', function(src, charId)
    print('[CM-SPAWN] characterLoaded for src=' .. tostring(src) .. ' charId=' .. tostring(charId))
    PendingSpawns[src] = { charId = charId, ready = false }

    local attempts = 0
    CreateThread(function()
        while attempts < 50 do
            Wait(100)
            attempts = attempts + 1
            if exports['cm-playerdata'].IsLoaded(src) then
                print('[CM-SPAWN] cm-playerdata ready for src=' .. src)
                if PendingSpawns[src] and not PendingSpawns[src].ready then
                    PendingSpawns[src].ready = true
                    DoSpawn(src, charId)
                end
                return
            end
        end

        if PendingSpawns[src] and not PendingSpawns[src].ready then
            print('[CM-SPAWN] TIMEOUT waiting for cm-playerdata, forcing spawn for src=' .. src)
            PendingSpawns[src].ready = true
            DoSpawn(src, charId)
        end
    end)
end)

AddEventHandler('cm-playerdata:server:readyForSpawn', function(src, data)
    if PendingSpawns[src] and not PendingSpawns[src].ready then
        print('[CM-SPAWN] Received readyForSpawn for src=' .. src)
        PendingSpawns[src].ready = true
        DoSpawn(src, (data and data.charId) or PendingSpawns[src].charId)
    end
end)

AddEventHandler('playerDropped', function()
    PendingSpawns[source] = nil
end)

function BuildSpawnList(lastPos, hasSpawned)
    local isFirstTime = not IsHasSpawned(hasSpawned)
    print('[CM-SPAWN] BuildSpawnList: isFirstTime=' .. tostring(isFirstTime) .. ' has_spawned=' .. tostring(hasSpawned) .. ' type=' .. type(hasSpawned))

    local spawns = {}
    for _, spawn in ipairs(SpawnPoints) do
        local available = {
            key = spawn.key,
            label = spawn.label,
            description = spawn.description,
            icon = spawn.icon,
            locked = spawn.locked or false,
            lockedReason = spawn.lockedReason,
            coords = spawn.coords,
            color = spawn.color or 'blue',
            image = spawn.image
        }

        if spawn.key == 'last' then
            if isFirstTime then
                available.locked = true
                available.lockedReason = 'Available after first spawn'
            else
                if lastPos and lastPos ~= '' and lastPos ~= '{}' and lastPos ~= 'null' and lastPos ~= '[]' then
                    local ok, decoded = pcall(json.decode, lastPos)
                    if ok and decoded and decoded.x then
                        available.coords = vector4(decoded.x, decoded.y, decoded.z, decoded.h or decoded.heading or 0.0)
                    else
                        available.locked = true
                        available.lockedReason = 'Position unavailable'
                    end
                else
                    available.locked = true
                    available.lockedReason = 'No saved position'
                end
            end
        end

        table.insert(spawns, available)
    end

    return spawns, isFirstTime
end

function DoSpawn(src, charId)
    if not PendingSpawns[src] then return end
    PendingSpawns[src] = nil

    if Player(src).state.isDead then
        print('[CM-SPAWN] Player reconnecting while dead. Forcing hospital spawn.')
        local charRow = exports['cm-core']:Query('SELECT appearance_json FROM characters WHERE id = ? LIMIT 1', {charId})
        local appearance = nil
        if charRow and #charRow > 0 and charRow[1].appearance_json and charRow[1].appearance_json ~= '' then
            local ok, decoded = pcall(json.decode, charRow[1].appearance_json)
            if ok then appearance = decoded end
        end
        resetPlayerWorldState(src, false)
        TriggerClientEvent('cm-spawn:client:spawn', src, 'hospital', false, vector4(341.0, -1397.0, 33.0, 50.0), appearance)
        return
    end

    local charRow = exports['cm-core']:Query(
        'SELECT first_name, last_name, cash, last_position, appearance_json, tutorial_completed, tutorial_step, has_spawned FROM characters WHERE id = ? LIMIT 1',
        {charId}
    )

    if not charRow or #charRow == 0 then
        print('[CM-SPAWN] ERROR: Character not found: ' .. tostring(charId))
        return
    end

    local char = charRow[1]
    print('[CM-SPAWN] Character row id=' .. tostring(charId) .. ' has_spawned=' .. tostring(char.has_spawned) .. ' type=' .. type(char.has_spawned) .. ' last_position=' .. tostring(char.last_position))
    local appearance = nil
    if char.appearance_json and char.appearance_json ~= '' and char.appearance_json ~= 'null' then
        local ok, decoded = pcall(json.decode, char.appearance_json)
        if ok then appearance = decoded end
    end

    local spawns, isFirstTime = BuildSpawnList(char.last_position, char.has_spawned)
    print('[CM-SPAWN] DoSpawn: isFirstTime=' .. tostring(isFirstTime) .. ' spawns=' .. #spawns)

    if isFirstTime then
        local default = GetSpawnByKey('hotel')
        if not default then return end
        print('[CM-SPAWN] First time spawn for src=' .. src .. ' at ' .. default.key)
        resetPlayerWorldState(src, false)
        TriggerClientEvent('cm-spawn:client:spawn', src, default.key, true, default.coords, appearance)
    else
        print('[CM-SPAWN] Showing spawn selector for src=' .. src)
        TriggerClientEvent('cm-spawn:client:openSelector', src, spawns, appearance, {
            name = (char.first_name or '') .. ' ' .. (char.last_name or ''),
            cash = char.cash or 0
        })
    end
end

RegisterNetEvent('cm-spawn:server:selectSpawn', function(spawnKey)
    local src = source
    local charId = Player(src).state.charId
    if not charId then
        print('[CM-SPAWN] ERROR: No charId for player ' .. src)
        return
    end

    resetPlayerWorldState(src, false)

    local spawnData = GetSpawnByKey(spawnKey)
    if not spawnData then
        print('[CM-SPAWN] ERROR: Invalid spawn key: ' .. tostring(spawnKey))
        return
    end

    if spawnData.locked then
        print('[CM-SPAWN] BLOCKED locked spawn exploit: src=' .. src .. ' spawn=' .. tostring(spawnKey))
        TriggerClientEvent('cm-characters:client:error', src, spawnData.lockedReason or 'This spawn is locked')
        return
    end

    local coords = spawnData.coords

    if spawnKey == 'last' then
        local posRow = exports['cm-core']:Query('SELECT last_position, has_spawned FROM characters WHERE id = ?', {charId})
        if not posRow or #posRow == 0 or not IsHasSpawned(posRow[1].has_spawned) then
            print('[CM-SPAWN] BLOCKED last spawn before first spawn: src=' .. src)
            return
        end
        if posRow[1].last_position and posRow[1].last_position ~= '' then
            local ok, decoded = pcall(json.decode, posRow[1].last_position)
            if ok and decoded and decoded.x then
                coords = vector4(decoded.x, decoded.y, decoded.z, decoded.h or decoded.heading or 0.0)
            end
        end
    end

    if not coords then
        local fallback = GetSpawnByKey('hotel')
        coords = fallback and fallback.coords or vector4(324.0, -212.0, 54.0, 0.0)
    end

    local appRow = exports['cm-core']:Query('SELECT appearance_json FROM characters WHERE id = ? LIMIT 1', {charId})
    local appearance = nil
    if appRow and #appRow > 0 and appRow[1].appearance_json and appRow[1].appearance_json ~= '' then
        local ok, decoded = pcall(json.decode, appRow[1].appearance_json)
        if ok then appearance = decoded end
    end

    TriggerClientEvent('cm-spawn:client:spawn', src, spawnKey, false, coords, appearance)
end)


RegisterNetEvent('cm-spawn:server:resetWorldState', function(complete)
    resetPlayerWorldState(source, complete == true)
end)

RegisterNetEvent('cm-spawn:server:spawnComplete', function()
    local src = source
    resetPlayerWorldState(src, true)

    local charId = Player(src).state.charId
    if not charId then return end
    markSpawned(charId)
end)


local function sendCommandLine(src, msg)
    print(msg)
    if src and src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { 'CM-SPAWN', msg } })
    end
end

RegisterCommand('checkbuckets', function(src)
    for _, id in ipairs(GetPlayers()) do
        sendCommandLine(src, ('[bucket] player=%s bucket=%s'):format(id, GetPlayerRoutingBucket(tonumber(id))))
    end
end, false)

RegisterCommand('fixbucket', function(src, args)
    local target = tonumber(args and args[1]) or src
    if not target or target <= 0 then
        sendCommandLine(src, '[fixbucket] Usage from console: fixbucket PLAYER_ID')
        return
    end

    resetPlayerWorldState(target, true)
    sendCommandLine(src, ('[fixbucket] Player %s moved to bucket 0 and spawn state reset'):format(target))
end, false)

RegisterNetEvent('cm-spawn:server:tutorialComplete', function()
    local src = source
    local charId = Player(src).state.charId
    if not charId then return end
    exports['cm-core']:Query('UPDATE characters SET tutorial_completed = 1, tutorial_step = 999 WHERE id = ?', {charId})
    print('[CM-SPAWN] Tutorial marked complete for char ' .. tostring(charId))
end)
