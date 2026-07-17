local Config = CMWash.Config
CMWash.Server = CMWash.Server or {}

local sessions = {}
local vehicleLocks = {}
local locationLocks = {}
local activeWashes = {}
local openCooldowns = {}
local purchaseCooldowns = {}
local purchaseLocks = {}

math.randomseed(os.time())

local function dbg(...)
    if Config.Debug then print('[CM-CARWASH]', ...) end
end

local function reject(src, message, reason)
    if Config.Security and Config.Security.logRejectedAttempts == true then
        print(('[CM-CARWASH][REJECT] src=%s reason=%s'):format(tostring(src), tostring(reason or message)))
    end
    TriggerClientEvent('cm-carwash:client:openDenied', src, tostring(message or 'Request rejected.'))
end

local function normalizePlate(value)
    return tostring(value or ''):upper():gsub('%s+', ''):sub(1, 12)
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function sameHash(left, right)
    left, right = tonumber(left), tonumber(right)
    if not left or not right then return false end
    return (left & 0xFFFFFFFF) == (right & 0xFFFFFFFF)
end

local function playerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function getCash(src)
    local api = playerData()
    if not api then return nil end
    local ok, amount = pcall(function() return api:GetCash(src) end)
    if ok and type(amount) == 'number' then return math.floor(amount) end
    return nil
end

local function removeCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:RemoveCash(src, amount, reason) end)
    return ok and result == true
end

local function addCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:AddCash(src, amount, reason) end)
    return ok and result == true
end

local function chargeCash(src, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local balance = getCash(src)
    if balance == nil then return false, 'Cash payment system is unavailable.' end
    if balance < amount then
        return false, ('Not enough cash. You need $%d.'):format(amount)
    end
    if not removeCash(src, amount, 'automatic-car-wash') then
        return false, 'Cash payment could not be completed.'
    end
    return true
end

local function getNetworkVehicle(netId)
    netId = tonumber(netId) or 0
    if netId <= 0 then return nil end

    local ok, entity = pcall(NetworkGetEntityFromNetworkId, netId)
    if not ok or not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    if GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function getEntityPlate(entity)
    local statePlate
    pcall(function() statePlate = Entity(entity).state.cmPlate end)
    if statePlate and statePlate ~= '' then return normalizePlate(statePlate) end

    local ok, plate = pcall(GetVehicleNumberPlateText, entity)
    return ok and normalizePlate(plate) or ''
end

local function getManagedVehicleRow(plate)
    if GetResourceState('cm-vehicles') ~= 'started' then return nil end
    local ok, row = pcall(function()
        return exports['cm-vehicles']:GetVehicleByPlate(plate)
    end)
    if ok and type(row) == 'table' then return row end
    return nil
end

local function hasVehicleAccess(src, plate)
    if Config.Security.requireVehicleAccess == false then return true end
    if GetResourceState('cm-vehicles') ~= 'started' then return false end

    local ok, allowed = pcall(function()
        return exports['cm-vehicles']:HasVehicleAccess(src, plate)
    end)
    return ok and allowed == true
end

local function serviceVehicle(plate, patch)
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports['cm-vehicles']:ServiceVehicle(plate, patch)
    end)
    return ok and result == true
end

local function getLiveDirt(entity, row)
    local stateDirt
    pcall(function() stateDirt = Entity(entity).state.cmDirt end)
    if type(stateDirt) == 'number' then
        return clamp(stateDirt, 0.0, tonumber(Config.maxDirtLevel) or 15.0)
    end

    local ok, nativeDirt = pcall(GetVehicleDirtLevel, entity)
    if ok and type(nativeDirt) == 'number' then
        return clamp(nativeDirt, 0.0, tonumber(Config.maxDirtLevel) or 15.0)
    end

    return clamp(row and (row.dirt_level or row.dirtLevel) or 0.0, 0.0, tonumber(Config.maxDirtLevel) or 15.0)
end

local function closestLocation(coords, maximumDistance)
    local bestIndex, bestDistance
    for index, location in ipairs(Config.Locations or {}) do
        local distance = #(coords - location)
        if distance <= maximumDistance and (not bestDistance or distance < bestDistance) then
            bestIndex = index
            bestDistance = distance
        end
    end
    return bestIndex, bestDistance
end

local function releaseSession(src)
    local session = sessions[src]
    if session then
        if session.plate ~= '' and vehicleLocks[session.plate] == src then
            vehicleLocks[session.plate] = nil
        end
        if session.locationIndex and locationLocks[session.locationIndex] == src then
            locationLocks[session.locationIndex] = nil
        end
    end
    sessions[src] = nil
end

local function validateVehicle(src, netId, suppliedPlate, requiredLocationIndex)
    local entity = getNetworkVehicle(netId)
    if not entity then return false, 'Vehicle is not available.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, 'Player is not available.'
    end

    if GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(entity) then
        return false, 'Vehicle is in another routing instance.'
    end

    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(entity)
    if #(playerCoords - vehicleCoords) > (tonumber(Config.Security.vehicleDistance) or 8.0) then
        return false, 'Move closer to the vehicle.'
    end

    local locationIndex = tonumber(requiredLocationIndex)
    local location = locationIndex and Config.Locations[locationIndex] or nil
    if not location then
        locationIndex = closestLocation(playerCoords, tonumber(Config.Security.locationTolerance) or 8.0)
        location = locationIndex and Config.Locations[locationIndex] or nil
    end
    if not location then return false, 'You are not inside a car-wash bay.' end

    local tolerance = tonumber(Config.Security.locationTolerance) or 8.0
    if #(playerCoords - location) > tolerance or #(vehicleCoords - location) > tolerance then
        return false, 'Position the vehicle inside the wash bay.'
    end

    if Config.Security.requireDriver ~= false then
        local occupied = GetVehiclePedIsIn(ped, false)
        if occupied ~= entity then return false, 'You must be inside the selected vehicle.' end
        if GetPedInVehicleSeat(entity, -1) ~= ped then
            return false, 'Only the driver can use the car wash.'
        end
    end

    local actualPlate = getEntityPlate(entity)
    local expectedPlate = normalizePlate(suppliedPlate)
    if actualPlate == '' or (expectedPlate ~= '' and expectedPlate ~= actualPlate) then
        return false, 'Vehicle plate validation failed.'
    end

    local row = getManagedVehicleRow(actualPlate)
    if Config.Security.requireManagedVehicle ~= false and not row then
        return false, 'This vehicle is not registered in CM Vehicles.'
    end

    if row then
        if normalizePlate(row.plate) ~= actualPlate then
            return false, 'Vehicle record does not match.'
        end

        if Config.Security.requireManagedVehicle ~= false then
            local statePlate, stateVehicleId = '', nil
            pcall(function()
                statePlate = normalizePlate(Entity(entity).state.cmPlate)
                stateVehicleId = tonumber(Entity(entity).state.cmVehicleId)
            end)
            if statePlate == '' or not stateVehicleId then
                return false, 'Vehicle network identity is not ready.'
            end
            if statePlate ~= actualPlate or tonumber(row.id) ~= stateVehicleId then
                return false, 'Vehicle network identity does not match its database record.'
            end
        end

        if row.model ~= nil then
            local expectedModel = tonumber(row.model)
            if not expectedModel then expectedModel = joaat(tostring(row.model)) end
            if expectedModel and not sameHash(expectedModel, GetEntityModel(entity)) then
                return false, 'Vehicle model validation failed.'
            end
        end
    end

    if not hasVehicleAccess(src, actualPlate) then
        return false, 'You do not have keys for this vehicle.'
    end

    return true, {
        entity = entity,
        netId = tonumber(netId),
        plate = actualPlate,
        row = row,
        locationIndex = locationIndex,
        dirt = getLiveDirt(entity, row),
    }
end

local function makeSessionToken(src)
    return ('wash:%d:%d:%d'):format(src, GetGameTimer(), math.random(100000, 999999))
end

local function sendWashDenied(src, message, close)
    TriggerClientEvent('cm-carwash:client:washDenied', src, {
        message = tostring(message or 'The wash could not be started.'),
        cash = getCash(src) or 0,
        close = close == true,
    })
end

RegisterNetEvent('cm-carwash:server:requestOpen', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    local now = GetGameTimer()
    local cooldown = tonumber(Config.Security.openCooldownMs) or 700
    if now - (openCooldowns[src] or 0) < cooldown then
        reject(src, 'Please wait a moment and try again.', 'open cooldown')
        return
    end
    openCooldowns[src] = now

    releaseSession(src)

    local valid, vehicle = validateVehicle(src, data.netId, data.plate, data.locationIndex)
    if not valid then
        reject(src, tostring(vehicle), 'open validation')
        return
    end

    local lockedBy = vehicleLocks[vehicle.plate]
    local active = activeWashes[vehicle.plate]
    if active and active.expiresAt > os.time() then
        reject(src, 'This vehicle is already using a car wash.', 'active wash locked')
        return
    end
    if lockedBy and lockedBy ~= src then
        reject(src, 'This vehicle already has an open car-wash session.', 'vehicle session locked')
        return
    end

    local locationOwner = locationLocks[vehicle.locationIndex]
    if locationOwner and locationOwner ~= src then
        reject(src, 'This wash bay is currently occupied.', 'wash location locked')
        return
    end

    local cash = getCash(src)
    if cash == nil then
        reject(src, 'Cash payment system is unavailable.', 'cash unavailable')
        return
    end

    local token = makeSessionToken(src)
    sessions[src] = {
        token = token,
        netId = vehicle.netId,
        plate = vehicle.plate,
        locationIndex = vehicle.locationIndex,
        expiresAt = os.time() + (tonumber(Config.Security.sessionSeconds) or 45),
    }
    vehicleLocks[vehicle.plate] = src
    locationLocks[vehicle.locationIndex] = src

    local row = vehicle.row or {}
    TriggerClientEvent('cm-carwash:client:openSession', src, {
        sessionToken = token,
        stationName = Config.stationName or 'Car Wash',
        vehicle = {
            plate = vehicle.plate,
            label = tostring(row.label or 'Vehicle'),
            model = tostring(row.model or ''),
        },
        dirt = vehicle.dirt,
        maxDirt = tonumber(Config.maxDirtLevel) or 15.0,
        minDirt = tonumber(Config.minDirtToOffer) or 0.5,
        price = math.max(0, math.floor(tonumber(Config.price) or 0)),
        cash = cash,
        durationMs = math.max(1500, tonumber(Config.durationMs) or 7000),
        paymentMethod = 'cash',
    })
end)

RegisterNetEvent('cm-carwash:server:cancelSession', function(token)
    local src = source
    local session = sessions[src]
    if session and session.token == tostring(token or '') then
        releaseSession(src)
    end
end)

RegisterNetEvent('cm-carwash:server:startWash', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    local now = GetGameTimer()
    local cooldown = tonumber(Config.Security.purchaseCooldownMs) or 1200
    if now - (purchaseCooldowns[src] or 0) < cooldown then
        sendWashDenied(src, 'Please wait before trying again.', false)
        return
    end
    purchaseCooldowns[src] = now

    if purchaseLocks[src] then
        sendWashDenied(src, 'Your wash request is still processing.', false)
        return
    end
    purchaseLocks[src] = true

    local ok, errorMessage = xpcall(function()
        local session = sessions[src]
        if not session or session.token ~= tostring(data.sessionToken or '') then
            sendWashDenied(src, 'Car-wash session expired. Open the wash again.', true)
            releaseSession(src)
            return
        end
        if os.time() > (session.expiresAt or 0) then
            sendWashDenied(src, 'Car-wash session expired. Open the wash again.', true)
            releaseSession(src)
            return
        end

        local valid, vehicle = validateVehicle(src, session.netId, session.plate, session.locationIndex)
        if not valid then
            sendWashDenied(src, tostring(vehicle), true)
            releaseSession(src)
            return
        end

        local currentDirt = getLiveDirt(vehicle.entity, vehicle.row)
        if currentDirt < (tonumber(Config.minDirtToOffer) or 0.5) then
            sendWashDenied(src, 'This vehicle is already clean.', false)
            return
        end

        local price = math.max(0, math.floor(tonumber(Config.price) or 0))
        local paid, paymentError = chargeCash(src, price)
        if not paid then
            sendWashDenied(src, paymentError or 'Cash payment failed.', false)
            return
        end

        local cleanTo = clamp(Config.cleanDirtLevel, 0.0, tonumber(Config.maxDirtLevel) or 15.0)
        if not serviceVehicle(vehicle.plate, { dirtLevel = cleanTo }) then
            local refunded = addCash(src, price, 'automatic-car-wash-refund')
            if not refunded then
                print(('[CM-CARWASH][CRITICAL] Could not refund $%d to source %s after service persistence failed.'):format(price, src))
                sendWashDenied(src, 'Vehicle update failed and the automatic refund failed. Contact an administrator.', true)
            else
                sendWashDenied(src, 'Vehicle update failed. Your cash was refunded.', true)
            end
            releaseSession(src)
            return
        end

        local duration = math.max(1500, tonumber(Config.durationMs) or 7000)
        activeWashes[vehicle.plate] = {
            src = src,
            netId = vehicle.netId,
            cleanDirtLevel = cleanTo,
            locationIndex = vehicle.locationIndex,
            completeAfter = os.time() + math.ceil(duration / 1000),
            expiresAt = os.time() + math.ceil(duration / 1000) + 8,
        }
        pcall(function() Entity(vehicle.entity).state:set('cmDirt', cleanTo, true) end)

        sessions[src] = nil
        -- Keep the plate locked for the real server-side service duration. A
        -- client cannot release it early by spoofing a completion event.
        SetTimeout(duration, function()
            TriggerClientEvent('cm-carwash:client:syncClean', -1, vehicle.netId, cleanTo)
            local active = activeWashes[vehicle.plate]
            if active and active.src == src and active.netId == vehicle.netId then
                activeWashes[vehicle.plate] = nil
                if vehicleLocks[vehicle.plate] == src then vehicleLocks[vehicle.plate] = nil end
                if locationLocks[vehicle.locationIndex] == src then locationLocks[vehicle.locationIndex] = nil end
            end
        end)

        TriggerClientEvent('cm-carwash:client:washApproved', src, {
            netId = vehicle.netId,
            plate = vehicle.plate,
            price = price,
            cash = getCash(src) or 0,
            durationMs = duration,
            cleanDirtLevel = cleanTo,
            message = ('Paid $%d cash. Automatic wash started.'):format(price),
            completeMessage = 'Wash complete · vehicle state saved',
        })
    end, debug.traceback)

    purchaseLocks[src] = nil
    if not ok then
        print('[CM-CARWASH][ERROR] ' .. tostring(errorMessage))
        sendWashDenied(src, 'The car wash encountered an internal error.', true)
        releaseSession(src)
    end
end)

RegisterNetEvent('cm-carwash:server:washComplete', function(netId)
    local src = source
    netId = tonumber(netId) or 0

    for plate, wash in pairs(activeWashes) do
        if wash.src == src and wash.netId == netId then
            wash.clientCompleted = true
            dbg('client wash animation completed', src, plate)
            return
        end
    end
end)

-- Deprecated legacy event. It intentionally cannot charge or wash without a
-- server-created NUI session.
RegisterNetEvent('cm-carwash:server:requestWash', function()
    TriggerClientEvent('cm-carwash:client:notify', source, 'Use the E interaction in the wash bay.', 'info')
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()

        for src, session in pairs(sessions) do
            if now > (session.expiresAt or 0) then
                releaseSession(src)
            end
        end

        for plate, wash in pairs(activeWashes) do
            if now > (wash.expiresAt or 0) then
                activeWashes[plate] = nil
                if vehicleLocks[plate] == wash.src then vehicleLocks[plate] = nil end
                if wash.locationIndex and locationLocks[wash.locationIndex] == wash.src then
                    locationLocks[wash.locationIndex] = nil
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    releaseSession(src)
    purchaseLocks[src] = nil
    openCooldowns[src] = nil
    purchaseCooldowns[src] = nil

    for plate, wash in pairs(activeWashes) do
        if wash.src == src then
            activeWashes[plate] = nil
            if vehicleLocks[plate] == src then vehicleLocks[plate] = nil end
            if wash.locationIndex and locationLocks[wash.locationIndex] == src then
                locationLocks[wash.locationIndex] = nil
            end
        end
    end
end)
