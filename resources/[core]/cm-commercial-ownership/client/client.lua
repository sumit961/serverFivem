-- cm-commercial-ownership/client/client.lua
-- Shared staff-panel NUI host. All authority lives on the server; this file only relays.

local isOpen = false
local inviteOpen = false

local function hideWorldPrompt()
    if GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract() end)
    end
end

local function closeUi(notifyServer)
    if not isOpen and not inviteOpen then return end
    local wasPanel = isOpen
    isOpen, inviteOpen = false, false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
    if notifyServer and wasPanel then TriggerServerEvent('cm-commercial-ownership:server:close') end
end

-- Shared entry point for business resources: server validates ownership/permission before anything opens.
exports('OpenStaffPanel', function(businessType, businessId)
    if isOpen or inviteOpen then return false end
    TriggerServerEvent('cm-commercial-ownership:server:open', tostring(businessType or ''), tostring(businessId or ''))
    return true
end)

RegisterCommand('businessstaff', function(_, args)
    if args[1] and args[2] then
        exports['cm-commercial-ownership']:OpenStaffPanel(args[1], args[2])
    end
end, false)

RegisterNetEvent('cm-commercial-ownership:client:state', function(mode, data)
    if mode == 'open' then
        if inviteOpen then return end
        isOpen = true
        hideWorldPrompt()
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'open', data = data })
    elseif isOpen then
        SendNUIMessage({ type = 'update', data = data })
    end
end)

RegisterNetEvent('cm-commercial-ownership:client:candidates', function(list)
    if isOpen then SendNUIMessage({ type = 'candidates', list = list }) end
end)

RegisterNetEvent('cm-commercial-ownership:client:supply', function(kind, payload)
    if isOpen and type(kind) == 'string' then SendNUIMessage({ type = 'supply', kind = kind, payload = payload }) end
end)

RegisterNetEvent('cm-commercial-ownership:client:result', function(res)
    if isOpen then SendNUIMessage({ type = 'result', result = res }) end
end)

RegisterNetEvent('cm-commercial-ownership:client:close', function() closeUi(false) end)

RegisterNetEvent('cm-commercial-ownership:client:invite', function(invite)
    if inviteOpen or type(invite) ~= 'table' then return end
    inviteOpen = true
    hideWorldPrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'invite', invite = { token = invite.token, label = invite.label, rankName = invite.rankName, expiresIn = invite.expiresIn } })
end)

RegisterNUICallback('close', function(_, cb)
    closeUi(true)
    cb('ok')
end)

RegisterNUICallback('request', function(body, cb)
    if isOpen and type(body) == 'table' and type(body.action) == 'string' then
        TriggerServerEvent('cm-commercial-ownership:server:request', body.action, type(body.payload) == 'table' and body.payload or {})
    end
    cb('ok')
end)

RegisterNUICallback('respondInvite', function(body, cb)
    if inviteOpen and type(body) == 'table' and type(body.token) == 'string' then
        TriggerServerEvent('cm-commercial-ownership:server:respondInvite', body.token, body.accept == true)
        closeUi(false)
    end
    cb('ok')
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
