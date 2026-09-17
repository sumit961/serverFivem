local PLAYERDATA = 'cm-playerdata'
local PAGE = 'gang'
local targetGeneration = 0
local pendingGangInvite
local gangSearchOpen = false
local GANG_SEARCH_UI_REASON = 'cm-gang-search'

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

local function addRobCashOption()
    if not playerDataStarted() then return end
    pcall(function()
        exports[PLAYERDATA]:RegisterInteractionOption(PAGE, {
            id = 'gang_rob_cash', action = 'gang_rob_cash', label = 'Steal Cash (10%)', icon = 'cash',
            type = 'extension', order = 30, close = true, allowDeadTarget = true,
        })
    end)
end

local function addRobberyOption(id, action, label, icon, order)
    if not playerDataStarted() then return end
    pcall(function() exports[PLAYERDATA]:RegisterInteractionOption(PAGE, {
        id = id, action = action, label = label, icon = icon, type = 'extension', order = order,
        close = true, allowDeadTarget = true,
    }) end)
end

local function addStatusOption(label)
    if not playerDataStarted() then return end
    pcall(function() exports[PLAYERDATA]:RegisterInteractionOption(PAGE, {
        id = 'gang_action_status', action = 'gang_action_status', label = label, icon = 'circle-info',
        type = 'noop', order = 800, close = false,
    }) end)
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
        if options.search == true then addRobberyOption('gang_search', 'gang_search', 'Search Player', 'magnifying-glass', 20) end
        if options.robCash == true then addRobCashOption() end
        if options.robItems == true then addRobberyOption('gang_rob_items', 'gang_rob_items', 'Steal Item (Lottery)', 'hand', 40) end
        if options.gangMember == true and options.invite ~= true and options.search ~= true and options.robCash ~= true and options.robItems ~= true then
            addStatusOption('Your gang rank has no player robbery permissions')
        end
        TriggerEvent('cm-playerdata:client:refreshInteractionMenu')
    end)
end

RegisterNetEvent('cm-gang:client:requestRobCash', function(targetServerId)
    TriggerServerEvent('cm-gang:server:robCash', { target = targetServerId })
end)

RegisterNetEvent('cm-gang:client:requestRandomItemRobbery', function(targetServerId)
    TriggerServerEvent('cm-gang:server:robRandomItem', { target = targetServerId })
end)

RegisterNetEvent('cm-gang:client:requestRobberyInventory', function(targetServerId, mode)
    CreateThread(function()
        local response = lib.callback.await('cm-gang:server:getRobberyInventory', false, tonumber(targetServerId), 'search')
        if type(response) ~= 'table' or response.ok ~= true then
            return lib.notify({ description = 'The inventory could not be searched.', type = 'error' })
        end
        gangSearchOpen = true
        SetNuiFocus(true, true)
        TriggerEvent('cm-hud:client:hideForUi', GANG_SEARCH_UI_REASON)
        TriggerEvent('cm-chat:client:hideForUi', GANG_SEARCH_UI_REASON)
        SendNUIMessage({ action = 'gangSearchOpen', items = response.items or {} })
    end)
end)

RegisterNUICallback('closeGangSearch', function(_, cb)
    gangSearchOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'gangSearchClose' })
    TriggerEvent('cm-hud:client:showAfterUi', GANG_SEARCH_UI_REASON)
    TriggerEvent('cm-chat:client:showAfterUi', GANG_SEARCH_UI_REASON)
    cb({ ok = true })
end)

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
    if gangSearchOpen then
        gangSearchOpen = false
        TriggerEvent('cm-hud:client:showAfterUi', GANG_SEARCH_UI_REASON)
        TriggerEvent('cm-chat:client:showAfterUi', GANG_SEARCH_UI_REASON)
    end
    clearOptions()
end)
