CMRacing = CMRacing or {}
CMRacing.Server = CMRacing.Server or {}
CMRacing.Server.Progression = {}

local Progression = CMRacing.Server.Progression
local Config = CMRacing.Config

-- Cooldown tracking in memory: [charId .. ':' .. routeId] = expiresAtUnix
local RouteCooldowns = {}

local function getPlayerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function getCharId(src)
    local pd = getPlayerData()
    if not pd then return nil end
    local ok, charId = pcall(function() return pd:GetCharacterId(src) end)
    if ok and charId and tostring(charId) ~= '' then
        return tostring(charId)
    end
    return nil
end

local function defaultProfile()
    return {
        level = 1,
        xp = 0,
        racesCompleted = 0,
        personalBests = {},
        pendingWages = 0, -- Retained wages if payday registration is pending
        history = {},
    }
end

function Progression.GetProfile(src)
    local pd = getPlayerData()
    local charId = getCharId(src)
    if not pd or not charId then
        return defaultProfile()
    end

    local ok, meta = pcall(function() return pd:GetMetadata(src, 'cmRacing') end)
    if ok and type(meta) == 'table' then
        meta.level = tonumber(meta.level) or 1
        meta.xp = tonumber(meta.xp) or 0
        meta.racesCompleted = tonumber(meta.racesCompleted) or 0
        meta.personalBests = type(meta.personalBests) == 'table' and meta.personalBests or {}
        meta.pendingWages = tonumber(meta.pendingWages) or 0
        meta.history = type(meta.history) == 'table' and meta.history or {}
        return meta
    end

    local initial = defaultProfile()
    pcall(function()
        pd:SetMetadata(src, 'cmRacing', initial)
        pd:Save(src, 'cm-racing-init')
    end)
    return initial
end

function Progression.SaveProfile(src, profile)
    local pd = getPlayerData()
    if not pd then return false, 'playerdata_unavailable' end

    local okSet = pcall(function()
        return pd:SetMetadata(src, 'cmRacing', profile)
    end)
    if not okSet then return false, 'set_metadata_failed' end

    local okSave = pcall(function()
        return pd:Save(src, 'cm-racing')
    end)
    return okSave == true
end

function Progression.CalculateLevel(xp)
    xp = tonumber(xp) or 0
    local currentLevel = 1
    for lvl = 1, #Config.Progression do
        local tier = Config.Progression[lvl]
        if xp >= tier.requiredXp then
            currentLevel = tier.level
        end
    end
    return currentLevel
end

function Progression.AddRaceResult(src, routeId, finalTimeMs, xpGained)
    local profile = Progression.GetProfile(src)
    local isPb = false

    profile.racesCompleted = (profile.racesCompleted or 0) + 1
    profile.xp = (profile.xp or 0) + (tonumber(xpGained) or 0)
    profile.level = Progression.CalculateLevel(profile.xp)

    local previousPb = tonumber(profile.personalBests[routeId])
    if not previousPb or finalTimeMs < previousPb then
        profile.personalBests[routeId] = finalTimeMs
        isPb = true
    end

    -- Retain recent run in history (keep last 5)
    table.insert(profile.history, 1, {
        routeId = routeId,
        timeMs = finalTimeMs,
        date = os.time(),
        isPb = isPb
    })
    while #profile.history > 5 do
        table.remove(profile.history)
    end

    Progression.SaveProfile(src, profile)
    return isPb, profile
end

function Progression.RetainPendingWage(src, amount, reason, reference)
    local profile = Progression.GetProfile(src)
    profile.pendingWages = (profile.pendingWages or 0) + math.floor(tonumber(amount) or 0)
    profile.pendingEntries = profile.pendingEntries or {}
    table.insert(profile.pendingEntries, 1, {
        reference = reference or ('RACE-' .. tostring(src) .. '-' .. tostring(os.time())),
        amount = math.floor(tonumber(amount) or 0),
        reason = reason or 'pending_payroll_integration',
        createdAt = os.time(),
        settled = false
    })
    while #profile.pendingEntries > 20 do
        table.remove(profile.pendingEntries)
    end
    Progression.SaveProfile(src, profile)
    print(('[CM-RACING] Retained $%d in character pending wages for src=%s ref=%s (reason: %s)'):format(
        amount, tostring(src), tostring(reference or 'N/A'), tostring(reason or 'pending_payroll_integration')
    ))
end

function Progression.IsOnCooldown(charId, routeId)
    if not charId or not routeId then return false, 0 end
    local key = tostring(charId) .. ':' .. tostring(routeId)
    local expiry = RouteCooldowns[key]
    if not expiry then return false, 0 end

    local remaining = expiry - os.time()
    if remaining <= 0 then
        RouteCooldowns[key] = nil
        return false, 0
    end
    return true, remaining
end

function Progression.SetCooldown(charId, routeId, seconds)
    if not charId or not routeId then return end
    local key = tostring(charId) .. ':' .. tostring(routeId)
    RouteCooldowns[key] = os.time() + (tonumber(seconds) or 180)
end
