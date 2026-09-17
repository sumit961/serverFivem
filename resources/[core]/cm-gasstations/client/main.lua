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

local function sendInteraction(visible, hasVehicle, isHeli)
    if visible then
        local key = Config.interactKeyLabel or 'E'
        local label = hasVehicle and (isHeli and 'REFUEL HELICOPTER' or 'REFUEL VEHICLE') or 'GAS STATION STORE'
        local name = isHeli and 'Rooftop Helipad' or (Config.stationName or 'Gas Station')
        local role = isHeli and 'Aviation Fuel' or 'Fuel & Shop'
        promptVisible = true

        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:ShowInteract({
                    key = key,
                    label = label,
                    name = name,
                    role = role,
                })
            end)
        else
            SendNUIMessage({
                action = 'interaction',
                visible = true,
                key = key,
                title = isHeli and 'ROOFTOP REFUEL' or 'FUEL STATION',
                label = label,
                hint = isHeli and 'Helicopter is secured on roof' or 'Vehicle is secured while ordering',
                hasVehicle = hasVehicle == true,
            })
        end
    else
        if promptVisible then
            promptVisible = false
            promptMode = nil
            if GetResourceState('cm-ui') == 'started' then
                pcall(function()
                    exports['cm-ui']:HideInteract()
                end)
            end
            SendNUIMessage({
                action = 'interaction',
                visible = false,
            })
        end
    end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function() exports['cm-ui']:HideInteract() end)
        end
    end
end)

local function isHelicopter(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    return GetVehicleClass(vehicle) == 15 or IsThisModelAHeli(GetEntityModel(vehicle))
end

local function getNearbyPumpProp(coords, radius)
    radius = tonumber(radius) or tonumber(Config.pumpPropDistance) or 4.2
    local models = Config.PumpModels or {
        'prop_gas_pump_1a',
        'prop_gas_pump_1b',
        'prop_gas_pump_1c',
        'prop_gas_pump_1d',
        'prop_gas_pump_old1',
        'prop_gas_pump_old2',
        'prop_gas_pump_old3',
        'prop_vintage_pump',
    }
    for _, model in ipairs(models) do
        local hash = type(model) == 'string' and joaat(model) or model
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, hash, false, false, false)
        if obj ~= 0 and DoesEntityExist(obj) then
            return obj, GetEntityCoords(obj)
        end
    end
    return nil, nil
end

local function checkHeliRooftop(stationIndex, vehicle, pedCoords)
    local pump = Config.Pumps[stationIndex]
    if not pump then return false end

    local vehCoords = (vehicle ~= 0 and DoesEntityExist(vehicle)) and GetEntityCoords(vehicle) or nil
    local targetCoords = vehCoords or pedCoords

    local dist2d = #(vector2(targetCoords.x, targetCoords.y) - vector2(pump.x, pump.y))
    local dz = targetCoords.z - pump.z

    local heliCfg = Config.HeliRooftop or {}
    local maxRadius = promptVisible and (tonumber(heliCfg.radius or 24.0) + 6.0) or (tonumber(heliCfg.radius) or 24.0)
    local minHeight = tonumber(heliCfg.minHeight) or 4.0
    local maxHeight = tonumber(heliCfg.maxHeight) or 30.0

    if dist2d > maxRadius or dz < minHeight or dz > maxHeight then
        return false
    end

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        if not isHelicopter(vehicle) then return false end

        local speed = GetEntitySpeed(vehicle)
        local maxSpeed = tonumber(heliCfg.maxLandedSpeed) or 2.5
        if speed > maxSpeed then return false end

        local heightAboveSurface = GetEntityHeightAboveGround(vehicle)
        local maxHeightAboveRoof = promptVisible and 5.0 or (tonumber(heliCfg.maxHeightAboveRoof) or 4.0)
        if heightAboveSurface > maxHeightAboveRoof then return false end

        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) ~= vehicle then
            local pedDz = pedCoords.z - pump.z
            if pedDz < minHeight then return false end
            local pedToHeli = #(pedCoords - vehCoords)
            if pedToHeli > 16.0 then return false end
        end

        return true
    end

    return false
end

local function getActionVehicle(forceScan)
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

    local now = GetGameTimer()
    if not forceScan and now - lastVehicleScan < 300 then
        if cachedActionVehicle ~= 0 and DoesEntityExist(cachedActionVehicle) then
            return cachedActionVehicle
        end
        return 0
    end
    lastVehicleScan = now

    local coords = GetEntityCoords(ped)
    local closest, closestDistance = 0, 999.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local isHeli = isHelicopter(vehicle)
            local maxDist = isHeli and 12.0 or 4.5
            local maxZ = isHeli and 4.0 or 2.5

            local vCoords = GetEntityCoords(vehicle)
            local dist2d = #(vector2(coords.x, coords.y) - vector2(vCoords.x, vCoords.y))
            local dz = math.abs(coords.z - vCoords.z)

            if dist2d <= maxDist and dz <= maxZ then
                if dist2d < closestDistance then
                    closest = vehicle
                    closestDistance = dist2d
                end
            end
        end
    end
    cachedActionVehicle = closest
    return closest
end

local function findClosestPump(coords, maxDistance, minZ, maxZ)
    local maxHoriz = tonumber(maxDistance) or tonumber(Config.stationDetectDistance) or 60.0
    local zMin = tonumber(minZ) or -20.0
    local zMax = tonumber(maxZ) or 50.0

    local foundIndex, foundDistance
    for index, pump in ipairs(Config.Pumps or {}) do
        local dist2d = #(vector2(coords.x, coords.y) - vector2(pump.x, pump.y))
        local dz = coords.z - pump.z
        if dist2d <= maxHoriz and dz >= zMin and dz <= zMax then
            if not foundDistance or dist2d < foundDistance then
                foundIndex = index
                foundDistance = dist2d
            end
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

RegisterNUICallback('buyStation', function(_, cb)
    if currentSessionToken and currentPumpIndex then TriggerServerEvent('cm-gas:server:buyStation', currentPumpIndex) end
    cb({ ok = true })
end)
RegisterNUICallback('manageStation', function(data, cb)
    if currentSessionToken and currentPumpIndex then
        data = type(data) == 'table' and data or {}; data.stationId = currentPumpIndex
        TriggerServerEvent('cm-gas:server:manageStation', data)
    end
    cb({ ok = true })
end)
RegisterNUICallback('payTax', function(_, cb)
    if currentSessionToken and currentPumpIndex then TriggerServerEvent('cm-gas:server:payTax', currentPumpIndex) end
    cb({ ok = true })
end)
RegisterNUICallback('withdrawBusiness', function(_, cb)
    if currentSessionToken and currentPumpIndex then TriggerServerEvent('cm-gas:server:withdrawBusiness', currentPumpIndex) end
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
        local waitMs = 500

        if menuOpen or openPending then
            sendInteraction(false, false)
            Wait(250)
        else
            local ped = PlayerPedId()

            if IsPauseMenuActive() or IsEntityDead(ped) then
                sendInteraction(false, false)
                Wait(500)
            else
                local coords = GetEntityCoords(ped)
                local vehicle = getActionVehicle(false)
                local isHeli = vehicle ~= 0 and isHelicopter(vehicle)

                -- Strict pump prop distance: only active when directly at a physical gas pump
                local pumpDistance = tonumber(Config.pumpPropDistance) or 4.2
                local pumpProp = getNearbyPumpProp(coords, pumpDistance)
                if not pumpProp and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    pumpProp = getNearbyPumpProp(GetEntityCoords(vehicle), pumpDistance + 1.2)
                end

                -- Resolve closest station index for pricing & business data
                local nearIndex = findClosestPump(coords, 90.0, -35.0, 65.0)
                if not nearIndex and pumpProp then
                    nearIndex = findClosestPump(coords, 180.0, -50.0, 80.0)
                end

                local inStationZone = false
                local isRooftopHeli = false

                if isHeli then
                    -- Helicopter: strictly active only when landed on the station roof
                    if nearIndex and vehicle ~= 0 and checkHeliRooftop(nearIndex, vehicle, coords) then
                        inStationZone = true
                        isRooftopHeli = true
                    end
                else
                    -- Ground vehicle / player: strictly active only when close to a physical gas pump prop
                    if pumpProp and nearIndex then
                        inStationZone = true
                    end
                end

                if inStationZone then
                    waitMs = 0
                    local hasVehicle = vehicle ~= 0
                    sendInteraction(true, hasVehicle, isRooftopHeli)

                    if IsControlJustReleased(0, Config.interactKey or 38) then
                        vehicle = getActionVehicle(true)
                        CMGas.Client.OpenMenu(vehicle, nearIndex)
                    end
                else
                    sendInteraction(false, false)
                    waitMs = 350
                end
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
