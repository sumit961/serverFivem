-- CM License System — Main Server Module

local RequestTimes = {}
local NPCInteractionDistance = 3.0
local MaintenanceIntervalMinutes = 5

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

local function decodeCoords(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
end

local function isPlayerNearCoords(src, coords, distance)
    local ped = GetPlayerPed(src)
    if ped == 0 or not coords then return false end
    local playerCoords = GetEntityCoords(ped)
    local dx, dy, dz = playerCoords.x - coords.x, playerCoords.y - coords.y, playerCoords.z - coords.z
    return (dx * dx + dy * dy + dz * dz) <= distance * distance
end

-- Initialize resource
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    print('^2[CM-License]^7 Starting CM License System...')
    
    -- Initialize database
    Database.Init()
    
    -- Initialize cache
    Cache.Init()
    
    print('^2[CM-License]^7 Resource initialized successfully')
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    print('^3[CM-License]^7 Stopping CM License System...')
    
    -- Fail all active tests
    for charId, session in pairs(Tests.ActiveSessions) do
        Tests.FailTest(charId, Constants.FAIL_REASON.ADMIN_CANCELLED)
    end
    
    print('^3[CM-License]^7 Resource stopped')
end)

-- Player disconnect handler
AddEventHandler('playerDropped', function(reason)
    local src = source
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    
    if charId then
        -- Cleanup any active tests
        Tests.OnPlayerDropped(charId)
        
        -- Cleanup licenses
        Licenses.OnPlayerDropped(charId)
    end
    local prefix = tostring(src) .. ':'
    for key in pairs(RequestTimes) do
        if key:sub(1, #prefix) == prefix then RequestTimes[key] = nil end
    end
    Admin.CancelBuilder(src)
end)

-- Character loaded event
AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    src = tonumber(src) or source
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    
    if charId then
        -- Check and cleanup expired licenses
        Licenses.CheckAndCleanupExpired(charId)
        Licenses.DeliverPending(src, charId)
    end
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

exports('RevokeLicense', function(characterId, licenseTypeId, revokedBy, reason)
    return Licenses.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
end)

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================

-- Request to start a test
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
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'Error', 'Invalid test request' }
        })
        return
    end
    local requestedLicense = Cache.GetLicenseType(licenseTypeId)
    if not requestedLicense or not isPlayerNearCoords(src, decodeCoords(requestedLicense.npc_coords), NPCInteractionDistance + 1.0) then
        return
    end
    
    -- Start test
    local ok, result = Tests.StartTest(src, charId, licenseTypeId)
    
    if ok then
        -- Notify client
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_STARTED, src, result)
    else
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
            reason = result,
            message = 'Failed to start test: ' .. tostring(result)
        })
        -- Notify client of failure
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'License System', 'Failed to start test: ' .. tostring(result) },
            color = { 255, 0, 0 }
        })
    end
end)

RegisterNetEvent(Constants.EVENTS.SERVER.START_TEST, function(testId, vehicleNetId)
    local src = source
    if not rateLimit(src, 'begin_test', 1000) then return end
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end
    local ok, reason = Tests.BeginTest(charId, testId, vehicleNetId)
    if not ok then
        Tests.FailTest(charId, reason)
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, { reason = reason, message = 'The test could not be started securely.' })
    end
end)

-- Checkpoint reached
RegisterNetEvent(Constants.EVENTS.SERVER.CHECKPOINT_REACHED, function(checkpointNumber)
    local src = source
    if not rateLimit(src, 'checkpoint', 500) then return end
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    
    if not charId then return end
    
    local session = Tests.GetActiveTest(charId)
    if not session then
        print('^1[CM-License]^7 Checkpoint report from ' .. charId .. ' but no active test!')
        return
    end
    
    -- Validate checkpoint number
    if checkpointNumber ~= session.currentCheckpoint + 1 then
        print('^3[CM-License]^7 Invalid checkpoint: ' .. checkpointNumber .. ', expected ' .. (session.currentCheckpoint + 1))
        return
    end
    
    local ok, checkpointError = Tests.ReportCheckpoint(charId, checkpointNumber)
    if not ok then
        TriggerClientEvent('cm-license:client:checkpointRejected', src,
            checkpointError == 'unsafe_landing' and 'Land safely and stop the helicopter.' or 'Checkpoint was not accepted.')
        return
    end
    
    -- Notify client
    TriggerClientEvent(Constants.EVENTS.CLIENT.SET_CHECKPOINT, src, {
        currentCheckpoint = checkpointNumber,
        totalCheckpoints = session.totalCheckpoints
    })
end)

-- Finish test
RegisterNetEvent(Constants.EVENTS.SERVER.FINISH_TEST, function()
    local src = source
    if not rateLimit(src, 'finish_test', 1000) then return end
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    
    if not charId then return end
    
    local ok, result = Tests.CompleteTest(charId)
    
    if ok then
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_COMPLETED, src, result)
    else
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
            reason = 'completion_failed',
            message = result
        })
    end
end)

-- Cancel test
RegisterNetEvent(Constants.EVENTS.SERVER.CANCEL_TEST, function()
    local src = source
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    
    if not charId then return end
    
    Tests.CancelTest(charId)
    
    -- Notify client
    TriggerClientEvent('chat:addMessage', src, {
        args = { 'License System', 'Test cancelled' }
    })
end)

-- Test failed (client reports failure)
RegisterNetEvent(Constants.EVENTS.SERVER.TEST_FAILED, function(reason)
    local src = source
    if not rateLimit(src, 'fail_test', 1000) then return end
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    
    if not charId then return end
    
    local allowedReasons = {}
    for _, value in pairs(Constants.FAIL_REASON) do allowedReasons[value] = true end
    reason = tostring(reason or '')
    if not allowedReasons[reason] then reason = 'invalid_client_failure' end
    Tests.FailTest(charId, reason)
    
    -- Notify client
    TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
        reason = reason,
        message = Constants.RESULT_MESSAGES[reason] or 'Test failed'
    })
end)

-- Request My Licenses
RegisterNetEvent('cm-license:server:requestMyLicenses', function()
    local src = source
    local charId = exports['cm-playerdata']:GetCharacterId(src)
    if not charId then return end
    local licenses = Licenses.GetLicenses(charId)
    
    TriggerClientEvent('cm-license:client:showMyLicenses', src, licenses or {})
end)

-- Get NPC Locations (player near NPC)
RegisterNetEvent('cm-license:server:getNPCLocations', function()
    local src = source
    if not rateLimit(src, 'npc_menu', 500) then return end
    local licenseTypes = Cache.GetLicenseTypes()
    local nearby = {}
    for _, licenseType in ipairs(licenseTypes or {}) do
        local coords = decodeCoords(licenseType.npc_coords)
        if isPlayerNearCoords(src, coords, NPCInteractionDistance + 1.0) then
            nearby[#nearby + 1] = licenseType
        end
    end
    if #nearby > 0 then
        TriggerClientEvent('cm-license:client:showLicenseMenu', src, nearby)
    end
end)

-- Local-only authoritative inventory contract. Dropping the physical license
-- revokes the matching database entitlement for that character.
AddEventHandler('cm-inventory:server:itemDropped', function(src, ownerId, itemName, amount, metadata)
    if tonumber(amount) ~= 1 then return end
    local ok = Licenses.RevokeDroppedItem(tonumber(src), tonumber(ownerId), tostring(itemName or ''), metadata)
    if ok then
        auditAdmin(tonumber(src), 'license_discarded', { itemName=tostring(itemName), characterId=tonumber(ownerId) })
        TriggerClientEvent('chat:addMessage', tonumber(src), {
            args={'License System','You discarded your license. It is no longer valid.'}, color={255,120,80}
        })
    end
end)

RegisterNetEvent('cm-license:server:requestNPCDefinitions', function()
    local src = source
    if not rateLimit(src, 'npc_definitions', 2000) then return end
    local definitions = {}
    local seen = {}
    for _, licenseType in ipairs(Cache.GetLicenseTypes() or {}) do
        local coords = decodeCoords(licenseType.npc_coords)
        local key = coords and ('%.3f:%.3f:%.3f:%s'):format(coords.x,coords.y,coords.z,licenseType.npc_model or '') or nil
        if key and not seen[key] and licenseType.npc_model then
            seen[key] = true
            definitions[#definitions + 1] = { model = licenseType.npc_model, coords = coords,
                name=CMLicenseConfig.NPC.Name, role=CMLicenseConfig.NPC.Role }
        end
    end
    TriggerClientEvent('cm-license:client:setNPCDefinitions', src, definitions)
end)

-- ============================================================================
-- ADMIN COMMANDS
-- ============================================================================

TriggerEvent('chat:addSuggestion', '/licensesetup', 'Record a license route', {
    { name='vehicle type', help='car, boat, or air' }
})

RegisterCommand('licensesetup', function(source, args, rawCommand)
    local src = source
    
    -- Check permission
    if not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then
        return
    end
    
    local requested = tostring(args[1] or ''):lower()
    if requested == '' then
        TriggerClientEvent('cm-license:client:openAdminMenu', src, Admin.GetAllLicenseTypes())
        return
    end
    local typeName = ({car='driver',driver='driver',boat='boat',air='air'})[requested]
    if not typeName then
        TriggerClientEvent('chat:addMessage',src,{args={'License Setup','Usage: /licensesetup car | boat | air'},color={0,229,255}})
        return
    end
    local licenseType = Cache.GetLicenseTypeByName(typeName)
    if not licenseType then
        TriggerClientEvent('chat:addMessage',src,{args={'License Setup','Standard license definitions are not available.'},color={255,80,80}})
        return
    end
    local ok,result=Admin.BeginBuilder(src,licenseType.id)
    if ok then auditAdmin(src,'route_builder_started',{licenseType=typeName}) end
    adminResult(src,'beginBuilder',ok,type(result)=='table' and result or {message=tostring(result)})
end, false)

RegisterNetEvent('cm-license:server:adminSaveType', function(data)
    local src=source
    if not rateLimit(src,'admin_save_type',800) or not Admin.ValidateAdminAction(src,Constants.PERMISSIONS.MANAGE_LICENSES) then return end
    local id=type(data)=='table' and tonumber(data.id) or nil
    local ok,result=id and Admin.UpdateLicenseType(id,data) or Admin.CreateLicenseType(data)
    if ok then auditAdmin(src,id and 'type_updated' or 'type_created',{licenseTypeId=id or result}) end
    adminResult(src,'saveType',ok,{message=ok and 'License test saved.' or tostring(result),id=id or (ok and result or nil),tests=Admin.GetAllLicenseTypes()})
end)

RegisterNetEvent('cm-license:server:adminDeleteType', function(typeId)
    local src=source
    if not rateLimit(src,'admin_delete_type',1000) or not Admin.ValidateAdminAction(src,Constants.PERMISSIONS.MANAGE_LICENSES) then return end
    local ok,reason=Admin.DeleteLicenseType(tonumber(typeId))
    if ok then auditAdmin(src,'type_deleted',{licenseTypeId=tonumber(typeId)}) end
    adminResult(src,'deleteType',ok,{message=ok and 'License test deleted.' or tostring(reason),tests=Admin.GetAllLicenseTypes()})
end)

RegisterNetEvent('cm-license:server:adminSetNpc', function(typeId,model,scenario)
    local src=source
    if not rateLimit(src,'admin_set_npc',800) or not Admin.ValidateAdminAction(src,Constants.PERMISSIONS.MANAGE_LICENSES) then return end
    local ok,result=Admin.SaveNpcAtPlayer(src,typeId,model,scenario)
    if ok then auditAdmin(src,'npc_saved',{licenseTypeId=tonumber(typeId)}) end
    adminResult(src,'setNpc',ok,{message=ok and 'Instructor NPC saved at your position.' or tostring(result),tests=Admin.GetAllLicenseTypes()})
end)

RegisterNetEvent('cm-license:server:adminBeginBuilder', function(typeId)
    local src=source
    if not rateLimit(src,'admin_begin_builder',1000) or not Admin.ValidateAdminAction(src,Constants.PERMISSIONS.MANAGE_LICENSES) then return end
    local ok,result=Admin.BeginBuilder(src,typeId)
    adminResult(src,'beginBuilder',ok,type(result)=='table' and result or {message=tostring(result)})
end)

RegisterNetEvent('cm-license:server:adminBuilderAction', function(action)
    local src=source
    if not rateLimit(src,'admin_builder_action',250) or not Admin.ValidateAdminAction(src,Constants.PERMISSIONS.MANAGE_LICENSES) then return end
    action=tostring(action or '')
    if action~='save_spawn' and action~='add_point' and action~='undo' and action~='finish' then return end
    local ok,result=Admin.BuilderAction(src,action)
    if ok and type(result)=='table' and result.stage=='complete' then auditAdmin(src,'route_saved',{count=result.count}) end
    adminResult(src,'builderAction',ok,type(result)=='table' and result or {message=tostring(result)})
end)

RegisterNetEvent('cm-license:server:adminCancelBuilder', function()
    local src=source
    if not Admin.ValidateAdminAction(src,Constants.PERMISSIONS.MANAGE_LICENSES) then return end
    Admin.CancelBuilder(src)
    adminResult(src,'cancelBuilder',true,{message='Route builder cancelled.'})
end)

-- ============================================================================
-- PERIODIC CLEANUP
-- ============================================================================

-- Run cleanup every 5 minutes
local function PeriodicMaintenance()
    -- Cleanup expired test sessions
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
    while true do
        Wait(MaintenanceIntervalMinutes * 60 * 1000)
        PeriodicMaintenance()
    end
end)

-- ============================================================================
-- DEBUG COMMANDS (remove in production)
-- ============================================================================

if GetConvar('debug_licenses', 'false') == 'true' then
    RegisterCommand('lsinfo', function(source, args, rawCommand)
        local src = source
        local charId = exports['cm-playerdata']:GetCharacterId(src)
        
        if not charId then
            print('Character not loaded')
            return
        end
        
        local licenses = Licenses.GetLicenses(charId)
        print('^2[CM-License Debug]^7 Licenses for character ' .. charId)
        for _, lic in ipairs(licenses or {}) do
            print('  - ' .. lic.label .. ': ' .. lic.status .. ' (' .. lic.remainingDays .. ' days)')
        end
        
        local activeTest = Tests.GetActiveTest(charId)
        if activeTest then
            print('^3[CM-License Debug]^7 Active test: checkpoint ' .. activeTest.currentCheckpoint .. '/' .. activeTest.totalCheckpoints)
        else
            print('^3[CM-License Debug]^7 No active test')
        end
    end, false)
end

print('^2[CM-License]^7 Server module loaded')
