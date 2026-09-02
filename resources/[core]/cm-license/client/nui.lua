-- CM License System — NUI Callbacks

local function closeMenu()
    NPC.CloseMenu()
end

-- Handle NUI callbacks from the license menu
RegisterNUICallback('startTest', function(data, cb)
    if data.licenseType then
        closeMenu()
        TriggerServerEvent(Constants.EVENTS.SERVER.REQUEST_START_TEST, data.licenseType)
    end
    cb('ok')
end)

RegisterNUICallback('cancelTest', function(_, cb)
    closeMenu()
    TriggerServerEvent(Constants.EVENTS.SERVER.CANCEL_TEST)
    cb('ok')
end)

RegisterNUICallback('requestMyLicenses', function(_, cb)
    TriggerServerEvent('cm-license:server:requestMyLicenses')
    cb('ok')
end)

RegisterNUICallback('closeMenu', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('getNPCLocations', function(_, cb)
    TriggerServerEvent('cm-license:server:getNPCLocations')
    cb('ok')
end)

RegisterNUICallback('adminSaveType', function(data, cb)
    TriggerServerEvent('cm-license:server:adminSaveType', data)
    cb('ok')
end)

RegisterNUICallback('adminDeleteType', function(data, cb)
    TriggerServerEvent('cm-license:server:adminDeleteType', tonumber(data.id))
    cb('ok')
end)

RegisterNUICallback('adminSetNpc', function(data, cb)
    TriggerServerEvent('cm-license:server:adminSetNpc', data)
    cb('ok')
end)

RegisterNUICallback('adminBeginBuilder', function(data, cb)
    closeMenu()
    TriggerServerEvent('cm-license:server:adminBeginBuilder', tonumber(data.id))
    cb('ok')
end)

-- Server event responses that populate NUI dialogs

-- Request License Menu
RegisterNetEvent('cm-license:client:showLicenseMenu', function(licenses)
    NPC.ShowLicenseMenu(licenses)
end)

-- Request My Licenses
RegisterNetEvent('cm-license:client:showMyLicenses', function(licenses)
    NPC.ShowMyLicenses(licenses)
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
    AdminClient.OpenMenu(licenses)
end)

print('^2[CM-License]^7 NUI callbacks registered')
