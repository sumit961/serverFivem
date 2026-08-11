-- Client route and presentation for selectable EMS missions.

local activeMission
local missionBlip
local patientPed
local missionVehicle
local hospitalStaffPed
local sceneProps = {}
local currentStageReady = false
local stageBusy = false
local missionPlacementActive = false
local patientAtBed = false
local currentActionToken
local currentActionRunId
local currentActionStageIndex
CMEMSMissionObjectiveReady = false

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'EMS Mission', description = message, type = kind or 'inform' }) end
end

local function cleanupBlip()
    if missionBlip and DoesBlipExist(missionBlip) then RemoveBlip(missionBlip) end
    missionBlip = nil
end

local function cleanupPatient()
    if patientPed and DoesEntityExist(patientPed) then
        SetEntityAsMissionEntity(patientPed, true, true)
        DeletePed(patientPed)
    end
    patientPed = nil
    patientAtBed = false
end

local function cleanupScenePresentation()
    for _, entity in ipairs(sceneProps) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    sceneProps = {}
    if hospitalStaffPed and DoesEntityExist(hospitalStaffPed) then DeletePed(hospitalStaffPed) end
    hospitalStaffPed = nil
end

local function dischargePatientPresentation()
    if not patientAtBed or not patientPed or not DoesEntityExist(patientPed) then
        return cleanupPatient()
    end
    local dischargedPed = patientPed
    patientPed, patientAtBed = nil, false
    CreateThread(function()
        Wait(8000)
        if DoesEntityExist(dischargedPed) then
            SetEntityAsMissionEntity(dischargedPed, true, true)
            DeletePed(dischargedPed)
        end
    end)
end

local function cleanupMissionVehicle()
    if missionVehicle and DoesEntityExist(missionVehicle) then
        SetEntityAsMissionEntity(missionVehicle, true, true)
        DeleteVehicle(missionVehicle)
    end
    missionVehicle = nil
end

local conditionLabels = {
    cardiac_arrest = 'Cardiac arrest: begin CPR immediately',
    overdose = 'Suspected overdose: administer reversal medication',
    bleeding = 'Active bleeding: control bleeding and stabilize',
    breathing_difficulty = 'Breathing difficulty: administer emergency medication',
    unconscious = 'Unconscious patient: assess breathing and stabilize',
    stable_transport = 'Stable patient: prepare for safe transport',
}

local patientModels = {
    'a_m_m_business_01', 'a_f_y_business_02', 'a_m_y_hipster_01',
    'a_f_m_bevhills_01', 'a_m_m_farmer_01', 'a_f_y_tourist_01',
}

local function spawnSceneProps(stage)
    if type(stage and stage.coords) ~= 'table' or GetInteriorFromEntity(PlayerPedId()) ~= 0 then return end
    local model = joaat('prop_roadcone02a')
    RequestModel(model)
    local deadline = GetGameTimer() + 2500
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local x, y, z = tonumber(stage.coords.x) or 0.0, tonumber(stage.coords.y) or 0.0, tonumber(stage.coords.z) or 0.0
    for _, offset in ipairs({ { 2.2, 1.4 }, { -2.2, 1.4 } }) do
        local prop = CreateObject(model, x + offset[1], y + offset[2], z, false, false, false)
        if prop and prop ~= 0 then
            PlaceObjectOnGroundProperly(prop); FreezeEntityPosition(prop, true)
            sceneProps[#sceneProps + 1] = prop
        end
    end
    SetModelAsNoLongerNeeded(model)
end

local function spawnStageVehicle(stage)
    if missionVehicle or not stage or not stage.spawnVehicle or type(stage.coords) ~= 'table' then return end
    local model = joaat(tostring(stage.spawnVehicle))
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then return end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    missionVehicle = CreateVehicle(model, (tonumber(stage.coords.x) or 0.0) + 4.0, (tonumber(stage.coords.y) or 0.0) + 2.0,
        tonumber(stage.coords.z) or 0.0, tonumber(stage.vehicleHeading) or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    if not missionVehicle or missionVehicle == 0 then missionVehicle = nil; return end
    SetEntityAsMissionEntity(missionVehicle, true, true)
    SetEntityInvincible(missionVehicle, true)
    SetVehicleEngineHealth(missionVehicle, 300.0)
    SetVehicleBodyHealth(missionVehicle, 650.0)
    SetVehicleEngineOn(missionVehicle, false, true, true)
    SetVehicleDoorOpen(missionVehicle, 4, false, false)
    FreezeEntityPosition(missionVehicle, true)
end

local patientStageTypes = {
    treat = true, recover = true, pickup_patient = true, escort_patient = true,
    board_vehicle = true, transport = true, unload_patient = true, deliver_patient = true,
    hospital_handoff = true,
}

-- Stages where the visible patient is the actual interaction point. The old
-- logic also required the player to stand almost exactly on the configured
-- route coordinate. Ground snapping, slopes and MLO interiors can move the
-- local patient a few metres from that coordinate, leaving no [E] prompt even
-- while the medic is standing beside the NPC.
local patientAnchoredStageTypes = {
    treat = true, recover = true, pickup_patient = true, board_vehicle = true,
}

local function isPatientAction(stageType)
    return patientStageTypes[tostring(stageType or '')] == true
end

local function patientPresentationStage(mission)
    if not mission or not mission.route then return nil end
    local stages = mission.route.stages or {}
    -- Infer patient presentation from the stage types as well as the route
    -- checkbox. This keeps admin-created missions functional when they contain
    -- patient objectives but were saved without the route-level patient flag.
    local hasPatientRoute = mission.route.patient == true
    if not hasPatientRoute then
        for index = 1, #stages do
            if patientStageTypes[tostring(stages[index] and stages[index].type)] then
                hasPatientRoute = true
                break
            end
        end
    end
    if not hasPatientRoute then return nil end
    local currentIndex = math.max(1, math.floor(tonumber(mission.stageIndex) or 1))
    local current = mission.stage or stages[currentIndex]
    if current and patientStageTypes[tostring(current.type)] then return current end
    -- Before the patient is reached (for example, collecting medicine first),
    -- use the next patient objective as the spawn anchor.
    for index = currentIndex, #stages do
        if patientStageTypes[tostring(stages[index] and stages[index].type)] then return stages[index] end
    end
    -- A player can join or reopen the board after the patient has already moved.
    -- Falling back to the latest patient stage keeps a local presentation available
    -- instead of searching forever at the original scene.
    for index = math.min(currentIndex - 1, #stages), 1, -1 do
        if patientStageTypes[tostring(stages[index] and stages[index].type)] then return stages[index] end
    end
end

local function playPatientCondition(stageType)
    if not patientPed or not DoesEntityExist(patientPed) then return end
    ClearPedTasksImmediately(patientPed)
    if stageType == 'pickup_patient' then
        TaskStartScenarioInPlace(patientPed, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
        return
    end
    local dict = 'combat@damage@writhe'
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(patientPed, dict, 'writhe_loop', 3.0, -3.0, -1, 1, 0.0, false, false, false)
    end
end

local function stabilizePatient()
    if not patientPed or not DoesEntityExist(patientPed) or IsPedInAnyVehicle(patientPed, false) then return end
    FreezeEntityPosition(patientPed, false)
    ClearPedTasksImmediately(patientPed)
    local dict = 'amb@world_human_picnic@male@idle_a'
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(patientPed, dict, 'idle_a', 2.0, -2.0, -1, 1, 0.0, false, false, false)
    end
end

local function placePedOnOutdoorGround(ped, coords)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    -- PLACE_ENTITY_ON_GROUND_PROPERLY is not a FiveM Lua native. Ped placement
    -- is handled with an authored interior Z or an outdoor ground-Z lookup.
    if GetInteriorFromEntity(ped) ~= 0 then return end
    local current = coords or GetEntityCoords(ped)
    local x, y, z = tonumber(current.x) or 0.0, tonumber(current.y) or 0.0, tonumber(current.z) or 0.0
    RequestCollisionAtCoord(x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
    if found then
        SetEntityCoordsNoOffset(ped, x, y, groundZ, false, false, false)
    end
end

local function spawnMissionPatient(mission)
    if patientPed and DoesEntityExist(patientPed) then return end
    local stage = patientPresentationStage(mission)
    if not stage or type(stage.coords) ~= 'table' then return end
    local modelName = stage.type == 'recover' and 'a_m_m_beach_01'
        or patientModels[((tonumber(mission.runId) or 1) % #patientModels) + 1]
    local model = joaat(modelName)
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    patientPed = CreatePed(4, model, tonumber(stage.coords.x) or 0.0, tonumber(stage.coords.y) or 0.0,
        tonumber(stage.coords.z) or 0.0, 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    if not patientPed or patientPed == 0 then patientPed = nil; return end
    SetEntityAsMissionEntity(patientPed, true, true)
    SetEntityInvincible(patientPed, true)
    SetEntityHealth(patientPed, 150)
    SetBlockingOfNonTemporaryEvents(patientPed, true)
    SetPedCanRagdoll(patientPed, false)
    SetPedFleeAttributes(patientPed, 0, false)
    -- Load collision before positioning. Outdoors we resolve ground Z; inside
    -- an MLO we keep the authored Z coordinate so the patient is not dropped
    -- to the road or basement below the interior.
    RequestCollisionAtCoord(tonumber(stage.coords.x) or 0.0, tonumber(stage.coords.y) or 0.0,
        tonumber(stage.coords.z) or 0.0)
    SetEntityCoordsNoOffset(patientPed, tonumber(stage.coords.x) or 0.0, tonumber(stage.coords.y) or 0.0,
        tonumber(stage.coords.z) or 0.0, false, false, false)
    placePedOnOutdoorGround(patientPed, stage.coords)
    SetEntityHeading(patientPed, tonumber(stage.heading) or 0.0)
    -- Keep scene patients from slowly drifting away while their injured or
    -- waiting animation is playing. They are released as soon as escorting or
    -- vehicle loading begins.
    FreezeEntityPosition(patientPed, patientAnchoredStageTypes[tostring(stage.type or '')] == true)
    playPatientCondition(stage.type)
    if stage.type == 'treat' or stage.type == 'recover' then spawnSceneProps(stage) end
    local briefing = conditionLabels[tostring(mission.condition or '')]
    if briefing then notify(briefing, 'inform') end
end

local function isAuthorizedEmsVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local fleet = Entity(vehicle).state.cmEmsFleet
    if type(fleet) == 'table' and fleet.placement ~= true and fleet.model then return true end
    local model = GetEntityModel(vehicle)
    for _, allowed in ipairs((Config.EMSMissions or {}).allowedTransportVehicles or { 'ambulance', 'polmav' }) do
        if model == joaat(tostring(allowed)) then return true end
    end
    return false
end

local function nearbyEmsVehicle(maxDistance)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closest, closestDistance
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if isAuthorizedEmsVehicle(vehicle) then
            local distance = #(playerCoords - GetEntityCoords(vehicle))
            if distance <= maxDistance and (not closestDistance or distance < closestDistance) then
                closest, closestDistance = vehicle, distance
            end
        end
    end
    return closest
end

local function loadPatientIntoVehicle()
    if not patientPed or not DoesEntityExist(patientPed) then return false, 'The mission patient is unavailable.' end
    FreezeEntityPosition(patientPed, false)
    local vehicle = nearbyEmsVehicle(12.0)
    if not vehicle or vehicle == 0 then return false, 'Park an authorized EMS vehicle beside the patient.' end
    ClearPedTasksImmediately(patientPed)
    local seat
    for candidate = 1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if IsVehicleSeatFree(vehicle, candidate) then seat = candidate break end
    end
    if not seat and IsVehicleSeatFree(vehicle, 0) then seat = 0 end
    if not seat then return false, 'The EMS vehicle has no free passenger seat.' end
    TaskEnterVehicle(patientPed, vehicle, 5000, seat, 1.0, 1, 0)
    local deadline = GetGameTimer() + 5000
    while DoesEntityExist(patientPed) and GetGameTimer() < deadline
        and GetVehiclePedIsIn(patientPed, false) ~= vehicle do Wait(50) end
    -- Custom ambulances and obstructed rear doors can defeat pedestrian
    -- pathing. Fall back only after giving the visible boarding task time.
    if GetVehiclePedIsIn(patientPed, false) ~= vehicle then SetPedIntoVehicle(patientPed, vehicle, seat) end
    if GetVehiclePedIsIn(patientPed, false) ~= vehicle then
        return false, 'The patient could not be secured in the EMS vehicle.'
    end
    return true, nil, vehicle
end

local function patientTransportVehicle()
    if not patientPed or not DoesEntityExist(patientPed) then return nil end
    local vehicle = GetVehiclePedIsIn(patientPed, false)
    return isAuthorizedEmsVehicle(vehicle) and vehicle or nil
end

local function spawnHospitalStaff()
    if hospitalStaffPed and DoesEntityExist(hospitalStaffPed) then return end
    local vehicle = patientTransportVehicle()
    if not vehicle then return end
    local model = joaat('s_m_m_paramedic_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local spawn = GetOffsetFromEntityInWorldCoords(vehicle, 3.5, -4.0, 0.0)
    hospitalStaffPed = CreatePed(4, model, spawn.x, spawn.y, spawn.z, GetEntityHeading(vehicle), false, false)
    SetModelAsNoLongerNeeded(model)
    if not hospitalStaffPed or hospitalStaffPed == 0 then hospitalStaffPed = nil; return end
    SetEntityAsMissionEntity(hospitalStaffPed, true, true)
    SetBlockingOfNonTemporaryEvents(hospitalStaffPed, true)
    SetEntityInvincible(hospitalStaffPed, true)
    TaskGoToEntity(hospitalStaffPed, vehicle, -1, 2.5, 1.2, 1073741824, 0)
end

local function completeHospitalHandoff()
    local vehicle = patientTransportVehicle()
    if not vehicle then return false, 'The patient must be inside the nearby EMS vehicle.' end
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) > 12.0 then
        return false, 'Stay beside the ambulance while hospital staff receive the patient.'
    end
    FreezeEntityPosition(patientPed, false)
    ClearPedTasksImmediately(patientPed)
    TaskLeaveVehicle(patientPed, vehicle, 16)
    local deadline = GetGameTimer() + 1200
    while IsPedInVehicle(patientPed, vehicle, false) and GetGameTimer() < deadline do Wait(50) end
    if IsPedInVehicle(patientPed, vehicle, false) then ClearPedTasksImmediately(patientPed) end
    return true
end

local function escortPatient()
    if not patientPed or not DoesEntityExist(patientPed) or IsPedInAnyVehicle(patientPed, false) then return end
    FreezeEntityPosition(patientPed, false)
    ClearPedTasksImmediately(patientPed)
    TaskFollowToOffsetOfEntity(patientPed, PlayerPedId(), 0.0, -1.15, 0.0, 1.35, -1, 1.2, true)
end

local function unloadPatientFromVehicle()
    if not patientPed or not DoesEntityExist(patientPed) then return end
    FreezeEntityPosition(patientPed, false)
    local vehicle = GetVehiclePedIsIn(patientPed, false)
    if vehicle and vehicle ~= 0 then
        local drop = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -3.2, 0.0)
        ClearPedTasksImmediately(patientPed)
        SetEntityCoordsNoOffset(patientPed, drop.x, drop.y, drop.z, false, false, false)
        SetEntityHeading(patientPed, GetEntityHeading(vehicle))
    end
    escortPatient()
end

local function placePatientOnBed(stage)
    if not patientPed or not DoesEntityExist(patientPed) or type(stage and stage.coords) ~= 'table' then return end
    ClearPedTasksImmediately(patientPed)
    local coords = stage.coords
    SetEntityCoordsNoOffset(patientPed, tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0,
        (tonumber(coords.z) or 0.0) + 0.18, false, false, false)
    SetEntityHeading(patientPed, tonumber(stage.heading) or 0.0)
    local dict = 'anim@gangops@morgue@table@'
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(patientPed, dict, 'body_search', 2.0, -2.0, -1, 1, 0.0, false, false, false)
    end
    FreezeEntityPosition(patientPed, true)
    patientAtBed = true
end

local function clearLocalStageAction()
    currentActionToken = nil
    currentActionRunId = nil
    currentActionStageIndex = nil
end

local function releaseLocalStageAction()
    if currentActionToken and lib and lib.callback then
        pcall(function()
            lib.callback.await('cm-ems:server:cancelMissionStage', false,
                currentActionRunId, currentActionStageIndex, currentActionToken)
        end)
    end
    clearLocalStageAction()
end

local function setObjective(mission)
    activeMission = mission
    cleanupBlip()
    currentStageReady = false
    if not mission or not mission.stage or type(mission.stage.coords) ~= 'table' then return end
    local coords = mission.stage.coords
    missionBlip = AddBlipForCoord(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    SetBlipSprite(missionBlip, 280); SetBlipColour(missionBlip, 3); SetBlipScale(missionBlip, 0.9); SetBlipRoute(missionBlip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(('EMS Mission: %s'):format(tostring(mission.stage.label or mission.label))); EndTextCommandSetBlipName(missionBlip)
    SetNewWaypoint(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0)
    notify(('%s/%s · %s'):format(mission.stageIndex, mission.stageCount, tostring(mission.stage.label or 'Continue mission')), 'inform')
end

RegisterNetEvent('cm-ems:client:startMission', function(mission) cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle(); setObjective(mission) end)
RegisterNetEvent('cm-ems:client:missionUpdated', function(mission)
    if not mission then return end
    -- Participant joins/leaves also refresh the mission payload. Preserve an
    -- objective currently being performed when the run and stage did not change.
    local sameRun = activeMission and tonumber(activeMission.runId) == tonumber(mission.runId)
    local sameStage = sameRun and tonumber(activeMission.stageIndex) == tonumber(mission.stageIndex)
    if not sameStage then
        stageBusy = false
        clearLocalStageAction()
    end
    -- The scene props are local presentation only. Recreate them when the
    -- shared crew advances so every participant sees the same current stage.
    local previousType = sameRun and activeMission.stage and activeMission.stage.type or nil
    if not sameRun then
        cleanupPatient()
        cleanupScenePresentation()
        cleanupMissionVehicle()
    end
    setObjective(mission)
    if (previousType == 'treat' or previousType == 'recover' or previousType == 'pickup_patient')
        and patientPed and DoesEntityExist(patientPed) then
        stabilizePatient()
    end
    if previousType == 'treat' or previousType == 'recover' then cleanupScenePresentation() end
    if (previousType == 'pickup_patient' or previousType == 'escort_patient')
        and mission.stage and (mission.stage.type == 'escort_patient' or mission.stage.type == 'board_vehicle') then
        escortPatient()
    end
    if previousType == 'board_vehicle' and mission.stage and mission.stage.type == 'transport' then loadPatientIntoVehicle() end
    if previousType == 'unload_patient' and mission.stage and mission.stage.type == 'deliver_patient' then unloadPatientFromVehicle() end
end)
RegisterNetEvent('cm-ems:client:missionEnded', function(_, reason)
    activeMission = nil; stageBusy = false; currentStageReady = false; clearLocalStageAction(); cleanupBlip(); dischargePatientPresentation(); cleanupScenePresentation(); cleanupMissionVehicle()
    CMEMSMissionObjectiveReady = false
    if reason then notify(reason, reason:lower():find('complete', 1, true) and 'success' or 'inform') end
end)

RegisterNetEvent('cm-ems:client:npcEmergency', function(call)
    if type(call) ~= 'table' then return end
    notify(('New public emergency: %s · %s. Open /ems > Employee Tasks to accept.'):format(
        tostring(call.label or 'Medical emergency'), tostring(call.location or 'Location pending')), 'inform')
end)

RegisterNUICallback('missionBoard', function(_, cb)
    local board, reason = lib.callback.await('cm-ems:server:missionBoard', false)
    if not board then notify(reason or 'Mission board unavailable.', 'error') end
    if board and board.active then
        local runChanged = not activeMission or tonumber(activeMission.runId) ~= tonumber(board.active.runId)
        local stageChanged = not activeMission or tonumber(activeMission.stageIndex) ~= tonumber(board.active.stageIndex)
        if runChanged or stageChanged then
            stageBusy = false
            clearLocalStageAction()
            cleanupPatient()
            cleanupScenePresentation()
            cleanupMissionVehicle()
            setObjective(board.active)
        end
    elseif board and activeMission then
        activeMission = nil
        stageBusy = false
        currentStageReady = false
        clearLocalStageAction()
        cleanupBlip()
        cleanupPatient()
        cleanupScenePresentation()
        cleanupMissionVehicle()
    end
    cb({ ok = board ~= nil, board = board })
end)

RegisterNUICallback('startMission', function(data, cb)
    local ok, message, mission, board = lib.callback.await('cm-ems:server:startMission', false, data and data.missionId)
    notify(message or (ok and 'Mission started.' or 'Mission could not start.'), ok and 'success' or 'error')
    if ok and mission then
        cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle(); setObjective(mission)
        TriggerEvent('cm-ems:client:closeMenu')
    end
    cb({ ok = ok == true, message = message, mission = mission, board = board })
end)

RegisterNUICallback('acceptPublicIncident', function(data, cb)
    local ok, message, mission, board = lib.callback.await('cm-ems:server:acceptPublicIncident', false, data and data.incidentId)
    notify(message or (ok and 'Emergency accepted.' or 'Emergency is unavailable.'), ok and 'success' or 'error')
    if ok and mission then
        cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle(); setObjective(mission)
        TriggerEvent('cm-ems:client:closeMenu')
    end
    cb({ ok = ok == true, message = message, mission = mission, board = board })
end)

RegisterNUICallback('joinMission', function(data, cb)
    local ok, message, mission, board = lib.callback.await('cm-ems:server:joinMission', false, data and data.runId)
    notify(message or (ok and 'Joined EMS crew.' or 'Could not join crew.'), ok and 'success' or 'error')
    if ok and mission then
        cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle(); setObjective(mission)
        TriggerEvent('cm-ems:client:closeMenu')
    end
    cb({ ok = ok == true, message = message, mission = mission, board = board })
end)

RegisterNUICallback('cancelMission', function(_, cb)
    local ok, message, board = lib.callback.await('cm-ems:server:cancelMission', false)
    notify(message or (ok and 'Mission cancelled.' or 'Could not cancel mission.'), ok and 'success' or 'error')
    if ok then activeMission = nil; cleanupBlip(); cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle() end
    cb({ ok = ok == true, board = board })
end)

RegisterNUICallback('missionAdminList', function(_, cb)
    local rows, reason = lib.callback.await('cm-ems:server:missionAdminList', false)
    if not rows then notify(reason or 'Mission creator is unavailable.', 'error') end
    cb({ ok = rows ~= nil, missions = rows or {} })
end)

RegisterNUICallback('saveAdminMission', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:saveAdminMission', false, data)
    notify(message or (ok and 'Mission saved.' or 'Mission could not be saved.'), ok and 'success' or 'error')
    cb({ ok = ok == true, message = message })
end)

RegisterNUICallback('deleteAdminMission', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:deleteAdminMission', false, data and data.databaseId)
    notify(message or (ok and 'Mission deleted.' or 'Mission could not be deleted.'), ok and 'success' or 'error')
    cb({ ok = ok == true, message = message })
end)

RegisterNUICallback('missionCurrentPosition', function(_, cb)
    local coords = GetEntityCoords(PlayerPedId())
    cb({ ok = true, x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(PlayerPedId()) })
end)

RegisterNUICallback('missionPlaceStage', function(data, cb)
    if missionPlacementActive then return cb({ ok = false }) end
    missionPlacementActive = true
    local stageIndex = math.max(0, math.floor(tonumber(data and data.stageIndex) or 0))
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'mission:placementMode', stageIndex = stageIndex })
    cb({ ok = true })
    CreateThread(function()
        while missionPlacementActive do
            Wait(0)
            SetTextFont(4); SetTextScale(0.42, 0.42); SetTextCentre(true)
            SetTextColour(238, 250, 255, 255)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName('Move to the route point  ~b~[E]~s~ Capture position   ~r~[BACKSPACE]~s~ Cancel')
            EndTextCommandDisplayText(0.5, 0.88)
            if IsControlJustPressed(0, 38) then
                local coords = GetEntityCoords(PlayerPedId())
                missionPlacementActive = false
                SetNuiFocus(true, true)
                SendNUIMessage({
                    action = 'mission:positionCaptured', stageIndex = stageIndex,
                    x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(PlayerPedId()),
                })
            elseif IsControlJustPressed(0, 177) then
                missionPlacementActive = false
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'mission:placementCancelled', stageIndex = stageIndex })
            end
        end
    end)
end)

local function performStage()
    if missionPlacementActive or not activeMission or stageBusy or not currentStageReady then return end
    stageBusy = true
    local stageAtStart = activeMission.stage
    local patientAction = isPatientAction(stageAtStart.type)
    if patientAction and IsPedInAnyVehicle(PlayerPedId(), false) then
        stageBusy = false
        return notify('Exit the vehicle and move beside the patient first.', 'error')
    end
    local ok, message, action = lib.callback.await('cm-ems:server:beginMissionStage', false, activeMission.runId, activeMission.stageIndex)
    if not ok or not action then stageBusy = false; return notify(message or 'Mission action could not begin.', 'error') end
    currentActionToken = action.token
    currentActionRunId = activeMission.runId
    currentActionStageIndex = activeMission.stageIndex
    if stageAtStart.type == 'hospital_handoff' then spawnHospitalStaff() end
    local finished = true
    local duration = math.max(0, tonumber(action.duration) or 0)
    if duration > 0 and lib and lib.progressCircle then
        local animation
        if stageAtStart.type == 'recover' then
            animation = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 }
        elseif stageAtStart.type == 'treat' or stageAtStart.type == 'pickup_patient' then
            animation = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 }
        elseif stageAtStart.type == 'board_vehicle' then
            animation = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 }
        elseif stageAtStart.type == 'unload_patient' or stageAtStart.type == 'hospital_handoff' then
            animation = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 }
        elseif stageAtStart.type == 'deliver_patient' then
            animation = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 }
        end
        finished = lib.progressCircle({
            duration = duration, label = tostring(stageAtStart.label or 'Completing EMS objective...'), position = 'bottom',
            useWhileDead = false, canCancel = true, disable = { move = true, car = true, combat = true },
            anim = animation,
        })
    elseif duration > 0 then
        Wait(duration)
    end
    if not finished then
        releaseLocalStageAction()
        stageBusy = false
        return notify('Mission action cancelled. You can try the objective again.', 'error')
    end
    if stageAtStart.type == 'board_vehicle' then
        local loaded, loadReason = loadPatientIntoVehicle()
        if not loaded then
            releaseLocalStageAction()
            stageBusy = false
            return notify(loadReason or 'The patient could not be loaded.', 'error')
        end
    elseif stageAtStart.type == 'hospital_handoff' then
        local handedOff, handoffReason = completeHospitalHandoff()
        if not handedOff then
            releaseLocalStageAction()
            stageBusy = false
            return notify(handoffReason or 'Hospital handoff could not be completed.', 'error')
        end
    elseif stageAtStart.type == 'deliver_patient' then
        placePatientOnBed(stageAtStart)
        Wait(1500)
    end
    local completed, completeMessage, nextMission, missionFinished = lib.callback.await('cm-ems:server:completeMissionStage', false,
        currentActionRunId, currentActionStageIndex, currentActionToken)
    clearLocalStageAction()
    stageBusy = false
    if not completed then return notify(completeMessage or 'Mission objective was not confirmed.', 'error') end
    if stageAtStart.type == 'hospital_handoff' then cleanupPatient() end
    if stageAtStart.type == 'pickup_patient' or stageAtStart.type == 'escort_patient' then escortPatient() end
    if stageAtStart.type == 'unload_patient' then unloadPatientFromVehicle() end
    if stageAtStart.type == 'treat' or stageAtStart.type == 'recover' or stageAtStart.type == 'pickup_patient' then
        stabilizePatient()
    end
    if stageAtStart.type == 'repair' and missionVehicle and DoesEntityExist(missionVehicle) then
        SetVehicleFixed(missionVehicle); SetVehicleEngineHealth(missionVehicle, 1000.0); SetVehicleDoorShut(missionVehicle, 4, false)
        SetVehicleDoorsLocked(missionVehicle, 2); FreezeEntityPosition(missionVehicle, true)
    end
    notify(completeMessage or 'Mission objective complete.', missionFinished and 'success' or 'inform')
    if missionFinished then
        activeMission = nil; currentStageReady = false; cleanupBlip(); dischargePatientPresentation(); cleanupScenePresentation(); cleanupMissionVehicle()
    elseif nextMission then
        setObjective(nextMission)
    end
end

RegisterCommand('+cm_ems_mission_action', performStage, false)
RegisterCommand('-cm_ems_mission_action', function() end, false)
RegisterKeyMapping('+cm_ems_mission_action', 'EMS mission objective', 'keyboard', 'E')

local function drawPrompt(label)
    DrawRect(0.5, 0.89, 0.36, 0.048, 7, 16, 24, 220)
    DrawRect(0.34, 0.89, 0.034, 0.034, 0, 218, 235, 240)
    SetTextFont(4); SetTextScale(0.32, 0.32); SetTextColour(238, 250, 255, 255); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('~b~E~s~  %s'):format(label)); EndTextCommandDisplayText(0.515, 0.878)
end

-- Shown instead of the [E] prompt when the player is near the objective but
-- something is blocking the interaction (in a vehicle, patient not found
-- yet, still a little too far). Without this, arriving close to the
-- objective and not being able to press anything looked like a dead mission
-- with zero feedback about what to do next.
local function drawHint(label)
    DrawRect(0.5, 0.89, 0.34, 0.040, 15, 20, 26, 190)
    SetTextFont(4); SetTextScale(0.30, 0.30); SetTextColour(210, 220, 230, 230); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(label); EndTextCommandDisplayText(0.5, 0.878)
end

CreateThread(function()
    while true do
        local sleep = 700
        currentStageReady = false
        CMEMSMissionObjectiveReady = false
        if not missionPlacementActive and activeMission and activeMission.stage and type(activeMission.stage.coords) == 'table' then
            if patientPed and not DoesEntityExist(patientPed) then patientPed = nil; patientAtBed = false end
            if missionVehicle and not DoesEntityExist(missionVehicle) then missionVehicle = nil end
            local patientObjective = patientPresentationStage(activeMission)
            if not patientPed and patientObjective and type(patientObjective.coords) == 'table' then
                local patientCoords = vector3(tonumber(patientObjective.coords.x) or 0.0, tonumber(patientObjective.coords.y) or 0.0, tonumber(patientObjective.coords.z) or 0.0)
                local currentType = tostring(activeMission.stage.type or '')
                local needsVehiclePresentation = currentType == 'transport' or currentType == 'unload_patient'
                    or currentType == 'hospital_handoff'
                local canCreatePresentation = not needsVehiclePresentation or nearbyEmsVehicle(20.0) ~= nil
                if canCreatePresentation and #(GetEntityCoords(PlayerPedId()) - patientCoords) < 150.0 then
                    spawnMissionPatient(activeMission)
                    if patientPed and (currentType == 'transport' or currentType == 'unload_patient'
                        or currentType == 'hospital_handoff') then
                        loadPatientIntoVehicle()
                    elseif patientPed and (currentType == 'escort_patient' or currentType == 'board_vehicle'
                        or currentType == 'deliver_patient') then
                        stabilizePatient()
                    end
                end
            end
            if activeMission.stage.spawnVehicle and not missionVehicle then
                local vehicleCoords = vector3(tonumber(activeMission.stage.coords.x) or 0.0, tonumber(activeMission.stage.coords.y) or 0.0, tonumber(activeMission.stage.coords.z) or 0.0)
                if #(GetEntityCoords(PlayerPedId()) - vehicleCoords) < 150.0 then spawnStageVehicle(activeMission.stage) end
            end
            local coords = activeMission.stage.coords
            local playerCoords = GetEntityCoords(PlayerPedId())
            local target = vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
            local distance = #(playerCoords - target)
            local stageType = tostring(activeMission.stage.type or '')
            local patientAction = isPatientAction(stageType)
            local hasPatientPed = patientAction and patientPed and DoesEntityExist(patientPed)
            local patientCoords = hasPatientPed and GetEntityCoords(patientPed) or nil
            local patientDistance = patientCoords and #(playerCoords - patientCoords) or math.huge
            local nearbyPresentation = distance < 80.0 or patientDistance < 35.0
            if nearbyPresentation then
                sleep = 0
                -- For scene treatment/loading, place the marker on the visible NPC,
                -- not a stale authored coordinate. Destination stages still use the
                -- route marker because both patient and medic must reach that point.
                local markerTarget = patientAnchoredStageTypes[stageType] and patientCoords or target
                if markerTarget then
                    DrawMarker(1, markerTarget.x, markerTarget.y, markerTarget.z - 1.0, 0.0,0.0,0.0, 0.0,0.0,0.0,
                        2.2,2.2,0.8, 0,218,235,120, false,false,2,false,nil,nil,false)
                end

                local requiredPatientDistance = 4.5
                local objectiveDistance = patientAction and 8.0 or 7.0
                local inVehicle = patientAction and IsPedInAnyVehicle(PlayerPedId(), false)
                local blockedReason
                if (stageType == 'board_vehicle' or stageType == 'unload_patient' or stageType == 'hospital_handoff')
                    and not nearbyEmsVehicle(12.0) then
                    blockedReason = stageType == 'board_vehicle'
                        and 'Park an EMS vehicle beside the patient' or 'Park the EMS vehicle in the ambulance bay'
                elseif stageType == 'hospital_handoff' and not patientTransportVehicle() then
                    blockedReason = 'The patient must remain inside the EMS vehicle'
                elseif activeMission.stage.requireTransportVehicle == true and stageType ~= 'board_vehicle' then
                    local occupied = GetVehiclePedIsIn(PlayerPedId(), false)
                    if not isAuthorizedEmsVehicle(occupied) then blockedReason = 'Use an authorized EMS vehicle to continue' end
                end

                local patientClose = hasPatientPed and patientDistance <= requiredPatientDistance
                local destinationClose = distance <= objectiveDistance
                local canInteract
                if patientAnchoredStageTypes[stageType] then
                    -- The NPC is authoritative for treatment, pickup and loading.
                    canInteract = patientClose and not inVehicle and not blockedReason
                elseif stageType == 'transport' or stageType == 'hospital_handoff' then
                    canInteract = destinationClose and not blockedReason
                elseif patientAction then
                    -- Escort/unload/delivery must reach the destination together.
                    canInteract = destinationClose and patientClose and not inVehicle and not blockedReason
                else
                    canInteract = destinationClose and not blockedReason
                end

                if canInteract and not stageBusy then
                    currentStageReady = true
                    CMEMSMissionObjectiveReady = true
                    drawPrompt(tostring(activeMission.stage.label or 'Complete EMS objective'))
                    -- Direct input fallback. Some servers already map E to another
                    -- resource (for example the stretcher), which can prevent the
                    -- registered mission key mapping from firing consistently.
                    if IsControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 38) then
                        performStage()
                    end
                elseif not stageBusy and (destinationClose or patientDistance <= 10.0) then
                    if blockedReason then
                        drawHint(blockedReason)
                    elseif inVehicle then
                        drawHint('Exit the vehicle to continue')
                    elseif patientAction and not hasPatientPed then
                        drawHint('Locating patient...')
                    elseif patientAnchoredStageTypes[stageType] and not patientClose then
                        drawHint('Move closer to the patient')
                    elseif patientAction and not destinationClose then
                        drawHint(('Take the patient to %s'):format(tostring(activeMission.stage.location or 'the marked location')))
                    elseif patientAction and not patientClose then
                        drawHint('Wait for the patient to come closer')
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(1500)
        if activeMission and activeMission.stage
            and (activeMission.stage.type == 'escort_patient' or activeMission.stage.type == 'deliver_patient')
            and patientPed and DoesEntityExist(patientPed) and not IsPedInAnyVehicle(patientPed, false) then
            local playerPed = PlayerPedId()
            local separation = #(GetEntityCoords(playerPed) - GetEntityCoords(patientPed))
            -- NPC pathing can fail across hospital doors, stairs or custom MLO
            -- transitions. Only use a catch-up teleport after a large separation
            -- so normal walking remains visible during ordinary escort gameplay.
            if separation > 18.0 and not IsPedInAnyVehicle(playerPed, false) then
                local catchUp = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, -1.6, 0.0)
                RequestCollisionAtCoord(catchUp.x, catchUp.y, catchUp.z)
                SetEntityCoordsNoOffset(patientPed, catchUp.x, catchUp.y, catchUp.z, false, false, false)
                placePedOnOutdoorGround(patientPed, catchUp)
                SetEntityHeading(patientPed, GetEntityHeading(playerPed))
                separation = #(GetEntityCoords(playerPed) - GetEntityCoords(patientPed))
            end
            if separation > 1.8 then escortPatient() end
        end
    end
end)

AddStateBagChangeHandler('cmEms', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    if activeMission and (type(value) ~= 'table' or value.onDuty ~= true) then
        activeMission = nil; stageBusy = false; clearLocalStageAction(); cleanupBlip(); cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupBlip(); cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle(); clearLocalStageAction()
    missionPlacementActive = false
    CMEMSMissionObjectiveReady = false
end)

-- ============================================================
--  Daily mission NPC -- admin-placed dispatcher ped, one random
--  high-reward mission per character per calendar day. Interacting
--  starts a normal mission run through the exact same engine as the
--  mission board above (setObjective renders blips/stage prompts) --
--  the daily gate itself is entirely server-side.
-- ============================================================

local dailyNpcLocation
local dailyNpcPed, dailyNpcBlip = nil, nil

local function spawnDailyMissionNpc()
    if not dailyNpcLocation then return end
    if dailyNpcPed and DoesEntityExist(dailyNpcPed) then DeleteEntity(dailyNpcPed) end
    if dailyNpcBlip and DoesBlipExist(dailyNpcBlip) then RemoveBlip(dailyNpcBlip) end

    local hash = GetHashKey(((Config.EMSMissions or {}).dailyNpcMission or {}).npcModel or 's_m_m_paramedic_01')
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return end

    dailyNpcPed = CreatePed(4, hash, dailyNpcLocation.x, dailyNpcLocation.y, dailyNpcLocation.z - 1.0, dailyNpcLocation.heading or 0.0, false, false)
    SetEntityInvincible(dailyNpcPed, true)
    FreezeEntityPosition(dailyNpcPed, true)
    SetBlockingOfNonTemporaryEvents(dailyNpcPed, true)
    TaskStartScenarioInPlace(dailyNpcPed, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(hash)

    dailyNpcBlip = AddBlipForCoord(dailyNpcLocation.x, dailyNpcLocation.y, dailyNpcLocation.z)
    SetBlipSprite(dailyNpcBlip, 61)
    SetBlipColour(dailyNpcBlip, 2)
    SetBlipAsShortRange(dailyNpcBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('EMS Dispatch Coordinator')
    EndTextCommandSetBlipName(dailyNpcBlip)
end

CreateThread(function()
    dailyNpcLocation = lib.callback.await('cm-ems:server:dailyMissionNpcLocation', false)
    spawnDailyMissionNpc()
end)

RegisterNetEvent('cm-ems:client:dailyMissionNpcUpdated', function(location)
    dailyNpcLocation = location
    spawnDailyMissionNpc()
end)

local function requestDailyMission()
    local ok, message, mission = lib.callback.await('cm-ems:server:requestDailyMission', false)
    notify(message or (ok and 'Daily mission assigned.' or 'Could not start daily mission.'), ok and 'success' or 'error')
    if ok and mission then
        cleanupPatient(); cleanupScenePresentation(); cleanupMissionVehicle(); setObjective(mission)
    end
end

CreateThread(function()
    while true do
        local wait = 1000
        if dailyNpcLocation then
            local coords = GetEntityCoords(PlayerPedId())
            local interactDistance = ((Config.EMSMissions or {}).dailyNpcMission or {}).interactDistance or 2.5
            local dist = #(coords - vector3(dailyNpcLocation.x, dailyNpcLocation.y, dailyNpcLocation.z))
            if dist <= interactDistance then
                wait = 0
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to request your daily EMS mission.')
                EndTextCommandDisplayHelp(0, false, false, 1)
                if IsControlJustPressed(0, 38) then requestDailyMission() end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if dailyNpcPed and DoesEntityExist(dailyNpcPed) then DeleteEntity(dailyNpcPed) end
    if dailyNpcBlip and DoesBlipExist(dailyNpcBlip) then RemoveBlip(dailyNpcBlip) end
end)
