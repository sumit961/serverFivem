-- Separate RP-radio and non-RP text channels for every legal organization.
-- cm-chat remains the sender/logger; cm-law remains membership authority.

local Registered = false

local function registerChannels()
    if GetResourceState('cm-chat') ~= 'started' then return false end
    local organizations = exports[GetCurrentResourceName()]:GetOrganizations()
    for _, org in ipairs(organizations or {}) do
        exports['cm-chat']:RegisterChatChannel(org.radioChannel, org.shortLabel .. ' RP RADIO', {
            type = 'group', group = 'legal_' .. org.id .. '_radio', color = '#31e6ff', format = 'group', appendOrder = true,
        })
        exports['cm-chat']:RegisterChatChannel(org.chatChannel, org.shortLabel .. ' NON-RP', {
            type = 'group', group = 'legal_' .. org.id .. '_chat', color = '#9bb8c8', format = 'group', appendOrder = true,
        })
    end
    for _, src in ipairs(GetPlayers()) do TriggerEvent('cm-chat:server:refreshPlayerChannels', tonumber(src)) end
    Registered = true
    return true
end

local function send(src, channelId, message)
    src = tonumber(src)
    if not src or src <= 0 then return end
    if GetResourceState('cm-chat') ~= 'started' or (not Registered and not registerChannels()) then
        return TriggerClientEvent('cm-hud:client:notify', src, 'Organization chat is unavailable.', 'error')
    end
    local accepted = exports['cm-chat']:SendPlayerChatMessage(src, channelId, table.concat(message or {}, ' '), 'group')
    if accepted ~= true then TriggerClientEvent('cm-hud:client:notify', src, 'Organization chat channel is unavailable.', 'error') end
end

for orgId, org in pairs(Config.Organizations) do
    local radioChannel, chatChannel = org.radioChannel, org.chatChannel
    RegisterCommand(orgId .. 'rp', function(src, args) send(src, radioChannel, args) end, false)
    RegisterCommand(orgId .. 'nrp', function(src, args) send(src, chatChannel, args) end, false)
end

RegisterCommand('lawrp', function(src, args)
    local member = select(1, activeMemberForSource(src))
    local org = member and Config.Organizations[member.organizationId]
    if not org then return TriggerClientEvent('cm-hud:client:notify', src, 'You are not in a legal organization.', 'error') end
    send(src, org.radioChannel, args)
end, false)

RegisterCommand('lawnrp', function(src, args)
    local member = select(1, activeMemberForSource(src))
    local org = member and Config.Organizations[member.organizationId]
    if not org then return TriggerClientEvent('cm-hud:client:notify', src, 'You are not in a legal organization.', 'error') end
    send(src, org.chatChannel, args)
end, false)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'cm-chat' and resource ~= GetCurrentResourceName() then return end
    if resource == 'cm-chat' then Registered = false end
    CreateThread(function()
        local deadline = GetGameTimer() + 10000
        while not LawIsReady() and GetGameTimer() < deadline do Wait(100) end
        Wait(250)
        registerChannels()
    end)
end)
