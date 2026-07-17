-- cm-family | server/sv_chat.lua
-- Private family chat. Active family membership grants access; cm-family owns
-- recipients and emits a clean integration event for cm-chat while retaining
-- a standard chat fallback.

local B = CMFamilyBridge
local lastUse = {}

local function cleanMessage(value)
    local maxLength = tonumber(Config.Chat and Config.Chat.maxLength) or 180
    local message = tostring(value or ''):gsub('[\r\n\t]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    message = message:gsub('[<>]', '')
    if #message > maxLength then message = message:sub(1, maxLength) end
    return message
end

local function sendFamilyChat(src, args)
    if not (Config.Chat and Config.Chat.enabled) then return false, 'family_chat_disabled' end
    local cid = B.GetCid(src)
    local rank, fam = GetRankForCid(cid)
    if not rank or not fam then
        B.Notify(src, 'You are not in a family.', 'error')
        return false, 'not_in_a_family'
    end
    local now = GetGameTimer()
    local cooldown = tonumber(Config.Chat.cooldownMs) or 1200
    if lastUse[src] and now - lastUse[src] < cooldown then
        LogFamily(fam.id, cid, 'family_chat_blocked', { reason = 'cooldown' }, { status = 'denied' })
        return false, 'family_chat_cooldown'
    end
    lastUse[src] = now

    local message = cleanMessage(type(args) == 'table' and table.concat(args, ' ') or args)
    if message == '' then
        B.Notify(src, 'Usage: /f message', 'inform')
        LogFamily(fam.id, cid, 'family_chat_blocked', { reason = 'empty_message' }, { status = 'denied' })
        return false, 'empty_message'
    end

    local identity = BuildFamilyMemberState(cid)
    local payload = {
        source = src,
        familyId = fam.id,
        familyName = fam.name,
        tag = fam.tag,
        color = fam.color or '#00f0ff',
        characterId = tostring(cid),
        name = B.GetCharName(cid),
        rankName = rank.name,
        title = identity and identity.customTitle or nil,
        message = message,
    }

    local recipients = {}
    for memberCid, membership in pairs(MemberByCid) do
        if tonumber(membership.family_id) == tonumber(fam.id) then
            local memberSrc = B.GetSrcByCid(memberCid)
            if memberSrc then recipients[#recipients + 1] = memberSrc end
        end
    end

    local customChatRunning = GetResourceState('cm-chat') == 'started'
    if not customChatRunning then
        for _, memberSrc in ipairs(recipients) do
            TriggerClientEvent('cm-family:client:familyChat', memberSrc, payload)
        end
    end

    -- Server-only integration seam. cm-chat validates the author/family state
    -- again and rebuilds recipients before displaying the message.
    TriggerEvent('cm-family:server:chatMessage', payload, recipients)
    TriggerEvent('cm-chat:server:familyMessage', payload, recipients)
    LogFamily(fam.id, cid, 'family_chat_sent', { length = #message, recipientCount = #recipients })
    return true
end

for _, command in ipairs((Config.Chat and Config.Chat.commands) or { 'f', 'familychat' }) do
    RegisterCommand(command, function(src, args)
        if src > 0 then sendFamilyChat(src, args) end
    end, false)
end

exports('SendFamilyChat', function(src, message) return sendFamilyChat(tonumber(src), message) end)

AddEventHandler('playerDropped', function() lastUse[source] = nil end)
