-- cm-billing client: NUI host for the player's own invoices. No authority lives here: the NUI can only ask the server to list
-- the caller's own invoices and to pay one of them from cash or bank.
local Config = CMBilling.Config

local isOpen, opening = false, false

local ENDPOINTS = { list = true, pay = true }

local function notify(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', message, kind or 'info')
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function closeBills()
    if not isOpen and not opening then
        SetNuiFocus(false, false)
        return
    end
    isOpen, opening = false, false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openBills()
    if isOpen or opening then return end
    opening = true
    local result = lib.callback.await('cm-billing:list', false)
    if not opening then return end
    if type(result) ~= 'table' or not result.ok then
        opening = false
        notify('Billing is not available right now.', 'error')
        return
    end
    isOpen, opening = true, false
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = result.data })
end

RegisterCommand(Config.OpenCommand, function()
    if isOpen then closeBills() else openBills() end
end, false)

RegisterNUICallback('close', function(_, cb)
    closeBills()
    cb({ ok = true })
end)

RegisterNUICallback('api', function(data, cb)
    data = type(data) == 'table' and data or {}
    local endpoint = tostring(data.endpoint or '')
    if not ENDPOINTS[endpoint] then
        cb({ ok = false, error = 'invalid_request' })
        return
    end
    local result = lib.callback.await('cm-billing:' .. endpoint, false, data.payload)
    if type(result) ~= 'table' then result = { ok = false, error = 'internal_error' } end
    cb(result)
end)

-- Server hint that the caller's invoice list changed (new invoice). Targeted, carries no data.
RegisterNetEvent('cm-billing:client:changed', function()
    if isOpen then SendNUIMessage({ action = 'changed' }) end
end)

-- Force-close paths: death, character unload, resource stop.
CreateThread(function()
    while true do
        if isOpen then
            if IsEntityDead(PlayerPedId()) then closeBills() end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

RegisterNetEvent('cm-playerdata:client:characterUnloaded', function() closeBills() end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
