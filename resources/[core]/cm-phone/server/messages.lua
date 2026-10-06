-- Persistent SMS: direct and small group conversations.
-- Sender identity always comes from the caller's session (character id + its own phone number).
-- Conversations are only ever read/written through a membership row for that character.
local S = CMPhone.Server
local Config = CMPhone.Config
local M = Config.Messages

local SYSTEM_SENDER = 'system'

local function convId(value)
    local id = math.floor(tonumber(value) or 0)
    if id <= 0 then return nil end
    return id
end

local function directKey(a, b)
    a, b = tostring(a), tostring(b)
    if a > b then a, b = b, a end
    return a .. '|' .. b
end

local function isMember(cid, id)
    local row = MySQL.single.await('SELECT last_read_message_id FROM cm_phone_conversation_members WHERE conversation_id = ? AND character_id = ? LIMIT 1', { id, cid })
    return row ~= nil
end
S.IsConversationMember = isMember

local function members(id)
    return MySQL.query.await([[SELECT m.character_id, n.phone_number FROM cm_phone_conversation_members m
        LEFT JOIN cm_phone_numbers n ON n.character_id = m.character_id WHERE m.conversation_id = ?]], { id }) or {}
end

local function preview(kind, body)
    if kind == 'location' then return 'Shared a location' end
    body = tostring(body or '')
    if #body > 60 then body = body:sub(1, 57) .. '...' end
    return body
end

-- Inserts a message and advances the conversation pointer. Returns message id.
local function insertMessage(id, senderCid, senderNumber, kind, body, payload)
    -- No nil values inside parameter arrays (oxmysql positional params): NULLs use dedicated statements.
    local encoded = payload and S.json(payload) or ''
    local messageId
    if senderCid then
        messageId = MySQL.insert.await(
            "INSERT INTO cm_phone_messages (conversation_id, sender_character_id, sender_number, kind, body, payload) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''))",
            { id, senderCid, senderNumber, kind, body or '', encoded })
    else
        messageId = MySQL.insert.await(
            "INSERT INTO cm_phone_messages (conversation_id, sender_character_id, sender_number, kind, body, payload) VALUES (?, NULL, ?, ?, ?, NULLIF(?, ''))",
            { id, senderNumber, kind, body or '', encoded })
    end
    if not messageId then return nil end
    MySQL.update.await('UPDATE cm_phone_conversations SET last_message_id = ?, last_message_at = CURRENT_TIMESTAMP WHERE id = ?', { messageId, id })
    if senderCid then
        MySQL.update.await('UPDATE cm_phone_conversation_members SET last_read_message_id = GREATEST(last_read_message_id, ?) WHERE conversation_id = ? AND character_id = ?',
            { messageId, id, senderCid })
    end
    return messageId
end

local function deliver(id, messageId, senderCid, senderNumber, kind, body, convName, convKind)
    for _, m in ipairs(members(id)) do
        local memberCid = tostring(m.character_id)
        if memberCid ~= tostring(senderCid or '') then
            local src = S.SourceOf(memberCid)
            if src then
                S.Emit(src, 'cm-phone:client:message', {
                    conversationId = id, id = messageId, from = senderNumber, kind = kind,
                    preview = preview(kind, body), group = convKind == 'group' and (convName or 'Group') or nil,
                })
            end
        end
    end
end

-- Get or create the direct conversation between two characters (concurrency-safe via UNIQUE direct_key).
local function directConversation(cidA, cidB)
    local key = directKey(cidA, cidB)
    MySQL.query.await("INSERT IGNORE INTO cm_phone_conversations (kind, direct_key, creator_character_id) VALUES ('direct', ?, ?)", { key, cidA })
    local row = MySQL.single.await('SELECT id FROM cm_phone_conversations WHERE direct_key = ? LIMIT 1', { key })
    if not row then return nil end
    MySQL.query.await('INSERT IGNORE INTO cm_phone_conversation_members (conversation_id, character_id) VALUES (?, ?), (?, ?)', { row.id, cidA, row.id, cidB })
    return row.id
end

local function validBody(kind, body)
    if kind == 'location' then return '' end
    return S.cleanText(body, M.textMax, true)
end

-- Core send. `target` is either { number = '555-0100' } (direct) or { conversationId = n }.
-- Returns true, { conversationId, id } or false, reason. Never reveals whether a block caused a failure.
function S.SendMessage(senderCid, senderNumber, target, kind, body, payload)
    if type(target) ~= 'table' then return false, 'invalid_request' end
    kind = kind == 'location' and 'location' or 'text'
    local text = validBody(kind, body)
    if kind == 'text' and not text then return false, 'invalid_message' end
    if kind == 'location' and type(payload) ~= 'table' then return false, 'invalid_request' end

    local id, convName, convKind
    if target.conversationId ~= nil then
        id = convId(target.conversationId)
        if not id or not isMember(senderCid, id) then return false, 'not_found' end
        local conv = MySQL.single.await('SELECT kind, name, direct_key FROM cm_phone_conversations WHERE id = ? LIMIT 1', { id })
        if not conv then return false, 'not_found' end
        -- System threads (city notices) are receive-only.
        if type(conv.direct_key) == 'string' and conv.direct_key:sub(1, 7) == 'system|' then return false, 'forbidden' end
        convKind, convName = conv.kind, conv.name
        if convKind == 'direct' then
            for _, m in ipairs(members(id)) do
                if tostring(m.character_id) ~= tostring(senderCid) and S.IsBlocked(tostring(m.character_id), senderNumber) then
                    return false, 'undeliverable'
                end
            end
        end
    else
        local number = S.NormalizeNumber(target.number)
        if not number then return false, 'invalid_recipient' end
        if number == senderNumber then return false, 'invalid_recipient' end
        local targetCid = S.CidByNumber(number)
        if not targetCid or targetCid == tostring(senderCid) then return false, 'invalid_recipient' end
        if S.IsBlocked(targetCid, senderNumber) then return false, 'undeliverable' end
        id = directConversation(tostring(senderCid), targetCid)
        if not id then return false, 'internal_error' end
        convKind = 'direct'
    end

    local messageId = insertMessage(id, tostring(senderCid), senderNumber, kind, text, payload)
    if not messageId then return false, 'internal_error' end
    deliver(id, messageId, senderCid, senderNumber, kind, text, convName, convKind)
    return true, { conversationId = id, id = messageId }
end

-- Trusted-system send (no sender character). Used by SendSystemMessage.
function S.SendSystem(targetCid, title, body, payload)
    title = S.cleanText(tostring(title or ''), 32) or 'City'
    local text = S.cleanText(body, M.textMax, true)
    if not text then return false, 'invalid_message' end
    -- System messages live in a direct conversation between the character and a per-title sender key.
    local key = 'system|' .. tostring(targetCid) .. '|' .. title:lower()
    MySQL.query.await("INSERT IGNORE INTO cm_phone_conversations (kind, direct_key, name) VALUES ('direct', ?, ?)", { key, title })
    local row = MySQL.single.await('SELECT id FROM cm_phone_conversations WHERE direct_key = ? LIMIT 1', { key })
    if not row then return false, 'internal_error' end
    MySQL.query.await('INSERT IGNORE INTO cm_phone_conversation_members (conversation_id, character_id) VALUES (?, ?)', { row.id, tostring(targetCid) })
    local messageId = insertMessage(row.id, nil, SYSTEM_SENDER, 'system', text, payload)
    if not messageId then return false, 'internal_error' end
    deliver(row.id, messageId, nil, title, 'system', text, title, 'group')
    return true, { conversationId = row.id, id = messageId }
end

function S.ListConversations(cid)
    local rows = MySQL.query.await([[SELECT c.id, c.kind, c.name, c.direct_key, UNIX_TIMESTAMP(c.last_message_at) AS last_at,
            lm.body AS last_body, lm.kind AS last_kind, lm.sender_number AS last_sender,
            (SELECT COUNT(*) FROM cm_phone_messages x WHERE x.conversation_id = c.id AND x.id > mem.last_read_message_id
                AND (x.sender_character_id IS NULL OR x.sender_character_id <> ?)) AS unread,
            (SELECT n.phone_number FROM cm_phone_conversation_members om
                JOIN cm_phone_numbers n ON n.character_id = om.character_id
                WHERE om.conversation_id = c.id AND om.character_id <> ? LIMIT 1) AS other_number
        FROM cm_phone_conversation_members mem
        JOIN cm_phone_conversations c ON c.id = mem.conversation_id
        LEFT JOIN cm_phone_messages lm ON lm.id = c.last_message_id
        WHERE mem.character_id = ? AND (c.last_message_id IS NOT NULL OR c.kind = 'group')
        ORDER BY c.last_message_at DESC, c.id DESC LIMIT ?]], { cid, cid, cid, M.conversationListMax }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local system = type(r.direct_key) == 'string' and r.direct_key:sub(1, 7) == 'system|'
        out[#out + 1] = {
            id = r.id, kind = system and 'system' or r.kind, name = r.name,
            number = (r.kind == 'direct' and not system) and r.other_number or nil,
            lastAt = tonumber(r.last_at) or 0, unread = tonumber(r.unread) or 0,
            preview = preview(r.last_kind, r.last_body), lastSender = r.last_sender,
        }
    end
    return out
end

function S.UnreadTotal(cid)
    return tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM cm_phone_messages x
        JOIN cm_phone_conversation_members mem ON mem.conversation_id = x.conversation_id AND mem.character_id = ?
        WHERE x.id > mem.last_read_message_id AND (x.sender_character_id IS NULL OR x.sender_character_id <> ?)]], { cid, cid })) or 0
end

-- Opens a conversation the caller belongs to; marks it read.
function S.OpenConversation(cid, rawId, beforeId)
    local id = convId(rawId)
    if not id or not isMember(cid, id) then return false, 'not_found' end
    local conv = MySQL.single.await('SELECT id, kind, name, direct_key, creator_character_id FROM cm_phone_conversations WHERE id = ? LIMIT 1', { id })
    if not conv then return false, 'not_found' end
    local before = convId(beforeId)

    local rows
    if before then
        rows = MySQL.query.await([[SELECT id, sender_character_id, sender_number, kind, body, payload, UNIX_TIMESTAMP(created_at) AS at
            FROM cm_phone_messages WHERE conversation_id = ? AND id < ? ORDER BY id DESC LIMIT ?]], { id, before, M.historyPage }) or {}
    else
        rows = MySQL.query.await([[SELECT id, sender_character_id, sender_number, kind, body, payload, UNIX_TIMESTAMP(created_at) AS at
            FROM cm_phone_messages WHERE conversation_id = ? ORDER BY id DESC LIMIT ?]], { id, M.historyPage }) or {}
    end
    local messages = {}
    for i = #rows, 1, -1 do
        local r = rows[i]
        messages[#messages + 1] = {
            id = r.id, from = r.sender_number, mine = r.sender_character_id ~= nil and tostring(r.sender_character_id) == tostring(cid),
            kind = r.kind, body = r.body, payload = S.decode(r.payload), at = tonumber(r.at) or 0,
        }
    end

    local info = { id = id, kind = conv.kind, name = conv.name, isOwner = tostring(conv.creator_character_id or '') == tostring(cid), members = {} }
    if type(conv.direct_key) == 'string' and conv.direct_key:sub(1, 7) == 'system|' then info.kind = 'system' end
    for _, m in ipairs(members(id)) do
        local memberCid = tostring(m.character_id)
        if memberCid ~= tostring(cid) then
            info.members[#info.members + 1] = m.phone_number
            if conv.kind == 'direct' then info.number = m.phone_number end
        end
    end

    if not before then S.MarkRead(cid, id) end
    return true, { conversation = info, messages = messages, more = #rows >= M.historyPage }
end

function S.MarkRead(cid, rawId)
    local id = convId(rawId)
    if not id then return false, 'not_found' end
    local changed = MySQL.update.await([[UPDATE cm_phone_conversation_members mem
        JOIN cm_phone_conversations c ON c.id = mem.conversation_id
        SET mem.last_read_message_id = GREATEST(mem.last_read_message_id, COALESCE(c.last_message_id, 0))
        WHERE mem.conversation_id = ? AND mem.character_id = ?]], { id, cid })
    return (tonumber(changed) or 0) >= 0
end

-- Groups ---------------------------------------------------------------------

local function systemLine(id, text)
    local messageId = insertMessage(id, nil, SYSTEM_SENDER, 'system', text, nil)
    return messageId
end

function S.CreateGroup(cid, ownNumber, name, numbers)
    name = S.cleanText(name, M.groupNameMax)
    if not name then return false, 'invalid_name' end
    if type(numbers) ~= 'table' then return false, 'invalid_request' end

    local seen, unique = { [ownNumber] = true }, {}
    for _, raw in ipairs(numbers) do
        local number = S.NormalizeNumber(raw)
        if not number then return false, 'invalid_number' end
        if not seen[number] then
            seen[number] = true
            unique[#unique + 1] = number
        end
    end
    if #unique + 1 > M.groupMembersMax then return false, 'group_limit' end
    local targets = {}
    for _, number in ipairs(unique) do
        local targetCid = S.CidByNumber(number)
        if not targetCid then return false, 'invalid_recipient' end
        targets[#targets + 1] = targetCid
    end
    if #targets < 1 then return false, 'invalid_recipient' end

    local id = MySQL.insert.await("INSERT INTO cm_phone_conversations (kind, name, creator_character_id) VALUES ('group', ?, ?)", { name, cid })
    if not id then return false, 'internal_error' end
    MySQL.query.await('INSERT IGNORE INTO cm_phone_conversation_members (conversation_id, character_id) VALUES (?, ?)', { id, cid })
    for _, targetCid in ipairs(targets) do
        MySQL.query.await('INSERT IGNORE INTO cm_phone_conversation_members (conversation_id, character_id) VALUES (?, ?)', { id, targetCid })
    end
    local messageId = systemLine(id, ('%s created the group'):format(ownNumber))
    if messageId then MySQL.update.await('UPDATE cm_phone_conversation_members SET last_read_message_id = ? WHERE conversation_id = ? AND character_id = ?', { messageId, id, cid }) end
    deliver(id, messageId or 0, cid, ownNumber, 'system', ('Added you to %s'):format(name), name, 'group')
    return true, { conversationId = id }
end

local function groupInfo(cid, rawId)
    local id = convId(rawId)
    if not id or not isMember(cid, id) then return nil end
    local conv = MySQL.single.await("SELECT id, name, creator_character_id FROM cm_phone_conversations WHERE id = ? AND kind = 'group' LIMIT 1", { id })
    return conv
end

function S.GroupAdd(cid, ownNumber, rawId, rawNumber)
    local conv = groupInfo(cid, rawId)
    if not conv then return false, 'not_found' end
    if tostring(conv.creator_character_id) ~= tostring(cid) then return false, 'forbidden' end
    local number = S.NormalizeNumber(rawNumber)
    if not number then return false, 'invalid_number' end
    local targetCid = S.CidByNumber(number)
    if not targetCid then return false, 'invalid_recipient' end
    if #members(conv.id) >= M.groupMembersMax then return false, 'group_limit' end
    if isMember(targetCid, conv.id) then return false, 'already_member' end
    MySQL.query.await('INSERT IGNORE INTO cm_phone_conversation_members (conversation_id, character_id) VALUES (?, ?)', { conv.id, targetCid })
    systemLine(conv.id, ('%s was added'):format(number))
    local src = S.SourceOf(targetCid)
    if src then S.Emit(src, 'cm-phone:client:message', { conversationId = conv.id, id = 0, from = ownNumber, kind = 'system', preview = 'Added you to ' .. tostring(conv.name), group = conv.name }) end
    return true
end

function S.GroupRemove(cid, rawId, rawNumber)
    local conv = groupInfo(cid, rawId)
    if not conv then return false, 'not_found' end
    if tostring(conv.creator_character_id) ~= tostring(cid) then return false, 'forbidden' end
    local number = S.NormalizeNumber(rawNumber)
    local targetCid = number and S.CidByNumber(number)
    if not targetCid or targetCid == tostring(cid) or not isMember(targetCid, conv.id) then return false, 'not_found' end
    MySQL.update.await('DELETE FROM cm_phone_conversation_members WHERE conversation_id = ? AND character_id = ?', { conv.id, targetCid })
    systemLine(conv.id, ('%s was removed'):format(number))
    return true
end

function S.LeaveGroup(cid, ownNumber, rawId)
    local conv = groupInfo(cid, rawId)
    if not conv then return false, 'not_found' end
    MySQL.update.await('DELETE FROM cm_phone_conversation_members WHERE conversation_id = ? AND character_id = ?', { conv.id, cid })
    local remaining = MySQL.query.await('SELECT character_id FROM cm_phone_conversation_members WHERE conversation_id = ? ORDER BY joined_at ASC, character_id ASC', { conv.id }) or {}
    if #remaining == 0 then
        MySQL.update.await('DELETE FROM cm_phone_messages WHERE conversation_id = ?', { conv.id })
        MySQL.update.await('DELETE FROM cm_phone_conversations WHERE id = ?', { conv.id })
        return true
    end
    if tostring(conv.creator_character_id) == tostring(cid) then
        MySQL.update.await('UPDATE cm_phone_conversations SET creator_character_id = ? WHERE id = ?', { remaining[1].character_id, conv.id })
    end
    systemLine(conv.id, ('%s left'):format(ownNumber))
    return true
end

-- Location payload built from server-observed position; label is cosmetic client text.
function S.BuildLocationPayload(src, label)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    if not coords or (math.abs(coords.x) < 0.01 and math.abs(coords.y) < 0.01) then return nil end
    return {
        x = math.floor(coords.x * 10 + 0.5) / 10,
        y = math.floor(coords.y * 10 + 0.5) / 10,
        label = S.cleanText(label or '', M.locationLabelMax) or 'Shared location',
    }
end
