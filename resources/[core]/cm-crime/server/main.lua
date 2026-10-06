-- cm-crime FiveM wiring for server/core.lua. See docs/README.md.
-- SERVER-TO-SERVER ONLY: there is no client event, NUI callback or command a player can use to touch a crime session.
-- Physical client interaction goes CLIENT -> crime content server resource -> these exports.
local Config = CMCrime.Config
local Core, Store = CMCrime.Core, CMCrime.Store

local function xcall(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then return false, 'resource_unavailable' end
    local args = table.pack(...)
    local res = table.pack(pcall(function() return exports[resource][name](exports[resource], table.unpack(args, 1, args.n)) end))
    if not res[1] then return false, 'call_failed' end
    return true, table.unpack(res, 2, res.n)
end

local function jsonEncode(t) local ok, s = pcall(json.encode, t); return ok and s or '' end

-- ---------------------------------------------------------------- adapters

local chars = {
    sourceOf = function(cid)
        local ok, src = xcall('cm-playerdata', 'GetSourceByCharId', tonumber(cid))
        src = ok and tonumber(src) or nil
        if src and src > 0 and GetPlayerName(src) then return src end
        return nil
    end,
    bucket = function(src)
        local ok, b = pcall(GetPlayerRoutingBucket, src)
        return ok and tonumber(b) or nil
    end,
}

-- Police availability comes from the law owner ONLY: `cm-law:GetOnDutyCount(orgId)` (docs: cm-law/docs/ON_DUTY_COUNT.md). cm-crime keeps no roster, never
-- enumerates characters and never falls back to another method: an unavailable, forbidden, malformed or non-numeric answer is nil and the core fails closed
-- (`police_unavailable`). 0 is a real answer (healthy law, nobody on duty) and is distinguished from nil by the core. Only a SUCCESSFUL count is cached,
-- for a few seconds (Config.Police.cacheSeconds), so a cm-law restart can never leave a stale "unavailable" behind and recovery needs no restart.
local policeCache = {}
local police = {
    count = function(org)
        local now = os.time()
        local hit = policeCache[org]
        if hit and now - hit.at < Config.Police.cacheSeconds then return hit.n end
        local ok, n = xcall('cm-law', 'GetOnDutyCount', org)       -- xcall refuses when cm-law is not started
        if ok and type(n) == 'number' and n == n and n >= 0 and n == math.floor(n) and n < 1000000 then
            policeCache[org] = { n = n, at = now }
            return n
        end
        policeCache[org] = nil
        return nil
    end,
}

-- Dispatch goes through the existing law dispatch export (no second dispatch system). Only safe, server-built data is sent.
local dispatch = {
    send = function(info)
        local text = tostring(info.text or ''):sub(1, 170)
        local okc, success = xcall('cm-law', 'CreateLawIncident', text, { x = info.coords.x + 0.0, y = info.coords.y + 0.0, z = info.coords.z + 0.0 },
            nil, 'Alarm', { callType = 'crime_alarm', priority = info.priority, organizationId = 'police', routingBucket = info.bucket or 0 })
        return okc and success == true
    end,
}

local hits = {}
local function rate(key, bucket)
    local cfg = Config.RateLimits[bucket]
    if not cfg then return true end
    local k, now = key .. ':' .. bucket, os.time()
    local kept = {}
    for _, t in ipairs(hits[k] or {}) do if now - t < cfg[2] then kept[#kept + 1] = t end end
    if #kept >= cfg[1] then hits[k] = kept; return false end
    kept[#kept + 1] = now; hits[k] = kept
    return true
end

local core = Core.New({
    cfg = Config, store = Store, now = os.time, rand = math.random, encode = jsonEncode,
    chars = chars, police = police, dispatch = dispatch, rate = rate,
    owners = { started = function(resource) return GetResourceState(resource) == 'started' end },
    audit = function(kind, detail) TriggerEvent('cm-admin:server:addLog', 0, kind, { category = 'crime', detail = detail or {} }) end,
    log = function(level, msg) print(('[cm-crime] ^1%s: %s^7'):format(level, tostring(msg))) end,
})
CMCrime.Engine = core
local ready = false

-- ---------------------------------------------------------- public exports
-- Every mutation is bound to GetInvokingResource(): only the resource that registered an activity can touch its sessions.

local function owned(fn)
    return function(...)
        local invoker = GetInvokingResource()
        if not invoker or invoker == GetCurrentResourceName() then return false, 'forbidden' end
        if not ready then return false, 'not_ready' end
        return fn(invoker, ...)
    end
end

exports('RegisterCrimeActivity', owned(function(inv, def) return core:RegisterActivity(inv, def) end))
exports('CanBeginCrime', owned(function(inv, activityId, ctx) return core:CanBegin(inv, activityId, ctx) end))
exports('BeginCrimeSession', owned(function(inv, activityId, ctx) return core:Begin(inv, activityId, ctx) end))
exports('JoinCrimeSession', owned(function(inv, ref, cid) return core:Join(inv, ref, cid) end))
exports('LeaveCrimeSession', owned(function(inv, ref, cid, state, reason) return core:Leave(inv, ref, cid, state, reason) end))
exports('GetCrimeSession', owned(function(inv, ref) return core:Get(inv, ref) end))
exports('AdvanceCrimeStage', owned(function(inv, ref, expected, nextStage, ctx) return core:Advance(inv, ref, expected, nextStage, ctx) end))
exports('TriggerCrimeDispatch', owned(function(inv, ref, dtype) return core:Dispatch(inv, ref, dtype) end))
exports('CompleteCrime', owned(function(inv, ref, result) return core:Complete(inv, ref, result) end))
exports('FailCrime', owned(function(inv, ref, reason) return core:Fail(inv, ref, reason) end))
exports('CancelCrime', owned(function(inv, ref, reason) return core:Cancel(inv, ref, reason) end))
exports('ConfirmCrimeReward', owned(function(inv, ref, token) return core:ConfirmReward(inv, ref, token) end))
exports('ReportCrimeRewardFailure', owned(function(inv, ref, token, reason) return core:ReportRewardFailure(inv, ref, token, reason) end))
exports('GetCrimeCooldown', owned(function(inv, activityId, scope, key) return core:GetCooldown(inv, activityId, scope, key) end))

-- Admin / recovery (caller must be cm-admin; cm-admin stays the permission gate). UI wiring is deferred.
local function admin(fn)
    return function(...)
        if not Config.AdminCallers[GetInvokingResource() or ''] then return false, 'forbidden' end
        if not ready then return false, 'not_ready' end
        return fn(...)
    end
end
exports('AdminListCrimeSessions', admin(function(filter) return core:AdminList(filter) end))
exports('AdminInspectCrime', admin(function(ref) return core:AdminInspect(ref) end))
exports('AdminListCrimeCooldowns', admin(function(filter) return core:AdminCooldowns(filter) end))
exports('AdminCancelCrime', admin(function(ref, label) return core:AdminCancel(ref, label) end))
exports('AdminReconcileCrime', admin(function(ref, resolution, label) return core:AdminReconcile(ref, resolution, label) end))

local function consoleOnly(name, fn)
    RegisterCommand(name, function(src, args)
        if src ~= 0 then return end
        local ok, a, b = pcall(fn, args)
        print(('[cm-crime] %s -> %s'):format(name, ok and jsonEncode({ a, b }) or tostring(a)))
    end, true)
end
consoleOnly('cm_crime_list', function() return core:AdminList() end)
consoleOnly('cm_crime_inspect', function(a) return core:AdminInspect(a[1]) end)
consoleOnly('cm_crime_cooldowns', function() return core:AdminCooldowns() end)
consoleOnly('cm_crime_cancel', function(a) return core:AdminCancel(a[1], 'console') end)
consoleOnly('cm_crime_reconcile', function(a) return core:AdminReconcile(a[1], a[2], 'console') end)

-- ------------------------------------------------------------------ lifecycle

CreateThread(function()
    local ok, err = pcall(function() Store.EnsureSchema(); Store.cooldownPurge(os.time() - 7 * 24 * 3600) end)
    if not ok then print(('[cm-crime] ^1schema error: %s^7'):format(tostring(err))); return end
    ready = true
    -- Definitions live in memory: ask content resources to register again (local server event, not networked).
    TriggerEvent('cm-crime:server:registryReady')
    Wait(3000)   -- let owners re-register before the first recovery sweep decides an owner is gone
    local rok, rerr = pcall(function() return core:Sweep() end)
    if not rok then print(('[cm-crime] recovery error: %s'):format(tostring(rerr))) end
    while true do
        Wait(Config.SweepSeconds * 1000)
        local sok, serr = pcall(function() return core:Sweep() end)
        if not sok then print(('[cm-crime] sweep error: %s'):format(tostring(serr))) end
    end
end)
