-- cm-law 911/dispatch. Mirrors the proven shape of cm-police's own
-- server/dispatch.lua closely, generalized to a JOINT channel across all
-- four organizations (sahp/sheriff/fib/army) instead of one -- a citizen
-- calling for help has no way to know which agency is on shift, so a call
-- broadcasts to every on-duty member with law.receive_dispatch regardless
-- of organization, and any of them can accept/resolve it.
--
-- Includes server-authoritative officer backup/panic alerts and restores
-- unresolved calls after a resource or server restart.

local ActiveCalls = {} -- [callId] = { id, callerCid, callerName, details, coords, location, status, responders = { [characterId] = {name, source, organizationId, acceptedAt, status} }, createdAt }
local nextCallId = 0

local function dispatchNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function hasPerm(member, permission)
    return member.isLeader == true or member.permissions[permission] == true
end

local function cleanDetails(value)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #value > 180 then value = value:sub(1, 180) end
    return value ~= '' and value or 'Suspicious activity reported.'
end

-- Best-effort street/intersection label, same fallback-to-coordinates
-- reasoning as cm-police's own locationLabel.
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

local function dispatchMemberForSource(src)
    local member, characterId = activeMemberForSource(src)
    if member then return member, characterId end
    if GetResourceState('cm-police') ~= 'started' then return nil, characterId end
    characterId = characterId or characterIdFor(src)
    if not characterId then return nil, nil end
    local ok, police = pcall(function() return exports['cm-police']:GetMember(characterId) end)
    if not ok or type(police) ~= 'table' or police.onDuty ~= true or police.suspended == true then return nil, characterId end
    police.organizationId = 'police'
    police.isLeader = police.isLeader == true
    police.permissions = type(police.permissions) == 'table' and police.permissions or {}
    local permitted = false
    pcall(function() permitted = exports['cm-police']:HasPermission(characterId, 'police.receive_dispatch') == true end)
    police.permissions['law.receive_dispatch'] = permitted
    return police, characterId
end

local function recipients(permission, routingBucket, audienceOrganizationId)
    local out = {}
    for _, rawSrc in ipairs(GetPlayers()) do
        local targetSrc = tonumber(rawSrc)
        if targetSrc then
            local member = dispatchMemberForSource(targetSrc)
            if member and not member.suspended and member.onDuty and hasPerm(member, permission)
                and (not audienceOrganizationId or member.organizationId == audienceOrganizationId)
                and (routingBucket == nil or GetPlayerRoutingBucket(targetSrc) == routingBucket) then
                out[#out + 1] = targetSrc
            end
        end
    end
    return out
end

local function responderRows(call)
    local rows = {}
    for characterId, responder in pairs(call.responders or {}) do
        rows[#rows + 1] = {
            characterId = tostring(characterId), name = responder.name,
            organizationId = responder.organizationId, status = responder.status or 'accepted',
            acceptedAt = responder.acceptedAt,
        }
    end
    table.sort(rows, function(a, b) return (a.acceptedAt or 0) < (b.acceptedAt or 0) end)
    return rows
end

local function publicCall(call)
    return {
        id = call.id, details = call.details, callerName = call.callerName,
        coords = call.coords, location = call.location, status = call.status,
        createdAt = call.createdAt, responders = responderRows(call),
        callType = call.callType or 'citizen', priority = call.priority or 1,
        organizationId = call.organizationId, audienceOrganizationId = call.audienceOrganizationId,
    }
end

local function persistIncident(call)
    MySQL.update.await('UPDATE cm_legal_incidents SET status = ?, responders = ?, resolution = ?, resolved_at = IF(? = 1, CURRENT_TIMESTAMP, resolved_at) WHERE id = ?', {
        call.status, json.encode(responderRows(call)), call.resolution,
        (call.status == 'resolved' or call.status == 'expired') and 1 or 0, call.id,
    })
end

local function broadcastToRecipients(event, payload, routingBucket, audienceOrganizationId)
    for _, targetSrc in ipairs(recipients('law.receive_dispatch', routingBucket, audienceOrganizationId)) do
        TriggerClientEvent(event, targetSrc, payload)
    end
end

local function createCall(details, coords, callerCid, callerName, options)
    if not LawIsReady() then return nil, 'Dispatch is still starting.' end
    options = type(options) == 'table' and options or {}
    nextCallId = nextCallId + 1
    local callId = nextCallId
    local location = locationLabel(coords)
    local call = {
        id = callId, callerCid = callerCid, callerName = callerName,
        details = details, coords = { x = coords.x, y = coords.y, z = coords.z }, location = location,
        status = 'waiting', responders = {}, createdAt = os.time(),
        callType = options.callType or 'citizen', priority = tonumber(options.priority) or 1,
        organizationId = options.organizationId, routingBucket = tonumber(options.routingBucket) or 0,
        audienceOrganizationId = options.audienceOrganizationId,
    }
    local insertedOk, inserted = pcall(function()
        return MySQL.insert.await([[INSERT INTO cm_legal_incidents
            (id, caller_cid, caller_name, details, coords_x, coords_y, coords_z, location, status,
             call_type, priority, organization_id, routing_bucket)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            { callId, callerCid, callerName, details, coords.x, coords.y, coords.z, location, 'waiting',
              call.callType, call.priority, call.organizationId, call.routingBucket })
    end)
    if not insertedOk or not inserted then return nil, 'Dispatch could not save this call.' end
    ActiveCalls[callId] = call

    broadcastToRecipients('cm-law:client:dispatchCall', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    return call
end

exports('CreateLawCall', function(src, details)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false, 'Invalid caller.' end
    if not rateLimit(src, 'law_shared_911', Config.Dispatch.Cooldown or 30000) then
        return false, 'You already contacted authorities recently.'
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Your location is not ready.' end
    local callerCid = characterIdFor(src)
    local call, reason = createCall(cleanDetails(details), GetEntityCoords(ped), callerCid,
        callerCid and nameFor(callerCid) or GetPlayerName(src) or 'Unknown caller',
        { routingBucket = GetPlayerRoutingBucket(src) })
    if not call then return false, reason end
    return true, 'Dispatch received your emergency call.'
end)

exports('CreateLawCallForOrganization', function(src, organizationId, details)
    src, organizationId = tonumber(src), tostring(organizationId or ''):lower()
    if not src or src <= 0 or not GetPlayerName(src) then return false, 'Invalid caller.' end
    if organizationId ~= 'police' and not Config.Organizations[organizationId] then return false, 'Invalid organization.' end
    if not rateLimit(src, 'law_front_desk_dispatch_' .. organizationId, Config.Dispatch.Cooldown or 30000) then
        return false, 'You already contacted this organization recently.'
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Your location is not ready.' end
    local callerCid = characterIdFor(src)
    local call, reason = createCall(cleanDetails(details), GetEntityCoords(ped), callerCid,
        callerCid and nameFor(callerCid) or GetPlayerName(src) or 'Unknown caller', {
            organizationId = organizationId, audienceOrganizationId = organizationId,
            callType = 'front_desk', routingBucket = GetPlayerRoutingBucket(src),
        })
    if not call then return false, reason end
    return true, 'The requested organization has been notified.'
end)

exports('CreateLawIncident', function(details, coords, callerCid, callerName, options)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return false, 'Invalid incident coordinates.' end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return false, 'Invalid incident coordinates.' end
    local call, reason = createCall(cleanDetails(details), vector3(x, y, z), callerCid,
        cleanDetails(callerName or 'Unknown caller'), options)
    return call ~= nil, call and publicCall(call) or reason
end)

RegisterCommand('reportlaw', function(src, args)
    src = tonumber(src)
    if not src or src <= 0 then return end
    if not rateLimit(src, 'law_report_crime', Config.Dispatch.Cooldown or 30000) then
        return dispatchNotify(src, 'You already reported something recently. Please wait before calling again.', 'error')
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    local details = cleanDetails(table.concat(args or {}, ' '))
    local callerCid = characterIdFor(src)
    local callerName = callerCid and nameFor(callerCid) or GetPlayerName(src) or 'Unknown caller'
    local call, reason = createCall(details, coords, callerCid, callerName,
        { routingBucket = GetPlayerRoutingBucket(src) })
    if not call then return dispatchNotify(src, reason, 'error') end
    dispatchNotify(src, 'Your report has been sent to on-duty units.', 'success')
end, false)

lib.callback.register('cm-law:server:createOfficerAlert', function(src, alertType)
    alertType = tostring(alertType or ''):lower()
    if alertType ~= 'backup' and alertType ~= 'panic' then return false, 'Invalid alert type.' end
    local member, characterId = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then
        return false, 'You must be an on-duty legal officer with dispatch access.'
    end
    local cooldown = alertType == 'panic' and (Config.Dispatch.PanicCooldown or 60000)
        or (Config.Dispatch.BackupCooldown or 30000)
    if not rateLimit(src, 'law_officer_alert_' .. alertType, cooldown) then
        return false, ('Your %s alert is already active.'):format(alertType)
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Your location is not ready.' end
    local org = Config.Organizations[member.organizationId] or {}
    local officerName = nameFor(characterId)
    local details = alertType == 'panic'
        and ('PANIC BUTTON · OFFICER IN DISTRESS · %s %s'):format(org.shortLabel or member.organizationId, officerName)
        or ('BACKUP REQUEST · %s %s'):format(org.shortLabel or member.organizationId, officerName)
    local call, reason = createCall(details, GetEntityCoords(ped), characterId, officerName, {
        callType = alertType, priority = alertType == 'panic' and 3 or 2,
        organizationId = member.organizationId, routingBucket = GetPlayerRoutingBucket(src),
    })
    if not call then return false, reason end
    logActivity(member.organizationId, characterId, 'dispatch_officer_alert', {
        callId = call.id, alertType = alertType, location = call.location,
    })
    return true, alertType == 'panic' and 'Panic alert sent to all available units.' or 'Backup requested from available units.'
end)

lib.callback.register('cm-law:server:acceptDispatchCall', function(src, callId)
    callId = tonumber(callId)
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    local member, characterId = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then
        return false, 'You must be an on-duty member with dispatch access.'
    end
    if GetPlayerRoutingBucket(src) ~= call.routingBucket then return false, 'That call is in another routing instance.' end
    if call.audienceOrganizationId and call.audienceOrganizationId ~= member.organizationId then return false, 'That call belongs to another organization.' end
    if not call.responders[characterId] then
        call.responders[characterId] = {
            name = nameFor(characterId), source = src, organizationId = member.organizationId,
            acceptedAt = os.time(), status = 'accepted',
        }
    end
    call.status = 'accepted'
    persistIncident(call)
    broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    return true, 'You are responding to the call.'
end)

lib.callback.register('cm-law:server:setDispatchResponseStatus', function(src, callId, status)
    callId = tonumber(callId)
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    local member, characterId = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then
        return false, 'You must be an on-duty member with dispatch access.'
    end
    if GetPlayerRoutingBucket(src) ~= call.routingBucket then return false, 'That call is in another routing instance.' end
    if call.audienceOrganizationId and call.audienceOrganizationId ~= member.organizationId then return false, 'That call belongs to another organization.' end
    local responder = characterId and call.responders[characterId]
    if not responder then return false, 'You must accept this call first.' end
    if status ~= 'en_route' then return false, 'Invalid status.' end
    responder.status = status
    persistIncident(call)
    broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    return true, 'Marked en route.'
end)

lib.callback.register('cm-law:server:resolveDispatchCall', function(src, callId, resolution)
    callId = tonumber(callId)
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    local member, characterId = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then
        return false, 'You must be an on-duty member with dispatch access.'
    end
    if GetPlayerRoutingBucket(src) ~= call.routingBucket then return false, 'That call is in another routing instance.' end
    if call.audienceOrganizationId and call.audienceOrganizationId ~= member.organizationId then return false, 'That call belongs to another organization.' end
    if not characterId or not call.responders[characterId] then
        return false, 'You must accept this call before resolving it.'
    end
    call.status = 'resolved'
    call.resolution = cleanDetails(resolution or 'Resolved')
    local responseMs = math.max(0, (os.time() - (call.responders[characterId].acceptedAt or os.time())) * 1000)
    persistIncident(call)
    ActiveCalls[callId] = nil
    if member then
        logActivity(member.organizationId, characterId, 'dispatch_call_resolved', { callId = callId, details = call.details, responseMs = responseMs })
    end
    broadcastToRecipients('cm-law:client:dispatchCallResolved', callId)
    return true, 'Call marked resolved.'
end)

lib.callback.register('cm-law:server:dispatchActiveCalls', function(src)
    local member = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then return {} end
    local list = {}
    local bucket = GetPlayerRoutingBucket(src)
    for _, call in pairs(ActiveCalls) do
        if call.routingBucket == bucket and (not call.audienceOrganizationId or call.audienceOrganizationId == member.organizationId) then list[#list + 1] = publicCall(call) end
    end
    table.sort(list, function(a, b) return a.createdAt < b.createdAt end)
    return list
end)

lib.callback.register('cm-law:server:dispatchHistory', function(src)
    local member = dispatchMemberForSource(src)
    if not member or not hasPerm(member, 'law.receive_dispatch') then return {} end
    local limit = math.max(1, math.min(tonumber(Config.Dispatch.HistoryLimit) or 50, 200))
    local rows = MySQL.query.await([[SELECT id, caller_name, details, location, status, resolution, created_at, resolved_at
        FROM cm_legal_incidents WHERE status IN (?, ?) AND (call_type <> 'front_desk' OR organization_id = ?)
        ORDER BY id DESC LIMIT ?]], { 'resolved', 'expired', member.organizationId, limit }) or {}
    for _, row in ipairs(rows) do
        row.callerName = row.caller_name
        row.createdAt = tostring(row.created_at or '')
        row.resolvedAt = row.resolved_at and tostring(row.resolved_at) or nil
        row.caller_name, row.created_at, row.resolved_at = nil, nil, nil
    end
    return rows
end)

-- Auto-expire: a call nobody ever resolves shouldn't linger forever.
CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for callId, call in pairs(ActiveCalls) do
            if now - call.createdAt >= math.floor((Config.Dispatch.ExpireAfterMs or 600000) / 1000) then
                call.status = 'expired'
                persistIncident(call)
                ActiveCalls[callId] = nil
                broadcastToRecipients('cm-law:client:dispatchCallResolved', callId)
            end
        end
    end
end)

CreateThread(function()
    while not LawIsReady() do Wait(500) end
    local highest = MySQL.scalar.await('SELECT MAX(id) FROM cm_legal_incidents')
    nextCallId = tonumber(highest) or 0
    local expirySeconds = math.floor((Config.Dispatch.ExpireAfterMs or 600000) / 1000)
    local rows = MySQL.query.await([[SELECT id, caller_cid, caller_name, details, coords_x, coords_y, coords_z,
        location, status, responders, call_type, priority, organization_id, routing_bucket,
        UNIX_TIMESTAMP(created_at) AS created_epoch
        FROM cm_legal_incidents WHERE status IN ('waiting', 'accepted')]]) or {}
    local now = os.time()
    for _, row in ipairs(rows) do
        local createdAt = tonumber(row.created_epoch) or now
        if now - createdAt >= expirySeconds then
            MySQL.update.await("UPDATE cm_legal_incidents SET status = 'expired', resolved_at = CURRENT_TIMESTAMP WHERE id = ?", { row.id })
        else
            local responders = {}
            local ok, decoded = pcall(json.decode, row.responders or '[]')
            if ok and type(decoded) == 'table' then
                for _, responder in ipairs(decoded) do
                    if responder.characterId then responders[tostring(responder.characterId)] = responder end
                end
            end
            ActiveCalls[tonumber(row.id)] = {
                id = tonumber(row.id), callerCid = row.caller_cid, callerName = row.caller_name,
                details = row.details, coords = { x = row.coords_x, y = row.coords_y, z = row.coords_z },
                location = row.location, status = row.status, responders = responders, createdAt = createdAt,
                callType = row.call_type or 'citizen', priority = tonumber(row.priority) or 1,
                organizationId = row.organization_id,
                audienceOrganizationId = row.call_type == 'front_desk' and row.organization_id or nil,
                routingBucket = tonumber(row.routing_bucket) or 0,
            }
        end
    end
end)
