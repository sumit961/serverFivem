-- cm-phone server core: identity resolution, sanitising, rate limits, operation locks.
-- Character ID is the only persistent identity. Source IDs are transport only and are
-- never written to the database or returned to clients.
CMPhone.Server = CMPhone.Server or {}
local S = CMPhone.Server
local Config = CMPhone.Config
local PLAYERDATA = 'cm-playerdata'

-- Online[cid] = src, rebuilt from lifecycle events. Always re-verified before use.
local Online = {}
S.TestOnline = nil -- selftest-only: { [cid] = fakeNegativeSource }

function S.dbg(...)
    if Config.Debug then print('[cm-phone]', ...) end
end

function S.playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

-- source -> active character id (string) or nil. Resolved from cm-playerdata on every call.
function S.CharacterOf(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local api = S.playerData()
    if not api then return nil end
    local ok, cid = pcall(function() return api:GetCharacterId(src) end)
    if not ok or cid == nil or tostring(cid) == '' then return nil end
    return tostring(cid)
end

-- character id -> live source or nil (offline). Verified against playerdata.
function S.SourceOf(cid)
    cid = cid and tostring(cid)
    if not cid then return nil end
    if S.TestOnline and S.TestOnline[cid] then return S.TestOnline[cid] end
    local src = Online[cid]
    if src and GetPlayerName(src) and S.CharacterOf(src) == cid then return src end
    if src then Online[cid] = nil end
    return nil
end

function S.IsOnline(cid)
    return S.SourceOf(cid) ~= nil
end

local function track(src)
    local cid = S.CharacterOf(src)
    if cid then Online[cid] = tonumber(src) end
end

local function untrack(src)
    src = tonumber(src)
    for cid, s in pairs(Online) do
        if s == src then Online[cid] = nil end
    end
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    track(src)
    TriggerEvent('cm-phone:internal:characterLoaded', tonumber(src))
end)
AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    TriggerEvent('cm-phone:internal:characterUnloaded', tonumber(src))
    untrack(src)
end)
AddEventHandler('playerDropped', function()
    local src = source
    TriggerEvent('cm-phone:internal:characterUnloaded', tonumber(src))
    untrack(src)
end)

CreateThread(function()
    for _ = 1, 20 do
        local waiting = false
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            if src then
                if S.CharacterOf(src) then track(src) else waiting = true end
            end
        end
        if not waiting then break end
        Wait(500)
    end
end)

-- Safe emit: skips offline/fake (negative) sources so service logic is testable.
function S.Emit(src, event, ...)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false end
    TriggerClientEvent(event, src, ...)
    return true
end

function S.Notify(src, message, kind)
    if GetResourceState('cm-hud') ~= 'started' then return end
    S.Emit(src, 'cm-hud:client:notify', message, kind or 'info')
end

-- ---------------------------------------------------------------------------
-- Text handling. The NUI renders with textContent only; this removes control
-- characters and bounds length so stored data is predictable.
-- ---------------------------------------------------------------------------
function S.cleanText(value, maxLen, allowNewlines)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('\r\n', '\n'):gsub('\r', '\n')
    if allowNewlines then
        value = value:gsub('[\0-\8\11\12\14-\31\127]', '')
    else
        value = value:gsub('[\0-\31\127]', ' ')
    end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    -- Count by UTF-8 characters, not bytes.
    local count, cut = 0, #value
    for pos in value:gmatch('()[\0-\127\194-\244][\128-\191]*') do
        count = count + 1
        if count > maxLen then cut = pos - 1 break end
    end
    if count > maxLen then value = value:sub(1, cut) end
    return value
end

-- ---------------------------------------------------------------------------
-- Rate limits (per character + bucket): minimum interval and burst window.
-- ---------------------------------------------------------------------------
local rate = {}

function S.RateLimit(cid, bucket)
    local cfg = Config.RateLimits[bucket]
    if not cfg or not cid then return true end
    local now = GetGameTimer()
    local key = tostring(cid) .. ':' .. bucket
    local state = rate[key]
    if not state then
        state = { last = 0, stamps = {} }
        rate[key] = state
    end
    if now - state.last < (cfg.minMs or 0) then return false end
    local fresh = {}
    for _, t in ipairs(state.stamps) do
        if now - t < (cfg.windowMs or 0) then fresh[#fresh + 1] = t end
    end
    if #fresh >= (cfg.burst or 9999) then
        state.stamps = fresh
        return false
    end
    fresh[#fresh + 1] = now
    state.stamps = fresh
    state.last = now
    return true
end

CreateThread(function()
    while true do
        Wait(300000)
        local now = GetGameTimer()
        for key, state in pairs(rate) do
            if now - state.last > 900000 then rate[key] = nil end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Operation locks: one in-flight mutation per character + operation.
-- ---------------------------------------------------------------------------
local locks = {}

function S.Lock(cid, op)
    local key = tostring(cid) .. ':' .. op
    if locks[key] then return false end
    locks[key] = GetGameTimer()
    return true
end

function S.Unlock(cid, op)
    locks[tostring(cid) .. ':' .. op] = nil
end

-- Runs fn under a lock; always releases, even on error.
function S.WithLock(cid, op, fn, ...)
    if not S.Lock(cid, op) then return false, 'busy' end
    local ok, a, b, c = pcall(fn, ...)
    S.Unlock(cid, op)
    if not ok then
        print(('[cm-phone] %s failed: %s'):format(op, tostring(a)))
        return false, 'internal_error'
    end
    return a, b, c
end

-- Required context for every client-originated action:
-- source -> loaded character -> phone identity. Returns cid, number or nil, reason.
function S.Context(src)
    local cid = S.CharacterOf(src)
    if not cid then return nil, 'character_not_loaded' end
    local number = S.GetNumber(cid)
    if not number then return nil, 'no_phone' end
    return cid, number
end

function S.json(value)
    local ok, encoded = pcall(json.encode, value)
    return ok and encoded or nil
end

function S.decode(value)
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
end

function S.audit(src, kind, detail)
    if GetResourceState('cm-admin') ~= 'started' then return end
    pcall(function()
        TriggerEvent('cm-admin:server:addLog', src, kind, { category = 'phone', detail = detail or {} })
    end)
end
