local PLAYERDATA = 'cm-playerdata'
local PAGE = 'clubs'
local dashboardOpen = false
local targetGeneration = 0

local function notify(message, kind)
    if type(lib) == 'table' and type(lib.notify) == 'function' then
        lib.notify({ title = 'Social Clubs', description = tostring(message or 'Club action unavailable.'), type = kind or 'inform' })
    end
end

RegisterNetEvent('cm-clubs:client:notify', function(message, kind) notify(message, kind) end)

local function registerPage()
    if GetResourceState(PLAYERDATA) ~= 'started' then return end
    pcall(function()
        exports[PLAYERDATA]:RegisterInteractionPage({
            id = PAGE,
            label = 'Social Club',
            icon = 'users',
            order = 37,
            emptyLabel = 'No club actions available',
        })
    end)
end

local function clearOptions()
    if GetResourceState(PLAYERDATA) ~= 'started' then return end
    pcall(function() exports[PLAYERDATA]:ClearInteractionOptions(PAGE) end)
end

local function rebuildTarget(targetServerId)
    targetGeneration = targetGeneration + 1
    local generation = targetGeneration
    clearOptions()
    targetServerId = tonumber(targetServerId)
    if not targetServerId or type(lib) ~= 'table' or type(lib.callback) ~= 'table' then return end
    CreateThread(function()
        local actions = lib.callback.await('cm-clubs:server:getTargetActions', false, targetServerId)
        if generation ~= targetGeneration or type(actions) ~= 'table' or actions.invite ~= true then return end
        pcall(function()
            exports[PLAYERDATA]:RegisterInteractionOption(PAGE, {
                id = 'club_invite',
                action = 'club_invite',
                label = 'Invite to Club',
                description = 'Send a one-use club invitation',
                icon = 'user-plus',
                type = 'extension',
                order = 10,
                close = true,
            })
        end)
        TriggerEvent('cm-playerdata:client:refreshInteractionMenu')
    end)
end

local function closeDashboard()
    if not dashboardOpen then return end
    dashboardOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerEvent('cm-clubs:client:dashboardState', false)
end

local function openDashboard()
    if dashboardOpen then return end
    local response = lib.callback.await('cm-clubs:server:getDashboard', false)
    if not response or response.ok ~= true then
        return notify((response and response.reason or 'not_in_club'):gsub('_', ' '), 'error')
    end
    dashboardOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = response })
    TriggerEvent('cm-clubs:client:dashboardState', true)
end

RegisterCommand('club', openDashboard, false)
RegisterNetEvent('cm-clubs:client:openDashboard', openDashboard)
RegisterNetEvent('cm-clubs:client:closeDashboard', closeDashboard)

RegisterNetEvent('cm-clubs:client:invitePrompt', function(invite)
    if type(invite) ~= 'table' or not invite.inviteId then return end
    local confirmed = false
    if GetResourceState('cm-ui') == 'started' then
        local ok, value = pcall(function()
            return exports['cm-ui']:Confirm({
                title = ('Join %s [%s]'):format(tostring(invite.clubName or 'Social Club'), tostring(invite.clubTag or 'CLUB')),
                message = ('%s invited you. This invitation expires in %ss.'):format(tostring(invite.inviter or 'A member'), tostring(invite.expires or 90)),
                confirmText = 'ACCEPT',
                cancelText = 'DECLINE',
            })
        end)
        confirmed = ok and value == true
    end
    TriggerServerEvent('cm-clubs:server:respondInvite', tostring(invite.inviteId), confirmed)
end)

RegisterNUICallback('close', function(_, cb) closeDashboard(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb)
    local response = lib.callback.await('cm-clubs:server:getDashboard', false)
    if response and response.ok then SendNUIMessage({ action = 'data', data = response }) end
    cb(response or { ok = false, reason = 'request_failed' })
end)
RegisterNUICallback('leave', function(_, cb)
    local response = lib.callback.await('cm-clubs:server:leave', false) or { ok = false, reason = 'request_failed' }
    if response.ok then closeDashboard() else notify((response.reason or 'leave_failed'):gsub('_', ' '), 'error') end
    cb(response)
end)
RegisterNUICallback('memberAction', function(data, cb)
    local response = lib.callback.await('cm-clubs:server:memberAction', false, data or {}) or { ok = false, reason = 'request_failed' }
    if response.ok then
        local fresh = lib.callback.await('cm-clubs:server:getDashboard', false)
        if fresh and fresh.ok then SendNUIMessage({ action = 'data', data = fresh }) end
    else
        notify((response.reason or 'member_update_failed'):gsub('_', ' '), 'error')
    end
    cb(response)
end)

AddEventHandler('cm-playerdata:client:interactionTargetChanged', rebuildTarget)
AddEventHandler('cm-playerdata:client:characterUnloaded', function() closeDashboard(); clearOptions() end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeDashboard(); clearOptions() end
end)

CreateThread(function()
    Wait(500)
    registerPage()
end)

CreateThread(function()
    while true do
        if dashboardOpen and (IsEntityDead(PlayerPedId()) or IsPauseMenuActive()) then closeDashboard() end
        Wait(dashboardOpen and 500 or 1500)
    end
end)
