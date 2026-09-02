-- cm-police spike strips (client). Deploy/recall are officer-only commands,
-- but the tire-burst detection thread at the bottom runs for EVERY player
-- (matches the reference module's own shape) -- each driver's own client
-- detects contact with a tagged strip and bursts its OWN vehicle's tires
-- only. There is no server-authoritative collision detection anywhere in
-- this codebase to build on top of instead.

local function notify(message, kind)
    PoliceNotify(message, kind)
end

local OwnedSceneEquipment = {} -- [deploymentId] = authoritative server registration payload

local function localCharacterId()
    local police = LocalPlayer.state.cmPolice
    if type(police) == 'table' and police.characterId then return tostring(police.characterId) end
    local legal = LocalPlayer.state.cmLegalOrg
    if type(legal) == 'table' and legal.characterId then return tostring(legal.characterId) end
    return nil
end

RegisterNetEvent('cm-law:client:sceneEquipmentRegistered', function(payload)
    if type(payload) ~= 'table' or not payload.deploymentId or not payload.networkId then return end
    OwnedSceneEquipment[tonumber(payload.deploymentId)] = payload

    -- CREATE_OBJECT_NO_OFFSET is a server setter: the entity can be registered
    -- before this client owns/streams it. Once it resolves locally, apply the
    -- intended heading/frozen state. This is visual initialization only; the
    -- server remains authoritative for deployment and deletion.
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        local object = 0
        repeat
            object = NetworkGetEntityFromNetworkId(tonumber(payload.networkId) or 0)
            if object ~= 0 and DoesEntityExist(object) then break end
            Wait(50)
        until GetGameTimer() >= deadline

        if object ~= 0 and DoesEntityExist(object) then
            local state = Entity(object).state
            if tonumber(state.cmLawSceneEquipment) == tonumber(payload.deploymentId) then
                if tonumber(payload.heading) then SetEntityHeading(object, tonumber(payload.heading) + 0.0) end
                FreezeEntityPosition(object, true)
            end
        end
    end)
end)

local function canUseSpike()
    local state = LocalPlayer.state.cmPolice
    if type(state) == 'table' and state.onDuty == true then
        local permissions = state.permissions or {}
        return state.isLeader == true or permissions['police.spike'] == true
    end
    state = LocalPlayer.state.cmLegalOrg
    local permissions = type(state) == 'table' and state.permissions or {}
    return type(state) == 'table' and state.onDuty == true
        and (state.isLeader == true or permissions['law.spike'] == true)
end

-- Global (not local) so client/quickmenu.lua's J-key menu can call these
-- without duplicating logic -- the chat commands below are thin wrappers
-- around the same functions. Placement itself (moving/rotating the preview,
-- confirm/cancel/timeout) is shared with barricades via
-- client/placement.lua's PoliceBeginObjectPlacement -- this function only
-- owns the spike-specific reservation and final-object creation.
function PoliceDeploySpike()
    if PoliceIsPlacing() then return end
    if not canUseSpike() then return notify('You must be an on-duty officer with spike strip permission.', 'error') end
    local ok, result = lib.callback.await('cm-police:server:deploySpikeStrip', false)
    if not ok then return notify(result or 'Could not deploy spike strip.', 'error') end
    local stripId = result

    -- Matches the server's own reservation grace period exactly
    -- (Config.SpikeStrips.PlacementTimeoutMs) -- without this, the server
    -- could free the reservation while the officer was still positioning,
    -- and a late E-press would then deploy a real, networked strip the
    -- server no longer tracks (permanently un-recallable).
    -- PoliceIsPlacing() was already checked above, so the only way this can
    -- refuse to start is the model failing to load -- which already runs
    -- onCancel('model_failed') itself, releasing the reservation. Nothing
    -- else to do with the return value here.
    PoliceBeginObjectPlacement({
        model = Config.SpikeStrips.Model,
        startDistance = Config.SpikeStrips.DeployDistance or 3.0,
        timeoutMs = Config.SpikeStrips.PlacementTimeoutMs or 45000,
        onConfirm = function(finalCoords, finalHeading)
            local confirmed, payload = lib.callback.await('cm-police:server:confirmSpikeStrip', false, stripId,
                finalCoords.x, finalCoords.y, finalCoords.z, finalHeading)
            if confirmed and type(payload) == 'table' then
                OwnedSceneEquipment[tonumber(payload.deploymentId)] = payload
                notify('Spike strip deployed.', 'success')
            else
                notify(tostring(payload or 'Spike strip deployment was not registered by the server.'), 'error')
            end
        end,
        onCancel = function(reason)
            TriggerServerEvent('cm-police:server:cancelSpikeStrip', stripId)
            if reason == 'timeout' then notify('Spike strip placement timed out.', 'error')
            elseif reason == 'model_failed' then notify('Spike strip model failed to load.', 'error')
            else notify('Spike strip placement cancelled.', 'inform') end
        end,
    })
end

function PoliceRecallSpikes()
    local removed, failed = lib.callback.await('cm-police:server:recallSpikeStrips', false)
    removed, failed = tonumber(removed) or 0, tonumber(failed) or 0
    if failed > 0 then
        notify(('Removed %d spike strip(s); %d could not be removed yet. Try again while near the strip.'):format(removed, failed), 'error')
        return
    end
    if removed == 0 and PoliceRecoverOwnedSceneEquipment then
        local recovered = PoliceRecoverOwnedSceneEquipment('spike')
        if recovered > 0 then
            notify(('Recovered and removed %d tracked spike strip(s).'):format(recovered), 'success')
            return
        end
    end
    notify(('Recalled %d spike strip(s).'):format(removed), removed > 0 and 'success' or 'inform')
end

RegisterCommand('policespike', PoliceDeploySpike, false)
RegisterCommand('recallspikes', PoliceRecallSpikes, false)

RegisterCommand('cmsceneversion', function()
    local state = lib.callback.await('cm-police:server:sceneEquipmentState', false)
    if type(state) ~= 'table' then
        print('[cm-scene] cm-law scene equipment authority did not answer.')
        return
    end
    print(('[cm-scene] version=%s spikes=%s barricades=%s'):format(
        tostring(state.version or 'unknown'), tostring(state.spike or 0), tostring(state.barricade or 0)))
end, false)

local function scenePayloadMatches(object, payload, stateKey)
    if object == 0 or not DoesEntityExist(object) then return false end
    local deploymentId = tonumber(payload.deploymentId)
    local modelHash = tonumber(payload.modelHash)
    if modelHash and GetEntityModel(object) ~= modelHash then return false end
    if type(payload.coords) == 'table' then
        local expected = vector3(tonumber(payload.coords.x) or 0.0, tonumber(payload.coords.y) or 0.0, tonumber(payload.coords.z) or 0.0)
        if #(GetEntityCoords(object) - expected) > 4.5 then return false end
    end
    local state = Entity(object).state
    local deploymentTag = state.cmLawSceneEquipment
    if deploymentTag ~= nil and deploymentId and tonumber(deploymentTag) ~= deploymentId then return false end
    local typeTag = state[stateKey]
    if typeTag ~= nil and typeTag ~= true then return false end
    return true
end

local function deleteNetworkObject(netId, payload, stateKey)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return false end

    local object, resolveDeadline = 0, GetGameTimer() + 3000
    repeat
        object = NetworkGetEntityFromNetworkId(netId)
        if object ~= 0 and DoesEntityExist(object) then break end
        Wait(50)
    until GetGameTimer() >= resolveDeadline

    -- If this client no longer sees the network object, the server will make
    -- the final authoritative decision. Reporting success simply asks it to
    -- re-check the stored network id.
    if object == 0 or not DoesEntityExist(object) then return true end
    if payload and not scenePayloadMatches(object, payload, stateKey) then return false end

    local controlDeadline = GetGameTimer() + 5000
    while DoesEntityExist(object) and not NetworkHasControlOfEntity(object) and GetGameTimer() < controlDeadline do
        NetworkRequestControlOfNetworkId(netId)
        NetworkRequestControlOfEntity(object)
        Wait(50)
    end

    if DoesEntityExist(object) and NetworkHasControlOfEntity(object) then
        for _ = 1, 6 do
            SetEntityAsMissionEntity(object, true, true)
            DeleteObject(object)
            if DoesEntityExist(object) then DeleteEntity(object) end
            Wait(50)
            if not DoesEntityExist(object) then return true end
        end
    end

    return not DoesEntityExist(object)
end

-- Recovery path for a scene object whose in-memory server registry was lost.
-- It can ONLY touch replicated objects whose owner CID matches this character;
-- model-only world deletion is deliberately forbidden.
function PoliceRecoverOwnedSceneEquipment(kind)
    local cid = localCharacterId()
    if not cid then return 0 end
    local removed = 0
    local stateKey = kind == 'barricade' and 'cmBarricade' or 'cmSpikeStrip'
    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local state = Entity(object).state
            if state[stateKey] == true
                and tostring(state.cmLawSceneOwnerCid or '') == cid
                and tostring(state.cmLawSceneType or kind) == kind then
                local netId = NetworkGetNetworkIdFromEntity(object)
                if netId and netId > 0 and deleteNetworkObject(netId, nil, stateKey) then
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

RegisterNetEvent('cm-police:client:removeSpikeStrip', function(netId)
    deleteNetworkObject(netId, nil, 'cmSpikeStrip')
end)

RegisterNetEvent('cm-law:client:deleteSceneEquipment', function(payload)
    if type(payload) ~= 'table' or payload.equipmentType ~= 'spike' then return end
    local deploymentId, netId = tonumber(payload.deploymentId), tonumber(payload.networkId)
    if not deploymentId or not netId then return end

    if deleteNetworkObject(netId, payload, 'cmSpikeStrip') then
        TriggerServerEvent('cm-law:server:sceneEquipmentDeleteResult', deploymentId, netId, 'spike', payload.cleanupToken)
    end
end)

-- One-time migration cleanup for orphan strips created by older scene-equipment
-- builds that tagged cmSpikeStrip but had no cmLawSceneEquipment deployment id.
-- New tracked strips are never touched by this sweep.
CreateThread(function()
    Wait(5000)
    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local state = Entity(object).state
            if state.cmSpikeStrip == true and state.cmLawSceneEquipment == nil then
                local netId = NetworkGetNetworkIdFromEntity(object)
                if netId and netId > 0 then deleteNetworkObject(netId, nil, 'cmSpikeStrip') end
            end
        end
    end
end)

-- Standard GTA5 wheel-bone-to-tyre-index mapping for a 4-wheel vehicle
-- (indices 2/3 belong to a 6-wheel vehicle's middle axle, not used here).
local wheelTyreIndex = { wheel_lf = 0, wheel_rf = 1, wheel_lr = 4, wheel_rr = 5 }

CreateThread(function()
    while true do
        Wait(250)
        local ped = PlayerPedId()
        local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            local vehCoords = GetEntityCoords(vehicle)
            for _, object in ipairs(GetGamePool('CObject')) do
                if DoesEntityExist(object) then
                    local isStrip = false
                    pcall(function() isStrip = Entity(object).state.cmSpikeStrip == true end)
                    if isStrip then
                        local stripCoords = GetEntityCoords(object)
                        if #(vehCoords - stripCoords) <= 3.0 then
                            for boneName, tyreIndex in pairs(wheelTyreIndex) do
                                local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
                                if boneIndex ~= -1 then
                                    local boneCoords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
                                    if #(boneCoords - stripCoords) <= (Config.SpikeStrips.BurstDistance or 0.6) then
                                        SetVehicleTyreBurst(vehicle, tyreIndex, true, 1000.0)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else
            Wait(750)
        end
    end
end)
