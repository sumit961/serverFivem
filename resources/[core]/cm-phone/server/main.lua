-- cm-phone server callbacks. Every client request is resolved source -> loaded character -> phone
-- identity here. Request fields are only ever treated as untrusted input to the service layer.
local S = CMPhone.Server
local Config = CMPhone.Config

-- Registers a callback with context resolution, rate limiting and error isolation.
-- fn(src, cid, number, a, b) returns ok, data|errorCode (+ optional extra)
local function register(name, bucket, fn)
    lib.callback.register('cm-phone:' .. name, function(src, a, b)
        local cid, number = S.Context(src)
        if not cid then return { ok = false, error = number or 'character_not_loaded' } end
        if bucket and not S.RateLimit(cid, bucket) then return { ok = false, error = 'rate_limited' } end
        local called, ok, data, extra = pcall(fn, src, cid, number, a, b)
        if not called then
            print(('[cm-phone] %s failed: %s'):format(name, tostring(ok)))
            return { ok = false, error = 'internal_error' }
        end
        if ok then return { ok = true, data = data } end
        return { ok = false, error = tostring(data or 'failed'), extra = extra }
    end)
end

local function isDead(src)
    local api = S.playerData()
    if not api then return false end
    local ok, dead = pcall(function() return api:IsDead(src) end)
    return ok and dead == true
end

register('bootstrap', 'read', function(src, cid, number)
    return true, {
        number = number,
        contacts = S.ListContacts(cid),
        conversations = S.ListConversations(cid),
        calls = S.ListCalls(cid),
        blocks = S.ListBlocks(cid),
        unread = S.UnreadTotal(cid),
        call = S.CallState(cid),
        limits = {
            textMax = Config.Messages.textMax, nameMax = Config.Contacts.nameMax, groupNameMax = Config.Messages.groupNameMax,
            groupMembersMax = Config.Messages.groupMembersMax, advertMax = Config.Adverts.textMax, advertMin = Config.Adverts.textMin,
            advertFee = Config.Adverts.fee, advertCooldown = Config.Adverts.cooldownSeconds, detailsMax = Config.Emergency.detailsMax,
        },
    }
end)

-- Contacts ---------------------------------------------------------------
register('contactSave', 'contact', function(src, cid, number, data)
    local ok, result = S.SaveContact(cid, data)
    if not ok then return false, result end
    return true, { id = result, contacts = S.ListContacts(cid) }
end)

register('contactDelete', 'contact', function(src, cid, number, id)
    local ok, reason = S.DeleteContact(cid, id)
    if not ok then return false, reason end
    return true, { contacts = S.ListContacts(cid) }
end)

-- Blocking ---------------------------------------------------------------
register('block', 'block', function(src, cid, number, raw)
    local ok, reason = S.Block(cid, number, raw)
    if not ok then return false, reason end
    return true, { blocks = S.ListBlocks(cid) }
end)

register('unblock', 'block', function(src, cid, number, raw)
    local ok, reason = S.Unblock(cid, raw)
    if not ok then return false, reason end
    return true, { blocks = S.ListBlocks(cid) }
end)

-- Messages ---------------------------------------------------------------
local function target(data)
    if type(data) ~= 'table' then return nil end
    if data.conversationId ~= nil then return { conversationId = data.conversationId } end
    return { number = data.number }
end

register('conversations', 'read', function(src, cid)
    return true, { conversations = S.ListConversations(cid), unread = S.UnreadTotal(cid) }
end)

register('openConversation', 'read', function(src, cid, number, data)
    data = type(data) == 'table' and data or {}
    return S.OpenConversation(cid, data.conversationId, data.before)
end)

register('markRead', 'read', function(src, cid, number, conversationId)
    local ok, reason = S.MarkRead(cid, conversationId)
    if not ok then return false, reason end
    return true, { unread = S.UnreadTotal(cid) }
end)

register('send', 'sms', function(src, cid, number, data)
    local t = target(data)
    if not t then return false, 'invalid_request' end
    return S.SendMessage(cid, number, t, 'text', data.text)
end)

register('sendLocation', 'sms', function(src, cid, number, data)
    local t = target(data)
    if not t then return false, 'invalid_request' end
    local payload = S.BuildLocationPayload(src, data.label)
    if not payload then return false, 'location_unavailable' end
    return S.SendMessage(cid, number, t, 'location', '', payload)
end)

-- Groups -----------------------------------------------------------------
register('groupCreate', 'group', function(src, cid, number, data)
    data = type(data) == 'table' and data or {}
    return S.WithLock(cid, 'group', S.CreateGroup, cid, number, data.name, data.numbers)
end)

register('groupAdd', 'group', function(src, cid, number, data)
    data = type(data) == 'table' and data or {}
    return S.WithLock(cid, 'group', S.GroupAdd, cid, number, data.conversationId, data.number)
end)

register('groupRemove', 'group', function(src, cid, number, data)
    data = type(data) == 'table' and data or {}
    return S.WithLock(cid, 'group', S.GroupRemove, cid, data.conversationId, data.number)
end)

register('groupLeave', 'group', function(src, cid, number, conversationId)
    return S.WithLock(cid, 'group', S.LeaveGroup, cid, number, conversationId)
end)

-- Calls ------------------------------------------------------------------
register('dial', 'call', function(src, cid, number, raw)
    if isDead(src) then return false, 'unavailable' end
    return S.StartCall(cid, number, src, raw)
end)
register('answer', nil, function(src, cid) return S.AnswerCall(cid) end)
register('decline', nil, function(src, cid) return S.DeclineCall(cid) end)
register('hangup', nil, function(src, cid) return S.HangupCall(cid) end)
register('calls', 'read', function(src, cid) return true, { calls = S.ListCalls(cid) } end)

-- Adverts ----------------------------------------------------------------
register('adverts', 'read', function() return true, { adverts = S.ListAdverts() } end)

register('advertPost', nil, function(src, cid, number, text)
    local ok, result, extra = S.PostAdvert(src, cid, number, text)
    if not ok then return false, result, extra end
    return true, { adverts = S.ListAdverts(), fee = result.fee }
end)

-- Emergency --------------------------------------------------------------
register('emergency', 'emergency', function(src, cid, number, data)
    data = type(data) == 'table' and data or {}
    local ok, message = S.SendEmergency(src, cid, tostring(data.service or ''), data.details)
    if not ok then return false, 'dispatch_failed', message end
    return true, { message = message }
end)

-- Services (Service Marketplace) ------------------------------------------
-- The phone only forwards to the SOURCE OWNER through a registered adapter; see docs/SERVICES.md.
register('services', 'read', function(src, cid)
    return S.Services:ListServices(cid)
end)

register('serviceStatus', 'read', function(src, cid, number, serviceId)
    local ok, status = S.Services:Status(cid, tostring(serviceId or ''))
    if not ok then return false, status end
    return true, { status = status }
end)

register('serviceRequest', nil, function(src, cid, number, data)
    if type(data) ~= 'table' then return false, 'invalid_request' end
    local ok, status, current = S.Services:Request(src, cid, tostring(data.serviceId or ''), data.fields)
    if not ok then return false, status, current end
    return true, { status = status }
end)

register('serviceCancel', nil, function(src, cid, number, data)
    if type(data) ~= 'table' then return false, 'invalid_request' end
    local ok, status = S.Services:Cancel(src, cid, tostring(data.serviceId or ''), data.ref)
    if not ok then return false, status end
    return true, { status = status }
end)

-- Maintenance -------------------------------------------------------------
CreateThread(function()
    if not S.AwaitSchema() then return end
    while true do
        pcall(S.PurgeExpiredAdverts)
        local days = tonumber(Config.Calls.historyRetentionDays) or 0
        if days > 0 then
            pcall(function() MySQL.update.await('DELETE FROM cm_phone_calls WHERE started_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? DAY)', { days }) end)
        end
        local keep = tonumber(Config.Messages.retentionDays) or 0
        if keep > 0 then
            pcall(function() MySQL.update.await('DELETE FROM cm_phone_messages WHERE created_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? DAY)', { keep }) end)
        end
        Wait(3600000)
    end
end)
