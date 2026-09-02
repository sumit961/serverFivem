local RESOURCE = GetCurrentResourceName()
local PLAYERDATA = 'cm-playerdata'
local ACTION = 'gang_invite'
local responseLocks = {}
local inviteCooldowns = {}
local sourceCharacters = {}

local function characterIdForSource(src)
    src = tonumber(src)
    if not src then return nil end
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(src) end)
    local text = ok and tostring(value or '') or ''
    if text == '' or #text > 64 or not text:match('^%d+$') then return nil end
    sourceCharacters[src] = text
    return text
end

local function sourceForCharacter(characterId)
    local ok, value = pcall(function()
        return exports[PLAYERDATA]:GetSourceByCharId(tonumber(characterId))
    end)
    value = ok and tonumber(value) or nil
    return value and GetPlayerName(value) and value or nil
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-gang:client:notify', src, message, kind or 'error')
end

local function hasOrganizationMembership(src, characterId)
    if exports[RESOURCE]:GetGangForCharacter(characterId) then return true end
    local ok, metadata = pcall(function() return exports[PLAYERDATA]:GetMetadata(tonumber(src)) end)
    metadata = ok and type(metadata) == 'table' and metadata or {}
    for _, key in ipairs({ 'organization_id', 'organizationId', 'organization', 'org_id', 'orgId', 'org' }) do
        local value = metadata[key]
        if value ~= nil and value ~= false and tostring(value) ~= '' and tostring(value) ~= '0' then return true end
    end
    local stateOk, state = pcall(function() return Player(tonumber(src)).state end)
    state = stateOk and state or nil
    if state then
        for _, key in ipairs({ 'organizationId', 'organization_id', 'orgId', 'org_id' }) do
            local value = state[key]
            if value ~= nil and value ~= false and tostring(value) ~= '' and tostring(value) ~= '0' then return true end
        end
    end
    return false
end

local function validatePhysical(actorSrc, targetSrc)
    actorSrc, targetSrc = tonumber(actorSrc), tonumber(targetSrc)
    if not actorSrc or not targetSrc or actorSrc == targetSrc then return false, 'invalid_target' end
    if not GetPlayerName(actorSrc) or not GetPlayerName(targetSrc) then return false, 'player_offline' end
    if GetPlayerRoutingBucket(actorSrc) ~= GetPlayerRoutingBucket(targetSrc) then return false, 'different_bucket' end
    local actorPed, targetPed = GetPlayerPed(actorSrc), GetPlayerPed(targetSrc)
    if actorPed == 0 or targetPed == 0 or not DoesEntityExist(actorPed) or not DoesEntityExist(targetPed) then
        return false, 'entity_unavailable'
    end
    local distance = #(GetEntityCoords(actorPed) - GetEntityCoords(targetPed))
    if distance > (tonumber(Config.Security.interactionDistance) or 3.0) then return false, 'too_far' end
    return true
end

local function actorDecision(src)
    local characterId = characterIdForSource(src)
    if not characterId then return nil, 'character_not_loaded' end
    local decision = exports[RESOURCE]:GetPermissionDecision(characterId, 'gang.invite')
    if type(decision) ~= 'table' or decision.allowed ~= true then
        return nil, decision and decision.reason or 'not_authorized'
    end
    local membership = exports[RESOURCE]:GetGangForCharacter(characterId)
    if not membership or membership.enabled ~= true then return nil, 'gang_disabled' end
    return { source = tonumber(src), characterId = characterId, membership = membership }
end

local function lowestEntryRank(gangId)
    local gang = exports[RESOURCE]:GetGang(gangId)
    local selected
    for _, rank in pairs(gang and gang.ranksById or {}) do
        if not rank.isLeaderRank and (not selected or rank.tier < selected.tier) then selected = rank end
    end
    return selected
end

local function safeName(src)
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterFullName(src) end)
    return ok and value and tostring(value) or 'A gang member'
end

local function uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return template:gsub('[xy]', function(char)
        local value = char == 'x' and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(value)
    end)
end

local function logInvite(gangId, action, actorId, targetId, detail)
    MySQL.insert.await([[
        INSERT INTO cm_gang_activity
            (event_uid, gang_id, action, actor_character_id, target_character_id, detail)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        ('%s:%s:%d:%d'):format(RESOURCE, action, os.time(), math.random(100000, 999999)),
        gangId, action, actorId, targetId, detail and json.encode(detail) or nil,
    })
end

local friendly = {
    character_not_loaded = 'Character data is not loaded.', not_authorized = 'Your rank cannot invite gang members.',
    no_permission = 'Your rank cannot invite gang members.', gang_disabled = 'Your gang is disabled.',
    invalid_target = 'That player is not a valid target.', player_offline = 'That player is no longer online.',
    character_changed = 'A character changed during the invitation. Try again.',
    different_bucket = 'That player is in another instance.', entity_unavailable = 'That player is not available.',
    too_far = 'That player is too far away.', target_in_gang = 'You are already in an organization.',
    target_in_org = 'You are already in an organization.',
    duplicate_invite = 'That character already has a pending gang invitation.', rate_limited = 'Please wait before inviting again.',
    no_entry_rank = 'This gang has no valid entry rank.', expired = 'That invitation has expired.',
    target_blacklisted = 'That character is blacklisted from this gang.',
}

local function targetBlacklisted(gangId, characterId)
    local ok, blacklisted = pcall(function()
        return exports[RESOURCE]:IsCharacterBlacklistedFromGang(gangId, characterId)
    end)
    return ok and blacklisted == true
end

local function createInvite(src, targetSrc)
    local actor, reason = actorDecision(src)
    if not actor then return false, reason end
    local physical
    physical, reason = validatePhysical(src, targetSrc)
    if not physical then return false, reason end
    local targetId = characterIdForSource(targetSrc)
    if not targetId or targetId == actor.characterId then return false, 'invalid_target' end
    if targetBlacklisted(actor.membership.gangId, targetId) then return false, 'target_blacklisted' end
    local now = GetGameTimer()
    if (inviteCooldowns[actor.characterId] or 0) > now then return false, 'rate_limited' end
    inviteCooldowns[actor.characterId] = now + ((tonumber(Config.Security.inviteCooldownSeconds) or 10) * 1000)
    -- Expire this target's stale row immediately. The database unique slot is
    -- status-based, so waiting for the 30-second janitor would otherwise make
    -- a just-expired invitation look like a duplicate for a short period.
    MySQL.update.await([[UPDATE cm_gang_invites SET status='expired', resolved_at=NOW()
        WHERE target_character_id=? AND status='pending' AND expires_at<=NOW()]], { targetId })
    local pending = MySQL.scalar.await([[
        SELECT 1 FROM cm_gang_invites
        WHERE target_character_id = ? AND status = 'pending' AND expires_at > NOW() LIMIT 1
    ]], { targetId })
    if pending then return false, 'duplicate_invite' end
    local rank = lowestEntryRank(actor.membership.gangId)
    if not rank then return false, 'no_entry_rank' end
    local inviteId = uuid()
    local expiry = math.max(30, math.min(120, tonumber(Config.Security.inviteExpirySeconds) or 60))
    local inserted = MySQL.update.await(([=[
        INSERT IGNORE INTO cm_gang_invites
            (invite_id, gang_id, actor_character_id, target_character_id, entry_rank_id, expires_at)
        VALUES (?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL %d SECOND))
    ]=]):format(expiry), { inviteId, actor.membership.gangId, actor.characterId, targetId, rank.id })
    if tonumber(inserted) ~= 1 then return false, 'duplicate_invite' end
    logInvite(actor.membership.gangId, 'invite_sent', actor.characterId, targetId, { rankId = rank.id })
    TriggerClientEvent('cm-gang:client:inviteReceived', targetSrc, {
        inviteId = inviteId,
        gangName = actor.membership.displayName,
        invitedBy = safeName(src),
        expiresIn = expiry,
    })
    return true
end

lib.callback.register('cm-gang:server:canInviteTarget', function(src, targetSrc)
    local actor = actorDecision(src)
    if not actor then return false end
    if validatePhysical(src, targetSrc) ~= true then return false end
    local targetId = characterIdForSource(targetSrc)
    return targetId ~= nil and targetId ~= actor.characterId
end)


lib.callback.register('cm-gang:server:getTargetActions', function(src, targetSrc)
    local actorCharacterId = characterIdForSource(src)
    local actorMembership = actorCharacterId and exports[RESOURCE]:GetGangForCharacter(actorCharacterId) or nil
    local result = { gangMember = actorMembership ~= nil and actorMembership.enabled == true, invite = false, search = false, robCash = false, robItems = false }
    local actor = actorDecision(src)
    if actor and validatePhysical(src, targetSrc) == true then
        local targetId = characterIdForSource(targetSrc)
        result.invite = targetId ~= nil and targetId ~= actor.characterId
    end
    local robbery = exports[RESOURCE]:ValidateRobberyTarget(src, targetSrc, 'gang.rob_cash')
    result.robCash = robbery ~= nil
    result.search = exports[RESOURCE]:ValidateRobberyTarget(src, targetSrc, 'gang.search') ~= nil
    result.robItems = exports[RESOURCE]:ValidateRobberyTarget(src, targetSrc, 'gang.rob_items') ~= nil
    return result
end)

local function registerAction()
    if GetResourceState(PLAYERDATA) ~= 'started' then return end
    for _, actionId in ipairs({ ACTION, 'gang_rob_cash', 'gang_search', 'gang_rob_player', 'gang_rob_items' }) do
        TriggerEvent('cm-playerdata:server:unregisterInteractionAction', actionId)
    end
    TriggerEvent('cm-playerdata:server:registerInteractionAction', {
        id = ACTION,
        event = 'cm-gang:server:gMenuAction',
        resource = RESOURCE,
        allowDeadTarget = false,
    })
    TriggerEvent('cm-playerdata:server:registerInteractionAction', {
        id = 'gang_rob_cash',
        event = 'cm-gang:server:gMenuAction',
        resource = RESOURCE,
        allowDeadTarget = true,
    })
    TriggerEvent('cm-playerdata:server:registerInteractionAction', {
        id = 'gang_search', event = 'cm-gang:server:gMenuAction', resource = RESOURCE, allowDeadTarget = true,
    })
    TriggerEvent('cm-playerdata:server:registerInteractionAction', {
        id = 'gang_rob_player', event = 'cm-gang:server:gMenuAction', resource = RESOURCE, allowDeadTarget = true,
    })
    TriggerEvent('cm-playerdata:server:registerInteractionAction', {
        id = 'gang_rob_items', event = 'cm-gang:server:gMenuAction', resource = RESOURCE, allowDeadTarget = true,
    })
end

AddEventHandler('cm-gang:server:gMenuAction', function(src, targetSrc, actionId)
    if actionId == 'gang_rob_cash' then
        TriggerClientEvent('cm-gang:client:requestRobCash', tonumber(src), tonumber(targetSrc))
        return
    end
    if actionId == 'gang_rob_items' or actionId == 'gang_rob_player' then
        TriggerClientEvent('cm-gang:client:requestRandomItemRobbery', tonumber(src), tonumber(targetSrc))
        return
    end
    if actionId == 'gang_search' then
        TriggerClientEvent('cm-gang:client:requestRobberyInventory', tonumber(src), tonumber(targetSrc), actionId ~= 'gang_search' and 'take' or 'search')
        return
    end
    if actionId ~= ACTION then return end
    local ok, reason = createInvite(tonumber(src), tonumber(targetSrc))
    notify(src, ok and 'Gang invitation sent.' or (friendly[reason] or 'Gang invitation failed.'), ok and 'success' or 'error')
end)

RegisterNetEvent('cm-gang:server:respondInvite', function(payload)
    local targetSrc = source
    payload = type(payload) == 'table' and payload or {}
    local inviteId = type(payload.inviteId) == 'string' and payload.inviteId:sub(1, 36) or nil
    if inviteId and not inviteId:match('^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F]+$') then inviteId = nil end
    local targetId = characterIdForSource(targetSrc)
    if not inviteId or not targetId or responseLocks[targetId] then return end
    responseLocks[targetId] = true
    local ok, accepted, reason = xpcall(function()
        local invite = MySQL.single.await([[
            SELECT invite_id, gang_id, actor_character_id, target_character_id, entry_rank_id,
                   CASE WHEN status = 'pending' AND expires_at > NOW() THEN 1 ELSE 0 END AS valid
            FROM cm_gang_invites WHERE invite_id = ? AND target_character_id = ? LIMIT 1
        ]], { inviteId, targetId })
        if not invite then return false, 'expired' end
        if not CMGangDbTrue(invite.valid) then
            MySQL.update.await("UPDATE cm_gang_invites SET status = 'expired', resolved_at = NOW() WHERE invite_id = ? AND status = 'pending'", { inviteId })
            return false, 'expired'
        end
        if payload.accept ~= true then
            local declined = MySQL.update.await([[
                UPDATE cm_gang_invites
                SET status = 'declined', resolved_at = NOW()
                WHERE invite_id = ?
                  AND target_character_id = ?
                  AND status = 'pending'
                  AND expires_at > NOW()
            ]], { inviteId, targetId })
            if tonumber(declined) ~= 1 then return false, 'expired' end
            logInvite(invite.gang_id, 'invite_declined', targetId, invite.actor_character_id, {})
            return true, 'declined'
        end
        if hasOrganizationMembership(targetSrc, targetId) then
            MySQL.update.await([[UPDATE cm_gang_invites SET status='cancelled', resolved_at=NOW()
                WHERE invite_id=? AND target_character_id=? AND status='pending']], { inviteId, targetId })
            return false, 'target_in_org'
        end
        if targetBlacklisted(invite.gang_id, targetId) then return false, 'target_blacklisted' end
        local actorSrc = sourceForCharacter(invite.actor_character_id)
        if not actorSrc then return false, 'player_offline' end
        local actor, actorReason = actorDecision(actorSrc)
        if not actor then return false, actorReason or 'not_authorized' end
        if actor.membership.gangId ~= invite.gang_id then return false, 'not_authorized' end
        local physical, physicalReason = validatePhysical(actorSrc, targetSrc)
        if not physical then return false, physicalReason end
        local rank = lowestEntryRank(invite.gang_id)
        if not rank or tonumber(invite.entry_rank_id) ~= tonumber(rank.id) then return false, 'no_entry_rank' end
        if characterIdForSource(targetSrc) ~= targetId or characterIdForSource(actorSrc) ~= actor.characterId then
            return false, 'character_changed'
        end
        local committed = MySQL.transaction.await({
            { query = [[
                INSERT INTO cm_gang_members (gang_id, character_id, rank_id, is_leader)
                SELECT i.gang_id, i.target_character_id, i.entry_rank_id, 0
                FROM cm_gang_invites i
                WHERE i.invite_id = ?
                  AND i.target_character_id = ?
                  AND i.gang_id = ?
                  AND i.entry_rank_id = ?
                  AND i.status = 'pending'
                  AND i.expires_at > NOW()
            ]], values = { inviteId, targetId, invite.gang_id, rank.id } },
            { query = [[
                UPDATE cm_gang_invites i
                INNER JOIN cm_gang_members m
                    ON m.gang_id = i.gang_id
                   AND m.character_id = i.target_character_id
                   AND m.rank_id = i.entry_rank_id
                SET i.status = 'accepted', i.resolved_at = NOW()
                WHERE i.invite_id = ?
                  AND i.target_character_id = ?
                  AND i.status = 'pending'
            ]], values = { inviteId, targetId } },
        })
        if committed ~= true then return false, 'membership_failed' end
        local acceptedMembership = MySQL.scalar.await([[
            SELECT 1
            FROM cm_gang_invites i
            INNER JOIN cm_gang_members m
                ON m.gang_id = i.gang_id
               AND m.character_id = i.target_character_id
               AND m.rank_id = i.entry_rank_id
            WHERE i.invite_id = ?
              AND i.target_character_id = ?
              AND i.status = 'accepted'
            LIMIT 1
        ]], { inviteId, targetId })
        if not acceptedMembership then return false, 'expired' end
        exports[RESOURCE]:RefreshCharacters({ actor.characterId, targetId })
        logInvite(invite.gang_id, 'member_joined', actor.characterId, targetId, { rankId = rank.id, inviteId = inviteId })
        return true, 'accepted'
    end, debug.traceback)
    responseLocks[targetId] = nil
    if not ok then
        print(('[cm-gang] invitation response failed: %s'):format(tostring(accepted)))
        notify(targetSrc, 'Gang invitation processing failed.', 'error')
        return
    end
    notify(targetSrc, accepted and (reason == 'declined' and 'Gang invitation declined.' or 'You joined the gang.')
        or (friendly[reason] or 'Gang invitation failed.'), accepted and 'success' or 'error')
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    local characterId = data and (data.charId or data.characterId)
    if characterId then sourceCharacters[tonumber(src)] = tostring(characterId) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local characterId = sourceCharacters[src] or characterIdForSource(src)
    sourceCharacters[src] = nil
    if not characterId then return end
    responseLocks[characterId] = nil
    inviteCooldowns[characterId] = nil
    if not CMGangDatabaseReady or GetResourceState('oxmysql') ~= 'started' then return end
    local ok, err = pcall(function()
        MySQL.update.await([[
            UPDATE cm_gang_invites SET status = 'cancelled', resolved_at = NOW()
            WHERE status = 'pending' AND (actor_character_id = ? OR target_character_id = ?)
        ]], { characterId, characterId })
    end)
    if not ok and GetResourceState(RESOURCE) == 'started' and GetResourceState('oxmysql') == 'started' then
        print(('[cm-gang] invite disconnect cleanup failed: %s'):format(tostring(err)))
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == RESOURCE or resourceName == PLAYERDATA then CreateThread(function() Wait(350) registerAction() end) end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    TriggerEvent('cm-playerdata:server:unregisterInteractionAction', ACTION)
    TriggerEvent('cm-playerdata:server:unregisterInteractionAction', 'gang_rob_cash')
    TriggerEvent('cm-playerdata:server:unregisterInteractionAction', 'gang_search')
    TriggerEvent('cm-playerdata:server:unregisterInteractionAction', 'gang_rob_player')
    TriggerEvent('cm-playerdata:server:unregisterInteractionAction', 'gang_rob_items')
    responseLocks, inviteCooldowns, sourceCharacters = {}, {}, {}
end)

CreateThread(function()
    while true do
        Wait(30000)
        if CMGangDatabaseReady then
            MySQL.update.await("UPDATE cm_gang_invites SET status = 'expired', resolved_at = NOW() WHERE status = 'pending' AND expires_at <= NOW()")
        end
    end
end)
