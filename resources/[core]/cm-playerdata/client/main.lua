local PlayerData = {}

RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    PlayerData = data
    print('[CM-PLAYERDATA] Loaded | Cash: $' .. (data.cash or 0) .. ' | Bank: $' .. (data.bank or 0))
end)

RegisterNetEvent('cm-playerdata:client:update', function(key, value)
    PlayerData[key] = value
    -- You can forward this to your HUD resource here if needed
    -- TriggerEvent('cm-hud:updateData', key, value)
end)

-- Send position to server every 30s for last_position save
CreateThread(function()
    while true do
        Wait(30000)
        if LocalPlayer.state.isLoggedIn and LocalPlayer.state.playerDataLoaded then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local h = GetEntityHeading(ped)
            TriggerServerEvent('cm-playerdata:server:updatePosition', {
                x = Round(coords.x, 2),
                y = Round(coords.y, 2),
                z = Round(coords.z, 2),
                h = Round(h, 2)
            })
        end
    end
end)

function Round(num, places)
    local mult = 10^(places or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Exports for other client resources
exports('GetPlayerData', function()
    return PlayerData
end)

exports('GetPlayerDataByKey', function(key)
    return PlayerData[key]
end)