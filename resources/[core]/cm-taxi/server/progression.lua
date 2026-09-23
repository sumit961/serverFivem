local Config = CMTaxi.Config
CMTaxi.Server = CMTaxi.Server or {}

local dbReady = false

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cm_taxi_drivers` (
            `charid` VARCHAR(64) NOT NULL PRIMARY KEY,
            `xp` INT NOT NULL DEFAULT 0,
            `level` INT NOT NULL DEFAULT 1
        )
    ]])
    dbReady = true
end)

local function getCharId(src)
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    local ok, charId = pcall(function() return exports['cm-playerdata']:GetCharId(src) end)
    if ok and charId then return tostring(charId) end
    return nil
end

-- Progression is cached in-memory per source while the driver is online and
-- flushed to MySQL on every change; cm-playerdata already owns money/items.
local cache = {}

local function loadProgression(src)
    local waited = 0
    while not dbReady and waited < 5000 do Wait(100) waited = waited + 100 end

    local charId = getCharId(src)
    if not charId then return nil end

    if cache[src] and cache[src].charId == charId then
        return cache[src]
    end
    cache[src] = nil

    local row = MySQL.single.await('SELECT xp, level FROM cm_taxi_drivers WHERE charid = ?', { charId })
    if not row then
        MySQL.insert.await('INSERT INTO cm_taxi_drivers (charid, xp, level) VALUES (?, 0, 1)', { charId })
        row = { xp = 0, level = 1 }
    end

    cache[src] = { charId = charId, xp = tonumber(row.xp) or 0, level = tonumber(row.level) or 1 }
    return cache[src]
end

local function saveProgression(src)
    local data = cache[src]
    if not data then return end
    MySQL.update.await('UPDATE cm_taxi_drivers SET xp = ?, level = ? WHERE charid = ?', { data.xp, data.level, data.charId })
end

local function clearProgression(src)
    cache[src] = nil
end

local function grantReward(src, reward)
    if type(reward) ~= 'table' then return end
    if reward.type == 'money' then
        if GetResourceState('cm-playerdata') == 'started' then
            pcall(function() exports['cm-playerdata']:AddCash(src, reward.amount, 'Taxi level-up reward') end)
        end
    elseif reward.type == 'item' then
        if GetResourceState('cm-inventory') == 'started' then
            pcall(function() exports['cm-inventory']:AddItem(src, reward.name, reward.amount, nil, 'taxi-level-reward') end)
        end
    end
end

local function xpForLevel(level)
    return math.floor(level * 100 * Config.SkillMultiplier)
end

-- Adds xp, applies level-ups (with rewards) and persists to MySQL. Returns
-- the updated {xp, level} table.
local function addXp(src, amount)
    local data = cache[src]
    if not data then return nil end

    amount = math.max(0, tonumber(amount) or 0)
    data.xp = data.xp + amount

    local leveledUp = false
    while data.level < Config.SkillMaxLevel and data.xp >= xpForLevel(data.level) do
        data.xp = data.xp - xpForLevel(data.level)
        data.level = data.level + 1
        leveledUp = true
    end

    saveProgression(src)

    TriggerClientEvent('cm-taxi:client:progression', src, data)

    if leveledUp then
        local levelConfig = Config.Levels[data.level]
        local rewardLabel = levelConfig and levelConfig.label or nil
        if levelConfig and levelConfig.reward then
            grantReward(src, levelConfig.reward)
        end
        TriggerClientEvent('cm-taxi:client:notify', src, CMTaxi.Locale('levelup', rewardLabel or 'a milestone bonus'), 'success')
    end

    return data
end

local function removeXp(src, amount)
    local data = cache[src]
    if not data then return nil end

    amount = math.max(0, tonumber(amount) or 0)
    while amount > 0 do
        if data.xp >= amount then
            data.xp = data.xp - amount
            amount = 0
        elseif data.level <= 1 then
            data.xp = 0
            amount = 0
        else
            amount = amount - data.xp
            data.level = data.level - 1
            data.xp = xpForLevel(data.level)
        end
    end

    saveProgression(src)
    TriggerClientEvent('cm-taxi:client:progression', src, data)
    return data
end

local function getProgression(src)
    return cache[src]
end

-- Applies xp even when the driver is off duty (cache already cleared) -- used
-- by cm-payday to apply xp banked from fares once the hourly payday fires,
-- since a driver may have clocked off before their earnings were paid out.
local function addXpStandalone(src, amount)
    local hadCache = cache[src] ~= nil
    if not hadCache then loadProgression(src) end
    addXp(src, amount)
    if not hadCache then cache[src] = nil end
end

CMTaxi.Server.Progression = {
    Load = loadProgression,
    Clear = clearProgression,
    AddXp = addXp,
    RemoveXp = removeXp,
    Get = getProgression,
    XpForLevel = xpForLevel,
}

exports('AddXp', addXpStandalone)
