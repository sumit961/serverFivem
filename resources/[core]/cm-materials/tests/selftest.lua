-- Deterministic self-test for the cm-materials catalog, production graph and economy rules (no FiveM, no database).
--   lua tests/selftest.lua        (run from resources/[core]/cm-materials)
--
-- REAL: shared/catalog.lua + shared/graph.lua; the REAL cm-items definitions (../cm-items/shared/items.lua); the REAL cm-crafting recipe
--       registry (core.lua + config.lua) for recipe registration; the REAL source files of cm-recycling/cm-trucking for the "deferred stays disabled" checks.
-- DOUBLES: the cm-crafting characters/inventory/store are not used here (registration only). Real crafting+inventory settlement of a production
--       recipe is covered by tests/integration_crafting.lua.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local core = here .. '/..'

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
local function readAll(p) local f = io.open(p, 'rb'); if not f then return nil end local s = f:read('a'); f:close(); return s end

dofile(here .. '/shared/catalog.lua')
dofile(here .. '/shared/graph.lua')
local M, G = CMMaterials, CMMaterials.Graph
CMItems = {}
dofile(core .. '/cm-items/shared/items.lua')
local function itemDef(name) return CMItems.Items[name] end

local function has(errs, needle) for _, e in ipairs(errs) do if e:find(needle, 1, true) then return true end end return false end
local function mutated(fn) local c = { Version = M.Version, Economy = G.deepCopy(M.Economy), Stages = M.Stages, Categories = M.Categories, Tags = M.Tags, Statuses = M.Statuses, LinkStatuses = M.LinkStatuses, StationTypes = G.deepCopy(M.StationTypes), Items = G.deepCopy(M.Items), Recipes = G.deepCopy(M.Recipes) }; fn(c); return G.validate(c, { itemDef = itemDef }) end

-- =================================================================== CATALOG (real cm-items definitions)
local errs = G.validate(M, { itemDef = itemDef })
check('CATALOG validates against the real cm-items definitions', #errs == 0, errs[1])
local ids, count = {}, 0
for id in pairs(M.Items) do ids[#ids + 1] = id; count = count + 1 end
check('CATALOG is small: 6-12 materials', count >= 6 and count <= 12, count)
local allExist = true
for _, id in ipairs(ids) do if not itemDef(id) then allExist = false end end
check('CATALOG every material id exists in cm-items', allExist)
local rid, dupR = {}, false
for _, r in ipairs(M.Recipes) do if rid[r.id] then dupR = true end rid[r.id] = true end
check('CATALOG recipe ids are unique', not dupR)
local fine = true
for _, id in ipairs(ids) do
    local m, d = M.Items[id], itemDef(id)
    if not (M.Stages[m.stage] and M.Categories[m.category] and m.refValue > 0 and m.refValue % 5 == 0 and d.stack == true and d.unique == false and d.weight > 0) then fine = false end
end
check('CATALOG stages/categories valid, positive round values, stackable commodities', fine)
check('CATALOG commodities carry no metadata requirement and are not usable', (function() for _, id in ipairs(ids) do local d = itemDef(id); if d.metadataRequired or d.usable == true then return false end end return true end)())
check('CATALOG reuses the EXISTING cm-items materials (no duplicate iron/scrap/plastic items)', M.Items.metal_scrap and M.Items.plastic and (function()
    for k in pairs(CMItems.Items) do if k:find('^refined_') or k == 'iron' or k == 'steel' or k == 'scrap' then return false end end return true end)())
check('CATALOG materials stay within V1 stages (raw/processed only; component stage unused)', (function() for _, id in ipairs(ids) do if M.Items[id].stage == 'component' then return false end end return true end)())
check('CATALOG weights let a no-bag character (25 kg) carry meaningful but bounded stacks', (function()
    for _, id in ipairs(ids) do local w = itemDef(id).weight; local n = math.floor(25000 / w); if n < 20 or n > 700 then return false, id end end return true end)())
check('CATALOG no material has a direct NPC sale (no universal sell NPC)', (function() for _, id in ipairs(ids) do if M.Items[id].directSale ~= false then return false end end return true end)())

-- =================================================================== GRAPH
check('GRAPH every recipe input and output is a catalog material', (function()
    for _, r in ipairs(M.Recipes) do for _, l in ipairs(r.inputs) do if not M.Items[l.item] then return false end end for _, l in ipairs(r.outputs) do if not M.Items[l.item] then return false end end end return true end)())
check('GRAPH no cycle (no A->B->A) in the production graph', G.findCycle(M) == nil)
check('GRAPH every non-deferred material has a source and a sink', (function() for _, id in ipairs(ids) do local m = M.Items[id]; if m.status ~= 'DEFERRED' and (#m.sources == 0 or #m.sinks == 0) then return false end end return true end)())
check('GRAPH source/sink process links agree with the recipes', #errs == 0)
check('GRAPH one mineral, one wood and one reclaimed chain exist', (function()
    local c = {}
    for _, r in ipairs(M.Recipes) do for _, o in ipairs(r.outputs) do c[M.Items[o.item].category] = true end end
    return c.mineral and c.wood and c.reclaimed end)())
check('GRAPH every processed material has a documented sink', (function() for _, id in ipairs(ids) do local m = M.Items[id]; if m.stage == 'processed' and #m.sinks == 0 then return false end end return true end)())
check('GRAPH the DEFERRED material (plastic) is in no enabled recipe', (function() for _, r in ipairs(M.Recipes) do if r.enabled then for _, l in ipairs(r.inputs) do if l.item == 'plastic' then return false end end end end return true end)())

-- =================================================================== RECIPES (real cm-crafting registry)
CMCrafting = {}
dofile(core .. '/cm-crafting/config.lua')
dofile(core .. '/cm-crafting/server/core.lua')
local cfg = G.deepCopy(CMCrafting.Config)
cfg.TrustedOwners = { ['cm-test-station-owner'] = true }
local reg = CMCrafting.Core.New({
    cfg = cfg, store = {}, now = os.time, rand = math.random, encode = tostring, decode = function() return nil end,
    chars = {}, items = { exists = function(n) return CMItems.Items[n] ~= nil end, validateMetadata = function() return true end },
    inventory = { ready = function() return true end }, owners = { started = function() return true end, call = function() return true, true end },
    audit = function() end, rate = function() return true end,
})
local regOk = true
for _, r in ipairs(M.Recipes) do
    local def = G.deepCopy(r); def.enabled = nil
    local ok, why = reg:RegisterRecipe('cm-test-station-owner', def)
    if not ok then regOk = false; print('   register failed: ' .. r.id .. ' ' .. tostring(why)) end
end
check('RECIPES every production recipe registers with the REAL cm-crafting registry', regOk)
check('RECIPES an untrusted resource cannot register them', select(2, reg:RegisterRecipe('cm-random', G.deepCopy(M.Recipes[1]))) == 'untrusted_resource')
check('RECIPES quantities positive and station types possible', (function()
    for _, r in ipairs(M.Recipes) do
        for _, l in ipairs(r.inputs) do if l.amount < 1 then return false end end
        for _, l in ipairs(r.outputs) do if l.amount < 1 then return false end end
        for _, s in ipairs(r.stations) do if not M.StationTypes[s] then return false end end
    end return true end)())
check('RECIPES all are namespaced materials: (distinct from cm-crafting test: recipes)', (function() for _, r in ipairs(M.Recipes) do if not r.id:find('^materials:') then return false end end return true end)())
check('RECIPES no reverse recipe exists (no A->B plus B->A)', (function()
    local fwd = {}
    for _, r in ipairs(M.Recipes) do for _, i in ipairs(r.inputs) do for _, o in ipairs(r.outputs) do fwd[i.item .. '>' .. o.item] = true end end end
    for k in pairs(fwd) do local a, b = k:match('^(.-)>(.*)$'); if fwd[b .. '>' .. a] then return false end end return true end)())

-- =================================================================== ECONOMY
print('\n   value flow (reference value; per recipe):')
local allOk = true
for _, r in ipairs(M.Recipes) do
    local v = G.recipeValues(M, r, M.Items)
    print(('   %-24s in=%4d out=%4d created=%3d allowance=%3d createdPerHour(back-to-back)=%5d'):format(r.id, v.inputValue, v.outputValue, v.created, v.allowance, v.createdPerHour))
    if v.created > v.allowance or v.createdPerHour > M.Economy.processing.maxValueCreatedPerHour or v.created < 0 then allOk = false end
end
check('ECONOMY no recipe creates more than its processing justification; none destroys value; hourly cap respected', allOk)
check('ECONOMY positive-value cycle impossible (graph acyclic and no reverse recipe)', G.findCycle(M) == nil)
check('ECONOMY a chain end-to-end never exceeds raw value plus cumulative allowance', (function()
    -- ore -> ingot, log -> timber, scrap -> reclaimed: compare 1 raw "unit chain" value
    for _, r in ipairs(M.Recipes) do local v = G.recipeValues(M, r, M.Items); if v.outputValue > v.inputValue + v.allowance then return false end end return true end)())
print('\n   gathering ceilings (items/hour so that material value <= 40% of the 50k beginner activity band):')
for _, id in ipairs({ 'iron_ore', 'log', 'metal_scrap', 'plastic' }) do print(('   %-12s ref=%4d ceiling=%d/h'):format(id, M.Items[id].refValue, G.quantityCeilingPerHour(M, id))) end
check('ECONOMY ceilings: iron_ore 200/h, log 166/h, metal_scrap 500/h', G.quantityCeilingPerHour(M, 'iron_ore') == 200 and G.quantityCeilingPerHour(M, 'log') == 166 and G.quantityCeilingPerHour(M, 'metal_scrap') == 500)
check('ECONOMY ceiling value never exceeds the material share', (function()
    for _, id in ipairs(ids) do local c = G.quantityCeilingPerHour(M, id); if c * M.Items[id].refValue > M.Economy.gatheringActivityBandPerHour[1] * M.Economy.maxMaterialShareOfActivity then return false end end return true end)())

-- =================================================================== SOURCE / SINK / DEFERRED STAYS DISABLED
check('SOURCE/SINK no material or link is ACTIVE until its owner integrates (honest status)', (function()
    for _, id in ipairs(ids) do local m = M.Items[id]; if m.status == 'ACTIVE' then return false end
        for _, l in ipairs(m.sources) do if l.status == 'active' then return false end end for _, l in ipairs(m.sinks) do if l.status == 'active' then return false end end end return true end)())
check('SOURCE/SINK every external link names an owner and a contract/note', (function()
    for _, id in ipairs(ids) do for _, l in ipairs(M.Items[id].sinks) do if l.kind == 'external' and (not l.owner or not l.contract) then return false end end
        for _, l in ipairs(M.Items[id].sources) do if l.kind ~= 'process' and (not l.owner or not l.note) then return false end end end return true end)())
local rec = readAll(core .. '/cm-recycling/shared/config.lua') or ''
check('DEFERRED cm-recycling material grants stay disabled (materialsEnabled = false)', rec:find('materialsEnabled%s*=%s*false') ~= nil)
local truck = readAll(core .. '/cm-trucking/shared/config.lua') or ''
check('DEFERRED cm-trucking bulk_material_transport stays disabled', truck:find("%-%-%s*'bulk_material_transport' is deferred") ~= nil)
for _, r in ipairs({ 'mining', 'lumber', 'construction', 'warehouse' }) do   -- informational drift note, not a pass/fail gate for Agent 3
    local f = io.open(core .. '/cm-' .. r .. '/server/main.lua', 'rb'); local size = 0
    if f then size = #f:read('a'); f:close() end
    print(('   note: cm-%s/server/main.lua is %d bytes (%s)'):format(r, size, size == 0 and 'empty scaffold: catalog links stay integration_required' or 'HAS CODE: re-audit the catalog links for this owner'))
end

-- =================================================================== validator mutation tests (the rules actually bite)
check('MUTATION item missing from cm-items is detected', has(mutated(function(c) c.Items.ghost_ore = G.deepCopy(c.Items.iron_ore) end), 'ghost_ore: not defined in cm-items'))
check('MUTATION non-round reference value is detected', has(mutated(function(c) c.Items.iron_ore.refValue = 103 end), 'not a round'))
check('MUTATION zero reference value is detected', has(mutated(function(c) c.Items.iron_ore.refValue = 0 end), 'positive whole number'))
check('MUTATION ACTIVE material with a non-active link is detected', has(mutated(function(c) c.Items.iron_ore.status = 'ACTIVE' end), 'ACTIVE material has a non-active link'))
check('MUTATION ACTIVE material without an active sink is detected', has(mutated(function(c) c.Items.iron_ore.status = 'ACTIVE'; c.Items.iron_ore.sources[1].status = 'active'; c.Items.iron_ore.sinks[1].status = 'deferred' end), 'no active sink'))
check('MUTATION source without a sink is detected', has(mutated(function(c) c.Items.log.sinks = {} end), 'at least one source and one sink'))
check('MUTATION recipe with an unknown input is detected', has(mutated(function(c) c.Recipes[1].inputs[1].item = 'mystery' end), 'not a catalog material'))
check('MUTATION impossible station type is detected', has(mutated(function(c) c.Recipes[1].stations = { 'warp_gate' } end), 'impossible station type'))
check('MUTATION handcraft production recipe is detected', has(mutated(function(c) c.Recipes[1].handcraft = true end), 'handcraft must be false'))
check('MUTATION value-creating recipe is detected', has(mutated(function(c) c.Recipes[1].outputs[1].amount = 3 end), 'creates'))
check('MUTATION value-destroying recipe is detected', has(mutated(function(c) c.Recipes[1].inputs[1].amount = 9 end), 'destroys'))
check('MUTATION A->B plus B->A cycle is detected', has(mutated(function(c)
    c.Items.ingot2 = G.deepCopy(c.Items.iron_ingot); c.Recipes[#c.Recipes + 1] = { id = 'materials:back', label = 'Back', durationSeconds = 5, batch = { min = 1, max = 1 }, stations = { 'furnace' }, handcraft = false, enabled = true, inputs = { { item = 'iron_ingot', amount = 1 } }, outputs = { { item = 'iron_ore', amount = 3 } } } end), 'cycle'))
check('MUTATION enabled recipe consuming the DEFERRED material is detected', has(mutated(function(c) c.Recipes[1].inputs[1] = { item = 'plastic', amount = 3 } end), 'DEFERRED'))
check('MUTATION direct sale above 50% of reference is detected', has(mutated(function(c) c.Items.iron_ore.directSale = { price = 80 } end), 'directSale'))
check('MUTATION direct sale at or below 50% is allowed', not has(mutated(function(c) c.Items.iron_ore.directSale = { price = 50 } end), 'directSale'))
check('MUTATION output metadata on a commodity is detected', has(mutated(function(c) c.Recipes[1].outputs[1].metadata = { q = 1 } end), 'metadata'))
check('MUTATION process link to a recipe that does not produce the item is detected', has(mutated(function(c) c.Items.iron_ingot.sources[1].recipe = 'materials:saw_timber'; c.Items.iron_ingot.sources[1].station = 'sawmill' end), 'does not produce'))
check('MUTATION a serial/unique commodity is detected', has((function() local d = CMItems.Items.iron_ore; local old = d.unique; d.unique = true; local e = G.validate(M, { itemDef = itemDef }); d.unique = old; return e end)(), 'stackable non-unique'))

print(('\ncm-materials self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
