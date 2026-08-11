Exports = {}

function Exports.normalizePlate(plate)
    if not plate then
        return nil
    end
    return tostring(plate):gsub("^%s+", ""):gsub("%s+$", ""):upper()
end

exports("GetAuthorizedVehicles", function()
    local vehicles = lib.callback.await("p_mdt/server/garage/fetchGarageData", false)
    if not vehicles then
        return {}
    end
    return Garages:sortVehicles(vehicles)
end)

exports("GetVehicleSpawnPoints", function(jobName)
    if jobName then
        return Garages.points[jobName] or {}
    end

    local job = Bridge.Framework.fetchPlayerJob()
    if job and Garages.points[job.name] then
        return Garages.points[job.name]
    end

    return Garages.points
end)

exports("SpawnFleetVehicle", function(vehicleId, pointIndex)
    if not vehicleId then
        return false, "invalid_vehicle_id"
    end

    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not Config.Departments[job.name] then
        return false, "not_authorized"
    end

    local garagePoints = Garages.points[job.name]
    if not garagePoints then
        return false, "no_garage"
    end

    local garagePoint = pointIndex and garagePoints[pointIndex] or nil
    if not garagePoint then
        for _, point in pairs(garagePoints) do
            garagePoint = point
            break
        end
    end

    if not garagePoint then
        return false, "no_garage"
    end

    local spawnPoint = Garages:getFreeSpawnPoint(garagePoint.spawnPoints)
    if not spawnPoint then
        return false, "no_free_spawn_point"
    end

    local vehicleProps = lib.callback.await("p_mdt/server/garage/spawnVehicle", false, vehicleId)
    if not vehicleProps then
        return false, "cannot_spawn_vehicle"
    end

    local entity = Editable:spawnVehicle(vehicleProps, spawnPoint)
    if not entity or not DoesEntityExist(entity) then
        return false, "spawn_failed"
    end

    Garages.spawnedVehicles[vehicleId] = entity
    Entity(entity).state:set("mdt:vehicleId", {
        id = vehicleId,
        job = job.name,
    }, true)

    return {
        netId = NetworkGetNetworkIdFromEntity(entity),
        plate = GetVehicleNumberPlateText(entity),
    }, "spawned"
end)

exports("DespawnFleetVehicle", function(vehicleIdOrPlate)
    if not vehicleIdOrPlate then
        return false, "invalid_argument"
    end

    local vehicleId = nil
    local entity = nil

    if Garages.spawnedVehicles[vehicleIdOrPlate] then
        vehicleId = vehicleIdOrPlate
        entity = Garages.spawnedVehicles[vehicleIdOrPlate]
    else
        local normalizedPlate = Exports.normalizePlate(vehicleIdOrPlate)
        for id, spawnedEntity in pairs(Garages.spawnedVehicles) do
            if DoesEntityExist(spawnedEntity) then
                if Exports.normalizePlate(GetVehicleNumberPlateText(spawnedEntity)) == normalizedPlate then
                    vehicleId = id
                    entity = spawnedEntity
                    break
                end
            end
        end
    end

    if not entity or not DoesEntityExist(entity) then
        return false, "vehicle_not_found"
    end

    local plate = GetVehicleNumberPlateText(entity)
    if Bridge and Bridge.CarKeys and Bridge.CarKeys.RemoveKeys then
        Bridge.CarKeys.RemoveKeys(plate, entity)
    end

    local mods = lib.getVehicleProperties(entity)
    mods.plate = plate

    local stored = lib.callback.await("p_mdt/server/garage/storeVehicle", false, {
        id = vehicleId,
        netId = NetworkGetNetworkIdFromEntity(entity),
        mods = mods,
    })

    if not stored then
        return false, "cannot_store_vehicle"
    end

    Garages.spawnedVehicles[vehicleId] = nil
    return true, "stored"
end)
