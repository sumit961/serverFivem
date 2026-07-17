CMVehicles.Client = CMVehicles.Client or {}
local Config = CMVehicles.Config

local WINDOW_BONES = {
    [0] = { 'window_lf', 'window_lf1', 'window_lf2', 'window_lf3' },
    [1] = { 'window_rf', 'window_rf1', 'window_rf2', 'window_rf3' },
    [2] = { 'window_lr', 'window_lr1', 'window_lr2', 'window_lr3' },
    [3] = { 'window_rr', 'window_rr1', 'window_rr2', 'window_rr3' },
    [4] = { 'window_lm' }, [5] = { 'window_rm' }, [6] = { 'windscreen' }, [7] = { 'windscreen_r' },
}

local function hasWindowBone(vehicle, index)
    for _, name in ipairs(WINDOW_BONES[index] or {}) do
        local bone = GetEntityBoneIndexByName(vehicle, name)
        if bone and bone ~= -1 then return true end
    end
    return false
end

local function condition(vehicle)
    local out = { windowSchema = 2, brokenWindows = {}, doors = {}, tyres = {} }
    for i = 0, 7 do
        local key = tostring(i)
        if hasWindowBone(vehicle, i) and not IsVehicleWindowIntact(vehicle, i) then out.brokenWindows[key] = true end
        local damaged = IsVehicleDoorDamaged(vehicle, i) == true
        local angle = tonumber(GetVehicleDoorAngleRatio(vehicle, i)) or 0.0
        out.doors[key] = { damaged = damaged, broken = damaged, angle = angle }
        local onRim = IsVehicleTyreBurst(vehicle, i, true) == true
        local burst = onRim or IsVehicleTyreBurst(vehicle, i, false) == true
        out.tyres[key] = { burst = burst, onRim = onRim }
    end
    out.engineRunning = GetIsVehicleEngineRunning(vehicle) == true
    out.undriveable = not IsVehicleDriveable(vehicle, false)
    return out
end

local function snapshot(vehicle, reason)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local vehicleId = CMVehicles.Client.VehicleId(vehicle)
    if not vehicleId then return nil end
    local state = Entity(vehicle).state
    if state.cmHouseGarageDisplay == true or state.cmConditionReady ~= true then return nil end
    local coords = GetEntityCoords(vehicle)
    return {
        vehicleId = tonumber(vehicleId),
        netId = CMVehicles.Client.SafeNetId(vehicle) or 0,
        fuel = CMVehicles.Client.GetVehicleFuel(vehicle),
        engineHealth = GetVehicleEngineHealth(vehicle),
        bodyHealth = GetVehicleBodyHealth(vehicle),
        tankHealth = GetVehiclePetrolTankHealth(vehicle),
        dirtLevel = GetVehicleDirtLevel(vehicle),
        conditionState = condition(vehicle),
        position = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(vehicle) },
        reason = tostring(reason or 'dirty_state'),
    }
end

local function encoded(v)
    local ok, out = pcall(json.encode, v)
    return ok and out or ''
end

local function changed(old, new)
    if not old then return true end
    local p = Config.Persistence or {}
    if math.abs((new.fuel or 0) - (old.fuel or 0)) >= (p.fuelThreshold or 0.5) then return true end
    if math.abs((new.engineHealth or 0) - (old.engineHealth or 0)) >= (p.healthThreshold or 1.0) then return true end
    if math.abs((new.bodyHealth or 0) - (old.bodyHealth or 0)) >= (p.healthThreshold or 1.0) then return true end
    if math.abs((new.tankHealth or 0) - (old.tankHealth or 0)) >= (p.healthThreshold or 1.0) then return true end
    if math.abs((new.dirtLevel or 0) - (old.dirtLevel or 0)) >= (p.dirtThreshold or 0.1) then return true end
    local a, b = old.position or {}, new.position or {}
    local dx, dy, dz = (b.x or 0)-(a.x or 0), (b.y or 0)-(a.y or 0), (b.z or 0)-(a.z or 0)
    if math.sqrt(dx*dx + dy*dy + dz*dz) >= (p.positionThresholdMeters or 1.5) then return true end
    if math.abs((b.w or 0) - (a.w or 0)) >= (p.headingThresholdDegrees or 4.0) then return true end
    return encoded(old.conditionState) ~= encoded(new.conditionState)
end

local lastVehicle = 0
local lastSent = nil
local lastSentAt = 0

local function sendSnapshot(vehicle, reason, force)
    local snap = snapshot(vehicle, reason)
    if not snap then return false end
    local maxDelay = tonumber(Config.Persistence and Config.Persistence.dirtyMaximumDelayMs) or 15000
    if force or changed(lastSent, snap) or GetGameTimer() - lastSentAt >= maxDelay then
        TriggerServerEvent('cm-vehicles:server:saveState', snap.vehicleId, snap)
        lastSent = snap
        lastSentAt = GetGameTimer()
        return true
    end
    return false
end

function CMVehicles.Client.FlushCurrentVehicle(reason)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then vehicle = lastVehicle end
    return sendSnapshot(vehicle, reason or 'explicit_client_flush', true)
end
exports('FlushCurrentVehicle', CMVehicles.Client.FlushCurrentVehicle)

CreateThread(function()
    local interval = tonumber(Config.Persistence and Config.Persistence.dirtyCheckIntervalMs) or 1000
    while true do
        Wait(interval)
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local driving = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped

        if driving then
            if lastVehicle ~= 0 and lastVehicle ~= vehicle then
                sendSnapshot(lastVehicle, 'driver_changed_vehicle', true)
                lastSent = nil
            end
            lastVehicle = vehicle
            sendSnapshot(vehicle, 'dirty_state', false)
        elseif lastVehicle ~= 0 then
            sendSnapshot(lastVehicle, 'driver_exit', true)
            lastVehicle = 0
            lastSent = nil
            lastSentAt = 0
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if lastVehicle ~= 0 then sendSnapshot(lastVehicle, 'client_resource_stop', true) end
end)
