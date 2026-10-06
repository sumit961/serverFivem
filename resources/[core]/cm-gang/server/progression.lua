local RESOURCE = GetCurrentResourceName()
local PLAYERDATA = 'cm-playerdata'
local ADMIN = 'cm-admin'

local locks = {}
local claimSequence = 0

local function asCharacterId(value)
    local valueType = type(value)
    if valueType ~= 'number' and valueType ~= 'string' then
        return nil
    end

    local characterId = tostring(value)
    if #characterId == 0 or #characterId > 64 or not characterId:match('^%d+$') then
        return nil
    end

    return characterId
end

local function asGangId(value)
    if type(value) ~= 'string' or #value == 0 or #value > 32 then
        return nil
    end

    if not value:match('^[%w_%-]+$') then
        return nil
    end

    return value
end

local function isEnabled(value)
    return value == true or value == 1 or value == '1'
end

local function isFixedGang(gangId)
    if type(Config.IsFixedGangId) == 'function' then
        local ok, result = pcall(Config.IsFixedGangId, gangId)
        return ok and result == true
    end

    return false
end

local function getGang(gangId)
    if not isFixedGang(gangId) then
        return nil
    end

    local ok, gang = pcall(function()
        return exports[RESOURCE]:GetGang(gangId)
    end)
    if not ok or type(gang) ~= 'table' or not isEnabled(gang.enabled) then
        return nil
    end

    return gang
end

local function getCharacterId(source)
    source = tonumber(source)
    if not source or source <= 0 or GetResourceState(PLAYERDATA) ~= 'started' then
        return nil
    end

    local ok, characterId = pcall(function()
        return exports[PLAYERDATA]:GetCharacterId(source)
    end)
    if not ok then
        return nil
    end

    return asCharacterId(characterId)
end

local function getMembership(characterId)
    characterId = asCharacterId(characterId)
    if not characterId then
        return nil
    end

    local ok, membership = pcall(function()
        return exports[RESOURCE]:GetGangForCharacter(characterId)
    end)
    if not ok or type(membership) ~= 'table' then
        return nil
    end

    local gangId = asGangId(membership.gangId or membership.gang_id)
    if not gangId or not isEnabled(membership.enabled) or not getGang(gangId) then
        return nil
    end

    return membership, gangId
end

local function memberContext(source)
    local characterId = getCharacterId(source)
    if not characterId then
        return nil, 'character_unavailable'
    end

    local membership, gangId = getMembership(characterId)
    if not membership then
        return nil, 'active_membership_required'
    end

    return {
        source = tonumber(source),
        characterId = characterId,
        gangId = gangId,
        membership = membership,
        gang = getGang(gangId),
    }
end

local function progressionConfig()
    local progression = Config and Config.Progression
    if type(progression) ~= 'table' or type(progression.levels) ~= 'table' then
        return nil
    end

    local levels = {}
    for index, level in pairs(progression.levels) do
        if type(level) ~= 'table' then
            return nil
        end

        local levelNumber = tonumber(level.level)
        local threshold = tonumber(level.threshold)
        local label = type(level.label) == 'string' and level.label or nil
        if not levelNumber or levelNumber < 1 or levelNumber % 1 ~= 0 or not threshold or threshold < 0 or threshold % 1 ~= 0 or not label or #label == 0 or #label > 48 then
            return nil
        end

        levels[#levels + 1] = {
            level = levelNumber,
            threshold = threshold,
            label = label,
            configIndex = index,
        }
    end

    table.sort(levels, function(left, right)
        if left.threshold == right.threshold then
            return left.level < right.level
        end
        return left.threshold < right.threshold
    end)

    if #levels == 0 or levels[1].threshold ~= 0 then
        return nil
    end

    for index = 2, #levels do
        if levels[index].threshold <= levels[index - 1].threshold or levels[index].level <= levels[index - 1].level then
            return nil
        end
    end

    return progression, levels
end

local function levelForTotal(total, levels)
    local current = levels[1]
    for index = 2, #levels do
        if total >= levels[index].threshold then
            current = levels[index]
        else
            break
        end
    end
    return current
end

local function buildProgression(row)
    local progression, levels = progressionConfig()
    if not progression then
        return nil, 'progression_config_invalid'
    end

    row = row or {}
    local contributionPoints = math.max(0, tonumber(row.contribution_points) or 0)
    local totalEarned = math.max(0, tonumber(row.total_contribution_earned) or 0)
    local current = levelForTotal(totalEarned, levels)
    local nextLevel
    for index, level in ipairs(levels) do
        if level.level == current.level then
            nextLevel = levels[index + 1]
            break
        end
    end

    local percent = 100
    local pointsIntoLevel = math.max(0, totalEarned - current.threshold)
    local pointsToNext = 0
    if nextLevel then
        local span = nextLevel.threshold - current.threshold
        pointsToNext = math.max(0, nextLevel.threshold - totalEarned)
        percent = math.max(0, math.min(100, math.floor((pointsIntoLevel * 100) / span)))
    end

    return {
        contributionPoints = contributionPoints,
        totalContributionEarned = totalEarned,
        reputationLevel = current.level,
        reputationLabel = current.label,
        lastContributionAt = row.last_contribution_at,
        createdAt = row.created_at,
        updatedAt = row.updated_at,
        progress = {
            currentThreshold = current.threshold,
            nextThreshold = nextLevel and nextLevel.threshold or nil,
            pointsIntoLevel = pointsIntoLevel,
            pointsToNext = pointsToNext,
            percent = percent,
            nextLevel = nextLevel and nextLevel.level or nil,
            nextLabel = nextLevel and nextLevel.label or nil,
        },
    }
end

local function readRow(gangId, characterId)
    return MySQL.single.await([[
        SELECT gang_id, character_id, contribution_points, reputation_level,
               total_contribution_earned, last_contribution_at, created_at, updated_at
        FROM cm_gang_progression
        WHERE gang_id = ? AND character_id = ?
        LIMIT 1
    ]], { gangId, characterId })
end

local function readProgression(gangId, characterId)
    local progression, reason = buildProgression(readRow(gangId, characterId))
    if not progression then
        return nil, reason
    end
    return progression
end

local function hasAdminViewPermission(source)
    if GetResourceState(ADMIN) ~= 'started' then
        return false
    end

    local ok, allowed = pcall(function()
        return exports[ADMIN]:HasPermission(tonumber(source), 'gang.admin.view')
    end)
    return ok and allowed == true
end

local function hasLeaderViewPermission(context)
    if context.membership.isLeader == true or context.membership.is_leader == true then
        return true
    end

    local ok, allowed = pcall(function()
        return exports[RESOURCE]:HasPermission(context.characterId, 'gang.manage_members')
    end)
    return ok and allowed == true
end

local function lockMember(gangId, characterId)
    local key = ('%s:%s'):format(gangId, characterId)
    local waited = 0
    while locks[key] do
        if waited >= 2500 then
            return nil
        end
        Wait(25)
        waited = waited + 25
    end
    locks[key] = true
    return key
end

local function unlockMember(key)
    if key then
        locks[key] = nil
    end
end

local function sanitizeMetadata(metadata)
    local progression = Config and Config.Progression or {}
    local maximumKeys = tonumber(progression.metadataMaximumKeys) or 8
    local maximumKeyLength = tonumber(progression.metadataKeyMaximumLength) or 32
    local maximumValueLength = tonumber(progression.metadataValueMaximumLength) or 96
    local maximumBytes = tonumber(progression.metadataMaximumBytes) or 1024

    if metadata == nil then
        return '{}'
    end
    if type(metadata) ~= 'table' then
        return nil
    end

    local sanitized = {}
    local count = 0
    for key, value in pairs(metadata) do
        if type(key) ~= 'string' or #key == 0 or #key > maximumKeyLength or not key:match('^[%w_%-]+$') then
            return nil
        end
        if type(value) ~= 'string' and type(value) ~= 'number' and type(value) ~= 'boolean' then
            return nil
        end
        if type(value) == 'string' and #value > maximumValueLength then
            return nil
        end
        count = count + 1
        if count > maximumKeys then
            return nil
        end
        sanitized[key] = value
    end

    local encoded = json.encode(sanitized)
    if type(encoded) ~= 'string' or #encoded > maximumBytes then
        return nil
    end
    return encoded
end

local function validReference(reference)
    local maximumLength = tonumber(Config.Progression and Config.Progression.referenceMaximumLength) or 128
    if type(reference) ~= 'string' or #reference == 0 or #reference > maximumLength then
        return nil
    end
    if not reference:match('^[%w%._:%-]+$') then
        return nil
    end
    return reference
end

local function validPoints(points)
    local maximumAward = tonumber(Config.Progression and Config.Progression.maximumAwardPoints) or 0
    if type(points) ~= 'number' or points < 1 or points % 1 ~= 0 or maximumAward < 1 or points > maximumAward then
        return nil
    end
    return points
end

local function makeClaimToken(reference)
    claimSequence = claimSequence + 1
    return ('%s:%d:%d:%s'):format(RESOURCE, os.time(), claimSequence, reference):sub(1, 96)
end

local function existingHistory(reference)
    return MySQL.single.await([[
        SELECT gang_id, character_id, points, source_resource, applied
        FROM cm_gang_contribution_history
        WHERE contribution_reference = ?
        LIMIT 1
    ]], { reference })
end

local function contributionResult(context, points, duplicate)
    local progression, reason = readProgression(context.gangId, context.characterId)
    if not progression then
        return { ok = false, reason = reason or 'progression_unavailable' }
    end

    return {
        ok = true,
        duplicate = duplicate == true,
        gangId = context.gangId,
        characterId = context.characterId,
        points = points,
        progression = progression,
    }
end

local function recordContribution(source, reference, points, metadata)
    local context, contextReason = memberContext(source)
    if not context then
        return { ok = false, reason = contextReason }
    end

    reference = validReference(reference)
    points = validPoints(points)
    local encodedMetadata = sanitizeMetadata(metadata)
    if not reference or not points or not encodedMetadata then
        return { ok = false, reason = 'invalid_contribution' }
    end

    local maximumTotal = tonumber(Config.Progression.maximumTotalContribution) or 0
    if maximumTotal < 1 then
        return { ok = false, reason = 'progression_config_invalid' }
    end

    local lockKey = lockMember(context.gangId, context.characterId)
    if not lockKey then
        return { ok = false, reason = 'busy' }
    end

    local function finish(result)
        unlockMember(lockKey)
        return result
    end

    local sourceResource = GetInvokingResource()
    if type(sourceResource) ~= 'string' or sourceResource == '' then
        return finish({ ok = false, reason = 'untrusted_resource' })
    end

    local trusted = Config.Progression.trustedContributionResources or {}
    if trusted[sourceResource] ~= true then
        return finish({ ok = false, reason = 'untrusted_resource' })
    end

    local currentRow = readRow(context.gangId, context.characterId)
    if currentRow and (tonumber(currentRow.total_contribution_earned) or 0) + points > maximumTotal then
        return finish({ ok = false, reason = 'contribution_limit' })
    end

    local history = existingHistory(reference)
    if history then
        if history.gang_id ~= context.gangId or asCharacterId(history.character_id) ~= context.characterId or tonumber(history.points) ~= points or history.source_resource ~= sourceResource then
            return finish({ ok = false, reason = 'reference_conflict' })
        end
        if tonumber(history.applied) == 1 then
            return finish(contributionResult(context, points, true))
        end
    else
        local inserted = MySQL.insert.await([[
            INSERT IGNORE INTO cm_gang_contribution_history
                (gang_id, character_id, contribution_reference, points, source_resource, metadata)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], { context.gangId, context.characterId, reference, points, sourceResource, encodedMetadata })
        if not inserted then
            return finish({ ok = false, reason = 'history_unavailable' })
        end

        history = existingHistory(reference)
        if not history then
            return finish({ ok = false, reason = 'history_unavailable' })
        end
    end

    if tonumber(history.applied) == 1 then
        return finish(contributionResult(context, points, true))
    end

    local claimToken = makeClaimToken(reference)
    local transaction = MySQL.transaction.await({
        {
            query = [[
                UPDATE cm_gang_contribution_history
                SET claim_token = ?
                WHERE contribution_reference = ? AND applied = 0 AND claim_token IS NULL
            ]],
            parameters = { claimToken, reference },
        },
        {
            query = [[
                INSERT INTO cm_gang_progression
                    (gang_id, character_id, contribution_points, reputation_level, total_contribution_earned, last_contribution_at, audit_metadata)
                SELECT ?, ?, ?, 1, ?, CURRENT_TIMESTAMP, ?
                FROM (SELECT 1) AS claim
                WHERE EXISTS (
                    SELECT 1 FROM cm_gang_contribution_history
                    WHERE contribution_reference = ? AND claim_token = ? AND applied = 0
                )
                ON DUPLICATE KEY UPDATE
                    contribution_points = contribution_points + VALUES(contribution_points),
                    total_contribution_earned = total_contribution_earned + VALUES(total_contribution_earned),
                    last_contribution_at = CURRENT_TIMESTAMP,
                    audit_metadata = VALUES(audit_metadata),
                    updated_at = CURRENT_TIMESTAMP
            ]],
            parameters = { context.gangId, context.characterId, points, points, encodedMetadata, reference, claimToken },
        },
        {
            query = [[
                UPDATE cm_gang_contribution_history
                SET applied = 1, applied_at = CURRENT_TIMESTAMP, claim_token = NULL
                WHERE contribution_reference = ? AND claim_token = ? AND applied = 0
            ]],
            parameters = { reference, claimToken },
        },
    })

    if transaction ~= true then
        return finish({ ok = false, reason = 'contribution_not_applied' })
    end

    local appliedHistory = existingHistory(reference)
    if not appliedHistory or tonumber(appliedHistory.applied) ~= 1 then
        return finish({ ok = false, reason = 'contribution_not_applied' })
    end

    local row = readRow(context.gangId, context.characterId)
    if not row or (tonumber(row.total_contribution_earned) or 0) > maximumTotal then
        return finish({ ok = false, reason = 'contribution_limit' })
    end

    local progression, progressionReason = buildProgression(row)
    if not progression then
        return finish({ ok = false, reason = progressionReason or 'progression_config_invalid' })
    end

    MySQL.update.await([[
        UPDATE cm_gang_progression
        SET reputation_level = ?, updated_at = CURRENT_TIMESTAMP
        WHERE gang_id = ? AND character_id = ?
    ]], { progression.reputationLevel, context.gangId, context.characterId })

    return finish(contributionResult(context, points, false))
end

function CMGangGetOwnProgression(source)
    local context, reason = memberContext(source)
    if not context then
        return { ok = false, reason = reason }
    end

    local progression, progressionReason = readProgression(context.gangId, context.characterId)
    if not progression then
        return { ok = false, reason = progressionReason }
    end

    return { ok = true, gangId = context.gangId, characterId = context.characterId, progression = progression }
end

function CMGangGetMemberProgression(source, requestedCharacterId, requestedGangId)
    local context, reason = memberContext(source)
    if not context then
        return { ok = false, reason = reason }
    end

    local targetCharacterId = asCharacterId(requestedCharacterId)
    local targetGangId
    if requestedGangId == nil then
        targetGangId = context.gangId
    else
        targetGangId = asGangId(requestedGangId)
    end
    if not targetCharacterId or not getGang(targetGangId) then
        return { ok = false, reason = 'invalid_member' }
    end

    local isAdmin = hasAdminViewPermission(context.source)
    if not isAdmin then
        if targetGangId ~= context.gangId or not hasLeaderViewPermission(context) then
            return { ok = false, reason = 'unauthorized' }
        end

        local targetMembership, targetMembershipGangId = getMembership(targetCharacterId)
        if not targetMembership or targetMembershipGangId ~= targetGangId then
            return { ok = false, reason = 'member_not_in_gang' }
        end
    end

    local progression, progressionReason = readProgression(targetGangId, targetCharacterId)
    if not progression then
        return { ok = false, reason = progressionReason }
    end

    return {
        ok = true,
        gangId = targetGangId,
        characterId = targetCharacterId,
        progression = progression,
    }
end

exports('RecordGangContribution', function(source, reference, points, metadata)
    return recordContribution(source, reference, points, metadata)
end)

exports('GetOwnGangProgression', function(source)
    return CMGangGetOwnProgression(source)
end)

exports('GetGangMemberProgression', function(source, characterId, gangId)
    return CMGangGetMemberProgression(source, characterId, gangId)
end)

if lib and lib.callback then
    lib.callback.register('cm-gang:server:getMyProgression', function(source)
        return CMGangGetOwnProgression(source)
    end)

    lib.callback.register('cm-gang:server:getMemberProgression', function(source, request)
        if type(request) ~= 'table' then
            return { ok = false, reason = 'invalid_request' }
        end
        return CMGangGetMemberProgression(source, request.characterId, request.gangId)
    end)
end
