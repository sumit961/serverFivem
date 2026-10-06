local LiftSessions = {}
local LastOpenAt = {}
local LastSelectionAt = {}
local SessionCounter = 0

local function dprint(message)
    if Config.Debug then
        print(('[CM-LIFT] %s'):format(tostring(message)))
    end
end

local function openRejected(reason)
    dprint(('rejected reason=%s'):format(tostring(reason)))
    return false, reason
end

local function now()
    return GetGameTimer()
end

local function cleanString(value, maxLength)
    if type(value) ~= 'string' then return nil end

    value = value:gsub('[%c\r\n\t]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end

    return value:sub(1, maxLength)
end

local function cleanId(value)
    local id = cleanString(value, Config.MaxIdLength)
    if not id or not id:match('^[%w%._%-]+$') then return nil end
    return id
end

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function readVector4(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then
        return nil
    end

    local ok, x, y, z, heading = pcall(function()
        return value.x or value[1], value.y or value[2], value.z or value[3], value.w or value.heading or value[4]
    end)
    if not ok then return nil end

    x, y, z = finiteNumber(x), finiteNumber(y), finiteNumber(z)
    heading = finiteNumber(heading or 0)
    if not x or not y or not z or not heading then return nil end
    if x < -10000 or x > 10000 or y < -10000 or y > 10000 or z < -1000 or z > 5000 then return nil end
    if heading < -360 or heading > 360 then return nil end

    return { x = x, y = y, z = z, heading = heading }
end

local function readExitOffset(value)
    if value == nil then return 0.0 end
    local offset = finiteNumber(value)
    if not offset or offset < 0 or offset > Config.MaxExitOffset then return nil end
    return offset
end

local function applyExitOffset(coords, exitOffset)
    if not exitOffset or exitOffset == 0 then
        return { x = coords.x, y = coords.y, z = coords.z, heading = coords.heading }
    end

    local radians = math.rad(coords.heading)
    return {
        -- GTA heading 0 faces north; this keeps the supplied Z authoritative.
        x = coords.x - math.sin(radians) * exitOffset,
        y = coords.y + math.cos(radians) * exitOffset,
        z = coords.z,
        heading = coords.heading
    }
end

local function notify(src, message, notifyType)
    pcall(function()
        exports['cm-core']:Notify(src, message, notifyType or 'error', 4000)
    end)
end

local function reject(src, reason)
    dprint(('select rejected src=%s reason=%s'):format(tostring(src), tostring(reason)))
    local messages = {
        invalid_session = 'ELEVATOR UNAVAILABLE',
        expired_session = 'ELEVATOR UNAVAILABLE',
        invalid_floor = 'ELEVATOR UNAVAILABLE',
        no_available_destination = 'ELEVATOR UNAVAILABLE',
        locked_floor = 'THAT FLOOR IS LOCKED',
        current_floor = 'YOU ARE ALREADY ON THIS FLOOR',
        rate_limited = 'PLEASE WAIT BEFORE USING THE ELEVATOR AGAIN',
        in_vehicle = 'EXIT YOUR VEHICLE TO USE THE ELEVATOR',
        player_unavailable = 'ELEVATOR UNAVAILABLE',
        invalid_destination = 'ELEVATOR UNAVAILABLE'
    }
    notify(src, messages[reason] or 'ELEVATOR UNAVAILABLE', reason == 'locked_floor' and 'info' or 'error')
    TriggerClientEvent('cm-lift:client:rejected', src, reason)
end

local function sessionIdFor(src)
    SessionCounter = SessionCounter + 1
    return ('%s:%s:%s'):format(src, now(), SessionCounter)
end

local function playerVehicleState(src)
    local pedOk, ped = pcall(GetPlayerPed, src)
    if not pedOk or not ped or ped == 0 then return nil end

    local vehicleOk, vehicle = pcall(GetVehiclePedIsIn, ped, false)
    if not vehicleOk then return nil end
    return vehicle and vehicle ~= 0
end

local function normalizeFloor(rawFloor, currentFloor)
    if type(rawFloor) ~= 'table' then return nil end

    local id = cleanId(rawFloor.id)
    local label = cleanString(rawFloor.label, Config.MaxLabelLength)
    local coords = readVector4(rawFloor.coords)
    local exitOffset = readExitOffset(rawFloor.exitOffset)
    if not id or not label or not coords or exitOffset == nil then return nil end

    local current = currentFloor ~= nil and id == currentFloor
    local floor = {
        id = id,
        label = label,
        subtitle = cleanString(rawFloor.subtitle, Config.MaxSubtitleLength),
        icon = cleanString(rawFloor.icon, Config.MaxIconLength),
        locked = rawFloor.locked == true,
        lockedReason = cleanString(rawFloor.lockedReason, Config.MaxSubtitleLength),
        current = current,
        coords = coords,
        exitOffset = exitOffset
    }

    if not floor.locked then floor.lockedReason = nil end
    floor.disabled = floor.locked or floor.current
    return floor
end

local function presentationFor(session)
    local floors = {}
    for index, floor in ipairs(session.floors or {}) do
        floors[index] = {
            id = floor.id,
            label = floor.label,
            subtitle = floor.subtitle,
            icon = floor.icon,
            locked = floor.locked,
            lockedReason = floor.lockedReason,
            current = floor.current,
            disabled = floor.disabled
        }
    end

    return {
        sessionId = session.sessionId,
        id = session.id,
        label = session.label,
        direct = session.direct == true,
        directFloorId = session.directFloorId,
        floors = floors
    }
end

local function completeSession(src, session, destination, selectedFloorId, clientEvent)
    local resolved = applyExitOffset(destination.coords, destination.exitOffset)
    LiftSessions[src] = nil
    dprint(('select accepted src=%s floor=%s destination=%.4f,%.4f,%.4f'):format(
        tostring(src), tostring(selectedFloorId), resolved.x, resolved.y, resolved.z))

    TriggerEvent('cm-lift:server:completed', {
        ownerResource = session.ownerResource,
        liftId = session.id,
        source = src,
        selectedFloorId = selectedFloorId
    })

    TriggerClientEvent(clientEvent or 'cm-lift:client:beginTeleport', src, {
        sessionId = session.sessionId,
        destination = resolved
    })
end

local function OpenLift(src, data)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then
        return openRejected('invalid_source')
    end
    if type(data) ~= 'table' then return openRejected('invalid_data') end

    local requestedFloors = type(data.floors) == 'table' and #data.floors or (data.destination ~= nil and 1 or 0)
    dprint(('OpenLift id=%s current=%s totalFloors=%s'):format(
        tostring(data.id or ''), tostring(data.currentFloor or ''), tostring(requestedFloors)))

    local currentTime = now()
    if LastOpenAt[src] and currentTime - LastOpenAt[src] < Config.OpenRateLimitMs then
        return openRejected('rate_limited')
    end
    if LiftSessions[src] then return openRejected('session_active') end

    local id = cleanId(data.id)
    local label = cleanString(data.label or 'Elevator', Config.MaxLabelLength)
    local currentFloor = data.currentFloor and cleanId(data.currentFloor) or nil
    if not id or not label then return openRejected('invalid_data') end

    local hasDestination = data.destination ~= nil
    local hasFloors = data.floors ~= nil
    if hasDestination == hasFloors then return openRejected('invalid_data') end

    local session = {
        sessionId = sessionIdFor(src),
        id = id,
        label = label,
        ownerResource = GetInvokingResource(),
        createdAt = currentTime,
        floors = {},
        floorById = {},
        direct = false
    }

    if hasDestination then
        local coords = readVector4(data.destination)
        local exitOffset = readExitOffset(data.exitOffset)
        local destinationFloorId = data.destinationFloorId == nil and nil or cleanId(data.destinationFloorId)
        if not coords or exitOffset == nil or (data.destinationFloorId ~= nil and not destinationFloorId) then
            return openRejected('invalid_destination')
        end

        session.direct = true
        session.directFloorId = destinationFloorId
        session.destination = { coords = coords, exitOffset = exitOffset }
    else
        if type(data.floors) ~= 'table' or #data.floors < 1 or #data.floors > Config.MaxFloors then
            return openRejected('invalid_data')
        end

        local invalidFloorCount = 0
        for _, rawFloor in ipairs(data.floors) do
            local floor = normalizeFloor(rawFloor, currentFloor)
            if not floor then
                invalidFloorCount = invalidFloorCount + 1
            elseif session.floorById[floor.id] then
                return openRejected('invalid_data')
            else
                session.floors[#session.floors + 1] = floor
                session.floorById[floor.id] = floor
            end
        end
        if invalidFloorCount > 0 then
            dprint(('ignored invalid floors=%s'):format(invalidFloorCount))
        end
        if #session.floors == 0 then
            return openRejected('no_valid_floor')
        end

        local destinations = {}
        for _, floor in ipairs(session.floors) do
            if not floor.current and not floor.locked and not floor.disabled then
                destinations[#destinations + 1] = floor
            end
        end

        -- The current floor is not a destination. Decide direct-vs-menu from
        -- the remaining valid destinations, not from the raw floor count.
        if #destinations == 0 then
            dprint('rejected empty floor payload')
            return openRejected('no_available_destination')
        elseif #destinations == 1 then
            local floor = destinations[1]
            session.direct = true
            session.directFloorId = floor.id
            session.destination = { coords = floor.coords, exitOffset = floor.exitOffset }
            dprint(('selectable destinations=1 direct destination=%s'):format(floor.id))
        else
            dprint(('selectable destinations=%s'):format(#destinations))
        end
    end

    if session.direct then
        local vehicleState = playerVehicleState(src)
        if vehicleState == nil then return openRejected('player_unavailable') end
        if vehicleState then return openRejected('in_vehicle') end
    end

    LastOpenAt[src] = currentTime
    LiftSessions[src] = session
    dprint(('open requested session=%s'):format(session.sessionId))
    if session.direct then
        dprint(('direct destination, skipping menu session=%s'):format(session.sessionId))
        completeSession(src, session, session.destination, session.directFloorId, 'cm-lift:client:beginDirect')
        return true, session.sessionId
    else
        local destinationCount = 0
        for _, floor in ipairs(session.floors) do
            if not floor.current and not floor.locked and not floor.disabled then destinationCount = destinationCount + 1 end
        end
        dprint(('menu opened floors=%s session=%s'):format(destinationCount, session.sessionId))
    end
    TriggerClientEvent('cm-lift:client:open', src, presentationFor(session))
    return true, session.sessionId
end

exports('OpenLift', OpenLift)
exports('CreateLiftSession', OpenLift)

RegisterNetEvent('cm-lift:server:selectFloor', function(sessionId, floorId)
    local src = source
    local session = LiftSessions[src]
    local currentTime = now()

    dprint(('select request src=%s session=%s floor=%s'):format(tostring(src), tostring(sessionId), tostring(floorId)))

    if type(sessionId) ~= 'string' or not session or session.sessionId ~= sessionId then
        reject(src, 'invalid_session')
        return
    end
    if currentTime - session.createdAt > Config.SessionLifetimeMs then
        LiftSessions[src] = nil
        reject(src, 'expired_session')
        return
    end
    if LastSelectionAt[src] and currentTime - LastSelectionAt[src] < Config.SelectionRateLimitMs then
        reject(src, 'rate_limited')
        return
    end
    LastSelectionAt[src] = currentTime

    local vehicleState = playerVehicleState(src)
    dprint(('select vehicle state src=%s state=%s'):format(tostring(src), tostring(vehicleState)))
    if vehicleState == nil then
        LiftSessions[src] = nil
        reject(src, 'player_unavailable')
        return
    end
    if vehicleState then
        LiftSessions[src] = nil
        reject(src, 'in_vehicle')
        return
    end

    local destination = session.destination
    if not session.direct then
        if type(floorId) ~= 'string' then
            reject(src, 'invalid_floor')
            return
        end

        local floor = session.floorById[floorId]
        if not floor then
            reject(src, 'invalid_floor')
            return
        end
        if floor.locked then
            reject(src, 'locked_floor')
            return
        end
        if floor.current then
            reject(src, 'current_floor')
            return
        end
        destination = { coords = floor.coords, exitOffset = floor.exitOffset }
    elseif session.directFloorId and floorId ~= session.directFloorId then
        reject(src, 'invalid_floor')
        return
    elseif floorId ~= nil then
        reject(src, 'invalid_floor')
        return
    end

    local selectedFloorId = floorId
    completeSession(src, session, destination, selectedFloorId)
end)

RegisterNetEvent('cm-lift:server:cancel', function(sessionId)
    local src = source
    local session = LiftSessions[src]
    if session and session.sessionId == sessionId then LiftSessions[src] = nil end
end)

AddEventHandler('playerDropped', function()
    local src = source
    LiftSessions[src] = nil
    LastOpenAt[src] = nil
    LastSelectionAt[src] = nil
end)

CreateThread(function()
    while true do
        Wait(5000)
        local currentTime = now()
        for src, session in pairs(LiftSessions) do
            if currentTime - session.createdAt > Config.SessionLifetimeMs then
                LiftSessions[src] = nil
                TriggerClientEvent('cm-lift:client:sessionExpired', src, session.sessionId)
                dprint(('menu closed reason=session_expired session=%s'):format(session.sessionId))
            end
        end
    end
end)

local function runTestLift(src, mode)
    if src == 0 then
        print('[CM-LIFT] /testlift must be used in-game.')
        return
    end
    if not Config.Debug then
        TriggerClientEvent('chat:addMessage', src, { args = { 'CM LIFT', 'Lift diagnostics are disabled.' } })
        return
    end

    mode = tostring(mode or 'multi'):lower()
    dprint(('testlift invoked src=%s mode=%s'):format(tostring(src), mode))

        local ped = GetPlayerPed(src)
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        if mode == 'direct' then
            OpenLift(src, {
                id = 'debug_direct',
                label = 'Debug Elevator',
                destination = { x = coords.x, y = coords.y, z = coords.z, w = heading }
            })
            return
        end

        OpenLift(src, {
            id = 'debug_multi',
            label = 'Debug Elevator',
            currentFloor = 'current',
            floors = {
                { id = 'current', label = 'Current Position', coords = { x = coords.x, y = coords.y, z = coords.z, w = heading } },
                { id = 'offset', label = 'Offset Position', subtitle = 'Development test', coords = { x = coords.x + 1.0, y = coords.y, z = coords.z, w = heading } },
                { id = 'upper', label = 'Upper Test Floor', subtitle = 'Development test', coords = { x = coords.x + 2.0, y = coords.y, z = coords.z, w = heading } }
            }
        })
end

RegisterNetEvent('cm-lift:server:runTest', function(mode)
    runTestLift(source, mode)
end)

RegisterCommand('testlift', function(src, args)
    runTestLift(src, args[1])
end, false)
