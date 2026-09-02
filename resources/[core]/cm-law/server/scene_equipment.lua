-- Generic law scene equipment authority. Police-specific scene contracts
-- remain in cm-police until the shared equipment migration is complete.
--
-- IMPORTANT: all final props are server-created. We therefore keep BOTH the
-- server entity handle and the network id for the lifetime of each deployment.
-- The original entity handle is the most reliable deletion path on the server;
-- the net id is retained for client visibility / ownership fallback.
local deployments, nextId = {}, 0
local SCENE_VERSION = '4.0.0'

local TYPES = {
    -- Match the existing Police gameplay limits. Keep these small because these
    -- are temporary road hazards, not persistent map objects.
    spike = {
        capability = 'spikes',
        lawPermission = 'law.spike',
        policePermission = 'police.spike',
        model = 'p_ld_stinger_s',
        max = 1,
        placementMs = 45000,
        lifetimeMs = 120000,
        state = 'cmSpikeStrip',
    },
    barricade = {
        capability = 'barricades',
        lawPermission = 'law.barricade',
        policePermission = 'police.barricade',
        max = 2,
        placementMs = 45000,
        lifetimeMs = 1800000,
        state = 'cmBarricade',
    },
}

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
            or not (legal.isLeader or legal.permissions[cfg.lawPermission] == true) then
            return nil
        end
        return tostring(characterId), legal.organizationId
    end

    return nil
end

local function deploymentIdsWhere(predicate)
    local ids = {}
    for id, entry in pairs(deployments) do
        if predicate(entry) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function activeCount(characterId, kind)
    characterId = tostring(characterId or '')
    local total = 0
    for _, entry in pairs(deployments) do
        if entry.officerCid == characterId and entry.equipmentType == kind then
            total = total + 1
        end
    end
    return total
end

local function networkEntityExists(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return false end

    if type(NetworkDoesEntityExistWithNetworkId) == 'function' then
        local ok, exists = pcall(NetworkDoesEntityExistWithNetworkId, netId)
        if ok then return exists == true end
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    return entity ~= 0 and DoesEntityExist(entity)
end

local function resolveServerEntity(entry)
    -- The server-created handle is deliberately retained. This avoids relying
    -- entirely on NetworkGetEntityFromNetworkId during ownership migration.
    local entity = tonumber(entry.serverEntity) or 0
    if entity ~= 0 and DoesEntityExist(entity) then return entity end

    if entry.networkId then
        entity = NetworkGetEntityFromNetworkId(entry.networkId)
        if entity ~= 0 and DoesEntityExist(entity) then
            entry.serverEntity = entity
            return entity
        end
    end

    return 0
end

local function entityRoutingBucket(entity)
    if type(GetEntityRoutingBucket) ~= 'function' then return nil end
    local ok, bucket = pcall(GetEntityRoutingBucket, entity)
    return ok and tonumber(bucket) or nil
end

local function validDeploymentEntity(entry, entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    local cfg = TYPES[entry.equipmentType]
    if not cfg then return false end

    -- Model + recorded position + bucket identify the server-created object even
    -- if a state bag was not immediately readable on the server. State tags are
    -- still checked when present; a conflicting tag always fails closed.
    if entry.modelHash and GetEntityModel(entity) ~= entry.modelHash then return false end

    if entry.coords then
        local coords = GetEntityCoords(entity)
        if #(coords - entry.coords) > 4.0 then return false end
    end

    local bucket = entityRoutingBucket(entity)
    if bucket ~= nil and bucket ~= tonumber(entry.routingBucket) then return false end

    local state = Entity(entity).state
    local deploymentTag = state.cmLawSceneEquipment
    if deploymentTag ~= nil and tonumber(deploymentTag) ~= tonumber(entry.deploymentId) then return false end

    local typeTag = state[cfg.state]
    if typeTag ~= nil and typeTag ~= true then return false end

    return true
end

local function deploymentStillExists(entry)
    local entity = resolveServerEntity(entry)
    if entity ~= 0 and DoesEntityExist(entity) then return true end
    return entry.networkId and networkEntityExists(entry.networkId) or false
end

local function deleteServerEntity(entry, attempts)
    attempts = math.max(1, tonumber(attempts) or 5)

    for _ = 1, attempts do
        local entity = resolveServerEntity(entry)

        if entity ~= 0 and DoesEntityExist(entity) then
            if not validDeploymentEntity(entry, entity) then
                return false
            end

            -- The entity was created by this server resource. Delete the actual
            -- server handle first; client network ownership is only a fallback.
            DeleteEntity(entity)
        end

        Wait(75)
        if not deploymentStillExists(entry) then return true end
    end

    return not deploymentStillExists(entry)
end

local function cleanupTargets(entry)
    local targets, seen = {}, {}

    local function add(src)
        src = tonumber(src)
        if not src or src <= 0 or seen[src] or not GetPlayerName(src) then return end
        if GetPlayerRoutingBucket(src) ~= entry.routingBucket then return end
        seen[src] = true
        targets[#targets + 1] = src
    end

    local entity = resolveServerEntity(entry)
    if entity ~= 0 and DoesEntityExist(entity) and type(NetworkGetEntityOwner) == 'function' then
        local ok, owner = pcall(NetworkGetEntityOwner, entity)
        if ok then add(owner) end
    end

    add(entry.officerSource)

    -- Any player streaming the object can become the network owner. Include
    -- nearby same-bucket players, but never players from another routing bucket.
    if entry.coords then
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            if src and GetPlayerRoutingBucket(src) == entry.routingBucket then
                local ped = GetPlayerPed(src)
                if ped ~= 0 and #(GetEntityCoords(ped) - entry.coords) <= 175.0 then
                    add(src)
                end
            end
        end
    end

    return targets
end

local function sendClientCleanup(entry)
    entry.cleanupToken = ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    entry.clientDeleteConfirmed = nil

    local payload = {
        deploymentId = entry.deploymentId,
        equipmentType = entry.equipmentType,
        networkId = entry.networkId,
        cleanupToken = entry.cleanupToken,
        modelHash = entry.modelHash,
        routingBucket = entry.routingBucket,
        coords = entry.coords and { x = entry.coords.x, y = entry.coords.y, z = entry.coords.z } or nil,
    }

    local sent = 0
    for _, target in ipairs(cleanupTargets(entry)) do
        TriggerClientEvent('cm-law:client:deleteSceneEquipment', target, payload)
        sent = sent + 1
    end
    return sent
end

local function deleteDeployment(entry, fast)
    -- A placement reservation that never created an entity is safe to forget.
    if not entry.networkId and (not entry.serverEntity or not DoesEntityExist(entry.serverEntity)) then
        return true
    end

    if deleteServerEntity(entry, fast and 2 or 6) then return true end

    -- Resource shutdown cannot wait for long network ownership hand-offs.
    if fast then
        sendClientCleanup(entry)
        Wait(50)
        return not deploymentStillExists(entry)
    end

    -- Give streaming/owner clients a bounded chance to take control and delete.
    -- The acknowledgement never replaces authoritative server verification.
    for _ = 1, 3 do
        sendClientCleanup(entry)

        for _ = 1, 30 do
            Wait(100)
            if not deploymentStillExists(entry) then return true end

            if entry.clientDeleteConfirmed then
                entry.clientDeleteConfirmed = nil
                if deleteServerEntity(entry, 3) then return true end
            end
        end
    end

    return false
end

RegisterNetEvent('cm-law:server:sceneEquipmentDeleteResult', function(deploymentId, networkId, equipmentType, cleanupToken)
    local entry = deployments[tonumber(deploymentId)]
    if not entry or not entry.deleting
        or tonumber(networkId) ~= tonumber(entry.networkId)
        or tostring(equipmentType or '') ~= entry.equipmentType
        or tostring(cleanupToken or '') ~= tostring(entry.cleanupToken or '') then
        return
    end

    if GetPlayerRoutingBucket(source) ~= entry.routingBucket then return end

    local ped = GetPlayerPed(source)
    if ped == 0 then return end
    if entry.coords and #(GetEntityCoords(ped) - entry.coords) > 175.0 then return end

    entry.clientDeleteConfirmed = true
end)

local function finalizeEntry(id)
    deployments[id] = nil
end

local function clearEntry(id, fast)
    local entry = deployments[id]
    if not entry then return true end
    if entry.deleting then return false end

    if not entry.networkId and (not entry.serverEntity or not DoesEntityExist(entry.serverEntity)) then
        finalizeEntry(id)
        return true
    end

    entry.deleting = true

    if not deleteDeployment(entry, fast == true) then
        -- KEEP the registry record. The caller can retry; we never intentionally
        -- orphan an entity by forgetting its authoritative deployment first.
        entry.deleting = nil
        entry.cleanupToken = nil
        entry.clientDeleteConfirmed = nil
        return false
    end

    finalizeEntry(id)
    return true
end

local function reserve(src, kind)
    if not rateLimit(src, 'law_scene_' .. kind, 1500) then return false, 'Please wait.' end

    local characterId, orgId = authority(src, kind)
    if not characterId then return false, 'You are not authorized to deploy this equipment.' end

    local cfg = TYPES[kind]
    if activeCount(characterId, kind) >= cfg.max then
        return false, ('You already have the maximum of %d %s%s deployed.'):format(
            cfg.max,
            kind == 'spike' and 'spike strip' or 'barricade',
            cfg.max == 1 and '' or 's'
        )
    end

    nextId = nextId + 1
    deployments[nextId] = {
        deploymentId = nextId,
        equipmentType = kind,
        organizationId = orgId,
        officerCid = tostring(characterId),
        officerSource = src,
        networkId = nil,
        serverEntity = nil,
        routingBucket = GetPlayerRoutingBucket(src),
        createdAt = os.time(),
        expiresAt = os.time() + math.ceil(cfg.placementMs / 1000),
    }

    return true, nextId
end

local function approvedBarricade(model)
    return MySQL.scalar.await('SELECT 1 FROM cm_police_barricade_catalog WHERE model_name = ? LIMIT 1', { model }) ~= nil
end

local function confirm(src, id, kind, x, y, z, heading, model)
    id = tonumber(id)
    local entry, cfg = deployments[id], TYPES[kind]
    if not entry or not cfg or entry.equipmentType ~= kind then
        return false, 'Scene-equipment reservation was not found. Restart cm-law and try again.'
    end
    if entry.networkId or entry.serverEntity then
        return false, 'This scene-equipment reservation was already used.'
    end

    local characterId, orgId = authority(src, kind)
    if not characterId then
        clearEntry(id)
        return false, 'You are no longer authorized to deploy this equipment.'
    end
    if entry.officerCid ~= tostring(characterId) or entry.organizationId ~= orgId then
        clearEntry(id)
        return false, 'The scene-equipment reservation no longer belongs to you.'
    end

    x = validNumber(x, 10000)
    y = validNumber(y, 10000)
    z = validNumber(z, 2500)
    heading = validNumber(heading, 100000) or 0
    if not x or not y or not z then
        clearEntry(id)
        return false, 'Invalid scene-equipment placement coordinates.'
    end

    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(x, y, z)) > 7.0 then
        clearEntry(id)
        return false, 'Placement is too far from your character.'
    end

    model = kind == 'spike' and cfg.model or tostring(model or '')
    if kind == 'barricade' and not approvedBarricade(model) then
        clearEntry(id)
        return false, 'That barricade model is not in the approved catalog.'
    end

    local modelHash = GetHashKey(model)

    -- IMPORTANT: CreateObject is a server RPC native. It can return 0 even when
    -- the officer is standing beside the placement because the RPC depends on a
    -- suitable client accepting the creation request. Cfx recommends the server
    -- setter CREATE_OBJECT_NO_OFFSET for authoritative server-created objects.
    -- This registers the object directly with OneSync instead of asking a client
    -- to create it on the server's behalf.
    local entity = CreateObjectNoOffset(modelHash, x, y, z, true, true, false)
    if not entity or entity == 0 then
        clearEntry(id)
        return false, 'The server could not register the scene-equipment object.'
    end

    -- A server-setter entity can begin life orphaned until a nearby client takes
    -- ownership. Give OneSync a short bounded window to expose the handle.
    local entityDeadline = GetGameTimer() + 2500
    while not DoesEntityExist(entity) and GetGameTimer() < entityDeadline do
        Wait(25)
    end
    if not DoesEntityExist(entity) then
        pcall(DeleteEntity, entity)
        clearEntry(id)
        return false, 'The server registered the object but it did not become available.'
    end

    -- Keep the temporary road object owned by the script until our explicit
    -- recall/expiry cleanup removes it.
    if type(SetEntityOrphanMode) == 'function' then
        pcall(SetEntityOrphanMode, entity, 2)
    end

    entry.serverEntity = entity
    entry.modelName = model
    entry.modelHash = modelHash
    entry.coords = vector3(x, y, z)
    entry.heading = heading % 360

    -- These setters may be RPC-backed while the entity is orphaned. We still
    -- attempt them server-side, and replicate the desired transform so the
    -- nearby client can apply it as soon as it owns/streams the object.
    pcall(SetEntityRoutingBucket, entity, entry.routingBucket)
    pcall(SetEntityHeading, entity, entry.heading)
    pcall(FreezeEntityPosition, entity, true)

    -- Replicated identity makes the object recoverable even if the in-memory
    -- registry is lost during a resource restart. Never use model-only deletion.
    local state = Entity(entity).state
    state:set(cfg.state, true, true)
    state:set('cmLawSceneEquipment', entry.deploymentId, true)
    state:set('cmLawSceneOwnerCid', tostring(entry.officerCid), true)
    state:set('cmLawSceneOrganization', tostring(entry.organizationId), true)
    state:set('cmLawSceneType', kind, true)
    state:set('cmLawSceneVersion', SCENE_VERSION, true)
    state:set('cmLawSceneHeading', entry.heading, true)
    state:set('cmLawSceneFrozen', true, true)

    local netId = 0
    local networkDeadline = GetGameTimer() + 2500
    repeat
        netId = NetworkGetNetworkIdFromEntity(entity) or 0
        if netId > 0 then break end
        Wait(25)
    until GetGameTimer() >= networkDeadline

    if netId <= 0 then
        deleteServerEntity(entry, 6)
        finalizeEntry(id)
        return false, 'The server created the object but could not assign a network ID.'
    end

    entry.networkId = netId
    entry.expiresAt = os.time() + math.floor(cfg.lifetimeMs / 1000)

    local payload = {
        deploymentId = entry.deploymentId,
        equipmentType = kind,
        networkId = netId,
        organizationId = entry.organizationId,
        officerCid = entry.officerCid,
        modelHash = entry.modelHash,
        routingBucket = entry.routingBucket,
        version = SCENE_VERSION,
        heading = entry.heading,
    }
    TriggerClientEvent('cm-law:client:sceneEquipmentRegistered', src, payload)
    return true, payload
end

local function cancel(src, id, kind)
    local entry = deployments[tonumber(id)]
    local characterId = characterIdFor(src)
    if entry and entry.equipmentType == kind and not entry.networkId and not entry.serverEntity
        and tostring(characterId or '') == entry.officerCid then
        clearEntry(entry.deploymentId)
    end
end

local function recall(src, kind)
    local characterId, orgId = authority(src, kind)
    if not characterId then return 0 end

    local ids = deploymentIdsWhere(function(entry)
        return entry.equipmentType == kind
            and entry.officerCid == tostring(characterId)
            and entry.organizationId == orgId
    end)

    local removed = 0
    for _, id in ipairs(ids) do
        if clearEntry(id) then removed = removed + 1 end
    end

    return removed, math.max(0, #ids - removed)
end

lib.callback.register('cm-law:server:deploySpikeStrip', function(src)
    return reserve(src, 'spike')
end)

lib.callback.register('cm-law:server:deployBarricade', function(src)
    return reserve(src, 'barricade')
end)

-- New clients confirm synchronously so a visible object can never be mistaken
-- for an untracked deployment. The legacy events below remain as compatibility
-- adapters for any older Police callers.
lib.callback.register('cm-law:server:confirmSpikeStrip', function(src, id, x, y, z, h)
    return confirm(src, id, 'spike', x, y, z, h)
end)

lib.callback.register('cm-law:server:confirmBarricade', function(src, id, x, y, z, h, model)
    return confirm(src, id, 'barricade', x, y, z, h, model)
end)

lib.callback.register('cm-law:server:recallSpikeStrips', function(src)
    return recall(src, 'spike')
end)

lib.callback.register('cm-law:server:recallBarricades', function(src)
    return recall(src, 'barricade')
end)

lib.callback.register('cm-law:server:sceneEquipmentState', function(src)
    local characterId = characterIdFor(src)
    if not characterId then return { version = SCENE_VERSION, spike = 0, barricade = 0 } end
    return {
        version = SCENE_VERSION,
        spike = activeCount(characterId, 'spike'),
        barricade = activeCount(characterId, 'barricade'),
    }
end)

RegisterNetEvent('cm-law:server:spikeStripDeployed', function(id, x, y, z, h)
    local ok, payloadOrReason = confirm(source, id, 'spike', x, y, z, h)
    if ok then
        TriggerClientEvent('cm-playerdata:client:interactionNotify', source, 'Spike strip deployed.', 'success')
    else
        TriggerClientEvent('cm-playerdata:client:interactionNotify', source, payloadOrReason or 'Spike deployment failed.', 'error')
    end
end)

RegisterNetEvent('cm-law:server:barricadeDeployed', function(id, x, y, z, h, model)
    local ok, payloadOrReason = confirm(source, id, 'barricade', x, y, z, h, model)
    if ok then
        TriggerClientEvent('cm-playerdata:client:interactionNotify', source, 'Barricade deployed.', 'success')
    else
        TriggerClientEvent('cm-playerdata:client:interactionNotify', source, payloadOrReason or 'Barricade deployment failed.', 'error')
    end
end)

RegisterNetEvent('cm-law:server:cancelSpikeStrip', function(id)
    cancel(source, id, 'spike')
end)

RegisterNetEvent('cm-law:server:cancelBarricade', function(id)
    cancel(source, id, 'barricade')
end)

local function cleanupOfficer(characterId)
    characterId = tostring(characterId or '')
    if characterId == '' then return end

    local ids = deploymentIdsWhere(function(entry)
        return entry.officerCid == characterId
    end)

    for _, id in ipairs(ids) do clearEntry(id) end
end

AddEventHandler('cm-law:server:memberWentOffDuty', function(_, cid)
    cleanupOfficer(cid)
end)

AddEventHandler('playerDropped', function()
    local dropped = source
    local ids = deploymentIdsWhere(function(entry)
        return entry.officerSource == dropped
    end)
    for _, id in ipairs(ids) do clearEntry(id) end
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        local ids = deploymentIdsWhere(function(entry)
            return now >= entry.expiresAt
        end)
        for _, id in ipairs(ids) do clearEntry(id) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- Best-effort shutdown cleanup. Use the retained server entity handle first;
    -- do not block resource shutdown waiting for multi-second client retries.
    local ids = deploymentIdsWhere(function() return true end)
    for _, id in ipairs(ids) do
        local entry = deployments[id]
        if entry then
            entry.deleting = true
            deleteServerEntity(entry, 3)
            if deploymentStillExists(entry) then sendClientCleanup(entry) end
            finalizeEntry(id)
        end
    end
end)
