local isOpen = false

local function postUiMessage(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function releaseUi()
    isOpen = false
    SetNuiFocus(false, false)
    postUiMessage('close')
end

local function notify(message, kind)
    if lib and lib.notify then
        lib.notify({ description = message, type = kind or 'inform' })
    end
end

local function loadDashboard()
    local response = lib.callback.await('cm-citybulletin:server:getDashboard', false)
    if not response or response.ok ~= true then
        return nil, response and response.reason or 'bulletin_unavailable'
    end
    return response
end

local function openBulletin()
    if isOpen then return end
    local dashboard, reason = loadDashboard()
    if not dashboard then
        notify(reason == 'character_unavailable' and 'Your character is not ready.' or 'The city bulletin is unavailable.', 'error')
        return
    end
    isOpen = true
    SetNuiFocus(true, true)
    postUiMessage('open', dashboard)
end

RegisterCommand(Config.Commands.primary, openBulletin, false)
RegisterCommand(Config.Commands.alias, openBulletin, false)

RegisterNUICallback('close', function(_, cb)
    releaseUi()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    if not isOpen then cb({ ok = false, reason = 'closed' }); return end
    local dashboard, reason = loadDashboard()
    cb(dashboard or { ok = false, reason = reason })
end)

RegisterNUICallback('markRead', function(data, cb)
    if not isOpen or type(data) ~= 'table' then cb({ ok = false, reason = 'invalid_request' }); return end
    local response = lib.callback.await('cm-citybulletin:server:markRead', false, {
        noticeId = data.noticeId,
    })
    cb(response or { ok = false, reason = 'read_state_failed' })
end)

RegisterNUICallback('forceClose', function(_, cb)
    releaseUi()
    cb({ ok = true })
end)

RegisterNetEvent('cm-playerdata:client:characterUnloaded', releaseUi)
RegisterNetEvent('cm-playerdata:client:unloaded', releaseUi)
RegisterNetEvent('cm-playerdata:client:lifeStateChanged', function(state)
    state = tostring(state or ''):lower()
    if state == 'dead' or state == 'downed' then releaseUi() end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then releaseUi() end
end)
