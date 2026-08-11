-- Lightweight daily/weekly EMS employee tasks.

local function periodKey(period)
    if period == 'weekly' then return os.date('%Y-W%W') end
    return os.date('%Y-%m-%d')
end

local function taskNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function definitions(period)
    local configured = (Config.EmployeeTasks or {})[period]
    return type(configured) == 'table' and configured or {}
end

local function eligible(member, task)
    return not task.permission or has(member, tostring(task.permission))
end

local onlineSource

local function progressionLevel(xp)
    xp = math.max(0, math.floor(tonumber(xp) or 0))
    local levels = ((Config.EmployeeProgression or {}).levels) or {}
    local current = { level = 1, xp = 0, label = 'EMS Responder' }
    local nextLevel
    for _, entry in ipairs(levels) do
        local required = math.max(0, math.floor(tonumber(entry.xp) or 0))
        if xp >= required and required >= (tonumber(current.xp) or 0) then
            current = { level = tonumber(entry.level) or 1, xp = required, label = tostring(entry.label or 'EMS Responder') }
        elseif required > xp and (not nextLevel or required < nextLevel.xp) then
            nextLevel = { level = tonumber(entry.level) or current.level + 1, xp = required, label = tostring(entry.label or 'EMS Responder') }
        end
    end
    return current, nextLevel
end

local function progressionPayload(characterId)
    local xp = tonumber(MySQL.scalar.await('SELECT xp FROM cm_ems_employee_progress WHERE character_id = ? LIMIT 1', { tostring(characterId) })) or 0
    local current, nextLevel = progressionLevel(xp)
    return {
        xp = xp, level = current.level, label = current.label,
        levelStartXp = current.xp, nextLevelXp = nextLevel and nextLevel.xp or current.xp,
        nextLevelLabel = nextLevel and nextLevel.label or nil,
        maxLevel = nextLevel == nil,
    }
end

local function awardEmployeeXp(characterId, award)
    award = math.max(0, math.floor(tonumber(award) or 0))
    if award <= 0 then return end
    local before = progressionPayload(characterId)
    MySQL.insert.await([[INSERT INTO cm_ems_employee_progress (character_id, xp) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp)]], { tostring(characterId), award })
    local after = progressionPayload(characterId)
    local src = onlineSource(characterId)
    if src then
        taskNotify(src, ('EMS XP +%d · %s'):format(award, after.label), 'success')
        if tonumber(after.level) > tonumber(before.level) then
            taskNotify(src, ('Career level unlocked: Level %d — %s'):format(after.level, after.label), 'success')
        end
    end
end

local function addEmployeeXp(characterId, metric, amount)
    local perAction = tonumber((((Config.EmployeeProgression or {}).xpByMetric) or {})[metric]) or 0
    awardEmployeeXp(characterId, perAction * math.max(1, tonumber(amount) or 1))
end

function EMSAwardEmployeeXP(characterId, award)
    characterId = tostring(characterId or '')
    local member = characterId ~= '' and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) then return false end
    awardEmployeeXp(characterId, award)
    return true
end

onlineSource = function(characterId)
    local ok, value = pcall(function()
        return exports[Config.PlayerDataResource]:GetSourceByCharId(characterId)
    end)
    return ok and tonumber(value) or nil
end

local function taskPayload(characterId, member)
    local keys = { daily = periodKey('daily'), weekly = periodKey('weekly') }
    local rows = MySQL.query.await([[SELECT period_type, period_key, task_id, progress, claimed
        FROM cm_ems_task_progress WHERE character_id = ?
        AND ((period_type = 'daily' AND period_key = ?) OR (period_type = 'weekly' AND period_key = ?))]],
        { tostring(characterId), keys.daily, keys.weekly }) or {}
    local progress = {}
    for _, row in ipairs(rows) do
        progress[('%s:%s'):format(row.period_type, row.task_id)] = {
            progress = tonumber(row.progress) or 0, claimed = dbBoolean(row.claimed),
        }
    end
    local payload = { daily = {}, weekly = {}, dailyKey = keys.daily, weeklyKey = keys.weekly,
        progression = progressionPayload(characterId) }
    for _, period in ipairs({ 'daily', 'weekly' }) do
        for _, task in ipairs(definitions(period)) do
            if eligible(member, task) then
                local current = progress[('%s:%s'):format(period, tostring(task.id))] or { progress = 0, claimed = false }
                local target = math.max(1, math.floor(tonumber(task.target) or 1))
                payload[period][#payload[period] + 1] = {
                    id = tostring(task.id), metric = tostring(task.metric), label = tostring(task.label or task.id),
                    description = tostring(task.description or ''), target = target,
                    progress = math.min(target, math.max(0, current.progress)), reward = math.max(0, math.floor(tonumber(task.reward) or 0)),
                    completed = current.progress >= target, claimed = current.claimed,
                }
            end
        end
    end
    return payload
end

local function findTask(period, taskId, member)
    for _, task in ipairs(definitions(period)) do
        if tostring(task.id) == tostring(taskId) and eligible(member, task) then return task end
    end
end

function EMSAddTaskProgress(characterId, metric, amount, uniqueKey)
    characterId, metric = tostring(characterId or ''), tostring(metric or '')
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local member = characterId ~= '' and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or metric == '' then return false end

    if uniqueKey then
        local eventKey = ('%s:%s:%s'):format(characterId, metric, tostring(uniqueKey)):sub(1, 160)
        local inserted = MySQL.update.await('INSERT IGNORE INTO cm_ems_task_events (event_key, character_id, metric) VALUES (?, ?, ?)',
            { eventKey, characterId, metric })
        if not inserted or tonumber(inserted) == 0 then return false end
    end

    local completed = {}
    for _, period in ipairs({ 'daily', 'weekly' }) do
        local key = periodKey(period)
        for _, task in ipairs(definitions(period)) do
            if tostring(task.metric) == metric and eligible(member, task) then
                local previous = tonumber(MySQL.scalar.await([[SELECT progress FROM cm_ems_task_progress
                    WHERE character_id = ? AND period_type = ? AND period_key = ? AND task_id = ? LIMIT 1]],
                    { characterId, period, key, tostring(task.id) })) or 0
                MySQL.insert.await([[INSERT INTO cm_ems_task_progress
                    (character_id, period_type, period_key, task_id, progress, claimed) VALUES (?, ?, ?, ?, ?, 0)
                    ON DUPLICATE KEY UPDATE progress = progress + VALUES(progress)]],
                    { characterId, period, key, tostring(task.id), amount })
                local target = math.max(1, math.floor(tonumber(task.target) or 1))
                if previous < target and previous + amount >= target then completed[#completed + 1] = tostring(task.label or task.id) end
            end
        end
    end
    addEmployeeXp(characterId, metric, amount)
    local src = onlineSource(characterId)
    for _, label in ipairs(completed) do
        if src then taskNotify(src, ('Task complete: %s. Open EMS Tasks to claim your reward.'):format(label), 'success') end
    end
    return true
end

lib.callback.register('cm-ems:server:employeeTasks', function(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) then return nil, 'You are not an active EMS employee.' end
    return taskPayload(characterId, member)
end)

lib.callback.register('cm-ems:server:claimEmployeeTask', function(src, period, taskId)
    if not rateLimit(src, 'claim_employee_task', 700) then return false, 'Please wait.' end
    period = period == 'weekly' and 'weekly' or period == 'daily' and 'daily' or nil
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not period or not member or dbBoolean(member.is_suspended) then return false, 'Task is unavailable.' end
    local task = findTask(period, taskId, member)
    if not task then return false, 'Task is unavailable for your rank.' end
    local target = math.max(1, math.floor(tonumber(task.target) or 1))
    local changed = MySQL.update.await([[UPDATE cm_ems_task_progress SET claimed = 1
        WHERE character_id = ? AND period_type = ? AND period_key = ? AND task_id = ?
        AND progress >= ? AND claimed = 0]],
        { characterId, period, periodKey(period), tostring(task.id), target })
    if not changed or tonumber(changed) == 0 then return false, 'Complete this task first, or its reward was already claimed.' end
    local reward = math.max(0, math.floor(tonumber(task.reward) or 0))
    local paid = reward == 0
    if reward > 0 then
        pcall(function() paid = exports[Config.PlayerDataResource]:AddMoney(src, 'bank', reward, 'ems_employee_task') == true end)
    end
    if not paid then
        MySQL.update.await([[UPDATE cm_ems_task_progress SET claimed = 0 WHERE character_id = ?
            AND period_type = ? AND period_key = ? AND task_id = ?]],
            { characterId, period, periodKey(period), tostring(task.id) })
        return false, 'Reward payment failed safely. Try again.'
    end
    log(characterId, 'employee_task_claimed', { period = period, taskId = task.id, reward = reward })
    return true, ('Task reward claimed: $%d deposited to your bank.'):format(reward), taskPayload(characterId, member)
end)

-- Count real connected on-duty time. One loop equals one minute; reconnecting
-- or toggling duty cannot award more than actual elapsed server time.
CreateThread(function()
    while true do
        Wait(60000)
        for _, rawSrc in ipairs(GetPlayers()) do
            local characterId = cid(tonumber(rawSrc))
            if characterId then EMSAddTaskProgress(characterId, 'duty_minutes', 1) end
        end
    end
end)

-- G-menu medikit treatment completed through cm-playerdata.
AddEventHandler('cm-playerdata:server:treatCompleted', function(medicSrc, patientSrc, result)
    result = type(result) == 'table' and result or {}
    if result.revived ~= true then return end
    local medicCid = cid(tonumber(medicSrc))
    local patientCid = tostring(result.targetCharacterId or cid(tonumber(patientSrc)) or '')
    local deathCount = 0
    pcall(function()
        local info = exports[Config.PlayerDataResource]:GetDeathInfo(tonumber(patientSrc))
        deathCount = tonumber(info and info.deathCount) or 0
    end)
    if medicCid and patientCid ~= '' then
        EMSAddTaskProgress(medicCid, 'patient_revives', 1, ('patient:%s:death:%d'):format(patientCid, deathCount))
        pcall(function() exports['cm-ems']:AwardMedicReward(tonumber(medicSrc), tonumber(patientSrc), 'ems_treatment_reward') end)
    end
end)

CreateThread(function()
    while true do
        Wait(21600000)
        MySQL.update.await('DELETE FROM cm_ems_task_events WHERE created_at < DATE_SUB(NOW(), INTERVAL 120 DAY)')
        MySQL.update.await('DELETE FROM cm_ems_task_progress WHERE updated_at < DATE_SUB(NOW(), INTERVAL 120 DAY)')
    end
end)
