local RESOURCE = GetCurrentResourceName()

local function normalizeCharacterId(value)
    local text = tostring(value or '')
    if text == '' or #text > 64 or not text:match('^%d+$') then return nil end
    return text
end

local function cleanReason(value)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return text:sub(1, 255)
end

local function actorContext(actorCharacterId, permissionKey)
    local characterId = normalizeCharacterId(actorCharacterId)
    if not characterId then return nil, 'invalid_actor' end
    local decision = exports[RESOURCE]:GetPermissionDecision(characterId, permissionKey)
    if type(decision) ~= 'table' or decision.allowed ~= true then
        return nil, (decision and decision.reason) or 'not_authorized'
    end
    local membership = exports[RESOURCE]:GetGangForCharacter(characterId)
    if not membership or membership.enabled ~= true then return nil, 'gang_disabled' end
    return { characterId = characterId, gangId = membership.gangId }
end

local function logActivity(gangId, action, actorCharacterId, targetCharacterId, detail)
    MySQL.insert.await([[
        INSERT INTO cm_gang_activity (event_uid, gang_id, action, actor_character_id, target_character_id, detail)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        ('%s:%s:%d:%d'):format(RESOURCE, action, os.time(), math.random(100000, 999999)),
        gangId, action, actorCharacterId, targetCharacterId, detail and json.encode(detail) or nil,
    })
end

-- Server-authoritative check used by invites.lua before both invite
-- creation and invite acceptance -- never trust a hidden dashboard button.
exports('IsCharacterBlacklistedFromGang', function(gangId, characterId)
    gangId = tostring(gangId or '')
    characterId = normalizeCharacterId(characterId)
    if not Config.IsFixedGangId(gangId) or not characterId then return false end
    local row = MySQL.scalar.await([[
        SELECT 1 FROM cm_gang_blacklist
        WHERE gang_id = ? AND character_id = ? AND (expires_at IS NULL OR expires_at > NOW())
        LIMIT 1
    ]], { gangId, characterId })
    return row ~= nil
end)

exports('AddGangBlacklist', function(actorCharacterId, targetCharacterId, reason, expiresInSeconds)
    local actor, reason1 = actorContext(actorCharacterId, 'gang.blacklist')
    if not actor then return false, reason1 end
    local targetId = normalizeCharacterId(targetCharacterId)
    if not targetId then return false, 'invalid_target' end
    if targetId == actor.characterId then return false, 'cannot_modify_self' end

    local characterExists = MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { targetId })
    if characterExists == nil then return false, 'character_not_found' end

    local existingMembership = exports[RESOURCE]:GetGangForCharacter(targetId)
    if existingMembership and existingMembership.gangId == actor.gangId then
        -- Leader/hierarchy protection mirrors RemoveMember's rules; a
        -- blacklist-then-kick of an in-gang target still goes through the
        -- normal hierarchy-safe removal path first.
        local removed, removeReason = exports[RESOURCE]:RemoveMember(actor.characterId, targetId)
        if not removed then return false, removeReason end
    end

    local cleanedReason = cleanReason(reason)
    local ttl = math.floor(tonumber(expiresInSeconds) or 0)
    local expiresClause = ttl > 0 and ('DATE_ADD(NOW(), INTERVAL %d SECOND)'):format(math.min(ttl, 31536000)) or 'NULL'
    local nameSnapshot = MySQL.scalar.await(
        'SELECT TRIM(CONCAT(first_name, \' \', last_name)) FROM characters WHERE id = ? LIMIT 1', { targetId })

    MySQL.insert.await(([[
        INSERT INTO cm_gang_blacklist (gang_id, character_id, character_name_snapshot, reason, blacklisted_by, expires_at)
        VALUES (?, ?, ?, ?, ?, %s)
        ON DUPLICATE KEY UPDATE reason = VALUES(reason), blacklisted_by = VALUES(blacklisted_by),
            character_name_snapshot = VALUES(character_name_snapshot), expires_at = VALUES(expires_at), created_at = NOW()
    ]]):format(expiresClause), {
        actor.gangId, targetId, nameSnapshot and tostring(nameSnapshot):sub(1, 96) or nil,
        cleanedReason ~= '' and cleanedReason or nil, actor.characterId,
    })

    logActivity(actor.gangId, 'member_blacklisted', actor.characterId, targetId, { reason = cleanedReason })
    return true
end)

exports('RemoveGangBlacklist', function(actorCharacterId, targetCharacterId)
    local actor, reason = actorContext(actorCharacterId, 'gang.manage_blacklist')
    if not actor then return false, reason end
    local targetId = normalizeCharacterId(targetCharacterId)
    if not targetId then return false, 'invalid_target' end

    local removed = MySQL.update.await(
        'DELETE FROM cm_gang_blacklist WHERE gang_id = ? AND character_id = ?', { actor.gangId, targetId })
    if tonumber(removed) ~= 1 then return false, 'not_blacklisted' end

    logActivity(actor.gangId, 'blacklist_removed', actor.characterId, targetId, {})
    return true
end)

exports('GetGangBlacklist', function(actorCharacterId)
    local actor, reason = actorContext(actorCharacterId, 'gang.blacklist')
    if not actor then
        actor, reason = actorContext(actorCharacterId, 'gang.manage_blacklist')
        if not actor then return nil, reason end
    end
    local rows = MySQL.query.await([[
        SELECT character_id, character_name_snapshot, reason, blacklisted_by, created_at, expires_at
        FROM cm_gang_blacklist WHERE gang_id = ? ORDER BY created_at DESC
    ]], { actor.gangId }) or {}
    local result = {}
    for _, row in ipairs(rows) do
        result[#result + 1] = {
            characterId = tostring(row.character_id),
            name = row.character_name_snapshot and tostring(row.character_name_snapshot) or nil,
            reason = row.reason and tostring(row.reason) or nil,
            blacklistedBy = row.blacklisted_by and tostring(row.blacklisted_by) or nil,
            createdAt = tostring(row.created_at or ''),
            expiresAt = row.expires_at and tostring(row.expires_at) or nil,
        }
    end
    return result
end)

lib.callback.register('cm-gang:server:dashboardBlacklistAction', function(source, request)
    request = type(request) == 'table' and request or {}
    local characterId
    do
        local ok, value = pcall(function() return exports['cm-playerdata']:GetCharacterId(tonumber(source)) end)
        characterId = ok and value and tostring(value):match('^%d+$') and tostring(value) or nil
    end
    if not characterId then return { ok = false, reason = 'character_not_loaded' } end
    local action = tostring(request.action or '')
    if action == 'list' then
        local list, reason = exports[RESOURCE]:GetGangBlacklist(characterId)
        return { ok = list ~= nil, reason = list == nil and reason or nil, entries = list or {} }
    elseif action == 'add' then
        local ok, reason = exports[RESOURCE]:AddGangBlacklist(characterId, request.targetCharacterId, request.reason, request.expiresInSeconds)
        return { ok = ok == true, reason = ok == true and nil or reason }
    elseif action == 'remove' then
        local ok, reason = exports[RESOURCE]:RemoveGangBlacklist(characterId, request.targetCharacterId)
        return { ok = ok == true, reason = ok == true and nil or reason }
    end
    return { ok = false, reason = 'invalid_action' }
end)
