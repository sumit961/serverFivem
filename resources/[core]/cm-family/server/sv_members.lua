-- ============================================================
--  cm-family | sv_members.lua
--  Invitations, membership, promotion/demotion, kicks, leaving, and founder
--  succession. Enforces the same authority rules as ranks: you cannot act on a
--  member whose rank is at or above your own.
-- ============================================================

local B = CMFamilyBridge

local function actorContext(actorCid)
    local rank, fam = GetRankForCid(actorCid)
    if not rank or not fam then return nil, nil, 'not_in_family' end
    return rank, fam
end

local function lowestRank(fam)
    local lowest
    for _, r in pairs(fam.ranksById) do
        if not lowest or r.tier < lowest.tier then lowest = r end
    end
    return lowest
end

local function memberRank(fam, cid)
    local m = GetMembership(cid)
    if not m or m.family_id ~= fam.id then return nil end
    return fam.ranksById[m.rank_id]
end

local function isFounderCid(fam, cid)
    return fam ~= nil and tostring(fam.founder_cid or '') == tostring(cid or '')
end

local function tierOf(rank)
    return tonumber(rank and rank.tier) or 0
end

-- ---------- invitations ----------
local function inviteIdValue(mode, familyId, targetCid)
    mode = mode or {}
    if not mode.present or mode.autoIncrement then return nil end

    if mode.numeric then
        return tonumber(MySQL.scalar.await(
            'SELECT COALESCE(MAX(CAST(`id` AS UNSIGNED)), 0) + 1 FROM cm_family_invites')) or 1
    end

    local value = ('i%s_%s'):format(tostring(familyId), tostring(targetCid))
    local maxLength = tonumber(mode.maxLength)
    if maxLength and maxLength > 0 then value = value:sub(1, maxLength) end
    return value
end

local function saveInvite(familyId, targetCid, actorCid, rankId, inviteSeconds)
    familyId = tonumber(familyId)
    rankId = tonumber(rankId)
    targetCid = tostring(targetCid)
    actorCid = tostring(actorCid)
    inviteSeconds = math.max(30, math.min(86400, math.floor(tonumber(inviteSeconds) or 300)))
    if not familyId or not rankId or targetCid == '' or actorCid == '' then
        return false, 'invalid_invitation_values'
    end

    -- First update an existing family/character invitation. This avoids relying
    -- on the shape of a legacy primary key and refreshes expiry using DB time.
    local updateSql = ([=[
        UPDATE cm_family_invites
        SET invited_by = ?, rank_id = ?, expires_at = DATE_ADD(NOW(), INTERVAL %d SECOND), created_at = NOW()
        WHERE family_id = ? AND character_id = ?
    ]=]):format(inviteSeconds)
    local updated = tonumber(MySQL.update.await(updateSql,
        { actorCid, rankId, familyId, targetCid })) or 0

    if updated == 0 then
        local mode = CMFamilyInviteIdMode or {}
        local explicitId = inviteIdValue(mode, familyId, targetCid)
        local insertSql
        local values
        if explicitId ~= nil then
            insertSql = ([=[
                INSERT INTO cm_family_invites
                    (`id`, family_id, character_id, invited_by, rank_id, expires_at, created_at)
                VALUES (?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL %d SECOND), NOW())
            ]=]):format(inviteSeconds)
            values = { explicitId, familyId, targetCid, actorCid, rankId }
        else
            insertSql = ([=[
                INSERT INTO cm_family_invites
                    (family_id, character_id, invited_by, rank_id, expires_at, created_at)
                VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL %d SECOND), NOW())
            ]=]):format(inviteSeconds)
            values = { familyId, targetCid, actorCid, rankId }
        end

        local inserted, insertErr = pcall(function()
            return MySQL.update.await(insertSql, values)
        end)
        if not inserted then
            -- A concurrent request may have inserted the unique family/member row.
            -- Retry as an update before reporting failure.
            local retried, retryResult = pcall(function()
                return MySQL.update.await(updateSql,
                    { actorCid, rankId, familyId, targetCid })
            end)
            if not retried then
                return false, tostring(insertErr)
            end
            -- An unchanged row can legitimately report 0 affected rows when a
            -- duplicate invitation is refreshed within the same DB second. The
            -- verified SELECT below is the authoritative success check.
        end
    end

    -- Never display a client prompt until the exact row is confirmed valid by
    -- the same database clock used by acceptance and the family menu.
    local row = MySQL.single.await([[
        SELECT id, family_id, character_id, invited_by, rank_id,
               UNIX_TIMESTAMP(expires_at) AS expires_unix
        FROM cm_family_invites
        WHERE family_id = ? AND character_id = ?
          AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY created_at DESC
        LIMIT 1
    ]], { familyId, targetCid })

    if not row then return false, 'invitation_not_persisted' end
    return true, row
end

function InviteMember(actorCid, targetCid, rankId)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.invite') then return false, 'no_permission' end
    targetCid = targetCid ~= nil and tostring(targetCid) or nil
    if not targetCid or targetCid == '' then return false, 'invalid_target' end
    if GetMembership(targetCid) then return false, 'That player is already in a family.' end

    local rank = rankId and fam.ranksById[tonumber(rankId)] or lowestRank(fam)
    if not rank then return false, 'no_rank_available' end
    if not actorRank.is_founder and tierOf(rank) >= tierOf(actorRank) then
        return false, 'You cannot invite at or above your own rank.'
    end

    local inviteSeconds = math.max(30, tonumber(Config.Invites and Config.Invites.expiresSeconds) or 300)
    local saved, inviteRow = saveInvite(fam.id, targetCid, actorCid, rank.id, inviteSeconds)
    if not saved then
        print(('[cm-family] failed to persist invitation family=%s target=%s: %s')
            :format(tostring(fam.id), targetCid, tostring(inviteRow)))
        return false, 'The family invitation could not be saved.'
    end

    LogFamily(fam.id, actorCid, 'invite_sent', { to = targetCid, rankId = rank.id })

    local targetSrc = B.GetSrcByCid(targetCid)
    if targetSrc then
        TriggerClientEvent('cm-family:client:inviteReceived', targetSrc, {
            inviteId = tonumber(inviteRow.id) or inviteRow.id,
            familyId = tonumber(inviteRow.family_id) or fam.id,
            familyName = fam.name,
            familyTag = fam.tag,
            color = fam.color,
            invitedBy = B.GetCharName(actorCid),
            expiresAt = tonumber(inviteRow.expires_unix),
            promptSeconds = math.max(5, tonumber(Config.Invites and Config.Invites.promptSeconds) or 30),
        })
    end
    return true
end

local inviteResponseLocks = {}

function RespondToInvite(targetCid, accept, requestedInviteId, requestedFamilyId)
    targetCid = tostring(targetCid)
    if inviteResponseLocks[targetCid] then return false, 'An invitation response is already being processed.' end
    inviteResponseLocks[targetCid] = true

    local ok, resultA, resultB = xpcall(function()
        local invite
        local familyId = tonumber(requestedFamilyId)

        -- family_id + character_id is the stable identity shared by every schema.
        -- Legacy invite IDs may be text, blank-default, or non-auto-incrementing.
        if familyId then
            invite = MySQL.single.await([[
                SELECT *, CASE WHEN expires_at IS NULL OR expires_at > NOW() THEN 1 ELSE 0 END AS is_valid
                FROM cm_family_invites
                WHERE family_id = ? AND character_id = ?
                ORDER BY created_at DESC LIMIT 1
            ]], { familyId, targetCid })
        elseif requestedInviteId ~= nil and tostring(requestedInviteId) ~= '' then
            invite = MySQL.single.await([[
                SELECT *, CASE WHEN expires_at IS NULL OR expires_at > NOW() THEN 1 ELSE 0 END AS is_valid
                FROM cm_family_invites
                WHERE CAST(id AS CHAR) = ? AND character_id = ?
                LIMIT 1
            ]], { tostring(requestedInviteId), targetCid })
        else
            invite = MySQL.single.await([[
                SELECT *, CASE WHEN expires_at IS NULL OR expires_at > NOW() THEN 1 ELSE 0 END AS is_valid
                FROM cm_family_invites
                WHERE character_id = ?
                ORDER BY created_at DESC LIMIT 1
            ]], { targetCid })
        end
        if not invite then return false, 'You have no pending family invitation.' end

        local inviteFamilyId = tonumber(invite.family_id) or invite.family_id
        if tonumber(invite.is_valid) ~= 1 then
            MySQL.update.await(
                'DELETE FROM cm_family_invites WHERE family_id = ? AND character_id = ?',
                { inviteFamilyId, targetCid })
            return false, 'That family invitation has expired.'
        end

        if accept ~= true then
            MySQL.update.await(
                'DELETE FROM cm_family_invites WHERE family_id = ? AND character_id = ?',
                { inviteFamilyId, targetCid })
            LogFamily(inviteFamilyId, targetCid, 'invite_declined', {})
            return true, 'declined'
        end

        if GetMembership(targetCid) then return false, 'You are already in a family.' end
        local inviteRankId = tonumber(invite.rank_id) or invite.rank_id
        local fam = Families[inviteFamilyId]
        if not fam then
            MySQL.update.await(
                'DELETE FROM cm_family_invites WHERE family_id = ? AND character_id = ?',
                { inviteFamilyId, targetCid })
            return false, 'That family no longer exists.'
        end

        local rank = fam.ranksById[inviteRankId] or lowestRank(fam)
        if not rank then return false, 'No valid family rank is available.' end

        local inserted, insertErr = CMFamilyInsertMember(fam.id, targetCid, rank.id)
        if not inserted then
            return false, ('Membership could not be created: %s'):format(tostring(insertErr or 'unknown'))
        end

        local removed = tonumber(MySQL.update.await(
            'DELETE FROM cm_family_invites WHERE family_id = ? AND character_id = ?',
            { fam.id, targetCid })) or 0
        if removed < 1 then
            print(('[cm-family] warning: membership committed but invite cleanup matched no row; family=%s cid=%s')
                :format(tostring(fam.id), targetCid))
        end

        MemberByCid[targetCid] = {
            family_id = fam.id,
            rank_id = rank.id,
            custom_title = nil,
            tag_hidden = false,
        }

        -- Set the online player's authoritative family state before replying.
        -- Slow house/cache refreshes remain detached and cannot block the ACK.
        SyncFamilyMemberState(targetCid)
        B.RefreshCharacterAccess(targetCid)

        CreateThread(function()
            local sideEffectOk, sideEffectErr = xpcall(function()
                LogFamily(fam.id, targetCid, 'member_joined', { rankId = rank.id })
                B.RefreshFamilyMembers(fam.id)
                B.RefreshFamilyAccess(fam.id)
            end, debug.traceback)
            if not sideEffectOk then
                print(('[cm-family] post-join refresh failed for cid %s in family %s: %s')
                    :format(targetCid, tostring(fam.id), tostring(sideEffectErr)))
            end
        end)

        return true, 'accepted'
    end, debug.traceback)

    inviteResponseLocks[targetCid] = nil
    if not ok then return false, tostring(resultA) end
    return resultA, resultB
end

function GetPendingInvite(cid)
    return MySQL.single.await([[
        SELECT i.*, f.name AS family_name, f.tag AS family_tag, f.color AS family_color,
               UNIX_TIMESTAMP(i.expires_at) AS expires_unix
        FROM cm_family_invites i
        LEFT JOIN cm_families f ON f.id = i.family_id
        WHERE i.character_id = ?
          AND (i.expires_at IS NULL OR i.expires_at > NOW())
        ORDER BY i.created_at DESC
        LIMIT 1
    ]], { tostring(cid) })
end

-- ---------- kick / leave ----------
function KickMember(actorCid, targetCid)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.kick') then return false, 'no_permission' end
    targetCid = tostring(targetCid)
    if tostring(actorCid) == targetCid then return false, 'Use "leave family" to remove yourself.' end

    local targetRank = memberRank(fam, targetCid)
    if not targetRank then return false, 'They are not in your family.' end
    if isFounderCid(fam, targetCid) then return false, 'The founder cannot be kicked.' end
    if not actorRank.is_founder and tierOf(targetRank) >= tierOf(actorRank) then
        return false, 'You cannot kick someone at or above your own rank.'
    end

    local affected = tonumber(MySQL.update.await(
        'DELETE FROM cm_family_members WHERE family_id = ? AND character_id = ?',
        { fam.id, targetCid }
    )) or 0
    if affected < 1 then return false, 'The member record could not be removed.' end

    MemberByCid[targetCid] = nil
    if CMFamilyRevokeVehicleKeysForCharacter then
        CMFamilyRevokeVehicleKeysForCharacter(targetCid, 'family-member-kicked')
    end
    LogFamily(fam.id, actorCid, 'member_kicked', {
        target = targetCid,
        oldRankId = targetRank.id,
        oldRankName = targetRank.name,
    })
    B.RefreshFamilyMembers(fam.id)
    B.RefreshFamilyAccess(fam.id)

    local targetSrc = B.GetSrcByCid(targetCid)
    ClearFamilyMemberState(targetCid)
    if targetSrc then
        B.Notify(targetSrc, ('%s removed you from the "%s" family.'):format(
            B.GetCharName(actorCid), fam.name
        ), 'error')
    end
    return true, {
        targetCid = targetCid,
        targetName = B.GetCharName(targetCid),
        oldRankId = targetRank.id,
        oldRankName = targetRank.name,
        familyId = fam.id,
        familyName = fam.name,
    }
end

function LeaveFamily(actorCid)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end

    if actorRank.is_founder then
        -- Founder must hand off or disband. Attempt succession to the next
        -- highest-tier member; if none, the family disbands.
        local ok, why = SucceedFounder(actorCid)
        if not ok and why == 'no_successor' then
            return DisbandFamily(actorCid)
        elseif not ok then
            return false, why
        end
    end

    MySQL.update.await('DELETE FROM cm_family_members WHERE family_id = ? AND character_id = ?',
        { fam.id, tostring(actorCid) })
    MemberByCid[tostring(actorCid)] = nil
    if CMFamilyRevokeVehicleKeysForCharacter then
        CMFamilyRevokeVehicleKeysForCharacter(actorCid, 'family-member-left')
    end
    LogFamily(fam.id, actorCid, 'member_left', {})
    ClearFamilyMemberState(actorCid)
    B.RefreshFamilyMembers(fam.id)
    B.RefreshFamilyAccess(fam.id)
    return true
end

-- ---------- promote / demote ----------
function SetMemberRank(actorCid, targetCid, newRankId)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    targetCid = tostring(targetCid)

    local targetRank = memberRank(fam, targetCid)
    if not targetRank then return false, 'They are not in your family.' end
    if isFounderCid(fam, targetCid) then return false, 'You cannot change the founder rank.' end

    local newRank = fam.ranksById[tonumber(newRankId)]
    if not newRank then return false, 'no_such_rank' end
    if newRank.is_founder or isFounderCid(fam, targetCid) then return false, 'Use "transfer leadership" to make a new founder.' end

    -- The actual direction of the change decides which permission gates it --
    -- never trust a caller-supplied permission name, otherwise a generic rank
    -- edit could demote someone using only promote authority (or vice versa).
    local requiredPermission = tierOf(newRank) > tierOf(targetRank) and 'family.promote' or 'family.demote'
    if not RankHasPermission(actorRank, requiredPermission) then return false, 'no_permission' end

    -- Non-founders cannot manage equal/higher members. Nobody, including the
    -- owner, may assign their own authority tier or higher through a rank edit;
    -- ownership itself can only move through the confirmed transfer flow.
    if not actorRank.is_founder and tierOf(targetRank) >= tierOf(actorRank) then
        return false, 'That member is at or above your rank.'
    end
    if tierOf(newRank) >= tierOf(actorRank) then
        return false, 'You cannot promote someone to your own rank or higher.'
    end

    local affected = tonumber(MySQL.update.await(
        'UPDATE cm_family_members SET rank_id = ? WHERE family_id = ? AND character_id = ?',
        { newRank.id, fam.id, targetCid }
    )) or 0
    if affected < 1 then return false, 'The member rank could not be updated.' end

    local m = GetMembership(targetCid)
    if m then m.rank_id = newRank.id end
    if CMFamilyRevokeVehicleKeysForCharacter then
        CMFamilyRevokeVehicleKeysForCharacter(targetCid, 'family-rank-changed')
    end
    local direction = (tonumber(newRank.tier) or 0) > (tonumber(targetRank.tier) or 0)
        and 'promoted' or 'demoted'
    LogFamily(fam.id, actorCid, direction == 'promoted' and 'member_promoted' or 'member_demoted', {
        target = targetCid,
        oldRankId = targetRank.id,
        oldRankName = targetRank.name,
        rankId = newRank.id,
        rankName = newRank.name,
    })
    SyncFamilyMemberState(targetCid)
    B.RefreshFamilyAccess(fam.id)

    local targetSrc = B.GetSrcByCid(targetCid)
    if targetSrc then
        B.Notify(targetSrc, ('You were %s from %s to %s by %s.'):format(
            direction,
            tostring(targetRank.name or 'your previous rank'),
            tostring(newRank.name or 'your new rank'),
            B.GetCharName(actorCid)
        ), direction == 'promoted' and 'success' or 'inform')
    end

    return true, {
        targetCid = targetCid,
        targetName = B.GetCharName(targetCid),
        oldRankId = targetRank.id,
        oldRankName = targetRank.name,
        newRankId = newRank.id,
        newRankName = newRank.name,
        direction = direction,
    }
end


-- ---------- one-step G-menu rank actions / member identity ----------
local function sortedRanks(fam)
    local ranks = {}
    for _, rank in pairs(fam.ranksById or {}) do ranks[#ranks + 1] = rank end
    table.sort(ranks, function(a, b) return (tonumber(a.tier) or 0) < (tonumber(b.tier) or 0) end)
    return ranks
end

function PromoteMember(actorCid, targetCid)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.promote') then return false, 'no_permission' end
    targetCid = tostring(targetCid)
    local current = memberRank(fam, targetCid)
    if not current then return false, 'They are not in your family.' end
    if isFounderCid(fam, targetCid) then return false, 'The founder cannot be promoted.' end
    if not actorRank.is_founder and tierOf(current) >= tierOf(actorRank) then return false, 'That member is at or above your rank.' end

    local nextRank
    for _, rank in ipairs(sortedRanks(fam)) do
        if tierOf(rank) > tierOf(current)
            and tierOf(rank) < tierOf(actorRank)
            and not rank.is_founder then
            nextRank = rank
            break
        end
    end
    if not nextRank then return false, 'There is no higher rank you can assign.' end
    return SetMemberRank(actorCid, targetCid, nextRank.id)
end

function DemoteMember(actorCid, targetCid)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.demote') then return false, 'no_permission' end
    targetCid = tostring(targetCid)
    local current = memberRank(fam, targetCid)
    if not current then return false, 'They are not in your family.' end
    if isFounderCid(fam, targetCid) then return false, 'The founder cannot be demoted.' end
    if not actorRank.is_founder and tierOf(current) >= tierOf(actorRank) then return false, 'That member is at or above your rank.' end

    local previous
    for _, rank in ipairs(sortedRanks(fam)) do
        if rank.tier < current.tier then previous = rank end
    end
    if not previous then return false, 'That member is already on the lowest rank.' end
    return SetMemberRank(actorCid, targetCid, previous.id)
end

local function cleanTitle(value)
    local maxLength = tonumber(Config.Identity and Config.Identity.customTitleMaxLength) or 24
    local title = tostring(value or ''):gsub('[\r\n\t]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    title = title:gsub('[<>]', '')
    if #title > maxLength then title = title:sub(1, maxLength) end
    if title == '' then return nil end
    return title
end

function SetMemberTitle(actorCid, targetCid, title)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.manage_titles') then return false, 'no_permission' end
    targetCid = tostring(targetCid)
    local targetRank = memberRank(fam, targetCid)
    if not targetRank then return false, 'They are not in your family.' end
    if not actorRank.is_founder and tierOf(targetRank) >= tierOf(actorRank) and tostring(actorCid) ~= targetCid then
        return false, 'You cannot edit the title of an equal or higher rank.'
    end
    title = cleanTitle(title)
    local affected = tonumber(MySQL.update.await(
        'UPDATE cm_family_members SET custom_title = ? WHERE family_id = ? AND character_id = ?',
        { title, fam.id, targetCid })) or 0
    if affected < 1 then return false, 'member_update_failed' end
    local membership = GetMembership(targetCid)
    if membership then membership.custom_title = title end
    LogFamily(fam.id, actorCid, 'member_title_set', { target = targetCid, title = title })
    SyncFamilyMemberState(targetCid)
    return true
end

function SetOwnTagHidden(actorCid, hidden)
    local rank, fam, err = actorContext(actorCid)
    if not rank then return false, err end
    hidden = hidden == true
    local affected = tonumber(MySQL.update.await(
        'UPDATE cm_family_members SET tag_hidden = ? WHERE family_id = ? AND character_id = ?',
        { hidden and 1 or 0, fam.id, tostring(actorCid) })) or 0
    if affected < 1 then return false, 'member_update_failed' end
    local membership = GetMembership(actorCid)
    if membership then membership.tag_hidden = hidden end
    LogFamily(fam.id, actorCid, 'member_tag_visibility', { hidden = hidden })
    SyncFamilyMemberState(actorCid)
    return true
end

-- ---------- founder succession & disband ----------
-- Promote the highest-tier non-founder member to the founder rank. Returns
-- (false, 'no_successor') when the founder is the only member.
function SucceedFounder(founderCid)
    local founderRank, fam = GetRankForCid(founderCid)
    if not founderRank or not founderRank.is_founder then return false, 'not_founder' end

    local best, bestCid
    for cid, m in pairs(MemberByCid) do
        if m.family_id == fam.id and tostring(cid) ~= tostring(founderCid) then
            local r = fam.ranksById[m.rank_id]
            if r and (not best or r.tier > best.tier) then best, bestCid = r, cid end
        end
    end
    if not bestCid then return false, 'no_successor' end

    local founderRankRow = nil
    for _, r in pairs(fam.ranksById) do if r.is_founder then founderRankRow = r end end
    if not founderRankRow then return false, 'no_founder_rank' end

    MySQL.update.await('UPDATE cm_family_members SET rank_id = ? WHERE family_id = ? AND character_id = ?',
        { founderRankRow.id, fam.id, tostring(bestCid) })
    MySQL.update.await('UPDATE cm_families SET founder_cid = ? WHERE id = ?', { tostring(bestCid), fam.id })
    fam.founder_cid = tostring(bestCid)
    local m = GetMembership(bestCid) ; if m then m.rank_id = founderRankRow.id end
    if CMFamilyRevokeVehicleKeysForCharacter then
        CMFamilyRevokeVehicleKeysForCharacter(bestCid, 'family-founder-changed')
        CMFamilyRevokeVehicleKeysForCharacter(founderCid, 'family-founder-changed')
    end
    LogFamily(fam.id, founderCid, 'founder_succeeded', { newFounder = bestCid })
    SyncFamilyMemberState(bestCid)
    SyncFamilyMemberState(founderCid)
    B.RefreshFamilyAccess(fam.id)
    return true, bestCid
end

-- Explicit leadership transfer to a chosen member.
function TransferLeadership(actorCid, targetCid, confirmed)
    if confirmed ~= true then
        return false, 'Ownership transfer requires the confirmed player G-menu flow.'
    end
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not actorRank.is_founder then return false, 'Only the founder can transfer leadership.' end

    targetCid = tostring(targetCid)
    actorCid = tostring(actorCid)
    if actorCid == targetCid then return false, 'You already own this family.' end

    local targetRank = memberRank(fam, targetCid)
    if not targetRank then return false, 'They are not in your family.' end
    if tostring(fam.founder_cid or '') == targetCid then
        return false, 'That member already owns the family.'
    end

    local orderedRanks = {}
    for _, rank in pairs(fam.ranksById or {}) do orderedRanks[#orderedRanks + 1] = rank end
    table.sort(orderedRanks, function(a, b) return tierOf(a) > tierOf(b) end)

    -- Legacy schemas may not mark the highest rank is_founder=1. The family
    -- owner is authoritative from founder_cid, so use the highest tier as the
    -- owner rank and the next-highest tier for the previous owner.
    local founderRankRow = orderedRanks[1]
    local secondRank = orderedRanks[2]
    if not founderRankRow then return false, 'The family has no valid ranks.' end
    if not secondRank then return false, 'Create a non-founder rank before transferring ownership.' end

    -- All three authority changes commit together. A crash or failed query must
    -- never leave two founders or a founder_cid that disagrees with membership.
    local transactionOk, committed = pcall(function()
        return MySQL.transaction.await({
            {
                query = 'UPDATE cm_family_members SET rank_id = ? WHERE family_id = ? AND character_id = ?',
                values = { founderRankRow.id, fam.id, targetCid },
            },
            {
                query = 'UPDATE cm_family_members SET rank_id = ? WHERE family_id = ? AND character_id = ?',
                values = { secondRank.id, fam.id, actorCid },
            },
            {
                query = 'UPDATE cm_families SET founder_cid = ? WHERE id = ? AND founder_cid = ?',
                values = { targetCid, fam.id, actorCid },
            },
        })
    end)
    if not transactionOk or committed ~= true then
        return false, 'Family ownership transfer failed safely.'
    end

    fam.founder_cid = targetCid
    local mt = GetMembership(targetCid)
    if mt then mt.rank_id = founderRankRow.id end
    local ma = GetMembership(actorCid)
    if ma then ma.rank_id = secondRank.id end

    if CMFamilyRevokeVehicleKeysForCharacter then
        CMFamilyRevokeVehicleKeysForCharacter(targetCid, 'family-leadership-transferred')
        CMFamilyRevokeVehicleKeysForCharacter(actorCid, 'family-leadership-transferred')
    end

    LogFamily(fam.id, actorCid, 'leadership_transferred', {
        to = targetCid,
        oldFounderRankId = founderRankRow.id,
        previousFounderNewRankId = secondRank.id,
    })
    SyncFamilyMemberState(targetCid)
    SyncFamilyMemberState(actorCid)
    B.RefreshFamilyAccess(fam.id)

    local oldFounderSrc = B.GetSrcByCid(actorCid)
    local newFounderSrc = B.GetSrcByCid(targetCid)
    if oldFounderSrc then
        B.Notify(oldFounderSrc, ('Family ownership transferred to %s. You are now %s.'):format(
            B.GetCharName(targetCid), tostring(secondRank.name or 'a member')
        ), 'success')
    end
    if newFounderSrc then
        B.Notify(newFounderSrc, ('%s transferred ownership of "%s" to you.'):format(
            B.GetCharName(actorCid), tostring(fam.name)
        ), 'success')
    end

    return true, {
        familyId = fam.id,
        familyName = fam.name,
        oldFounderCid = actorCid,
        newFounderCid = targetCid,
        newFounderName = B.GetCharName(targetCid),
        oldFounderNewRankId = secondRank.id,
        oldFounderNewRankName = secondRank.name,
    }
end

-- Disband: unlink the house, remove all members and ranks, delete the family.
function DisbandFamily(actorCid)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not actorRank.is_founder then return false, 'Only the founder can disband the family.' end

    local familyId = fam.id
    local houseUnlinked = false
    if fam.house_id then
        local unlinked, unlinkErr = B.SetFamilyHouseLink(fam.house_id, nil, actorCid)
        if not unlinked then
            return false, ('Could not unlink the family house: %s'):format(tostring(unlinkErr or 'unknown'))
        end
        houseUnlinked = true
    end

    if type(CMFamilyDeleteFamilyRows) ~= 'function' then
        if houseUnlinked then pcall(function() B.SetFamilyHouseLink(fam.house_id, familyId, actorCid) end) end
        return false, 'Family database cleanup is unavailable.'
    end

    local deleted, deleteErr = CMFamilyDeleteFamilyRows(familyId)
    if not deleted then
        -- The DB transaction is atomic, so the family still exists. Restore the
        -- house link that was removed above before returning the failure.
        if houseUnlinked then
            local relinked, relinkErr = B.SetFamilyHouseLink(fam.house_id, familyId, actorCid)
            if not relinked then
                print(('[cm-family] CRITICAL: failed to restore house %s link to family %s after disband rollback: %s')
                    :format(tostring(fam.house_id), tostring(familyId), tostring(relinkErr)))
            end
        end
        return false, ('Family disband failed safely: %s'):format(tostring(deleteErr))
    end

    LogFamily(familyId, actorCid, 'family_deleted', {
        houseId = fam.house_id,
        reason = 'manual_disband',
        familyName = fam.name,
    }, { highRisk = true, houseId = fam.house_id })

    if CMFamilyRevokeVehicleKeysForFamily then
        CMFamilyRevokeVehicleKeysForFamily(familyId, 'family-disbanded')
    end

    local removedCids = {}
    for cid, m in pairs(MemberByCid) do
        if tonumber(m.family_id) == familyId then
            removedCids[#removedCids + 1] = cid
            MemberByCid[cid] = nil
        end
    end
    Families[familyId] = nil
    for _, cid in ipairs(removedCids) do ClearFamilyMemberState(cid) end
    if InvalidateVehicleCache then InvalidateVehicleCache(familyId) end
    B.RefreshFamilyMembers(familyId)
    return true, 'disbanded'
end

-- ---------- immediate Y/N invitation response transport (v1.1.4) ----------
-- This event is intentionally separate from the full-menu ox_lib callback. It
-- always sends a client acknowledgement, including when validation or DB work
-- fails, so the top-screen prompt never appears to do nothing.
RegisterNetEvent('cm-family:server:respondInvitePrompt', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}
    local requestToken = tostring(payload.requestToken or '')
    local accept = payload.accept == true
    local inviteId = payload.inviteId

    if requestToken == '' then return end

    CreateThread(function()
        local familyId = tonumber(payload.familyId)

        local function reply(ok, reason)
            -- Triggering an event to a disconnected source is harmless. Do not
            -- suppress ACKs based on ping: local/listen-server players can report
            -- ping 0 and were previously left on "Accepting invitation…" forever.
            TriggerClientEvent('cm-family:client:inviteResponse', src, {
                requestToken = requestToken,
                inviteId = inviteId,
                familyId = familyId,
                accept = accept,
                ok = ok == true,
                reason = reason,
            })
        end

        local ready, dbError = false, 'database_not_ready'
        if type(CMFamilyIsDatabaseReady) == 'function' then
            ready, dbError = CMFamilyIsDatabaseReady()
        end
        if ready ~= true then
            reply(false, tostring(dbError or 'Family database is not ready.'))
            return
        end

        local cid = B.GetCid(src)
        if not cid then
            reply(false, 'Your character is not loaded.')
            return
        end

        local ran, ok, reason = xpcall(function()
            return RespondToInvite(cid, accept, inviteId, familyId)
        end, debug.traceback)

        if not ran then
            print(('[cm-family] invitation response failed for source %s: %s')
                :format(tostring(src), tostring(ok)))
            reply(false, 'Family invitation processing failed. Check the server console.')
            return
        end

        if ok ~= true then
            print(('[cm-family] invitation response rejected for cid %s family %s: %s')
                :format(tostring(cid), tostring(familyId or '?'), tostring(reason)))
        end
        reply(ok == true, reason)
    end)
end)
