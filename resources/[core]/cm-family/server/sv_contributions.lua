-- ============================================================
-- cm-family | sv_contributions.lua | v1.8.1
-- Authoritative family member contribution score and leaderboards.
-- Hardened with persistent daily financial cap and atomic transactions.
-- ============================================================

local B = CMFamilyBridge

local function getContributionConfig()
    return Config.Contribution or {}
end

function GetMemberContribution(characterId, familyId)
    characterId = tostring(characterId)
    familyId = tonumber(familyId)
    if not characterId or not familyId then return nil end

    local row = MySQL.single.await([[
        SELECT total_points, weekly_points, activity_points, financial_points,
               money_contributed, event_points, last_contribution_at
        FROM cm_family_member_contributions
        WHERE family_id = ? AND character_id = ?
        LIMIT 1
    ]], { familyId, characterId })

    if not row then
        return {
            totalPoints = 0,
            weeklyPoints = 0,
            activityPoints = 0,
            financialPoints = 0,
            moneyContributed = 0,
            eventPoints = 0,
            lastContributionAt = nil,
        }
    end

    return {
        totalPoints = tonumber(row.total_points) or 0,
        weeklyPoints = tonumber(row.weekly_points) or 0,
        activityPoints = tonumber(row.activity_points) or 0,
        financialPoints = tonumber(row.financial_points) or 0,
        moneyContributed = tonumber(row.money_contributed) or 0,
        eventPoints = tonumber(row.event_points) or 0,
        lastContributionAt = row.last_contribution_at,
    }
end
exports('GetMemberContribution', GetMemberContribution)

local contributionLocks = {}

local function acquireContributionLock(lockKey, maxWaitMs)
    maxWaitMs = tonumber(maxWaitMs) or 2500
    local elapsed = 0
    while contributionLocks[lockKey] do
        Wait(10)
        elapsed = elapsed + 10
        if elapsed >= maxWaitMs then
            return false, 'contribution_lock_timeout'
        end
    end
    contributionLocks[lockKey] = true
    return true
end

local function releaseContributionLock(lockKey)
    contributionLocks[lockKey] = nil
end

-- Transactional and idempotent member contribution award
function AddFamilyMemberContribution(characterId, familyId, amount, category, source, uniqueId)
    characterId = tostring(characterId)
    familyId = tonumber(familyId)
    amount = math.floor(tonumber(amount) or 0)
    category = tostring(category or 'activity'):lower()
    source = tostring(source or 'system')

    if not characterId or not familyId or amount <= 0 then
        return false, 'invalid_arguments'
    end

    -- Pre-check unique ID
    if uniqueId and uniqueId ~= '' then
        uniqueId = tostring(uniqueId)
        local existing = MySQL.scalar.await([[
            SELECT id FROM cm_family_reward_history
            WHERE unique_id = ?
            LIMIT 1
        ]], { uniqueId })
        if existing then
            return false, 'duplicate_reward_unique_id'
        end
    end

    -- Category validation & mapping
    local isActivity = (category == 'activity' or category == 'family_work' or category == 'defence' or category == 'management' or category == 'support')
    local isEvent = (category == 'event' or category == 'objective')
    local isFinancial = (category == 'financial')

    local actAdd = isActivity and amount or 0
    local eventAdd = isEvent and amount or 0
    local finAdd = isFinancial and amount or 0

    local currentWeekKey = (type(CMFamilyGetWeekKey) == 'function' and CMFamilyGetWeekKey()) or os.date('%Y-W%W')
    local statements = {}

    -- 1. Reward history reservation (fails closed if duplicate key)
    if uniqueId and uniqueId ~= '' then
        statements[#statements + 1] = {
            query = [[
                INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source)
                VALUES (?, ?, 'contribution', ?, ?)
            ]],
            values = { uniqueId, familyId, amount, source }
        }
    end

    -- 2. Overall lifetime contribution update
    statements[#statements + 1] = {
        query = [[
            INSERT INTO cm_family_member_contributions
              (family_id, character_id, total_points, weekly_points, activity_points, financial_points, event_points, last_contribution_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE
              total_points = total_points + VALUES(total_points),
              weekly_points = weekly_points + VALUES(weekly_points),
              activity_points = activity_points + VALUES(activity_points),
              financial_points = financial_points + VALUES(financial_points),
              event_points = event_points + VALUES(event_points),
              last_contribution_at = NOW()
        ]],
        values = { familyId, characterId, amount, amount, actAdd, finAdd, eventAdd }
    }

    -- 3. Dedicated weekly contribution ledger record
    statements[#statements + 1] = {
        query = [[
            INSERT INTO cm_family_contribution_weekly
              (family_id, character_id, week_key, total_points, activity_points, financial_points, event_points)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
              total_points = total_points + VALUES(total_points),
              activity_points = activity_points + VALUES(activity_points),
              financial_points = financial_points + VALUES(financial_points),
              event_points = event_points + VALUES(event_points)
        ]],
        values = { familyId, characterId, currentWeekKey, amount, actAdd, finAdd, eventAdd }
    }

    local txOk, committed = pcall(function()
        return MySQL.transaction.await(statements)
    end)

    if not txOk or committed ~= true then
        local errStr = tostring(committed or '')
        if uniqueId and uniqueId ~= '' then
            local exists = MySQL.scalar.await('SELECT 1 FROM cm_family_reward_history WHERE unique_id = ? LIMIT 1', { uniqueId })
            if exists then
                return false, 'duplicate_reward_unique_id'
            end
        end
        if string.find(errStr, 'Duplicate entry') then
            return false, 'duplicate_reward_unique_id'
        end
        return false, ('transaction_failed:%s'):format(errStr ~= '' and errStr or 'database_error')
    end

    return true, amount
end
exports('AddFamilyMemberContribution', AddFamilyMemberContribution)

-- Safe financial contribution recorder:
-- Uses persistent daily tracking in cm_family_contribution_daily.
-- Enforces a strict daily cap of maxDailyFinancialPoints (default 100 points)
-- across ALL deposits in a single day, serialized per (family, character, day).
-- Full cash value is always recorded in money_contributed.
function RecordFinancialContribution(characterId, familyId, moneyAmount, uniqueId)
    characterId = tostring(characterId)
    familyId = tonumber(familyId)
    moneyAmount = math.floor(tonumber(moneyAmount) or 0)

    if not characterId or not familyId or moneyAmount <= 0 then
        return false, 'invalid_arguments'
    end

    local cfg = getContributionConfig()
    local moneyPerPoint = tonumber(cfg.moneyPerPoint) or 1000
    local rawPoints = math.floor(moneyAmount / moneyPerPoint)
    local maxDaily = tonumber(cfg.maxDailyFinancialPoints) or 100
    local dayKey = os.date('!%Y-%m-%d') -- UTC day key
    local currentWeekKey = (type(CMFamilyGetWeekKey) == 'function' and CMFamilyGetWeekKey()) or os.date('%Y-W%W')

    -- Concurrency lock per (family, character, day)
    local lockKey = ('fin:%s:%s:%s'):format(familyId, characterId, dayKey)
    local lockOk, lockErr = acquireContributionLock(lockKey)
    if not lockOk then
        return false, lockErr or 'contribution_lock_timeout'
    end

    local execOk, resSuccess, resPoints = pcall(function()
        -- 1. Authoritative check under lock: how many financial points were already earned today?
        local dailyRow = MySQL.single.await([[
            SELECT financial_points, money_contributed
            FROM cm_family_contribution_daily
            WHERE family_id = ? AND character_id = ? AND day_key = ?
            LIMIT 1
        ]], { familyId, characterId, dayKey })

        local currentDailyPoints = dailyRow and tonumber(dailyRow.financial_points) or 0
        local remainingAllowed = math.max(0, maxDaily - currentDailyPoints)
        local pointsToAward = math.min(rawPoints, remainingAllowed)

        -- 2. Build atomic transaction
        local statements = {}

        if uniqueId and uniqueId ~= '' then
            statements[#statements + 1] = {
                query = [[
                    INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source)
                    VALUES (?, ?, 'financial_contribution', ?, 'bank_deposit')
                ]],
                values = { tostring(uniqueId), familyId, pointsToAward }
            }
        end

        -- Persistent daily tracking record (points capped, full money recorded)
        statements[#statements + 1] = {
            query = [[
                INSERT INTO cm_family_contribution_daily
                  (family_id, character_id, day_key, financial_points, money_contributed)
                VALUES (?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                  financial_points = financial_points + VALUES(financial_points),
                  money_contributed = money_contributed + VALUES(money_contributed)
            ]],
            values = { familyId, characterId, dayKey, pointsToAward, moneyAmount }
        }

        -- Overall member contribution record (points capped, full money recorded)
        statements[#statements + 1] = {
            query = [[
                INSERT INTO cm_family_member_contributions
                  (family_id, character_id, total_points, weekly_points, financial_points, money_contributed, last_contribution_at)
                VALUES (?, ?, ?, ?, ?, ?, NOW())
                ON DUPLICATE KEY UPDATE
                  total_points = total_points + VALUES(total_points),
                  weekly_points = weekly_points + VALUES(weekly_points),
                  financial_points = financial_points + VALUES(financial_points),
                  money_contributed = money_contributed + VALUES(money_contributed),
                  last_contribution_at = NOW()
            ]],
            values = { familyId, characterId, pointsToAward, pointsToAward, pointsToAward, moneyAmount }
        }

        -- Dedicated weekly contribution ledger
        statements[#statements + 1] = {
            query = [[
                INSERT INTO cm_family_contribution_weekly
                  (family_id, character_id, week_key, total_points, financial_points)
                VALUES (?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                  total_points = total_points + VALUES(total_points),
                  financial_points = financial_points + VALUES(financial_points)
            ]],
            values = { familyId, characterId, currentWeekKey, pointsToAward, pointsToAward }
        }

        local txCommitted = MySQL.transaction.await(statements)
        if txCommitted ~= true then
            return false, 'transaction_failed'
        end

        return true, pointsToAward
    end)

    releaseContributionLock(lockKey)

    if not execOk or resSuccess ~= true then
        return false, tostring(resPoints or 'financial_contribution_failed')
    end

    return true, resPoints
end
exports('RecordFinancialContribution', RecordFinancialContribution)

function GetFamilyContributionLeaderboard(familyId, scope)
    familyId = tonumber(familyId)
    if not familyId then return {} end

    scope = tostring(scope or 'this_week')
    local currentWeekKey = (type(CMFamilyGetWeekKey) == 'function' and CMFamilyGetWeekKey()) or os.date('%Y-W%W')

    local rows
    if scope == 'this_week' then
        rows = MySQL.query.await([[
            SELECT w.character_id, w.total_points AS weekly_points, w.activity_points,
                   w.financial_points, w.event_points,
                   c.total_points, c.money_contributed, c.last_contribution_at,
                   m.rank_id, m.custom_title, ch.first_name, ch.last_name
            FROM cm_family_contribution_weekly w
            LEFT JOIN cm_family_member_contributions c ON c.family_id = w.family_id AND c.character_id = w.character_id
            LEFT JOIN cm_family_members m ON m.family_id = w.family_id AND m.character_id = w.character_id
            LEFT JOIN characters ch ON ch.id = w.character_id
            WHERE w.family_id = ? AND w.week_key = ?
            ORDER BY w.total_points DESC, c.total_points DESC
            LIMIT 20
        ]], { familyId, currentWeekKey }) or {}
    else
        rows = MySQL.query.await([[
            SELECT c.character_id, c.total_points, c.weekly_points, c.activity_points,
                   c.financial_points, c.money_contributed, c.event_points, c.last_contribution_at,
                   m.rank_id, m.custom_title, ch.first_name, ch.last_name
            FROM cm_family_member_contributions c
            LEFT JOIN cm_family_members m ON m.family_id = c.family_id AND m.character_id = c.character_id
            LEFT JOIN characters ch ON ch.id = c.character_id
            WHERE c.family_id = ?
            ORDER BY c.total_points DESC
            LIMIT 20
        ]], { familyId }) or {}
    end

    local leaderboard = {}
    for index, r in ipairs(rows) do
        local name = B.GetCharName(r.character_id)
        local fam = GetFamilyById(familyId)
        local rank = (fam and fam.ranksById and fam.ranksById[tonumber(r.rank_id)]) or nil

        leaderboard[#leaderboard + 1] = {
            position = index,
            cid = r.character_id,
            name = name,
            rankName = rank and rank.name or 'Member',
            totalPoints = tonumber(r.total_points) or 0,
            weeklyPoints = tonumber(r.weekly_points) or 0,
            activityPoints = tonumber(r.activity_points) or 0,
            financialPoints = tonumber(r.financial_points) or 0,
            moneyContributed = tonumber(r.money_contributed) or 0,
            eventPoints = tonumber(r.event_points) or 0,
            lastContributionAt = r.last_contribution_at,
        }
    end

    return leaderboard
end
exports('GetFamilyContributionLeaderboard', GetFamilyContributionLeaderboard)
