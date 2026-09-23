local Config = CMTaxi.Config

-- A resource restart must never leave the taxi NUI owning keyboard/mouse
-- focus. Start with the game input restored; individual taxi panels acquire
-- focus only when the player explicitly opens them.
SetNuiFocus(false, false)
SetNuiFocusKeepInput(false)

CMTaxi.Client = CMTaxi.Client or {}

CMTaxi.Client.State = {
    onDuty = false,
    guiVisible = false,
    focusTablet = false,
    currentJob = nil,
    vehicle = 0,
    officeKey = nil,
    officePed = nil,
    progression = { xp = 0, level = 1 },
    rental = nil,
    shiftStats = { completed = 0, earnings = 0, tips = 0 },
    playerFareOffers = {},
}
local State = CMTaxi.Client.State

-- ============================================================
-- Server request/response helper (plain promises -- no ox_lib callback lib)
-- ============================================================

local pendingRequests = {}
local firstRideHintShown = false

local function makeRequestId()
    return ('%d-%d'):format(GetGameTimer(), math.random(100000, 999999))
end

local function request(serverEvent, timeoutMs, ...)
    local reqId = makeRequestId()
    local p = promise.new()
    pendingRequests[reqId] = p
    TriggerServerEvent(serverEvent, reqId, ...)
    SetTimeout(timeoutMs or 5000, function()
        if pendingRequests[reqId] then
            pendingRequests[reqId] = nil
            p:resolve({ success = false, timeout = true })
        end
    end)
    return Citizen.Await(p)
end

local function registerRequestHandler(eventName, onResolve)
    RegisterNetEvent(eventName, function(reqId, data)
        local p = pendingRequests[reqId]
        if p then
            pendingRequests[reqId] = nil
            if onResolve then onResolve(data) end
            p:resolve(data)
        end
    end)
end

registerRequestHandler('cm-taxi:client:takeJobResult')
registerRequestHandler('cm-taxi:client:cancelJobResult')
registerRequestHandler('cm-taxi:client:boardJobResult')
registerRequestHandler('cm-taxi:client:boardPassengerResult')
registerRequestHandler('cm-taxi:client:finishJobResult')
registerRequestHandler('cm-taxi:client:rentResult', function(data)
    if data and data.success then State.rental = data.rental end
end)
registerRequestHandler('cm-taxi:client:returnResult', function(data)
    if data and data.success then State.rental = nil end
end)

RegisterNetEvent('cm-taxi:client:playerFareOffers', function(offers)
    State.playerFareOffers = type(offers) == 'table' and offers or {}
end)

CMTaxi.Client.Request = request

-- ============================================================
-- NUI bridge
-- ============================================================

local function sendUI(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function toggleMeter(shouldShow)
    if State.guiVisible == shouldShow then return end
    State.guiVisible = shouldShow
    sendUI('setVisible', shouldShow)
    if not shouldShow and State.focusTablet then
        State.focusTablet = false
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
end

CMTaxi.Client.SendUI = sendUI
CMTaxi.Client.ToggleMeter = toggleMeter

-- ============================================================
-- Helpers
-- ============================================================

local function inTaxi(vehicle)
    if not vehicle or vehicle == 0 then return false end
    return Config.Vehicles[GetEntityModel(vehicle)] == true
end

local function isDriver(vehicle)
    local ped = PlayerPedId()
    return GetVehiclePedIsIn(ped, false) == vehicle and GetPedInVehicleSeat(vehicle, -1) == ped
end

local function zoneLabel(coords)
    local zoneCode = GetNameOfZone(coords.x, coords.y, coords.z)
    local zoneName = CMTaxi.Zones[zoneCode]
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
    if zoneName then
        return ('%s, %s'):format(street, zoneName)
    end
    return street
end

CMTaxi.Client.ZoneLabel = zoneLabel

local function round(value, decimals)
    local power = 10 ^ (decimals or 0)
    return math.floor((value * power) + 0.5) / power
end

CMTaxi.Client.Round = round

-- ============================================================
-- Duty
-- ============================================================

-- Player(src).state:set('cmTaxiDuty', ..., true) on the server replicates
-- here as a state bag -- listen on it directly instead of a bespoke event so
-- duty status can never drift out of sync with the server's own record.
AddStateBagChangeHandler('cmTaxiDuty', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    State.onDuty = value == true
end)

RegisterNetEvent('cm-taxi:client:progression', function(data)
    if type(data) == 'table' then
        State.progression = {
            xp = tonumber(data.xp) or 0,
            level = tonumber(data.level) or 1,
        }
    end
end)

RegisterNetEvent('cm-taxi:client:dutyResult', function(state)
    State.onDuty = state == true
    if not State.onDuty then
        State.playerFareOffers = {}
        if CMTaxi.Client.ResetFare and State.currentJob ~= nil then CMTaxi.Client.ResetFare(true) end
        State.progression = { xp = 0, level = 1 }
    end
end)

RegisterNetEvent('cm-taxi:client:shiftStats', function(data)
    if type(data) ~= 'table' then return end
    State.shiftStats = {
        completed = math.max(0, math.floor(tonumber(data.completed) or 0)),
        earnings = math.max(0, tonumber(data.earnings) or 0),
        tips = math.max(0, tonumber(data.tips) or 0),
    }
    if State.guiVisible then sendUI('setData', { shiftStats = State.shiftStats }) end
end)

RegisterNetEvent('cm-taxi:client:taxiRequestStatus', function(status, data)
    data = type(data) == 'table' and data or {}
    TriggerEvent('cm-taxi:client:passengerRequestStatus', status, data)
    if status == 'queued' then
        CMTaxi.Client.Notify(CMTaxi.Locale('taxi_request_queued'), 'info')
    elseif status == 'accepted' then
        CMTaxi.Client.Notify(CMTaxi.Locale('taxi_request_accepted', math.max(1, tonumber(data.etaMinutes) or 1)), 'success')
    elseif status == 'searching' then
        CMTaxi.Client.Notify(CMTaxi.Locale('taxi_request_searching'), 'info')
    elseif status == 'expired' then
        CMTaxi.Client.Notify(CMTaxi.Locale('taxi_request_expired'), 'warning')
    elseif status == 'cancelled' then
        CMTaxi.Client.Notify(CMTaxi.Locale('taxi_request_cancelled'), 'info')
    elseif status == 'completed' then
        CMTaxi.Client.Notify(CMTaxi.Locale('taxi_request_completed'), 'success')
    end
end)

RegisterNetEvent('cm-taxi:client:rentalState', function(data)
    State.rental = type(data) == 'table' and data or nil
    if not State.rental then
        firstRideHintShown = false
        sendUI('rentalIdleTimer', nil)
        sendUI('firstRideHint', false)
    end
end)

RegisterNetEvent('cm-taxi:client:rentalIdleTimer', function(remainingMs)
    sendUI('rentalIdleTimer', tonumber(remainingMs))
end)

RegisterNetEvent('cm-taxi:client:rentalExpired', function()
    State.rental = nil
    State.onDuty = false
    State.progression = { xp = 0, level = 1 }
    firstRideHintShown = false

    if CMTaxi.Client.ResetFare then CMTaxi.Client.ResetFare(true) end
    if CMTaxi.Client.ToggleMeter then CMTaxi.Client.ToggleMeter(false) end
    State.guiVisible = false
    sendUI('setVisible', false)
    sendUI('meterAvailable', false)
    sendUI('rentalIdleTimer', nil)
    sendUI('firstRideHint', false)
    sendUI('closeOffice')
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)

local function toggleDuty()
    local nextState = not State.onDuty
    TriggerServerEvent('cm-taxi:server:toggleDuty', nextState, State.officeKey)
end

CMTaxi.Client.ToggleDuty = toggleDuty

-- ============================================================
-- Meter keybind (focus tablet to click its buttons)
-- ============================================================

local function canUseMeter()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    State.vehicle = vehicle
    return vehicle ~= 0 and State.onDuty and inTaxi(vehicle) and isDriver(vehicle)
end

RegisterCommand(Config.Keybind.command, function()
    if not canUseMeter() then return end
    local shouldShow = not State.guiVisible
    State.focusTablet = shouldShow
    toggleMeter(shouldShow)
    SetNuiFocus(shouldShow, shouldShow)
    SetNuiFocusKeepInput(shouldShow)
end, false)
RegisterKeyMapping(Config.Keybind.command, Config.Keybind.description, 'keyboard', Config.Keybind.defaultKey)

local function keybindLabel()
    local ok, label = pcall(function()
        return GetControlInstructionalButton(0, joaat('+' .. Config.Keybind.command) | 0x80000000, true):sub(3)
    end)
    return ok and label or Config.Keybind.defaultKey
end

-- ============================================================
-- Meter loop
-- ============================================================

-- GlobalState.cmTaxiFares carries vector3 start/finish fields that the NUI's
-- JSON bridge cannot serialize -- send a plain, JSON-safe projection instead.
local function faresForUI()
    local out = {}
    local playerCoords = GetEntityCoords(PlayerPedId())
    for id, fare in pairs(GlobalState.cmTaxiFares or {}) do
        if fare and fare.name and not fare.driver then
            out[tostring(id)] = {
                name = fare.name,
                fare = fare.fare,
                distance = fare.start and round(#(fare.start - playerCoords)) or nil,
                tripDistance = (fare.start and fare.finish) and round(#(fare.finish - fare.start)) or nil,
                nearby = fare.start and #(fare.start - playerCoords) <= Config.NearbyFareDistance or false,
                playerRequested = fare.playerRequested == true,
                expiresAt = tonumber(fare.expiresAt),
            }
        end
    end
    for id, fare in pairs(State.playerFareOffers or {}) do
        if fare and fare.name and not fare.driver then
            out[tostring(id)] = {
                name = fare.name,
                fare = fare.fare,
                distance = fare.start and round(#(fare.start - playerCoords)) or tonumber(fare.distance),
                tripDistance = tonumber(fare.tripDistance),
                nearby = fare.start and #(fare.start - playerCoords) <= Config.NearbyFareDistance
                    or (not fare.start and fare.nearby == true),
                playerRequested = true,
                expiresAt = tonumber(fare.expiresAt),
            }
        end
    end
    return out
end

local function updateMeter()
    local vehicle = State.vehicle
    local data = {
        keybind = keybindLabel(),
        speed = { velocity = math.floor(GetEntitySpeed(vehicle) * 2.236936) },
        fares = faresForUI(),
        shiftStats = State.shiftStats,
    }

    if State.currentJob == nil then
        data.currentfareinfo = {
            active = false,
            customer = 'No active passenger',
            pickup = 'Available for dispatch',
            destination = 'No destination set',
            currentfare = '0.00',
            perminute = '2.00',
            basefare = '0.00',
            status = 'Ready for dispatch',
        }
        sendUI('setData', data)
        return
    end

    local fare = (GlobalState.cmTaxiFares or {})[State.currentJob] or State.currentJobData
    if not fare then
        data.currentfareinfo = {
            active = true,
            customer = 'Loading passenger',
            pickup = 'Loading pickup point',
            destination = 'Loading destination',
            currentfare = '0.00',
            perminute = '2.00',
            basefare = '0.00',
            status = 'Syncing active fare',
        }
        sendUI('setData', data)
        return
    end

    local start = fare.start or (State.currentJobData and State.currentJobData.start)
    local finish = fare.finish or (State.currentJobData and State.currentJobData.finish)
    local playerRequested = fare.playerRequested == true
    local passengerBoarded = fare.phase == 'boarded' or (State.currentJobData and State.currentJobData.boarded == true)
    data.currentfareinfo = {
        active = true,
        customer = fare.name,
        pickup = start and zoneLabel(start) or 'Pickup point pending',
        destination = finish and zoneLabel(finish) or '-',
        currentfare = ('%.2f'):format(fare.fare + Config.FuelBonus),
        perminute = '2.00',
        basefare = ('%.2f'):format(fare.fare),
        playerRequested = playerRequested,
        status = passengerBoarded and 'Passenger aboard' or (playerRequested and 'Player pickup' or 'Fare active'),
    }
    sendUI('setData', data)
end

CreateThread(function()
    local meterAvailable = false
    while true do
        local sleep = 800
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        State.vehicle = vehicle

        local canOpenMeter = vehicle ~= 0 and State.onDuty and inTaxi(vehicle) and isDriver(vehicle)
        if canOpenMeter then
            sleep = Config.MeterUpdateMs
            if State.guiVisible then updateMeter() end

            if State.rental and not firstRideHintShown then
                firstRideHintShown = true
                sendUI('firstRideHint', {
                    visible = true,
                    durationMs = Config.FirstRideHintMs,
                })
            end
        else
            toggleMeter(false)
        end

        if canOpenMeter ~= meterAvailable then
            meterAvailable = canOpenMeter
            sendUI('meterAvailable', meterAvailable)
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- Office blips + zone ped + interact prompt
-- ============================================================

CreateThread(function()
    for _, office in pairs(Config.Offices) do
        local blip = AddBlipForCoord(office.coords.x, office.coords.y, office.coords.z)
        SetBlipSprite(blip, office.blip.sprite)
        SetBlipScale(blip, office.blip.scale)
        SetBlipColour(blip, office.blip.colour)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(office.name)
        EndTextCommandSetBlipName(blip)
    end
end)

local function spawnOfficePed(officeKey)
    local office = Config.Offices[officeKey]
    local hash = GetHashKey(office.pedData.model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then return end

    local coords = office.pedData.coords
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, office.pedData.heading, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetModelAsNoLongerNeeded(hash)
    State.officePed = ped
end

local function despawnOfficePed()
    if State.officePed and DoesEntityExist(State.officePed) then
        DeletePed(State.officePed)
    end
    State.officePed = nil
end

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        local nearestKey, nearestDistance
        for key, office in pairs(Config.Offices) do
            local distance = #(coords - office.coords)
            if distance <= Config.OfficeDetectDistance and (not nearestDistance or distance < nearestDistance) then
                nearestKey, nearestDistance = key, distance
            end
        end

        if nearestKey ~= State.officeKey then
            despawnOfficePed()
            if GetResourceState('cm-ui') == 'started' then
                exports['cm-ui']:HideInteract()
            end
            if nearestKey == nil then
                -- Walked out of every office zone -- don't leave the panel
                -- open (and NUI focus stuck) behind the player.
                sendUI('closeOffice')
                SetNuiFocus(false, false)
            end
            State.officeKey = nearestKey
            if nearestKey then spawnOfficePed(nearestKey) end
        end

        if nearestKey then
            sleep = 0
            local office = Config.Offices[nearestKey]
            local pedDistance = #(coords - office.pedData.coords)

            if pedDistance <= Config.OfficeInteractDistance then
                if GetResourceState('cm-ui') == 'started' then
                    exports['cm-ui']:ShowInteract({
                        key = Config.InteractKeyLabel,
                        label = 'TAXI OFFICE',
                        name = Config.StationName,
                        role = 'CM TAXI',
                    })
                end
                if IsControlJustReleased(0, Config.InteractKey) then
                    CMTaxi.Client.OpenOffice()
                end
            elseif GetResourceState('cm-ui') == 'started' then
                exports['cm-ui']:HideInteract()
            end
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    despawnOfficePed()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    if GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract() end)
    end
end)

-- ============================================================
-- System decorator strip: real round-trip ping + in-game clock.
-- ============================================================

local lastPingMs = 0

RegisterNetEvent('cm-taxi:client:pong', function(sentAt)
    lastPingMs = GetGameTimer() - sentAt
end)

CreateThread(function()
    while true do
        TriggerServerEvent('cm-taxi:server:ping', GetGameTimer())
        local hours, minutes = GetClockHours(), GetClockMinutes()
        sendUI('sysinfo', {
            ping = lastPingMs,
            clock = ('%02d:%02d'):format(hours, minutes),
        })
        Wait(2500)
    end
end)
