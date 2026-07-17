local Config = CMGas.Config
CMGas.Client = CMGas.Client or {}

local menuOpen = false
local openPending = false
local orderPending = false
local currentSessionToken = nil
local currentPumpIndex = nil
local heldVehicle = 0
local promptVisible = false
local promptMode = nil
local cachedActionVehicle = 0
local lastVehicleScan = 0

local function dbg(...)
    if Config.Debug then print('[CM-GAS]', ...) end
end

local function notify(msg, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', msg, kind or 'info')
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg or ''))
    EndTextCommandThefeedPostTicker(false, false)
end
CMGas.Client.Notify = notify

local function vehToNet(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    local ok, netId = pcall(NetworkGetNetworkIdFromEntity, vehicle)
    if not ok then return 0 end
    return tonumber(netId) or 0
end

local function normalizePlate(value)
    return tostring(value or ''):upper():gsub('%s+', ''):sub(1, 12)
end

local function getVehiclePlate(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return '' end
    local statePlate
    pcall(function() statePlate = Entity(vehicle).state.cmPlate end)
    if statePlate and statePlate ~= '' then return normalizePlate(statePlate) end
    return normalizePlate(GetVehicleNumberPlateText(vehicle))
end

local function getVehicleFuel(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    local stateFuel
    pcall(function() stateFuel = Entity(vehicle).state.cmFuel end)
    if type(stateFuel) == 'number' then return math.max(0, math.min(100, stateFuel)) end
    if GetResourceState('cm-vehicles') == 'started' then
        local ok, fuel = pcall(function() return exports['cm-vehicles']:GetVehicleFuel(vehicle) end)
        if ok and type(fuel) == 'number' then return math.max(0, math.min(100, fuel)) end
    end
    return math.max(0, math.min(100, GetVehicleFuelLevel(vehicle) or 0.0))
end

local function requestEntityControl(entity, timeoutMs)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local deadline = GetGameTimer() + (timeoutMs or 400)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

local function holdVehicle(vehicle)
    local hold = Config.VehicleHold or {}
    if hold.enabled == false or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    heldVehicle = vehicle
    requestEntityControl(vehicle, 500)

    if hold.zeroVelocity ~= false then
        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
        SetVehicleForwardSpeed(vehicle, 0.0)
    end
    if hold.handbrake ~= false then
        SetVehicleHandbrake(vehicle, true)
        SetVehicleBrakeLights(vehicle, true)
    end
    if hold.engineOff ~= false then
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, false)
    end
    if hold.freezePosition ~= false then
        FreezeEntityPosition(vehicle, true)
    end
end

local function releaseHeldVehicle()
    local vehicle = heldVehicle
    heldVehicle = 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    requestEntityControl(vehicle, 250)
    FreezeEntityPosition(vehicle, false)
    SetVehicleHandbrake(vehicle, false)
    SetVehicleBrakeLights(vehicle, false)
    -- Deliberately keep the engine off. The driver can start it normally.
end

local function sendInteraction(visible, hasVehicle)
    local mode = hasVehicle and 'vehicle' or 'store'
    if promptVisible == visible and (not visible or promptMode == mode) then return end
    promptVisible = visible
    promptMode = visible and mode or nil

    local interaction = Config.Interaction or {}
    SendNUIMessage({
        action = 'interaction',
        visible = visible == true,
        key = Config.interactKeyLabel or 'E',
        title = interaction.title or 'FUEL STATION',
        label = hasVehicle and (interaction.vehicleAction or 'Refuel vehicle & open store')
            or (interaction.storeAction or 'Open gas station store'),
        hint = interaction.hint or 'Vehicle is secured while ordering',
        hasVehicle = hasVehicle == true,
    })
end

local function getActionVehicle(forceScan)
    local now = GetGameTimer()
    if not forceScan and now - lastVehicleScan < 250 then
        if cachedActionVehicle ~= 0 and DoesEntityExist(cachedActionVehicle) then
            return cachedActionVehicle
        end
        return 0
    end
    lastVehicleScan = now

    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    if inside ~= 0 then
        if GetPedInVehicleSeat(inside, -1) == ped then
            cachedActionVehicle = inside
            return inside
        end
        cachedActionVehicle = 0
        return 0
    end

    local coords = GetEntityCoords(ped)
    local maxDistance = tonumber(Config.Security and Config.Security.maxVehicleDistance) or 7.5
    local closest, closestDistance = 0, maxDistance
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local distance = #(coords - GetEntityCoords(vehicle))
            if distance < closestDistance then
                closest = vehicle
                closestDistance = distance
            end
        end
    end
    cachedActionVehicle = closest
    return closest
end

local function findClosestPump(coords, maxDistance)
    local foundIndex, foundDistance
    for index, pump in ipairs(Config.Pumps or {}) do
        local distance = #(coords - pump)
        if (not foundDistance or distance < foundDistance) and distance <= maxDistance then
            foundIndex = index
            foundDistance = distance
        end
    end
    return foundIndex, foundDistance
end

local function closeMenu(cancelSession)
    if not menuOpen and not openPending then
        releaseHeldVehicle()
        return
    end

    local token = currentSessionToken
    menuOpen = false
    openPending = false
    orderPending = false
    currentSessionToken = nil
    currentPumpIndex = nil

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    releaseHeldVehicle()

    if cancelSession ~= false and token then
        TriggerServerEvent('cm-gas:server:cancelSession', token)
    end
end
CMGas.Client.CloseMenu = closeMenu

function CMGas.Client.OpenMenu(vehicle, pumpIndex)
    if menuOpen or openPending then return end

    vehicle = tonumber(vehicle) or 0
    pumpIndex = tonumber(pumpIndex)
    openPending = true
    currentPumpIndex = pumpIndex
    sendInteraction(false, false)

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        holdVehicle(vehicle)
    end

    TriggerServerEvent('cm-gas:server:requestOpen', {
        pumpIndex = pumpIndex,
        netId = vehToNet(vehicle),
        plate = getVehiclePlate(vehicle),
    })
end

RegisterNetEvent('cm-gas:client:openSession', function(ctx)
    if not openPending or type(ctx) ~= 'table' then return end
    openPending = false
    menuOpen = true
    orderPending = false
    currentSessionToken = tostring(ctx.sessionToken or '')

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', ctx = ctx })
end)

RegisterNetEvent('cm-gas:client:openDenied', function(message)
    openPending = false
    currentSessionToken = nil
    releaseHeldVehicle()
    if message and message ~= '' then notify(message, 'error') end
end)

RegisterNetEvent('cm-gas:client:orderResult', function(result)
    result = type(result) == 'table' and result or { ok = false, message = 'Order failed.' }
    orderPending = false
    SendNUIMessage({ action = 'orderResult', result = result })

    if result.ok == true then
        if result.netId and result.fuel then
            local netId = tonumber(result.netId) or 0
            local vehicle = 0
            if netId > 0 and NetworkDoesNetworkIdExist(netId) then
                vehicle = NetworkGetEntityFromNetworkId(netId)
            end
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetVehicleFuelLevel(vehicle, tonumber(result.fuel) + 0.0)
            end
        end
        CreateThread(function()
            Wait(850)
            closeMenu(false)
        end)
    elseif result.close == true then
        if result.message and result.message ~= '' then notify(result.message, 'error') end
        CreateThread(function()
            Wait(500)
            closeMenu(false)
        end)
    elseif result.message and result.message ~= '' then
        notify(result.message, 'error')
    end
end)

RegisterNetEvent('cm-gas:client:notify', function(message, kind)
    notify(message, kind)
end)

RegisterNUICallback('placeOrder', function(data, cb)
    if not menuOpen or orderPending or not currentSessionToken then
        cb({ ok = false })
        return
    end

    data = type(data) == 'table' and data or {}
    orderPending = true
    local submittedToken = currentSessionToken
    TriggerServerEvent('cm-gas:server:placeOrder', {
        sessionToken = submittedToken,
        fuelTarget = tonumber(data.fuelTarget) or 0,
        kits = tonumber(data.kits) or 0,
        cans = tonumber(data.cans) or 0,
        washes = tonumber(data.washes) or 0,
    })

    CreateThread(function()
        Wait(15000)
        if menuOpen and orderPending and currentSessionToken == submittedToken then
            orderPending = false
            SendNUIMessage({
                action = 'orderResult',
                result = { ok = false, message = 'The gas station did not respond. Please try again.' }
            })
        end
    end)

    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu(true)
    cb({ ok = true })
end)

RegisterNUICallback('escape', function(_, cb)
    closeMenu(true)
    cb({ ok = true })
end)

CreateThread(function()
    local blipConfig = Config.Blip or {}
    if blipConfig.enabled == false then return end

    for _, position in ipairs(Config.Stations or {}) do
        local blip = AddBlipForCoord(position.x, position.y, position.z)
        SetBlipSprite(blip, blipConfig.sprite or 361)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, blipConfig.scale or 0.72)
        SetBlipColour(blip, blipConfig.color or 3)
        SetBlipAsShortRange(blip, blipConfig.shortRange ~= false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(blipConfig.name or 'Gas Station')
        EndTextCommandSetBlipName(blip)
    end
end)

CreateThread(function()
    while true do
        local waitMs = 900

        if menuOpen or openPending then
            sendInteraction(false, false)
            Wait(250)
        else
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local nearIndex = findClosestPump(coords, tonumber(Config.stationDetectDistance) or 80.0)

            if nearIndex and not IsPauseMenuActive() and not IsEntityDead(ped) then
                local pumpIndex = findClosestPump(coords, tonumber(Config.pumpInteractDistance) or 6.0)
                if pumpIndex then
                    waitMs = 0
                    local vehicle = getActionVehicle(false)
                    local hasVehicle = vehicle ~= 0
                    sendInteraction(true, hasVehicle)

                    if IsControlJustReleased(0, Config.interactKey or 38) then
                        vehicle = getActionVehicle(true)
                        CMGas.Client.OpenMenu(vehicle, pumpIndex)
                    end
                else
                    sendInteraction(false, false)
                end
            else
                sendInteraction(false, false)
            end

            Wait(waitMs)
        end
    end
end)

local function applyAuthorizedService(kind, vehicle, patch, preserve)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    patch = type(patch) == 'table' and patch or {}
    preserve = type(preserve) == 'table' and preserve or {}
    requestEntityControl(vehicle, 500)

    if kind == 'fuelCan' and patch.fuel ~= nil then
        SetVehicleFuelLevel(vehicle, tonumber(patch.fuel) + 0.0)
    elseif kind == 'repairKit' then
        local engine = tonumber(preserve.engineHealth) or GetVehicleEngineHealth(vehicle)
        local tank = tonumber(preserve.tankHealth) or GetVehiclePetrolTankHealth(vehicle)
        local dirt = tonumber(preserve.dirtLevel) or GetVehicleDirtLevel(vehicle)

        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleBodyHealth(vehicle, tonumber(patch.bodyHealth) or 1000.0)
        SetVehicleEngineHealth(vehicle, engine + 0.0)
        SetVehiclePetrolTankHealth(vehicle, tank + 0.0)
        SetVehicleDirtLevel(vehicle, dirt + 0.0)
        for wheel = 0, 7 do SetVehicleTyreFixed(vehicle, wheel) end
    elseif kind == 'washKit' then
        SetVehicleDirtLevel(vehicle, tonumber(patch.dirtLevel) or 0.0)
        WashDecalsFromVehicle(vehicle, 1.0)
    end
end

RegisterNetEvent('cm-gas:client:applyAuthorizedService', function(kind, netId, patch, preserve)
    local vehicle = 0
    netId = tonumber(netId) or 0
    if netId > 0 and NetworkDoesNetworkIdExist(netId) then
        vehicle = NetworkGetEntityFromNetworkId(netId)
    end
    if vehicle ~= 0 then
        applyAuthorizedService(kind, vehicle, patch, preserve)
    end
end)

RegisterNetEvent('cm-gas:client:useVehicleItem', function(kind, token, durationMs)
    local vehicle = getActionVehicle(true)
    if vehicle == 0 then
        TriggerServerEvent('cm-gas:server:useResult', token, false, 'Get near a vehicle first.', 0, '')
        return
    end

    local completed = true
    if GetResourceState('cm-vehicles') == 'started' then
        completed = false
        local ok = pcall(function()
            completed = exports['cm-vehicles']:RunServiceProgress(
                kind == 'fuelCan' and 'refuel' or (kind == 'repairKit' and 'repair' or 'wash'),
                vehicle,
                tonumber(durationMs)
            )
        end)
        if not ok then completed = false end
    else
        Wait(math.max(1000, tonumber(durationMs) or 5000))
    end

    if completed ~= true then
        TriggerServerEvent('cm-gas:server:useResult', token, false, 'Cancelled.', vehToNet(vehicle), getVehiclePlate(vehicle))
        return
    end

    TriggerServerEvent('cm-gas:server:useResult', token, true, nil, vehToNet(vehicle), getVehiclePlate(vehicle))
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    sendInteraction(false, false)
    SetNuiFocus(false, false)
    releaseHeldVehicle()
end)
