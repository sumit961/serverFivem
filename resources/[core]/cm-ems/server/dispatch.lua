-- Server-authoritative EMS ambulance dispatch.

local DispatchCalls = {}
local DispatchByCaller = {}
local dispatchSequence = 0
local assignGovernmentDoctor
local broadcast

-- [vehicleEntity] = { doctor = doctorEntity, host = src }. Populated only by
-- the trusted spawn path below (never from client input), so the departed
-- handoff can only ever act on an entity a client's own government doctor
-- actually owns -- never an arbitrary vehicle someone points a netId at.
local ManagedGovernmentEntities = {}
local GovernmentCleanup = {}
local GovernmentResponses = {}

local function responderRows(call)
    local rows = {}
    for characterId, responder in pairs(call.responders or {}) do
        rows[#rows + 1] = {
            characterId = tostring(characterId), name = responder.name,
            source = responder.source, status = responder.status or 'en_route',
            acceptedAt = responder.acceptedAt,
        }
    end
    table.sort(rows, function(a, b) return (a.acceptedAt or 0) < (b.acceptedAt or 0) end)
    return rows
end

local function persistIncident(call, resolved)
    if not call or not call.id then return end
    MySQL.update.await([[UPDATE cm_ems_incidents SET status = ?, priority = ?, patient_count = ?,
        responders = ?, resolution = ?, resolved_at = IF(? = 1, CURRENT_TIMESTAMP, resolved_at) WHERE id = ?]], {
        tostring(call.responseStatus or call.status or 'waiting'), tonumber(call.priority) or 2,
        tonumber(call.patientCount) or 1, json.encode(responderRows(call)), call.resolutionReason,
        resolved and 1 or 0, call.id,
    })
end

local function incidentEvent(incidentId, eventType, actorCharacterId, detail)
    incidentId = tonumber(incidentId)
    if not incidentId then return end
    local actorCid = actorCharacterId and tostring(actorCharacterId) or nil
    MySQL.insert.await([[INSERT INTO cm_ems_incident_events
        (incident_id, actor_cid, actor_name, event_type, detail) VALUES (?, ?, ?, ?, ?)]], {
        incidentId, actorCid, actorCid and nameFor(actorCid) or 'System', tostring(eventType), json.encode(detail or {}),
    })
end

local ResponseTransitions = {
    waiting = { driving = true, departing = true },
    driving = { parked = true, departing = true },
    parked = { treating = true, waiting_nearby = true, departing = true },
    treating = { parked = true, waiting_nearby = true, departing = true },
    waiting_nearby = { treating = true, parked = true, departing = true },
    departing = { cleanup = true },
    cleanup = {},
}

local function setResponseState(response, nextState)
    if not response or not ResponseTransitions[nextState] then return false end
    local current = response.state or 'waiting'
    if current == nextState then return true end
    if not (ResponseTransitions[current] and ResponseTransitions[current][nextState]) then return false end
    response.state = nextState
    response.stateChangedAt = GetGameTimer()
    return true
end

local function dispatchNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function cleanDetails(value)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #value > 180 then value = value:sub(1, 180) end
    return value ~= '' and value or 'Medical assistance requested.'
end

local function cleanNote(value)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #value > 120 then value = value:sub(1, 120) end
    return value ~= '' and value or nil
end

local function dispatchMember(src, permission)
    local characterId = cid(tonumber(src))
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, permission or 'ems.receive_dispatch') then
        return nil, characterId
    end
    return member, tostring(characterId)
end

local function recipients(permission)
    local out = {}
    for _, rawSrc in ipairs(GetPlayers()) do
        local targetSrc = tonumber(rawSrc)
        if targetSrc and dispatchMember(targetSrc, permission) then out[#out + 1] = targetSrc end
    end
    return out
end

local function minimumGovernmentStaffing()
    return math.max(0, math.floor(tonumber(((Config.Dispatch or {}).governmentDoctor or {}).minimumOnDutyEMS) or 1))
end

local function publicCall(call)
    return {
        id = call.id,
        code = call.code,
        title = call.title,
        status = call.status,
        details = call.details,
        callerName = call.callerName,
        callerCharacterId = call.callerCharacterId,
        coords = call.coords,
        bucket = call.bucket,
        area = call.area,
        createdAt = call.createdAt,
        expiresAt = call.expiresAt,
        acceptedByName = call.acceptedByName,
        acceptedByCharacterId = call.acceptedByCharacterId,
        responderType = call.responderType,
        incidentNumber = call.incidentNumber,
        patientCount = tonumber(call.patientCount) or 1,
        emergencyType = call.emergencyType or 'medical',
        priority = tonumber(call.priority) or 2,
        postal = call.postal or 'N/A',
        location = call.location or call.postal and ('Postal ' .. tostring(call.postal)) or 'Location available by GPS',
        responseStatus = call.responseStatus or 'waiting',
        backupRequested = call.backupRequested == true,
        priorityAcknowledgedBy = call.priorityAcknowledgedBy,
        panicOwnerName = call.panicOwnerName,
        patientInAmbulance = call.patientInAmbulance == true,
        transportVehiclePlate = call.transportVehiclePlate,
        notes = call.notes or {},
        responders = responderRows(call),
        resolutionReason = call.resolutionReason,
        cardLifetimeMs = tonumber(Config.Dispatch.cardLifetimeMs) or 18000,
        blipLifetimeMs = tonumber(Config.Dispatch.blipLifetimeMs) or 300000,
    }
end

local function callDistance(a, b)
    if not a or not b or type(a.coords) ~= 'table' or type(b.coords) ~= 'table' then return math.huge end
    local dx = (tonumber(a.coords.x) or 0.0) - (tonumber(b.coords.x) or 0.0)
    local dy = (tonumber(a.coords.y) or 0.0) - (tonumber(b.coords.y) or 0.0)
    local dz = (tonumber(a.coords.z) or 0.0) - (tonumber(b.coords.z) or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function protectCall(call, response, etaMs)
    if not call or not response then return end
    local options = Config.Dispatch.governmentDoctor or {}
    etaMs = math.max(0, math.floor(tonumber(etaMs) or 0))
    local minimum = etaMs + (tonumber(options.treatmentMs) or 10000)
        + (tonumber(options.protectionSafetyMs) or 30000)
    pcall(function()
        exports[Config.PlayerDataResource]:ProtectDeathTimer(
            tonumber(call.callerSource), minimum, etaMs, 'AI EMS RESPONDING', 'government:' .. tostring(response.id))
    end)
end

local function addResponsePatient(response, call)
    if not response or not call then return end
    response.patients = response.patients or {}
    response.patients[call.id] = {
        callId = call.id,
        source = tonumber(call.callerSource),
        coords = call.coords,
        createdAt = tonumber(call.createdAt) or os.time(),
        retryAfter = 0,
        attempts = 0,
    }
end

local function removeResponsePatient(call)
    if not call then return end
    local response = GovernmentResponses[tonumber(call.governmentResponseId or call.id)]
    if not response or not response.patients then return end
    response.patients[call.id] = nil
    if tonumber(response.currentCallId) == tonumber(call.id) then response.currentCallId = nil end
end

local function attachNearbyGovernmentResponse(call, automatic)
    local radius = tonumber(emsSetting('sharedResponseRadius')) or tonumber((Config.Dispatch.governmentDoctor or {}).sharedResponseRadius) or 40.0
    local best, bestDistance
    for _, response in pairs(GovernmentResponses) do
        if response.host and GetPlayerName(response.host)
            and not response.closing and response.bucket == call.bucket then
            local distance = callDistance(call, response)
            if type(response.position) == 'table' then
                distance = math.min(distance, callDistance(call, { coords = response.position }))
            end
            if distance <= radius and (not bestDistance or distance < bestDistance) then
                best, bestDistance = response, distance
            end
        end
    end
    if not best then return false end

    local responseId = tonumber(best.id)
    call.responderType = 'government_doctor'
    call.acceptedByName = 'Government Doctor'
    call.governmentHost = best.host
    call.governmentResponseId = responseId
    call.governmentStartedAt = best.startedAt or GetGameTimer()
    call.governmentAutomatic = automatic == true
    call.governmentVehicle = best.vehicle
    call.governmentDoctor = best.doctor
    addResponsePatient(best, call)
    local etaMs = math.max(0, (tonumber(best.arrivalAt) or GetGameTimer()) - GetGameTimer())
    protectCall(call, best, etaMs)

    TriggerClientEvent('cm-ems:client:addGovernmentDoctorPatient', call.governmentHost, responseId, {
        id = call.id,
        source = call.callerSource,
        coords = call.coords,
    })
    dispatchNotify(call.callerSource, 'The nearby government doctor will treat you after the current patient.', 'success')
    log(call.callerCharacterId, 'government_doctor_shared_response', {
        callId = call.id,
        responseId = responseId,
        distance = math.floor((bestDistance or 0.0) * 10.0) / 10.0,
    })
    incidentEvent(call.id, 'ai_assigned', nil, { responseId = responseId, shared = true })
    call.responseStatus = 'assigned_ai'
    persistIncident(call, false)
    broadcast('updated', call.id)
    return true
end

assignGovernmentDoctor = function(call, actorCharacterId, automatic)
    if not call or call.acceptedByCharacterId or call.responderType then return false, 'This call already has a responder.' end
    local callerSrc
    for _, rawSrc in ipairs(GetPlayers()) do
        if tostring(cid(tonumber(rawSrc)) or '') == call.callerCharacterId then callerSrc = tonumber(rawSrc); break end
    end
    if not callerSrc or not GetPlayerName(callerSrc) then return false, 'The patient is no longer online.' end
    local isDead = false
    pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(callerSrc) == true end)
    if not isDead then return false, 'The patient no longer needs treatment.' end

    if attachNearbyGovernmentResponse(call, automatic) then
        return true, 'A nearby government doctor will treat this patient.', publicCall(call)
    end

    -- However this got triggered -- immediately, an EMS member clicking
    -- "send" late, or a retry -- the patient's actual bleed-out clock is
    -- what matters, not the dispatch's usual random pacing. Pass the real
    -- remaining time through so the client can shrink its arrival delay
    -- when there isn't 1-3 minutes left to spare.
    local patientRemainingMs = nil
    pcall(function()
        local info = exports[Config.PlayerDataResource]:GetDeathInfo(callerSrc)
        if type(info) == 'table' then patientRemainingMs = tonumber(info.remainingMs) end
    end)

    call.responderType = 'government_doctor'
    call.acceptedByName = 'Government Doctor'
    call.governmentStartedAt = GetGameTimer()
    call.governmentHost = callerSrc
    call.governmentAutomatic = automatic == true
    call.governmentResponseId = call.id
    call.governmentClosing = nil
    GovernmentResponses[call.id] = {
        id = call.id,
        host = callerSrc,
        bucket = call.bucket,
        coords = call.coords,
        startedAt = call.governmentStartedAt,
        automatic = automatic == true,
        closing = false,
        state = 'waiting',
        stateChangedAt = GetGameTimer(),
        arrivalAt = GetGameTimer() + (tonumber(emsSetting('aiArrivalMs')) or tonumber((Config.Dispatch.governmentDoctor or {}).arrivalMaxMs) or 120000),
        patients = {},
    }
    addResponsePatient(GovernmentResponses[call.id], call)
    protectCall(call, GovernmentResponses[call.id], tonumber(emsSetting('aiArrivalMs')) or tonumber((Config.Dispatch.governmentDoctor or {}).arrivalMaxMs) or 120000)

    -- Claim valid nearby calls that were already waiting before this AI
    -- response was created. New calls are handled by createAmbulanceCall;
    -- this closes the opposite ordering race (other call existed first).
    for _, nearbyCall in pairs(DispatchCalls) do
        if nearbyCall ~= call and not nearbyCall.responderType and not nearbyCall.acceptedByCharacterId
            and nearbyCall.bucket == call.bucket then
            local nearbySrc = tonumber(nearbyCall.callerSource)
            local nearbyDead = false
            if nearbySrc and GetPlayerName(nearbySrc) then
                pcall(function() nearbyDead = exports[Config.PlayerDataResource]:IsDead(nearbySrc) == true end)
            end
            if nearbyDead then attachNearbyGovernmentResponse(nearbyCall, automatic) end
        end
    end

    -- Shallow copy: never write into the shared Config table itself, or a
    -- stale patientRemainingMs would leak into every dispatch after this one.
    local options = {}
    for key, value in pairs(Config.Dispatch.governmentDoctor or {}) do options[key] = value end
    options.patientRemainingMs = patientRemainingMs
    options.arrivalMinMs = tonumber(emsSetting('aiArrivalMs')) or options.arrivalMinMs
    options.arrivalMaxMs = tonumber(emsSetting('aiArrivalMs')) or options.arrivalMaxMs
    options.sharedResponseRadius = tonumber(emsSetting('sharedResponseRadius')) or options.sharedResponseRadius

    TriggerClientEvent('cm-ems:client:prepareGovernmentDoctor', callerSrc, publicCall(call), options)
    log(actorCharacterId, 'government_doctor_dispatched', { callId = call.id, automatic = automatic == true, patientRemainingMs = patientRemainingMs })
    incidentEvent(call.id, 'ai_assigned', actorCharacterId, { automatic = automatic == true })
    call.responseStatus = 'assigned_ai'
    persistIncident(call, false)
    broadcast('updated', call.id)
    return true, 'Government doctor dispatched.', publicCall(call)
end

RegisterNetEvent('cm-ems:server:spawnGovernmentDoctor', function(callId, spawn, heading, stopPoint)
    local src, call = source, DispatchCalls[tonumber(callId)]
    if not call or call.governmentHost ~= src or call.responderType ~= 'government_doctor' or call.governmentVehicle then return end
    if not rateLimit(src, 'spawn_government_doctor', 2000) or type(spawn) ~= 'table' or type(stopPoint) ~= 'table' then return end
    local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
    if not x or not y or not z then return end
    local patientPed = GetPlayerPed(src)
    if not patientPed or patientPed == 0 then return end
    local patient = GetEntityCoords(patientPed)
    local distance = math.sqrt((x - patient.x)^2 + (y - patient.y)^2 + (z - patient.z)^2)
    local governmentOptions = Config.Dispatch.governmentDoctor or {}
    local minimumSpawn = tonumber(governmentOptions.spawnMinDistance) or 55.0
    local maximumSpawn = tonumber(governmentOptions.spawnMaxDistance) or 100.0
    -- Match the client's documented relaxed road-node pass without allowing
    -- an ambulance to be created on top of the patient or outside simulation.
    if distance < minimumSpawn * 0.55 or distance > maximumSpawn * 1.5 then
        TriggerClientEvent('cm-ems:client:governmentDoctorSpawnFailed', src, call.id, 'unsafe_spawn_distance')
        return
    end
    local stopX, stopY, stopZ = tonumber(stopPoint.x), tonumber(stopPoint.y), tonumber(stopPoint.z)
    if not stopX or not stopY or not stopZ then return end
    local stopDistance = math.sqrt((stopX - patient.x)^2 + (stopY - patient.y)^2 + (stopZ - patient.z)^2)
    local minimumStop = tonumber(governmentOptions.sceneStopMinDistance) or 14.0
    local maximumStop = tonumber(governmentOptions.sceneStopMaxDistance) or 28.0
    if stopDistance < minimumStop * 0.55 or stopDistance > maximumStop * 1.7 then
        TriggerClientEvent('cm-ems:client:governmentDoctorSpawnFailed', src, call.id, 'unsafe_scene_stop')
        return
    end

    local options = governmentOptions
    local vehicleHash, pedHash = joaat(options.vehicleModel or 'ambulance'), joaat(options.pedModel or 's_m_m_paramedic_01')
    local vehicle
    if type(CreateVehicleServerSetter) == 'function' then
        vehicle = CreateVehicleServerSetter(vehicleHash, 'automobile', x, y, z, tonumber(heading) or 0.0)
    else
        vehicle = CreateVehicle(vehicleHash, x, y, z, tonumber(heading) or 0.0, true, true)
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        TriggerClientEvent('cm-ems:client:governmentDoctorSpawnFailed', src, call.id, 'vehicle_create_failed')
        return
    end
    local doctor = CreatePed(4, pedHash, x, y, z + 1.0, tonumber(heading) or 0.0, true, true)
    if not doctor or doctor == 0 or not DoesEntityExist(doctor) then
        DeleteEntity(vehicle)
        TriggerClientEvent('cm-ems:client:governmentDoctorSpawnFailed', src, call.id, 'doctor_create_failed')
        return
    end
    local bucket = GetPlayerRoutingBucket(src)
    SetEntityRoutingBucket(vehicle, bucket); SetEntityRoutingBucket(doctor, bucket)
    local streamingRadius = tonumber(options.streamingRadius) or 1200.0
    pcall(SetEntityDistanceCullingRadius, vehicle, streamingRadius)
    pcall(SetEntityDistanceCullingRadius, doctor, streamingRadius)
    call.governmentVehicle, call.governmentDoctor = vehicle, doctor
    local response = GovernmentResponses[tonumber(call.governmentResponseId or call.id)]
    if response then
        response.vehicle, response.doctor = vehicle, doctor
        setResponseState(response, 'driving')
    end
    for _, linkedCall in pairs(DispatchCalls) do
        if tonumber(linkedCall.governmentResponseId) == tonumber(call.id) then
            linkedCall.governmentVehicle = vehicle
            linkedCall.governmentDoctor = doctor
        end
    end
    ManagedGovernmentEntities[vehicle] = {
        doctor = doctor,
        host = src,
        responseId = tonumber(call.governmentResponseId or call.id),
    }
    pcall(SetPedIntoVehicle, doctor, vehicle, -1)
    local driveSpeed = tonumber(options.driveSpeed) or 25.0
    pcall(TaskVehicleDriveToCoordLongrange, doctor, vehicle, stopX, stopY, stopZ, driveSpeed, 1074528293, 5.0)
    local initialPosition = { x = x, y = y, z = z }
    TriggerClientEvent('cm-ems:client:dispatchResponderPosition', src, call.id, initialPosition, 'Government Doctor')
    for _, target in ipairs(recipients('ems.receive_dispatch')) do
        TriggerClientEvent('cm-ems:client:dispatchResponderPosition', target, call.id, initialPosition, 'Government Doctor')
    end
    dispatchNotify(src, 'Government ambulance has departed and is responding now.', 'success')
    TriggerClientEvent('cm-ems:client:startGovernmentDoctor', src, publicCall(call), options,
        NetworkGetNetworkIdFromEntity(vehicle), NetworkGetNetworkIdFromEntity(doctor),
        { x = stopX, y = stopY, z = stopZ })
end)

-- The owning client hands final cleanup off here once the doctor has boarded
-- and started driving away. Every player in the routing bucket then reports
-- real camera visibility; deletion happens only after nobody can see either
-- entity for the configured grace period.
RegisterNetEvent('cm-ems:server:governmentDoctorDeparted', function(vehicleNetId, doctorNetId)
    local src = source
    vehicleNetId = tonumber(vehicleNetId)
    if not vehicleNetId or not NetworkDoesNetworkIdExist(vehicleNetId) then return end
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    local managed = vehicle and vehicle ~= 0 and ManagedGovernmentEntities[vehicle]
    if not managed or managed.host ~= src then return end
    ManagedGovernmentEntities[vehicle] = nil
    local doctor = managed.doctor
    local responseId = tonumber(managed.responseId)
    local response = responseId and GovernmentResponses[responseId]
    if response then response.closing = true; setResponseState(response, 'cleanup') end
    local bucket = GetEntityRoutingBucket(vehicle)
    local cleanupState = {
        vehicle = vehicle,
        doctor = doctor,
        bucket = bucket,
        lastVisibleAt = GetGameTimer(),
    }
    GovernmentCleanup[vehicleNetId] = cleanupState
    for _, linkedCall in pairs(DispatchCalls) do
        if linkedCall.governmentVehicle == vehicle then linkedCall.governmentClosing = true end
    end

    for _, rawSrc in ipairs(GetPlayers()) do
        local target = tonumber(rawSrc)
        if target and GetPlayerRoutingBucket(target) == bucket then
            TriggerClientEvent('cm-ems:client:observeGovernmentDoctorCleanup', target, vehicleNetId, tonumber(doctorNetId) or 0)
        end
    end

    CreateThread(function()
        local options = Config.Dispatch.governmentDoctor or {}
        local hiddenForMs = tonumber(options.cleanupHiddenForMs) or 2500
        while DoesEntityExist(vehicle) do
            if GetGameTimer() - cleanupState.lastVisibleAt >= hiddenForMs then break end
            Wait(500)
        end
        GovernmentCleanup[vehicleNetId] = nil
        if doctor and DoesEntityExist(doctor) then DeleteEntity(doctor) end
        if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
        if responseId then GovernmentResponses[responseId] = nil end
        for _, rawSrc in ipairs(GetPlayers()) do
            TriggerClientEvent('cm-ems:client:stopGovernmentDoctorCleanupObserver', tonumber(rawSrc), vehicleNetId)
        end
    end)
end)

RegisterNetEvent('cm-ems:server:governmentDoctorStillVisible', function(vehicleNetId)
    local src = source
    vehicleNetId = tonumber(vehicleNetId)
    local state = vehicleNetId and GovernmentCleanup[vehicleNetId]
    if not state or GetPlayerRoutingBucket(src) ~= state.bucket then return end
    local playerPed = GetPlayerPed(src)
    if not playerPed or playerPed == 0 or not DoesEntityExist(state.vehicle) then return end
    if #(GetEntityCoords(playerPed) - GetEntityCoords(state.vehicle)) > 500.0 then return end
    state.lastVisibleAt = GetGameTimer()
end)

RegisterNetEvent('cm-ems:server:governmentDoctorClosing', function(responseId)
    local src = source
    responseId = tonumber(responseId)
    if not responseId then return end
    local response = GovernmentResponses[responseId]
    local authorized = response and response.host == src
    for _, call in pairs(DispatchCalls) do
        if tonumber(call.governmentResponseId or call.id) == responseId and call.governmentHost == src then
            authorized = true
            break
        end
    end
    if not authorized then return end
    if response then response.closing = true; setResponseState(response, 'departing') end
    for _, call in pairs(DispatchCalls) do
        if tonumber(call.governmentResponseId or call.id) == responseId then call.governmentClosing = true end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local retryCalls = {}
    for vehicle, managed in pairs(ManagedGovernmentEntities) do
        if managed.host == src then
            ManagedGovernmentEntities[vehicle] = nil
            if managed.responseId then GovernmentResponses[managed.responseId] = nil end
            if managed.doctor and DoesEntityExist(managed.doctor) then DeleteEntity(managed.doctor) end
            if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
        end
    end
    for responseId, response in pairs(GovernmentResponses) do
        if response.host == src then
            GovernmentResponses[responseId] = nil
            for _, call in pairs(DispatchCalls) do
                if tonumber(call.governmentResponseId or call.id) == tonumber(responseId) then
                    retryCalls[#retryCalls + 1] = call
                    pcall(function()
                        exports[Config.PlayerDataResource]:ReleaseDeathTimerProtection(
                            tonumber(call.callerSource), 'government:' .. tostring(responseId), 'EMS REASSIGNING')
                    end)
                    call.responderType, call.acceptedByName, call.governmentHost = nil, nil, nil
                    call.governmentDoctor, call.governmentVehicle = nil, nil
                    call.governmentResponseId, call.governmentPosition = nil, nil
                end
            end
        end
    end
    for _, call in ipairs(retryCalls) do
        log(call.callerCharacterId, 'government_doctor_host_lost', { callId = call.id })
        SetTimeout(2000, function()
            if DispatchCalls[call.id] == call and not call.responderType and not call.acceptedByCharacterId then
                assignGovernmentDoctor(call, nil, call.governmentAutomatic == true)
            end
        end)
    end
    for callId, call in pairs(DispatchCalls) do
        if tonumber(call.callerSource) == tonumber(src) then
            DispatchCalls[callId] = nil
            if DispatchByCaller[call.callerCharacterId] == callId then DispatchByCaller[call.callerCharacterId] = nil end
            call.backupRequested = false
            local panic = tostring(call.emergencyType) == 'ems_panic'
            call.responseStatus = panic and 'panic_owner_disconnected' or 'caller_disconnected'
            call.resolutionReason = call.responseStatus
            persistIncident(call, true)
            incidentEvent(call.id, panic and 'priority_cleared' or 'abandoned', call.callerCharacterId, { reason = 'disconnect' })
            broadcast('removed', call.id, call)
        end
    end
end)

broadcast = function(action, callId, snapshot)
    local call = snapshot or (callId and DispatchCalls[tonumber(callId)] or nil)
    local payload = call and publicCall(call) or { id = tonumber(callId) }
    local sent = {}
    for _, targetSrc in ipairs(recipients('ems.receive_dispatch')) do
        TriggerClientEvent('cm-ems:client:dispatchUpdated', targetSrc, action, payload)
        sent[targetSrc] = true
    end
    -- The caller isn't necessarily an EMS member, but their own client is
    -- tracking a responder blip (see dispatchResponderPosition) that only
    -- this event clears. Without this, a resolved/cancelled call leaves that
    -- blip stuck on their map indefinitely.
    local callerSrc = call and tonumber(call.callerSource)
    if callerSrc and not sent[callerSrc] and GetPlayerName(callerSrc) then
        TriggerClientEvent('cm-ems:client:dispatchUpdated', callerSrc, action, {
            id = call.id,
            coords = call.coords,
            responseStatus = call.responseStatus,
            resolutionReason = call.resolutionReason,
        })
    end
end

local function listCalls(viewerSrc)
    local now, rows = os.time(), {}
    local viewerPosition
    local viewerPed = viewerSrc and GetPlayerPed(tonumber(viewerSrc)) or 0
    if viewerPed and viewerPed ~= 0 and DoesEntityExist(viewerPed) then viewerPosition = GetEntityCoords(viewerPed) end
    local viewerCid = viewerSrc and cid(tonumber(viewerSrc)) or nil
    for id, call in pairs(DispatchCalls) do
        if now >= call.expiresAt then
            DispatchCalls[id] = nil
            if DispatchByCaller[call.callerCharacterId] == id then DispatchByCaller[call.callerCharacterId] = nil end
            call.resolutionReason, call.responseStatus = 'expired', 'expired'
            persistIncident(call, true)
        elseif not (call.declinedBy and viewerCid and call.declinedBy[tostring(viewerCid)]) then
            local row = publicCall(call)
            if viewerPosition then
                row.distance = math.floor(callDistance(call, { coords = viewerPosition }) + 0.5)
            end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if (a.priority or 2) ~= (b.priority or 2) then return (a.priority or 2) < (b.priority or 2) end
        return a.createdAt < b.createdAt
    end)
    return rows
end

local function createAmbulanceCall(src, details, trustedRequest)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false, 'Caller is not online.' end
    local request = type(details) == 'table' and details or {}
    if request.internalPanic ~= true and not rateLimit(src, 'ambulance_dispatch', tonumber(Config.Dispatch.callCooldownMs) or 60000) then
        return false, 'Please wait before requesting another ambulance.'
    end
    if type(details) == 'table' then details = request.details end
    local characterId = cid(src)
    if not characterId then return false, 'Your character is not loaded.' end
    local existingId = DispatchByCaller[tostring(characterId)]
    if existingId and DispatchCalls[existingId] then
        return true, ('Ambulance request #%d is already active.'):format(existingId), existingId
    end

    local coords
    if type(trustedRequest) == 'table' and tostring(trustedRequest.characterId or '') == tostring(characterId)
        and type(trustedRequest.coords) == 'table' then
        local x, y, z = tonumber(trustedRequest.coords.x), tonumber(trustedRequest.coords.y), tonumber(trustedRequest.coords.z)
        if x and y and z then coords = vector3(x, y, z) end
    end
    if not coords then
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return false, 'Your location is not available.' end
        coords = GetEntityCoords(ped)
    end
    if not coords or (math.abs(coords.x) < 0.01 and math.abs(coords.y) < 0.01) then return false, 'Your location is not ready.' end

    dispatchSequence = dispatchSequence + 1
    local emergencyType = tostring(request.emergencyType or (trustedRequest and trustedRequest.metadata and trustedRequest.metadata.emergencyType) or 'medical')
        :lower():gsub('[^%w_%- ]', ''):sub(1, 48)
    if emergencyType == '' then emergencyType = 'medical' end
    local priority = math.max(1, math.min(math.floor(tonumber(request.priority) or 2), 4))
    local patientCount = math.max(1, math.min(math.floor(tonumber(request.patientCount) or 1), 20))
    local postal = tostring(request.postal or (trustedRequest and trustedRequest.metadata and trustedRequest.metadata.postal) or 'N/A')
        :gsub('[%c]', ''):sub(1, 24)
    local callerName = request.anonymous == true and 'Unknown caller' or nameFor(characterId)
    local incidentNumber = ('EMS-%s-%04d'):format(os.date('%Y%m%d%H%M%S'), dispatchSequence % 10000)
    local encodedCoords = json.encode({ x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 })
    local callId = MySQL.insert.await([[INSERT INTO cm_ems_incidents
        (incident_number, caller_cid, caller_name, emergency_type, priority, patient_count, coords, postal, details, status, responders)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'waiting', ?)]], {
        incidentNumber, tostring(characterId), callerName, emergencyType, priority, patientCount,
        encodedCoords, postal, cleanDetails(details), json.encode({}),
    })
    callId = tonumber(callId)
    if not callId then return false, 'The incident could not be recorded.' end
    local lifetime = tonumber(Config.Dispatch.callLifetimeMs) or 600000
    local call = {
        id = callId, code = 'AMB-01', title = 'Ambulance requested',
        status = 'Critical health condition', details = cleanDetails(details),
        callerSource = src, callerCharacterId = tostring(characterId), callerName = callerName,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        bucket = GetPlayerRoutingBucket(src), area = 'urban',
        createdAt = os.time(), expiresAt = os.time() + math.floor(lifetime / 1000),
        incidentNumber = incidentNumber, emergencyType = emergencyType, priority = priority,
        patientCount = patientCount, postal = postal,
        location = postal ~= 'N/A' and ('Postal ' .. postal) or ('GPS %.0f, %.0f'):format(coords.x, coords.y),
        responseStatus = 'waiting', responders = {}, declinedBy = {},
    }
    DispatchCalls[callId] = call
    DispatchByCaller[tostring(characterId)] = callId
    incidentEvent(callId, 'created', characterId, { priority = priority, patientCount = patientCount, emergencyType = emergencyType })
    local targets = recipients('ems.receive_dispatch')
    for _, targetSrc in ipairs(targets) do TriggerClientEvent('cm-ems:client:dispatchCall', targetSrc, publicCall(call)) end
    log(characterId, 'ambulance_call_requested', { callId = callId, respondersNotified = #targets, bucket = call.bucket })
    SetTimeout(lifetime, function()
        if DispatchCalls[callId] == call then
            DispatchCalls[callId] = nil
            if DispatchByCaller[call.callerCharacterId] == callId then DispatchByCaller[call.callerCharacterId] = nil end
            call.resolutionReason = 'expired'
            call.responseStatus = 'expired'
            persistIncident(call, true)
            incidentEvent(call.id, 'expired', nil, {})
            if call.governmentHost then TriggerClientEvent('cm-ems:client:stopGovernmentDoctor', call.governmentHost, callId) end
            broadcast('removed', callId, call)
        end
    end)
    local govOptions = Config.Dispatch.governmentDoctor or {}
    if govOptions.enabled ~= false then
        local needsTreatment = false
        pcall(function() needsTreatment = exports[Config.PlayerDataResource]:IsDead(src) == true end)
        if needsTreatment and #targets < minimumGovernmentStaffing() and attachNearbyGovernmentResponse(call, true) then
            return true, ('Ambulance request #%d joined the nearby government doctor response.'):format(callId), callId
        end
    end
    if #targets < minimumGovernmentStaffing() and govOptions.enabled ~= false and emsSetting('autoDispatchEnabled') ~= false then
        local sent = assignGovernmentDoctor(call, nil, true)
        if sent then return true, ('Ambulance request #%d sent to a government doctor.'):format(callId), callId end
    end
    if #targets == 0 then return true, ('Ambulance request #%d was recorded, but no authorized EMS members are on duty.'):format(callId), callId end
    return true, ('Ambulance request #%d sent to %d authorized EMS member%s.'):format(callId, #targets, #targets == 1 and '' or 's'), callId
end

local function incidentHistory(limit)
    limit = math.max(1, math.min(math.floor(tonumber(limit) or 50), 100))
    local rows = MySQL.query.await(([=[SELECT id, incident_number, caller_name, emergency_type, priority,
        patient_count, postal, details, status, responders, resolution, created_at, resolved_at
        FROM cm_ems_incidents ORDER BY id DESC LIMIT %d]=]):format(limit)) or {}
    local byId, ids, placeholders = {}, {}, {}
    for _, row in ipairs(rows) do ids[#ids + 1] = tonumber(row.id); placeholders[#placeholders + 1] = '?' end
    local events = {}
    if #ids > 0 then
        events = MySQL.query.await(([=[SELECT incident_id, actor_cid, actor_name, event_type, detail, created_at
            FROM cm_ems_incident_events WHERE incident_id IN (%s) ORDER BY id ASC]=]):format(table.concat(placeholders, ',')), ids) or {}
    end
    for _, event in ipairs(events) do
        local incidentId = tonumber(event.incident_id)
        byId[incidentId] = byId[incidentId] or {}
        local detail = decode(event.detail)
        local item = { type = tostring(event.event_type), actorCid = event.actor_cid and tostring(event.actor_cid) or nil,
            actorName = tostring(event.actor_name or 'System'), at = tostring(event.created_at or ''), detail = detail }
        byId[incidentId][#byId[incidentId] + 1] = item
    end
    for _, row in ipairs(rows) do
        row.id, row.priority, row.patientCount = tonumber(row.id), tonumber(row.priority), tonumber(row.patient_count)
        row.incidentNumber, row.callerName = row.incident_number, row.caller_name
        row.emergencyType, row.responseStatus = row.emergency_type, row.status
        row.responders = decode(row.responders)
        row.timeline = byId[row.id] or {}
        for _, event in ipairs(row.timeline) do
            if event.type == 'accepted' and not row.acceptedAt then row.acceptedAt = event.at end
            if event.type == 'on_scene' and not row.onSceneAt then row.onSceneAt = event.at end
            if (event.type == 'resolved' or event.type == 'removed' or event.type == 'expired') then row.closedAt = event.at end
        end
        row.createdAt, row.resolvedAt = tostring(row.created_at or ''), row.resolved_at and tostring(row.resolved_at) or nil
        row.incident_number, row.caller_name, row.emergency_type, row.patient_count = nil, nil, nil, nil
        row.status, row.created_at, row.resolved_at = nil, nil, nil
    end
    return rows
end

local function responderFor(call, characterId)
    return call and call.responders and call.responders[tostring(characterId)] or nil
end

lib.callback.register('cm-ems:server:dispatchReject', function(src, callId)
    if not rateLimit(src, 'dispatch_reject', 1000) then return false, 'Please wait.' end
    local _, characterId = dispatchMember(src, 'ems.receive_dispatch')
    local call = DispatchCalls[tonumber(callId)]
    if not characterId or not call then return false, 'Incident is no longer active.' end
    if responderFor(call, characterId) then return false, 'Clear yourself from the incident instead of rejecting it.' end
    call.declinedBy = call.declinedBy or {}
    call.declinedBy[tostring(characterId)] = true
    log(characterId, 'dispatch_rejected', { callId = call.id, incidentNumber = call.incidentNumber })
    incidentEvent(call.id, 'declined', characterId, {})
    return true, 'Incident hidden from your dispatch board.'
end)

lib.callback.register('cm-ems:server:dispatchBackup', function(src, callId)
    if not rateLimit(src, 'dispatch_backup', 3000) then return false, 'Please wait.' end
    local member, characterId = dispatchMember(src, 'ems.request_backup')
    local call = DispatchCalls[tonumber(callId)]
    if not member or not characterId or not call or not responderFor(call, characterId) then return false, 'You are not assigned to that incident.' end
    call.backupRequested, call.priority = true, 1
    call.responseStatus = 'backup_requested'
    persistIncident(call, false)
    log(characterId, 'dispatch_backup_requested', { callId = call.id, incidentNumber = call.incidentNumber })
    for _, target in ipairs(recipients('ems.receive_dispatch')) do
        if target ~= src then
            dispatchNotify(target, ('Priority 1 backup requested for %s. GPS is available on the dispatch board.'):format(call.incidentNumber), 'error')
            TriggerClientEvent('cm-ems:client:dispatchCall', target, publicCall(call))
        end
    end
    broadcast('updated', call.id)
    return true, 'Priority backup request sent.'
end)

lib.callback.register('cm-ems:server:dispatchStatus', function(src, callId, nextStatus)
    if not rateLimit(src, 'dispatch_status', 700) then return false, 'Please wait.' end
    local _, characterId = dispatchMember(src, 'ems.receive_dispatch')
    local call = DispatchCalls[tonumber(callId)]
    local responder = characterId and call and responderFor(call, characterId)
    if not responder then return false, 'You are not assigned to that incident.' end
    local allowed = { en_route = true, on_scene = true, transporting = true, at_hospital = true, clear = true }
    nextStatus = tostring(nextStatus or '')
    if not allowed[nextStatus] then return false, 'Invalid response status.' end
    if nextStatus == 'on_scene' then
        local ped = GetPlayerPed(src)
        if GetPlayerRoutingBucket(src) ~= tonumber(call.bucket or 0) then
            return false, 'You are not in the patient scene instance.'
        end
        if not ped or ped == 0
            or callDistance(call, { coords = GetEntityCoords(ped) }) > (tonumber(Config.Dispatch.onSceneDistance) or 30.0) then
            return false, 'You are too far from the incident scene.'
        end
    end
    if nextStatus == 'clear' then
        incidentEvent(call.id, 'clear', characterId, {})
        call.responders[tostring(characterId)] = nil
        if tostring(call.priorityAcknowledgedByCharacterId or '') == tostring(characterId) then
            call.priorityAcknowledgedByCharacterId, call.priorityAcknowledgedBy = nil, nil
        end
        if tostring(call.acceptedByCharacterId or '') == tostring(characterId) then
            call.acceptedByCharacterId, call.acceptedBySource, call.acceptedByName = nil, nil, nil
            local nextCid, nextResponder = next(call.responders)
            if nextCid then
                call.acceptedByCharacterId, call.acceptedBySource = tostring(nextCid), nextResponder.source
                call.acceptedByName = nextResponder.name
            else
                call.responderType, call.responseStatus = nil, 'waiting'
            end
        end
    else
        responder.status = nextStatus
        if nextStatus == 'on_scene' and not responder.onSceneAt then responder.onSceneAt = os.time() end
        call.responseStatus = nextStatus
        incidentEvent(call.id, nextStatus, characterId, {})
    end
    persistIncident(call, false)
    log(characterId, 'dispatch_status_changed', { callId = call.id, status = nextStatus })
    broadcast('updated', call.id)
    return true, ('Incident status: %s.'):format(nextStatus:gsub('_', ' '))
end)

local function acceptCall(src, callId)
    local _, characterId = dispatchMember(src, 'ems.receive_dispatch')
    if not characterId then return false, 'You must be on duty with dispatch permission.' end
    callId = tonumber(callId)
    local call = callId and DispatchCalls[callId]
    if not call or os.time() >= call.expiresAt then return false, 'That ambulance request has expired.' end
    if call.responderType == 'government_doctor' then return false, 'A government doctor is already responding.' end
    call.responders = call.responders or {}
    if call.responders[characterId] then
        return true, ('You are already responding to incident %s.'):format(call.incidentNumber or ('#' .. callId)), publicCall(call)
    end
    local responderName = nameFor(characterId)
    call.responders[characterId] = {
        source = tonumber(src), name = responderName, status = 'en_route', acceptedAt = os.time(),
    }
    if not call.acceptedByCharacterId then
        call.acceptedByCharacterId = characterId
        call.acceptedBySource = tonumber(src)
        call.acceptedByName = responderName
        call.responderType = 'ems_player'
        call.acceptedAt = os.time()
    end
    call.responseStatus = 'en_route'
    if call.backupRequested and not call.priorityAcknowledgedByCharacterId then
        call.priorityAcknowledgedByCharacterId = tostring(characterId)
        call.priorityAcknowledgedBy = responderName
        incidentEvent(callId, 'priority_acknowledged', characterId, {})
        log(characterId, 'dispatch_priority_acknowledged', {
            callId = callId, incidentNumber = call.incidentNumber,
        })
        for _, responder in pairs(call.responders) do
            if responder.source and tonumber(responder.source) ~= tonumber(src) then
                dispatchNotify(responder.source,
                    ('%s acknowledged priority backup for %s.'):format(
                        responderName, call.incidentNumber or ('#' .. callId)), 'success')
            end
        end
    end
    if EMSAddTaskProgress then EMSAddTaskProgress(characterId, 'dispatch_responses', 1, 'incident:' .. tostring(callId)) end
    incidentEvent(callId, 'accepted', characterId, {})
    log(characterId, 'ambulance_call_accepted', { callId = callId, incidentNumber = call.incidentNumber, callerCid = call.callerCharacterId })
    if call.callerSource and GetPlayerName(call.callerSource) then
        dispatchNotify(call.callerSource, ('%s is responding to incident %s.'):format(responderName, call.incidentNumber or ('#' .. callId)), 'success')
    end
    persistIncident(call, false)
    broadcast('updated', callId)
    return true, ('Responding to incident %s.'):format(call.incidentNumber or ('#' .. callId)), publicCall(call)
end

lib.callback.register('cm-ems:server:dispatchAcknowledgePriority', function(src, callId)
    if not rateLimit(src, 'acknowledge_priority', 1000) then return false, 'Please wait.' end
    local call = DispatchCalls[tonumber(callId)]
    if not call or (call.backupRequested ~= true and tostring(call.emergencyType) ~= 'ems_panic') then
        return false, 'That priority request is no longer active.'
    end
    local ok, message, accepted = acceptCall(src, callId)
    if not ok then return false, message end
    local _, characterId = dispatchMember(src, 'ems.receive_dispatch')
    if not characterId then return false, 'You must be on duty with dispatch permission.' end
    if not call.priorityAcknowledgedByCharacterId then
        call.priorityAcknowledgedByCharacterId = tostring(characterId)
        call.priorityAcknowledgedBy = nameFor(characterId)
        incidentEvent(call.id, 'priority_acknowledged', characterId, {})
    end
    call.responseStatus = 'en_route'
    persistIncident(call, false)
    broadcast('updated', call.id)
    return true, ('Priority request acknowledged. GPS set for %s.'):format(call.incidentNumber or ('#' .. call.id)), publicCall(call)
end)

lib.callback.register('cm-ems:server:dispatchClearPriority', function(src, callId)
    if not rateLimit(src, 'clear_priority', 1000) then return false, 'Please wait.' end
    local member, characterId = dispatchMember(src, 'ems.receive_dispatch')
    local call = DispatchCalls[tonumber(callId)]
    if not member or not characterId or not call
        or (call.backupRequested ~= true and tostring(call.emergencyType) ~= 'ems_panic') then
        return false, 'That priority request is no longer active.'
    end
    local permitted = tostring(call.callerCharacterId or '') == tostring(characterId)
        or responderFor(call, characterId) ~= nil or has(member, 'ems.manage_dispatch')
    if not permitted then return false, 'Only the medic in distress, an assigned responder, or a supervisor can clear this alert.' end
    call.backupRequested = false
    incidentEvent(call.id, 'priority_cleared', characterId, {})
    log(characterId, 'dispatch_priority_cleared', { callId = call.id, incidentNumber = call.incidentNumber })
    if tostring(call.emergencyType) == 'ems_panic' then
        DispatchCalls[call.id] = nil
        if DispatchByCaller[call.callerCharacterId] == call.id then DispatchByCaller[call.callerCharacterId] = nil end
        call.responseStatus, call.resolutionReason = 'priority_cleared', 'priority_cleared'
        persistIncident(call, true)
        broadcast('removed', call.id, call)
    else
        call.priority = 2
        call.priorityAcknowledgedByCharacterId, call.priorityAcknowledgedBy = nil, nil
        local _, responder = next(call.responders or {})
        call.responseStatus = responder and tostring(responder.status or 'en_route') or 'waiting'
        persistIncident(call, false)
        broadcast('updated', call.id)
    end
    return true, 'Priority alert cleared.'
end)

-- Internal server-only helper used by the ambulance loading/admission flow.
-- Transport state is derived from the authoritative patient call and vehicle.
function EMSUpdatePatientTransport(patientSrc, vehicleNetId, nextStatus)
    patientSrc, vehicleNetId = tonumber(patientSrc), tonumber(vehicleNetId)
    local patientCid = patientSrc and cid(patientSrc)
    local callId = patientCid and DispatchByCaller[tostring(patientCid)]
    local call = callId and DispatchCalls[callId]
    local vehicle = vehicleNetId and NetworkGetEntityFromNetworkId(vehicleNetId)
    if not call or call.callerCharacterId ~= tostring(patientCid)
        or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)
        or GetEntityRoutingBucket(vehicle) ~= tonumber(call.bucket or 0) then
        return nil
    end
    nextStatus = nextStatus == 'at_hospital' and 'at_hospital'
        or nextStatus == 'on_scene' and 'on_scene' or 'transporting'
    call.patientInAmbulance = nextStatus == 'transporting'
    call.transportVehiclePlate = tostring(GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    call.responseStatus = nextStatus
    for _, responder in pairs(call.responders or {}) do responder.status = nextStatus end
    incidentEvent(call.id, nextStatus, nil, {
        automaticTransportUpdate = true,
        vehiclePlate = call.transportVehiclePlate,
    })
    persistIncident(call, false)
    broadcast('updated', call.id)
    return call.id
end

-- Called only from cm-ems's server-owned treatment path. If the revived
-- patient has an active dispatch call, attach the treating medic before
-- cm-playerdata's ambulanceResolved lifecycle closes the incident.
function EMSLinkTreatmentToDispatch(medicSrc, patientSrc)
    medicSrc, patientSrc = tonumber(medicSrc), tonumber(patientSrc)
    local medicCid, patientCid = medicSrc and cid(medicSrc), patientSrc and cid(patientSrc)
    local callId = patientCid and DispatchByCaller[tostring(patientCid)]
    local call = callId and DispatchCalls[callId]
    if not medicCid or not call or call.callerCharacterId ~= tostring(patientCid)
        or GetPlayerRoutingBucket(medicSrc) ~= call.bucket then return nil end
    call.responders = call.responders or {}
    local responder = call.responders[tostring(medicCid)]
    if not responder then
        responder = {
            source = medicSrc, name = nameFor(medicCid), status = 'on_scene',
            acceptedAt = os.time(), onSceneAt = os.time(),
        }
        call.responders[tostring(medicCid)] = responder
        if not call.acceptedByCharacterId then
            call.acceptedByCharacterId, call.acceptedBySource = tostring(medicCid), medicSrc
            call.acceptedByName, call.responderType = responder.name, 'ems_player'
        end
        incidentEvent(call.id, 'accepted', medicCid, { automaticTreatmentLink = true })
        if EMSAddTaskProgress then
            EMSAddTaskProgress(medicCid, 'dispatch_responses', 1, 'incident:' .. tostring(call.id))
        end
    end
    responder.status, responder.onSceneAt = 'on_scene', responder.onSceneAt or os.time()
    call.responseStatus = 'on_scene'
    incidentEvent(call.id, 'on_scene', medicCid, { automaticTreatmentLink = true })
    persistIncident(call, false)
    broadcast('updated', call.id)
    return call.id
end

RegisterCommand(tostring(Config.Dispatch.command or 'ambulance'), function(src, args)
    if src <= 0 then return end
    local ok, message = createAmbulanceCall(src, table.concat(args or {}, ' '))
    dispatchNotify(src, message, ok and 'success' or 'error')
end, false)

RegisterCommand('911', function(src, args)
    if src <= 0 then return end
    args = args or {}
    local requested = tostring(table.remove(args, 1) or 'ems'):lower()
    local policeOnly = requested == 'police' or requested == 'pd'
    local both = requested == 'both' or requested == 'all'
    local emsOnly = requested == 'ems' or requested == 'medical' or requested == 'ambulance'
    local details = table.concat(args, ' ')
    local emergencyType = (emsOnly or both) and 'medical' or requested

    local emsOk, emsMessage = true, nil
    if not policeOnly then
        emsOk, emsMessage = createAmbulanceCall(src, {
            emergencyType = emergencyType, priority = emergencyType == 'fire' and 1 or 2,
            patientCount = 1, details = details,
        })
    end

    local policeOk, policeMessage = true, nil
    if policeOnly or both then
        if GetResourceState('cm-police') ~= 'started' then
            policeOk, policeMessage = false, 'Police dispatch is unavailable.'
        else
            local called
            called, policeOk, policeMessage = pcall(function()
                return exports['cm-police']:CreatePoliceCall(src, details ~= '' and details or 'Emergency assistance requested.')
            end)
            if not called then policeOk, policeMessage = false, 'Police dispatch is unavailable.' end
        end
    end

    local ok = emsOk and policeOk
    local message
    if both and ok then message = 'Police and EMS received your emergency call.'
    elseif policeOnly then message = policeMessage
    else message = emsMessage end
    dispatchNotify(src, message or 'Emergency call processed.', ok and 'success' or 'error')
end, false)

local function activatePanic(src)
    local member, characterId = dispatchMember(src, 'ems.use_panic')
    if not member or not characterId then return dispatchNotify(src, 'You must be on duty with panic permission.', 'error') end
    if not rateLimit(src, 'ems_panic', 30000) then return dispatchNotify(src, 'Your panic button is cooling down.', 'error') end
    local ok, message, callId = createAmbulanceCall(src, {
        internalPanic = true, emergencyType = 'ems_panic', priority = 1, patientCount = 1,
        details = ('EMS panic activation by %s. Immediate assistance required.'):format(nameFor(characterId)),
    })
    if ok then
        local call = DispatchCalls[tonumber(callId)]
        if call then
            call.emergencyType, call.priority, call.backupRequested = 'ems_panic', 1, true
            call.panicOwnerName = nameFor(characterId)
            call.details = ('EMS panic activation by %s. Immediate assistance required.'):format(nameFor(characterId))
            call.responseStatus = 'backup_requested'
            persistIncident(call, false)
            incidentEvent(call.id, 'panic', characterId, {})
        end
        for _, target in ipairs(recipients('ems.receive_dispatch')) do
            if target ~= src then
                dispatchNotify(target, ('EMS PANIC: %s needs immediate assistance.'):format(nameFor(characterId)), 'error')
                if call then TriggerClientEvent('cm-ems:client:dispatchCall', target, publicCall(call)) end
            end
        end
        log(characterId, 'ems_panic_activated', {})
    end
    dispatchNotify(src, message, ok and 'success' or 'error')
end

RegisterCommand('emspanic', function(src)
    if src <= 0 then return end
    activatePanic(src)
end, false)

RegisterNetEvent('cm-ems:server:activatePanic', function()
    activatePanic(source)
end)

CreateThread(function()
    while true do
        Wait(2000)
        for callId, call in pairs(DispatchCalls) do
            if tostring(call.emergencyType) == 'ems_panic' then
                local member = call.callerCharacterId and memberFor(call.callerCharacterId)
                local active = call.callerSource and GetPlayerName(call.callerSource)
                    and member and not dbBoolean(member.is_suspended) and dbBoolean(member.on_duty)
                if not active then
                    DispatchCalls[callId] = nil
                    if DispatchByCaller[call.callerCharacterId] == callId then DispatchByCaller[call.callerCharacterId] = nil end
                    call.backupRequested = false
                    call.responseStatus, call.resolutionReason = 'panic_owner_unavailable', 'panic_owner_unavailable'
                    persistIncident(call, true)
                    incidentEvent(call.id, 'priority_cleared', call.callerCharacterId, { reason = 'off_duty_or_unavailable' })
                    broadcast('removed', call.id, call)
                else
                    local ped = GetPlayerPed(call.callerSource)
                    if ped and ped ~= 0 and DoesEntityExist(ped) then
                        local coords = GetEntityCoords(ped)
                        call.coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
                        call.bucket = GetPlayerRoutingBucket(call.callerSource)
                        broadcast('updated', call.id)
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('cm-ems:server:acceptDispatch', function(callId)
    local src = source
    if not rateLimit(src, 'accept_dispatch', 1200) then return end
    local ok, message, call = acceptCall(src, callId)
    dispatchNotify(src, message, ok and 'success' or 'error')
    if ok and call then TriggerClientEvent('cm-ems:client:dispatchAccepted', src, call) end
end)

lib.callback.register('cm-ems:server:dispatchBoard', function(src)
    local member, characterId = dispatchMember(src, 'ems.receive_dispatch')
    if not member then return nil, 'You must be on duty with dispatch permission.' end
    local availableUnits = {}
    if has(member, 'ems.manage_dispatch') then
        local online = {}
        for _, player in ipairs(GetPlayers()) do
            local unitSrc = tonumber(player)
            local unitCid = unitSrc and cid(unitSrc)
            if unitCid then online[tostring(unitCid)] = unitSrc end
        end
        local rows = MySQL.query.await([[
            SELECT m.character_id, m.on_duty, r.is_leader, r.permissions,
                   (m.suspended_until IS NOT NULL AND m.suspended_until > NOW()) AS is_suspended
            FROM cm_ems_members m
            JOIN cm_ems_ranks r ON r.id = m.rank_id
            WHERE m.on_duty = 1
        ]]) or {}
        for _, unit in ipairs(rows) do
            local unitCid = tostring(unit.character_id)
            if online[unitCid] and not dbBoolean(unit.is_suspended) and has(unit, 'ems.receive_dispatch') then
                availableUnits[#availableUnits + 1] = {
                    characterId = tostring(unitCid), name = nameFor(unitCid),
                }
            end
        end
        table.sort(availableUnits, function(a, b) return a.name < b.name end)
    end
    return {
        calls = listCalls(src),
        canManage = has(member, 'ems.manage_dispatch'),
        canSendGovernmentDoctor = has(member, 'ems.send_gov_doctor'),
        canRequestBackup = has(member, 'ems.request_backup'),
        selfCharacterId = characterId,
        availableUnits = availableUnits,
    }
end)

lib.callback.register('cm-ems:server:emsCallHistory', function(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) then return nil, 'You are not an active EMS employee.' end
    return incidentHistory(100)
end)

lib.callback.register('cm-ems:server:sendGovernmentDoctor', function(src, callId)
    local member, characterId = dispatchMember(src, 'ems.send_gov_doctor')
    if not member then return false, 'Your rank cannot send a government doctor.' end
    if not rateLimit(src, 'send_government_doctor', 2000) then return false, 'Please wait.' end
    return assignGovernmentDoctor(DispatchCalls[tonumber(callId)], characterId, false)
end)

RegisterNetEvent('cm-ems:server:governmentDoctorPosition', function(callId, coords)
    local src, call = source, DispatchCalls[tonumber(callId)]
    if not call or call.governmentHost ~= src or call.responderType ~= 'government_doctor' or type(coords) ~= 'table' then return end
    if not rateLimit(src, 'government_doctor_position', 700) then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    local patientPed = GetPlayerPed(src)
    if not patientPed or patientPed == 0 then return end
    local patient = GetEntityCoords(patientPed)
    -- Looser than the ~25m "stand here" convention used for stationary
    -- placements elsewhere: this fires continuously while the doctor is
    -- actively moving/driving between position updates, so it needs to
    -- tolerate real travel between the (rate-limited, every ~700ms) ticks --
    -- it just needs to reject a wildly spoofed coordinate, not pixel-match.
    if math.sqrt((x - patient.x)^2 + (y - patient.y)^2 + (z - patient.z)^2) > 200.0 then return end
    local position = { x = x, y = y, z = z }
    call.governmentPosition, call.governmentPositionAt = position, GetGameTimer()
    local response = GovernmentResponses[tonumber(call.governmentResponseId or call.id)]
    if response then response.position = position end
    for _, linkedCall in pairs(DispatchCalls) do
        if tonumber(linkedCall.governmentResponseId) == tonumber(call.governmentResponseId or call.id) then
            TriggerClientEvent('cm-ems:client:dispatchResponderPosition', linkedCall.callerSource, linkedCall.id, position, 'Government Doctor')
        end
    end
    for _, target in ipairs(recipients('ems.receive_dispatch')) do TriggerClientEvent('cm-ems:client:dispatchResponderPosition', target, call.id, position, 'Government Doctor') end
end)

RegisterNetEvent('cm-ems:server:governmentDoctorArrived', function(responseId)
    local src = source
    local response = GovernmentResponses[tonumber(responseId)]
    if not response or response.host ~= src or response.closing or response.state ~= 'driving' then return end
    if not response.vehicle or not DoesEntityExist(response.vehicle) then return end
    local vehiclePos = GetEntityCoords(response.vehicle)
    local closeToPatient = false
    for callId in pairs(response.patients or {}) do
        local call = DispatchCalls[tonumber(callId)]
        local ped = call and GetPlayerPed(tonumber(call.callerSource)) or 0
        if ped and ped ~= 0 and DoesEntityExist(ped) and #(vehiclePos - GetEntityCoords(ped)) <= 60.0 then
            closeToPatient = true
            break
        end
    end
    if closeToPatient then setResponseState(response, 'parked') end
end)

local function deathInfoFor(src)
    local info
    pcall(function() info = exports[Config.PlayerDataResource]:GetDeathInfo(tonumber(src)) end)
    return type(info) == 'table' and info or nil
end

local function nextResponsePatient(response)
    local now = GetGameTimer()
    local from = response.doctor and DoesEntityExist(response.doctor) and GetEntityCoords(response.doctor) or nil
    local best, bestRemaining, bestDistance, bestCreated
    for callId, patient in pairs(response.patients or {}) do
        local call = DispatchCalls[tonumber(callId)]
        local info = call and deathInfoFor(patient.source) or nil
        if not call or not info or info.isDead ~= true or not GetPlayerName(patient.source) then
            response.patients[callId] = nil
            if tonumber(response.currentCallId) == tonumber(callId) then response.currentCallId = nil end
        elseif (tonumber(patient.retryAfter) or 0) <= now then
            local remaining = tonumber(info.remainingMs) or math.huge
            local ped = GetPlayerPed(patient.source)
            local distance = math.huge
            if from and ped and ped ~= 0 and DoesEntityExist(ped) then distance = #(from - GetEntityCoords(ped)) end
            local created = tonumber(patient.createdAt) or math.huge
            if not best or remaining < bestRemaining
                or (remaining == bestRemaining and distance < bestDistance)
                or (remaining == bestRemaining and distance == bestDistance and created < bestCreated) then
                best, bestRemaining, bestDistance, bestCreated = patient, remaining, distance, created
            end
        end
    end
    return best
end

lib.callback.register('cm-ems:server:governmentDoctorNextPatient', function(src, responseId)
    local response = GovernmentResponses[tonumber(responseId)]
    if not response or response.host ~= src or response.closing then return nil, 'closed' end
    if response.state ~= 'parked' and response.state ~= 'waiting_nearby' and response.state ~= 'treating' then
        return nil, 'not_ready'
    end

    local patient = nextResponsePatient(response)
    if not patient then
        response.currentCallId = nil
        if response.state ~= 'waiting_nearby' then setResponseState(response, 'waiting_nearby') end
        return nil, 'empty'
    end
    response.currentCallId = patient.callId
    response.treatmentStartedAt = GetGameTimer()
    if response.state ~= 'treating' then setResponseState(response, 'treating') end
    return { id = patient.callId, source = patient.source, coords = patient.coords }, 'assigned'
end)

lib.callback.register('cm-ems:server:governmentDoctorTreat', function(src, responseId, callId)
    responseId, callId = tonumber(responseId), tonumber(callId)
    local response, call = GovernmentResponses[responseId], DispatchCalls[callId]
    if not response or response.host ~= src or response.closing or response.state ~= 'treating'
        or tonumber(response.currentCallId) ~= callId or not call
        or tonumber(call.governmentResponseId or call.id) ~= responseId then
        return false, 'assignment_changed'
    end

    local options = Config.Dispatch.governmentDoctor or {}
    local treatmentMs = tonumber(options.treatmentMs) or 10000
    if GetGameTimer() - (response.treatmentStartedAt or GetGameTimer()) < math.max(1000, treatmentMs - 1200) then
        return false, 'treatment_too_fast'
    end
    local patientSrc, vehicle, doctor = tonumber(call.callerSource), response.vehicle, response.doctor
    local info = patientSrc and deathInfoFor(patientSrc) or nil
    local ped = patientSrc and GetPlayerPed(patientSrc) or 0
    local valid = info and info.isDead == true and ped and ped ~= 0 and DoesEntityExist(ped)
        and vehicle and doctor and DoesEntityExist(vehicle) and DoesEntityExist(doctor)
        and GetEntityRoutingBucket(vehicle) == GetPlayerRoutingBucket(patientSrc)
        and GetEntityRoutingBucket(doctor) == GetPlayerRoutingBucket(patientSrc)
    if valid then
        local patientPos = GetEntityCoords(ped)
        valid = #(GetEntityCoords(vehicle) - patientPos) <= 45.0 and #(GetEntityCoords(doctor) - patientPos) <= 2.25
    end

    local ok = false
    if valid then pcall(function() ok = exports[Config.PlayerDataResource]:Heal(patientSrc, 100, 'government_doctor') == true end) end
    if ok then
        response.patients[callId] = nil
        response.currentCallId = nil
        setResponseState(response, 'parked')
        log(call.callerCharacterId, 'government_doctor_treated', { callId = call.id, responseId = responseId, fullHealth = true })
        TriggerEvent('cm-ems:server:recordMedicalEvent', patientSrc, {
            event = 'government_doctor_treatment', incidentId = call.id,
            treatment = 'Government doctor CPR and full stabilization', outcome = 'revived_on_scene',
        })
        return true, 'treated'
    end

    local patient = response.patients[callId]
    if patient then
        patient.attempts = (patient.attempts or 0) + 1
        patient.retryAfter = GetGameTimer() + (tonumber(options.treatmentRetryDelayMs) or 4000)
    end
    response.currentCallId = nil
    setResponseState(response, 'parked')
    if patientSrc and GetPlayerName(patientSrc) then
        dispatchNotify(patientSrc, 'Government treatment was not confirmed. The doctor is retrying.', 'error')
    end
    return false, valid and 'heal_rejected' or 'position_invalid'
end)

RegisterNetEvent('cm-ems:server:governmentDoctorFailed', function(callId, reason)
    local src, call = source, DispatchCalls[tonumber(callId)]
    if not call or call.governmentHost ~= src or call.responderType ~= 'government_doctor' then return end
    -- Entities are left alone here: the client plays a wait-then-return-to-
    -- vehicle sequence before cleaning them up itself. Deleting them out from
    -- under that sequence would make the doctor vanish mid-retreat.
    local wasAutomatic = call.governmentAutomatic == true
    local responseId = tonumber(call.governmentResponseId or call.id)
    GovernmentResponses[responseId] = nil
    for _, linkedCall in pairs(DispatchCalls) do
        if tonumber(linkedCall.governmentResponseId or linkedCall.id) == responseId then
            pcall(function()
                exports[Config.PlayerDataResource]:ReleaseDeathTimerProtection(
                    tonumber(linkedCall.callerSource), 'government:' .. tostring(responseId), 'EMS RETRYING')
            end)
            linkedCall.responderType, linkedCall.acceptedByName, linkedCall.governmentHost = nil, nil, nil
            linkedCall.governmentAutomatic = nil
            linkedCall.governmentDoctor, linkedCall.governmentVehicle = nil, nil
            linkedCall.governmentStartedAt, linkedCall.governmentPosition, linkedCall.governmentPositionAt = nil, nil, nil
            linkedCall.governmentResponseId, linkedCall.governmentClosing = nil, nil
        end
    end
    call.governmentAttempts = (call.governmentAttempts or 0) + 1
    log(call.callerCharacterId, 'government_doctor_failed', { callId = call.id, reason = cleanDetails(reason), attempt = call.governmentAttempts })

    local options = Config.Dispatch.governmentDoctor or {}
    local maxAttempts = tonumber(options.maxAttempts) or 4
    local retryDelayMs = tonumber(options.retryDelayMs) or 7000
    if options.enabled ~= false and call.governmentAttempts < maxAttempts then
        dispatchNotify(src, 'The government doctor could not safely reach you and is trying a different route.', 'error')
        SetTimeout(retryDelayMs, function()
            -- Re-check everything: the call may have expired, been resolved,
            -- or already picked up by a live medic during the delay.
            if DispatchCalls[call.id] == call and not call.responderType and not call.acceptedByCharacterId then
                -- Automatic AI remains automatic only while no real,
                -- dispatch-qualified EMS member is on duty. A government
                -- doctor explicitly sent by EMS may retry regardless.
                if not wasAutomatic or #recipients('ems.receive_dispatch') == 0 then
                    assignGovernmentDoctor(call, nil, wasAutomatic)
                else
                    dispatchNotify(src, 'A live EMS medic is now on duty. The call remains available for them.', 'inform')
                    broadcast('updated', call.id)
                end
            end
        end)
    else
        dispatchNotify(src, 'The government doctor could not safely reach you. Your EMS call remains active for a live medic.', 'error')
    end
    broadcast('updated', call.id)
end)

lib.callback.register('cm-ems:server:takeDispatch', function(src, callId)
    if not rateLimit(src, 'take_dispatch', 1200) then return false, 'Please wait.' end
    return acceptCall(src, callId)
end)

lib.callback.register('cm-ems:server:addDispatchNote', function(src, callId, value)
    local member, characterId = dispatchMember(src, 'ems.receive_dispatch')
    local call = DispatchCalls[tonumber(callId)]
    if not member or not characterId or not call then return false, 'That incident is no longer active.' end
    if not responderFor(call, characterId) and not has(member, 'ems.manage_dispatch') then
        return false, 'Only assigned responders or dispatch supervisors can add notes.'
    end
    if not rateLimit(src, 'dispatch_note', 1500) then return false, 'Please wait before adding another note.' end
    local note = cleanNote(value)
    if not note then return false, 'Enter a short incident note.' end
    call.notes = call.notes or {}
    if #call.notes >= 8 then table.remove(call.notes, 1) end
    local row = { text = note, author = nameFor(characterId), at = os.time() }
    call.notes[#call.notes + 1] = row
    incidentEvent(call.id, 'note', characterId, { text = note })
    log(characterId, 'dispatch_note_added', { callId = call.id, incidentNumber = call.incidentNumber })
    broadcast('updated', call.id)
    return true, 'Incident note added.'
end)

lib.callback.register('cm-ems:server:assignDispatchUnit', function(src, callId, targetCharacterId, replace)
    local member, supervisorCid = dispatchMember(src, 'ems.manage_dispatch')
    local call = DispatchCalls[tonumber(callId)]
    targetCharacterId = tostring(targetCharacterId or '')
    if not member or not supervisorCid then return false, 'Your rank cannot assign dispatch units.' end
    if not call then return false, 'That incident is no longer active.' end
    if call.responderType == 'government_doctor' then return false, 'Clear the government response before assigning a live unit.' end
    if not rateLimit(src, 'assign_dispatch_unit', 1200) then return false, 'Please wait.' end

    local targetSrc
    for _, player in ipairs(GetPlayers()) do
        local candidate = tonumber(player)
        local _, candidateCid = dispatchMember(candidate, 'ems.receive_dispatch')
        if candidateCid and tostring(candidateCid) == targetCharacterId then targetSrc = candidate; break end
    end
    if not targetSrc then return false, 'That EMS unit is not online and available for dispatch.' end

    call.responders = call.responders or {}
    if replace == true then
        for existingCid, responder in pairs(call.responders) do
            if tostring(existingCid) ~= targetCharacterId and responder.source then
                TriggerClientEvent('cm-ems:client:dispatchAssignmentRemoved', responder.source, call.id,
                    ('A supervisor reassigned %s.'):format(call.incidentNumber or ('#' .. call.id)))
            end
        end
        call.responders = {}
        call.acceptedByCharacterId, call.acceptedBySource, call.acceptedByName = nil, nil, nil
    end

    local responderName = nameFor(targetCharacterId)
    if not call.responders[targetCharacterId] then
        call.responders[targetCharacterId] = {
            source = targetSrc, name = responderName, status = 'en_route', acceptedAt = os.time(),
        }
        incidentEvent(call.id, 'accepted', targetCharacterId, {
            assignedBy = supervisorCid, supervisorAssignment = true, replaced = replace == true,
        })
        if EMSAddTaskProgress then
            EMSAddTaskProgress(targetCharacterId, 'dispatch_responses', 1, 'incident:' .. tostring(call.id))
        end
    end
    call.acceptedByCharacterId, call.acceptedBySource = targetCharacterId, targetSrc
    call.acceptedByName, call.responderType = responderName, 'ems_player'
    call.acceptedAt = call.acceptedAt or os.time()
    call.responseStatus = 'en_route'
    persistIncident(call, false)
    log(supervisorCid, replace == true and 'dispatch_unit_reassigned' or 'dispatch_unit_assigned', {
        callId = call.id, targetCid = targetCharacterId, incidentNumber = call.incidentNumber,
    })
    broadcast('updated', call.id)
    local payload = publicCall(call)
    TriggerClientEvent('cm-ems:client:dispatchAccepted', targetSrc, payload)
    dispatchNotify(targetSrc, ('Dispatch assigned you to %s. GPS route is active.'):format(
        call.incidentNumber or ('#' .. call.id)), 'success')
    return true, replace == true and 'Incident reassigned.' or 'EMS unit assigned.'
end)

lib.callback.register('cm-ems:server:removeDispatch', function(src, callId)
    if not rateLimit(src, 'remove_dispatch', 1200) then return false, 'Please wait.' end
    local member, characterId = dispatchMember(src, 'ems.manage_dispatch')
    if not member then return false, 'Your rank cannot remove dispatch calls.' end
    callId = tonumber(callId)
    local call = callId and DispatchCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    DispatchCalls[callId] = nil
    if DispatchByCaller[call.callerCharacterId] == callId then DispatchByCaller[call.callerCharacterId] = nil end
    call.resolutionReason = 'removed'
    call.responseStatus = 'removed'
    persistIncident(call, true)
    incidentEvent(call.id, 'removed', characterId, {})
    if call.governmentHost then TriggerClientEvent('cm-ems:client:stopGovernmentDoctor', call.governmentHost, callId) end
    log(characterId, 'ambulance_call_removed', { callId = callId })
    broadcast('removed', callId, call)
    return true, ('Ambulance request #%d removed.'):format(callId)
end)

exports('CreateAmbulanceCall', createAmbulanceCall)

-- Local-only bridge from cm-playerdata's validated death lifecycle.
AddEventHandler('cm-playerdata:server:ambulanceRequested', function(src, payload)
    payload = type(payload) == 'table' and payload or {}
    local details = payload.metadata and payload.metadata.details or 'Unconscious patient requested an ambulance.'
    local ok, message = createAmbulanceCall(tonumber(src), details, payload)
    if not ok then dispatchNotify(src, ('EMS dispatch could not be created: %s'):format(message), 'error') end
end)

AddEventHandler('cm-playerdata:server:ambulanceResolved', function(src, payload)
    src = tonumber(src)
    payload = type(payload) == 'table' and payload or {}
    local characterId = tostring(payload.characterId or '')
    if not src or characterId == '' or tostring(cid(src) or '') ~= characterId then return end
    local callId = DispatchByCaller[characterId]
    local call = callId and DispatchCalls[callId]
    -- Character ID is authoritative; the session source may change after a reconnect.
    if not call or call.callerCharacterId ~= characterId then return end

    removeResponsePatient(call)
    DispatchCalls[callId] = nil
    DispatchByCaller[characterId] = nil
    call.resolutionReason = tostring(payload.reason or 'resolved')
    call.responseStatus = call.resolutionReason == 'hospital_respawn' and 'patient_deceased' or 'patient_treated'
    persistIncident(call, true)
    incidentEvent(call.id, 'resolved', nil, { reason = call.resolutionReason, outcome = call.responseStatus })
    if call.governmentHost then TriggerClientEvent('cm-ems:client:stopGovernmentDoctor', call.governmentHost, callId) end
    local responseMessage = call.resolutionReason == 'hospital_respawn'
        and 'The patient has died and respawned. Dispatch and GPS were removed.'
        or 'The patient was revived and no longer needs dispatch. GPS was removed.'
    for _, responder in pairs(call.responders or {}) do
        if responder.source and GetPlayerName(responder.source) then
            TriggerClientEvent('cm-ems:client:dispatchPatientResolved', responder.source, callId, responseMessage)
        end
    end
    log(characterId, 'ambulance_call_resolved', { callId = callId, reason = call.resolutionReason })
    broadcast('removed', callId, call)
end)

AddEventHandler('cm-ems:server:memberWentOffDuty', function(src, characterId, reason)
    src = tonumber(src)
    characterId = tostring(characterId or '')
    if characterId == '' then return end
    for _, call in pairs(DispatchCalls) do
        local responder = call.responders and call.responders[characterId]
        if responder then
            call.responders[characterId] = nil
            if tostring(call.priorityAcknowledgedByCharacterId or '') == characterId then
                call.priorityAcknowledgedByCharacterId, call.priorityAcknowledgedBy = nil, nil
            end
            if tostring(call.acceptedByCharacterId or '') == characterId then
                call.acceptedByCharacterId, call.acceptedBySource, call.acceptedByName = nil, nil, nil
                local nextCid, nextResponder = next(call.responders)
                if nextCid then
                    call.acceptedByCharacterId, call.acceptedBySource = tostring(nextCid), nextResponder.source
                    call.acceptedByName, call.responseStatus = nextResponder.name, nextResponder.status or 'en_route'
                else
                    call.responderType, call.responseStatus = nil, 'waiting'
                end
            end
            persistIncident(call, false)
            incidentEvent(call.id, 'unit_removed', characterId, { reason = tostring(reason or 'off_duty') })
            broadcast('updated', call.id)
            if src and GetPlayerName(src) then
                TriggerClientEvent('cm-ems:client:dispatchAssignmentRemoved', src, call.id,
                    'You left EMS duty. Dispatch assignment and GPS were cleared.')
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1500)
        for _, call in pairs(DispatchCalls) do
            if call.responderType ~= 'government_doctor' then
                for _, responder in pairs(call.responders or {}) do
                    if responder.source and GetPlayerName(responder.source) then
                        local ped = GetPlayerPed(responder.source)
                        if ped and ped ~= 0 and DoesEntityExist(ped) then
                            local c = GetEntityCoords(ped)
                            local position = { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 }
                            TriggerClientEvent('cm-ems:client:dispatchResponderPosition', call.callerSource, call.id, position, responder.name or 'EMS')
                            for _, target in ipairs(recipients('ems.receive_dispatch')) do
                                TriggerClientEvent('cm-ems:client:dispatchResponderPosition', target, call.id, position, responder.name or 'EMS')
                            end
                        end
                    end
                end
            end
        end
    end
end)
