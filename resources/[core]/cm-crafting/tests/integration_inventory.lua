-- cm-crafting <-> cm-inventory integration test (deterministic, no FiveM, no database).
--   lua tests/integration_inventory.lua        (run from resources/[core]/cm-crafting)
--
-- REAL: cm-crafting core + config; the PRODUCTION inventory adapter (the `xcall` + `inventory` block is extracted verbatim from
--       server/main.lua and compiled here); the REAL cm-inventory craft code (server/craft.lua + the inventory internals it uses),
--       loaded through ../cm-inventory/tests/craft_harness.lua.
-- DOUBLES (labelled): the FiveM runtime, cm-items definitions, the SQL layer under cm-inventory (in-memory, transactional undo), and the
--       cm-crafting session store (mirrors server/store.lua). Real MySQL semantics are NOT exercised here.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local invHere = here .. '/../cm-inventory'
CMCrafting = {}
dofile(here .. '/config.lua')
dofile(here .. '/server/core.lua')
local H = dofile(invHere .. '/tests/craft_harness.lua')(invHere)
local json, deepcopy = H.json, H.deepcopy
local function ser(v)   -- loadable Lua-literal encoding for the session snapshot (same as selftest.lua)
    if type(v) == 'table' then
        local keys = {} for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local o = {} for _, k in ipairs(keys) do o[#o + 1] = '[' .. (type(k) == 'number' and tostring(k) or string.format('%q', tostring(k))) .. ']=' .. ser(v[k]) end
        return '{' .. table.concat(o, ',') .. '}'
    elseif type(v) == 'string' then return string.format('%q', v) end
    return tostring(v)
end

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
local function deser(s) local f = load('return ' .. s); return f and f() or nil end

-- session store double (mirrors server/store.lua)
local function newStore()
    local S = { sessions = {}, events = {} }
    local function copy(r) if not r then return nil end local c = {} for k, v in pairs(r) do c[k] = v end return c end
    local function inList(l, v) for _, x in ipairs(l) do if x == v then return true end end return false end
    local function find(ref) for _, s in ipairs(S.sessions) do if s.reference == ref then return s end end end
    function S.sessInsert(s)
        for _, x in ipairs(S.sessions) do
            if s.idem_key and x.idem_key == s.idem_key then return nil, 'duplicate_key' end
            if s.active_key and x.active_key == s.active_key then return nil, 'already_crafting' end
        end
        local c = copy(s); c.id = #S.sessions + 1; S.sessions[#S.sessions + 1] = c; return c.id
    end
    function S.sessGet(ref) return copy(find(ref)) end
    function S.sessGetByIdem(k) for _, x in ipairs(S.sessions) do if x.idem_key == k then return copy(x) end end end
    function S.sessActiveByChar(cid) for _, x in ipairs(S.sessions) do if x.active_key == cid and (x.status == 'active' or x.status == 'committing') then return copy(x) end end end
    function S.sessListOpen() local o = {} for _, x in ipairs(S.sessions) do if x.status == 'active' or x.status == 'committing' then o[#o + 1] = copy(x) end end return o end
    function S.sessCas(ref, from, patch)
        local s = find(ref); if not s or not inList(from, s.status) then return 0 end
        for k, v in pairs(patch) do if v == false then s[k] = nil else s[k] = v end end
        return 1
    end
    function S.eventInsert(e)
        if e.key then for _, x in ipairs(S.events) do if x.key == e.key then return false end end end
        S.events[#S.events + 1] = copy(e); return true
    end
    function S.eventList(ref) local o = {} for _, e in ipairs(S.events) do if e.session_ref == ref then o[#o + 1] = e end end return o end
    function S.count(kind, ref) local n = 0 for _, e in ipairs(S.events) do if e.kind == kind and (not ref or e.session_ref == ref) then n = n + 1 end end return n end
    return S
end

-- PRODUCTION adapter: extract the exact source from server/main.lua
local function readAll(p) local f = assert(io.open(p, 'rb')); local s = f:read('a'); f:close(); return s end
local mainSrc = readAll(here .. '/server/main.lua')
local function slice(from, to)
    local a = assert(mainSrc:find(from, 1, true), 'marker missing: ' .. from)
    local b = assert(mainSrc:find(to, a, true), 'marker missing: ' .. to)
    return mainSrc:sub(a, b - 1)
end
local adapterSrc = slice('local function xcall', 'local function jsonEncode') .. '\n' .. slice('local capability =', 'local hits = {}') .. '\nreturn inventory, capability\n'

local OWNER = 'cm-test-craft'
local state
local function build(opts)
    opts = opts or {}
    local db = opts.db or H.newDb()
    db.addChar(1)
    local inv = H.newWorld(db, {})
    inv.invoker = 'cm-crafting'
    local started = { ['cm-inventory'] = opts.inventoryStopped ~= true }
    local exportsBridge = setmetatable({}, { __index = function(_, resource)
        if resource ~= 'cm-inventory' then return setmetatable({}, { __index = function() return function() error('no export') end end }) end
        return setmetatable({}, { __index = function(_, name)
            local fn = inv.registry[name]
            if not fn or (opts.hideExports and opts.hideExports[name]) then return function() error('No such export ' .. name) end end
            return function(self, ...) return fn(self, ...) end
        end })
    end })
    local aenv = { exports = exportsBridge, GetResourceState = function(r) return started[r] and 'started' or 'stopped' end,
        os = os, pcall = pcall, table = table, type = type, tostring = tostring, tonumber = tonumber, string = string }
    local adapter, capability = assert(load(adapterSrc, '@cm-crafting/server/main.lua(adapter)', 't', aenv))()
    local S = { db = db, inv = inv, adapter = adapter, capability = capability, started = started, now = 1000000, store = opts.store or newStore() }
    local cfg = deepcopy(CMCrafting.Config)
    cfg.TrustedOwners = { [OWNER] = true }
    local seq = 4242
    S.core = CMCrafting.Core.New({
        cfg = cfg, store = S.store, now = function() return S.now end,
        rand = function(a, b) seq = (seq * 1103515245 + 12345) % 2147483648; if a then return (seq // 65536) % (b - a + 1) + a end return 0.5 end,
        encode = ser, decode = deser,
        chars = { sourceOf = function(cid) return 1101 end, position = function() return { x = 100.0, y = 101.0, z = 30.0, bucket = 0 } end },
        items = { exists = function(n) return H.ITEMS[n] ~= nil end, validateMetadata = function() return true end },
        inventory = adapter,
        owners = { started = function() return true end, call = function() return true, true end },
        audit = function() end, rate = function() return true end,
    })
    local ok, why = S.core:RegisterRecipe(OWNER, { id = 'test:ingot', label = 'Ingot', category = 'test', durationSeconds = 10, batch = { min = 1, max = 5 }, handcraft = true,
        inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'iron_ingot', amount = 1 } }, tools = { { item = 'hammer', durabilityUse = 2 } } })
    S.recipeOk, S.recipeWhy = ok, why
    db.clear(1)
    db.give(1, 'pocket-1', 'iron_ore', 10); db.give(1, 'pocket-2', 'hammer', 1, { durability = 50 })
    return S
end
local function hammer(S) for _, r in ipairs(S.db.rowsOf(1)) do if r.item_name == 'hammer' then return json.decode(r.metadata).durability end end end
local function begin(S, qty) return S.core:Begin(OWNER, '1', 'test:ingot', qty or 1, nil, {}) end
local function ready(S, ref) S.now = S.store.sessGet(ref).ready_at end

-- ============================================================ adapter contract detection
do
    local S = build()
    check('SETUP recipe registered against the real cm-items double', S.recipeOk == true, S.recipeWhy)
    check('CONTRACT production adapter detects the real inventory owner (IsCraftingSettlementReady = true)', S.adapter.ready() == true)
    local S2 = build({ inventoryStopped = true })
    check('CONTRACT inventory stopped -> not ready (fail closed)', S2.adapter.ready() == false)
    local S3 = build({ hideExports = { GetCraftTransactionStatus = true } })
    check('CONTRACT missing owner export -> not ready (fail closed)', S3.adapter.ready() == false)
    local okB, whyB = begin(S2)
    check('CONTRACT BeginCraft reports settlement_unavailable only when the owner is unavailable', okB == false and whyB == 'settlement_unavailable')
    S2.started['cm-inventory'] = true; S2.capability.at = 0
    local okB2, resB2 = begin(S2)
    check('CONTRACT BeginCraft no longer reports settlement_unavailable once the owner is available', okB2 == true, resB2)
end

-- ============================================================ BeginCraft real validation
do
    local S = build()
    S.db.clear(1); S.db.give(1, 'pocket-2', 'hammer', 1, { durability = 50 })
    local ok, why = begin(S)
    check('BEGIN real inventory validation: missing input -> insufficient_input', ok == false and why == 'insufficient_input', why)
    S.db.clear(1); S.db.give(1, 'pocket-1', 'iron_ore', 4)
    ok, why = begin(S)
    check('BEGIN real inventory validation: missing tool -> tool_missing', ok == false and why == 'tool_missing', why)
    S.db.give(1, 'pocket-2', 'hammer', 1, { durability = 1 })
    ok, why = begin(S)
    check('BEGIN real inventory validation: worn-out tool -> tool_durability', ok == false and why == 'tool_durability', why)
    local before = S.db.fingerprint()
    check('BEGIN consumes nothing', S.db.fingerprint() == before and #S.db.ledger == 0)
end

-- ============================================================ CompleteCraft real settlement
do
    local S = build()
    local ok, res = begin(S, 2)
    local ref = res.reference
    ready(S, ref)
    local okC, resC = S.core:Complete(OWNER, ref, '1', {})
    check('COMPLETE real atomic settlement completes the session', okC == true and resC.status == 'completed', resC)
    check('COMPLETE inputs consumed, output created, tool worn in one transaction', S.db.count(1, 'iron_ore') == 6 and S.db.count(1, 'iron_ingot') == 2 and hammer(S) == 46)
    check('COMPLETE inventory ledger holds the session reference', S.db.ledger[1] and S.db.ledger[1].reference == ref and S.adapter.status(ref) == 'committed')
    check('COMPLETE session is completed only after inventory committed', S.store.sessGet(ref).status == 'completed' and S.store.count('inventory_committed', ref) == 1)
    local fp = S.db.fingerprint()
    local okR, resR, tag = S.core:Complete(OWNER, ref, '1', {})
    check('COMPLETE repeat is a replay and mutates nothing', okR == true and tag == 'replayed' and S.db.fingerprint() == fp)
end

-- ============================================================ reconciliation with the real contract
do
    -- response lost: inventory committed but the caller never saw it
    local S = build()
    local _, res = begin(S); local ref = res.reference; ready(S, ref)
    local realExecute = S.adapter.execute
    S.core.inventory = setmetatable({ execute = function(r, c, t) realExecute(r, c, t); return false, 'unavailable' end }, { __index = S.adapter })
    local okC, why = S.core:Complete(OWNER, ref, '1', {})
    check('RECONCILE lost response leaves the session committing', okC == false and why == 'reconciling' and S.store.sessGet(ref).status == 'committing')
    check('RECONCILE inventory really committed once', S.db.count(1, 'iron_ingot') == 1 and #S.db.ledger == 1)
    S.core.inventory = S.adapter
    S.core:Sweep()
    check('RECONCILE committed ledger completes the session without re-applying', S.store.sessGet(ref).status == 'completed' and S.db.count(1, 'iron_ingot') == 1 and #S.db.ledger == 1 and hammer(S) == 48)

    -- not applied: inventory outage at commit, then it heals; the SAME reference is retried
    local S2 = build()
    local _, res2 = begin(S2); local ref2 = res2.reference; ready(S2, ref2)
    S2.db.failOn = function(sql) return sql:find('^INSERT INTO cm_inventory_transactions') end   -- DB fails mid-transaction: everything rolls back
    local ok2, why2 = S2.core:Complete(OWNER, ref2, '1', {})
    S2.db.failOn = nil
    check('RECONCILE inventory outage keeps the session recoverable (no guess, nothing applied)', ok2 == false and S2.db.count(1, 'iron_ingot') == 0 and #S2.db.ledger == 0)
    check('RECONCILE session is committing and the ledger says not_applied', S2.store.sessGet(ref2).status == 'committing' and S2.adapter.status(ref2) == 'not_applied')
    S2.now = S2.now + 100
    S2.core:Sweep()
    check('RECONCILE not_applied is retried through the SAME reference and commits once', S2.store.sessGet(ref2).status == 'completed' and #S2.db.ledger == 1 and S2.db.ledger[1].reference == ref2 and S2.db.count(1, 'iron_ingot') == 1)

    -- definite refusal by the owner at commit time (tool destroyed after the pre-validation) fails the session cleanly
    local S3 = build()
    local _, res3 = begin(S3); local ref3 = res3.reference; ready(S3, ref3)
    local realValidate = S3.adapter.validate
    S3.core.inventory = setmetatable({ validate = function() return true end }, { __index = S3.adapter })
    S3.db.clear(1); S3.db.give(1, 'pocket-1', 'iron_ore', 10)   -- the tool vanished between validation and commit
    local ok3, why3 = S3.core:Complete(OWNER, ref3, '1', {})
    check('RECONCILE a definite owner refusal fails the session, nothing consumed', ok3 == false and why3 == 'tool_missing' and S3.store.sessGet(ref3).status == 'failed' and S3.db.count(1, 'iron_ore') == 10 and #S3.db.ledger == 0)
    check('RECONCILE no new reference is generated for a retry', S3.store.sessGet(ref3).reference == ref3)
end

print(('\ncm-crafting <-> cm-inventory integration: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
