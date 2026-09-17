-- CM License System — NUI Callbacks

local function closeMenu()
    NPC.CloseMenu()
end

RegisterNUICallback('startTest', function(data, cb)
    if data and data.licenseType then
        closeMenu()
        TriggerServerEvent(Constants.EVENTS.SERVER.REQUEST_START_TEST, data.licenseType)
    end
    cb('ok')
end)

RegisterNUICallback('cancelTest', function(_, cb)
    closeMenu()
    if Client.IsInTest() then
        TriggerServerEvent(Constants.EVENTS.SERVER.CANCEL_TEST)
    end
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

-- ============================================================================
-- ADMIN CALLBACKS
-- ============================================================================

RegisterNUICallback('adminSaveType', function(data, cb)
    TriggerServerEvent('cm-license:server:adminSaveType', data)
    cb('ok')
end)

RegisterNUICallback('adminDeleteType', function(data, cb)
    TriggerServerEvent('cm-license:server:adminDeleteType', tonumber(data and data.id))
    cb('ok')
end)

RegisterNUICallback('adminSetNpc', function(data, cb)
    -- Sent as one payload; the server accepts both shapes.
    TriggerServerEvent('cm-license:server:adminSetNpc', data)
    cb('ok')
end)

RegisterNUICallback('adminBeginBuilder', function(data, cb)
    closeMenu()
    TriggerServerEvent('cm-license:server:adminBeginBuilder', {
        id = tonumber(data and data.id),
        routeId = tonumber(data and data.routeId),
    })
    cb('ok')
end)

RegisterNUICallback('adminListRoutes', function(data, cb)
    TriggerServerEvent('cm-license:server:adminListRoutes', tonumber(data and data.id))
    cb('ok')
end)

RegisterNUICallback('adminDeleteRoute', function(data, cb)
    TriggerServerEvent('cm-license:server:adminDeleteRoute', { routeId = tonumber(data and data.routeId) })
    cb('ok')
end)

RegisterNUICallback('adminToggleRoute', function(data, cb)
    TriggerServerEvent('cm-license:server:adminToggleRoute', {
        routeId = tonumber(data and data.routeId),
        enabled = data and data.enabled == true,
    })
    cb('ok')
end)

-- ============================================================================
-- SERVER EVENTS THAT POPULATE NUI DIALOGS
-- ============================================================================

RegisterNetEvent('cm-license:client:showLicenseMenu', function(licenses)
    NPC.ShowLicenseMenu(licenses)
end)

RegisterNetEvent('cm-license:client:showMyLicenses', function(licenses)
    NPC.ShowMyLicenses(licenses)
end)

-- Pass/fail screen. It gets a mouse cursor so the Close button works, but with
-- KeepInput set the player still controls their character and vehicle — the
-- result can appear mid-drive after a failure.
local resultFocusToken = 0

local function releaseResultFocus(token)
    if token and token ~= resultFocusToken then return end
    resultFocusToken = resultFocusToken + 1
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

RegisterNUICallback('closeResult', function(_, cb)
    releaseResultFocus(nil)
    cb('ok')
end)

RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_RESULT, function(data)
    data = type(data) == 'table' and data or {}

    SendNuiMessage(json.encode({
        type = 'testResult',
        passed = data.passed and true or false,
        licenseLabel = data.licenseLabel,
        licenseType = data.licenseType,
        category = data.category,
        validDays = data.validDays,
        failReason = data.failReason,
        message = data.message,
    }))

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    PlaySoundFrontend(-1, data.passed and 'RACE_PLACED' or 'CHECKPOINT_MISSED', 'HUD_AWARDS', true)

    -- Released automatically if the player never clicks Close.
    resultFocusToken = resultFocusToken + 1
    local token = resultFocusToken
    CreateThread(function()
        Wait(15000)
        releaseResultFocus(token)
    end)
end)

RegisterNetEvent('cm-license:client:openAdminMenu', function(licenses)
    AdminClient.OpenMenu(licenses)
end)

CMLog('NUI callbacks registered')
