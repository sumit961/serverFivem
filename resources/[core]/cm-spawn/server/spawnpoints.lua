-- cm-spawn/server/spawnpoints.lua
-- Static base spawn definitions. Dynamic/future systems such as organizations are
-- resolved in server/main.lua so selection is always server-authoritative.

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
        label = 'FAMILY HOME',
        coords = vector4(0, 0, 0, 0),
        description = 'Family house spawn point for future housing and family systems.',
        locked = true,
        lockedReason = 'Coming soon',
        icon = 'fa-house-chimney',
        color = 'blue',
        image = 'assets/family.svg'
    },
    {
        key = 'organization',
        label = 'ORGANIZATION',
        coords = nil,
        description = 'Future-ready spawn for gangs, police, army, companies, clubs, or any custom organization.',
        locked = true,
        lockedReason = 'Join an organization with an assigned spawn to unlock this.',
        icon = 'fa-building-shield',
        color = 'cyan',
        image = 'assets/organization.svg',
        dynamic = 'organization'
    }
}

local function GetSpawnByKey(key)
    for _, spawn in ipairs(SpawnPoints) do
        if spawn.key == key then return spawn end
    end
    return nil
end

exports('GetSpawnByKey', GetSpawnByKey)

exports('GetStaticSpawnPoints', function()
    return SpawnPoints
end)
