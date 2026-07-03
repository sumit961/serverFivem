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

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end


CMVehicles.Client.CachedVehicles = CMVehicles.Client.CachedVehicles or {}
CMVehicles.Client.CachedVehiclesUpdatedAt = CMVehicles.Client.CachedVehiclesUpdatedAt or 0

function CMVehicles.Client.GetCachedVehicles(force)
    local now = GetGameTimer()
    local ttl = tonumber(Config.Performance and Config.Performance.vehiclePoolCacheMs) or 1200
    if force == true or now - (CMVehicles.Client.CachedVehiclesUpdatedAt or 0) >= ttl then
        local pool = GetGamePool('CVehicle') or {}
        local vehicles = {}
        for i = 1, #pool do
            local veh = pool[i]
            if veh and veh ~= 0 and DoesEntityExist(veh) then
                vehicles[#vehicles + 1] = veh
            end
        end
        CMVehicles.Client.CachedVehicles = vehicles
        CMVehicles.Client.CachedVehiclesUpdatedAt = now
    end
    return CMVehicles.Client.CachedVehicles or {}
end

local function getModelRadius(vehicle)
    if not vehicle or vehicle == 0 then return 1.5 end
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local length = math.abs(maxDim.y - minDim.y)
    local width = math.abs(maxDim.x - minDim.x)
    local height = math.abs(maxDim.z - minDim.z)
    return math.max(1.25, math.max(length, width, height) * 0.5), minDim, maxDim
end

function CMVehicles.Client.GetVehiclePromptCoords(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    local _, _, maxDim = getModelRadius(vehicle)
    -- Put the prompt above the vehicle roof, not inside the window/door area.
    local zOffset = (tonumber(maxDim.z) or 1.0) + 0.48
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, zOffset)
end

local function getVehicleSamplePoints(vehicle)
    local radius, minDim, maxDim = getModelRadius(vehicle)
    local midZ = (minDim.z + maxDim.z) * 0.5
    local highZ = math.min(maxDim.z + 0.15, midZ + 0.9)
    local samples = {
        GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, midZ),
        GetOffsetFromEntityInWorldCoords(vehicle, 0.0, maxDim.y * 0.82, midZ),
        GetOffsetFromEntityInWorldCoords(vehicle, 0.0, minDim.y * 0.82, midZ),
        GetOffsetFromEntityInWorldCoords(vehicle, maxDim.x * 0.82, 0.0, midZ),
        GetOffsetFromEntityInWorldCoords(vehicle, minDim.x * 0.82, 0.0, midZ),
        GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, highZ)
    }

    local boot = GetEntityBoneIndexByName(vehicle, 'boot')
    if boot and boot >= 0 then samples[#samples + 1] = GetWorldPositionOfEntityBone(vehicle, boot) end
    local bonnet = GetEntityBoneIndexByName(vehicle, 'bonnet')
    if bonnet and bonnet >= 0 then samples[#samples + 1] = GetWorldPositionOfEntityBone(vehicle, bonnet) end

    return samples, radius
end

function CMVehicles.Client.GetVehicleInteractionDistance(vehicle, fromCoords)
    if not vehicle or vehicle == 0 then return 9999.0 end
    fromCoords = fromCoords or GetEntityCoords(PlayerPedId())
    local samples = getVehicleSamplePoints(vehicle)
    local best = #(fromCoords - GetEntityCoords(vehicle))
    for _, point in ipairs(samples) do
        local dist = #(fromCoords - point)
        if dist < best then best = dist end
    end
    return best
end

local function drawPromptTextAtCoord(coords, text, scale)
    local onScreen, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextFont(0)
    SetTextScale(0.0, tonumber(scale) or 0.36)
    SetTextCentre(true)
    SetTextProportional(1)
    SetTextColour(78, 232, 255, 245)
    SetTextEdge(0, 0, 0, 0, 0)
    SetTextDropShadow(0, 0, 0, 0, 0)
    SetTextEntry('STRING')
    AddTextComponentString(tostring(text or 'G'))
    DrawText(sx, sy)
end

function CMVehicles.Client.DrawVehiclePrompt3D(x, y, z, key)
    drawPromptTextAtCoord(vector3(x, y, z), key or 'G', 0.36)
end

function CMVehicles.Client.DrawVehiclePromptForVehicle(vehicle)
    if not vehicle or vehicle == 0 then return end
    local _, minDim, maxDim = getModelRadius(vehicle)

    -- Arrow marker goes above the roof. It uses a native marker instead of a
    -- Unicode arrow, so FiveM will not render a missing-glyph square.
    local arrowCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, (tonumber(maxDim.z) or 1.0) + 0.32)
    DrawMarker(2, arrowCoords.x, arrowCoords.y, arrowCoords.z, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
        0.28, 0.28, 0.24, 78, 232, 255, 190, false, true, 2, false, nil, nil, false)

    -- The G text stays in the visual middle of the vehicle, not above the roof.
    local midZ = ((tonumber(minDim.z) or 0.0) + (tonumber(maxDim.z) or 1.0)) * 0.52
    local gCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, midZ)
    drawPromptTextAtCoord(gCoords, Config.Controls.menuKey or 'G', 0.36)
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

function CMVehicles.Client.HasRacingHarness(vehicle)
    if not vehicle or vehicle == 0 then return false end
    local ok, installed = pcall(function() return Entity(vehicle).state.cmRacingHarness end)
    return ok and installed == true
end

function CMVehicles.Client.GetVehicleMileage(vehicle)
    if not vehicle or vehicle == 0 then return 0.0 end
    local ok, mileage = pcall(function() return Entity(vehicle).state.cmMileage end)
    return tonumber(ok and mileage or 0.0) or 0.0
end

local function clampFuel(value)
    value = tonumber(value)
    if value == nil then value = tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100.0 end
    if value < 0.0 then return 0.0 end
    if value > 100.0 then return 100.0 end
    return value
end

function CMVehicles.Client.SetVehicleFuel(vehicle, fuel)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0.0 end
    fuel = clampFuel(fuel)
    pcall(function() SetVehicleFuelLevel(vehicle, fuel + 0.0) end)
    pcall(function() Entity(vehicle).state:set('cmFuel', fuel, true) end)
    return fuel
end

function CMVehicles.Client.GetVehicleFuel(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100.0
    end

    local ok, stateFuel = pcall(function() return Entity(vehicle).state.cmFuel end)
    stateFuel = tonumber(ok and stateFuel or nil)
    if stateFuel ~= nil then return clampFuel(stateFuel) end

    local nativeFuel = 0.0
    pcall(function() nativeFuel = GetVehicleFuelLevel(vehicle) end)
    nativeFuel = tonumber(nativeFuel)
    if nativeFuel ~= nil and nativeFuel >= 0.0 then return clampFuel(nativeFuel) end

    return tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100.0
end



exports('HasRacingHarness', function(vehicle)
    vehicle = tonumber(vehicle) or vehicle
    if not vehicle or vehicle == 0 then vehicle = GetVehiclePedIsIn(PlayerPedId(), false) end
    return CMVehicles.Client.HasRacingHarness(vehicle)
end)

function CMVehicles.Client.GetMileagePenaltyText(mileage)
    mileage = tonumber(mileage) or 0.0
    if mileage < 5000.0 then return 'No mileage penalty yet. Next: 5,000 km.' end
    if mileage < 10000.0 then return 'Small wear: 2% power loss. Next: 10,000 km.' end
    if mileage < 20000.0 then return 'Moderate wear: 5% power loss. Next: 20,000 km.' end
    if mileage < 50000.0 then return 'Heavy wear: 10% power loss. Next: 50,000 km.' end
    return 'Very high mileage: 15% power loss.'
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
    for _, veh in ipairs(CMVehicles.Client.GetCachedVehicles()) do
        if CMVehicles.Client.VehiclePlate(veh) == plate then return veh end
    end
    return nil
end

function CMVehicles.Client.GetLookedAtVehicle(maxDistance)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local camCoords = GetGameplayCamCoord()
    local dir = rotationToDirection(GetGameplayCamRot(2))
    local distance = tonumber(maxDistance) or tonumber(Config.Interaction.lookDistance) or tonumber(Config.Interaction.distance) or 7.5
    local dest = camCoords + dir * distance
    local capsuleRadius = tonumber(Config.Interaction.capsuleRadius) or 0.55
    local actionDistance = tonumber(Config.Interaction.distance) or 5.8

    -- First pass: camera capsule ray. It is wide enough for custom/big vehicles,
    -- but still only succeeds when the player is actually looking at the vehicle.
    local ray = StartShapeTestCapsule(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, capsuleRadius, 10, ped, 7)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if hit == 1 and ent and ent ~= 0 and IsEntityAVehicle(ent) then
        local dist = CMVehicles.Client.GetVehicleInteractionDistance(ent, pedCoords)
        if dist <= actionDistance then
            return ent, dist
        end
    end

    -- Second pass: strict screen-centre fallback. This helps addon vehicles whose
    -- collision ray is bad, without showing G when the player is not looking at it.
    local lookDot = tonumber(Config.Interaction.lookDot) or 0.82
    local baseRadius = tonumber(Config.Interaction.lookRadius) or 0.85
    local screenMargin = tonumber(Config.Interaction.screenMargin) or 0.22
    local best, bestScore, bestDist = nil, -9999.0, nil

    for _, veh in ipairs(CMVehicles.Client.GetCachedVehicles()) do
        if DoesEntityExist(veh) then
            local nearDist = CMVehicles.Client.GetVehicleInteractionDistance(veh, pedCoords)
            if nearDist <= actionDistance then
                local samples, modelRadius = getVehicleSamplePoints(veh)
                local allowedRadius = baseRadius + math.min(modelRadius * 0.22, 1.15)

                for _, point in ipairs(samples) do
                    local toPoint = point - camCoords
                    local pointDistance = #toPoint
                    if pointDistance > 0.01 then
                        local dot = (toPoint.x * dir.x + toPoint.y * dir.y + toPoint.z * dir.z) / pointDistance
                        local forwardDistance = pointDistance * dot
                        local sideDistance = math.sqrt(math.max(0.0, (pointDistance * pointDistance) - (forwardDistance * forwardDistance)))
                        local onScreen, sx, sy = World3dToScreen2d(point.x, point.y, point.z)
                        local screenOffset = 999.0
                        if onScreen then
                            local dx = sx - 0.5
                            local dy = (sy - 0.5) * 1.78
                            screenOffset = math.sqrt((dx * dx) + (dy * dy))
                        end

                        if onScreen and dot >= lookDot and forwardDistance > 0.2 and forwardDistance <= distance and sideDistance <= allowedRadius and screenOffset <= screenMargin then
                            local score = (dot * 18.0) - (screenOffset * 18.0) - (sideDistance * 0.85) - (nearDist * 0.12)
                            if score > bestScore then
                                best, bestScore, bestDist = veh, score, nearDist
                            end
                        end
                    end
                end
            end
        end
    end

    return best, bestDist
end

function CMVehicles.Client.GetActionVehicle(allowLook)
    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    if inside and inside ~= 0 then return inside end

    local actionDistance = tonumber(Config.Interaction.distance) or 6.5
    if allowLook then
        local looked = CMVehicles.Client.GetLookedAtVehicle(tonumber(Config.Interaction.lookDistance) or actionDistance)
        if looked and looked ~= 0 then return looked end
    end

    local coords = GetEntityCoords(ped)
    local best, bestDist = nil, actionDistance
    for _, veh in ipairs(CMVehicles.Client.GetCachedVehicles()) do
        if DoesEntityExist(veh) then
            local d = CMVehicles.Client.GetVehicleInteractionDistance(veh, coords)
            if d <= bestDist then best, bestDist = veh, d end
        end
    end
    return best
end

function CMVehicles.Client.GetVehicleContext(vehicle, outside)
    local ped = PlayerPedId()
    local inVehicle = vehicle and vehicle ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle and outside ~= true
    return {
        outside = outside == true,
        inVehicle = inVehicle == true,
        isDriver = inVehicle == true and GetPedInVehicleSeat(vehicle, -1) == ped,
        plate = CMVehicles.Client.VehiclePlate(vehicle),
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        vehicleId = CMVehicles.Client.VehicleId(vehicle)
    }
end

local function loadAnimDict(dict, timeoutMs)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + (tonumber(timeoutMs) or 1800)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function trunkSleepAnimForPed(ped)
    -- Lying animation makes the player visibly sleep in the trunk/bed instead of standing frozen behind it.
    if IsPedMale(ped) then
        return 'amb@world_human_sunbathe@male@back@base', 'base'
    end
    return 'amb@world_human_sunbathe@female@back@base', 'base'
end

function CMVehicles.Client.PlayTrunkSleepAnim()
    local ped = PlayerPedId()
    local dict, anim = trunkSleepAnimForPed(ped)
    if loadAnimDict(dict, 1800) then
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        return true
    end

    -- Fallback if an addon build does not stream the sunbathe anim quickly enough.
    dict, anim = 'missfbi5ig_0', 'lyinginpain_loop_steve'
    if loadAnimDict(dict, 1200) then
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        return true
    end
    return false
end

function CMVehicles.Client.KeepTrunkSleepAnimAlive()
    if not CMVehicles.Client.InTrunk then return end
    local ped = PlayerPedId()
    local dict, anim = trunkSleepAnimForPed(ped)
    if HasAnimDictLoaded(dict) and IsEntityPlayingAnim(ped, dict, anim, 3) then return end
    CMVehicles.Client.PlayTrunkSleepAnim()
end

function CMVehicles.Client.EnterTrunk(vehicle, plate, skipServer)
    if not vehicle or vehicle == 0 then return end
    local ped = PlayerPedId()
    local _, minDim, maxDim = getModelRadius(vehicle)
    local vehicleLength = math.abs((tonumber(maxDim.y) or 2.0) - (tonumber(minDim.y) or -2.0))

    -- Rear/bed placement. This keeps trucks inside the tray and sedans inside the trunk area,
    -- instead of attaching the player standing behind the bumper.
    local trunkY = (tonumber(minDim.y) or -2.4) + math.min(math.max(vehicleLength * 0.24, 0.65), 1.20)
    local trunkZ = math.max((tonumber(minDim.z) or 0.0) + 0.62, 0.36)

    CMVehicles.Client.InTrunk = true
    CMVehicles.Client.TrunkVehicle = vehicle
    CMVehicles.Client.ActiveTrunkPlate = U.NormalizePlate(plate or CMVehicles.Client.VehiclePlate(vehicle))

    ClearPedTasksImmediately(ped)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, false, false)
    SetEntityNoCollisionEntity(ped, vehicle, true)
    SetPedCanRagdoll(ped, false)
    FreezeEntityPosition(ped, false)
    SetEntityHeading(ped, GetEntityHeading(vehicle))

    local attachCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, trunkY, trunkZ)
    SetEntityCoordsNoOffset(ped, attachCoords.x, attachCoords.y, attachCoords.z, false, false, false)

    -- Use vehicle rotation plus a lying animation. Do not pitch/roll the entity manually because
    -- that can snap peds upright on some custom vehicle skeletons.
    AttachEntityToEntity(ped, vehicle, 0, 0.0, trunkY, trunkZ, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    SetVehicleDoorOpen(vehicle, 5, false, false)
    CMVehicles.Client.PlayTrunkSleepAnim()
    notify('You got in the trunk. Press ESC or Backspace to get out. You can still move the camera.')
end

function CMVehicles.Client.ExitTrunk(forced, skipServer)
    if not CMVehicles.Client.InTrunk then return end
    local ped = PlayerPedId()
    local vehicle = CMVehicles.Client.TrunkVehicle
    local plate = CMVehicles.Client.ActiveTrunkPlate

    ClearPedTasksImmediately(ped)
    DetachEntity(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then SetEntityNoCollisionEntity(ped, vehicle, false) end
    SetPedCanRagdoll(ped, true)
    FreezeEntityPosition(ped, false)

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local coords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -3.0, 0.0)
        SetEntityCoords(ped, coords.x, coords.y, coords.z + 0.15, false, false, false, false)
    end

    CMVehicles.Client.InTrunk = false
    CMVehicles.Client.TrunkVehicle = nil
    CMVehicles.Client.ActiveTrunkPlate = nil

    if not skipServer and plate and plate ~= '' then
        TriggerServerEvent('cm-vehicles:server:leaveTrunk', plate)
    end

    notify(forced and 'You were taken out of the trunk.' or 'You left the trunk.')
end

RegisterNetEvent('cm-vehicles:client:enterTrunk', function(netId, plate)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 then veh = CMVehicles.Client.FindVehicleByPlate(plate) end
    if not veh or veh == 0 then return notify('Trunk vehicle not found.') end
    CMVehicles.Client.EnterTrunk(veh, plate, true)
end)

RegisterNetEvent('cm-vehicles:client:exitTrunk', function(forced)
    CMVehicles.Client.ExitTrunk(forced == true, true)
end)

RegisterNetEvent('cm-vehicles:client:forceLeaveVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return end
    TaskLeaveVehicle(ped, veh, 4160)
    Wait(900)
    if IsPedInAnyVehicle(ped, false) then
        ClearPedTasksImmediately(ped)
        local coords = GetOffsetFromEntityInWorldCoords(veh, 1.8, 0.0, 0.0)
        SetEntityCoords(ped, coords.x, coords.y, coords.z + 0.15, false, false, false, false)
    end
end)

RegisterCommand('vehgps', function(_, args)
    TriggerServerEvent('cm-vehicles:server:pingTracker', args[1])
end, false)


RegisterCommand('odometer', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = CMVehicles.Client.GetActionVehicle(true) end
    if not veh or veh == 0 then return notify('No vehicle nearby.') end
    local mileage = CMVehicles.Client.GetVehicleMileage(veh)
    notify(('Odometer: %.1f km | %s'):format(mileage, CMVehicles.Client.GetMileagePenaltyText(mileage)))
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
