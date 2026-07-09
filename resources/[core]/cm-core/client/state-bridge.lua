CM = CM or {}
CM.ClientState = CM.ClientState or {}

RegisterNetEvent('cm-core:client:stateUpdate', function(namespace, key, value)
    if type(namespace) ~= 'string' then return end
    CM.ClientState[namespace] = CM.ClientState[namespace] or {}
    CM.ClientState[namespace][key] = value
    SendNUIMessage({ action = 'stateUpdate', namespace = namespace, key = key, value = value })
end)

RegisterNUICallback('getState', function(_, cb)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)

    cb({
        player = {
            charId = LocalPlayer.state.charId,
            accountId = LocalPlayer.state.accountId,
            isLoggedIn = LocalPlayer.state.isLoggedIn,
            isDead = LocalPlayer.state.isDead,
            cash = LocalPlayer.state.cash,
            bank = LocalPlayer.state.bank,
            position = { x = pos.x, y = pos.y, z = pos.z },
            heading = GetEntityHeading(ped),
        },
        config = CM.Shared,
        registry = CM.ClientState,
    })
end)

exports('GetClientState', function(namespace, key)
    if not namespace then return CM.ClientState end
    if not key then return CM.ClientState[namespace] end
    return CM.ClientState[namespace] and CM.ClientState[namespace][key]
end)
