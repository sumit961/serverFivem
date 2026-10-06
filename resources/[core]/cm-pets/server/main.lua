local Config = CM_PETS.Config
local RESOURCE = GetCurrentResourceName()

local sessions = {}
local activePets = {}
local cooldowns = {}
local adoptionCenters = {}
local adoptionSessions = {}
local adoptionLocks = {}

local function now()
    return GetGameTimer()
end

local function clamp(value, min, max)
    value = tonumber(value) or min
    if value < min then return min end
    if value > max then return max end
    return math.floor(value)
end

local function trim(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > maxLength then return nil end
    return value
end

local function safeId(value, maxLength)
    value = trim(tostring(value or ''), maxLength)
    if not value or not value:match('^[%w_%-]+$') then return nil end
    return value:lower()
end

local function characterId(value)
    local id = tonumber(value)
    if not id or id < 1 or id % 1 ~= 0 then return nil end
    return tostring(math.floor(id))
end

local function encodeMetadata(value)
    if value == nil then return '{}' end
    if type(value) ~= 'table' then return nil end

    local clean, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > Config.Limits.MetadataKeys then return nil end
        local cleanKey = safeId(key, 32)
        if not cleanKey then return nil end
        local itemType = type(item)
        if itemType == 'string' then
            if #item > Config.Limits.MetadataValue then return nil end
            clean[cleanKey] = item
        elseif itemType == 'number' and item == item and item ~= math.huge and item ~= -math.huge then
            clean[cleanKey] = item
        elseif itemType == 'boolean' then
            clean[cleanKey] = item
        else
            return nil
        end
    end

    local ok, encoded = pcall(json.encode, clean)
    if not ok or type(encoded) ~= 'string' or #encoded > Config.Limits.MetadataJson then return nil end
    return encoded
end

local function database(method, query, params)
    local ok, result = pcall(function()
        return MySQL[method].await(query, params or {})
    end)
    if not ok then return false, nil end
    return true, result
end

local function centerClient(row)
    if type(row) ~= 'table' then return nil end
    local normalized = CM_PETS.Adoption.NormalizeCenter(row, row, Config)
    if not normalized or not normalized.enabled then return nil end
    return {
        id = normalized.centerId,
        displayName = normalized.displayName,
        interactionLabel = normalized.interactionLabel,
        npcModel = normalized.npcModel,
        enabled = true,
        x = normalized.x, y = normalized.y, z = normalized.z,
        heading = normalized.heading,
        interactionDistance = normalized.interactionDistance,
        routingBucket = normalized.routingBucket,
    }
end

local function refreshAdoptionCenters()
    local ok, rows = database('query', [[
        SELECT center_id, display_name, interaction_label, npc_model, enabled,
               x, y, z, heading, interaction_distance, routing_bucket
        FROM cm_pet_adoption_centers ORDER BY center_id ASC
    ]], {})
    local refreshed = {}
    if ok then
        for _, row in ipairs(rows or {}) do
            local normalized = CM_PETS.Adoption.NormalizeCenter(row, row, Config)
            if normalized then refreshed[normalized.centerId] = normalized end
        end
    end
    -- Static entries are intentionally empty by default, but supporting them
    -- keeps the configuration contract useful for development-only fixtures.
    for centerId, raw in pairs(Config.AdoptionCenters or {}) do
        local input = type(raw) == 'table' and raw or {}
        input.centerId = input.centerId or centerId
        local normalized = CM_PETS.Adoption.NormalizeCenter(input, nil, Config)
        if normalized and normalized.enabled and not refreshed[normalized.centerId] then
            refreshed[normalized.centerId] = normalized
        end
    end
    adoptionCenters = refreshed
    for src, adoptionSession in pairs(adoptionSessions) do
        if not adoptionCenters[adoptionSession.centerId] then adoptionSessions[src] = nil end
    end
    return ok
end

local function getAdoptionCenter(centerId)
    centerId = tostring(centerId or ''):lower()
    local row = adoptionCenters[centerId]
    return row and row or nil
end

local function adoptionContext(src, session)
    local data = getPlayerData(src)
    local ped = GetPlayerPed(src)
    if not session or not isAlive(data) or ped == 0 or not DoesEntityExist(ped)
        or GetEntityType(ped) ~= 1 or GetEntityHealth(ped) <= 0 then
        return nil
    end
    local coords = GetEntityCoords(ped)
    if not coords then return nil end
    return {
        loaded = data.loaded == true,
        alive = isAlive(data),
        playerValid = true,
        x = coords.x, y = coords.y, z = coords.z,
        routingBucket = GetPlayerRoutingBucket(src),
    }
end

local function centerContext(src, centerId, session)
    local center = getAdoptionCenter(centerId)
    if not center then return nil, 'adoption_center_unavailable' end
    local context = adoptionContext(src, session)
    if not context then return nil, 'player_unavailable' end
    local usable, reason = CM_PETS.Adoption.CenterUsable(context, center)
    if not usable then return nil, reason end
    return center, context
end

local function newAdoptionToken(src, session, centerId)
    local token = ('%s:%s:%s'):format(now(), src, math.random(100000, 999999))
    adoptionSessions[src] = {
        generation = session.generation,
        centerId = centerId,
        token = token,
        expiresAt = now() + 30000,
    }
    return token
end

local function publicAdoptableType(row)
    local model = tostring(row.model or ''):lower()
    local approved = Config.ApprovedModels[model]
    if not approved or tonumber(row.enabled) ~= 1 or approved.species ~= tostring(row.species or ''):lower() then return nil end
    return {
        typeId = tostring(row.type_id),
        displayName = tostring(row.display_name),
        species = tostring(row.species),
        description = tostring(row.description or ''),
    }
end

local function listAdoptableTypes()
    local ok, rows = database('query', [[
        SELECT type_id, display_name, species, model, description, enabled
        FROM cm_pet_types WHERE enabled = 1 ORDER BY display_name ASC, type_id ASC
    ]], {})
    if not ok then return nil, 'database_unavailable' end
    local types = {}
    for _, row in ipairs(rows or {}) do
        local value = publicAdoptableType(row)
        if value then types[#types + 1] = value end
    end
    return types
end

local function rateLimit(src, key, duration)
    local id = ('%s:%s'):format(src, key)
    local timestamp = now()
    if cooldowns[id] and timestamp - cooldowns[id] < duration then return false end
    cooldowns[id] = timestamp
    return true
end

local function getPlayerData(src)
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return nil end
    local ok, data = pcall(function()
        return exports[Config.PlayerDataResource]:GetPlayerData(src)
    end)
    return ok and type(data) == 'table' and data or nil
end

local function isAlive(data)
    return type(data) == 'table' and data.loaded == true and data.isDead ~= true
        and tostring(data.lifeState or 'alive') == 'alive'
end

local function getCharacterId(src)
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return nil end
    local ok, id = pcall(function()
        return exports[Config.PlayerDataResource]:GetCharacterId(src)
    end)
    return ok and characterId(id) or nil
end

local function getSession(src, expectedCharacterId)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil, 'player_unavailable' end
    local data = getPlayerData(src)
    local cid = getCharacterId(src)
    if not cid or not isAlive(data) then return nil, 'character_not_alive' end
    if expectedCharacterId and cid ~= expectedCharacterId then return nil, 'character_mismatch' end

    local session = sessions[src]
    if not session or session.characterId ~= cid then
        session = { characterId = cid, generation = (session and session.generation or 0) + 1 }
        sessions[src] = session
    end
    return session
end

local function activeEntityIsValid(src, row, petRow)
    if not row or not row.entity or not DoesEntityExist(row.entity) then return false end
    if GetEntityType(row.entity) ~= 1 then return false end
    if not sessions[src] then return false end
    if row.characterId ~= petRow.character_id or row.generation ~= sessions[src].generation then return false end
    if row.petTypeId ~= petRow.pet_type_id then return false end
    if GetEntityRoutingBucket(row.entity) ~= GetPlayerRoutingBucket(src) then return false end
    if Entity(row.entity).state.cmPetsResource ~= true then return false end
    if tonumber(GetEntityModel(row.entity)) ~= GetHashKey(petRow.model) then return false end
    return true
end

local function removeActive(src, reason)
    local row = activePets[src]
    activePets[src] = nil
    if row and row.entity and DoesEntityExist(row.entity) then
        DeleteEntity(row.entity)
    end
    if row and reason then
        TriggerClientEvent('cm-pets:client:hidden', src, reason)
    end
end

local function loadOwnedPet(cid)
    local ok, row = database('single', [[
        SELECT p.id, p.character_id, p.pet_type_id, p.pet_name, p.enabled, p.revoked,
               p.metadata_json, t.display_name, t.species, t.model, t.description,
               t.enabled AS type_enabled
        FROM cm_pets p
        INNER JOIN cm_pet_types t ON t.type_id = p.pet_type_id
        WHERE p.character_id = ? LIMIT 1
    ]], { cid })
    if not ok then return nil, 'database_unavailable' end
    return row
end

local function validCatalogRow(row)
    if type(row) ~= 'table' then return false end
    local model = tostring(row.model or ''):lower()
    local approved = Config.ApprovedModels[model]
    return tonumber(row.type_enabled) == 1 and tonumber(row.enabled) == 1
        and tonumber(row.revoked) == 0 and approved ~= nil and tostring(row.species or ''):lower() == approved.species
end

local function publicPet(row)
    if not row then return nil end
    return {
        id = tonumber(row.id),
        typeId = tostring(row.pet_type_id),
        name = tostring(row.pet_name),
        displayName = tostring(row.display_name),
        species = tostring(row.species),
        description = tostring(row.description or ''),
        enabled = tonumber(row.enabled) == 1,
        revoked = tonumber(row.revoked) == 1,
        typeEnabled = tonumber(row.type_enabled) == 1,
    }
end

local function actionContext(src, generation, action, requireEntity)
    src = tonumber(src)
    generation = tonumber(generation)
    if not src or not generation then return nil, 'invalid_session' end
    local session, failure = getSession(src)
    if not session or session.generation ~= generation then return nil, 'stale_session' end
    if not rateLimit(src, action, Config.Cooldowns[action] or 750) then return nil, 'please_wait' end

    local petRow, petFailure = loadOwnedPet(session.characterId)
    if petFailure then return nil, petFailure end
    if not petRow or petRow.character_id ~= session.characterId then return nil, 'pet_not_owned' end
    if not validCatalogRow(petRow) then
        removeActive(src, 'Pet type is disabled or no longer approved.')
        return nil, 'pet_type_unavailable'
    end

    local active = activePets[src]
    if active and not activeEntityIsValid(src, active, petRow) then
        removeActive(src, 'Pet entity was cleaned up.')
        active = nil
    end
    if requireEntity and not active then return nil, 'pet_not_summoned' end
    return { source = src, session = session, pet = petRow, active = active }
end

local function adminAuthorized(adminSrc)
    if GetInvokingResource() ~= Config.AdminInvokingResource then return false, 'owner_only' end
    adminSrc = tonumber(adminSrc)
    if not adminSrc or adminSrc <= 0 or not GetPlayerName(adminSrc) then return false, 'admin_unavailable' end
    if GetResourceState(Config.AdminResource) ~= 'started' then return false, 'admin_unavailable' end
    local ok, allowed = pcall(function()
        return exports[Config.AdminResource]:HasPermission(adminSrc, Config.AdminPermission)
    end)
    if not ok or allowed ~= true then return false, 'permission_denied' end
    return true, adminSrc
end

local function adminLog(src, action, data, targetCid)
    if GetResourceState(Config.AdminResource) ~= 'started' then return end
    pcall(function()
        exports[Config.AdminResource]:AddLog(src, action, data, targetCid and ('character:' .. targetCid) or nil, nil)
    end)
end

local function adminResult(adminSrc, action, data, targetCid)
    adminLog(adminSrc, action, data, targetCid)
    return true
end

local function normalizeTypeInput(data)
    if type(data) ~= 'table' then return nil, 'invalid_request' end
    local typeId = safeId(data.typeId or data.type_id, Config.Limits.TypeId)
    local displayName = trim(data.displayName or data.display_name, Config.Limits.DisplayName)
    local species = safeId(data.species, Config.Limits.Species)
    local model = safeId(data.model, Config.Limits.Model)
    local description = trim(data.description or '', Config.Limits.Description) or ''
    if not typeId or not displayName or not species or not model then return nil, 'invalid_catalog_type' end
    local approved = Config.ApprovedModels[model]
    if not approved or approved.species ~= species then return nil, 'model_not_allowlisted' end
    if data.enabled ~= nil and type(data.enabled) ~= 'boolean' then return nil, 'invalid_enabled_state' end
    return {
        typeId = typeId, displayName = displayName, species = species, model = model,
        description = description, enabled = data.enabled,
    }
end

exports('AddOrUpdatePetType', function(adminSrc, data)
    local authorized, value = adminAuthorized(adminSrc)
    if not authorized then return false, value end
    local row, failure = normalizeTypeInput(data)
    if not row then return false, failure end
    if row.enabled == nil then
        local existingOk, existing = database('single', 'SELECT enabled FROM cm_pet_types WHERE type_id = ? LIMIT 1', { row.typeId })
        if not existingOk then return false, 'database_unavailable' end
        row.enabled = existing and tonumber(existing.enabled) == 1 or true
    end
    local ok, changed = database('insert', [[
        INSERT INTO cm_pet_types
            (type_id, display_name, species, model, description, enabled, created_by_character_id, updated_by_character_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            display_name = VALUES(display_name), species = VALUES(species), model = VALUES(model),
            description = VALUES(description), enabled = VALUES(enabled), updated_by_character_id = VALUES(updated_by_character_id)
    ]], { row.typeId, row.displayName, row.species, row.model, row.description, row.enabled and 1 or 0, getCharacterId(adminSrc), getCharacterId(adminSrc) })
    if not ok then return false, 'database_unavailable' end
    adminResult(value, 'pets_type_upserted', { typeId = row.typeId, enabled = row.enabled }, nil)
    return true, tonumber(changed) or 0
end)

exports('SetPetTypeEnabled', function(adminSrc, typeId, enabled)
    local authorized, value = adminAuthorized(adminSrc)
    if not authorized then return false, value end
    typeId = safeId(typeId, Config.Limits.TypeId)
    if not typeId or type(enabled) ~= 'boolean' then return false, 'invalid_request' end
    local ok, changed = database('update', 'UPDATE cm_pet_types SET enabled = ?, updated_by_character_id = ? WHERE type_id = ?', {
        enabled and 1 or 0, getCharacterId(adminSrc), typeId,
    })
    if not ok then return false, 'database_unavailable' end
    if tonumber(changed) ~= 1 then return false, 'pet_type_not_found' end
    if not enabled then
        for src, active in pairs(activePets) do
            if active.petTypeId == typeId then removeActive(src, 'Pet type disabled by an administrator.') end
        end
    end
    adminResult(value, 'pets_type_enabled_changed', { typeId = typeId, enabled = enabled }, nil)
    return true
end)

exports('GrantPet', function(adminSrc, rawCharacterId, typeId, petName, metadata)
    local authorized, value = adminAuthorized(adminSrc)
    if not authorized then return false, value end
    local cid = characterId(rawCharacterId)
    typeId = safeId(typeId, Config.Limits.TypeId)
    petName = trim(petName, Config.Limits.PetName)
    local metadataJson = encodeMetadata(metadata)
    if not cid or not typeId or not petName or not metadataJson then return false, 'invalid_pet_grant' end

    local typeOk, typeRow = database('single', 'SELECT type_id, model, enabled FROM cm_pet_types WHERE type_id = ? LIMIT 1', { typeId })
    if not typeOk then return false, 'database_unavailable' end
    if not typeRow or tonumber(typeRow.enabled) ~= 1 or not Config.ApprovedModels[tostring(typeRow.model):lower()] then return false, 'pet_type_unavailable' end

    local ok, changed = database('insert', [[
        INSERT INTO cm_pets
            (character_id, pet_type_id, pet_name, enabled, revoked, metadata_json, granted_by_character_id, revoked_by_character_id, revoked_at)
        SELECT ?, type_id, ?, 1, 0, ?, ?, NULL, NULL
        FROM cm_pet_types WHERE type_id = ? AND enabled = 1
        ON DUPLICATE KEY UPDATE
            pet_type_id = VALUES(pet_type_id), pet_name = VALUES(pet_name), enabled = 1, revoked = 0,
            metadata_json = VALUES(metadata_json), granted_by_character_id = VALUES(granted_by_character_id),
            revoked_by_character_id = NULL, revoked_at = NULL
    ]], { cid, petName, metadataJson, getCharacterId(adminSrc), typeId })
    if not ok or tonumber(changed) == 0 then return false, 'grant_failed' end

    local sourceOk, targetSrc = pcall(function()
        return exports[Config.PlayerDataResource]:GetSourceByCharId(tonumber(cid))
    end)
    targetSrc = sourceOk and targetSrc or nil
    if targetSrc then removeActive(tonumber(targetSrc), 'Pet ownership was updated.') end
    adminResult(value, 'pets_granted', { petTypeId = typeId }, cid)
    return true
end)

exports('RevokePet', function(adminSrc, rawCharacterId)
    local authorized, value = adminAuthorized(adminSrc)
    if not authorized then return false, value end
    local cid = characterId(rawCharacterId)
    if not cid then return false, 'invalid_character_id' end
    local ok, changed = database('update', [[
        UPDATE cm_pets SET enabled = 0, revoked = 1, revoked_by_character_id = ?, revoked_at = CURRENT_TIMESTAMP
        WHERE character_id = ? AND revoked = 0
    ]], { getCharacterId(adminSrc), cid })
    if not ok then return false, 'database_unavailable' end
    if tonumber(changed) ~= 1 then return false, 'pet_not_found' end
    local sourceOk, targetSrc = pcall(function()
        return exports[Config.PlayerDataResource]:GetSourceByCharId(tonumber(cid))
    end)
    targetSrc = sourceOk and targetSrc or nil
    if targetSrc then removeActive(tonumber(targetSrc), 'Pet ownership was revoked.') end
    adminResult(value, 'pets_revoked', {}, cid)
    return true
end)

local function saveAdoptionCenter(adminSrc, data, existing)
    local center, failure = CM_PETS.Adoption.NormalizeCenter(data, existing, Config)
    if not center then return false, failure end
    local actor = getCharacterId(adminSrc)
    local ok = database('insert', [[
        INSERT INTO cm_pet_adoption_centers
            (center_id, display_name, interaction_label, npc_model, enabled,
             x, y, z, heading, interaction_distance, routing_bucket,
             created_by_character_id, updated_by_character_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            display_name = VALUES(display_name), interaction_label = VALUES(interaction_label),
            npc_model = VALUES(npc_model), enabled = VALUES(enabled), x = VALUES(x),
            y = VALUES(y), z = VALUES(z), heading = VALUES(heading),
            interaction_distance = VALUES(interaction_distance), routing_bucket = VALUES(routing_bucket),
            updated_by_character_id = VALUES(updated_by_character_id)
    ]], {
        center.centerId, center.displayName, center.interactionLabel, center.npcModel,
        center.enabled and 1 or 0, center.x, center.y, center.z, center.heading,
        center.interactionDistance, center.routingBucket, actor, actor,
    })
    if not ok then return false, 'database_unavailable' end
    refreshAdoptionCenters()
    TriggerClientEvent('cm-pets:client:adoptionCentersUpdated', -1)
    return true, center
end

exports('AdminSetAdoptionCenter', function(adminSrc, data)
    local authorized, value = adminAuthorized(adminSrc)
    if not authorized then return false, value end
    if type(data) ~= 'table' then return false, 'invalid_request' end
    local centerId = tostring(data.centerId or data.center_id or ''):lower()
    local existingOk, existing = database('single', [[
        SELECT center_id, display_name, interaction_label, npc_model, enabled,
               x, y, z, heading, interaction_distance, routing_bucket
        FROM cm_pet_adoption_centers WHERE center_id = ? LIMIT 1
    ]], { centerId })
    if not existingOk then return false, 'database_unavailable' end
    local saved, centerOrFailure = saveAdoptionCenter(value, data, existing)
    if not saved then return false, centerOrFailure end
    adminResult(value, 'pets_adoption_center_upserted', { centerId = centerOrFailure.centerId, enabled = centerOrFailure.enabled }, nil)
    return true, centerOrFailure
end)

exports('AdminEnableAdoptionCenter', function(adminSrc, rawCenterId, enabled)
    local authorized, value = adminAuthorized(adminSrc)
    if not authorized then return false, value end
    local centerId = safeId(rawCenterId, Config.Limits.CenterId)
    if not centerId or type(enabled) ~= 'boolean' then return false, 'invalid_request' end
    local existingOk, existing = database('single', [[
        SELECT center_id, display_name, interaction_label, npc_model, enabled,
               x, y, z, heading, interaction_distance, routing_bucket
        FROM cm_pet_adoption_centers WHERE center_id = ? LIMIT 1
    ]], { centerId })
    if not existingOk then return false, 'database_unavailable' end
    if not existing then return false, 'adoption_center_not_found' end
    local saved, centerOrFailure = saveAdoptionCenter(value, { centerId = centerId, enabled = enabled }, existing)
    if not saved then return false, centerOrFailure end
    adminResult(value, 'pets_adoption_center_enabled_changed', { centerId = centerId, enabled = enabled }, nil)
    return true, centerOrFailure
end)

exports('AdminListAdoptionCenters', function(adminSrc)
    local authorized = adminAuthorized(adminSrc)
    if not authorized then return {} end
    local ok, rows = database('query', [[
        SELECT center_id, display_name, interaction_label, npc_model, enabled,
               x, y, z, heading, interaction_distance, routing_bucket,
               created_by_character_id, updated_by_character_id, created_at, updated_at
        FROM cm_pet_adoption_centers ORDER BY center_id ASC
    ]], {})
    if not ok then return {} end
    local out = {}
    for _, row in ipairs(rows or {}) do
        local normalized = CM_PETS.Adoption.NormalizeCenter(row, row, Config)
        if normalized then
            normalized.createdByCharacterId = row.created_by_character_id and tostring(row.created_by_character_id) or nil
            normalized.updatedByCharacterId = row.updated_by_character_id and tostring(row.updated_by_character_id) or nil
            normalized.createdAt = row.created_at
            normalized.updatedAt = row.updated_at
            out[#out + 1] = normalized
        end
    end
    return out
end)

exports('ListOwnedPets', function(adminSrc, rawCharacterId, limit)
    local authorized, value = adminAuthorized(adminSrc)
    if not authorized then return {} end
    local cid = rawCharacterId and characterId(rawCharacterId) or nil
    if rawCharacterId and not cid then return {} end
    limit = clamp(limit or 100, 1, 200)
    local sql = [[
        SELECT p.id, p.character_id, p.pet_type_id, p.pet_name, p.enabled, p.revoked,
               t.display_name, t.species, t.model, t.enabled AS type_enabled
        FROM cm_pets p INNER JOIN cm_pet_types t ON t.type_id = p.pet_type_id
    ]]
    local params = {}
    if cid then sql = sql .. ' WHERE p.character_id = ?'; params[#params + 1] = cid end
    sql = sql .. (' ORDER BY p.id DESC LIMIT %d'):format(limit)
    local ok, rows = database('query', sql, params)
    if not ok then return {} end
    local out = {}
    for _, row in ipairs(rows or {}) do
        out[#out + 1] = {
            id = tonumber(row.id), characterId = tostring(row.character_id), typeId = tostring(row.pet_type_id),
            name = tostring(row.pet_name), displayName = tostring(row.display_name), species = tostring(row.species),
            model = tostring(row.model), enabled = row.enabled == 1, revoked = row.revoked == 1,
            typeEnabled = row.type_enabled == 1,
        }
    end
    return out
end)

lib.callback.register('cm-pets:server:listAdoptionCenters', function(src)
    local session = getSession(tonumber(src))
    if not session then return {} end
    local out = {}
    for id, center in pairs(adoptionCenters) do
        local value = centerClient(center)
        if value then out[#out + 1] = value end
    end
    table.sort(out, function(left, right) return tostring(left.id) < tostring(right.id) end)
    return out
end)

lib.callback.register('cm-pets:server:getOwned', function(src, requestedCenterId)
    src = tonumber(src)
    local session, failure = getSession(src)
    if not session then return { ok = false, message = failure } end
    if not rateLimit(src, 'open', Config.Cooldowns.OpenMs) then return { ok = false, message = 'please_wait' } end
    local row, dbFailure = loadOwnedPet(session.characterId)
    if dbFailure then return { ok = false, message = dbFailure } end
    local active = activePets[src]
    if active and (not row or not activeEntityIsValid(src, active, row)) then removeActive(src, 'Pet entity was cleaned up.') end
    local center, adoptable, adoptionToken
    if requestedCenterId ~= nil then
        local centerFailure
        center, centerFailure = centerContext(src, safeId(requestedCenterId, Config.Limits.CenterId), session)
        if not center then return { ok = false, message = centerFailure } end
        adoptable, centerFailure = listAdoptableTypes()
        if not adoptable then return { ok = false, message = centerFailure } end
        adoptionToken = newAdoptionToken(src, session, center.centerId)
    end
    return {
        ok = true,
        generation = session.generation,
        pet = publicPet(row),
        active = activePets[src] ~= nil,
        mode = activePets[src] and activePets[src].mode or nil,
        center = center and centerClient(center) or nil,
        adoptable = adoptable or {},
        adoptionToken = adoptionToken,
    }
end)

lib.callback.register('cm-pets:server:adopt', function(src, generation, centerId, typeId, token)
    src = tonumber(src)
    generation = tonumber(generation)
    local session, failure = getSession(src)
    if not session or session.generation ~= generation then return { ok = false, message = 'stale_session' } end
    if not rateLimit(src, 'adoption', Config.Cooldowns.AdoptionMs) then return { ok = false, message = 'please_wait' } end
    centerId = safeId(centerId, Config.Limits.CenterId)
    typeId = safeId(typeId, Config.Limits.TypeId)
    local adoptionSession = adoptionSessions[src]
    if not centerId or not typeId or not adoptionSession
        or adoptionSession.expiresAt < now()
        or not CM_PETS.Adoption.SessionTokenValid(session.generation, adoptionSession.token, generation, token)
        or adoptionSession.centerId ~= centerId then
        return { ok = false, message = 'stale_adoption_session' }
    end

    local center, contextOrFailure = centerContext(src, centerId, session)
    if not center then return { ok = false, message = contextOrFailure } end
    local typeOk, typeRow = database('single', [[
        SELECT type_id, display_name, species, model, description, enabled
        FROM cm_pet_types WHERE type_id = ? LIMIT 1
    ]], { typeId })
    if not typeOk then return { ok = false, message = 'database_unavailable' } end
    local approved = typeRow and Config.ApprovedModels[tostring(typeRow.model or ''):lower()]
    local existing, existingFailure = loadOwnedPet(session.characterId)
    if existingFailure then return { ok = false, message = existingFailure } end
    local allowed, decision = CM_PETS.Adoption.AdoptionDecision(contextOrFailure, center, {
        enabled = typeRow and typeRow.enabled,
        approvedModel = approved and approved.species == tostring(typeRow.species or ''):lower(),
    }, existing)
    if not allowed then
        if decision == 'already_owned' then
            return { ok = false, message = 'pet_already_owned', generation = session.generation, pet = publicPet(existing), active = activePets[src] ~= nil }
        end
        return { ok = false, message = decision } end

    local cid = session.characterId
    if adoptionLocks[cid] then return { ok = false, message = 'adoption_in_progress' } end
    adoptionLocks[cid] = true
    local metadataJson = encodeMetadata({ acquisition = 'adoption', center_id = centerId })
    local petName = trim(typeRow.display_name, Config.Limits.PetName) or 'Companion'
    local insertOk, changed = database('insert', [[
        INSERT IGNORE INTO cm_pets
            (character_id, pet_type_id, pet_name, enabled, revoked, metadata_json,
             granted_by_character_id, revoked_by_character_id, revoked_at)
        SELECT ?, type_id, ?, 1, 0, ?, NULL, NULL, NULL
        FROM cm_pet_types
        WHERE type_id = ? AND enabled = 1
          AND NOT EXISTS (SELECT 1 FROM cm_pets WHERE character_id = ?)
    ]], { cid, petName, metadataJson, typeId, cid })
    adoptionLocks[cid] = nil
    if not insertOk then return { ok = false, message = 'database_unavailable' } end

    local adopted = tonumber(changed) == 1
    local resultRow, resultFailure = loadOwnedPet(cid)
    if resultFailure then return { ok = false, message = resultFailure } end
    if not resultRow then return { ok = false, message = 'adoption_failed' } end
    return {
        ok = true,
        generation = session.generation,
        adopted = adopted,
        idempotent = not adopted,
        pet = publicPet(resultRow),
        active = activePets[src] ~= nil,
        mode = activePets[src] and activePets[src].mode or nil,
        center = centerClient(center),
    }
end)

lib.callback.register('cm-pets:server:summon', function(src, generation)
    local context, failure = actionContext(src, generation, 'summon', false)
    if not context then return { ok = false, message = failure } end
    local existing = activePets[context.source]
    if existing then return { ok = false, message = 'pet_already_summoned' } end
    local ped = GetPlayerPed(context.source)
    if ped == 0 or not DoesEntityExist(ped) then return { ok = false, message = 'player_entity_unavailable' } end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local pet = CreatePed(28, GetHashKey(context.pet.model), coords.x + 1.2, coords.y + 0.4, coords.z, heading, true, true)
    if pet == 0 or not DoesEntityExist(pet) then return { ok = false, message = 'networked_entity_unavailable' } end
    SetEntityRoutingBucket(pet, GetPlayerRoutingBucket(context.source))
    local netId = NetworkGetNetworkIdFromEntity(pet)
    if not netId or netId == 0 then DeleteEntity(pet); return { ok = false, message = 'networked_entity_unavailable' } end
    Entity(pet).state:set('cmPetsResource', true, true)
    Entity(pet).state:set('cmPetsSession', context.session.generation, true)
    activePets[context.source] = {
        entity = pet, netId = netId, characterId = context.session.characterId,
        generation = context.session.generation, petTypeId = context.pet.pet_type_id, mode = 'follow',
    }
    return { ok = true, generation = context.session.generation, netId = netId, model = context.pet.model, pet = publicPet(context.pet), active = true, mode = 'follow' }
end)

lib.callback.register('cm-pets:server:hide', function(src, generation)
    local context, failure = actionContext(src, generation, 'hide', true)
    if not context then return { ok = false, message = failure } end
    removeActive(context.source, 'Pet hidden.')
    return { ok = true, generation = context.session.generation, pet = publicPet(context.pet), active = false }
end)

lib.callback.register('cm-pets:server:rename', function(src, generation, rawName)
    local context, failure = actionContext(src, generation, 'rename', false)
    if not context then return { ok = false, message = failure } end
    local petName = trim(rawName, Config.Limits.PetName)
    if not petName then return { ok = false, message = 'invalid_pet_name' } end
    local ok, changed = database('update', [[
        UPDATE cm_pets SET pet_name = ? WHERE character_id = ? AND enabled = 1 AND revoked = 0
    ]], { petName, context.session.characterId })
    if not ok then return { ok = false, message = 'database_unavailable' } end
    if tonumber(changed) ~= 1 then return { ok = false, message = 'pet_not_owned' } end
    context.pet.pet_name = petName
    return { ok = true, generation = context.session.generation, pet = publicPet(context.pet), active = activePets[src] ~= nil, mode = activePets[src] and activePets[src].mode or nil }
end)

lib.callback.register('cm-pets:server:mode', function(src, generation, mode)
    local context, failure = actionContext(src, generation, 'mode', true)
    if not context then return { ok = false, message = failure } end
    mode = tostring(mode or '')
    if mode ~= 'follow' and mode ~= 'stay' then return { ok = false, message = 'invalid_pet_mode' } end
    context.active.mode = mode
    TriggerClientEvent('cm-pets:client:applyMode', src, context.active.netId, mode)
    return { ok = true, generation = context.session.generation, pet = publicPet(context.pet), active = true, mode = mode }
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    src = tonumber(src)
    local cid = characterId(data and data.charId)
    if not src or not cid then return end
    if sessions[src] then sessions[src].generation = sessions[src].generation + 1 else sessions[src] = { generation = 1 } end
    sessions[src].characterId = cid
    adoptionSessions[src] = nil
    removeActive(src, 'Character loaded.')
end)

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    src = tonumber(src)
    if not src then return end
    removeActive(src, 'Character unloaded.')
    adoptionSessions[src] = nil
    sessions[src] = { generation = (sessions[src] and sessions[src].generation or 0) + 1 }
end)

AddEventHandler('cm-playerdata:server:lifeStateChanged', function(src, lifeState)
    src = tonumber(src)
    if src and tostring(lifeState) ~= 'alive' then
        adoptionSessions[src] = nil
        removeActive(src, 'Pet hidden while you are not alive.')
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then
        removeActive(src, 'Player disconnected.')
        adoptionSessions[src] = nil
        sessions[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    for src in pairs(activePets) do removeActive(src) end
    activePets, sessions, cooldowns = {}, {}, {}
    adoptionCenters, adoptionSessions, adoptionLocks = {}, {}, {}
end)

CreateThread(function()
    Wait(0)
    refreshAdoptionCenters()
end)

CreateThread(function()
    while true do
        Wait(5000)
        for src, row in pairs(activePets) do
            local session = getSession(src)
            local pet = session and loadOwnedPet(session.characterId) or nil
            if not session or not pet or not validCatalogRow(pet) or not activeEntityIsValid(src, row, pet) then
                removeActive(src, 'Pet lifecycle validation failed.')
            else
                SetEntityRoutingBucket(row.entity, GetPlayerRoutingBucket(src))
            end
        end
    end
end)
