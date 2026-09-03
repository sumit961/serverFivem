-- CM License System — NUI Callbacks

local Constants = require 'shared.constants'

local function closeMenu()
    SetNuiFocus(false, false)
end

-- Handle NUI callbacks from the license menu
RegisterNuiCallbackType('startTest')
on_startTest = function(data, cb)
    if data.licenseType then
        local charId = exports['cm-playerdata']:GetCharacterId()

        closeMenu()

        TriggerServerEvent(Constants.EVENTS.SERVER.REQUEST_START_TEST, {
            charId = charId,
            licenseType = data.licenseType
        })
    end
    cb('ok')
end

RegisterNuiCallbackType('cancelTest')
on_cancelTest = function(data, cb)
    closeMenu()
    TriggerServerEvent(Constants.EVENTS.SERVER.CANCEL_TEST)
    cb('ok')
end

RegisterNuiCallbackType('requestMyLicenses')
on_requestMyLicenses = function(data, cb)
    local charId = exports['cm-playerdata']:GetCharacterId()
    TriggerServerEvent('cm-license:server:requestMyLicenses', charId)
    cb('ok')
end

RegisterNuiCallbackType('closeMenu')
on_closeMenu = function(data, cb)
    closeMenu()
    cb('ok')
end

RegisterNuiCallbackType('getNPCLocations')
on_getNPCLocations = function(data, cb)
    local playerCoords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('cm-license:server:getNPCLocations', playerCoords)
    cb('ok')
end

RegisterNuiCallbackType('startAdminSetup')
on_startAdminSetup = function(data, cb)
    closeMenu()
    TriggerServerEvent('cm-license:server:startAdminSetup', data)
    cb('ok')
end

RegisterNuiCallbackType('editLicense')
on_editLicense = function(data, cb)
    closeMenu()
    TriggerServerEvent('cm-license:server:editLicense', data)
    cb('ok')
end

RegisterNuiCallbackType('previewRoute')
on_previewRoute = function(data, cb)
    closeMenu()
    TriggerServerEvent('cm-license:server:previewRoute', data)
    cb('ok')
end

RegisterNuiCallbackType('deleteLicense')
on_deleteLicense = function(data, cb)
    closeMenu()
    TriggerServerEvent('cm-license:server:deleteLicense', data)
    cb('ok')
end

-- Server event responses that populate NUI dialogs

-- Request License Menu
RegisterNetEvent('cm-license:client:showLicenseMenu', function(licenses)
    require 'client.npc'.ShowLicenseMenu(licenses)
end)

-- Request My Licenses
RegisterNetEvent('cm-license:client:showMyLicenses', function(licenses)
    require 'client.npc'.ShowMyLicenses(licenses)
end)

-- Test Result
RegisterNetEvent('cm-license:client:testResult', function(data)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'testResult',
        passed = data.passed,
        licenseLabel = data.licenseLabel,
        validDays = data.validDays,
        failReason = data.failReason,
        message = data.message
    }))
end)

-- Admin Menu
RegisterNetEvent('cm-license:client:openAdminMenu', function(licenses)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'openAdminMenu',
        licenses = licenses
    }))
end)

print('^2[CM-License]^7 NUI callbacks registered')
