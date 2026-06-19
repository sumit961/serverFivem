-- cm-hud/server/main.lua

local ChatChannels = {
    rp = { id = 'rp', label = 'RP', radius = 20.0 },      -- local proximity chat
    nonrp = { id = 'nonrp', label = 'NON-RP', radius = nil } -- global OOC/non-RP chat
}
local ChatChannelOrder = { 'rp', 'nonrp' }
local LastChatAt = {}
local CHAT_COOLDOWN_MS = 500
local DEFAULT_RADIUS = nil

local function trimText(value)
    value = tostring(value or '')
    value = value:gsub('[\r\n\t]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, 180)
end

local function getNowMs()
    return math.floor(os.clock() * 1000)
end

local function getChannelList()
    local list = {}
    local added = {}
    for _, id in ipairs(ChatChannelOrder) do
        local ch = ChatChannels[id]
        if ch then
            list[#list + 1] = { id = ch.id, label = ch.label }
            added[id] = true
        end
    end
    for id, ch in pairs(ChatChannels) do
        if not added[id] then
            list[#list + 1] = { id = ch.id, label = ch.label }
        end
    end
    return list
end

local function registerChannel(id, label, options)
    id = tostring(id or ''):lower():gsub('%s+', '')
    if id == '' then return false end

    options = options or {}
    if not ChatChannels[id] then
        ChatChannelOrder[#ChatChannelOrder + 1] = id
    end

    ChatChannels[id] = {
        id = id,
        label = tostring(label or id:upper()),
        radius = options.radius or DEFAULT_RADIUS
    }

    TriggerClientEvent('cm-hud:client:setChatChannels', -1, getChannelList())
    return true
end

exports('RegisterChatChannel', registerChannel)

local function sendPayloadToTarget(target, payload)
    if type(target) == 'table' then
        for _, playerId in ipairs(target) do
            TriggerClientEvent('cm-hud:client:addChatMessage', tonumber(playerId), payload)
        end
    elseif target then
        TriggerClientEvent('cm-hud:client:addChatMessage', target, payload)
    else
        TriggerClientEvent('cm-hud:client:addChatMessage', -1, payload)
    end
end

local function sendProximityPayload(sourceId, radius, payload)
    local srcPed = GetPlayerPed(sourceId)
    if not srcPed or srcPed == 0 then return end

    local srcCoords = GetEntityCoords(srcPed)
    radius = tonumber(radius) or 20.0

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local ped = GetPlayerPed(target)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            if #(srcCoords - coords) <= radius then
                TriggerClientEvent('cm-hud:client:addChatMessage', target, payload)
            end
        end
    end
end

local function broadcastChatMessage(channel, authorName, authorId, text, target)
    channel = tostring(channel or 'rp'):lower()
    if not ChatChannels[channel] then
        -- Auto-register unknown channels so future family/gang/admin modules can use
        -- this chat without editing the HUD UI files again. By default dynamic channels
        -- are global; pass a target list or register the channel with { radius = 20.0 }
        -- if you want restricted delivery.
        registerChannel(channel, channel:upper())
    end

    local ch = ChatChannels[channel]
    text = trimText(text)
    if text == '' then return end

    local payload = {
        channel = ch.id,
        channelLabel = ch.label,
        author = tostring(authorName or 'Unknown'),
        id = tonumber(authorId) or 0,
        text = text,
        time = os.date('%H:%M')
    }

    if target ~= nil then
        sendPayloadToTarget(target, payload)
    elseif ch.radius then
        sendProximityPayload(tonumber(authorId) or 0, ch.radius, payload)
    else
        sendPayloadToTarget(-1, payload)
    end
end

exports('BroadcastChatMessage', broadcastChatMessage)

RegisterNetEvent('cm-hud:server:requestChatChannels', function()
    TriggerClientEvent('cm-hud:client:setChatChannels', source, getChannelList())
end)

RegisterNetEvent('cm-hud:server:sendChatMessage', function(channel, text)
    local src = source
    local now = getNowMs()
    local last = LastChatAt[src] or 0
    if now - last < CHAT_COOLDOWN_MS then return end
    LastChatAt[src] = now

    text = trimText(text)
    if text == '' then return end

    local name = GetPlayerName(src) or 'Unknown'
    broadcastChatMessage(channel, name, src, text, nil)
end)

AddEventHandler('playerDropped', function()
    LastChatAt[source] = nil
end)

-- Optional server-side event for other scripts.
-- Examples:
-- TriggerEvent('cm-hud:server:broadcastChatMessage', 'family', 'Sumit Yadav', 1, 'hello', {1, 2, 3})
-- exports['cm-hud']:RegisterChatChannel('family', 'FAMILY')
-- exports['cm-hud']:RegisterChatChannel('localadmin', 'ADMIN', { radius = 20.0 })
RegisterNetEvent('cm-hud:server:broadcastChatMessage', function(channel, authorName, authorId, text, target)
    broadcastChatMessage(channel, authorName, authorId, text, target)
end)
