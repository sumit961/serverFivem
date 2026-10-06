CMDiscovery = CMDiscovery or {}

local RESOURCE = GetCurrentResourceName()
local requestLocks = {}
local adminLocks = {}
local sourceCharacters = {}

local function result(ok, reason, extra)
    local value = extra or {}
    value.ok = ok
    if reason then value.reason = reason end
    return value
end

local function trim(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%z\1-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > max then return nil end
    return value
end

local function safeCharacterId(value)
    value = trim(tostring(value or ''), 64)
    if not value or not value:match('^[%w_%-]+$') then return nil end
    return value
end

local function safeLandmarkId(value)
    value = trim(tostring(value or ''):lower(), Config.Security.maxLandmarkId)
    if not value or not value:match('^[a-z0-9][a-z0-9_%-]*$') then return nil end
    return value
end

local function databaseReady()
    return CMDiscovery.DatabaseReady == true
end

local function lock(bucket, key, milliseconds)
    local now = GetGameTimer()
    local lockKey = ('%s:%s'):format(bucket, tostring(key))
    if (bucket == 'admin' and adminLocks[lockKey] or requestLocks[lockKey] or 0) > now then
        return false
    end
    if bucket == 'admin' then
        adminLocks[lockKey] = now + milliseconds
    else
        requestLocks[lockKey] = now + milliseconds
    end
    return true
end

local function currentCharacter(src)
    src = tonumber(src)
    if not src or src <= 0 or GetPlayerName(src) == nil then return nil end

    local loadedOk, loaded = pcall(function()
        return exports['cm-playerdata']:IsCharacterLoaded(src)
    end)
    if not loadedOk or loaded ~= true then return nil end

    local idOk, rawId = pcall(function()
        return exports['cm-playerdata']:GetCharacterId(src)
    end)
    local characterId = idOk and safeCharacterId(rawId) or nil
    if characterId then sourceCharacters[src] = characterId end
    return characterId
end

local function playerDead(src)
    local ok, dead = pcall(function()
        return exports['cm-playerdata']:IsDead(src)
    end)
    -- An unavailable lifecycle owner must fail closed rather than allowing a
    -- discovery request while the player state cannot be verified.
    return not ok or dead ~= false
end

local function numberInRange(value, min, max)
    value = tonumber(value)
    return value and value >= min and value <= max and value or nil
end

local function optionalInteger(value, min, max)
    if value == nil or tostring(value) == '' then return nil end
    value = tonumber(value)
    if not value or value % 1 ~= 0 or value < min or value > max then return nil end
    return value
end

local function normalizeLandmark(raw, existing)
    if type(raw) ~= 'table' then return nil, 'invalid_landmark' end

    local id = safeLandmarkId(raw.landmarkId or raw.landmark_id or (existing and existing.landmark_id))
    local name = trim(tostring(raw.name or (existing and existing.name) or ''), Config.Security.maxName)
    local description = trim(tostring(raw.description or (existing and existing.description) or ''), Config.Security.maxDescription) or ''
    local category = trim(tostring(raw.category or (existing and existing.category) or ''), Config.Security.maxCategory)
    local displayLabel = trim(tostring(raw.displayLabel or raw.display_label or (existing and existing.display_label) or ''), Config.Security.maxDisplayLabel)
    local enabled = raw.enabled
    if enabled == nil and existing then enabled = tonumber(existing.enabled) == 1 end
    enabled = enabled == true or tonumber(enabled) == 1

    local x = raw.x ~= nil and tonumber(raw.x) or (existing and tonumber(existing.x))
    local y = raw.y ~= nil and tonumber(raw.y) or (existing and tonumber(existing.y))
    local z = raw.z ~= nil and tonumber(raw.z) or (existing and tonumber(existing.z))
    local radius = raw.radius ~= nil and tonumber(raw.radius) or (existing and tonumber(existing.radius))
    local heading = raw.heading ~= nil and tonumber(raw.heading) or (existing and tonumber(existing.heading))
    local routingBucket = raw.routingBucket
    if routingBucket == nil then routingBucket = raw.routing_bucket end
    if routingBucket == nil and existing then routingBucket = existing.routing_bucket end
    if routingBucket ~= nil and tostring(routingBucket) ~= '' then
        routingBucket = optionalInteger(routingBucket, 0, Config.Security.maxRoutingBucket)
        if routingBucket == nil then return nil, 'invalid_routing_bucket' end
    else
        routingBucket = nil
    end

    local blip = type(raw.blip) == 'table' and raw.blip or {}
    local blipEnabled = blip.enabled
    if blipEnabled == nil and existing then blipEnabled = tonumber(existing.blip_enabled) == 1 end
    blipEnabled = blipEnabled == true or tonumber(blipEnabled) == 1
    local blipSprite = blip.sprite ~= nil and optionalInteger(blip.sprite, 0, Config.Security.maxBlipSprite) or (existing and tonumber(existing.blip_sprite))
    local blipColor = blip.color ~= nil and optionalInteger(blip.color, 0, Config.Security.maxBlipColor) or (existing and tonumber(existing.blip_color))
    local blipScale = blip.scale ~= nil and numberInRange(blip.scale, 0.1, Config.Security.maxBlipScale) or (existing and tonumber(existing.blip_scale))
    if blip.sprite ~= nil and tostring(blip.sprite) ~= '' and blipSprite == nil then return nil, 'invalid_blip_sprite' end
    if blip.color ~= nil and tostring(blip.color) ~= '' and blipColor == nil then return nil, 'invalid_blip_color' end
    if blip.scale ~= nil and tostring(blip.scale) ~= '' and blipScale == nil then return nil, 'invalid_blip_scale' end

    if not id or not name or not category then return nil, 'missing_landmark_identity' end
    if x and (x < Config.Security.minCoordinate or x > Config.Security.maxCoordinate) then return nil, 'invalid_x' end
    if y and (y < Config.Security.minCoordinate or y > Config.Security.maxCoordinate) then return nil, 'invalid_y' end
    if z and (z < Config.Security.minZ or z > Config.Security.maxZ) then return nil, 'invalid_z' end
    if heading and (heading < 0 or heading >= Config.Security.maxHeading) then return nil, 'invalid_heading' end
    if radius and (radius < Config.Security.minRadius or radius > Config.Security.maxRadius) then return nil, 'invalid_radius' end

    if enabled and (not x or not y or not z or not radius) then
        return nil, 'enabled_landmark_requires_coordinates_and_radius'
    end

    -- Disabled records retain descriptive data but never retain an incomplete
    -- active location that could accidentally become discoverable.
    if not enabled then
        x, y, z, radius, heading, routingBucket = nil, nil, nil, nil, nil, nil
        blipEnabled, blipSprite, blipColor, blipScale = false, nil, nil, nil
    end

    return {
        landmarkId = id,
        name = name,
        description = description,
        category = category,
        enabled = enabled,
        x = x, y = y, z = z, radius = radius, heading = heading,
        blipEnabled = blipEnabled,
        blipSprite = blipSprite,
        blipColor = blipColor,
        blipScale = blipScale,
        displayLabel = displayLabel,
        routingBucket = routingBucket,
    }
end

local function validConfiguredRow(row, includeDisabled)
    if not row then return false end
    if not includeDisabled and tonumber(row.enabled) ~= 1 then return false end
    local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    local radius = tonumber(row.radius)
    return row.name and row.name ~= '' and row.category and row.category ~= ''
        and (includeDisabled or tonumber(row.enabled) == 1)
        and (includeDisabled or (x and y and z and radius and radius >= Config.Security.minRadius and radius <= Config.Security.maxRadius))
end

local function rowToClient(row)
    return {
        id = row.landmark_id,
        name = row.name,
        description = row.description,
        category = row.category,
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
        radius = tonumber(row.radius), heading = tonumber(row.heading),
        displayLabel = row.display_label,
        blip = {
            enabled = tonumber(row.blip_enabled) == 1,
            sprite = tonumber(row.blip_sprite),
            color = tonumber(row.blip_color),
            scale = tonumber(row.blip_scale),
        },
        routingBucket = tonumber(row.routing_bucket),
    }
end

local function getLandmark(id)
    return MySQL.single.await([[SELECT landmark_id, name, description, category, enabled,
        x, y, z, radius, heading, blip_enabled, blip_sprite, blip_color,
        blip_scale, display_label, routing_bucket
        FROM cm_discovery_landmarks WHERE landmark_id = ? LIMIT 1]], { id })
end

local function adminAuthorized(adminSrc)
    local invoking = GetInvokingResource()
    if invoking ~= Config.Admin.invokingResource then return false end
    if GetResourceState(Config.Admin.invokingResource) ~= 'started' then return false end
    adminSrc = tonumber(adminSrc)
    if not adminSrc or adminSrc <= 0 then return false end
    local ok, allowed = pcall(function()
        return exports[Config.Admin.invokingResource]:HasPermission(adminSrc, Config.Admin.permission)
    end)
    return ok and allowed == true
end

local function adminCharacter(adminSrc)
    return currentCharacter(adminSrc)
end

local function broadcastLandmarkRefresh()
    for _, player in ipairs(GetPlayers()) do
        TriggerClientEvent('cm-discovery:client:refreshLandmarks', tonumber(player))
    end
end

local function adminMutation(adminSrc)
    if not adminAuthorized(adminSrc) then return false, 'admin_permission_required' end
    if not databaseReady() then return false, 'database_unavailable' end
    if not lock('admin', adminSrc, Config.Security.adminCooldownMs) then return false, 'rate_limited' end
    return true
end

exports('AdminCreateLandmark', function(adminSrc, raw)
    local allowed, reason = adminMutation(adminSrc)
    if not allowed then return result(false, reason) end
    local landmark, normalizeReason = normalizeLandmark(raw)
    if not landmark then return result(false, normalizeReason) end
    if getLandmark(landmark.landmarkId) then return result(false, 'landmark_exists') end
    local actor = adminCharacter(adminSrc)
    local inserted = MySQL.update.await([[INSERT IGNORE INTO cm_discovery_landmarks
        (landmark_id, name, description, category, enabled, x, y, z, radius,
         heading, blip_enabled, blip_sprite, blip_color, blip_scale,
         display_label, routing_bucket, created_by_character_id, updated_by_character_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        landmark.landmarkId, landmark.name, landmark.description, landmark.category,
        landmark.enabled and 1 or 0, landmark.x, landmark.y, landmark.z,
        landmark.radius, landmark.heading, landmark.blipEnabled and 1 or 0,
        landmark.blipSprite, landmark.blipColor, landmark.blipScale,
        landmark.displayLabel, landmark.routingBucket, actor, actor,
    })
    if inserted == nil or tonumber(inserted) < 1 then return result(false, 'landmark_create_failed') end
    local created = getLandmark(landmark.landmarkId)
    if not created then return result(false, 'landmark_create_failed') end
    broadcastLandmarkRefresh()
    return result(true, nil, { landmark = rowToClient(created) })
end)

exports('AdminUpdateLandmark', function(adminSrc, landmarkId, raw)
    local allowed, reason = adminMutation(adminSrc)
    if not allowed then return result(false, reason) end
    local id = safeLandmarkId(landmarkId)
    if not id then return result(false, 'invalid_landmark_id') end
    local existing = getLandmark(id)
    if not existing then return result(false, 'landmark_not_found') end
    raw = type(raw) == 'table' and raw or {}
    raw.landmarkId = id
    local landmark, normalizeReason = normalizeLandmark(raw, existing)
    if not landmark then return result(false, normalizeReason) end
    local actor = adminCharacter(adminSrc)
    local changed = MySQL.update.await([[UPDATE cm_discovery_landmarks SET
        name = ?, description = ?, category = ?, enabled = ?, x = ?, y = ?, z = ?,
        radius = ?, heading = ?, blip_enabled = ?, blip_sprite = ?, blip_color = ?,
        blip_scale = ?, display_label = ?, routing_bucket = ?, updated_by_character_id = ?
        WHERE landmark_id = ?]], {
        landmark.name, landmark.description, landmark.category, landmark.enabled and 1 or 0,
        landmark.x, landmark.y, landmark.z, landmark.radius, landmark.heading,
        landmark.blipEnabled and 1 or 0, landmark.blipSprite, landmark.blipColor,
        landmark.blipScale, landmark.displayLabel, landmark.routingBucket, actor, id,
    })
    if changed == nil then return result(false, 'landmark_update_failed') end
    broadcastLandmarkRefresh()
    return result(true, nil, { landmark = rowToClient(getLandmark(id)) })
end)

exports('AdminSetLandmarkEnabled', function(adminSrc, landmarkId, enabled)
    local allowed, reason = adminMutation(adminSrc)
    if not allowed then return result(false, reason) end
    local id = safeLandmarkId(landmarkId)
    if not id then return result(false, 'invalid_landmark_id') end
    local existing = getLandmark(id)
    if not existing then return result(false, 'landmark_not_found') end
    enabled = enabled == true or tonumber(enabled) == 1
    if enabled and not validConfiguredRow(existing, false) then
        return result(false, 'landmark_requires_valid_configuration')
    end
    local actor = adminCharacter(adminSrc)
    local changed
    if enabled then
        changed = MySQL.update.await([[UPDATE cm_discovery_landmarks
            SET enabled = 1, updated_by_character_id = ? WHERE landmark_id = ?]], { actor, id })
    else
        changed = MySQL.update.await([[UPDATE cm_discovery_landmarks SET
            enabled = 0, x = NULL, y = NULL, z = NULL, radius = NULL, heading = NULL,
            blip_enabled = 0, blip_sprite = NULL, blip_color = NULL, blip_scale = NULL,
            routing_bucket = NULL, updated_by_character_id = ? WHERE landmark_id = ?]], { actor, id })
    end
    if changed == nil then return result(false, 'landmark_update_failed') end
    broadcastLandmarkRefresh()
    return result(true, nil, { enabled = enabled })
end)

exports('AdminListLandmarks', function(adminSrc)
    if not adminAuthorized(adminSrc) then return result(false, 'admin_permission_required') end
    if not databaseReady() then return result(false, 'database_unavailable') end
    local rows = MySQL.query.await([[SELECT landmark_id, name, description, category, enabled,
        x, y, z, radius, heading, blip_enabled, blip_sprite, blip_color,
        blip_scale, display_label, routing_bucket, created_by_character_id,
        updated_by_character_id, created_at, updated_at
        FROM cm_discovery_landmarks ORDER BY category ASC, name ASC]], {}) or {}
    for _, row in ipairs(rows) do row.enabled = tonumber(row.enabled) == 1 end
    return result(true, nil, { landmarks = rows })
end)

local function authorizeDiscovery(src, rawId)
    local id = safeLandmarkId(rawId)
    if not id then return nil, result(false, 'invalid_landmark_id') end
    local cid = currentCharacter(src)
    if not cid then return nil, result(false, 'character_unavailable') end
    if playerDead(src) then return nil, result(false, 'player_unavailable') end
    if not lock('discover', cid, Config.Security.discoveryCooldownMs) then return nil, result(false, 'rate_limited') end

    local landmark = getLandmark(id)
    if not validConfiguredRow(landmark, false) then return nil, result(false, 'landmark_unavailable') end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) <= 0 then return nil, result(false, 'player_unavailable') end
    if landmark.routing_bucket ~= nil and tonumber(landmark.routing_bucket) ~= GetPlayerRoutingBucket(src) then
        return nil, result(false, 'routing_bucket_mismatch')
    end

    local coords = GetEntityCoords(ped)
    if not coords then return nil, result(false, 'player_unavailable') end
    local dx, dy, dz = coords.x - tonumber(landmark.x), coords.y - tonumber(landmark.y), coords.z - tonumber(landmark.z)
    local radius = tonumber(landmark.radius)
    if (dx * dx + dy * dy + dz * dz) > (radius * radius) then
        return nil, result(false, 'too_far_away')
    end
    return { characterId = cid, landmark = landmark }
end

local function discoveryRecord(cid, id)
    return MySQL.single.await([[SELECT discovered_at FROM cm_discoveries
        WHERE character_id = ? AND landmark_id = ? LIMIT 1]], { cid, id })
end

lib.callback.register('cm-discovery:server:discover', function(src, request)
    if not databaseReady() then return result(false, 'database_unavailable') end
    request = type(request) == 'table' and request or {}
    local auth, failure = authorizeDiscovery(src, request.landmarkId or request.landmark_id)
    if not auth then return failure end

    local id, cid = auth.landmark.landmark_id, auth.characterId
    local existing = discoveryRecord(cid, id)
    if existing then
        return result(true, nil, {
            alreadyDiscovered = true,
            discoveredAt = existing.discovered_at,
            landmark = rowToClient(auth.landmark),
        })
    end

    -- The composite primary key makes this insert idempotent under concurrent
    -- requests. No UPDATE is ever performed, preserving the first timestamp.
    local inserted = MySQL.update.await([[INSERT IGNORE INTO cm_discoveries (character_id, landmark_id)
        VALUES (?, ?)]], { cid, id })
    local record = discoveryRecord(cid, id)
    if not record then return result(false, 'discovery_unavailable') end
    return result(true, nil, {
        alreadyDiscovered = tonumber(inserted) ~= 1,
        discoveredAt = record.discovered_at,
        landmark = rowToClient(auth.landmark),
    })
end)

lib.callback.register('cm-discovery:server:getWorldLandmarks', function(src)
    if not databaseReady() or not currentCharacter(src) then return {} end
    local rows = MySQL.query.await([[SELECT landmark_id, name, description, category,
        x, y, z, radius, heading, blip_enabled, blip_sprite, blip_color,
        blip_scale, display_label, routing_bucket
        FROM cm_discovery_landmarks WHERE enabled = 1
        ORDER BY category ASC, name ASC]], {}) or {}
    local visible = {}
    for _, row in ipairs(rows) do
        if validConfiguredRow(row, false) then visible[#visible + 1] = rowToClient(row) end
    end
    return visible
end)

lib.callback.register('cm-discovery:server:getChecklist', function(src)
    if not databaseReady() then return result(false, 'database_unavailable') end
    local cid = currentCharacter(src)
    if not cid then return result(false, 'character_unavailable') end
    local rows = MySQL.query.await([[SELECT l.landmark_id, l.name, l.description,
        l.category, l.enabled, l.x, l.y, l.z, l.radius, l.display_label,
        d.discovered_at
        FROM cm_discovery_landmarks l
        LEFT JOIN cm_discoveries d ON d.landmark_id = l.landmark_id AND d.character_id = ?
        ORDER BY l.category ASC, l.name ASC]], { cid }) or {}
    local landmarks, categories = {}, {}
    local categorySeen = {}
    local discovered, total = 0, 0
    for _, row in ipairs(rows) do
        local wasDiscovered = row.discovered_at ~= nil
        local enabled = tonumber(row.enabled) == 1 and validConfiguredRow(row, false)
        -- Historical discoveries remain visible after an administrator
        -- disables a landmark, but disabled undiscovered records stay hidden.
        if enabled or wasDiscovered then
            if enabled then total = total + 1 end
            if enabled and wasDiscovered then discovered = discovered + 1 end
            if not categorySeen[row.category] then
                categorySeen[row.category] = true
                categories[#categories + 1] = row.category
            end
            landmarks[#landmarks + 1] = {
                id = row.landmark_id,
                name = row.name,
                description = row.description,
                category = row.category,
                enabled = enabled,
                discovered = wasDiscovered,
                discoveredAt = row.discovered_at,
                displayLabel = row.display_label,
            }
        end
    end
    return result(true, nil, {
        landmarks = landmarks,
        categories = categories,
        progress = {
            discovered = discovered,
            total = total,
            percent = total > 0 and math.floor((discovered / total) * 100 + 0.5) or 0,
        },
    })
end)

local function clearSource(src)
    src = tonumber(src)
    if not src then return end
    local characterId = sourceCharacters[src]
    if characterId then requestLocks[('discover:%s'):format(characterId)] = nil end
    requestLocks[('discover:%s'):format(src)] = nil
    sourceCharacters[src] = nil
end

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    clearSource(src)
end)

AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, isDead)
    if isDead == true then clearSource(src) end
end)

AddEventHandler('playerDropped', function()
    clearSource(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then
        requestLocks, adminLocks, sourceCharacters = {}, {}, {}
    end
end)
