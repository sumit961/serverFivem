local U = CMVehicles.Utils
local Config = CMVehicles.Config
CMVehicles.Spawn = CMVehicles.Spawn or {}
CMVehicles.Server.Spawned = CMVehicles.Server.Spawned or {}

local function waitForEntity(entity)
    local timeout = GetGameTimer() + 5000
    while entity and entity ~= 0 and not DoesEntityExist(entity) and GetGameTimer() < timeout do Wait(0) end
    return entity and entity ~= 0 and DoesEntityExist(entity)
end

function CMVehicles.Spawn.RegisterEntity(src, row, netId)
    netId = tonumber(netId)
    if not row or not netId then return false end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 then return false end
    local plate = U.NormalizePlate(row.plate)
    CMVehicles.Server.Spawned[plate] = CMVehicles.Server.Spawned[plate] or {}
    CMVehicles.Server.Spawned[plate].netId = netId
    CMVehicles.Server.Spawned[plate].entity = ent
    CMVehicles.Server.Spawned[plate].source = src
    CMVehicles.Server.Spawned[plate].vehicleId = row.id
    CMVehicles.Server.Spawned[plate].updatedAt = os.time()
    Entity(ent).state:set('cmPlate', plate, true)
    Entity(ent).state:set('cmVehicleId', tonumber(row.id), true)
    Entity(ent).state:set('cmLocked', row.is_locked == true, true)
    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    Entity(ent).state:set('cmMileage', tonumber(metadata.mileage) or 0.0, true)
    Entity(ent).state:set('cmRacingHarness', metadata.racingHarness == true or metadata.racing_harness == true, true)
    pcall(function() SetVehicleNumberPlateText(ent, '        ') end)
    return true
end

function CMVehicles.Spawn.DeleteByPlate(plate)
    plate = U.NormalizePlate(plate)
    local occupant = CMVehicles.Server.TrunkOccupants and CMVehicles.Server.TrunkOccupants[plate]
    if occupant then
        TriggerClientEvent('cm-vehicles:client:exitTrunk', occupant, true)
        CMVehicles.Server.TrunkOccupants[plate] = nil
    end
    local active = CMVehicles.Server.Spawned[plate]
    if active and active.entity and DoesEntityExist(active.entity) then DeleteEntity(active.entity) end
    CMVehicles.Server.Spawned[plate] = nil
end

function CMVehicles.Spawn.DeletePlayerVehicles(src)
    for plate, data in pairs(CMVehicles.Server.Spawned) do
        if tonumber(data.source) == tonumber(src) then
            local occupant = CMVehicles.Server.TrunkOccupants and CMVehicles.Server.TrunkOccupants[plate]
            if occupant then
                TriggerClientEvent('cm-vehicles:client:exitTrunk', occupant, true)
                CMVehicles.Server.TrunkOccupants[plate] = nil
            end
            if data.entity and DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
            CMVehicles.Server.Spawned[plate] = nil
        end
    end
end

function CMVehicles.Spawn.CreateForPlayer(src, row, opts)
    opts = type(opts) == 'table' and opts or {}
    if not row then return false, 'Vehicle missing.' end
    local plate = U.NormalizePlate(row.plate)
    CMVehicles.Spawn.DeleteByPlate(plate)

    local spawn = opts.spawn or U.Decode(row.last_position)
    local ped = GetPlayerPed(src)
    local pcoords = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 72.0)
    local x = spawn.x or spawn[1] or (pcoords.x + 3.0)
    local y = spawn.y or spawn[2] or pcoords.y
    local z = spawn.z or spawn[3] or pcoords.z
    local h = spawn.w or spawn.heading or spawn[4] or (ped and GetEntityHeading(ped) or 0.0)

    local modelHash = type(row.model) == 'number' and row.model or joaat(row.model or 'sultan')
    local veh = CreateVehicle(modelHash, x + 0.0, y + 0.0, z + 0.0, h + 0.0, true, true)
    if not waitForEntity(veh) then return false, 'Server-side CreateVehicle failed.' end

    SetEntityRoutingBucket(veh, GetPlayerRoutingBucket(src))
    -- Server-side OneSync creation only. Some visual natives are client-only on certain artifacts.
    -- Visual blank plate and white colours are applied in client/spawn.lua after the net entity exists.
    if SetVehicleNumberPlateText then SetVehicleNumberPlateText(veh, '        ') end

    local locked = opts.locked
    if locked == nil then locked = row.is_locked == true or row.is_locked == 1 end
    Entity(veh).state:set('cmPlate', plate, true)
    Entity(veh).state:set('cmVehicleId', tonumber(row.id), true)
    Entity(veh).state:set('cmLocked', locked == true, true)
    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    Entity(veh).state:set('cmMileage', tonumber(metadata.mileage) or 0.0, true)
    Entity(veh).state:set('cmRacingHarness', metadata.racingHarness == true or metadata.racing_harness == true, true)

    local netId = NetworkGetNetworkIdFromEntity(veh)
    CMVehicles.Server.Spawned[plate] = { entity = veh, netId = netId, source = src, vehicleId = tonumber(row.id), plate = plate, updatedAt = os.time() }

    TriggerClientEvent('cm-vehicles:client:finalizeSpawn', src, {
        netId = netId,
        id = tonumber(row.id),
        model = row.model,
        label = row.label,
        plate = plate,
        fuel = tonumber(row.fuel) or 100,
        engineHealth = U.ClampHealth(opts.engineHealth or row.engineHealth or row.engine_health),
        bodyHealth = U.ClampHealth(opts.bodyHealth or row.bodyHealth or row.body_health),
        tankHealth = U.ClampHealth(opts.tankHealth or row.tankHealth or row.tank_health or 1000),
        dirtLevel = tonumber(opts.dirtLevel or row.dirtLevel or row.dirt_level) or 0,
        locked = locked == true,
        warp = opts.warp == true,
        engineOn = opts.engineOn == true,
        repairFirst = opts.repairFirst == true,
        metadata = metadata
    })

    return true, netId
end

RegisterNetEvent('cm-vehicles:server:spawnOwnedVehicle', function(vehicleId)
    local src = source
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return U.Notify(src, 'Vehicle not found.', 'error') end
    if not CMVehicles.Server.IsOwner(src, row.plate) then return U.Notify(src, 'You do not own this vehicle.', 'error') end
    CMVehicles.Spawn.CreateForPlayer(src, row, { warp = false, engineOn = false, repairFirst = false })
end)

RegisterNetEvent('cm-vehicles:server:spawnPurchasedVehicle', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    CMVehicles.Spawn.CreateForPlayer(src, data, { warp = true, engineOn = false, repairFirst = true })
end)

function CMVehicles.Spawn.SpawnFromParking(src, vehicleId, lotId, spawn, options)
    options = type(options) == 'table' and options or {}
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return false, 'Vehicle not found.' end
    if tostring(row.owner_character_id) ~= tostring(CMVehicles.Server.GetCharacterId(src)) then return false, 'You do not own this vehicle.' end

    local wasStored = row.is_stored == true or row.is_stored == 1
    local destroyed = (tonumber(row.engine_health) or 1000) <= 0 or (tonumber(row.body_health) or 1000) <= 0 or (tonumber(row.tank_health) or 1000) <= 0

    -- Parking retrieval/call-out should always return a perfect, non-smoking vehicle.
    -- Login/world restore still uses exact saved health/dirt through spawnOwnedVehicle.
    local repair = true
    local finalLocked = options.unlockOnRetrieve == true and false or row.is_locked

    MySQL.update.await([[UPDATE cm_owned_vehicles SET
        is_stored = 0,
        parking_id = NULL,
        garage = NULL,
        parked_at = NULL,
        is_locked = ?,
        engine_health = ?,
        body_health = ?,
        tank_health = ?,
        dirt_level = ?
        WHERE id = ?]], {
        finalLocked and 1 or 0,
        1000.0,
        1000.0,
        1000.0,
        0.0,
        row.id
    })

    row.is_locked = finalLocked
    row.engine_health = 1000.0
    row.body_health = 1000.0
    row.tank_health = 1000.0
    row.dirt_level = 0.0

    local ok, result = CMVehicles.Spawn.CreateForPlayer(src, row, {
        spawn = spawn,
        warp = options.warp == true,
        engineOn = options.engineOn == true,
        repairFirst = true,
        engineHealth = 1000.0,
        bodyHealth = 1000.0,
        tankHealth = 1000.0,
        dirtLevel = 0.0,
        locked = finalLocked
    })
    if not ok then return false, result end

    local msg = destroyed and ('Insurance vehicle retrieved. Fee: $' .. tostring(Config.Rules.ParkingInsuranceFee)) or (wasStored and 'Vehicle retrieved from parking.' or 'Vehicle called to parking.')
    U.Notify(src, msg, 'success')
    return true, result, { wasStored = wasStored, destroyed = destroyed, repaired = repair, fee = destroyed and Config.Rules.ParkingInsuranceFee or 0 }
end

RegisterNetEvent('cm-vehicles:server:spawnFromParking', function(vehicleId, lotId, spawn, options)
    local src = source
    local ok, err = CMVehicles.Spawn.SpawnFromParking(src, vehicleId, lotId, spawn, options)
    if not ok then U.Notify(src, tostring(err or 'Could not spawn vehicle.'), 'error') end
end)

exports('SpawnVehicleFromParking', CMVehicles.Spawn.SpawnFromParking)
exports('DeleteSpawnedVehicle', CMVehicles.Spawn.DeleteByPlate)
