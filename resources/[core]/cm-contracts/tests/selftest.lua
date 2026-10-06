-- Deterministic local self-test for cm-contracts (no FiveM, no database).
--   lua tests/selftest.lua        (run from resources/[core]/cm-contracts)
-- The in-memory store mirrors server/store.lua semantics (single-statement compare-and-swap,
-- UNIQUE source key, once-only journal keys). The business-supply source and trucking provider
-- are test doubles that mimic the real exports' idempotency contracts.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
dofile(here .. '/config.lua')
dofile(here .. '/server/core.lua')
local Core, Config = CMContracts.Core, CMContracts.Config

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and (' (' .. tostring(detail) .. ')') or '')) end
end

-- ------------------------------------------------------------------ fake store
local function newStore(clock)
    local S, rows, events, nextId = {}, {}, {}, 0
    S.rows, S.log = rows, events
    local function copy(r) if not r then return nil end local c = {} for k, v in pairs(r) do c[k] = v end return c end
    function S.getByRef(ref) for _, r in pairs(rows) do if r.reference == ref then return copy(r) end end end
    function S.getBySource(res, ref, t) for _, r in pairs(rows) do if r.source_resource == res and r.source_reference == ref and r.contract_type == t then return copy(r) end end end
    function S.insert(r)
        if S.getBySource(r.source_resource, r.source_reference, r.contract_type) then return nil, 'duplicate' end
        nextId = nextId + 1; local c = copy(r); c.id = nextId; c.fallback_deferrals = 0; c.fallback_attempts = 0; c.fail_count = 0
        rows[nextId] = c; return nextId
    end
    function S.cas(ref, from, patch, where)
        local r; for _, x in pairs(rows) do if x.reference == ref then r = x end end
        if not r then return 0 end
        local okStatus = false
        for _, s in ipairs(from) do if r.status == s then okStatus = true end end
        if not okStatus then return 0 end
        where = where or {}
        if where.claimed_character_id and r.claimed_character_id ~= tostring(where.claimed_character_id) then return 0 end
        if where.fallback_after and not (r.fallback_at > where.fallback_after) then return 0 end
        if where.fallback_due and not (r.fallback_at <= where.fallback_due) then return 0 end
        if where.fallback_retry_due and not (r.fallback_next_at and r.fallback_next_at <= where.fallback_retry_due) then return 0 end
        if where.claim_expired and not (r.claim_expires_at and r.claim_expires_at < where.claim_expired) then return 0 end
        if where.claim_not_expired and not (r.claim_expires_at == nil or r.claim_expires_at > where.claim_not_expired) then return 0 end
        if where.completing_before and not (r.completing_at and r.completing_at < where.completing_before) then return 0 end
        for k, v in pairs(patch) do if v == false then r[k] = nil else r[k] = v end end
        return 1
    end
    local function matchCid(r, cid, pt, statuses)
        if r.claimed_character_id ~= cid or r.provider_type ~= pt then return false end
        for _, s in ipairs(statuses) do if r.status == s then return true end end
        return false
    end
    function S.countByCharacter(cid, pt, st) local n = 0 for _, r in pairs(rows) do if matchCid(r, cid, pt, st) then n = n + 1 end end return n end
    function S.listByCharacter(cid, pt, st) local o = {} for _, r in pairs(rows) do if matchCid(r, cid, pt, st) then o[#o + 1] = copy(r) end end return o end
    function S.listAvailable(pt, now, f, cid)
        local o = {}
        for i = 1, nextId do local r = rows[i]
            if r.status == 'available' and r.provider_type == pt and r.fallback_at > now
                and (not f.contractType or f.contractType == r.contract_type) and (not f.cargoClass or f.cargoClass == r.cargo_class) then o[#o + 1] = copy(r) end end
        if cid then for _, r in ipairs(S.listByCharacter(cid, pt, { 'claimed', 'active' })) do o[#o + 1] = r end end
        return o
    end
    function S.query(kind, arg, limit)
        local o = {}
        for i = 1, nextId do local r = rows[i]
            local hit = (kind == 'expired_claims' and r.status == 'claimed' and r.claim_expires_at and r.claim_expires_at < arg)
                or (kind == 'expired_active' and r.status == 'active' and r.claim_expires_at and r.claim_expires_at < arg)
                or (kind == 'stuck_completing' and r.status == 'completing' and r.completing_at and r.completing_at < arg)
                or (kind == 'fallback_due' and (r.status == 'available' or r.status == 'claimed' or r.status == 'active') and r.fallback_at <= arg)
                or (kind == 'fallback_retry' and r.status == 'fallback' and r.fallback_next_at and r.fallback_next_at <= arg)
            if hit and #o < (limit or 20) then o[#o + 1] = copy(r) end end
        return o
    end
    function S.insertEvent(id, kind, actor, detail, key)
        if key then for _, e in ipairs(events) do if e.id == id and e.key == key then return false end end end
        events[#events + 1] = { id = id, kind = kind, actor = actor, key = key, detail = detail }; return true
    end
    function S.events(id) local o = {} for _, e in ipairs(events) do if e.id == id then o[#o + 1] = e end end return o end
    function S.listAdmin(status, pt, limit) local o = {} for _, r in pairs(rows) do if not status and r.status ~= 'completed' and r.status ~= 'cancelled' or r.status == status then o[#o + 1] = copy(r) end end return o end
    return S
end

local function countKind(S, kind) local n = 0 for _, e in ipairs(S.log) do if e.kind == kind then n = n + 1 end end return n end
local function countTerminal(S, id) local n = 0 for _, e in ipairs(S.log) do if e.id == id and e.key == 'terminal' then n = n + 1 end end return n end

-- ---------------------------------------------------------------- the world
local W
local function world(opts)
    opts = opts or {}
    W = { clock = 1000000, orders = {}, stock = 0, stockCredits = 0, rewards = 0, calls = {}, providerEvents = {},
        eligibleCids = { ['101'] = true, ['102'] = true, ['103'] = true }, providerBroken = false, sourceMode = 'ok', sourceHook = nil }
    local S = newStore()
    -- Business-supply source double: idempotent complete/fallback, stock credited exactly once per order.
    local function credit(o)
        if o.delivered then return true, { replayed = true } end
        o.delivered = true; W.stock = W.stock + o.units; W.stockCredits = W.stockCredits + 1
        return true, { units = o.units }
    end
    local sourceExports = {
        ContractSourceComplete = function(ctx)
            W.calls[#W.calls + 1] = 'complete:' .. ctx.sourceReference
            if W.sourceHook then W.sourceHook('complete', ctx) end
            local o = W.orders[ctx.sourceReference]
            if not o or o.cancelled then return false, 'source_terminal' end
            if W.sourceMode == 'down' then error('source down') end
            if W.sourceMode == 'reject' then return false, 'over_capacity' end
            return credit(o)
        end,
        ContractSourceFallback = function(ctx)
            W.calls[#W.calls + 1] = 'fallback:' .. ctx.sourceReference
            if W.sourceHook then W.sourceHook('fallback', ctx) end
            local o = W.orders[ctx.sourceReference]
            if not o or o.cancelled then return false, 'source_terminal' end
            if W.sourceMode == 'down' then error('source down') end
            if W.sourceMode == 'reject' then return false, 'over_capacity' end
            return credit(o)
        end,
        ContractSourceCancel = function(ctx)
            local o = W.orders[ctx.sourceReference]
            if not o or o.delivered then return false, 'invalid_state' end
            o.cancelled = true; return true
        end,
        ContractSourceEvent = function(ctx) W.calls[#W.calls + 1] = 'event:' .. ctx.event end,
    }
    local providerExports = {
        Eligible = function(cid, view)
            if W.providerBroken then error('provider down') end
            if not W.eligibleCids[cid] then return false, 'no_licence' end
            return true
        end,
        OnEvent = function(ref, cid, event, reason) W.providerEvents[#W.providerEvents + 1] = cid .. ':' .. event end,
    }
    local function call(resource, name, ...)
        local fn = (resource == 'cm-commercial-ownership' and sourceExports[name]) or (resource == 'cm-trucking' and providerExports[name])
        if not fn then return false, 'resource_unavailable' end
        local res = table.pack(pcall(fn, ...))
        if not res[1] then return false, 'call_failed' end
        return true, res[2], res[3]
    end
    local core = Core.New({ cfg = Config, store = S, now = function() return W.clock end, call = call,
        encode = function(t) local n = 0 for k, v in pairs(t) do n = n + #tostring(k) + #tostring(v) end return string.rep('x', n) end,
        rand = (function() local i = 0 return function(a, b) i = i + 1 return a + (i * 7) % (b - a) end end)() })
    W.S, W.core = S, core
    assert(core:RegisterProvider('cm-trucking', 'trucking', { types = { 'business_supply', 'bulk_material_transport' },
        eligibilityExport = 'Eligible', eventExport = 'OnEvent', disconnectPolicy = opts.disconnectPolicy or 'grace', graceSeconds = 120 }))
    return core
end

local SRC = 'cm-commercial-ownership'
local function order(ref, units) W.orders[ref] = { units = units or 50 } return ref end
local function publish(core, ref, extra)
    order(ref)
    local d = { contractType = 'business_supply', sourceReference = ref, title = 'Supply delivery', cargoClass = 'general', metadata = { units = 50 } }
    for k, v in pairs(extra or {}) do d[k] = v end
    return core:CreateContract(SRC, d)
end
local function claim(core, ref, cid) return core:Claim('cm-trucking', ref, cid or '101') end
local function advance(s) W.clock = W.clock + s end

-- =============================================================== SOURCE
do
    local core = world()
    local ok, r = publish(core, 'SO-1')
    check('SOURCE trusted source creates contract', ok and r.reference:match('^CT%-') and r.status == 'available')
    check('SOURCE untrusted resource rejected', select(2, core:CreateContract('cm-evil', { contractType = 'business_supply', sourceReference = 'x' })) == 'untrusted_source')
    check('SOURCE type not allowed for this source rejected', select(2, core:CreateContract(SRC, { contractType = 'courier_delivery', sourceReference = 'x' })) == 'unsupported_type')
    check('SOURCE unknown type rejected', select(2, core:CreateContract(SRC, { contractType = 'nope', sourceReference = 'x' })) == 'unsupported_type')
    check('SOURCE invalid reference rejected', select(2, core:CreateContract(SRC, { contractType = 'business_supply', sourceReference = 'bad ref!' })) == 'invalid_source_reference')
    local ok2, r2 = core:CreateContract(SRC, { contractType = 'business_supply', sourceReference = 'SO-1' })
    check('SOURCE duplicate source reference returns existing, no new row', ok2 and r2.existing == true and r2.reference == r.reference and #core.store.listAdmin(nil) == 1)
    check('SOURCE create replay stable', select(2, core:CreateContract(SRC, { contractType = 'business_supply', sourceReference = 'SO-1' })).reference == r.reference)
    check('SOURCE provider type is server-decided', core.store.getByRef(r.reference).provider_type == 'trucking')
    local _, big = publish(core, 'SO-2', { fallbackAfterSeconds = 99999999 })
    check('SOURCE fallback window clamped to type max (45 min)', core.store.getByRef(big.reference).fallback_at - W.clock == 45 * 60)
    local _, small = publish(core, 'SO-3', { fallbackAfterSeconds = 5 })
    check('SOURCE fallback window clamped to type min (20 min)', core.store.getByRef(small.reference).fallback_at - W.clock == 20 * 60)
    check('SOURCE oversized metadata rejected', select(2, core:CreateContract(SRC, { contractType = 'business_supply', sourceReference = 'SO-9', metadata = { a = string.rep('x', 3000) } })) == 'invalid_metadata')
    check('SOURCE broker created no money/item/xp fields', (function() local r0 = core.store.getByRef(r.reference)
        for k in pairs(r0) do if k:find('money') or k:find('item') or k:find('xp') or k:find('reward') then return false end end return true end)())
end

-- ============================================================== PROVIDER
do
    local core = world()
    check('PROVIDER untrusted resource cannot register', select(2, core:RegisterProvider('cm-evil', 'trucking', { types = { 'business_supply' } })) == 'untrusted_provider')
    check('PROVIDER trusted resource wrong provider type rejected', select(2, core:RegisterProvider('cm-courier', 'trucking', { types = { 'business_supply' } })) == 'untrusted_provider')
    check('PROVIDER unsupported type rejected', select(2, core:RegisterProvider('cm-trucking', 'trucking', { types = { 'courier_delivery' } })) == 'unsupported_type')
    check('PROVIDER supported types registered', core.providers.trucking.types.business_supply == true)
    publish(core, 'SO-1')
    local ok, list = core:ListAvailable('cm-trucking', 'trucking', {}, '101')
    check('PROVIDER lists available contracts (safe view)', ok and #list == 1 and list[1].sourceReference == nil and list[1].reference ~= nil)
    check('PROVIDER wrong resource cannot list', select(2, core:ListAvailable('cm-garbage', 'trucking', {})) == 'untrusted_provider')
    check('PROVIDER other resource cannot claim', select(2, core:Claim('cm-garbage', list[1].reference, '101')) == 'forbidden')
    check('PROVIDER filter by cargo class', #select(2, core:ListAvailable('cm-trucking', 'trucking', { cargoClass = 'fuel' })) == 0)
end

-- ============================================================ ELIGIBILITY
do
    local core = world()
    local _, c = publish(core, 'SO-1')
    check('ELIGIBILITY eligible worker claims', claim(core, c.reference, '101') == true)
    local _, c2 = publish(core, 'SO-2')
    local ok, why = claim(core, c2.reference, '999')
    check('ELIGIBILITY rejected worker (provider reason surfaced)', ok == false and why == 'no_licence')
    W.providerBroken = true
    local ok3, why3 = claim(core, c2.reference, '102')
    check('ELIGIBILITY provider callback failure fails closed', ok3 == false and why3 == 'provider_error')
    check('ELIGIBILITY rejected claim leaves contract available', core.store.getByRef(c2.reference).status == 'available')
end

-- ============================================================= CLAIM RACE
do
    local core = world()
    local _, c = publish(core, 'SO-1')
    -- two workers race: the second eligibility check runs after the first claim committed
    local first = claim(core, c.reference, '101')
    local ok2, why2 = claim(core, c.reference, '102')
    check('RACE only one worker wins', first == true and ok2 == false and why2 == 'already_claimed')
    check('RACE exactly one active claimant', core.store.getByRef(c.reference).claimed_character_id == '101')

    -- true interleave: worker 2's eligibility callback runs while worker 1 commits
    local core2 = world(); local _, d = publish(core2, 'SO-9')
    local def = core2.providers.trucking
    core2.call = (function(orig) return function(res, name, cid, view)
        if name == 'Eligible' and cid == '102' then claim(core2, d.reference, '101') end -- worker 1 lands mid-check
        return orig(res, name, cid, view) end end)(core2.call)
    local ok, why = core2:Claim('cm-trucking', d.reference, '102')
    check('RACE claim committed during peer eligibility check -> CAS rejects loser', ok == false and why == 'already_claimed' and core2.store.getByRef(d.reference).claimed_character_id == '101')
    local dup, view, replay = claim(core, c.reference, '101')
    check('RACE duplicate claim by same worker is a replay', dup == true and replay == true)
    check('RACE claim of a stale/terminal contract rejected', (function()
        advance(60 * 60); core:Sweep(); local ok0, why0 = claim(core, c.reference, '103'); return ok0 == false end)())
    local core3 = world(); local _, e1 = publish(core3, 'SO-A'); local _, e2 = publish(core3, 'SO-B')
    claim(core3, e1.reference, '101')
    check('RACE worker limited to one active contract', select(2, claim(core3, e2.reference, '101')) == 'too_many_claims')
end

-- ================================================================== LEASE
do
    local core = world()
    local _, c = publish(core, 'SO-1')
    claim(core, c.reference, '101')
    advance(899); core:Sweep()
    check('LEASE not expired before 900s', core.store.getByRef(c.reference).status == 'claimed')
    advance(5); local st = core:Sweep()
    check('LEASE expired claim released', st.released == 1 and core.store.getByRef(c.reference).status == 'available' and core.store.getByRef(c.reference).claimed_character_id == nil)
    check('LEASE contract reappears on the board', #select(2, core:ListAvailable('cm-trucking', 'trucking', {})) == 1)
    check('LEASE original worker no longer authority', select(2, core:MarkActive('cm-trucking', c.reference, '101')) == 'not_claimant')
    check('LEASE second worker can now claim', claim(core, c.reference, '102') == true)
    local core2 = world({ disconnectPolicy = 'release' }); local _, d = publish(core2, 'SO-1'); claim(core2, d.reference, '101')
    core2:ReportWorkerDisconnected('cm-trucking', 'trucking', '101')
    check('LEASE disconnect policy release: immediate', core2.store.getByRef(d.reference).status == 'available')
    local core3 = world({ disconnectPolicy = 'grace' }); local _, g = publish(core3, 'SO-1'); claim(core3, g.reference, '101')
    core3:ReportWorkerDisconnected('cm-trucking', 'trucking', '101')
    check('LEASE disconnect policy grace: still claimed within grace', core3.store.getByRef(g.reference).status == 'claimed' and core3.store.getByRef(g.reference).claim_expires_at == W.clock + 120)
    advance(121); core3:Sweep()
    check('LEASE disconnect grace elapsed -> released', core3.store.getByRef(g.reference).status == 'available')
    local core4 = world(); local _, a = publish(core4, 'SO-1'); claim(core4, a.reference, '101'); core4:MarkActive('cm-trucking', a.reference, '101')
    core4.store.cas(a.reference, { 'active' }, { claim_expires_at = W.clock - 1 }, nil) -- active lease lapsed (worker vanished)
    core4:Sweep()
    check('LEASE active worker that vanished is released after active timeout', core4.store.getByRef(a.reference).status == 'available')
    check('LEASE provider told about lease loss (best effort)', (function() for _, e in ipairs(W.providerEvents) do if e == '101:lease_expired' then return true end end return false end)())
end

-- =================================================================== STATE
do
    local core = world()
    local _, c = publish(core, 'SO-1')
    check('STATE new contract is available', core.store.getByRef(c.reference).status == 'available')
    check('STATE cannot activate unclaimed', select(2, core:MarkActive('cm-trucking', c.reference, '101')) == 'not_claimant')
    check('STATE cannot complete unclaimed', select(2, core:Complete('cm-trucking', c.reference, '101')) == 'not_claimant')
    claim(core, c.reference, '101')
    check('STATE cannot complete while only claimed (invalid transition)', select(2, core:Complete('cm-trucking', c.reference, '101')) == 'invalid_state')
    check('STATE claimed -> active', core:MarkActive('cm-trucking', c.reference, '101') == true and core.store.getByRef(c.reference).status == 'active')
    check('STATE active replay is idempotent', select(2, core:MarkActive('cm-trucking', c.reference, '101')).replayed == true)
    local ok, r = core:Fail('cm-trucking', c.reference, '101', 'vehicle_destroyed')
    check('STATE failed worker contract returns to available (no reward)', ok and r.failCount == 1 and core.store.getByRef(c.reference).status == 'available' and W.rewards == 0)
    claim(core, c.reference, '102'); core:Fail('cm-trucking', c.reference, '102'); claim(core, c.reference, '103'); local _, f3 = core:Fail('cm-trucking', c.reference, '103')
    check('STATE too many failures -> fallback due', f3.toFallback == true)
    core:Sweep()
    check('STATE failed-out contract completed by source fallback', core.store.getByRef(c.reference).status == 'completed' and core.store.getByRef(c.reference).completion_mode == 'fallback')
    local _, d = publish(core, 'SO-2')
    check('STATE source cancel', core:Cancel(SRC, 'business_supply', 'SO-2', 'business_cancel') == true and core.store.getByRef(d.reference).status == 'cancelled')
    check('STATE cancel replay idempotent', select(2, core:Cancel(SRC, 'business_supply', 'SO-2')).replayed == true)
    check('STATE cancelled cannot be claimed', claim(core, d.reference, '101') == false)
    check('STATE completed cannot be cancelled', select(2, core:Cancel(SRC, 'business_supply', 'SO-1')) == 'terminal')
    check('STATE untrusted cancel rejected', select(2, core:Cancel('cm-evil', 'business_supply', 'SO-2')) == 'untrusted_source')
    local _, e = publish(core, 'SO-3'); claim(core, e.reference, '101')
    check('STATE release by claimant', core:Release('cm-trucking', e.reference, '101') == true and core.store.getByRef(e.reference).status == 'available')
    check('STATE release replay idempotent', select(2, core:Release('cm-trucking', e.reference, '101')).replayed == true)
    check('STATE release by non-claimant rejected', (function() claim(core, e.reference, '101'); return select(2, core:Release('cm-trucking', e.reference, '102')) == 'not_claimant' end)())
end

-- ================================================================ FALLBACK
do
    local core = world()
    local _, c = publish(core, 'SO-1')
    advance(29 * 60); core:Sweep()
    check('FALLBACK not before deadline', core.store.getByRef(c.reference).status == 'available' and W.stockCredits == 0)
    advance(61); core:Sweep()
    local row = core.store.getByRef(c.reference)
    check('FALLBACK untouched contract: source applies it, mode fallback', row.status == 'completed' and row.completion_mode == 'fallback' and W.stockCredits == 1 and W.stock == 50)
    check('FALLBACK no provider reward signal / no worker', row.claimed_character_id == nil and W.rewards == 0)
    advance(3600); core:Sweep(); core:Sweep()
    check('FALLBACK exactly once (replayed sweeps are no-ops)', W.stockCredits == 1 and countKind(W.S, 'completed_fallback') == 1 and countTerminal(W.S, row.id) == 1)
    local fc = 0 for _, cl in ipairs(W.calls) do if cl:find('^fallback') then fc = fc + 1 end end
    check('FALLBACK source called once', fc == 1)

    -- released contract still times out
    local core2 = world(); local _, r = publish(core2, 'SO-1'); claim(core2, r.reference, '101'); core2:Release('cm-trucking', r.reference, '101')
    advance(31 * 60); core2:Sweep()
    check('FALLBACK released contract timeout still falls back', core2.store.getByRef(r.reference).completion_mode == 'fallback')
    check('FALLBACK cannot be claimed after deadline', (function() local c3 = world(); local _, x = publish(c3, 'SO-1'); advance(31 * 60); return select(2, claim(c3, x.reference, '101')) == 'fallback_due' end)())

    -- temporary source failure -> retry with backoff, never marked complete
    local core3 = world(); local _, t = publish(core3, 'SO-1')
    W.sourceMode = 'down'; advance(31 * 60); core3:Sweep()
    local tr = core3.store.getByRef(t.reference)
    check('FALLBACK source temporary failure keeps contract in fallback (not complete)', tr.status == 'fallback' and tr.fallback_attempts == 1 and W.stockCredits == 0)
    local calls1 = #W.calls
    core3:Sweep(); core3:Sweep()
    check('FALLBACK retries are throttled (no spam between backoff windows)', #W.calls == calls1)
    advance(61); core3:Sweep()
    check('FALLBACK backoff doubles', core3.store.getByRef(t.reference).fallback_attempts == 2 and core3.store.getByRef(t.reference).fallback_next_at - W.clock == 120)
    W.sourceMode = 'ok'; advance(121); core3:Sweep()
    local td = core3.store.getByRef(t.reference)
    check('FALLBACK retry succeeds once source recovers', td.status == 'completed' and td.completion_mode == 'fallback' and W.stockCredits == 1)
    check('FALLBACK rejected-by-source also retries', (function()
        local c4 = world(); local _, y = publish(c4, 'SO-1'); W.sourceMode = 'reject'; advance(31 * 60); c4:Sweep()
        return c4.store.getByRef(y.reference).status == 'fallback' end)())
    -- source says the order is already over
    local core5 = world(); local _, z = publish(core5, 'SO-1'); W.orders['SO-1'].cancelled = true; advance(31 * 60); core5:Sweep()
    check('FALLBACK source terminal -> contract cancelled, nothing applied', core5.store.getByRef(z.reference).status == 'cancelled' and W.stockCredits == 0)
    -- worker active at the deadline gets a bounded grace, then fallback fires
    local core6 = world(); local _, w = publish(core6, 'SO-1'); claim(core6, w.reference, '101'); core6:MarkActive('cm-trucking', w.reference, '101')
    advance(31 * 60); core6:Sweep()
    check('FALLBACK active worker deferred (not stripped of the job at the boundary)', core6.store.getByRef(w.reference).status == 'active' and core6.store.getByRef(w.reference).fallback_deferrals == 1)
    advance(11 * 60); core6:Sweep(); advance(11 * 60); core6:Sweep()
    check('FALLBACK deferrals bounded: then source fallback, worker not rewarded', core6.store.getByRef(w.reference).completion_mode == 'fallback' and W.rewards == 0)
    local _, why = core6:Complete('cm-trucking', w.reference, '101')
    check('FALLBACK late player completion rejected, no reward signal', why == 'completed_by_fallback' and W.stockCredits == 1)
end

-- ======================================= PLAYER VS FALLBACK RACE (ORDER A/B/C)
do
    -- ORDER A: player path end to end
    local core = world()
    local _, a = publish(core, 'ORDER-A')
    check('ORDER A: provider sees the contract', #select(2, core:ListAvailable('cm-trucking', 'trucking', {}, '101')) == 1)
    check('ORDER A: trucker claims', claim(core, a.reference, '101') == true)
    check('ORDER A: trucking marks active', core:MarkActive('cm-trucking', a.reference, '101') == true)
    local ok, res = core:Complete('cm-trucking', a.reference, '101')
    local row = core.store.getByRef(a.reference)
    check('ORDER A: player completion applies stock once, mode player', ok and res.mode == 'player' and row.completion_mode == 'player' and W.stockCredits == 1 and W.stock == 50)
    check('ORDER A: provider told it may reward exactly this once', res.rewardable == true)
    local ok2, res2 = core:Complete('cm-trucking', a.reference, '101')
    check('ORDER A: completion replay is safe and NOT rewardable again', ok2 and res2.replayed == true and res2.rewardable == false and W.stockCredits == 1)
    advance(3600); core:Sweep()
    check('ORDER A: fallback never fires after player completion', (function() for _, cl in ipairs(W.calls) do if cl:find('^fallback') then return false end end return true end)() and row.completion_mode == 'player')
    check('ORDER A: single terminal event', countTerminal(W.S, row.id) == 1 and countKind(W.S, 'completed_player') == 1)

    -- ORDER B: nobody works it
    local coreB = world()
    local _, b = publish(coreB, 'ORDER-B')
    advance(46 * 60); coreB:Sweep()
    local rb = coreB.store.getByRef(b.reference)
    check('ORDER B: nobody completes -> source fallback, mode fallback', rb.completion_mode == 'fallback' and rb.status == 'completed' and W.stockCredits == 1)
    check('ORDER B: no player reward / no worker / no provider callbacks', W.rewards == 0 and rb.claimed_character_id == nil and #W.providerEvents == 0)
    local fcalls = 0 for _, cl in ipairs(W.calls) do if cl == 'fallback:ORDER-B' then fcalls = fcalls + 1 end end
    check('ORDER B: source fallback called exactly once', fcalls == 1)

    -- ORDER C1: player completion in flight at the boundary -> player wins, fallback skips
    local coreC = world()
    local _, c = publish(coreC, 'ORDER-C')
    claim(coreC, c.reference, '101'); coreC:MarkActive('cm-trucking', c.reference, '101')
    advance(31 * 60)
    W.sourceHook = function(kind) if kind == 'complete' then coreC:Sweep() end end -- deadline sweep fires while completing
    local okC, resC = coreC:Complete('cm-trucking', c.reference, '101')
    local rc = coreC.store.getByRef(c.reference)
    check('ORDER C (player first): exactly one path wins - player', okC and resC.rewardable == true and rc.completion_mode == 'player')
    check('ORDER C (player first): fallback no-op, service applied once', W.stockCredits == 1 and countTerminal(W.S, rc.id) == 1)
    W.sourceHook = nil

    -- ORDER C2: fallback wins the race, then the player's completion arrives
    local coreD = world()
    local _, d = publish(coreD, 'ORDER-D')
    claim(coreD, d.reference, '101'); coreD:MarkActive('cm-trucking', d.reference, '101')
    advance(31 * 60); coreD:Sweep(); advance(11 * 60); coreD:Sweep(); advance(11 * 60)
    local late
    W.sourceHook = function(kind) if kind == 'fallback' then late = { coreD:Complete('cm-trucking', d.reference, '101') } end end -- player arrives mid-fallback
    coreD:Sweep()
    local rd = coreD.store.getByRef(d.reference)
    check('ORDER C (fallback first): player completion mid-fallback rejected', late and late[1] == false and late[2] == 'fallback_in_progress')
    check('ORDER C (fallback first): service applied once, mode fallback, no reward', rd.completion_mode == 'fallback' and W.stockCredits == 1 and countTerminal(W.S, rd.id) == 1)
    W.sourceHook = nil
    check('ORDER C: terminal contract never reopens', select(2, coreD:Claim('cm-trucking', d.reference, '102')) == 'terminal')

    -- player completion rejected by source (retryable) keeps worker's contract
    local coreE = world(); local _, e = publish(coreE, 'ORDER-E'); claim(coreE, e.reference, '101'); coreE:MarkActive('cm-trucking', e.reference, '101')
    W.sourceMode = 'reject'
    local okE, whyE = coreE:Complete('cm-trucking', e.reference, '101')
    check('ORDER E: source rejection leaves contract active & retryable, nothing paid', okE == false and whyE == 'over_capacity' and coreE.store.getByRef(e.reference).status == 'active' and W.stockCredits == 0)
    W.sourceMode = 'ok'
    check('ORDER E: retry after source recovers succeeds once', select(1, coreE:Complete('cm-trucking', e.reference, '101')) == true and W.stockCredits == 1)
    W.sourceMode = 'down'; local coreF = world(); W.sourceMode = 'down'
    local _, f = publish(coreF, 'ORDER-F'); claim(coreF, f.reference, '101'); coreF:MarkActive('cm-trucking', f.reference, '101')
    local okF, whyF = coreF:Complete('cm-trucking', f.reference, '101')
    check('ORDER F: source down -> not completed, back to active', okF == false and whyF == 'source_unavailable' and coreF.store.getByRef(f.reference).status == 'active')
    W.orders['ORDER-F'].cancelled = true; W.sourceMode = 'ok'
    check('ORDER G: source terminal during completion -> contract cancelled, worker not rewarded', select(2, coreF:Complete('cm-trucking', f.reference, '101')) == 'contract_cancelled' and coreF.store.getByRef(f.reference).status == 'cancelled')
end

-- ================================================================== RESTART
do
    local core = world()
    local _, av = publish(core, 'SO-AV'); local _, cl = publish(core, 'SO-CL'); local _, ex = publish(core, 'SO-EX'); local _, dn = publish(core, 'SO-DN')
    claim(core, cl.reference, '101'); claim(core, ex.reference, '102')
    local _, p = publish(core, 'SO-PL'); claim(core, p.reference, '103'); core:MarkActive('cm-trucking', p.reference, '103'); core:Complete('cm-trucking', p.reference, '103')
    local store = core.store
    advance(1000) -- broker is down: leases lapse (900s) before any fallback deadline (30 min)
    -- "restart": a new core instance over the same persisted rows, no provider registered yet
    local core2 = Core.New({ cfg = Config, store = store, now = function() return W.clock end, call = core.call })
    local st = core2:Sweep()
    check('RESTART expired claims release', store.getByRef(cl.reference).status == 'available' and store.getByRef(ex.reference).status == 'available')
    check('RESTART completed stays terminal and untouched', store.getByRef(p.reference).status == 'completed' and store.getByRef(p.reference).completion_mode == 'player')
    check('RESTART available contract not duplicated', #(function() local n = {} for _, r in pairs(store.rows) do if r.source_reference == 'SO-AV' then n[#n + 1] = r end end return n end)() == 1)
    advance(60 * 60); core2:Sweep(); core2:Sweep()
    check('RESTART fallback due while offline processed exactly once', store.getByRef(av.reference).completion_mode == 'fallback' and W.stockCredits == 5 and countKind(W.S, 'completed_fallback') == 4)
    check('RESTART completed contract never reopened or double completed', store.getByRef(p.reference).completion_mode == 'player' and countTerminal(W.S, store.getByRef(p.reference).id) == 1)
    -- stuck completing (crash between source call and terminal write)
    local core3 = world(); local _, s = publish(core3, 'SO-ST'); claim(core3, s.reference, '101'); core3:MarkActive('cm-trucking', s.reference, '101')
    core3.store.cas(s.reference, { 'active' }, { status = 'completing', completing_at = W.clock }, nil)
    core3:Sweep()
    check('RESTART fresh completing left alone', core3.store.getByRef(s.reference).status == 'completing')
    advance(130); core3:Sweep()
    local rs = core3.store.getByRef(s.reference)
    check('RESTART stuck completing replayed against idempotent source: once', rs.status == 'completed' and rs.completion_mode == 'player' and W.stockCredits == 1)
    advance(10); core3:Sweep()
    check('RESTART stuck-completing recovery runs once', W.stockCredits == 1 and countTerminal(W.S, rs.id) == 1)
end

-- ============================================================= IDEMPOTENCY
do
    local core = world()
    local _, c = publish(core, 'SO-1')
    local again = select(2, core:CreateContract(SRC, { contractType = 'business_supply', sourceReference = 'SO-1' }))
    check('IDEMPOTENT create replay returns same contract', again.existing == true and again.reference == c.reference)
    claim(core, c.reference, '101'); core:MarkActive('cm-trucking', c.reference, '101')
    core:Complete('cm-trucking', c.reference, '101'); core:Complete('cm-trucking', c.reference, '101'); core:Complete('cm-trucking', c.reference, '101')
    check('IDEMPOTENT completion replay: stock once', W.stockCredits == 1)
    check('IDEMPOTENT replay after terminal create reports terminal state', select(2, core:CreateContract(SRC, { contractType = 'business_supply', sourceReference = 'SO-1' })).status == 'completed')
    local core2 = world(); local _, d = publish(core2, 'SO-1'); advance(46 * 60)
    for _ = 1, 3 do core2:Sweep() end
    check('IDEMPOTENT fallback replay: stock once', W.stockCredits == 1)
    local core3 = world(); local _, e = publish(core3, 'SO-1'); claim(core3, e.reference, '101')
    for _ = 1, 3 do core3:Release('cm-trucking', e.reference, '101') end
    check('IDEMPOTENT release replay stable', core3.store.getByRef(e.reference).status == 'available' and countKind(W.S, 'released') == 1)
end

-- ================================================================ SECURITY
do
    local core = world()
    local _, a = publish(core, 'SO-A'); local _, b = publish(core, 'SO-B')
    claim(core, a.reference, '101'); core:MarkActive('cm-trucking', a.reference, '101')
    check('SECURITY forged worker CID cannot complete', select(2, core:Complete('cm-trucking', a.reference, '102')) == 'not_claimant' and W.stockCredits == 0)
    check('SECURITY forged worker CID cannot release', select(2, core:Release('cm-trucking', a.reference, '102')) == 'not_claimant')
    check('SECURITY forged worker CID cannot fail someone elses job', select(2, core:Fail('cm-trucking', a.reference, '102')) == 'not_claimant')
    check('SECURITY wrong provider resource cannot complete', select(2, core:Complete('cm-courier', a.reference, '101')) == 'forbidden')
    claim(core, b.reference, '102'); core:MarkActive('cm-trucking', b.reference, '102')
    check('SECURITY cross-contract completion: worker 102 cannot finish contract A', select(2, core:Complete('cm-trucking', a.reference, '102')) == 'not_claimant')
    check('SECURITY wrong source cannot cancel other sources contract', select(2, core:Cancel('cm-evil', 'business_supply', 'SO-A')) == 'untrusted_source')
    check('SECURITY source cannot create outside its types', select(2, core:CreateContract(SRC, { contractType = 'mechanic_request', sourceReference = 'Z' })) == 'unsupported_type')
    check('SECURITY source reference never exposed to providers', (function() local _, l = core:ListAvailable('cm-trucking', 'trucking', {}, '101'); for _, v in ipairs(l) do if v.sourceReference or v.source_reference then return false end end return true end)())
    check('SECURITY admin cancel needs source permission', (function()
        local _, x = publish(core, 'SO-X'); W.orders['SO-X'].delivered = true
        return select(2, core:AdminCancel(x.reference, 'test')) == 'invalid_state' and core.store.getByRef(x.reference).status == 'available' end)())
    local _, y = publish(core, 'SO-Y')
    check('SECURITY admin cancel when source permits', core:AdminCancel(y.reference, 'test') == true and core.store.getByRef(y.reference).status == 'cancelled' and W.orders['SO-Y'].cancelled == true)
    check('SECURITY admin release stale claim', core:AdminRelease(a.reference, 'stale') == true and core.store.getByRef(a.reference).status == 'available')
    check('SECURITY admin inspect shows timeline', (function() local ok, d = core:AdminInspect(a.reference); return ok and #d.events >= 3 end)())
    check('SECURITY broker never calls money/inventory/xp exports', (function() for _, cl in ipairs(W.calls) do if cl:find('money') or cl:find('item') or cl:find('xp') then return false end end return true end)())
end

print(('\ncm-contracts self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
