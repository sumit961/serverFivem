CmQaClientActions = {}

function CmQaClientActions.snapshot()
    local coords = GetEntityCoords(PlayerPedId())
    local width, height = GetActiveScreenResolution()
    local bucket = 0
    pcall(function() bucket = GetPlayerRoutingBucket(PlayerId()) end)
    local characterId
    pcall(function() characterId = exports['cm-playerdata']:GetLocalCharacterId() end)
    return {
        ready = true,
        resource = GetCurrentResourceName(),
        screen = { width = width, height = height },
        coords = { x = coords.x, y = coords.y, z = coords.z },
        routingBucket = bucket,
        nuiFocused = IsNuiFocused(),
        characterId = tonumber(characterId),
    }
end

function CmQaClientActions.wait(ms)
    ms = math.max(0, math.min(10000, math.floor(tonumber(ms) or 0)))
    Wait(ms)
    return true
end
