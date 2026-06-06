CM = CM or {}
CM.ClientState = {}

RegisterNetEvent('cm-core:client:stateUpdate', function(namespace, key, value)
    CM.ClientState[namespace] = CM.ClientState[namespace] or {}
    CM.ClientState[namespace][key] = value
    SendNUIMessage({action = 'stateUpdate', namespace = namespace, key = key, value = value})
end)

RegisterNUICallback('getState', function(data, cb)
    local pos = GetEntityCoords(PlayerPedId())
    cb({
        player = {
            charId = LocalPlayer.state.charId,
            isLoggedIn = LocalPlayer.state.isLoggedIn,
            isDead = LocalPlayer.state.isDead,
            position = {x = pos.x, y = pos.y, z = pos.z},
            heading = GetEntityHeading(PlayerPedId()),
        },
        config = CM.Shared,
        registry = CM.ClientState
    })
end)

exports('GetClientState', function(namespace, key)
    if not namespace then return CM.ClientState end
    if not key then return CM.ClientState[namespace] end
    return CM.ClientState[namespace] and CM.ClientState[namespace][key]
end)