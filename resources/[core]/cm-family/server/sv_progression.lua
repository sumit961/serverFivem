-- ============================================================
-- cm-family | sv_progression.lua | v1.8.1
-- Authoritative, persistent family progression, reputation, and level engine.
-- Fully transactional, concurrency-safe, and idempotent.
-- ============================================================

local B = CMFamilyBridge
ProgressionByFamily = {} -- [familyId] = { level, currentXp, lifetimeReputation, seasonReputation }

local progressionLocks = {}

local function acquireProgressionLock(familyId, maxWaitMs)
    if type(AcquireTreasuryLock) == 'function' then
        return AcquireTreasuryLock(familyId, maxWaitMs)
    end
    maxWaitMs = tonumber(maxWaitMs) or 2000
    local elapsed = 0
    while progressionLocks[familyId] do
        Wait(10)
        elapsed = elapsed + 10
        if elapsed >= maxWaitMs then
            return false, 'progression_lock_timeout'
        end
    end
    progressionLocks[familyId] = true
    return true
end

local function releaseProgressionLock(familyId)
    if type(ReleaseTreasuryLock) == 'function' then
        return ReleaseTreasuryLock(familyId)
    end
    progressionLocks[familyId] = nil
end

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
        pcall(function()
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

-- Transactional calculation helper using fresh DB state
local function calculateNewProgression(currentLevel, currentXp, lifetimeRep, seasonRep, addedAmount)
    local maxLevel = getProgressionConfig().maxLevel or 25
    local oldLevel = currentLevel
    local newXp = currentXp + addedAmount
    local newLifetime = lifetimeRep + addedAmount
    local newSeason = seasonRep + addedAmount
    local newLevel = currentLevel
    local leveledUp = false

    while newLevel < maxLevel do
        local required = getNextLevelXp(newLevel)
        if newXp >= required then
            newXp = newXp - required
            newLevel = newLevel + 1
            leveledUp = true
        else
            break
        end
    end

    if newLevel >= maxLevel then
        newXp = math.min(newXp, getNextLevelXp(maxLevel))
    end

    return newLevel, newXp, newLifetime, newSeason, leveledUp, oldLevel
end

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

    -- Pre-check unique ID
    if uniqueId and uniqueId ~= '' then
        uniqueId = tostring(uniqueId)
        if not CanAwardFamilyReputation(familyId, uniqueId) then
            return false, 'duplicate_reward_unique_id'
        end
    end

    -- Serialize per-family updates to prevent lost XP from concurrent awards
    local lockOk, lockErr = acquireProgressionLock(familyId)
    if not lockOk then
        return false, lockErr or 'progression_lock_timeout'
    end

    local execOk, resultSuccess, resultPayload = pcall(function()
        -- 1. Read authoritative progression fresh from DB
        local row = MySQL.single.await([[
            SELECT level, current_xp, lifetime_reputation, season_reputation
            FROM cm_family_progression
            WHERE family_id = ?
            LIMIT 1
        ]], { familyId })

        if not row then
            LoadFamilyProgression(familyId)
            row = MySQL.single.await([[
                SELECT level, current_xp, lifetime_reputation, season_reputation
                FROM cm_family_progression
                WHERE family_id = ?
                LIMIT 1
            ]], { familyId })
        end

        local curLevel = math.max(1, tonumber(row and row.level) or 1)
        local curXp = math.max(0, tonumber(row and row.current_xp) or 0)
        local curLifetime = math.max(0, tonumber(row and row.lifetime_reputation) or 0)
        local curSeason = math.max(0, tonumber(row and row.season_reputation) or 0)

        local newLevel, newXp, newLifetime, newSeason, leveledUp, oldLevel =
            calculateNewProgression(curLevel, curXp, curLifetime, curSeason, amount)

        -- 2. Build atomic transaction statements
        local statements = {}

        if uniqueId and uniqueId ~= '' then
            statements[#statements + 1] = {
                query = [[
                    INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source, metadata)
                    VALUES (?, ?, 'reputation', ?, ?, ?)
                ]],
                values = { uniqueId, familyId, amount, source, metadata and json.encode(metadata) or nil }
            }
        end

        statements[#statements + 1] = {
            query = [[
                UPDATE cm_family_progression
                SET level = ?, current_xp = ?, lifetime_reputation = ?, season_reputation = ?
                WHERE family_id = ?
            ]],
            values = { newLevel, newXp, newLifetime, newSeason, familyId }
        }

        -- 3. Execute transaction
        local txCommitted = MySQL.transaction.await(statements)
        if txCommitted ~= true then
            return false, 'transaction_failed'
        end

        -- 4. Update in-memory cache ONLY after successful DB commit
        local prog = ProgressionByFamily[familyId] or {}
        prog.level = newLevel
        prog.currentXp = newXp
        prog.lifetimeReputation = newLifetime
        prog.seasonReputation = newSeason
        ProgressionByFamily[familyId] = prog

        -- Audit log
        LogFamily(familyId, nil, 'reputation_awarded', {
            amount = amount,
            source = source,
            uniqueId = uniqueId,
            newLevel = newLevel,
            leveledUp = leveledUp,
        })

        if leveledUp then
            LogFamily(familyId, nil, 'family_level_up', {
                oldLevel = oldLevel,
                newLevel = newLevel,
                unlocked = Config.GetLevelUnlocks and Config.GetLevelUnlocks(newLevel) or nil,
            }, { severity = 'warning' })

            for cid, membership in pairs(MemberByCid) do
                if tonumber(membership.family_id) == familyId then
                    local playerSrc = B.GetSrcByCid(cid)
                    if playerSrc then
                        B.Notify(playerSrc, ('Family reached Level %d! Check your progression unlocks.'):format(newLevel), 'success')
                    end
                end
            end
            SyncFamilyState(familyId)
        end

        return true, {
            level = newLevel,
            currentXp = newXp,
            nextLevelXp = getNextLevelXp(newLevel),
            lifetimeReputation = newLifetime,
            leveledUp = leveledUp,
        }
    end)

    releaseProgressionLock(familyId)

    if not execOk then
        return false, tostring(resultSuccess)
    end
    return resultSuccess, resultPayload
end
exports('AddFamilyReputation', AddFamilyReputation)

-- Semantics:
-- 1. lifetime_reputation NEVER decreases (total positive reputation ever earned).
-- 2. Family level NEVER goes backwards (unlocks stay earned).
-- 3. Penalty reduces current_xp (minimum 0) and season_reputation (minimum 0).
function RemoveFamilyReputation(familyId, amount, reason)
    familyId = tonumber(familyId)
    amount = math.floor(tonumber(amount) or 0)
    reason = tostring(reason or 'penalty')

    if not familyId or amount <= 0 then
        return false, 'invalid_arguments'
    end

    local lockOk, lockErr = acquireProgressionLock(familyId)
    if not lockOk then
        return false, lockErr or 'progression_lock_timeout'
    end

    local execOk, resSuccess, resPayload = pcall(function()
        local row = MySQL.single.await([[
            SELECT level, current_xp, lifetime_reputation, season_reputation
            FROM cm_family_progression
            WHERE family_id = ?
            LIMIT 1
        ]], { familyId })

        if not row then
            return false, 'progression_unavailable'
        end

        local curLevel = math.max(1, tonumber(row.level) or 1)
        local curXp = math.max(0, (tonumber(row.current_xp) or 0) - amount)
        local curSeason = math.max(0, (tonumber(row.season_reputation) or 0) - amount)
        local lifetime = math.max(0, tonumber(row.lifetime_reputation) or 0)

        local updated = MySQL.update.await([[
            UPDATE cm_family_progression
            SET current_xp = ?, season_reputation = ?
            WHERE family_id = ?
        ]], { curXp, curSeason, familyId })

        if not updated or updated <= 0 then
            return false, 'database_update_failed'
        end

        local prog = ProgressionByFamily[familyId] or {}
        prog.level = curLevel
        prog.currentXp = curXp
        prog.seasonReputation = curSeason
        prog.lifetimeReputation = lifetime
        ProgressionByFamily[familyId] = prog

        LogFamily(familyId, nil, 'reputation_removed', {
            amount = amount,
            reason = reason,
            remainingCurrentXp = curXp,
        })

        return true, { level = curLevel, currentXp = curXp }
    end)

    releaseProgressionLock(familyId)

    if not execOk then return false, tostring(resSuccess) end
    return resSuccess, resPayload
end
exports('RemoveFamilyReputation', RemoveFamilyReputation)

-- Unified Root Idempotent Event / Activity Reward API.
-- Protects the ENTIRE activity reward under payload.uniqueId.
-- If payload.uniqueId was already claimed, pays NOTHING (0 XP, $0 treasury, 0 contribution).
function AwardFamilyActivityReward(payload)
    payload = type(payload) == 'table' and payload or {}
    local familyId = tonumber(payload.familyId)
    if not familyId then return false, 'invalid_family_id' end

    local repReward = math.max(0, math.floor(tonumber(payload.reputation) or 0))
    local contribReward = math.max(0, math.floor(tonumber(payload.memberContribution) or 0))
    local treasuryReward = math.max(0, math.floor(tonumber(payload.treasuryAmount) or 0))
    local uniqueId = payload.uniqueId and tostring(payload.uniqueId) or nil

    -- Requirement 5: Require uniqueId for any rewarded activity
    if repReward > 0 or contribReward > 0 or treasuryReward > 0 then
        if not uniqueId or uniqueId == '' then
            return false, 'unique_id_required'
        end
    end

    if uniqueId and uniqueId ~= '' then
        if not CanAwardFamilyReputation(familyId, uniqueId) then
            return false, 'duplicate_reward_unique_id'
        end
    end

    local eventType = tostring(payload.eventType or 'activity')
    local actorCid = payload.actorCid and tostring(payload.actorCid) or nil
    local participants = type(payload.participants) == 'table' and payload.participants or {}

    -- Resolve unique participant CIDs
    local targetCids = {}
    local seenCids = {}
    if #participants > 0 then
        for _, p in ipairs(participants) do
            local cid = type(p) == 'table' and (p.cid or p.characterId) or tostring(p)
            if cid and cid ~= '' and not seenCids[cid] then
                seenCids[cid] = true
                targetCids[#targetCids + 1] = cid
            end
        end
    elseif actorCid and actorCid ~= '' then
        targetCids[1] = actorCid
    end

    local lockOk, lockErr = acquireProgressionLock(familyId)
    if not lockOk then
        return false, lockErr or 'progression_lock_timeout'
    end

    local currentWeekKey = (type(CMFamilyGetWeekKey) == 'function' and CMFamilyGetWeekKey()) or os.date('%Y-W%W')
    local actualTreasuryCredited = 0

    local execOk, resSuccess, resPayload = pcall(function()
        local statements = {}

        -- Pre-calculate treasury headroom under the lock for accurate delivery envelope
        if treasuryReward > 0 then
            local maxBal = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
            local curBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId })) or 0
            local spaceRemaining = math.max(0, maxBal - curBal)
            actualTreasuryCredited = math.min(treasuryReward, spaceRemaining)
        end

        -- Build authoritative delivery envelope for root reward history
        local deliveryEnvelope = {
            reputation = repReward,
            treasuryRequested = treasuryReward,
            treasuryCredited = actualTreasuryCredited,
            memberContribution = contribReward,
            participantCount = #targetCids,
            eventUid = payload.eventUid,
            eventKey = payload.eventKey or eventType,
            familyId = familyId,
            deliveredAt = os.time(),
        }
        if type(payload.metadata) == 'table' then
            for k, v in pairs(payload.metadata) do
                if deliveryEnvelope[k] == nil then
                    deliveryEnvelope[k] = v
                end
            end
        end

        -- 1. Reserve root operation in cm_family_reward_history.
        -- This guarantees that even if repReward == 0 (treasury-only or contribution-only),
        -- calling twice will fail on unique key constraint.
        if uniqueId and uniqueId ~= '' then
            statements[#statements + 1] = {
                query = [[
                    INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source, metadata)
                    VALUES (?, ?, 'activity_root', ?, ?, ?)
                ]],
                values = { uniqueId, familyId, repReward, eventType, json.encode(deliveryEnvelope) }
            }
        end

        -- 2. Progression update
        local newLevel, newXp, newLifetime, newSeason, leveledUp, oldLevel
        if repReward > 0 then
            local row = MySQL.single.await([[
                SELECT level, current_xp, lifetime_reputation, season_reputation
                FROM cm_family_progression
                WHERE family_id = ?
                LIMIT 1
            ]], { familyId })

            local curLevel = math.max(1, tonumber(row and row.level) or 1)
            local curXp = math.max(0, tonumber(row and row.current_xp) or 0)
            local curLifetime = math.max(0, tonumber(row and row.lifetime_reputation) or 0)
            local curSeason = math.max(0, tonumber(row and row.season_reputation) or 0)

            newLevel, newXp, newLifetime, newSeason, leveledUp, oldLevel =
                calculateNewProgression(curLevel, curXp, curLifetime, curSeason, repReward)

            statements[#statements + 1] = {
                query = [[
                    UPDATE cm_family_progression
                    SET level = ?, current_xp = ?, lifetime_reputation = ?, season_reputation = ?
                    WHERE family_id = ?
                ]],
                values = { newLevel, newXp, newLifetime, newSeason, familyId }
            }
        end

        -- 3. Treasury payout with strict balance cap accounting
        if actualTreasuryCredited > 0 then
            statements[#statements + 1] = {
                query = [[
                    UPDATE cm_families
                    SET bank_balance = bank_balance + ?
                    WHERE id = ?
                ]],
                values = { actualTreasuryCredited, familyId }
            }

            local bankReason = (uniqueId and uniqueId ~= '') and ('event_reward:%s:%s'):format(eventType, uniqueId) or ('event_reward:%s'):format(eventType)
            statements[#statements + 1] = {
                query = [[
                    INSERT INTO cm_family_bank_log (family_id, character_id, direction, category, amount, balance_after, reason)
                    VALUES (?, ?, 'deposit', 'event_reward', ?, (SELECT bank_balance FROM cm_families WHERE id = ?), ?)
                ]],
                values = { familyId, actorCid, actualTreasuryCredited, familyId, bankReason }
            }
        end

        -- 4. Requirement 4: Include participant contributions in the SAME transaction!
        if contribReward > 0 and #targetCids > 0 then
            for _, cid in ipairs(targetCids) do
                local childId = uniqueId and ('%s:participant:%s'):format(uniqueId, cid) or nil
                if childId then
                    statements[#statements + 1] = {
                        query = [[
                            INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source)
                            VALUES (?, ?, 'participant_contribution', ?, ?)
                        ]],
                        values = { childId, familyId, contribReward, eventType }
                    }
                end

                statements[#statements + 1] = {
                    query = [[
                        INSERT INTO cm_family_member_contributions
                          (family_id, character_id, total_points, weekly_points, event_points, last_contribution_at)
                        VALUES (?, ?, ?, ?, ?, NOW())
                        ON DUPLICATE KEY UPDATE
                          total_points = total_points + VALUES(total_points),
                          weekly_points = weekly_points + VALUES(weekly_points),
                          event_points = event_points + VALUES(event_points),
                          last_contribution_at = NOW()
                    ]],
                    values = { familyId, cid, contribReward, contribReward, contribReward }
                }

                statements[#statements + 1] = {
                    query = [[
                        INSERT INTO cm_family_contribution_weekly
                          (family_id, character_id, week_key, total_points, event_points)
                        VALUES (?, ?, ?, ?, ?)
                        ON DUPLICATE KEY UPDATE
                          total_points = total_points + VALUES(total_points),
                          event_points = event_points + VALUES(event_points)
                    ]],
                    values = { familyId, cid, currentWeekKey, contribReward, contribReward }
                }
            end
        end

        -- Execute core family-level transaction (including all participant rows)
        local txCommitted = MySQL.transaction.await(statements)
        if txCommitted ~= true then
            return false, 'transaction_failed'
        end

        -- Update progression in memory
        if repReward > 0 and newLevel then
            local prog = ProgressionByFamily[familyId] or {}
            prog.level = newLevel
            prog.currentXp = newXp
            prog.lifetimeReputation = newLifetime
            prog.seasonReputation = newSeason
            ProgressionByFamily[familyId] = prog

            if leveledUp then
                LogFamily(familyId, nil, 'family_level_up', {
                    oldLevel = oldLevel,
                    newLevel = newLevel,
                }, { severity = 'warning' })
                SyncFamilyState(familyId)
            end
        end

        -- Update treasury in memory
        if actualTreasuryCredited > 0 then
            local fam = GetFamilyById(familyId)
            local newBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId })) or 0
            if fam then fam.bank_balance = newBal end
        end

        return true, 'committed'
    end)

    releaseProgressionLock(familyId)

    if not execOk or resSuccess ~= true then
        return false, tostring(resPayload or 'root_reward_failed')
    end

    -- 5. Advance weekly objectives
    if type(AdvanceFamilyObjective) == 'function' then
        AdvanceFamilyObjective(familyId, 'family_actions', 1, actorCid)
        if actualTreasuryCredited > 0 then
            AdvanceFamilyObjective(familyId, 'net_deposits', actualTreasuryCredited, actorCid)
        end
    end

    LogFamily(familyId, actorCid, 'activity_reward_granted', {
        eventType = eventType,
        uniqueId = uniqueId,
        reputation = repReward,
        memberContribution = contribReward,
        treasuryRequested = treasuryReward,
        treasuryCredited = actualTreasuryCredited,
        participantCount = #targetCids,
    })

    return true, {
        familyId = familyId,
        uniqueId = uniqueId,
        reputation = repReward,
        treasury = actualTreasuryCredited,
        treasuryRequested = treasuryReward,
        treasuryCredited = actualTreasuryCredited,
        memberContribution = contribReward,
        participantCount = #targetCids,
        participants = targetCids,
    }
end
exports('AwardFamilyActivityReward', AwardFamilyActivityReward)
