-- Production-recipe integration test: cm-materials recipes -> REAL cm-crafting core -> production adapter -> REAL cm-inventory craft settlement.
--   lua tests/integration_crafting.lua        (run from resources/[core]/cm-materials)
--
-- REAL: cm-materials catalog/recipes, the real cm-items DEFINITIONS (weight/stack of the material items are copied into the item double),
--       cm-crafting core + config, the PRODUCTION inventory adapter extracted verbatim from cm-crafting/server/main.lua, and the real
--       cm-inventory craft code (server/craft.lua + internals) via ../cm-inventory/tests/craft_harness.lua.
-- DOUBLES (labelled): the FiveM runtime, the SQL layer under cm-inventory (in-memory, transactional undo), the cm-crafting session store, characters.
--       No MySQL, no connected client. No physical station/job exists yet: the station is a test fixture registered by a TEST owner.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local core = here .. '/..'
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

dofile(here .. '/shared/catalog.lua'); dofile(here .. '/shared/graph.lua')
local M, G = CMMaterials, CMMaterials.Graph
CMItems = {}; dofile(core .. '/cm-items/shared/items.lua')
CMCrafting = {}; dofile(core .. '/cm-crafting/config.lua'); dofile(core .. '/cm-crafting/server/core.lua')
local H = dofile(core .. '/cm-inventory/tests/craft_harness.lua')(core .. '/cm-inventory')
local json = H.json

-- real cm-items weight/stack for every catalog material
for id in pairs(M.Items) do
    local d = CMItems.Items[id]
    H.ITEMS[id] = { weight = d.weight, stack = d.stack, unique = d.unique, durability = d.durability }
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

-- production adapter, verbatim from cm-crafting/server/main.lua
local f = assert(io.open(core .. '/cm-crafting/server/main.lua', 'rb')); local mainSrc = f:read('a'); f:close()
local function slice(from, to)
    local a = assert(mainSrc:find(from, 1, true)); local b = assert(mainSrc:find(to, a, true)); return mainSrc:sub(a, b - 1)
end
local adapterSrc = slice('local function xcall', 'local function jsonEncode') .. '\n' .. slice('local capability =', 'local hits = {}') .. '\nreturn inventory\n'

local OWNER = 'cm-test-station-owner'   -- stands in for the future Agent 3 station owner (cm-mining / cm-lumber / cm-recycling)
local db = H.newDb(); db.addChar(1)
local inv = H.newWorld(db, {}); inv.invoker = 'cm-crafting'
local bridge = setmetatable({}, { __index = function(_, res)
    if res ~= 'cm-inventory' then return setmetatable({}, { __index = function() return function() error('no export') end end }) end
    return setmetatable({}, { __index = function(_, name) local fn = inv.registry[name]; return function(self, ...) return fn(self, ...) end end })
end })
local adapter = assert(load(adapterSrc, '@adapter', 't', { exports = bridge, GetResourceState = function() return 'started' end, os = os, pcall = pcall, table = table, type = type, tostring = tostring, tonumber = tonumber, string = string }))()

local store, now = newStore(), 1000000
local cfg = deepcopy(CMCrafting.Config); cfg.TrustedOwners = { [OWNER] = true }
local engine = CMCrafting.Core.New({
    cfg = cfg, store = store, now = function() return now end,
    rand = (function() local s = 99 return function(a, b) s = (s * 1103515245 + 12345) % 2147483648; if a then return (s // 65536) % (b - a + 1) + a end return 0.5 end end)(),
    encode = ser, decode = deser,
    chars = { sourceOf = function() return 1101 end, position = function() return { x = 100.0, y = 101.0, z = 30.0, bucket = 0 } end },
    items = { exists = function(n) return CMItems.Items[n] ~= nil end, validateMetadata = function() return true end },
    inventory = adapter, owners = { started = function() return true end, call = function() return true, true end },
    audit = function() end, rate = function() return true end,
})

-- a station owner registers the catalog's definitions for its station type (the documented pattern)
local function registerFor(stationType)
    local n = 0
    for _, r in ipairs(M.Recipes) do
        if r.enabled and r.stations[1] == stationType then
            local def = G.deepCopy(r); def.enabled = nil
            local ok, why = engine:RegisterRecipe(OWNER, def); assert(ok, why); n = n + 1
        end
    end
    return n
end
for _, st in ipairs({ 'furnace', 'sawmill', 'recycling_processor' }) do
    registerFor(st)
    assert(engine:RegisterStation(OWNER, { id = 'test_' .. st, type = st, coords = { x = 100.0, y = 100.0, z = 30.0 }, radius = 3.0 }))
end

local function stock(item) return db.count(1, item) end
local function produce(recipe, station, qty)
    local ok, res = engine:Begin(OWNER, '1', recipe, qty, station, {})
    if not ok then return false, res end
    local s = store.sessGet(res.reference); now = s.ready_at
    local okC, resC = engine:Complete(OWNER, res.reference, '1', {})
    return okC, resC, res.reference
end

check('SETUP production adapter sees the REAL inventory owner (not settlement_unavailable)', adapter.ready() == true)

-- ------------------------------------------------------------ mineral chain
db.clear(1); db.give(1, 'pocket-1', 'iron_ore', 10)
local ok, res, ref = produce('materials:smelt_iron', 'test_furnace', 2)
check('MINERAL smelt 2 batches: 6 iron_ore -> 2 iron_ingot through real cm-crafting + real inventory transaction', ok == true and stock('iron_ore') == 4 and stock('iron_ingot') == 2, res)
check('MINERAL the inventory ledger holds the session reference exactly once', #db.ledger == 1 and db.ledger[1].reference == ref)
local snap = db.fingerprint()
local okR, _, tag = engine:Complete(OWNER, ref, '1', {})
check('MINERAL completing again is a replay and mutates nothing', okR == true and tag == 'replayed' and db.fingerprint() == snap)
local okF, whyF = produce('materials:smelt_iron', 'test_furnace', 2)
check('MINERAL insufficient ore (4 < 6) is refused before anything is consumed', okF == false and whyF == 'insufficient_input' and stock('iron_ore') == 4 and stock('iron_ingot') == 2)

-- ------------------------------------------------------------ wood chain
db.clear(1); db.give(1, 'pocket-1', 'log', 4)
ok, res = produce('materials:saw_timber', 'test_sawmill', 2)
check('WOOD saw 2 batches: 4 log -> 6 timber', ok == true and stock('log') == 0 and stock('timber') == 6, res)

-- ------------------------------------------------------------ reclaimed chain
db.clear(1); db.give(1, 'pocket-1', 'metal_scrap', 9)
ok, res = produce('materials:reclaim_metal', 'test_recycling_processor', 2)
check('RECLAIMED reclaim 2 batches: 8 metal_scrap -> 2 reclaimed_metal (1 scrap left over)', ok == true and stock('metal_scrap') == 1 and stock('reclaimed_metal') == 2, res)

-- ------------------------------------------------------------ capacity with REAL weights
db.clear(1); db.give(1, 'pocket-1', 'log', 30)   -- 30 x 800 g = 24 kg of a 25 kg no-bag limit
local okC, whyC = produce('materials:saw_timber', 'test_sawmill', 5)   -- 10 logs -> 15 timber (+9 kg, -8 kg = 25 kg) fits exactly? 30*800-8000+15*600 = 25000
check('CAPACITY real weights: post-transaction weight of exactly 25 kg is accepted', okC == true and stock('log') == 20 and stock('timber') == 15, whyC)
db.clear(1); db.give(1, 'pocket-1', 'log', 30)
okC, whyC = produce('materials:saw_timber', 'test_sawmill', 6)   -- 12 logs -> 18 timber: 24000-9600+10800 = 25200 > 25000
check('CAPACITY real weights: 25.2 kg final state is refused and nothing changes', okC == false and whyC == 'no_capacity' and stock('log') == 30 and stock('timber') == 0)

-- ------------------------------------------------------------ boundaries
check('BOUNDARY the catalog recipes cannot be run by another resource', select(2, engine:Begin('cm-other', '1', 'materials:smelt_iron', 1, 'test_furnace', {})) ~= nil and select(1, engine:Begin('cm-other', '1', 'materials:smelt_iron', 1, 'test_furnace', {})) == false)
check('BOUNDARY no recipe grants plastic (DEFERRED) or any cash/currency item', (function()
    for _, r in ipairs(M.Recipes) do for _, o in ipairs(r.outputs) do if o.item == 'plastic' or o.item:find('cash') or o.item:find('money') then return false end end end return true end)())

print(('\ncm-materials production-recipe integration: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
