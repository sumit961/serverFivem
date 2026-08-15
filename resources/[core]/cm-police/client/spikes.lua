-- cm-police spike strips (client). Deploy/recall are officer-only commands,
-- but the tire-burst detection thread at the bottom runs for EVERY player
-- (matches the reference module's own shape) -- each driver's own client
-- detects contact with a tagged strip and bursts its OWN vehicle's tires
-- only. There is no server-authoritative collision detection anywhere in
-- this codebase to build on top of instead.

local function notify(message, kind)
    PoliceNotify(message, kind)
end

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
            TriggerServerEvent('cm-police:server:spikeStripDeployed', stripId,
                finalCoords.x, finalCoords.y, finalCoords.z, finalHeading)
            notify('Spike strip placement requested.', 'inform')
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
    local removed = lib.callback.await('cm-police:server:recallSpikeStrips', false)
    notify(('Recalled %d spike strip(s).'):format(tonumber(removed) or 0), 'success')
end

RegisterCommand('policespike', PoliceDeploySpike, false)
RegisterCommand('recallspikes', PoliceRecallSpikes, false)

RegisterNetEvent('cm-police:client:removeSpikeStrip', function(netId)
    local object = NetworkGetEntityFromNetworkId(netId)
    if object and object ~= 0 and DoesEntityExist(object) then
        DeleteEntity(object)
    end
end)

RegisterNetEvent('cm-law:client:deleteSceneEquipment', function(payload)
    if type(payload) ~= 'table' or payload.equipmentType ~= 'spike' then return end
    local deploymentId, netId = tonumber(payload.deploymentId), tonumber(payload.networkId)
    if not deploymentId or not netId then return end
    local object, resolveDeadline = 0, GetGameTimer() + 3000
    repeat
        object = NetworkGetEntityFromNetworkId(netId)
        if object ~= 0 and DoesEntityExist(object) then break end
        Wait(50)
    until GetGameTimer() >= resolveDeadline
    if object == 0 or not DoesEntityExist(object) then return end
    local state = Entity(object).state
    if tonumber(state.cmLawSceneEquipment) ~= deploymentId or state.cmSpikeStrip ~= true then return end
    local deadline = GetGameTimer() + 5000
    while DoesEntityExist(object) and not NetworkHasControlOfEntity(object) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(object)
        Wait(50)
    end
    if not DoesEntityExist(object) or not NetworkHasControlOfEntity(object) then return end
    for _ = 1, 4 do
        SetEntityAsMissionEntity(object, true, true)
        DeleteObject(object)
        if not DoesEntityExist(object) then
            TriggerServerEvent('cm-law:server:sceneEquipmentDeleteResult', deploymentId, netId, 'spike')
            return
        end
        DeleteEntity(object)
        if not DoesEntityExist(object) then
            TriggerServerEvent('cm-law:server:sceneEquipmentDeleteResult', deploymentId, netId, 'spike')
            return
        end
        Wait(50)
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
