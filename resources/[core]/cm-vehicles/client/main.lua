local Config = CMVehicles.Config
local U = CMVehicles.Utils
CMVehicles.Client = CMVehicles.Client or {}
CMVehicles.Client.MenuOpen = false
CMVehicles.Client.TrunkOpen = false
CMVehicles.Client.CurrentTrunkPlate = nil
CMVehicles.Client.InTrunk = false
CMVehicles.Client.TrunkVehicle = nil
CMVehicles.Client.CurrentMenuContext = {}
CMVehicles.Client.OpenTrunks = {}
CMVehicles.Client.Seatbelt = false
CMVehicles.Client.Cruise = false
CMVehicles.Client.LastSavedMileageDelta = 0.0

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg or '')
    EndTextCommandThefeedPostTicker(false, false)
end
CMVehicles.Client.Notify = notify

RegisterNetEvent('cm-vehicles:client:notify', function(msg)
    notify(msg)
    SendNUIMessage({ action = 'toast', message = msg or '' })
end)

function CMVehicles.Client.Nui(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

function CMVehicles.Client.CloseNui()
    CMVehicles.Client.MenuOpen = false
    CMVehicles.Client.TrunkOpen = false
    CMVehicles.Client.CurrentTrunkPlate = nil
    SetNuiFocus(false, false)
    CMVehicles.Client.Nui('close', {})
end

function CMVehicles.Client.DrawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(245, 245, 245, 230)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

function CMVehicles.Client.VehiclePlate(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    local ok, statePlate = pcall(function() return Entity(vehicle).state.cmPlate end)
    if ok and statePlate and tostring(statePlate) ~= '' then return U.NormalizePlate(statePlate) end
    return U.NormalizePlate(GetVehicleNumberPlateText(vehicle))
end

function CMVehicles.Client.VehicleId(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    local ok, id = pcall(function() return Entity(vehicle).state.cmVehicleId end)
    return ok and tonumber(id) or nil
end

function CMVehicles.Client.HasControl(entity, timeoutMs)
    timeoutMs = timeoutMs or 1500
    NetworkRequestControlOfEntity(entity)
    local timeout = GetGameTimer() + timeoutMs
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

function CMVehicles.Client.ApplyLock(vehicle, locked)
    if not vehicle or vehicle == 0 then return end
    if locked then
        SetVehicleDoorsLocked(vehicle, 2)
        SetVehicleDoorsLockedForAllPlayers(vehicle, true)
    else
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleDoorsLocked(vehicle, 0)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
    end
end

function CMVehicles.Client.FindVehicleByPlate(plate)
    plate = U.NormalizePlate(plate)
    if plate == '' then return nil end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if CMVehicles.Client.VehiclePlate(veh) == plate then return veh end
    end
    return nil
end

function CMVehicles.Client.GetLookedAtVehicle(maxDistance)
    local ped = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    local dir = vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
    local dest = camCoords + dir * (maxDistance or 4.0)
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 10, ped, 0)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if hit == 1 and ent and ent ~= 0 and IsEntityAVehicle(ent) then
        return ent, #(GetEntityCoords(ped) - GetEntityCoords(ent))
    end
    return nil, nil
end

function CMVehicles.Client.GetActionVehicle(allowLook)
    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    if inside and inside ~= 0 then return inside end
    if allowLook then
        local looked = CMVehicles.Client.GetLookedAtVehicle(Config.Interaction.distance or 4.2)
        if looked and looked ~= 0 then return looked end
    end
    local coords = GetEntityCoords(ped)
    local best, bestDist = nil, Config.Interaction.distance or 4.2
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(coords - GetEntityCoords(veh))
        if d <= bestDist then best, bestDist = veh, d end
    end
    return best
end

function CMVehicles.Client.GetVehicleContext(vehicle, outside)
    return {
        outside = outside == true,
        plate = CMVehicles.Client.VehiclePlate(vehicle),
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        vehicleId = CMVehicles.Client.VehicleId(vehicle)
    }
end

function CMVehicles.Client.EnterTrunk(vehicle)
    if not vehicle or vehicle == 0 then return end
    local ped = PlayerPedId()
    CMVehicles.Client.InTrunk = true
    CMVehicles.Client.TrunkVehicle = vehicle
    AttachEntityToEntity(ped, vehicle, 0, 0.0, -2.2, 0.35, 0.0, 0.0, 0.0, false, false, false, false, 20, true)
    SetEntityVisible(ped, false, false)
    notify('You got in the trunk. Press G to get out.')
end

function CMVehicles.Client.ExitTrunk()
    if not CMVehicles.Client.InTrunk then return end
    local ped = PlayerPedId()
    DetachEntity(ped, true, true)
    SetEntityVisible(ped, true, false)
    local vehicle = CMVehicles.Client.TrunkVehicle
    if vehicle and vehicle ~= 0 then
        local coords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -3.0, 0.0)
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    end
    CMVehicles.Client.InTrunk = false
    CMVehicles.Client.TrunkVehicle = nil
    notify('You left the trunk.')
end

RegisterCommand('vehgps', function(_, args)
    TriggerServerEvent('cm-vehicles:server:pingTracker', args[1])
end, false)

RegisterNetEvent('cm-vehicles:client:trackerPing', function(netId, label)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId))
    if not veh or veh == 0 then return end
    local coords = GetEntityCoords(veh)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 225)
    SetBlipScale(blip, 1.0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Tracked Vehicle')
    EndTextCommandSetBlipName(blip)
    SetTimeout(60000, function() if DoesBlipExist(blip) then RemoveBlip(blip) end end)
end)
