CMClubs = CMClubs or {}

local RESOURCE = GetCurrentResourceName()
local inviteLocks = {}
local mutationLocks = {}
local clubhouseLocks = {}
local sequence = 0
math.randomseed(os.time())

local function result(ok, reason, extra)
    local value = extra or {}
    value.ok = ok
    if reason then value.reason = reason end
    return value
end

local function trim(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%z\1-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > max then return nil end
    return value
end

local function characterId(value)
    value = trim(tostring(value or ''), 64)
    if not value or not value:match('^[%w_%-]+$') then return nil end
    return value
end

local function clubId(value)
    value = trim(tostring(value or ''):lower(), Config.Security.maxClubId)
    if not value or not value:match('^[a-z0-9][a-z0-9_%-]*$') then return nil end
    return value
end

local function color(value)
    value = trim(tostring(value or ''), 7)
    if value and value:match('^#[%da-fA-F]{6}$') then return value:upper() end
    return nil
end

local function normalizeClubhouse(input)
    if input == nil then
        return {
            enabled = false, x = nil, y = nil, z = nil, heading = nil,
            npcModel = nil, displayName = nil, interactionLabel = nil,
            interactionDistance = nil, routingBucket = nil,
        }
    end
    if type(input) ~= 'table' then return nil, 'invalid_clubhouse' end

    local enabled = input.enabled == true
    local x, y, z = tonumber(input.x), tonumber(input.y), tonumber(input.z)
    local heading = tonumber(input.heading)
    local distance = tonumber(input.interactionDistance or input.interaction_distance)
    local model = trim(tostring(input.npcModel or input.npc_model or ''), 64)
    local displayName = trim(tostring(input.displayName or input.display_name or ''), 64)
    local interactionLabel = trim(tostring(input.interactionLabel or input.interaction_label or ''), 64)
    local bucket = input.routingBucket
    if bucket == nil then bucket = input.routing_bucket end
    if bucket ~= nil and tostring(bucket) ~= '' then
        bucket = tonumber(bucket)
        if not bucket or bucket % 1 ~= 0 or bucket < 0 or bucket > 65535 then return nil, 'invalid_routing_bucket' end
    else
        bucket = nil
    end

    if enabled and (not x or not y or not z or not heading or not model or not displayName or not interactionLabel) then
        return nil, 'clubhouse_requires_complete_configuration'
    end
    if (x and (x < -10000 or x > 10000)) or (y and (y < -10000 or y > 10000)) or (z and (z < -2000 or z > 3000)) then
        return nil, 'invalid_clubhouse_coordinates'
    end
    if heading and (heading < 0 or heading >= 360) then return nil, 'invalid_clubhouse_heading' end
    if enabled and Config.Clubhouse.modelNames[model] ~= true then return nil, 'npc_model_not_allowlisted' end
    if distance == nil then distance = Config.Clubhouse.defaultInteractionDistance end
    if distance < 1.0 or distance > Config.Clubhouse.maxInteractionDistance then return nil, 'invalid_interaction_distance' end
    return {
        enabled = enabled, x = enabled and x or nil, y = enabled and y or nil, z = enabled and z or nil,
        heading = enabled and (heading or 0.0) or nil, npcModel = enabled and model or nil,
        displayName = enabled and displayName or nil, interactionLabel = enabled and interactionLabel or nil,
        interactionDistance = enabled and distance or nil, routingBucket = enabled and bucket or nil,
    }
end

local function isDatabaseReady()
    return CMClubs.DatabaseReady == true
end

local function cooldown(bucket, key, milliseconds)
    local now = GetGameTimer()
    local id = ('%s:%s'):format(bucket, tostring(key))
    if (bucket == 'invite' and inviteLocks[id] or mutationLocks[id] or 0) > now then return false end
    if bucket == 'invite' then inviteLocks[id] = now + milliseconds else mutationLocks[id] = now + milliseconds end
    return true
end

local function loadedCharacter(src)
    src = tonumber(src)
    if not src or src <= 0 or GetPlayerName(src) == nil then return nil end
    local okLoaded, loaded = pcall(function() return exports['cm-playerdata']:IsCharacterLoaded(src) end)
    if not okLoaded or loaded ~= true then return nil end
    local okId, rawId = pcall(function() return exports['cm-playerdata']:GetCharacterId(src) end)
    if not okId then return nil end
    return characterId(rawId)
end

local function sourceForCharacter(cid)
    cid = characterId(cid)
    if not cid then return nil end
    local ok, src = pcall(function() return exports['cm-playerdata']:GetSourceByCharId(cid) end)
    src = ok and tonumber(src) or nil
    return src and loadedCharacter(src) == cid and src or nil
end

local function isDead(src)
    local ok, dead = pcall(function() return exports['cm-playerdata']:IsDead(src) end)
    if ok and dead == true then return true end
    local player = Player(src)
    return player and player.state and (player.state.isDead == true or player.state.dead == true) or false
end

local function sameBucket(a, b)
    return GetPlayerRoutingBucket(a) == GetPlayerRoutingBucket(b)
end

local function nearby(a, b)
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or pedA == 0 or not pedB or pedB == 0 then return false end
    local aCoords, bCoords = GetEntityCoords(pedA), GetEntityCoords(pedB)
    if not aCoords or not bCoords then return false end
    local dx, dy, dz = aCoords.x - bCoords.x, aCoords.y - bCoords.y, aCoords.z - bCoords.z
    return (dx * dx + dy * dy + dz * dz) <= (Config.Security.interactionMaxDistance ^ 2)
end

local function notify(src, message, kind)
    if tonumber(src) then TriggerClientEvent('cm-clubs:client:notify', src, message, kind or 'inform') end
end

local function decodePermissions(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end

local function hasPermission(member, permission)
    if not member or not permission then return false end
    return tonumber(member.is_leader) == 1 or member.rank_is_leader == 1 or decodePermissions(member.permissions)[permission] == true
end

local function getMember(cid)
    if not isDatabaseReady() then return nil end
    return MySQL.single.await([[SELECT m.id, m.club_id, m.character_id, m.rank_id, m.is_leader,
        c.name AS club_name, c.short_tag, c.description, c.display_color, c.enabled,
        r.rank_key, r.name AS rank_name, r.tier, r.permissions, r.is_leader_rank AS rank_is_leader
        FROM cm_club_members m
        INNER JOIN cm_clubs c ON c.club_id = m.club_id
        INNER JOIN cm_club_ranks r ON r.id = m.rank_id
        WHERE m.character_id = ? AND m.status = 'active' LIMIT 1]], { cid })
end

local function getClub(club)
    if not isDatabaseReady() then return nil end
    return MySQL.single.await('SELECT club_id, name, short_tag, description, display_color, enabled FROM cm_clubs WHERE club_id = ? LIMIT 1', { club })
end

local function getRank(club, rankKey)
    return MySQL.single.await('SELECT id, club_id, rank_key, name, tier, permissions, is_leader_rank FROM cm_club_ranks WHERE club_id = ? AND rank_key = ? LIMIT 1', { club, rankKey })
end

local function defaultRanks(raw)
    if type(raw) == 'table' and #raw > 0 then return raw end
    return Config.DefaultRanks
end

local function validateRanks(raw)
    local rows, keys, tiers, leaders = {}, {}, {}, 0
    for _, input in ipairs(defaultRanks(raw)) do
        if type(input) ~= 'table' then return nil, 'invalid_rank' end
        local key = trim(tostring(input.rankKey or input.rank_key or ''), 32)
        local name = trim(tostring(input.name or ''), 48)
        local tier = tonumber(input.tier)
        if not key or not key:match('^[a-z0-9_%-]+$') or not name or not tier or tier < 1 or tier > 1000 or tier % 1 ~= 0 or keys[key] or tiers[tier] then
            return nil, 'invalid_rank'
        end
        local permissions, safePermissions = type(input.permissions) == 'table' and input.permissions or {}, {}
        for permission, enabled in pairs(permissions) do
            local known = false
            for _, configured in pairs(Config.Permissions) do if configured == permission then known = true break end end
            if known and enabled == true then safePermissions[permission] = true end
        end
        local leader = input.isLeader == true or input.is_leader == true
        if leader then leaders = leaders + 1 end
        keys[key], tiers[tier] = true, true
        rows[#rows + 1] = { key = key, name = name, tier = tier, permissions = json.encode(safePermissions), leader = leader }
    end
    if #rows < 1 or leaders ~= 1 then return nil, 'one_leader_rank_required' end
    return rows
end

local function appendActivity(club, action, actor, target, detail, eventUid)
    sequence = sequence + 1
    eventUid = eventUid or ('%s:%s:%s:%s'):format(RESOURCE, os.time(), sequence, action)
    detail = type(detail) == 'table' and detail or {}
    local encoded = json.encode(detail) or '{}'
    if #encoded > Config.Security.maxActivityDetail then encoded = '{}' end
    return MySQL.insert.await([[INSERT IGNORE INTO cm_club_activity
        (event_uid, club_id, action, actor_character_id, target_character_id, detail)
        VALUES (?, ?, ?, ?, ?, ?)]], { eventUid, club, action, actor, target, encoded })
end

local function syncChat(src, member)
    if GetResourceState('cm-chat') ~= 'started' then return false end
    local ok = pcall(function()
        exports['cm-chat']:SetPlayerChatGroup(src, Config.Chat.group, member and member.club_id or nil, member and member.display_color or Config.Chat.fallbackColor)
    end)
    return ok
end

local function syncCharacter(src)
    local cid = loadedCharacter(src)
    if not cid then syncChat(src, nil) return end
    local member = getMember(cid)
    if not member or tonumber(member.enabled) ~= 1 then syncChat(src, nil) else syncChat(src, member) end
end

local function cancelPendingInvitesForCharacter(cid, reason)
    cid = characterId(cid)
    if not cid or not isDatabaseReady() then return end
    MySQL.update.await("UPDATE cm_club_invites SET status = ?, resolved_at = NOW() WHERE status = 'pending' AND (inviter_character_id = ? OR target_character_id = ?)", { reason or 'cancelled', cid, cid })
end

local function notifyMembers(club, message, kind)
    local rows = MySQL.query.await("SELECT character_id FROM cm_club_members WHERE club_id = ? AND status = 'active'", { club }) or {}
    for _, row in ipairs(rows) do
        local src = sourceForCharacter(row.character_id)
        if src then notify(src, message, kind) end
    end
end

local function refreshClubhouseClients(club)
    if not isDatabaseReady() then return end
    local rows = MySQL.query.await("SELECT character_id FROM cm_club_members WHERE club_id = ? AND status = 'active'", { club }) or {}
    for _, row in ipairs(rows) do
        local src = sourceForCharacter(row.character_id)
        if src then TriggerClientEvent('cm-clubs:client:refreshClubhouse', src) end
    end
end

local function currentMember(src)
    local cid = loadedCharacter(src)
    if not cid then return nil, 'character_unavailable' end
    local member = getMember(cid)
    if not member or tonumber(member.enabled) ~= 1 then return nil, 'not_in_club' end
    return member, cid
end

local function inviteTarget(src, target)
    local actor, actorCid = currentMember(src)
    if not actor then return result(false, actorCid) end
    if not hasPermission(actor, Config.Permissions.invite) then return result(false, 'permission_denied') end
    if not cooldown('invite', src, Config.Security.inviteCooldownMs) then return result(false, 'rate_limited') end
    target = tonumber(target)
    local targetCid = target and loadedCharacter(target)
    if not targetCid or target == src or isDead(src) or isDead(target) or not sameBucket(src, target) or not nearby(src, target) then
        return result(false, 'target_unavailable')
    end
    if getMember(targetCid) then return result(false, 'target_already_in_club') end
    MySQL.update.await("UPDATE cm_club_invites SET status = 'expired', resolved_at = NOW() WHERE target_character_id = ? AND status = 'pending' AND expires_at <= NOW()", { targetCid })
    local pending = MySQL.single.await("SELECT invite_id FROM cm_club_invites WHERE target_character_id = ? AND status = 'pending' AND expires_at > NOW() LIMIT 1", { targetCid })
    if pending then return result(false, 'invite_already_pending') end
    local rank = getRank(actor.club_id, 'member')
    if not rank then
        rank = MySQL.single.await('SELECT id FROM cm_club_ranks WHERE club_id = ? AND is_leader_rank = 0 ORDER BY tier ASC LIMIT 1', { actor.club_id })
    end
    if not rank then return result(false, 'club_has_no_entry_rank') end
    local inviteId = ('%08x-%04x-%04x-%04x-%012x'):format(math.random(0, 0xffffffff), math.random(0, 0xffff), math.random(0, 0xffff), math.random(0, 0xffff), math.random(0, 0xffffffffffff))
    local inserted = MySQL.insert.await([[INSERT INTO cm_club_invites
        (invite_id, club_id, inviter_character_id, target_character_id, entry_rank_id, expires_at)
        VALUES (?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))]], { inviteId, actor.club_id, actorCid, targetCid, rank.id, Config.Security.inviteExpirySeconds })
    if not inserted then return result(false, 'invite_unavailable') end
    appendActivity(actor.club_id, 'invite_created', actorCid, targetCid, {})
    TriggerClientEvent('cm-clubs:client:invitePrompt', target, { inviteId = inviteId, clubName = actor.club_name, clubTag = actor.short_tag, inviter = ('Character ID %s'):format(actorCid), expires = Config.Security.inviteExpirySeconds })
    notify(src, ('Invitation sent to Character ID %s.'):format(targetCid), 'success')
    return result(true)
end

local function acceptInvite(src, inviteId)
    local targetCid = loadedCharacter(src)
    if not targetCid or isDead(src) then return result(false, 'character_unavailable') end
    inviteId = trim(tostring(inviteId or ''), 36)
    if not inviteId or not cooldown('mutation', src, Config.Security.mutationCooldownMs) then return result(false, 'rate_limited') end
    local invite = MySQL.single.await([[SELECT i.*, c.name AS club_name, c.enabled
        FROM cm_club_invites i INNER JOIN cm_clubs c ON c.club_id = i.club_id
        WHERE i.invite_id = ? AND i.target_character_id = ? AND i.status = 'pending' AND i.expires_at > NOW() LIMIT 1]], { inviteId, targetCid })
    if not invite or tonumber(invite.enabled) ~= 1 then return result(false, 'invite_expired') end
    local inviterSrc = sourceForCharacter(invite.inviter_character_id)
    if not inviterSrc or isDead(inviterSrc) or not sameBucket(src, inviterSrc) or not nearby(src, inviterSrc) then return result(false, 'inviter_unavailable') end
    local inviter = getMember(invite.inviter_character_id)
    if not inviter or inviter.club_id ~= invite.club_id or not hasPermission(inviter, Config.Permissions.invite) then return result(false, 'invitation_no_longer_valid') end
    if getMember(targetCid) then return result(false, 'already_in_club') end
    local committed = MySQL.transaction.await({
        { query = "UPDATE cm_club_invites SET status = 'accepted', resolved_at = NOW() WHERE invite_id = ? AND target_character_id = ? AND status = 'pending' AND expires_at > NOW()", values = { inviteId, targetCid } },
        { query = "INSERT INTO cm_club_members (club_id, character_id, rank_id, is_leader, status) VALUES (?, ?, ?, 0, 'active')", values = { invite.club_id, targetCid, invite.entry_rank_id } },
        { query = 'INSERT IGNORE INTO cm_club_activity (event_uid, club_id, action, actor_character_id, target_character_id, detail) VALUES (?, ?, ?, ?, ?, ?)', values = { inviteId .. ':accepted', invite.club_id, 'member_joined', invite.inviter_character_id, targetCid, '{}' } },
    })
    if committed ~= true then return result(false, 'accept_failed') end
    syncCharacter(src)
    notify(src, ('Welcome to %s.'):format(invite.club_name), 'success')
    notify(inviterSrc, ('Character ID %s joined %s.'):format(targetCid, invite.club_name), 'success')
    return result(true)
end

local function declineInvite(src, inviteId)
    local cid = loadedCharacter(src)
    if not cid then return result(false, 'character_unavailable') end
    inviteId = trim(tostring(inviteId or ''), 36)
    local changed = MySQL.update.await("UPDATE cm_club_invites SET status = 'declined', resolved_at = NOW() WHERE invite_id = ? AND target_character_id = ? AND status = 'pending' AND expires_at > NOW()", { inviteId, cid })
    if tonumber(changed) ~= 1 then return result(false, 'invite_expired') end
    return result(true)
end

local function dashboard(src)
    local member, cid = currentMember(src)
    if not member then return result(false, cid) end
    local members = MySQL.query.await([[SELECT m.character_id, m.rank_id, m.is_leader, r.rank_key, r.name AS rank_name
        FROM cm_club_members m INNER JOIN cm_club_ranks r ON r.id = m.rank_id
        WHERE m.club_id = ? AND m.status = 'active' ORDER BY r.tier DESC, m.character_id ASC]], { member.club_id }) or {}
    for _, row in ipairs(members) do
        row.label = ('Character ID %s'):format(row.character_id)
        row.online = sourceForCharacter(row.character_id) ~= nil
    end
    local activity = MySQL.query.await([[SELECT action, actor_character_id, target_character_id, detail, created_at
        FROM cm_club_activity WHERE club_id = ? ORDER BY id DESC LIMIT 20]], { member.club_id }) or {}
    for _, row in ipairs(activity) do row.detail = decodePermissions(row.detail) end
    local ranks = MySQL.query.await('SELECT rank_key, name, tier, is_leader_rank FROM cm_club_ranks WHERE club_id = ? ORDER BY tier DESC', { member.club_id }) or {}
    return result(true, nil, {
        club = { id = member.club_id, name = member.club_name, tag = member.short_tag, description = member.description, color = member.display_color, enabled = tonumber(member.enabled) == 1 },
        self = { characterId = cid, rank = member.rank_name, rankKey = member.rank_key, tier = tonumber(member.tier) or 0, permissions = decodePermissions(member.permissions) },
        members = members,
        ranks = ranks,
        activity = activity,
        actions = { leave = member.rank_is_leader ~= 1 and member.is_leader ~= 1, manageMembers = hasPermission(member, Config.Permissions.manageMembers), manageRanks = hasPermission(member, Config.Permissions.manageRanks) },
    })
end

lib.callback.register('cm-clubs:server:getTargetActions', function(src, targetSrc)
    local actor = currentMember(src)
    targetSrc = tonumber(targetSrc)
    if not actor or not targetSrc or targetSrc == src or not loadedCharacter(targetSrc) or isDead(src) or isDead(targetSrc) then return {} end
    if not hasPermission(actor, Config.Permissions.invite) or not sameBucket(src, targetSrc) or not nearby(src, targetSrc) then return {} end
    if getMember(loadedCharacter(targetSrc)) then return {} end
    return { invite = true }
end)

local function leaveClub(src)
    local member, cid = currentMember(src)
    if not member then return result(false, cid) end
    if member.rank_is_leader == 1 or tonumber(member.is_leader) == 1 then return result(false, 'leader_must_be_reassigned') end
    local committed = MySQL.transaction.await({
        { query = "UPDATE cm_club_members SET status = 'left', left_at = NOW(), updated_at = NOW() WHERE id = ? AND character_id = ? AND status = 'active'", values = { member.id, cid } },
        { query = 'INSERT INTO cm_club_activity (event_uid, club_id, action, actor_character_id, target_character_id, detail) VALUES (?, ?, ?, ?, ?, ?)', values = { ('leave:%s:%s'):format(member.id, os.time()), member.club_id, 'member_left', cid, cid, '{}' } },
    })
    if committed ~= true then return result(false, 'leave_failed') end
    syncChat(src, nil)
    return result(true)
end

local function manageMember(src, request)
    request = type(request) == 'table' and request or {}
    local actor, actorCid = currentMember(src)
    if not actor or not hasPermission(actor, Config.Permissions.manageMembers) then return result(false, actorCid or 'permission_denied') end
    local targetCid, action = characterId(request.characterId), tostring(request.action or '')
    if not targetCid or (action ~= 'remove' and action ~= 'set_rank') then return result(false, 'invalid_request') end
    if action == 'set_rank' and not hasPermission(actor, Config.Permissions.manageRanks) then return result(false, 'permission_denied') end
    local target = MySQL.single.await([[SELECT m.id, m.character_id, m.rank_id, m.is_leader, r.tier, r.rank_key
        FROM cm_club_members m INNER JOIN cm_club_ranks r ON r.id = m.rank_id
        WHERE m.club_id = ? AND m.character_id = ? AND m.status = 'active' LIMIT 1]], { actor.club_id, targetCid })
    if not target or targetCid == actorCid or tonumber(target.is_leader) == 1 or target.rank_key == 'leader' then return result(false, 'member_not_manageable') end
    if tonumber(target.tier) >= tonumber(actor.tier) then return result(false, 'hierarchy_denied') end
    if action == 'remove' then
        local committed = MySQL.transaction.await({
            { query = "UPDATE cm_club_members SET status = 'removed', left_at = NOW(), removed_by_character_id = ?, updated_at = NOW() WHERE id = ? AND status = 'active'", values = { actorCid, target.id } },
            { query = 'INSERT INTO cm_club_activity (event_uid, club_id, action, actor_character_id, target_character_id, detail) VALUES (?, ?, ?, ?, ?, ?)', values = { ('remove:%s:%s'):format(target.id, os.time()), actor.club_id, 'member_removed', actorCid, targetCid, '{}' } },
        })
        if committed ~= true then return result(false, 'member_update_failed') end
        local targetSrc = sourceForCharacter(targetCid); if targetSrc then syncCharacter(targetSrc); notify(targetSrc, 'You were removed from the club.', 'error') end
        return result(true)
    end
    local rankKey = trim(tostring(request.rankKey or ''), 32)
    local rank = rankKey and getRank(actor.club_id, rankKey)
    if not rank or tonumber(rank.is_leader_rank) == 1 or tonumber(rank.tier) >= tonumber(actor.tier) then return result(false, 'rank_not_allowed') end
    local changed = MySQL.update.await('UPDATE cm_club_members SET rank_id = ?, is_leader = 0, updated_at = NOW() WHERE id = ? AND status = \'active\'', { rank.id, target.id })
    if tonumber(changed) ~= 1 then return result(false, 'member_update_failed') end
    appendActivity(actor.club_id, 'member_rank_changed', actorCid, targetCid, { rankKey = rank.rank_key })
    local targetSrc = sourceForCharacter(targetCid); if targetSrc then syncCharacter(targetSrc) end
    return result(true)
end

local function adminAuthorized(adminSrc)
    if GetInvokingResource() ~= Config.Admin.invokingResource then return false, 'owner_only' end
    adminSrc = tonumber(adminSrc)
    if not adminSrc or adminSrc <= 0 or GetPlayerName(adminSrc) == nil or GetResourceState('cm-admin') ~= 'started' then return false, 'admin_unavailable' end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(adminSrc, Config.Admin.permission) end)
    if not ok or allowed ~= true then return false, 'permission_denied' end
    return true, adminSrc
end

local function adminCreate(adminSrc, data)
    local authorized, value = adminAuthorized(adminSrc); if not authorized then return result(false, value) end
    if not isDatabaseReady() or type(data) ~= 'table' then return result(false, 'database_unavailable') end
    local id, name, tag, description = clubId(data.clubId), trim(data.name, Config.Security.maxName), trim(data.shortTag, Config.Security.maxTag), trim(data.description or '', Config.Security.maxDescription) or ''
    local displayColor = color(data.color) or Config.Chat.fallbackColor
    if not id or not name or not tag or not tag:match('^[%w%-]+$') then return result(false, 'invalid_club') end
    local clubhouse, clubhouseReason = normalizeClubhouse(data.clubhouse)
    if not clubhouse then return result(false, clubhouseReason) end
    local ranks, rankReason = validateRanks(data.ranks); if not ranks then return result(false, rankReason) end
    local creator = loadedCharacter(value)
    local statements = {{ query = [[INSERT INTO cm_clubs
        (club_id, name, short_tag, description, display_color, enabled, created_by_character_id, updated_by_character_id,
         clubhouse_enabled, clubhouse_x, clubhouse_y, clubhouse_z, clubhouse_heading, clubhouse_npc_model,
         clubhouse_display_name, clubhouse_interaction_label, clubhouse_interaction_distance, clubhouse_routing_bucket)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], values = {
        id, name, tag, description, displayColor, 1, creator, creator,
        clubhouse.enabled and 1 or 0, clubhouse.x, clubhouse.y, clubhouse.z, clubhouse.heading,
        clubhouse.npcModel, clubhouse.displayName, clubhouse.interactionLabel, clubhouse.interactionDistance, clubhouse.routingBucket,
    } }}
    for _, rank in ipairs(ranks) do statements[#statements + 1] = { query = 'INSERT INTO cm_club_ranks (club_id, rank_key, name, tier, permissions, is_leader_rank) VALUES (?, ?, ?, ?, ?, ?)', values = { id, rank.key, rank.name, rank.tier, rank.permissions, rank.leader and 1 or 0 } } end
    if MySQL.transaction.await(statements) ~= true then return result(false, 'club_exists_or_create_failed') end
    return result(true, nil, { clubId = id })
end

local function adminSetEnabled(adminSrc, rawId, enabled)
    local authorized, value = adminAuthorized(adminSrc); if not authorized then return result(false, value) end
    if not isDatabaseReady() then return result(false, 'database_unavailable') end
    local id = clubId(rawId); if not id or type(enabled) ~= 'boolean' then return result(false, 'invalid_request') end
    local changed = MySQL.update.await('UPDATE cm_clubs SET enabled = ?, updated_by_character_id = ? WHERE club_id = ?', { enabled and 1 or 0, loadedCharacter(value), id })
    if tonumber(changed) ~= 1 then return result(false, 'club_not_found') end
    if not enabled then
        MySQL.update.await("UPDATE cm_club_invites SET status = 'cancelled', resolved_at = NOW() WHERE club_id = ? AND status = 'pending'", { id })
        local rows = MySQL.query.await("SELECT character_id FROM cm_club_members WHERE club_id = ? AND status = 'active'", { id }) or {}
        for _, row in ipairs(rows) do local src = sourceForCharacter(row.character_id); if src then syncChat(src, nil) end end
    end
    refreshClubhouseClients(id)
    return result(true)
end

local function adminAssignLeader(adminSrc, rawId, rawCid)
    local authorized, value = adminAuthorized(adminSrc); if not authorized then return result(false, value) end
    if not isDatabaseReady() then return result(false, 'database_unavailable') end
    local id, targetCid = clubId(rawId), characterId(rawCid); if not id or not targetCid then return result(false, 'invalid_request') end
    local target = MySQL.single.await([[SELECT m.id FROM cm_club_members m INNER JOIN cm_clubs c ON c.club_id = m.club_id
        WHERE m.club_id = ? AND m.character_id = ? AND m.status = 'active' AND c.enabled = 1 LIMIT 1]], { id, targetCid })
    local leader = MySQL.single.await('SELECT id FROM cm_club_ranks WHERE club_id = ? AND is_leader_rank = 1 LIMIT 1', { id })
    local fallback = MySQL.single.await('SELECT id FROM cm_club_ranks WHERE club_id = ? AND is_leader_rank = 0 ORDER BY tier DESC LIMIT 1', { id })
    if not target or not leader or not fallback then return result(false, 'leader_assignment_unavailable') end
    local actorCid = loadedCharacter(value)
    local committed = MySQL.transaction.await({
        { query = 'UPDATE cm_club_members SET rank_id = ?, is_leader = 0, updated_at = NOW() WHERE club_id = ? AND status = \'active\' AND (is_leader = 1 OR rank_id = ?)', values = { fallback.id, id, leader.id } },
        { query = 'UPDATE cm_club_members SET rank_id = ?, is_leader = 1, updated_at = NOW() WHERE id = ? AND status = \'active\'', values = { leader.id, target.id } },
        { query = 'INSERT INTO cm_club_activity (event_uid, club_id, action, actor_character_id, target_character_id, detail) VALUES (?, ?, ?, ?, ?, ?)', values = { ('leader:%s:%s'):format(id, os.time()), id, 'leader_assigned', actorCid, targetCid, '{}' } },
    })
    if committed ~= true then return result(false, 'leader_assignment_failed') end
    local src = sourceForCharacter(targetCid); if src then syncCharacter(src) end
    return result(true)
end

local function adminUpsertRank(adminSrc, rawId, data)
    local authorized, value = adminAuthorized(adminSrc); if not authorized then return result(false, value) end
    if not isDatabaseReady() then return result(false, 'database_unavailable') end
    local id = clubId(rawId); data = type(data) == 'table' and data or {}
    local key, name, tier = trim(data.rankKey, 32), trim(data.name, 48), tonumber(data.tier)
    if not id or not key or not key:match('^[a-z0-9_%-]+$') or not name or not tier or tier < 1 or tier > 1000 or tier % 1 ~= 0 then return result(false, 'invalid_rank') end
    if not getClub(id) then return result(false, 'club_not_found') end
    local known, permissions = {}, {}
    for permission, enabled in pairs(type(data.permissions) == 'table' and data.permissions or {}) do
        for _, configured in pairs(Config.Permissions) do if permission == configured and enabled == true then known[permission] = true end end
    end
    for permission in pairs(known) do permissions[permission] = true end
    local leader = data.isLeader == true and 1 or 0
    local currentLeader = MySQL.single.await('SELECT rank_key FROM cm_club_ranks WHERE club_id = ? AND is_leader_rank = 1 LIMIT 1', { id })
    if leader == 0 and currentLeader and currentLeader.rank_key == key then return result(false, 'leader_rank_required') end
    if leader == 1 then MySQL.update.await('UPDATE cm_club_ranks SET is_leader_rank = 0 WHERE club_id = ?', { id }) end
    local changed = MySQL.update.await([[INSERT INTO cm_club_ranks (club_id, rank_key, name, tier, permissions, is_leader_rank)
        VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), tier = VALUES(tier), permissions = VALUES(permissions), is_leader_rank = VALUES(is_leader_rank)]], { id, key, name, tier, json.encode(permissions), leader })
    if not changed then return result(false, 'rank_update_failed') end
    return result(true)
end

local function adminSetClubhouse(adminSrc, rawId, data)
    local authorized, value = adminAuthorized(adminSrc); if not authorized then return result(false, value) end
    if not isDatabaseReady() then return result(false, 'database_unavailable') end
    local id = clubId(rawId)
    if not id or not getClub(id) then return result(false, 'club_not_found') end
    local clubhouse, reason = normalizeClubhouse(type(data) == 'table' and (data.clubhouse or data) or nil)
    if not clubhouse then return result(false, reason) end
    local actor = loadedCharacter(value)
    local changed = MySQL.update.await([[UPDATE cm_clubs SET
        clubhouse_enabled = ?, clubhouse_x = ?, clubhouse_y = ?, clubhouse_z = ?, clubhouse_heading = ?,
        clubhouse_npc_model = ?, clubhouse_display_name = ?, clubhouse_interaction_label = ?,
        clubhouse_interaction_distance = ?, clubhouse_routing_bucket = ?, updated_by_character_id = ?
        WHERE club_id = ?]], {
        clubhouse.enabled and 1 or 0, clubhouse.x, clubhouse.y, clubhouse.z, clubhouse.heading,
        clubhouse.npcModel, clubhouse.displayName, clubhouse.interactionLabel, clubhouse.interactionDistance,
        clubhouse.routingBucket, actor, id,
    })
    if tonumber(changed) ~= 1 then return result(false, 'clubhouse_update_failed') end
    refreshClubhouseClients(id)
    return result(true, nil, { clubId = id, enabled = clubhouse.enabled })
end

local function adminGetClubs(adminSrc)
    local authorized, value = adminAuthorized(adminSrc); if not authorized then return result(false, value) end
    if not isDatabaseReady() then return result(false, 'database_unavailable') end
    local clubs = MySQL.query.await([[SELECT club_id, name, short_tag, description, display_color, enabled,
        clubhouse_enabled, clubhouse_x, clubhouse_y, clubhouse_z, clubhouse_heading, clubhouse_npc_model,
        clubhouse_display_name, clubhouse_interaction_label, clubhouse_interaction_distance, clubhouse_routing_bucket,
        created_at, updated_at FROM cm_clubs ORDER BY name ASC]]) or {}
    return result(true, nil, { clubs = clubs })
end

lib.callback.register('cm-clubs:server:getDashboard', function(src) return dashboard(src) end)
lib.callback.register('cm-clubs:server:leave', function(src) return leaveClub(src) end)
lib.callback.register('cm-clubs:server:memberAction', function(src, request) return manageMember(src, request) end)

RegisterNetEvent('cm-clubs:server:respondInvite', function(inviteId, accepted)
    local src = source
    local response = accepted == true and acceptInvite(src, inviteId) or declineInvite(src, inviteId)
    if not response.ok then notify(src, (response.reason or 'Invitation unavailable.'):gsub('_', ' '), 'error') end
end)

AddEventHandler('cm-clubs:server:interactionInvite', function(src, target, actionId, payload, context)
    local response = inviteTarget(src, target)
    if not response.ok then notify(src, (response.reason or 'Invite unavailable.'):gsub('_', ' '), 'error') end
end)

local function registerInteractionAction()
    if GetResourceState('cm-playerdata') ~= 'started' then return end
    pcall(function()
        exports['cm-playerdata']:RegisterInteractionAction({
            id = 'club_invite',
            event = 'cm-clubs:server:interactionInvite',
            allowDeadTarget = false,
            resource = RESOURCE,
        })
    end)
end

RegisterNetEvent('cm-clubs:server:openDashboard', function() TriggerClientEvent('cm-clubs:client:openDashboard', source) end)

exports('AdminCreateClub', adminCreate)
exports('AdminSetClubEnabled', adminSetEnabled)
exports('AdminAssignClubLeader', adminAssignLeader)
exports('AdminUpsertClubRank', adminUpsertRank)
exports('AdminSetClubhouse', adminSetClubhouse)
exports('AdminGetClubs', adminGetClubs)

local function clubhouseForClub(id)
    local row = MySQL.single.await([[SELECT c.name, c.enabled, c.clubhouse_enabled, c.clubhouse_x, c.clubhouse_y,
        c.clubhouse_z, c.clubhouse_heading, c.clubhouse_npc_model, c.clubhouse_display_name,
        c.clubhouse_interaction_label, c.clubhouse_interaction_distance, c.clubhouse_routing_bucket
        FROM cm_clubs c WHERE c.club_id = ? LIMIT 1]], { id })
    if not row or tonumber(row.enabled) ~= 1 or tonumber(row.clubhouse_enabled) ~= 1 then return nil, 'clubhouse_disabled' end
    local normalized, reason = normalizeClubhouse({
        enabled = true,
        x = row.clubhouse_x, y = row.clubhouse_y, z = row.clubhouse_z,
        heading = row.clubhouse_heading, npcModel = row.clubhouse_npc_model,
        displayName = row.clubhouse_display_name, interactionLabel = row.clubhouse_interaction_label,
        interactionDistance = row.clubhouse_interaction_distance, routingBucket = row.clubhouse_routing_bucket,
    })
    if not normalized then return nil, reason or 'clubhouse_not_configured' end
    normalized.clubName = tostring(row.name or 'Social Club')
    return normalized
end

local function clubhousePayload(id, member)
    local row, reason = clubhouseForClub(id)
    if not row then return nil, reason end
    return {
        clubId = id,
        clubName = row.clubName,
        displayName = row.displayName,
        interactionLabel = row.interactionLabel,
        npcModel = row.npcModel,
        x = row.x, y = row.y, z = row.z, heading = row.heading,
        interactionDistance = row.interactionDistance,
        routingBucket = row.routingBucket,
    }
end

local function authorizeClubhouse(src, request)
    request = type(request) == 'table' and request or {}
    if tostring(request.action or '') ~= 'dashboard' then return result(false, 'invalid_action') end
    local requestedClub = clubId(request.clubId)
    if not requestedClub then return result(false, 'invalid_club') end
    local member, cid = currentMember(src)
    if not member then return result(false, cid) end
    if member.club_id ~= requestedClub or member.character_id ~= cid then return result(false, 'club_membership_mismatch') end
    local facility, reason = clubhouseForClub(requestedClub)
    if not facility then return result(false, reason) end
    local bucket = facility.routingBucket
    if bucket ~= nil and GetPlayerRoutingBucket(src) ~= bucket then return result(false, 'wrong_routing_bucket') end
    if isDead(src) then return result(false, 'player_not_alive') end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return result(false, 'player_entity_unavailable') end
    if IsEntityDead(ped) or (GetEntityHealth(ped) or 0) <= 0 then return result(false, 'player_not_alive') end
    local coords = GetEntityCoords(ped)
    if not coords then return result(false, 'player_entity_unavailable') end
    if #(coords - vector3(facility.x, facility.y, facility.z)) > facility.interactionDistance + 0.35 then
        return result(false, 'too_far_away')
    end
    local now = GetGameTimer()
    if clubhouseLocks[src] and clubhouseLocks[src] > now then return result(false, 'interaction_rate_limited') end
    clubhouseLocks[src] = now + Config.Clubhouse.requestCooldownMs
    return result(true, nil, { clubId = requestedClub })
end

lib.callback.register('cm-clubs:server:getClubhouse', function(src)
    local member, reason = currentMember(src)
    if not member then return result(false, reason) end
    local clubhouse, clubhouseReason = clubhousePayload(member.club_id, member)
    if not clubhouse then return result(false, clubhouseReason) end
    return result(true, nil, { clubhouse = clubhouse })
end)

lib.callback.register('cm-clubs:server:authorizeClubhouse', function(src, request)
    return authorizeClubhouse(src, request)
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    SetTimeout(250, function()
        syncCharacter(src)
        TriggerClientEvent('cm-clubs:client:refreshClubhouse', src)
    end)
end)
AddEventHandler('cm-playerdata:server:characterUnloaded', function(src, data)
    local cid = type(data) == 'table' and (data.charId or data.characterId or data.id) or loadedCharacter(src)
    clubhouseLocks[src] = nil
    cancelPendingInvitesForCharacter(cid, 'cancelled')
    syncChat(src, nil)
end)
AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, dead)
    if dead == true then
        clubhouseLocks[src] = nil
        cancelPendingInvitesForCharacter(loadedCharacter(src), 'cancelled')
        TriggerClientEvent('cm-clubs:client:refreshClubhouse', src)
    end
end)
AddEventHandler('playerDropped', function()
    clubhouseLocks[source] = nil
    cancelPendingInvitesForCharacter(loadedCharacter(source), 'cancelled')
    syncChat(source, nil)
end)
AddEventHandler('onResourceStart', function(resource)
    if resource == 'cm-playerdata' then SetTimeout(250, registerInteractionAction) end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then
        if GetResourceState('cm-playerdata') == 'started' then
            pcall(function() exports['cm-playerdata']:UnregisterInteractionAction('club_invite') end)
        end
        return
    end
    if resource == 'cm-chat' then return end
end)

CreateThread(function()
    Wait(1000)
    registerInteractionAction()
end)
