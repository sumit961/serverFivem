-- cm-hud/server/main.lua

local ChatChannels = {
    rp = { id = 'rp', label = 'RP', radius = 20.0 },      -- local proximity chat
    nonrp = { id = 'nonrp', label = 'NON-RP', radius = nil } -- global OOC/non-RP chat
}
local ChatChannelOrder = { 'rp', 'nonrp' }
local LastChatAt = {}
local CHAT_COOLDOWN_MS = 500
local DEFAULT_RADIUS = nil
local ActiveHudCharacters = {}
local LastHudPayload = {}
local dbFetchOne
local cleanCharacterId


local function trimText(value)
    value = tostring(value or '')
    value = value:gsub('[\r\n\t]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, 180)
end

local function getNowMs()
    return GetGameTimer and GetGameTimer() or math.floor(os.clock() * 1000)
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
    sourceId = tonumber(sourceId)
    if not sourceId or sourceId <= 0 then return end
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

local function broadcastChatMessage(channel, authorName, authorId, text, target, sourcePlayer)
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
        sendProximityPayload(tonumber(sourcePlayer) or 0, ch.radius, payload)
    else
        sendPayloadToTarget(-1, payload)
    end
end

exports('BroadcastChatMessage', broadcastChatMessage)

RegisterNetEvent('cm-hud:server:requestChatChannels', function()
    TriggerClientEvent('cm-hud:client:setChatChannels', source, getChannelList())
end)


local function getActiveCharacterName(src)
    local active = ActiveHudCharacters[src]
    if type(active) == 'table' then return active.name, active.id end
    return nil, cleanCharacterId(active)
end

RegisterNetEvent('cm-hud:server:sendChatMessage', function(channel, text)
    local src = source
    local now = getNowMs()
    local last = LastChatAt[src] or 0
    if now - last < CHAT_COOLDOWN_MS then return end
    LastChatAt[src] = now

    text = trimText(text)
    if text == '' then return end

    local dbName, dbCharId = getActiveCharacterName(src)
    if dbName and dbCharId then
        broadcastChatMessage(channel, dbName, dbCharId, text, nil, src)
        return
    end

    -- If chat is used before HUD sync finishes, refresh once and send with DB character name/id.
    local active = ActiveHudCharacters[src]
    local activeId = type(active) == 'table' and active.id or active
    if activeId then
        dbFetchOne('SELECT id, first_name, last_name FROM characters WHERE id = ? LIMIT 1', { activeId }, function(row)
            local name = row and trimText((row.first_name or '') .. ' ' .. (row.last_name or '')) or ''
            if name == '' then name = 'Unknown' end
            if row and row.id then ActiveHudCharacters[src] = { id = tostring(row.id), name = name } end
            broadcastChatMessage(channel, name, row and row.id or activeId, text, nil, src)
        end)
        return
    end

    -- No character loaded: do not show FiveM server id/name as character data.
    broadcastChatMessage(channel, 'Unknown', 0, text, nil, src)
end)

AddEventHandler('playerDropped', function()
    LastChatAt[source] = nil
    ActiveHudCharacters[source] = nil
end)

-- Optional server-side event for other scripts.
-- Examples:
-- TriggerEvent('cm-hud:server:broadcastChatMessage', 'family', 'Sumit Yadav', 1, 'hello', {1, 2, 3})
-- exports['cm-hud']:RegisterChatChannel('family', 'FAMILY')
-- exports['cm-hud']:RegisterChatChannel('localadmin', 'ADMIN', { radius = 20.0 })
RegisterNetEvent('cm-hud:server:broadcastChatMessage', function(channel, authorName, authorId, text, target)
    broadcastChatMessage(channel, authorName, authorId, text, target)
end)

-- ============================================================
-- CHARACTER HUD DATABASE SYNC
-- Pulls ID/cash/bank from characters table so HUD matches DB in real time.
-- Supports oxmysql exports without making oxmysql a hard manifest dependency.
-- ============================================================
local HUD_SYNC_INTERVAL_MS = 2500

dbFetchOne = function(query, params, cb)
    params = params or {}

    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:single(query, params, cb)
        return true
    end

    if MySQL and MySQL.single then
        MySQL.single(query, params, cb)
        return true
    end

    print('[CM-HUD] No SQL resource found. Start oxmysql before cm-hud for DB money sync.')
    cb(nil)
    return false
end

cleanCharacterId = function(value)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    return value:sub(1, 50)
end

local function sendCharacterHud(src, charId)
    
    if type(charId) == 'table' then charId = charId.id end
    local active = ActiveHudCharacters[src]
    if not charId and type(active) == 'table' then charId = active.id end
    charId = cleanCharacterId(charId or active)
    if not charId then return end

    dbFetchOne('SELECT id, first_name, last_name, cash, bank FROM characters WHERE id = ? LIMIT 1', { charId }, function(row)
        if not row then return end
        local fullName = trimText((row.first_name or '') .. ' ' .. (row.last_name or ''))
        if fullName == '' then fullName = 'Unknown' end
        local payload = {
            id = tostring(row.id),
            name = fullName,
            cash = tonumber(row.cash) or 0,
            bank = tonumber(row.bank) or 0
        }
        ActiveHudCharacters[src] = { id = tostring(row.id), name = fullName }
        local encoded = json.encode(payload)
        if LastHudPayload[src] ~= encoded then
            LastHudPayload[src] = encoded
            TriggerClientEvent('cm-hud:client:updateCharacterHud', src, payload)
        end
    end)
end



local function readStateValue(src, keys)
    if not Player then return nil end
    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end
    for _, key in ipairs(keys) do
        local okValue, value = pcall(function() return state[key] end)
        if okValue and value ~= nil and tostring(value) ~= '' then
            return value
        end
    end
    return nil
end

local function extractCharacterIdFromAny(...)
    local args = { ... }
    for _, value in ipairs(args) do
        if type(value) == 'table' then
            local found = value.id or value.characterId or value.charId or value.charid or value.char_id or value.citizenid
            if found then return cleanCharacterId(found) end
            if type(value.character) == 'table' then
                found = value.character.id or value.character.characterId or value.character.charId or value.character.char_id
                if found then return cleanCharacterId(found) end
            end
        else
            local cleaned = cleanCharacterId(value)
            if cleaned then return cleaned end
        end
    end
    return nil
end

local function setActiveCharacterForSource(src, charId)
    src = tonumber(src)
    charId = cleanCharacterId(charId)
    if not src or not charId then return false end
    ActiveHudCharacters[src] = { id = charId, name = nil }
    sendCharacterHud(src, charId)
    return true
end

local function handleCharacterLoadedEvent(a, b, c)
    local src = source
    local charId

    -- Server-to-server style: TriggerEvent(eventName, src, charIdOrData)
    if tonumber(a) and tonumber(a) > 0 and tostring(a) ~= tostring(b) then
        src = tonumber(a)
        charId = extractCharacterIdFromAny(b, c)
    else
        -- Client-to-server style: TriggerServerEvent(eventName, charIdOrData)
        charId = extractCharacterIdFromAny(a, b, c)
    end

    if src and tonumber(src) and charId then
        setActiveCharacterForSource(src, charId)
    end
end

for _, eventName in ipairs({
    'cm-hud:server:setCharacter',
    'cm-characters:server:characterLoaded',
    'cm-characters:server:characterSelected',
    'cm-characters:server:selectedCharacter',
    'cm-characters:server:selectCharacter',
    'cm-spawn:server:characterLoaded',
    'cm-spawn:characterLoaded',
    'cm-core:server:characterLoaded'
}) do
    RegisterNetEvent(eventName, handleCharacterLoadedEvent)
end

local function resolveCharacterByHints(src, hints, cb)
    hints = hints or {}
    local charId = cleanCharacterId(hints.id or hints.characterId or hints.charid or hints.char_id or hints.citizenid)
    if charId then cb(charId) return end

    charId = extractCharacterIdFromAny(readStateValue(src, { 'characterId', 'charId', 'charid', 'char_id', 'citizenid', 'currentCharacterId' }))
    if charId then cb(charId) return end

    local accountId = cleanCharacterId(hints.account_id or hints.accountId or hints.account or hints.accountid) or cleanCharacterId(readStateValue(src, { 'account_id', 'accountId', 'account', 'accountid' }))
    local slot = tonumber(hints.slot or hints.charSlot or hints.character_slot)

    if accountId and slot then
        dbFetchOne('SELECT id FROM characters WHERE account_id = ? AND slot = ? LIMIT 1', { accountId, slot }, function(row)
            cb(row and row.id or nil)
        end)
        return
    end

    if accountId then
        dbFetchOne('SELECT id FROM characters WHERE account_id = ? ORDER BY has_spawned DESC, last_played DESC, created_at DESC LIMIT 1', { accountId }, function(row)
            cb(row and row.id or nil)
        end)
        return
    end

    -- Last safe fallback: if the client did not provide any character/account id, do not use FiveM server id.
    -- The HUD will keep ID blank until cm-playerdata/cm-characters sends the real character id.
    cb(nil)
end


RegisterNetEvent('cm-hud:server:requestCharacterHud', function(charId, hints)
    local src = source
    if type(charId) == 'table' and hints == nil then
        hints = charId
        charId = nil
    end
    hints = hints or {}
    hints.id = hints.id or charId

    resolveCharacterByHints(src, hints, function(resolvedId)
        resolvedId = cleanCharacterId(resolvedId)
        if not resolvedId then
            TriggerClientEvent('cm-hud:client:updateCharacterHud', src, { id = '', name = 'Unknown', cash = 0, bank = 0 })
            print(('[CM-HUD] Could not resolve DB character for player %s. Send character id/account_id from cm-playerdata.'):format(src))
            return
        end
        ActiveHudCharacters[src] = { id = resolvedId, name = nil }
        sendCharacterHud(src, resolvedId)
    end)
end)

-- Optional export for cm-playerdata/cm-characters after saving money:
-- exports['cm-hud']:RefreshCharacterHud(source, characterId)
exports('RefreshCharacterHud', function(src, charId)
    src = tonumber(src)
    if not src then return end
    if charId then ActiveHudCharacters[src] = { id = cleanCharacterId(charId), name = nil } end
    sendCharacterHud(src, ActiveHudCharacters[src])
end)

CreateThread(function()
    while true do
        Wait(HUD_SYNC_INTERVAL_MS)
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            if src and ActiveHudCharacters[src] then
                sendCharacterHud(src, ActiveHudCharacters[src])
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    ActiveHudCharacters[source] = nil
    LastHudPayload[source] = nil
end)
