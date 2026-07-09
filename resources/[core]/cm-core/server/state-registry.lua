CM = CM or {}
CM.State = CM.State or {
    OnlinePlayers = {},
    Sessions = {},
    Registries = {},
}

local function shallowCopy(tbl)
    local copy = {}
    if type(tbl) ~= 'table' then return copy end
    for k, v in pairs(tbl) do copy[k] = v end
    return copy
end

exports('RegisterState', function(resourceName, initialData)
    if type(resourceName) ~= 'string' then return nil end
    CM.State.Registries[resourceName] = type(initialData) == 'table' and shallowCopy(initialData) or {}
    return CM.State.Registries[resourceName]
end)

exports('GetState', function(resourceName)
    if type(resourceName) ~= 'string' then return nil end
    if not CM.State.Registries[resourceName] then return nil end
    return shallowCopy(CM.State.Registries[resourceName])
end)

exports('UpdateState', function(resourceName, key, value)
    if type(resourceName) ~= 'string' or key == nil then return false end
    if not CM.State.Registries[resourceName] then return false end

    local old = CM.State.Registries[resourceName][key]
    CM.State.Registries[resourceName][key] = value

    TriggerEvent('cm-core:stateChanged', resourceName, key, value, old)
    TriggerClientEvent('cm-core:client:stateUpdate', -1, resourceName, key, value)
    return true
end)

exports('SubscribeState', function(resourceName, callback)
    if type(resourceName) ~= 'string' or type(callback) ~= 'function' then return false end
    AddEventHandler('cm-core:stateChanged', function(res, key, newVal, oldVal)
        if res == resourceName then callback(key, newVal, oldVal) end
    end)
    return true
end)

-- Compatibility event for old resources. New resources should use cm-playerdata events.
AddEventHandler('cm-core:characterLoaded', function(src, charId)
    src = tonumber(src)
    if not src or not charId then return end

    CM.State.OnlinePlayers[charId] = {
        src = src,
        charId = charId,
        name = 'Unknown',
        joinedAt = os.time(),
    }
    CM.State.Sessions[src] = { charId = charId, connectTime = os.time() }

    pcall(function()
        Player(src).state:set('charId', charId, true)
        Player(src).state:set('isLoggedIn', true, true)
        Player(src).state:set('isDead', false, true)
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local charId
    pcall(function() charId = Player(src).state.charId end)

    if charId then CM.State.OnlinePlayers[charId] = nil end
    CM.State.Sessions[src] = nil
end)

exports('IsPlayerOnline', function(charId)
    if not charId then return false end
    return CM.State.OnlinePlayers[charId] ~= nil or exports['cm-core']:GetOnlinePlayer(charId) ~= nil
end)

exports('GetOnlinePlayerByCharId', function(charId)
    if not charId then return nil end
    return CM.State.OnlinePlayers[charId]
end)

exports('GetStateOnlineCount', function()
    local c = 0
    for _ in pairs(CM.State.OnlinePlayers) do c = c + 1 end
    return c
end)
