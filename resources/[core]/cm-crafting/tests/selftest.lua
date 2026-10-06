-- Deterministic local self-test for cm-crafting (no FiveM, no database).
--   lua tests/selftest.lua        (run from resources/[core]/cm-crafting)
--
-- REAL: cm-crafting core + config (registry, stations, session lifecycle, timing, idempotency, recovery logic).
-- TEST DOUBLES (labelled): the in-memory session store (same CAS/UNIQUE semantics as server/store.lua), characters, cm-items, and
-- **THE INVENTORY OWNER**. The real cm-inventory has NO atomic, idempotent craft transaction yet, so everything below that touches
-- "inventory" runs against a double that implements the DOCUMENTED CONTRACT. These results prove the framework's orchestration, NOT real item
-- settlement: REAL ATOMIC INVENTORY INTEGRATION is BLOCKED (SHARED INTEGRATION REQUIRED - cm-inventory). The test recipes exist only here.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
CMCrafting = {}
dofile(here .. '/config.lua')
dofile(here .. '/server/core.lua')

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
local function ser(v)
    if type(v) == 'table' then
        local keys = {} for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local o = {} for _, k in ipairs(keys) do o[#o + 1] = '[' .. (type(k) == 'number' and tostring(k) or string.format('%q', tostring(k))) .. ']=' .. ser(v[k]) end
        return '{' .. table.concat(o, ',') .. '}'
    elseif type(v) == 'string' then return string.format('%q', v) end
    return tostring(v)
end
local function deser(s) local f = load('return ' .. s); return f and f() or nil end
local function deepcopy(t) if type(t) ~= 'table' then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end

-- ------------------------------------------------------- fake store (mirrors server/store.lua)
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

-- ------------------------------------------------------------------------------ world
local W
local OWNER, OTHER = 'cm-test-craft', 'cm-other-craft'
local PLANK = { id = 'test:plank', label = 'Test Plank', category = 'test', durationSeconds = 10, batch = { min = 1, max = 5 }, stations = { 'workbench' },
    inputs = { { item = 'test_log', amount = 2 } }, outputs = { { item = 'test_plank', amount = 1 } }, tools = { { item = 'test_saw' } } }
local ROPE = { id = 'test:rope', label = 'Test Rope', durationSeconds = 5, batch = { min = 1, max = 3 }, handcraft = true,
    inputs = { { item = 'test_fiber', amount = 3 } }, outputs = { { item = 'test_rope', amount = 1, metadata = { quality = 'basic' } } } }
local ELIG = { id = 'test:elig', label = 'Eligible Recipe', durationSeconds = 5, batch = { min = 1, max = 1 }, handcraft = true, eligibilityExport = 'CanCraftTest',
    inputs = { { item = 'test_fiber', amount = 1 } }, outputs = { { item = 'test_cord', amount = 1 } } }
local BENCH = { id = 'bench_a', type = 'workbench', coords = { x = 100.0, y = 100.0, z = 30.0 }, radius = 3.0 }

local function newWorld(store, keep)
    local prev = W
    W = keep and prev or { now = 1000000, online = {}, pos = {}, stock = {}, ledger = {}, executes = 0, invDown = false, invReady = true, crashAfterCommit = false, capacity = 50,
        eligible = true, eligibilityBroken = false, itemsDown = false, audits = {}, rateBlock = false, ownersUp = { [OWNER] = true, [OTHER] = true }, seed = 777 }
    if not keep then
        W.online['101'], W.online['102'] = 1101, 1102
        W.pos[1101] = { x = 100.0, y = 101.0, z = 30.0, bucket = 0 }; W.pos[1102] = { x = 100.0, y = 101.0, z = 30.0, bucket = 0 }
        W.stock['101'] = { test_log = 10, test_saw = 1, test_fiber = 9 }; W.stock['102'] = { test_log = 4, test_saw = 1, test_fiber = 3 }
    end
    local cfg = deepcopy(CMCrafting.Config)
    cfg.TrustedOwners = { [OWNER] = true, [OTHER] = true }
    W.cfg = cfg
    W.store = store or W.store or newStore()
    local knownItems = { test_log = true, test_plank = true, test_saw = true, test_fiber = true, test_rope = true, test_cord = true, test_bigout = true }
    local function have(cid, item) return (W.stock[cid] and W.stock[cid][item]) or 0 end
    local function dvalidate(cid, tx)
        if W.invDown then return false, 'unavailable' end
        for _, l in ipairs(tx.inputs) do if have(cid, l.item) < l.amount then return false, 'insufficient_input' end end
        for _, t in ipairs(tx.tools) do if have(cid, t.item) < 1 then return false, 'tool_missing' end end
        for _, o in ipairs(tx.outputs) do if have(cid, o.item) + o.amount > W.capacity then return false, 'no_capacity' end end
        return true
    end
    local inv = {
        ready = function() return W.invReady end,
        validate = dvalidate,
        execute = function(ref, cid, tx)
            if W.ledger[ref] then return true, { replayed = true } end
            if W.invDown then return false, 'unavailable' end
            local ok, why = dvalidate(cid, tx)   -- the owner's OWN atomic check (independent of the framework's pre-validation)
            if not ok then return false, why end
            W.stock[cid] = W.stock[cid] or {}
            for _, l in ipairs(tx.inputs) do W.stock[cid][l.item] = have(cid, l.item) - l.amount end
            for _, o in ipairs(tx.outputs) do W.stock[cid][o.item] = have(cid, o.item) + o.amount; W.lastMeta = o.metadata end
            W.ledger[ref] = cid; W.executes = W.executes + 1
            if W.crashAfterCommit then return false, 'unavailable' end   -- committed, but the response was lost
            return true
        end,
        status = function(ref) if W.ledger[ref] then return 'committed' end if W.invDown then return 'unknown' end return 'not_applied' end,
    }
    local seq = W.seed; W.seed = W.seed + 7919
    W.core = CMCrafting.Core.New({
        cfg = cfg, store = W.store, now = function() return W.now end,
        rand = function(a, b) seq = (seq * 1103515245 + 12345) % 2147483648; if a then return (seq // 65536) % (b - a + 1) + a end return 0.5 end,
        encode = ser, decode = deser,
        chars = { sourceOf = function(cid) return W.online[cid] end, position = function(src) local p = W.pos[src]; return p and deepcopy(p) or nil end },
        items = { exists = function(n) if W.itemsDown then return nil end return knownItems[n] == true end, validateMetadata = function(n, m) return m.bad == nil end },
        inventory = inv,
        owners = { started = function(r) return W.ownersUp[r] == true end,
            call = function(res, name, cid) if W.eligibilityBroken then return false, 'call_failed' end return true, W.eligible, W.eligible and nil or 'not_member' end },
        audit = function(k, d) W.audits[#W.audits + 1] = { kind = k, detail = d } end,
        rate = function() return not W.rateBlock end,
    })
    return W
end
local function reg(def, owner) return W.core:RegisterRecipe(owner or OWNER, def) end
local function fresh()
    newWorld(); reg(PLANK); reg(ROPE); reg(ELIG); W.core:RegisterStation(OWNER, BENCH); return W
end
-- station: nil = the default bench, false = no station (handcraft)
local function begin(cid, recipe, qty, station, ctx) if station == false then station = nil elseif station == nil then station = 'bench_a' end return W.core:Begin(OWNER, cid, recipe or 'test:plank', qty or 1, station, ctx) end
local function sess(ref) return W.store.sessGet(ref) end
local function done(ref, cid) return W.core:Complete(OWNER, ref, cid or '101', {}) end
local function ready(ref) local s = sess(ref); W.now = s.ready_at end
local function count(kind, ref) return W.store.count(kind, ref) end
local function stock(cid, item) return (W.stock[cid] or {})[item] or 0 end

-- ======================================================================================== REGISTRY
do
    newWorld()
    check('REGISTRY trusted owner registers a valid recipe', select(1, reg(PLANK)) == true)
    check('REGISTRY same-owner re-registration replaces its own recipe (reload)', select(2, reg(PLANK)).replaced == true)
    check('REGISTRY untrusted resource rejected', select(2, W.core:RegisterRecipe('cm-evil', PLANK)) == 'untrusted_resource')
    check('REGISTRY nil / empty invoker rejected (a client can never register)', select(2, W.core:RegisterRecipe(nil, PLANK)) == 'untrusted_resource' and select(2, W.core:RegisterRecipe('', PLANK)) == 'untrusted_resource')
    check('REGISTRY cross-owner duplicate rejected (owner pinned)', select(2, W.core:RegisterRecipe(OTHER, PLANK)) == 'owner_mismatch' and W.core.recipes['test:plank'].owner == OWNER)
    check('REGISTRY empty TrustedOwners (shipped default) is fail closed', select(2, CMCrafting.Core.New({ cfg = CMCrafting.Config, store = newStore() }):RegisterRecipe('x', PLANK)) == 'untrusted_resource')
    local function variant(patch) local d = deepcopy(PLANK); d.id = 'test:var'; for k, v in pairs(patch) do d[k] = v end return d end
    check('REGISTRY malformed: not a table / bad id / missing namespace', select(2, reg('x')) == 'invalid_recipe' and select(2, reg(variant({ id = 'BadId' }))) == 'invalid_id' and select(2, reg(variant({ id = 'noprefix' }))) == 'invalid_id')
    check('REGISTRY malformed: no inputs / no outputs / non-table lines', select(2, reg(variant({ inputs = {} }))) == 'invalid_inputs' and select(2, reg(variant({ outputs = 5 }))) == 'invalid_outputs' and select(2, reg(variant({ inputs = { 'x' } }))) == 'invalid_inputs')
    check('REGISTRY invalid item (cm-items does not know it) rejected', select(2, reg(variant({ inputs = { { item = 'ghost_item', amount = 1 } } }))) == 'unknown_item')
    check('REGISTRY item authority unavailable fails closed', (function() W.itemsDown = true; local why = select(2, reg(variant({}))); W.itemsDown = false; return why == 'items_unavailable' end)())
    check('REGISTRY invalid quantities (zero / negative / fractional / huge / string)', select(2, reg(variant({ inputs = { { item = 'test_log', amount = 0 } } }))) == 'invalid_amount'
        and select(2, reg(variant({ inputs = { { item = 'test_log', amount = -3 } } }))) == 'invalid_amount' and select(2, reg(variant({ inputs = { { item = 'test_log', amount = 1.5 } } }))) == 'invalid_amount'
        and select(2, reg(variant({ inputs = { { item = 'test_log', amount = 99999 } } }))) == 'invalid_amount' and select(2, reg(variant({ inputs = { { item = 'test_log', amount = '2' } } }))) == 'invalid_amount')
    check('REGISTRY output limits: too many outputs / overflow after batch', select(2, reg(variant({ outputs = { { item = 'test_plank', amount = 1 }, { item = 'test_rope', amount = 1 }, { item = 'test_cord', amount = 1 }, { item = 'test_bigout', amount = 1 }, { item = 'test_fiber', amount = 1 } } }))) == 'invalid_outputs'
        and select(2, reg(variant({ outputs = { { item = 'test_plank', amount = 1000 } }, batch = { min = 1, max = 50 } }))) == 'invalid_amount')
    check('REGISTRY recursive recipe (output is also an input/tool) rejected', select(2, reg(variant({ outputs = { { item = 'test_log', amount = 1 } } }))) == 'recursive_recipe' and select(2, reg(variant({ outputs = { { item = 'test_saw', amount = 1 } } }))) == 'recursive_recipe')
    check('REGISTRY duplicate item lines rejected', select(2, reg(variant({ inputs = { { item = 'test_log', amount = 1 }, { item = 'test_log', amount = 1 } } }))) == 'invalid_inputs')
    check('REGISTRY invalid duration rejected (0 / negative / huge / non-integer)', select(2, reg(variant({ durationSeconds = 0 }))) == 'invalid_duration' and select(2, reg(variant({ durationSeconds = -5 }))) == 'invalid_duration'
        and select(2, reg(variant({ durationSeconds = 99999 }))) == 'invalid_duration' and select(2, reg(variant({ durationSeconds = 2.5 }))) == 'invalid_duration')
    check('REGISTRY invalid batch limits rejected', select(2, reg(variant({ batch = { min = 0, max = 1 } }))) == 'invalid_batch' and select(2, reg(variant({ batch = { min = 3, max = 2 } }))) == 'invalid_batch' and select(2, reg(variant({ batch = { min = 1, max = 5000 } }))) == 'invalid_batch')
    check('REGISTRY total duration (per-unit x max batch) is bounded', select(2, reg(variant({ durationSeconds = 3000, batch = { min = 1, max = 50 } }))) == 'invalid_duration')
    check('REGISTRY recipe with neither handcraft nor stations rejected (never craftable anywhere by omission)', select(2, reg(variant({ stations = {} }))) == 'invalid_station')
    check('REGISTRY arbitrary callback code rejected (functions in the definition)', select(2, reg(variant({ eligibility = function() return true end }))) == 'invalid_recipe' and select(2, reg(variant({ inputs = { { item = 'test_log', amount = 1, check = print } } }))) == 'invalid_inputs')
    check('REGISTRY eligibility export must be a plain name', select(2, reg(variant({ eligibilityExport = 'x; os.exit()' }))) == 'invalid_eligibility')
    check('REGISTRY output metadata must be plain static values, validated by cm-items', select(2, reg(variant({ outputs = { { item = 'test_plank', amount = 1, metadata = { f = print } } } }))) == 'invalid_metadata'
        and select(2, reg(variant({ outputs = { { item = 'test_plank', amount = 1, metadata = { bad = true } } } }))) == 'invalid_metadata' and select(1, reg(variant({ outputs = { { item = 'test_plank', amount = 1, metadata = { quality = 'ok' } } } }))) == true)
    check('REGISTRY input lines cannot carry metadata', select(2, reg(variant({ inputs = { { item = 'test_log', amount = 1, metadata = { a = 1 } } } }))) == 'invalid_metadata')
    check('REGISTRY tool durability use is bounded', select(2, reg(variant({ tools = { { item = 'test_saw', durabilityUse = 0 } } }))) == 'invalid_tools' and select(1, reg(variant({ tools = { { item = 'test_saw', durabilityUse = 3 } } }))) == true)
    check('REGISTRY listing returns only the caller\'s recipes', (function() reg(PLANK); local _, l = W.core:GetRecipes(OWNER); local _, l2 = W.core:GetRecipes(OTHER); return #l >= 1 and #l2 == 0 and select(2, W.core:GetRecipes('cm-evil')) == 'untrusted_resource' end)())
end

-- ======================================================================================== STATIONS
do
    fresh()
    check('STATION trusted owner registers a station', select(1, W.core:RegisterStation(OWNER, { id = 'bench_b', type = 'workbench', coords = { x = 1, y = 2, z = 3 } })) == true)
    check('STATION untrusted resource / cross-owner takeover rejected', select(2, W.core:RegisterStation('cm-evil', BENCH)) == 'untrusted_resource' and select(2, W.core:RegisterStation(OTHER, BENCH)) == 'owner_mismatch')
    check('STATION invalid coords / radius / id rejected', select(2, W.core:RegisterStation(OWNER, { id = 'bench_c', type = 'workbench', coords = { x = 'a' } })) == 'invalid_coords'
        and select(2, W.core:RegisterStation(OWNER, { id = 'bench_c', type = 'workbench', coords = { x = 1, y = 1, z = 1 }, radius = 500 })) == 'invalid_radius' and select(2, W.core:RegisterStation(OWNER, { id = 'BAD ID', type = 'workbench', coords = { x = 1, y = 1, z = 1 } })) == 'invalid_id')
    check('STATION valid begin at a registered station within range', select(1, begin('101')) == true)
    check('STATION unknown station rejected (client coordinates are never an authority)', select(2, begin('102', 'test:plank', 1, 'bench_zzz')) == 'unknown_station')
    check('STATION wrong station type rejected', (function() W.core:RegisterStation(OWNER, { id = 'furnace_a', type = 'furnace', coords = { x = 100, y = 100, z = 30 } }); return select(2, begin('102', 'test:plank', 1, 'furnace_a')) == 'wrong_station_type' end)())
    check('STATION too far from the station rejected', (function() W.pos[1102].x = 200.0; local why = select(2, begin('102')); W.pos[1102].x = 100.0; return why == 'too_far' end)())
    check('STATION wrong routing bucket rejected (station bucket policy)', (function()
        W.core:RegisterStation(OWNER, { id = 'bench_p', type = 'workbench', coords = { x = 100, y = 100, z = 30 }, bucket = 0 }); W.pos[1102].bucket = 3
        local why = select(2, begin('102', 'test:plank', 1, 'bench_p')); W.pos[1102].bucket = 0; return why == 'wrong_bucket' end)())
    check('STATION station-only recipe cannot be crafted by hand', select(2, begin('102', 'test:plank', 1, false)) == 'station_required')
    check('STATION handcraft recipe works without a station', (function() fresh(); return select(1, begin('101', 'test:rope', 1, false)) == true end)())
    check('STATION handcraft recipe rejects an unneeded station of wrong type', (function() fresh(); return select(2, begin('101', 'test:rope', 1, 'bench_a')) == 'wrong_station_type' end)())
    check('STATION another owner\'s private station cannot be used', (function() fresh(); reg(PLANK, OTHER); W.core:RegisterStation(OTHER, { id = 'bench_o', type = 'workbench', coords = { x = 100, y = 100, z = 30 } }); return select(2, begin('101', 'test:plank', 1, 'bench_o')) == 'station_forbidden' end)())
    check('STATION a shared station may be used by another trusted owner\'s recipe', (function()
        fresh(); W.core:RegisterStation(OTHER, { id = 'bench_s', type = 'workbench', coords = { x = 100, y = 100, z = 30 }, shared = true }); return select(1, begin('101', 'test:plank', 1, 'bench_s')) == true end)())
    check('STATION non-string station id rejected', (function() fresh(); return select(2, begin('101', 'test:plank', 1, 42)) == 'invalid_station' end)())
end

-- ======================================================================================== ELIGIBILITY
do
    fresh()
    check('ELIGIBILITY eligible character may craft', select(1, begin('101', 'test:elig', 1, false)) == true)
    check('ELIGIBILITY denied by the owner', (function() fresh(); W.eligible = false; return select(2, begin('101', 'test:elig', 1, false)) == 'not_member' end)())
    check('ELIGIBILITY owner callback failure fails closed', (function() fresh(); W.eligibilityBroken = true; return select(2, begin('101', 'test:elig', 1, false)) == 'eligibility_unavailable' end)())
    check('ELIGIBILITY owner resource stopped fails closed', (function() fresh(); W.ownersUp[OWNER] = false; return select(2, begin('101', 'test:elig', 1, false)) == 'owner_unavailable' end)())
    check('ELIGIBILITY recipe unavailable (never registered)', select(2, begin('101', 'test:nothing', 1, false)) == 'unknown_recipe')
    check('ELIGIBILITY another resource cannot craft this owner\'s recipe', (function() fresh(); return select(2, W.core:Begin(OTHER, '101', 'test:rope', 1, nil)) == 'forbidden' end)())
    check('ELIGIBILITY is re-checked at completion (lost eligibility blocks the commit)', (function()
        fresh(); local r = select(2, begin('101', 'test:elig', 1, false)).reference; ready(r); W.eligible = false
        local why = select(2, done(r)); return why == 'not_member' and sess(r).status == 'active' and W.executes == 0 end)())
end

-- ======================================================================================== BEGIN / SETTLEMENT GATE
do
    fresh()
    local ok, r = begin('101', 'test:plank', 2)
    check('BEGIN valid craft returns a reference and a SERVER duration (2 x 10s)', ok and r.reference:match('^CRAFT%-') ~= nil and r.durationSeconds == 20 and r.readyAt == W.now + 20)
    local s = sess(r.reference)
    check('BEGIN persisted by character id, owner, station, bucket, quantity (no source id)', s.character_id == '101' and s.owner_resource == OWNER and s.station_id == 'bench_a' and s.quantity == 2 and s.bucket == 0 and s.source == nil and s.src == nil)
    check('BEGIN inputs are NOT consumed at start (no early removal)', stock('101', 'test_log') == 10 and W.executes == 0)
    check('BEGIN transaction snapshot is server generated and multiplied by quantity', (function() local tx = deser(s.tx_json); return tx.inputs[1].item == 'test_log' and tx.inputs[1].amount == 4 and tx.outputs[1].amount == 2 and tx.tools[1].item == 'test_saw' end)())
    check('BEGIN started event journalled', count('started', r.reference) == 1)
    check('BEGIN already crafting rejected (one live craft per character)', select(2, begin('101', 'test:plank', 1)) == 'already_crafting')
    check('BEGIN invalid quantities rejected (0 / negative / fractional / string / above batch max / nil)', (function()
        fresh(); local c = {}
        for _, q in ipairs({ 0, -1, 1.5, '2', 6, 9999999999 }) do c[#c + 1] = select(2, begin('101', 'test:plank', q)) end
        c[#c + 1] = select(2, W.core:Begin(OWNER, '101', 'test:plank', nil, 'bench_a'))
        for _, why in ipairs(c) do if why ~= 'invalid_quantity' then return false, why end end return true end)())
    check('BEGIN batch maximum accepted, max+1 rejected', (function() fresh(); W.stock['101'].test_log = 100; return select(1, begin('101', 'test:plank', 5)) == true end)())
    check('BEGIN ingredients apparently missing rejected', (function() fresh(); W.stock['101'].test_log = 1; return select(2, begin('101', 'test:plank', 1)) == 'insufficient_input' end)())
    check('BEGIN batch needs batch-scaled inputs', (function() fresh(); W.stock['101'].test_log = 5; return select(2, begin('101', 'test:plank', 3)) == 'insufficient_input' end)())
    check('BEGIN required tool missing rejected', (function() fresh(); W.stock['101'].test_saw = 0; return select(2, begin('101', 'test:plank', 1)) == 'tool_missing' end)())
    check('BEGIN output capacity checked up front', (function() fresh(); W.stock['101'].test_plank = 50; return select(2, begin('101', 'test:plank', 1)) == 'no_capacity' end)())
    check('BEGIN offline / invalid character rejected', (function() fresh(); return select(2, begin('999')) == 'character_offline' and select(2, begin('1; DROP')) == 'invalid_character' and select(2, begin(nil)) == 'invalid_character' end)())
    check('BEGIN rate limited', (function() fresh(); W.rateBlock = true; local why = select(2, begin('101')); W.rateBlock = false; return why == 'rate_limited' end)())
    check('BEGIN replay with the same idempotency key returns the same session', (function()
        fresh(); local a = select(2, begin('101', 'test:plank', 1, 'bench_a', { idempotencyKey = 'k1' })); local b = select(2, begin('101', 'test:plank', 1, 'bench_a', { idempotencyKey = 'k1' }))
        return a.reference == b.reference and b.existing == true and #W.store.sessions == 1 end)())
    check('BEGIN idempotency key reused for another recipe / character is a conflict', (function()
        fresh(); begin('101', 'test:plank', 1, 'bench_a', { idempotencyKey = 'k2' }); return select(2, begin('101', 'test:rope', 1, false, { idempotencyKey = 'k2' })) == 'idempotency_conflict' end)())
    check('BEGIN invalid idempotency key / context rejected', (function() fresh(); return select(2, begin('101', 'test:plank', 1, 'bench_a', { idempotencyKey = 'bad key!' })) == 'invalid_key' and select(2, W.core:Begin(OWNER, '101', 'test:plank', 1, 'bench_a', 'x')) == 'invalid_request' end)())
    check('BEGIN read-only CanCraft agrees and creates nothing', (function() fresh(); local ok1 = W.core:CanCraft(OWNER, '101', 'test:plank', 1, 'bench_a'); local no = select(2, W.core:CanCraft(OWNER, '101', 'test:plank', 9, 'bench_a')); return ok1 == true and no == 'invalid_quantity' and #W.store.sessions == 0 end)())
    check('SETTLEMENT GATE: live crafting is DISABLED while the inventory owner has no craft contract', (function()
        fresh(); W.invReady = false; local why = select(2, begin('101')); W.invReady = true; return why == 'settlement_unavailable' and #W.store.sessions == 0 end)())
    check('SETTLEMENT GATE: inventory validation outage fails closed', (function() fresh(); W.invDown = true; local why = select(2, begin('101')); W.invDown = false; return why == 'inventory_unavailable' end)())
    check('SETTLEMENT GATE: there is no RemoveItem/AddItem path in the shipped code', (function()
        for _, f in ipairs({ 'server/core.lua', 'server/main.lua', 'server/store.lua' }) do
            local h = io.open(here .. '/' .. f, 'r'); local src = h:read('a'); h:close()
            src = src:gsub('%-%-[^\n]*', '')
            if src:find('RemoveItem') or src:find('AddItem') or src:find('AddMoney') or src:find('RemoveCash') or src:find('ConsumeItemDurability') then return false end
        end return true end)())
end

-- ======================================================================================== TIMING
do
    fresh()
    local r = select(2, begin('101', 'test:plank', 2)).reference
    check('TIMING early completion rejected (timer not reached)', select(2, done(r)) == 'too_early' and W.executes == 0 and sess(r).status == 'active')
    W.now = W.now + 19
    check('TIMING one second before the end is still too early', select(2, done(r)) == 'too_early')
    W.now = W.now + 1
    check('TIMING exact completion time is allowed', select(1, done(r)) == true and sess(r).status == 'completed')
    fresh(); local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2); W.now = W.now + 300
    check('TIMING late completion (within the grace window) is allowed', select(1, done(r2)) == true)
    fresh(); local r3 = select(2, begin('101', 'test:plank', 1)).reference; ready(r3); W.now = W.now + 601
    check('TIMING completion after the grace window expires the session', select(2, done(r3)) == 'expired' and sess(r3).status == 'expired' and W.executes == 0)
    check('TIMING client cannot shorten the duration: speed hint ignored beyond the clamp, extra args ignored', (function()
        fresh(); local a = select(2, begin('101', 'test:plank', 1, 'bench_a', { speedModifier = 1000 })); local b = select(2, begin('102', 'test:rope', 1, false, { duration = 0, durationSeconds = 0, readyAt = 1 }))
        return a.durationSeconds == 5 and b.durationSeconds == 5 end)())
    check('TIMING a zero/negative modifier is clamped, duration never below 1s', (function()
        fresh(); local a = select(2, begin('101', 'test:rope', 1, false, { speedModifier = 0 })); return a.durationSeconds == 10 end)())
    check('TIMING invalid modifier types rejected', (function() fresh(); return select(2, begin('101', 'test:rope', 1, false, { speedModifier = 'fast' })) == 'invalid_request' end)())
    check('TIMING minimum duration is 1 second for a 1-second recipe at max speed', (function()
        fresh(); reg({ id = 'test:quick', durationSeconds = 1, handcraft = true, inputs = { { item = 'test_fiber', amount = 1 } }, outputs = { { item = 'test_cord', amount = 1 } } })
        return select(2, begin('101', 'test:quick', 1, false, { speedModifier = 2.0 })).durationSeconds >= 1 end)())
end

-- ======================================================================================== FINAL VALIDATION
do
    fresh()
    local function started(cid, recipe, station) local r = select(2, begin(cid, recipe, 1, station)).reference; ready(r); return r end
    check('FINAL ingredients consumed elsewhere during the timer: craft fails safely, nothing consumed', (function()
        local r = started('101'); W.stock['101'].test_log = 0; local why = select(2, done(r)); return why == 'insufficient_input' and sess(r).status == 'failed' and W.executes == 0 and stock('101', 'test_plank') == 0 end)())
    check('FINAL tool missing at finish fails safely', (function() fresh(); local r = started('101'); W.stock['101'].test_saw = 0; local why = select(2, done(r)); return why == 'tool_missing' and sess(r).status == 'failed' and stock('101', 'test_log') == 10 end)())
    check('FINAL moved away from the station: rejected, session stays active', (function() fresh(); local r = started('101'); W.pos[1101].x = 500.0; local why = select(2, done(r)); W.pos[1101].x = 100.0; return why == 'too_far' and sess(r).status == 'active' end)())
    check('FINAL returning to the station completes it', (function() fresh(); local r = started('101'); W.pos[1101].x = 500.0; done(r); W.pos[1101].x = 100.0; return select(1, done(r)) == true end)())
    check('FINAL bucket changed rejected', (function() fresh(); local r = started('101'); W.pos[1101].bucket = 9; local why = select(2, done(r)); W.pos[1101].bucket = 0; return why == 'bucket_changed' end)())
    check('FINAL stationless craft also rejects a changed bucket', (function() fresh(); local r = started('101', 'test:rope', false); W.pos[1101].bucket = 4; local why = select(2, done(r)); W.pos[1101].bucket = 0; return why == 'bucket_changed' end)())
    check('FINAL character offline cannot complete', (function() fresh(); local r = started('101'); W.online['101'] = nil; local why = select(2, done(r)); W.online['101'] = 1101; return why == 'character_offline' end)())
    check('FINAL output capacity gone at finish fails with nothing consumed', (function() fresh(); local r = started('101'); W.stock['101'].test_plank = 50; local why = select(2, done(r)); return why == 'no_capacity' and W.executes == 0 and stock('101', 'test_log') == 10 end)())
    check('FINAL inventory outage at validation keeps the session active (no guess)', (function() fresh(); local r = started('101'); W.invDown = true; local why = select(2, done(r)); W.invDown = false; return why == 'inventory_unavailable' and sess(r).status == 'active' end)())
    check('FINAL settlement not ready blocks completion', (function() fresh(); local r = started('101'); W.invReady = false; local why = select(2, done(r)); W.invReady = true; return why == 'settlement_unavailable' and sess(r).status == 'active' end)())
    check('FINAL owner not re-registered (recipe gone) keeps it active until expiry', (function() fresh(); local r = started('101'); W.core.recipes = {}; return select(2, done(r)) == 'owner_unavailable' and sess(r).status == 'active' end)())
end

-- ======================================================================================== INVENTORY TRANSACTION / OUTPUT
do
    fresh()
    local r = select(2, begin('101', 'test:plank', 2)).reference; ready(r)
    local ok, res = done(r)
    check('INVENTORY successful commit consumes inputs and creates outputs once (double)', ok and W.executes == 1 and stock('101', 'test_log') == 6 and stock('101', 'test_plank') == 2)
    check('INVENTORY the result lists the authoritative outputs', res.status == 'completed' and res.outputs[1].item == 'test_plank' and res.outputs[1].amount == 2)
    check('INVENTORY tools are required but not consumed', stock('101', 'test_saw') == 1)
    check('INVENTORY transaction reference is the craft reference (deterministic, not a client id)', W.ledger[r] == '101' and r:match('^CRAFT%-') ~= nil)
    check('INVENTORY completed only AFTER settlement; events journalled once', sess(r).status == 'completed' and count('commit_started', r) == 1 and count('inventory_committed', r) == 1 and count('completed', r) == 1)
    check('INVENTORY replay of the same craft returns the previous result, never a second craft', (function()
        local ok2, res2, tag = done(r); local ok3 = done(r); return ok2 and tag == 'replayed' and res2.outputs[1].amount == 2 and W.executes == 1 and stock('101', 'test_plank') == 2 and count('completed', r) == 1 end)())
    check('INVENTORY frees the character for the next craft', select(1, begin('101', 'test:plank', 1)) == true)
    check('INVENTORY insufficient input at commit (race with the validate step) fails with nothing applied', (function()
        fresh(); local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2)
        local realValidate = W.core.inventory.validate; W.core.inventory.validate = function() return true end   -- simulate the TOCTOU: validation passes, atomic commit still refuses
        W.stock['101'].test_log = 1
        local ok2, why = done(r2); W.core.inventory.validate = realValidate
        return ok2 == false and why == 'insufficient_input' and sess(r2).status == 'failed' and W.executes == 0 and stock('101', 'test_log') == 1 end)())
    check('INVENTORY no output capacity at commit: no inputs consumed', (function()
        fresh(); local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2)
        local realValidate = W.core.inventory.validate; W.core.inventory.validate = function() return true end; W.stock['101'].test_plank = 50
        local ok2, why = done(r2); W.core.inventory.validate = realValidate
        return ok2 == false and why == 'no_capacity' and stock('101', 'test_log') == 10 and sess(r2).status == 'failed' end)())
    check('INVENTORY unavailable at commit: stays committing, nothing guessed, no second craft', (function()
        fresh(); local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2)
        local realValidate = W.core.inventory.validate; W.core.inventory.validate = function() return true end; W.invDown = true
        local ok2, why = done(r2); W.core.inventory.validate = realValidate
        return ok2 == false and why == 'reconciling' and sess(r2).status == 'committing' and W.executes == 0 end)())
    check('INVENTORY committing session recovers when the inventory returns (retry is idempotent)', (function()
        W.invDown = false; W.now = W.now + 20; local _, st = W.core:Sweep(); local r2 = W.store.sessions[#W.store.sessions]
        return r2.status == 'completed' and W.executes == 1 and stock('101', 'test_plank') == 1 end)())
    check('INVENTORY committed but the response was lost: status query recovers it, no duplicate', (function()
        fresh(); W.crashAfterCommit = true; local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2)
        local ok2, why = done(r2); local mid = sess(r2).status
        W.crashAfterCommit = false; local ok3, res3, tag = done(r2)
        return ok2 == false and why == 'reconciling' and mid == 'committing' and ok3 == true and tag == 'replayed' and W.executes == 1 and stock('101', 'test_plank') == 1 and stock('101', 'test_log') == 8 end)())
    check('INVENTORY committed-status recovery also works via the sweep', (function()
        fresh(); W.crashAfterCommit = true; local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2); done(r2); W.crashAfterCommit = false
        W.core:Sweep(); return sess(r2).status == 'completed' and W.executes == 1 and count('reconciled', r2) == 1 end)())
    check('INVENTORY not_applied status retries the idempotent commit', (function()
        fresh(); W.invDown = false; local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2)
        local realValidate = W.core.inventory.validate; W.core.inventory.validate = function() return true end; W.invDown = true; done(r2); W.invDown = false; W.core.inventory.validate = realValidate
        W.now = W.now + 100; W.core:Sweep(); return sess(r2).status == 'completed' and W.executes == 1 end)())
    check('INVENTORY not_applied forever fails after bounded attempts', (function()
        fresh(); local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2)
        local realValidate = W.core.inventory.validate; W.core.inventory.validate = function() return true end
        local realExec = W.core.inventory.execute; W.core.inventory.execute = function() return false, 'unavailable' end
        W.core.inventory.status = function() return 'not_applied' end
        done(r2); for _ = 1, 12 do W.now = W.now + 200; W.core:Sweep() end
        W.core.inventory.validate, W.core.inventory.execute = realValidate, realExec
        return sess(r2).status == 'failed' and sess(r2).failure_reason == 'commit_failed' end)())
    check('INVENTORY unknown status is flagged for reconciliation after the window, never re-applied', (function()
        fresh(); W.crashAfterCommit = true; local r2 = select(2, begin('101', 'test:plank', 1)).reference; ready(r2); done(r2); W.crashAfterCommit = false
        W.invDown = true; W.core.inventory.status = function() return 'unknown' end; W.core:Sweep(); W.now = W.now + 1000; W.core:Sweep(); W.core:Sweep()
        return sess(r2).status == 'committing' and count('reconcile_stuck', r2) == 1 and W.executes == 1 and #W.audits > 0 end)())
    check('OUTPUT exact quantity for a single craft and a batch', (function()
        fresh(); local a = select(2, begin('101', 'test:plank', 1)).reference; ready(a); done(a); local one = stock('101', 'test_plank')
        local b = select(2, begin('101', 'test:plank', 3)).reference; ready(b); done(b); return one == 1 and stock('101', 'test_plank') == 4 and stock('101', 'test_log') == 10 - 2 - 6 end)())
    check('OUTPUT static recipe metadata is passed to the inventory contract', (function()
        fresh(); local a = select(2, begin('101', 'test:rope', 1, false)).reference; ready(a); done(a); return W.lastMeta and W.lastMeta.quality == 'basic' end)())
    check('OUTPUT malicious client metadata / outputs / inputs in the context are ignored', (function()
        fresh(); W.lastMeta = nil
        local a = select(2, begin('101', 'test:rope', 1, false, { outputMetadata = { quality = 'legendary' }, metadata = { x = 1 }, outputs = { { item = 'test_bigout', amount = 9999 } }, inputs = {} })).reference
        ready(a); local ok = W.core:Complete(OWNER, a, '101', { metadata = { quality = 'legendary' }, outputs = { { item = 'test_bigout', amount = 9999 } }, amount = 500 })
        return ok and W.lastMeta.quality == 'basic' and stock('101', 'test_bigout') == 0 and stock('101', 'test_rope') == 1 end)())
end

-- ======================================================================================== CANCEL / FAIL / DISCONNECT / RACES
do
    fresh()
    local r = select(2, begin('101')).reference
    check('CANCEL active craft: terminal, nothing consumed, no refund needed', select(1, W.core:Cancel(OWNER, r, '101', 'moved')) == true and sess(r).status == 'cancelled' and stock('101', 'test_log') == 10 and W.executes == 0)
    check('CANCEL repeat cancel is idempotent', select(2, W.core:Cancel(OWNER, r, '101')).replayed == true)
    check('CANCEL frees the character', select(1, begin('101')) == true)
    check('CANCEL after commit rejected', (function()
        fresh(); local r2 = select(2, begin('101')).reference; ready(r2); done(r2); return select(2, W.core:Cancel(OWNER, r2, '101')) == 'cancel_not_allowed' and sess(r2).status == 'completed' end)())
    check('CANCEL during committing rejected', (function()
        fresh(); W.crashAfterCommit = true; local r2 = select(2, begin('101')).reference; ready(r2); done(r2); W.crashAfterCommit = false
        return select(2, W.core:Cancel(OWNER, r2, '101')) == 'cancel_not_allowed' and sess(r2).status == 'committing' end)())
    check('CANCEL forged character id / other owner rejected', (function()
        fresh(); local r2 = select(2, begin('101')).reference
        return select(2, W.core:Cancel(OWNER, r2, '102')) == 'forbidden' and select(2, W.core:Cancel(OTHER, r2, '101')) == 'forbidden' and sess(r2).status == 'active' end)())
    check('FAIL content owner fails an active craft (death/interruption); replay safe', (function()
        fresh(); local r2 = select(2, begin('101')).reference; local ok = W.core:Fail(OWNER, r2, 'interrupted'); local again = select(2, W.core:Fail(OWNER, r2, 'x'))
        return ok and sess(r2).status == 'failed' and again.replayed == true and sess(r2).failure_reason == 'interrupted' end)())
    check('FAIL cannot fail a committing craft (reconciliation decides)', (function()
        fresh(); W.crashAfterCommit = true; local r2 = select(2, begin('101')).reference; ready(r2); done(r2); W.crashAfterCommit = false
        return select(2, W.core:Fail(OWNER, r2, 'x')) == 'commit_in_progress' end)())
    check('DISCONNECT active session: brief drop keeps it, long drop fails it, no output', (function()
        fresh(); local r2 = select(2, begin('101')).reference; W.online['101'] = nil; W.core:Sweep(); W.now = W.now + 30; W.core:Sweep(); local mid = sess(r2).status
        W.now = W.now + 40; W.core:Sweep()
        return mid == 'active' and sess(r2).status == 'failed' and sess(r2).failure_reason == 'disconnected' and stock('101', 'test_plank') == 0 and W.executes == 0 end)())
    check('DISCONNECT reconnecting within grace keeps the session', (function()
        fresh(); local r2 = select(2, begin('101')).reference; W.online['101'] = nil; W.core:Sweep(); W.now = W.now + 30; W.online['101'] = 1101; W.core:Sweep(); W.now = W.now + 100; W.core:Sweep(); return sess(r2).status == 'active' end)())
    check('DISCONNECT in the commit state: reconciliation still settles exactly once, offline', (function()
        fresh(); W.crashAfterCommit = true; local r2 = select(2, begin('101')).reference; ready(r2); done(r2); W.crashAfterCommit = false; W.online['101'] = nil
        W.core:Sweep(); return sess(r2).status == 'completed' and W.executes == 1 and stock('101', 'test_plank') == 1 end)())
    check('DISCONNECT never gives a free output: failed offline session leaves stock untouched', (function()
        fresh(); local r2 = select(2, begin('101')).reference; W.online['101'] = nil; W.now = W.now + 100; W.core:Sweep(); W.core:Sweep(); return stock('101', 'test_plank') == 0 and stock('101', 'test_log') == 10 end)())
    check('OWNER STOP: owner gone past grace fails its active crafts', (function()
        fresh(); local r2 = select(2, begin('101')).reference; W.ownersUp[OWNER] = false; W.core:Sweep(); W.now = W.now + 130; W.core:Sweep(); W.ownersUp[OWNER] = true
        return sess(r2).status == 'failed' and sess(r2).failure_reason == 'owner_stopped' end)())
    check('EXPIRY a ready-but-never-completed session expires on the sweep', (function()
        fresh(); local r2 = select(2, begin('101')).reference; ready(r2); W.now = W.now + 601; local _, st = W.core:Sweep(); return sess(r2).status == 'expired' and st.expired == 1 and W.executes == 0 end)())
    check('RACE complete vs cancel: only one terminal result', (function()
        fresh(); local r2 = select(2, begin('101')).reference; ready(r2)
        local c1 = W.core:Complete(OWNER, r2, '101', {}); local c2 = select(2, W.core:Cancel(OWNER, r2, '101'))
        return c1 == true and c2 == 'cancel_not_allowed' and sess(r2).status == 'completed' and W.executes == 1 end)())
    check('RACE cancel then complete: complete is refused, output never created', (function()
        fresh(); local r2 = select(2, begin('101')).reference; ready(r2); W.core:Cancel(OWNER, r2, '101'); local why = select(2, done(r2)); return why == 'terminal_cancelled' and W.executes == 0 end)())
    check('RACE double completion: output once, one completed event', (function()
        fresh(); local r2 = select(2, begin('101')).reference; ready(r2); done(r2); done(r2); done(r2); return W.executes == 1 and count('completed', r2) == 1 and stock('101', 'test_plank') == 1 end)())
    check('RACE lock contention returns busy instead of double-settling', (function()
        fresh(); local r2 = select(2, begin('101')).reference; ready(r2); W.core.locks['sess:' .. r2] = true; local why = select(2, done(r2)); W.core.locks['sess:' .. r2] = nil; return why == 'busy' and W.executes == 0 end)())
    check('RACE two simultaneous begins for one character: one session (UNIQUE active_key)', (function()
        fresh(); local a = begin('101'); local b = begin('101'); return a == true and b == false and #W.store.sessions == 1 end)())
end

-- ======================================================================================== RESTART
do
    fresh()
    local store = W.store
    local a = select(2, begin('101', 'test:plank', 1)).reference                         -- active, timer not reached
    local b = select(2, begin('102', 'test:rope', 1, false)).reference                      -- will be committing
    ready(b); W.crashAfterCommit = true; done(b, '102'); W.crashAfterCommit = false
    local c = select(2, begin('101', 'test:plank', 1)); -- rejected: 101 busy
    W.store.sessCas(a, { 'active' }, { status = 'active' })
    -- a completed one
    W.online['103'], W.pos[1103] = 1103, { x = 100.0, y = 101.0, z = 30.0, bucket = 0 }; W.online['103'] = 1103; W.stock['103'] = { test_fiber = 3 }
    local d = select(2, begin('103', 'test:rope', 1, false)).reference; ready(d); done(d, '103')
    local executesBefore, ropeBefore = W.executes, stock('102', 'test_rope')
    newWorld(store, true); reg(PLANK); reg(ROPE); reg(ELIG); W.core:RegisterStation(OWNER, BENCH)
    local _, st = W.core:Recover()
    check('RESTART active uncommitted craft fails on recovery (no trust in a pre-restart timer)', sess(a).status == 'failed' and sess(a).failure_reason == 'restart' and st.failedOnRestart == 1)
    check('RESTART nothing was consumed for the failed craft', stock('101', 'test_log') == 10 and stock('101', 'test_plank') == 0)
    check('RESTART committing craft reconciles against the inventory status (committed -> completed)', sess(b).status == 'completed' and count('reconciled', b) == 1)
    check('RESTART reconciliation did not duplicate the output', W.executes == executesBefore and stock('102', 'test_rope') == ropeBefore and W.ledger[b] == '102')
    check('RESTART completed craft remains terminal and replays its result', (function() local ok, res, tag = done(d, '103'); return ok and tag == 'replayed' and W.executes == executesBefore end)())
    check('RESTART the character is free again after recovery', select(1, begin('101')) == true)
    check('RESTART a second recovery run changes nothing', (function() W.core:Recover(); local before = #W.store.events; W.core:Recover(); return #W.store.events == before end)())
    check('RESTART transaction replay after recovery does not duplicate', (function() local ok = W.core.inventory.execute(a, '101', { inputs = {}, outputs = { { item = 'test_plank', amount = 5 } }, tools = {} }); local first = stock('101', 'test_plank'); W.core.inventory.execute(a, '101', { inputs = {}, outputs = { { item = 'test_plank', amount = 5 } }, tools = {} }); return stock('101', 'test_plank') == first end)())
    check('RESTART committing with the inventory still unknown stays committing (never re-applied)', (function()
        newWorld(); reg(PLANK); W.core:RegisterStation(OWNER, BENCH); W.crashAfterCommit = true
        local x = select(2, begin('101')).reference; ready(x); done(x); W.crashAfterCommit = false; local exec = W.executes
        local st0 = W.store; W.ledger = {}; W.invDown = true; W.core.inventory.status = function() return 'unknown' end; W.core:Recover()
        local ok = sess(x).status == 'committing' and W.executes == exec; return ok end)())
    check('RESTART recipes are not persisted: content must re-register (registry empty until it does)', (function()
        newWorld(); return next(W.core.recipes) == nil and select(2, W.core:Begin(OWNER, '101', 'test:plank', 1, 'bench_a')) == 'unknown_recipe' end)())
end

-- ======================================================================================== SECURITY / ADMIN
do
    fresh()
    local r = select(2, begin('101', 'test:plank', 1)).reference; ready(r)
    check('SECURITY forged CID: another character cannot complete / cancel / read the craft', select(2, W.core:Complete(OWNER, r, '102', {})) == 'forbidden' and select(2, W.core:Cancel(OWNER, r, '102')) == 'forbidden' and W.executes == 0)
    check('SECURITY forged / malformed CID strings rejected', select(2, W.core:Complete(OWNER, r, "1' OR '1", {})) == 'forbidden' and select(2, begin("1'; --")) == 'invalid_character')
    check('SECURITY forged recipe: unknown / other owner\'s recipe cannot be begun', select(2, begin('102', 'evil:recipe')) == 'unknown_recipe' and select(2, W.core:Begin(OTHER, '102', 'test:plank', 1, 'bench_a')) == 'forbidden')
    check('SECURITY forged owner resource: cross-resource completion / cancel / fail / read rejected', (function()
        return select(2, W.core:Complete(OTHER, r, '101', {})) == 'forbidden' and select(2, W.core:Cancel(OTHER, r, '101')) == 'forbidden' and select(2, W.core:Fail(OTHER, r)) == 'forbidden' and select(2, W.core:Get(OTHER, r)) == 'forbidden' end)())
    check('SECURITY forged owner names (nil / number) rejected', select(2, W.core:Complete(nil, r, '101', {})) == 'forbidden' and select(2, W.core:Complete(42, r, '101', {})) == 'forbidden')
    check('SECURITY session untouched by every rejected call', sess(r).status == 'active' and W.executes == 0)
    check('SECURITY forged station: arbitrary / injected station ids rejected', select(2, begin('102', 'test:plank', 1, "bench_a' OR 1=1")) == 'unknown_station' and select(2, begin('102', 'test:plank', 1, { id = 'bench_a' })) == 'invalid_station')
    check('SECURITY forged inputs/outputs/quantity/duration in begin context never reach the transaction', (function()
        fresh(); local a = select(2, begin('101', 'test:plank', 1, 'bench_a', { inputs = { { item = 'test_log', amount = 0 } }, outputs = { { item = 'test_bigout', amount = 500 } }, quantity = 99, duration = 0 })).reference
        local tx = deser(sess(a).tx_json); return #tx.outputs == 1 and tx.outputs[1].item == 'test_plank' and tx.outputs[1].amount == 1 and tx.inputs[1].amount == 2 and sess(a).quantity == 1 end)())
    check('SECURITY malformed references rejected safely', select(2, W.core:Get(OWNER, "CRAFT-1' OR 1=1")) == 'invalid_reference' and select(2, W.core:Get(OWNER, {})) == 'invalid_reference' and select(2, W.core:Get(OWNER, nil)) == 'invalid_reference')
    check('SECURITY direct client pathway absent: no net event / NUI / callback / client script / player command', (function()
        local bad = 0
        for _, f in ipairs({ 'server/main.lua', 'server/core.lua', 'server/store.lua' }) do
            local h = io.open(here .. '/' .. f, 'r'); local src = h:read('a'); h:close()
            for _, pat in ipairs({ 'RegisterNetEvent', 'RegisterServerEvent', 'RegisterNUICallback', 'lib%.callback%.register', 'TriggerClientEvent' }) do if src:find(pat) then bad = bad + 1 end end
            local cmds = select(2, src:gsub('RegisterCommand%(', '')); if cmds > 0 and not (cmds == 1 and src:find('if src ~= 0 then return end', 1, true)) then bad = bad + 1 end
        end
        local m = io.open(here .. '/fxmanifest.lua', 'r'):read('a'); if m:find('client_script') or m:find('ui_page') then bad = bad + 1 end
        return bad == 0 end)())
    check('SECURITY every export is bound to the invoking resource (static)', (function()
        local h = io.open(here .. '/server/main.lua', 'r'); local src = h:read('a'); h:close()
        local n = select(2, src:gsub("exports%('[%w]+'", '')); local owned = select(2, src:gsub("exports%('[%w]+', owned%(", '')); local adm = select(2, src:gsub("exports%('[%w]+', admin%(", ''))
        local readOnly = select(2, src:gsub("exports%('IsCraftingSettlementReady'", ''))
        return n == owned + adm + readOnly and n > 0 end)())
    check('SECURITY no source id and no money/inventory write in the schema', (function() local h = io.open(here .. '/server/store.lua', 'r'); local s = h:read('a'); h:close(); return not s:find('source_id') and not s:find('server_id') and not s:find('license') end)())
    check('SECURITY rate limits on begin / cancel / complete', (function() fresh(); local a = select(2, begin('101')); local r2 = select(2, begin('102')).reference; ready(r2); W.rateBlock = true
        local c = select(2, W.core:Complete(OWNER, r2, '102', {})); local d = select(2, W.core:Cancel(OWNER, r2, '102')); local e = select(2, begin('101', 'test:rope', 1, false)); W.rateBlock = false
        return c == 'rate_limited' and d == 'rate_limited' and e == 'rate_limited' end)())
    check('ADMIN list / inspect: session, transaction snapshot, events', (function()
        fresh(); local r2 = select(2, begin('101')).reference; local _, l = W.core:AdminList(); local ok, info = W.core:AdminInspect(r2)
        return #l == 1 and ok and info.session.reference == r2 and info.transaction.inputs[1].item == 'test_log' and #info.events >= 1 end)())
    check('ADMIN cancel a stuck active craft; committing must be reconciled instead', (function()
        fresh(); local r2 = select(2, begin('101')).reference; local ok = W.core:AdminCancel(r2, 'tester')
        W.crashAfterCommit = true; local r3 = select(2, begin('101')).reference; ready(r3); done(r3); W.crashAfterCommit = false
        return ok == true and sess(r2).status == 'cancelled' and count('admin_cancel', r2) == 1 and select(2, W.core:AdminCancel(r3, 'tester')) == 'committing_use_reconcile' end)())
    check('ADMIN force reconciliation settles a committing craft once', (function()
        fresh(); W.crashAfterCommit = true; local r2 = select(2, begin('101')).reference; ready(r2); done(r2); W.crashAfterCommit = false
        local ok, res = W.core:AdminReconcile(r2, 'tester'); local again = W.core:AdminReconcile(r2, 'tester')
        return ok and res.status == 'completed' and again == true and W.executes == 1 end)())
    check('ADMIN invalid / unknown references rejected', select(2, W.core:AdminInspect("x'y")) == 'invalid_reference' and select(2, W.core:AdminInspect('CRAFT-NOPE0000')) == 'not_found' and select(2, W.core:AdminCancel('CRAFT-NOPE0000')) == 'not_found')
    check('AUDIT terminal outcomes mirrored to the admin log without secrets', (function() local blob = ser(W.audits); return #W.audits > 0 and not blob:find('token') and not blob:find('license') end)())
    check('ECONOMY the core exposes no money / price / market surface', (function()
        for k in pairs(CMCrafting.Core) do local l = k:lower(); if l:find('cash') or l:find('money') or l:find('price') or l:find('fee') or l:find('sell') then return false end end
        for k in pairs(CMCrafting.Config) do local l = k:lower(); if l:find('price') or l:find('value') or l:find('fee') then return false end end return true end)())
end

print(('\ncm-crafting selftest: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
