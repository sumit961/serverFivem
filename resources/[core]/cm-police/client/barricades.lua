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
            local confirmed, payload = lib.callback.await('cm-police:server:confirmBarricade', false, barricadeId,
                finalCoords.x, finalCoords.y, finalCoords.z, finalHeading, finalModelName)
            if confirmed and type(payload) == 'table' then
                notify('Barricade deployed.', 'success')
            else
                notify(tostring(payload or 'Barricade deployment was not registered by the server.'), 'error')
            end
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
    local removed, failed = lib.callback.await('cm-police:server:recallBarricades', false)
    removed, failed = tonumber(removed) or 0, tonumber(failed) or 0
    if failed > 0 then
        notify(('Removed %d barricade(s); %d could not be removed yet. Try again while near the barricade.'):format(removed, failed), 'error')
        return
    end
    if removed == 0 and PoliceRecoverOwnedSceneEquipment then
        local recovered = PoliceRecoverOwnedSceneEquipment('barricade')
        if recovered > 0 then
            notify(('Recovered and removed %d tracked barricade(s).'):format(recovered), 'success')
            return
        end
    end
    notify(('Recalled %d barricade(s).'):format(removed), removed > 0 and 'success' or 'inform')
end

RegisterCommand('policebarricade', PoliceDeployBarricade, false)
RegisterCommand('recallbarricades', PoliceRecallBarricades, false)

local function barricadePayloadMatches(object, payload)
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
    local typeTag = state.cmBarricade
    if typeTag ~= nil and typeTag ~= true then return false end
    return true
end

local function deleteBarricadeNetworkObject(netId, payload)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return false end

    local object, resolveDeadline = 0, GetGameTimer() + 3000
    repeat
        object = NetworkGetEntityFromNetworkId(netId)
        if object ~= 0 and DoesEntityExist(object) then break end
        Wait(50)
    until GetGameTimer() >= resolveDeadline

    if object == 0 or not DoesEntityExist(object) then return true end
    if payload and not barricadePayloadMatches(object, payload) then return false end

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

RegisterNetEvent('cm-police:client:removeBarricade', function(netId)
    deleteBarricadeNetworkObject(netId, nil)
end)

RegisterNetEvent('cm-law:client:deleteSceneEquipment', function(payload)
    if type(payload) ~= 'table' or payload.equipmentType ~= 'barricade' then return end
    local deploymentId, netId = tonumber(payload.deploymentId), tonumber(payload.networkId)
    if not deploymentId or not netId then return end

    if deleteBarricadeNetworkObject(netId, payload) then
        TriggerServerEvent('cm-law:server:sceneEquipmentDeleteResult', deploymentId, netId, 'barricade', payload.cleanupToken)
    end
end)

-- Remove orphan barricades from older builds once per client resource start.
CreateThread(function()
    Wait(5000)
    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local state = Entity(object).state
            if state.cmBarricade == true and state.cmLawSceneEquipment == nil then
                local netId = NetworkGetNetworkIdFromEntity(object)
                if netId and netId > 0 then deleteBarricadeNetworkObject(netId, nil) end
            end
        end
    end
end)
