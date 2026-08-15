-- cm-police barricades (client). Deploy/recall are officer-only commands,
-- same shape as client/spikes.lua's own deploy/recall pair, but placement
-- itself is shared with spikes via client/placement.lua's
-- PoliceBeginObjectPlacement. Unlike a spike strip, the final object keeps
-- normal collision -- once frozen in place, blocking vehicle movement is
-- just ordinary GTA physics, no custom detection thread needed.

local function notify(message, kind)
    PoliceNotify(message, kind)
end

local function canUseBarricade()
    local state = LocalPlayer.state.cmPolice
    if type(state) == 'table' and state.onDuty == true then
        local permissions = state.permissions or {}
        return state.isLeader == true or permissions['police.barricade'] == true
    end
    state = LocalPlayer.state.cmLegalOrg
    local permissions = type(state) == 'table' and state.permissions or {}
    return type(state) == 'table' and state.onDuty == true
        and (state.isLeader == true or permissions['law.barricade'] == true)
end

-- Admin-managed catalog (server/barricades.lua), fetched once at resource
-- start and kept live via the update event -- deploy can happen before the
-- F7 dashboard has ever fetched/shown it. List of model-name strings.
local BarricadeCatalog = {}

local function catalogModelNames()
    local names = {}
    for _, entry in ipairs(BarricadeCatalog) do names[#names + 1] = entry.modelName end
    return names
end

CreateThread(function()
    local list = lib.callback.await('cm-police:server:barricadeCatalogList', false)
    if type(list) == 'table' then BarricadeCatalog = list end
end)

RegisterNetEvent('cm-police:client:barricadeCatalogUpdated', function(list)
    if type(list) == 'table' then BarricadeCatalog = list end
end)

function PoliceDeployBarricade()
    if PoliceIsPlacing() then return end
    if not canUseBarricade() then return notify('You must be an on-duty officer with barricade permission.', 'error') end
    local modelNames = catalogModelNames()
    if #modelNames == 0 then return notify('An admin has not added any barricade models yet.', 'error') end
    local ok, result = lib.callback.await('cm-police:server:deployBarricade', false)
    if not ok then return notify(result or 'Could not deploy barricade.', 'error') end
    local barricadeId = result

    PoliceBeginObjectPlacement({
        models = modelNames,
        startDistance = Config.Barricades.DeployDistance or 3.0,
        timeoutMs = Config.Barricades.PlacementTimeoutMs or 45000,
        onConfirm = function(finalCoords, finalHeading, finalModelName)
            TriggerServerEvent('cm-police:server:barricadeDeployed', barricadeId,
                finalCoords.x, finalCoords.y, finalCoords.z, finalHeading, finalModelName)
            notify('Barricade placement requested.', 'inform')
        end,
        onCancel = function(reason)
            TriggerServerEvent('cm-police:server:cancelBarricade', barricadeId)
            if reason == 'timeout' then notify('Barricade placement timed out.', 'error')
            elseif reason == 'model_failed' then notify('Barricade model failed to load.', 'error')
            else notify('Barricade placement cancelled.', 'inform') end
        end,
    })
end

function PoliceRecallBarricades()
    local removed = lib.callback.await('cm-police:server:recallBarricades', false)
    notify(('Recalled %d barricade(s).'):format(tonumber(removed) or 0), 'success')
end

RegisterCommand('policebarricade', PoliceDeployBarricade, false)
RegisterCommand('recallbarricades', PoliceRecallBarricades, false)

RegisterNetEvent('cm-police:client:removeBarricade', function(netId)
    local object = NetworkGetEntityFromNetworkId(netId)
    if object and object ~= 0 and DoesEntityExist(object) then
        DeleteEntity(object)
    end
end)

RegisterNetEvent('cm-law:client:deleteSceneEquipment', function(payload)
    if type(payload) ~= 'table' or payload.equipmentType ~= 'barricade' then return end
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
    if tonumber(state.cmLawSceneEquipment) ~= deploymentId or state.cmBarricade ~= true then return end
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
            TriggerServerEvent('cm-law:server:sceneEquipmentDeleteResult', deploymentId, netId, 'barricade')
            return
        end
        DeleteEntity(object)
        if not DoesEntityExist(object) then
            TriggerServerEvent('cm-law:server:sceneEquipmentDeleteResult', deploymentId, netId, 'barricade')
            return
        end
        Wait(50)
    end
end)
