local PLAYERDATA = 'cm-playerdata'
local PAGE = 'gang'
local targetGeneration = 0
local pendingGangInvite

local function playerDataStarted()
    return GetResourceState(PLAYERDATA) == 'started'
end

local function registerPage()
    if not playerDataStarted() then return end
    pcall(function()
        exports[PLAYERDATA]:RegisterInteractionPage({
            id = PAGE,
            label = 'Gang',
            icon = 'people-group',
            order = 36,
            emptyLabel = 'No gang actions available',
        })
    end)
end

local function clearOptions()
    if not playerDataStarted() then return end
    pcall(function() exports[PLAYERDATA]:ClearInteractionOptions(PAGE) end)
end

local function addInviteOption()
    if not playerDataStarted() then return end
    pcall(function()
        exports[PLAYERDATA]:RegisterInteractionOption(PAGE, {
            id = 'gang_invite',
            action = 'gang_invite',
            label = 'Invite to Gang',
            icon = 'user-plus',
            type = 'extension',
            order = 10,
            close = true,
        })
    end)
end

local function rebuild(targetServerId)
    targetGeneration = targetGeneration + 1
    local generation = targetGeneration
    clearOptions()
    targetServerId = tonumber(targetServerId)
    if not targetServerId or type(lib) ~= 'table' or type(lib.callback) ~= 'table' then return end
    CreateThread(function()
        local options = lib.callback.await('cm-gang:server:getTargetActions', false, targetServerId)
        if generation ~= targetGeneration or type(options) ~= 'table' then return end
        if options.invite == true then addInviteOption() end
        TriggerEvent('cm-playerdata:client:refreshInteractionMenu')
    end)
end

RegisterNetEvent('cm-gang:client:notify', function(message, kind)
    if type(lib) == 'table' and type(lib.notify) == 'function' then
        lib.notify({ description = tostring(message or 'Gang action failed.'), type = kind or 'inform' })
    end
end)

RegisterNetEvent('cm-gang:client:inviteReceived', function(invite)
    if type(invite) ~= 'table' or type(invite.inviteId) ~= 'string' then return end
    pendingGangInvite = {
        inviteId = invite.inviteId,
        expiresAt = GetGameTimer() + (math.max(1, tonumber(invite.expiresIn) or 60) * 1000),
    }
    lib.notify({
        title = 'Gang Invitation',
        description = ('%s invited you to join %s. Press Y to accept or N to decline.'):format(
            tostring(invite.invitedBy or 'A gang member'), tostring(invite.gangName or 'a gang')),
        type = 'inform', duration = 10000,
    })
end)

local function respondToGangInvite(accept)
    local invite = pendingGangInvite
    if not invite then return end
    pendingGangInvite = nil
    if invite.expiresAt <= GetGameTimer() then
        return lib.notify({ description = 'That gang invitation has expired.', type = 'error' })
    end
    TriggerServerEvent('cm-gang:server:respondInvite', { inviteId = invite.inviteId, accept = accept == true })
end

RegisterCommand('+cm_gang_accept_invite', function() respondToGangInvite(true) end, false)
RegisterCommand('-cm_gang_accept_invite', function() end, false)
RegisterKeyMapping('+cm_gang_accept_invite', 'Accept gang invitation', 'keyboard', 'Y')
RegisterCommand('+cm_gang_decline_invite', function() respondToGangInvite(false) end, false)
RegisterCommand('-cm_gang_decline_invite', function() end, false)
RegisterKeyMapping('+cm_gang_decline_invite', 'Decline gang invitation', 'keyboard', 'N')

RegisterNetEvent('cm-playerdata:client:interactionTargetChanged', rebuild)
AddEventHandler('cm-playerdata:client:interactionRegistryReady', function()
    registerPage()
    rebuild(nil)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= PLAYERDATA and resourceName ~= GetCurrentResourceName() then return end
    Wait(300)
    registerPage()
    clearOptions()
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    pendingGangInvite = nil
    targetGeneration = targetGeneration + 1
    clearOptions()
end)
