lib.locale(Bridge?.Config?.Language or 'en')

Editable = {}

function Editable:spawnVehicle(data, coords)
    local vehModel = lib.requestModel(data.model)
    local vehicle = CreateVehicle(vehModel, coords.x, coords.y, coords.z, coords.w, true, false)
    SetVehicleNumberPlateText(vehicle, data.plate)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleEngineHealth(vehicle, data.engineHealth or 1000)
    SetVehicleBodyHealth(vehicle, data.bodyHealth or 1000)
    SetVehicleFuelLevel(vehicle, data.fuelLevel or 100.0)
    TaskWarpPedIntoVehicle(cache.ped, vehicle, -1)
    lib.setVehicleProperties(vehicle, data)

    if Bridge?.CarKeys?.CreateKeys then
        Bridge.CarKeys.CreateKeys(data.plate, vehicle)
    end

    return vehicle
end
