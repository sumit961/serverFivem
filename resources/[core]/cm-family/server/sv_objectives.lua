-- ============================================================
-- cm-family | sv_objectives.lua | v1.8.0
-- Authoritative weekly family objectives & anti-abuse progression tracking.
-- All objective progress is evaluated strictly server-side.
-- ============================================================

local B = CMFamilyBridge

local function getCurrentWeekKey()
    if type(CMFamilyGetWeekKey) == 'function' then
        return CMFamilyGetWeekKey()
    end
    return os.date('%Y-W%W')
end

local function getObjectivePool()
    return (Config.Objectives and Config.Objectives.pool) or {}
end

-- Deterministically selects weekly objectives for a family so every member sees
-- identical objectives throughout the week without requiring constant DB synchronization.
local function getWeeklyObjectivesForFamily(familyId)
    local pool = getObjectivePool()
    if #pool == 0 then return {} end

    local weekKey, yearNum, weekNum
    if type(CMFamilyGetWeekKey) == 'function' then
        weekKey, yearNum, weekNum = CMFamilyGetWeekKey()
    else
        weekKey = os.date('%Y-W%W')
        yearNum = tonumber(os.date('%Y')) or 2026
        weekNum = tonumber(os.date('%W')) or 1
    end
    yearNum = tonumber(yearNum) or 2026
    weekNum = tonumber(weekNum) or 1
    local seed = (tonumber(familyId) * 17) + (yearNum * 53) + weekNum

    local selected = {}
    local usedIndices = {}
    local needed = math.min(tonumber(Config.Objectives and Config.Objectives.rotationCount) or 3, #pool)

    for i = 1, needed do
        local pickIndex = ((seed + (i * 7)) % #pool) + 1
        while usedIndices[pickIndex] do
            pickIndex = (pickIndex % #pool) + 1
        end
        usedIndices[pickIndex] = true
        selected[#selected + 1] = pool[pickIndex]
    end

    return selected, weekKey
end
CMFamilyGetWeeklyObjectivesForFamily = getWeeklyObjectivesForFamily

-- Crash recovery for stuck processing objectives
function RecoverStaleObjectiveProcessing(targetFamilyId)
    local query
    local params
    if targetFamilyId then
        query = [[
            SELECT id, family_id, objective_key, week_key, reward_state, reward_processing_at
            FROM cm_family_objective_progress
            WHERE family_id = ? AND reward_state = 'processing'
              AND (reward_processing_at IS NULL OR reward_processing_at < NOW() - INTERVAL 1 MINUTE)
        ]]
        params = { tonumber(targetFamilyId) }
    else
        query = [[
            SELECT id, family_id, objective_key, week_key, reward_state, reward_processing_at
            FROM cm_family_objective_progress
            WHERE reward_state = 'processing'
              AND (reward_processing_at IS NULL OR reward_processing_at < NOW() - INTERVAL 1 MINUTE)
        ]]
        params = {}
    end

    local rows = MySQL.query.await(query, params) or {}
    local recoveredCount = 0

    for _, r in ipairs(rows) do
        local rootUniqueId = ('obj:%s:%s:%s'):format(r.family_id, r.week_key, r.objective_key)
        local rootExists = MySQL.scalar.await([[
            SELECT 1 FROM cm_family_reward_history WHERE unique_id = ? LIMIT 1
        ]], { rootUniqueId })

        if rootExists then
            MySQL.update.await([[
                UPDATE cm_family_objective_progress
                SET reward_state = 'delivered', reward_claimed = 1
                WHERE id = ?
            ]], { r.id })
        else
            MySQL.update.await([[
                UPDATE cm_family_objective_progress
                SET reward_state = 'failed'
                WHERE id = ?
            ]], { r.id })
        end
        recoveredCount = recoveredCount + 1
    end

    return recoveredCount
end
exports('RecoverStaleObjectiveProcessing', RecoverStaleObjectiveProcessing)

function GetFamilyWeeklyObjectives(familyId)
    familyId = tonumber(familyId)
    if not familyId then return {} end

    -- Recover any stuck processing objectives before loading
    pcall(function() RecoverStaleObjectiveProcessing(familyId) end)

    local objectives, weekKey = getWeeklyObjectivesForFamily(familyId)
    if #objectives == 0 then return {} end

    local keys = {}
    for _, obj in ipairs(objectives) do keys[#keys + 1] = obj.key end

    local placeholders = table.concat(table.pack(table.unpack((function()
        local t = {}
        for _ in ipairs(keys) do t[#t + 1] = '?' end
        return t
    end)())), ', ')

    local params = { familyId, weekKey }
    for _, k in ipairs(keys) do params[#params + 1] = k end

    local progressRows = MySQL.query.await(([[
        SELECT objective_key, current_value, completed, completed_at
        FROM cm_family_objective_progress
        WHERE family_id = ? AND week_key = ? AND objective_key IN (%s)
    ]]):format(placeholders), params) or {}

    local progressMap = {}
    for _, row in ipairs(progressRows) do
        progressMap[row.objective_key] = row
    end

    -- Special real-time evaluations:
    local result = {}
    for _, obj in ipairs(objectives) do
        local prog = progressMap[obj.key]
        local val = prog and tonumber(prog.current_value) or 0
        local completed = prog and tonumber(prog.completed) == 1 or false

        if not completed then
            if obj.targetType == 'unique_active_members' then
                local activeOnline = 0
                for cid, mem in pairs(MemberByCid) do
                    if tonumber(mem.family_id) == familyId and B.GetSrcByCid(cid) then
                        activeOnline = activeOnline + 1
                    end
                end
                val = math.max(val, activeOnline)
            elseif obj.targetType == 'member_count' then
                local totalMembers = 0
                for _, mem in pairs(MemberByCid) do
                    if tonumber(mem.family_id) == familyId then totalMembers = totalMembers + 1 end
                end
                val = totalMembers
            elseif obj.targetType == 'fleet_vehicles' then
                local vehicles = B.GetFamilyVehicles(familyId)
                val = #vehicles
            end

            if val >= obj.targetValue and not completed then
                completed = true
                -- Mark completed in DB and award rewards (no actor cid available for real-time stat evaluations)
                CompleteObjective(familyId, obj, weekKey, val, nil)
            end
        end

        local pct = math.min(100, math.max(0, math.floor((val / math.max(1, obj.targetValue)) * 100)))

        result[#result + 1] = {
            key = obj.key,
            title = obj.title,
            description = obj.description,
            targetType = obj.targetType,
            targetValue = obj.targetValue,
            currentValue = val,
            percent = pct,
            completed = completed,
            rewardReputation = obj.rewardReputation,
            rewardContribution = obj.rewardContribution,
            rewardTreasury = obj.rewardTreasury,
            weekKey = weekKey,
        }
    end

    return result
end
exports('GetFamilyWeeklyObjectives', GetFamilyWeeklyObjectives)

function CompleteObjective(familyId, obj, weekKey, finalValue, actorCid)
    familyId = tonumber(familyId)
    weekKey = weekKey or getCurrentWeekKey()
    actorCid = actorCid and tostring(actorCid) or nil

    -- 1. Atomically reserve completion and transition reward_state to 'processing'
    -- Only transitions from 'unclaimed' or 'failed' to prevent duplicate execution
    local reserved = false
    pcall(function()
        local affected = MySQL.update.await([[
            UPDATE cm_family_objective_progress
            SET current_value = ?, completed = 1, completed_at = COALESCE(completed_at, NOW()),
                reward_state = 'processing', reward_processing_at = NOW()
            WHERE family_id = ? AND objective_key = ? AND week_key = ? AND (reward_state = 'unclaimed' OR reward_state = 'failed')
        ]], { finalValue or obj.targetValue, familyId, obj.key, weekKey })

        if affected and affected > 0 then
            reserved = true
        else
            -- If row does not exist yet, attempt insert with reward_state = 'processing'
            local ins = MySQL.insert.await([[
                INSERT INTO cm_family_objective_progress
                  (family_id, objective_key, week_key, current_value, completed, completed_at, reward_claimed, reward_state, reward_processing_at)
                VALUES (?, ?, ?, ?, 1, NOW(), 0, 'processing', NOW())
                ON DUPLICATE KEY UPDATE
                  completed = 1,
                  completed_at = COALESCE(completed_at, NOW())
            ]], { familyId, obj.key, weekKey, finalValue or obj.targetValue })
            if ins and ins > 0 then
                reserved = true
            end
        end
    end)

    if not reserved then
        return false, 'already_completed_or_processing'
    end

    -- 2. Execute root idempotent activity reward operation
    -- Requirement 8: The completing actor receives configured rewardContribution
    local contribReward = math.max(0, math.floor(tonumber(obj.rewardContribution) or 0))
    local participants = (actorCid and actorCid ~= '' and contribReward > 0) and { actorCid } or {}
    local awardedContribution = (actorCid and actorCid ~= '') and contribReward or 0

    local uniqueRewardId = ('obj:%s:%s:%s'):format(familyId, weekKey, obj.key)
    local okReward, rewardErr = AwardFamilyActivityReward({
        familyId = familyId,
        uniqueId = uniqueRewardId,
        eventType = 'weekly_objective',
        reputation = obj.rewardReputation or 0,
        treasuryAmount = obj.rewardTreasury or 0,
        memberContribution = awardedContribution,
        actorCid = actorCid,
        participants = participants,
        metadata = {
            objectiveKey = obj.key,
            title = obj.title,
            weekKey = weekKey,
            completedBy = actorCid,
        }
    })

    -- 3. Confirm delivery state
    if okReward then
        MySQL.update.await([[
            UPDATE cm_family_objective_progress
            SET reward_state = 'delivered', reward_claimed = 1
            WHERE family_id = ? AND objective_key = ? AND week_key = ?
        ]], { familyId, obj.key, weekKey })

        -- Notify online members
        for cid, mem in pairs(MemberByCid) do
            if tonumber(mem.family_id) == familyId then
                local src = B.GetSrcByCid(cid)
                if src then
                    B.Notify(src, ('Objective completed: %s! Rewards delivered to family.'):format(obj.title), 'success')
                end
            end
        end
    else
        -- Mark failed so the system or retry can safely re-attempt
        MySQL.update.await([[
            UPDATE cm_family_objective_progress
            SET reward_state = 'failed'
            WHERE family_id = ? AND objective_key = ? AND week_key = ? AND reward_claimed = 0
        ]], { familyId, obj.key, weekKey })
        return false, tostring(rewardErr or 'reward_delivery_failed')
    end

    LogFamily(familyId, actorCid, 'family_objective_completed', {
        objectiveKey = obj.key,
        title = obj.title,
        weekKey = weekKey,
        reputation = obj.rewardReputation,
        treasury = obj.rewardTreasury,
        awardedContribution = awardedContribution,
        completedBy = actorCid,
    }, { severity = 'info' })

    return true
end

function AdvanceFamilyObjective(familyId, objectiveType, count, characterId)
    familyId = tonumber(familyId)
    count = math.max(0, math.floor(tonumber(count) or 1))
    if not familyId or count <= 0 then return false end

    local objectives, weekKey = getWeeklyObjectivesForFamily(familyId)
    if #objectives == 0 then return false end

    for _, obj in ipairs(objectives) do
        if obj.targetType == objectiveType then
            pcall(function()
                MySQL.query.await([[
                    INSERT INTO cm_family_objective_progress
                      (family_id, objective_key, week_key, current_value, completed)
                    VALUES (?, ?, ?, ?, 0)
                    ON DUPLICATE KEY UPDATE
                      current_value = current_value + VALUES(current_value)
                ]], { familyId, obj.key, weekKey, count })
            end)

            -- Check if this completes the objective
            local row = MySQL.single.await([[
                SELECT current_value, completed
                FROM cm_family_objective_progress
                WHERE family_id = ? AND objective_key = ? AND week_key = ?
                LIMIT 1
            ]], { familyId, obj.key, weekKey })

            if row and tonumber(row.completed) ~= 1 and (tonumber(row.current_value) or 0) >= obj.targetValue then
                CompleteObjective(familyId, obj, weekKey, tonumber(row.current_value), characterId)
            end
        end
    end

    return true
end
exports('AdvanceFamilyObjective', AdvanceFamilyObjective)

-- Startup background check to recover stale processing rows
CreateThread(function()
    Wait(5000)
    pcall(function()
        RecoverStaleObjectiveProcessing()
    end)
end)

