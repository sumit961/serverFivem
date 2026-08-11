-- Simple stretcher controls: J deploy/store, E push/release/load/unload.

local stretcherStates = {}
local currentUse
local localPatientStretcher
local localCarrierStretcher
local deployBusy = false
local pushAnimDict = 'anim@heists@box_carry@'
local pushAnimName = 'idle'
local pushBlocked = false
local pushGroundSamples = {}
local pushGroundSampleAt = 0
local pushGroundStretcherId

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'EMS Stretcher', description = message, type = kind or 'inform' }) end
end

RegisterNetEvent('cm-ems:client:loadIntoAmbulance', function(vehicleNetId, seat)
    vehicleNetId, seat = tonumber(vehicleNetId), tonumber(seat)
    if not vehicleNetId or seat == nil then return end
    local timeout = GetGameTimer() + 2500
    while not NetworkDoesEntityExistWithNetworkId(vehicleNetId) and GetGameTimer() < timeout do Wait(50) end
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return TriggerServerEvent('cm-ems:server:ambulanceSeatResult', vehicleNetId, false)
    end
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, seat)
    Wait(250)
    TriggerServerEvent('cm-ems:server:ambulanceSeatResult', vehicleNetId,
        GetVehiclePedIsIn(PlayerPedId(), false) == vehicle and GetPedInVehicleSeat(vehicle, seat) == PlayerPedId())
end)

RegisterNetEvent('cm-ems:client:removeFromAmbulance', function(vehicleNetId)
    vehicleNetId = tonumber(vehicleNetId)
    local vehicle = vehicleNetId and NetworkGetEntityFromNetworkId(vehicleNetId) or 0
    local ped = PlayerPedId()
    if vehicle == 0 or GetVehiclePedIsIn(ped, false) ~= vehicle then return end
    TaskLeaveVehicle(ped, vehicle, 16)
end)

RegisterNetEvent('cm-ems:client:hospitalAdmitted', function(bed, hospitalLabel)
    bed = type(bed) == 'table' and bed or {}
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 then TaskLeaveVehicle(ped, vehicle, 16); Wait(900) end
    if bed.x and bed.y and bed.z then
        SetEntityCoords(ped, bed.x + 0.0, bed.y + 0.0, bed.z + 0.0, false, false, false, false)
        SetEntityHeading(ped, tonumber(bed.h) or 0.0)
    end
    if lib and lib.notify then
        lib.notify({ title = 'Hospital Admission', description = ('You were admitted to %s and stabilized.'):format(tostring(hospitalLabel or 'hospital')), type = 'success' })
    end
end)

local function eligible()
    local member = LocalPlayer.state.cmEms
    return type(member) == 'table' and member.onDuty == true
        and (member.isLeader == true or (member.permissions or {})['ems.treat_player'] == true)
        and (Config.Stretcher or {}).enabled ~= false
end

local function entityFromState(state)
    local netId = state and tonumber(state.netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
    local entity = NetToObj(netId)
    return entity ~= 0 and DoesEntityExist(entity) and entity or nil
end

local function requestControl(entity)
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local deadline = GetGameTimer() + 800
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do Wait(0); NetworkRequestControlOfEntity(entity) end
    return NetworkHasControlOfEntity(entity)
end

local function offset(name, defaults)
    local raw = ((Config.Stretcher or {})[name]) or {}
    return tonumber(raw.x) or defaults[1], tonumber(raw.y) or defaults[2], tonumber(raw.z) or defaults[3],
        tonumber(raw.rx) or defaults[4], tonumber(raw.ry) or defaults[5], tonumber(raw.rz) or defaults[6]
end

local function stopPushAnimation()
    if not localCarrierStretcher then return end
    StopAnimTask(PlayerPedId(), pushAnimDict, pushAnimName, 1.5)
    localCarrierStretcher = nil
    pushGroundSamples = {}
    pushGroundSampleAt = 0
    pushGroundStretcherId = nil
end

local function ensurePushAnimation(state)
    if tonumber(state.carrier) ~= GetPlayerServerId(PlayerId()) then
        if localCarrierStretcher == state.id then stopPushAnimation() end
        return
    end
    localCarrierStretcher = state.id
    RequestAnimDict(pushAnimDict)
    if HasAnimDictLoaded(pushAnimDict)
        and not IsEntityPlayingAnim(PlayerPedId(), pushAnimDict, pushAnimName, 3) then
        TaskPlayAnim(PlayerPedId(), pushAnimDict, pushAnimName, 4.0, 4.0, -1, 49, 0.0, false, false, false)
    end
end

local function applyState(state)
    local object = entityFromState(state)
    if not object then return end
    SetEntityCollision(object, true, true)
    if state.vehicleNetId and NetworkDoesNetworkIdExist(tonumber(state.vehicleNetId)) then
        requestControl(object)
        FreezeEntityPosition(object, false)
        local vehicle = NetToVeh(tonumber(state.vehicleNetId))
        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            local x,y,z,rx,ry,rz = offset('vehicleOffset', {0.0,-1.25,0.15,0.0,0.0,0.0})
            AttachEntityToEntity(object, vehicle, 0, x,y,z,rx,ry,rz, false,false,true,false,2,true)
        end
    elseif state.carrier then
        -- Only the assigned carrier may mutate the networked stretcher while
        -- it is being pushed. Other clients render its synchronized position
        -- without repeatedly stealing control and causing vertical jitter.
        if tonumber(state.carrier) == GetPlayerServerId(PlayerId()) and requestControl(object) then
            FreezeEntityPosition(object, false)
            if IsEntityAttached(object) then DetachEntity(object, true, true) end
        end
    else
        requestControl(object)
        if IsEntityAttached(object) then DetachEntity(object, true, true) end
        PlaceObjectOnGroundProperly(object)
        FreezeEntityPosition(object, true)
    end
    ensurePushAnimation(state)

    local myServerId = GetPlayerServerId(PlayerId())
    if tonumber(state.patient) == myServerId then
        local ped = PlayerPedId()
        local x,y,z,rx,ry,rz = offset('patientOffset', {0.0,0.0,0.78,0.0,0.0,90.0})
        AttachEntityToEntity(ped, object, 0, x,y,z,rx,ry,rz, false,false,false,false,2,true)
        RequestAnimDict('anim@gangops@morgue@table@')
        local deadline = GetGameTimer() + 1500
        while not HasAnimDictLoaded('anim@gangops@morgue@table@') and GetGameTimer() < deadline do Wait(0) end
        if HasAnimDictLoaded('anim@gangops@morgue@table@') then TaskPlayAnim(ped, 'anim@gangops@morgue@table@', 'body_search', 4.0, -4.0, -1, 1, 0.0, false, false, false) end
        localPatientStretcher = state.id
    elseif localPatientStretcher == state.id then
        DetachEntity(PlayerPedId(), true, false)
        ClearPedTasks(PlayerPedId())
        localPatientStretcher = nil
    end
end

RegisterNetEvent('cm-ems:client:stretcherState', function(id, state)
    id = tonumber(id)
    local old = stretcherStates[id]
    if not state then
        if localCarrierStretcher == id then stopPushAnimation() end
        if localPatientStretcher == id then DetachEntity(PlayerPedId(), true, false); ClearPedTasks(PlayerPedId()); localPatientStretcher = nil end
        stretcherStates[id] = nil
        return
    end
    state.id = tonumber(state.id) or id
    stretcherStates[id] = state
    applyState(state)
end)

local function nearestState(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance
    for _, state in pairs(stretcherStates) do
        local object = entityFromState(state)
        if object then
            local distance = #(coords - GetEntityCoords(object))
            if distance <= maxDistance and (not bestDistance or distance < bestDistance) then best, bestDistance = state, distance end
        end
    end
    return best
end

local function nearestAmbulance(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local allowed = {}
    for _, model in ipairs((Config.Stretcher or {}).allowedVehicles or { 'ambulance' }) do allowed[joaat(tostring(model))] = true end
    local best, bestDistance
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if allowed[GetEntityModel(vehicle)] then
            local distance = #(coords - GetEntityCoords(vehicle))
            if distance <= maxDistance and (not bestDistance or distance < bestDistance) then best, bestDistance = vehicle, distance end
        end
    end
    return best
end

RegisterCommand('cm_ems_stretcher_deploy', function()
    if deployBusy or not eligible() or LocalPlayer.state.isDead == true then return end
    deployBusy = true
    local model = joaat(tostring((Config.Stretcher or {}).model or 'v_med_bed2'))
    if not IsModelInCdimage(model) or not IsModelValid(model) then
        deployBusy = false
        return notify('The configured stretcher model is invalid.', 'error')
    end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then
        deployBusy = false
        return notify('The stretcher model could not be loaded.', 'error')
    end
    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.8, 0.0)
    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
    if foundGround then coords = vector3(coords.x, coords.y, groundZ + 0.05) end
    local ok, message = lib.callback.await('cm-ems:server:toggleStretcher', false,
        { x = coords.x, y = coords.y, z = coords.z }, GetEntityHeading(ped))
    SetModelAsNoLongerNeeded(model)
    deployBusy = false
    notify(message or (ok and 'Done.' or 'Stretcher action failed.'), ok and 'success' or 'error')
end, false)

RegisterCommand(tostring((Config.Stretcher or {}).returnCommand or 'emsreturnstretcher'), function()
    if deployBusy or not eligible() then return end
    deployBusy = true
    local ok, message = lib.callback.await('cm-ems:server:returnOwnedStretcher', false)
    deployBusy = false
    notify(message or (ok and 'Stretcher returned.' or 'Could not return stretcher.'), ok and 'success' or 'error')
end, false)

RegisterCommand('+cm_ems_stretcher_use', function()
    if not currentUse then return end
    local vehicleNetId
    if currentUse.vehicle then vehicleNetId = VehToNet(currentUse.vehicle) end
    local ok, message = lib.callback.await('cm-ems:server:useStretcher', false, currentUse.state.id, currentUse.action, vehicleNetId)
    if ok then
        PlaySoundFrontend(-1, currentUse.action == 'release' and 'BACK' or 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
    notify(message or (ok and 'Done.' or 'Stretcher action failed.'), ok and 'success' or 'error')
end, false)
RegisterCommand('-cm_ems_stretcher_use', function() end, false)
RegisterKeyMapping('+cm_ems_stretcher_use', 'EMS: Use stretcher', 'keyboard', tostring((Config.Stretcher or {}).interactKey or 'E'))

local function drawPrompt(label)
    DrawRect(0.5, 0.89, 0.29, 0.046, 7, 16, 24, 210)
    DrawRect(0.37, 0.89, 0.032, 0.032, 0, 218, 235, 235)
    SetTextFont(4); SetTextScale(0.32, 0.32); SetTextColour(238, 250, 255, 255); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('~b~E~s~  %s'):format(label)); EndTextCommandDisplayText(0.51, 0.878)
end

local function stretcherStatus(state)
    local ownership = state.isOwner and 'YOUR STRETCHER' or 'EMS STRETCHER'
    if state.patient then return ownership .. ' · PATIENT SECURED' end
    if state.vehicleNetId then return ownership .. ' · IN AMBULANCE' end
    if state.carrier then return ownership .. ' · IN USE' end
    return ownership .. ' · EMPTY'
end

local function obstacleAhead()
    local ped = PlayerPedId()
    local start = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.45, 0.45)
    local finish = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.75, 0.45)
    local probe = StartShapeTestCapsule(start.x, start.y, start.z, finish.x, finish.y, finish.z, 0.32, 1, ped, 7)
    for _ = 1, 5 do
        local status, hit = GetShapeTestResult(probe)
        if status == 2 then return hit == 1 end
        Wait(0)
    end
    return false
end

local function movePushedStretcher()
    local state = localCarrierStretcher and stretcherStates[localCarrierStretcher]
    if not state or tonumber(state.carrier) ~= GetPlayerServerId(PlayerId()) then return false end
    if pushGroundStretcherId ~= state.id then
        pushGroundStretcherId = state.id
        pushGroundSamples = {}
        pushGroundSampleAt = 0
    end
    local object = entityFromState(state)
    if not object or not requestControl(object) then return false end

    local ped = PlayerPedId()
    local distance = tonumber((Config.Stretcher or {}).pushDistance) or 1.35
    local clearance = tonumber((Config.Stretcher or {}).pushGroundClearance) or 0.03
    local headingOffset = tonumber((Config.Stretcher or {}).pushHeadingOffset) or 180.0
    local target = GetOffsetFromEntityInWorldCoords(ped, 0.0, distance, 0.0)
    local objectCoords = GetEntityCoords(object)
    local groundZ = objectCoords.z
    local now = GetGameTimer()
    if now >= pushGroundSampleAt then
        local foundGround, sampledGround = GetGroundZFor_3dCoord(target.x, target.y, target.z + 1.5, false)
        if foundGround then
        local minimum = GetModelDimensions(GetEntityModel(object))
            pushGroundSamples[#pushGroundSamples + 1] = sampledGround - minimum.z + clearance
            if #pushGroundSamples > 3 then table.remove(pushGroundSamples, 1) end
        end
        pushGroundSampleAt = now + 150
    end
    if #pushGroundSamples > 0 then
        -- The lowest recent result is the terrain. A higher alternating
        -- result can be the stretcher/patient itself and caused rapid bounce.
        groundZ = pushGroundSamples[1]
        for index = 2, #pushGroundSamples do
            if pushGroundSamples[index] < groundZ then groundZ = pushGroundSamples[index] end
        end
        local delta = groundZ - objectCoords.z
        local maximumStep = 0.035
        groundZ = objectCoords.z + math.max(-maximumStep, math.min(maximumStep, delta))
    end

    if IsEntityAttached(object) then DetachEntity(object, true, true) end
    SetEntityNoCollisionEntity(object, ped, false)
    SetEntityNoCollisionEntity(ped, object, false)
    SetEntityCoordsNoOffset(object, target.x, target.y, groundZ, false, false, false)
    SetEntityHeading(object, GetEntityHeading(ped) + headingOffset)
    return true
end

CreateThread(function()
    local synced = lib.callback.await('cm-ems:server:stretcherSync', false) or {}
    for _, state in pairs(synced) do stretcherStates[tonumber(state.id)] = state; applyState(state) end
    while true do
        local sleep = 700
        currentUse = nil
        if eligible() and LocalPlayer.state.isDead ~= true and CMEMSMissionObjectiveReady ~= true then
            local state = nearestState(tonumber((Config.Stretcher or {}).interactDistance) or 2.6)
            if state then
                sleep = 0
                local myId = GetPlayerServerId(PlayerId())
                if tonumber(state.carrier) == myId then
                    local vehicle = nearestAmbulance(tonumber((Config.Stretcher or {}).vehicleDistance) or 5.0)
                    currentUse = { state = state, action = vehicle and 'load' or 'release', vehicle = vehicle }
                    drawPrompt(vehicle and 'Load stretcher into ambulance' or 'Release stretcher')
                elseif state.vehicleNetId then
                    currentUse = { state = state, action = 'unload' }
                    drawPrompt('Unload stretcher from ambulance')
                elseif not state.carrier then
                    currentUse = { state = state, action = 'grab' }
                    drawPrompt('Push stretcher')
                end
                SetTextFont(4); SetTextScale(0.29, 0.29); SetTextColour(210, 246, 255, 235); SetTextCentre(true)
                BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(stretcherStatus(state)); EndTextCommandDisplayText(0.5, 0.915)
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if localCarrierStretcher then
            Wait(0)
            local state = stretcherStates[localCarrierStretcher]
            if not state or tonumber(state.carrier) ~= GetPlayerServerId(PlayerId()) then
                stopPushAnimation()
            else
                ensurePushAnimation(state)
                movePushedStretcher()
                DisableControlAction(0, 21, true) -- sprint
                DisableControlAction(0, 22, true) -- jump
                DisableControlAction(0, 24, true) -- attack
                DisableControlAction(0, 25, true) -- aim
                if pushBlocked then DisableControlAction(0, 32, true) end -- forward into wall
            end
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if localCarrierStretcher then
            pushBlocked = obstacleAhead()
            Wait(100)
        else
            pushBlocked = false
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1500)
        for _, state in pairs(stretcherStates) do applyState(state) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopPushAnimation()
    if localPatientStretcher then DetachEntity(PlayerPedId(), true, false); ClearPedTasks(PlayerPedId()) end
end)
