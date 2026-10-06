-- Deterministic local self-test for cm-mechanic (no FiveM, no database).
--   lua tests/selftest.lua        (run from resources/[core]/cm-mechanic)
--
-- REAL code under test:   cm-mechanic core + pricing + config, cm-phone services core + phone config (catalogue/validation),
--                         cm-contracts broker core + contracts config (allowlists, mechanic_request type).
-- TEST DOUBLES (labelled): fake in-memory stores (mechanic + broker; same CAS/UNIQUE semantics as the SQL stores),
--                         cm-billing (the real one needs MySQL/FiveM; this mimics CreateInvoice idempotency, provider rules, status,
--                         void and business-balance settlement), cm-commercial-ownership (owner/employee/permission lookups),
--                         cm-vehicles (identity, access, condition, ServiceVehicle). Their behaviour is asserted in the checks that rely on it.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local core = here .. '/..'

CMPhone = {}
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
dofile(core .. '/cm-phone/config.lua')
dofile(core .. '/cm-phone/server/services_core.lua')
CMContracts = {}
dofile(core .. '/cm-contracts/config.lua')
dofile(core .. '/cm-contracts/server/core.lua')
CMMechanic = {}
dofile(here .. '/config.lua')
dofile(here .. '/server/pricing.lua')
dofile(here .. '/server/core.lua')

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

-- --------------------------------------------------------------- tiny serializer (stands in for json)
local function ser(v)
    local t = type(v)
    if t == 'table' then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local o = {}
        for _, k in ipairs(keys) do o[#o + 1] = '[' .. ser(k) .. ']=' .. ser(v[k]) end
        return '{' .. table.concat(o, ',') .. '}'
    elseif t == 'string' then return string.format('%q', v)
    else return tostring(v) end
end
local function deser(s) local f = load('return ' .. s); return f and f() or nil end
local function deepcopy(t) if type(t) ~= 'table' then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end

-- -------------------------------------------------------- fake broker store (mirrors cm-contracts/tests/selftest.lua)
local function newBrokerStore()
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
    function S.listAdmin(status, pt, limit) local o = {} for _, r in pairs(rows) do o[#o + 1] = copy(r) end return o end
    return S
end

-- --------------------------------------------------------------- fake mechanic store (same semantics as server/store.lua)
local function newMechStore(W)
    local S = { reqs = {}, wos = {}, events = {} }
    local nextId = 0
    local function copy(r) if not r then return nil end local c = {} for k, v in pairs(r) do c[k] = v end return c end
    local OPENWO = { assigned = true, diagnosing = true, quoted = true, awaiting_payment = true, servicing = true }
    local function apply(r, patch) for k, v in pairs(patch) do if v == false then r[k] = nil else r[k] = v end end end
    local function inList(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
    function S.reqInsert(r)
        for _, x in ipairs(S.reqs) do if r.active_key and x.active_key == r.active_key then return nil, 'duplicate_active' end end
        nextId = nextId + 1; local c = copy(r); c.id = nextId; S.reqs[#S.reqs + 1] = c; return nextId
    end
    local function findReq(f) for _, x in ipairs(S.reqs) do if f(x) then return x end end end
    function S.reqGetByRef(ref) return copy(findReq(function(x) return x.reference == ref end)) end
    function S.reqGetByContract(ref) return copy(findReq(function(x) return x.contract_ref == ref end)) end
    function S.reqOpenByCustomer(cid) return copy(findReq(function(x) return x.active_key == cid and (x.status == 'open' or x.status == 'assigned') end)) end
    function S.reqLatestByCustomer(cid) local last; for _, x in ipairs(S.reqs) do if x.customer_cid == cid then last = x end end return copy(last) end
    function S.reqListOpen() local o = {} for _, x in ipairs(S.reqs) do if x.status == 'open' or x.status == 'assigned' then o[#o + 1] = copy(x) end end return o end
    function S.reqCas(ref, from, patch)
        local r = findReq(function(x) return x.reference == ref end)
        if not r or not inList(from, r.status) then return 0 end
        apply(r, patch); return 1
    end
    function S.woInsert(w)
        for _, x in ipairs(S.wos) do if w.active_key and x.active_key == w.active_key then return nil, 'duplicate_active' end end
        nextId = nextId + 1; local c = copy(w); c.id = nextId; S.wos[#S.wos + 1] = c; return nextId
    end
    local function findWo(f) for _, x in ipairs(S.wos) do if f(x) then return x end end end
    function S.woGetByRef(ref) return copy(findWo(function(x) return x.reference == ref end)) end
    function S.woActiveByRequest(ref) return copy(findWo(function(x) return x.active_key == ref end)) end
    function S.woActiveByMechanic(cid) local last; for _, x in ipairs(S.wos) do if x.mechanic_cid == cid and OPENWO[x.state] then last = x end end return copy(last) end
    function S.woActiveByCustomer(cid, state) local last; for _, x in ipairs(S.wos) do if x.customer_cid == cid and (state and x.state == state or (not state and OPENWO[x.state])) then last = x end end return copy(last) end
    function S.woListOpen() local o = {} for _, x in ipairs(S.wos) do if OPENWO[x.state] then o[#o + 1] = copy(x) end end return o end
    function S.woCas(ref, from, patch, where)
        local r = findWo(function(x) return x.reference == ref end)
        if not r or not inList(from, r.state) then return 0 end
        if where and where.commit_state and r.commit_state ~= where.commit_state then return 0 end
        apply(r, patch); return 1
    end
    function S.eventInsert(e)
        if e.key then for _, x in ipairs(S.events) do if x.key == e.key then return false end end end
        S.events[#S.events + 1] = copy(e); return true
    end
    function S.eventList(ref) local o = {} for _, e in ipairs(S.events) do if e.request_ref == ref or e.work_ref == ref then o[#o + 1] = e end end return o end
    function S.countEvents(kind, workRef) local n = 0 for _, e in ipairs(S.events) do if e.kind == kind and (not workRef or e.work_ref == workRef) then n = n + 1 end end return n end
    return S
end

-- ------------------------------------------------------------------------------ the world
local W
local function newWorld(opts)
    opts = opts or {}
    W = { now = 1000000, online = {}, pos = {}, dead = {}, veh = {}, netToVeh = {}, invoices = {}, invoiceByKey = {}, balances = {}, customerMoney = { ['101'] = 100000, ['102'] = 100000 },
        applied = {}, applyFail = 0, notes = {}, audits = {}, pushes = {}, brokerDown = false, phoneLog = {}, rateBlock = false, nextInv = 0 }
    local cfg = deepcopy(CMMechanic.Config)
    cfg.Shops = {
        { id = 'main', label = 'Main Mechanic', roadside = true },                                      -- no location: workshop services unavailable
        { id = 'bay', label = 'Bay Shop', roadside = true, location = { x = 1000.0, y = 1000.0, z = 30.0, radius = 40.0 } },
        { id = 'other', label = 'Other Mechanic', roadside = true },
        { id = 'noroad', label = 'No Roadside', roadside = false },
    }
    W.cfg = cfg

    -- characters: customers 101/102, mechanics 201 (main, all perms), 202 (main, no mechanic perms), 203 (main, accept only), 301 (other), 401 (bay)
    local function addChar(cid, src, x, y, z) W.online[cid] = src; W.pos[src] = { x = x, y = y, z = z or 30.0, bucket = 0 } end
    addChar('101', 1101, 100.0, 100.0); addChar('102', 1102, 500.0, 500.0)
    addChar('201', 2201, 103.0, 100.0); addChar('202', 2202, 103.0, 100.0); addChar('203', 2203, 103.0, 100.0)
    addChar('301', 3301, 103.0, 100.0); addChar('401', 4401, 1001.0, 1000.0)
    local ALL = { 'mechanic.accept_requests', 'mechanic.create_quote', 'mechanic.service_vehicle', 'mechanic.complete_work', 'mechanic.manage_services' }
    local function set(list) local s = {} for _, p in ipairs(list) do s[p] = true end return s end
    W.biz = {
        ['mechanic:main'] = { owned = true, owner = '500', label = 'Main Mechanic', staff = { ['201'] = set(ALL), ['202'] = set({}), ['203'] = set({ 'mechanic.accept_requests' }) } },
        ['mechanic:bay'] = { owned = true, owner = '501', label = 'Bay Shop', staff = { ['401'] = set(ALL) } },
        ['mechanic:other'] = { owned = true, owner = '600', label = 'Other Mechanic', staff = { ['301'] = set(ALL) } },
        ['mechanic:noroad'] = { owned = true, owner = '601', label = 'No Roadside', staff = { ['301'] = set(ALL) } },
    }
    if opts.unowned then for _, b in pairs(W.biz) do b.owned = false end end
    for k in pairs(W.biz) do W.balances[k] = 0 end

    -- vehicles (cm-vehicles double): 7001 owned by customer 101 (net 9001), 7002 owned by 102 (net 9002, far away)
    local function addVeh(id, net, owner, x, y, model, cond)
        W.veh[id] = { id = id, plate = 'PL' .. id, model = model or 'sultan', label = 'Sultan', ownerType = 'character', ownerCharacterId = owner, stored = false, admin = false,
            keys = {}, pos = { x = x, y = y, z = 30.0, bucket = 0 }, netId = net, value = 400000,
            cond = cond or { engine = 400.0, body = 700.0, tank = 1000.0, conditionState = { windowSchema = 2, brokenWindows = { ['0'] = true }, doors = { ['1'] = { damaged = true, broken = false, angle = 0.0 } }, tyres = { ['2'] = { burst = true, onRim = false } }, engineRunning = false, undriveable = true } } }
        W.netToVeh[net] = id
    end
    addVeh(7001, 9001, '101', 101.0, 100.0)
    addVeh(7002, 9002, '102', 501.0, 500.0)

    local mech = newMechStore(W)
    W.mech = mech

    local chars = {
        sourceOf = function(cid) return W.online[tostring(cid)] end,
        position = function(src) local p = W.pos[src]; return p and deepcopy(p) end,
        isDead = function(src) return W.dead[src] == true end,
    }
    local function cidOfSrc(src) for c, s in pairs(W.online) do if s == src then return c end end end
    local vehicles = {
        fromNet = function(netId)
            local id = W.netToVeh[tonumber(netId)]
            if not id then return nil, 'vehicle_not_found' end
            return id
        end,
        get = function(id) local v = W.veh[id]; if not v then return nil end return { id = v.id, plate = v.plate, model = v.model, label = v.label, ownerType = v.ownerType, ownerCharacterId = v.ownerCharacterId, stored = v.stored, admin = v.admin } end,
        position = function(id) local v = W.veh[id]; return v and v.pos and deepcopy(v.pos) or nil end,
        netIdOf = function(id) local v = W.veh[id]; return v and v.netId end,
        condition = function(id) local v = W.veh[id]; if not v then return nil, 'vehicle_not_found' end if v.condPending then return nil, 'condition_pending' end return deepcopy(v.cond) end,
        value = function(model) for _, v in pairs(W.veh) do if v.model == model then return v.value end end return nil end,
        canUse = function(src, id, level)
            local v = W.veh[id]; local cid = cidOfSrc(src)
            if not v or not cid then return false end
            if v.ownerType == 'character' and v.ownerCharacterId == cid then return true end
            if level == 'owner' then return false end
            return v.keys[cid] == true
        end,
        apply = function(id, patch)
            if W.applyFail > 0 then W.applyFail = W.applyFail - 1; return false end
            local v = W.veh[id]; if not v then return false end
            W.applied[#W.applied + 1] = { id = id, patch = deepcopy(patch) }
            if patch.engineHealth then v.cond.engine = patch.engineHealth end
            if patch.bodyHealth then v.cond.body = patch.bodyHealth end
            if patch.tankHealth then v.cond.tank = patch.tankHealth end
            if patch.conditionState then v.cond.conditionState = deepcopy(patch.conditionState) end
            return true
        end,
    }
    local business = {
        get = function(t, i) local b = W.biz[t .. ':' .. i]; if not b then return nil end return { owned = b.owned, label = b.label, balance = W.balances[t .. ':' .. i] } end,
        has = function(t, i, cid, perm)
            local b = W.biz[t .. ':' .. i]; if not b or not b.owned then return false end
            if not perm or not perm:match('^mechanic%.') then return false end
            if b.owner == tostring(cid) then return true end
            return b.staff[tostring(cid)] ~= nil and b.staff[tostring(cid)][perm] == true
        end,
        list = function(cid)
            local o = {}
            for key, b in pairs(W.biz) do
                if b.staff[tostring(cid)] or b.owner == tostring(cid) then local t, i = key:match('^(%w+):(.+)$'); o[#o + 1] = { type = t, id = i, role = 'employee' } end
            end
            table.sort(o, function(a, b2) return a.id < b2.id end)
            return o
        end,
    }
    -- cm-billing double: CreateInvoice idempotency by key, provider rules (business issuer, business destination, owned business,
    -- metadata namespace, amount cap), VoidInvoice only while pending, settlement into the business balance exactly once.
    -- The provider limit comes from the REAL cm-billing config (Config.Providers['cm-mechanic'] + platform ceiling), exactly as billing computes it.
    dofile(core .. '/cm-billing/config.lua')
    local BC = CMBilling.Config
    W.billingLimit = math.min(BC.Providers['cm-mechanic'].maxAmount, BC.HardMaxAmount)
    local billing = {
        limit = function() if W.billingDown then return nil end return W.billingLimit end,
        create = function(d)
            if W.billingDown then return false, 'unavailable' end
            if type(d) ~= 'table' or math.type(d.amount) ~= 'integer' or d.amount < 1 then return false, 'invalid_amount' end
            if d.amount > W.billingLimit then return false, 'amount_exceeds_provider_limit' end
            if d.issuerType ~= 'business' then return false, 'forbidden_issuer_type' end
            if not d.destination or d.destination.type ~= 'business' then return false, 'invalid_destination' end
            local b = W.biz[d.destination.id or '']; if not b or not b.owned then return false, 'destination_unavailable' end
            for k in pairs(d.metadata or {}) do if not k:match('^mechanic%.') then return false, 'invalid_metadata' end end
            if not W.online[d.recipientCharacterId] and not W.allowOfflineRecipient then return false, 'recipient_offline' end
            if d.idempotencyKey and W.invoiceByKey[d.idempotencyKey] then return true, { reference = W.invoiceByKey[d.idempotencyKey], existing = true } end
            W.nextInv = W.nextInv + 1
            local ref = 'INV-' .. W.nextInv
            W.invoices[ref] = { ref = ref, amount = d.amount, status = 'pending', recipient = d.recipientCharacterId, dest = d.destination.id, key = d.idempotencyKey, label = d.label, data = d }
            if d.idempotencyKey then W.invoiceByKey[d.idempotencyKey] = ref end
            return true, { reference = ref }
        end,
        status = function(ref) local i = W.invoices[ref]; return i and i.status or nil end,
        void = function(ref) local i = W.invoices[ref]; if i and i.status == 'pending' then i.status = 'voided'; return true end return false end,
    }
    function W.pay(ref)
        local i = W.invoices[ref]; assert(i and i.status == 'pending', 'invoice not payable')
        if W.customerMoney[i.recipient] < i.amount then return false, 'insufficient_funds' end
        W.customerMoney[i.recipient] = W.customerMoney[i.recipient] - i.amount
        W.balances[i.dest] = W.balances[i.dest] + i.amount
        i.status = 'paid'; return true
    end

    -- broker: the REAL cm-contracts core over the fake store; mechanic exports are routed back into the engine like the real call()
    local engine
    local bstore = newBrokerStore(); W.bstore = bstore
    local handlers = {
        ContractSourceComplete = function(ctx) return engine:SourceComplete(ctx) end,
        ContractSourceFallback = function(ctx) return engine:SourceFallback(ctx) end,
        ContractSourceCancel = function(ctx) return engine:SourceCancel(ctx) end,
        ContractSourceEvent = function(ctx) return engine:SourceEvent(ctx) end,
        ContractEligible = function(cid, view) return engine:Eligible(cid, view) end,
        ContractEvent = function() return true end,
    }
    local function brokerCall(resource, name, ...)
        if resource ~= 'cm-mechanic' then return false, 'resource_unavailable' end
        if W.mechanicDown then return false, 'resource_unavailable' end
        local h = handlers[name]; if not h then return false, 'no_export' end
        local r = table.pack(pcall(h, ...)); if not r[1] then return false, 'call_failed' end
        return true, r[2], r[3]
    end
    local broker = CMContracts.Core.New({ cfg = CMContracts.Config, store = bstore, now = function() return W.now end, call = brokerCall, encode = ser, rand = math.random })
    W.broker = broker
    local function brokerCallOK(fn, ...) if W.brokerDown then return false, 'resource_unavailable' end return fn(...) end
    local contracts = {
        create = function(d) return brokerCallOK(function() return broker:CreateContract('cm-mechanic', d) end) end,
        cancel = function(t, ref, why) return brokerCallOK(function() return broker:Cancel('cm-mechanic', t, ref, why) end) end,
        get = function(t, ref) return brokerCallOK(function() return broker:GetSourceContract('cm-mechanic', t, ref) end) end,
        claim = function(ref, cid, o) return brokerCallOK(function() return broker:Claim('cm-mechanic', ref, cid, o) end) end,
        active = function(ref, cid) return brokerCallOK(function() return broker:MarkActive('cm-mechanic', ref, cid) end) end,
        complete = function(ref, cid, o) return brokerCallOK(function() return broker:Complete('cm-mechanic', ref, cid, o) end) end,
        release = function(ref, cid, why) return brokerCallOK(function() return broker:Release('cm-mechanic', ref, cid, why) end) end,
        list = function(f, cid) return brokerCallOK(function() return broker:ListAvailable('cm-mechanic', 'mechanic', f, cid) end) end,
        disconnected = function(cid) return brokerCallOK(function() return broker:ReportWorkerDisconnected('cm-mechanic', 'mechanic', cid) end) end,
    }
    local okReg, regWhy = broker:RegisterProvider('cm-mechanic', 'mechanic', { types = { cfg.ContractType }, eligibilityExport = 'ContractEligible', eventExport = 'ContractEvent',
        disconnectPolicy = 'grace', graceSeconds = 120, leaseSeconds = 600 })
    W.registered = okReg == true

    engine = CMMechanic.Core.New({
        cfg = cfg, store = mech, now = function() return W.now end, rand = math.random, encode = ser, decode = deser,
        clean = function(s, max) if type(s) ~= 'string' then return nil end s = s:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''); if s == '' then return nil end return s:sub(1, max) end,
        chars = chars, vehicles = vehicles, business = business, billing = billing, contracts = contracts,
        notify = function(cid, kind, payload) W.notes[#W.notes + 1] = { cid = cid, kind = kind, payload = payload }; if kind == 'phone' then W.pushes[#W.pushes + 1] = { cid = cid, view = payload } end end,
        audit = function(kind, detail) W.audits[#W.audits + 1] = { kind = kind, detail = detail } end,
        rate = function() return not W.rateBlock end,
        log = function(level, msg) W.lastError = msg end,
    })
    W.engine = engine

    -- cm-phone: the REAL services core + REAL phone config; the adapter calls the engine through the same export shape (cm-phone-only guard).
    local phoneHandlers = {
        PhoneServiceCreate = function(cid, service, fields, ctx) return engine:CreateRequest(cid, fields, ctx) end,
        PhoneServiceStatus = function(cid) return engine:RequestStatus(cid) end,
        PhoneServiceCancel = function(cid, service, ref) return engine:CancelRequest(cid, ref) end,
        PhoneServiceAvailability = function() return engine:Availability() end,
    }
    W.phoneStarted = { ['cm-mechanic'] = true }
    local function phoneCall(resource, name, ...)
        if not W.phoneStarted[resource] then return false, 'resource_unavailable' end
        local h = phoneHandlers[name]; if not h then return false, 'no_export' end
        local r = table.pack(pcall(h, ...)); if not r[1] then return false, 'call_failed' end
        return true, r[2], r[3]
    end
    W.phone = CMPhone.ServicesCore.New({ cfg = CMPhone.Config, call = phoneCall, started = function(r) return W.phoneStarted[r] == true end, now = function() return W.now end,
        rateLimit = function() return true end, position = function(src) local p = W.pos[src]; return p and deepcopy(p) or nil end, isDead = function(src) return W.dead[src] == true end,
        emit = function(cid, ev, payload) W.phoneLog[#W.phoneLog + 1] = { cid = cid, payload = payload }; return true end, audit = function() end,
        cleanText = function(v, max) if type(v) ~= 'string' then return nil end v = v:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''); if v == '' then return nil end return v:sub(1, max) end })
    W.phoneRegistered = W.phone:RegisterAdapter('cm-mechanic', 'mechanic', { create = 'PhoneServiceCreate', status = 'PhoneServiceStatus', cancel = 'PhoneServiceCancel', availability = 'PhoneServiceAvailability' })
    return W
end

-- ------------------------------------------------------------------------------- flow helpers
local function request(cid, service, details)
    local src = W.online[cid]
    return W.phone:Request(src, cid, 'mechanic', { service = service or 'repair', details = details })
end
local function reqRow(ref) return W.mech.reqGetByRef(ref) end
local function woOf(ref) return W.mech.woGetByRef(ref) end
local function board(cid) local ok, b = W.engine:Board(cid); return ok, b end
local function claimFirst(cid, businessId)
    local ok, b = board(cid); if not ok or not b.requests[1] then return false, b end
    return W.engine:Claim(cid, b.requests[1].contract, businessId)
end
local function sweep() return W.engine:Reconcile() end
local function advance(s) W.now = W.now + s end
local function diagnose(mcid, wo, net) return W.engine:BeginDiagnosis(mcid, wo, net or 9001) end

-- Request through to a quoted order. Returns the work-order reference and the request reference.
local function toQuoted(service, svcId, mcid)
    mcid = mcid or '201'
    local ok, view = request('101', service or 'repair')
    assert(ok, 'request failed: ' .. tostring(view))
    local okC, wov = claimFirst(mcid)
    assert(okC, 'claim failed: ' .. tostring(wov))
    local okD, d = diagnose(mcid, wov.workOrder)
    assert(okD, 'diagnose failed: ' .. tostring(d))
    local okQ, q = W.engine:CreateQuote(mcid, wov.workOrder, svcId or 'repair_basic', 9001)
    assert(okQ, 'quote failed: ' .. tostring(q))
    return wov.workOrder, view.ref, q
end
local function toPaid(svcId, mcid)
    local wo, ref, q = toQuoted('repair', svcId, mcid)
    local ok = W.engine:RespondQuote('101', true); assert(ok, 'approve failed')
    local w = woOf(wo)
    assert(W.pay(w.invoice_ref), 'pay failed')
    sweep()
    assert(woOf(wo).state == 'servicing', 'not servicing: ' .. tostring(woOf(wo).state))
    return wo, ref, q
end
local function finishService(wo, mcid, net)
    mcid = mcid or '201'
    local ok, s = W.engine:StartService(mcid, wo, net or 9001); if not ok then return false, s end
    advance(60)
    return W.engine:FinishService(mcid, wo, net or 9001)
end

-- ======================================================================================== CONFIG / WIRING
do
    newWorld()
    check('CONFIG phone: mechanic is no longer Coming Soon', CMPhone.Config.Services.Catalog.mechanic.comingSoon == nil)
    check('CONFIG phone: mechanic source allowlist is cm-mechanic', CMPhone.Config.Services.Sources['cm-mechanic'] and CMPhone.Config.Services.Sources['cm-mechanic'].mechanic == true)
    check('CONFIG phone: adapter registers for cm-mechanic', W.phoneRegistered == true)
    check('CONFIG phone: other resources cannot register the mechanic service', select(2, W.phone:RegisterAdapter('cm-taxi', 'mechanic', { create = 'a', status = 'b' })) == 'untrusted_source')
    check('CONFIG phone: enum is diagnostic/repair/body/tires/tuning', (function()
        local o = CMPhone.Config.Services.Catalog.mechanic.fields[1].options; return #o == 5 and o[1] == 'diagnostic' and o[4] == 'tires' and o[5] == 'tuning' end)())
    check('CONFIG contracts: cm-mechanic is an allowlisted SOURCE for mechanic_request', CMContracts.Config.Sources['cm-mechanic'] and CMContracts.Config.Sources['cm-mechanic'].types.mechanic_request == true)
    check('CONFIG contracts: cm-mechanic is an allowlisted PROVIDER (mechanic)', CMContracts.Config.Providers['cm-mechanic'] and CMContracts.Config.Providers['cm-mechanic'].providerTypes.mechanic == true)
    check('CONFIG contracts: provider registration accepted', W.registered == true)
    check('CONFIG contracts: mechanic_request fallback window is 5-15 min (player-first, short)', CMContracts.Config.Types.mechanic_request.fallbackMinMinutes == 5 and CMContracts.Config.Types.mechanic_request.fallbackMaxMinutes == 15)
    check('CONFIG contracts: another resource cannot register as mechanic provider', select(2, W.broker:RegisterProvider('cm-taxi', 'mechanic', { types = { 'mechanic_request' } })) == 'untrusted_provider')
    check('CONFIG perms: every service permission key maps to a mechanic.* permission', (function()
        for _, s in pairs(W.cfg.Services) do if not W.cfg.Permissions[s.permission] then return false end end return true end)())
    check('CONFIG catalogue: tuning is enabled but owned by cm-tuning (never priced or applied here)', W.cfg.Services.tuning_request.enabled ~= false and W.cfg.Services.tuning_request.authority == 'cm-tuning' and W.cfg.Services.tuning_request.parts[1] == nil)
    check('CONFIG catalogue: every enabled repair service max price stays <= the billing provider limit', (function()
        for _, s in pairs(W.cfg.Services) do if s.enabled ~= false and s.maxPrice > W.billingLimit then return false end end return true end)())
    check('CONFIG phone catalogue: hints all have a service suggestion', (function() for h in pairs(W.cfg.Request.hints) do if not W.cfg.HintServices[h] then return false end end return true end)())
end

-- ======================================================================================== PRICING (pure)
do
    local P = CMMechanic.Pricing
    local cfg = CMMechanic.Config
    local full = P.diagnose({ engine = 1000.0, body = 1000.0, tank = 1000.0, conditionState = {} }, cfg)
    check('PRICING healthy vehicle: repair has nothing to repair', select(2, P.quote(cfg, 'repair_basic', full, 400000)) == 'nothing_to_repair')
    local diag = P.diagnose({ engine = 400.0, body = 700.0, tank = 1000.0, conditionState = {} }, cfg)
    local ok, q = P.quote(cfg, 'repair_basic', diag, 400000)
    -- engine missing 600: 1200 + 6*600 + 0.004*400000*0.6 = 1200+3600+960 = 5760; + base 1500 = 7260
    check('PRICING engine formula (base + per-point + value share) + service base', ok and q.amount == 7260, q and q.amount)
    local okB, qb = P.quote(cfg, 'repair_body', diag, 400000)
    -- body missing 300: 900 + 4*300 + 0.003*400000*0.3 = 900+1200+360 = 2460; + base 1000 = 3460
    check('PRICING body formula', okB and qb.amount == 3460, qb and qb.amount)
    local okH, qh = P.quote(cfg, 'repair_basic', diag, 4000000)
    check('PRICING scales with vehicle value (same damage, 10x vehicle costs more)', okH and qh.amount > q.amount)
    local zero = P.diagnose({ engine = 0.0, body = 1000.0, tank = 1000.0, conditionState = {} }, cfg)
    check('PRICING genuine zero health is real damage (max severity), not "unknown"', zero.engine.known == true and zero.engine.missing == 1000 and zero.engine.needed == true)
    local unknown = P.diagnose({ conditionState = {} }, cfg)
    check('PRICING missing condition is UNKNOWN, never full health', unknown.engine.known == false and unknown.engine.needed == false)
    check('PRICING all-unknown condition cannot be quoted', select(2, P.quote(cfg, 'repair_basic', unknown, 100000)) == 'condition_unknown')
    local cap = P.diagnose({ engine = 0.0, body = 0.0, tank = 0.0, conditionState = { brokenWindows = { ['0'] = true, ['1'] = true }, doors = { ['0'] = { broken = true } }, tyres = { ['0'] = { burst = true }, ['1'] = { onRim = true } } } }, cfg)
    local okF, qf = P.quote(cfg, 'repair_full', cap, 20000000)
    check('PRICING clamps to the service maxPrice (billing cap safe)', okF and qf.amount <= 49000 and qf.amount == 49000, qf and qf.amount)
    check('PRICING diagnostic is a flat fee', select(2, P.quote(cfg, 'diagnostic', full, 400000)).amount == 1500)
    check('PRICING unknown vehicle value falls back to the configured value', select(2, P.quote(cfg, 'repair_basic', diag, nil)).amount > 0)
    check('PRICING invalid / disabled services are rejected', select(2, P.quote(cfg, 'nope', diag, 1)) == 'invalid_service' and select(2, P.quote(cfg, 'tuning_request', diag, 1)) == 'service_unavailable')
    local patch = P.buildPatch({ engine = true, body = true }, { brokenWindows = { ['0'] = true }, tyres = { ['2'] = { burst = true } } })
    check('PRICING patch holds ABSOLUTE targets (idempotent)', patch.engineHealth == 1000.0 and patch.bodyHealth == 1000.0 and patch.tankHealth == nil)
    check('PRICING patch keeps unrelated damage (tyres untouched by engine/body repair)', patch.conditionState and patch.conditionState.tyres['2'] and patch.conditionState.tyres['2'].burst == true)
    local p2 = P.buildPatch({ cosmetic = true, tyres = true }, { brokenWindows = { ['0'] = true }, doors = { ['1'] = { damaged = true } }, tyres = { ['2'] = { burst = true } } })
    check('PRICING cosmetic + tyre repair clears windows/doors/tyres only', next(p2.conditionState.brokenWindows) == nil and next(p2.conditionState.doors) == nil and next(p2.conditionState.tyres) == nil and p2.engineHealth == nil)
    check('PRICING summary exposes percentages only (no ids)', (function() local s = P.summary(diag); return s.engine == 40 and s.body == 70 and s.tank == 100 and s.id == nil end)())
end

-- ======================================================================================== PHONE SOURCE
do
    newWorld()
    local ok, view = request('101', 'repair', 'engine smoking')
    check('PHONE valid request creates a searching request', ok == true and view.state == 'searching' and view.ref ~= nil and view.ref:match('^MR%-') ~= nil)
    local row = reqRow(view.ref)
    check('PHONE request is owned by the CHARACTER, status open, contract published', row.customer_cid == '101' and row.status == 'open' and row.contract_ref ~= nil)
    check('PHONE request stores the safe note and server-observed position', row.note == 'engine smoking' and row.pos_x == 100.0)
    check('PHONE broker has exactly one mechanic_request contract for it', (function() local n = 0 for _, r in pairs(W.bstore.rows) do if r.source_reference == view.ref and r.contract_type == 'mechanic_request' then n = n + 1 end end return n == 1 end)())
    local okS, st = W.engine:RequestStatus('101')
    check('PHONE status: searching, cancellable, public vocabulary only', okS and st.state == 'searching' and st.canCancel == true and st.detail == 'Looking for a mechanic')
    local ok2, again = request('101', 'repair')
    check('PHONE duplicate request refused by the phone (already_active)', ok2 == false and again == 'already_active')
    local ok3, same = W.engine:CreateRequest('101', { service = 'repair' }, { position = { x = 1, y = 1, z = 1 } })
    check('PHONE retry straight into the source returns the SAME request (idempotent)', ok3 == true and same.ref == view.ref)
    check('PHONE retry did not create a second contract', (function() local n = 0 for _ in pairs(W.bstore.rows) do n = n + 1 end return n == 1 end)())
    check('PHONE malformed: invalid enum rejected by the phone', select(2, request('102', 'tow')) == 'invalid_field')
    check('PHONE malformed: missing service rejected', select(2, W.phone:Request(1102, '102', 'mechanic', {})) == 'missing_field')
    check('PHONE malformed: unknown field rejected', select(2, W.phone:Request(1102, '102', 'mechanic', { service = 'repair', vehicle_id = 7002 })) == 'invalid_field')
    check('PHONE malformed: table note rejected', select(2, W.phone:Request(1102, '102', 'mechanic', { service = 'repair', details = { 'x' } })) == 'invalid_field')
    check('PHONE source also rejects a bad category on its own', select(2, W.engine:CreateRequest('102', { service = 'tow' }, { position = { x = 1, y = 1, z = 1 } })) == 'not_allowed')
    check('PHONE source rejects non-table fields and a missing position', select(2, W.engine:CreateRequest('102', 'x', { position = { x = 1, y = 1 } })) == 'not_allowed' and select(2, W.engine:CreateRequest('102', { service = 'repair' }, {})) == 'service_unavailable')
    check('PHONE offline customer cannot create', select(2, W.engine:CreateRequest('999', { service = 'repair' }, { position = { x = 1, y = 1 } })) == 'service_unavailable')
    W.dead[1102] = true
    check('PHONE dead customer refused (dead)', select(2, request('102', 'repair')) == 'unavailable' or select(2, request('102', 'repair')) == 'dead')
    W.dead[1102] = false
    -- ownership: another character cannot see or cancel 101's request
    check('PHONE customer ownership: 102 sees no request', select(2, W.engine:RequestStatus('102')) == nil)
    check('PHONE customer ownership: 102 cannot cancel 101 request', select(2, W.engine:CancelRequest('102', view.ref)) == 'not_found')
    check('PHONE cancel through the phone works and ends the request', (function()
        local okc = W.phone:Cancel(1101, '101', 'mechanic', view.ref); return okc == true and reqRow(view.ref).status == 'cancelled' end)())
    check('PHONE cancel released the active_key so a new request is possible', select(1, request('101', 'repair')) == true)
    check('PHONE cancel cancelled the broker contract', (function() local ok4, c = W.broker:GetSourceContract('cm-mechanic', 'mechanic_request', view.ref); return ok4 and c.status == 'cancelled' end)())
    check('PHONE cancelled status is terminal in the public vocabulary', (function() local _, s = W.engine:RequestStatus('101'); return s ~= nil end)())
    check('PHONE availability: true when a mechanic business is owned', W.engine:Availability() == true)
    newWorld({ unowned = true })
    check('PHONE availability false and request refused when no mechanic business is owned', W.engine:Availability() == false and select(2, request('101', 'repair')) == 'service_unavailable')
    check('PHONE source itself refuses with no_provider when nothing is owned', select(2, W.engine:CreateRequest('101', { service = 'repair' }, { position = { x = 1, y = 1, z = 1 } })) == 'no_provider')
    newWorld(); W.brokerDown = true
    check('PHONE broker down: request fails closed and no phantom open request remains', select(1, request('101', 'repair')) == false and W.mech.reqOpenByCustomer('101') == nil)
    newWorld(); W.phoneStarted['cm-mechanic'] = false
    check('PHONE mechanic offline: service reports unavailable', select(2, request('101', 'repair')) == 'service_unavailable')
end

-- ======================================================================================== CONTRACTS / BUSINESS
do
    newWorld()
    local _, view = request('101', 'repair')
    local row = reqRow(view.ref)
    local okB, b201 = board('201')
    check('CONTRACT publish: eligible mechanic sees the request on the board', okB and #b201.requests == 1 and b201.requests[1].contract == row.contract_ref)
    check('CONTRACT board shows only safe fields (no customer id, no vehicle, no money)', (function()
        local r = b201.requests[1]
        for k, v in pairs(r) do if type(v) == 'string' and (v:find('101') and k ~= 'contract' and k ~= 'area') then return false end end
        return r.customer == nil and r.customer_cid == nil and r.vehicle == nil and r.price == nil and r.invoice == nil end)())
    check('CONTRACT board area is rounded (approximate location only)', b201.requests[1].area == 'Roadside near 100, 100')
    check('BUSINESS ineligible: employee without accept permission gets not_mechanic', select(2, board('202')) == 'not_mechanic')
    check('BUSINESS ineligible: a non-employee customer cannot see the board', select(2, board('102')) == 'not_mechanic')
    check('BUSINESS ineligible: offline character cannot be eligible', select(2, W.engine:Eligible('999', { reference = row.contract_ref })) == 'not_loaded')
    check('BUSINESS permission denied: accept-only employee 203 CAN claim (has accept)', select(1, W.engine:Eligible('203', { reference = row.contract_ref })) == true)
    check('BUSINESS invalid/unknown business id rejected on claim', select(2, W.engine:Claim('201', row.contract_ref, 'nonexistent')) == 'not_mechanic')
    check('BUSINESS isolation: 201 (main) cannot claim as business "other"', select(2, W.engine:Claim('201', row.contract_ref, 'other')) == 'not_mechanic')
    check('CONTRACT self-service: a mechanic cannot accept their own request', (function()
        local ok = request('201', 'repair'); local contract = W.mech.reqOpenByCustomer('201')
        local okC, why = W.engine:Claim('201', contract.contract_ref); return ok and okC == false and why == 'self_service' end)())
    W.engine:CancelRequest('201', W.mech.reqOpenByCustomer('201').reference)

    local okC, wov = W.engine:Claim('201', row.contract_ref)
    check('CONTRACT claim: eligible mechanic claims through the broker -> work order assigned', okC and wov.state == 'assigned' and wov.business == 'mechanic:main')
    local cRow = W.bstore.getByRef(row.contract_ref)
    check('CONTRACT lease: broker row is claimed by the mechanic character with a lease', cRow.status == 'claimed' and cRow.claimed_character_id == '201' and cRow.claim_expires_at > W.now)
    check('CONTRACT lease uses the provider lease (600s)', cRow.claim_expires_at - W.now == 600)
    check('CONTRACT assignment: request is assigned and linked to the work order', reqRow(view.ref).status == 'assigned' and reqRow(view.ref).work_order_ref == wov.workOrder)
    check('CONTRACT provider ref is the work order reference', cRow.provider_ref == wov.workOrder)
    check('CONTRACT exclusivity: a second mechanic cannot claim the same request', select(1, W.engine:Claim('301', row.contract_ref)) == false)
    check('CONTRACT exclusivity: board no longer lists it for others', #select(2, board('203')).requests == 0)
    check('CONTRACT duplicate claim by the same mechanic is idempotent', (function() local ok2, v2 = W.engine:Claim('201', row.contract_ref); return ok2 and v2.workOrder == wov.workOrder end)())
    check('PHONE status: assigned (Mechanic on the way), cancellable', (function() local _, s = W.engine:RequestStatus('101'); return s.state == 'assigned' and s.detail == 'Mechanic on the way' and s.canCancel end)())
    check('PHONE status push sent on assignment', (function() for _, p in ipairs(W.pushes) do if p.view.state == 'assigned' then return true end end return false end)())
    check('PHONE status never leaks contract/work-order internals', (function()
        local _, s = W.engine:RequestStatus('101')
        for k in pairs(s) do if not ({ ref = true, state = true, detail = true, workerLabel = true, canCancel = true })[k] then return false end end
        return s.workerLabel == 'Mechanic assigned' end)())

    -- release: lease expiry returns the request to the board and cancels the unstarted order
    advance(500); W.broker:Sweep()   -- fallback deadline reached while claimed: the broker defers (worker keeps the job)
    check('CONTRACT fallback deferral: a claimed job is not stripped at the deadline', W.bstore.getByRef(row.contract_ref).status == 'claimed' and reqRow(view.ref).status == 'assigned')
    advance(101); W.broker:Sweep()
    check('CONTRACT release: lease expiry returns the contract to the board', W.bstore.getByRef(row.contract_ref).status == 'available')
    check('CONTRACT release: request is open again and the old work order is cancelled', reqRow(view.ref).status == 'open' and woOf(wov.workOrder).state == 'cancelled' and woOf(wov.workOrder).active_key == nil)
    local ok301, w2 = W.engine:Claim('301', row.contract_ref, 'other')
    check('CONTRACT re-claim after release by another business works (new work order)', ok301 and w2.workOrder ~= wov.workOrder and w2.business == 'mechanic:other')
    check('BUSINESS isolation: business "main" employee cannot act on the "other" order', select(2, W.engine:BeginDiagnosis('201', w2.workOrder, 9001)) == 'not_found')
    -- explicit release by the mechanic (abandon)
    check('CONTRACT release: mechanic abandon returns request to the board', W.engine:AbandonWork('301', w2.workOrder) == true and reqRow(view.ref).status == 'open' and W.bstore.getByRef(row.contract_ref).status == 'available')

    -- fallback / expiry: nobody serves it
    advance(2000); W.broker:Sweep()
    local fr = reqRow(view.ref)
    check('FALLBACK: expired unserved request is EXPIRED (no repair, no completion)', fr.status == 'expired' and #W.applied == 0)
    check('FALLBACK: contract ends cancelled via source_terminal (not rewardable fallback completion)', W.bstore.getByRef(row.contract_ref).status == 'cancelled')
    check('FALLBACK: phone shows no_provider', (function() local _, s = W.engine:RequestStatus('101'); return s.state == 'no_provider' end)())
    check('FALLBACK: active_key freed so the customer can request again', select(1, request('101', 'repair')) == true)
    check('FALLBACK: no money moved and no invoice exists', next(W.invoices) == nil and W.balances['mechanic:main'] == 0)
    check('FALLBACK: no worker became claimed (nobody rewarded)', (function() for _, r in pairs(W.bstore.rows) do if r.completion_mode == 'player' then return false end end return true end)())
end

-- ======================================================================================== VEHICLE
do
    newWorld()
    request('101', 'repair'); local _, wov = claimFirst('201'); local wo = wov.workOrder
    check('VEHICLE diagnose before assignment of vehicle: valid vehicle binds vehicle_id', (function()
        local ok, d = diagnose('201', wo); return ok and d.state == 'diagnosing' and woOf(wo).vehicle_id == 7001 end)())
    check('VEHICLE diagnosis exposes health percentages only', (function() local _, v = W.engine:GetWork('201', wo); return v.diagnosis.engine == 40 and v.diagnosis.body == 70 and v.diagnosis.id == nil end)())
    check('VEHICLE diagnosis marks the broker contract active', W.bstore.getByRef(reqRow(woOf(wo).request_ref).contract_ref).status == 'active')
    check('VEHICLE owner snapshot stored for ownership-change detection', woOf(wo).owner_snapshot == 'character:101')
    check('VEHICLE missing vehicle (unknown net id) rejected', select(2, diagnose('201', wo, 123456)) == 'vehicle_not_found')
    check('VEHICLE wrong vehicle: another customer\'s car (no access) rejected', (function()
        W.pos[2201] = { x = 501.0, y = 500.0, z = 30.0, bucket = 0 }; W.pos[1101] = { x = 501.0, y = 500.0, z = 30.0, bucket = 0 }
        local why = select(2, diagnose('201', wo, 9002))
        W.pos[2201] = { x = 103.0, y = 100.0, z = 30.0, bucket = 0 }; W.pos[1101] = { x = 100.0, y = 100.0, z = 30.0, bucket = 0 }
        return why == 'wrong_vehicle' end)())
    check('VEHICLE too far: mechanic away from the car', (function() W.pos[2201].x = 140.0; local why = select(2, diagnose('201', wo)); W.pos[2201].x = 103.0; return why == 'too_far' end)())
    check('VEHICLE customer too far from their car (roadside)', (function() W.pos[1101].x = 160.0; local why = select(2, diagnose('201', wo)); W.pos[1101].x = 100.0; return why == 'customer_too_far' end)())
    check('VEHICLE routing bucket mismatch rejected', (function() W.pos[2201].bucket = 5; local why = select(2, diagnose('201', wo)); W.pos[2201].bucket = 0; return why == 'wrong_bucket' end)())
    check('VEHICLE customer without access rejected (keyholder only passes)', (function()
        W.veh[7001].ownerCharacterId = '555'; local why = select(2, diagnose('201', wo)); W.veh[7001].ownerCharacterId = '101'; return why == 'no_access' end)())
    check('VEHICLE keyholder (not owner) customer is accepted for normal repair', (function()
        W.veh[7001].ownerCharacterId = '555'; W.veh[7001].keys['101'] = true
        local ok = diagnose('201', wo); W.veh[7001].ownerCharacterId = '101'; W.veh[7001].keys = {}; return ok == true end)())
    check('VEHICLE protected: organization/fleet vehicle refused', (function() W.veh[7001].ownerType = 'organization'; local why = select(2, diagnose('201', wo)); W.veh[7001].ownerType = 'character'; return why == 'vehicle_protected' end)())
    check('VEHICLE protected: admin vehicle refused', (function() W.veh[7001].admin = true; local why = select(2, diagnose('201', wo)); W.veh[7001].admin = false; return why == 'vehicle_protected' end)())
    check('VEHICLE stored/garaged vehicle is not physically present', (function() W.veh[7001].stored = true; local why = select(2, diagnose('201', wo)); W.veh[7001].stored = false; return why == 'vehicle_not_present' end)())
    check('VEHICLE condition not initialised -> pending (never full health)', (function() W.veh[7001].condPending = true; local why = select(2, diagnose('201', wo)); W.veh[7001].condPending = nil; return why == 'condition_pending' end)())
    check('VEHICLE mechanic without quote permission cannot diagnose', (function()
        W.biz['mechanic:main'].staff['201']['mechanic.create_quote'] = nil
        local why = select(2, diagnose('201', wo)); W.biz['mechanic:main'].staff['201']['mechanic.create_quote'] = true; return why == 'forbidden' end)())
    check('VEHICLE customer offline blocks diagnosis', (function() local s = W.online['101']; W.online['101'] = nil; local why = select(2, diagnose('201', wo)); W.online['101'] = s; return why == 'customer_offline' end)())
    check('VEHICLE vehicle_id (not net id / plate) is what the order stores', woOf(wo).vehicle_id == 7001 and woOf(wo).net_id == nil and woOf(wo).plate == nil)
    -- ownership change mid-work
    W.veh[7001].ownerCharacterId = '102'; W.veh[7001].keys = { ['101'] = true }
    check('VEHICLE ownership changed mid-work invalidates the quote request', select(2, W.engine:CreateQuote('201', wo, 'repair_basic', 9001)) == 'ownership_changed')
    W.veh[7001].ownerCharacterId = '101'; W.veh[7001].keys = {}
end

-- ======================================================================================== SERVICE / QUOTE
do
    newWorld()
    W.cfg.Quote.maxDeclines = 10   -- this block exercises several declines; the cancel-after-max case below resets it
    request('101', 'repair'); local _, wov = claimFirst('201'); local wo = wov.workOrder
    check('SERVICE quote before diagnosis rejected (invalid_state)', select(2, W.engine:CreateQuote('201', wo, 'repair_basic', 9001)) == 'invalid_state')
    diagnose('201', wo)
    check('SERVICE invalid service id rejected', select(2, W.engine:CreateQuote('201', wo, 'free_money', 9001)) == 'invalid_service')
    check('SERVICE a cm-tuning service is never quoted through the repair path (needs the tuning session)', select(2, W.engine:CreateQuote('201', wo, 'tuning_request', 9001)) == 'use_tuning_session')
    check('SERVICE non-string service rejected', select(2, W.engine:CreateQuote('201', wo, { id = 'x' }, 9001)) == 'invalid_service')
    check('SERVICE workshop-only service unavailable roadside (shop has no bay location)', select(2, W.engine:CreateQuote('201', wo, 'repair_full', 9001)) == 'workshop_not_configured')
    check('SERVICE nothing-to-repair rejected', (function()
        local saved = deepcopy(W.veh[7001].cond); W.veh[7001].cond = { engine = 1000.0, body = 1000.0, tank = 1000.0, conditionState = {} }
        local why = select(2, W.engine:CreateQuote('201', wo, 'repair_basic', 9001)); W.veh[7001].cond = saved; return why == 'nothing_to_repair' end)())
    check('SERVICE tyre service quote works roadside', (function() local ok, q = W.engine:CreateQuote('201', wo, 'tire_service', 9001); if ok then W.engine:RespondQuote('101', false) end return ok and q.amount == 650 end)())
    local ok, q = W.engine:CreateQuote('201', wo, 'repair_basic', 9001)
    check('QUOTE generated with the authoritative amount (engine+tank formula)', ok and q.amount == 7260 and q.service == 'Engine and fuel system repair')
    check('QUOTE order stored: state quoted, amount, service, expiry', woOf(wo).state == 'quoted' and woOf(wo).quote_amount == 7260 and woOf(wo).service_id == 'repair_basic' and woOf(wo).quote_expires_at == W.now + 300)
    check('QUOTE customer notified with service/amount/business only', (function()
        for i = #W.notes, 1, -1 do local n = W.notes[i]; if n.kind == 'quote' then return n.cid == '101' and n.payload.amount == 7260 and n.payload.business == 'Main Mechanic' and n.payload.vehicle == nil end end return false end)())
    check('QUOTE client price ignored: extra argument can never set the amount', (function()
        W.engine:RespondQuote('101', false); local ok2, q2 = W.engine:CreateQuote('201', wo, 'repair_basic', 9001, 1); return ok2 and q2.amount == 7260 end)())
    check('QUOTE second quote while quoted is rejected (state machine)', select(2, W.engine:CreateQuote('201', wo, 'repair_body', 9001)) == 'invalid_state')
    check('QUOTE pending quote view is the customer\'s own', W.engine:PendingQuote('101').amount == 7260 and W.engine:PendingQuote('102') == nil)
    check('QUOTE foreign customer cannot respond (no order of their own)', select(2, W.engine:RespondQuote('102', true)) == 'not_found')
    check('QUOTE mechanic cannot approve their own quote (no customer order for 201)', select(2, W.engine:RespondQuote('201', true)) == 'not_found')
    check('QUOTE decline returns the order to diagnosing and counts the decline', (function()
        local ok2 = W.engine:RespondQuote('101', false); return ok2 == true and woOf(wo).state == 'diagnosing' and woOf(wo).declines >= 1 and woOf(wo).quote_amount == nil end)())
    check('QUOTE decline replay is rejected (no longer quoted)', select(2, W.engine:RespondQuote('101', false)) == 'not_found')
    check('QUOTE expiry: an unanswered quote is rejected and returns to diagnosing', (function()
        W.engine:CreateQuote('201', wo, 'repair_basic', 9001); advance(301)
        local why = select(2, W.engine:RespondQuote('101', true)); return why == 'quote_expired' and woOf(wo).state == 'diagnosing' end)())
    check('QUOTE max declines cancels the order and the request', (function()
        newWorld(); request('101', 'repair'); local _, v2 = claimFirst('201'); diagnose('201', v2.workOrder)
        for _ = 1, 3 do W.engine:CreateQuote('201', v2.workOrder, 'repair_basic', 9001); W.engine:RespondQuote('101', false) end
        local ref = woOf(v2.workOrder).request_ref
        return woOf(v2.workOrder).state == 'cancelled' and reqRow(ref).status == 'cancelled' and W.mech.woActiveByRequest(ref) == nil end)())
    check('QUOTE worse damage between quote and approval invalidates the quote (never charged more)', (function()
        newWorld(); local wo2 = toQuoted('repair', 'repair_basic')
        W.veh[7001].cond.engine = 0.0
        local why = select(2, W.engine:RespondQuote('101', true)); return why == 'quote_changed' and woOf(wo2).state == 'diagnosing' and next(W.invoices) == nil end)())
    check('QUOTE less damage at approval still bills the quoted amount cap (never more)', (function()
        newWorld(); local wo2 = toQuoted('repair', 'repair_basic')
        W.veh[7001].cond.engine = 700.0
        local ok2 = W.engine:RespondQuote('101', true); return ok2 == true and W.invoices[woOf(wo2).invoice_ref].amount == 7260 end)())
    check('SERVICE roadside disabled shop: roadside service rejected', (function()
        newWorld(); request('101', 'repair'); local _, v2 = claimFirst('301', 'noroad'); diagnose('301', v2.workOrder)
        return select(2, W.engine:CreateQuote('301', v2.workOrder, 'repair_basic', 9001)) == 'roadside_disabled' end)())
    check('SERVICE workshop policy: bay shop mechanic inside the bay can quote workshop service', (function()
        newWorld(); W.pos[2201] = nil; W.online['401'] = 4401
        W.veh[7001].pos = { x = 1002.0, y = 1000.0, z = 30.0, bucket = 0 }; W.pos[1101] = { x = 1000.0, y = 1001.0, z = 30.0, bucket = 0 }
        request('101', 'repair'); local _, v2 = claimFirst('401'); diagnose('401', v2.workOrder)
        local ok2, q2 = W.engine:CreateQuote('401', v2.workOrder, 'repair_full', 9001)
        return ok2 and q2.amount > 0 end)())
    check('SERVICE workshop policy: bay mechanic outside the bay radius rejected', (function()
        newWorld(); W.online['401'] = 4401
        W.pos[4401] = { x = 1002.0, y = 1000.0, z = 30.0, bucket = 0 }
        W.veh[7001].pos = { x = 1003.0, y = 1000.0, z = 30.0, bucket = 0 }; W.pos[1101] = { x = 1001.0, y = 1001.0, z = 30.0, bucket = 0 }
        request('101', 'repair'); local _, v2 = claimFirst('401'); diagnose('401', v2.workOrder)
        W.pos[4401] = { x = 1500.0, y = 1000.0, z = 30.0, bucket = 0 }; W.veh[7001].pos = { x = 1501.0, y = 1000.0, z = 30.0, bucket = 0 }; W.pos[1101] = { x = 1500.0, y = 1001.0, z = 30.0, bucket = 0 }
        return select(2, W.engine:CreateQuote('401', v2.workOrder, 'repair_full', 9001)) == 'not_in_workshop' end)())
    check('SERVICE permission: mechanic without service_vehicle cannot quote a repair', (function()
        newWorld(); request('101', 'repair'); local _, v2 = claimFirst('201'); diagnose('201', v2.workOrder)
        W.biz['mechanic:main'].staff['201']['mechanic.service_vehicle'] = nil
        return select(2, W.engine:CreateQuote('201', v2.workOrder, 'repair_basic', 9001)) == 'forbidden' end)())
end

-- ======================================================================================== BILLING / REPAIR COMMIT / COMPLETION / MONEY
do
    newWorld()
    local wo, ref, q = toQuoted('repair', 'repair_basic')
    local moneyBefore = W.customerMoney['101']
    local ok, r = W.engine:RespondQuote('101', true)
    local w = woOf(wo)
    check('BILLING approval creates exactly one invoice and moves to awaiting_payment', ok and w.state == 'awaiting_payment' and w.invoice_ref ~= nil and W.nextInv == 1)
    local inv = W.invoices[w.invoice_ref]
    check('BILLING invoice amount is the server quote', inv.amount == q.amount)
    check('BILLING invoice destination is the mechanic BUSINESS (business:mechanic:main)', inv.data.destination.type == 'business' and inv.dest == 'mechanic:main')
    check('BILLING invoice issuer is the business, recipient is the customer character', inv.data.issuerType == 'business' and inv.recipient == '101' and inv.data.issuerCharacterId == '201')
    check('BILLING invoice idempotency key is per work order + attempt', inv.key == 'mechinv:' .. wo .. ':1')
    check('BILLING invoice metadata is in the mechanic.* namespace', inv.data.metadata['mechanic.work'] == wo)
    check('BILLING replay: a second approve is rejected and creates no second invoice', select(2, W.engine:RespondQuote('101', true)) == 'not_found' and W.nextInv == 1)
    check('BILLING _ensureInvoice replay returns the same invoice (no duplicate)', select(2, W.engine:_ensureInvoice(woOf(wo))) == w.invoice_ref and W.nextInv == 1)
    check('BILLING crash window: invoice created but ref not saved -> same key returns the same invoice', (function()
        local saved = W.mech.wos[1].invoice_ref; W.mech.wos[1].invoice_ref = nil
        local okE, rr = W.engine:_ensureInvoice(woOf(wo)); local same = okE and rr == saved and W.nextInv == 1; return same end)())
    check('BILLING invoice event journaled once', W.mech.countEvents('invoice_created', wo) == 1)
    check('REPAIR before payment is rejected: StartService refused while awaiting payment', select(2, W.engine:StartService('201', wo, 9001)) == 'invalid_state')
    check('REPAIR before payment is rejected: FinishService refused', select(2, W.engine:FinishService('201', wo, 9001)) == 'payment_pending')
    check('REPAIR before payment: vehicle untouched', #W.applied == 0 and W.veh[7001].cond.engine == 400.0)
    check('PHONE status awaiting payment is public text', (function() local _, s = W.engine:RequestStatus('101'); return s.state == 'active' and s.detail:find('Awaiting payment') ~= nil end)())
    sweep()
    check('BILLING unpaid invoice stays awaiting_payment after sweep', woOf(wo).state == 'awaiting_payment')
    check('BILLING insufficient funds: payment fails, nothing credited, order safe', (function()
        W.customerMoney['101'] = 10; local okP = W.pay(w.invoice_ref); W.customerMoney['101'] = moneyBefore
        sweep(); return okP == false and W.balances['mechanic:main'] == 0 and woOf(wo).state == 'awaiting_payment' and #W.applied == 0 end)())
    check('BILLING payment success: business credited exactly once by billing (double)', (function()
        local okP = W.pay(w.invoice_ref); return okP and W.balances['mechanic:main'] == q.amount and W.customerMoney['101'] == moneyBefore - q.amount end)())
    sweep(); sweep()
    check('BILLING paid detected once -> servicing (replay safe)', woOf(wo).state == 'servicing' and W.mech.countEvents('payment_confirmed', wo) == 1)
    check('REPAIR still not applied until the service action', #W.applied == 0)
    check('PHYSICAL finish before start is rejected', select(2, W.engine:FinishService('201', wo, 9001)) == 'service_not_started')
    check('PHYSICAL start validates mechanic proximity', (function() W.pos[2201].x = 300.0; local why = select(2, W.engine:StartService('201', wo, 9001)); W.pos[2201].x = 103.0; return why == 'too_far' end)())
    check('PHYSICAL start requires service permission', (function() W.biz['mechanic:main'].staff['201']['mechanic.service_vehicle'] = nil; local why = select(2, W.engine:StartService('201', wo, 9001)); W.biz['mechanic:main'].staff['201']['mechanic.service_vehicle'] = true; return why == 'forbidden' end)())
    check('PHYSICAL start returns the server duration', (function() local okS, s = W.engine:StartService('201', wo, 9001); return okS and s.durationSeconds == 20 end)())
    check('PHYSICAL finishing too early (client skipped the progress) rejected', select(2, W.engine:FinishService('201', wo, 9001)) == 'too_early')
    advance(30)
    check('PHYSICAL wrong vehicle at finish rejected', select(2, W.engine:FinishService('201', wo, 9002)) == 'wrong_vehicle')
    check('PHYSICAL foreign mechanic cannot finish this order', select(2, W.engine:FinishService('301', wo, 9001)) == 'not_found')
    check('PHYSICAL permission: complete_work required', (function() W.biz['mechanic:main'].staff['201']['mechanic.complete_work'] = nil; local why = select(2, W.engine:FinishService('201', wo, 9001)); W.biz['mechanic:main'].staff['201']['mechanic.complete_work'] = true; return why == 'forbidden' end)())
    W.applyFail = 1
    local okF, whyF = W.engine:FinishService('201', wo, 9001)
    check('REPAIR cm-vehicles failure: order stays servicing, nothing lost, retry scheduled', okF == false and whyF == 'vehicle_service_failed' and woOf(wo).state == 'servicing' and woOf(wo).commit_state == 'committing' and #W.applied == 0)
    check('REPAIR failure keeps the invoice paid and business credited (no refund needed, no second charge)', W.balances['mechanic:main'] == q.amount and W.nextInv == 1)
    local okFin, resFin = W.engine:FinishService('201', wo, 9001)
    check('REPAIR valid paid commit applies the vehicle patch exactly once', okFin and #W.applied == 1 and W.veh[7001].cond.engine == 1000.0 and W.veh[7001].cond.body == 700.0)
    check('REPAIR commit patch is absolute, only touches what was quoted (tank was healthy), keeps tyre/window damage', (function()
        local p = W.applied[1].patch; return p.engineHealth == 1000.0 and p.tankHealth == nil and p.bodyHealth == nil and p.conditionState.tyres['2'] ~= nil and p.conditionState.undriveable == false end)())
    check('REPAIR order completed + committed, active_key released', woOf(wo).state == 'completed' and woOf(wo).commit_state == 'committed' and woOf(wo).active_key == nil)
    check('REPAIR duplicate finish is a safe replay (no second repair)', (function() local o2, r2 = W.engine:FinishService('201', wo, 9001); return o2 and r2.replayed == true and #W.applied == 1 end)())
    check('REPAIR direct commit replay is a no-op', (function() local o2, r2 = W.engine:_commit(woOf(wo), 'x'); return o2 and #W.applied == 1 end)())
    check('REPAIR committed event journaled once, audit mirrored', W.mech.countEvents('service_committed', wo) == 1 and (function() local n = 0 for _, a in ipairs(W.audits) do if a.kind == 'mechanic_service_committed' then n = n + 1 end end return n == 1 end)())
    check('COMPLETION: contract completed by the player path (service success)', (function() local c = W.bstore.getByRef(reqRow(ref).contract_ref); return c.status == 'completed' and c.completion_mode == 'player' end)())
    check('COMPLETION: request completed and phone shows Completed', reqRow(ref).status == 'completed' and select(2, W.engine:RequestStatus('101')).state == 'completed')
    check('COMPLETION: broker completion replay is safe (not rewardable again)', (function()
        local ok2, r2 = W.broker:Complete('cm-mechanic', reqRow(ref).contract_ref, '201', {}); return ok2 and r2.rewardable == false end)())
    check('COMPLETION: source complete callback replays idempotently', select(1, W.engine:SourceComplete({ sourceReference = ref, workerCharacterId = '201' })) == true)
    check('COMPLETION: callback for another worker is refused on an unfinished order', (function()
        newWorld(); local wo2, ref2 = toQuoted('repair', 'repair_basic')
        return select(2, W.engine:SourceComplete({ sourceReference = ref2, workerCharacterId = '201' })) == 'work_not_finished' end)())
    check('MONEY FLOW: customer paid exactly once, business credited exactly once, no money minted', (function()
        newWorld(); local wo2 = toPaid('repair_basic')
        local total0 = 200000
        finishService(wo2)
        local total1 = W.customerMoney['101'] + W.customerMoney['102'] + W.balances['mechanic:main'] + W.balances['mechanic:bay'] + W.balances['mechanic:other'] + W.balances['mechanic:noroad']
        return total1 == total0 and W.balances['mechanic:main'] == 7260 and W.applied[1] ~= nil end)())
    check('MONEY FLOW: no employee commission/payout exists (employees\' balances untouched)', (function() return W.balances['201'] == nil end)())
end

-- ======================================================================================== INVOICE OUTCOMES / CANCEL AFTER INVOICE
do
    newWorld()
    local wo, ref = toQuoted('repair', 'repair_basic'); W.engine:RespondQuote('101', true)
    local inv1 = woOf(wo).invoice_ref
    check('INVOICE expiry returns the order to diagnosing with a new attempt (no free repair, no duplicate)', (function()
        W.invoices[inv1].status = 'expired'; sweep()
        local w = woOf(wo); return w.state == 'diagnosing' and w.invoice_attempt == 2 and w.invoice_ref == nil and #W.applied == 0 end)())
    check('INVOICE re-quote after expiry creates a NEW invoice (new key)', (function()
        W.engine:CreateQuote('201', wo, 'repair_basic', 9001); W.engine:RespondQuote('101', true)
        local w = woOf(wo); return w.invoice_ref ~= inv1 and W.invoices[w.invoice_ref].key == 'mechinv:' .. wo .. ':2' and W.nextInv == 2 end)())
    check('CANCEL customer cancel with a pending invoice voids it and ends the request', (function()
        local w = woOf(wo); local ok = W.engine:CancelRequest('101', ref)
        return ok == true and W.invoices[w.invoice_ref].status == 'voided' and woOf(wo).state == 'cancelled' and reqRow(ref).status == 'cancelled' end)())
    check('CANCEL after cancel nothing is billed and the vehicle is untouched', W.balances['mechanic:main'] == 0 and #W.applied == 0)
    check('CANCEL not allowed once paid (irreversible)', (function()
        newWorld(); local wo2, ref2 = toPaid('repair_basic')
        local ok, why = W.engine:CancelRequest('101', ref2); return ok == false and why == 'cancel_not_allowed' and woOf(wo2).state == 'servicing' end)())
    check('CANCEL: phone cancelable flag is false while servicing', (function() local _, s = W.engine:RequestStatus('101'); return s.canCancel == false end)())
    check('CANCEL race: customer cancels while invoice settling (void refused) -> not allowed', (function()
        newWorld(); local wo2, ref2 = toQuoted('repair', 'repair_basic'); W.engine:RespondQuote('101', true)
        W.invoices[woOf(wo2).invoice_ref].status = 'processing'
        local ok, why = W.engine:CancelRequest('101', ref2); return ok == false and why == 'cancel_not_allowed' end)())
    check('BILLING failure at approval leaves the quote re-approvable and creates no invoice', (function()
        newWorld(); local wo2 = toQuoted('repair', 'repair_basic'); W.billingDown = true
        local ok, why = W.engine:RespondQuote('101', true); local stuck = woOf(wo2).state
        W.billingDown = nil; local ok2 = W.engine:RespondQuote('101', true)
        return ok == false and why == 'billing_unavailable' and stuck == 'quoted' and ok2 == true and W.nextInv == 1 end)())
    check('BILLING mechanic mismatch: invoices for a destination business that lost its owner are refused by billing', (function()
        newWorld(); local wo2 = toQuoted('repair', 'repair_basic'); W.biz['mechanic:main'].owned = false
        local ok, why = W.engine:RespondQuote('101', true); return ok == false and next(W.invoices) == nil end)())
    check('BILLING cap: a forged oversized quote cannot become an invoice (billing enforces the provider limit)', (function()
        newWorld(); local wo2 = toQuoted('repair', 'repair_basic')
        W.mech.wos[1].quote_amount = 5000000
        local ok = W.engine:RespondQuote('101', true); return ok == false and next(W.invoices) == nil and woOf(wo2).state == 'quoted' end)())
    check('BILLING limit failure is surfaced as the stable amount_over_limit reason (no duplicate cap in cm-mechanic)', (function()
        newWorld(); local wo2 = toQuoted('repair', 'repair_basic'); W.mech.wos[1].quote_amount = W.billingLimit + 1
        local ok, why = W.engine:RespondQuote('101', true); return ok == false and next(W.invoices) == nil and woOf(wo2).state == 'quoted' and (why == 'amount_over_limit') end)())
    check('BILLING policy: cm-mechanic has no hard-coded invoice cap of its own', W.cfg.Tuning.maxInvoiceAmount == nil)
end

-- ======================================================================================== RECOVERY / DISCONNECT / RESTART
do
    newWorld()
    local wo, ref = toPaid('repair_basic')
    check('RESTART paid-but-never-finished order is committed by the server after the auto-commit window', (function()
        advance(299); sweep(); local early = #W.applied
        advance(2); sweep()
        return early == 0 and #W.applied == 1 and woOf(wo).state == 'completed' and W.veh[7001].cond.engine == 1000.0 end)())
    check('RESTART recovery commit also completed the contract', W.bstore.getByRef(reqRow(ref).contract_ref).status == 'completed')
    check('RESTART second sweep does not repair or bill again', (function() sweep(); sweep(); return #W.applied == 1 and W.nextInv == 1 and W.balances['mechanic:main'] == 7260 end)())

    newWorld()
    local wo2 = toPaid('repair_basic')
    check('RESTART crash mid-commit: committing state replayed with absolute patch, no double effect', (function()
        W.mech.wos[1].commit_state = 'committing'  -- simulated crash after step 1
        W.veh[7001].cond.engine = 1000.0            -- simulated: patch had already been written before the crash
        sweep()
        local w = woOf(wo2); return w.state == 'completed' and w.commit_state == 'committed' and W.veh[7001].cond.engine == 1000.0 and W.mech.countEvents('service_committed', wo2) == 1 end)())
    check('RESTART admin reconcile of an already-committed order is a no-op', select(1, W.engine:AdminReconcile(wo2, 'tester')) == true and #W.applied <= 2)

    newWorld()
    local wo3 = toPaid('repair_basic')
    check('RECONCILE vehicle API failing repeatedly backs off and never double-applies', (function()
        W.applyFail = 3; advance(400); sweep(); local a1 = woOf(wo3).commit_attempts
        sweep()                                       -- before next_commit_at: no retry
        local a2 = woOf(wo3).commit_attempts
        advance(30); sweep(); advance(60); sweep(); advance(100); sweep()
        return a1 == 1 and a2 == 1 and woOf(wo3).state == 'completed' and #W.applied == 1 end)())
    check('RECONCILE stuck-commit alert mirrored after max attempts', (function()
        newWorld(); local wo4 = toPaid('repair_basic'); W.applyFail = 99; advance(400)
        for _ = 1, 8 do sweep(); advance(700) end
        for _, a in ipairs(W.audits) do if a.kind == 'mechanic_commit_stuck' then return true end end return false end)())

    -- customer disconnect
    newWorld()
    local _, v1 = request('101', 'repair'); local okC, wov = claimFirst('201'); diagnose('201', wov.workOrder)
    W.online['101'] = nil; sweep()
    check('DISCONNECT customer offline briefly: order is kept', woOf(wov.workOrder).state == 'diagnosing')
    advance(200); sweep()
    check('DISCONNECT customer offline too long: order and request cancelled, contract cancelled', woOf(wov.workOrder).state == 'cancelled' and reqRow(v1.ref).status == 'cancelled' and W.bstore.getByRef(reqRow(v1.ref).contract_ref).status == 'cancelled')
    check('DISCONNECT cancelled request frees the customer', W.mech.reqOpenByCustomer('101') == nil)
    -- customer drops with an open, unclaimed request
    newWorld(); local _, v2 = request('101', 'repair'); W.online['101'] = nil; sweep(); advance(200); sweep()
    check('DISCONNECT customer offline with an unclaimed request: cancelled', reqRow(v2.ref).status == 'cancelled')
    -- customer drops after paying: service still owed
    newWorld(); local wo5, ref5 = toPaid('repair_basic'); W.online['101'] = nil; advance(400); sweep()
    check('DISCONNECT customer offline AFTER paying: the paid service is still applied once', woOf(wo5).state == 'completed' and #W.applied == 1)
    -- mechanic disconnect
    newWorld(); local _, v3 = request('101', 'repair'); local _, wov3 = claimFirst('201'); diagnose('201', wov3.workOrder)
    W.engine:OnMechanicDropped('201'); W.online['201'] = nil
    sweep(); check('DISCONNECT mechanic offline briefly: order kept (grace)', woOf(wov3.workOrder).state == 'diagnosing')
    advance(200); sweep()
    check('DISCONNECT mechanic offline too long: order cancelled and request back on the board', woOf(wov3.workOrder).state == 'cancelled' and reqRow(v3.ref).status == 'open' and W.bstore.getByRef(reqRow(v3.ref).contract_ref).status == 'available')
    W.online['201'] = 2201
    check('DISCONNECT another mechanic can take the freed request', select(1, claimFirst('301')) == true)
    -- mechanic disconnects while payment pending / after payment
    newWorld(); local wo6, ref6 = toQuoted('repair', 'repair_basic'); W.engine:RespondQuote('101', true)
    W.engine:OnMechanicDropped('201'); W.online['201'] = nil; advance(700); W.broker:Sweep(); sweep()
    check('DISCONNECT mechanic lost during awaiting_payment: paid work survives claim release', (function()
        W.pay(woOf(wo6).invoice_ref); sweep(); advance(400); sweep()
        return woOf(wo6).state == 'completed' and #W.applied == 1 end)())
    check('DISCONNECT completed after claim lapse: contract is closed, not left on the board', (function()
        local c = W.bstore.getByRef(reqRow(ref6).contract_ref); return c.status == 'completed' or c.status == 'cancelled' end)())
    check('DISCONNECT lapsed claim cannot be re-claimed by a new mechanic after completion', select(1, W.engine:Claim('301', reqRow(ref6).contract_ref)) == false)
    -- stale
    newWorld(); local _, v7 = request('101', 'repair'); local _, wov7 = claimFirst('201')
    advance(1900); W.broker:Sweep(); sweep()
    check('STALE assigned order never started is released (not stuck forever)', woOf(wov7.workOrder).state == 'cancelled')
    -- broker fallback with live work
    newWorld(); local wo8, ref8 = toQuoted('repair', 'repair_basic'); W.engine:RespondQuote('101', true)
    advance(600); W.broker:Sweep(); advance(700); W.broker:Sweep(); advance(1000); W.broker:Sweep()
    check('FALLBACK with an invoice pending never auto-completes or repairs (work_in_progress retry)', #W.applied == 0 and reqRow(ref8).status == 'assigned')
    W.pay(woOf(wo8).invoice_ref); sweep(); advance(400); sweep()
    check('FALLBACK retry never beats paid work: service committed once, contract ends', woOf(wo8).state == 'completed' and #W.applied == 1)
    -- unpublished request (crash between the request insert and the broker publish)
    newWorld(); W.brokerDown = true
    do
        local row = { reference = 'MR-TEST0001', customer_cid = '101', hint = 'repair', status = 'open', active_key = '101', pos_x = 1.0, pos_y = 1.0, pos_z = 1.0, created_at = W.now, updated_at = W.now }
        W.mech.reqInsert(row)
        sweep()
        check('RESTART unpublished request stays open and retried while the broker is down', reqRow('MR-TEST0001').status == 'open' and reqRow('MR-TEST0001').contract_ref == nil)
        advance(W.cfg.Request.publishRetrySeconds + 1); sweep()
        check('RESTART unpublished request expires after the retry window (never stuck open)', reqRow('MR-TEST0001').status == 'expired' and W.mech.reqOpenByCustomer('101') == nil)
        local row2 = { reference = 'MR-TEST0002', customer_cid = '102', hint = 'repair', status = 'open', active_key = '102', pos_x = 1.0, pos_y = 1.0, pos_z = 1.0, created_at = W.now, updated_at = W.now }
        W.mech.reqInsert(row2); W.brokerDown = false; sweep()
        check('RESTART unpublished request is published exactly once when the broker returns', reqRow('MR-TEST0002').contract_ref ~= nil and (function() local n = 0 for _, r in pairs(W.bstore.rows) do if r.source_reference == 'MR-TEST0002' then n = n + 1 end end sweep(); return n == 1 end)())
    end
    -- restart: new engine instance over the same persisted rows re-publishes nothing twice
    newWorld(); local _, v9 = request('101', 'repair'); local nBefore = 0 for _ in pairs(W.bstore.rows) do nBefore = nBefore + 1 end
    sweep(); sweep()
    local nAfter = 0 for _ in pairs(W.bstore.rows) do nAfter = nAfter + 1 end
    check('RESTART reconcile never creates a second contract', nBefore == 1 and nAfter == 1)
    check('RESTART contract ended by broker while request open -> request expired by reconcile', (function()
        W.broker:AdminCancel(reqRow(v9.ref).contract_ref, 'test'); sweep()
        return reqRow(v9.ref).status == 'cancelled' or reqRow(v9.ref).status == 'expired' end)())
end

-- ======================================================================================== SECURITY
do
    newWorld()
    local wo, ref = toQuoted('repair', 'repair_basic')
    check('SECURITY forged mechanic CID: another employee cannot quote/diagnose someone else\'s order', select(2, W.engine:CreateQuote('301', wo, 'repair_basic', 9001)) == 'not_found' and select(2, diagnose('202', wo)) == 'not_found')
    check('SECURITY forged business: no input path accepts a business on quote/diagnose/service (resolved from the order)', (function()
        local w = woOf(wo); return w.business_type == 'mechanic' and w.business_id == 'main' end)())
    check('SECURITY forged vehicle: swapping the net id after diagnosis is rejected', (function()
        newWorld(); request('101', 'repair'); local _, v = claimFirst('201'); diagnose('201', v.workOrder)
        local why = select(2, W.engine:CreateQuote('201', v.workOrder, 'repair_basic', 9002)); return why == 'wrong_vehicle' end)())
    newWorld(); wo, ref = toQuoted('repair', 'repair_basic')
    check('SECURITY forged amount: invoice amount is always the stored server quote', (function()
        W.engine:RespondQuote('101', true); return W.invoices[woOf(wo).invoice_ref].amount == 7260 end)())
    check('SECURITY foreign work order: other business cannot finish / start it', select(2, W.engine:StartService('301', wo, 9001)) == 'not_found' and select(2, W.engine:FinishService('301', wo, 9001)) == 'not_found')
    check('SECURITY foreign work order: other customer cannot cancel', select(2, W.engine:CancelRequest('102', ref)) == 'not_found')
    check('SECURITY foreign work order: GetWork refuses a stranger', select(2, W.engine:GetWork('301', wo)) == 'not_found')
    check('SECURITY unknown work order ref', select(2, W.engine:BeginDiagnosis('201', 'WO-NOPE', 9001)) == 'not_found' and select(2, W.engine:GetWork('201', 'WO-NOPE')) == 'not_found')
    check('SECURITY non-string refs are safe', select(2, W.engine:CancelRequest('101', { })) == 'not_found' and select(2, W.engine:Claim('201', 42)) == 'invalid_request')
    check('SECURITY customer cannot self-complete (no customer path reaches FinishService)', select(2, W.engine:FinishService('101', wo, 9001)) == 'not_found')
    check('SECURITY wrong source resource: broker rejects a non-source resource creating mechanic contracts', select(2, W.broker:CreateContract('cm-taxi', { contractType = 'mechanic_request', sourceReference = 'MR-X' })) == 'untrusted_source')
    check('SECURITY wrong source resource: a non-provider cannot claim mechanic contracts', select(2, W.broker:Claim('cm-store', reqRow(ref).contract_ref, '999', {})) == 'forbidden')
    check('SECURITY broker callbacks cannot be driven with a forged source reference to repair', (function()
        local before = #W.applied
        local ok = W.engine:SourceComplete({ sourceReference = 'MR-FORGED', workerCharacterId = '201' })
        local ok2 = W.engine:SourceFallback({ sourceReference = 'MR-FORGED' })
        return ok == false and ok2 == false and #W.applied == before end)())
    check('SECURITY rate limit is enforced on every mutating entry', (function()
        W.rateBlock = true
        local a = select(2, W.engine:CreateQuote('201', wo, 'repair_basic', 9001)); local b = select(2, W.engine:RespondQuote('101', true))
        local c = select(2, W.engine:CancelRequest('101', ref)); local d = select(2, W.engine:StartService('201', wo, 9001))
        local e = select(2, W.engine:Board('201')); local f = select(2, W.engine:Claim('201', 'x')); local g = select(2, W.engine:BeginDiagnosis('201', wo, 9001))
        W.rateBlock = false
        return a == 'rate_limited' and b == 'rate_limited' and c == 'cooldown' and d == 'rate_limited' and e == 'rate_limited' and f == 'rate_limited' and g == 'rate_limited' end)())
    check('SECURITY audit events recorded for the full chain', (function()
        local kinds = {} for _, e in ipairs(W.mech.events) do kinds[e.kind] = true end
        return kinds.request_created and kinds.mechanic_claimed and kinds.diagnosis_started and kinds.quote_created and kinds.quote_approved and kinds.invoice_created end)())
    check('SECURITY audit events carry reference/actor, no secrets', (function()
        for _, e in ipairs(W.mech.events) do if e.detail and (e.detail:find('token') or e.detail:find('password') or e.detail:find('license')) then return false end end return true end)())
    -- admin recovery
    local okI, info = W.engine:AdminInspect(wo)
    check('ADMIN inspect returns request, work order and event history', okI and info.request.reference == ref and info.workOrder.reference == wo and #info.events > 0)
    check('ADMIN inspect by request reference', select(1, W.engine:AdminInspect(ref)) == true and select(2, W.engine:AdminInspect('NOPE')) == 'not_found')
    check('ADMIN cancel of an order with a pending invoice voids it', (function()
        local inv = woOf(wo).invoice_ref; local ok = W.engine:AdminCancel(wo, 'tester')
        return ok == true and W.invoices[inv].status == 'voided' and reqRow(ref).status == 'cancelled' end)())
    check('ADMIN cancel refuses to cancel a paid order (must reconcile instead)', (function()
        newWorld(); local wo2 = toPaid('repair_basic'); local ok, why = W.engine:AdminCancel(wo2, 'tester'); return ok == false and why == 'paid_use_reconcile' end)())
    check('ADMIN force reconcile commits a stuck paid order once', (function()
        newWorld(); local wo2 = toPaid('repair_basic'); local ok = W.engine:AdminReconcile(wo2, 'tester'); local again = W.engine:AdminReconcile(wo2, 'tester')
        return ok == true and again == true and #W.applied == 1 and woOf(wo2).state == 'completed' end)())
    check('ADMIN actions are audit-logged', (function() for _, e in ipairs(W.mech.events) do if e.kind == 'admin_reconcile' then return true end end return false end)())
    check('SECURITY diagnostic service: pay then finish applies no vehicle mutation', (function()
        newWorld(); request('101', 'diagnostic'); local _, v = claimFirst('201'); diagnose('201', v.workOrder)
        local ok, q = W.engine:CreateQuote('201', v.workOrder, 'diagnostic', 9001); W.engine:RespondQuote('101', true)
        W.pay(woOf(v.workOrder).invoice_ref); sweep()
        local okF = finishService(v.workOrder)
        return ok and q.amount == 1500 and okF == true and #W.applied == 0 and woOf(v.workOrder).state == 'completed' end)())
end

-- ======================================================================================== TUNING (mechanic work order <-> the REAL cm-tuning service)
-- REAL: the mechanic core above AND cm-tuning's real server code (config, service core, main.lua, service.lua exports, journal state machine) via
-- cm-tuning/tests/harness.lua. DOUBLES: as labelled there (FiveM runtime, SQL for vehicle mods, journal store) + this file's cm-billing / business doubles.
do
    local TH = dofile(core .. '/cm-tuning/tests/harness.lua')
    local vec = TH.vec
    local CAPS = { engine = 3, brakes = 3, transmission = 3, suspension = 3, armor = 4 }
    local TURBO = { toggles = { turbo = true } }
    local Wt

    local function bindTuning(world)
        Wt = world; W.tw = world
        local function tc(name)
            return function(...)
                if W.tuningDown then return false, 'unavailable' end
                local args = table.pack(...)
                local ok, a, b = pcall(function() return Wt.as('cm-mechanic', name, table.unpack(args, 1, args.n)) end)
                if not ok then return false, 'unavailable' end
                return a == true, b
            end
        end
        W.engine.tuning = {
            authorize = tc('CreateMechanicTuningAuthorization'), open = tc('OpenMechanicTuningSession'), quote = tc('GetMechanicTuningQuote'),
            validate = tc('ValidateMechanicTuningQuote'), bind = tc('BindMechanicTuningInvoice'), release = tc('ReleaseMechanicTuningInvoice'),
            paid = tc('MarkMechanicTuningPaid'), execute = tc('ExecuteMechanicTuning'), cancel = tc('CancelMechanicTuning'), status = tc('GetMechanicTuningStatus'),
        }
        Wt.invoices = setmetatable({}, { __index = function(_, ref) local i = W.invoices[ref]; return i and i.status end })   -- billing owner state, never a copy
        Wt.env.AddEventHandler('cm-tuning:service:quoted', function(ref) W.engine:OnTuningQuoted(ref) end)
    end
    local function tuningWorld(opts)
        newWorld(opts)
        local world = TH.build({ clock = W.now })
        world.addPlayer(2201, '201', vec(103.0, 100.0, 30.0)); world.addPlayer(2202, '202', vec(103.0, 100.0, 30.0)); world.addPlayer(1101, '101', vec(100.0, 100.0, 30.0))
        world.addVehicle(7001, { plate = 'PL7001', owner_character_id = '101', pos = vec(101.0, 100.0, 30.0), netId = 9001, entity = 19001 })
        world.addVehicle(7002, { plate = 'PL7002', owner_character_id = '102', pos = vec(501.0, 500.0, 30.0), netId = 9002, entity = 19002 })
        bindTuning(world)
        W.tuningDown = false
        return world
    end
    local function tadvance(s) advance(s); Wt.clock = W.now; Wt.timer = Wt.timer + s * 1000 end
    local function tuneMods() return Wt.vehicles[7001].mods and TH.json.decode(Wt.vehicles[7001].mods) or {} end
    local function invoiceCount() local n = 0 for _ in pairs(W.invoices) do n = n + 1 end return n end
    local function proposeFor(mcid, wo, shop, changes, caps)
        local ok, r = W.engine:StartTuning(mcid, wo, 9001, shop or 'chip', 2201)
        if not ok then return false, r end
        local token = Wt.lastClient('cm-tuning:client:openService').args[1].token
        Wt.timer = Wt.timer + 5000; Wt.clearEvents()
        Wt.fire(2201, 'cm-tuning:server:servicePropose', { token = token, caps = caps or CAPS, changes = changes })
        local denied = Wt.lastClient('cm-tuning:client:purchaseDenied')
        if denied then return false, denied.args[1] end
        return true
    end
    -- phone request ("tuning") -> claim -> scan -> tuning session -> proposal -> quoted order
    local function toTuningQuoted(changes, shop, mcid)
        mcid = mcid or '201'
        local ok, view = request('101', 'tuning'); assert(ok, 'request failed: ' .. tostring(view))
        local okC, wov = claimFirst(mcid); assert(okC, 'claim failed')
        local okD = diagnose(mcid, wov.workOrder); assert(okD, 'diagnose failed')
        local okP, why = proposeFor(mcid, wov.workOrder, shop, changes or TURBO); assert(okP, 'propose failed: ' .. tostring(why))
        return wov.workOrder, view.ref
    end
    local function toTuningPaid(changes)
        local wo, ref = toTuningQuoted(changes)
        assert(W.engine:RespondQuote('101', true), 'approve failed')
        assert(W.pay(woOf(wo).invoice_ref), 'pay failed')
        sweep()
        assert(woOf(wo).state == 'servicing', 'not servicing: ' .. tostring(woOf(wo).state))
        return wo, ref
    end

    -- ------------------------------------------------------------------ phone + catalogue
    tuningWorld()
    check('TUNING catalogue: tuning_request is enabled and owned by cm-tuning (no parts, never repair-priced)', W.cfg.Services.tuning_request.authority == 'cm-tuning' and W.cfg.Services.tuning_request.enabled ~= false and #W.cfg.Services.tuning_request.parts == 0)
    local okReq, rview = request('101', 'tuning', 'wheels please')
    check('TUNING PHONE a tuning request is just a mechanic request (phone owns no tuning data)', okReq == true and rview.state == 'searching' and reqRow(rview.ref).hint == 'tuning' and next(rview) ~= nil
        and rview.options == nil and rview.price == nil and rview.shop == nil)
    local okC, wov = claimFirst('201'); diagnose('201', wov.workOrder)
    check('TUNING offers: the tuning service is offered to the mechanic only as a tuning session', (function()
        local view = W.engine:MechanicView(woOf(wov.workOrder))
        for _, o in ipairs(view.offers) do if o.id == 'tuning_request' then return o.tuning == true end end return false end)())
    check('TUNING offers: without a cm-tuning adapter the tuning service is not offered at all', (function()
        local saved = W.engine.tuning; W.engine.tuning = nil
        local view = W.engine:MechanicView(woOf(wov.workOrder)); W.engine.tuning = saved
        for _, o in ipairs(view.offers) do if o.id == 'tuning_request' then return false end end return true end)())
    check('TUNING the repair quote path refuses tuning (price owner is cm-tuning)', select(2, W.engine:CreateQuote('201', wov.workOrder, 'tuning_request', 9001)) == 'use_tuning_session')

    -- ------------------------------------------------------------------ session authorization validation
    do
        local wo = wov.workOrder
        check('TUNING AUTH a different mechanic cannot start tuning on this order', select(2, W.engine:StartTuning('301', wo, 9001, 'chip', 2201)) == 'not_found')
        check('TUNING AUTH an unknown shop / repair category is refused', select(2, W.engine:StartTuning('201', wo, 9001, 'repair', 2201)) == 'invalid_service' and select(2, W.engine:StartTuning('201', wo, 9001, 'engine_rebuild', 2201)) == 'invalid_service')
        check('TUNING AUTH the wrong vehicle (another customer\'s car) is refused', select(2, W.engine:StartTuning('201', wo, 9002, 'chip', 2201)) == 'wrong_vehicle')
        check('TUNING AUTH no vehicle nearby', select(2, W.engine:StartTuning('201', wo, 99999, 'chip', 2201)) == 'vehicle_not_found')
        local perm = W.biz['mechanic:main'].staff['201']['mechanic.service_vehicle']
        W.biz['mechanic:main'].staff['201']['mechanic.service_vehicle'] = nil
        check('TUNING AUTH missing business permission is refused (checked against the business owner, not the client)', select(2, W.engine:StartTuning('201', wo, 9001, 'chip', 2201)) == 'forbidden')
        W.biz['mechanic:main'].staff['201']['mechanic.service_vehicle'] = perm
        W.pos[2201].x = 900.0
        check('TUNING AUTH the mechanic must be next to the vehicle', select(2, W.engine:StartTuning('201', wo, 9001, 'chip', 2201)) == 'too_far')
        W.pos[2201].x = 103.0
        check('TUNING AUTH the tuning session must belong to the mechanic\'s own character (wrong source refused by cm-tuning)', select(2, W.engine:StartTuning('201', wo, 9001, 'chip', 2202)) == 'wrong_mechanic')
        check('TUNING AUTH cm-tuning unavailable: no session, no state change', (function() W.tuningDown = true; local ok, why = W.engine:StartTuning('201', wo, 9001, 'chip', 2201); W.tuningDown = false
            return ok == false and woOf(wo).state == 'diagnosing' and woOf(wo).service_id == nil end)())
        check('TUNING AUTH a valid start opens the tuning UI for the mechanic and links the order', W.engine:StartTuning('201', wo, 9001, 'chip', 2201) == true and woOf(wo).service_id == 'tuning_request' and Wt.lastClient('cm-tuning:client:openService').src == 2201)
        W.engine:AbandonWork('201', wo)
    end

    -- ------------------------------------------------------------------ the happy path: one authorization, quote, invoice, payment, modification
    tuningWorld()
    local wo, ref = toTuningQuoted(TURBO)
    local w = woOf(wo)
    check('TUNING QUOTE the order is quoted from the cm-tuning proposal (price from cm-tuning, not the mechanic formulas)', w.state == 'quoted' and w.quote_amount == 25000 and w.service_id == 'tuning_request')
    check('TUNING QUOTE the customer is shown the server quote with a description (no client price anywhere)', (function()
        for _, n in ipairs(W.notes) do if n.cid == '101' and n.kind == 'quote' then return n.payload.amount == 25000 and n.payload.detail:find('Turbo') ~= nil end end return false end)())
    local jr
    for _, r in ipairs(Wt.store.rows) do jr = r end
    check('TUNING QUOTE the journal binds work order, mechanic, customer, business, vehicle_id and the amount', jr.work_order_ref == wo and jr.mechanic_cid == '201' and jr.customer_cid == '101' and jr.business_type == 'mechanic' and jr.business_id == 'main' and jr.vehicle_id == 7001 and jr.amount == 25000 and jr.status == 'quoted')
    check('TUNING QUOTE nothing is installed and nobody is charged before approval', Wt.vehicles[7001].mods == nil and invoiceCount() == 0 and #Wt.charges == 0)
    local okA = W.engine:RespondQuote('101', true)
    local w2 = woOf(wo)
    check('TUNING APPROVE the customer approval creates exactly ONE invoice to the mechanic business at the quoted price', okA == true and invoiceCount() == 1 and W.invoices[w2.invoice_ref].amount == 25000 and W.invoices[w2.invoice_ref].dest == 'mechanic:main'
        and W.invoices[w2.invoice_ref].data.metadata['mechanic.tuning'] == jr.reference)
    check('TUNING APPROVE the journal is bound to that invoice', (function() for _, r in ipairs(Wt.store.rows) do if r.reference == jr.reference then return r.status == 'invoiced' and r.invoice_ref == w2.invoice_ref end end end)())
    check('TUNING APPROVE a duplicate approval / reconcile creates no second invoice', select(2, W.engine:RespondQuote('101', true)) == 'not_found' and (function() sweep(); sweep(); return invoiceCount() == 1 end)())
    check('TUNING PAY unpaid invoice: no payment detection, nothing installed, tuning refuses a direct execute', (function() sweep()
        return woOf(wo).state == 'awaiting_payment' and Wt.vehicles[7001].mods == nil and select(2, Wt.as('cm-mechanic', 'ExecuteMechanicTuning', jr.reference)) == 'not_paid' end)())
    check('TUNING PAY the customer pays through cm-billing (business balance credited by billing, not by tuning)', W.pay(w2.invoice_ref) == true and W.balances['mechanic:main'] == 25000 and W.customerMoney['101'] == 75000)
    sweep()
    check('TUNING PAY payment is verified against cm-billing by BOTH the mechanic order and cm-tuning (paid)', woOf(wo).state == 'servicing' and woOf(wo).paid_at ~= nil and (function() for _, r in ipairs(Wt.store.rows) do if r.reference == jr.reference then return r.status == 'paid' end end end)())
    check('TUNING PAY still nothing installed until the service is carried out', Wt.vehicles[7001].mods == nil)
    local okF = finishService(wo)
    check('TUNING APPLY the paid service is applied exactly once and the order completes', okF == true and woOf(wo).state == 'completed' and woOf(wo).commit_state == 'committed' and tuneMods().turbo == true and Wt.modWrites == 1)
    check('TUNING APPLY journal committed, request completed, no repair patch was applied to the vehicle', (function() for _, r in ipairs(Wt.store.rows) do if r.reference == jr.reference then return r.status == 'committed' end end end)() and #W.applied == 0 and reqRow(ref).status == 'completed')
    check('TUNING APPLY exactly one payment and no direct cm-tuning charge anywhere', invoiceCount() == 1 and #Wt.charges == 0 and #Wt.refunds == 0 and W.balances['mechanic:main'] == 25000)
    check('TUNING APPLY replaying finish / reconcile / commit never applies or invoices again', (function() finishService(wo); sweep(); W.engine:AdminReconcile(wo, 'tester'); return Wt.modWrites == 1 and invoiceCount() == 1 and #W.applied == 0 end)())
    check('TUNING APPLY audit: authorization, quote, invoice, payment and commit are in the timeline', (function()
        local kinds = {} for _, e in ipairs(W.mech.events) do kinds[e.kind] = true end
        return kinds.tuning_authorized and kinds.quote_created and kinds.quote_approved and kinds.invoice_created and kinds.payment_confirmed and kinds.service_committed end)())

    -- ------------------------------------------------------------------ quote integrity / re-quote
    tuningWorld()
    local woS = toTuningQuoted(TURBO)
    Wt.vehicles[7001].mods = TH.json.encode({ mods = { ['11'] = 1 } })        -- the vehicle is tuned (self-service) after the quote
    local okS, whyS = W.engine:RespondQuote('101', true)
    check('TUNING STALE the vehicle changed after the quote: approval refused, order back to diagnosing, no invoice', okS == false and whyS == 'quote_changed' and woOf(woS).state == 'diagnosing' and invoiceCount() == 0 and woOf(woS).service_id == nil)
    check('TUNING STALE ... the old quote is dead (journal cancelled) and the mechanic can re-quote against the current state', (function()
        for _, r in ipairs(Wt.store.rows) do if r.status ~= 'cancelled' then return false end end
        local ok = proposeFor('201', woS, 'chip', { slots = { brakes = 1 } })
        return ok == true and woOf(woS).state == 'quoted' and woOf(woS).quote_amount == 16000 end)())
    check('TUNING STALE the new quote is approved and applied without touching the earlier engine upgrade', (function()
        W.engine:RespondQuote('101', true); W.pay(woOf(woS).invoice_ref); sweep(); finishService(woS)
        local m = tuneMods(); return woOf(woS).state == 'completed' and m.mods['12'] == 1 and m.mods['11'] == 1 end)())

    tuningWorld()
    local woO = toTuningQuoted(TURBO)
    W.engine:RespondQuote('101', false)
    check('TUNING DECLINE the customer declines: back to diagnosing, quote journal cancelled, vehicle untouched, nothing invoiced', woOf(woO).state == 'diagnosing' and invoiceCount() == 0 and Wt.vehicles[7001].mods == nil
        and (function() for _, r in ipairs(Wt.store.rows) do if r.status ~= 'cancelled' then return false end end return #Wt.store.rows == 1 end)())
    check('TUNING DECLINE ... a new tuning session can start on the same order', proposeFor('201', woO, 'workshop', { color = 27 }) == true and woOf(woO).state == 'quoted' and woOf(woO).quote_amount == 2500)
    advance(W.cfg.Quote.validSeconds + 5); Wt.clock = W.now
    check('TUNING EXPIRY an unanswered quote expires: the order reopens, the journal row is cancelled', (function() sweep(); return woOf(woO).state == 'diagnosing' and (function() for _, r in ipairs(Wt.store.rows) do if r.status == 'quoted' then return false end end return true end)() end)())

    tuningWorld()
    local woL = toTuningQuoted(TURBO)
    W.engine:RespondQuote('101', false)
    -- HIGH VALUE: the old 50,000 cap no longer splits legitimate jobs. Engine L4 + turbo (73,000) is priced by cm-tuning, one quote.
    check('TUNING HIGH engine L4 + turbo (73,000, previously refused) is now accepted at cm-tuning\'s exact price', proposeFor('201', woL, 'chip', { slots = { engine = 3 }, toggles = { turbo = true } }) == true and woOf(woL).quote_amount == 73000)
    W.engine:RespondQuote('101', false)
    check('TUNING HIGH the largest single performance item (48,000) is accepted at its exact price', proposeFor('201', woL, 'chip', { slots = { engine = 3 } }) == true and woOf(woL).quote_amount == 48000)
    W.engine:RespondQuote('101', false)
    tuningWorld(); woL = toTuningQuoted(TURBO); W.engine:RespondQuote('101', false)
    -- the FULL performance bundle (engine 4 + brakes 4 + transmission 4 + suspension 4 + armor 5 + tyres 4 + turbo) is the largest chip quote: 242,000
    local FULLCHIP = { slots = { engine = 3, brakes = 3, transmission = 3, suspension = 3, armor = 4 }, tyres = 4, toggles = { turbo = true } }
    check('TUNING HIGH the maximum performance bundle is quoted by cm-tuning as ONE quote (242,000) within the billing limit', proposeFor('201', woL, 'chip', FULLCHIP) == true and woOf(woL).quote_amount == 242000 and 242000 <= W.billingLimit)
    check('TUNING HIGH one authorization -> one quote -> one invoice: approval creates exactly one invoice for the full amount (no split)', (function()
        W.customerMoney['101'] = 1000000
        local ok = W.engine:RespondQuote('101', true)
        return ok == true and invoiceCount() == 1 and W.invoices[woOf(woL).invoice_ref].amount == 242000 and W.invoices[woOf(woL).invoice_ref].data.metadata['mechanic.tuning'] ~= nil end)())
    check('TUNING HIGH the invoice is payable through billing and reconciles: paid -> servicing, business credited once, customer debited once', (function()
        local bBefore, cBefore = W.balances['mechanic:main'], W.customerMoney['101']
        local paid = W.pay(woOf(woL).invoice_ref); sweep()
        return paid == true and W.balances['mechanic:main'] == bBefore + 242000 and W.customerMoney['101'] == cBefore - 242000 and woOf(woL).state == 'servicing' and woOf(woL).paid_at ~= nil end)())
    check('TUNING HIGH exactly one payment and no direct cm-tuning charge for the high-value job', invoiceCount() == 1 and #Wt.charges == 0)

    tuningWorld()
    local woW = toTuningQuoted(TURBO); W.engine:RespondQuote('101', false)
    local WCAPS = { wheels = 200, frontBumper = 200, rearBumper = 200 }
    check('TUNING HIGH a single wheel at the 200-index ceiling (1,105,500) fits the provider limit and is quoted exactly', proposeFor('201', woW, 'workshop', { slots = { wheels = 200 } }, WCAPS) == true and woOf(woW).quote_amount == 1105500 and 1105500 <= W.billingLimit)
    W.engine:RespondQuote('101', false)
    local okBig, whyBig = proposeFor('201', woW, 'workshop', { slots = { wheels = 200, frontBumper = 200, rearBumper = 200 } }, WCAPS)
    check('TUNING CAP a bundle above even the provider limit (2,713,500) is refused with an explicit reason; the order stays diagnosing; nothing is billed, clamped or split', okBig == false and whyBig:find('maximum invoice') ~= nil and woOf(woW).state == 'diagnosing' and invoiceCount() == 0)

    -- ------------------------------------------------------------------ invoice void / expiry before payment
    tuningWorld()
    local woV = toTuningQuoted(TURBO); W.engine:RespondQuote('101', true)
    local invV = woOf(woV).invoice_ref
    advance(W.cfg.Quote.invoiceExpirySeconds + 5); Wt.clock = W.now
    W.invoices[invV].status = 'expired'; sweep()
    check('TUNING INVOICE an expired unpaid invoice returns the order to diagnosing and kills the quote journal', woOf(woV).state == 'diagnosing' and (function() for _, r in ipairs(Wt.store.rows) do if r.status ~= 'cancelled' then return false end end return true end)() and Wt.vehicles[7001].mods == nil)
    tuningWorld()
    local woC, refC = toTuningQuoted(TURBO); W.engine:RespondQuote('101', true)
    local okX = W.engine:CancelRequest('101', refC)
    check('TUNING CANCEL the customer cancels before paying: invoice voided, journal cancelled, nothing installed', okX == true and woOf(woC).state == 'cancelled' and W.invoices[woOf(woC).invoice_ref].status == 'voided' and Wt.vehicles[7001].mods == nil
        and (function() for _, r in ipairs(Wt.store.rows) do if r.status ~= 'cancelled' then return false end end return true end)())

    -- ------------------------------------------------------------------ forward-only recovery after payment
    tuningWorld()
    local woP = toTuningPaid(TURBO)
    check('TUNING FORWARD a paid tuning order cannot be abandoned or cancelled by anyone (no refund API)', select(2, W.engine:AbandonWork('201', woP)) == 'invalid_state' and select(1, W.engine:CancelRequest('101', woOf(woP).request_ref)) == false
        and select(2, W.engine:AdminCancel(woP, 'tester')) == 'paid_use_reconcile')
    W.tuningDown = true
    local okD, whyD = finishService(woP)
    check('TUNING FORWARD cm-tuning unavailable at commit: the order stays PAID/servicing, retry is scheduled, nothing is lost or duplicated', okD == false and whyD == 'vehicle_service_failed' and woOf(woP).state == 'servicing' and woOf(woP).commit_attempts == 1 and Wt.vehicles[7001].mods == nil and invoiceCount() == 1)
    W.tuningDown = false
    advance(60); tadvance(0); sweep()
    check('TUNING FORWARD cm-tuning returns: the scheduled recovery applies the paid modification exactly once and completes the order', woOf(woP).state == 'completed' and tuneMods().turbo == true and Wt.modWrites == 1)

    tuningWorld()
    local woR = toTuningPaid(TURBO)
    local realExecute = W.engine.tuning.execute
    W.engine.tuning.execute = function(r) realExecute(r); return false, 'unavailable' end      -- committed in cm-tuning, the response was lost
    local okLost = finishService(woR)
    check('TUNING RESPONSE LOSS tuning committed but the mechanic never heard: order not completed yet, modification applied once', okLost == false and woOf(woR).state == 'servicing' and Wt.modWrites == 1)
    W.engine.tuning.execute = realExecute
    advance(60); sweep()
    check('TUNING RESPONSE LOSS the retry replays the committed result: order completes, still ONE modification, no second charge', woOf(woR).state == 'completed' and Wt.modWrites == 1 and invoiceCount() == 1 and #Wt.charges == 0)

    tuningWorld()
    local woD = toTuningPaid(TURBO)
    W.online['201'] = nil; W.online['101'] = nil          -- mechanic AND customer disconnect after payment
    advance(W.cfg.Commit.autoCommitAfterSeconds + 5); tadvance(0); sweep()
    check('TUNING DISCONNECT mechanic and customer gone after payment: the server still applies the paid service (auto-commit), once', woOf(woD).state == 'completed' and tuneMods().turbo == true and Wt.modWrites == 1)

    tuningWorld()
    local woT = toTuningPaid(TURBO)
    local keep = { store = Wt.store, clock = W.now }
    local raw = Wt.vehicles[7001].mods
    local Wt2 = TH.build(keep)
    Wt2.addPlayer(2201, '201', vec(103.0, 100.0, 30.0))
    Wt2.addVehicle(7001, { plate = 'PL7001', owner_character_id = '101', pos = vec(101.0, 100.0, 30.0), netId = 9001, entity = 19001, mods = raw })
    bindTuning(Wt2)
    advance(W.cfg.Commit.autoCommitAfterSeconds + 5); tadvance(0); sweep()
    check('TUNING RESTART cm-tuning restarted between payment and apply: the journal survives and the paid service completes forward, once', woOf(woT).state == 'completed' and tuneMods().turbo == true and Wt.modWrites == 1)

    tuningWorld()
    local woM = toTuningPaid(TURBO)
    Wt.vehicles[7001].owner_character_id = '102'          -- ownership changes AFTER payment: the customer paid, the service still lands
    advance(W.cfg.Commit.autoCommitAfterSeconds + 5); tadvance(0); sweep()
    check('TUNING FORWARD an ownership change after payment does not void the paid service', woOf(woM).state == 'completed' and tuneMods().turbo == true)

    -- cm-tuning briefly unavailable while payment is being detected: money is taken, the order only waits
    tuningWorld()
    local woW, _ = toTuningQuoted(TURBO); W.engine:RespondQuote('101', true); W.pay(woOf(woW).invoice_ref)
    W.tuningDown = true; sweep()
    check('TUNING FORWARD cm-tuning unavailable while payment is detected: the order stays awaiting_payment (retry), never cancelled or refunded', woOf(woW).state == 'awaiting_payment' and W.invoices[woOf(woW).invoice_ref].status == 'paid')
    W.tuningDown = false; sweep()
    check('TUNING FORWARD ... and proceeds to servicing when cm-tuning returns', woOf(woW).state == 'servicing')

    -- forged / out-of-order calls cannot skip the payment
    tuningWorld()
    local woF = toTuningQuoted(TURBO)
    local refF; for _, r in ipairs(Wt.store.rows) do refF = r.reference end
    check('TUNING SECURITY an untrusted resource cannot bind, pay or execute a mechanic authorization', select(2, Wt.as('cm-trade', 'MarkMechanicTuningPaid', refF, 'INV-1')) == 'forbidden' and select(2, Wt.as('cm-phone', 'ExecuteMechanicTuning', refF)) == 'forbidden')
    check('TUNING SECURITY a "paid" claim with no billing evidence is refused', (function()
        Wt.as('cm-mechanic', 'BindMechanicTuningInvoice', refF, 'INV-FAKE')
        local ok, why = Wt.as('cm-mechanic', 'MarkMechanicTuningPaid', refF, 'INV-FAKE'); return ok == false and (why == 'not_paid' or why == 'billing_unavailable') and Wt.vehicles[7001].mods == nil end)())
    check('TUNING SECURITY the client has no event that applies, pays or authorizes tuning', (function() for name in pairs(Wt.netHandlers) do if name:find('Mechanic') or name:find('paid') or name:find('execute') or name:find('authoriz') then return false end end return true end)())
    check('TUNING SECURITY a customer cannot answer a quote that is not theirs (resolved from their own character)', select(2, W.engine:RespondQuote('102', true)) == 'not_found')

    -- existing repair flow is unchanged next to the tuning machinery
    tuningWorld()
    local woRep = toPaid('repair_basic')
    check('TUNING REGRESSION the repair flow still pays, then applies the absolute patch through cm-vehicles (no tuning call)', finishService(woRep) == true and #W.applied == 1 and #Wt.store.rows == 0 and woOf(woRep).state == 'completed')
end

print(('\ncm-mechanic selftest: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
