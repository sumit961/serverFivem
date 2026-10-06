-- cm-trade/client/client.lua
-- Presentation only. The server owns sessions, offers, confirmations and settlement; the client relays requests.

local uiOpen = false
local currentId = nil
local PAGE = 'cm_trade'

local function hideWorldPrompt()
    if GetResourceState('cm-ui') == 'started' then pcall(function() exports['cm-ui']:HideInteract() end) end
end

local function show()
    if uiOpen then return end
    uiOpen = true
    hideWorldPrompt()
    SetNuiFocus(true, true)
end

local function hide()
    if not uiOpen then return end
    uiOpen = false
    currentId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

RegisterNetEvent('cm-trade:client:invite', function(invite)
    if type(invite) ~= 'table' or uiOpen then
        if type(invite) == 'table' then TriggerServerEvent('cm-trade:server:respond', invite.id, false) end
        return
    end
    show()
    SendNUIMessage({ type = 'invite', invite = { id = invite.id, from = invite.from, expiresIn = invite.expiresIn } })
end)

RegisterNetEvent('cm-trade:client:open', function(view)
    if type(view) ~= 'table' then return end
    show()
    currentId = view.id
    SendNUIMessage({ type = 'open', view = view })
    TriggerServerEvent('cm-trade:server:inventory', view.id)
end)

RegisterNetEvent('cm-trade:client:state', function(view)
    if uiOpen and type(view) == 'table' and view.id == currentId then SendNUIMessage({ type = 'state', view = view }) end
end)

RegisterNetEvent('cm-trade:client:inventory', function(list)
    if uiOpen then SendNUIMessage({ type = 'inventory', list = list }) end
end)

RegisterNetEvent('cm-trade:client:result', function(res)
    if uiOpen then SendNUIMessage({ type = 'result', result = res }) end
end)

RegisterNetEvent('cm-trade:client:ended', function(info)
    if type(info) ~= 'table' then return end
    if not uiOpen then return end
    SendNUIMessage({ type = 'ended', info = info })
    SetTimeout(2200, function() hide() end)
end)

RegisterNUICallback('respond', function(body, cb)
    if type(body) == 'table' and type(body.id) == 'string' then
        TriggerServerEvent('cm-trade:server:respond', body.id, body.accept == true)
        if body.accept ~= true then hide() end
    end
    cb('ok')
end)

RegisterNUICallback('offer', function(body, cb)
    if uiOpen and currentId and type(body) == 'table' and type(body.op) == 'string' then
        TriggerServerEvent('cm-trade:server:offer', currentId, body.op, body.a, body.b)
    end
    cb('ok')
end)

RegisterNUICallback('confirm', function(body, cb)
    if uiOpen and currentId and type(body) == 'table' then TriggerServerEvent('cm-trade:server:confirm', currentId, tonumber(body.rev)) end
    cb('ok')
end)

RegisterNUICallback('cancel', function(_, cb)
    if currentId then TriggerServerEvent('cm-trade:server:cancel', currentId) end
    cb('ok')
end)

-- ESC while the server is settling must not drop focus handling: the server decides, the UI waits for 'ended'.
RegisterNUICallback('close', function(_, cb)
    if currentId then TriggerServerEvent('cm-trade:server:cancel', currentId) else hide() end
    cb('ok')
end)

RegisterNUICallback('forceClose', function(_, cb)
    hide()
    cb('ok')
end)

-- ---- G menu registration (cm-playerdata public extension contract) ----------------------------------------------
local function registerMenu()
    if GetResourceState('cm-playerdata') ~= 'started' then return end
    pcall(function()
        exports['cm-playerdata']:RegisterInteractionPage({ id = PAGE, label = 'Trade', icon = 'handshake', order = 45, emptyLabel = 'No trade actions' })
        exports['cm-playerdata']:RegisterInteractionOption(PAGE, { id = 'trade_invite', action = 'trade_invite', label = 'Offer a Trade', icon = 'handshake', type = 'extension', order = 10, close = true })
    end)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'cm-playerdata' then SetTimeout(1000, registerMenu) end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
