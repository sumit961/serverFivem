RegisterNetEvent('cm-itemactions:client:heal', function(amount)
    amount = tonumber(amount) or 0
    local ped = PlayerPedId()
    local current = GetEntityHealth(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.min(maxHealth, current + amount))
end)

RegisterNetEvent('cm-itemactions:client:armor', function(amount)
    amount = tonumber(amount) or 0
    local ped = PlayerPedId()
    local current = GetPedArmour(ped)
    SetPedArmour(ped, math.min(100, current + amount))
end)

RegisterNetEvent('cm-itemactions:client:repairVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        local coords = GetEntityCoords(ped)
        veh = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end
    if veh ~= 0 then
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleEngineHealth(veh, 900.0)
        SetVehicleBodyHealth(veh, 900.0)
    end
end)

RegisterNetEvent('cm-itemactions:client:lockpickStart', function()
    -- Placeholder. Later this should open your lockpick minigame.
    print('[CM-ITEMACTIONS] Lockpick placeholder triggered')
end)

RegisterNetEvent('cm-itemactions:client:showIdCard', function(item)
    -- Placeholder. Later this should show the ID card to nearby players.
    print(('[CM-ITEMACTIONS] ID card metadata: %s'):format(json.encode(item and item.metadata or {})))
end)
