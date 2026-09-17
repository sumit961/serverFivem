-- CM License System — Main Server Module

local RequestTimes = {}

local function interactionDistance()
    return (tonumber(CMLicenseConfig.NPC.InteractionDistance) or 3.0) + 1.0
end

-- All player-facing text goes through one path so the client can render it
-- with cm-hud and fall back to chat when cm-hud is not running.
local function notify(src, message, kind)
    if not src or src <= 0 then return end
    TriggerClientEvent('cm-license:client:notify', src, tostring(message), kind or 'inform')
end

local START_ERRORS = {
    already_in_test = 'You are already taking a test.',
    already_licensed = 'You already hold that license.',
    request_in_progress = 'Hold on — your previous request is still being processed.',
    route_not_configured = 'This test has no route configured yet.',
    license_type_not_found = 'That license test is not available.',
    character_not_loaded = 'Your character is not fully loaded yet.',
    insufficient_funds = 'You cannot afford the test fee.',
    vehicle_service_unavailable = 'The examination vehicle service is offline.',
    vehicle_spawn_failed = 'The examination vehicle could not be prepared.',
    temporary_key_failed = 'The examination vehicle keys could not be issued.',
    test_not_configured = 'This test is not fully configured yet.',
    database_error = 'Something went wrong. Your fee has not been taken.',
}

local function startErrorMessage(reason)
    reason = tostring(reason or '')
    local cooldown = reason:match('^retry_cooldown:(%d+)$')
    if cooldown then
        return ('You failed recently. Try again in %s minute(s).'):format(cooldown)
    end
    return START_ERRORS[reason] or ('Failed to start test: ' .. reason)
end

local function adminResult(src, action, ok, payload)
    TriggerClientEvent('cm-license:client:adminResult', src, action, ok == true, payload)
end

local function auditAdmin(src, action, data)
    TriggerEvent('cm-admin:server:addLog', src, 'cm_license_' .. tostring(action), { category='licenses', detail=data or {} })
end

local function rateLimit(src, action, intervalMs)
    local now = GetGameTimer()
    local key = ('%s:%s'):format(src, action)
    if RequestTimes[key] and now - RequestTimes[key] < intervalMs then return false end
    RequestTimes[key] = now
    return true
end

local function isPlayerNearCoords(src, coords, distance)
    local ped = GetPlayerPed(src)
    if ped == 0 or not coords then return false end
    return Utils.DistanceSquared(GetEntityCoords(ped), coords) <= distance * distance
end

-- Show the pass/fail screen and the matching notification.
local function sendResult(src, passed, payload)
    payload = payload or {}
    TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_RESULT, src, {
        passed = passed,
        licenseLabel = payload.licenseLabel,
        licenseType = payload.licenseType,
        category = payload.category,
        validDays = payload.validDays,
        failReason = payload.failReason,
        message = payload.message,
    })
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    print('^2[CM-License]^7 Starting CM License System...')

    Database.Init()
    -- Sessions left in flight by a crash or an unclean stop.
    Database.RecoverStaleSessions()
    Cache.Init()

    print('^2[CM-License]^7 Resource initialized successfully')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    print('^3[CM-License]^7 Stopping CM License System...')

    for charId in pairs(Tests.ActiveSessions) do
        Tests.FailTest(charId, Constants.FAIL_REASON.ADMIN_CANCELLED)
    end

    for src in pairs(Admin.Sessions) do
        Admin.CancelBuilder(src)
    end

    print('^3[CM-License]^7 Resource stopped')
end)

AddEventHandler('playerDropped', function()
    local src = source
    local charId = exports['cm-playerdata']:GetCharacterId(src)

    -- charId may already be nil here, so the session is looked up by source too.
    Tests.OnPlayerDropped(charId, src)

    if charId then
        Licenses.OnPlayerDropped(charId)
    end

    local prefix = tostring(src) .. ':'
    for key in pairs(RequestTimes) do
        if key:sub(1, #prefix) == prefix then RequestTimes[key] = nil end
    end

    Admin.CancelBuilder(src)
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    src = tonumber(src) or source
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    if CMLicenseConfig.Maintenance.CheckOnLoad then
        Licenses.CheckAndCleanupExpired(charId)
    end
    Licenses.DeliverPending(src, charId)
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('HasLicense', function(characterId, licenseType)
    return Licenses.HasLicense(characterId, licenseType)
end)

exports('GetLicense', function(characterId, licenseType)
    return Licenses.GetLicense(characterId, licenseType)
end)

exports('GetLicenses', function(characterId)
    return Licenses.GetLicenses(characterId)
end)

-- Compact map of license_type -> { status, expiresAt, ... } for ID checks.
exports('GetLicenseSummary', function(characterId)
    return Licenses.GetLicenseSummary(characterId)
end)

exports('IssueLicense', function(characterId, licenseTypeId, validDays)
    return Licenses.IssueLicense(characterId, licenseTypeId, validDays)
end)

exports('RevokeLicense', function(characterId, licenseTypeId, revokedBy, reason)
    return Licenses.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
end)

exports('IsInTest', function(characterId)
    return Tests.GetActiveTest(characterId) ~= nil
end)

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================

RegisterNetEvent(Constants.EVENTS.SERVER.REQUEST_START_TEST, function(licenseTypeId)
    local src = source
    if not rateLimit(src, 'start_test', 1500) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)

    local requestedType = type(licenseTypeId) == 'table' and licenseTypeId.licenseType or licenseTypeId
    licenseTypeId = tonumber(requestedType)
    if not licenseTypeId and type(requestedType) == 'string' then
        local record = Cache.GetLicenseTypeByName(requestedType:lower())
        licenseTypeId = record and tonumber(record.id) or nil
    end

    if not charId or not licenseTypeId then
        notify(src, 'Invalid test request.', 'error')
        return
    end

    local requestedLicense = Cache.GetLicenseType(licenseTypeId)
    if not requestedLicense or not isPlayerNearCoords(src, Utils.DecodeObject(requestedLicense.npc_coords), interactionDistance()) then
        return
    end

    local ok, result = Tests.StartTest(src, charId, licenseTypeId)

    if ok then
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_STARTED, src, result)
    else
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
            reason = result,
            message = startErrorMessage(result),
            silent = true,
        })
        notify(src, startErrorMessage(result), 'error')
    end
end)

RegisterNetEvent(Constants.EVENTS.SERVER.START_TEST, function(testId, vehicleNetId)
    local src = source
    if not rateLimit(src, 'begin_test', 1000) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    local ok, result = Tests.BeginTest(charId, testId, vehicleNetId)
    if ok then
        TriggerClientEvent('cm-license:client:testBegan', src, result)
    else
        Tests.FailTest(charId, result)
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
            reason = result, message = 'The test could not be started securely.'
        })
    end
end)

RegisterNetEvent(Constants.EVENTS.SERVER.CHECKPOINT_REACHED, function(checkpointNumber)
    local src = source
    -- Deliberately permissive: the client retries an unacknowledged checkpoint,
    -- and two markers can legitimately be crossed in quick succession.
    if not rateLimit(src, 'checkpoint', 250) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    local session = Tests.GetActiveTest(charId)
    if not session then return end

    local ok, checkpointError = Tests.ReportCheckpoint(charId, checkpointNumber)
    if not ok then
        TriggerClientEvent(Constants.EVENTS.CLIENT.CHECKPOINT_REJECTED, src, {
            reason = checkpointError,
            expected = session.currentCheckpoint + 1,
            message = checkpointError == 'unsafe_landing' and 'Land safely and stop the helicopter.' or nil,
        })
        return
    end

    TriggerClientEvent(Constants.EVENTS.CLIENT.SET_CHECKPOINT, src, {
        currentCheckpoint = checkpointNumber,
        totalCheckpoints = session.totalCheckpoints,
        secondsRemaining = math.max(0, (session.expiresAt or 0) - os.time()),
    })
end)

RegisterNetEvent(Constants.EVENTS.SERVER.REPORT_MISTAKE, function(reason)
    local src = source
    if not rateLimit(src, 'mistake', 1000) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    local allowed = { collision = true, speeding = true, altitude_violation = true }
    reason = tostring(reason or '')
    if not allowed[reason] then return end

    local session = Tests.GetActiveTest(charId)
    local survived, info = Tests.ReportMistake(charId, reason)
    if survived and type(info) == 'table' then
        TriggerClientEvent('cm-license:client:mistake', src, info)
    elseif not survived and info == 'failed' then
        local message = Constants.RESULT_MESSAGES.too_many_mistakes
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
            reason = Constants.FAIL_REASON.TOO_MANY_MISTAKES, message = message
        })
        sendResult(src, false, { failReason = message, message = 'Take the test again when you are ready.',
            licenseType = session and session.licenseType, category = session and session.category })
    end
end)

RegisterNetEvent(Constants.EVENTS.SERVER.FINISH_TEST, function()
    local src = source
    if not rateLimit(src, 'finish_test', 1000) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    local ok, result = Tests.CompleteTest(charId)

    if ok then
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_COMPLETED, src, result)
        sendResult(src, true, {
            licenseLabel = result.licenseLabel,
            licenseType = result.licenseType,
            category = result.category,
            validDays = result.validDays,
            message = result.delivered and ('Valid for %d days. The card is in your inventory.'):format(result.validDays or 0)
                or ('Valid for %d days. Your inventory was full — collect the card from the instructor.'):format(result.validDays or 0),
        })
    elseif result == 'not_all_checkpoints_completed' then
        -- The session survives: tell the client to resume rather than stranding
        -- the player in a test they can no longer finish.
        local session = Tests.GetActiveTest(charId)
        TriggerClientEvent(Constants.EVENTS.CLIENT.COMPLETION_REJECTED, src, {
            currentCheckpoint = session and session.currentCheckpoint or 0,
            totalCheckpoints = session and session.totalCheckpoints or 0,
        })
    elseif result ~= 'no_active_test' then
        local message = Constants.RESULT_MESSAGES[result] or 'Test failed'
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, { reason = result, message = message })
        sendResult(src, false, { failReason = message })
    end
end)

RegisterNetEvent(Constants.EVENTS.SERVER.CANCEL_TEST, function()
    local src = source
    if not rateLimit(src, 'cancel_test', 1000) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    if Tests.CancelTest(charId) then
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
            reason = Constants.FAIL_REASON.CANCELLED,
            message = Constants.RESULT_MESSAGES.cancelled,
            silent = true,
        })
        notify(src, 'Test cancelled. The fee is not refunded.', 'inform')
    end
end)

RegisterNetEvent(Constants.EVENTS.SERVER.TEST_FAILED, function(reason)
    local src = source
    if not rateLimit(src, 'fail_test', 1000) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    local allowedReasons = {}
    for _, value in pairs(Constants.FAIL_REASON) do allowedReasons[value] = true end
    reason = tostring(reason or '')
    if not allowedReasons[reason] then reason = Constants.FAIL_REASON.INVALID_CLIENT_FAILURE end

    local failed, session = Tests.FailTest(charId, reason)
    if not failed then return end

    local message = Constants.RESULT_MESSAGES[reason] or 'Test failed'
    TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, { reason = reason, message = message })
    sendResult(src, false, { failReason = message, message = 'Speak to the instructor to try again.',
        licenseType = session and session.licenseType, category = session and session.category })
end)

RegisterNetEvent('cm-license:server:requestMyLicenses', function()
    local src = source
    if not rateLimit(src, 'my_licenses', 500) then return end

    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end

    TriggerClientEvent('cm-license:client:showMyLicenses', src, Licenses.GetLicenses(charId) or {})
end)

RegisterNetEvent('cm-license:server:getNPCLocations', function()
    local src = source
    if not rateLimit(src, 'npc_menu', 500) then return end

    local nearby = {}
    for _, licenseType in ipairs(Cache.GetLicenseTypes() or {}) do
        if isPlayerNearCoords(src, Utils.DecodeObject(licenseType.npc_coords), interactionDistance()) then
            nearby[#nearby + 1] = licenseType
        end
    end

    if #nearby > 0 then
        TriggerClientEvent('cm-license:client:showLicenseMenu', src, nearby)
    end
end)

RegisterNetEvent('cm-license:server:requestNPCDefinitions', function()
    local src = source
    if not rateLimit(src, 'npc_definitions', 2000) then return end

    local definitions, seen = {}, {}
    for _, licenseType in ipairs(Cache.GetLicenseTypes() or {}) do
        local coords = Utils.DecodeObject(licenseType.npc_coords)
        local key = coords and ('%.3f:%.3f:%.3f:%s'):format(coords.x, coords.y, coords.z, licenseType.npc_model or '') or nil
        if key and not seen[key] and licenseType.npc_model then
            seen[key] = true
            definitions[#definitions + 1] = { model = licenseType.npc_model, coords = coords,
                name = CMLicenseConfig.NPC.Name, role = CMLicenseConfig.NPC.Role }
        end
    end

    TriggerClientEvent('cm-license:client:setNPCDefinitions', src, definitions)
end)

-- Local-only authoritative inventory contract. The physical card and the
-- database entitlement move together: dropping the card revokes the license,
-- picking your own card back up re-activates that same license.

local function onLicenseDropped(src, ownerId, itemName, amount, metadata)
    if tonumber(amount) ~= 1 then return end

    local ok = Licenses.RevokeDroppedItem(tonumber(src), tonumber(ownerId), tostring(itemName or ''), metadata)
    if ok then
        auditAdmin(tonumber(src), 'license_discarded', { itemName=tostring(itemName), characterId=tonumber(ownerId) })
        notify(tonumber(src), 'You discarded your license. It is no longer valid.', 'error')
    end
end

local PICKUP_FAILURES = {
    item_owner_mismatch = 'This license belongs to someone else — it is worthless to you.',
    revoked_by_authority = 'This license was revoked by the authorities. Picking it up does not restore it.',
    expired = 'This license expired while it was out of your hands.',
    superseded_card = 'This card was replaced by a newer license and is no longer valid.',
    no_license_record = 'There is no record of this license.',
}

local function onLicensePickedUp(src, ownerId, itemName, amount, metadata)
    if tonumber(amount) ~= 1 then return end

    local ok, result = Licenses.RestoreDroppedItem(tonumber(src), tonumber(ownerId), tostring(itemName or ''), metadata)
    if ok then
        auditAdmin(tonumber(src), 'license_restored', { itemName=tostring(itemName), characterId=tonumber(ownerId) })
        notify(tonumber(src), ('You picked your %s back up. It is valid again.')
            :format(type(result) == 'table' and result.label or 'license'), 'success')
        return
    end

    -- 'already_active' and 'not_license_item' are silent: nothing was wrong.
    local message = PICKUP_FAILURES[result]
    if message then notify(tonumber(src), message, 'error') end
end

AddEventHandler('cm-inventory:server:itemDropped', onLicenseDropped)
AddEventHandler('cm-inventory:server:itemPickedUp', onLicensePickedUp)

-- Exported so cm-inventory can call the pick-up hook directly if its event is
-- named differently from the drop event this resource already listens to.
exports('OnLicenseItemPickedUp', onLicensePickedUp)

-- ============================================================================
-- ADMIN COMMANDS
-- ============================================================================

TriggerEvent('chat:addSuggestion', '/licensesetup', 'Open license setup, or record a route directly', {
    { name='vehicle type', help='car, boat, or air (optional)' }
})
TriggerEvent('chat:addSuggestion', '/givelicense', 'Issue a license to a player', {
    { name='id', help='server id' }, { name='type', help='driver, boat or air' }, { name='days', help='optional validity override' }
})
TriggerEvent('chat:addSuggestion', '/revokelicense', 'Revoke a player license', {
    { name='id', help='server id' }, { name='type', help='driver, boat or air' }, { name='reason', help='optional' }
})
TriggerEvent('chat:addSuggestion', '/licenses', 'List a player\'s licenses', {
    { name='id', help='server id (defaults to yourself)' }
})

RegisterCommand('licensesetup', function(source, args)
    local src = source
    if not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    local requested = tostring(args[1] or ''):lower()
    if requested == '' then
        TriggerClientEvent('cm-license:client:openAdminMenu', src, Admin.GetAllLicenseTypes())
        return
    end

    local typeName = ({car='driver',driver='driver',boat='boat',air='air'})[requested]
    if not typeName then
        notify(src, 'Usage: /licensesetup car | boat | air', 'inform')
        return
    end

    local licenseType = Cache.GetLicenseTypeByName(typeName)
    if not licenseType then
        notify(src, 'Standard license definitions are not available.', 'error')
        return
    end

    local ok, result = Admin.BeginBuilder(src, licenseType.id)
    if ok then auditAdmin(src, 'route_builder_started', { licenseType=typeName }) end
    adminResult(src, 'beginBuilder', ok, type(result)=='table' and result or { message=tostring(result) })
end, false)

local function resolveTarget(src, targetId)
    targetId = tonumber(targetId)
    if not targetId then return nil, 'Invalid server id.' end
    local charId = exports['cm-playerdata']:GetCharacterId(targetId)
    if not charId then return nil, 'That player has no character loaded.' end
    return targetId, nil, charId
end

RegisterCommand('givelicense', function(source, args)
    local src = source
    if not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.ISSUE_LICENSES) then return end

    local targetId, err, charId = resolveTarget(src, args[1])
    if not targetId then return notify(src, err, 'error') end

    local licenseType = Cache.GetLicenseTypeByName(tostring(args[2] or ''):lower())
    if not licenseType then return notify(src, 'Unknown license type.', 'error') end

    local ok, result = Licenses.IssueLicense(charId, licenseType.id, tonumber(args[3]))
    if not ok then return notify(src, 'Could not issue that license: ' .. tostring(result), 'error') end

    Licenses.DeliverPending(targetId, charId)
    auditAdmin(src, 'license_granted', { characterId=charId, licenseTypeId=licenseType.id })
    notify(src, ('Issued %s to server id %d.'):format(licenseType.label, targetId), 'success')
    notify(targetId, ('You have been issued a %s.'):format(licenseType.label), 'success')
end, false)

RegisterCommand('revokelicense', function(source, args)
    local src = source
    if not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.REVOKE_LICENSES) then return end

    local targetId, err, charId = resolveTarget(src, args[1])
    if not targetId then return notify(src, err, 'error') end

    local licenseType = Cache.GetLicenseTypeByName(tostring(args[2] or ''):lower())
    if not licenseType then return notify(src, 'Unknown license type.', 'error') end

    local reason = table.concat(args, ' ', 3)
    local adminCharId = exports['cm-playerdata']:GetCharacterId(src) or 0
    local ok, failure = Licenses.RevokeLicense(charId, licenseType.id, adminCharId, reason ~= '' and reason or 'admin_revoked')
    if not ok then return notify(src, 'Could not revoke: ' .. tostring(failure), 'error') end

    auditAdmin(src, 'license_revoked', { characterId=charId, licenseTypeId=licenseType.id, reason=reason })
    notify(src, ('Revoked %s from server id %d.'):format(licenseType.label, targetId), 'success')
    notify(targetId, ('Your %s has been revoked.'):format(licenseType.label), 'error')
end, false)

RegisterCommand('licenses', function(source, args)
    local src = source
    if not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    local targetId = tonumber(args[1]) or src
    local charId = exports['cm-playerdata']:GetCharacterId(targetId)
    if not charId then return notify(src, 'That player has no character loaded.', 'error') end

    local licenses = Licenses.GetLicenses(charId)
    if #licenses == 0 then return notify(src, 'That character holds no licenses.', 'inform') end

    for _, license in ipairs(licenses) do
        notify(src, ('%s — %s, expires %s (%d days)'):format(license.label,
            license.isExpired and 'EXPIRED' or string.upper(license.status),
            license.expiresAtDate, license.remainingDays), 'inform')
    end
end, false)

-- ============================================================================
-- ADMIN NUI EVENTS
-- ============================================================================

RegisterNetEvent('cm-license:server:adminSaveType', function(data)
    local src = source
    if not rateLimit(src, 'admin_save_type', 800) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    local id = type(data) == 'table' and tonumber(data.id) or nil
    local ok, result = id and Admin.UpdateLicenseType(id, data) or Admin.CreateLicenseType(data)
    if ok then auditAdmin(src, id and 'type_updated' or 'type_created', { licenseTypeId = id or result }) end

    adminResult(src, 'saveType', ok, {
        message = ok and 'License test saved.' or tostring(result),
        id = id or (ok and result or nil),
        tests = Admin.GetAllLicenseTypes(),
    })
end)

RegisterNetEvent('cm-license:server:adminDeleteType', function(typeId)
    local src = source
    if not rateLimit(src, 'admin_delete_type', 1000) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    typeId = type(typeId) == 'table' and tonumber(typeId.id) or tonumber(typeId)
    local ok, reason = Admin.DeleteLicenseType(typeId)
    if ok then auditAdmin(src, 'type_deleted', { licenseTypeId = typeId }) end

    adminResult(src, 'deleteType', ok, {
        message = ok and 'License test deleted.' or tostring(reason),
        tests = Admin.GetAllLicenseTypes(),
    })
end)

-- The NUI sends a single payload; older callers passed positional arguments.
RegisterNetEvent('cm-license:server:adminSetNpc', function(typeId, model, scenario)
    local src = source
    if not rateLimit(src, 'admin_set_npc', 800) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    if type(typeId) == 'table' then
        local payload = typeId
        typeId = tonumber(payload.id) or tonumber(payload.typeId)
        model = payload.npcModel or payload.npc_model or payload.model
        scenario = payload.npcScenario or payload.npc_scenario or payload.scenario
    end

    local ok, result = Admin.SaveNpcAtPlayer(src, typeId, model, scenario)
    if ok then auditAdmin(src, 'npc_saved', { licenseTypeId = tonumber(typeId) }) end

    adminResult(src, 'setNpc', ok, {
        message = ok and 'Instructor NPC saved at your position. Restart the resource or rejoin to see it move.' or tostring(result),
        tests = Admin.GetAllLicenseTypes(),
    })

    if ok then
        -- Push the new placement to everyone immediately.
        for _, player in ipairs(GetPlayers()) do
            TriggerEvent('cm-license:server:refreshNPCsFor', tonumber(player))
        end
    end
end)

AddEventHandler('cm-license:server:refreshNPCsFor', function(target)
    local definitions, seen = {}, {}
    for _, licenseType in ipairs(Cache.GetLicenseTypes() or {}) do
        local coords = Utils.DecodeObject(licenseType.npc_coords)
        local key = coords and ('%.3f:%.3f:%.3f:%s'):format(coords.x, coords.y, coords.z, licenseType.npc_model or '') or nil
        if key and not seen[key] and licenseType.npc_model then
            seen[key] = true
            definitions[#definitions + 1] = { model = licenseType.npc_model, coords = coords,
                name = CMLicenseConfig.NPC.Name, role = CMLicenseConfig.NPC.Role }
        end
    end
    TriggerClientEvent('cm-license:client:setNPCDefinitions', target, definitions)
end)

RegisterNetEvent('cm-license:server:adminBeginBuilder', function(payload)
    local src = source
    if not rateLimit(src, 'admin_begin_builder', 1000) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    local typeId, replaceRouteId
    if type(payload) == 'table' then
        typeId = tonumber(payload.id)
        replaceRouteId = tonumber(payload.routeId)
    else
        typeId = tonumber(payload)
    end

    local ok, result = Admin.BeginBuilder(src, typeId, replaceRouteId)
    if ok then auditAdmin(src, 'route_builder_started', { licenseTypeId = typeId, replaceRouteId = replaceRouteId }) end
    adminResult(src, 'beginBuilder', ok, type(result)=='table' and result or { message=tostring(result) })
end)

-- Routes are listed on demand: a type can own many and the exam draws one.
RegisterNetEvent('cm-license:server:adminListRoutes', function(typeId)
    local src = source
    if not rateLimit(src, 'admin_list_routes', 400) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    typeId = type(typeId) == 'table' and tonumber(typeId.id) or tonumber(typeId)
    local licenseType = typeId and Database.GetLicenseType(typeId)
    if not licenseType then
        adminResult(src, 'listRoutes', false, { message = 'That license test no longer exists.' })
        return
    end

    adminResult(src, 'listRoutes', true, {
        licenseTypeId = typeId,
        licenseLabel = licenseType.label,
        licenseType = licenseType.license_type,
        routes = Admin.GetRoutes(typeId),
    })
end)

RegisterNetEvent('cm-license:server:adminDeleteRoute', function(payload)
    local src = source
    if not rateLimit(src, 'admin_delete_route', 600) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    local routeId = type(payload) == 'table' and tonumber(payload.routeId) or tonumber(payload)
    local ok, typeIdOrError = Admin.DeleteRoute(routeId)
    if ok then auditAdmin(src, 'route_deleted', { routeId = routeId }) end

    adminResult(src, 'deleteRoute', ok, {
        message = ok and 'Route deleted.' or tostring(typeIdOrError),
        licenseTypeId = ok and typeIdOrError or nil,
        routes = ok and Admin.GetRoutes(typeIdOrError) or nil,
        tests = ok and Admin.GetAllLicenseTypes() or nil,
    })
end)

RegisterNetEvent('cm-license:server:adminToggleRoute', function(payload)
    local src = source
    if not rateLimit(src, 'admin_toggle_route', 600) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    payload = type(payload) == 'table' and payload or {}
    local ok, typeIdOrError = Admin.SetRouteEnabled(tonumber(payload.routeId), payload.enabled == true)
    if ok then auditAdmin(src, 'route_toggled', { routeId = tonumber(payload.routeId), enabled = payload.enabled == true }) end

    adminResult(src, 'toggleRoute', ok, {
        message = ok and (payload.enabled and 'Route enabled.' or 'Route disabled.') or tostring(typeIdOrError),
        licenseTypeId = ok and typeIdOrError or nil,
        routes = ok and Admin.GetRoutes(typeIdOrError) or nil,
        tests = ok and Admin.GetAllLicenseTypes() or nil,
    })
end)

RegisterNetEvent('cm-license:server:adminBuilderAction', function(action)
    local src = source
    if not rateLimit(src, 'admin_builder_action', 250) or not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end

    action = tostring(action or '')
    if action ~= 'save_spawn' and action ~= 'add_point' and action ~= 'undo' and action ~= 'finish' then return end

    local ok, result = Admin.BuilderAction(src, action)
    if ok and type(result) == 'table' and result.stage == 'complete' then
        auditAdmin(src, 'route_saved', { count = result.count })
    end
    adminResult(src, 'builderAction', ok, type(result)=='table' and result or { message=tostring(result) })
end)

RegisterNetEvent('cm-license:server:adminCancelBuilder', function()
    local src = source
    if not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then return end
    Admin.CancelBuilder(src)
    adminResult(src, 'cancelBuilder', true, { message='Route builder cancelled.' })
end)

-- ============================================================================
-- PERIODIC MAINTENANCE
-- ============================================================================

local function periodicMaintenance()
    Tests.CleanupExpiredSessions()

    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        local characterId = src and exports['cm-playerdata']:GetCharacterId(src) or nil
        if characterId then
            Licenses.CheckAndCleanupExpired(characterId)
            Licenses.DeliverPending(src, characterId)
        end
    end
end

CreateThread(function()
    local interval = (tonumber(CMLicenseConfig.Maintenance.IntervalMinutes) or 5) * 60 * 1000
    while true do
        Wait(interval)
        periodicMaintenance()
    end
end)

-- The exam clock is enforced independently of the slower maintenance pass.
CreateThread(function()
    while true do
        Wait(10000)
        Tests.CleanupExpiredSessions()
    end
end)

if CMLicenseConfig.Debug then
    RegisterCommand('lsinfo', function(source)
        local src = source
        local charId = exports['cm-playerdata']:GetCharacterId(src)
        if not charId then
            print('Character not loaded')
            return
        end

        for _, lic in ipairs(Licenses.GetLicenses(charId) or {}) do
            print(('  - %s: %s (%d days)'):format(lic.label, lic.status, lic.remainingDays))
        end

        local activeTest = Tests.GetActiveTest(charId)
        print(activeTest
            and ('^3[CM-License]^7 Active test: checkpoint %d/%d'):format(activeTest.currentCheckpoint, activeTest.totalCheckpoints)
            or '^3[CM-License]^7 No active test')

        local stats = Cache.GetStats()
        print(('^3[CM-License]^7 Cache: %d types, %d routes, %d checkpoints'):format(stats.licenseTypes, stats.routes, stats.checkpoints))
    end, false)
end

print('^2[CM-License]^7 Server module loaded')
