local Config = CMVehicles.Config
local MenuOpen = false
local TrunkOpen = false
local CurrentTrunkPlate = nil
local EngineState = {}
local LockState = {}
local InTrunk = false
local TrunkVehicle = nil
local CurrentMenuContext = {}
local OpenTrunks = {}

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg or '')
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent('cm-vehicles:client:notify', function(msg)
    notify(msg)
    SendNUIMessage({ action = 'toast', message = msg or '' })
end)

local function normalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

local function nui(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function closeNui()
    MenuOpen = false
    TrunkOpen = false
    CurrentTrunkPlate = nil
    SetNuiFocus(false, false)
    nui('close', {})
end

local function drawText3D(x, y, z, text)
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

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local endTime = GetGameTimer() + 7000
    while not HasModelLoaded(hash) and GetGameTimer() < endTime do Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function vehiclePlate(vehicle)
    if not vehicle or vehicle == 0 then return '' end

    -- Visual GTA plates can be blank. The real internal vehicle id/plate is stored
    -- in entity state so owner/key/trunk checks still work.
    local ok, statePlate = pcall(function() return Entity(vehicle).state.cmPlate end)
    if ok and statePlate and tostring(statePlate) ~= '' then
        return normalizePlate(statePlate)
    end

    return normalizePlate(GetVehicleNumberPlateText(vehicle))
end

local function getClosestVehicle(maxDistance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')
    local closest, closestDist = nil, maxDistance or 4.0
    for _, veh in ipairs(vehicles) do
        local dist = #(coords - GetEntityCoords(veh))
        if dist < closestDist then
            closest = veh
            closestDist = dist
        end
    end
    return closest, closestDist
end


local function getGameplayCamForwardVector()
    local rot = GetGameplayCamRot(2)
    local rotX = math.rad(rot.x)
    local rotZ = math.rad(rot.z)
    local cosX = math.abs(math.cos(rotX))
    return vector3(-math.sin(rotZ) * cosX, math.cos(rotZ) * cosX, math.sin(rotX))
end

local function getLookedAtVehicle(maxDistance)
    local ped = PlayerPedId()
    local distance = tonumber(maxDistance) or (Config.Interaction.distance or 4.0)
    local playerCoords = GetEntityCoords(ped)
    local camCoords = GetGameplayCamCoord()
    local forward = getGameplayCamForwardVector()

    -- First use a raycast for direct targeting.
    local dest = camCoords + (forward * (distance + 1.5))
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 10, ped, 7)
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(ray)
    if hit == 1 and entityHit and entityHit ~= 0 and IsEntityAVehicle(entityHit) then
        local dist = #(playerCoords - GetEntityCoords(entityHit))
        if dist <= distance + 0.8 then
            return entityHit, dist, endCoords
        end
    end

    -- Then use a wider camera cone so G appears from all angles when looking at the car,
    -- not only when the ray hits the exact middle.
    local best, bestDist, bestScore = nil, nil, -999.0
    local lookDot = tonumber(Config.Interaction.lookDot) or 0.46
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            local center = GetEntityCoords(veh)
            local dist = #(playerCoords - center)
            if dist <= distance + 0.8 then
                local onScreen = World3dToScreen2d(center.x, center.y, center.z + 0.45)
                if onScreen then
                    local dir = center - camCoords
                    local len = #(dir)
                    if len > 0.01 then
                        dir = dir / len
                        local dot = forward.x * dir.x + forward.y * dir.y + forward.z * dir.z
                        if dot >= lookDot then
                            local score = dot - (dist * 0.035)
                            if score > bestScore then
                                best, bestDist, bestScore = veh, dist, score
                            end
                        end
                    end
                end
            end
        end
    end

    if best then return best, bestDist, GetEntityCoords(best) end
    return nil, nil, nil
end

local function getVehicleContext(vehicle, looked)
    local ped = PlayerPedId()
    local currentVeh = GetVehiclePedIsIn(ped, false)
    local inVehicle = currentVeh and currentVeh ~= 0
    return {
        inVehicle = inVehicle == true,
        isDriver = inVehicle and GetPedInVehicleSeat(currentVeh, -1) == ped or false,
        outside = not inVehicle,
        lookedAt = looked == true,
        canPhysical = not inVehicle
    }
end

local function findVehicleByPlate(plate)
    plate = normalizePlate(plate)
    if plate == '' then return nil end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if vehiclePlate(veh) == plate then return veh end
    end
    return nil
end

local function getActionVehicle(allowClosest)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then
        CurrentMenuContext = getVehicleContext(veh, false)
        return veh
    end

    local lookedVeh, lookedDist = getLookedAtVehicle(Config.Interaction.distance or 3.2)
    if lookedVeh and lookedVeh ~= 0 then
        CurrentMenuContext = getVehicleContext(lookedVeh, true)
        return lookedVeh, lookedDist
    end

    if allowClosest == true then
        local closest, dist = getClosestVehicle(Config.Interaction.distance or 3.2)
        if closest and closest ~= 0 then
            CurrentMenuContext = getVehicleContext(closest, false)
        end
        return closest, dist
    end

    CurrentMenuContext = {}
    return nil, nil
end

local function applyLock(vehicle, locked)
    if not vehicle or vehicle == 0 then return end
    local state = locked == true
    LockState[vehiclePlate(vehicle)] = state
    if state then
        SetVehicleDoorsLocked(vehicle, 2)
        SetVehicleDoorsLockedForAllPlayers(vehicle, true)
    else
        -- Fully release GTA door locks for the local player and all network players.
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleDoorsLocked(vehicle, 0)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
        SetVehicleNeedsToBeHotwired(vehicle, false)
    end
end

local function strictEngineRequired()
    return false
end


local function normalizeVehicleDrive(vehicle, resetSpeed)
    -- v1.5 normal-drive: do not touch gears, speed, clutch, handbrake, or handling.
    -- This function is kept only so older commands/events do not error.
    if not vehicle or vehicle == 0 then return end
    SetVehicleNeedsToBeHotwired(vehicle, false)
end


local function applyEngine(vehicle, enabled)
    if not vehicle or vehicle == 0 then return end
    local state = enabled == true
    EngineState[vehiclePlate(vehicle)] = state
    -- v1.6 native-drive: no forced engine/gear/drive rules.
    -- Keep hotwire disabled only; never force reverse/handbrake/undriveable.
    SetVehicleNeedsToBeHotwired(vehicle, false)
end

local function openMenuForVehicle(vehicle)
    if not vehicle or vehicle == 0 then notify('No vehicle nearby.') return end
    local plate = vehiclePlate(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, netId)
    TriggerServerEvent('cm-vehicles:server:requestInfo', plate, netId)
end

local function enterTrunk(vehicle)
    if InTrunk or not vehicle or vehicle == 0 then return end
    local ped = PlayerPedId()
    local bone = GetEntityBoneIndexByName(vehicle, 'boot')
    if bone < 0 then bone = 0 end
    InTrunk = true
    TrunkVehicle = vehicle
    SetVehicleDoorOpen(vehicle, 5, false, false)
    Wait(300)
    AttachEntityToEntity(ped, vehicle, bone, 0.0, -0.6, 0.15, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    notify('You are in the trunk. Press G to exit.')
end

local function exitTrunk()
    if not InTrunk then return end
    local ped = PlayerPedId()
    DetachEntity(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    if TrunkVehicle and TrunkVehicle ~= 0 then
        local coords = GetOffsetFromEntityInWorldCoords(TrunkVehicle, 0.0, -2.6, 0.0)
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
        SetVehicleDoorShut(TrunkVehicle, 5, false)
    end
    InTrunk = false
    TrunkVehicle = nil
    notify('You left the trunk.')
end

RegisterNetEvent('cm-vehicles:client:openMenu', function(info)
    info = type(info) == 'table' and info or {}
    info.context = CurrentMenuContext or {}
    MenuOpen = true
    SetNuiFocus(true, true)
    nui('openMenu', { vehicle = info })
end)

RegisterNetEvent('cm-vehicles:client:openTrunk', function(payload)
    TrunkOpen = true
    MenuOpen = false
    CurrentTrunkPlate = normalizePlate(payload and payload.plate)
    SetNuiFocus(true, true)
    nui('openTrunk', payload or {})
end)

RegisterNetEvent('cm-vehicles:client:updateTrunk', function(payload)
    if TrunkOpen then
        CurrentTrunkPlate = normalizePlate(payload and payload.plate)
        nui('updateTrunk', payload or {})
    end
end)

RegisterNetEvent('cm-vehicles:client:setVehicleState', function(plate, netId, state)
    plate = normalizePlate(plate)
    state = type(state) == 'table' and state or {}
    local veh = nil
    if netId then veh = NetworkGetEntityFromNetworkId(tonumber(netId)) end
    if not veh or veh == 0 then veh = findVehicleByPlate(plate) end
    if not veh or veh == 0 then return end

    if state.locked ~= nil then applyLock(veh, state.locked == true) end
    -- v1.6 native-drive: ignore server engine state; GTA handles normal driving.
    if state.trunkOpen ~= nil then
        OpenTrunks[plate] = state.trunkOpen == true or nil
        if state.trunkOpen then
            SetVehicleDoorOpen(veh, 5, false, false)
        else
            SetVehicleDoorShut(veh, 5, false)
        end
    end
end)

RegisterNetEvent('cm-vehicles:client:spawnPurchasedVehicle', function(data)
    data = type(data) == 'table' and data or {}
    local model = data.model or 'sultan'
    local hash = loadModel(model)
    if not hash then notify('Vehicle model could not load: ' .. tostring(model)) return end

    local ped = PlayerPedId()
    local coords = data.spawnCoords or GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.5, 0.0)
    local heading = data.heading or GetEntityHeading(ped)
    local veh = CreateVehicle(hash, coords.x or coords[1], coords.y or coords[2], coords.z or coords[3], heading, true, false)
    if not veh or veh == 0 then notify('Vehicle spawn failed.') return end

    SetVehicleNumberPlateText(veh, '        ') -- visual plate intentionally blank for now
    pcall(function() Entity(veh).state:set('cmPlate', data.plate, true) end)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    local locked = data.is_locked
    if locked == nil then locked = true end
    applyLock(veh, locked == true or locked == 1)
    if data.engineHealth then SetVehicleEngineHealth(veh, tonumber(data.engineHealth) or 1000.0) end
    if data.bodyHealth then SetVehicleBodyHealth(veh, tonumber(data.bodyHealth) or 1000.0) end
    if data.fuel then SetVehicleFuelLevel(veh, tonumber(data.fuel) or 100.0) end

    local plate = normalizePlate(data.plate)
    EngineState[plate] = true
    SetVehicleNeedsToBeHotwired(veh, false)
    TaskWarpPedIntoVehicle(ped, veh, -1)
    SetGameplayCamRelativeHeading(0.0)
    if not Config.Rules or Config.Rules.DefaultSpawnEngineOn ~= false then
        SetVehicleUndriveable(veh, false)
        SetVehicleHandbrake(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdExistsOnAllMachines(netId, true)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', data.plate, netId)
    notify((data.message or ('Vehicle ready: %s.'):format(data.label or data.model or 'vehicle')))
    SetModelAsNoLongerNeeded(hash)
end)

RegisterNetEvent('cm-vehicles:client:showMyVehicles', function(rows)
    rows = type(rows) == 'table' and rows or {}
    if #rows == 0 then notify('You do not own any vehicles.') return end
    for _, v in ipairs(rows) do
        notify(('#%s | %s | trunk %s'):format(v.id or '?', v.label or v.model or 'vehicle', v.trunk_level or 0))
        Wait(500)
    end
end)

RegisterCommand('veh_menu', function()
    if InTrunk then exitTrunk() return end

    local ped = PlayerPedId()
    local insideVeh = GetVehiclePedIsIn(ped, false)
    local veh = nil

    if insideVeh and insideVeh ~= 0 then
        veh = insideVeh
        CurrentMenuContext = getVehicleContext(veh, false)
    else
        veh = getLookedAtVehicle(Config.Interaction.distance or 3.2)
        if veh and veh ~= 0 then
            CurrentMenuContext = getVehicleContext(veh, true)
        end
    end

    if not veh or veh == 0 then
        notify('Look at the vehicle to open the menu.')
        return
    end

    openMenuForVehicle(veh)
end, false)
RegisterKeyMapping('veh_menu', 'Vehicle interaction menu', 'keyboard', Config.Controls.menuKey or 'G')

RegisterCommand('veh_lock', function()
    local veh = getActionVehicle(true)
    if not veh or veh == 0 then notify('No vehicle nearby.') return end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local plate = vehiclePlate(veh)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, netId)
    TriggerServerEvent('cm-vehicles:server:toggleLock', plate, netId)
end, false)
RegisterKeyMapping('veh_lock', 'Lock/unlock vehicle', 'keyboard', Config.Controls.lockKey or 'L')

RegisterCommand('veh_engine', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
        notify('You must be in the driver seat.')
        return
    end
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', vehiclePlate(veh), NetworkGetNetworkIdFromEntity(veh))
    TriggerServerEvent('cm-vehicles:server:toggleEngine', vehiclePlate(veh), NetworkGetNetworkIdFromEntity(veh))
end, false)
-- v1.6 native-drive: no default engine keybind. This avoids LCTRL/control conflicts with GTA driving.

-- Friendly F8 aliases without underscores.
RegisterCommand('vehmenu', function() ExecuteCommand('veh_menu') end, false)
RegisterCommand('vehlock', function() ExecuteCommand('veh_lock') end, false)
RegisterCommand('vehengine', function() ExecuteCommand('veh_engine') end, false)

RegisterCommand('vehstart', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then notify('You must be in the driver seat.') return end
    local plate = vehiclePlate(veh)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, NetworkGetNetworkIdFromEntity(veh))
    TriggerServerEvent('cm-vehicles:server:setEngine', plate, NetworkGetNetworkIdFromEntity(veh), true)
end, false)

RegisterCommand('vehstop', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then notify('You must be in the driver seat.') return end
    local plate = vehiclePlate(veh)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, NetworkGetNetworkIdFromEntity(veh))
    TriggerServerEvent('cm-vehicles:server:setEngine', plate, NetworkGetNetworkIdFromEntity(veh), false)
end, false)

RegisterCommand('vehfixdrive', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then veh = getActionVehicle(true) end
    if not veh or veh == 0 then notify('No vehicle found.') return end
    -- Manual dev-only repair/reset. No loop, no forced gear.
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehicleUndriveable(veh, false)
    SetVehicleHandbrake(veh, false)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleFixed(veh)
    SetVehicleEngineOn(veh, true, true, false)
    local plate = vehiclePlate(veh)
    if plate ~= '' then EngineState[plate] = true end
    notify('Vehicle repaired/reset for testing. Driving is GTA native.')
end, false)

RegisterCommand('vehrepairtest', function() ExecuteCommand('vehfixdrive') end, false)

RegisterCommand('vehfixreverse', function()
    -- Kept for compatibility. We no longer force gears because that caused reverse-driving bugs.
    ExecuteCommand('vehfixdrive')
end, false)

RegisterCommand('vehnormal', function() ExecuteCommand('vehfixdrive') end, false)

RegisterCommand('vehtrunk', function()
    local veh = getActionVehicle(true)
    if not veh or veh == 0 then notify('No vehicle nearby.') return end
    local plate = vehiclePlate(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, netId)
    TriggerServerEvent('cm-vehicles:server:toggleTrunkDoor', plate, netId)
end, false)

RegisterNUICallback('close', function(_, cb)
    -- Closing the trunk inventory UI must NOT close the physical trunk door.
    -- The trunk stays open until the player selects Open/Close Trunk from G menu.
    closeNui()
    cb({ ok = true })
end)

RegisterNUICallback('vehicleAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local action = tostring(data.action or '')
    local plate = normalizePlate(data.plate)
    local veh = findVehicleByPlate(plate) or getActionVehicle(true)
    local netId = veh and veh ~= 0 and NetworkGetNetworkIdFromEntity(veh) or nil
    local ped = PlayerPedId()
    local inVehicle = IsPedInAnyVehicle(ped, false)

    if action == 'lock' then
        TriggerServerEvent('cm-vehicles:server:toggleLock', plate, netId)
    elseif action == 'engine' then
        local driverVeh = GetVehiclePedIsIn(ped, false)
        if not driverVeh or driverVeh == 0 or GetPedInVehicleSeat(driverVeh, -1) ~= ped then
            notify('You must be in the driver seat to use the engine from the menu.')
        else
            TriggerServerEvent('cm-vehicles:server:toggleEngine', plate, netId)
        end
    elseif action == 'trunk' then
        if inVehicle then
            notify('You must be outside the vehicle to use the trunk.')
        else
            TriggerServerEvent('cm-vehicles:server:toggleTrunkDoor', plate, netId)
        end
    elseif action == 'key' then
        TriggerServerEvent('cm-vehicles:server:giveTempKey', plate, tonumber(data.target))
    elseif action == 'enterTrunk' then
        if inVehicle then
            notify('You cannot get in the trunk while inside a vehicle.')
        elseif veh and veh ~= 0 then
            enterTrunk(veh)
            closeNui()
        end
    elseif action == 'repair' or action == 'refuel' or action == 'charge' or action == 'passengers' or action == 'getOutTrunk' then
        notify('This RP option is coming soon.')
    end

    cb({ ok = true })
end)

RegisterNUICallback('moveToTrunk', function(data, cb)
    TriggerServerEvent('cm-vehicles:server:moveToTrunk', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('takeFromTrunk', function(data, cb)
    TriggerServerEvent('cm-vehicles:server:takeFromTrunk', data or {})
    cb({ ok = true })
end)


local function getNearbyOpenTrunkVehicle(maxDistance)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return nil, nil end
    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, tonumber(maxDistance) or (Config.Interaction.trunkDistance or 4.0)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local plate = vehiclePlate(veh)
        if plate ~= '' and OpenTrunks[plate] == true then
            local boot = GetEntityBoneIndexByName(veh, 'boot')
            local target = boot >= 0 and GetWorldPositionOfEntityBone(veh, boot) or GetOffsetFromEntityInWorldCoords(veh, 0.0, -2.5, 0.0)
            local dist = #(coords - target)
            if dist <= closestDist then
                closest, closestDist = veh, dist
            end
        end
    end
    return closest, closestDist
end

local function tryOpenNearbyTrunkInventory()
    if MenuOpen or TrunkOpen or InTrunk then return false end
    local veh = getNearbyOpenTrunkVehicle(Config.Interaction.trunkDistance or 4.0)
    if not veh or veh == 0 then return false end
    local plate = vehiclePlate(veh)
    if plate == '' then return false end
    TriggerServerEvent('cm-vehicles:server:openTrunk', plate, NetworkGetNetworkIdFromEntity(veh))
    return true
end

exports('TryOpenNearbyTrunkInventory', tryOpenNearbyTrunkInventory)
RegisterCommand('vehtrunkinv', function()
    if not tryOpenNearbyTrunkInventory() then notify('No open trunk nearby.') end
end, false)

CreateThread(function()
    while true do
        local sleep = 700
        if not MenuOpen and not TrunkOpen and not InTrunk then
            local ped = PlayerPedId()
            local insideVeh = IsPedInAnyVehicle(ped, false)
            if not insideVeh then
                local veh, dist = getLookedAtVehicle(Config.Interaction.distance or 3.2)
                if veh and veh ~= 0 and dist <= (Config.Interaction.distance or 3.2) then
                    sleep = 0
                    local coords = GetEntityCoords(veh)
                    drawText3D(coords.x, coords.y, coords.z + 0.95, '[G] Vehicle menu')
                end
            end
        elseif InTrunk then
            sleep = 0
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 47, true)
            if IsControlJustPressed(0, 47) then exitTrunk() end
        end
        Wait(sleep)
    end
end)


-- v1.5 normal-drive: removed constant vehicle drive-control thread.
-- The script no longer touches gears, speed, handbrake, or undriveable state while driving.

