-- cm-spawn/server/main.lua

-- Helper to find spawn data
local function GetSpawnByKey(key)
    for _, spawn in ipairs(SpawnPoints) do
        if spawn.key == key then return spawn end
    end
    return nil
end

-- Track players waiting for playerdata to load
local PendingSpawns = {}

-- Listen to character selection (fired by cm-characters)
AddEventHandler('cm-core:characterLoaded', function(src, charId)
    print('[CM-SPAWN] characterLoaded for src=' .. tostring(src) .. ' charId=' .. tostring(charId))
    
    -- Store pending spawn info
    PendingSpawns[src] = {
        charId = charId,
        ready = false
    }
    
    -- Wait for cm-playerdata to load (max 5 seconds)
    local attempts = 0
    CreateThread(function()
        while attempts < 50 do
            Wait(100)
            attempts = attempts + 1
            
            -- Check if cm-playerdata has loaded this player
            if exports['cm-playerdata'].IsLoaded(src) then
                print('[CM-SPAWN] cm-playerdata ready for src=' .. src)
                if PendingSpawns[src] and not PendingSpawns[src].ready then
                    PendingSpawns[src].ready = true
                    DoSpawn(src, charId)
                end
                return
            end
        end
        
        -- Timeout — only force if not already done
        if PendingSpawns[src] and not PendingSpawns[src].ready then
            print('[CM-SPAWN] TIMEOUT waiting for cm-playerdata, forcing spawn for src=' .. src)
            PendingSpawns[src].ready = true
            DoSpawn(src, charId)
        end
    end)
end)

-- Also listen to cm-playerdata ready event (backup)
AddEventHandler('cm-playerdata:server:readyForSpawn', function(src, data)
    if PendingSpawns[src] and not PendingSpawns[src].ready then
        print('[CM-SPAWN] Received readyForSpawn for src=' .. src)
        PendingSpawns[src].ready = true
        DoSpawn(src, data.charId)
    end
end)

-- Build spawn list directly with correct data (no export call)
function BuildSpawnList(lastPos)
    local isFirstTime = true
    
    -- Check if we have a valid saved position
    if lastPos and lastPos ~= '' and lastPos ~= '{}' and lastPos ~= 'null' and lastPos ~= '[]' then
        local ok, decoded = pcall(json.decode, lastPos)
        if ok and decoded and decoded.x then
            -- Check if it's not the default spawn (0,0,1)
            if math.abs(decoded.x) > 1.0 or math.abs(decoded.y) > 1.0 or decoded.z > 2.0 then
                isFirstTime = false
            end
        end
    end
    
    print('[CM-SPAWN] BuildSpawnList: isFirstTime=' .. tostring(isFirstTime) .. ' lastPos=' .. tostring(lastPos))

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
            color = spawn.color or 'blue'
        }

        -- Last location: only if not first time
        if spawn.key == 'last' then
            if isFirstTime then
                available.locked = true
                available.lockedReason = 'Available after first spawn'
                print('[CM-SPAWN] Last Coord LOCKED (first time)')
            else
                -- Decode last position for coords
                if lastPos and lastPos ~= '' then
                    local ok, decoded = pcall(json.decode, lastPos)
                    if ok and decoded and decoded.x then
                        available.coords = vector4(decoded.x, decoded.y, decoded.z, decoded.h or decoded.heading or 0.0)
                        print('[CM-SPAWN] Last Coord UNLOCKED at ' .. json.encode(decoded))
                    else
                        available.locked = true
                        available.lockedReason = 'Position unavailable'
                        print('[CM-SPAWN] Last Coord LOCKED (decode failed)')
                    end
                else
                    available.locked = true
                    available.lockedReason = 'No saved position'
                    print('[CM-SPAWN] Last Coord LOCKED (no position)')
                end
            end
        end

        table.insert(spawns, available)
    end

    return spawns, isFirstTime
end

-- Actual spawn logic
function DoSpawn(src, charId)
    if not PendingSpawns[src] then return end
    PendingSpawns[src] = nil
    
    -- Check if reconnecting while dead
    if Player(src).state.isDead then
        print('[CM-SPAWN] Player reconnecting while dead. Forcing hospital spawn.')
        
        local charRow = exports['cm-core']:Query('SELECT appearance_json FROM characters WHERE id = ? LIMIT 1', {charId})
        local appearance = nil
        if charRow and #charRow > 0 and charRow[1].appearance_json and charRow[1].appearance_json ~= '' then
            local ok, decoded = pcall(json.decode, charRow[1].appearance_json)
            if ok then appearance = decoded end
        end

        local hospital = {x = 341.0, y = -1397.0, z = 33.0, h = 50.0}
        TriggerClientEvent('cm-spawn:client:spawn', src, 'hospital', false, hospital, appearance)
        return
    end

    -- Get FRESH data from DB
    local charRow = exports['cm-core']:Query(
        'SELECT first_name, last_name, cash, last_position, appearance_json, tutorial_completed, tutorial_step FROM characters WHERE id = ? LIMIT 1',
        {charId}
    )

    if not charRow or #charRow == 0 then
        print('[CM-SPAWN] ERROR: Character not found: ' .. tostring(charId))
        return
    end

    local char = charRow[1]

    -- Decode appearance
    local appearance = nil
    if char.appearance_json and char.appearance_json ~= '' and char.appearance_json ~= 'null' then
        local ok, decoded = pcall(json.decode, char.appearance_json)
        if ok then appearance = decoded end
    end

    -- Build spawn list directly using the DB last_position
    local spawns, isFirstTime = BuildSpawnList(char.last_position)

    print('[CM-SPAWN] DoSpawn: isFirstTime=' .. tostring(isFirstTime) .. ' spawns=' .. #spawns)

    if isFirstTime then
        -- First time: spawn directly at hotel
        local default = GetSpawnByKey('hotel')
        print('[CM-SPAWN] First time spawn for src=' .. src .. ' at ' .. default.key)
        TriggerClientEvent('cm-spawn:client:spawn', src, default.key, false, default.coords, appearance)
    else
        -- Returning player: show spawn selector
        print('[CM-SPAWN] Showing spawn selector for src=' .. src)
        TriggerClientEvent('cm-spawn:client:openSelector', src, spawns, appearance, {
            name = (char.first_name or '') .. ' ' .. (char.last_name or ''),
            cash = char.cash or 0
        })
    end
end

-- Player picked a spawn from the UI
RegisterNetEvent('cm-spawn:server:selectSpawn', function(spawnKey)
    local src = source
    local charId = Player(src).state.charId
    if not charId then
        print('[CM-SPAWN] ERROR: No charId for player ' .. src)
        return
    end

    print('[CM-SPAWN] Player selected spawn: ' .. tostring(spawnKey))

    local spawnData = GetSpawnByKey(spawnKey)
    if not spawnData then
        print('[CM-SPAWN] ERROR: Invalid spawn key: ' .. tostring(spawnKey))
        return
    end

    local coords = spawnData.coords

    -- Load last position from DB if selected
    if spawnKey == 'last' then
        local posRow = exports['cm-core']:Query('SELECT last_position FROM characters WHERE id = ?', {charId})
        if posRow and #posRow > 0 and posRow[1].last_position and posRow[1].last_position ~= '' then
            local ok, decoded = pcall(json.decode, posRow[1].last_position)
            if ok and decoded then
                coords = vector4(decoded.x, decoded.y, decoded.z, decoded.heading or 0.0)
            end
        end
    end

    if not coords then
        local fallback = GetSpawnByKey('hotel')
        coords = fallback and fallback.coords or vector4(324.0, -212.0, 54.0, 0.0)
    end

    -- Load appearance for this spawn
    local appRow = exports['cm-core']:Query('SELECT appearance_json FROM characters WHERE id = ? LIMIT 1', {charId})
    local appearance = nil
    if appRow and #appRow > 0 and appRow[1].appearance_json and appRow[1].appearance_json ~= '' then
        local ok, decoded = pcall(json.decode, appRow[1].appearance_json)
        if ok then appearance = decoded end
    end

    TriggerClientEvent('cm-spawn:client:spawn', src, spawnKey, false, coords, appearance)
end)

-- Tutorial completed (kept for future use, not called right now)
RegisterNetEvent('cm-spawn:server:tutorialComplete', function()
    local src = source
    local charId = Player(src).state.charId
    if not charId then return end

    exports['cm-core']:Query(
        'UPDATE characters SET tutorial_completed = 1, tutorial_step = 999 WHERE id = ?',
        {charId}
    )
    print('[CM-SPAWN] Tutorial marked complete for char ' .. tostring(charId))
end)