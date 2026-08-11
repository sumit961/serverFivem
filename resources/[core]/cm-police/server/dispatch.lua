-- cm-police 911/dispatch. Mirrors the proven shape of cm-ems's own
-- dispatch engine (server/dispatch.lua there: recipients()-style on-duty
-- targeting, a sanitized free-text details string, a flattened publicCall
-- view sent to clients) but is fully independent -- no shared state, no
-- shared command name (that resource already owns '911'; this uses
-- /reportcrime instead, see shared/config.lua's Config.Dispatch comment),
-- and deliberately simpler than EMS's own multi-stage machine: New ->
-- Accepted -> (optionally) En Route -> Resolved, no AI fallback responder.
-- Two call sources feed the same engine: a citizen's /reportcrime, and
-- client/gunfire.lua's automatic "heavy gunfire" detection (anonymous, no
-- caller identity -- see createCall below).

local ActiveCalls = {} -- [callId] = { id, callerCid, callerName, details, coords, location, status, responders = { [characterId] = {name, source, acceptedAt, status} }, createdAt }
local nextCallId = 0

-- Server-side notify to a specific client -- same shape as citationNotify/
-- cuffNotify/bookingNotify elsewhere in this codebase. PoliceNotify
-- (client/ui.lua) is a CLIENT-only function; the client's own
-- interactionNotify handler is what actually renders this toast.
local function dispatchNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function cleanDetails(value)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #value > 180 then value = value:sub(1, 180) end
    return value ~= '' and value or 'Suspicious activity reported.'
end

-- Best-effort street/intersection label so a call reads like "Vinewood Blvd
-- & 3rd St" instead of raw coordinates. Falls back to coordinates if the
-- natives are ever unavailable server-side in a given build -- never lets a
-- call fail to create just because this lookup didn't work.
local function locationLabel(coords)
    local label
    pcall(function()
        local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
        local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or nil
        local cross = crossHash and crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or nil
        if street and street ~= '' then
            label = (cross and cross ~= '') and ('%s & %s'):format(street, cross) or street
        end
    end)
    return label or ('%.0f, %.0f'):format(coords.x, coords.y)
end

-- Global (not local) so server/mdt.lua's BOLO callbacks can reuse the exact
-- same on-duty + permission audience, same cross-file-global convention as
-- cid/memberFor/has/log/rateLimit/nameFor from server/main.lua.
function recipients(permission)
    local out = {}
    for _, rawSrc in ipairs(GetPlayers()) do
        local targetSrc = tonumber(rawSrc)
        if targetSrc then
            local characterId = cid(targetSrc)
            local member = characterId and memberFor(characterId)
            if member and not dbBoolean(member.is_suspended) and dbBoolean(member.on_duty) and has(member, permission) then
                out[#out + 1] = targetSrc
            end
        end
    end
    return out
end

local function responderRows(call)
    local rows = {}
    for characterId, responder in pairs(call.responders or {}) do
        rows[#rows + 1] = { characterId = tostring(characterId), name = responder.name, status = responder.status or 'accepted', acceptedAt = responder.acceptedAt }
    end
    table.sort(rows, function(a, b) return (a.acceptedAt or 0) < (b.acceptedAt or 0) end)
    return rows
end

local function publicCall(call)
    return {
        id = call.id,
        details = call.details,
        callerName = call.callerName,
        coords = call.coords,
        location = call.location,
        status = call.status,
        createdAt = call.createdAt,
        responders = responderRows(call),
    }
end

local function persistIncident(call)
    MySQL.update.await('UPDATE cm_police_incidents SET status = ?, responders = ?, resolution = ?, resolved_at = IF(? = 1, CURRENT_TIMESTAMP, resolved_at) WHERE id = ?', {
        call.status, json.encode(responderRows(call)), call.resolution,
        (call.status == 'resolved' or call.status == 'expired') and 1 or 0, call.id,
    })
end

local function broadcastToRecipients(event, payload)
    for _, targetSrc in ipairs(recipients('police.receive_dispatch')) do
        TriggerClientEvent(event, targetSrc, payload)
    end
end

-- Shared by /reportcrime and the anonymous gunfire report below -- the only
-- difference between a citizen call and an automatic one is what caller
-- identity (if any) gets attached; everything else (persistence, broadcast,
-- location resolution) is identical.
local function createCall(details, coords, callerCid, callerName, routingBucket)
    if GetResourceState('cm-law') == 'started' then
        local ok, result = exports['cm-law']:CreateLawIncident(details,
            { x = coords.x, y = coords.y, z = coords.z }, callerCid, callerName,
            { callType = 'police_report', organizationId = 'police', routingBucket = tonumber(routingBucket) or 0 })
        if ok then return result end
        return nil, result
    end
    if not PoliceDatabaseReady() then return nil, 'Police dispatch is still starting.' end
    nextCallId = nextCallId + 1
    local callId = nextCallId
    local location = locationLabel(coords)
    local call = {
        id = callId, callerCid = callerCid, callerName = callerName,
        details = details, coords = { x = coords.x, y = coords.y, z = coords.z }, location = location,
        status = 'waiting', responders = {}, createdAt = os.time(),
    }
    ActiveCalls[callId] = call

    MySQL.insert.await('INSERT INTO cm_police_incidents (id, caller_cid, caller_name, details, coords_x, coords_y, coords_z, location, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { callId, callerCid, callerName, details, coords.x, coords.y, coords.z, location, 'waiting' })

    broadcastToRecipients('cm-police:client:dispatchCall', publicCall(call))
    return call
end

exports('CreatePoliceCall', function(src, details)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false, 'Invalid caller.' end
    if GetResourceState('cm-law') == 'started' then
        return exports['cm-law']:CreateLawCallForOrganization(src, 'police', cleanDetails(details))
    end
    if not rateLimit(src, 'police_shared_911', Config.Dispatch.Cooldown or 30000) then return false, 'You already contacted emergency services recently.' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Your location is not ready.' end
    local callerCid = cid(src)
    local call, reason = createCall(cleanDetails(details), GetEntityCoords(ped), callerCid,
        callerCid and nameFor(callerCid) or GetPlayerName(src) or 'Unknown caller')
    if not call then return false, reason end
    return true, 'Police dispatch received your emergency call.'
end)

RegisterCommand('reportcrime', function(src, args)
    src = tonumber(src)
    if not src or src <= 0 then return end
    if not rateLimit(src, 'police_report_crime', Config.Dispatch.Cooldown or 30000) then
        return dispatchNotify(src, 'You already reported something recently. Please wait before calling again.', 'error')
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    local details = cleanDetails(table.concat(args or {}, ' '))
    local callerCid = cid(src)
    local callerName = callerCid and nameFor(callerCid) or GetPlayerName(src) or 'Unknown caller'
    local call, reason = createCall(details, coords, callerCid, callerName, GetPlayerRoutingBucket(src))
    if not call then return dispatchNotify(src, reason, 'error') end
    dispatchNotify(src, 'Your report has been sent to on-duty Police.', 'success')
end, false)

-- Automatic "heavy gunfire" call -- fired by client/gunfire.lua once a
-- player's own shots cross Config.Dispatch.GunfireShotThreshold within
-- GunfireWindowMs. Deliberately anonymous (callerCid/callerName omit the
-- shooter entirely) -- per the confirmed design, this is meant to read like
-- a real automatic gunfire-detection system: a location, not a suspect
-- name, so officers still have to investigate. Server-side rate limit here
-- is defense in depth on top of the client's own cooldown (a modified
-- client could otherwise spam this event directly).
RegisterNetEvent('cm-police:server:reportGunfire', function(x, y, z)
    local src = source
    if not rateLimit(src, 'police_gunfire_report', Config.Dispatch.GunfireCooldownMs or 120000) then return end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local serverCoords = GetEntityCoords(ped)
    local reportedCoords = vector3(x, y, z)
    if #(serverCoords - reportedCoords) > (Config.Dispatch.GunfireCoordinateTolerance or 12.0) then
        log(cid(src), 'gunfire_report_rejected', { reason = 'coordinate_mismatch' })
        return
    end
    createCall('Heavy gunfire reported in the area.', serverCoords, nil, 'Gunfire Detection System', GetPlayerRoutingBucket(src))
end)

lib.callback.register('cm-police:server:acceptDispatchCall', function(src, callId)
    callId = tonumber(callId)
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, 'police.receive_dispatch') then
        return false, 'You must be an on-duty officer with dispatch access.'
    end
    if not call.responders[characterId] then
        call.responders[characterId] = { name = nameFor(characterId), source = src, acceptedAt = os.time(), status = 'accepted' }
    end
    call.status = 'accepted'
    persistIncident(call)
    broadcastToRecipients('cm-police:client:dispatchCallUpdated', publicCall(call))
    return true, 'You are responding to the call.'
end)

-- Per-officer status, independent of the call's own overall status --
-- lighter-weight than cm-ems's full response-state machine (which tracks a
-- single AI response's state), mirroring instead the one field cm-ems
-- ALSO tracks per human responder (call.responders[id].status). Only one
-- extra value beyond "accepted" for now: "en_route".
lib.callback.register('cm-police:server:setDispatchResponseStatus', function(src, callId, status)
    callId = tonumber(callId)
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    local characterId = cid(src)
    local responder = characterId and call.responders[characterId]
    if not responder then return false, 'You must accept this call first.' end
    if status ~= 'en_route' then return false, 'Invalid status.' end
    responder.status = status
    persistIncident(call)
    broadcastToRecipients('cm-police:client:dispatchCallUpdated', publicCall(call))
    return true, 'Marked en route.'
end)

lib.callback.register('cm-police:server:resolveDispatchCall', function(src, callId, resolution)
    callId = tonumber(callId)
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    local characterId = cid(src)
    if not characterId or not call.responders[characterId] then
        return false, 'You must accept this call before resolving it.'
    end
    call.status = 'resolved'
    call.resolution = cleanDetails(resolution or 'Resolved')
    local responseMs = math.max(0, (os.time() - (call.responders[characterId].acceptedAt or os.time())) * 1000)
    persistIncident(call)
    ActiveCalls[callId] = nil
    log(characterId, 'dispatch_call_resolved', { callId = callId, details = call.details, responseMs = responseMs })
    broadcastToRecipients('cm-police:client:dispatchCallResolved', callId)
    return true, 'Call marked resolved.'
end)

lib.callback.register('cm-police:server:dispatchActiveCalls', function(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, 'police.receive_dispatch') then
        return {}
    end
    local list = {}
    for _, call in pairs(ActiveCalls) do list[#list + 1] = publicCall(call) end
    table.sort(list, function(a, b) return a.createdAt < b.createdAt end)
    return list
end)

lib.callback.register('cm-police:server:dispatchHistory', function(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or not has(member, 'police.receive_dispatch') then return {} end
    local limit = math.max(1, math.min(tonumber(Config.Dispatch.HistoryLimit) or 50, 200))
    local rows = MySQL.query.await('SELECT id, caller_name, details, location, status, resolution, created_at, resolved_at FROM cm_police_incidents WHERE status IN (?, ?) ORDER BY id DESC LIMIT ?', { 'resolved', 'expired', limit }) or {}
    for _, row in ipairs(rows) do
        row.callerName = row.caller_name
        row.createdAt = tostring(row.created_at or '')
        row.resolvedAt = row.resolved_at and tostring(row.resolved_at) or nil
        row.caller_name, row.created_at, row.resolved_at = nil, nil, nil
    end
    return rows
end)

-- Backup request (J quick-menu, client/quickmenu.lua). Deliberately not a
-- dispatch call -- no accept/resolve workflow, nothing persisted -- just a
-- rate-limited broadcast; client/dispatch.lua's own blip handles itself
-- expiring after Config.Backup.BlipLifetimeMs with no further server input.
lib.callback.register('cm-police:server:requestBackup', function(src, requestedPriority)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) then
        return false, 'You must be an on-duty officer.'
    end
    local priority = tostring(requestedPriority or 'normal')
    if priority ~= 'normal' and priority ~= 'urgent' and priority ~= 'panic' then priority = 'normal' end
    local cooldown = priority == 'panic' and (Config.Backup.PanicCooldown or 30000) or (Config.Backup.Cooldown or 60000)
    if not rateLimit(src, 'police_request_backup_' .. priority, cooldown) then
        return false, 'You already called for backup recently.'
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Unable to resolve your location.' end
    local coords = GetEntityCoords(ped)
    local name = nameFor(characterId)
    local action = priority == 'panic' and 'panic_activated' or 'backup_requested'
    log(characterId, action, { priority = priority, coords = { x = coords.x, y = coords.y, z = coords.z } })
    for _, targetSrc in ipairs(recipients('police.receive_dispatch')) do
        TriggerClientEvent('cm-police:client:backupRequested', targetSrc, name, coords, priority)
    end
    local message = priority == 'panic' and 'Panic alert sent to all on-duty units.'
        or (priority == 'urgent' and 'Urgent backup requested.' or 'Backup requested.')
    return true, message
end)

-- Auto-expire: same shape as server/spikes.lua's/server/booking.lua's own
-- periodic sweep threads. A call nobody ever resolves shouldn't linger
-- forever -- it just goes stale, same as a real unanswered call would.
CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for callId, call in pairs(ActiveCalls) do
            if now - call.createdAt >= math.floor((Config.Dispatch.ExpireAfterMs or 600000) / 1000) then
                call.status = 'expired'
                persistIncident(call)
                ActiveCalls[callId] = nil
                broadcastToRecipients('cm-police:client:dispatchCallResolved', callId)
            end
        end
    end
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_incidents (
        id BIGINT UNSIGNED NOT NULL,
        caller_cid VARCHAR(64) NULL,
        caller_name VARCHAR(128) NULL,
        details VARCHAR(180) NOT NULL,
        coords_x FLOAT NOT NULL, coords_y FLOAT NOT NULL, coords_z FLOAT NOT NULL,
        status ENUM('waiting','accepted','resolved','expired') NOT NULL DEFAULT 'waiting',
        responders LONGTEXT NULL,
        resolution VARCHAR(160) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        resolved_at TIMESTAMP NULL,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Column add for servers upgrading from before location resolution
    -- existed -- same idempotent-alter pattern server/main.lua's own
    -- setupDatabase() already uses (pcall-wrapped so re-running on an
    -- already-migrated install is a silent no-op).
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_incidents ADD COLUMN location VARCHAR(120) NULL') end)
    -- id isn't AUTO_INCREMENT (createCall assigns it itself so it can insert
    -- and broadcast with the same id in one step) -- without this, nextCallId
    -- would restart from 0 on every resource restart and collide with the
    -- highest id already persisted, making the very next call's INSERT fail
    -- and silently killing that call's broadcast to on-duty officers.
    local highest = MySQL.scalar.await('SELECT MAX(id) FROM cm_police_incidents')
    nextCallId = tonumber(highest) or 0
    PoliceSchemaMarkReady('dispatch')
end)
