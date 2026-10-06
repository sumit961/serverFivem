local Config = CMPayday.Config
local PLAYERDATA = 'cm-playerdata'

-- pending[src] = { charId = string, data = { cash, xp, payout } }
-- The source is only an online cache key. Persistent metadata is always read
-- while that source has the matching active character loaded.
local pending = {}
local sessions = {}
local payoutLocks = {}
local payoutSequence = 0

local function dbg(...)
    if Config.Debug then print('[CM-PAYDAY]', ...) end
end

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

local function activeCharacterId(src)
    src = tonumber(src)
    local api = playerData()
    if not src or not api then return nil end
    local ok, charId = pcall(function() return api:GetCharacterId(src) end)
    if not ok or not charId or tostring(charId) == '' then return nil end
    return tostring(charId)
end

local function normalizeJob(jobName)
    jobName = tostring(jobName or ''):lower()
    if not Config.Jobs[jobName] then return nil end
    return jobName
end

local function normalizeAmount(raw, maximum)
    local amount = tonumber(raw)
    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then return nil end
    amount = math.floor(amount)
    if amount <= 0 or amount > maximum then return nil end
    return amount
end

local function decodeTable(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    return ok and type(decoded) == 'table' and decoded or {}
end

local function copyXp(xp)
    local copy = {}
    for jobName, amount in pairs(type(xp) == 'table' and xp or {}) do
        copy[jobName] = amount
    end
    return copy
end

local function getMeta(src, key, default)
    local api = playerData()
    if not api then return default end
    local ok, value = pcall(function() return api:GetMetadata(src, key) end)
    if ok and value ~= nil then return value end
    return default
end

local function setMeta(src, key, value)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:SetMetadata(src, key, value) end)
    return ok and result == true
end

local function saveCharacter(src, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:Save(src, reason or 'cm-payday') end)
    return ok and result == true
end

local function notify(src, message, kind)
    if GetResourceState('cm-hud') ~= 'started' then return end
    pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
end

local function auditPayout(src, charId, cashAmount, account, cashByJob, xpResults)
    if GetResourceState('cm-admin') ~= 'started' then return end
    pcall(function()
        TriggerEvent('cm-admin:server:addLog', src, 'cm_payday_payout', {
            category = 'payday',
            detail = {
                characterId = charId,
                source = src,
                cashAmount = cashAmount or 0,
                payoutAccount = account,
                cashByJob = cashByJob or {},
                xp = xpResults or {},
            }
        })
    end)
end

-- ---------------------------------------------------------------------------
-- Pending pay/xp -- persisted to cm-playerdata metadata on every change so a
-- disconnect or server restart before the next payday never loses earnings.
-- ---------------------------------------------------------------------------

local function loadPending(src)
    src = tonumber(src)
    local charId = activeCharacterId(src)
    if not src or not charId then return nil, 'character_not_loaded' end

    local cached = pending[src]
    if cached and cached.charId == charId then return cached.data end
    pending[src] = nil

    local cash = math.max(0, math.floor(tonumber(getMeta(src, 'cmPaydayPendingCash', 0)) or 0))
    local cashByJob = copyXp(decodeTable(getMeta(src, 'cmPaydayPendingCashByJob', nil)))
    local xp = {}
    local raw = getMeta(src, 'cmPaydayPendingXp', nil)
    xp = decodeTable(raw)
    local payout = getMeta(src, 'cmPaydayPayout', nil)
    payout = type(payout) == 'table' and payout or decodeTable(payout)
    if next(payout) == nil then payout = nil end

    local data = { cash = cash, cashByJob = cashByJob, xp = xp, payout = payout }
    pending[src] = { charId = charId, data = data }
    return data
end

local function pendingMetadataSnapshot(src)
    return {
        cash = getMeta(src, 'cmPaydayPendingCash', nil),
        cashByJob = getMeta(src, 'cmPaydayPendingCashByJob', nil),
        xp = getMeta(src, 'cmPaydayPendingXp', nil),
        payout = getMeta(src, 'cmPaydayPayout', nil),
    }
end

local function restorePendingMetadata(src, snapshot)
    if type(snapshot) ~= 'table' then return end
    setMeta(src, 'cmPaydayPendingCash', snapshot.cash)
    setMeta(src, 'cmPaydayPendingCashByJob', snapshot.cashByJob)
    setMeta(src, 'cmPaydayPendingXp', snapshot.xp)
    setMeta(src, 'cmPaydayPayout', snapshot.payout)
end

local function savePending(src)
    src = tonumber(src)
    local entry = src and pending[src]
    local currentCharId = activeCharacterId(src)
    if not entry or not currentCharId or currentCharId ~= entry.charId then
        return false, 'character_changed'
    end

    local data = entry.data
    local snapshot = pendingMetadataSnapshot(src)
    local function fail(reason)
        restorePendingMetadata(src, snapshot)
        return false, reason
    end

    -- Order matters: cash is persisted before the payout marker is cleared.
    -- If a later metadata write fails, the marker remains recoverable.
    if not setMeta(src, 'cmPaydayPendingCash', math.floor(data.cash)) then
        return fail('cash_persist_failed')
    end
    if not setMeta(src, 'cmPaydayPendingCashByJob', json.encode(data.cashByJob)) then
        return fail('cash_attribution_persist_failed')
    end
    if not setMeta(src, 'cmPaydayPendingXp', json.encode(data.xp)) then
        return fail('xp_persist_failed')
    end
    if not setMeta(src, 'cmPaydayPayout', data.payout) then
        return fail('payout_state_persist_failed')
    end
    if not saveCharacter(src, 'cm-payday-pending') then
        return fail('character_persist_failed')
    end
    return true
end

local function addPendingCash(src, jobName, amount, reason)
    src = tonumber(src)
    jobName = normalizeJob(jobName)
    amount = normalizeAmount(amount, tonumber(Config.MaxPendingCash) or 1000000000)
    if not src then return false, 'invalid_source' end
    if not jobName then return false, 'unknown_job' end
    if not amount then return false, 'invalid_amount' end

    local data, loadError = loadPending(src)
    if not data then return false, loadError end
    local previous = data.cash
    local previousByJob = copyXp(data.cashByJob)
    data.cash = data.cash + amount
    data.cashByJob[jobName] = (data.cashByJob[jobName] or 0) + amount
    if data.cash > (tonumber(Config.MaxPendingCash) or 1000000000) then
        data.cash = previous
        data.cashByJob = previousByJob
        return false, 'pending_cash_limit'
    end
    local saved, saveError = savePending(src)
    if not saved then
        data.cash = previous
        data.cashByJob = previousByJob
        return false, saveError
    end

    local jobConfig = Config.Jobs[jobName]
    notify(src, ('%s: +$%d held for payday'):format(jobConfig.label, amount), 'info')
    dbg(('pending +$%d for %s (job=%s reason=%s)'):format(amount, src, tostring(jobName), tostring(reason)))
    return true
end

local function addPendingXp(src, jobName, amount)
    src = tonumber(src)
    jobName = normalizeJob(jobName)
    amount = normalizeAmount(amount, tonumber(Config.MaxPendingXp) or 1000000)
    if not src then return false, 'invalid_source' end
    if not jobName then return false, 'unknown_job' end
    if Config.Jobs[jobName].xp ~= true then return false, 'xp_not_supported' end
    if not amount then return false, 'invalid_amount' end

    local data, loadError = loadPending(src)
    if not data then return false, loadError end
    local previous = data.xp[jobName] or 0
    if previous + amount > (tonumber(Config.MaxPendingXp) or 1000000) then
        return false, 'pending_xp_limit'
    end
    data.xp[jobName] = (data.xp[jobName] or 0) + amount
    local saved, saveError = savePending(src)
    if not saved then
        data.xp[jobName] = previous > 0 and previous or nil
        return false, saveError
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Playtime -- accumulated in real seconds, persisted incrementally so a
-- crash or ungraceful restart only ever loses the current flush window.
-- ---------------------------------------------------------------------------

local function flushPlaytime(src)
    local session = sessions[src]
    if not session then return end
    if activeCharacterId(src) ~= session.charId then
        dbg(('skipping playtime flush for stale source cache src=%s char=%s'):format(src, session.charId))
        return false, 'character_changed'
    end
    local elapsed = os.time() - session.joinedAt
    if elapsed <= 0 then return end
    local base = math.max(0, math.floor(tonumber(getMeta(src, 'cmPaydayPlaytimeSeconds', 0)) or 0))
    local target = base + elapsed
    if not setMeta(src, 'cmPaydayPlaytimeSeconds', target) then
        return false, 'playtime_persist_failed'
    end
    if not saveCharacter(src, 'cm-payday-playtime') then
        setMeta(src, 'cmPaydayPlaytimeSeconds', base)
        return false, 'playtime_persist_failed'
    end
    session.joinedAt = os.time()
    return true
end

local function totalPlaytimeSeconds(src)
    local base = math.max(0, math.floor(tonumber(getMeta(src, 'cmPaydayPlaytimeSeconds', 0)) or 0))
    local session = sessions[src]
    if not session or activeCharacterId(src) ~= session.charId then return base end
    return base + math.max(0, os.time() - session.joinedAt)
end

local function beginSession(src)
    src = tonumber(src)
    local charId = activeCharacterId(src)
    if not src or not charId then return false end
    local existing = sessions[src]
    if existing and existing.charId == charId then return true end
    if existing then pending[src] = nil end
    sessions[src] = { charId = charId, joinedAt = os.time() }
    loadPending(src)
    return true
end

local function endSession(src)
    src = tonumber(src)
    if not src then return end
    flushPlaytime(src)
    sessions[src] = nil
    pending[src] = nil
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src) beginSession(src) end)
AddEventHandler('cm-playerdata:server:characterUnloaded', function(src) endSession(src) end)
AddEventHandler('playerDropped', function() endSession(source) end)

-- Covers a cm-payday resource restart while players are already connected;
-- their pending totals are still safe in cm-playerdata metadata either way.
CreateThread(function()
    for _ = 1, 20 do
        local waiting = false
        for _, playerId in ipairs(GetPlayers()) do
            if not beginSession(tonumber(playerId)) then waiting = true end
        end
        if not waiting then break end
        Wait(500)
    end
end)

CreateThread(function()
    while true do
        Wait(5 * 60000)
        for src in pairs(sessions) do flushPlaytime(src) end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src in pairs(sessions) do flushPlaytime(src) end
end)

-- ---------------------------------------------------------------------------
-- Job xp handoff -- only jobs with their own leveling system get xp applied
-- back at payout time; the rest just bank cash.
-- ---------------------------------------------------------------------------

-- `charId` is passed to the consumer as an optional 3rd argument so it can
-- refuse to apply xp if the source now belongs to a different character
-- (consumers that ignore extra args -- taxi, farming -- are unaffected).
local function applyXpForJob(src, jobName, amount, charId)
    amount = normalizeAmount(amount, tonumber(Config.MaxPendingXp) or 1000000)
    if not amount then return false, 'invalid_amount' end

    local resource = ({ taxi = 'cm-taxi', fishing = 'cm-fishing', farming = 'cm-farming' })[jobName]
    if not resource or GetResourceState(resource) ~= 'started' then
        return false, 'xp_consumer_offline'
    end

    local ok, applied, state, leveledUp = pcall(function()
        return exports[resource]:AddXp(src, amount, charId)
    end)
    if not ok then return false, tostring(applied) end
    if applied ~= true then return false, tostring(state or 'xp_not_applied') end
    return true, state, leveledUp
end

-- ---------------------------------------------------------------------------
-- Payday tick -- fires once at the top of every real-world hour.
-- ---------------------------------------------------------------------------

local function hourKey()
    local t = os.date('*t')
    return t.year * 10000 + t.yday * 100 + t.hour
end

local lastFiredHourKey = hourKey()

local function payoutAccount()
    return tostring(Config.PayoutAccount or 'cash'):lower() == 'bank' and 'bank' or 'cash'
end

local function nextPayoutId(charId)
    payoutSequence = payoutSequence + 1
    return ('%s-%s-%s'):format(charId, os.time(), payoutSequence)
end

-- AddCash/AddBank already write economy_transactions before returning success
-- in the current cm-playerdata configuration. The marker and reason let a
-- restarted cm-payday distinguish a completed payout from a failed attempt.
local function payoutTransactionExists(payout)
    if not MySQL or type(payout) ~= 'table' then return nil, 'database_unavailable' end
    local ok, row = pcall(function()
        return MySQL.single.await([[SELECT id FROM economy_transactions
            WHERE character_id = ? AND account_type = ? AND amount = ?
              AND action = 'add' AND reason = ?
            ORDER BY id DESC LIMIT 1]], {
            tostring(payout.charId), tostring(payout.account), tonumber(payout.amount), tostring(payout.reason)
        })
    end)
    if not ok then return nil, tostring(row) end
    return row ~= nil
end

local function subtractCashAttribution(data, payout)
    for jobName, amount in pairs(type(payout.cashByJob) == 'table' and payout.cashByJob or {}) do
        local current = tonumber(data.cashByJob[jobName]) or 0
        amount = tonumber(amount) or 0
        if amount > 0 and current >= amount then
            current = current - amount
            data.cashByJob[jobName] = current > 0 and current or nil
        end
    end
end

local function recoverPayoutMarker(src, data, charId)
    local payout = data.payout
    if type(payout) ~= 'table' then return true end
    if tostring(payout.charId) ~= tostring(charId) then return false, 'payout_character_mismatch' end

    local exists, queryError = payoutTransactionExists(payout)
    if exists == nil then return false, queryError end
    if not exists then return true end

    local before = tonumber(payout.cashBefore) or 0
    local amount = tonumber(payout.amount) or 0
    -- If the cash metadata write completed before the marker clear, the value
    -- is already cashBefore-amount. If not, subtract it now. New earnings
    -- added after the payout are preserved by the comparison.
    if data.cash >= before then data.cash = math.max(0, data.cash - amount) end
    subtractCashAttribution(data, payout)
    data.payout = nil
    local saved = savePending(src)
    if not saved then
        data.payout = payout
        return false, 'payout_recovery_persist_failed'
    end
    dbg(('recovered completed payout %s for character %s'):format(tostring(payout.id), charId))
    return true
end

local function payCash(src, data, charId)
    local recovered, recoveryError = recoverPayoutMarker(src, data, charId)
    if not recovered then return false, 0, recoveryError end
    if data.cash <= 0 then return false, 0, nil end

    local payout = data.payout
    if not payout then
        local account = payoutAccount()
        local amount = math.floor(data.cash)
        payout = {
            id = nextPayoutId(charId),
            charId = tostring(charId),
            amount = amount,
            cashBefore = amount,
            cashByJob = copyXp(data.cashByJob),
            account = account,
            reason = nil,
            createdAt = os.time(),
        }
        -- Keep the same ID in the reason without adding another sequence
        -- value; the reason is the idempotency lookup key.
        payout.reason = ('CM Payday %s'):format(payout.id)
        data.payout = payout
        local marked = savePending(src)
        if not marked then
            data.payout = nil
            return false, 0, 'payout_marker_persist_failed'
        end
    end

    local amount = tonumber(payout.amount) or 0
    if amount <= 0 or data.cash < amount then return false, 0, 'payout_amount_invalid' end
    local api = playerData()
    if not api then return false, 0, 'playerdata_unavailable' end

    local ok, result
    if payout.account == 'bank' then
        ok, result = pcall(function() return api:AddBank(src, amount, payout.reason) end)
    else
        ok, result = pcall(function() return api:AddCash(src, amount, payout.reason) end)
    end
    if not ok or result ~= true then
        return false, 0, ok and 'money_api_rejected' or tostring(result)
    end

    local completedMarker = data.payout
    data.cash = data.cash - amount
    subtractCashAttribution(data, completedMarker)
    data.payout = nil
    if not savePending(src) then
        -- savePending writes cash before clearing the marker. Retaining the
        -- marker in memory keeps recovery safe if the process continues; on
        -- restart the persisted marker is resolved from economy_transactions.
        data.payout = completedMarker
        dbg(('payout state cleanup deferred for character %s'):format(charId))
        return true, amount, 'payout_state_pending'
    end
    return true, amount, nil
end

local function runPaydayForPlayer(src)
    local charId = activeCharacterId(src)
    local data = charId and loadPending(src) or nil
    if not charId or not data or payoutLocks[charId] then return end
    payoutLocks[charId] = true

    local ok, paidCash, cashAmount, cashError, xpParts, xpResults, cashByJob = xpcall(function()
        local beforeCashByJob = copyXp(data.cashByJob)
        local cashPaid, paidAmount, errorReason = payCash(src, data, charId)
        local beforeXp = copyXp(data.xp)
        if errorReason == 'payout_state_pending' or errorReason == 'payout_recovery_persist_failed' then
            return true, cashPaid, paidAmount, errorReason, {}, {}, beforeCashByJob
        end
        local successfulXp = {}
        local parts = {}
        local results = {}

        for jobName, rawAmount in pairs(beforeXp) do
            local amount = normalizeAmount(rawAmount, tonumber(Config.MaxPendingXp) or 1000000)
            if amount then
                local applied, stateOrError = applyXpForJob(src, jobName, amount, charId)
                if applied then
                    data.xp[jobName] = nil
                    local jobConfig = Config.Jobs[jobName]
                    parts[#parts + 1] = ('+%d %s XP'):format(amount, jobConfig.label)
                    successfulXp[jobName] = true
                    results[jobName] = { amount = amount, applied = true }
                else
                    results[jobName] = { amount = amount, applied = false, reason = tostring(stateOrError) }
                    dbg(('XP retained for character=%s job=%s reason=%s'):format(charId, jobName, tostring(stateOrError)))
                end
            end
        end

        if next(successfulXp) ~= nil then
            local saved = savePending(src)
            if not saved then
                data.xp = beforeXp
                parts = {}
                dbg(('XP state cleanup deferred for character %s'):format(charId))
            end
        end

        return true, cashPaid, paidAmount, errorReason, parts, results, beforeCashByJob
    end, function(err)
        return tostring(err)
    end)
    payoutLocks[charId] = nil

    if not ok then
        print(('^1[CM-PAYDAY]^7 ERROR payout failed character=%s source=%s error=%s'):format(charId, src, tostring(paidCash)))
        return
    end

    local parts = {}
    if paidCash and cashAmount > 0 then
        parts[#parts + 1] = ('+$%d paid to %s'):format(cashAmount, payoutAccount())
    end
    for _, part in ipairs(xpParts or {}) do parts[#parts + 1] = part end
    auditPayout(src, charId, paidCash and cashAmount or 0, payoutAccount(), cashByJob, xpResults)
    if #parts > 0 then
        flushPlaytime(src)
        local hours = totalPlaytimeSeconds(src) / 3600.0
        notify(src, ('PAYDAY\n%s\nPlayed %.1fh total'):format(table.concat(parts, '\n'), hours), 'success')
    elseif cashError then
        dbg(('cash retained for character=%s reason=%s'):format(charId, tostring(cashError)))
    end
end

local function runPayday()
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src then runPaydayForPlayer(src) end
    end
end

CreateThread(function()
    while true do
        Wait(15000)
        local nowKey = hourKey()
        if nowKey ~= lastFiredHourKey then
            lastFiredHourKey = nowKey
            dbg('firing payday tick at', os.date('%X'))
            runPayday()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Self-check command
-- ---------------------------------------------------------------------------

RegisterCommand('payday', function(src)
    if src == 0 then return end
    local data = loadPending(src)
    if not data then return end
    local hours = totalPlaytimeSeconds(src) / 3600.0
    local t = os.date('*t')
    local minutesLeft = 59 - t.min

    local xpParts = {}
    for jobName, amount in pairs(data.xp) do
        amount = math.floor(tonumber(amount) or 0)
        if amount > 0 then
            local jobConfig = Config.Jobs[jobName]
            xpParts[#xpParts + 1] = ('%s +%dXP'):format(jobConfig and jobConfig.label or tostring(jobName), amount)
        end
    end

    notify(src, ('Payday pending: +$%d%s | next payday in ~%d min | %.1fh played'):format(
        math.floor(data.cash),
        #xpParts > 0 and (' (' .. table.concat(xpParts, ', ') .. ')') or '',
        minutesLeft, hours
    ), 'info')
end, false)

RegisterCommand('paydaytest', function(src, args)
    if not Config.Debug or src ~= 0 then return end
    local target = tonumber(args[1])
    local action = tostring(args[2] or 'show'):lower()
    if not target then
        print('Usage: paydaytest <serverId> <addcash|addxp|show|force> [job] [amount]')
        return
    end

    if action == 'addcash' then
        local ok, reason = addPendingCash(target, args[3] or 'taxi', args[4] or 100, 'debug_paydaytest')
        print(('[CM-PAYDAY] addcash ok=%s reason=%s'):format(tostring(ok), tostring(reason)))
    elseif action == 'addxp' then
        local ok, reason = addPendingXp(target, args[3] or 'taxi', args[4] or 5)
        print(('[CM-PAYDAY] addxp ok=%s reason=%s'):format(tostring(ok), tostring(reason)))
    elseif action == 'force' then
        runPaydayForPlayer(target)
    else
        local data = loadPending(target)
        print(('[CM-PAYDAY] pending src=%s data=%s'):format(target, json.encode(data or {})))
    end
end, false)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('AddPendingCash', addPendingCash)
exports('AddPendingXp', addPendingXp)

exports('GetPending', function(src)
    src = tonumber(src)
    local data = loadPending(src)
    if not data then return { cash = 0, xp = {} } end
    return { cash = data.cash, cashByJob = copyXp(data.cashByJob), xp = copyXp(data.xp) }
end)

exports('GetPlaytimeSeconds', function(src)
    return totalPlaytimeSeconds(tonumber(src))
end)

exports('GetSecondsUntilNextPayday', function()
    local t = os.date('*t')
    return (59 - t.min) * 60 + (60 - t.sec)
end)
