local lastForcedExit = 0

RegisterNetEvent('cm-vehicles:client:forceOrganizationVehicleExit', function(netId)
    if GetGameTimer() - lastForcedExit < 750 then return end
    lastForcedExit = GetGameTimer()
    local ped = PlayerPedId()
    local vehicle = NetToVeh(tonumber(netId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) then vehicle = GetVehiclePedIsIn(ped, false) end
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    SetVehicleEngineOn(vehicle, false, true, true)
    TaskLeaveVehicle(ped, vehicle, 16)
    TriggerEvent('cm-hud:client:notify', 'You are not authorized to drive this organization vehicle.', 'error')
end)
