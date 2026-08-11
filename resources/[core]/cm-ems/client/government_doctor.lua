local mission
local pendingCallId
local responderBlips = {}
local pendingStops = {}
local pendingSpawns = {}
local pendingPatients = {}
local cleanupObservers = {}

-- cm-playerdata replicates isDead on the player's own statebag (see ApplyState
-- server-side). Reading it locally is the one signal that stays correct no
-- matter how the player stopped needing treatment (bled out, gave up, was
-- revived by someone/something else) — the mission must never keep chasing
-- once this flips false.
local function patientStillDown(patient)
    local serverId = patient and tonumber(patient.source) or GetPlayerServerId(PlayerId())
    if serverId == GetPlayerServerId(PlayerId()) then
        return LocalPlayer and LocalPlayer.state and LocalPlayer.state.isDead ~= false
    end
    -- Nearby patients were placed in this queue by the authoritative server
    -- after validating their active dispatch. Do not trust another player's
    -- client statebag here: depending on statebag scope it can temporarily say
    -- false even while that player is still down. The server removes resolved
    -- calls and revalidates IsDead again before applying treatment.
    return true
end

local function patientPed(patient)
    local serverId = patient and tonumber(patient.source) or GetPlayerServerId(PlayerId())
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    return ped and ped ~= 0 and DoesEntityExist(ped) and ped or nil
end

local function hasDownPatients(current)
    if not current or type(current.patients) ~= 'table' then return false end
    for _, patient in pairs(current.patients) do
        if patientStillDown(patient) then return true end
    end
    return false
end

local function nearestDownPatient(current, from)
    local best, bestDistance
    for _, patient in pairs(current.patients or {}) do
        if patientStillDown(patient) then
            local ped = patientPed(patient)
            if ped then
                local distance = #(GetEntityCoords(ped) - from)
                if not bestDistance or distance < bestDistance then
                    best, bestDistance = patient, distance
                end
            end
        end
    end
    return best
end

local function loadModel(name)
    local hash = joaat(tostring(name))
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
    return HasModelLoaded(hash) and hash or nil
end

local function cleanup(current)
    if not current then return end
    if current.doctor and DoesEntityExist(current.doctor) then DeleteEntity(current.doctor) end
    if current.vehicle and DoesEntityExist(current.vehicle) then DeleteEntity(current.vehicle) end
    if mission == current then mission = nil end
end

-- Hands final cleanup off to the server instead of deleting locally. Only
-- the server can see every connected player's real position regardless of
-- this client's own streaming range, so only the server can correctly judge
-- "nobody is near this anymore" -- a bystander who wandered off from the
-- caller but stayed by the ambulance would otherwise be invisible to a
-- client-only "am I still watching it" check.
local function handoffCleanup(current)
    if not current then return end
    if mission == current then mission = nil end
    if not current.vehicle or not DoesEntityExist(current.vehicle) then return end
    local vehicleNetId = NetworkGetNetworkIdFromEntity(current.vehicle)
    local doctorNetId = (current.doctor and DoesEntityExist(current.doctor)) and NetworkGetNetworkIdFromEntity(current.doctor) or nil
    TriggerServerEvent('cm-ems:server:governmentDoctorDeparted', vehicleNetId, doctorNetId)
end

local function reportFailure(callId, reason)
    pendingStops[tonumber(callId)] = nil
    TriggerServerEvent('cm-ems:server:governmentDoctorFailed', tonumber(callId), tostring(reason or 'response_failed'))
end

local function roadNodeAround(patient, distances, minimum, maximum, clearRadius, angleStep)
    angleStep = angleStep or 45
    for _, distance in ipairs(distances) do
        for angle = 0, 360 - angleStep, angleStep do
            local radians = math.rad(angle)
            local x, y = patient.x + math.cos(radians) * distance, patient.y + math.sin(radians) * distance
            local found, position, heading = GetClosestVehicleNodeWithHeading(x, y, patient.z, 1, 3.0, 0)
            if found and position then
                local nodeDistance = #(position - patient)
                local clear = not clearRadius or not IsAnyVehicleNearPoint(position.x, position.y, position.z, clearRadius)
                if nodeDistance >= minimum and nodeDistance <= maximum
                    and math.abs(position.z - patient.z) < 180.0 and clear then
                    return position, heading
                end
            end
        end
    end
    return nil, nil
end

-- A road node is only a candidate; GTA can return one occupied by traffic or
-- with collision not streamed yet. Validate the actual spawn volume before
-- asking the server to create a networked ambulance there.
local function spawnVolumeClear(position, radius)
    radius = tonumber(radius) or 8.0
    if IsAnyVehicleNearPoint(position.x, position.y, position.z, radius) then return false end
    if IsAnyPedNearPoint and IsAnyPedNearPoint(position.x, position.y, position.z, radius) then return false end
    return true
end

local function loadAndGroundSpawn(position, options)
    RequestCollisionAtCoord(position.x, position.y, position.z)
    if RequestAdditionalCollisionAtCoord then
        RequestAdditionalCollisionAtCoord(position.x, position.y, position.z)
    end

    local deadline = GetGameTimer() + (tonumber(options.spawnCollisionTimeoutMs) or 3000)
    local groundFound, groundZ = false, nil
    repeat
        groundFound, groundZ = GetGroundZFor_3dCoord(position.x, position.y, position.z + 60.0, false)
        if groundFound then break end
        Wait(50)
        RequestCollisionAtCoord(position.x, position.y, position.z)
    until GetGameTimer() >= deadline

    if not groundFound or not groundZ or math.abs(groundZ - position.z) > 12.0 then return nil end
    local grounded = vector3(position.x, position.y, groundZ + 0.25)
    if not spawnVolumeClear(grounded, tonumber(options.spawnClearRadius) or 8.0) then return nil end
    return grounded
end

-- Finds a vehicle node to spawn the ambulance at, within [minimum, maximum]
-- of the patient and with a sane drive route to `destination`. `relaxed`
-- widens every tolerance and uses finer angle steps, used as a fallback pass
-- so a sparse road network near the patient doesn't strand the call outright.
local function findResponseSpawn(patient, destination, options, relaxed)
    local minimum = tonumber(options.spawnMinDistance) or 55.0
    local maximum = tonumber(options.spawnMaxDistance) or 100.0
    local targetRoute = tonumber(options.targetRouteDistance) or 90.0
    local minimumRoute = tonumber(options.minimumRouteDistance) or 35.0
    local maximumRoute = tonumber(options.maximumRouteDistance) or 180.0
    local maximumFactor = tonumber(options.maximumRouteFactor) or 2.5
    local clearRadius, angleStep = 7.0, 45
    if relaxed then
        minimum, maximum = minimum * 0.6, maximum * 1.4
        minimumRoute, maximumRoute = minimumRoute * 0.5, maximumRoute * 1.6
        maximumFactor = maximumFactor * 1.5
        clearRadius, angleStep = 4.0, 22.5
    end
    local middle = (minimum + maximum) * .5
    local bestPosition, bestHeading, bestScore
    for _, distance in ipairs({ middle, minimum, maximum }) do
        for angle = 0, 360 - angleStep, angleStep do
            local radians = math.rad(angle)
            local x, y = patient.x + math.cos(radians) * distance, patient.y + math.sin(radians) * distance
            local found, position, heading = GetClosestVehicleNodeWithHeading(x, y, patient.z, 1, 3.0, 0)
            if found and position and spawnVolumeClear(position, clearRadius) then
                local straight = #(position - destination)
                local patientDistance = #(position - patient)
                local ok, route = pcall(CalculateTravelDistanceBetweenPoints,
                    position.x, position.y, position.z, destination.x, destination.y, destination.z)
                route = ok and tonumber(route) or nil
                if patientDistance >= minimum and patientDistance <= maximum
                    and math.abs(position.z - patient.z) < 180.0
                    and route and route >= minimumRoute and route <= maximumRoute and route <= straight * maximumFactor then
                    -- Prefer a road just outside the camera view. This makes
                    -- the nearby, fully simulated spawn look like an ambient
                    -- GTA emergency response rather than appearing in front
                    -- of the patient.
                    local visiblePenalty = IsSphereVisible(position.x, position.y, position.z, 4.0) and 1000.0 or 0.0
                    local score = math.abs(route - targetRoute) + visiblePenalty
                    if not bestScore or score < bestScore then
                        local desired = GetHeadingFromVector_2d(destination.x - position.x, destination.y - position.y)
                        local difference = math.abs(((heading - desired + 180.0) % 360.0) - 180.0)
                        if difference > 90.0 then heading = (heading + 180.0) % 360.0 end
                        bestPosition, bestHeading, bestScore = position, heading, score
                    end
                end
            end
        end
    end
    return bestPosition, bestHeading
end

local function responseSpawn(patient, destination, options)
    local position, heading = findResponseSpawn(patient, destination, options, false)
    if position then
        local grounded = loadAndGroundSpawn(position, options)
        if grounded then return grounded, heading end
    end
    position, heading = findResponseSpawn(patient, destination, options, true)
    if not position then return nil, nil end
    local grounded = loadAndGroundSpawn(position, options)
    return grounded, grounded and heading or nil
end

local function sceneStop(patient, options)
    local minimum = tonumber(options.sceneStopMinDistance) or 14.0
    local maximum = tonumber(options.sceneStopMaxDistance) or 28.0
    local position, heading = roadNodeAround(patient, { 20.0, 16.0, 24.0, 28.0 }, minimum, maximum, nil)
    if position then return position, heading end
    -- Relaxed fallback: wider band, finer angle steps. Keeps a sparse road
    -- network near the patient from failing the call outright.
    return roadNodeAround(patient, { 20.0, 16.0, 24.0, 28.0, 32.0, 12.0, 36.0, 10.0 },
        minimum * 0.6, maximum * 1.6, nil, 22.5)
end

RegisterNetEvent('cm-ems:client:dispatchResponderPosition', function(callId, coords, label)
    callId = tonumber(callId)
    if not callId or type(coords) ~= 'table' then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    local blip = responderBlips[callId]
    if not blip or not DoesBlipExist(blip) then
        blip = AddBlipForCoord(x, y, z)
        responderBlips[callId] = blip
        SetBlipSprite(blip, 153); SetBlipColour(blip, 1); SetBlipScale(blip, .85); SetBlipAsShortRange(blip, false)
        ShowHeadingIndicatorOnBlip(blip, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentString(tostring(label or 'EMS responder')); EndTextCommandSetBlipName(blip)
    else
        SetBlipCoords(blip, x, y, z)
    end
end)

RegisterNetEvent('cm-ems:client:dispatchUpdated', function(action, call)
    if action ~= 'removed' or type(call) ~= 'table' then return end
    local id, blip = tonumber(call.id), responderBlips[tonumber(call.id)]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    responderBlips[id] = nil
end)

RegisterNetEvent('cm-ems:client:prepareGovernmentDoctor', function(call, options)
    if type(call) ~= 'table' or type(call.coords) ~= 'table' then return end
    local callId = tonumber(call.id)
    if not callId or pendingCallId then return end

    -- A failed ambulance may still be visibly returning to its vehicle when
    -- the server assigns a fresh route. Do not silently drop that retry just
    -- because cleanup needs a few more seconds.
    if mission then
        local cleanupDeadline = GetGameTimer() + 30000
        while mission and GetGameTimer() < cleanupDeadline and patientStillDown() do Wait(250) end
        if mission then
            reportFailure(callId, 'previous_response_cleanup_busy')
            return
        end
        if not patientStillDown() then return end
    end
    options = type(options) == 'table' and options or {}
    pendingCallId = callId
    if lib and lib.notify then lib.notify({ title = 'Government medical response', description = 'A government doctor has been dispatched and is on the way.', type = 'inform' }) end

    -- Real dispatch takes real time. Hold here — nothing exists in the world
    -- yet — instead of spawning the ambulance immediately and leaving it
    -- parked for minutes before it starts moving.
    local minArrivalMs = tonumber(options.arrivalMinMs) or 120000
    local maxArrivalMs = tonumber(options.arrivalMaxMs) or 120000
    local estimatedTravelMs = tonumber(options.estimatedTravelMs) or 15000
    local targetArrivalMs = math.random(math.min(minArrivalMs, maxArrivalMs), math.max(minArrivalMs, maxArrivalMs))

    -- The patient's actual bleed-out clock always wins over the usual random
    -- pacing: dispatched late (an EMS member clicking "send" with little time
    -- left, or a retry after an earlier attempt failed), the doctor needs a
    -- real shot at arriving before they die, not a confident 1-3 minute wait
    -- that guarantees it shows up too late.
    local patientRemainingMs = tonumber(options.patientRemainingMs)
    if patientRemainingMs and options.allowUrgentArrival ~= false then
        local treatmentSafetyMs = (tonumber(options.treatmentMs) or 10000) + 8000
        local urgentArrivalMs = math.max(patientRemainingMs - treatmentSafetyMs, 5000)
        if urgentArrivalMs < targetArrivalMs then targetArrivalMs = urgentArrivalMs end
    end

    local dispatchDelayMs = math.max(targetArrivalMs - estimatedTravelMs, 0)
    if dispatchDelayMs > 0 then
        local deadline = GetGameTimer() + dispatchDelayMs
        while GetGameTimer() < deadline and pendingCallId == callId and patientStillDown() do
            Wait(500)
        end
        if pendingCallId ~= callId or not patientStillDown() then
            pendingCallId = nil
            return
        end
    end

    local vehicleHash, pedHash = loadModel(options.vehicleModel or 'ambulance'), loadModel(options.pedModel or 's_m_m_paramedic_01')
    if not vehicleHash or not pedHash then pendingCallId = nil; reportFailure(call.id, 'model_load_failed'); return end
    local patient = vector3(tonumber(call.coords.x), tonumber(call.coords.y), tonumber(call.coords.z))
    local stopPoint = sceneStop(patient, options)
    if not stopPoint then pendingCallId = nil; reportFailure(call.id, 'no_safe_scene_stop'); return end
    local spawn, heading = responseSpawn(patient, stopPoint, options)
    if not spawn then pendingCallId = nil; reportFailure(call.id, 'no_safe_spawn_node'); return end
    pendingStops[callId] = stopPoint
    pendingSpawns[callId] = spawn
    TriggerServerEvent('cm-ems:server:spawnGovernmentDoctor', callId,
        { x = spawn.x, y = spawn.y, z = spawn.z }, heading,
        { x = stopPoint.x, y = stopPoint.y, z = stopPoint.z })
    SetModelAsNoLongerNeeded(vehicleHash); SetModelAsNoLongerNeeded(pedHash)
    pendingCallId = nil
end)

RegisterNetEvent('cm-ems:client:governmentDoctorSpawnFailed', function(callId, reason)
    reportFailure(callId, reason)
end)

RegisterNetEvent('cm-ems:client:addGovernmentDoctorPatient', function(responseId, patient)
    responseId = tonumber(responseId)
    if not responseId or type(patient) ~= 'table' or not tonumber(patient.id) or not tonumber(patient.source) then return end
    patient.id, patient.source = tonumber(patient.id), tonumber(patient.source)
    if mission and mission.id == responseId then
        mission.patients[patient.id] = patient
        mission.resolved = false
    else
        pendingPatients[responseId] = pendingPatients[responseId] or {}
        pendingPatients[responseId][patient.id] = patient
    end
end)

RegisterNetEvent('cm-ems:client:observeGovernmentDoctorCleanup', function(vehicleNetId, doctorNetId)
    vehicleNetId, doctorNetId = tonumber(vehicleNetId), tonumber(doctorNetId) or 0
    if not vehicleNetId or vehicleNetId <= 0 then return end
    local token = GetGameTimer()
    cleanupObservers[vehicleNetId] = token

    CreateThread(function()
        while cleanupObservers[vehicleNetId] == token do
            local visible = false
            local function entityIsVisible(netId)
                if netId <= 0 or not NetworkDoesNetworkIdExist(netId) then return false end
                local entity = NetworkGetEntityFromNetworkId(netId)
                if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                return IsEntityOnScreen(entity)
                    and not IsEntityOccluded(entity)
                    and HasEntityClearLosToEntity(PlayerPedId(), entity, 17)
            end
            visible = entityIsVisible(vehicleNetId) or entityIsVisible(doctorNetId)
            if visible then TriggerServerEvent('cm-ems:server:governmentDoctorStillVisible', vehicleNetId) end
            Wait(400)
        end
        if cleanupObservers[vehicleNetId] == token then cleanupObservers[vehicleNetId] = nil end
    end)
end)

RegisterNetEvent('cm-ems:client:stopGovernmentDoctorCleanupObserver', function(vehicleNetId)
    cleanupObservers[tonumber(vehicleNetId)] = nil
end)

-- One walk attempt toward the player, using either the navmesh (routes
-- around walls/fences/stairs) or GTA's "any means" pathing (a different
-- algorithm that can occasionally get past things the navmesh refuses, e.g.
-- vaulting a low obstacle). Retasks periodically to track a moving patient
-- and gives up if the ped is genuinely not moving (blocked), rather than
-- reacting to distance-to-target staying flat while still legitimately
-- walking a route around an obstacle.
local function walkAttempt(doctor, patient, budgetMs, stoppingRadius, useAnyMeans)
    local moveBlendRatio = 2.0
    local retaskEveryMs = 3000
    local idleStuckAfterMs = 4500
    local minMoveSpeed = 0.15

    local function currentTarget()
        local ped = patientPed(patient)
        return ped and DoesEntityExist(ped) and GetEntityCoords(ped) or nil
    end

    local function task(target)
        if useAnyMeans then
            TaskGoToCoordAnyMeans(doctor, target.x, target.y, target.z, moveBlendRatio, 0, false, 786603, 0.0)
        else
            -- timeout -1 = let the task run indefinitely; this loop owns the
            -- give-up budget instead of the native silently ending it early.
            TaskFollowNavMeshToCoord(doctor, target.x, target.y, target.z, moveBlendRatio, -1, stoppingRadius, false, 0.0)
        end
    end

    local target = currentTarget()
    if not target then return false end
    task(target)

    local startedAt, lastMovingAt, lastRetaskAt = GetGameTimer(), GetGameTimer(), GetGameTimer()
    -- Grace period: pathfinding across a route with obstacles takes a moment
    -- to compute, and the ped can sit still briefly before it starts moving.
    Wait(1500)
    while DoesEntityExist(doctor) and GetGameTimer() - startedAt < budgetMs do
        if not patientStillDown(patient) then return false end
        target = currentTarget()
        if not target then return false end
        local distance = #(GetEntityCoords(doctor) - target)
        if distance <= stoppingRadius + 1.5 then return true end
        if GetEntitySpeed(doctor) > minMoveSpeed then lastMovingAt = GetGameTimer() end
        if GetGameTimer() - lastRetaskAt > retaskEveryMs then
            task(target)
            lastRetaskAt = GetGameTimer()
        end
        if GetGameTimer() - lastMovingAt > idleStuckAfterMs then return false end
        Wait(250)
    end
    return false
end

-- Tries the navmesh for most of the budget; if that gives up (genuinely
-- blocked, not just a long route), spends the remainder on "any means"
-- pathing as a last try before the caller treats the patient as unreachable.
local function approachPatient(doctor, patient, timeoutMs, stoppingRadius)
    local anyMeansBudget = 8000
    local navBudget = math.max(timeoutMs - anyMeansBudget, 8000)
    if walkAttempt(doctor, patient, navBudget, stoppingRadius, false) then return true end
    if not DoesEntityExist(doctor) then return false end
    return walkAttempt(doctor, patient, anyMeansBudget, stoppingRadius, true)
end

local function alignDoctorForCpr(doctor, patient)
    local targetPed = patientPed(patient)
    if not targetPed or not DoesEntityExist(doctor) then return false end
    TaskGoToEntity(doctor, targetPed, 5000, 1.0, 1.0, 0.0, 0)
    local deadline = GetGameTimer() + 5000
    while DoesEntityExist(doctor) and DoesEntityExist(targetPed)
        and #(GetEntityCoords(doctor) - GetEntityCoords(targetPed)) > 1.6
        and GetGameTimer() < deadline do
        Wait(100)
    end
    if not DoesEntityExist(doctor) or not DoesEntityExist(targetPed)
        or #(GetEntityCoords(doctor) - GetEntityCoords(targetPed)) > 1.8 then return false end
    TaskTurnPedToFaceEntity(doctor, targetPed, 750)
    Wait(750)
    return DoesEntityExist(targetPed) and #(GetEntityCoords(doctor) - GetEntityCoords(targetPed)) <= 1.8
end

-- Called once the doctor gives up reaching the patient on foot: wait briefly
-- (looks like the doctor deciding it's a lost cause) then walk back to the
-- ambulance and re-board, instead of just vanishing in front of the player.
local function retreatToVehicle(doctor, vehicle)
    if not DoesEntityExist(doctor) then return end
    ClearPedTasksImmediately(doctor)
    TaskStandStill(doctor, 2000)
    Wait(2000)
    if not DoesEntityExist(doctor) or not DoesEntityExist(vehicle) then return end
    local vehiclePos = GetEntityCoords(vehicle)
    TaskFollowNavMeshToCoord(doctor, vehiclePos.x, vehiclePos.y, vehiclePos.z, 2.0, -1, 2.0, false, 0.0)
    local deadline = GetGameTimer() + 15000
    while DoesEntityExist(doctor) and DoesEntityExist(vehicle)
        and #(GetEntityCoords(doctor) - GetEntityCoords(vehicle)) > 4.0 and GetGameTimer() < deadline do
        Wait(250)
    end
end

-- Re-boards the doctor and drives back out toward the road it originally
-- came from (a real vehicle node, not an arbitrary wander), so leaving the
-- scene looks like a deliberate drive-off. Falls back to ambient wandering
-- only if the original spawn point isn't known (e.g. a resource restart
-- mid-mission lost it).
local function departScene(doctor, vehicle, driveAwayPoint, driveSpeed)
    if not DoesEntityExist(doctor) or not DoesEntityExist(vehicle) then return end
    local controlDeadline = GetGameTimer() + 3000
    while GetGameTimer() < controlDeadline
        and (not NetworkHasControlOfEntity(doctor) or not NetworkHasControlOfEntity(vehicle)) do
        NetworkRequestControlOfEntity(doctor)
        NetworkRequestControlOfEntity(vehicle)
        Wait(100)
    end
    FreezeEntityPosition(vehicle, false); SetVehicleHandbrake(vehicle, false)
    TaskEnterVehicle(doctor, vehicle, 10000, -1, 1.5, 1, 0)
    local enterDeadline = GetGameTimer() + 10000
    while DoesEntityExist(doctor) and DoesEntityExist(vehicle)
        and GetPedInVehicleSeat(vehicle, -1) ~= doctor and GetGameTimer() < enterDeadline do
        Wait(200)
    end
    if not DoesEntityExist(doctor) or not DoesEntityExist(vehicle) then return end
    -- GTA pathing can fail to find the driver door after CPR, especially when
    -- the ambulance parked tight against a kerb. Warp only as a recovery after
    -- the natural enter animation has had its full chance to complete.
    if GetPedInVehicleSeat(vehicle, -1) ~= doctor then SetPedIntoVehicle(doctor, vehicle, -1) end
    if GetPedInVehicleSeat(vehicle, -1) ~= doctor then return end
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleSiren(vehicle, false)
    SetDriverAbility(doctor, 1.0); SetDriverAggressiveness(doctor, .3)
    if driveAwayPoint then
        TaskVehicleDriveToCoordLongrange(doctor, vehicle, driveAwayPoint.x, driveAwayPoint.y, driveAwayPoint.z, driveSpeed or 20.0, 1074528293, 8.0)
        -- TaskVehicleDriveToCoordLongrange stops the vehicle once it arrives
        -- instead of continuing on -- left alone, it just parks there and
        -- sits, which both looks wrong and can stall the server-side cleanup
        -- (it only deletes once nobody's nearby, and a parked ambulance near
        -- where the player still is never satisfies that). Switch to
        -- open-ended wandering once it's close to the getaway point (or after
        -- a timeout) so it keeps actually moving like normal traffic.
        CreateThread(function()
            local deadline = GetGameTimer() + 60000
            while DoesEntityExist(vehicle) and GetGameTimer() < deadline
                and #(GetEntityCoords(vehicle) - driveAwayPoint) > 15.0 do
                Wait(1000)
            end
            if DoesEntityExist(doctor) and DoesEntityExist(vehicle) then
                TaskVehicleDriveWander(doctor, vehicle, 20.0, 786603)
            end
        end)
    else
        TaskVehicleDriveWander(doctor, vehicle, 20.0, 786603)
    end

    -- Confirm the departure task actually starts. If it is still stationary,
    -- retask twice and then fall back to ambient driving so visibility-based
    -- cleanup can never leave a permanently parked ambulance at the scene.
    local moveDeadline, lastRetask = GetGameTimer() + 7000, GetGameTimer()
    while DoesEntityExist(vehicle) and DoesEntityExist(doctor)
        and GetEntitySpeed(vehicle) < 0.5 and GetGameTimer() < moveDeadline do
        if GetGameTimer() - lastRetask >= 2000 then
            if driveAwayPoint then
                TaskVehicleDriveToCoordLongrange(doctor, vehicle, driveAwayPoint.x, driveAwayPoint.y, driveAwayPoint.z, driveSpeed or 20.0, 1074528293, 8.0)
            else
                TaskVehicleDriveWander(doctor, vehicle, 20.0, 786603)
            end
            lastRetask = GetGameTimer()
        end
        Wait(250)
    end
    if DoesEntityExist(vehicle) and DoesEntityExist(doctor) and GetEntitySpeed(vehicle) < 0.5 then
        TaskVehicleDriveWander(doctor, vehicle, 20.0, 786603)
    end
end

-- If the vehicle has been genuinely stationary for a while, it's pressed
-- against something the pathing didn't account for -- or, on a complex
-- multi-level interchange (highway ramps stacked over surface streets), GTA's
-- own vehicle AI can get physically wedged against a support pillar or ramp
-- edge well above the actual road. Blindly stepping it back using its CURRENT
-- (possibly already-wrong, e.g. up on a pillar) Z can shuffle it around on
-- top of that same bad structure instead of actually freeing it. Only ever
-- reposition to a real, verified road node -- never a raw coordinate guess.
-- Returns true if a safe node was found and used, false if not (the caller
-- should treat "not" as a strong signal to give up on this route entirely
-- rather than keep retrying the same spot).
local function nudgeStuckVehicle(doctor, vehicle, stopPoint, driveSpeed)
    if not DoesEntityExist(vehicle) or not DoesEntityExist(doctor) then return false end
    local pos = GetEntityCoords(vehicle)
    local rad = math.rad(GetEntityHeading(vehicle))
    local forwardX, forwardY = -math.sin(rad), math.cos(rad)
    local backX, backY = pos.x - forwardX * 4.0, pos.y - forwardY * 4.0

    local found, node, heading = GetClosestVehicleNodeWithHeading(backX, backY, pos.z, 1, 3.0, 0)
    if not found then
        for _, offset in ipairs({ 0, 90, -90, 180 }) do
            local orad = math.rad(offset)
            local ox = pos.x + math.cos(orad) * 15.0
            local oy = pos.y + math.sin(orad) * 15.0
            found, node, heading = GetClosestVehicleNodeWithHeading(ox, oy, pos.z, 1, 3.0, 0)
            if found then break end
        end
    end
    if not found or not node then return false end

    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
    SetEntityCoords(vehicle, node.x, node.y, node.z, false, false, false, false)
    SetEntityHeading(vehicle, heading)
    SetVehicleOnGroundProperly(vehicle)
    Wait(300)
    if DoesEntityExist(doctor) and DoesEntityExist(vehicle) then
        TaskVehicleDriveToCoordLongrange(doctor, vehicle, stopPoint.x, stopPoint.y, stopPoint.z, driveSpeed, 1074528293, 5.0)
    end
    return true
end

RegisterNetEvent('cm-ems:client:startGovernmentDoctor', function(call, options, vehicleNetId, doctorNetId, serverStopPoint)
    if mission or type(call) ~= 'table' or type(call.coords) ~= 'table' then return end
    options = type(options) == 'table' and options or {}
    local deadline = GetGameTimer() + 15000
    local vehicle, doctor
    while GetGameTimer() < deadline do
        local vehicleId, doctorId = tonumber(vehicleNetId) or 0, tonumber(doctorNetId) or 0
        if vehicleId > 0 and NetworkDoesNetworkIdExist(vehicleId) then vehicle = NetworkGetEntityFromNetworkId(vehicleId) end
        if doctorId > 0 and NetworkDoesNetworkIdExist(doctorId) then doctor = NetworkGetEntityFromNetworkId(doctorId) end
        if DoesEntityExist(vehicle) and DoesEntityExist(doctor) then break end
        Wait(100)
    end
    if not DoesEntityExist(vehicle) or not DoesEntityExist(doctor) then
        reportFailure(call.id, 'entity_stream_failed')
        -- These entities exist server-side even though they never streamed
        -- in for us -- hand cleanup off directly by netId so the server
        -- doesn't keep tracking (and the world doesn't keep holding) an
        -- ambulance nobody can ever reach from this client.
        if tonumber(vehicleNetId) then
            TriggerServerEvent('cm-ems:server:governmentDoctorDeparted', tonumber(vehicleNetId), tonumber(doctorNetId))
        end
        return
    end
    local patient = vector3(tonumber(call.coords.x), tonumber(call.coords.y), tonumber(call.coords.z))
    local stopPoint = type(serverStopPoint) == 'table' and vector3(tonumber(serverStopPoint.x), tonumber(serverStopPoint.y), tonumber(serverStopPoint.z))
        or pendingStops[tonumber(call.id)] or sceneStop(patient, options)
    pendingStops[tonumber(call.id)] = nil
    local driveAwayPoint = pendingSpawns[tonumber(call.id)]
    pendingSpawns[tonumber(call.id)] = nil
    if not stopPoint then reportFailure(call.id, 'no_safe_scene_stop'); return end
    SetEntityAsMissionEntity(vehicle, true, true); SetEntityAsMissionEntity(doctor, true, true)
    local vehicleNetworkId, doctorNetworkId = NetworkGetNetworkIdFromEntity(vehicle), NetworkGetNetworkIdFromEntity(doctor)
    if vehicleNetworkId and vehicleNetworkId > 0 then SetNetworkIdCanMigrate(vehicleNetworkId, true) end
    if doctorNetworkId and doctorNetworkId > 0 then SetNetworkIdCanMigrate(doctorNetworkId, true) end
    SetVehicleSiren(vehicle, true); SetVehicleEngineOn(vehicle, true, true, false); SetVehicleHandbrake(vehicle, false)
    SetVehicleUndriveable(vehicle, false)
    SetBlockingOfNonTemporaryEvents(doctor, true)
    SetPedCanBeDraggedOut(doctor, false)
    SetPedFleeAttributes(doctor, 0, false)
    SetEntityInvincible(doctor, true)
    SetDriverAbility(doctor, 1.0); SetDriverAggressiveness(doctor, .55); SetPedKeepTask(doctor, true)
    local responseId = tonumber(call.id)
    local patients = pendingPatients[responseId] or {}
    pendingPatients[responseId] = nil
    patients[responseId] = {
        id = responseId,
        source = GetPlayerServerId(PlayerId()),
        coords = call.coords,
    }
    mission = { id = responseId, vehicle = vehicle, doctor = doctor, resolved = false, patients = patients }
    local current = mission
    local driveSpeed = tonumber(options.driveSpeed) or 25.0

    -- The dispatch/response delay already happened before this ambulance was
    -- even spawned (see prepareGovernmentDoctor) — from here it starts
    -- closing in right away, no idle parked wait.
    CreateThread(function()
        if not DoesEntityExist(vehicle) or not DoesEntityExist(doctor) then
            reportFailure(current.id, 'entity_lost')
            return cleanup(current)
        end

        -- Control can drift during a multi-minute dispatch delay, so
        -- re-check it fresh here rather than trusting a value captured
        -- before the wait.
        local controlDeadline = GetGameTimer() + 10000
        while GetGameTimer() < controlDeadline and (not NetworkHasControlOfEntity(vehicle) or not NetworkHasControlOfEntity(doctor)) do
            NetworkRequestControlOfEntity(vehicle); NetworkRequestControlOfEntity(doctor)
            Wait(100)
        end
        local hasControl = NetworkHasControlOfEntity(vehicle) and NetworkHasControlOfEntity(doctor)
        if not hasControl then
            reportFailure(current.id, 'entity_control_failed')
            return handoffCleanup(current)
        end
        SetPedIntoVehicle(doctor, vehicle, -1)

        -- The ambulance was deliberately spawned inside active simulation
        -- range, so this is a normal GTA road-driving task from start to end.
        TaskVehicleDriveToCoordLongrange(doctor, vehicle, stopPoint.x, stopPoint.y, stopPoint.z, driveSpeed, 1074528293, 5.0)
        local drivingControl = true

        local startedAt, lastMovingAt, lastRecoveryAt, recoveryAttempts = GetGameTimer(), GetGameTimer(), 0, 0
        while mission == current and not current.resolved and hasDownPatients(current)
            and DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - stopPoint) > 7.0 do
            local pos = GetEntityCoords(vehicle)
            if not NetworkHasControlOfEntity(vehicle) or not NetworkHasControlOfEntity(doctor) then
                NetworkRequestControlOfEntity(vehicle); NetworkRequestControlOfEntity(doctor)
            end
            local controlsBoth = NetworkHasControlOfEntity(vehicle) and NetworkHasControlOfEntity(doctor)
            if not controlsBoth then drivingControl = false end
            if controlsBoth and not drivingControl then
                SetPedIntoVehicle(doctor, vehicle, -1)
                SetVehicleEngineOn(vehicle, true, true, false); SetVehicleHandbrake(vehicle, false); SetVehicleUndriveable(vehicle, false)
                TaskVehicleDriveToCoordLongrange(doctor, vehicle, stopPoint.x, stopPoint.y, stopPoint.z, driveSpeed, 1074528293, 5.0)
                drivingControl = true
            end
            if GetEntitySpeed(vehicle) > 0.5 then lastMovingAt = GetGameTimer() end
            if controlsBoth and drivingControl and recoveryAttempts < 5
                and GetGameTimer() - lastMovingAt > 6000 and GetGameTimer() - lastRecoveryAt > 6000 then
                -- Truly stationary, not just a long route: almost certainly
                -- pressed against something. Back off and retry rather than
                -- revving forward into whatever is blocking it.
                local recovered = nudgeStuckVehicle(doctor, vehicle, stopPoint, driveSpeed)
                if not recovered then
                    -- No real road node anywhere nearby to fall back to --
                    -- this is likely a vehicle physically wedged somewhere
                    -- (e.g. on a highway interchange support structure), not
                    -- a simple "pressed against a wall". Give up on this
                    -- route now and let the caller retry from a fresh spawn
                    -- point rather than sitting stuck for the full timeout.
                    reportFailure(current.id, 'route_stuck')
                    return cleanup(current)
                end
                lastRecoveryAt, lastMovingAt = GetGameTimer(), GetGameTimer()
                recoveryAttempts = recoveryAttempts + 1
            end
            if GetGameTimer() - startedAt > (tonumber(options.routeTimeoutMs) or 120000) then
                reportFailure(current.id, 'route_timeout')
                departScene(doctor, vehicle, driveAwayPoint, driveSpeed)
                return handoffCleanup(current)
            end
            TriggerServerEvent('cm-ems:server:governmentDoctorPosition', current.id, { x = pos.x, y = pos.y, z = pos.z })
            Wait(1000)
        end
        if mission ~= current or not DoesEntityExist(vehicle) then return cleanup(current) end
        if current.resolved then
            TriggerServerEvent('cm-ems:server:governmentDoctorClosing', current.id)
            departScene(doctor, vehicle, driveAwayPoint, driveSpeed)
            return handoffCleanup(current)
        end
        TaskVehicleTempAction(doctor, vehicle, 27, 2500); Wait(1500)
        SetVehicleForwardSpeed(vehicle, 0.0); SetVehicleHandbrake(vehicle, true)
        FreezeEntityPosition(vehicle, true)
        -- The parked ambulance must never trap its own medic between the body
        -- and a kerb/wall. Disable only this entity pair's collision while the
        -- medic exits and works; all world/player collision remains normal.
        SetEntityNoCollisionEntity(doctor, vehicle, false)
        SetEntityNoCollisionEntity(vehicle, doctor, false)
        TaskLeaveVehicle(doctor, vehicle, 0)
        local leaveDeadline = GetGameTimer() + 5000
        while IsPedInVehicle(doctor, vehicle, false) and GetGameTimer() < leaveDeadline do Wait(100) end
        if IsPedInVehicle(doctor, vehicle, false) then
            TaskLeaveVehicle(doctor, vehicle, 16)
            Wait(500)
        end
        TriggerServerEvent('cm-ems:server:governmentDoctorArrived', current.id)
        RequestAnimDict('mini@cpr@char_a@cpr_str')
        while not HasAnimDictLoaded('mini@cpr@char_a@cpr_str') do Wait(50) end
        local queueWaitMs = tonumber(options.sharedResponseWaitMs) or 30000
        local idleDeadline = GetGameTimer() + queueWaitMs
        local leaveWhenQueueEmpty = false
        while mission == current and not current.resolved do
            local targetPatient, queueState = lib.callback.await('cm-ems:server:governmentDoctorNextPatient', false, current.id)
            if type(targetPatient) ~= 'table' then
                -- Once a patient has been stabilized, do one authoritative
                -- queue check and leave immediately when nobody else is
                -- already assigned to this shared government response.
                if leaveWhenQueueEmpty and queueState == 'empty' then break end
                if GetGameTimer() >= idleDeadline then break end
                Wait(queueState == 'not_ready' and 500 or 1000)
            else
                idleDeadline = GetGameTimer() + queueWaitMs
                current.patients[targetPatient.id] = targetPatient
                local reached = approachPatient(doctor, targetPatient, tonumber(options.footApproachTimeoutMs) or 25000, 1.3)
                local aligned = reached and alignDoctorForCpr(doctor, targetPatient)
                if aligned and patientStillDown(targetPatient) then
                    TaskPlayAnim(doctor, 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest', 8.0, -8.0, tonumber(options.treatmentMs) or 10000, 1, 0, false, false, false)
                    Wait(tonumber(options.treatmentMs) or 10000)
                    local treated = false
                    if patientStillDown(targetPatient) then
                        treated = lib.callback.await('cm-ems:server:governmentDoctorTreat', false, current.id, targetPatient.id) == true
                    end
                    if treated or not patientStillDown(targetPatient) then
                        current.patients[targetPatient.id] = nil
                        leaveWhenQueueEmpty = true
                    end
                end
                if not leaveWhenQueueEmpty then idleDeadline = GetGameTimer() + queueWaitMs end
                Wait(aligned and 500 or 1200)
            end
        end
        TriggerServerEvent('cm-ems:server:governmentDoctorClosing', current.id)
        departScene(doctor, vehicle, driveAwayPoint, driveSpeed)
        handoffCleanup(current)
    end)
end)

RegisterNetEvent('cm-ems:client:stopGovernmentDoctor', function(callId)
    callId = tonumber(callId)
    if mission and mission.patients then
        mission.patients[callId] = nil
    end
    if pendingCallId == callId then pendingCallId = nil end
    for _, patients in pairs(pendingPatients) do patients[callId] = nil end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanup(mission)
    cleanupObservers = {}
    for id, blip in pairs(responderBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end; responderBlips[id] = nil end
end)
