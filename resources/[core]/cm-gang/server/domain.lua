local RESOURCE = GetCurrentResourceName()
local PLAYERDATA = 'cm-playerdata'

local gangs = {}
local membersByCharacter = {}
local permissionCatalog = {}
local mutationLocks = {}
local mutationCooldowns = {}
local sourceCharacters = {}
local domainReady = false

for _, permission in ipairs(Config.Permissions or {}) do
    permissionCatalog[permission.key] = true
end

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function normalizeCharacterId(value)
    local text = tostring(value or '')
    if text == '' or #text > 64 or not text:match('^%d+$') then return nil end
    return text
end

local function normalizeRankId(value)
    local number = tonumber(value)
    if not number or number < 1 or number ~= math.floor(number) then return nil end
    return number
end

local function decodePermissions(raw)
    if type(raw) ~= 'table' then
        local ok, decoded = pcall(json.decode, raw or '{}')
        raw = ok and decoded or {}
    end
    local result = {}
    if type(raw) ~= 'table' then return result end
    for key, enabled in pairs(raw) do
        key = tostring(key)
        if permissionCatalog[key] and (enabled == true or enabled == 1) then result[key] = true end
    end
    return result
end

local function encodePermissions(raw)
    local filtered = {}
    for key, enabled in pairs(raw or {}) do
        if permissionCatalog[key] and enabled == true then filtered[key] = true end
    end
    return json.encode(filtered)
end

local function indexRank(gang, row)
    local rank = {
        id = tonumber(row.id),
        gangId = row.gang_id,
        tier = tonumber(row.tier),
        name = tostring(row.name),
        permissions = decodePermissions(row.permissions),
        isLeaderRank = CMGangDbTrue(row.is_leader_rank),
    }
    gang.ranksById[rank.id] = rank
    gang.ranksByTier[rank.tier] = rank
end

local syncCharacterState

-- One per-gang mutation gate is shared by normal member management and the
-- cm-admin recovery/configuration paths. This prevents leader/rank operations
-- from racing each other simply because they entered through different files.
CMGangAcquireMutationLock = function(gangId, token)
    if not Config.IsFixedGangId(gangId) or mutationLocks[gangId] ~= nil then return false end
    mutationLocks[gangId] = token or true
    return true
end

CMGangReleaseMutationLock = function(gangId, token)
    if not Config.IsFixedGangId(gangId) then return end
    if token == nil or mutationLocks[gangId] == token then mutationLocks[gangId] = nil end
end

local function loadDomain()
    local gangRows = MySQL.query.await([[
        SELECT gang_id, display_name, short_tag, color, logo_asset, art_asset,
               leader_character_id, enabled
        FROM cm_gangs ORDER BY gang_id
    ]]) or {}
    local rankRows = MySQL.query.await([[
        SELECT id, gang_id, tier, name, permissions, is_leader_rank
        FROM cm_gang_ranks ORDER BY gang_id, tier DESC
    ]]) or {}
    local memberRows = MySQL.query.await([[
        SELECT id, gang_id, character_id, rank_id, is_leader
        FROM cm_gang_members
    ]]) or {}

    local nextGangs = {}
    for _, row in ipairs(gangRows) do
        if Config.IsFixedGangId(row.gang_id) then
            nextGangs[row.gang_id] = {
                id = row.gang_id,
                displayName = tostring(row.display_name),
                shortTag = tostring(row.short_tag),
                color = tostring(row.color),
                logoAsset = row.logo_asset,
                artAsset = row.art_asset,
                leaderCharacterId = normalizeCharacterId(row.leader_character_id),
                enabled = CMGangDbTrue(row.enabled),
                ranksById = {},
                ranksByTier = {},
                members = {},
            }
        end
    end
    for _, row in ipairs(rankRows) do
        local gang = nextGangs[row.gang_id]
        if gang then indexRank(gang, row) end
    end

    local nextMembers = {}
    for _, row in ipairs(memberRows) do
        local gang = nextGangs[row.gang_id]
        local characterId = normalizeCharacterId(row.character_id)
        local rankId = normalizeRankId(row.rank_id)
        local rank = gang and gang.ranksById[rankId]
        if characterId and rank then
            local membership = {
                id = tonumber(row.id), gangId = gang.id, characterId = characterId,
                rankId = rank.id, isLeader = CMGangDbTrue(row.is_leader),
            }
            gang.members[characterId] = membership
            nextMembers[characterId] = membership
        end
    end

    gangs = nextGangs
    membersByCharacter = nextMembers
    domainReady = true
end

local function reloadDomainAndOnlineStates()
    loadDomain()
    for _, playerId in ipairs(GetPlayers()) do
        local ok, characterId = pcall(function()
            return exports[PLAYERDATA]:GetCharacterId(tonumber(playerId))
        end)
        if ok and characterId then syncCharacterState(characterId) end
    end
    return true
end

local function sourceForCharacter(characterId)
    local ok, src = pcall(function()
        return exports[PLAYERDATA]:GetSourceByCharId(tonumber(characterId))
    end)
    return ok and tonumber(src) or nil
end

local function publicMembership(characterId)
    local membership = membersByCharacter[normalizeCharacterId(characterId)]
    if not membership then return nil end
    local gang = gangs[membership.gangId]
    local rank = gang and gang.ranksById[membership.rankId]
    if not gang or not rank then return nil end
    if (rank.isLeaderRank == true) ~= (membership.isLeader == true) then return nil end
    return {
        gangId = gang.id,
        displayName = gang.displayName,
        shortTag = gang.shortTag,
        color = gang.color,
        enabled = gang.enabled,
        rankId = rank.id,
        rankName = rank.name,
        tier = rank.tier,
        isLeader = membership.isLeader,
        permissions = copy(rank.permissions),
    }
end

syncCharacterState = function(characterId)
    local src = sourceForCharacter(characterId)
    if not src then return end
    sourceCharacters[tonumber(src)] = tostring(characterId)
    local membership = publicMembership(characterId)
    local safeState = membership and membership.enabled and {
        gangId = membership.gangId,
        displayName = membership.displayName,
        shortTag = membership.shortTag,
        color = membership.color,
        rankName = membership.rankName,
        tier = membership.tier,
        isLeader = membership.isLeader,
    } or nil
    pcall(function() Player(src).state:set('cmGang', safeState, true) end)
    TriggerEvent('cm-playerdata:server:affiliationIdentityChanged', tonumber(src))
end

local function refreshAndSync(characterIds)
    loadDomain()
    for _, characterId in ipairs(characterIds or {}) do syncCharacterState(characterId) end
end

local function permissionDecision(characterId, permissionKey)
    if not domainReady then return false, 'domain_not_ready' end
    if not permissionCatalog[tostring(permissionKey or '')] then return false, 'unknown_permission' end
    local membership = membersByCharacter[normalizeCharacterId(characterId)]
    if not membership then return false, 'not_in_gang' end
    local gang = gangs[membership.gangId]
    if not gang or not gang.enabled then return false, 'gang_disabled' end
    local rank = gang.ranksById[membership.rankId]
    if not rank then return false, 'invalid_rank' end
    if (rank.isLeaderRank == true) ~= (membership.isLeader == true) then return false, 'leader_state_invalid' end
    if rank.permissions[permissionKey] ~= true then return false, 'no_permission' end
    return true, nil, membership, gang, rank
end

local function activityUid(action)
    return ('%s:%s:%d:%d'):format(RESOURCE, tostring(action), os.time(), math.random(100000, 999999))
end

local function logActivity(gangId, action, actorCharacterId, targetCharacterId, detail)
    MySQL.insert.await([[
        INSERT INTO cm_gang_activity
            (event_uid, gang_id, action, actor_character_id, target_character_id, detail)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        activityUid(action), gangId, tostring(action):sub(1, 64),
        normalizeCharacterId(actorCharacterId), normalizeCharacterId(targetCharacterId),
        detail and json.encode(detail) or nil,
    })
end

local function withMutation(actorCharacterId, gangId, callback)
    local actorId = normalizeCharacterId(actorCharacterId)
    if not actorId or not Config.IsFixedGangId(gangId) then return false, 'invalid_request' end
    local token = ('member:%s:%d'):format(actorId, GetGameTimer())
    if not CMGangAcquireMutationLock(gangId, token) then return false, 'mutation_busy' end
    local now = GetGameTimer()
    if (mutationCooldowns[actorId] or 0) > now then
        CMGangReleaseMutationLock(gangId, token)
        return false, 'rate_limited'
    end
    mutationCooldowns[actorId] = now + ((Config.Security.mutationCooldownSeconds or 2) * 1000)
    local ok, success, result = xpcall(callback, debug.traceback)
    CMGangReleaseMutationLock(gangId, token)
    if not ok then
        print(('[cm-gang] mutation failed: %s'):format(success))
        return false, 'internal_error'
    end
    return success, result
end

local function actorContext(actorCharacterId, permissionKey)
    local allowed, reason, membership, gang, rank = permissionDecision(actorCharacterId, permissionKey)
    if not allowed then return nil, reason end
    return { characterId = normalizeCharacterId(actorCharacterId), membership = membership, gang = gang, rank = rank }
end

local function targetContext(gang, targetCharacterId)
    local characterId = normalizeCharacterId(targetCharacterId)
    local membership = characterId and gang.members[characterId]
    local rank = membership and gang.ranksById[membership.rankId]
    if not membership or not rank then return nil, 'target_not_in_gang' end
    return { characterId = characterId, membership = membership, rank = rank }
end

local function canManageTarget(actor, target)
    if actor.characterId == target.characterId then return false, 'cannot_modify_self' end
    if target.membership.isLeader or target.rank.isLeaderRank then return false, 'leader_protected' end
    if target.rank.tier >= actor.rank.tier then return false, 'hierarchy_denied' end
    return true
end

local function cleanRankName(value)
    local name = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' or #name > Config.Ranks.nameMaximumLength then return nil end
    return name
end

exports('IsDomainReady', function() return domainReady end)
exports('GetGangForCharacter', function(characterId) return copy(publicMembership(characterId)) end)
exports('HasPermission', function(characterId, permissionKey)
    local allowed = permissionDecision(characterId, permissionKey)
    return allowed == true
end)
exports('GetPermissionDecision', function(characterId, permissionKey)
    local allowed, reason = permissionDecision(characterId, permissionKey)
    return { allowed = allowed == true, reason = reason }
end)
exports('GetGang', function(gangId)
    if not domainReady or not Config.IsFixedGangId(gangId) then return nil end
    local gang = copy(gangs[gangId])
    if gang then gang.members = nil end
    return gang
end)
exports('GetGangRanks', function(actorCharacterId)
    local characterId = normalizeCharacterId(actorCharacterId)
    if not characterId then return nil end
    local membership = membersByCharacter[characterId]
    local gang = membership and gangs[membership.gangId] or nil
    if not gang or not gang.enabled then return nil end
    local rank = gang.ranksById[membership.rankId]
    if not rank then return nil end
    local canView = rank.permissions['gang.view_members'] == true
        or rank.permissions['gang.manage_ranks'] == true
        or rank.permissions['gang.manage_permissions'] == true
        or membership.isLeader == true
    if not canView then return nil end
    local result = {}
    for _, item in pairs(gang.ranksById) do result[#result + 1] = copy(item) end
    table.sort(result, function(left, right) return left.tier > right.tier end)
    return result
end)
exports('GetGangMembers', function(actorCharacterId)
    local characterId = normalizeCharacterId(actorCharacterId)
    if not characterId then return nil end
    local membership = membersByCharacter[characterId]
    local gang = membership and gangs[membership.gangId] or nil
    if not gang or not gang.enabled then return nil end
    local rank = gang.ranksById[membership.rankId]
    if not rank then return nil end
    local canView = membership.isLeader == true
        or rank.permissions['gang.view_members'] == true
        or rank.permissions['gang.manage_members'] == true
    if not canView then return nil end
    local result = {}
    for characterId, member in pairs(gang.members) do
        local rank = gang.ranksById[member.rankId]
        result[#result + 1] = {
            characterId = characterId,
            rankId = member.rankId,
            rankName = rank and rank.name or nil,
            tier = rank and rank.tier or nil,
            isLeader = member.isLeader,
        }
    end
    table.sort(result, function(left, right)
        if left.tier ~= right.tier then return (left.tier or 0) > (right.tier or 0) end
        return left.characterId < right.characterId
    end)
    return result
end)

-- Trusted server-resource refresh seam for owner integrations that commit a
-- membership transaction (invitations/admin recovery). It is not networked.
exports('RefreshCharacters', function(characterIds)
    if not domainReady or type(characterIds) ~= 'table' then return false end
    local normalized = {}
    for _, value in ipairs(characterIds) do
        local characterId = normalizeCharacterId(value)
        if characterId then normalized[#normalized + 1] = characterId end
    end
    refreshAndSync(normalized)
    return true
end)

-- Trusted recovery/configuration seam. cm-admin remains the user-facing
-- permission owner; this export independently rechecks the invoking resource
-- and permission before replacing the complete database-backed cache.
local function adminReloadDomain(src, requireInvoker)
    src = tonumber(src)
    if not src or (requireInvoker and GetInvokingResource() ~= 'cm-admin') or GetResourceState('cm-admin') ~= 'started' then
        return false, 'trusted_resource_required'
    end
    local ok, allowed = pcall(function()
        return exports['cm-admin']:HasPermission(src, 'gang.admin.manage')
    end)
    if not ok or allowed ~= true then return false, 'permission_denied' end
    local loaded, result = xpcall(reloadDomainAndOnlineStates, debug.traceback)
    if not loaded then
        print(('[cm-gang] admin domain reload failed: %s'):format(result))
        return false, 'domain_reload_failed'
    end
    return true
end

CMGangReloadDomainForAdmin = function(src)
    return adminReloadDomain(src, false)
end

exports('AdminReloadDomain', function(src)
    return adminReloadDomain(src, true)
end)

exports('CreateRank', function(actorCharacterId, name, tier, permissions)
    local actor = actorContext(actorCharacterId, 'gang.manage_ranks')
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_ranks')
        if not actor then return false, 'not_authorized' end
        name = cleanRankName(name)
        tier = tonumber(tier)
        if not name or not tier or tier ~= math.floor(tier) or tier < 1 or tier > 99 then return false, 'invalid_rank' end
        if tier >= actor.rank.tier or actor.gang.ranksByTier[tier] then return false, 'hierarchy_denied' end
        local count = 0
        for _ in pairs(actor.gang.ranksById) do count = count + 1 end
        if count >= Config.Ranks.maximum then return false, 'rank_limit' end
        local requested = decodePermissions(permissions)
        if next(requested) ~= nil and actor.rank.permissions['gang.manage_permissions'] ~= true then
            return false, 'cannot_grant_permission'
        end
        for key in pairs(requested) do
            if actor.rank.permissions[key] ~= true then return false, 'cannot_grant_permission' end
        end
        local rankId = MySQL.insert.await([[
            INSERT INTO cm_gang_ranks (gang_id, tier, name, permissions, is_leader_rank)
            VALUES (?, ?, ?, ?, 0)
        ]], { actor.gang.id, tier, name, encodePermissions(requested) })
        if not rankId then return false, 'rank_create_failed' end
        logActivity(actor.gang.id, 'rank_created', actor.characterId, nil, { rankId = rankId, tier = tier, name = name })
        refreshAndSync({ actor.characterId })
        return true, tonumber(rankId)
    end)
end)

exports('RenameRank', function(actorCharacterId, rankId, name)
    local actor = actorContext(actorCharacterId, 'gang.manage_ranks')
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_ranks')
        local rank = actor and actor.gang.ranksById[normalizeRankId(rankId)]
        name = cleanRankName(name)
        if not actor or not rank or not name then return false, 'invalid_rank' end
        if rank.isLeaderRank or rank.tier >= actor.rank.tier then return false, 'hierarchy_denied' end
        local changed = MySQL.update.await('UPDATE cm_gang_ranks SET name = ? WHERE id = ? AND gang_id = ?',
            { name, rank.id, actor.gang.id })
        if tonumber(changed) ~= 1 then return false, 'rank_update_failed' end
        logActivity(actor.gang.id, 'rank_renamed', actor.characterId, nil, { rankId = rank.id, name = name })
        refreshAndSync({ actor.characterId })
        return true
    end)
end)

exports('SetRankTier', function(actorCharacterId, rankId, tier)
    local actor = actorContext(actorCharacterId, 'gang.manage_ranks')
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_ranks')
        local rank = actor and actor.gang.ranksById[normalizeRankId(rankId)]
        tier = tonumber(tier)
        if not actor or not rank or not tier or tier ~= math.floor(tier) or tier < 1 or tier > 99 then
            return false, 'invalid_rank'
        end
        if rank.isLeaderRank or rank.tier >= actor.rank.tier or tier >= actor.rank.tier then
            return false, 'hierarchy_denied'
        end
        if actor.gang.ranksByTier[tier] then return false, 'tier_in_use' end
        local changed = MySQL.update.await('UPDATE cm_gang_ranks SET tier = ? WHERE id = ? AND gang_id = ?',
            { tier, rank.id, actor.gang.id })
        if tonumber(changed) ~= 1 then return false, 'rank_update_failed' end
        logActivity(actor.gang.id, 'rank_retiered', actor.characterId, nil,
            { rankId = rank.id, previousTier = rank.tier, tier = tier })
        local affected = { actor.characterId }
        for characterId, member in pairs(actor.gang.members) do
            if member.rankId == rank.id then affected[#affected + 1] = characterId end
        end
        refreshAndSync(affected)
        return true
    end)
end)

exports('SetRankPermission', function(actorCharacterId, rankId, permissionKey, enabled)
    local actor = actorContext(actorCharacterId, 'gang.manage_permissions')
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_permissions')
        local rank = actor and actor.gang.ranksById[normalizeRankId(rankId)]
        permissionKey = tostring(permissionKey or '')
        if not actor or not rank or not permissionCatalog[permissionKey] then return false, 'invalid_permission' end
        if rank.isLeaderRank or rank.tier >= actor.rank.tier then return false, 'hierarchy_denied' end
        if enabled == true and actor.rank.permissions[permissionKey] ~= true then return false, 'cannot_grant_permission' end
        local nextPermissions = copy(rank.permissions)
        nextPermissions[permissionKey] = enabled == true or nil
        local changed = MySQL.update.await('UPDATE cm_gang_ranks SET permissions = ? WHERE id = ? AND gang_id = ?',
            { encodePermissions(nextPermissions), rank.id, actor.gang.id })
        if tonumber(changed) ~= 1 then return false, 'rank_update_failed' end
        logActivity(actor.gang.id, 'rank_permission_changed', actor.characterId, nil,
            { rankId = rank.id, permission = permissionKey, enabled = enabled == true })
        local affected = {}
        for characterId, membership in pairs(actor.gang.members) do
            if membership.rankId == rank.id then affected[#affected + 1] = characterId end
        end
        refreshAndSync(affected)
        return true
    end)
end)

exports('UpdateRank', function(actorCharacterId, rankId, name, tier, permissions)
    local actor = actorContext(actorCharacterId, 'gang.manage_ranks')
    if not actor then actor = actorContext(actorCharacterId, 'gang.manage_permissions') end
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_ranks')
        if not actor then actor = actorContext(actorCharacterId, 'gang.manage_permissions') end
        local rank = actor and actor.gang.ranksById[normalizeRankId(rankId)]
        if not actor or not rank then return false, 'invalid_rank' end
        if rank.isLeaderRank or rank.tier >= actor.rank.tier then return false, 'hierarchy_denied' end

        local canManageRanks = actor.rank.permissions['gang.manage_ranks'] == true
        local canManagePermissions = actor.rank.permissions['gang.manage_permissions'] == true
        local nextName, nextTier = rank.name, rank.tier
        if canManageRanks then
            nextName = cleanRankName(name)
            nextTier = tonumber(tier)
            if not nextName or not nextTier or nextTier ~= math.floor(nextTier) or nextTier < 1 or nextTier > 99 then
                return false, 'invalid_rank'
            end
            if nextTier >= actor.rank.tier then return false, 'hierarchy_denied' end
            local tierOwner = actor.gang.ranksByTier[nextTier]
            if tierOwner and tierOwner.id ~= rank.id then return false, 'tier_in_use' end
        end

        local requested = copy(rank.permissions)
        if canManagePermissions then
            requested = decodePermissions(permissions)
            for key in pairs(requested) do
                if actor.rank.permissions[key] ~= true then return false, 'cannot_grant_permission' end
            end
        end

        local changed = MySQL.update.await([[
            UPDATE cm_gang_ranks SET name = ?, tier = ?, permissions = ?
            WHERE id = ? AND gang_id = ? AND is_leader_rank = 0
        ]], { nextName, nextTier, encodePermissions(requested), rank.id, actor.gang.id })
        if tonumber(changed) ~= 1 then return false, 'rank_update_failed' end
        logActivity(actor.gang.id, 'rank_updated', actor.characterId, nil, {
            rankId = rank.id, previousName = rank.name, name = nextName,
            previousTier = rank.tier, tier = nextTier,
            permissionsChanged = canManagePermissions,
        })
        local affected = { actor.characterId }
        for characterId, membership in pairs(actor.gang.members) do
            if membership.rankId == rank.id then affected[#affected + 1] = characterId end
        end
        refreshAndSync(affected)
        return true
    end)
end)

exports('DeleteRank', function(actorCharacterId, rankId)
    local actor = actorContext(actorCharacterId, 'gang.manage_ranks')
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_ranks')
        local rank = actor and actor.gang.ranksById[normalizeRankId(rankId)]
        if not actor or not rank then return false, 'invalid_rank' end
        if rank.isLeaderRank or rank.tier >= actor.rank.tier then return false, 'hierarchy_denied' end
        for _, membership in pairs(actor.gang.members) do
            if membership.rankId == rank.id then return false, 'rank_in_use' end
        end
        local nonLeaderCount = 0
        for _, existingRank in pairs(actor.gang.ranksById) do
            if existingRank.isLeaderRank ~= true then nonLeaderCount = nonLeaderCount + 1 end
        end
        if nonLeaderCount <= 1 then return false, 'last_nonleader_rank_protected' end
        local changed = MySQL.update.await('DELETE FROM cm_gang_ranks WHERE id = ? AND gang_id = ?', { rank.id, actor.gang.id })
        if tonumber(changed) ~= 1 then return false, 'rank_delete_failed' end
        logActivity(actor.gang.id, 'rank_deleted', actor.characterId, nil, { rankId = rank.id, name = rank.name })
        refreshAndSync({ actor.characterId })
        return true
    end)
end)

exports('AssignMemberRank', function(actorCharacterId, targetCharacterId, rankId)
    local actor = actorContext(actorCharacterId, 'gang.manage_members')
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_members')
        local target = actor and targetContext(actor.gang, targetCharacterId)
        local destination = actor and actor.gang.ranksById[normalizeRankId(rankId)]
        if not actor or not target or not destination then return false, 'invalid_member_or_rank' end
        local allowed, reason = canManageTarget(actor, target)
        if not allowed then return false, reason end
        if destination.isLeaderRank or destination.tier >= actor.rank.tier then return false, 'hierarchy_denied' end
        if destination.id == target.rank.id then return true end
        local changed = MySQL.update.await([[
            UPDATE cm_gang_members SET rank_id = ?
            WHERE gang_id = ? AND character_id = ? AND is_leader = 0
        ]], { destination.id, actor.gang.id, target.characterId })
        if tonumber(changed) ~= 1 then return false, 'member_update_failed' end
        logActivity(actor.gang.id, destination.tier > target.rank.tier and 'member_promoted' or 'member_demoted',
            actor.characterId, target.characterId, { fromRankId = target.rank.id, toRankId = destination.id })
        refreshAndSync({ actor.characterId, target.characterId })
        return true
    end)
end)

exports('RemoveMember', function(actorCharacterId, targetCharacterId)
    local actor = actorContext(actorCharacterId, 'gang.manage_members')
    if not actor then return false, 'not_authorized' end
    return withMutation(actor.characterId, actor.gang.id, function()
        actor = actorContext(actor.characterId, 'gang.manage_members')
        local target = actor and targetContext(actor.gang, targetCharacterId)
        if not actor or not target then return false, 'target_not_in_gang' end
        local allowed, reason = canManageTarget(actor, target)
        if not allowed then return false, reason end
        local changed = MySQL.update.await([[
            DELETE FROM cm_gang_members WHERE gang_id = ? AND character_id = ? AND is_leader = 0
        ]], { actor.gang.id, target.characterId })
        if tonumber(changed) ~= 1 then return false, 'member_remove_failed' end
        logActivity(actor.gang.id, 'member_removed', actor.characterId, target.characterId, { rankId = target.rank.id })
        refreshAndSync({ actor.characterId, target.characterId })
        return true
    end)
end)

exports('TransferLeadership', function(actorCharacterId, targetCharacterId)
    -- Compatibility stub: leadership is deliberately admin-only. Keeping the
    -- export avoids a nil-export crash in an older consumer while failing closed.
    return false, 'admin_only_leadership'
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    if not domainReady then return end
    local characterId = normalizeCharacterId(data and (data.charId or data.characterId))
    if not characterId then
        local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(src) end)
        characterId = ok and normalizeCharacterId(value) or nil
    end
    if characterId then
        sourceCharacters[tonumber(src)] = characterId
        syncCharacterState(characterId)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local characterId = sourceCharacters[src]
    sourceCharacters[src] = nil
    if not characterId then
        local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(src) end)
        characterId = ok and normalizeCharacterId(value) or nil
    end
    if characterId then mutationCooldowns[characterId] = nil end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    mutationLocks = {}
    mutationCooldowns = {}
    sourceCharacters = {}
end)

MySQL.ready(function()
    CreateThread(function()
        while not CMGangDatabaseReady do
            if CMGangDatabaseError and CMGangDatabaseError ~= 'initializing' then return end
            Wait(100)
        end
        local ok, err = xpcall(loadDomain, debug.traceback)
        if not ok then
            domainReady = false
            print(('[cm-gang] domain load failed: %s'):format(err))
            return
        end
        for _, playerId in ipairs(GetPlayers()) do
            local okId, characterId = pcall(function() return exports[PLAYERDATA]:GetCharacterId(tonumber(playerId)) end)
            if okId and characterId then syncCharacterState(characterId) end
        end
        print('^2[cm-gang] owner domain ready^7')
    end)
end)
