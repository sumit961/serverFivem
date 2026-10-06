CMCityCalendar = CMCityCalendar or {}

local RESOURCE = GetCurrentResourceName()
local actionLocks = {}
local adminLocks = {}
local eventLocks = {}
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

local function characterId(value)
    value = trim(tostring(value or ''), 64)
    if not value or not value:match('^[%w_%-]+$') then return nil end
    return value
end

local function eventId(value)
    value = trim(tostring(value or ''):lower(), Config.Security.maxEventId)
    if not value or not value:match('^[a-z0-9][a-z0-9_%-]*$') then return nil end
    return value
end

local function now()
    return os.time()
end

local function databaseReady()
    return CMCityCalendar.DatabaseReady == true
end

local function lock(bucket, key, milliseconds)
    local locks = bucket == 'admin' and adminLocks or actionLocks
    local lockKey = ('%s:%s'):format(bucket, tostring(key))
    local current = GetGameTimer()
    if (locks[lockKey] or 0) > current then return false end
    locks[lockKey] = current + milliseconds
    return true
end

local function eventLock(id)
    if eventLocks[id] then return false end
    eventLocks[id] = true
    return true
end

local function releaseEventLock(id)
    eventLocks[id] = nil
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
    local id = idOk and characterId(rawId) or nil
    if id then sourceCharacters[src] = id end
    return id
end

local function isDead(src)
    local ok, dead = pcall(function()
        return exports['cm-playerdata']:IsDead(src)
    end)
    return not ok or dead ~= false
end

local function clampInteger(value, min, max)
    value = tonumber(value)
    if not value or value % 1 ~= 0 or value < min or value > max then return nil end
    return value
end

local function optionalInteger(value, min, max)
    if value == nil or tostring(value) == '' then return nil end
    return clampInteger(value, min, max)
end

local function validCoordinate(value, min, max)
    value = tonumber(value)
    if not value or value < min or value > max then return nil end
    return value
end

local function colour(value)
    if value == nil or tostring(value) == '' then return nil end
    value = trim(tostring(value), Config.Security.maxColourLength)
    if not value or not value:match('^#[%da-fA-F]{6}$') then return nil end
    return value:upper()
end

local function parseLocation(raw, existing)
    local location = raw.location
    if location == false then
        return nil, nil, nil, nil, nil, nil
    end
    if location == nil then
        location = raw
    end
    if type(location) ~= 'table' then
        if existing and existing.x ~= nil then
            return tonumber(existing.x), tonumber(existing.y), tonumber(existing.z),
                tonumber(existing.attendance_radius), tonumber(existing.heading), tonumber(existing.routing_bucket)
        end
        return nil, nil, nil, nil, nil, nil
    end

    local x = location.x
    local y = location.y
    local z = location.z
    local radius = location.radius or location.attendanceRadius or location.attendance_radius
    local heading = location.heading
    local bucket = location.routingBucket or location.routing_bucket
    if x == nil and existing then x = existing.x end
    if y == nil and existing then y = existing.y end
    if z == nil and existing then z = existing.z end
    if radius == nil and existing then radius = existing.attendance_radius end
    if heading == nil and existing then heading = existing.heading end
    if bucket == nil and existing then bucket = existing.routing_bucket end
    return tonumber(x), tonumber(y), tonumber(z), tonumber(radius), tonumber(heading), bucket
end

local function normalizeEvent(raw, existing)
    if type(raw) ~= 'table' then return nil, 'invalid_event' end
    local id = eventId(raw.eventId or raw.event_id or (existing and existing.event_id))
    local title = trim(tostring(raw.title or (existing and existing.title) or ''), Config.Security.maxTitle)
    local description = trim(tostring(raw.description or (existing and existing.description) or ''), Config.Security.maxDescription) or ''
    local category = trim(tostring(raw.category or (existing and existing.category) or ''), Config.Security.maxCategory)
    local displayLabel = trim(tostring(raw.displayLabel or raw.display_label or (existing and existing.display_label) or ''), Config.Security.maxDisplayLabel)
    local displayColour = raw.colour or raw.color
    if displayColour == nil and existing then displayColour = existing.colour end
    if displayColour ~= nil and tostring(displayColour) ~= '' then
        displayColour = colour(displayColour)
        if not displayColour then return nil, 'invalid_colour' end
    end

    local enabled = raw.enabled
    if enabled == nil and existing then enabled = tonumber(existing.enabled) == 1 end
    enabled = enabled == true or tonumber(enabled) == 1

    local startAt = raw.startAt or raw.start_at or (existing and existing.start_ts)
    local endAt = raw.endAt or raw.end_at or (existing and existing.end_ts)
    startAt = clampInteger(startAt, 1, 4102444800)
    endAt = clampInteger(endAt, 1, 4102444800)
    if not startAt or not endAt or endAt <= startAt then return nil, 'invalid_event_window' end
    if endAt - startAt > Config.Security.maxEventDurationSeconds then return nil, 'event_window_too_long' end

    local capacity = raw.capacity
    if capacity == nil and existing then capacity = existing.capacity end
    if capacity ~= nil and tostring(capacity) ~= '' then
        capacity = optionalInteger(capacity, 1, Config.Security.maxCapacity)
        if not capacity then return nil, 'invalid_capacity' end
    else
        capacity = nil
    end

    local x, y, z, radius, heading, routingBucket = parseLocation(raw, existing)
    local coordinatesPresent = x ~= nil or y ~= nil or z ~= nil or radius ~= nil
    if coordinatesPresent and (not x or not y or not z or not radius) then
        return nil, 'location_requires_coordinates_and_radius'
    end
    if x and not validCoordinate(x, Config.Security.minCoordinate, Config.Security.maxCoordinate) then return nil, 'invalid_x' end
    if y and not validCoordinate(y, Config.Security.minCoordinate, Config.Security.maxCoordinate) then return nil, 'invalid_y' end
    if z and not validCoordinate(z, Config.Security.minZ, Config.Security.maxZ) then return nil, 'invalid_z' end
    if radius and (radius < Config.Security.minRadius or radius > Config.Security.maxRadius) then return nil, 'invalid_attendance_radius' end
    if heading and (heading < 0 or heading >= Config.Security.maxHeading) then return nil, 'invalid_heading' end
    if routingBucket ~= nil and tostring(routingBucket) ~= '' then
        routingBucket = optionalInteger(routingBucket, 0, Config.Security.maxRoutingBucket)
        if routingBucket == nil then return nil, 'invalid_routing_bucket' end
    else
        routingBucket = nil
    end

    if not id or not title or not category then return nil, 'missing_event_identity' end
    if enabled and endAt <= now() then return nil, 'expired_event_cannot_be_enabled' end

    return {
        eventId = id,
        title = title,
        description = description,
        category = category,
        enabled = enabled,
        startAt = startAt,
        endAt = endAt,
        capacity = capacity,
        x = x, y = y, z = z, radius = radius,
        heading = heading, colour = displayColour,
        displayLabel = displayLabel,
        routingBucket = routingBucket,
    }
end

local function adminAuthorized(adminSrc)
    if GetInvokingResource() ~= Config.Admin.invokingResource then return false end
    if GetResourceState(Config.Admin.invokingResource) ~= 'started' then return false end
    adminSrc = tonumber(adminSrc)
    if not adminSrc or adminSrc <= 0 then return false end
    local ok, allowed = pcall(function()
        return exports[Config.Admin.invokingResource]:HasPermission(adminSrc, Config.Admin.permission)
    end)
    return ok and allowed == true
end

local function adminMutation(adminSrc)
    if not adminAuthorized(adminSrc) then return false, 'admin_permission_required' end
    if not databaseReady() then return false, 'database_unavailable' end
    if not lock('admin', adminSrc, Config.Security.adminCooldownMs) then return false, 'rate_limited' end
    return true
end

local function adminCharacter(adminSrc)
    return currentCharacter(adminSrc)
end

local function eventRow(id)
    return MySQL.single.await([[SELECT event_id, title, description, category, enabled,
        cancelled, UNIX_TIMESTAMP(start_at) AS start_ts, UNIX_TIMESTAMP(end_at) AS end_ts,
        capacity, rsvp_count, x, y, z, attendance_radius, heading, colour,
        display_label, routing_bucket, cancellation_reason, UNIX_TIMESTAMP(cancelled_at) AS cancelled_ts
        FROM cm_citycalendar_events WHERE event_id = ? LIMIT 1]], { id })
end

local function publicEvent(row, rsvpStatus, checkedIn, attendanceAt)
    if not row then return nil end
    local capacity = tonumber(row.capacity)
    local count = tonumber(row.rsvp_count) or 0
    return {
        id = row.event_id,
        title = row.title,
        description = row.description,
        category = row.category,
        enabled = tonumber(row.enabled) == 1,
        cancelled = tonumber(row.cancelled) == 1,
        startAt = tonumber(row.start_ts),
        endAt = tonumber(row.end_ts),
        capacity = capacity,
        rsvpCount = count,
        remainingCapacity = capacity and math.max(0, capacity - count) or nil,
        hasLocation = row.x ~= nil and row.y ~= nil and row.z ~= nil and row.attendance_radius ~= nil,
        displayLabel = row.display_label,
        colour = row.colour,
        cancellationReason = row.cancellation_reason,
        rsvpStatus = rsvpStatus,
        checkedIn = checkedIn == true,
        attendanceAt = attendanceAt,
    }
end

local function eventState(row, timestamp)
    if tonumber(row.cancelled) == 1 then return 'cancelled' end
    if tonumber(row.enabled) ~= 1 then return 'unavailable' end
    timestamp = timestamp or now()
    if timestamp < tonumber(row.start_ts) then return 'upcoming' end
    if timestamp < tonumber(row.end_ts) then return 'active' end
    return 'past'
end

local function refreshClients()
    for _, player in ipairs(GetPlayers()) do
        TriggerClientEvent('cm-citycalendar:client:refreshWorldEvents', tonumber(player))
    end
end

local function withEventLock(id, callback)
    if not eventLock(id) then return result(false, 'request_in_progress') end
    local ok, response = pcall(callback)
    releaseEventLock(id)
    if not ok then return result(false, 'request_failed') end
    return response
end

exports('AdminCreateEvent', function(adminSrc, raw)
    local allowed, reason = adminMutation(adminSrc)
    if not allowed then return result(false, reason) end
    local event, normalizeReason = normalizeEvent(raw)
    if not event then return result(false, normalizeReason) end
    if eventRow(event.eventId) then return result(false, 'event_exists') end
    local actor = adminCharacter(adminSrc)
    local changed = MySQL.update.await([[INSERT IGNORE INTO cm_citycalendar_events
        (event_id, title, description, category, enabled, cancelled, start_at, end_at,
         capacity, rsvp_count, x, y, z, attendance_radius, heading, colour,
         display_label, routing_bucket, created_by_character_id, updated_by_character_id)
        VALUES (?, ?, ?, ?, ?, 0, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        event.eventId, event.title, event.description, event.category, event.enabled and 1 or 0,
        event.startAt, event.endAt, event.capacity, event.x, event.y, event.z, event.radius,
        event.heading, event.colour, event.displayLabel, event.routingBucket, actor, actor,
    })
    if changed == nil or tonumber(changed) < 1 then return result(false, 'event_create_failed') end
    local created = eventRow(event.eventId)
    refreshClients()
    return result(true, nil, { event = publicEvent(created) })
end)

exports('AdminUpdateEvent', function(adminSrc, rawId, raw)
    local allowed, reason = adminMutation(adminSrc)
    if not allowed then return result(false, reason) end
    local id = eventId(rawId)
    if not id then return result(false, 'invalid_event_id') end
    return withEventLock(id, function()
        local existing = eventRow(id)
        if not existing then return result(false, 'event_not_found') end
        raw = type(raw) == 'table' and raw or {}
        raw.eventId = id
        local event, normalizeReason = normalizeEvent(raw, existing)
        if not event then return result(false, normalizeReason) end
        if tonumber(existing.cancelled) == 1 and event.enabled then return result(false, 'cancelled_event_cannot_be_enabled') end
        local actor = adminCharacter(adminSrc)
        local changed = MySQL.update.await([[UPDATE cm_citycalendar_events SET
            title = ?, description = ?, category = ?, enabled = ?, start_at = FROM_UNIXTIME(?),
            end_at = FROM_UNIXTIME(?), capacity = ?, x = ?, y = ?, z = ?, attendance_radius = ?,
            heading = ?, colour = ?, display_label = ?, routing_bucket = ?, updated_by_character_id = ?
            WHERE event_id = ?]], {
            event.title, event.description, event.category, event.enabled and 1 or 0,
            event.startAt, event.endAt, event.capacity, event.x, event.y, event.z, event.radius,
            event.heading, event.colour, event.displayLabel, event.routingBucket, actor, id,
        })
        if changed == nil then return result(false, 'event_update_failed') end
        refreshClients()
        return result(true, nil, { event = publicEvent(eventRow(id)) })
    end)
end)

exports('AdminSetEventEnabled', function(adminSrc, rawId, enabled)
    local allowed, reason = adminMutation(adminSrc)
    if not allowed then return result(false, reason) end
    local id = eventId(rawId)
    if not id then return result(false, 'invalid_event_id') end
    enabled = enabled == true or tonumber(enabled) == 1
    return withEventLock(id, function()
        local existing = eventRow(id)
        if not existing then return result(false, 'event_not_found') end
        if enabled then
            if tonumber(existing.cancelled) == 1 then return result(false, 'cancelled_event_cannot_be_enabled') end
            if not existing.start_ts or tonumber(existing.end_ts) <= now() then return result(false, 'expired_event_cannot_be_enabled') end
            local normalized, normalizeReason = normalizeEvent({ eventId = id, enabled = true }, existing)
            if not normalized then return result(false, normalizeReason) end
        end
        local actor = adminCharacter(adminSrc)
        local changed = MySQL.update.await([[UPDATE cm_citycalendar_events
            SET enabled = ?, updated_by_character_id = ? WHERE event_id = ?]], {
            enabled and 1 or 0, actor, id,
        })
        if changed == nil then return result(false, 'event_update_failed') end
        refreshClients()
        return result(true, nil, { enabled = enabled })
    end)
end)

exports('AdminCancelEvent', function(adminSrc, rawId, cancellationReason)
    local allowed, reason = adminMutation(adminSrc)
    if not allowed then return result(false, reason) end
    local id = eventId(rawId)
    if not id then return result(false, 'invalid_event_id') end
    return withEventLock(id, function()
        local existing = eventRow(id)
        if not existing then return result(false, 'event_not_found') end
        if tonumber(existing.cancelled) == 1 then return result(true, nil, { alreadyCancelled = true }) end
        local actor = adminCharacter(adminSrc)
        local safeReason = trim(tostring(cancellationReason or 'Cancelled by administrator.'), Config.Security.maxCancellationReason)
            or 'Cancelled by administrator.'
        local changed = MySQL.update.await([[UPDATE cm_citycalendar_events SET
            enabled = 0, cancelled = 1, cancellation_reason = ?, cancelled_at = NOW(),
            updated_by_character_id = ? WHERE event_id = ? AND cancelled = 0]], {
            safeReason, actor, id,
        })
        if changed == nil then return result(false, 'event_cancel_failed') end
        refreshClients()
        return result(true, nil, { cancelled = true })
    end)
end)

exports('AdminListEvents', function(adminSrc)
    if not adminAuthorized(adminSrc) then return result(false, 'admin_permission_required') end
    if not databaseReady() then return result(false, 'database_unavailable') end
    local rows = MySQL.query.await([[SELECT event_id, title, description, category, enabled,
        cancelled, UNIX_TIMESTAMP(start_at) AS start_ts, UNIX_TIMESTAMP(end_at) AS end_ts,
        capacity, rsvp_count, x, y, z, attendance_radius, heading, colour,
        display_label, routing_bucket, cancellation_reason, cancelled_at,
        created_by_character_id, updated_by_character_id, created_at, updated_at
        FROM cm_citycalendar_events ORDER BY start_at DESC]], {}) or {}
    for _, row in ipairs(rows) do
        row.enabled = tonumber(row.enabled) == 1
        row.cancelled = tonumber(row.cancelled) == 1
    end
    return result(true, nil, { events = rows })
end)

local function playerEventAccess(src, rawId)
    local id = eventId(rawId)
    if not id then return nil, nil, result(false, 'invalid_event_id') end
    local cid = currentCharacter(src)
    if not cid then return nil, nil, result(false, 'character_unavailable') end
    local row = eventRow(id)
    if not row then return nil, nil, result(false, 'event_not_found') end
    return row, cid, nil
end

local function rsvpStatus(id, cid)
    return MySQL.single.await([[SELECT status FROM cm_citycalendar_rsvps
        WHERE event_id = ? AND character_id = ? LIMIT 1]], { id, cid })
end

local function attendanceStatus(id, cid)
    return MySQL.single.await([[SELECT UNIX_TIMESTAMP(checked_in_at) AS checked_in_at
        FROM cm_citycalendar_attendance WHERE event_id = ? AND character_id = ? LIMIT 1]], { id, cid })
end

local function mutateRsvp(src, rawId, cancel)
    if not databaseReady() then return result(false, 'database_unavailable') end
    local row, cid, failure = playerEventAccess(src, rawId)
    if failure then return failure end
    local id = row.event_id
    if not eventLock(id) then return result(false, 'request_in_progress') end
    local ok, response = pcall(function()
        if not lock('action', cid, Config.Security.actionCooldownMs) then return result(false, 'rate_limited') end
        local state = eventState(row)
        if state == 'cancelled' or state == 'unavailable' then return result(false, 'event_unavailable') end
        if state == 'past' then return result(false, 'event_has_ended') end
        local current = rsvpStatus(id, cid)
        local active = current and current.status == 'active'
        if cancel then
            if not active then return result(true, nil, { alreadyCancelled = true, eventId = id }) end
            local committed = MySQL.transaction.await({
                { query = [[UPDATE cm_citycalendar_events SET rsvp_count = GREATEST(rsvp_count - 1, 0) WHERE event_id = ?]], values = { id } },
                { query = [[UPDATE cm_citycalendar_rsvps SET status = 'cancelled', cancelled_at = NOW() WHERE event_id = ? AND character_id = ? AND status = 'active']], values = { id, cid } },
            })
            if committed ~= true then return result(false, 'rsvp_cancel_failed') end
            return result(true, nil, { cancelled = true, eventId = id })
        end
        if active then return result(true, nil, { alreadyRsvped = true, eventId = id }) end
        local currentCount = tonumber(row.rsvp_count) or 0
        local capacity = tonumber(row.capacity)
        if capacity and currentCount >= capacity then return result(false, 'event_full') end
        local committed = MySQL.transaction.await({
            { query = [[UPDATE cm_citycalendar_events SET rsvp_count = rsvp_count + 1
                WHERE event_id = ? AND enabled = 1 AND cancelled = 0 AND end_at > NOW()
                  AND (capacity IS NULL OR rsvp_count < capacity)]], values = { id } },
            { query = [[INSERT INTO cm_citycalendar_rsvps (event_id, character_id, status, rsvp_at, cancelled_at)
                VALUES (?, ?, 'active', NOW(), NULL)
                ON DUPLICATE KEY UPDATE status = 'active', rsvp_at = NOW(), cancelled_at = NULL]], values = { id, cid } },
        })
        if committed ~= true then return result(false, 'rsvp_failed') end
        return result(true, nil, { rsvped = true, eventId = id })
    end)
    releaseEventLock(id)
    if not ok then return result(false, 'request_failed') end
    return response
end

lib.callback.register('cm-citycalendar:server:rsvp', function(src, request)
    request = type(request) == 'table' and request or {}
    return mutateRsvp(src, request.eventId or request.event_id, false)
end)

lib.callback.register('cm-citycalendar:server:cancelRsvp', function(src, request)
    request = type(request) == 'table' and request or {}
    return mutateRsvp(src, request.eventId or request.event_id, true)
end)

lib.callback.register('cm-citycalendar:server:checkIn', function(src, request)
    if not databaseReady() then return result(false, 'database_unavailable') end
    request = type(request) == 'table' and request or {}
    local row, cid, failure = playerEventAccess(src, request.eventId or request.event_id)
    if failure then return failure end
    local id = row.event_id
    if not eventLock(id) then return result(false, 'request_in_progress') end
    local ok, response = pcall(function()
        if not lock('action', cid, Config.Security.actionCooldownMs) then return result(false, 'rate_limited') end
        if tonumber(row.enabled) ~= 1 or tonumber(row.cancelled) == 1 then return result(false, 'event_unavailable') end
        local timestamp = now()
        if timestamp < tonumber(row.start_ts) or timestamp >= tonumber(row.end_ts) then return result(false, 'event_not_active') end
        local rsvp = rsvpStatus(id, cid)
        if not rsvp or rsvp.status ~= 'active' then return result(false, 'active_rsvp_required') end
        if isDead(src) then return result(false, 'player_unavailable') end
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 or GetEntityHealth(ped) <= 0 then return result(false, 'player_unavailable') end
        if row.routing_bucket ~= nil and tonumber(row.routing_bucket) ~= GetPlayerRoutingBucket(src) then return result(false, 'routing_bucket_mismatch') end
        if not row.x or not row.y or not row.z or not row.attendance_radius then return result(false, 'physical_attendance_unavailable') end
        local coords = GetEntityCoords(ped)
        if not coords then return result(false, 'player_unavailable') end
        local dx = coords.x - tonumber(row.x); local dy = coords.y - tonumber(row.y); local dz = coords.z - tonumber(row.z)
        local radius = tonumber(row.attendance_radius)
        if (dx * dx + dy * dy + dz * dz) > radius * radius then return result(false, 'too_far_away') end
        local existing = attendanceStatus(id, cid)
        if existing then return result(true, nil, { alreadyCheckedIn = true, checkedInAt = existing.checked_in_at, eventId = id }) end
        local inserted = MySQL.update.await([[INSERT IGNORE INTO cm_citycalendar_attendance
            (event_id, character_id, checked_in_at) VALUES (?, ?, NOW())]], { id, cid })
        local record = attendanceStatus(id, cid)
        if not record then return result(false, 'check_in_failed') end
        return result(true, nil, { checkedIn = tonumber(inserted) == 1, checkedInAt = record.checked_in_at, eventId = id })
    end)
    releaseEventLock(id)
    if not ok then return result(false, 'request_failed') end
    return response
end)

lib.callback.register('cm-citycalendar:server:getDashboard', function(src)
    if not databaseReady() then return result(false, 'database_unavailable') end
    local cid = currentCharacter(src)
    if not cid then return result(false, 'character_unavailable') end
    local rows = MySQL.query.await([[SELECT e.event_id, e.title, e.description, e.category,
        e.enabled, e.cancelled, UNIX_TIMESTAMP(e.start_at) AS start_ts,
        UNIX_TIMESTAMP(e.end_at) AS end_ts, e.capacity, e.rsvp_count,
        e.x, e.y, e.z, e.attendance_radius, e.display_label, e.colour,
        e.cancellation_reason, r.status AS rsvp_status,
        UNIX_TIMESTAMP(a.checked_in_at) AS checked_in_at
        FROM cm_citycalendar_events e
        LEFT JOIN cm_citycalendar_rsvps r ON r.event_id = e.event_id AND r.character_id = ?
        LEFT JOIN cm_citycalendar_attendance a ON a.event_id = e.event_id AND a.character_id = ?
        WHERE e.enabled = 1 OR e.cancelled = 1
        ORDER BY e.start_at ASC]], { cid, cid }) or {}
    local events, categories = {}, {}
    local categorySeen = {}
    local timestamp = now()
    for _, row in ipairs(rows) do
        local status = eventState(row, timestamp)
        if status ~= 'unavailable' then
            if not categorySeen[row.category] then categorySeen[row.category] = true; categories[#categories + 1] = row.category end
            events[#events + 1] = publicEvent(row, row.rsvp_status, row.checked_in_at ~= nil, row.checked_in_at)
            events[#events].status = status
        end
    end
    return result(true, nil, { serverTime = timestamp, events = events, categories = categories })
end)

lib.callback.register('cm-citycalendar:server:getWorldEvents', function(src)
    if not databaseReady() or not currentCharacter(src) then return {} end
    local rows = MySQL.query.await([[SELECT event_id, title, category, x, y, z,
        attendance_radius, display_label, routing_bucket, colour
        FROM cm_citycalendar_events
        WHERE enabled = 1 AND cancelled = 0 AND start_at <= NOW() AND end_at > NOW()
          AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL AND attendance_radius IS NOT NULL
        ORDER BY start_at ASC]], {}) or {}
    local visible = {}
    for _, row in ipairs(rows) do
        visible[#visible + 1] = {
            id = row.event_id, title = row.title, category = row.category,
            x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
            radius = tonumber(row.attendance_radius), displayLabel = row.display_label,
            routingBucket = tonumber(row.routing_bucket), colour = row.colour,
        }
    end
    return visible
end)

local function clearSource(src)
    src = tonumber(src)
    if not src then return end
    local cid = sourceCharacters[src]
    if cid then actionLocks[('action:%s'):format(cid)] = nil end
    actionLocks[('action:%s'):format(src)] = nil
    sourceCharacters[src] = nil
end

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    clearSource(src)
end)

AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, isDeadNow)
    if isDeadNow == true then clearSource(src) end
end)

AddEventHandler('playerDropped', function()
    clearSource(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then
        actionLocks, adminLocks, eventLocks, sourceCharacters = {}, {}, {}, {}
    end
end)
