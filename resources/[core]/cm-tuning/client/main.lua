local Config = CMTuning.Config
CMTuning.Client = CMTuning.Client or {}

local menuOpen = false
local busy = false
local pendingOpen = false
local currentVeh = 0
local currentShop = nil
local original = nil
local sessionToken = nil
local uiReady = false
local uiRendered = false
local interactionVisible = false
local interactionSignature = nil
local lastInteraction = nil
local requestSerial = 0
local cam = nil
local camAngle = 0.0
local camDist = 5.2
local camHeight = 1.15
local lockState = nil

local function notify(msg, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', msg, kind or 'info')
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent('cm-tuning:client:notify', function(msg, kind)
    notify(msg, kind)
end)

local function plateOf(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    local statePlate = ''
    pcall(function() statePlate = tostring(Entity(vehicle).state.cmPlate or '') end)
    statePlate = statePlate:upper():gsub('%s+', '')
    if statePlate ~= '' then return statePlate end
    return tostring(GetVehicleNumberPlateText(vehicle) or ''):upper():gsub('%s+', '')
end

local function vehicleName(vehicle)
    local label = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local name = label and GetLabelText(label) or nil
    if not name or name == '' or name == 'NULL' then name = label or 'Vehicle' end
    return name
end

local function hasHarness(vehicle)
    if not vehicle or vehicle == 0 then return false end
    local ok, value = pcall(function() return Entity(vehicle).state.cmRacingHarness end)
    return ok and value == true
end

local function requestControl(entity, timeoutMs)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local untilAt = GetGameTimer() + (tonumber(timeoutMs) or 1000)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < untilAt do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

local function secureVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if Config.VehicleLock and Config.VehicleLock.enabled == false then return true end
    requestControl(vehicle, 1000)

    lockState = {
        vehicle = vehicle,
        engineWasOn = GetIsVehicleEngineRunning(vehicle) == true,
    }

    SetVehicleForwardSpeed(vehicle, 0.0)
    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
    SetVehicleHandbrake(vehicle, true)
    if not Config.VehicleLock or Config.VehicleLock.engineOff ~= false then
        SetVehicleEngineOn(vehicle, false, true, true)
    end
    if not Config.VehicleLock or Config.VehicleLock.freezePosition ~= false then
        FreezeEntityPosition(vehicle, true)
    end
    return true
end

local function releaseVehicle(vehicle)
    vehicle = vehicle or (lockState and lockState.vehicle) or currentVeh
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        requestControl(vehicle, 600)
        FreezeEntityPosition(vehicle, false)
        SetVehicleHandbrake(vehicle, false)
        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
        if Config.VehicleLock and Config.VehicleLock.leaveEngineOff == false and lockState and lockState.engineWasOn then
            SetVehicleEngineOn(vehicle, true, false, true)
        else
            SetVehicleEngineOn(vehicle, false, true, true)
        end
    end
    lockState = nil
end

local function readMods(vehicle)
    SetVehicleModKit(vehicle, 0)
    local primary, secondary = GetVehicleColours(vehicle)
    local pearl, wheelColor = GetVehicleExtraColours(vehicle)
    local mods = {
        primaryColor = primary,
        secondaryColor = secondary,
        pearlColor = pearl,
        wheelColor = wheelColor,
        wheelType = GetVehicleWheelType(vehicle),
        windowTint = GetVehicleWindowTint(vehicle),
        plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
        livery = GetVehicleLivery(vehicle),
        customWheels = GetVehicleModVariation(vehicle, 23) == 1,
        mods = {},
        extras = {},
        turbo = IsToggleModOn(vehicle, 18) == true,
        xenon = IsToggleModOn(vehicle, 22) == true,
        bulletproofTyres = GetVehicleTyresCanBurst(vehicle) == false,
        neons = {},
    }

    if GetResourceState('cm-vehicles') == 'started' then
        local ok, level = pcall(function() return exports['cm-vehicles']:GetTyreLevel(vehicle) end)
        mods.tyreLevel = ok and tonumber(level) or 0
    else
        mods.tyreLevel = 0
    end

    local okHeadlight, headlight = pcall(GetVehicleXenonLightsColour, vehicle)
    mods.headlightColor = okHeadlight and tonumber(headlight) or -1

    for modType = 0, 49 do
        local index = GetVehicleMod(vehicle, modType)
        if index ~= nil and index ~= -1 then mods.mods[tostring(modType)] = index end
    end
    for extra = 0, 20 do
        if DoesExtraExist(vehicle, extra) then
            mods.extras[tostring(extra)] = IsVehicleExtraTurnedOn(vehicle, extra) == 1
        end
    end
    for index = 0, 3 do mods.neons[index + 1] = IsVehicleNeonLightEnabled(vehicle, index) == true end
    local r, g, b = GetVehicleNeonLightsColour(vehicle)
    mods.neonColor = { r = r or 255, g = g or 255, b = b or 255 }
    return mods
end

local function applyExtendedVisuals(vehicle, mods)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or type(mods) ~= 'table' then return end
    if mods.headlightColor ~= nil then
        local colour = tonumber(mods.headlightColor) or -1
        if colour < 0 then
            ToggleVehicleMod(vehicle, 22, mods.xenon == true)
            if mods.xenon == true then pcall(function() SetVehicleXenonLightsColour(vehicle, -1) end) end
        else
            ToggleVehicleMod(vehicle, 22, true)
            pcall(function() SetVehicleXenonLightsColour(vehicle, colour) end)
        end
    end
    if type(mods.neons) == 'table' then
        for index = 0, 3 do SetVehicleNeonLightEnabled(vehicle, index, mods.neons[index + 1] == true) end
    end
    if type(mods.neonColor) == 'table' then
        SetVehicleNeonLightsColour(vehicle,
            tonumber(mods.neonColor.r) or 255,
            tonumber(mods.neonColor.g) or 255,
            tonumber(mods.neonColor.b) or 255)
    end
end

local function applySavedMods(vehicle, mods)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or type(mods) ~= 'table' then return end
    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:ApplyVehicleMods(vehicle, mods) end)
        pcall(function() exports['cm-vehicles']:ApplyPerformance(vehicle, {}) end)
    end
    applyExtendedVisuals(vehicle, mods)
end

local function buildSlot(vehicle, def)
    local count = GetNumVehicleMods(vehicle, def.modType) or 0
    if count <= 0 then return nil end
    local current = GetVehicleMod(vehicle, def.modType)
    local options = { { index = -1, label = 'Stock', price = 0 } }
    for index = 0, count - 1 do
        local textLabel = GetModTextLabel(vehicle, def.modType, index)
        local label = textLabel and GetLabelText(textLabel) or nil
        if not label or label == '' or label == 'NULL' then label = ('%s %d'):format(def.label, index + 1) end
        options[#options + 1] = {
            index = index,
            label = label,
            price = math.max(0, math.floor((tonumber(def.pricePerLevel) or 0) * (index + 1))),
        }
    end
    return {
        key = def.key,
        label = def.label,
        modType = def.modType,
        current = current == nil and -1 or current,
        options = options,
        maxIndex = count - 1,
    }
end

local function buildCaps(vehicle, shop)
    SetVehicleModKit(vehicle, 0)
    local caps = {}
    local defs = shop == 'chip' and (Config.Performance or {}) or (Config.Visual or {})
    for _, def in ipairs(defs) do
        caps[def.key] = math.max(-1, (GetNumVehicleMods(vehicle, def.modType) or 0) - 1)
    end
    return caps
end

local function buildCatalog(vehicle, shop)
    SetVehicleModKit(vehicle, 0)
    local data = {
        shop = shop,
        shopLabel = Config.Shops[shop] and Config.Shops[shop].label or 'Tuning',
        shopSub = Config.Shops[shop] and Config.Shops[shop].sub or '',
        vehicleName = vehicleName(vehicle),
        plate = plateOf(vehicle),
        slots = {},
        toggles = {},
        cameraPresets = {},
    }

    for _, preset in ipairs((Config.Camera and Config.Camera.Presets) or {}) do
        data.cameraPresets[#data.cameraPresets + 1] = { label = preset.label }
    end

    if shop == 'chip' then
        for _, def in ipairs(Config.Performance or {}) do
            local slot = buildSlot(vehicle, def)
            if slot then data.slots[#data.slots + 1] = slot end
        end

        local turbo = Config.Turbo
        if turbo then
            data.toggles[#data.toggles + 1] = {
                key = 'turbo', label = turbo.label, modType = turbo.modType,
                price = turbo.price or 0,
                current = IsToggleModOn(vehicle, turbo.modType) == true,
            }
        end

        local tyres = Config.Tyres or {}
        if tyres.enabled ~= false then
            local current = 0
            if GetResourceState('cm-vehicles') == 'started' then
                local ok, value = pcall(function() return exports['cm-vehicles']:GetTyreLevel(vehicle) end)
                if ok then current = tonumber(value) or 0 end
            end
            local options = { { index = 0, label = 'Stock', price = 0 } }
            for level = 1, tonumber(tyres.maxLevel) or 4 do
                options[#options + 1] = {
                    index = level,
                    label = tyres.Names and tyres.Names[level] or ('Level ' .. level),
                    price = math.floor((tonumber(tyres.pricePerLevel) or 0) * level),
                }
            end
            data.tyres = { label = tyres.label or 'Tyres', current = current, options = options }
        end

        if GetResourceState('cm-vehicles') == 'started' then
            data.speeds = {}
            for level = 0, 4 do
                local ok, speed = pcall(function() return exports['cm-vehicles']:EstimateTopSpeed(vehicle, level) end)
                data.speeds[#data.speeds + 1] = ok and tonumber(speed) or 0
            end
        end

        if Config.Harness and Config.Harness.enabled ~= false then
            data.harness = {
                label = Config.Harness.label or 'Racing Harness',
                price = Config.Harness.price or 0,
                installed = hasHarness(vehicle),
            }
        end

        local repair = Config.EngineRepair or {}
        if repair.enabled ~= false then
            local health = math.floor(GetVehicleEngineHealth(vehicle) or 1000.0)
            local missing = math.max(0, 1000 - health)
            local price = 0
            if missing > 0 then
                price = math.min(
                    tonumber(repair.maxPrice) or 25000,
                    (tonumber(repair.basePrice) or 0) + missing * (tonumber(repair.pricePerHealthPoint) or 0)
                )
            end
            data.engine = { health = health, missing = missing, price = math.floor(price) }
        end
    else
        for _, def in ipairs(Config.Visual or {}) do
            local slot = buildSlot(vehicle, def)
            if slot then data.slots[#data.slots + 1] = slot end
        end

        local xenon = Config.Xenon
        if xenon then
            data.toggles[#data.toggles + 1] = {
                key = 'xenon', label = xenon.label, modType = xenon.modType,
                price = xenon.price or 0,
                current = IsToggleModOn(vehicle, xenon.modType) == true,
            }
        end

        data.colors = Config.Colors or {}
        data.tints = Config.WindowTints or {}
        data.neonColors = Config.NeonColors or {}
        data.headlightColors = Config.HeadlightColors or {}
        data.plateStyles = Config.PlateStyles or {}

        local primary, secondary = GetVehicleColours(vehicle)
        local _, wheelColor = GetVehicleExtraColours(vehicle)
        data.currentPrimary = primary
        data.currentSecondary = secondary
        data.currentWheelColor = wheelColor
        data.currentTint = GetVehicleWindowTint(vehicle)
        data.currentNeon = IsVehicleNeonLightEnabled(vehicle, 0) == true
        data.currentPlate = GetVehicleNumberPlateTextIndex(vehicle)
        local ok, headlight = pcall(GetVehicleXenonLightsColour, vehicle)
        data.currentHeadlight = ok and tonumber(headlight) or -1
        local nr, ng, nb = GetVehicleNeonLightsColour(vehicle)
        data.currentNeonColor = { r = nr or 255, g = ng or 255, b = nb or 255 }
        data.prices = {
            respray = Config.resprayPrice or Config.respayPrice or 0,
            tint = Config.windowTintPrice or 0,
            neon = Config.neonPrice or 0,
            wheelColor = Config.wheelColorPrice or 0,
            headlight = Config.headlightColorPrice or 0,
            plate = Config.plateStylePrice or 0,
        }
    end
    return data
end

local function restoreOriginal()
    local vehicle = currentVeh
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or type(original) ~= 'table' then return end
    SetVehicleModKit(vehicle, 0)

    local slots = {}
    for _, def in ipairs(Config.Performance or {}) do slots[#slots + 1] = def.modType end
    for _, def in ipairs(Config.Visual or {}) do slots[#slots + 1] = def.modType end
    for _, modType in ipairs(slots) do
        local previous = original.mods and original.mods[tostring(modType)]
        SetVehicleMod(vehicle, modType, tonumber(previous) or -1, original.customWheels == true)
    end

    ToggleVehicleMod(vehicle, 18, original.turbo == true)
    ToggleVehicleMod(vehicle, 22, original.xenon == true)
    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:ApplyTyreLevel(vehicle, tonumber(original.tyreLevel) or 0) end)
    end
    SetVehicleTyresCanBurst(vehicle, original.bulletproofTyres ~= true)

    if original.primaryColor ~= nil and original.secondaryColor ~= nil then
        SetVehicleColours(vehicle, original.primaryColor, original.secondaryColor)
    end
    if original.pearlColor ~= nil and original.wheelColor ~= nil then
        SetVehicleExtraColours(vehicle, original.pearlColor, original.wheelColor)
    end
    if original.windowTint ~= nil then SetVehicleWindowTint(vehicle, original.windowTint) end
    if original.wheelType ~= nil then SetVehicleWheelType(vehicle, original.wheelType) end
    if original.plateIndex ~= nil then SetVehicleNumberPlateTextIndex(vehicle, original.plateIndex) end
    if original.livery ~= nil then SetVehicleLivery(vehicle, original.livery) end
    applyExtendedVisuals(vehicle, original)

    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:ApplyPerformance(vehicle, {}) end)
    end
end

local function camPlace()
    if not cam or not DoesCamExist(cam) or currentVeh == 0 or not DoesEntityExist(currentVeh) then return end
    local coords = GetEntityCoords(currentVeh)
    local heading = GetEntityHeading(currentVeh)
    local radians = math.rad(heading + camAngle)
    SetCamCoord(cam,
        coords.x + math.sin(radians) * camDist,
        coords.y - math.cos(radians) * camDist,
        coords.z + camHeight)
    PointCamAtCoord(cam, coords.x, coords.y, coords.z + 0.25)
end

local function camStart()
    local cfg = Config.Camera or {}
    if cfg.enabled == false or currentVeh == 0 or not DoesEntityExist(currentVeh) then return end
    camAngle = tonumber(cfg.startAngle) or 320.0
    camDist = tonumber(cfg.distance) or 5.2
    camHeight = tonumber(cfg.height) or 1.15
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(cam, true)
    SetCamFov(cam, tonumber(cfg.fov) or 45.0)
    camPlace()
    RenderScriptCams(true, true, 450, true, true)
end

local function camStop()
    RenderScriptCams(false, true, 350, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, true) end
    cam = nil
end

local function hideInteraction()
    if interactionVisible or lastInteraction then
        interactionVisible = false
        interactionSignature = nil
        lastInteraction = nil
        if uiReady then SendNUIMessage({ action = 'interaction', show = false }) end
    end
end

local function showInteraction(shop)
    local def = Config.Shops and Config.Shops[shop]
    if not def then return end
    local data = {
        action = 'interaction',
        show = true,
        key = 'E',
        title = Config.Interaction and Config.Interaction.title or 'CM MOTORWORKS',
        label = def.label or 'Tuning',
        hint = Config.Interaction and Config.Interaction.hint or 'Vehicle is secured while customising',
    }
    local signature = tostring(shop) .. '|' .. tostring(data.label)
    lastInteraction = data
    if not interactionVisible or interactionSignature ~= signature then SendNUIMessage(data) end
    interactionSignature = signature
    interactionVisible = true
end

local function clearState()
    currentVeh = 0
    currentShop = nil
    original = nil
    sessionToken = nil
    pendingOpen = false
    busy = false
    uiRendered = false
end

local function closeMenu(restore, release, tellServer)
    local vehicle = currentVeh
    local token = sessionToken
    if restore then restoreOriginal() end
    menuOpen = false
    pendingOpen = false
    camStop()
    SetNuiFocus(false, false)
    pcall(function() SetNuiFocusKeepInput(false) end)
    SendNUIMessage({ action = 'close' })
    if tellServer and token then TriggerServerEvent('cm-tuning:server:cancelSession', token) end
    if release ~= false then releaseVehicle(vehicle) end
    clearState()
end
CMTuning.Client.CloseMenu = closeMenu

local function openShop(shop)
    if menuOpen or busy or pendingOpen then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or (Config.requireDriver ~= false and GetPedInVehicleSeat(vehicle, -1) ~= ped) then
        notify('Drive into the bay and stay in the driver seat.', 'error')
        return
    end

    currentVeh = vehicle
    currentShop = shop
    pendingOpen = true
    hideInteraction()
    secureVehicle(vehicle)

    TriggerServerEvent('cm-tuning:server:requestOpen', {
        shop = shop,
        plate = plateOf(vehicle),
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        caps = buildCaps(vehicle, shop),
    })

    local requestedVehicle = vehicle
    SetTimeout(6500, function()
        if pendingOpen and currentVeh == requestedVehicle and not menuOpen then
            notify('Tuning server did not respond. Vehicle released.', 'error')
            closeMenu(true, true, true)
        end
    end)
end

RegisterNUICallback('uiReady', function(_, cb)
    uiReady = true
    if lastInteraction then SendNUIMessage(lastInteraction) end
    cb({ ok = true })
end)

RegisterNUICallback('uiRendered', function(_, cb)
    uiRendered = true
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu(true, true, true)
    cb({ ok = true })
end)

RegisterNUICallback('preview', function(data, cb)
    local vehicle = currentVeh
    if not menuOpen or busy or vehicle == 0 or not DoesEntityExist(vehicle) then cb({ ok = false }) return end
    data = type(data) == 'table' and data or {}
    SetVehicleModKit(vehicle, 0)

    local kind = tostring(data.kind or '')
    if kind == 'mod' then
        local modType = tonumber(data.modType)
        local index = tonumber(data.index)
        if modType and index then
            SetVehicleMod(vehicle, math.floor(modType), math.floor(index), false)
            if modType == 11 and GetResourceState('cm-vehicles') == 'started' then
                pcall(function() exports['cm-vehicles']:ApplyPerformance(vehicle, {}) end)
            end
        end
    elseif kind == 'toggle' then
        local modType = tonumber(data.modType)
        if modType then ToggleVehicleMod(vehicle, math.floor(modType), data.value == true) end
    elseif kind == 'tyres' then
        if GetResourceState('cm-vehicles') == 'started' then
            pcall(function() exports['cm-vehicles']:ApplyTyreLevel(vehicle, tonumber(data.value) or 0) end)
        end
    elseif kind == 'wheelColor' then
        local pearl = select(1, GetVehicleExtraColours(vehicle))
        SetVehicleExtraColours(vehicle, pearl, tonumber(data.value) or 0)
    elseif kind == 'headlight' then
        local value = tonumber(data.value) or -1
        if value < 0 then
            pcall(function() SetVehicleXenonLightsColour(vehicle, -1) end)
        else
            ToggleVehicleMod(vehicle, 22, true)
            pcall(function() SetVehicleXenonLightsColour(vehicle, value) end)
        end
    elseif kind == 'plate' then
        SetVehicleNumberPlateTextIndex(vehicle, tonumber(data.value) or 0)
    elseif kind == 'color' then
        local _, secondary = GetVehicleColours(vehicle)
        SetVehicleColours(vehicle, tonumber(data.value) or 0, secondary)
    elseif kind == 'color2' then
        local primary = select(1, GetVehicleColours(vehicle))
        SetVehicleColours(vehicle, primary, tonumber(data.value) or 0)
    elseif kind == 'tint' then
        SetVehicleWindowTint(vehicle, tonumber(data.value) or 0)
    elseif kind == 'neon' then
        for index = 0, 3 do SetVehicleNeonLightEnabled(vehicle, index, data.value == true) end
    elseif kind == 'neonColor' and type(data.value) == 'table' then
        SetVehicleNeonLightsColour(vehicle,
            tonumber(data.value.r) or 255,
            tonumber(data.value.g) or 255,
            tonumber(data.value.b) or 255)
    end
    cb({ ok = true })
end)

local function beginBusyTimeout(message)
    requestSerial = requestSerial + 1
    local serial = requestSerial
    SetTimeout(15000, function()
        if busy and menuOpen and requestSerial == serial then
            busy = false
            requestSerial = requestSerial + 1
            SendNUIMessage({ action = 'processing', value = false })
            SendNUIMessage({ action = 'toast', kind = 'error', message = message or 'Server request timed out.' })
            notify(message or 'Server request timed out.', 'error')
        end
    end)
end

RegisterNUICallback('purchase', function(data, cb)
    if not menuOpen or busy or not sessionToken then cb({ ok = false }) return end
    busy = true
    beginBusyTimeout('Purchase request timed out.')
    SendNUIMessage({ action = 'processing', value = true, message = 'Securing purchase...' })
    TriggerServerEvent('cm-tuning:server:purchase', {
        token = sessionToken,
        account = type(data) == 'table' and data.account or nil,
        changes = type(data) == 'table' and data.changes or {},
    })
    cb({ ok = true })
end)

RegisterNUICallback('installHarness', function(data, cb)
    if not menuOpen or busy or not sessionToken then cb({ ok = false }) return end
    busy = true
    beginBusyTimeout('Harness request timed out.')
    SendNUIMessage({ action = 'processing', value = true, message = 'Installing harness...' })
    TriggerServerEvent('cm-tuning:server:installHarness', {
        token = sessionToken,
        account = type(data) == 'table' and data.account or nil,
    })
    cb({ ok = true })
end)

RegisterNUICallback('repairEngine', function(data, cb)
    if not menuOpen or busy or not sessionToken then cb({ ok = false }) return end
    busy = true
    beginBusyTimeout('Engine rebuild request timed out.')
    SendNUIMessage({ action = 'processing', value = true, message = 'Authorising rebuild...' })
    TriggerServerEvent('cm-tuning:server:repairEngine', {
        token = sessionToken,
        account = type(data) == 'table' and data.account or nil,
    })
    cb({ ok = true })
end)

RegisterNUICallback('camPreset', function(data, cb)
    local presets = (Config.Camera and Config.Camera.Presets) or {}
    local preset = presets[tonumber(data and data.index) or 1]
    if preset then
        camAngle = tonumber(preset.angle) or camAngle
        camDist = tonumber(preset.distance) or tonumber(Config.Camera.distance) or 5.2
        camHeight = tonumber(preset.height) or tonumber(Config.Camera.height) or 1.15
        camPlace()
    end
    cb({ ok = true })
end)

RegisterNetEvent('cm-tuning:client:open', function(payload)
    if not pendingOpen or currentVeh == 0 or not DoesEntityExist(currentVeh) or not currentShop then return end
    payload = type(payload) == 'table' and payload or {}
    sessionToken = tostring(payload.token or '')
    if sessionToken == '' then
        notify('Tuning session token was missing.', 'error')
        return closeMenu(true, true, true)
    end

    if type(payload.savedMods) == 'table' then applySavedMods(currentVeh, payload.savedMods) end
    original = readMods(currentVeh)
    pendingOpen = false
    menuOpen = true
    busy = false
    uiRendered = false

    local catalog = buildCatalog(currentVeh, currentShop)
    catalog.balances = type(payload.balances) == 'table' and payload.balances or { cash = 0, bank = 0 }
    catalog.defaultAccount = Config.defaultAccount or 'cash'
    catalog.allowCash = Config.allowCash ~= false
    catalog.allowBank = Config.allowBank ~= false

    SetNuiFocus(true, true)
    pcall(function() SetNuiFocusKeepInput(true) end)
    camStart()

    CreateThread(function()
        local untilAt = GetGameTimer() + 3500
        repeat
            SendNUIMessage({ action = 'open', data = catalog })
            Wait(250)
        until uiRendered or not menuOpen or GetGameTimer() >= untilAt

        if menuOpen and not uiRendered then
            notify('Tuning UI failed to render. Vehicle released.', 'error')
            closeMenu(true, true, true)
        end
    end)
end)

RegisterNetEvent('cm-tuning:client:denied', function(message)
    pendingOpen = false
    notify(message or 'Tuning request denied.', 'error')
    closeMenu(true, true, false)
end)

RegisterNetEvent('cm-tuning:client:purchaseApproved', function(payload)
    requestSerial = requestSerial + 1
    payload = type(payload) == 'table' and payload or {}
    local vehicle = currentVeh
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        restoreOriginal()
        applySavedMods(vehicle, payload.mods or {})
    end
    local price = math.max(0, math.floor(tonumber(payload.price) or 0))
    closeMenu(false, true, false)
    notify(price > 0 and ('Work complete. Paid $%d.'):format(price) or 'Vehicle changes saved.', 'success')
end)

RegisterNetEvent('cm-tuning:client:purchaseDenied', function(message)
    requestSerial = requestSerial + 1
    busy = false
    SendNUIMessage({ action = 'processing', value = false })
    SendNUIMessage({ action = 'toast', kind = 'error', message = message or 'Purchase failed.' })
    notify(message or 'Purchase failed.', 'error')
end)

RegisterNetEvent('cm-tuning:client:specialDenied', function(message)
    requestSerial = requestSerial + 1
    busy = false
    SendNUIMessage({ action = 'processing', value = false })
    SendNUIMessage({ action = 'toast', kind = 'error', message = message or 'Service failed.' })
    notify(message or 'Service failed.', 'error')
end)

RegisterNetEvent('cm-tuning:client:harnessInstalled', function(payload)
    requestSerial = requestSerial + 1
    payload = type(payload) == 'table' and payload or {}
    restoreOriginal()
    local vehicle = currentVeh
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        pcall(function() Entity(vehicle).state:set('cmRacingHarness', true, true) end)
    end
    closeMenu(false, true, false)
    notify(('Racing harness fitted for $%d.'):format(math.floor(tonumber(payload.price) or 0)), 'success')
end)

RegisterNetEvent('cm-tuning:client:engineApproved', function(payload)
    requestSerial = requestSerial + 1
    payload = type(payload) == 'table' and payload or {}
    local vehicle = currentVeh
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        closeMenu(false, true, false)
        return
    end

    restoreOriginal()
    menuOpen = false
    camStop()
    SetNuiFocus(false, false)
    pcall(function() SetNuiFocusKeepInput(false) end)
    SendNUIMessage({ action = 'close' })

    local duration = math.max(1000, tonumber(payload.durationMs) or 15000)
    local startedAt = GetGameTimer()
    local serviceUi = GetResourceState('cm-vehicles') == 'started'
    if serviceUi then
        pcall(function()
            exports['cm-vehicles']:ShowServiceProgress('repair', 'Rebuilding engine', 'Precision mechanical work in progress')
        end)
    end

    while GetGameTimer() - startedAt < duration do
        Wait(100)
        if not DoesEntityExist(vehicle) then break end
        SetVehicleForwardSpeed(vehicle, 0.0)
        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
        if serviceUi then
            pcall(function()
                exports['cm-vehicles']:UpdateServiceProgress(((GetGameTimer() - startedAt) / duration) * 100.0)
            end)
        end
    end

    if serviceUi then pcall(function() exports['cm-vehicles']:HideServiceProgress() end) end
    if DoesEntityExist(vehicle) then
        local dirt = GetVehicleDirtLevel(vehicle) or 0.0
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        if payload.full == true then
            SetVehicleBodyHealth(vehicle, 1000.0)
            SetVehiclePetrolTankHealth(vehicle, 1000.0)
        end
        SetVehicleDirtLevel(vehicle, dirt)
    end

    releaseVehicle(vehicle)
    local price = math.floor(tonumber(payload.price) or 0)
    clearState()
    notify(('Engine rebuilt. Paid $%d.'):format(price), 'success')
end)

RegisterNetEvent('cm-tuning:client:sessionExpired', function()
    if menuOpen or pendingOpen then
        notify('Tuning session expired. Preview changes reverted.', 'error')
        closeMenu(true, true, false)
    end
end)

-- Apply extended visual fields after CM Vehicles spawns a vehicle.
RegisterNetEvent('cm-vehicles:client:finalizeSpawn', function(data)
    data = type(data) == 'table' and data or {}
    if type(data.mods) ~= 'table' then return end
    local netId = tonumber(data.netId)
    if not netId then return end
    CreateThread(function()
        local untilAt = GetGameTimer() + 7000
        while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < untilAt do Wait(50) end
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < untilAt do
            Wait(50)
            vehicle = NetworkGetEntityFromNetworkId(netId)
        end
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            Wait(250)
            applyExtendedVisuals(vehicle, data.mods)
        end
    end)
end)

CreateThread(function()
    while true do
        Wait(0)
        if (menuOpen or pendingOpen or busy) and currentVeh ~= 0 and DoesEntityExist(currentVeh) and lockState then
            SetVehicleForwardSpeed(currentVeh, 0.0)
            SetEntityVelocity(currentVeh, 0.0, 0.0, 0.0)
            SetVehicleHandbrake(currentVeh, true)
            if not Config.VehicleLock or Config.VehicleLock.engineOff ~= false then
                SetVehicleEngineOn(currentVeh, false, true, true)
            end
            DisableControlAction(0, 71, true)
            DisableControlAction(0, 72, true)
            DisableControlAction(0, 63, true)
            DisableControlAction(0, 64, true)
            DisableControlAction(0, 75, Config.VehicleLock and Config.VehicleLock.disableExit ~= false)
        else
            Wait(200)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if menuOpen and cam and DoesCamExist(cam) then
            local speed = tonumber(Config.Camera and Config.Camera.rotateSpeed) or 1.6
            local moved = false
            if IsControlPressed(0, 44) then
                camAngle = (camAngle - speed) % 360.0
                moved = true
            elseif IsControlPressed(0, 38) then
                camAngle = (camAngle + speed) % 360.0
                moved = true
            end
            if moved then camPlace() end
        else
            Wait(200)
        end
    end
end)

CreateThread(function()
    for _, shop in pairs(Config.Shops or {}) do
        local blipConfig = shop.Blip
        if blipConfig and blipConfig.enabled ~= false then
            for _, position in ipairs(shop.Locations or {}) do
                local blip = AddBlipForCoord(position.x, position.y, position.z)
                SetBlipSprite(blip, blipConfig.sprite or 446)
                SetBlipDisplay(blip, 4)
                SetBlipScale(blip, blipConfig.scale or 0.75)
                SetBlipColour(blip, blipConfig.color or 47)
                SetBlipAsShortRange(blip, blipConfig.shortRange ~= false)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(blipConfig.name or shop.label or 'Tuning')
                EndTextCommandSetBlipName(blip)
            end
        end
    end
end)

CreateThread(function()
    while true do
        local waitMs = 1000
        if not menuOpen and not busy and not pendingOpen then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            local isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
            local coords = isDriver and GetEntityCoords(vehicle) or GetEntityCoords(ped)
            local nearestShop, nearestDistance

            for key, shop in pairs(Config.Shops or {}) do
                for _, point in ipairs(shop.Locations or {}) do
                    local distance = #(coords - point)
                    if distance < (tonumber(Config.detectDistance) or 70.0) and (not nearestDistance or distance < nearestDistance) then
                        nearestShop, nearestDistance = key, distance
                    end
                end
            end

            if nearestShop and nearestDistance <= (tonumber(Config.interactDistance) or 6.0) then
                waitMs = 0
                if isDriver then
                    showInteraction(nearestShop)
                    if IsControlJustReleased(0, tonumber(Config.interactKey) or 38) then openShop(nearestShop) end
                else
                    hideInteraction()
                end
            else
                hideInteraction()
                if nearestShop then waitMs = 250 end
            end
        else
            hideInteraction()
        end
        Wait(waitMs)
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        if (menuOpen or pendingOpen) and currentVeh ~= 0 then
            local ped = PlayerPedId()
            local invalid = not DoesEntityExist(currentVeh)
            if not invalid and Config.requireDriver ~= false then
                invalid = GetVehiclePedIsIn(ped, false) ~= currentVeh or GetPedInVehicleSeat(currentVeh, -1) ~= ped
            end
            if invalid then
                notify('Tuning session cancelled. Changes reverted.', 'error')
                closeMenu(true, true, true)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    hideInteraction()
    if menuOpen or pendingOpen then restoreOriginal() end
    camStop()
    SetNuiFocus(false, false)
    pcall(function() SetNuiFocusKeepInput(false) end)
    releaseVehicle(currentVeh)
end)
