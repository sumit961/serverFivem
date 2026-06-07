-- cm-spawn/server/spawnpoints.lua

SpawnPoints = {
    {
        key = 'last',
        label = 'LAST COORD',
        coords = nil,
        description = 'By clicking here, you can spawn again at the place you last exited.',
        alwaysUnlocked = true,
        icon = 'fa-location-dot',
        color = 'orange'
    },
    {
        key = 'hotel',
        label = 'HOTEL',
        coords = vector4(324.0, -212.0, 54.0, 0.0),
        description = 'By clicking here, you can spawn in the town hotel.',
        alwaysUnlocked = true,
        icon = 'fa-hotel',
        color = 'green'
    },
    {
        key = 'family',
        label = 'FAMILY',
        coords = vector4(0, 0, 0, 0),
        description = 'By clicking here, you can spawn in the family house.',
        locked = true,
        lockedReason = 'Coming soon',
        icon = 'fa-house-chimney',
        color = 'blue'
    },
    {
        key = 'gang',
        label = 'GANG',
        coords = vector4(0, 0, 0, 0),
        description = 'By clicking here, you can spawn in the gang territory.',
        locked = true,
        lockedReason = 'Coming soon',
        icon = 'fa-skull',
        color = 'purple'
    }
}

local function GetSpawnByKey(key)
    for _, spawn in ipairs(SpawnPoints) do
        if spawn.key == key then return spawn end
    end
    return nil
end

exports('GetSpawnByKey', GetSpawnByKey)

-- DEPRECATED: Kept for backward compatibility only
-- Use BuildSpawnList in main.lua instead
exports('GetAvailableSpawns', function(src, charData)
    print('[CM-SPAWN] WARNING: GetAvailableSpawns export called — this is deprecated, use BuildSpawnList in main.lua')
    return {}, true
end)