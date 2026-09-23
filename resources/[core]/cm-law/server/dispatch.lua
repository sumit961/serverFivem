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
local UnitStates = {} -- session state keyed by character ID; positions are always read live from the server ped

local function organizationShortLabel(organizationId)
    if organizationId == 'police' then return 'LSPD' end
    local org = Config.Organizations[organizationId] or {}
    return tostring(org.shortLabel or org.label or organizationId or 'LAW'):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
end

local function defaultCallsign(member, characterId)
    local suffix = tostring(characterId or ''):gsub('[^%w]', ''):upper()
    suffix = suffix:sub(math.max(1, #suffix - 2))
    if suffix == '' then suffix = '001' end
    return ('%s-%s'):format(organizationShortLabel(member.organizationId), suffix)
end

local function unitState(member, characterId)
    characterId = tostring(characterId)
    local current = UnitStates[characterId]
    if not current then
        current = { status = 'available', callsign = defaultCallsign(member, characterId), updatedAt = os.time() }
        for callId, call in pairs(ActiveCalls) do
            local responder = call.responders and call.responders[characterId]
            if responder then
                current.assignedCallId = callId
                current.status = responder.status == 'on_scene' and 'on_scene' or 'en_route'
                current.callsign = responder.callsign or current.callsign
                break
            end
        end
        UnitStates[characterId] = current
    end
    return current
end

local function commandAllowed(member)
    return member and (member.isLeader == true or (type(member.permissions) == 'table' and member.permissions['law.manage_dispatch'] == true))
end

local function dispatchAudit(member, characterId, action, detail)
    if not member or not characterId then return end
    if member.organizationId == 'police' and type(log) == 'function' then
        log(characterId, action, detail)
    else
        logActivity(member.organizationId, characterId, action, detail)
    end
end

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
    if member then
        if not LawCapabilityEnabled(member.organizationId, 'dispatch') then return nil, characterId end
        return member, characterId
    end
    return nil, characterId
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
            acceptedAt = responder.acceptedAt, callsign = responder.callsign,
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
    MySQL.update.await('UPDATE cm_legal_incidents SET status = ?, responders = ?, resolution = ?, priority = ?, resolved_at = IF(? = 1, CURRENT_TIMESTAMP, resolved_at) WHERE id = ?', {
        call.status, json.encode(responderRows(call)), call.resolution, call.priority or 1,
        (call.status == 'resolved' or call.status == 'expired') and 1 or 0, call.id,
    })
end

local function broadcastToRecipients(event, payload, routingBucket, audienceOrganizationId)
    for _, targetSrc in ipairs(recipients('law.receive_dispatch', routingBucket, audienceOrganizationId)) do
        TriggerClientEvent(event, targetSrc, payload)
    end
end

local function broadcastLiveOperations(routingBucket)
    for _, targetSrc in ipairs(recipients('law.receive_dispatch', routingBucket)) do
        TriggerClientEvent('cm-law:client:liveOperationsUpdated', targetSrc)
    end
end

local function clearUnitAssignments(call)
    for characterId, responder in pairs(call and call.responders or {}) do
        local state = UnitStates[tostring(characterId)]
        if state and tonumber(state.assignedCallId) == tonumber(call.id) then
            state.assignedCallId, state.status, state.updatedAt = nil, 'available', os.time()
        end
        if responder.organizationId == 'police' then
            TriggerEvent('cm-police:server:liveUnitStatusChanged', tostring(characterId), 'available')
        end
    end
end

local function releaseResponder(call, characterId)
    characterId = tostring(characterId or '')
    local responder = call and call.responders and call.responders[characterId]
    if not responder then return nil end
    local state = UnitStates[characterId]
    if state and tonumber(state.assignedCallId) == tonumber(call.id) then
        state.assignedCallId, state.status, state.updatedAt = nil, 'available', os.time()
    end
    if responder.organizationId == 'police' then
        TriggerEvent('cm-police:server:liveUnitStatusChanged', characterId, 'available')
    end
    call.responders[characterId] = nil
    if next(call.responders) == nil then call.status = 'waiting' end
    return responder
end

local function releaseUnitAssignment(characterId)
    characterId = characterId and tostring(characterId) or nil
    if not characterId then return end
    for _, call in pairs(ActiveCalls) do
        if call.responders and call.responders[characterId] then
            releaseResponder(call, characterId)
            persistIncident(call)
            broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
            broadcastLiveOperations(call.routingBucket)
        end
    end
    UnitStates[characterId] = nil
end

local function eligibleUnit(src, bucket)
    local member, characterId = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then return nil end
    if bucket ~= nil and GetPlayerRoutingBucket(src) ~= bucket then return nil end
    return member, tostring(characterId)
end

local function liveUnitRows(viewerSrc)
    local rows, bucket = {}, GetPlayerRoutingBucket(viewerSrc)
    for _, rawSrc in ipairs(GetPlayers()) do
        local targetSrc = tonumber(rawSrc)
        local member, characterId
        if targetSrc then member, characterId = eligibleUnit(targetSrc, bucket) end
        if member then
            local ped = GetPlayerPed(targetSrc)
            local coords = ped and ped > 0 and GetEntityCoords(ped) or nil
            local current = unitState(member, characterId)
            local assignedCall = current.assignedCallId and ActiveCalls[tonumber(current.assignedCallId)] or nil
            if current.assignedCallId and not assignedCall then
                current.assignedCallId, current.status = nil, 'available'
            end
            rows[#rows + 1] = {
                characterId = characterId, name = nameFor(characterId), callsign = current.callsign,
                organizationId = member.organizationId, organizationLabel = organizationShortLabel(member.organizationId),
                rankName = member.rankName, tier = member.tier, status = current.status,
                assignedCallId = current.assignedCallId, updatedAt = current.updatedAt,
                x = coords and coords.x or nil, y = coords and coords.y or nil, z = coords and coords.z or nil,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.status == b.status then return tostring(a.callsign) < tostring(b.callsign) end
        local order = { on_scene = 1, en_route = 2, available = 3, busy = 4, unavailable = 5 }
        return (order[a.status] or 9) < (order[b.status] or 9)
    end)
    return rows
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

lib.callback.register('cm-law:server:liveOperations', function(src)
    local member, characterId = eligibleUnit(tonumber(src))
    if not member then return { ok = false, error = 'Live operations requires on-duty dispatch access.' } end
    local current = unitState(member, characterId)
    return {
        ok = true, selfCharacterId = characterId, selfStatus = current.status,
        selfCallsign = current.callsign, canCommand = commandAllowed(member),
        units = liveUnitRows(tonumber(src)),
        statuses = { 'available', 'busy', 'unavailable' },
        refreshedAt = os.time(),
    }
end)

lib.callback.register('cm-law:server:setUnitStatus', function(src, status)
    src, status = tonumber(src), tostring(status or ''):lower()
    local member, characterId = eligibleUnit(src)
    if not member then return false, 'You must be on duty with dispatch access.' end
    if status ~= 'available' and status ~= 'busy' and status ~= 'unavailable' then return false, 'Invalid unit status.' end
    local current = unitState(member, characterId)
    if current.assignedCallId then return false, 'Clear or resolve your assigned call before changing availability.' end
    current.status, current.updatedAt = status, os.time()
    if member.organizationId == 'police' then TriggerEvent('cm-police:server:liveUnitStatusChanged', characterId, status) end
    broadcastLiveOperations(GetPlayerRoutingBucket(src))
    return true, ('Unit status changed to %s.'):format(status:gsub('_', ' '))
end)

lib.callback.register('cm-law:server:setUnitCallsign', function(src, callsign)
    src = tonumber(src)
    local member, characterId = eligibleUnit(src)
    if not member then return false, 'You must be on duty with dispatch access.' end
    callsign = tostring(callsign or ''):upper():gsub('[^A-Z0-9%-]', ''):sub(1, 12)
    if #callsign < 3 then return false, 'Callsign must contain at least three letters or numbers.' end
    for _, rawSrc in ipairs(GetPlayers()) do
        local otherMember, otherCid = eligibleUnit(tonumber(rawSrc), GetPlayerRoutingBucket(src))
        if otherMember and otherCid ~= characterId and unitState(otherMember, otherCid).callsign == callsign then
            return false, 'That callsign is already active.'
        end
    end
    local current = unitState(member, characterId)
    current.callsign, current.updatedAt = callsign, os.time()
    for _, call in pairs(ActiveCalls) do
        if call.responders[characterId] then call.responders[characterId].callsign = callsign; persistIncident(call) end
    end
    broadcastLiveOperations(GetPlayerRoutingBucket(src))
    return true, ('Callsign set to %s.'):format(callsign)
end)

lib.callback.register('cm-law:server:assignDispatchUnit', function(src, callId, targetCharacterId)
    src, callId, targetCharacterId = tonumber(src), tonumber(callId), tostring(targetCharacterId or '')
    local commander = dispatchMemberForSource(src)
    if not commander or commander.suspended or not commander.onDuty or not commandAllowed(commander) then
        return false, 'Your rank cannot assign units.'
    end
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    if GetPlayerRoutingBucket(src) ~= call.routingBucket then return false, 'That call is in another routing instance.' end
    if call.audienceOrganizationId and call.audienceOrganizationId ~= commander.organizationId then
        return false, 'That call belongs to another organization.'
    end
    local targetSrc = sourceFor(targetCharacterId)
    local targetMember, targetCid
    if targetSrc then targetMember, targetCid = eligibleUnit(targetSrc, call.routingBucket) end
    if not targetMember or targetCid ~= targetCharacterId then return false, 'That unit is no longer available.' end
    if call.audienceOrganizationId and call.audienceOrganizationId ~= targetMember.organizationId then
        return false, 'That unit cannot access this organization-only call.'
    end
    local targetState = unitState(targetMember, targetCid)
    if targetState.status ~= 'available' then return false, 'Only an available unit can be command-assigned.' end
    if targetState.assignedCallId and tonumber(targetState.assignedCallId) ~= callId then return false, 'That unit already has another assignment.' end
    call.responders[targetCid] = call.responders[targetCid] or {
        name = nameFor(targetCid), source = targetSrc, organizationId = targetMember.organizationId,
        acceptedAt = os.time(),
    }
    call.responders[targetCid].status, call.responders[targetCid].callsign = 'en_route', targetState.callsign
    call.status = 'accepted'
    targetState.assignedCallId, targetState.status, targetState.updatedAt = callId, 'en_route', os.time()
    if targetMember.organizationId == 'police' then TriggerEvent('cm-police:server:liveUnitStatusChanged', targetCid, 'en_route') end
    persistIncident(call)
    TriggerClientEvent('cm-law:client:dispatchAssigned', targetSrc, publicCall(call))
    broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    broadcastLiveOperations(call.routingBucket)
    dispatchAudit(commander, characterIdFor(src), 'dispatch_unit_assigned', {
        callId = callId, targetCharacterId = targetCid, callsign = targetState.callsign,
    })
    return true, ('%s assigned to call #%d.'):format(targetState.callsign, callId)
end)

lib.callback.register('cm-law:server:releaseDispatchUnit', function(src, callId, targetCharacterId)
    src, callId, targetCharacterId = tonumber(src), tonumber(callId), tostring(targetCharacterId or '')
    local member, characterId = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then
        return false, 'You must be on duty with dispatch access.'
    end
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    if GetPlayerRoutingBucket(src) ~= call.routingBucket then return false, 'That call is in another routing instance.' end
    if call.audienceOrganizationId and call.audienceOrganizationId ~= member.organizationId then
        return false, 'That call belongs to another organization.'
    end
    if targetCharacterId == '' then targetCharacterId = tostring(characterId or '') end
    local isSelf = targetCharacterId == tostring(characterId)
    if not isSelf and not commandAllowed(member) then return false, 'Your rank cannot release another unit.' end
    local responder = releaseResponder(call, targetCharacterId)
    if not responder then return false, 'That unit is not assigned to this call.' end
    persistIncident(call)
    local targetSrc = sourceFor(targetCharacterId)
    if targetSrc then dispatchNotify(targetSrc, ('You were released from call #%d.'):format(callId), 'inform') end
    broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    broadcastLiveOperations(call.routingBucket)
    dispatchAudit(member, characterId, isSelf and 'dispatch_assignment_cleared' or 'dispatch_unit_released', {
        callId = callId, targetCharacterId = targetCharacterId, callsign = responder.callsign,
    })
    return true, isSelf and 'Assignment cleared. Unit is available.' or ('%s released from call #%d.'):format(responder.callsign or responder.name, callId)
end)

lib.callback.register('cm-law:server:setDispatchPriority', function(src, callId, priority)
    src, callId, priority = tonumber(src), tonumber(callId), math.floor(tonumber(priority) or 0)
    local member, characterId = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not commandAllowed(member) then
        return false, 'Your rank cannot change call priority.'
    end
    local call = callId and ActiveCalls[callId]
    if not call then return false, 'That call is no longer active.' end
    if priority < 1 or priority > 3 then return false, 'Priority must be routine, urgent, or critical.' end
    if GetPlayerRoutingBucket(src) ~= call.routingBucket then return false, 'That call is in another routing instance.' end
    if call.audienceOrganizationId and call.audienceOrganizationId ~= member.organizationId then
        return false, 'That call belongs to another organization.'
    end
    call.priority = priority
    persistIncident(call)
    broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    broadcastLiveOperations(call.routingBucket)
    dispatchAudit(member, characterId, 'dispatch_priority_changed', { callId = callId, priority = priority })
    return true, ('Call #%d priority updated.'):format(callId)
end)

lib.callback.register('cm-law:server:routeToUnit', function(src, targetCharacterId)
    src, targetCharacterId = tonumber(src), tostring(targetCharacterId or '')
    if not eligibleUnit(src) then return false, 'Dispatch access required.' end
    local targetSrc = sourceFor(targetCharacterId)
    local member = targetSrc and eligibleUnit(targetSrc, GetPlayerRoutingBucket(src))
    if not member then return false, 'That unit is no longer available.' end
    local ped = GetPlayerPed(targetSrc)
    if not ped or ped <= 0 then return false, 'Unit location is unavailable.' end
    local coords = GetEntityCoords(ped)
    return true, 'Route set to unit.', { x = coords.x, y = coords.y, z = coords.z }
end)

AddEventHandler('playerDropped', function()
    local characterId = characterIdFor(source)
    releaseUnitAssignment(characterId)
end)

AddEventHandler('cm-law:server:memberWentOffDuty', function(_, characterId)
    releaseUnitAssignment(characterId)
end)

AddEventHandler('cm-police:server:memberWentOffDuty', function(_, characterId)
    releaseUnitAssignment(characterId)
end)

AddEventHandler('cm-law:server:legacyUnitStatusChanged', function(src, characterId, legacyStatus)
    local member, resolvedCid = eligibleUnit(tonumber(src))
    if not member or member.organizationId ~= 'police' or tostring(resolvedCid) ~= tostring(characterId) then return end
    local current = unitState(member, resolvedCid)
    if current.assignedCallId then return end
    current.status = legacyStatus == '10-6' and 'busy' or 'available'
    current.updatedAt = os.time()
    broadcastLiveOperations(GetPlayerRoutingBucket(tonumber(src)))
end)

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
    local officerName = nameFor(characterId)
    local details = alertType == 'panic'
        and ('PANIC BUTTON · OFFICER IN DISTRESS · %s %s'):format(organizationShortLabel(member.organizationId), officerName)
        or ('BACKUP REQUEST · %s %s'):format(organizationShortLabel(member.organizationId), officerName)
    local call, reason = createCall(details, GetEntityCoords(ped), characterId, officerName, {
        callType = alertType, priority = alertType == 'panic' and 3 or 2,
        organizationId = member.organizationId, routingBucket = GetPlayerRoutingBucket(src),
    })
    if not call then return false, reason end
    local detail = { callId = call.id, alertType = alertType, location = call.location }
    if member.organizationId == 'police' and type(log) == 'function' then
        log(characterId, 'dispatch_officer_alert', detail)
    else
        logActivity(member.organizationId, characterId, 'dispatch_officer_alert', detail)
    end
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
    local current = unitState(member, characterId)
    if current.status ~= 'available' and tonumber(current.assignedCallId) ~= callId then
        return false, 'Set your unit available before accepting a call.'
    end
    if current.assignedCallId and tonumber(current.assignedCallId) ~= callId then return false, 'Resolve your current assignment first.' end
    if not call.responders[characterId] then
        call.responders[characterId] = {
            name = nameFor(characterId), source = src, organizationId = member.organizationId,
            acceptedAt = os.time(), status = 'en_route', callsign = current.callsign,
        }
    end
    current.assignedCallId, current.status, current.updatedAt = callId,
        call.responders[characterId].status == 'on_scene' and 'on_scene' or 'en_route', os.time()
    if member.organizationId == 'police' then TriggerEvent('cm-police:server:liveUnitStatusChanged', characterId, current.status) end
    call.status = 'accepted'
    persistIncident(call)
    broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    broadcastLiveOperations(call.routingBucket)
    return true, 'You are responding to the call. Route set.', publicCall(call)
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
    if status ~= 'en_route' and status ~= 'on_scene' then return false, 'Invalid status.' end
    responder.status = status
    local current = unitState(member, characterId)
    current.assignedCallId, current.status, current.updatedAt = callId, status, os.time()
    if member.organizationId == 'police' then TriggerEvent('cm-police:server:liveUnitStatusChanged', characterId, status) end
    persistIncident(call)
    broadcastToRecipients('cm-law:client:dispatchCallUpdated', publicCall(call), call.routingBucket, call.audienceOrganizationId)
    broadcastLiveOperations(call.routingBucket)
    return true, status == 'on_scene' and 'Marked on scene.' or 'Marked en route.'
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
    local responder = characterId and call.responders[characterId]
    local commandClose = not responder and commandAllowed(member)
    if not responder and not commandClose then return false, 'You must accept this call before resolving it.' end
    call.status = 'resolved'
    call.resolution = cleanDetails(resolution or 'Resolved')
    local responseMs = math.max(0, (os.time() - ((responder and responder.acceptedAt) or call.createdAt or os.time())) * 1000)
    persistIncident(call)
    clearUnitAssignments(call)
    ActiveCalls[callId] = nil
    dispatchAudit(member, characterId, commandClose and 'dispatch_call_command_closed' or 'dispatch_call_resolved', {
        callId = callId, details = call.details, responseMs = responseMs,
    })
    if type(LawDailyRecord) == 'function' then LawDailyRecord(src, 'dispatch', 1) end
    broadcastToRecipients('cm-law:client:dispatchCallResolved', callId)
    broadcastLiveOperations(call.routingBucket)
    return true, 'Call marked resolved.'
end)

-- Automatic "shots fired" dispatch, shared across all four cm-law
-- organizations. client/gunfire.lua (embedded/police's own copy, loaded
-- resource-wide) already reports every player's self-detected gunfire on
-- 'cm-police:server:reportGunfire' -- rather than run a second competing
-- IsPedShooting poller just for SAHP/Sheriff/FIB/Army, this adds a second
-- handler on that same event so the one detector reaches every legal
-- organization's dispatch board, not only the legacy Police one. A citizen
-- calling for help (or gunfire being heard) has no way to know which agency
-- is on shift, matching the reasoning already used for /reportlaw.
RegisterNetEvent('cm-police:server:reportGunfire', function(x, y, z)
    local src = source
    if not rateLimit(src, 'law_gunfire_report', Config.Dispatch.GunfireCooldownMs or 120000) then return end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local serverCoords = GetEntityCoords(ped)
    if #(serverCoords - vector3(x, y, z)) > 12.0 then return end
    createCall('Heavy gunfire reported in the area.', serverCoords, nil, 'Gunfire Detection System',
        { routingBucket = GetPlayerRoutingBucket(src), callType = 'gunfire', priority = 2 })
end)

-- Simple count for server/mdt.lua's dashboard aggregation -- no auth needed,
-- it's a bare number with no call detail attached.
function LawActiveCallCount()
    local count = 0
    for _ in pairs(ActiveCalls) do count = count + 1 end
    return count
end

lib.callback.register('cm-law:server:dispatchActiveCalls', function(src)
    local member = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then return {} end
    local list = {}
    local bucket = GetPlayerRoutingBucket(src)
    for _, call in pairs(ActiveCalls) do
        if call.routingBucket == bucket and (not call.audienceOrganizationId or call.audienceOrganizationId == member.organizationId) then list[#list + 1] = publicCall(call) end
    end
    table.sort(list, function(a, b)
        if tonumber(a.priority or 1) == tonumber(b.priority or 1) then return a.createdAt < b.createdAt end
        return tonumber(a.priority or 1) > tonumber(b.priority or 1)
    end)
    return list
end)

lib.callback.register('cm-law:server:dispatchHistory', function(src)
    local member = dispatchMemberForSource(src)
    if not member or member.suspended or not member.onDuty or not hasPerm(member, 'law.receive_dispatch') then return {} end
    local limit = math.max(1, math.min(tonumber(Config.Dispatch.HistoryLimit) or 50, 200))
    local rows = MySQL.query.await([[SELECT id, caller_name, details, location, status, resolution, created_at, resolved_at
        FROM cm_legal_incidents WHERE status IN (?, ?) AND routing_bucket = ?
          AND (call_type <> 'front_desk' OR organization_id = ?)
        ORDER BY id DESC LIMIT ?]], { 'resolved', 'expired', GetPlayerRoutingBucket(src), member.organizationId, limit }) or {}
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
                clearUnitAssignments(call)
                ActiveCalls[callId] = nil
                broadcastToRecipients('cm-law:client:dispatchCallResolved', callId)
                broadcastLiveOperations(call.routingBucket)
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
