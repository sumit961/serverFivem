local U = CMVehicles.Utils


local function getMileageSpeedMultiplier(mileage)
    mileage = tonumber(mileage) or 0.0
    if mileage < 5000.0 then return 1.0 end
    if mileage < 10000.0 then return 0.98 end
    if mileage < 20000.0 then return 0.95 end
    if mileage < 50000.0 then return 0.90 end
    return 0.85
end

local function applyMileagePerformance(vehicle, metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local multiplier = getMileageSpeedMultiplier(metadata.mileage)

    -- Mileage only makes the car slower. It must never damage engine/body/tank health.
    SetVehicleEnginePowerMultiplier(vehicle, (multiplier - 1.0) * 100.0)
    SetVehicleEngineTorqueMultiplier(vehicle, multiplier)
end

local function waitForNetVehicle(netId)
    local timeout = GetGameTimer() + 7000
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < timeout do Wait(0) end
    local veh = NetworkGetEntityFromNetworkId(netId)
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and GetGameTimer() < timeout do
        veh = NetworkGetEntityFromNetworkId(netId)
        Wait(0)
    end
    return veh
end

RegisterNetEvent('cm-vehicles:client:finalizeSpawn', function(data)
    data = type(data) == 'table' and data or {}
    local veh = waitForNetVehicle(tonumber(data.netId))
    if not veh or veh == 0 then return end
    CMVehicles.Client.HasControl(veh, 2500)

    Wait(50) -- lets OneSync physics/vehicle skeleton load
    SetVehicleFixed(veh) -- must run first to avoid negative health physics bug

    local engine = U.ClampHealth(data.engineHealth)
    local body = U.ClampHealth(data.bodyHealth)
    local tank = U.ClampHealth(data.tankHealth or 1000)
    SetVehicleEngineHealth(veh, engine)
    SetVehicleBodyHealth(veh, body)
    SetVehiclePetrolTankHealth(veh, tank)
    SetVehicleDirtLevel(veh, tonumber(data.dirtLevel) or 0.0)
    applyMileagePerformance(veh, data.metadata)

    SetVehicleNumberPlateText(veh, '        ')
    SetVehicleColours(veh, 111, 111)
    SetVehicleExtraColours(veh, 111, 111)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    -- Spawned vehicles must NOT auto-start. Driver must press Left Ctrl.
    SetVehicleUndriveable(veh, true)
    CMVehicles.Client.ApplyLock(veh, data.locked == true)

    if data.metadata and type(data.metadata.neons) == 'table' then
        for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, data.metadata.neons[i + 1] == true) end
    end

    SetVehicleEngineOn(veh, false, true, true)
    if data.warp == true then
        Wait(50) -- second physics wait before warp
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end
end)

RegisterNetEvent('cm-vehicles:client:spawnPurchasedVehicle', function(data)
    -- Backward compatible event name. Actual spawn is now server-side.
    TriggerServerEvent('cm-vehicles:server:spawnPurchasedVehicle', data or {})
end)

CreateThread(function()
    local lastCoords = nil
    while true do
        Wait(CMVehicles.Config.Persistence.saveIntervalMs)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local vehicleId = CMVehicles.Client.VehicleId(veh)
            if vehicleId then
                local coords = GetEntityCoords(veh)
                local deltaKm = 0.0
                if lastCoords then deltaKm = #(coords - lastCoords) / 1000.0 end
                lastCoords = coords
                TriggerServerEvent('cm-vehicles:server:saveState', vehicleId, {
                    fuel = GetVehicleFuelLevel(veh),
                    engineHealth = GetVehicleEngineHealth(veh),
                    bodyHealth = GetVehicleBodyHealth(veh),
                    tankHealth = GetVehiclePetrolTankHealth(veh),
                    dirtLevel = GetVehicleDirtLevel(veh),
                    mileage = deltaKm,
                    position = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(veh) }
                })
            end
        else
            lastCoords = nil
        end
    end
end)
