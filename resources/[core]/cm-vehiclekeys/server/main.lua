local RESOURCE = GetCurrentResourceName()
local Settings = (Config and Config.VehicleKeys) or {}

-- [characterId][normalizedPlate] = key record
local TempKeys = {}
-- [serverId] = active characterId
local ActiveCharacters = {}

local function invokingResourceAllowed(list)
    local invoker = GetInvokingResource()
    if invoker == nil or invoker == RESOURCE then return true end
    if type(list) ~= 'table' then return false end
    for i = 1, #list do
        if tostring(list[i]) == tostring(invoker) then return true end
    end
    return false
end

local function debugLog(message, ...)
    if Settings.debug ~= true then return end
    print(('[%s] %s'):format(RESOURCE:upper(), tostring(message):format(...)))
end

local function normalizePlate(plate)
    local value = tostring(plate or ''):upper():gsub('%s+', '')
    local maxLength = tonumber(Settings.maxPlateLength) or 16
    if value == '' or #value > maxLength then return '' end
    return value
end

local function normalizeCharacterId(characterId)
    local value = tostring(characterId or '')
    if value == '' or value == '0' or #value > 128 then return nil end
    return value
end

local function getStateCharacterId(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return nil end

    local ok, characterId = pcall(function()
        local state = Player(src).state
        local keys = Settings.characterStateKeys or {
            'charId', 'characterId', 'character_id', 'citizenid'
        }

        for i = 1, #keys do
            local value = state[keys[i]]
            if value ~= nil then
                local normalized = normalizeCharacterId(value)
                if normalized then return normalized end
            end
        end

        return nil
    end)

    return ok and characterId or nil
end

local function isExpired(record, now)
    if type(record) ~= 'table' then return false end
    local expiresAt = tonumber(record.expiresAt) or 0
    return expiresAt > 0 and expiresAt <= (now or os.time())
end

local function clearCharacterKeys(characterId, reason)
    characterId = normalizeCharacterId(characterId)
    if not characterId then return false end

    if TempKeys[characterId] then
        TempKeys[characterId] = nil
        debugLog('Cleared temporary keys for character %s (%s).', characterId, reason or 'unknown')
    end

    return true
end

local function setActiveCharacter(src, characterId, reason)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    characterId = normalizeCharacterId(characterId)
    local previous = ActiveCharacters[src]

    if previous and previous ~= characterId then
        -- Keys belong to the old character session and must never survive a
        -- character switch on the same server connection.
        clearCharacterKeys(previous, reason or 'character-switch')
    end

    ActiveCharacters[src] = characterId
    return characterId
end

local function resolveCharacterId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local stateCharacterId = getStateCharacterId(src)
    if stateCharacterId then
        return setActiveCharacter(src, stateCharacterId, 'state-refresh')
    end

    -- Only use the cached character that was observed on this exact player
    -- session. Never guess from the account's most recently played character.
    return ActiveCharacters[src]
end

local function notify(src, message, messageType)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return end
    TriggerClientEvent('cm-vehiclekeys:client:notify', src, tostring(message or ''), messageType or 'info')
end

local function removePlateKey(characterId, plate)
    characterId = normalizeCharacterId(characterId)
    plate = normalizePlate(plate)
    if not characterId or plate == '' then return false end

    local keys = TempKeys[characterId]
    if not keys or not keys[plate] then return false end

    keys[plate] = nil
    if next(keys) == nil then TempKeys[characterId] = nil end
    return true
end

local function isFamilyKey(record)
    return type(record) == 'table' and tostring(record.kind or '') == 'family'
end

local function isOrganizationKey(record)
    return type(record) == 'table' and tostring(record.kind or '') == 'organization'
end

local function validateOrganizationKey(characterId, record, action)
    if not isOrganizationKey(record) then return true, 'not_organization_key', nil end
    local resource = tostring(record.ownerResource or '')
    if resource == '' or GetResourceState(resource) ~= 'started' then return false, 'organization_resource_not_started', nil end
    local ok, allowed, reason, context = pcall(function()
        return exports[resource]:GetVehicleAccessDecision(tostring(characterId), tonumber(record.vehicleId), tostring(action or 'vehicle.drive'))
    end)
    if not ok or allowed ~= true then return false, ok and tostring(reason or 'organization_access_revoked') or 'organization_validation_failed', context end
    if tostring(record.organizationId or '') ~= tostring(context and context.gangId or '') then return false, 'organization_changed', context end
    return true, 'organization_key_valid', context
end

local function validateFamilyKey(characterId, record, action)
    if not isFamilyKey(record) then return true, 'not_family_key', nil end
    if GetResourceState('cm-family') ~= 'started' then
        return false, 'family_resource_not_started', nil
    end

    local ok, allowed, reason, context = pcall(function()
        return exports['cm-family']:GetFamilyVehicleAccessDecision(
            tostring(characterId),
            tonumber(record.vehicleId),
            tostring(action or 'vehicle.drive')
        )
    end)

    if not ok then return false, 'family_validation_failed', nil end
    if allowed ~= true then return false, tostring(reason or 'family_access_revoked'), context end

    local expectedFamily = tonumber(record.familyId)
    local actualFamily = type(context) == 'table' and tonumber(context.familyId) or nil
    if expectedFamily and actualFamily and expectedFamily ~= actualFamily then
        return false, 'family_changed', context
    end
    return true, 'family_key_valid', context
end

local function getKeyRecordByCharacter(characterId, plate, action)
    characterId = normalizeCharacterId(characterId)
    plate = normalizePlate(plate)
    if not characterId or plate == '' then return nil end

    local keys = TempKeys[characterId]
    local record = keys and keys[plate] or nil
    if not record then return nil end

    if isExpired(record) then
        removePlateKey(characterId, plate)
        return nil
    end

    if isFamilyKey(record) then
        local valid = validateFamilyKey(characterId, record, action)
        if valid ~= true then
            removePlateKey(characterId, plate)
            return nil
        end
    end
    if isOrganizationKey(record) then
        local valid = validateOrganizationKey(characterId, record, action)
        if valid ~= true then removePlateKey(characterId, plate); return nil end
    end

    return record
end

local function hasTempKeyByCharacter(characterId, plate, action)
    return getKeyRecordByCharacter(characterId, plate, action) ~= nil
end

local function validateGrantContext(sourceSrc, targetSrc)
    sourceSrc = tonumber(sourceSrc)
    targetSrc = tonumber(targetSrc)

    if not targetSrc or targetSrc <= 0 or not GetPlayerName(targetSrc) then
        return false, 'Target player is not online.'
    end

    -- Source 0/nil is reserved for trusted server-side/system grants.
    if not sourceSrc or sourceSrc <= 0 then return true end
    if not GetPlayerName(sourceSrc) then return false, 'Source player is not online.' end
    if sourceSrc == targetSrc then return false, 'You already have your own vehicle keys.' end

    if Settings.requireSameRoutingBucket ~= false then
        local sourceBucket = GetPlayerRoutingBucket(sourceSrc)
        local targetBucket = GetPlayerRoutingBucket(targetSrc)
        if sourceBucket ~= targetBucket then
            return false, 'Target player is not in the same instance.'
        end
    end

    local sourcePed = GetPlayerPed(sourceSrc)
    local targetPed = GetPlayerPed(targetSrc)
    if not sourcePed or sourcePed == 0 or not targetPed or targetPed == 0 then
        return false, 'Player position is unavailable.'
    end

    local sourceCoords = GetEntityCoords(sourcePed)
    local targetCoords = GetEntityCoords(targetPed)
    if not sourceCoords or not targetCoords then
        return false, 'Player position is unavailable.'
    end

    local dx = (sourceCoords.x or 0.0) - (targetCoords.x or 0.0)
    local dy = (sourceCoords.y or 0.0) - (targetCoords.y or 0.0)
    local dz = (sourceCoords.z or 0.0) - (targetCoords.z or 0.0)
    local distanceSquared = (dx * dx) + (dy * dy) + (dz * dz)
    local maxDistance = math.max(0.5, tonumber(Settings.maxGrantDistance) or 6.0)

    if distanceSquared > (maxDistance * maxDistance) then
        return false, 'Target player is too far away.'
    end

    return true
end

local function calculateExpiry(options)
    options = type(options) == 'table' and options or {}
    local duration = tonumber(options.durationSeconds)
    if duration == nil then duration = tonumber(Settings.defaultDurationSeconds) or 0 end

    duration = math.floor(duration)
    if duration <= 0 then return 0 end

    local maxDuration = math.max(1, tonumber(Settings.maxDurationSeconds) or 86400)
    return os.time() + math.min(duration, maxDuration)
end

local function giveTempKey(sourceSrc, targetSrc, plate, options)
    local valid, validationError = validateGrantContext(sourceSrc, targetSrc)
    if not valid then return false, validationError end

    plate = normalizePlate(plate)
    if plate == '' then return false, 'Invalid plate.' end

    local targetCharacterId = resolveCharacterId(targetSrc)
    if not targetCharacterId then return false, 'Target character is not loaded.' end

    local sourceCharacterId
    sourceSrc = tonumber(sourceSrc)
    if sourceSrc and sourceSrc > 0 then
        sourceCharacterId = resolveCharacterId(sourceSrc)
        if not sourceCharacterId then return false, 'Your character is not loaded.' end
    end

    if hasTempKeyByCharacter(targetCharacterId, plate, 'vehicle.drive') then
        return false, 'Target already has temporary keys for this vehicle.'
    end

    local now = os.time()
    TempKeys[targetCharacterId] = TempKeys[targetCharacterId] or {}
    TempKeys[targetCharacterId][plate] = {
        kind = 'temporary',
        plate = plate,
        characterId = targetCharacterId,
        grantedByCharacterId = sourceCharacterId,
        grantedBySource = sourceSrc and sourceSrc > 0 and sourceSrc or nil,
        grantedAt = now,
        expiresAt = calculateExpiry(options)
    }

    local record = TempKeys[targetCharacterId][plate]
    local expiryText = record.expiresAt > 0 and ' for a limited time.' or ' until you change character or log out.'
    notify(targetSrc, ('You received temporary keys for %s%s'):format(plate, expiryText), 'success')

    debugLog('Granted %s to character %s by %s.', plate, targetCharacterId, sourceCharacterId or 'system')
    return true, nil, record
end

local function grantFamilyKey(targetSrc, plate, context)
    targetSrc = tonumber(targetSrc)
    context = type(context) == 'table' and context or {}
    if not targetSrc or targetSrc <= 0 or not GetPlayerName(targetSrc) then
        return false, 'Target player is not online.'
    end

    plate = normalizePlate(plate)
    if plate == '' then return false, 'Invalid plate.' end

    local targetCharacterId = resolveCharacterId(targetSrc)
    if not targetCharacterId then return false, 'Target character is not loaded.' end

    local vehicleId = tonumber(context.vehicleId or context.vehicle_id)
    local familyId = tonumber(context.familyId or context.family_id)
    if not vehicleId or not familyId then return false, 'Family vehicle context is incomplete.' end

    local valid, reason, verified = validateFamilyKey(targetCharacterId, {
        kind = 'family',
        vehicleId = vehicleId,
        familyId = familyId,
    }, context.action or 'vehicle.drive')
    if valid ~= true then return false, tostring(reason or 'Family access denied.') end

    TempKeys[targetCharacterId] = TempKeys[targetCharacterId] or {}
    local existing = TempKeys[targetCharacterId][plate]
    if existing and not isFamilyKey(existing) then
        -- A manually lent key is stronger and must never be converted into a
        -- revocable family key.
        return true, nil, existing
    end

    local now = os.time()
    local familyName = tostring(context.familyName or (verified and verified.familyName) or 'Family')
    local firstGrant = not existing
    TempKeys[targetCharacterId][plate] = {
        kind = 'family',
        plate = plate,
        characterId = targetCharacterId,
        familyId = familyId,
        familyName = familyName,
        vehicleId = vehicleId,
        requiredTier = tonumber(context.requiredTier or (verified and verified.requiredTier)),
        grantedAt = existing and existing.grantedAt or now,
        refreshedAt = now,
        expiresAt = 0,
    }

    if firstGrant then
        notify(targetSrc, ('Family vehicle access granted for %s · %s.'):format(plate, familyName), 'success')
    end
    debugLog('Granted family key %s to character %s for family %s vehicle %s.',
        plate, targetCharacterId, familyId, vehicleId)
    return true, nil, TempKeys[targetCharacterId][plate]
end

local function grantOrganizationKey(targetSrc, plate, context)
    targetSrc, context = tonumber(targetSrc), type(context) == 'table' and context or {}
    if not targetSrc or targetSrc <= 0 or not GetPlayerName(targetSrc) then return false, 'target_offline' end
    plate = normalizePlate(plate)
    local characterId, vehicleId = resolveCharacterId(targetSrc), tonumber(context.vehicleId)
    local organizationId, ownerResource = tostring(context.organizationId or ''), tostring(context.ownerResource or '')
    if plate == '' or not characterId or not vehicleId or organizationId == '' or ownerResource == '' then return false, 'organization_context_incomplete' end
    local valid, reason = validateOrganizationKey(characterId, {
        kind='organization', vehicleId=vehicleId, organizationId=organizationId, ownerResource=ownerResource,
    }, context.action or 'vehicle.drive')
    if valid ~= true then return false, reason end
    TempKeys[characterId] = TempKeys[characterId] or {}
    TempKeys[characterId][plate] = { kind='organization', plate=plate, characterId=characterId, vehicleId=vehicleId,
        organizationId=organizationId, ownerResource=ownerResource, grantedAt=os.time(), expiresAt=0 }
    return true, nil, TempKeys[characterId][plate]
end

local function revokeOrganizationKeys(filter)
    filter = type(filter) == 'table' and filter or {}
    local removed = 0
    for characterId, keys in pairs(TempKeys) do
        for plate, record in pairs(keys) do
            if isOrganizationKey(record)
                and (not filter.characterId or tostring(characterId) == tostring(filter.characterId))
                and (not filter.vehicleId or tonumber(record.vehicleId) == tonumber(filter.vehicleId))
                and (not filter.organizationId or tostring(record.organizationId) == tostring(filter.organizationId))
                and (not filter.ownerResource or tostring(record.ownerResource) == tostring(filter.ownerResource)) then
                keys[plate], removed = nil, removed + 1
            end
        end
        if next(keys) == nil then TempKeys[characterId] = nil end
    end
    return removed
end

local function revokeFamilyKeysForCharacter(characterId, reason)
    characterId = normalizeCharacterId(characterId)
    if not characterId then return 0 end
    local keys = TempKeys[characterId]
    if not keys then return 0 end

    local removed = 0
    for plate, record in pairs(keys) do
        if isFamilyKey(record) then
            keys[plate] = nil
            removed = removed + 1
        end
    end
    if next(keys) == nil then TempKeys[characterId] = nil end
    debugLog('Revoked %s family keys for character %s (%s).', removed, characterId, reason or 'unknown')
    return removed
end

local function revokeFamilyKeysForVehicle(vehicleId, familyId, reason)
    vehicleId = tonumber(vehicleId)
    familyId = tonumber(familyId)
    if not vehicleId then return 0 end
    local removed = 0
    for characterId, keys in pairs(TempKeys) do
        for plate, record in pairs(keys) do
            if isFamilyKey(record)
                and tonumber(record.vehicleId) == vehicleId
                and (not familyId or tonumber(record.familyId) == familyId) then
                keys[plate] = nil
                removed = removed + 1
            end
        end
        if next(keys) == nil then TempKeys[characterId] = nil end
    end
    debugLog('Revoked %s family keys for vehicle %s family %s (%s).',
        removed, vehicleId, familyId or '*', reason or 'unknown')
    return removed
end

local function revokeFamilyKeysForFamily(familyId, reason)
    familyId = tonumber(familyId)
    if not familyId then return 0 end
    local removed = 0
    for characterId, keys in pairs(TempKeys) do
        for plate, record in pairs(keys) do
            if isFamilyKey(record) and tonumber(record.familyId) == familyId then
                keys[plate] = nil
                removed = removed + 1
            end
        end
        if next(keys) == nil then TempKeys[characterId] = nil end
    end
    debugLog('Revoked %s family keys for family %s (%s).', removed, familyId, reason or 'unknown')
    return removed
end

local function copyRecord(record)
    return {
        kind = record.kind or 'temporary',
        plate = record.plate,
        characterId = record.characterId,
        grantedByCharacterId = record.grantedByCharacterId,
        familyId = record.familyId,
        familyName = record.familyName,
        vehicleId = record.vehicleId,
        requiredTier = record.requiredTier,
        organizationId = record.organizationId,
        ownerResource = record.ownerResource,
        grantedAt = record.grantedAt,
        refreshedAt = record.refreshedAt,
        expiresAt = record.expiresAt
    }
end

local function getCharacterKeys(characterId)
    characterId = normalizeCharacterId(characterId)
    if not characterId then return {} end

    local result = {}
    local keys = TempKeys[characterId]
    if not keys then return result end

    local now = os.time()
    for plate, record in pairs(keys) do
        if isExpired(record, now) then
            removePlateKey(characterId, plate)
        elseif getKeyRecordByCharacter(characterId, plate, 'vehicle.drive') then
            result[#result + 1] = copyRecord(record)
        end
    end

    table.sort(result, function(a, b)
        return tostring(a.plate) < tostring(b.plate)
    end)
    return result
end

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local characterId = ActiveCharacters[src]
    ActiveCharacters[src] = nil

    if characterId then
        clearCharacterKeys(characterId, 'disconnect')
    end
end)

-- Safe for a client to request: it can only remove its own current session keys.
RegisterNetEvent('cm-vehiclekeys:server:clearMyTempKeys', function()
    local src = tonumber(source)
    local characterId = resolveCharacterId(src)
    if characterId then clearCharacterKeys(characterId, 'client-logout') end
end)

-- Explicit lifecycle exports for cm-playerdata/cm-characters. Polling below is
-- retained as a fail-safe when these are not called.
exports('RegisterCharacter', function(src, characterId)
    src = tonumber(src)
    characterId = normalizeCharacterId(characterId)
    if not src or src <= 0 or not characterId or not GetPlayerName(src) then return false end
    setActiveCharacter(src, characterId, 'explicit-load')
    return true
end)

exports('UnregisterCharacter', function(src, characterId)
    src = tonumber(src)
    if not src or src <= 0 then return false end

    local active = ActiveCharacters[src]
    local expected = normalizeCharacterId(characterId)
    if expected and active and expected ~= active then return false end

    ActiveCharacters[src] = nil
    if active then clearCharacterKeys(active, 'explicit-unload') end
    return true
end)

exports('GetActiveCharacterId', function(src)
    return resolveCharacterId(src)
end)

exports('HasTempKey', function(src, plate)
    return hasTempKeyByCharacter(resolveCharacterId(src), plate, 'vehicle.drive')
end)

exports('HasTempKeyByCharId', function(characterId, plate)
    return hasTempKeyByCharacter(characterId, plate, 'vehicle.drive')
end)

exports('HasVehicleKey', function(src, plate, action)
    return hasTempKeyByCharacter(resolveCharacterId(src), plate, action or 'vehicle.drive')
end)

exports('GetVehicleKeyRecord', function(src, plate, action)
    local record = getKeyRecordByCharacter(resolveCharacterId(src), plate, action or 'vehicle.drive')
    return record and copyRecord(record) or nil
end)

exports('GiveTempKey', function(sourceSrc, targetSrc, plate, options)
    return giveTempKey(sourceSrc, targetSrc, plate, options)
end)

exports('GrantFamilyKey', function(targetSrc, plate, context)
    if not invokingResourceAllowed(Settings.trustedFamilyResources) then
        return false, 'resource_not_authorized'
    end
    return grantFamilyKey(targetSrc, plate, context)
end)

exports('GrantOrganizationKey', function(targetSrc, plate, context)
    if not invokingResourceAllowed(Settings.trustedOrganizationResources) then return false, 'resource_not_authorized' end
    return grantOrganizationKey(targetSrc, plate, context)
end)

exports('RevokeOrganizationKeys', function(filter)
    if not invokingResourceAllowed(Settings.trustedOrganizationResources) then return 0 end
    return revokeOrganizationKeys(filter)
end)

exports('RevokeFamilyKeysForCharacter', function(characterId, reason)
    if not invokingResourceAllowed(Settings.trustedFamilyResources) then return 0 end
    return revokeFamilyKeysForCharacter(characterId, reason)
end)

exports('RevokeFamilyKeysForVehicle', function(vehicleId, familyId, reason)
    if not invokingResourceAllowed(Settings.trustedFamilyResources) then return 0 end
    return revokeFamilyKeysForVehicle(vehicleId, familyId, reason)
end)

exports('RevokeFamilyKeysForFamily', function(familyId, reason)
    if not invokingResourceAllowed(Settings.trustedFamilyResources) then return 0 end
    return revokeFamilyKeysForFamily(familyId, reason)
end)

exports('ClearTempKeys', function(src)
    local characterId = resolveCharacterId(src)
    if not characterId then return false end
    return clearCharacterKeys(characterId, 'server-clear')
end)

exports('ClearTempKeysByCharId', function(characterId)
    return clearCharacterKeys(characterId, 'server-clear-by-character')
end)

exports('RevokeTempKeyByChar', function(plate, characterId)
    return removePlateKey(characterId, plate)
end)

exports('RevokeTempKey', function(src, plate)
    local characterId = resolveCharacterId(src)
    if not characterId then return false end
    return removePlateKey(characterId, plate)
end)

exports('RevokeAllForPlate', function(plate)
    plate = normalizePlate(plate)
    if plate == '' then return 0 end

    local removed = 0
    for characterId in pairs(TempKeys) do
        if removePlateKey(characterId, plate) then removed = removed + 1 end
    end
    return removed
end)

exports('GetTempKeys', function(src)
    return getCharacterKeys(resolveCharacterId(src))
end)

exports('GetTempKeysByCharId', function(characterId)
    return getCharacterKeys(characterId)
end)

CreateThread(function()
    local interval = math.max(1000, tonumber(Settings.characterPollIntervalMs) or 2500)

    while true do
        Wait(interval)
        local online = {}

        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            online[src] = true

            local observedCharacterId = getStateCharacterId(src)
            local activeCharacterId = ActiveCharacters[src]

            if observedCharacterId and observedCharacterId ~= activeCharacterId then
                setActiveCharacter(src, observedCharacterId, 'poll-switch')
            elseif not observedCharacterId and activeCharacterId then
                ActiveCharacters[src] = nil
                clearCharacterKeys(activeCharacterId, 'poll-unload')
            end
        end

        -- Defensive cleanup in case a disconnect handler was skipped during a
        -- resource restart or player teardown race.
        for src, characterId in pairs(ActiveCharacters) do
            if not online[src] then
                ActiveCharacters[src] = nil
                clearCharacterKeys(characterId, 'offline-cleanup')
            end
        end

        -- Expired time-limited keys are pruned even when they are not queried.
        local now = os.time()
        for characterId, keys in pairs(TempKeys) do
            for plate, record in pairs(keys) do
                if isExpired(record, now) then
                    removePlateKey(characterId, plate)
                elseif isFamilyKey(record) or isOrganizationKey(record) then
                    getKeyRecordByCharacter(characterId, plate, 'vehicle.drive')
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == 'cm-family' or resourceName == 'cm-vehicles' then
        local characters = {}
        for characterId in pairs(TempKeys) do characters[#characters + 1] = characterId end
        for i = 1, #characters do
            revokeFamilyKeysForCharacter(characters[i], resourceName .. '-stopped')
        end
        return
    end
    if resourceName == 'cm-gang' then revokeOrganizationKeys({ ownerResource = 'cm-gang' }); return end
    if resourceName ~= RESOURCE then return end
    TempKeys = {}
    ActiveCharacters = {}
end)

CreateThread(function()
    Wait(0)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local characterId = getStateCharacterId(src)
        if characterId then setActiveCharacter(src, characterId, 'resource-start') end
    end

    print(('[CM-VEHICLEKEYS] Started v1.2.0 | manual + revocable family session keys enabled'))
end)
