-- ============================================================
-- cm-family | sv_progression.lua | v1.8.0
-- Authoritative, persistent family progression, reputation, and level engine.
-- Server-only validation; client requests cannot award reputation.
-- ============================================================

local B = CMFamilyBridge
ProgressionByFamily = {} -- [familyId] = { level, currentXp, lifetimeReputation, seasonReputation }

local function getProgressionConfig()
    return Config.Progression or { maxLevel = 25 }
end

local function getNextLevelXp(level)
    if Config.Progression and type(Config.Progression.GetXpForNextLevel) == 'function' then
        return Config.Progression.GetXpForNextLevel(level)
    end
    return 1000 + ((level - 1) * 500)
end

function LoadFamilyProgression(familyId)
    familyId = tonumber(familyId)
    if not familyId then return nil end

    local row = MySQL.single.await([[
        SELECT level, current_xp, lifetime_reputation, season_reputation
        FROM cm_family_progression
        WHERE family_id = ?
        LIMIT 1
    ]], { familyId })

    if not row then
        -- Initialize row for existing or new family
        local ok = pcall(function()
            MySQL.insert.await([[
                INSERT INTO cm_family_progression (family_id, level, current_xp, lifetime_reputation, season_reputation)
                VALUES (?, 1, 0, 0, 0)
                ON DUPLICATE KEY UPDATE level = level
            ]], { familyId })
        end)
        row = { level = 1, current_xp = 0, lifetime_reputation = 0, season_reputation = 0 }
    end

    local prog = {
        level = math.max(1, tonumber(row.level) or 1),
        currentXp = math.max(0, tonumber(row.current_xp) or 0),
        lifetimeReputation = math.max(0, tonumber(row.lifetime_reputation) or 0),
        seasonReputation = math.max(0, tonumber(row.season_reputation) or 0),
    }
    ProgressionByFamily[familyId] = prog
    return prog
end

function GetFamilyProgression(familyId)
    familyId = tonumber(familyId)
    if not familyId then return nil end

    local prog = ProgressionByFamily[familyId]
    if not prog then
        prog = LoadFamilyProgression(familyId)
    end
    if not prog then return nil end

    local nextXp = getNextLevelXp(prog.level)
    local xpPercent = math.min(100, math.max(0, math.floor((prog.currentXp / math.max(1, nextXp)) * 100)))

    return {
        level = prog.level,
        currentXp = prog.currentXp,
        nextLevelXp = nextXp,
        lifetimeReputation = prog.lifetimeReputation,
        seasonReputation = prog.seasonReputation,
        xpPercent = xpPercent,
        maxLevel = getProgressionConfig().maxLevel or 25,
    }
end
exports('GetFamilyProgression', GetFamilyProgression)

function CanAwardFamilyReputation(familyId, uniqueId)
    familyId = tonumber(familyId)
    if not familyId or not uniqueId or tostring(uniqueId) == '' then return true end

    local existing = MySQL.scalar.await([[
        SELECT id FROM cm_family_reward_history
        WHERE unique_id = ?
        LIMIT 1
    ]], { tostring(uniqueId) })

    return existing == nil
end
exports('CanAwardFamilyReputation', CanAwardFamilyReputation)

function AddFamilyReputation(familyId, amount, source, uniqueId, metadata)
    familyId = tonumber(familyId)
    amount = math.floor(tonumber(amount) or 0)
    source = tostring(source or 'unknown')

    if not familyId or amount <= 0 then
        return false, 'invalid_arguments'
    end

    local family = GetFamilyById(familyId)
    if not family then
        return false, 'family_not_found'
    end

    if uniqueId and uniqueId ~= '' then
        uniqueId = tostring(uniqueId)
        if not CanAwardFamilyReputation(familyId, uniqueId) then
            return false, 'duplicate_reward_unique_id'
        end
    end

    local prog = ProgressionByFamily[familyId] or LoadFamilyProgression(familyId)
    if not prog then
        return false, 'progression_unavailable'
    end

    local maxLevel = getProgressionConfig().maxLevel or 25
    local oldLevel = prog.level
    local currentXp = prog.currentXp + amount
    local lifetime = prog.lifetimeReputation + amount
    local season = prog.seasonReputation + amount
    local level = prog.level
    local leveledUp = false

    -- Calculate level progressions
    while level < maxLevel do
        local required = getNextLevelXp(level)
        if currentXp >= required then
            currentXp = currentXp - required
            level = level + 1
            leveledUp = true
        else
            break
        end
    end

    if level >= maxLevel then
        currentXp = math.min(currentXp, getNextLevelXp(maxLevel))
    end

    -- If uniqueId is provided, atomically insert reward history first.
    -- The DB unique index `uniq_reward_uid` guarantees duplicate prevention even under concurrent calls.
    if uniqueId and uniqueId ~= '' then
        local insOk, insRes = pcall(function()
            return MySQL.insert.await([[
                INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source, metadata)
                VALUES (?, ?, 'reputation', ?, ?, ?)
            ]], { uniqueId, familyId, amount, source, metadata and json.encode(metadata) or nil })
        end)
        if not insOk or not insRes then
            return false, 'duplicate_reward_unique_id'
        end
    end

    -- Update database progression
    local ok = pcall(function()
        return MySQL.update.await([[
            UPDATE cm_family_progression
            SET level = ?, current_xp = ?, lifetime_reputation = ?, season_reputation = ?
            WHERE family_id = ?
        ]], { level, currentXp, lifetime, season, familyId })
    end)

    if not ok then
        return false, 'database_update_failed'
    end

    prog.level = level
    prog.currentXp = currentXp
    prog.lifetimeReputation = lifetime
    prog.seasonReputation = season

    -- Audit log
    LogFamily(familyId, nil, 'reputation_awarded', {
        amount = amount,
        source = source,
        uniqueId = uniqueId,
        newLevel = level,
        leveledUp = leveledUp,
    })

    if leveledUp then
        LogFamily(familyId, nil, 'family_level_up', {
            oldLevel = oldLevel,
            newLevel = level,
            unlocked = Config.GetLevelUnlocks and Config.GetLevelUnlocks(level) or nil,
        }, { severity = 'warning' })

        -- Notify all online family members
        for cid, membership in pairs(MemberByCid) do
            if tonumber(membership.family_id) == familyId then
                local playerSrc = B.GetSrcByCid(cid)
                if playerSrc then
                    B.Notify(playerSrc, ('Family reached Level %d! Check your progression unlocks.'):format(level), 'success')
                end
            end
        end
        SyncFamilyState(familyId)
    end

    return true, {
        level = level,
        currentXp = currentXp,
        nextLevelXp = getNextLevelXp(level),
        lifetimeReputation = lifetime,
        leveledUp = leveledUp,
    }
end
exports('AddFamilyReputation', AddFamilyReputation)

function RemoveFamilyReputation(familyId, amount, reason)
    familyId = tonumber(familyId)
    amount = math.floor(tonumber(amount) or 0)
    reason = tostring(reason or 'penalty')

    if not familyId or amount <= 0 then
        return false, 'invalid_arguments'
    end

    local prog = ProgressionByFamily[familyId] or LoadFamilyProgression(familyId)
    if not prog then return false, 'progression_unavailable' end

    local currentXp = math.max(0, prog.currentXp - amount)
    local lifetime = math.max(0, prog.lifetimeReputation - amount)

    pcall(function()
        MySQL.update.await([[
            UPDATE cm_family_progression
            SET current_xp = ?, lifetime_reputation = ?
            WHERE family_id = ?
        ]], { currentXp, lifetime, familyId })
    end)

    prog.currentXp = currentXp
    prog.lifetimeReputation = lifetime

    LogFamily(familyId, nil, 'reputation_removed', {
        amount = amount,
        reason = reason,
    })

    return true, { level = prog.level, currentXp = currentXp }
end
exports('RemoveFamilyReputation', RemoveFamilyReputation)

-- Unified Event / Activity Reward API
-- Future resources and existing systems call this single seam
function AwardFamilyActivityReward(payload)
    payload = type(payload) == 'table' and payload or {}
    local familyId = tonumber(payload.familyId)
    if not familyId then return false, 'invalid_family_id' end

    local uniqueId = payload.uniqueId and tostring(payload.uniqueId)
    if uniqueId and uniqueId ~= '' and not CanAwardFamilyReputation(familyId, uniqueId) then
        return false, 'duplicate_reward_unique_id'
    end

    local eventType = tostring(payload.eventType or 'activity')
    local actorCid = payload.actorCid and tostring(payload.actorCid) or nil
    local repReward = math.floor(tonumber(payload.reputation) or 0)
    local contribReward = math.floor(tonumber(payload.memberContribution) or 0)
    local treasuryReward = math.floor(tonumber(payload.treasuryAmount) or 0)
    local participants = type(payload.participants) == 'table' and payload.participants or {}

    -- 1. Family Reputation
    if repReward > 0 then
        AddFamilyReputation(familyId, repReward, eventType, uniqueId, payload.metadata)
    end

    -- 2. Member Contribution to participants
    if contribReward > 0 then
        local targetCids = {}
        if #participants > 0 then
            for _, p in ipairs(participants) do
                local cid = type(p) == 'table' and (p.cid or p.characterId) or tostring(p)
                if cid and cid ~= '' then targetCids[#targetCids + 1] = cid end
            end
        elseif actorCid then
            targetCids[1] = actorCid
        end

        for _, cid in ipairs(targetCids) do
            if type(AddFamilyMemberContribution) == 'function' then
                AddFamilyMemberContribution(cid, familyId, contribReward, eventType, eventType, uniqueId and (uniqueId .. ':' .. cid))
            end
        end
    end

    -- 3. Treasury payout
    if treasuryReward > 0 then
        local maxBal = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
        pcall(function()
            MySQL.update.await([[
                UPDATE cm_families
                SET bank_balance = LEAST(bank_balance + ?, ?)
                WHERE id = ?
            ]], { treasuryReward, maxBal, familyId })

            local fam = GetFamilyById(familyId)
            local newBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId })) or 0
            if fam then fam.bank_balance = newBal end

            MySQL.insert.await([[
                INSERT INTO cm_family_bank_log (family_id, character_id, direction, category, amount, balance_after, reason)
                VALUES (?, ?, 'deposit', 'event_reward', ?, ?, ?)
            ]], { familyId, actorCid, treasuryReward, newBal, ('event_reward:%s'):format(eventType) })
        end)
    end

    -- 4. Advance weekly objectives
    if type(AdvanceFamilyObjective) == 'function' then
        AdvanceFamilyObjective(familyId, 'family_actions', 1, actorCid)
        if treasuryReward > 0 then
            AdvanceFamilyObjective(familyId, 'net_deposits', treasuryReward, actorCid)
        end
    end

    LogFamily(familyId, actorCid, 'activity_reward_granted', {
        eventType = eventType,
        uniqueId = uniqueId,
        reputation = repReward,
        memberContribution = contribReward,
        treasury = treasuryReward,
        participantCount = #participants,
    })

    return true
end
exports('AwardFamilyActivityReward', AwardFamilyActivityReward)

