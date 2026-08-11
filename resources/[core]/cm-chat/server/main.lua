-- cm-chat/server/main.lua
-- Modular RP/NON-RP/FAMILY/ORG/CLUB/ADMIN chat with character-name formatting.

local ActiveCharacters = {}
local LastChatAt = {}
local PlayerGroups = {}
local sendChannels

local function nowMs()
    return GetGameTimer and GetGameTimer() or math.floor(os.clock() * 1000)
end

local function cleanText(value, maxLen)
    value = tostring(value or ''):gsub('[\r\n\t]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, tonumber(maxLen) or Config.MaxMessageLength or 180)
end

local function cleanCharacterId(value)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or value == 'nil' then return nil end
    return value:sub(1, 50)
end

local function cleanGroupValue(value)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or value == 'nil' or value == 'false' then return nil end
    return value:sub(1, 80)
end

local function cleanColor(value, fallback)
    fallback = fallback or '#31e6ff'
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
    if value == '' or value == 'nil' then return fallback end

    local palette = Config.ColorPalette or {}
    if palette[value] then return palette[value] end
    if value:match('^#[0-9a-f][0-9a-f][0-9a-f]$') or value:match('^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$') or value:match('^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$') then
        return value
    end
    return fallback
end

local function dbFetchOne(query, params, cb)
    params = params or {}
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:single(query, params, cb)
        return true
    end
    if MySQL and MySQL.single then
        MySQL.single(query, params, cb)
        return true
    end
    cb(nil)
    return false
end

local function dbExecute(query, params)
    params = params or {}
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute(query, params)
        return true
    end
    if MySQL and MySQL.execute then
        MySQL.execute(query, params)
        return true
    end
    return false
end

local function safeJsonEncode(value)
    local ok, encoded = pcall(json.encode, value)
    return ok and encoded or '{}'
end

local function readStateValue(src, keys)
    if not Player then return nil end
    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end
    for _, key in ipairs(keys or {}) do
        local okValue, value = pcall(function() return state[key] end)
        if okValue and value ~= nil and tostring(value) ~= '' then
            return value
        end
    end
    return nil
end

local function getCmFamilyState(src)
    src = tonumber(src)
    if not src or src <= 0 or not Player then return nil end
    local ok, state = pcall(function() return Player(src).state.cmFamily end)
    if not ok or type(state) ~= 'table' or state.active == false then return nil end
    local familyId = tonumber(state.id or state.familyId or state.family_id)
    if not familyId then return nil end
    return {
        id = familyId,
        name = cleanText(state.name or state.familyName or 'Family', 60),
        tag = cleanText(state.tag or 'FAMILY', 12),
        color = cleanColor(state.color, '#72ff8c'),
        rankName = cleanText(state.rankName or 'Member', 32),
        title = cleanText(state.customTitle or '', 32),
        tier = tonumber(state.tier) or 0,
        permissions = type(state.permissions) == 'table' and state.permissions or {},
    }
end

local function extractCharacterIdFromAny(...)
    local args = { ... }
    for _, value in ipairs(args) do
        if type(value) == 'table' then
            local found = value.id or value.characterId or value.charId or value.charid or value.char_id or value.citizenid
            if found then return cleanCharacterId(found) end
            if type(value.character) == 'table' then
                found = value.character.id or value.character.characterId or value.character.charId or value.character.char_id or value.character.citizenid
                if found then return cleanCharacterId(found) end
            end
        else
            local cleaned = cleanCharacterId(value)
            if cleaned then return cleaned end
        end
    end
    return nil
end

local function sendSystemMessage(target, text, msgType)
    TriggerClientEvent('cm-chat:client:addMessage', target or -1, {
        channel = 'system',
        channelLabel = 'SYSTEM',
        author = 'Server',
        id = 0,
        text = cleanText(text, 180),
        type = msgType or 'system',
        format = 'system',
        time = os.date('%H:%M')
    })
end

local function isStaff(src)
    if not src or src <= 0 then return false end
    if IsPlayerAceAllowed(src, 'cm.admin') or IsPlayerAceAllowed(src, 'command.admin') then return true end
    if GetResourceState('cm-admin') == 'started' then
        local okActive, active = pcall(function() return exports['cm-admin']:IsAdminActive(src) end)
        if okActive and active == true then return true end

        local okAdmin, admin = pcall(function() return exports['cm-admin']:IsAdmin(src) end)
        if okAdmin and admin == true then return true end
    end
    return false
end

local function setPlayerGroup(src, groupName, groupValue, groupColor)
    src = tonumber(src)
    groupName = tostring(groupName or ''):lower():gsub('[^a-z0-9_%-]', '')
    if not src or src <= 0 or groupName == '' then return false end

    local defaultColor = Config.Channels and Config.Channels[groupName] and Config.Channels[groupName].color or '#31e6ff'
    PlayerGroups[src] = PlayerGroups[src] or {}
    PlayerGroups[src][groupName] = {
        value = cleanGroupValue(groupValue),
        color = cleanColor(groupColor, defaultColor)
    }

    if sendChannels then sendChannels(src) end
    return true
end

local function setPlayerGroups(src, groups)
    src = tonumber(src)
    if not src or src <= 0 or type(groups) ~= 'table' then return false end
    PlayerGroups[src] = PlayerGroups[src] or {}

    for groupName, groupData in pairs(groups) do
        groupName = tostring(groupName or ''):lower():gsub('[^a-z0-9_%-]', '')
        if groupName ~= '' then
            local value, color
            if type(groupData) == 'table' then
                value = groupData.id or groupData.value or groupData.groupId or groupData.group_id or groupData.name
                color = groupData.color or groupData.chatColor or groupData.chat_color
            else
                value = groupData
            end
            local defaultColor = Config.Channels and Config.Channels[groupName] and Config.Channels[groupName].color or '#31e6ff'
            PlayerGroups[src][groupName] = {
                value = cleanGroupValue(value),
                color = cleanColor(color, defaultColor)
            }
        end
    end

    if sendChannels then sendChannels(src) end
    return true
end

exports('SetPlayerChatGroup', setPlayerGroup)
exports('SetPlayerChatGroups', setPlayerGroups)

RegisterNetEvent('cm-chat:server:setChatGroup', function(groupName, groupValue, groupColor)
    setPlayerGroup(source, groupName, groupValue, groupColor)
end)

RegisterNetEvent('cm-chat:server:setChatGroups', function(groups)
    setPlayerGroups(source, groups)
end)

local function getGroupValue(src, groupName)
    groupName = tostring(groupName or ''):lower()

    -- Family membership is never accepted from the public manual-group event.
    -- Only cm-family's replicated server state can enable this channel.
    if groupName == 'family' then
        local family = getCmFamilyState(src)
        return family and tostring(family.id) or nil
    end

    -- EMS radio access is always rebuilt from cm-ems's authoritative
    -- membership. Never accept a client/manual group assignment for it.
    if groupName == 'ems' then
        if GetResourceState('cm-ems') ~= 'started' then return nil end
        local active = ActiveCharacters[src]
        local characterId = active and active.id or extractCharacterIdFromAny(
            readStateValue(src, { 'characterId', 'charId', 'charid', 'char_id', 'currentCharacterId' }))
        if not characterId then return nil end
        local ok, membership = pcall(function()
            return exports['cm-ems']:GetMember(tostring(characterId))
        end)
        if not ok or type(membership) ~= 'table' or membership.suspended == true then return nil end
        return 'ems'
    end

    -- Police channels are a separate authoritative organization group. A
    -- client/manual SetPlayerChatGroup call cannot grant Police chat access.
    if groupName == 'police' then
        if GetResourceState('cm-police') ~= 'started' then return nil end
        local active = ActiveCharacters[src]
        local characterId = active and active.id or extractCharacterIdFromAny(
            readStateValue(src, { 'characterId', 'charId', 'charid', 'char_id', 'currentCharacterId' }))
        if not characterId then return nil end
        local ok, membership = pcall(function()
            return exports['cm-police']:GetMember(tostring(characterId))
        end)
        if not ok or type(membership) ~= 'table' or membership.suspended == true then return nil end
        return 'police'
    end

    -- cm-law channels are authoritative per organization and capability.
    -- Manual group events/state bags cannot grant access to these groups.
    local legalOrgId, legalKind = groupName:match('^legal_([a-z0-9_%-]+)_(radio)$')
    if not legalOrgId then legalOrgId, legalKind = groupName:match('^legal_([a-z0-9_%-]+)_(chat)$') end
    if legalOrgId then
        if GetResourceState('cm-law') ~= 'started' then return nil end
        local active = ActiveCharacters[src]
        local characterId = active and active.id or extractCharacterIdFromAny(
            readStateValue(src, { 'characterId', 'charId', 'charid', 'char_id', 'currentCharacterId' }))
        if not characterId then return nil end
        local ok, membership = pcall(function() return exports['cm-law']:GetMember(tostring(characterId), legalOrgId) end)
        if not ok or type(membership) ~= 'table' or membership.suspended == true then return nil end
        local permission = legalKind == 'radio' and 'law.radio' or 'law.chat'
        if membership.isLeader ~= true and (type(membership.permissions) ~= 'table' or membership.permissions[permission] ~= true) then return nil end
        return legalOrgId
    end

    local manual = PlayerGroups[src] and PlayerGroups[src][groupName]
    if type(manual) == 'table' and manual.value then return manual.value end
    if manual and type(manual) ~= 'table' then return manual end

    local keys = Config.GroupStateKeys and Config.GroupStateKeys[groupName]
    if keys then
        local value = readStateValue(src, keys)
        if type(value) == 'table' then
            value = value.id or value.value or value.groupId or value.group_id or value.name
        end
        return cleanGroupValue(value)
    end
    return nil
end

local function getGroupColor(src, groupName, fallback)
    groupName = tostring(groupName or ''):lower()
    if groupName == 'family' then
        local family = getCmFamilyState(src)
        if family then return family.color end
    end
    local manual = PlayerGroups[src] and PlayerGroups[src][groupName]
    if type(manual) == 'table' and manual.color then
        return cleanColor(manual.color, fallback or '#31e6ff')
    end
    return cleanColor(fallback or '#31e6ff', '#31e6ff')
end

local function channelAvailableFor(src, ch)
    if not ch then return false end
    if ch.always == true then return true end
    if ch.staff == true or ch.type == 'staff' then return isStaff(src) end
    if ch.type == 'group' and ch.group then return getGroupValue(src, ch.group) ~= nil end
    return false
end

local function getChannelList(src)
    local list = {}
    local added = {}
    for _, id in ipairs(Config.ChannelOrder or {}) do
        local ch = Config.Channels[id]
        if ch and not ch.hiddenTab and channelAvailableFor(src, ch) then
            list[#list + 1] = { id = ch.id, label = ch.label, color = (ch.type == 'group' and getGroupColor(src, ch.group, ch.color) or ch.color), format = ch.format, type = ch.type }
            added[id] = true
        end
    end
    for id, ch in pairs(Config.Channels or {}) do
        if not added[id] and not ch.hiddenTab and channelAvailableFor(src, ch) then
            list[#list + 1] = { id = ch.id, label = ch.label, color = (ch.type == 'group' and getGroupColor(src, ch.group, ch.color) or ch.color), format = ch.format, type = ch.type }
        end
    end
    return list
end

function sendChannels(src)
    TriggerClientEvent('cm-chat:client:setChannels', src, getChannelList(src), Config.Actions or {})
end

local function registerChannel(id, label, options)
    id = tostring(id or ''):lower():gsub('%s+', '')
    if id == '' then return false end
    options = options or {}
    Config.Channels[id] = {
        id = id,
        label = tostring(label or id:upper()),
        type = options.type or (options.group and 'group') or (options.global and 'global') or 'proximity',
        group = options.group,
        radius = options.radius,
        staff = options.staff == true,
        always = options.always == true,
        hiddenTab = options.hiddenTab == true,
        color = cleanColor(options.color, '#31e6ff'),
        format = options.format or 'rp'
    }
    if options.appendOrder == true then
        local exists = false
        for _, current in ipairs(Config.ChannelOrder or {}) do if current == id then exists = true break end end
        if not exists then Config.ChannelOrder[#Config.ChannelOrder + 1] = id end
    end
    return true
end

exports('RegisterChatChannel', registerChannel)

local function setCharacter(src, charId, preloadName)
    src = tonumber(src)
    charId = cleanCharacterId(charId)
    if not src or src <= 0 or not charId then return false end

    ActiveCharacters[src] = {
        id = charId,
        name = preloadName or nil
    }

    if preloadName and preloadName ~= '' then
        sendChannels(src)
        return true
    end

    local q = ('SELECT %s AS id, %s AS first_name, %s AS last_name FROM %s WHERE %s = ? LIMIT 1'):format(
        Config.CharacterIdColumn or 'id',
        Config.CharacterFirstNameColumn or 'first_name',
        Config.CharacterLastNameColumn or 'last_name',
        Config.CharacterTable or 'characters',
        Config.CharacterIdColumn or 'id'
    )

    dbFetchOne(q, { charId }, function(row)
        if not row then return end
        local name = cleanText((row.first_name or '') .. ' ' .. (row.last_name or ''), 60)
        if name == '' then name = 'Unknown' end
        ActiveCharacters[src] = { id = tostring(row.id), name = name }
        sendChannels(src)
    end)

    return true
end

exports('SetPlayerCharacter', function(src, charId, name)
    return setCharacter(src, charId, name)
end)

local function resolveCharacterByHints(src, hints, cb)
    hints = hints or {}

    local stateId = extractCharacterIdFromAny(readStateValue(src, { 'characterId', 'charId', 'charid', 'char_id', 'citizenid', 'currentCharacterId' }))
    if stateId then cb(stateId) return end

    local charId = extractCharacterIdFromAny(hints.id or hints.characterId or hints.charId or hints.charid or hints.char_id or hints.citizenid)
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

    cb(nil)
end

RegisterNetEvent('cm-chat:server:resolveCharacter', function(charId, hints)
    local src = source
    hints = hints or {}
    hints.id = hints.id or charId
    resolveCharacterByHints(src, hints, function(resolvedId)
        resolvedId = cleanCharacterId(resolvedId)
        if resolvedId then
            setCharacter(src, resolvedId)
        else
            sendChannels(src)
        end
    end)
end)

local function handleCharacterLoadedEvent(a, b, c)
    local src = source
    local charId
    if tonumber(a) and tonumber(a) > 0 and tostring(a) ~= tostring(b) then
        src = tonumber(a)
        charId = extractCharacterIdFromAny(b, c)
    else
        charId = extractCharacterIdFromAny(a, b, c)
    end
    if src and charId then setCharacter(src, charId) end
end

for _, eventName in ipairs({
    'cm-chat:server:setCharacter',
    'cm-chat:server:setTrustedCharacter',
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

local function getActiveCharacter(src, cb)
    local active = ActiveCharacters[src]
    if active and active.id and active.name then cb(active) return end

    local stateId = extractCharacterIdFromAny(readStateValue(src, { 'characterId', 'charId', 'charid', 'char_id', 'citizenid', 'currentCharacterId' }))
    if stateId then
        setCharacter(src, stateId)
        Wait(50)
        active = ActiveCharacters[src]
        if active and active.id then
            if active.name then cb(active) return end
            local q = ('SELECT %s AS id, %s AS first_name, %s AS last_name FROM %s WHERE %s = ? LIMIT 1'):format(
                Config.CharacterIdColumn or 'id',
                Config.CharacterFirstNameColumn or 'first_name',
                Config.CharacterLastNameColumn or 'last_name',
                Config.CharacterTable or 'characters',
                Config.CharacterIdColumn or 'id'
            )
            dbFetchOne(q, { active.id }, function(row)
                if row then
                    local name = cleanText((row.first_name or '') .. ' ' .. (row.last_name or ''), 60)
                    if name == '' then name = 'Unknown' end
                    active = { id = tostring(row.id), name = name }
                    ActiveCharacters[src] = active
                    cb(active)
                else
                    cb(nil)
                end
            end)
            return
        end
    end

    cb(active)
end

local function hasBlockedWord(text)
    if Config.EnableBlockedWords ~= true then return false end
    local lowered = tostring(text or ''):lower()
    for _, word in ipairs(Config.BlockedWords or {}) do
        word = tostring(word or ''):lower()
        if word ~= '' and lowered:find(word, 1, true) then
            return true
        end
    end
    return false
end

local function logChat(src, active, channel, text, targetsMeta)
    if Config.EnableDatabaseLogs ~= true then return end
    dbExecute('INSERT INTO cm_chat_logs (source, character_id, character_name, channel, message, meta) VALUES (?, ?, ?, ?, ?, ?)', {
        src,
        active and active.id or nil,
        active and active.name or nil,
        channel,
        text,
        safeJsonEncode({ identifiers = GetPlayerIdentifiers(src), targets = targetsMeta })
    })
end

local function buildPayload(channelId, active, text, overrideFormat, overrideColor)
    local ch = Config.Channels[channelId] or { id = channelId, label = tostring(channelId):upper(), format = 'rp', color = '#31e6ff' }
    local color = cleanColor(overrideColor or ch.color, '#31e6ff')
    return {
        channel = ch.id or channelId,
        channelLabel = ch.label or tostring(channelId):upper(),
        channelColor = color,
        author = active and active.name or 'Unknown',
        id = tonumber(active and active.id) or 0,
        text = cleanText(text, Config.MaxMessageLength or 180),
        type = overrideFormat or ch.format or 'rp',
        format = overrideFormat or ch.format or 'rp',
        time = os.date('%H:%M')
    }
end

local function sendPayloadToTargets(targets, payload)
    if type(targets) == 'table' then
        for _, playerId in ipairs(targets) do
            TriggerClientEvent('cm-chat:client:addMessage', tonumber(playerId), payload)
        end
    elseif targets then
        TriggerClientEvent('cm-chat:client:addMessage', tonumber(targets), payload)
    else
        TriggerClientEvent('cm-chat:client:addMessage', -1, payload)
    end
end

local function sendProximity(src, radius, payload)
    src = tonumber(src)
    if not src or src <= 0 then return end
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return end
    local srcCoords = GetEntityCoords(srcPed)
    radius = tonumber(radius) or Config.DefaultLocalRadius or 20.0

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local ped = GetPlayerPed(target)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            if #(srcCoords - coords) <= radius then
                TriggerClientEvent('cm-chat:client:addMessage', target, payload)
            end
        end
    end
end

local function getGroupTargets(groupName, groupValue)
    local targets = {}
    groupValue = cleanGroupValue(groupValue)
    if not groupValue then return targets end

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if cleanGroupValue(getGroupValue(target, groupName)) == groupValue then
            targets[#targets + 1] = target
        end
    end
    return targets
end

local function getStaffTargets()
    local targets = {}
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if isStaff(target) then targets[#targets + 1] = target end
    end
    return targets
end

local function broadcastChatMessage(channelId, authorName, authorId, text, targets, sourcePlayer, formatOverride)
    channelId = tostring(channelId or 'rp'):lower()
    if not Config.Channels[channelId] then
        registerChannel(channelId, channelId:upper(), { type = targets == nil and 'global' or 'manual', format = formatOverride or 'rp' })
    end

    local active = { name = authorName or 'Unknown', id = authorId or 0 }
    local ch = Config.Channels[channelId]
    local colorOverride = ch and ch.type == 'group' and sourcePlayer and getGroupColor(sourcePlayer, ch.group, ch.color) or nil
    local payload = buildPayload(channelId, active, text, formatOverride, colorOverride)

    if targets ~= nil then
        sendPayloadToTargets(targets, payload)
    elseif ch.type == 'proximity' then
        sendProximity(sourcePlayer or 0, ch.radius, payload)
    elseif ch.type == 'global' then
        sendPayloadToTargets(nil, payload)
    elseif ch.type == 'staff' then
        sendPayloadToTargets(getStaffTargets(), payload)
    elseif ch.type == 'group' and sourcePlayer then
        local groupValue = getGroupValue(sourcePlayer, ch.group)
        sendPayloadToTargets(getGroupTargets(ch.group, groupValue), payload)
    else
        sendPayloadToTargets(sourcePlayer or -1, payload)
    end
end

exports('BroadcastChatMessage', broadcastChatMessage)

local function sendPlayerMessage(src, channelId, text, formatOverride)
    text = cleanText(text, Config.MaxMessageLength or 180)
    if text == '' then return end

    local now = nowMs()
    local last = LastChatAt[src] or 0
    if now - last < (Config.ChatCooldownMs or 650) then return end
    LastChatAt[src] = now

    if hasBlockedWord(text) then
        sendSystemMessage(src, 'Message blocked.', 'error')
        return
    end

    channelId = tostring(channelId or 'rp'):lower()
    channelId = Config.CommandAliases[channelId] or channelId
    local ch = Config.Channels[channelId]
    if not ch then
        channelId = 'rp'
        ch = Config.Channels.rp
    end

    if (ch.staff or ch.type == 'staff') and not isStaff(src) then
        sendSystemMessage(src, 'You do not have permission for admin chat.', 'error')
        return
    end

    if ch.type == 'group' then
        local groupValue = getGroupValue(src, ch.group)
        if not groupValue then
            sendSystemMessage(src, ('You are not in %s chat.'):format(ch.label or ch.group or 'this'), 'error')
            sendChannels(src)
            return
        end
    end

    -- Family chat authority lives in cm-family. The selected FAMILY tab and
    -- /f command must share the same permission, cooldown and recipient rules.
    if channelId == 'family' then
        if GetResourceState('cm-family') ~= 'started' then
            sendSystemMessage(src, 'Family chat is unavailable right now.', 'error')
            return
        end
        local ok, accepted, reason = pcall(function()
            return exports['cm-family']:SendFamilyChat(src, text)
        end)
        if not ok then
            print(('[CM-CHAT] cm-family SendFamilyChat failed: %s'):format(tostring(accepted)))
            sendSystemMessage(src, 'Family chat could not send the message.', 'error')
        elseif accepted == false and reason then
            sendSystemMessage(src, tostring(reason):gsub('_', ' '), 'error')
        end
        return
    end

    getActiveCharacter(src, function(active)
        if not active or not active.id then
            sendSystemMessage(src, 'Character is not loaded yet. Select your character first.', 'warning')
            return
        end

        local colorOverride = ch.type == 'group' and getGroupColor(src, ch.group, ch.color) or nil
        local payload = buildPayload(channelId, active, text, formatOverride or ch.format or 'rp', colorOverride)
        local targetsMeta = nil

        if ch.type == 'staff' then
            local targets = getStaffTargets()
            targetsMeta = targets
            sendPayloadToTargets(targets, payload)
        elseif ch.type == 'group' then
            local groupValue = getGroupValue(src, ch.group)
            local targets = getGroupTargets(ch.group, groupValue)
            targetsMeta = { group = ch.group, groupValue = groupValue, count = #targets }
            sendPayloadToTargets(targets, payload)
        elseif ch.type == 'proximity' then
            sendProximity(src, ch.radius, payload)
        elseif ch.type == 'global' then
            sendPayloadToTargets(nil, payload)
        else
            sendPayloadToTargets(src, payload)
        end

        logChat(src, active, channelId, text, targetsMeta)
    end)
end

-- Server-only integration used by organization resources for command aliases.
-- sendPlayerMessage still performs the same cooldown, blocked-word, character,
-- channel-membership, recipient, and database-log checks as the NUI path.
exports('SendPlayerChatMessage', function(src, channelId, text, formatOverride)
    src, channelId = tonumber(src), tostring(channelId or ''):lower()
    if not src or not Config.Channels[channelId] then return false end
    sendPlayerMessage(src, channelId, text, formatOverride)
    return true
end)

-- Internal server-only integration from cm-family. This event is intentionally
-- not registered as a network event, so clients cannot forge family messages.
AddEventHandler('cm-chat:server:familyMessage', function(data, suppliedRecipients)
    if type(data) ~= 'table' then return end

    local authorSource = tonumber(data.source)
    local familyId = tonumber(data.familyId or data.family_id)
    local message = cleanText(data.message, Config.MaxMessageLength or 180)
    if not authorSource or authorSource <= 0 or not familyId or message == '' then return end

    local authorFamily = getCmFamilyState(authorSource)
    if not authorFamily or tonumber(authorFamily.id) ~= familyId then
        print(('[CM-CHAT] rejected family message with invalid author state (source=%s family=%s)')
            :format(tostring(authorSource), tostring(familyId)))
        return
    end

    local payload = {
        channel = 'family',
        channelLabel = 'FAMILY',
        channelColor = cleanColor(data.color or authorFamily.color, '#72ff8c'),
        author = cleanText(data.name or GetPlayerName(authorSource) or 'Unknown', 60),
        id = tonumber(data.characterId) or 0,
        text = message,
        type = 'family',
        format = 'family',
        time = os.date('%H:%M'),
        familyId = familyId,
        familyName = cleanText(data.familyName or authorFamily.name, 60),
        familyTag = cleanText(data.tag or authorFamily.tag or 'FAMILY', 12),
        rankName = cleanText(data.rankName or authorFamily.rankName or 'Member', 32),
        memberTitle = cleanText(data.title or authorFamily.title or '', 32),
    }

    local recipients = {}
    local seen = {}
    -- Rebuild recipients from authoritative replicated family state. Never trust
    -- an arbitrary target list supplied by another resource.
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local targetFamily = getCmFamilyState(target)
        if target and targetFamily and tonumber(targetFamily.id) == familyId and not seen[target] then
            recipients[#recipients + 1] = target
            seen[target] = true
        end
    end

    if #recipients == 0 then return end
    sendPayloadToTargets(recipients, payload)
    logChat(authorSource, { id = payload.id, name = payload.author }, 'family', message, {
        familyId = familyId,
        familyTag = payload.familyTag,
        rankName = payload.rankName,
        recipients = #recipients,
    })
end)

AddEventHandler('cm-chat:server:refreshPlayerChannels', function(target)
    target = tonumber(target)
    if target and target > 0 and GetPlayerName(target) then sendChannels(target) end
end)

RegisterNetEvent('cm-chat:server:sendChatMessage', function(channel, text)
    sendPlayerMessage(source, channel, text)
end)

RegisterNetEvent('cm-chat:server:requestChannels', function()
    sendChannels(source)
end)

RegisterNetEvent('cm-chat:server:clearCharacter', function()
    ActiveCharacters[source] = nil
    PlayerGroups[source] = nil
end)

RegisterCommand('me', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'me', table.concat(args or {}, ' '), 'me')
end, false)

RegisterCommand('do', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'doo', table.concat(args or {}, ' '), 'do')
end, false)

RegisterCommand('try', function(src, args)
    if src <= 0 then return end
    local text = table.concat(args or {}, ' ')
    local result = math.random(1, 2) == 1 and 'success' or 'fail'
    if cleanText(text, 180) ~= '' then
        text = text .. ' — ' .. result
    else
        text = result
    end
    sendPlayerMessage(src, 'me', text, 'try')
end, false)

RegisterCommand('ooc', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'nonrp', table.concat(args or {}, ' '), 'nonrp')
end, false)

RegisterCommand('emsrp', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'ems_rp', table.concat(args or {}, ' '), 'ems_rp')
end, false)

RegisterCommand('emsnrp', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'ems_nonrp', table.concat(args or {}, ' '), 'ems_nonrp')
end, false)

RegisterCommand('policerp', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'police_rp', table.concat(args or {}, ' '), 'police_rp')
end, false)

RegisterCommand('policenrp', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'police_nonrp', table.concat(args or {}, ' '), 'police_nonrp')
end, false)

RegisterCommand('b', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'low', table.concat(args or {}, ' '), 'nonrp')
end, false)

RegisterCommand('low', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'low', table.concat(args or {}, ' '), 'rp')
end, false)

RegisterCommand('s', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'shout', table.concat(args or {}, ' '), 'rp')
end, false)

RegisterCommand('shout', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'shout', table.concat(args or {}, ' '), 'rp')
end, false)

RegisterCommand('a', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'admin', table.concat(args or {}, ' '), 'admin')
end, false)

RegisterCommand('staff', function(src, args)
    if src <= 0 then return end
    sendPlayerMessage(src, 'admin', table.concat(args or {}, ' '), 'admin')
end, false)

RegisterCommand('clear', function(src)
    if src <= 0 then return end
    TriggerClientEvent('cm-chat:client:clear', src)
end, false)

AddEventHandler('playerDropped', function()
    ActiveCharacters[source] = nil
    LastChatAt[source] = nil
    PlayerGroups[source] = nil
end)

CreateThread(function()
    Wait(1000)
    if Config.EnableDatabaseLogs == true then
        dbExecute([[CREATE TABLE IF NOT EXISTS cm_chat_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            source INT NULL,
            character_id VARCHAR(50) NULL,
            character_name VARCHAR(100) NULL,
            channel VARCHAR(50) NOT NULL,
            message TEXT NOT NULL,
            meta LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )]], {})
    end
    print('[CM-CHAT] Loaded modular cyan RP chat with authoritative family channel integration')
end)

-- ===========================================================================
-- v1.3: admin broadcast lines, RP action lines, admin announcements.
-- Extensible by design: new systems (family, gang, jobs) either register a
-- channel via RegisterChatChannel or emit through the exports below —
-- this file never needs editing for new content types.
-- ===========================================================================

-- New channels (hiddenTab = they render in chat but aren't selectable tabs).
registerChannel('action', 'ACTION', {
    type = 'proximity', radius = Config.ActionRadius or 20.0,
    color = Config.ColorPalette.actionpink or '#ff4fd8',
    format = 'action', hiddenTab = true, always = true
})
registerChannel('announce', 'ADMIN', {
    type = 'global',
    color = Config.ColorPalette.adminorange or '#ff8a2a',
    format = 'announce', hiddenTab = true, always = true
})
registerChannel('adminsys', 'ADMIN', {
    type = 'global',
    color = Config.ColorPalette.adminorange or '#ff8a2a',
    format = 'adminsys', hiddenTab = true, always = true
})

local function activeOrFallback(src)
    local active = ActiveCharacters[src]
    if active and active.name then return active end
    return { name = GetPlayerName(src) or 'Unknown', id = (active and active.id) or 0 }
end

-- ---------------------------------------------------------------------------
-- RP action lines (pink, proximity): "Garry Green (2778) puts something in the trunk"
-- From any resource:
--   exports['cm-chat']:SendActionMessage(source, 'puts something in the trunk')
--   exports['cm-chat']:SendActionMessage(source, 'takes something from the trunk', 25.0)
-- ---------------------------------------------------------------------------
local function sendActionMessage(src, text, radius)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    text = cleanText(text, 140)
    if text == '' then return false end

    local payload = buildPayload('action', activeOrFallback(src), text, 'action')
    sendProximity(src, radius or (Config.Channels.action and Config.Channels.action.radius), payload)
    return true
end
exports('SendActionMessage', sendActionMessage)

-- ---------------------------------------------------------------------------
-- Admin permission helper: cm-admin ranks first, ACE fallback.
-- ---------------------------------------------------------------------------
local function adminHasPermission(src, permission, aceFallback)
    local ok, allowed = pcall(function()
        return exports['cm-admin']:HasPermission(src, permission)
    end)
    if ok and type(allowed) == 'boolean' then return allowed end
    return IsPlayerAceAllowed(src, aceFallback or ('cm.chat.' .. permission))
end

-- ---------------------------------------------------------------------------
-- Admin announcements.
--   /announce <msg> -> "Administrator Alex Tek: msg"   (needs chat.announce)
--   /anon <msg>     -> "Administrator: msg"            (needs chat.announce_anon)
-- Rank decides who gets which: give lower ranks only chat.announce so their
-- name always shows; senior ranks get chat.announce_anon too.
-- ---------------------------------------------------------------------------
local function doAnnounce(src, args, anonymous)
    if src <= 0 then
        -- console can always announce, anonymously
        local payload = buildPayload('announce', { name = 'Server', id = 0 }, table.concat(args or {}, ' '), 'announce_anon')
        sendPayloadToTargets(nil, payload)
        return
    end

    local perm = anonymous and 'chat.announce_anon' or 'chat.announce'
    if not adminHasPermission(src, perm) then
        TriggerClientEvent('cm-chat:client:addMessage', src,
            buildPayload('adminsys', { name = 'Server', id = 0 }, 'You do not have permission: ' .. perm, 'system'))
        return
    end

    local text = cleanText(table.concat(args or {}, ' '), Config.MaxMessageLength or 180)
    if text == '' then return end

    local payload = buildPayload('announce', activeOrFallback(src), text, anonymous and 'announce_anon' or 'announce')
    sendPayloadToTargets(nil, payload)
end

RegisterCommand('announce', function(src, args) doAnnounce(src, args, false) end, false)
RegisterCommand('anon', function(src, args) doAnnounce(src, args, true) end, false)

-- ---------------------------------------------------------------------------
-- Admin action lines (orange, global), fed automatically by cm-admin's
-- actionLogged bridge. Add a template here (or via the export) and any new
-- admin action starts appearing in chat with zero code changes elsewhere.
-- Placeholders: {admin} {adminId} {target} {targetId} {reason}
-- ---------------------------------------------------------------------------
Config.AdminActionBroadcast = Config.AdminActionBroadcast or {
    kick   = 'Administrator {admin}[{adminId}] kicked {target}[{targetId}]. Reason: {reason}',
    ban    = 'Administrator {admin}[{adminId}] banned {target}[{targetId}]. Reason: {reason}',
    freeze = 'Administrator {admin}[{adminId}] froze {target}[{targetId}].',
    unfreeze = 'Administrator {admin}[{adminId}] unfroze {target}[{targetId}].',
    silence = 'Administrator {admin}[{adminId}] has silenced {target}[{targetId}]. Reason: {reason}'
}

local function registerAdminActionTemplate(action, template)
    Config.AdminActionBroadcast[tostring(action)] = tostring(template)
end
exports('RegisterAdminActionMessage', registerAdminActionTemplate)

local function broadcastAdminAction(src, action, data)
    local template = Config.AdminActionBroadcast[tostring(action or '')]
    if not template then return end
    data = type(data) == 'table' and data or {}

    local admin = activeOrFallback(src)
    local line = template
        :gsub('{admin}', cleanText(admin.name, 40))
        :gsub('{adminId}', tostring(admin.id or 0))
        :gsub('{target}', cleanText(data.targetName or data.name or data.target or 'Unknown', 40))
        :gsub('{targetId}', tostring(data.targetCharacterId or data.characterId or data.targetId or '?'))
        :gsub('{reason}', cleanText(data.reason or 'Not specified', 80))

    local payload = buildPayload('adminsys', { name = 'Server', id = 0 }, line, 'adminsys')
    sendPayloadToTargets(nil, payload)
end

AddEventHandler('cm-admin:server:actionLogged', function(src, action, data)
    broadcastAdminAction(src, action, data)
end)

-- Other resources (bans, reports, anticheat) can broadcast directly:
exports('AdminActionBroadcast', broadcastAdminAction)
