-- cm-family | server/sv_gmenu.lua
-- Authoritative family actions invoked from cm-playerdata's looked-at-player G menu.
-- v1.2.1: public family profiles, owner-only permission view, detailed member
-- notifications, and two-step ownership transfer confirmation.

local B = CMFamilyBridge
local registeredActions = {
    'family_invite',
    'family_promote',
    'family_demote',
    'family_kick',
    'family_profile',
    'family_permissions',
    'family_transfer',
    -- Backward-compatible alias used by older clients.
    'family_info',
}

local pendingTransfers = {}
local transferCounter = 0

local function notify(src, ok, message)
    B.Notify(src, tostring(message or (ok and 'Done.' or 'Family action failed.')), ok and 'success' or 'error')
end

local function friendlyReason(reason)
    reason = tostring(reason or 'Family action failed.')
    local map = {
        no_permission = 'Your rank does not have permission to do that.',
        not_in_family = 'You are not in a family.',
        invalid_target = 'That player is no longer available.',
        character_not_loaded = 'Character data is not loaded.',
        database_not_ready = 'The family database is not ready.',
    }
    return map[reason] or reason
end

local function registerActions()
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    for _, action in ipairs(registeredActions) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', {
            id = action,
            event = 'cm-family:server:gMenuAction',
            resource = GetCurrentResourceName(),
            allowDeadTarget = false,
        })
    end
end

local function countFamilyMembers(familyId)
    local count = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM cm_family_members WHERE family_id = ?',
        { tonumber(familyId) or familyId }
    )) or 0
    return math.max(0, count)
end

local function countOnlineFamilyMembers(familyId)
    familyId = tonumber(familyId) or familyId
    local count = 0
    for cid, membership in pairs(MemberByCid or {}) do
        if (tonumber(membership.family_id) or membership.family_id) == familyId and B.GetSrcByCid(cid) then
            count = count + 1
        end
    end
    return count
end

local function buildPublicFamilyProfile(targetCid)
    local targetState = BuildFamilyMemberState(targetCid)
    if not targetState then return nil, 'That player is not in a family.' end

    local familyId = tonumber(targetState.id) or targetState.id
    local fam = Families[familyId]
    if not fam then return nil, 'That family is not available.' end

    local houseLabel
    if fam.house_id then
        local house = B.GetHouse(fam.house_id)
        if type(house) == 'table' then
            houseLabel = house.label or house.name or house.house_number
        end
    end

    return {
        familyId = familyId,
        familyName = fam.name,
        familyTag = fam.tag,
        color = fam.color or '#00f0ff',
        founderName = B.GetCharName(fam.founder_cid),
        memberCount = countFamilyMembers(familyId),
        onlineCount = countOnlineFamilyMembers(familyId),
        houseId = tonumber(fam.house_id) or fam.house_id,
        houseLabel = houseLabel,
        targetName = B.GetCharName(targetCid),
        targetCid = tostring(targetCid),
        targetRank = targetState.rankName,
        targetTitle = targetState.customTitle,
        targetIsFounder = targetState.isFounder == true,
    }
end

local function buildMemberPermissions(actorCid, targetCid)
    local actorRank, fam = GetRankForCid(actorCid)
    if not actorRank or not fam then return nil, 'You are not in a family.' end
    if actorRank.is_founder ~= true then
        return nil, 'Only the family owner can view member permissions.'
    end

    local targetState = BuildFamilyMemberState(targetCid)
    if not targetState or tonumber(targetState.id) ~= tonumber(fam.id) then
        return nil, 'That player is not in your family.'
    end

    local permissions = {}
    for _, permission in ipairs(Config.Permissions or {}) do
        permissions[#permissions + 1] = {
            key = permission.key,
            label = permission.label or permission.key,
            group = permission.group or 'other',
            allowed = targetState.isFounder == true
                or (type(targetState.permissions) == 'table' and targetState.permissions[permission.key] == true),
        }
    end

    return {
        familyId = fam.id,
        familyName = fam.name,
        familyTag = fam.tag,
        color = fam.color or '#00f0ff',
        targetCid = tostring(targetCid),
        targetName = B.GetCharName(targetCid),
        targetRank = targetState.rankName,
        targetTitle = targetState.customTitle,
        targetIsFounder = targetState.isFounder == true,
        permissions = permissions,
    }
end

local function createTransferToken(src, targetSrc, familyId)
    transferCounter = transferCounter + 1
    return ('%s:%s:%s:%s:%s'):format(
        tostring(src), tostring(targetSrc), tostring(familyId),
        tostring(GetGameTimer()), tostring(transferCounter)
    )
end

local function beginOwnershipTransfer(src, targetSrc, actorCid, targetCid)
    local actorRank, fam = GetRankForCid(actorCid)
    if not actorRank or not fam then return false, 'You are not in a family.' end
    if actorRank.is_founder ~= true then return false, 'Only the family owner can transfer ownership.' end
    if tostring(actorCid) == tostring(targetCid) then return false, 'You already own this family.' end

    local targetState = BuildFamilyMemberState(targetCid)
    if not targetState or tonumber(targetState.id) ~= tonumber(fam.id) then
        return false, 'That player is not in your family.'
    end
    if targetState.isFounder == true then return false, 'That player already owns the family.' end

    local token = createTransferToken(src, targetSrc, fam.id)
    pendingTransfers[src] = {
        token = token,
        targetSrc = tonumber(targetSrc),
        actorCid = tostring(actorCid),
        targetCid = tostring(targetCid),
        familyId = tonumber(fam.id),
        expiresAt = GetGameTimer() + 20000,
    }

    TriggerClientEvent('cm-family:client:confirmOwnershipTransfer', src, {
        token = token,
        targetServerId = tonumber(targetSrc),
        targetName = B.GetCharName(targetCid),
        targetCid = tostring(targetCid),
        familyName = fam.name,
        familyTag = fam.tag,
        color = fam.color or '#00f0ff',
    })
    return true
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() or resourceName == Config.PlayerDataResource then
        CreateThread(function() Wait(350) registerActions() end)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, action in ipairs(registeredActions) do
        TriggerEvent('cm-playerdata:server:unregisterInteractionAction', action)
    end
end)

AddEventHandler('playerDropped', function()
    pendingTransfers[source] = nil
end)

AddEventHandler('cm-family:server:gMenuAction', function(src, targetSrc, actionId, payload, context)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc or type(context) ~= 'table' then return end

    local actorCid = context.sourceCharacterId or B.GetCid(src)
    local targetCid = context.targetCharacterId or B.GetCid(targetSrc)
    if not actorCid or not targetCid then return notify(src, false, 'Character data is not loaded.') end

    if actionId == 'family_profile' or actionId == 'family_info' then
        local profile, reason = buildPublicFamilyProfile(targetCid)
        if not profile then return notify(src, false, friendlyReason(reason)) end
        TriggerClientEvent('cm-family:client:showPublicFamilyProfile', src, profile)
        return
    end

    if actionId == 'family_permissions' then
        local permissions, reason = buildMemberPermissions(actorCid, targetCid)
        if not permissions then return notify(src, false, friendlyReason(reason)) end
        TriggerClientEvent('cm-family:client:showMemberPermissions', src, permissions)
        return
    end

    if actionId == 'family_transfer' then
        local ok, reason = beginOwnershipTransfer(src, targetSrc, actorCid, targetCid)
        if not ok then notify(src, false, friendlyReason(reason)) end
        return
    end

    local ok, result
    local targetName = B.GetCharName(targetCid)

    if actionId == 'family_invite' then
        ok, result = InviteMember(actorCid, targetCid, nil)
        if ok then
            notify(src, true, ('Family invitation sent to %s.'):format(targetName))
        else
            notify(src, false, friendlyReason(result))
        end
        return
    elseif actionId == 'family_promote' then
        local before = BuildFamilyMemberState(targetCid)
        ok, result = PromoteMember(actorCid, targetCid)
        if ok then
            local after = BuildFamilyMemberState(targetCid)
            notify(src, true, ('%s promoted: %s → %s.'):format(
                targetName,
                before and before.rankName or 'Previous rank',
                after and after.rankName or 'New rank'
            ))
        else
            notify(src, false, friendlyReason(result))
        end
        return
    elseif actionId == 'family_demote' then
        local before = BuildFamilyMemberState(targetCid)
        ok, result = DemoteMember(actorCid, targetCid)
        if ok then
            local after = BuildFamilyMemberState(targetCid)
            notify(src, true, ('%s demoted: %s → %s.'):format(
                targetName,
                before and before.rankName or 'Previous rank',
                after and after.rankName or 'New rank'
            ))
        else
            notify(src, false, friendlyReason(result))
        end
        return
    elseif actionId == 'family_kick' then
        local before = BuildFamilyMemberState(targetCid)
        ok, result = KickMember(actorCid, targetCid)
        if ok then
            notify(src, true, ('%s was kicked from %s.'):format(
                targetName,
                before and before.name or 'the family'
            ))
        else
            notify(src, false, friendlyReason(result))
        end
        return
    end

    notify(src, false, 'Unknown family action.')
end)

RegisterNetEvent('cm-family:server:cancelOwnershipTransfer', function(token)
    local src = source
    local pending = pendingTransfers[src]
    if pending and tostring(pending.token) == tostring(token or '') then
        pendingTransfers[src] = nil
        B.Notify(src, 'Family ownership transfer cancelled.', 'inform')
    end
end)

RegisterNetEvent('cm-family:server:confirmOwnershipTransfer', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}
    local pending = pendingTransfers[src]
    pendingTransfers[src] = nil

    if not pending or tostring(pending.token) ~= tostring(payload.token or '') then
        return notify(src, false, 'That ownership-transfer confirmation is no longer valid.')
    end
    if GetGameTimer() > tonumber(pending.expiresAt or 0) then
        return notify(src, false, 'The ownership-transfer confirmation expired.')
    end

    local targetSrc = tonumber(pending.targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then
        return notify(src, false, 'The selected player is no longer online.')
    end

    -- Revalidate proximity and target state after the confirmation dialog. The
    -- initial G-menu validation is not trusted after a delay.
    local callOk, valid, resolvedTarget, validationReason = pcall(function()
        return exports[Config.PlayerDataResource]:ValidateInteractionTarget(
            src, targetSrc, 'family_transfer_confirm', 1000
        )
    end)
    if not callOk or valid ~= true or tonumber(resolvedTarget) ~= targetSrc then
        return notify(src, false, validationReason or 'The player moved too far away.')
    end

    local actorCid = B.GetCid(src)
    local targetCid = B.GetCid(targetSrc)
    if tostring(actorCid or '') ~= tostring(pending.actorCid)
        or tostring(targetCid or '') ~= tostring(pending.targetCid) then
        return notify(src, false, 'Character state changed. Start the transfer again.')
    end

    local ok, reason = TransferLeadership(actorCid, targetCid, true)
    if not ok then return notify(src, false, friendlyReason(reason)) end
end)
