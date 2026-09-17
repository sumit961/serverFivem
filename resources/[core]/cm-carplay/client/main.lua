--[[
    cm-carplay - Client main

    Wires the CarPlay NUI tablet to the actual vehicle: doors/windows/locks/
    engine/lights/seatbelt/seats, neon lights, drive modes and the tuner chip
    handling-modifier system,
    the music player (playback state, YouTube/local track resolution), and
    the HUD widgets the menu shows on open (waypoint, weather, time, player
    profile). client/sound.lua (loaded first) provides the actual audio
    engine this file leans on for music (GetCurrentTime, FetchData).
]]

windowsOpen = false -- shared with sound.lua's IsVehicleOpenOrDamaged

local carplayMenuOpen = false
local tunerChipInstalled = false
local carplayInstalled = false
local carplayInstallReason = nil
local carplayInstalledCache = {}     -- plate -> bool
local currentMusicVehicleKey = nil -- normalized plate of the vehicle currently playing music (used as its audioSourceId prefix, NOT a network id)
local currentMusicAudioSourceId = nil -- server-generated source id for the current track
local currentMusicSong = nil
local isMusicPlaying = false

local pendingYoutubeResolveCallbacks = {} -- videoId -> callback(result)
local pendingYoutubeResolveTimers = {} -- videoId -> timeout handle
local youtubePlaybackRequestId = 0

local function cancelPendingYoutubeResolves()
    youtubePlaybackRequestId = youtubePlaybackRequestId + 1
    for videoId in pairs(pendingYoutubeResolveCallbacks) do
        pendingYoutubeResolveCallbacks[videoId] = nil
        pendingYoutubeResolveTimers[videoId] = nil
    end
end

local function finishYoutubeResolve(videoId, result)
    local callback = pendingYoutubeResolveCallbacks[videoId]
    if not callback then return end
    pendingYoutubeResolveCallbacks[videoId] = nil
    -- FiveM's SetTimeout callback is one-shot; the timeout handler checks
    -- whether the pending callback still exists, so no cancellation native is
    -- required here and late timers cannot invoke the completed request.
    pendingYoutubeResolveTimers[videoId] = nil
    callback(result)
end

RegisterNetEvent('prism-carplay:client:receiveYoutubeAudioResolved', function(videoId, result)
    finishYoutubeResolve(videoId, result)
end)

-- Small helpers -------------------------------------------------------------

-- Mirrors the same extraction logic web/dist's audio engine uses client-side
-- (bare 11-char id, or one of the standard YouTube URL shapes).
local function extractYoutubeVideoId(url)
    if type(url) ~= 'string' then return nil end
    if url:match('^[%w_%-]+$') and #url == 11 then return url end

    local id = url:match('[?&]v=([%w_%-]+)')
    if id then return id:sub(1, 11) end

    id = url:match('youtu%.be/([%w_%-]+)')
    if id then return id:sub(1, 11) end

    id = url:match('youtube%.com/embed/([%w_%-]+)')
    if id then return id:sub(1, 11) end

    id = url:match('youtube%.com/shorts/([%w_%-]+)')
    if id then return id:sub(1, 11) end

    id = url:match('youtube%.com/live/([%w_%-]+)')
    if id then return id:sub(1, 11) end

    return nil
end

-- GetVehicleNumberPlateText pads the plate out to 8 characters; trim that
-- so it can be used as a stable cache/table key.
local function normalizePlate(plate)
    if not plate then
        return ""
    end
    return plate.gsub(plate, "%s+", "")
end

local function getVehiclePlateKey(vehicle)
    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if plate == '' then
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId and netId > 0 then
            return ('__net_%s'):format(netId)
        end
    end
    return plate
end

-- Music exists only for the lifetime of the current networked vehicle
-- entity. Key it by that entity instead of its number plate so custom plate
-- casing/formatting and duplicate plates cannot break or cross-wire playback.
local function getVehicleMusicKey(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId > 0 then
        return ('__net_%s'):format(netId)
    end
    return nil
end

local function getGameTime()
    return { hour = GetClockHours(), minute = GetClockMinutes() }
end

-- Weather -> plausible ambient temperature (°C) range, used to fake a
-- temperature reading since GTA doesn't expose one.
local WEATHER_TEMPERATURE_RANGES = {
    EXTRASUNNY = { min = 30, max = 38 },
    CLEAR      = { min = 22, max = 28 },
    CLOUDS     = { min = 18, max = 24 },
    SMOG       = { min = 20, max = 26 },
    FOGGY      = { min = 12, max = 18 },
    OVERCAST   = { min = 15, max = 20 },
    RAIN       = { min = 14, max = 18 },
    THUNDER    = { min = 12, max = 16 },
    CLEARING   = { min = 18, max = 24 },
    NEUTRAL    = { min = 20, max = 25 },
    SNOW       = { min = -5, max = 2 },
    BLIZZARD   = { min = -15, max = -5 },
    SNOWLIGHT  = { min = -2, max = 4 },
    XMAS       = { min = -8, max = 0 },
}

local function getWeatherInfo()
    local currentHash = GetPrevWeatherTypeHashName()
    local weatherType = "CLEAR"
    local knownWeatherTypes = {
        "EXTRASUNNY", "CLEAR", "CLOUDS", "SMOG", "FOGGY", "OVERCAST", "RAIN",
        "THUNDER", "CLEARING", "NEUTRAL", "SNOW", "BLIZZARD", "SNOWLIGHT", "XMAS",
    }
    for _, name in ipairs(knownWeatherTypes) do
        if currentHash == GetHashKey(name) then
            weatherType = name
            break
        end
    end

    local range = WEATHER_TEMPERATURE_RANGES[weatherType] or { min = 20, max = 25 }
    return {
        type = weatherType,
        temperature = math.random(range.min, range.max),
    }
end

local function getPlayerPosition()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    return {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = GetEntityHeading(ped),
    }
end

local function getWaypointInfo()
    if not IsWaypointActive() then
        return nil
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        return nil
    end

    local blipCoords = GetBlipInfoIdCoord(blip)
    local distance = #(vector2(playerCoords.x, playerCoords.y) - vector2(blipCoords.x, blipCoords.y))

    local streetHash, crossingHash = GetStreetNameAtCoord(blipCoords.x, blipCoords.y, blipCoords.z)
    local streetName = GetStreetNameFromHashKey(streetHash)
    local crossingName = GetStreetNameFromHashKey(crossingHash)

    local fullStreetName = streetName
    if crossingName and crossingName ~= "" then
        fullStreetName = streetName .. " / " .. crossingName
    end

    return {
        active = true,
        x = blipCoords.x,
        y = blipCoords.y,
        z = blipCoords.z,
        distance = math.floor(distance),
        streetName = fullStreetName,
    }
end

-- Player profile (name/mugshot/current vehicle plate) --------------------
-- Ped headshots take a few frames to render, so this polls until ready
-- (capped at 100 * 50ms = 5s) before invoking the callback.

local pedheadshotHandle = nil
local pedheadshotTxd = nil

local function clearPedheadshot()
    if pedheadshotHandle then
        UnregisterPedheadshot(pedheadshotHandle)
        pedheadshotHandle = nil
        pedheadshotTxd = nil
    end
end

local function getPlayerProfile(callback)
    local ped = PlayerPedId()
    local playerName = GetPlayerName(PlayerId())

    local vehiclePlate = nil
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        vehiclePlate = GetVehicleNumberPlateText(vehicle)
    end

    -- Reuse the cached headshot if it's still valid.
    if pedheadshotHandle and IsPedheadshotValid(pedheadshotHandle) and pedheadshotTxd then
        callback({ name = playerName, mugshot = pedheadshotTxd, vehiclePlate = vehiclePlate })
        return
    end

    clearPedheadshot()
    pedheadshotHandle = RegisterPedheadshot(ped)
    local thisHandle = pedheadshotHandle

    CreateThread(function()
        local attempts = 0
        while not IsPedheadshotReady(thisHandle) and attempts < 100 do
            Wait(50)
            attempts = attempts + 1
        end

        local mugshot = nil
        if IsPedheadshotReady(thisHandle) then
            mugshot = GetPedheadshotTxdString(thisHandle)
            pedheadshotTxd = mugshot
        end

        callback({ name = playerName, mugshot = mugshot, vehiclePlate = vehiclePlate })
    end)
end

-- Menu open/close -----------------------------------------------------------

local function setMenuVisible(visible, focus)
    carplayMenuOpen = visible
    if focus == false then
        focus = false
    else
        focus = visible
    end

    SetNuiFocus(visible, focus)
    SendNUIMessage({ action = "setVisible", data = visible })
end

-- cm-admin owns the shared GTA map atlas and its effective world bounds.
-- Refresh the bounds whenever CarPlay opens so an admin calibration change is
-- picked up without restarting this resource.
local function requestMapBounds()
    TriggerServerEvent('prism-carplay:server:getMapBounds')
end

RegisterNetEvent('prism-carplay:client:receiveMapBounds', function(bounds)
    SendNUIMessage({ action = "updateMapBounds", data = bounds })
end)

requestMapBounds()

local function openCarplayMenu()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        Config.Notify("You must be in a vehicle to use CarPlay", "error")
        return
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        Config.Notify("Only the driver can use CarPlay", "error")
        return
    end

    if Config.RequireCarplayItem then
        -- Always refresh on open. Manage Vehicles settings can be changed
        -- while the player remains in the same vehicle, so a cached false
        -- from the entry poll must not permanently deny CarPlay.
        local plate = getVehiclePlateKey(vehicle)
        carplayInstalled = nil
        carplayInstallReason = nil
        TriggerServerEvent('prism-carplay:server:getCarplayInstalled', plate, NetworkGetNetworkIdFromEntity(vehicle))
        local deadline = GetGameTimer() + 2000
        while carplayInstalled == nil and GetGameTimer() < deadline do
            Wait(50)
        end
        if carplayInstalled ~= true then
            if carplayInstalled == nil then
                Config.Notify("CarPlay could not verify this vehicle. Please try again", "error")
            elseif carplayInstallReason == 'vehicle_not_found' then
                Config.Notify("CarPlay could not verify your current vehicle. Please try again", "error")
            else
                Config.Notify("This vehicle model is not enabled for CarPlay and no CarPlay unit is installed", "error")
            end
            return
        end
    end

    if carplayMenuOpen then
        return
    end

    SendNUIMessage({ action = "updatePrimaryColor", data = Config.PrimaryColor })
    SendNUIMessage({ action = "setLocale", data = GetLocaleTable() })
    SendNUIMessage({ action = "updatePlayerPosition", data = getPlayerPosition() })
    SendNUIMessage({ action = "updateGameTime", data = getGameTime() })
    SendNUIMessage({ action = "updateWeather", data = getWeatherInfo() })
    requestMapBounds()

    getPlayerProfile(function(profile)
        SendNUIMessage({ action = "updatePlayerProfile", data = profile })
    end)

    SendNUIMessage({ action = "updateWaypoint", data = getWaypointInfo() })
    SendNUIMessage({ action = "updateTunerChip", data = tunerChipInstalled })

    if currentMusicVehicleKey and currentMusicSong then
        SendNUIMessage({ action = "musicStarted", data = { song = currentMusicSong } })
    end

    setMenuVisible(true)
end

local function closeCarplayMenu()
    if carplayMenuOpen then
        setMenuVisible(false)
    end
end

-- Periodic HUD widget refreshers while the menu is open ---------------------

CreateThread(function()
    while true do
        if carplayMenuOpen then
            SendNUIMessage({ action = "updatePlayerPosition", data = getPlayerPosition() })
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        if carplayMenuOpen then
            SendNUIMessage({ action = "updateGameTime", data = getGameTime() })
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        if carplayMenuOpen then
            SendNUIMessage({ action = "updateWeather", data = getWeatherInfo() })
        end
        Wait(30000)
    end
end)

CreateThread(function()
    while true do
        if carplayMenuOpen then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            local plate = nil
            if vehicle ~= 0 then
                plate = GetVehicleNumberPlateText(vehicle)
            end
            SendNUIMessage({ action = "updateVehiclePlate", data = plate })
        end
        Wait(5000)
    end
end)

CreateThread(function()
    while true do
        if carplayMenuOpen then
            SendNUIMessage({ action = "updateWaypoint", data = getWaypointInfo() })
        end
        Wait(1000)
    end
end)

-- Keybind / command ----------------------------------------------------------

-- openCarplayMenu() itself performs the "in a vehicle" / "driver seat" /
-- "CarPlay installed" checks below before priming and showing the NUI.
RegisterCommand('carplay', function()
    openCarplayMenu()
end, false)
RegisterKeyMapping('carplay', 'Open CarPlay', 'keyboard', Config.Keybind)

-- Vehicle controls: doors/windows/locks/engine/lights/seats -----------------

RegisterNUICallback('closeMenu', function(data, cb)
    closeCarplayMenu()
    cb('ok')
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    local x = tonumber(data and data.x)
    local y = tonumber(data and data.y)
    if x and y and math.abs(x) <= 20000 and math.abs(y) <= 20000 then
        SetNewWaypoint(x + 0.0, y + 0.0)
    end
    cb('ok')
end)

RegisterNUICallback('toggleDoors', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        if data.open then
            for doorIndex = 0, 3 do
                SetVehicleDoorOpen(vehicle, doorIndex, false, false)
            end
        else
            SetVehicleDoorsShut(vehicle, false)
        end
    end
    cb('ok')
end)

RegisterNUICallback('toggleTrunk', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        local trunkDoor = GetNumberOfVehicleDoors(vehicle) - 1
        if data.open then
            SetVehicleDoorOpen(vehicle, trunkDoor, false, false)
        else
            SetVehicleDoorShut(vehicle, trunkDoor, false)
        end
    end
    cb('ok')
end)

RegisterNUICallback('toggleSeatbelt', function(data, cb)
    Config.ToggleSeatbelt(data.on)
    cb('ok')
end)

RegisterNUICallback('toggleWindows', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        if data.down then
            RollDownWindows(vehicle)
            windowsOpen = true
        else
            RollUpWindow(vehicle, 0)
            RollUpWindow(vehicle, 1)
            RollUpWindow(vehicle, 2)
            RollUpWindow(vehicle, 3)
            windowsOpen = false
        end
    end
    cb('ok')
end)

RegisterNUICallback('toggleLock', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        if data.locked then
            SetVehicleDoorsLocked(vehicle, 2)
        else
            SetVehicleDoorsLocked(vehicle, 1)
        end
    end
    cb('ok')
end)

RegisterNUICallback('toggleEngine', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        SetVehicleEngineOn(vehicle, data.on and true or false, false, true)
    end
    cb('ok')
end)

RegisterNUICallback('toggleLights', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        if data.on then
            SetVehicleLights(vehicle, 2)
        else
            SetVehicleLights(vehicle, 1)
        end
    end
    cb('ok')
end)

RegisterNUICallback('toggleDoor', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        if data.open then
            SetVehicleDoorOpen(vehicle, data.door, false, false)
        else
            SetVehicleDoorShut(vehicle, data.door, false)
        end
    end
    cb('ok')
end)

RegisterNUICallback('selectSeat', function(data, cb)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        local seatIndex = data.seat - 1
        if IsVehicleSeatFree(vehicle, seatIndex) then
            SetPedIntoVehicle(ped, vehicle, seatIndex)
        end
    end
    cb('ok')
end)

RegisterNUICallback('getVehicleInfo', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        cb({
            drivetrain = "N/A",
            driveBias = 0,
            fuelLevel = 0,
            engineHealth = 0,
            bodyHealth = 0,
            tireHealth = 0,
            engineTemp = 0,
        })
        return
    end

    local driveBias = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fDriveBiasFront")
    local drivetrain = "AWD"
    if driveBias >= 0.6 then
        drivetrain = "FWD"
    elseif driveBias <= 0.4 then
        drivetrain = "RWD"
    end

    local fuelLevel = GetVehicleFuelLevel(vehicle)

    local engineHealth = math.floor(GetVehicleEngineHealth(vehicle) / 10)
    engineHealth = math.max(0, math.min(100, engineHealth))

    local bodyHealth = math.floor(GetVehicleBodyHealth(vehicle) / 10)
    bodyHealth = math.max(0, math.min(100, bodyHealth))

    local wheelCount = GetVehicleNumberOfWheels(vehicle)
    local wheelHealthTotal = 0
    for wheelIndex = 0, wheelCount - 1 do
        wheelHealthTotal = wheelHealthTotal + GetVehicleWheelHealth(vehicle, wheelIndex)
    end
    local tireHealth = math.floor((wheelHealthTotal / wheelCount) / 10)
    tireHealth = math.max(0, math.min(100, tireHealth))

    local engineTemp = 70
    if not GetIsVehicleEngineRunning(vehicle) then
        engineTemp = 25
    else
        engineTemp = 70 + math.floor((100 - engineHealth) * 0.5)
    end

    cb({
        drivetrain = drivetrain,
        driveBias = driveBias,
        fuelLevel = fuelLevel,
        engineHealth = engineHealth,
        bodyHealth = bodyHealth,
        tireHealth = tireHealth,
        engineTemp = engineTemp,
    })
end)

-- Tuner chip ------------------------------------------------------------
-- Applies a percentage boost (relative to the vehicle's OWN base handling,
-- cached per-vehicle the first time it's touched) capped by Config.TunerChip
-- maxPercent limits.

local baseHandlingCache = {}          -- vehicle -> { topSpeed, gearChange, dragCoeff, brakeForce }
local pendingTunerChipRequests = {}   -- plate -> NUI callback awaiting server data

local function getBaseHandling(vehicle)
    if not baseHandlingCache[vehicle] then
        baseHandlingCache[vehicle] = {
            topSpeed = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel"),
            gearChange = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fClutchChangeRateScaleUpShift"),
            dragCoeff = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff"),
            brakeForce = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fBrakeForce"),
        }
    end
    return baseHandlingCache[vehicle]
end

local vehicleTunerChipData = {}       -- plate -> { installed, boostPower, gearChange, acceleration, brakes }
local vehicleModificationsData = {}   -- plate -> { driveMode, neonPatterns, neonLocations, neonHue, ... }
local pendingModificationsRequests = {}

local currentNeonThreadId = 0
local currentNeonPattern = "solid"
local currentNeonModifications = nil

local function applyTunerChipHandling(vehicle, tunerChip)
    if not vehicle or vehicle == 0 or not tunerChip then
        return
    end

    local base = getBaseHandling(vehicle)

    if tunerChip.boostPower and tunerChip.boostPower > 0 then
        local maxPercent = Config.TunerChip.BoostPower.maxPercent
        local boost = base.topSpeed * (tunerChip.boostPower / 100) * (maxPercent / 100)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel", base.topSpeed + boost + 0.0)
        ModifyVehicleTopSpeed(vehicle, 1.0)
    end

    if tunerChip.gearChange and tunerChip.gearChange > 0 then
        local maxPercent = Config.TunerChip.GearChange.maxPercent
        local boost = base.gearChange * (tunerChip.gearChange / 100) * (maxPercent / 100)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fClutchChangeRateScaleUpShift", base.gearChange + boost + 0.0)
    end

    if tunerChip.acceleration and tunerChip.acceleration > 0 then
        local maxPercent = Config.TunerChip.Acceleration.maxPercent
        local reduction = base.dragCoeff * (tunerChip.acceleration / 100) * (maxPercent / 100)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", base.dragCoeff - reduction + 0.0)
    end

    if tunerChip.brakes and tunerChip.brakes > 0 then
        local maxPercent = Config.TunerChip.Brakes.maxPercent
        local boost = base.brakeForce * (tunerChip.brakes / 100) * (maxPercent / 100)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fBrakeForce", base.brakeForce + boost + 0.0)
    end
end

local function resetTunerChipHandling(vehicle)
    if not vehicle or vehicle == 0 then
        return
    end

    local base = baseHandlingCache[vehicle]
    if base then
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel", base.topSpeed + 0.0)
        ModifyVehicleTopSpeed(vehicle, 1.0)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fClutchChangeRateScaleUpShift", base.gearChange + 0.0)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", base.dragCoeff + 0.0)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", "fBrakeForce", base.brakeForce + 0.0)
    end
end

RegisterNetEvent('prism-carplay:client:receiveTunerChipData', function(plate, tunerChip)
    vehicleTunerChipData[plate] = tunerChip

    local pendingCb = pendingTunerChipRequests[plate]
    if pendingCb then
        pendingTunerChipRequests[plate] = nil
        if tunerChip then
            pendingCb({
                boostPower = tunerChip.boostPower or 0,
                gearChange = tunerChip.gearChange or 0,
                acceleration = tunerChip.acceleration or 0,
                brakes = tunerChip.brakes or 0,
            })
        else
            pendingCb({ boostPower = 0, gearChange = 0, acceleration = 0, brakes = 0 })
        end
    end

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehiclePlateKey(vehicle) == plate then
        tunerChipInstalled = (tunerChip and tunerChip.installed) and true or false
        SendNUIMessage({ action = 'updateTunerChip', data = tunerChipInstalled })
        if tunerChip then
            applyTunerChipHandling(vehicle, tunerChip)
        end
    end
end)

RegisterNetEvent('prism-carplay:client:tunerChipDataUpdated', function(plate, tunerChip)
    vehicleTunerChipData[plate] = tunerChip

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehiclePlateKey(vehicle) == plate then
        local wasInstalled = tunerChipInstalled
        tunerChipInstalled = (tunerChip and tunerChip.installed) and true or false
        SendNUIMessage({ action = 'updateTunerChip', data = tunerChipInstalled })

        if wasInstalled and not tunerChipInstalled then
            SendNUIMessage({ action = 'navigateHome' })
        end

        if tunerChip then
            applyTunerChipHandling(vehicle, tunerChip)
        end
    end
end)

RegisterNetEvent('prism-carplay:client:useCarplayItem', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        Config.Notify("You must be in a vehicle to install CarPlay", "error")
        return
    end

    local plate = getVehiclePlateKey(vehicle)
    local nowInstalled = not (carplayInstalledCache[plate] or false)
    carplayInstalledCache[plate] = nowInstalled
    carplayInstalled = nowInstalled

    TriggerServerEvent('prism-carplay:server:saveCarplayInstalled', plate, nowInstalled)

    if nowInstalled then
        Config.Notify("CarPlay installed in this vehicle", "success")
    else
        Config.Notify("CarPlay removed from this vehicle", "info")
        if carplayMenuOpen then
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'setVisible', data = false })
            carplayMenuOpen = false
        end
    end
end)

RegisterNetEvent('prism-carplay:client:receiveCarplayInstalled', function(plate, installed, reason)
    carplayInstalledCache[plate] = (installed == true)

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehiclePlateKey(vehicle) == plate then
        carplayInstalled = (installed == true)
        carplayInstallReason = reason
    end
end)

RegisterNetEvent('prism-carplay:client:carplayInstalledUpdated', function(plate, installed)
    carplayInstalledCache[plate] = (installed == true)

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehiclePlateKey(vehicle) == plate then
        carplayInstalled = (installed == true)
    end
end)

RegisterNetEvent('prism-carplay:client:useTunerChip', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        Config.Notify("You must be in a vehicle to install a tuner chip", "error")
        return
    end

    local plate = getVehiclePlateKey(vehicle)
    local tunerChip = vehicleTunerChipData[plate] or {}
    tunerChip.installed = not tunerChip.installed

    if not tunerChip.installed then
        tunerChip.boostPower = 0
        tunerChip.gearChange = 0
        tunerChip.acceleration = 0
        tunerChip.brakes = 0
        resetTunerChipHandling(vehicle)
    end

    vehicleTunerChipData[plate] = tunerChip
    TriggerServerEvent('prism-carplay:server:saveTunerChipData', plate, tunerChip)

    tunerChipInstalled = tunerChip.installed
    SendNUIMessage({ action = 'updateTunerChip', data = tunerChipInstalled })

    if tunerChipInstalled then
        Config.Notify("Tuner Chip Installed - Statistics and Modifications unlocked", "success")
    else
        SendNUIMessage({ action = 'navigateHome' })
        Config.Notify("Tuner Chip Removed - Statistics and Modifications locked", "error")
    end
end)

RegisterNUICallback('removeTunerChip', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        cb({ success = false })
        return
    end

    local plate = getVehiclePlateKey(vehicle)
    local tunerChip = { installed = false, boostPower = 0, gearChange = 0, acceleration = 0, brakes = 0 }
    vehicleTunerChipData[plate] = tunerChip
    TriggerServerEvent('prism-carplay:server:saveTunerChipData', plate, tunerChip)

    resetTunerChipHandling(vehicle)

    tunerChipInstalled = false
    SendNUIMessage({ action = 'updateTunerChip', data = false })
    SendNUIMessage({ action = 'navigateHome' })

    cb({ success = true })
end)

RegisterNUICallback('getTunerChipValues', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        cb({ boostPower = 0, gearChange = 0, acceleration = 0, brakes = 0 })
        return
    end

    getBaseHandling(vehicle)
    local plate = getVehiclePlateKey(vehicle)
    local tunerChip = vehicleTunerChipData[plate]

    if tunerChip then
        cb({
            boostPower = tunerChip.boostPower or 0,
            gearChange = tunerChip.gearChange or 0,
            acceleration = tunerChip.acceleration or 0,
            brakes = tunerChip.brakes or 0,
        })
    else
        pendingTunerChipRequests[plate] = cb
        TriggerServerEvent('prism-carplay:server:getTunerChipData', plate)
    end
end)

RegisterNUICallback('setTunerChipValue', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and data.type and data.value then
        local value = data.value
        local base = getBaseHandling(vehicle)
        local plate = getVehiclePlateKey(vehicle)

        local tunerChip = vehicleTunerChipData[plate]
        if not tunerChip then
            tunerChip = { boostPower = 0, gearChange = 0, acceleration = 0, brakes = 0, installed = true }
        end

        if data.type == 'boostPower' then
            local maxPercent = Config.TunerChip.BoostPower.maxPercent
            local boost = base.topSpeed * (value / 100) * (maxPercent / 100)
            SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveMaxFlatVel", base.topSpeed + boost + 0.0)
            ModifyVehicleTopSpeed(vehicle, 1.0)
            tunerChip.boostPower = value
        elseif data.type == 'gearChange' then
            local maxPercent = Config.TunerChip.GearChange.maxPercent
            local boost = base.gearChange * (value / 100) * (maxPercent / 100)
            SetVehicleHandlingFloat(vehicle, "CHandlingData", "fClutchChangeRateScaleUpShift", base.gearChange + boost + 0.0)
            tunerChip.gearChange = value
        elseif data.type == 'acceleration' then
            local maxPercent = Config.TunerChip.Acceleration.maxPercent
            local reduction = base.dragCoeff * (value / 100) * (maxPercent / 100)
            SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", base.dragCoeff - reduction + 0.0)
            tunerChip.acceleration = value
        elseif data.type == 'brakes' then
            local maxPercent = Config.TunerChip.Brakes.maxPercent
            local boost = base.brakeForce * (value / 100) * (maxPercent / 100)
            SetVehicleHandlingFloat(vehicle, "CHandlingData", "fBrakeForce", base.brakeForce + boost + 0.0)
            tunerChip.brakes = value
        end

        tunerChip.installed = true
        vehicleTunerChipData[plate] = tunerChip
        TriggerServerEvent('prism-carplay:server:saveTunerChipData', plate, tunerChip)
    end

    cb('ok')
end)

-- Neon lights -------------------------------------------------------------

-- HSB (hue 0-360, saturation/brightness 0-100) -> RGB (0-255), used because
-- the NUI works in HSB but SetVehicleNeonLightsColour wants RGB.
local function hsbToRgb(hue, saturation, brightness)
    local h = hue / 360
    local s = saturation / 100
    local v = brightness / 100

    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    local r, g, b
    local sector = i % 6
    if sector == 0 then r, g, b = v, t, p
    elseif sector == 1 then r, g, b = q, v, p
    elseif sector == 2 then r, g, b = p, v, t
    elseif sector == 3 then r, g, b = p, q, v
    elseif sector == 4 then r, g, b = t, p, v
    elseif sector == 5 then r, g, b = v, p, q
    end

    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

local function isNeonLocationEnabled(neonLocationId, enabledLocations)
    for _, location in ipairs(enabledLocations) do
        if location.id == neonLocationId and location.enabled then
            return true
        end
    end
    return false
end

local function applyNeonSolidColor(vehicle, modifications)
    if not vehicle or vehicle == 0 or not modifications then
        return
    end

    local hue = modifications.neonHue or 120
    local saturation = modifications.neonSaturation or 100
    local brightness = modifications.neonBrightness or 50
    local r, g, b = hsbToRgb(hue, saturation, brightness)
    SetVehicleNeonLightsColour(vehicle, r, g, b)

    local enabledLocations = modifications.neonLocations or {}
    for _, location in ipairs(Config.NeonLocations) do
        SetVehicleNeonLightEnabled(vehicle, location.index, isNeonLocationEnabled(location.id, enabledLocations))
    end
end

local function bumpNeonThreadId()
    currentNeonThreadId = currentNeonThreadId + 1
    currentNeonPattern = nil
end

-- Pattern: 1 = solid, 2 = pulse, 3 = flash, 4 = fade (also accepts the
-- matching string names, used by the drive-mode/modifications NUI payload).
local function applyNeonPattern(vehicle, pattern, modifications)
    if not vehicle or vehicle == 0 or not modifications then
        return
    end

    currentNeonModifications = modifications

    local patternId = pattern
    if type(pattern) == "string" then
        if pattern == "solid" then patternId = 1
        elseif pattern == "pulse" then patternId = 2
        elseif pattern == "flash" then patternId = 3
        elseif pattern == "fade" then patternId = 4
        end
    end

    local currentPatternId = currentNeonPattern
    if type(currentNeonPattern) == "string" then
        if currentNeonPattern == "solid" then currentPatternId = 1
        elseif currentNeonPattern == "pulse" then currentPatternId = 2
        elseif currentNeonPattern == "flash" then currentPatternId = 3
        elseif currentNeonPattern == "fade" then currentPatternId = 4
        end
    end

    -- Already running this exact pattern: just refresh locations/color, don't
    -- restart the animation thread.
    if patternId == currentPatternId then
        if patternId ~= 3 then
            local enabledLocations = modifications.neonLocations or {}
            for _, location in ipairs(Config.NeonLocations) do
                SetVehicleNeonLightEnabled(vehicle, location.index, isNeonLocationEnabled(location.id, enabledLocations))
            end
        end
        if patternId == 1 then
            local hue = modifications.neonHue or 120
            local saturation = modifications.neonSaturation or 100
            local brightness = modifications.neonBrightness or 50
            local r, g, b = hsbToRgb(hue, saturation, brightness)
            SetVehicleNeonLightsColour(vehicle, r, g, b)
        end
        return
    end

    bumpNeonThreadId()
    currentNeonPattern = pattern

    if patternId == 1 then
        applyNeonSolidColor(vehicle, modifications)
        return
    end

    if patternId == 2 or patternId == 4 then
        local enabledLocations = modifications.neonLocations or {}
        for _, location in ipairs(Config.NeonLocations) do
            SetVehicleNeonLightEnabled(vehicle, location.index, isNeonLocationEnabled(location.id, enabledLocations))
        end
    end

    currentNeonThreadId = currentNeonThreadId + 1
    local threadId = currentNeonThreadId

    CreateThread(function()
        local t = 0
        while true do
            if threadId ~= currentNeonThreadId then
                return
            end
            if GetVehiclePedIsIn(PlayerPedId(), false) ~= vehicle then
                return
            end

            local activeModifications = currentNeonModifications or modifications
            local hue = activeModifications.neonHue or 120
            local saturation = activeModifications.neonSaturation or 100
            local brightness = activeModifications.neonBrightness or 50

            if patternId == 2 then
                -- Pulse: sine-wave brightness between 30% and 100%.
                local pulseBrightness = brightness * (0.3 + 0.7 * math.abs(math.sin(t)))
                local r, g, b = hsbToRgb(hue, saturation, pulseBrightness)
                SetVehicleNeonLightsColour(vehicle, r, g, b)
                t = t + 0.05
            elseif patternId == 3 then
                -- Flash: all enabled locations blink on/off together.
                local lightsOn = math.floor(t) % 2 == 0
                local enabledLocations = activeModifications.neonLocations or {}
                for _, location in ipairs(Config.NeonLocations) do
                    local locationEnabled = isNeonLocationEnabled(location.id, enabledLocations)
                    SetVehicleNeonLightEnabled(vehicle, location.index, locationEnabled and lightsOn)
                end
                t = t + 0.15
            elseif patternId == 4 then
                -- Fade: hue cycles continuously through the color wheel.
                local fadeHue = (hue + t * 50) % 360
                local r, g, b = hsbToRgb(fadeHue, saturation, brightness)
                SetVehicleNeonLightsColour(vehicle, r, g, b)
                t = t + 0.02
            end

            Wait(50)
        end
    end)
end

-- Applies drive mode + neon settings from a modifications payload (used on
-- vehicle-enter and whenever modifications data is (re)received).
local function applyVehicleModifications(vehicle, modifications)
    if not vehicle or vehicle == 0 or not modifications then
        return
    end

    if modifications.driveMode then
        setDriveMode(vehicle, modifications.driveMode)
    end

    local activePatternId = 1
    for _, pattern in ipairs(modifications.neonPatterns or {}) do
        if pattern.enabled then
            activePatternId = pattern.id
            break
        end
    end

    applyNeonPattern(vehicle, activePatternId, modifications)
end

-- Drive modes ---------------------------------------------------------------

local vehicleBaseHandlingFields = {
    "fInitialDriveMaxFlatVel", "fInitialDragCoeff", "fBrakeForce",
    "fTractionCurveMax", "fTractionCurveMin", "fSuspensionForce",
    "fDriveInertia", "fSteeringLock", "fTractionCurveLateral",
    "fLowSpeedTractionLossMult",
}
local vehicleBaseHandlingCache = {}   -- vehicle -> { field -> baseValue }
local activeDriveModeByVehicle = {}   -- vehicle -> mode name

local function getVehicleBaseDriveHandling(vehicle)
    if not vehicleBaseHandlingCache[vehicle] then
        local base = {}
        for _, field in ipairs(vehicleBaseHandlingFields) do
            base[field] = GetVehicleHandlingFloat(vehicle, "CHandlingData", field)
        end
        vehicleBaseHandlingCache[vehicle] = base
    end
    return vehicleBaseHandlingCache[vehicle]
end

-- Applies (or resets) a Config.DriveModes entry to a vehicle's handling.
-- Sports/Eco are multiplicative against the vehicle's own base handling;
-- Drift is additive. Always restores from the cached base first so modes
-- can be swapped repeatedly without compounding.
function setDriveMode(vehicle, mode)
    if not vehicle or vehicle == 0 then
        return
    end

    local modeConfig = Config.DriveModes[mode]
    if not modeConfig then
        modeConfig = Config.DriveModes.normal
        mode = "normal"
    end

    local base = getVehicleBaseDriveHandling(vehicle)

    for field, value in pairs(base) do
        SetVehicleHandlingFloat(vehicle, "CHandlingData", field, value + 0.0)
    end
    ModifyVehicleTopSpeed(vehicle, 1.0)

    if modeConfig.type == "reset" or mode == "normal" then
        activeDriveModeByVehicle[vehicle] = "normal"
        return
    end

    activeDriveModeByVehicle[vehicle] = mode

    if modeConfig.type == "multiplier" then
        for field, multiplier in pairs(modeConfig) do
            if field ~= "type" and base[field] then
                local value = base[field] * multiplier
                if field == "fInitialDragCoeff" and value < 0.1 then
                    value = 0.1
                end
                SetVehicleHandlingFloat(vehicle, "CHandlingData", field, value + 0.0)
            end
        end
    elseif modeConfig.type == "additive" then
        for field, addend in pairs(modeConfig) do
            if field ~= "type" and base[field] then
                local value = base[field] + addend
                if field == "fInitialDragCoeff" and value < 0.1 then
                    value = 0.1
                end
                SetVehicleHandlingFloat(vehicle, "CHandlingData", field, value + 0.0)
            end
        end
    end

    ModifyVehicleTopSpeed(vehicle, 1.0)

    -- Re-apply any tuner chip boosts on top of the new drive mode base.
    local plate = getVehiclePlateKey(vehicle)
    local tunerChip = vehicleTunerChipData[plate]
    if tunerChip and tunerChip.installed then
        applyTunerChipHandling(vehicle, tunerChip)
    end
end

RegisterNetEvent('prism-carplay:client:receiveModificationsData', function(plate, modifications)
    vehicleModificationsData[plate] = modifications

    local pendingCb = pendingModificationsRequests[plate]
    if pendingCb then
        pendingModificationsRequests[plate] = nil
        pendingCb(modifications or {})
    end

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehiclePlateKey(vehicle) == plate and modifications then
        applyVehicleModifications(vehicle, modifications)
    end
end)

RegisterNetEvent('prism-carplay:client:modificationsDataUpdated', function(plate, modifications)
    vehicleModificationsData[plate] = modifications

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehiclePlateKey(vehicle) == plate and modifications then
        applyVehicleModifications(vehicle, modifications)
    end
end)

RegisterNUICallback('getModificationsData', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        cb({})
        return
    end

    local plate = getVehiclePlateKey(vehicle)
    local modifications = vehicleModificationsData[plate]
    if modifications then
        cb(modifications)
    else
        pendingModificationsRequests[plate] = cb
        TriggerServerEvent('prism-carplay:server:getModificationsData', plate)
    end
end)

RegisterNUICallback('saveModificationsData', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and data then
        local plate = getVehiclePlateKey(vehicle)
        vehicleModificationsData[plate] = data
        applyVehicleModifications(vehicle, data)
        TriggerServerEvent('prism-carplay:server:saveModificationsData', plate, data)
    end
    cb('ok')
end)

RegisterNUICallback('setDriveMode', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and data.mode then
        local plate = getVehiclePlateKey(vehicle)
        local modifications = vehicleModificationsData[plate] or {}
        modifications.driveMode = data.mode
        vehicleModificationsData[plate] = modifications

        setDriveMode(vehicle, data.mode)
        TriggerServerEvent('prism-carplay:server:saveModificationsData', plate, modifications)
    end
    cb('ok')
end)

closeCarplayMenu = function()
    if carplayMenuOpen then
        setMenuVisible(false)
    end
end

-- CarPlay-installed / tuner-chip / modifications / music: poll for the
-- player's current vehicle changing, and (re)fetch per-vehicle state ------

local lastVehicle = 0

CreateThread(function()
    while true do
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

        if vehicle ~= 0 then
            if vehicle ~= lastVehicle then
                local newPlate = getVehiclePlateKey(vehicle)
                local newMusicKey = getVehicleMusicKey(vehicle)
                -- A pending resolver must never start a song in a vehicle the
                -- player has already left. Vehicle music itself is shared and
                -- continues for other occupants; only this client's local UI
                -- state is cleared here.
                if currentMusicVehicleKey and currentMusicVehicleKey ~= newMusicKey then
                    cancelPendingYoutubeResolves()
                    currentMusicVehicleKey = nil
                    currentMusicAudioSourceId = nil
                    currentMusicSong = nil
                    isMusicPlaying = false
                    SendNUIMessage({ action = 'musicStopped', data = true })
                end

                lastVehicle = vehicle
                local plate = newPlate

                -- Invalidate then eagerly recompute both base-handling caches
                -- for the new vehicle, so drive-mode/tuner-chip math has a
                -- fresh baseline the moment it's needed.
                vehicleBaseHandlingCache[vehicle] = nil
                baseHandlingCache[vehicle] = nil
                getVehicleBaseDriveHandling(vehicle)
                getBaseHandling(vehicle)

                if Config.RequireCarplayItem then
                    if carplayInstalledCache[plate] ~= nil then
                        carplayInstalled = carplayInstalledCache[plate]
                    else
                        carplayInstalled = false
                        -- The server re-derives both the plate and the vehicle's
                        -- model hash itself (never trusts them from the client),
                        -- then checks rn-vehicleshop's Manage Vehicles flag for
                        -- that model -- works for ANY vehicle of that model (test
                        -- drives, trainer spawns), not only purchased/owned ones.
                        TriggerServerEvent('prism-carplay:server:getCarplayInstalled', plate, NetworkGetNetworkIdFromEntity(vehicle))
                    end
                else
                    carplayInstalled = true
                end

                local tunerChip = vehicleTunerChipData[plate]
                if tunerChip then
                    tunerChipInstalled = tunerChip.installed or false
                    SendNUIMessage({ action = 'updateTunerChip', data = tunerChipInstalled })
                    applyTunerChipHandling(vehicle, tunerChip)
                else
                    tunerChipInstalled = false
                    SendNUIMessage({ action = 'updateTunerChip', data = false })
                    TriggerServerEvent('prism-carplay:server:getTunerChipData', plate)
                end

                local modifications = vehicleModificationsData[plate]
                if modifications then
                    applyVehicleModifications(vehicle, modifications)
                else
                    TriggerServerEvent('prism-carplay:server:getModificationsData', plate)
                end

                if newMusicKey then
                    TriggerServerEvent('prism-carplay:server:getMusicState', newMusicKey)
                end
            end
        elseif vehicle == 0 then
            if lastVehicle ~= 0 then
                cancelPendingYoutubeResolves()
                if currentMusicVehicleKey then
                    currentMusicVehicleKey = nil
                    currentMusicAudioSourceId = nil
                    currentMusicSong = nil
                    isMusicPlaying = false
                    SendNUIMessage({ action = 'musicStopped', data = true })
                end
            end
            lastVehicle = 0
            carplayInstalled = false
            bumpNeonThreadId()
        end

        Wait(500)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    SendNUIMessage({ action = 'setVisible', data = false })
end)

-- Music player ------------------------------------------------------------
-- main.lua owns the NUI/UI side and the network sync of "what's playing";
-- sound.lua (loaded first) owns the actual audio source/speaker lifecycle
-- and exposes GetCurrentTime/FetchData that this file calls into directly.

RegisterNUICallback('getMusicLibrary', function(data, cb)
    cb(Config.MusicLibrary or {})
end)

RegisterNUICallback('fetchYouTubeData', function(data, cb)
    if not data.url then
        cb({ success = false, error = "No URL provided" })
        return
    end

    FetchData(data.url, function(result)
        if result then
            if result.status == "success" then
                cb({
                    success = true,
                    title = result.title or "YouTube Video",
                    duration = result.duration or 0,
                })
                return
            end
        end
        cb({ success = false, error = "Failed to fetch video data" })
    end)
end)

RegisterNUICallback('playMusic', function(data, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        cb({ success = false, error = "Not in vehicle" })
        return
    end

    local plate = getVehicleMusicKey(vehicle)
    if not plate then
        cb({ success = false, error = "Vehicle is not networked yet" })
        return
    end
    local song = data.song
    if type(song) ~= 'table' then
        cb({ success = false, error = "Invalid track" })
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    cancelPendingYoutubeResolves()

    if song.filePath then
        if not song.isYouTube then
            if not (string.match(song.filePath, "^https://") or string.match(song.filePath, "^http://")) then
                song.url = "https://cfx-nui-" .. GetCurrentResourceName() .. "/web/dist/sounds/" .. song.filePath
            end
        end
    end

    if song.isYouTube and song.url then
        local videoId = extractYoutubeVideoId(song.url)
        if not videoId then
            cb({ success = false, error = "Could not parse YouTube video id" })
            return
        end

        -- YouTube's server-side stream URLs now require frequently changing
        -- authentication/PO-token data. Use YouTube's supported IFrame player
        -- directly; sound-engine.js still synchronizes transport and applies
        -- per-vehicle distance/inside-volume rules without downloading media.
        song.videoId = videoId
        TriggerServerEvent('prism-carplay:server:playMusic', plate, song, netId)
        currentMusicVehicleKey = plate
        currentMusicAudioSourceId = nil
        currentMusicSong = song
        cb({ success = true })
        return
    end

    TriggerServerEvent('prism-carplay:server:playMusic', plate, song, netId)
    currentMusicVehicleKey = plate
    currentMusicAudioSourceId = nil
    currentMusicSong = song
    cb({ success = true })
end)

RegisterNUICallback('getMusicTime', function(data, cb)
    if currentMusicVehicleKey then
        local sourceId = currentMusicAudioSourceId or (currentMusicVehicleKey .. "carplay")
        local currentTime = GetCurrentTime(sourceId)
        cb({ currentTime = currentTime or 0 })
    else
        cb({ currentTime = 0 })
    end
end)

RegisterNUICallback('toggleMusic', function(data, cb)
    if not currentMusicVehicleKey then
        cb('ok')
        return
    end
    TriggerServerEvent('prism-carplay:server:toggleMusic', currentMusicVehicleKey)
    cb('ok')
end)

RegisterNUICallback('stopMusic', function(data, cb)
    if currentMusicVehicleKey then
        TriggerServerEvent('prism-carplay:server:stopMusic', currentMusicVehicleKey)
        currentMusicVehicleKey = nil
        currentMusicAudioSourceId = nil
        currentMusicSong = nil
        isMusicPlaying = false
    end
    cb('ok')
end)

RegisterNUICallback('seekMusic', function(data, cb)
    if currentMusicVehicleKey and data.time then
        TriggerServerEvent('prism-carplay:server:seekMusic', currentMusicVehicleKey, data.time)
    end
    cb('ok')
end)

RegisterNUICallback('setMusicVolume', function(data, cb)
    if currentMusicVehicleKey and data.volume then
        TriggerServerEvent('prism-carplay:server:setMusicVolume', currentMusicVehicleKey, data.volume * 100)
    end
    cb('ok')
end)

RegisterNUICallback('getMusicState', function(data, cb)
    if currentMusicVehicleKey and currentMusicSong then
        local sourceId = currentMusicAudioSourceId or (currentMusicVehicleKey .. "carplay")
        local currentTime = GetCurrentTime(sourceId)
        SendNUIMessage({
            action = 'syncMusicState',
            data = {
                song = currentMusicSong,
                isPlaying = isMusicPlaying,
                currentTime = currentTime or 0,
                audioSourceId = sourceId,
            },
        })
    end
    cb('ok')
end)

RegisterNetEvent('prism-carplay:client:musicStarted', function(plate, song, audioSourceId)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehicleMusicKey(vehicle) == plate then
        currentMusicVehicleKey = plate
        currentMusicAudioSourceId = audioSourceId or (plate .. "carplay")
        currentMusicSong = song
        isMusicPlaying = true

        SendNUIMessage({
            action = 'musicStarted',
            data = { song = song, audioSourceId = currentMusicAudioSourceId },
        })
    end
end)

RegisterNetEvent('prism-carplay:client:playbackStatus', function(plate, isPlaying)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehicleMusicKey(vehicle) == plate then
        isMusicPlaying = isPlaying
        SendNUIMessage({ action = 'updatePlaybackStatus', data = { isPlaying = isPlaying } })
    end
end)

RegisterNetEvent('prism-carplay:client:musicError', function(plate, message)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehicleMusicKey(vehicle) == plate then
        currentMusicVehicleKey = nil
        currentMusicAudioSourceId = nil
        currentMusicSong = nil
        isMusicPlaying = false
        SendNUIMessage({ action = 'musicError', data = { message = message or 'Unable to play this track' } })
    end
end)

-- Note: like the original, this only processes the event while the player
-- is in a vehicle at all (own plate is checked first, falling back to
-- whichever vehicle's music we think is currently playing).
RegisterNetEvent('prism-carplay:client:musicStopped', function(plate)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        local ownMusicKey = getVehicleMusicKey(vehicle)
        if ownMusicKey == plate or currentMusicVehicleKey == plate then
            SendNUIMessage({ action = 'musicStopped', data = true })
            currentMusicVehicleKey = nil
            currentMusicAudioSourceId = nil
            currentMusicSong = nil
            isMusicPlaying = false
        end
    end
end)

RegisterNetEvent('prism-carplay:client:trackEnded', function(plate)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        local ownMusicKey = getVehicleMusicKey(vehicle)
        if ownMusicKey == plate or currentMusicVehicleKey == plate then
            SendNUIMessage({ action = 'trackEnded', data = true })
            currentMusicVehicleKey = nil
            currentMusicAudioSourceId = nil
            currentMusicSong = nil
            isMusicPlaying = false
        end
    end
end)

RegisterNetEvent('prism-carplay:client:syncMusicState', function(plate, state)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and getVehicleMusicKey(vehicle) == plate and state.currentSong then
        currentMusicVehicleKey = plate
        currentMusicAudioSourceId = state.audioSourceId or (plate .. "carplay")
        currentMusicSong = state.currentSong
        isMusicPlaying = state.isPlaying

        local audioSourceId = currentMusicAudioSourceId
        local currentTime = GetCurrentTime(audioSourceId)

        SendNUIMessage({
            action = 'syncMusicState',
            data = {
                song = state.currentSong,
                isPlaying = state.isPlaying,
                volume = state.volume,
                currentTime = currentTime or 0,
                audioSourceId = audioSourceId,
            },
        })
    end
end)
