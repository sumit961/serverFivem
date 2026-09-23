-- ============================================================
-- cm-family | sv_objectives.lua | v1.8.0
-- Authoritative weekly family objectives & anti-abuse progression tracking.
-- All objective progress is evaluated strictly server-side.
-- ============================================================

local B = CMFamilyBridge

local function getCurrentWeekKey()
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

    local weekKey = getCurrentWeekKey()
    local weekNum = tonumber(os.date('%W')) or 1
    local yearNum = tonumber(os.date('%Y')) or 2026
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

function GetFamilyWeeklyObjectives(familyId)
    familyId = tonumber(familyId)
    if not familyId then return {} end

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
    -- 1. unique_active_members: count online members or members active this week
    -- 2. member_count: total roster size
    -- 3. fleet_vehicles: vehicles stored in family garage
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
                -- Mark completed in DB and award rewards
                CompleteObjective(familyId, obj, weekKey, val)
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

function CompleteObjective(familyId, obj, weekKey, finalValue)
    familyId = tonumber(familyId)
    weekKey = weekKey or getCurrentWeekKey()

    -- Atomic check-and-claim to prevent race conditions or duplicate awards
    local claimed = false
    pcall(function()
        local affected = MySQL.update.await([[
            UPDATE cm_family_objective_progress
            SET current_value = ?, completed = 1, completed_at = COALESCE(completed_at, NOW()), reward_claimed = 1
            WHERE family_id = ? AND objective_key = ? AND week_key = ? AND reward_claimed = 0
        ]], { finalValue or obj.targetValue, familyId, obj.key, weekKey })

        if affected and affected > 0 then
            claimed = true
        else
            -- Try inserting if row does not exist yet (with reward_claimed = 1)
            local ins = MySQL.insert.await([[
                INSERT INTO cm_family_objective_progress
                  (family_id, objective_key, week_key, current_value, completed, completed_at, reward_claimed)
                VALUES (?, ?, ?, ?, 1, NOW(), 1)
                ON DUPLICATE KEY UPDATE
                  completed = 1,
                  completed_at = COALESCE(completed_at, NOW())
            ]], { familyId, obj.key, weekKey, finalValue or obj.targetValue })
            if ins and ins > 0 then
                claimed = true
            end
        end
    end)

    if not claimed then
        return false, 'already_completed'
    end

    -- Award family rewards
    local uniqueRewardId = ('obj:%s:%s:%s'):format(familyId, weekKey, obj.key)

    if (obj.rewardReputation or 0) > 0 and type(AddFamilyReputation) == 'function' then
        AddFamilyReputation(familyId, obj.rewardReputation, 'objective', uniqueRewardId, {
            objectiveKey = obj.key,
            title = obj.title,
        })
    end

    if (obj.rewardTreasury or 0) > 0 then
        local maxBal = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
        pcall(function()
            MySQL.update.await([[
                UPDATE cm_families
                SET bank_balance = LEAST(bank_balance + ?, ?)
                WHERE id = ?
            ]], { obj.rewardTreasury, maxBal, familyId })

            local fam = GetFamilyById(familyId)
            local newBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId })) or 0
            if fam then fam.bank_balance = newBal end

            MySQL.insert.await([[
                INSERT INTO cm_family_bank_log (family_id, direction, category, amount, balance_after, reason)
                VALUES (?, 'deposit', 'event_reward', ?, ?, ?)
            ]], { familyId, obj.rewardTreasury, newBal, ('objective_reward:%s'):format(obj.key) })
        end)
    end

    -- Notify online members
    for cid, mem in pairs(MemberByCid) do
        if tonumber(mem.family_id) == familyId then
            local src = B.GetSrcByCid(cid)
            if src then
                B.Notify(src, ('Objective completed: %s!'):format(obj.title), 'success')
            end
        end
    end

    LogFamily(familyId, nil, 'family_objective_completed', {
        objectiveKey = obj.key,
        title = obj.title,
        weekKey = weekKey,
        reputation = obj.rewardReputation,
        treasury = obj.rewardTreasury,
    }, { severity = 'info' })
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
                CompleteObjective(familyId, obj, weekKey, tonumber(row.current_value))
            end
        end
    end

    return true
end
exports('AdvanceFamilyObjective', AdvanceFamilyObjective)

