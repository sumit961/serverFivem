-- cm-spawn/server/spawnpoints.lua

SpawnPoints = {
    {
        key = 'last',
        label = 'LAST LOCATION',
        coords = nil,
        description = 'Continue from the place you last exited.',
        alwaysUnlocked = true,
        icon = 'fa-location-dot',
        color = 'orange',
        image = 'assets/last.svg'
    },
    {
        key = 'hotel',
        label = 'HOTEL',
        coords = vector4(324.0, -212.0, 54.0, 0.0),
        description = 'Start safely from the city hotel.',
        alwaysUnlocked = true,
        icon = 'fa-hotel',
        color = 'green',
        image = 'assets/hotel.svg'
    },
    {
        key = 'family',
        label = 'FAMILY',
        coords = vector4(0, 0, 0, 0),
        description = 'Family house spawn point for future housing/family systems.',
        locked = true,
        lockedReason = 'Coming soon',
        icon = 'fa-house-chimney',
        color = 'blue',
        image = 'assets/family.svg'
    },
    {
        key = 'gang',
        label = 'GANG',
        coords = vector4(0, 0, 0, 0),
        description = 'Gang territory spawn point for future gang systems.',
        locked = true,
        lockedReason = 'Coming soon',
        icon = 'fa-skull',
        color = 'purple',
        image = 'assets/gang.svg'
    }
}

local function GetSpawnByKey(key)
    for _, spawn in ipairs(SpawnPoints) do
        if spawn.key == key then return spawn end
    end
    return nil
end

exports('GetSpawnByKey', GetSpawnByKey)

exports('GetAvailableSpawns', function(src, charData)
    print('[CM-SPAWN] WARNING: GetAvailableSpawns export called — use BuildSpawnList in main.lua')
    return {}, true
end)
