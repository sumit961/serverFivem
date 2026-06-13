local Config = CMParking.Config
local NpcPeds = {}
local CurrentLot = nil
local UiOpen = false

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg or '')
    EndTextCommandThefeedPostTicker(false, false)
    SendNUIMessage({ action = 'toast', message = msg or '' })
end

RegisterNetEvent('cm-parking:client:notify', function(msg)
    notify(msg)
end)

local function normalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

local function nui(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function closeUi()
    UiOpen = false
    SetNuiFocus(false, false)
    nui('close', {})
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 7000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
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

local function spawnNpc(lot)
    if NpcPeds[lot.id] then return end
    local hash = loadModel(lot.npc or 's_m_m_security_01')
    if not hash then return end
    local c = lot.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, true)
    if not ped or ped == 0 then return end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    NpcPeds[lot.id] = ped
    SetModelAsNoLongerNeeded(hash)
end

local function nearestLot(maxDistance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local best, bestDist = nil, maxDistance or Config.Interaction.distance or 3.0
    for _, lot in ipairs(Config.ParkingLots or {}) do
        local dist = #(coords - vector3(lot.coords.x, lot.coords.y, lot.coords.z))
        if dist <= bestDist then
            best, bestDist = lot, dist
        end
    end
    return best, bestDist
end

local function vehiclePlate(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    local ok, statePlate = pcall(function() return Entity(vehicle).state.cmPlate end)
    if ok and statePlate and tostring(statePlate) ~= '' then return normalizePlate(statePlate) end
    return normalizePlate(GetVehicleNumberPlateText(vehicle))
end



local function findVehicleByInternalPlate(plate)
    plate = normalizePlate(plate)
    if plate == '' then return nil end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            local ok, statePlate = pcall(function() return Entity(veh).state.cmPlate end)
            local p = ok and normalizePlate(statePlate) or normalizePlate(GetVehicleNumberPlateText(veh))
            if p == plate then return veh end
        end
    end
    return nil
end

local function deleteLocalVehicleIfExists(plate)
    local veh = findVehicleByInternalPlate(plate)
    if not veh or veh == 0 then return end
    NetworkRequestControlOfEntity(veh)
    local timeout = GetGameTimer() + 1200
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(veh)
        Wait(0)
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
end

local function currentDriverVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return nil
end

local function sendParkCurrent()
    if not CurrentLot then notify('No parking selected.') return end
    local veh = currentDriverVehicle()
    if not veh then notify('You must be in the driver seat to park.') return end
    local plate = vehiclePlate(veh)
    if plate == '' then notify('Vehicle id not found. Try lock/unlock or G menu first.') return end

    local coords = GetEntityCoords(veh)
    TriggerServerEvent('cm-parking:server:parkVehicle', {
        lotId = CurrentLot.id,
        plate = plate,
        netId = NetworkGetNetworkIdFromEntity(veh),
        fuel = GetVehicleFuelLevel(veh),
        engineHealth = GetVehicleEngineHealth(veh),
        bodyHealth = GetVehicleBodyHealth(veh),
        position = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(veh) }
    })
end


local function normalizeVehicleDrive(vehicle, resetSpeed)
    -- v1.5 normal-drive: parking does not touch gears, speed, handbrake, or handling.
    -- Kept only for compatibility with older code paths.
    if not vehicle or vehicle == 0 then return end
    SetVehicleNeedsToBeHotwired(vehicle, false)
end


local function applyLock(vehicle, locked)
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

local function spawnParkedVehicle(data)
    data = type(data) == 'table' and data or {}
    deleteLocalVehicleIfExists(data.plate)
    local hash = loadModel(data.model or 'sultan')
    if not hash then notify('Vehicle model could not load: ' .. tostring(data.model)) return end

    local coords = data.spawnCoords or {}
    local heading = data.heading or coords.w or 0.0
    local veh = CreateVehicle(hash, coords.x or coords[1], coords.y or coords[2], coords.z or coords[3], heading, true, false)
    if not veh or veh == 0 then notify('Vehicle spawn failed.') return end

    SetVehicleNumberPlateText(veh, '        ')
    pcall(function() Entity(veh).state:set('cmPlate', data.plate, true) end)
    pcall(function() Entity(veh).state:set('cmVehicleId', data.id, true) end)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    -- v1.6 native-drive testing: spawn healthy so damaged saved values do not cause smoke/broken driving.
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleFixed(veh)
    SetVehicleFuelLevel(veh, tonumber(data.fuel) or 100.0)
    applyLock(veh, data.is_locked == true or data.is_locked == 1)
    SetVehicleNeedsToBeHotwired(veh, false)
    -- v1.6 native-drive: do not force engine/gears/speed after parking retrieve.

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdExistsOnAllMachines(netId, true)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', data.plate, netId)

    if Config.Rules and Config.Rules.WarpIntoVehicleOnRetrieve then
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetGameplayCamRelativeHeading(0.0)
    end

    notify(data.message or ('Retrieved %s.'):format(data.label or data.model or 'vehicle'))
    SetModelAsNoLongerNeeded(hash)
end

RegisterNetEvent('cm-parking:client:open', function(payload)
    payload = type(payload) == 'table' and payload or {}
    CurrentLot = nil
    for _, lot in ipairs(Config.ParkingLots or {}) do
        if lot.id == payload.lotId then CurrentLot = lot break end
    end
    UiOpen = true
    SetNuiFocus(true, true)
    nui('open', payload)
end)

RegisterNetEvent('cm-parking:client:update', function(payload)
    if UiOpen then nui('update', payload or {}) end
end)

RegisterNetEvent('cm-parking:client:deleteVehicle', function(netId)
    netId = tonumber(netId)
    if not netId then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return end
    NetworkRequestControlOfEntity(veh)
    local timeout = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(veh)
        Wait(0)
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
end)

RegisterNetEvent('cm-parking:client:spawnParkedVehicle', spawnParkedVehicle)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('parkCurrent', function(_, cb)
    sendParkCurrent()
    cb({ ok = true })
end)

RegisterNUICallback('retrieve', function(data, cb)
    if CurrentLot then
        TriggerServerEvent('cm-parking:server:retrieveVehicle', {
            lotId = CurrentLot.id,
            vehicleId = data and data.vehicleId,
            plate = data and data.plate
        })
    end
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    if CurrentLot then TriggerServerEvent('cm-parking:server:refresh', CurrentLot.id) end
    cb({ ok = true })
end)

RegisterCommand('parkmenu', function()
    local lot = nearestLot(5.0)
    if not lot then notify('No parking nearby.') return end
    CurrentLot = lot
    TriggerServerEvent('cm-parking:server:open', lot.id)
end, false)

RegisterCommand('park', function()
    local lot = nearestLot(5.0)
    if not lot then notify('No parking nearby.') return end
    CurrentLot = lot
    sendParkCurrent()
end, false)

RegisterCommand('unpark', function(_, args)
    local lot = nearestLot(5.0)
    if not lot then notify('No parking nearby.') return end
    local id = tonumber(args and args[1])
    if not id then notify('Use: unpark vehicleId') return end
    TriggerServerEvent('cm-parking:server:retrieveVehicle', { lotId = lot.id, vehicleId = id })
end, false)



RegisterCommand('callvehicle', function(_, args)
    local lot = nearestLot(5.0)
    if not lot then notify('No parking nearby.') return end
    local id = tonumber(args and args[1])
    if not id then notify('Use: callvehicle vehicleId') return end
    TriggerServerEvent('cm-parking:server:retrieveVehicle', { lotId = lot.id, vehicleId = id })
end, false)

CreateThread(function()
    for _, lot in ipairs(Config.ParkingLots or {}) do spawnNpc(lot) end
end)

CreateThread(function()
    while true do
        local sleep = 800
        if not UiOpen then
            local lot, dist = nearestLot(Config.Interaction.drawDistance or 25.0)
            if lot then
                local c = lot.coords
                if dist <= (Config.Interaction.drawDistance or 25.0) then
                    sleep = dist <= (Config.Interaction.distance or 3.0) and 0 or 300
                    drawText3D(c.x, c.y, c.z + 1.05, lot.label)
                    if dist <= (Config.Interaction.distance or 3.0) then
                        drawText3D(c.x, c.y, c.z + 0.85, '[E] Parking')
                        if IsControlJustPressed(0, 38) then
                            CurrentLot = lot
                            TriggerServerEvent('cm-parking:server:open', lot.id)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, ped in pairs(NpcPeds) do
        if ped and ped ~= 0 then DeleteEntity(ped) end
    end
end)
