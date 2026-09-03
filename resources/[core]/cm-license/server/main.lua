-- CM License System — Main Server Module

local Database = require 'server.database'
local Cache = require 'server.cache'
local Licenses = require 'server.licenses'
local Tests = require 'server.tests'
local Admin = require 'server.admin'
local Constants = require 'shared.constants'

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
end)

-- Character loaded event
AddEventHandler('cm-playerdata:client:characterLoaded', function()
    local src = source
    local charId = exports['cm-playerdata']:GetCharacterId(src)

    if charId then
        -- Check and cleanup expired licenses
        Licenses.CheckAndCleanupExpired(charId)
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
    local charId = exports['cm-playerdata']:GetCharacterId(src)

    if not charId or not licenseTypeId then
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'Error', 'Invalid test request' }
        })
        return
    end

    -- Start test
    local ok, result = Tests.StartTest(src, charId, licenseTypeId)

    if ok then
        -- Notify client
        TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_STARTED, src, result)
    else
        -- Notify client of failure
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'License System', 'Failed to start test: ' .. tostring(result) },
            color = { 255, 0, 0 }
        })
    end
end)

-- Checkpoint reached
RegisterNetEvent(Constants.EVENTS.SERVER.CHECKPOINT_REACHED, function(checkpointNumber)
    local src = source
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

    -- Update session
    Tests.ReportCheckpoint(charId, checkpointNumber)

    -- Notify client
    TriggerClientEvent(Constants.EVENTS.CLIENT.SET_CHECKPOINT, src, {
        currentCheckpoint = checkpointNumber,
        totalCheckpoints = session.totalCheckpoints
    })
end)

-- Finish test
RegisterNetEvent(Constants.EVENTS.SERVER.FINISH_TEST, function()
    local src = source
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
    local charId = exports['cm-playerdata']:GetCharacterId(src)

    if not charId then return end

    Tests.FailTest(charId, reason or 'unknown_failure')

    -- Notify client
    TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, src, {
        reason = reason,
        message = Constants.RESULT_MESSAGES[reason] or 'Test failed'
    })
end)

-- Request My Licenses
RegisterNetEvent('cm-license:server:requestMyLicenses', function(charId)
    local src = source
    local playerCharId = exports['cm-playerdata']:GetCharacterId(src)

    if playerCharId ~= charId then
        return  -- Security: player can only request their own licenses
    end

    local licenses = Licenses.GetLicenses(charId)

    TriggerClientEvent('cm-license:client:showMyLicenses', src, licenses or {})
end)

-- Get NPC Locations (player near NPC)
RegisterNetEvent('cm-license:server:getNPCLocations', function(playerCoords)
    local src = source

    -- Get all license types with NPC locations
    local licenseTypes = Cache.GetLicenseTypes()

    if licenseTypes then
        TriggerClientEvent('cm-license:client:showLicenseMenu', src, licenseTypes)
    end
end)

-- ============================================================================
-- ADMIN COMMANDS
-- ============================================================================

TriggerEvent('chat:addSuggestion', '/licensesetup', 'Open license test setup menu', {})

RegisterCommand('licensesetup', function(source, args, rawCommand)
    local src = source

    -- Check permission
    if not Admin.ValidateAdminAction(src, Constants.PERMISSIONS.MANAGE_LICENSES) then
        return
    end

    -- Open admin menu
    TriggerClientEvent('cm-license:client:openAdminMenu', src)
end, false)

-- ============================================================================
-- PERIODIC CLEANUP
-- ============================================================================

-- Run cleanup every 5 minutes
local function PeriodicMaintenance()
    -- Cleanup expired test sessions
    Tests.CleanupExpiredSessions()

    -- Could add periodic license expiration cleanup here if needed
end

SetInterval(function()
    PeriodicMaintenance()
end, 5 * 60 * 1000)  -- 5 minutes

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
