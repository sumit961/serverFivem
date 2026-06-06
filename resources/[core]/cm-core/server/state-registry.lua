CM.State = {
    OnlinePlayers = {},
    Sessions = {},
    Registries = {},
}

exports('RegisterState', function(resourceName, initialData)
    CM.State.Registries[resourceName] = initialData or {}
    return CM.State.Registries[resourceName]
end)

exports('GetState', function(resourceName)
    if not CM.State.Registries[resourceName] then return nil end
    local copy = {}
    for k, v in pairs(CM.State.Registries[resourceName]) do copy[k] = v end
    return copy
end)

exports('UpdateState', function(resourceName, key, value)
    if not CM.State.Registries[resourceName] then return false end
    local old = CM.State.Registries[resourceName][key]
    CM.State.Registries[resourceName][key] = value
    TriggerEvent('cm-core:stateChanged', resourceName, key, value, old)
    TriggerClientEvent('cm-core:client:stateUpdate', -1, resourceName, key, value)
    return true
end)

exports('SubscribeState', function(resourceName, callback)
    AddEventHandler('cm-core:stateChanged', function(res, key, newVal, oldVal)
        if res == resourceName then callback(key, newVal, oldVal) end
    end)
end)

AddEventHandler('cm-core:characterLoaded', function(src, charId)
    local char = nil
    if exports['cm-characters'] then
        char = exports['cm-characters']:GetCharacterById(charId)
    end
    
    CM.State.OnlinePlayers[charId] = {
        src = src, charId = charId,
        name = char and (char.first_name .. " " .. char.last_name) or "Unknown",
        rankId = char and char.current_rank_id or 1,
        joinedAt = os.time(),
    }
    
    CM.State.Sessions[src] = {charId = charId, connectTime = os.time()}
    
    local ps = Player(src).state
    ps:set('charId', charId, true)
    ps:set('isLoggedIn', true, true)
    ps:set('isDead', false, true)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local charId = Player(src).state.charId
    
    if charId and CM.State.OnlinePlayers[charId] then
        CM.State.OnlinePlayers[charId] = nil
    end
    if CM.State.Sessions[src] then
        CM.State.Sessions[src] = nil
    end
    
    local ps = Player(src).state
    ps:set('charId', nil, true)
    ps:set('isLoggedIn', false, true)
end)

exports('IsPlayerOnline', function(charId) return CM.State.OnlinePlayers[charId] ~= nil end)
exports('GetOnlinePlayer', function(charId) return CM.State.OnlinePlayers[charId] end)
exports('GetOnlineCount', function()
    local c = 0
    for _ in pairs(CM.State.OnlinePlayers) do c = c + 1 end
    return c
end)