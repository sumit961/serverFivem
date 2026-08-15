-- Generic law scene equipment authority. Public cm-police:* contracts are
-- intentionally retained so existing Police clients remain compatible.
local deployments, counts, nextId = {}, {}, 0
local TYPES = {
    spike = { capability = 'spikes', lawPermission = 'law.spike', policePermission = 'police.spike',
        model = 'p_ld_stinger_s', max = 3, placementMs = 45000, lifetimeMs = 120000, state = 'cmSpikeStrip' },
    barricade = { capability = 'barricades', lawPermission = 'law.barricade', policePermission = 'police.barricade',
        max = 2, placementMs = 45000, lifetimeMs = 1800000, state = 'cmBarricade' },
}

local function countKey(cid, kind) return tostring(cid) .. ':' .. kind end
local function validNumber(value, limit)
    value = tonumber(value)
    return value and value == value and math.abs(value) <= limit and value or nil
end

local function authority(src, kind)
    local cfg, characterId = TYPES[kind], characterIdFor(src)
    if not cfg or not characterId then return nil end
    local legal = activeMemberForSource(src)
    if legal then
        if legal.suspended or not legal.onDuty or not LawCapabilityEnabled(legal.organizationId, cfg.capability)
            or not (legal.isLeader or legal.permissions[cfg.lawPermission] == true) then return nil end
        return tostring(characterId), legal.organizationId
    end
    if GetResourceState('cm-police') ~= 'started' then return nil end
    local ok, police = pcall(function() return exports['cm-police']:GetMember(characterId) end)
    local permitted = false
    pcall(function() permitted = exports['cm-police']:HasPermission(characterId, cfg.policePermission) == true end)
    if not ok or type(police) ~= 'table' or police.suspended == true or police.onDuty ~= true or not permitted then return nil end
    return tostring(characterId), 'police'
end

local function deleteDeployment(entry)
    local entity = entry.networkId and NetworkGetEntityFromNetworkId(entry.networkId) or 0
    if entity ~= 0 and DoesEntityExist(entity) then
        local state = Entity(entity).state
        if tonumber(state.cmLawSceneEquipment) == tonumber(entry.deploymentId)
            and state[TYPES[entry.equipmentType].state] == true then
            for _ = 1, 4 do
                DeleteEntity(entity)
                if not DoesEntityExist(entity) then return true end
                Wait(50)
            end
        end
    end
    local cleanup = { deploymentId = entry.deploymentId, equipmentType = entry.equipmentType,
        networkId = entry.networkId }
    for _ = 1, 3 do
        TriggerClientEvent('cm-law:client:deleteSceneEquipment', -1, cleanup)
        -- Clients may need up to three seconds to resolve the network ID and
        -- five more to obtain control before deletion. Keep the server-side
        -- deletion window open long enough to accept that acknowledgement.
        for _ = 1, 90 do
            Wait(100)
            if entry.clientDeleteConfirmed == true then return true end
            entity = NetworkGetEntityFromNetworkId(entry.networkId)
            if entity ~= 0 and not DoesEntityExist(entity) then return true end
        end
    end
    -- A zero server handle can mean the networked object is currently out of
    -- server scope, not that it was deleted. Keep the authoritative record
    -- unless server deletion or a validated client acknowledgement proved it.
    return false
end

RegisterNetEvent('cm-law:server:sceneEquipmentDeleteResult', function(deploymentId, networkId, equipmentType)
    local entry = deployments[tonumber(deploymentId)]
    if not entry or not entry.deleting or tonumber(networkId) ~= tonumber(entry.networkId)
        or tostring(equipmentType or '') ~= entry.equipmentType then return end
    if GetPlayerRoutingBucket(source) ~= entry.routingBucket then return end
    entry.clientDeleteConfirmed = true
end)

local function clearEntry(id)
    local entry = deployments[id]
    if not entry then return true end
    if entry.deleting then return false end
    entry.deleting = true
    if not deleteDeployment(entry) then
        entry.deleting = nil
        return false
    end
    deployments[id] = nil
    local key = countKey(entry.officerCid, entry.equipmentType)
    counts[key] = math.max(0, (counts[key] or 1) - 1)
    return true
end

local function reserve(src, kind)
    if not rateLimit(src, 'law_scene_' .. kind, 1500) then return false, 'Please wait.' end
    local characterId, orgId = authority(src, kind)
    if not characterId then return false, 'You are not authorized to deploy this equipment.' end
    local cfg, key = TYPES[kind], countKey(characterId, kind)
    if (counts[key] or 0) >= cfg.max then return false, ('Maximum active %s equipment reached.'):format(kind) end
    nextId = nextId + 1
    counts[key] = (counts[key] or 0) + 1
    deployments[nextId] = { deploymentId = nextId, equipmentType = kind, organizationId = orgId,
        officerCid = characterId, officerSource = src, networkId = nil,
        routingBucket = GetPlayerRoutingBucket(src), createdAt = os.time(),
        expiresAt = os.time() + math.ceil(cfg.placementMs / 1000) }
    return true, nextId
end

local function approvedBarricade(model)
    return MySQL.scalar.await('SELECT 1 FROM cm_police_barricade_catalog WHERE model_name = ? LIMIT 1', { model }) ~= nil
end

local function confirm(src, id, kind, x, y, z, heading, model)
    local entry, cfg = deployments[tonumber(id)], TYPES[kind]
    local characterId, orgId = authority(src, kind)
    x, y, z, heading = validNumber(x, 10000), validNumber(y, 10000), validNumber(z, 2500), validNumber(heading, 100000) or 0
    if not entry or entry.equipmentType ~= kind or entry.networkId or not characterId
        or entry.officerCid ~= characterId or entry.organizationId ~= orgId or not x or not y or not z then return end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(x, y, z)) > 7.0 then return end
    model = kind == 'spike' and cfg.model or tostring(model or '')
    if kind == 'barricade' and not approvedBarricade(model) then return end
    local entity = CreateObject(GetHashKey(model), x, y, z, true, true, false)
    if entity == 0 or not DoesEntityExist(entity) then return clearEntry(entry.deploymentId) end
    SetEntityHeading(entity, heading % 360); FreezeEntityPosition(entity, true)
    SetEntityRoutingBucket(entity, entry.routingBucket)
    Entity(entity).state:set(cfg.state, true, true)
    Entity(entity).state:set('cmLawSceneEquipment', entry.deploymentId, true)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId <= 0 then DeleteEntity(entity); return clearEntry(entry.deploymentId) end
    entry.networkId, entry.expiresAt = netId, os.time() + math.floor(cfg.lifetimeMs / 1000)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', src,
        kind == 'spike' and 'Spike strip deployed.' or 'Barricade deployed.', 'success')
end

local function cancel(src, id, kind)
    local entry = deployments[tonumber(id)]
    local characterId = characterIdFor(src)
    if entry and entry.equipmentType == kind and not entry.networkId and tostring(characterId or '') == entry.officerCid then clearEntry(entry.deploymentId) end
end

local function recall(src, kind)
    local characterId = characterIdFor(src)
    if not characterId then return 0 end
    local removed = 0
    for id, entry in pairs(deployments) do
        if entry.equipmentType == kind and entry.officerCid == tostring(characterId) and clearEntry(id) then removed = removed + 1 end
    end
    return removed
end

lib.callback.register('cm-police:server:deploySpikeStrip', function(src) return reserve(src, 'spike') end)
lib.callback.register('cm-police:server:deployBarricade', function(src) return reserve(src, 'barricade') end)
lib.callback.register('cm-police:server:recallSpikeStrips', function(src) return recall(src, 'spike') end)
lib.callback.register('cm-police:server:recallBarricades', function(src) return recall(src, 'barricade') end)
RegisterNetEvent('cm-police:server:spikeStripDeployed', function(id,x,y,z,h) confirm(source,id,'spike',x,y,z,h) end)
RegisterNetEvent('cm-police:server:barricadeDeployed', function(id,x,y,z,h,model) confirm(source,id,'barricade',x,y,z,h,model) end)
RegisterNetEvent('cm-police:server:cancelSpikeStrip', function(id) cancel(source,id,'spike') end)
RegisterNetEvent('cm-police:server:cancelBarricade', function(id) cancel(source,id,'barricade') end)

local function cleanupOfficer(characterId)
    characterId = tostring(characterId or '')
    for id, entry in pairs(deployments) do if entry.officerCid == characterId then clearEntry(id) end end
end
AddEventHandler('cm-police:server:memberWentOffDuty', function(_, cid) cleanupOfficer(cid) end)
AddEventHandler('cm-law:server:memberWentOffDuty', function(_, cid) cleanupOfficer(cid) end)
AddEventHandler('playerDropped', function()
    local dropped = source
    for id, entry in pairs(deployments) do if entry.officerSource == dropped then clearEntry(id) end end
end)
CreateThread(function()
    while true do
        Wait(5000); local now = os.time()
        for id, entry in pairs(deployments) do if now >= entry.expiresAt then clearEntry(id) end end
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(deployments) do clearEntry(id) end
end)
