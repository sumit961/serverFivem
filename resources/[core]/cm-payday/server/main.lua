local Config = CMPayday.Config
local PLAYERDATA = 'cm-playerdata'

-- pending[src]  = { cash = number, xp = { [jobName] = number } }
-- sessions[src] = { joinedAt = os.time() }  (current-session playtime clock)
local pending = {}
local sessions = {}

local function dbg(...)
    if Config.Debug then print('[CM-PAYDAY]', ...) end
end

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
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

local function notify(src, message, kind)
    if GetResourceState('cm-hud') ~= 'started' then return end
    pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
end

-- ---------------------------------------------------------------------------
-- Pending pay/xp -- persisted to cm-playerdata metadata on every change so a
-- disconnect or server restart before the next payday never loses earnings.
-- ---------------------------------------------------------------------------

local function loadPending(src)
    if pending[src] then return pending[src] end

    local cash = math.max(0, math.floor(tonumber(getMeta(src, 'cmPaydayPendingCash', 0)) or 0))
    local xp = {}
    local raw = getMeta(src, 'cmPaydayPendingXp', nil)
    if type(raw) == 'string' and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then xp = decoded end
    end

    pending[src] = { cash = cash, xp = xp }
    return pending[src]
end

local function savePending(src)
    local data = pending[src]
    if not data then return end
    setMeta(src, 'cmPaydayPendingCash', math.floor(data.cash))
    setMeta(src, 'cmPaydayPendingXp', json.encode(data.xp))
end

local function addPendingCash(src, jobName, amount, reason)
    src = tonumber(src)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 then return false end

    local data = loadPending(src)
    data.cash = data.cash + amount
    savePending(src)

    local jobConfig = Config.Jobs[jobName]
    notify(src, ('%s: +$%d banked for payday'):format(jobConfig and jobConfig.label or tostring(jobName), amount), 'info')
    dbg(('pending +$%d for %s (job=%s reason=%s)'):format(amount, src, tostring(jobName), tostring(reason)))
    return true
end

local function addPendingXp(src, jobName, amount)
    src = tonumber(src)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 then return false end

    local data = loadPending(src)
    data.xp[jobName] = (data.xp[jobName] or 0) + amount
    savePending(src)
    return true
end

-- ---------------------------------------------------------------------------
-- Playtime -- accumulated in real seconds, persisted incrementally so a
-- crash or ungraceful restart only ever loses the current flush window.
-- ---------------------------------------------------------------------------

local function flushPlaytime(src)
    local session = sessions[src]
    if not session then return end
    local elapsed = os.time() - session.joinedAt
    if elapsed <= 0 then return end
    local base = math.max(0, math.floor(tonumber(getMeta(src, 'cmPaydayPlaytimeSeconds', 0)) or 0))
    setMeta(src, 'cmPaydayPlaytimeSeconds', base + elapsed)
    session.joinedAt = os.time()
end

local function totalPlaytimeSeconds(src)
    local base = math.max(0, math.floor(tonumber(getMeta(src, 'cmPaydayPlaytimeSeconds', 0)) or 0))
    local session = sessions[src]
    if not session then return base end
    return base + math.max(0, os.time() - session.joinedAt)
end

local function beginSession(src)
    src = tonumber(src)
    if not src then return end
    sessions[src] = { joinedAt = os.time() }
    loadPending(src)
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
    for _, playerId in ipairs(GetPlayers()) do
        beginSession(tonumber(playerId))
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

local function applyXpForJob(src, jobName, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    if jobName == 'taxi' and GetResourceState('cm-taxi') == 'started' then
        pcall(function() exports['cm-taxi']:AddXp(src, amount) end)
    elseif jobName == 'fishing' and GetResourceState('cm-fishing') == 'started' then
        pcall(function() exports['cm-fishing']:AddXp(src, amount) end)
    elseif jobName == 'farming' and GetResourceState('cm-farming') == 'started' then
        pcall(function() exports['cm-farming']:AddXp(src, amount) end)
    end
end

-- ---------------------------------------------------------------------------
-- Payday tick -- fires once at the top of every real-world hour.
-- ---------------------------------------------------------------------------

local function hourKey()
    local t = os.date('*t')
    return t.year * 10000 + t.yday * 100 + t.hour
end

local lastFiredHourKey = hourKey()

local function runPayday()
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src then
            local data = loadPending(src)
            local cash = math.floor(data.cash)
            local paidCash = false

            if cash > 0 then
                local api = playerData()
                if api then
                    local ok, result = pcall(function() return api:AddCash(src, cash, 'CM Payday') end)
                    paidCash = ok and result == true
                end
            end

            local xpParts = {}
            for jobName, amount in pairs(data.xp) do
                amount = math.floor(tonumber(amount) or 0)
                if amount > 0 then
                    applyXpForJob(src, jobName, amount)
                    local jobConfig = Config.Jobs[jobName]
                    xpParts[#xpParts + 1] = ('+%d %s XP'):format(amount, jobConfig and jobConfig.label or tostring(jobName))
                end
            end

            if paidCash then data.cash = data.cash - cash end
            if paidCash or #xpParts > 0 then
                data.xp = {}
                savePending(src)
            end

            if paidCash or #xpParts > 0 then
                flushPlaytime(src)
                local hours = totalPlaytimeSeconds(src) / 3600.0

                local parts = {}
                if paidCash then parts[#parts + 1] = ('+$%d'):format(cash) end
                for _, p in ipairs(xpParts) do parts[#parts + 1] = p end

                notify(src, ('PAYDAY: %s (played %.1fh total)'):format(table.concat(parts, ', '), hours), 'success')
            end
        end
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

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('AddPendingCash', addPendingCash)
exports('AddPendingXp', addPendingXp)

exports('GetPending', function(src)
    src = tonumber(src)
    local data = loadPending(src)
    return { cash = data.cash, xp = data.xp }
end)

exports('GetPlaytimeSeconds', function(src)
    return totalPlaytimeSeconds(tonumber(src))
end)

exports('GetSecondsUntilNextPayday', function()
    local t = os.date('*t')
    return (59 - t.min) * 60 + (60 - t.sec)
end)
