-- cm-family | rank-gated admin diagnostics and bounded recovery actions.
local B = CMFamilyBridge
local recoveryLocks = {}

local function adminAllowed(src, permission)
    src = tonumber(src)
    if not src or src <= 0 or GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
    return ok and allowed == true
end

local function canOpen(src)
    return adminAllowed(src, 'family.admin.open')
        or adminAllowed(src, 'family.admin.recovery')
end

local function canRecover(src)
    return adminAllowed(src, 'family.admin.recovery')
end

local function adminLog(src, action, details)
    TriggerEvent('cm-admin:server:addLog', src, action, {
        category = 'family', details = details or {},
    })
end

local function collectFamilies()
    local rows = MySQL.query.await([[
        SELECT f.id, f.name, f.tag, f.founder_cid, f.house_id, f.created_at,
               h.id AS house_exists, h.family_id AS house_family_id, h.owner_cid AS house_owner_cid,
               (SELECT COUNT(*) FROM cm_family_members m WHERE m.family_id = f.id) AS member_count,
               (SELECT COUNT(*) FROM cm_family_ranks r WHERE r.family_id = f.id) AS rank_count,
               (SELECT COUNT(*) FROM cm_family_invites i WHERE i.family_id = f.id AND i.expires_at > NOW()) AS pending_invites,
               (SELECT COUNT(*) FROM cm_family_invites i WHERE i.family_id = f.id AND i.expires_at <= NOW()) AS expired_invites,
               (SELECT COUNT(*) FROM cm_family_members fm WHERE fm.family_id = f.id AND fm.character_id = f.founder_cid) AS founder_member,
               (SELECT COUNT(*) FROM cm_family_members m LEFT JOIN cm_family_ranks r ON r.id = m.rank_id
                  WHERE m.family_id = f.id AND r.id IS NULL) AS missing_rank_members
        FROM cm_families f
        LEFT JOIN cm_houses h ON h.id = f.house_id
        ORDER BY f.id DESC
    ]]) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local issues = {}
        if row.house_id == nil then issues[#issues + 1] = 'No linked house' end
        if row.house_id ~= nil and row.house_exists == nil then issues[#issues + 1] = 'Linked house is missing' end
        if row.house_exists ~= nil and tonumber(row.house_family_id) ~= tonumber(row.id) then issues[#issues + 1] = 'House family link mismatch' end
        if tonumber(row.founder_member) ~= 1 then issues[#issues + 1] = 'Founder membership missing' end
        if tonumber(row.missing_rank_members) > 0 then issues[#issues + 1] = ('%d member(s) have a missing rank'):format(tonumber(row.missing_rank_members)) end
        if tonumber(row.expired_invites) > 0 then issues[#issues + 1] = ('%d expired invitation(s)'):format(tonumber(row.expired_invites)) end
        out[#out + 1] = {
            id = tonumber(row.id), name = tostring(row.name or 'Family'), tag = row.tag,
            founderCid = tostring(row.founder_cid or ''), founderName = B.GetCharName(row.founder_cid),
            houseId = tonumber(row.house_id), memberCount = tonumber(row.member_count) or 0,
            rankCount = tonumber(row.rank_count) or 0, pendingInvites = tonumber(row.pending_invites) or 0,
            expiredInvites = tonumber(row.expired_invites) or 0,
            issues = issues, healthy = #issues == 0, createdAt = tostring(row.created_at or ''),
        }
    end
    return out
end

lib.callback.register('cm-family:server:adminData', function(src)
    if not canOpen(src) then return nil end
    local logs = {}
    if adminAllowed(src, 'family.logs.view') or adminAllowed(src, 'admin.logs.view') then
        logs = MySQL.query.await([[
            SELECT id, family_id, action, severity, status, actor_cid, actor_name, detail, created_at
            FROM cm_family_activity_log WHERE high_risk = 1 ORDER BY id DESC LIMIT 100
        ]]) or {}
    end
    return { families = collectFamilies(), highRisk = logs, canRecover = canRecover(src) }
end)

local function refreshFamily(familyId)
    local fam = Families[familyId]
    if not fam then return false, 'The family is not loaded; restart recovery requires database review.' end
    SyncFamilyState(familyId)
    for cid, membership in pairs(MemberByCid or {}) do
        if tonumber(membership.family_id) == familyId then SyncFamilyMemberState(cid) end
    end
    B.RefreshFamilyMembers(familyId)
    B.RefreshFamilyAccess(familyId)
    return true, 'Family, member, and house-access state refreshed.'
end

local function repairFounder(familyId)
    local row = MySQL.single.await([[
        SELECT f.founder_cid, f.house_id, h.owner_cid
        FROM cm_families f JOIN cm_houses h ON h.id = f.house_id AND h.family_id = f.id
        WHERE f.id = ? LIMIT 1
    ]], { familyId })
    if not row or tostring(row.founder_cid or '') == '' then
        return false, 'The family/house ownership relationship is not safe to repair automatically.'
    end
    local characterExists = MySQL.scalar.await(
        'SELECT id FROM characters WHERE id = ? LIMIT 1', { tostring(row.founder_cid) })
    if not characterExists then
        return false, 'The recorded founder character no longer exists; manual review is required.'
    end
    local founderRank = MySQL.single.await([[
        SELECT id FROM cm_family_ranks WHERE family_id = ?
        ORDER BY is_founder DESC, tier DESC LIMIT 1
    ]], { familyId })
    if not founderRank then return false, 'The family has no founder rank.' end
    local member = MySQL.single.await(
        'SELECT character_id FROM cm_family_members WHERE family_id = ? AND character_id = ? LIMIT 1',
        { familyId, tostring(row.founder_cid) })
    if member then
        MySQL.update.await('UPDATE cm_family_members SET rank_id = ? WHERE family_id = ? AND character_id = ?',
            { founderRank.id, familyId, tostring(row.founder_cid) })
    else
        local inserted, why = CMFamilyInsertMember(familyId, tostring(row.founder_cid), founderRank.id)
        if not inserted then return false, 'Founder membership repair failed: ' .. tostring(why) end
    end
    MemberByCid[tostring(row.founder_cid)] = {
        family_id = familyId, rank_id = tonumber(founderRank.id) or founderRank.id,
        custom_title = nil, tag_hidden = false,
    }
    return refreshFamily(familyId)
end

lib.callback.register('cm-family:server:adminAction', function(src, action, familyId)
    if not canRecover(src) then return false, 'You do not have family recovery permission.' end
    familyId = tonumber(familyId)
    if not familyId then return false, 'Invalid family.' end
    if recoveryLocks[familyId] then return false, 'That family already has a recovery operation running.' end
    local allowed = { refresh = true, repair_founder = true, clear_expired_invites = true }
    if not allowed[action] then return false, 'Unknown recovery action.' end
    recoveryLocks[familyId] = true
    local ok, result, detail = xpcall(function()
        if action == 'refresh' then return refreshFamily(familyId) end
        if action == 'repair_founder' then return repairFounder(familyId) end
        local deleted = tonumber(MySQL.update.await(
            'DELETE FROM cm_family_invites WHERE family_id = ? AND expires_at <= NOW()', { familyId })) or 0
        return true, ('Removed %d expired invitation(s).'):format(deleted)
    end, debug.traceback)
    recoveryLocks[familyId] = nil
    if not ok then
        print(('[cm-family] admin recovery failed family=%s action=%s: %s'):format(familyId, action, result))
        return false, 'Recovery failed unexpectedly; review the server log.'
    end
    if result ~= true then return false, detail or 'Recovery was rejected.' end
    local adminCid = B.GetCid(src)
    LogFamily(familyId, adminCid, 'admin_family_recovery', { action = action })
    adminLog(src, 'family_recovery', { familyId = familyId, action = action })
    return true, detail or 'Recovery completed.'
end)

AddEventHandler('cm-family:dev:openAdmin', function(src)
    src = tonumber(src)
    if not canOpen(src) then return end
    TriggerClientEvent('cm-family:client:openAdmin', src)
end)

CreateThread(function()
    while GetResourceState('cm-admin') ~= 'started' do Wait(5000) end
    pcall(function()
        exports['cm-admin']:RegisterDevTool({
            id = 'family', label = 'Family Admin', category = 'World', icon = 'users',
            permission = 'family.admin.open',
            actions = {{ id = 'open', label = 'Open Family Admin', type = 'launcher', realm = 'server',
                event = 'cm-family:dev:openAdmin', hint = 'Inspect families, recovery issues, and high-risk activity.' }},
        })
    end)
end)
