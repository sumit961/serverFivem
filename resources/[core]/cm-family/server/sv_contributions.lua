-- ============================================================
-- cm-family | sv_contributions.lua | v1.8.0
-- Authoritative family member contribution score and leaderboards.
-- Separates merit-based contribution points from raw money deposited.
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

function AddFamilyMemberContribution(characterId, familyId, amount, category, source, uniqueId)
    characterId = tostring(characterId)
    familyId = tonumber(familyId)
    amount = math.floor(tonumber(amount) or 0)
    category = tostring(category or 'activity'):lower()
    source = tostring(source or 'system')

    if not characterId or not familyId or amount <= 0 then
        return false, 'invalid_arguments'
    end

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

    local ok = pcall(function()
        MySQL.query.await([[
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
        ]], { familyId, characterId, amount, amount, actAdd, finAdd, eventAdd })

        if uniqueId and uniqueId ~= '' then
            MySQL.insert.await([[
                INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source)
                VALUES (?, ?, 'contribution', ?, ?)
            ]], { uniqueId, familyId, amount, source })
        end
    end)

    if not ok then
        return false, 'database_error'
    end

    return true, amount
end
exports('AddFamilyMemberContribution', AddFamilyMemberContribution)

-- Safe financial contribution recorder: tracks cash deposited, but strictly
-- limits points so wealthy players do not completely distort contribution scores
function RecordFinancialContribution(characterId, familyId, moneyAmount)
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
    local pointsToAward = math.min(rawPoints, maxDaily)

    pcall(function()
        MySQL.query.await([[
            INSERT INTO cm_family_member_contributions
              (family_id, character_id, total_points, weekly_points, financial_points, money_contributed, last_contribution_at)
            VALUES (?, ?, ?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE
              total_points = total_points + VALUES(total_points),
              weekly_points = weekly_points + VALUES(weekly_points),
              financial_points = financial_points + VALUES(financial_points),
              money_contributed = money_contributed + VALUES(money_contributed),
              last_contribution_at = NOW()
        ]], { familyId, characterId, pointsToAward, pointsToAward, pointsToAward, moneyAmount })
    end)

    return true, pointsToAward
end
exports('RecordFinancialContribution', RecordFinancialContribution)

function GetFamilyContributionLeaderboard(familyId, scope)
    familyId = tonumber(familyId)
    if not familyId then return {} end

    scope = tostring(scope or 'this_week')
    local orderBy = (scope == 'all_time') and 'total_points' or 'weekly_points'

    local rows = MySQL.query.await(([[
        SELECT c.character_id, c.total_points, c.weekly_points, c.activity_points,
               c.financial_points, c.money_contributed, c.event_points, c.last_contribution_at,
               m.rank_id, m.custom_title, ch.first_name, ch.last_name
        FROM cm_family_member_contributions c
        LEFT JOIN cm_family_members m ON m.family_id = c.family_id AND m.character_id = c.character_id
        LEFT JOIN characters ch ON ch.id = c.character_id
        WHERE c.family_id = ?
        ORDER BY c.%s DESC, c.total_points DESC
        LIMIT 20
    ]]):format(orderBy), { familyId }) or {}

    local leaderboard = {}
    for index, r in ipairs(rows) do
        local name = B.GetCharName(r.character_id)
        local member = GetMembership(r.character_id)
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

