-- ============================================================
--  cm-family | sv_menu.lua
--  The NPC create/join flow, the owned-house pick list, and every callback the
--  /family full-screen menu uses. All callbacks resolve the caller's cid from
--  `source` (never trust a client-supplied id).
-- ============================================================

local B = CMFamilyBridge

local function cidOf(src)
    return B.GetCid(src)
end

local function databaseReady()
    if not CMFamilyIsDatabaseReady then return false, 'database_not_initialized' end
    local ready, err = CMFamilyIsDatabaseReady()
    if ready then return true end
    return false, err or 'database_not_ready'
end

local creationLocks = {}
local announcementCooldowns = {}

local function rollbackFamily(familyId)
    familyId = tonumber(familyId)
    if not familyId then return true end

    if type(CMFamilyDeleteFamilyRows) ~= 'function' then
        print(('[cm-family] rollback failed for family %s: delete helper is unavailable'):format(familyId))
        return false
    end

    local deleted, err = CMFamilyDeleteFamilyRows(familyId)
    if not deleted then
        print(('[cm-family] rollback failed for family %s: %s'):format(familyId, tostring(err)))
        return false
    end
    return true
end

-- ---------- house pick list for "create my family" ----------
-- Returns houses the caller OWNS and that cm-house will accept as a family
-- house (family_eligible, not an apartment). cm-house's GetHousesForCharacter
-- returns owner+family houses; we filter to owner-only and eligible.
local function ownedEligibleHouses(cid)
    local houses = B.GetHousesForCharacter(cid)
    local out = {}
    for _, h in ipairs(houses) do
        local isOwner = tostring(h.access_kind or '') == 'owner'
        local notApartment = tostring(h.house_type or '') ~= 'apartment'
        local eligible = h.family_eligible == true or h.family_eligible == 1
        if isOwner and notApartment and eligible and not h.family_id then
            out[#out + 1] = {
                id = h.id,
                label = h.label or ('House #' .. tostring(h.house_number or h.id)),
                number = h.house_number,
                type = h.house_type,
                image = h.image_url,
            }
        end
    end
    return out
end

lib.callback.register('cm-family:server:getCreationHouses', function(src)
    local ready = databaseReady()
    if not ready then return { ok = false, reason = 'database_not_ready', message = 'Family database is still initializing.' } end
    local cid = cidOf(src)
    if not cid then return { ok = false, reason = 'character_not_loaded' } end
    if GetMembership(cid) then return { ok = false, reason = 'already_in_family' } end
    local houses = ownedEligibleHouses(cid)
    if #houses == 0 then
        return { ok = false, reason = 'no_house',
            message = "You don't own any house eligible to become a family house." }
    end
    return { ok = true, houses = houses }
end)

-- ---------- create the family ----------
lib.callback.register('cm-family:server:createFamily', function(src, data)
    local ready, dbErr = databaseReady()
    if not ready then return false, ('Family database is not ready: %s'):format(tostring(dbErr)) end

    local cid = cidOf(src)
    if not cid then return false, 'character_not_loaded' end
    local lockKey = tostring(cid)
    if creationLocks[lockKey] then return false, 'A family creation request is already running.' end
    if GetMembership(cid) then return false, 'You are already in a family.' end

    data = type(data) == 'table' and data or {}
    local name = tostring(data.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local houseId = tonumber(data.houseId)
    local tag = data.tag and tostring(data.tag):gsub('^%s+', ''):gsub('%s+$', '') or nil
    if tag == '' then tag = nil end
    if tag then tag = tag:sub(1, Config.Create.tagMaxLength) end
    local color = tostring(data.color or '#00f0ff'):sub(1, 9)

    if #name < Config.Create.minNameLength or #name > Config.Create.maxNameLength then
        return false, ('Family name must be %d-%d characters.'):format(Config.Create.minNameLength, Config.Create.maxNameLength)
    end
    if not houseId then return false, 'Pick a house to become the family house.' end
    if not color:match('^#%x%x%x%x%x%x%x?%x?$') then color = '#00f0ff' end

    -- Confirm the caller still owns an eligible copy of that house.
    local eligible = false
    for _, h in ipairs(ownedEligibleHouses(cid)) do
        if tonumber(h.id) == houseId then eligible = true break end
    end
    if not eligible then return false, 'That house cannot become a family house.' end

    -- Unique name check (case-insensitive). The DB unique index remains the
    -- final authority against two simultaneous requests.
    local existing = MySQL.scalar.await('SELECT id FROM cm_families WHERE LOWER(name) = LOWER(?) LIMIT 1', { name })
    if existing then return false, 'A family with that name already exists.' end

    creationLocks[lockKey] = true
    local familyId
    local charged = false
    local houseLinked = false

    local ok, resultA, resultB = xpcall(function()
        if (Config.Create.creationFee or 0) > 0 then
            if not B.RemoveMoney(src, Config.Create.creationFee, 'family_creation_fee') then
                return false, ('You need $%d to found a family.'):format(Config.Create.creationFee)
            end
            charged = true
        end

        familyId = tonumber(MySQL.insert.await(
            'INSERT INTO cm_families (name, tag, color, founder_cid, house_id) VALUES (?, ?, ?, ?, ?)',
            { name, tag, color, tostring(cid), houseId }))
        if not familyId or familyId <= 0 then
            error('family_insert_failed')
        end

        -- Register a provisional cache entry so the rank loader can attach the
        -- default ranks. It is removed by rollback on every failure path.
        Families[familyId] = {
            id = familyId, name = name, tag = tag, color = color, tag_visible = true,
            founder_cid = tostring(cid), house_id = houseId, bank_balance = 0,
            ranks = {}, ranksById = {},
        }

        local founderRankId, rankErr = CreateDefaultRanks(familyId)
        if not founderRankId then error(rankErr or 'default_rank_creation_failed') end

        -- cm_family_members may intentionally have no AUTO_INCREMENT id in
        -- legacy installations. Confirm the affected row count instead of
        -- requiring an insert id that such tables cannot return.
        local memberInserted, memberErr = CMFamilyInsertMember(familyId, tostring(cid), founderRankId)
        if not memberInserted then
            error(('founder_membership_insert_failed:%s'):format(tostring(memberErr or 'unknown')))
        end

        -- Publish membership before linking the property so every family
        -- permission export is ready immediately. cm-house also verifies the
        -- committed membership row directly, avoiding a circular export call.
        -- Every failure path below clears this provisional cache entry and
        -- removes the inserted DB rows, so it cannot survive a failed create.
        MemberByCid[tostring(cid)] = { family_id = familyId, rank_id = founderRankId, custom_title = nil, tag_hidden = false }

        local provisional = GetMembership(cid)
        if not provisional or tonumber(provisional.family_id) ~= familyId then
            error('founder_membership_cache_failed')
        end

        local linked, why = B.SetFamilyHouseLink(houseId, familyId, cid)
        if not linked then
            error(('house_link_failed:%s'):format(tostring(why or 'unknown')))
        end
        houseLinked = true
        LogFamily(familyId, cid, 'family_created', { houseId = houseId, name = name })
        SyncFamilyMemberState(cid)
        B.RefreshFamilyMembers(familyId)
        B.RefreshFamilyAccess(familyId)
        return true, familyId
    end, debug.traceback)

    creationLocks[lockKey] = nil

    if not ok then
        print(('[cm-family] create family failed for cid %s: %s'):format(tostring(cid), tostring(resultA)))
        if houseLinked then
            pcall(function() B.SetFamilyHouseLink(houseId, nil, cid) end)
        end
        MemberByCid[tostring(cid)] = nil
        if familyId then Families[familyId] = nil end
        rollbackFamily(familyId)
        if charged then B.AddMoney(src, Config.Create.creationFee, 'family_creation_refund') end
        return false, 'Family creation failed safely. No family or fee was kept.'
    end

    -- The guarded function can return a normal validation failure after the
    -- lock is acquired (currently only the creation fee path).
    if resultA ~= true then
        if charged then B.AddMoney(src, Config.Create.creationFee, 'family_creation_refund') end
        return false, resultB or 'family_creation_failed'
    end

    return true, resultB
end)

-- ---------- full family snapshot for the menu ----------
local function buildMemberList(fam)
    local out = {}
    local rows = MySQL.query.await([[
        SELECT m.character_id, m.rank_id, m.custom_title, m.tag_hidden, m.joined_at,
               c.last_seen,
               COALESCE(b.total_contributed, 0) AS total_contributed,
               COALESCE(b.week_contributed, 0) AS week_contributed,
               COALESCE(a.week_actions, 0) AS week_actions
        FROM cm_family_members m
        LEFT JOIN characters c ON c.id = m.character_id
        LEFT JOIN (
            SELECT character_id,
                   SUM(CASE WHEN direction = 'deposit' THEN amount ELSE 0 END) AS total_contributed,
                   SUM(CASE WHEN direction = 'deposit' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN amount ELSE 0 END) AS week_contributed
            FROM cm_family_bank_log
            WHERE family_id = ?
            GROUP BY character_id
        ) b ON b.character_id = m.character_id
        LEFT JOIN (
            SELECT actor_cid, COUNT(*) AS week_actions
            FROM cm_family_activity_log
            WHERE family_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
              AND actor_cid IS NOT NULL AND actor_cid <> ''
            GROUP BY actor_cid
        ) a ON a.actor_cid = m.character_id
        WHERE m.family_id = ?
    ]], { fam.id, fam.id, fam.id }) or {}
    for _, m in ipairs(rows) do
        local rankId = tonumber(m.rank_id) or m.rank_id
        local rank = fam.ranksById[rankId]
        local online = B.GetSrcByCid(m.character_id) ~= nil
        out[#out + 1] = {
            cid = m.character_id,
            name = B.GetCharName(m.character_id),
            rankId = rankId,
            rankName = rank and rank.name or '?',
            tier = rank and rank.tier or 0,
            isFounder = rank and rank.is_founder or false,
            online = online,
            customTitle = m.custom_title,
            tagHidden = tonumber(m.tag_hidden) == 1,
            joinedAt = m.joined_at,
            lastSeen = online and nil or m.last_seen,
            totalContribution = tonumber(m.total_contributed) or 0,
            weeklyContribution = tonumber(m.week_contributed) or 0,
            weeklyActions = tonumber(m.week_actions) or 0,
        }
    end
    table.sort(out, function(a, b) return (a.tier or 0) > (b.tier or 0) end)
    return out
end

local function buildWeeklyStats(fam)
    local bank = MySQL.single.await([[
        SELECT
            COALESCE(SUM(CASE WHEN direction = 'deposit' THEN amount ELSE 0 END), 0) AS deposits,
            COALESCE(SUM(CASE WHEN direction = 'withdraw' THEN amount ELSE 0 END), 0) AS withdrawals,
            COUNT(*) AS transactions
        FROM cm_family_bank_log
        WHERE family_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    ]], { fam.id }) or {}
    local activity = MySQL.single.await([[
        SELECT COUNT(*) AS actions, COUNT(DISTINCT actor_cid) AS active_members
        FROM cm_family_activity_log
        WHERE family_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    ]], { fam.id }) or {}
    local joined = MySQL.scalar.await([[
        SELECT COUNT(*) FROM cm_family_members
        WHERE family_id = ? AND joined_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    ]], { fam.id })
    return {
        deposits = tonumber(bank.deposits) or 0,
        withdrawals = tonumber(bank.withdrawals) or 0,
        transactions = tonumber(bank.transactions) or 0,
        actions = tonumber(activity.actions) or 0,
        activeMembers = tonumber(activity.active_members) or 0,
        newMembers = tonumber(joined) or 0,
    }
end

local function buildRankList(fam)
    local out = {}
    for _, r in pairs(fam.ranksById) do
        local perms = {}
        for _, p in ipairs(Config.Permissions) do perms[p.key] = r.permissions[p.key] == true or r.is_founder end
        out[#out + 1] = {
            id = r.id, tier = r.tier, name = r.name, isFounder = r.is_founder,
            bankDailyLimit = r.bank_daily_limit,
            symbol = CMFamilyNormalizeSymbol(r.overhead_symbol),
            symbolColor = CMFamilyNormalizeSymbolColor(r.overhead_color, fam.color),
            permissions = perms,
        }
    end
    table.sort(out, function(a, b) return a.tier > b.tier end)
    return out
end

lib.callback.register('cm-family:server:getMenu', function(src)
    local ready = databaseReady()
    if not ready then return { ok = false, reason = 'database_not_ready' } end
    local cid = cidOf(src)
    if not cid then return { ok = false, reason = 'character_not_loaded' } end
    local rank, fam = GetRankForCid(cid)
    if not rank or not fam then
        return { ok = false, reason = 'not_in_family', invite = GetPendingInvite(cid) }
    end

    local viewerMembership = GetMembership(cid) or {}
    local viewer = {
        cid = cid, rankId = rank.id, tier = rank.tier, isFounder = rank.is_founder,
        customTitle = viewerMembership.custom_title,
        tagHidden = false,
        symbol = CMFamilyNormalizeSymbol(fam.symbol),
        symbolColor = CMFamilyNormalizeSymbolColor(fam.color),
        permissions = {},
    }
    for _, p in ipairs(Config.Permissions) do viewer.permissions[p.key] = RankHasPermission(rank, p.key) end

    return {
        ok = true,
        family = {
            id = fam.id, name = fam.name, tag = fam.tag, color = fam.color,
            symbol = CMFamilyNormalizeSymbol(fam.symbol),
            houseId = fam.house_id, bankBalance = fam.bank_balance,
            founderCid = fam.founder_cid,
            announcement = fam.announcement,
            announcementBy = fam.announcement_by,
            announcementByName = fam.announcement_by and B.GetCharName(fam.announcement_by) or nil,
            announcementAt = fam.announcement_at,
            tagVisible = false,
            symbolVisible = true,
        },
        viewer = viewer,
        members = buildMemberList(fam),
        weeklyStats = buildWeeklyStats(fam),
        ranks = buildRankList(fam),
        vehicles = GetFamilyVehiclesWithLevels(fam.id, cid),
        bankLog = RankHasPermission(rank, 'bank.view') and GetBankLog(fam.id, 30) or {},
        activityLog = ((CMFamilyIsFounder and CMFamilyIsFounder(cid, fam)) or RankHasPermission(rank, 'family.view_logs'))
            and GetFamilyActivityLogs(fam.id, { limit = Config.Audit and Config.Audit.menuLimit or 75 }) or false,
        permissionCatalog = (function()
            local visible = {}
            for _, permission in ipairs(Config.Permissions or {}) do
                if tostring(permission.group or '') ~= 'bank' then
                    visible[#visible + 1] = permission
                end
            end
            return visible
        end)(),
        symbolCatalog = (function()
            local out = {}
            for _, key in ipairs((Config.Identity and Config.Identity.symbolOrder) or {}) do
                local entry = Config.Identity.allowedSymbols and Config.Identity.allowedSymbols[key]
                if entry then out[#out + 1] = { key = key, label = entry.label or key } end
            end
            return out
        end)(),
        maxRanks = Config.MaxRanks,
    }
end)

-- ---------- family meeting point ----------
-- Kept beside the action callback so registration and implementation load as one unit.
local meetingCooldowns = {}
local MEETING_COOLDOWN_MS = 10000

local function validMeetingCoordinate(value, limit)
    value = tonumber(value)
    return value and value == value and math.abs(value) <= limit and value or nil
end

function CMFamilySetMeetingPoint(src, actorCid, payload)
    src = tonumber(src)
    payload = type(payload) == 'table' and payload or {}
    local rank, fam = GetRankForCid(actorCid)
    if not src or not rank or not fam then return false, 'not_in_family' end
    if not RankHasPermission(rank, 'family.set_meeting') then return false, 'no_permission' end

    local now = GetGameTimer()
    local nextAllowed = meetingCooldowns[src] or 0
    if now < nextAllowed then
        return false, ('Please wait %d seconds before setting another meeting point.'):format(math.ceil((nextAllowed - now) / 1000))
    end

    local x = validMeetingCoordinate(payload.x, 10000.0)
    local y = validMeetingCoordinate(payload.y, 10000.0)
    local z = validMeetingCoordinate(payload.z, 2500.0)
    if not x or not y or not z then return false, 'invalid_location' end

    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local serverCoords = GetEntityCoords(ped)
        if serverCoords and #(serverCoords - vector3(x, y, z)) > 25.0 then
            return false, 'location_mismatch'
        end
    end

    meetingCooldowns[src] = now + MEETING_COOLDOWN_MS
    local setterName = B.GetCharName(actorCid)
    local recipients = 0
    for memberCid, membership in pairs(MemberByCid) do
        if tonumber(membership.family_id) == tonumber(fam.id) then
            local memberSrc = B.GetSrcByCid(memberCid)
            if memberSrc then
                TriggerClientEvent('cm-family:client:setMeetingPoint', memberSrc, {
                    x = x, y = y, z = z, setterName = setterName,
                })
                recipients = recipients + 1
            end
        end
    end

    LogFamily(fam.id, actorCid, 'meeting_point_set', { x = x, y = y, z = z, recipients = recipients })
    return true, ('Meeting point sent to %d online family member%s.'):format(recipients, recipients == 1 and '' or 's')
end

AddEventHandler('playerDropped', function()
    meetingCooldowns[source] = nil
end)

-- ---------- action router ----------
-- One callback for every mutating menu action keeps the client simple and the
-- authority checks centralized (each handler resolves cid from source).
lib.callback.register('cm-family:server:action', function(src, action, payload)
    local ready = databaseReady()
    if not ready then return false, 'database_not_ready' end
    local cid = cidOf(src)
    if not cid then return false, 'character_not_loaded' end
    payload = type(payload) == 'table' and payload or {}
    action = tostring(action or '')

    if action == 'invite' then
        return InviteMember(cid, payload.targetCid, payload.rankId)
    elseif action == 'respondInvite' then
        return RespondToInvite(cid, payload.accept == true, payload.inviteId, payload.familyId)
    elseif action == 'kick' then
        return KickMember(cid, payload.targetCid)
    elseif action == 'leave' then
        return LeaveFamily(cid)
    elseif action == 'setMemberRank' then
        return SetMemberRank(cid, payload.targetCid, payload.rankId)
    elseif action == 'promote' then
        return PromoteMember(cid, payload.targetCid)
    elseif action == 'demote' then
        return DemoteMember(cid, payload.targetCid)
    elseif action == 'setMemberTitle' then
        return SetMemberTitle(cid, payload.targetCid, payload.title)
    elseif action == 'transferLeadership' then
        return false, 'Transfer ownership from the target player G-menu so the server can require confirmation and proximity.'
    elseif action == 'disband' then
        return DisbandFamily(cid)
    elseif action == 'createRank' then
        return CreateRank(cid, payload.name, payload.tier, payload.permissions)
    elseif action == 'renameRank' then
        return RenameRank(cid, payload.rankId, payload.name)
    elseif action == 'deleteRank' then
        return DeleteRank(cid, payload.rankId)
    elseif action == 'setRankPermission' then
        return SetRankPermission(cid, payload.rankId, payload.key, payload.enabled)
    elseif action == 'setFamilySymbol' then
        local rank, fam = GetRankForCid(cid)
        if not rank or not fam then return false, 'not_in_family' end
        if not RankHasPermission(rank, 'family.manage_tags') then return false, 'no_permission' end
        local symbol = CMFamilyNormalizeSymbol(payload.symbol)
        local color = CMFamilyNormalizeSymbolColor(payload.color, fam.color)
        local changed = tonumber(MySQL.update.await(
            'UPDATE cm_families SET symbol = ?, color = ? WHERE id = ?',
            { symbol, color, fam.id })) or 0
        if changed < 1 then return false, 'family_symbol_update_failed' end
        fam.symbol, fam.color = symbol, color
        LogFamily(fam.id, cid, 'family_symbol_updated', { symbol = symbol, color = color })
        SyncFamilyState(fam.id)
        return true
    elseif action == 'setFamilyAnnouncement' then
        local rank, fam = GetRankForCid(cid)
        if not rank or not fam then return false, 'not_in_family' end
        if not RankHasPermission(rank, 'family.manage_announcement') then return false, 'no_permission' end
        local now = os.time()
        if announcementCooldowns[src] and announcementCooldowns[src] > now then
            return false, 'Please wait before changing the announcement again.'
        end
        local message = tostring(payload.message or ''):gsub('[%z\1-\8\11\12\14-\31\127]', '')
        message = message:gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 280)
        if message == '' then message = nil end
        local changed = tonumber(MySQL.update.await([[UPDATE cm_families
            SET announcement = ?, announcement_by = ?, announcement_at = CURRENT_TIMESTAMP WHERE id = ?]],
            { message, tostring(cid), fam.id })) or 0
        if changed < 1 then return false, 'family_announcement_update_failed' end
        fam.announcement, fam.announcement_by = message, tostring(cid)
        fam.announcement_at = os.date('%Y-%m-%d %H:%M:%S')
        announcementCooldowns[src] = now + 3
        LogFamily(fam.id, cid, 'family_announcement_updated', { cleared = message == nil })
        SyncFamilyState(fam.id)
        return true
    elseif action == 'setRankBankLimit' then
        return SetRankBankLimit(cid, payload.rankId, payload.limit)
    elseif action == 'setVehicleShared' then
        return SetVehicleSharedAndLevel(cid, payload.vehicleId, payload.shared == true, payload.level)
    elseif action == 'trackVehicle' then
        return CMFamilyRequestVehicleTrack(cid, payload.vehicleId)
    elseif action == 'setMeetingPoint' then
        if type(CMFamilySetMeetingPoint) ~= 'function' then
            return false, 'meeting_point_handler_unavailable'
        end
        return CMFamilySetMeetingPoint(src, cid, payload)
    elseif action == 'recallAllFamilyCars' then
        local rank, fam = GetRankForCid(cid)
        if not rank or not fam then return false, 'not_in_family' end
        if not RankHasPermission(rank, 'family.manage_vehicles') then return false, 'no_permission' end
        local recalled, result = B.RecallAllFamilyGarageVehicles(fam.id, cid)
        if recalled == true then
            LogFamily(fam.id, cid, 'garage_recall_all', type(result) == 'table' and result or {})
            return true, type(result) == 'table' and result.message or result
        end
        return false, result
    elseif action == 'setVehicleLevel' then
        local rank, fam = GetRankForCid(cid)
        if not rank or not fam then return false, 'not_in_family' end
        if not RankHasPermission(rank, 'family.manage_vehicles') then return false, 'no_permission' end
        return SetVehicleLevel(fam.id, payload.vehicleId, payload.level, cid)
    elseif action == 'bankDeposit' then
        return BankDeposit(cid, payload.amount)
    elseif action == 'bankWithdraw' then
        return BankWithdraw(cid, payload.amount)
    elseif action == 'updateIdentity' then
        local rank, fam = GetRankForCid(cid)
        if not rank or not fam then return false, 'not_in_family' end
        if not RankHasPermission(rank, 'family.manage_tags') then return false, 'no_permission' end

        local maxTag = tonumber(Config.Identity and Config.Identity.tagMaxLength) or Config.Create.tagMaxLength or 8
        local tag = tostring(payload.tag or ''):upper():gsub('[^A-Z0-9]', ''):sub(1, maxTag)
        if tag == '' then tag = nil end
        local color = tostring(payload.color or fam.color or '#00f0ff'):lower()
        if not color:match('^#%x%x%x%x%x%x$') then return false, 'invalid_color' end
        local visible = payload.tagVisible ~= false

        if tag then
            local duplicate = MySQL.scalar.await(
                'SELECT id FROM cm_families WHERE UPPER(tag) = UPPER(?) AND id <> ? LIMIT 1',
                { tag, fam.id })
            if duplicate then return false, 'That family tag is already used.' end
        end

        local changed = tonumber(MySQL.update.await(
            'UPDATE cm_families SET tag = ?, color = ?, tag_visible = ? WHERE id = ?',
            { tag, color, visible and 1 or 0, fam.id })) or 0
        if changed < 1 then return false, 'family_identity_update_failed' end
        fam.tag, fam.color, fam.tag_visible = tag, color, visible
        LogFamily(fam.id, cid, 'family_identity_updated', { tag = tag, color = color, tagVisible = visible })
        SyncFamilyState(fam.id)
        return true
    elseif action == 'rename' then
        local rank, fam = GetRankForCid(cid)
        if not rank or not fam then return false, 'not_in_family' end
        if not RankHasPermission(rank, 'family.rename') then return false, 'no_permission' end
        local name = tostring(payload.name or ''):gsub('^%s+',''):gsub('%s+$','')
        if #name < Config.Create.minNameLength or #name > Config.Create.maxNameLength then return false, 'invalid_name' end
        local dupe = MySQL.scalar.await('SELECT id FROM cm_families WHERE LOWER(name)=LOWER(?) AND id<>? LIMIT 1', { name, fam.id })
        if dupe then return false, 'A family with that name already exists.' end
        MySQL.update.await('UPDATE cm_families SET name = ? WHERE id = ?', { name, fam.id })
        fam.name = name
        LogFamily(fam.id, cid, 'family_renamed', { name = name })
        SyncFamilyState(fam.id)
        return true
    end

    return false, 'unknown_action'
end)

AddEventHandler('playerDropped', function()
    announcementCooldowns[source] = nil
end)
