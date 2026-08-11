-- Lightweight, server-authoritative EMS stretcher transport.

local Stretchers = {}
local StretcherSequence = 0
local PendingAmbulanceLoads = {}

local function stretcherNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function authorized(src)
    local characterId = cid(tonumber(src))
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, 'ems.treat_player') then
        return nil, characterId
    end
    return member, tostring(characterId)
end

local function distanceBetween(a, b)
    return #(GetEntityCoords(a) - GetEntityCoords(b))
end

local function entityFor(state)
    return state and state.entity and DoesEntityExist(state.entity) and state.entity or nil
end

local function publicState(state, viewerSrc)
    return {
        id = state.id, netId = state.netId, carrier = state.carrier,
        patient = state.patient, vehicleNetId = state.vehicleNetId,
        isOwner = viewerSrc ~= nil and tonumber(state.ownerSource) == tonumber(viewerSrc),
    }
end

local function ownedStretcher(characterId)
    for _, state in pairs(Stretchers) do
        if tostring(state.ownerCharacterId or '') == tostring(characterId or '') then return state end
    end
end

local function broadcastState(state, removed)
    for _, player in ipairs(GetPlayers()) do
        local target = tonumber(player)
        TriggerClientEvent('cm-ems:client:stretcherState', target, state.id,
            removed and nil or publicState(state, target))
    end
end

local function nearestStretcher(src, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local best, bestDistance
    for _, state in pairs(Stretchers) do
        local entity = entityFor(state)
        if entity and GetEntityRoutingBucket(entity) == GetPlayerRoutingBucket(src) then
            local distance = distanceBetween(ped, entity)
            if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                best, bestDistance = state, distance
            end
        end
    end
    return best, bestDistance
end

local function validAmbulance(netId)
    netId = tonumber(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return nil end
    local model = GetEntityModel(vehicle)
    for _, allowed in ipairs((Config.Stretcher or {}).allowedVehicles or { 'ambulance' }) do
        if model == joaat(tostring(allowed)) then return vehicle end
    end
end

lib.callback.register('cm-ems:server:stretcherSync', function(src)
    local rows = {}
    for id, state in pairs(Stretchers) do rows[id] = publicState(state, src) end
    return rows
end)

lib.callback.register('cm-ems:server:toggleStretcher', function(src, coords, heading)
    if (Config.Stretcher or {}).enabled == false then return false, 'Stretchers are disabled.' end
    local _, characterId = authorized(src)
    if not rateLimit(src, 'toggle_stretcher', 1200) or not characterId then return false, 'You must be an on-duty EMS medic.' end
    local nearby = nearestStretcher(src, tonumber((Config.Stretcher or {}).maxDeployDistance) or 3.0)
    if nearby then
        if tostring(nearby.ownerCharacterId or '') ~= characterId then return false, 'That stretcher belongs to another medic.' end
        if nearby.carrier or nearby.patient or nearby.vehicleNetId then return false, 'Release and empty the stretcher before storing it.' end
        local entity = entityFor(nearby)
        Stretchers[nearby.id] = nil
        broadcastState(nearby, true)
        if entity then DeleteEntity(entity) end
        return true, 'Stretcher stored.', 'stored'
    end
    if ownedStretcher(characterId) then
        return false, 'You already have a stretcher deployed. Move near it or use /emsreturnstretcher.'
    end
    if type(coords) ~= 'table' then return false, 'Invalid deployment position.' end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    local ped = GetPlayerPed(src)
    if not x or not y or not z or not ped or ped == 0 then return false, 'Invalid deployment position.' end
    if #(GetEntityCoords(ped) - vector3(x, y, z)) > 4.0 then return false, 'Deployment position is too far away.' end
    local entity = CreateObjectNoOffset(joaat(tostring((Config.Stretcher or {}).model or 'v_med_bed2')), x, y, z, true, true, false)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false, 'The stretcher could not be deployed.' end
    SetEntityHeading(entity, tonumber(heading) or 0.0)
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    FreezeEntityPosition(entity, true)
    StretcherSequence = StretcherSequence + 1
    local state = {
        id = StretcherSequence, entity = entity, netId = NetworkGetNetworkIdFromEntity(entity),
        ownerCharacterId = characterId, ownerSource = tonumber(src),
    }
    Stretchers[state.id] = state
    broadcastState(state)
    return true, 'Stretcher deployed.', 'deployed', publicState(state, src)
end)

lib.callback.register('cm-ems:server:returnOwnedStretcher', function(src)
    local _, characterId = authorized(src)
    if not rateLimit(src, 'return_owned_stretcher', 2000) or not characterId then
        return false, 'You must be an on-duty EMS medic.'
    end
    local state = ownedStretcher(characterId)
    if not state then return false, 'You do not have a deployed stretcher.' end
    if state.patient then return false, 'Remove the patient before returning this stretcher.' end
    if state.carrier then return false, 'Release the stretcher before returning it.' end
    if state.vehicleNetId then return false, 'Unload the stretcher before returning it.' end
    local entity = entityFor(state)
    Stretchers[state.id] = nil
    broadcastState(state, true)
    if entity then DeleteEntity(entity) end
    return true, 'Your empty stretcher was returned.'
end)

lib.callback.register('cm-ems:server:useStretcher', function(src, stretcherId, action, vehicleNetId)
    if not rateLimit(src, 'use_stretcher', 500) or not authorized(src) then return false, 'You must be an on-duty EMS medic.' end
    local state = Stretchers[tonumber(stretcherId)]
    local entity = entityFor(state)
    if not state or not entity then return false, 'That stretcher is unavailable.' end
    if GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(src) then return false, 'That stretcher is unavailable.' end
    local maxDistance = tonumber((Config.Stretcher or {}).vehicleDistance) or 5.0
    if distanceBetween(GetPlayerPed(src), entity) > maxDistance then return false, 'Move closer to the stretcher.' end
    action = tostring(action or '')
    if action == 'grab' then
        if state.carrier or state.vehicleNetId then return false, 'That stretcher is already in use.' end
        state.carrier = src
        FreezeEntityPosition(entity, false)
    elseif action == 'release' then
        if state.carrier ~= src then return false, 'You are not pushing this stretcher.' end
        state.carrier = nil
        FreezeEntityPosition(entity, true)
    elseif action == 'load' then
        if state.carrier ~= src then return false, 'Push the stretcher before loading it.' end
        local vehicle = validAmbulance(vehicleNetId)
        if not vehicle or distanceBetween(GetPlayerPed(src), vehicle) > maxDistance then return false, 'Move to the rear of an ambulance.' end
        if GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then return false, 'That ambulance is unavailable.' end
        state.carrier, state.vehicleNetId = nil, tonumber(vehicleNetId)
        FreezeEntityPosition(entity, false)
    elseif action == 'unload' then
        local vehicle = validAmbulance(state.vehicleNetId)
        if not vehicle or distanceBetween(GetPlayerPed(src), vehicle) > maxDistance then return false, 'Move closer to the ambulance.' end
        state.vehicleNetId, state.carrier = nil, src
        FreezeEntityPosition(entity, false)
    else
        return false, 'Invalid stretcher action.'
    end
    broadcastState(state)
    return true, action == 'load' and 'Patient loaded into the ambulance.' or action == 'unload' and 'Stretcher unloaded.' or action == 'grab' and 'You are pushing the stretcher.' or 'Stretcher released.', publicState(state, src)
end)

AddEventHandler('cm-ems:server:stretcherAction', function(medicSrc, targetSrc, action)
    if action ~= 'ems_stretcher_place' and action ~= 'ems_stretcher_remove'
        and action ~= 'ems_ambulance_load' and action ~= 'ems_ambulance_unload' and action ~= 'ems_safe_treatment'
        and action ~= 'ems_hospital_admit' then return end
    medicSrc, targetSrc = tonumber(medicSrc), tonumber(targetSrc)
    if not medicSrc or not targetSrc or not authorized(medicSrc) then return end
    local maxDistance = tonumber((Config.Stretcher or {}).patientDistance) or 4.0
    if GetPlayerRoutingBucket(medicSrc) ~= GetPlayerRoutingBucket(targetSrc) then return end
    local medicPed, targetPed = GetPlayerPed(medicSrc), GetPlayerPed(targetSrc)
    if not medicPed or medicPed == 0 or not targetPed or targetPed == 0
        or distanceBetween(medicPed, targetPed) > maxDistance then
        return stretcherNotify(medicSrc, 'Move closer to the patient.', 'error')
    end
    if action == 'ems_safe_treatment' then
        local isDead = false
        pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(targetSrc) == true end)
        if not isDead or IsPedInAnyVehicle(targetPed, false) then
            return stretcherNotify(medicSrc, 'Unload the unconscious patient before safe-area treatment.', 'error')
        end
        local safeVehicle
        for _, vehicle in ipairs(GetAllVehicles()) do
            if vehicle ~= 0 and validAmbulance(NetworkGetNetworkIdFromEntity(vehicle))
                and GetEntityRoutingBucket(vehicle) == GetPlayerRoutingBucket(medicSrc)
                and distanceBetween(medicPed, vehicle) <= 10.0
                and GetEntitySpeed(vehicle) <= 0.75 then safeVehicle = vehicle; break end
        end
        if not safeVehicle then
            return stretcherNotify(medicSrc, 'Park an EMS ambulance nearby before treating at this safe area.', 'error')
        end
        TriggerClientEvent('cm-ems:client:beginSafeTreatment', medicSrc, targetSrc)
        return
    elseif action == 'ems_hospital_admit' then
        local vehicle = GetVehiclePedIsIn(targetPed, false)
        if not vehicle or vehicle == 0 or not validAmbulance(NetworkGetNetworkIdFromEntity(vehicle)) then
            return stretcherNotify(medicSrc, 'The patient must be inside an ambulance.', 'error')
        end
        local selected, vehicleCoords = nil, GetEntityCoords(vehicle)
        local radius = tonumber((Config.HospitalAdmissions or {}).bayRadius) or 22.0
        for _, hospital in ipairs((Config.HospitalAdmissions or {}).hospitals or {}) do
            local bay = hospital.bay or {}
            if bay.x and #(vehicleCoords - vector3(bay.x, bay.y, bay.z)) <= radius then selected = hospital; break end
        end
        if not selected then return stretcherNotify(medicSrc, 'Park the ambulance inside a hospital admission bay.', 'error') end
        local isDead = false
        pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(targetSrc) == true end)
        if not isDead then return stretcherNotify(medicSrc, 'That patient does not require emergency admission.', 'error') end
        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        local incidentId = EMSLinkTreatmentToDispatch and EMSLinkTreatmentToDispatch(medicSrc, targetSrc) or nil
        if EMSUpdatePatientTransport then EMSUpdatePatientTransport(targetSrc, vehicleNetId, 'at_hospital') end
        local healed = false
        pcall(function() healed = exports[Config.PlayerDataResource]:Heal(targetSrc, 100, 'ems_hospital_admission') == true end)
        if not healed then return stretcherNotify(medicSrc, 'Hospital admission could not be completed.', 'error') end
        local bed = selected.bed or {}
        TriggerClientEvent('cm-ems:client:hospitalAdmitted', targetSrc, bed, selected.label)
        pcall(function() exports['cm-ems']:AwardMedicReward(medicSrc, targetSrc, 'ems_hospital_admission_reward') end)
        local patientCid = cid(targetSrc)
        if EMSAddTaskProgress and patientCid then
            local info, deathCount = nil, 0
            pcall(function() info = exports[Config.PlayerDataResource]:GetDeathInfo(targetSrc) end)
            deathCount = tonumber(info and info.deathCount) or 0
            EMSAddTaskProgress(cid(medicSrc), 'patient_revives', 1,
                ('patient:%s:death:%d'):format(patientCid, deathCount))
        end
        TriggerEvent('cm-ems:server:recordMedicalEvent', targetSrc, {
            event = 'ems_hospital_admission', incidentId = incidentId, medicSource = medicSrc,
            hospitalId = selected.id, location = selected.label,
            treatment = 'Emergency ambulance admission and hospital stabilization',
            outcome = 'admitted',
        })
        log(cid(medicSrc), 'patient_admitted', { patientCid = patientCid, hospitalId = selected.id, incidentId = incidentId })
        stretcherNotify(medicSrc, ('Patient admitted to %s.'):format(selected.label), 'success')
        return
    elseif action == 'ems_ambulance_unload' then
        local vehicle = GetVehiclePedIsIn(targetPed, false)
        if not vehicle or vehicle == 0 or not validAmbulance(NetworkGetNetworkIdFromEntity(vehicle)) then
            return stretcherNotify(medicSrc, 'That patient is not inside an EMS ambulance.', 'error')
        end
        if GetEntitySpeed(vehicle) > 0.75 then
            return stretcherNotify(medicSrc, 'Stop the ambulance before removing the patient.', 'error')
        end
        if distanceBetween(medicPed, vehicle) > maxDistance + 2.0 then
            return stretcherNotify(medicSrc, 'Move closer to the ambulance.', 'error')
        end
        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        TriggerClientEvent('cm-ems:client:removeFromAmbulance', targetSrc, vehicleNetId)
        if EMSUpdatePatientTransport then EMSUpdatePatientTransport(targetSrc, vehicleNetId, 'on_scene') end
        stretcherNotify(medicSrc, 'Patient removed from the ambulance.', 'success')
        return
    elseif action == 'ems_ambulance_load' then
        if (Config.Patch or {}).allowDirectAmbulanceLoad ~= true then return end
        local isDead = false
        pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(targetSrc) == true end)
        if not isDead then return stretcherNotify(medicSrc, 'Only an unconscious player can be loaded.', 'error') end
        if IsPedInAnyVehicle(targetPed, false) then return stretcherNotify(medicSrc, 'That patient is already in a vehicle.', 'error') end
        for _, candidate in pairs(Stretchers) do
            if candidate.patient == targetSrc then
                return stretcherNotify(medicSrc, 'Remove the patient from the stretcher before direct loading.', 'error')
            end
        end
        local loadDistance = math.max(3.0, tonumber((Config.Patch or {}).ambulanceLoadDistance) or 6.0)
        local bestVehicle, bestDistance
        for _, vehicle in ipairs(GetAllVehicles()) do
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
                and GetEntityRoutingBucket(vehicle) == GetPlayerRoutingBucket(medicSrc) then
                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                if validAmbulance(netId) then
                    local distance = distanceBetween(medicPed, vehicle)
                    if distance <= loadDistance and (not bestDistance or distance < bestDistance) then
                        bestVehicle, bestDistance = vehicle, distance
                    end
                end
            end
        end
        if not bestVehicle then return stretcherNotify(medicSrc, 'Move the patient closer to an ambulance.', 'error') end
        local seat
        for index = GetVehicleMaxNumberOfPassengers(bestVehicle) - 1, 0, -1 do
            if GetPedInVehicleSeat(bestVehicle, index) == 0 then seat = index; break end
        end
        if seat == nil then return stretcherNotify(medicSrc, 'The ambulance has no free passenger seat.', 'error') end
        local vehicleNetId = NetworkGetNetworkIdFromEntity(bestVehicle)
        PendingAmbulanceLoads[targetSrc] = {
            medic = medicSrc, vehicleNetId = vehicleNetId, seat = seat,
            expires = GetGameTimer() + 3000,
        }
        TriggerClientEvent('cm-ems:client:loadIntoAmbulance', targetSrc, vehicleNetId, seat)
        return
    end
    local state = nearestStretcher(targetSrc, maxDistance)
    if action == 'ems_stretcher_place' then
        if not state then return stretcherNotify(medicSrc, 'Move an empty stretcher closer to the patient.', 'error') end
        if state.patient then return stretcherNotify(medicSrc, 'That stretcher already has a patient.', 'error') end
        local isDead = false
        pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(targetSrc) == true end)
        if not isDead then return stretcherNotify(medicSrc, 'Only an unconscious player can be placed on a stretcher.', 'error') end
        state.patient = targetSrc
        broadcastState(state)
        stretcherNotify(medicSrc, 'Patient secured on the stretcher.', 'success')
        stretcherNotify(targetSrc, 'EMS placed you on a stretcher.', 'inform')
    else
        for _, candidate in pairs(Stretchers) do
            if candidate.patient == targetSrc then
                candidate.patient = nil
                broadcastState(candidate)
                stretcherNotify(medicSrc, 'Patient removed from the stretcher.', 'success')
                stretcherNotify(targetSrc, 'EMS removed you from the stretcher.', 'inform')
                return
            end
        end
        stretcherNotify(medicSrc, 'That player is not on a stretcher.', 'error')
    end
end)

RegisterNetEvent('cm-ems:server:ambulanceSeatResult', function(vehicleNetId, success)
    local targetSrc = tonumber(source)
    local pending = PendingAmbulanceLoads[targetSrc]
    PendingAmbulanceLoads[targetSrc] = nil
    if not pending or GetGameTimer() > pending.expires
        or tonumber(vehicleNetId) ~= tonumber(pending.vehicleNetId) then return end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId))
    local targetPed = GetPlayerPed(targetSrc)
    local seated = success == true and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
        and targetPed and targetPed ~= 0 and GetVehiclePedIsIn(targetPed, false) == vehicle
        and GetPedInVehicleSeat(vehicle, tonumber(pending.seat)) == targetPed
    if not seated then
        return stretcherNotify(pending.medic, 'The patient could not be seated in the ambulance.', 'error')
    end
    if EMSUpdatePatientTransport then EMSUpdatePatientTransport(targetSrc, vehicleNetId, 'transporting') end
    stretcherNotify(pending.medic, 'Patient loaded into the ambulance.', 'success')
    stretcherNotify(targetSrc, 'EMS loaded you into an ambulance.', 'inform')
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    PendingAmbulanceLoads[src] = nil
    for targetSrc, pending in pairs(PendingAmbulanceLoads) do
        if tonumber(pending.medic) == src then PendingAmbulanceLoads[targetSrc] = nil end
    end
    for id, state in pairs(Stretchers) do
        local entity = entityFor(state)
        if tonumber(state.carrier) == src then
            state.carrier = nil
            if entity then FreezeEntityPosition(entity, true) end
            broadcastState(state)
        end
        if tonumber(state.patient) == src then
            state.patient = nil
            broadcastState(state)
        end
        if tonumber(state.ownerSource) == src and not state.carrier and not state.patient and not state.vehicleNetId then
            Stretchers[id] = nil
            broadcastState(state, true)
            if entity then DeleteEntity(entity) end
        end
    end
end)

AddEventHandler('cm-ems:server:memberWentOffDuty', function(src, characterId)
    src = tonumber(src)
    characterId = tostring(characterId or '')
    for targetSrc, pending in pairs(PendingAmbulanceLoads) do
        if tonumber(pending.medic) == src then PendingAmbulanceLoads[targetSrc] = nil end
    end
    for id, state in pairs(Stretchers) do
        local owned = tostring(state.ownerCharacterId or '') == characterId
        local patient = tonumber(state.patient)
        if tonumber(state.carrier) == src then state.carrier = nil end
        if tonumber(state.patient) == src then state.patient = nil end
        if owned then
            state.patient, state.carrier, state.vehicleNetId = nil, nil, nil
            Stretchers[id] = nil
            broadcastState(state, true)
            local entity = entityFor(state)
            if entity then DeleteEntity(entity) end
            if patient and GetPlayerName(patient) then
                stretcherNotify(patient, 'The stretcher was released because the medic left duty.', 'inform')
            end
        else
            local entity = entityFor(state)
            if entity and not state.carrier and not state.vehicleNetId then FreezeEntityPosition(entity, true) end
            broadcastState(state)
        end
    end
end)

AddEventHandler('cm-playerdata:server:ambulanceResolved', function(src)
    src = tonumber(src)
    for _, state in pairs(Stretchers) do
        if state.patient == src then state.patient = nil; broadcastState(state) end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for targetSrc, pending in pairs(PendingAmbulanceLoads) do
            if now > (tonumber(pending.expires) or 0) then PendingAmbulanceLoads[targetSrc] = nil end
        end
        for id, state in pairs(Stretchers) do
            local changed = false
            if not entityFor(state) then
                Stretchers[id] = nil
                broadcastState(state, true)
            else
                if state.carrier and (not GetPlayerName(state.carrier) or not authorized(state.carrier)) then state.carrier = nil; changed = true end
                if state.ownerSource and not GetPlayerName(state.ownerSource) then state.ownerSource = nil end
                if state.vehicleNetId and not validAmbulance(state.vehicleNetId) then state.vehicleNetId = nil; changed = true end
                if state.patient then
                    local dead = false
                    if GetPlayerName(state.patient) then pcall(function() dead = exports[Config.PlayerDataResource]:IsDead(state.patient) == true end) end
                    if not dead then state.patient = nil; changed = true end
                end
                if changed then
                    if not state.carrier and not state.vehicleNetId then FreezeEntityPosition(state.entity, true) end
                    broadcastState(state)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, state in pairs(Stretchers) do
        local entity = entityFor(state)
        if entity then DeleteEntity(entity) end
    end
end)
