CMRacing = CMRacing or {}
CMRacing.Server = CMRacing.Server or {}
CMRacing.Server.Validation = {}

local Validation = CMRacing.Server.Validation
local Config = CMRacing.Config

local function getVehiclesResource()
    if GetResourceState('cm-vehicles') ~= 'started' then return nil end
    return exports['cm-vehicles']
end

function Validation.ValidateDriverAndVehicle(src, routeId)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return false, 'invalid_player_ped', nil
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        return false, 'must_be_in_vehicle', nil
    end

    if GetPedInVehicleSeat(veh, -1) ~= ped then
        return false, 'must_be_driver', nil
    end

    local engineHealth = GetVehicleEngineHealth(veh)
    if engineHealth <= 100.0 then
        return false, 'vehicle_too_damaged', nil
    end

    local plate = tostring(GetVehicleNumberPlateText(veh) or ''):gsub('^%s*(.-)%s*$', '%1')
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local vehicleClass = GetVehicleClass(veh)

    local route = Config.Routes[routeId]
    if route and route.allowedClasses then
        if not route.allowedClasses[vehicleClass] then
            return false, 'vehicle_class_ineligible', {
                vehicleClass = vehicleClass,
                allowed = route.allowedClasses
            }
        end
    end

    -- Authoritative verification with cm-vehicles
    local cmVeh = getVehiclesResource()
    local isAuthorized = false
    local vehicleData = nil

    if cmVeh then
        local okPlate, row = pcall(function() return cmVeh:GetVehicleByPlate(plate) end)
        if okPlate and type(row) == 'table' and row.id then
            vehicleData = row
            local okAccess, hasAccess = pcall(function() return cmVeh:HasVehicleAccess(src, row.id) end)
            if okAccess and hasAccess then
                isAuthorized = true
            else
                local okUse, canUse = pcall(function() return cmVeh:CanUseVehicle(src, row.id, 'vehicle.drive') end)
                if okUse and canUse then
                    isAuthorized = true
                end
            end
        end
    else
        -- Fallback if cm-vehicles is not installed/running
        isAuthorized = true
    end

    if not isAuthorized then
        return false, 'vehicle_not_authorized', {
            plate = plate,
            reason = 'Vehicle not registered or driver lacks authorized keys in cm-vehicles'
        }
    end

    return true, nil, {
        entity = veh,
        netId = netId,
        plate = plate,
        class = vehicleClass,
        dbId = vehicleData and vehicleData.id or nil
    }
end

function Validation.ValidateCheckpoint(session, checkpointIndex)
    if not session or session.status ~= 'racing' then
        return false, 'no_active_race'
    end

    local route = Config.Routes[session.routeId]
    if not route then
        return false, 'unknown_route'
    end

    local expectedIndex = session.currentCheckpoint + 1
    if checkpointIndex ~= expectedIndex then
        return false, 'out_of_order_checkpoint', {
            expected = expectedIndex,
            received = checkpointIndex
        }
    end

    local targetCp = route.checkpoints[checkpointIndex]
    if not targetCp then
        return false, 'invalid_checkpoint_index'
    end

    -- Proximity verification
    local veh = NetworkGetEntityFromNetworkId(session.vehicleNetId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return false, 'vehicle_vanished'
    end

    local ped = GetPlayerPed(session.src)
    if GetVehiclePedIsIn(ped, false) ~= veh or GetPedInVehicleSeat(veh, -1) ~= ped then
        return false, 'driver_abandoned_seat'
    end

    local vehCoords = GetEntityCoords(veh)
    local cpCoords = vector3(targetCp.x, targetCp.y, targetCp.z)
    local distance = #(vehCoords - cpCoords)
    local maxAllowedDist = (Config.Validation.DefaultCheckpointRadius or 12.0) + Config.Validation.CheckpointTolerance

    if distance > maxAllowedDist then
        return false, 'checkpoint_out_of_range', {
            distance = distance,
            maxAllowed = maxAllowedDist
        }
    end

    -- Plausible segment timing check
    local nowMs = GetGameTimer()
    local prevCoords = nil
    if session.currentCheckpoint == 0 then
        prevCoords = vector3(route.staging.x, route.staging.y, route.staging.z)
    else
        local prevCp = route.checkpoints[session.currentCheckpoint]
        prevCoords = vector3(prevCp.x, prevCp.y, prevCp.z)
    end

    local segmentDistance = #(cpCoords - prevCoords)
    local elapsedSegmentMs = nowMs - (session.lastCheckpointTimeMs or session.startedAtMs)

    -- Maximum plausible velocity: 90 m/s (~324 km/h).
    -- Minimum theoretical segment milliseconds: (dist / 90) * 1000 with a slight network grace of 250ms
    local minTheoreticalMs = math.max(100, math.floor((segmentDistance / Config.Validation.MaxPlausibleSpeedMps) * 1000) - 250)

    if elapsedSegmentMs < minTheoreticalMs then
        print(('[CM-RACING] Exploitation detected for src=%s: segment %d traveled in %d ms (min theoretical: %d ms, distance: %.1f m)'):format(
            tostring(session.src), checkpointIndex, elapsedSegmentMs, minTheoreticalMs, segmentDistance
        ))
        return false, 'implausible_segment_speed', {
            elapsed = elapsedSegmentMs,
            minimum = minTheoreticalMs
        }
    end

    return true, nil, {
        elapsedSegmentMs = elapsedSegmentMs,
        nowMs = nowMs,
        isFinish = (checkpointIndex == #route.checkpoints)
    }
end
