local ActiveRentals = {}
local RentalSessions = {}
local ReceptionSessions = {}
local RentalLocks = {}
local LastRequestAt = {}
local TokenCounter = 0
local PlateCounter = 0

local function dprint(message)
    if Config.Debug then
        print(('[CM-HOTEL] %s'):format(tostring(message)))
    end
end

local function hotelConfig()
    return CMHotelSetup and CMHotelSetup.GetRuntime and CMHotelSetup.GetRuntime() or Config.Hotel or {}
end

local function cleanId(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c%s]+', ''):sub(1, 64)
    if value == '' or not value:match('^[%w%._%-]+$') then return nil end
    return value
end

local function number(value)
    local result = tonumber(value)
    if not result or result ~= result or result == math.huge or result == -math.huge then return nil end
    return result
end

local function readVector4(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end
    local ok, x, y, z, heading = pcall(function()
        return value.x or value[1], value.y or value[2], value.z or value[3], value.w or value.heading or value.h or value[4]
    end)
    if not ok then return nil end
    x, y, z, heading = number(x), number(y), number(z), number(heading or 0)
    if not x or not y or not z or not heading then return nil end
    if x < -10000 or x > 10000 or y < -10000 or y > 10000 or z < -1000 or z > 5000 then return nil end
    if heading < -360 or heading > 360 then return nil end
    return vector4(x, y, z, heading)
end

local function copyVector4(value)
    local coords = readVector4(value)
    return coords and vector4(coords.x, coords.y, coords.z, coords.w) or nil
end

local function getCharacterId(src)
    src = tonumber(src)
    if not src then return nil end

    if GetResourceState('cm-playerdata') == 'started' then
        local ok, charId = pcall(function() return exports['cm-playerdata']:GetCharacterId(src) end)
        if ok and charId ~= nil and tostring(charId) ~= '' then return tostring(charId) end
    end
    if GetResourceState('cm-core') == 'started' then
        local ok, charId = pcall(function() return exports['cm-core']:GetCharacterId(src) end)
        if ok and charId ~= nil and tostring(charId) ~= '' then return tostring(charId) end
    end
    return nil
end

local function notify(src, message, notifyType)
    if GetResourceState('cm-core') == 'started' then
        local ok = pcall(function()
            exports['cm-core']:Notify(src, tostring(message), notifyType or 'error', 4500)
        end)
        if ok then return end
    end
    TriggerClientEvent('chat:addMessage', src, { args = { 'CM HOTEL', tostring(message) } })
end

local function token(prefix, src)
    TokenCounter = TokenCounter + 1
    return ('%s:%s:%s:%s'):format(prefix, tostring(src), tostring(GetGameTimer()), tostring(TokenCounter))
end

local function requestRateLimited(src, key)
    local now = GetGameTimer()
    local cooldown = tonumber(Config.Rental and Config.Rental.requestCooldownMs) or 750
    local bucket = LastRequestAt[src]
    if type(bucket) ~= 'table' then
        bucket = {}
        LastRequestAt[src] = bucket
    end
    if bucket[key] and now - bucket[key] < cooldown then return true end
    bucket[key] = now
    return false
end

local function playerNear(src, coords, distance)
    coords = readVector4(coords)
    if not coords then return false end
    local pedOk, ped = pcall(GetPlayerPed, tonumber(src))
    if not pedOk or not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local playerCoords = GetEntityCoords(ped)
    local dx, dy, dz = playerCoords.x - coords.x, playerCoords.y - coords.y, playerCoords.z - coords.z
    local actualDistance = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
    return actualDistance <= (tonumber(distance) or 2.0), actualDistance
end

local function receptionConfig()
    return hotelConfig().receptionist or {}
end

local function rentalConfig()
    return hotelConfig().rental or {}
end

local function validateNearReception(src)
    local cfg = receptionConfig()
    return playerNear(src, cfg.coords, cfg.interactionDistance or 2.0)
end

local function validateNearRental(src)
    local cfg = rentalConfig()
    return playerNear(src, cfg.coords, cfg.interactionDistance or 2.0)
end

local function getHelpLocation(key)
    key = cleanId(key)
    if not key then return nil end

    local value = hotelConfig().help and hotelConfig().help[key]
    if key == 'rental' and not value then value = rentalConfig().coords end
    local coords = readVector4(value)
    if not coords then return nil end
    return vector3(coords.x, coords.y, coords.z)
end

local function findLift(liftId)
    liftId = cleanId(liftId)
    local lifts = hotelConfig().lifts or {}
    return liftId and lifts[liftId] or nil, liftId
end

local function findFloor(lift, floorId)
    floorId = cleanId(floorId)
    if not lift or type(lift.floors) ~= 'table' then return nil, floorId end
    for _, floor in ipairs(lift.floors) do
        if type(floor) == 'table' and cleanId(floor.id) == floorId then return floor, floorId end
    end
    return nil, floorId
end

local function validRentalOption(option)
    if type(option) ~= 'table' then return false end
    local id = cleanId(option.id)
    local model = type(option.model) == 'string' and option.model:match('^[%w_%-]+$') and option.model or nil
    local label = type(option.label) == 'string' and option.label:sub(1, 80) or nil
    local price = number(option.price)
    local duration = number(option.durationMinutes)
    return id ~= nil and model ~= nil and label ~= nil and label ~= '' and price ~= nil and price >= 0
        and duration ~= nil and duration >= 1 and duration <= 1440
end

local function findRentalOption(optionId)
    optionId = cleanId(optionId)
    for _, option in ipairs(Config.RentalVehicles or {}) do
        if validRentalOption(option) and cleanId(option.id) == optionId then return option end
    end
    return nil
end

local function activeRentalFor(charId)
    return charId and ActiveRentals[tostring(charId)] or nil
end

local function rentalEntity(record)
    if not record then return 0 end
    if record.netId then
        local ok, entity = pcall(NetworkGetEntityFromNetworkId, record.netId)
        if ok and entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    end
    if record.entity and DoesEntityExist(record.entity) then return record.entity end
    return 0
end

local function movingWithDriver(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local driver = GetPedInVehicleSeat(entity, -1)
    return driver and driver ~= 0 and GetEntitySpeed(entity) > (Config.Rental.highSpeedCleanupMps or 15.0)
end

local function clearRental(charId, reason, shouldNotify, allowDefer)
    charId = tostring(charId or '')
    local record = ActiveRentals[charId]
    if not record then return true end

    local entity = rentalEntity(record)
    if allowDefer and movingWithDriver(entity) then
        record.expiryPending = true
        return false, 'moving'
    end

    if GetResourceState('cm-vehicles') == 'started' and record.plate then
        local ok, deleted = pcall(function() return exports['cm-vehicles']:DeleteAdminVehicle(record.plate) end)
        if not ok or deleted ~= true then return false, 'vehicle_cleanup_failed' end
    elseif entity ~= 0 and DoesEntityExist(entity) then
        -- cm-vehicles owns these entities. If it is unavailable, do not issue
        -- a second cleanup path that could race its registry.
        return false, 'vehicle_owner_unavailable'
    end

    ActiveRentals[charId] = nil
    TriggerEvent('cm-hotel:server:rentalReturned', {
        characterId = charId,
        rentalId = record.optionId,
        plate = record.plate,
        reason = reason or 'returned'
    })
    if shouldNotify and record.source and GetPlayerName(record.source) then
        notify(record.source, reason == 'expired' and 'YOUR RENTAL VEHICLE HAS EXPIRED' or 'RENTAL VEHICLE RETURNED', reason == 'expired' and 'info' or 'success')
    end
    return true
end

local function isSpawnAreaClear(src, coords)
    local radius = tonumber(Config.Rental.spawnClearRadius) or 3.5
    local bucket = GetPlayerRoutingBucket(src)
    local ok, vehicles = pcall(GetGamePool, 'CVehicle')
    if not ok or type(vehicles) ~= 'table' then return false, 'spawn_check_unavailable' end

    for _, vehicle in ipairs(vehicles) do
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            local sameBucket = true
            local bucketOk, vehicleBucket = pcall(GetEntityRoutingBucket, vehicle)
            if bucketOk and vehicleBucket ~= bucket then sameBucket = false end
            if sameBucket then
                local vehicleCoords = GetEntityCoords(vehicle)
                local dx, dy, dz = vehicleCoords.x - coords.x, vehicleCoords.y - coords.y, vehicleCoords.z - coords.z
                if (dx * dx) + (dy * dy) + (dz * dz) <= radius * radius then return false, 'spawn_blocked' end
            end
        end
    end
    return true
end

local function rentalPresentation(src, charId, sessionToken)
    local active = activeRentalFor(charId)
    local options = {}
    if active then
        options[1] = {
            id = 'return',
            label = 'RETURN VEHICLE',
            description = 'Return your active temporary rental at the Hotel.'
        }
    else
        for _, option in ipairs(Config.RentalVehicles or {}) do
            if validRentalOption(option) then
                options[#options + 1] = {
                    id = cleanId(option.id),
                    label = tostring(option.label),
                    description = ('$%d · %d MIN'):format(math.floor(option.price), math.floor(option.durationMinutes))
                }
            end
        end
    end

    return {
        token = sessionToken,
        active = active ~= nil,
        configured = #options > 0,
        options = options
    }
end

local function OpenLiftForPlayer(src, liftId, floorId)
    local lift, safeLiftId = findLift(liftId)
    local floor, safeFloorId = findFloor(lift, floorId)
    if not lift or not floor or not safeLiftId or not safeFloorId then
        dprint(('lift request src=%s floor=%s rejected reason=unknown_floor'):format(tostring(src), tostring(floorId)))
        notify(src, 'ELEVATOR UNAVAILABLE', 'error')
        return false
    end

    local interaction = readVector4(floor.interaction)
    local near, distance = false, nil
    if interaction then
        near, distance = playerNear(src, interaction, floor.interactionDistance or lift.interactionDistance or 2.0)
    end
    dprint(('lift request src=%s floor=%s distance=%s'):format(tostring(src), tostring(safeFloorId), distance and ('%.2f'):format(distance) or 'invalid'))
    if not interaction or not near then
        dprint(('lift request src=%s floor=%s rejected reason=too_far'):format(tostring(src), tostring(safeFloorId)))
        notify(src, 'MOVE CLOSER TO THE ELEVATOR', 'error')
        return false
    end

    local available = {}
    local seenFloorIds = {}
    for _, candidate in ipairs(lift.floors or {}) do
        local id = type(candidate) == 'table' and cleanId(candidate.id) or nil
        local destination = type(candidate) == 'table' and copyVector4(candidate.destination) or nil
        local label = type(candidate) == 'table' and tostring(candidate.label or id or 'Floor'):sub(1, 80) or nil
        if id and destination and label and not seenFloorIds[id] then
            available[#available + 1] = { id = id, label = label, coords = destination }
            seenFloorIds[id] = true
        end
    end
    if #available == 0 then
        dprint(('lift request src=%s floor=%s rejected reason=no_valid_floor'):format(tostring(src), tostring(safeFloorId)))
        notify(src, 'ELEVATOR UNAVAILABLE', 'error')
        return false
    end

    local payload = {
        id = ('hotel_%s'):format(safeLiftId),
        label = tostring(lift.label or 'Hotel Elevator'),
        currentFloor = safeFloorId
    }

    local destinations = {}
    for _, candidate in ipairs(available) do
        if candidate.id ~= safeFloorId then destinations[#destinations + 1] = candidate end
    end

    dprint(('lift request src=%s floor=%s selectable destinations=%s'):format(tostring(src), tostring(safeFloorId), tostring(#destinations)))

    -- Decide direct-vs-menu after removing the floor the player is standing on.
    if #destinations == 1 then
        local target = destinations[1]
        payload.destination = target.coords
        payload.destinationFloorId = target.id
        dprint(('direct destination=%s'):format(target.id))
    elseif #destinations > 1 then
        payload.floors = available
    else
        dprint(('lift request src=%s floor=%s rejected reason=no_available_destination'):format(tostring(src), tostring(safeFloorId)))
        notify(src, 'ELEVATOR UNAVAILABLE', 'error')
        return false
    end

    local ok, opened, reason = pcall(function() return exports['cm-lift']:OpenLift(src, payload) end)
    if not ok or opened ~= true then
        dprint(('lift request src=%s floor=%s rejected reason=%s'):format(tostring(src), tostring(safeFloorId), tostring(ok and reason or 'cm_lift_error')))
        notify(src, 'ELEVATOR UNAVAILABLE', 'error')
        return false
    end
    return true
end

exports('GetFirstSpawn', function()
    local cfg = hotelConfig()
    if cfg.enabled ~= true then return nil end
    local coords = copyVector4(cfg.firstSpawn)
    if not coords then return nil end
    return { key = 'hotel', label = 'HOTEL', coords = coords }
end)

exports('GetHelpLocation', function(key)
    local coords = getHelpLocation(key)
    return coords and vector3(coords.x, coords.y, coords.z) or nil
end)

RegisterNetEvent('cm-hotel:server:useLift', function(liftId, floorId)
    local src = source
    if hotelConfig().enabled ~= true then return end
    if requestRateLimited(src, 'lift') then return end
    OpenLiftForPlayer(src, liftId, floorId)
end)

RegisterNetEvent('cm-hotel:server:setupTestLift', function(supplied, direction)
    local src = source
    if not CMHotelSetup or not CMHotelSetup.IsSessionValid or not CMHotelSetup.IsSessionValid(src, supplied) then
        notify(src, 'HOTEL SETUP SESSION EXPIRED', 'error')
        return
    end
    local floorId = direction == 'lobbyToRooms' and 'lobby' or direction == 'roomsToLobby' and 'rooms' or nil
    if not floorId then notify(src, 'INVALID HOTEL LIFT TEST', 'error') return end
    OpenLiftForPlayer(src, 'main', floorId)
end)

RegisterNetEvent('cm-hotel:server:useReception', function()
    local src = source
    if requestRateLimited(src, 'reception') then return end
    if hotelConfig().enabled ~= true or not validateNearReception(src) then
        notify(src, 'MOVE CLOSER TO HOTEL RECEPTION', 'error')
        return
    end

    local charId = getCharacterId(src)
    if not charId then
        notify(src, 'YOUR CHARACTER IS NOT READY', 'error')
        return
    end

    local sessionToken = token('reception', src)
    ReceptionSessions[src] = { token = sessionToken, characterId = charId, expiresAt = GetGameTimer() + 30000 }
    TriggerClientEvent('cm-hotel:client:openReception', src, { token = sessionToken })
    TriggerEvent('cm-hotel:server:receptionUsed', { characterId = charId })
end)

RegisterNetEvent('cm-hotel:server:receptionChoice', function(sessionToken, choiceId)
    local src = source
    if requestRateLimited(src, 'receptionChoice') then return end
    local session = ReceptionSessions[src]
    local charId = getCharacterId(src)
    choiceId = cleanId(choiceId)
    if not session or session.token ~= sessionToken or GetGameTimer() > session.expiresAt or not charId or tostring(charId) ~= tostring(session.characterId) then
        notify(src, 'HOTEL RECEPTION IS UNAVAILABLE', 'error')
        return
    end
    if not validateNearReception(src) then
        notify(src, 'RETURN TO HOTEL RECEPTION', 'error')
        return
    end

    local messages = {
        new = 'Welcome to the city. Start with transportation, obtain your driving licence, visit the Job Centre, complete your first job, and explore the essentials.',
        rental = 'I can mark the beginner rental desk for you.',
        license = 'I can mark the driving test centre for you.',
        job = 'I can mark the Job Centre for you.',
        essentials = 'I can mark the nearest essential city service for you.'
    }
    if not messages[choiceId] then
        notify(src, 'That reception option is unavailable.', 'error')
        return
    end

    local helpKey = ({ rental = 'rental', license = 'license', job = 'jobCentre', essentials = 'hospital' })[choiceId]
    local coords = helpKey and getHelpLocation(helpKey) or nil
    TriggerClientEvent('cm-hotel:client:receptionResponse', src, {
        ok = true,
        message = messages[choiceId],
        waypoint = coords and { label = choiceId:upper(), x = coords.x, y = coords.y, z = coords.z } or nil,
        unavailable = helpKey ~= nil and coords == nil
    })
end)

RegisterNetEvent('cm-hotel:server:openRental', function()
    local src = source
    if requestRateLimited(src, 'rentalOpen') then return end
    if hotelConfig().enabled ~= true or not validateNearRental(src) then
        notify(src, 'MOVE CLOSER TO THE RENTAL DESK', 'error')
        return
    end
    local charId = getCharacterId(src)
    if not charId then
        notify(src, 'YOUR CHARACTER IS NOT READY', 'error')
        return
    end

    local sessionToken = token('rental', src)
    RentalSessions[src] = { token = sessionToken, characterId = tostring(charId), expiresAt = GetGameTimer() + (Config.Rental.sessionLifetimeMs or 15000) }
    TriggerClientEvent('cm-hotel:client:openRental', src, rentalPresentation(src, tostring(charId), sessionToken))
end)

RegisterNetEvent('cm-hotel:server:rentalChoice', function(sessionToken, optionId)
    local src = source
    if requestRateLimited(src, 'rentalChoice') then return end
    local session = RentalSessions[src]
    local charId = getCharacterId(src)
    optionId = cleanId(optionId)
    local nowTime = GetGameTimer()
    if not session or session.token ~= sessionToken or nowTime > session.expiresAt or not charId or tostring(charId) ~= tostring(session.characterId) then
        notify(src, 'RENTAL MENU EXPIRED', 'error')
        return
    end
    if not validateNearRental(src) then
        notify(src, 'RETURN TO THE HOTEL RENTAL DESK', 'error')
        return
    end
    RentalSessions[src] = nil

    charId = tostring(charId)
    if RentalLocks[charId] then
        notify(src, 'PLEASE WAIT, YOUR RENTAL IS BEING PROCESSED', 'error')
        return
    end
    RentalLocks[charId] = true

    local function finish(message, kind)
        RentalLocks[charId] = nil
        TriggerClientEvent('cm-hotel:client:rentalResult', src, { ok = kind == 'success', message = message, type = kind or 'error' })
    end

    if optionId == 'return' then
        local record = activeRentalFor(charId)
        if not record then finish('YOU DO NOT HAVE AN ACTIVE RENTAL', 'error') return end
        local entity = rentalEntity(record)
        local rentalDistance = tonumber(rentalConfig().returnDistance) or 12.0
        if entity == 0 or not playerNear(src, { x = GetEntityCoords(entity).x, y = GetEntityCoords(entity).y, z = GetEntityCoords(entity).z, w = 0.0 }, rentalDistance) then
            finish('BRING YOUR RENTAL VEHICLE BACK TO THE HOTEL', 'error')
            return
        end
        local removed, reason = clearRental(charId, 'returned', false, false)
        finish(removed and 'RENTAL VEHICLE RETURNED' or ('RENTAL RETURN FAILED: ' .. tostring(reason)), removed and 'success' or 'error')
        return
    end

    if activeRentalFor(charId) then
        finish('YOU ALREADY HAVE A RENTAL VEHICLE', 'error')
        return
    end

    local option = findRentalOption(optionId)
    local spawn = copyVector4(rentalConfig().vehicleSpawn)
    if not option or not spawn or GetResourceState('cm-vehicles') ~= 'started' then
        finish('RENTAL SERVICE IS NOT CONFIGURED', 'error')
        return
    end

    local clear, clearReason = isSpawnAreaClear(src, spawn)
    if not clear then
        finish(clearReason == 'spawn_blocked' and 'RENTAL AREA BLOCKED · PLEASE WAIT' or 'RENTAL AREA IS UNAVAILABLE', 'error')
        return
    end

    local price = math.floor(number(option.price) or 0)
    local account = cleanId(rentalConfig().account or 'cash') or 'cash'
    if price > 0 then
        local paid, paymentReason = exports['cm-core']:RemoveMoney(src, account, price, 'hotel_rental:' .. tostring(option.id))
        if paid ~= true then
            finish(paymentReason == 'insufficient_funds' and 'YOU CANNOT AFFORD THIS RENTAL' or 'RENTAL PAYMENT FAILED', 'error')
            return
        end
    end

    PlateCounter = PlateCounter + 1
    local prefix = tostring(rentalConfig().platePrefix or 'CMR'):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)
    local plate = ('%s%04d'):format(prefix == '' and 'CMR' or prefix, PlateCounter % 10000)
    local spawnResult = exports['cm-vehicles']:SpawnAdminVehicle(src, option.model, {
        x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.w
    }, {
        placementKind = 'car',
        access = 'owner',
        ownerCid = charId,
        label = option.label,
        plate = plate,
        warp = true,
        engineOn = true
    })

    if type(spawnResult) ~= 'table' or spawnResult.ok ~= true then
        if price > 0 then exports['cm-core']:AddMoney(src, account, price, 'hotel_rental_refund:' .. tostring(option.id)) end
        finish(type(spawnResult) == 'table' and tostring(spawnResult.error or 'RENTAL VEHICLE COULD NOT BE SPAWNED') or 'RENTAL VEHICLE COULD NOT BE SPAWNED', 'error')
        return
    end

    local expiresAt = os.time() + (math.floor(number(option.durationMinutes) or 30) * 60)
    ActiveRentals[charId] = {
        source = src,
        characterId = charId,
        optionId = tostring(option.id),
        label = tostring(option.label),
        plate = tostring(spawnResult.plate or plate),
        netId = tonumber(spawnResult.netId),
        entity = tonumber(spawnResult.entity),
        expiresAt = expiresAt
    }
    TriggerEvent('cm-hotel:server:rentalCreated', {
        characterId = charId,
        rentalId = tostring(option.id),
        plate = ActiveRentals[charId].plate,
        durationMinutes = math.floor(number(option.durationMinutes) or 30)
    })
    finish(('%s rented for %d minutes'):format(option.label, math.floor(number(option.durationMinutes) or 30)), 'success')
end)

AddEventHandler('cm-lift:server:completed', function(payload)
    if type(payload) ~= 'table' or payload.ownerResource ~= GetCurrentResourceName() then return end
    local src = tonumber(payload.source)
    local charId = src and getCharacterId(src) or nil
    if not charId then return end
    TriggerEvent('cm-hotel:server:liftUsed', {
        characterId = tostring(charId),
        liftId = tostring(payload.liftId or ''),
        floorId = payload.selectedFloorId and tostring(payload.selectedFloorId) or nil
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    local charId = getCharacterId(src)
    RentalSessions[src] = nil
    ReceptionSessions[src] = nil
    LastRequestAt[src] = nil
    if charId then
        clearRental(charId, 'disconnect', false, false)
    else
        for trackedCharId, record in pairs(ActiveRentals) do
            if record.source == src then
                clearRental(trackedCharId, 'disconnect', false, false)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(tonumber(Config.Rental.expiryCheckMs) or 10000)
        local nowTime = os.time()
        for charId, record in pairs(ActiveRentals) do
            if nowTime >= tonumber(record.expiresAt or 0) then
                clearRental(charId, 'expired', true, true)
            elseif record.source and GetPlayerName(record.source) and tostring(getCharacterId(record.source) or '') ~= tostring(charId) then
                clearRental(charId, 'character_changed', false, false)
            end
        end
        for src, session in pairs(RentalSessions) do
            if GetGameTimer() > session.expiresAt then RentalSessions[src] = nil end
        end
        for src, session in pairs(ReceptionSessions) do
            if GetGameTimer() > session.expiresAt then ReceptionSessions[src] = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('cm-vehicles') == 'started' then
        for charId in pairs(ActiveRentals) do clearRental(charId, 'resource_restart', false, false) end
    end
    ActiveRentals = {}
    RentalSessions = {}
    ReceptionSessions = {}
    RentalLocks = {}
end)
