local Config = CMWash.Config
CMWash.Client = CMWash.Client or {}

local menuOpen = false
local openPending = false
local washActive = false
local purchasePending = false
local currentSessionToken = nil
local currentLocationIndex = nil
local heldVehicle = 0
local heldCoords = nil
local heldHeading = nil
local promptVisible = false
local promptMode = nil
local promptClean = nil
local openRequestNonce = 0
local nuiReady = false
local lastInteractionPayload = nil
local queuedOpenContext = nil
local uiOpenConfirmed = false
local lastInteractionSentAt = 0

local function dbg(...)
    if Config.Debug then print('[CM-CARWASH]', ...) end
end

local function notify(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'info')
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

local function normalizePlate(value)
    return tostring(value or ''):upper():gsub('%s+', ''):sub(1, 12)
end

local function vehicleToNet(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    local ok, netId = pcall(NetworkGetNetworkIdFromEntity, vehicle)
    return ok and tonumber(netId) or 0
end

local function getVehiclePlate(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return '' end

    local statePlate
    pcall(function() statePlate = Entity(vehicle).state.cmPlate end)
    if statePlate and statePlate ~= '' then return normalizePlate(statePlate) end

    local ok, plate = pcall(GetVehicleNumberPlateText, vehicle)
    return ok and normalizePlate(plate) or ''
end

local function getVehicleDirt(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0.0 end
    local ok, dirt = pcall(GetVehicleDirtLevel, vehicle)
    if not ok then return 0.0 end
    dirt = tonumber(dirt) or 0.0
    return math.max(0.0, math.min(tonumber(Config.maxDirtLevel) or 15.0, dirt))
end

local function requestEntityControl(entity, timeoutMs)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end

    NetworkRequestControlOfEntity(entity)
    local deadline = GetGameTimer() + (timeoutMs or 500)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

local function holdVehicle(vehicle)
    local hold = Config.VehicleHold or {}
    if hold.enabled == false or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    heldVehicle = vehicle
    heldCoords = GetEntityCoords(vehicle)
    heldHeading = GetEntityHeading(vehicle)
    requestEntityControl(vehicle, 700)

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

    return true
end

local function keepVehicleHeld()
    local vehicle = heldVehicle
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    local hold = Config.VehicleHold or {}
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
    end
    if hold.freezePosition ~= false then
        FreezeEntityPosition(vehicle, true)
    end

    -- FreezeEntityPosition normally keeps the exact transform. Reapply only if
    -- another script/network migration moved it noticeably while this resource
    -- owns the service hold.
    if heldCoords then
        local current = GetEntityCoords(vehicle)
        if #(current - heldCoords) > 0.20 then
            SetEntityCoordsNoOffset(vehicle, heldCoords.x, heldCoords.y, heldCoords.z, false, false, false)
            if heldHeading then SetEntityHeading(vehicle, heldHeading) end
        end
    end
    return true
end

local function releaseHeldVehicle()
    local vehicle = heldVehicle
    heldVehicle = 0
    heldCoords = nil
    heldHeading = nil

    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    requestEntityControl(vehicle, 350)
    FreezeEntityPosition(vehicle, false)
    SetVehicleHandbrake(vehicle, false)
    SetVehicleBrakeLights(vehicle, false)
    -- Keep the engine off; the player can start it normally after the wash.
end

local function findClosestLocation(coords, maximumDistance)
    local closestIndex, closestDistance
    for index, location in ipairs(Config.Locations or {}) do
        local distance = #(coords - location)
        if distance <= maximumDistance and (not closestDistance or distance < closestDistance) then
            closestIndex = index
            closestDistance = distance
        end
    end
    return closestIndex, closestDistance
end

local function getDriverVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return 0, 'noVehicle' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return vehicle, 'passenger' end
    return vehicle, 'driver'
end

local function sendInteraction(visible, mode, isClean, force)
    mode = mode or 'driver'
    local sameState = promptVisible == visible
        and (not visible or (promptMode == mode and promptClean == (isClean == true)))

    promptVisible = visible
    promptMode = visible and mode or nil
    promptClean = visible and (isClean == true) or nil

    local interaction = Config.Interaction or {}
    local label = interaction.action or 'Open automatic car wash'
    local hint = interaction.hint or 'Cash payment · vehicle secured during service'

    if isClean then
        hint = interaction.cleanHint or 'This vehicle is already clean'
    end

    lastInteractionPayload = {
        action = 'interaction',
        visible = visible == true,
        enabled = visible == true,
        key = Config.interactKeyLabel or 'E',
        title = interaction.title or 'CAR WASH',
        label = label,
        hint = hint,
        clean = isClean == true,
    }

    local now = GetGameTimer()
    if sameState and force ~= true and (now - lastInteractionSentAt) < 1000 then return end
    lastInteractionSentAt = now
    SendNUIMessage(lastInteractionPayload)
end

local function sendOpenContext(context)
    queuedOpenContext = context
    if type(context) ~= 'table' then return end

    -- Do not gate the panel behind the ready callback. Some FiveM/CEF clients
    -- load the NUI page before Lua callbacks are registered and can miss the
    -- first ready request. Repeated delivery makes opening deterministic.
    SendNUIMessage({ action = 'open', ctx = context })

    CreateThread(function()
        local retryDelays = { 100, 250, 500, 900, 1500 }
        for _, delay in ipairs(retryDelays) do
            Wait(delay)
            if not menuOpen or uiOpenConfirmed then return end
            SendNUIMessage({ action = 'open', ctx = context })
        end
    end)
end

local function closeMenu(cancelSession)
    if washActive or purchasePending then return false end

    local token = currentSessionToken
    menuOpen = false
    openPending = false
    purchasePending = false
    currentSessionToken = nil
    currentLocationIndex = nil
    uiOpenConfirmed = false
    queuedOpenContext = nil

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    releaseHeldVehicle()

    if cancelSession ~= false and token then
        TriggerServerEvent('cm-carwash:server:cancelSession', token)
    end
    return true
end

local function openMenu(vehicle, locationIndex)
    if menuOpen or openPending or washActive then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        notify('Drive a vehicle into the wash bay.', 'error')
        return
    end

    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('Only the driver can use the car wash.', 'error')
        return
    end

    openPending = true
    currentLocationIndex = locationIndex
    openRequestNonce = openRequestNonce + 1
    local requestNonce = openRequestNonce
    sendInteraction(false)
    holdVehicle(vehicle)

    TriggerServerEvent('cm-carwash:server:requestOpen', {
        locationIndex = locationIndex,
        netId = vehicleToNet(vehicle),
        plate = getVehiclePlate(vehicle),
    })

    CreateThread(function()
        Wait(8000)
        if openPending and openRequestNonce == requestNonce then
            openPending = false
            currentSessionToken = nil
            currentLocationIndex = nil
            releaseHeldVehicle()
            notify('The car wash did not respond. Please try again.', 'error')
        end
    end)
end

RegisterNetEvent('cm-carwash:client:openSession', function(context)
    if not openPending or type(context) ~= 'table' then return end

    openPending = false
    openRequestNonce = openRequestNonce + 1
    menuOpen = true
    purchasePending = false
    uiOpenConfirmed = false
    currentSessionToken = tostring(context.sessionToken or '')

    -- Send the panel before and after focus. This avoids a blank focused NUI
    -- when Chromium is still completing its first page load.
    sendOpenContext(context)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', ctx = context })

    local expectedToken = currentSessionToken
    CreateThread(function()
        Wait(3500)
        if menuOpen and not uiOpenConfirmed and currentSessionToken == expectedToken then
            local token = currentSessionToken
            menuOpen = false
            openPending = false
            purchasePending = false
            currentSessionToken = nil
            currentLocationIndex = nil
            queuedOpenContext = nil
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'close' })
            releaseHeldVehicle()
            if token then TriggerServerEvent('cm-carwash:server:cancelSession', token) end
            notify('Car-wash UI failed to load. Restart cm-carwash and clear the FiveM cache if it repeats.', 'error')
        end
    end)
end)

RegisterNetEvent('cm-carwash:client:openDenied', function(message)
    openPending = false
    openRequestNonce = openRequestNonce + 1
    currentSessionToken = nil
    currentLocationIndex = nil
    releaseHeldVehicle()
    if message and message ~= '' then notify(message, 'error') end
end)

RegisterNetEvent('cm-carwash:client:washDenied', function(result)
    result = type(result) == 'table' and result or { message = 'The wash could not be started.' }
    purchasePending = false
    SendNUIMessage({ action = 'washResult', result = {
        ok = false,
        message = tostring(result.message or 'The wash could not be started.'),
        cash = tonumber(result.cash) or nil,
        close = result.close == true,
    } })

    if result.close == true then
        CreateThread(function()
            Wait(550)
            closeMenu(false)
        end)
    end
end)

local function washStage(progress)
    if progress < 22 then return 'Pre-rinse' end
    if progress < 65 then return 'Foam wash' end
    if progress < 88 then return 'Pressure rinse' end
    return 'Drying vehicle'
end

RegisterNetEvent('cm-carwash:client:washApproved', function(result)
    if not menuOpen or washActive or type(result) ~= 'table' then return end

    purchasePending = false
    washActive = true
    currentSessionToken = nil

    local vehicle = heldVehicle
    local expectedNetId = tonumber(result.netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle)
        or (expectedNetId > 0 and vehicleToNet(vehicle) ~= expectedNetId) then
        washActive = false
        menuOpen = false
        openPending = false
        purchasePending = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
        releaseHeldVehicle()
        notify('Payment completed and the clean state was saved, but the live vehicle became unavailable.', 'info')
        return
    end

    SetNuiFocus(false, false)
    local duration = math.max(1500, tonumber(result.durationMs) or tonumber(Config.durationMs) or 7000)
    local cleanTo = tonumber(result.cleanDirtLevel) or tonumber(Config.cleanDirtLevel) or 0.0
    local startDirt = getVehicleDirt(vehicle)
    local startedAt = GetGameTimer()

    SendNUIMessage({
        action = 'washStarted',
        durationMs = duration,
        cash = tonumber(result.cash) or 0,
        message = tostring(result.message or 'Cash accepted. Wash started.'),
    })

    CreateThread(function()
        while washActive and GetGameTimer() - startedAt < duration do
            Wait(100)

            if vehicle == 0 or not DoesEntityExist(vehicle) then
                washActive = false
                notify('The vehicle became unavailable during the wash.', 'error')
                break
            end

            keepVehicleHeld()
            local elapsed = GetGameTimer() - startedAt
            local progress = math.max(0.0, math.min(100.0, (elapsed / duration) * 100.0))
            local dirtNow = startDirt + ((cleanTo - startDirt) * (progress / 100.0))
            SetVehicleDirtLevel(vehicle, dirtNow + 0.0)
            pcall(function() WashDecalsFromVehicle(vehicle, progress / 100.0) end)

            SendNUIMessage({
                action = 'washProgress',
                progress = progress,
                stage = washStage(progress),
            })
        end

        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetVehicleDirtLevel(vehicle, cleanTo + 0.0)
            pcall(function() WashDecalsFromVehicle(vehicle, 1.0) end)
        end

        local completed = washActive
        washActive = false
        menuOpen = false
        openPending = false
        purchasePending = false
        SetNuiFocus(false, false)

        if completed then
            SendNUIMessage({
                action = 'washComplete',
                message = tostring(result.completeMessage or 'Vehicle washed and ready.'),
            })
            TriggerServerEvent('cm-carwash:server:washComplete', expectedNetId)
            notify('Vehicle washed.', 'success')
            Wait(1100)
        else
            SendNUIMessage({ action = 'close' })
        end

        SendNUIMessage({ action = 'close' })
        releaseHeldVehicle()
    end)
end)


RegisterNetEvent('cm-carwash:client:syncClean', function(netId, cleanDirtLevel)
    netId = tonumber(netId) or 0
    if netId <= 0 or not NetworkDoesNetworkIdExist(netId) then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetVehicleDirtLevel(vehicle, tonumber(cleanDirtLevel) or 0.0)
    pcall(function() WashDecalsFromVehicle(vehicle, 1.0) end)
end)

RegisterNetEvent('cm-carwash:client:notify', function(message, kind)
    notify(message, kind)
end)

RegisterNUICallback('ready', function(_, cb)
    nuiReady = true
    cb({ ok = true })

    if menuOpen and type(queuedOpenContext) == 'table' then
        sendOpenContext(queuedOpenContext)
    elseif lastInteractionPayload then
        SendNUIMessage(lastInteractionPayload)
    else
        sendInteraction(false, 'driver', false, true)
    end
end)

RegisterNUICallback('uiOpened', function(data, cb)
    if menuOpen then
        local token = type(data) == 'table' and tostring(data.sessionToken or '') or ''
        if token == '' or token == tostring(currentSessionToken or '') then
            uiOpenConfirmed = true
            queuedOpenContext = nil
        end
    end
    cb({ ok = true })
end)

RegisterNUICallback('startWash', function(_, cb)
    if not menuOpen or washActive or purchasePending or not currentSessionToken then
        cb({ ok = false })
        return
    end

    purchasePending = true
    local submittedToken = currentSessionToken
    TriggerServerEvent('cm-carwash:server:startWash', {
        sessionToken = submittedToken,
    })

    CreateThread(function()
        Wait(12000)
        if menuOpen and purchasePending and currentSessionToken == submittedToken then
            purchasePending = false
            SendNUIMessage({
                action = 'washResult',
                result = { ok = false, message = 'The car wash did not respond. Please try again.' }
            })
        end
    end)

    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = closeMenu(true) })
end)

RegisterNUICallback('escape', function(_, cb)
    cb({ ok = closeMenu(true) })
end)

CreateThread(function()
    local blip = Config.Blip or {}
    if blip.enabled == false then return end

    for _, position in ipairs(Config.Locations or {}) do
        local handle = AddBlipForCoord(position.x, position.y, position.z)
        SetBlipSprite(handle, blip.sprite or 100)
        SetBlipDisplay(handle, 4)
        SetBlipScale(handle, blip.scale or 0.70)
        SetBlipColour(handle, blip.color or 3)
        SetBlipAsShortRange(handle, blip.shortRange ~= false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(blip.name or 'Car Wash')
        EndTextCommandSetBlipName(handle)
    end
end)

-- Custom on-screen interaction prompt. It is intentionally available only
-- while the player is seated in the driver seat of a vehicle inside a wash bay.
CreateThread(function()
    while true do
        local waitMs = 750

        if menuOpen or openPending or washActive then
            sendInteraction(false)
            Wait(250)
        else
            local ped = PlayerPedId()
            local vehicle, mode = getDriverVehicle()

            if mode == 'driver'
                and vehicle ~= 0
                and DoesEntityExist(vehicle)
                and not IsPauseMenuActive()
                and not IsEntityDead(ped) then

                local vehicleCoords = GetEntityCoords(vehicle)
                local nearIndex = findClosestLocation(vehicleCoords, tonumber(Config.detectDistance) or 65.0)

                if nearIndex then
                    local locationIndex = findClosestLocation(vehicleCoords, tonumber(Config.interactDistance) or 8.0)
                    if locationIndex then
                        waitMs = 0
                        local clean = getVehicleDirt(vehicle) < (tonumber(Config.minDirtToOffer) or 0.5)
                        sendInteraction(true, 'driver', clean)

                        if IsControlJustReleased(0, Config.interactKey or 38) then
                            openMenu(vehicle, locationIndex)
                        end
                    else
                        sendInteraction(false)
                    end
                else
                    sendInteraction(false)
                end
            else
                -- No walking interaction and no passenger-seat interaction.
                sendInteraction(false)
            end
        end

        Wait(waitMs)
    end
end)

-- Keep the vehicle fixed and prevent conflicting driving/exit controls while
-- the menu or automatic service owns it.
CreateThread(function()
    while true do
        if heldVehicle ~= 0 then
            Wait(0)
            if not DoesEntityExist(heldVehicle) then
                heldVehicle = 0
                heldCoords = nil
                heldHeading = nil
                if menuOpen or openPending then
                    menuOpen = false
                    openPending = false
                    purchasePending = false
                    currentSessionToken = nil
                    SetNuiFocus(false, false)
                    SendNUIMessage({ action = 'close' })
                    notify('The selected vehicle is no longer available.', 'error')
                end
            else
                if IsEntityDead(PlayerPedId()) and not washActive then
                    purchasePending = false
                    closeMenu(true)
                    notify('Car wash closed because the player is unavailable.', 'error')
                else
                    keepVehicleHeld()
                end
                DisableControlAction(0, 23, true) -- enter vehicle
                DisableControlAction(0, 75, true) -- exit vehicle
                DisableControlAction(0, 71, true) -- accelerate
                DisableControlAction(0, 72, true) -- brake/reverse
                DisableControlAction(0, 76, true) -- handbrake
                DisableControlAction(0, 59, true) -- steering
                DisableControlAction(0, 60, true) -- steering
            end
        else
            Wait(300)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    releaseHeldVehicle()
end)
