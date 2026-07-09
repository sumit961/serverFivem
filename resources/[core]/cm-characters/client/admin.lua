-- cm-characters/client/admin.lua
-- NUI bridge for the character admin panel.


-- Production-safe local logger wrapper.
-- When Config.Debug/Config.VerboseLogs is false, normal CM-CHARACTERS debug prints are hidden.
-- Warnings/errors still print so real problems are visible.
local __cmCharactersPrint = print
local function __cmCharactersShouldVerbose()
    return Config and (Config.Debug == true or Config.VerboseLogs == true or Config.ProductionMode == false)
end
local function print(...)
    if __cmCharactersShouldVerbose() then
        return __cmCharactersPrint(...)
    end

    local first = tostring(select(1, ...) or '')
    local isCmCharactersLog = first:find('%[CM%-CHARACTERS') ~= nil
    if not isCmCharactersLog then
        return __cmCharactersPrint(...)
    end

    local upper = first:upper()
    if upper:find('ERROR', 1, true) or upper:find('WARNING', 1, true) or upper:find('FAILED', 1, true) or upper:find('DENIED', 1, true) then
        return __cmCharactersPrint(...)
    end
end

RegisterNetEvent('cm-characters:client:openAdmin', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openCharacterAdmin' })
end)

RegisterNetEvent('cm-characters:client:adminResults', function(results)
    SendNUIMessage({ action = 'characterAdminResults', results = results or {} })
end)

RegisterNetEvent('cm-characters:client:adminStatus', function(data)
    data = type(data) == 'table' and data or {}
    SendNUIMessage({ action = 'characterAdminStatus', ok = data.ok == true, message = data.message or '' })
end)

RegisterNUICallback('charAdminSearch', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-characters:server:adminSearch', data.query or '')
    cb({ ok = true })
end)

RegisterNUICallback('charAdminAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-characters:server:adminAction', data.actionName or '', data.payload or {})
    cb({ ok = true })
end)

RegisterNUICallback('charAdminClose', function(data, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterCommand('charadmin', function()
    TriggerServerEvent('cm-characters:server:requestOpenAdmin')
end, false)
