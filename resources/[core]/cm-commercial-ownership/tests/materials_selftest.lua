-- Deterministic self-test for the business material demand & settlement platform.
--   lua tests/materials_selftest.lua        (run from resources/[core]/cm-commercial-ownership)
-- See tests/materials_harness.lua for exactly what is REAL (production materials.lua, real cm-materials exports, real cm-items definitions,
-- real cm-inventory atomic sink) and what is a labelled DOUBLE (FiveM runtime, business SQL layer, foundation, broker). No MySQL, no player.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local coRoot = here .. '/..'
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

dofile(here .. '/config.lua')   -- global Config (real)
local H = dofile(here .. '/tests/materials_harness.lua')(coRoot)
local invH, Sched = H.inv, H.Sched
local catReg = H.loadMaterialsCatalog(coRoot)

-- real material weights/stack into the inventory item double
local itemsEnv = setmetatable({ CMItems = {} }, { __index = _G })
assert(load(assert(io.open(coRoot .. '/cm-items/shared/items.lua', 'rb')):read('a'), '@items', 't', itemsEnv))()
for _, id in ipairs({ 'timber', 'iron_ore', 'iron_ingot', 'log', 'reclaimed_metal', 'metal_scrap', 'plastic' }) do
    local d = itemsEnv.CMItems.Items[id]; invH.ITEMS[id] = { weight = d.weight, stack = d.stack, unique = d.unique }
end

local function newWorld(shared)
    shared = shared or {}
    local W = { now = 1000000, invDb = shared.invDb or invH.newDb(), businesses = shared.businesses or { ['store:1'] = { owner = 100 }, ['mechanic:7'] = { owner = 101 }, ['gasstation:2'] = { owner = false } } }
    for c = 1, 4 do W.invDb.addChar(c) end
    W.invW = invH.newWorld(W.invDb)
    local C, env = H.loadMaterialsModule({ Config = Config, MySQL = {}, businesses = W.businesses, path = here .. '/server/materials.lua' })
    W.bizDb = shared.bizDb or H.newBizDb(C.Materials.SQL)
    -- rebind the SQL double to THIS module's statements (same strings) and load it
    env.MySQL = W.bizDb.MySQL
    W.C, W.M = C, C.Materials
    C.TestNow = function() return W.now end
    C.TestMaterials = { IsMaterial = catReg.IsMaterial, GetMaterial = catReg.GetMaterial }
    W.inventoryCalls = {}
    W.hook = nil
    C.TestInventory = {
        ExecuteItemSinkTransaction = function(ref, cid, items)
            if W.hook and W.hook.before_debit then W.hook.before_debit(ref) end
            W.invW.invoker = 'cm-commercial-ownership'
            W.inventoryCalls[#W.inventoryCalls + 1] = ref
            local a, b = W.invW.registry.ExecuteItemSinkTransaction(ref, cid, items)
            if W.hook and W.hook.after_debit then W.hook.after_debit(ref) end
            if W.inventoryDown then return false, 'unavailable' end
            return a, b
        end,
        GetItemSinkTransactionStatus = function(ref)
            W.invW.invoker = 'cm-commercial-ownership'
            return W.invW.registry.GetItemSinkTransactionStatus(ref)
        end,
    }
    W.contracts = { created = {}, cancelled = {}, bySource = {} }
    C.TestBroker = {
        CreateContract = function(data)
            local ex = W.contracts.bySource[data.sourceReference]
            if ex then return true, { reference = ex, existing = true } end
            local ref = ('CT-%04d'):format(#W.contracts.created + 1)
            W.contracts.created[#W.contracts.created + 1] = { reference = ref, data = data }
            W.contracts.bySource[data.sourceReference] = ref
            return true, { reference = ref, existing = false }
        end,
        CancelContract = function(ctype, ref, reason) W.contracts.cancelled[#W.contracts.cancelled + 1] = { ref = ref, reason = reason }; return true end,
    }
    W.as = function(who) C.TestInvoker = who end
    W.as('cm-commercial-ownership')
    return W
end
local function giveTimber(W, cid, n) W.invDb.clear(cid); if n > 0 then W.invDb.give(cid, 'pocket-1', 'timber', n) end end
local function timber(W, cid) return W.invDb.count(cid, 'timber') end
local function demand(W, qty, extra)
    local opts = { businessType = 'store', businessId = '1', materialId = 'timber', quantity = qty or 10 }
    for k, v in pairs(extra or {}) do opts[k] = v end
    W.as('cm-commercial-ownership')
    local ok, view = W.M.CreateDemand(opts)
    return ok, view
end
local function deliver(W, ref, dref, cid, qty, ctx) W.as('cm-trucking'); return W.M.Deliver(ref, dref, tostring(cid), qty, ctx) end

-- =================================================================== MATERIAL VALIDATION (real cm-materials)
do
    local W = newWorld()
    local ok1 = W.M.ApprovedMaterial('timber')
    check('MATERIAL approved material accepted', ok1 == true)
    check('MATERIAL unknown item rejected', select(2, W.M.ApprovedMaterial('mystery_item')) == 'invalid_material')
    check('MATERIAL non-material cm-items item rejected (water)', select(2, W.M.ApprovedMaterial('water')) == 'invalid_material')
    check('MATERIAL DEFERRED material rejected (plastic)', select(2, W.M.ApprovedMaterial('plastic')) == 'material_deferred')
    check('MATERIAL malformed id rejected', select(2, W.M.ApprovedMaterial("timber'; DROP")) == 'invalid_material')
    W.C.TestMaterials = { IsMaterial = function() return nil end, GetMaterial = function() return nil end }
    check('MATERIAL catalog unavailable fails closed', select(2, W.M.ApprovedMaterial('timber')) == 'unavailable')
end

-- =================================================================== BUSINESS STOCK
do
    local W = newWorld()
    check('STOCK initial balance is zero', select(2, W.M.GetStock('store', '1', 'timber')) == 0)
    W.as('cm-commercial-ownership')
    local ok, res = W.M.Credit('CRD-TEST0001', 'store', '1', 'timber', 25, {})
    check('STOCK credit', ok == true and res.quantity == 25 and res.replayed == false and W.bizDb.qty('store', '1', 'timber') == 25)
    local snap = W.bizDb.fingerprint()
    local ok2, res2 = W.M.Credit('CRD-TEST0001', 'store', '1', 'timber', 25, {})
    check('STOCK duplicate credit replays without a second credit', ok2 == true and res2.replayed == true and W.bizDb.fingerprint() == snap)
    check('STOCK same reference with a different quantity is a conflict', select(2, W.M.Credit('CRD-TEST0001', 'store', '1', 'timber', 26, {})) == 'reference_conflict' and W.bizDb.fingerprint() == snap)
    check('STOCK credit journals one event with the resulting quantity', #W.bizDb.events == 1 and W.bizDb.events[1].resulting_quantity == 25 and W.bizDb.events[1].delta == 25)
    check('STOCK credit validates quantity (zero, negative, fractional, huge)', select(2, W.M.Credit('CRD-TEST0002', 'store', '1', 'timber', 0, {})) == 'invalid_quantity' and select(2, W.M.Credit('CRD-TEST0003', 'store', '1', 'timber', -5, {})) == 'invalid_quantity'
        and select(2, W.M.Credit('CRD-TEST0004', 'store', '1', 'timber', 1.5, {})) == 'invalid_quantity' and select(2, W.M.Credit('CRD-TEST0005', 'store', '1', 'timber', 10001, {})) == 'invalid_quantity')
    check('STOCK credit rejects non-material and DEFERRED material', select(2, W.M.Credit('CRD-TEST0006', 'store', '1', 'water', 1, {})) == 'invalid_material' and select(2, W.M.Credit('CRD-TEST0007', 'store', '1', 'plastic', 1, {})) == 'material_deferred')
    check('STOCK credit rejects unknown / unowned business', select(2, W.M.Credit('CRD-TEST0008', 'store', '999', 'timber', 1, {})) == 'unknown_business' and select(2, W.M.Credit('CRD-TEST0009', 'gasstation', '2', 'timber', 1, {})) == 'no_owner')
    for i = 1, 9 do W.M.Credit(('CRD-CAP%05d'):format(i), 'store', '1', 'timber', 10000, {}) end
    check('STOCK over the 100,000 cap is refused', select(2, W.M.Credit('CRD-CAP00099', 'store', '1', 'timber', 10000, {})) == 'over_capacity' and W.bizDb.qty('store', '1', 'timber') <= 100000)
    W.as('cm-trucking')
    check('STOCK credit from a non-allowlisted resource is forbidden', select(2, W.M.Credit('CRD-TEST0011', 'store', '1', 'timber', 1, {})) == 'forbidden')
    W.as('cm-mechanic')
    check('STOCK consume from a non-allowlisted resource (mechanic) is forbidden until approved parts exist', select(2, W.M.Consume('CNS-TEST0001', 'mechanic', '7', { { material = 'timber', quantity = 1 } }, {})) == 'forbidden')
    -- consume
    local W2 = newWorld()
    W2.as('cm-commercial-ownership')
    W2.M.Credit('CRD-A0000001', 'mechanic', '7', 'reclaimed_metal', 10, {}); W2.M.Credit('CRD-A0000002', 'mechanic', '7', 'iron_ingot', 4, {})
    local c1, r1 = W2.M.Consume('CNS-TEST0001', 'mechanic', '7', { { material = 'reclaimed_metal', quantity = 2 }, { material = 'iron_ingot', quantity = 1 } }, {})
    check('STOCK multi-material consume is atomic and journaled', c1 == true and r1.replayed == false and W2.bizDb.qty('mechanic', '7', 'reclaimed_metal') == 8 and W2.bizDb.qty('mechanic', '7', 'iron_ingot') == 3 and W2.bizDb.eventsOf('consume') == 2)
    local snap2 = W2.bizDb.fingerprint()
    local c2, r2 = W2.M.Consume('CNS-TEST0001', 'mechanic', '7', { { material = 'iron_ingot', quantity = 1 }, { material = 'reclaimed_metal', quantity = 2 } }, {})
    check('STOCK consume replay (any line order) does not consume again', c2 == true and r2.replayed == true and W2.bizDb.fingerprint() == snap2)
    check('STOCK consume same reference different content is a conflict', select(2, W2.M.Consume('CNS-TEST0001', 'mechanic', '7', { { material = 'iron_ingot', quantity = 2 } }, {})) == 'reference_conflict' and W2.bizDb.fingerprint() == snap2)
    local c3, why3, short = W2.M.Consume('CNS-TEST0002', 'mechanic', '7', { { material = 'reclaimed_metal', quantity = 3 }, { material = 'iron_ingot', quantity = 9 } }, {})
    check('STOCK insufficient requirement rolls back EVERY line (multi-material all-or-nothing)', c3 == false and why3 == 'insufficient_material' and short == 'iron_ingot' and W2.bizDb.fingerprint() == snap2)
    check('STOCK never negative: exact drain then one more fails', (function()
        local a = W2.M.Consume('CNS-TEST0003', 'mechanic', '7', { { material = 'iron_ingot', quantity = 3 } }, {})
        local b, w = W2.M.Consume('CNS-TEST0004', 'mechanic', '7', { { material = 'iron_ingot', quantity = 1 } }, {})
        return a == true and b == false and w == 'insufficient_material' and W2.bizDb.qty('mechanic', '7', 'iron_ingot') == 0 end)())
    check('STOCK invalid requirement shapes rejected', select(2, W2.M.Consume('CNS-TEST0005', 'mechanic', '7', {}, {})) == 'invalid_requirements' and select(2, W2.M.Consume('CNS-TEST0006', 'mechanic', '7', { { material = 'timber', quantity = 1 }, { material = 'timber', quantity = 1 } }, {})) == 'invalid_requirements'
        and select(2, W2.M.Consume('CNS-TEST0007', 'mechanic', '7', { { material = 'timber', quantity = 0 } }, {})) == 'invalid_requirements')
    check('STOCK consume failure injection (SQL error mid-way) rolls back', (function()
        local before = W2.bizDb.fingerprint()
        W2.bizDb.failOn = function(name) return name == 'eventInsert' end
        local a = W2.M.Consume('CNS-TEST0008', 'mechanic', '7', { { material = 'reclaimed_metal', quantity = 1 } }, {})
        W2.bizDb.failOn = nil
        return a == false and W2.bizDb.fingerprint() == before end)())
    check('STOCK business stock is a separate ledger from retail product stock (no cm_stores.stock write)', (function()
        for _, e in ipairs(W2.bizDb.events) do if e.material_id ~= 'reclaimed_metal' and e.material_id ~= 'iron_ingot' then return false end end return true end)())
    check('STOCK GetBusinessMaterials lists positive balances only', (function() local ok, list = W2.M.GetMaterials('mechanic', '7'); return ok and #list == 1 and list[1].materialId == 'reclaimed_metal' and list[1].quantity == 8 end)())
    check('STOCK read of an unknown business fails', select(2, W2.M.GetStock('store', '404', 'timber')) == 'unknown_business')
end

-- =================================================================== DEMAND
do
    local W = newWorld()
    local ok, v = demand(W, 100)
    check('DEMAND create valid (open, remaining = required)', ok == true and v.status == 'open' and v.required == 100 and v.remaining == 100 and v.fulfilled == 0 and v.material == 'timber')
    check('DEMAND invalid business / unowned business', select(2, demand(W, 5, { businessId = '404' })) == 'unknown_business' and select(2, demand(W, 5, { businessType = 'gasstation', businessId = '2' })) == 'no_owner')
    check('DEMAND invalid material / DEFERRED material', select(2, demand(W, 5, { materialId = 'water' })) == 'invalid_material' and select(2, demand(W, 5, { materialId = 'plastic' })) == 'material_deferred')
    check('DEMAND zero / negative / fractional / huge quantity', select(2, demand(W, 0)) == 'invalid_quantity' and select(2, demand(W, -1)) == 'invalid_quantity' and select(2, demand(W, 2.5)) == 'invalid_quantity' and select(2, demand(W, 5001)) == 'invalid_quantity')
    check('DEMAND invalid category / deadline', select(2, demand(W, 5, { category = 'free_money' })) == 'invalid_category' and select(2, demand(W, 5, { deadlineMinutes = 1 })) == 'invalid_deadline')
    local a, v1 = demand(W, 10, { idempotencyKey = 'order-key-1' })
    W.as('cm-commercial-ownership'); local b, v2, tag = W.M.CreateDemand({ businessType = 'store', businessId = '1', materialId = 'timber', quantity = 10, idempotencyKey = 'order-key-1' })
    check('DEMAND duplicate idempotency key returns the same demand once', a == true and b == true and v1.reference == v2.reference and tag == 'replayed' and #W.bizDb.demands == 2)
    check('DEMAND idempotency key reused with different content is rejected', select(2, demand(W, 11, { idempotencyKey = 'order-key-1' })) == 'idempotency_conflict')
    check('DEMAND caller must be allowlisted', (function() W.as('cm-trucking'); local r = select(2, W.M.CreateDemand({ businessType = 'store', businessId = '1', materialId = 'timber', quantity = 1 })); W.as('cm-commercial-ownership'); return r == 'forbidden' end)())
    for i = 1, 3 do demand(W, 1) end
    check('DEMAND per-business open demand limit', select(2, demand(W, 1)) == 'too_many_demands')
    local W2 = newWorld()
    local _, d2 = demand(W2, 10)
    W2.as('cm-commercial-ownership')
    local c1, r1 = W2.M.CancelDemand(d2.reference, 'staff')
    check('DEMAND cancel', c1 == true and r1.replayed == false and W2.bizDb.demandBy(d2.reference).status == 'cancelled')
    check('DEMAND cancel replay', select(2, W2.M.CancelDemand(d2.reference, 'staff')).replayed == true)
    giveTimber(W2, 1, 10)
    check('DEMAND a cancelled demand cannot be delivered to', select(2, deliver(W2, 'DEL-CANCEL001', d2.reference, 1, 5)) == 'demand_closed' and timber(W2, 1) == 10)
    local _, d3 = demand(W2, 10, { deadlineMinutes = 10 })
    W2.now = W2.now + 11 * 60
    W2.as('cm-commercial-ownership')
    check('DEMAND delivery after the deadline is refused', select(2, deliver(W2, 'DEL-LATE00001', d3.reference, 1, 5)) == 'deadline_passed' and timber(W2, 1) == 10)
    W2.as('cm-admin'); local rs = select(2, W2.M.AdminReconcile())
    check('DEMAND reconciliation expires a past-deadline demand with nothing in flight', rs.expired >= 1 and W2.bizDb.demandBy(d3.reference).status == 'expired')
    check('DEMAND capacity: stock + open demands + new quantity may not exceed the per-material cap', (function()
        local W3 = newWorld(); W3.as('cm-commercial-ownership')
        for i = 1, 4 do W3.M.CreateDemand({ businessType = 'store', businessId = '1', materialId = 'timber', quantity = 5000 }) end
        for i = 1, 8 do W3.M.Credit(('CRD-DC%06d'):format(i), 'store', '1', 'timber', 10000, {}) end
        local r = select(2, W3.M.CreateDemand({ businessType = 'store', businessId = '1', materialId = 'timber', quantity = 5000 }))
        return r == 'over_capacity' end)())
end

-- =================================================================== DELIVERY (real inventory sink)
do
    local W = newWorld()
    local _, d = demand(W, 10)
    giveTimber(W, 1, 10)
    local ok, res = deliver(W, 'DEL-OK0000001', d.reference, 1, 10)
    check('DELIVERY player -> business: inventory debited exactly once, business credited exactly once, demand fulfilled', ok == true and res.status == 'completed' and res.replayed == false and timber(W, 1) == 0 and W.bizDb.qty('store', '1', 'timber') == 10 and W.bizDb.demandBy(d.reference).status == 'fulfilled')
    check('DELIVERY the real inventory ledger holds one item_sink row', #W.invDb.ledger == 1 and W.invDb.ledger[1].tx_type == 'item_sink' and W.invDb.ledger[1].reference == 'BMD-DEL-OK0000001')
    check('DELIVERY events journal the delivery with the character and resulting quantity', (function() local e = W.bizDb.events[#W.bizDb.events]; return e.event_type == 'delivery' and e.delta == 10 and e.resulting_quantity == 10 and tostring(e.character_id) == '1' end)())
    local snap, isnap = W.bizDb.fingerprint(), W.invDb.fingerprint()
    local ok2, res2 = deliver(W, 'DEL-OK0000001', d.reference, 1, 10)
    check('DELIVERY replay (same reference, same payload) returns the previous result and mutates NOTHING', ok2 == true and res2.replayed == true and W.bizDb.fingerprint() == snap and W.invDb.fingerprint() == isnap)
    check('DELIVERY same reference + different quantity / character is a conflict', select(2, deliver(W, 'DEL-OK0000001', d.reference, 1, 9)) == 'reference_conflict' and select(2, deliver(W, 'DEL-OK0000001', d.reference, 2, 10)) == 'reference_conflict' and W.bizDb.fingerprint() == snap)
    check('DELIVERY a fulfilled demand accepts nothing more', select(2, deliver(W, 'DEL-OK0000002', d.reference, 1, 1)) == 'demand_closed')

    local W2 = newWorld()
    local _, d2 = demand(W2, 10)
    giveTimber(W2, 1, 4)
    local snapB, snapI = W2.bizDb.fingerprint(), W2.invDb.fingerprint()
    local ok3, why3 = deliver(W2, 'DEL-SHORT0001', d2.reference, 1, 10)
    check('DELIVERY insufficient player material: refused, reservation released, nothing credited', ok3 == false and why3 == 'insufficient_input' and timber(W2, 1) == 4 and W2.bizDb.qty('store', '1', 'timber') == 0
        and W2.bizDb.demandBy(d2.reference).quantity_reserved == 0 and W2.bizDb.deliveryBy('DEL-SHORT0001').status == 'failed' and W2.invDb.fingerprint() == snapI)
    check('DELIVERY a failed delivery reference replays as failed (never re-debits)', select(2, deliver(W2, 'DEL-SHORT0001', d2.reference, 1, 10)) == 'insufficient_input')
    giveTimber(W2, 1, 10)
    W2.inventoryDown = true
    local ok4, why4 = deliver(W2, 'DEL-DOWN00001', d2.reference, 1, 10)
    W2.inventoryDown = false
    check('DELIVERY inventory unavailable (unknown outcome): reported unavailable, delivery stays prepared with the reservation held', ok4 == false and why4 == 'unavailable' and W2.bizDb.deliveryBy('DEL-DOWN00001').status == 'prepared' and W2.bizDb.demandBy(d2.reference).quantity_reserved == 10)
    check('DELIVERY the debit really happened despite the lost response (ledger says committed)', W2.invW.registry.GetItemSinkTransactionStatus('BMD-DEL-DOWN00001') == 'committed' or (function() W2.invW.invoker = 'cm-commercial-ownership'; return W2.invW.registry.GetItemSinkTransactionStatus('BMD-DEL-DOWN00001') == 'committed' end)())
    W2.now = W2.now + 10; W2.as('cm-admin'); W2.M.AdminReconcile()
    check('DELIVERY reconciliation completes the lost-response delivery without debiting again', timber(W2, 1) == 0 and W2.bizDb.qty('store', '1', 'timber') == 10 and W2.bizDb.deliveryBy('DEL-DOWN00001').status == 'completed' and #W2.invDb.ledger == 1)
    check('DELIVERY wrong character / unknown demand / bad inputs', select(2, deliver(W2, 'DEL-BAD0000001', 'MD-NOTEXIST', 1, 1)) == 'demand_not_found' and select(2, deliver(W2, 'x', d2.reference, 1, 1)) == 'invalid_reference'
        and select(2, deliver(W2, 'DEL-BAD0000002', d2.reference, 'abc', 1)) == 'invalid_character' and select(2, deliver(W2, 'DEL-BAD0000003', d2.reference, 1, 0)) == 'invalid_quantity')
    check('DELIVERY only allowlisted physical providers may call it', (function() W2.as('cm-evil'); local r = select(2, W2.M.Deliver('DEL-EVIL00001', d2.reference, '1', 1, {})); W2.as('cm-commercial-ownership'); return r == 'forbidden' end)())
    check('DELIVERY destination unavailable (business gone) is refused before any debit', (function()
        local W3 = newWorld(); local _, dd = demand(W3, 10); giveTimber(W3, 1, 10)
        W3.C.TestMaterials = { IsMaterial = function() return nil end, GetMaterial = function() return nil end }
        local ok5, why5 = deliver(W3, 'DEL-NOCAT0001', dd.reference, 1, 10)
        return ok5 == false and why5 == 'unavailable' and timber(W3, 1) == 10 and #W3.invDb.ledger == 0 end)())
    check('DELIVERY partial deliveries on a non-contract demand: 4 then 6 fulfil it', (function()
        local W3 = newWorld(); local _, dd = demand(W3, 10); giveTimber(W3, 1, 4); giveTimber(W3, 2, 6)
        local a = deliver(W3, 'DEL-PART00001', dd.reference, 1, 4)
        local midStatus, midF = W3.bizDb.demandBy(dd.reference).status, W3.bizDb.demandBy(dd.reference).quantity_fulfilled
        local b = deliver(W3, 'DEL-PART00002', dd.reference, 2, 6)
        local fin = W3.bizDb.demandBy(dd.reference)
        return a == true and midStatus == 'partially_fulfilled' and midF == 4 and b == true and fin.status == 'fulfilled' and W3.bizDb.qty('store', '1', 'timber') == 10 end)())
    check('DELIVERY over-delivery beyond the remaining quantity is refused', (function()
        local W3 = newWorld(); local _, dd = demand(W3, 10); giveTimber(W3, 1, 20)
        local a, why = deliver(W3, 'DEL-OVER00001', dd.reference, 1, 11)
        return a == false and why == 'over_remaining' and timber(W3, 1) == 20 end)())
    check('DELIVERY real inventory sink only consumes metadata-free stacks (items with metadata are not delivered)', (function()
        local W3 = newWorld(); local _, dd = demand(W3, 5); W3.invDb.clear(1); W3.invDb.give(1, 'pocket-1', 'timber', 5, { purity = 'high' })
        local a, why = deliver(W3, 'DEL-META00001', dd.reference, 1, 5)
        return a == false and why == 'insufficient_input' end)())
end

-- =================================================================== CRASH RECOVERY (a "restart" reloads the real module against the same databases)
do
    local function restart(W) local n = newWorld({ invDb = W.invDb, bizDb = W.bizDb, businesses = W.businesses }); n.now = W.now; return n end
    -- 1. crash BEFORE the inventory debit
    do
        local W = newWorld(); local _, d = demand(W, 10); giveTimber(W, 1, 10)
        W.hook = { before_debit = function() error('CRASH before debit') end }
        local ok = pcall(function() return deliver(W, 'DEL-CRASH0001', d.reference, 1, 10) end)
        local snapState = W.bizDb.deliveryBy('DEL-CRASH0001')
        check('CRASH before debit: delivery is prepared, the player still has the items', snapState and snapState.status == 'prepared' and timber(W, 1) == 10 and #W.invDb.ledger == 0)
        local R = restart(W); R.as('cm-admin'); R.now = R.now + 10
        local st = select(2, R.M.AdminReconcile())
        check('CRASH before debit: after restart the SAME reference is retried and settles exactly once', R.bizDb.deliveryBy('DEL-CRASH0001').status == 'completed' and timber(R, 1) == 0 and R.bizDb.qty('store', '1', 'timber') == 10 and #R.invDb.ledger == 1 and st.retried == 1)
        local W2 = newWorld(); local _, d2 = demand(W2, 10); giveTimber(W2, 1, 10)
        W2.hook = { before_debit = function() error('CRASH before debit') end }
        pcall(function() return deliver(W2, 'DEL-CRASH0002', d2.reference, 1, 10) end)
        local R2 = restart(W2); R2.as('cm-admin'); R2.now = R2.now + 300
        R2.invW.invoker = 'cm-commercial-ownership'
        local st2 = select(2, R2.M.AdminReconcile())
        check('CRASH before debit, never retried: past the timeout it is CANCELLED (inventory definitively not applied), reservation released, items untouched',
            R2.bizDb.deliveryBy('DEL-CRASH0002').status == 'cancelled' and R2.bizDb.demandBy(d2.reference).quantity_reserved == 0 and timber(R2, 1) == 10 and R2.bizDb.qty('store', '1', 'timber') == 0)
    end
    -- 2. crash AFTER the inventory debit (response lost), before business credit
    do
        local W = newWorld(); local _, d = demand(W, 10); giveTimber(W, 1, 10)
        W.hook = { after_debit = function() error('CRASH after debit') end }
        pcall(function() return deliver(W, 'DEL-CRASH0003', d.reference, 1, 10) end)
        check('CRASH after debit: items are gone, business has not been credited, delivery is still prepared', timber(W, 1) == 0 and W.bizDb.qty('store', '1', 'timber') == 0 and W.bizDb.deliveryBy('DEL-CRASH0003').status == 'prepared')
        local R = restart(W); R.as('cm-admin'); R.now = R.now + 10
        R.M.AdminReconcile()
        check('CRASH after debit: recovery credits the business ONLY (no second debit, no refund)', R.bizDb.deliveryBy('DEL-CRASH0003').status == 'completed' and R.bizDb.qty('store', '1', 'timber') == 10 and #R.invDb.ledger == 1 and R.bizDb.demandBy(d.reference).status == 'fulfilled')
        local snap = R.bizDb.fingerprint(); local isnap = R.invDb.fingerprint()
        R.M.AdminReconcile(); R.as('cm-trucking')
        check('CRASH completed delivery: a further reconcile and a replay change nothing on either side', R.bizDb.fingerprint() == snap and R.invDb.fingerprint() == isnap and select(2, R.M.Deliver('DEL-CRASH0003', d.reference, '1', 10, {})).replayed == true and R.bizDb.fingerprint() == snap)
    end
    -- 3. crash BEFORE the business credit (inventory_committed), credit transaction fails
    do
        local W = newWorld(); local _, d = demand(W, 10); giveTimber(W, 1, 10)
        W.bizDb.failOn = function(name) return name == 'stockSet' end   -- finalization transaction cannot run
        local ok, why = deliver(W, 'DEL-CRASH0004', d.reference, 1, 10)
        W.bizDb.failOn = nil
        check('CRASH before business credit: debit is committed, delivery marked inventory_committed, balance untouched (the whole credit txn rolled back)',
            ok == false and W.bizDb.deliveryBy('DEL-CRASH0004').status == 'inventory_committed' and W.bizDb.qty('store', '1', 'timber') == 0 and timber(W, 1) == 0 and W.bizDb.demandBy(d.reference).quantity_reserved == 10)
        W.as('cm-admin'); W.now = W.now + 10; W.M.AdminReconcile()
        check('CRASH before business credit: reconciliation retries the credit only; completed once', W.bizDb.deliveryBy('DEL-CRASH0004').status == 'completed' and W.bizDb.qty('store', '1', 'timber') == 10 and #W.invDb.ledger == 1 and W.bizDb.eventsOf('delivery') == 1)
    end
    -- 4. crash before the status update: the LAST statement of the finalization fails -> credit is rolled back with it (atomic), never half-applied
    do
        local W = newWorld(); local _, d = demand(W, 10); giveTimber(W, 1, 10)
        W.bizDb.failOn = function(name) return name == 'deliveryComplete' end
        deliver(W, 'DEL-CRASH0005', d.reference, 1, 10)
        W.bizDb.failOn = nil
        check('CRASH before settlement finalization: credit + demand + status are one transaction - none of them applied', W.bizDb.qty('store', '1', 'timber') == 0 and W.bizDb.demandBy(d.reference).quantity_fulfilled == 0 and W.bizDb.deliveryBy('DEL-CRASH0005').status == 'inventory_committed')
        W.as('cm-admin'); W.now = W.now + 10; W.M.AdminReconcile()
        check('CRASH before settlement finalization: recovery completes it exactly once', W.bizDb.qty('store', '1', 'timber') == 10 and W.bizDb.deliveryBy('DEL-CRASH0005').status == 'completed')
    end
    -- 5. business credit already journaled but the status update was lost (defensive reconstruction)
    do
        local W = newWorld(); local _, d = demand(W, 10); giveTimber(W, 1, 10)
        W.bizDb.failOn = function(name) return name == 'stockSet' end
        deliver(W, 'DEL-CRASH0006', d.reference, 1, 10); W.bizDb.failOn = nil
        -- simulate an older partial state: the credit event + balance exist, the delivery/demand rows were never advanced
        W.bizDb.stock[#W.bizDb.stock + 1] = { business_type = 'store', business_id = '1', material_id = 'timber', quantity = 10 }
        W.bizDb.events[#W.bizDb.events + 1] = { id = 99, reference = 'DEL-CRASH0006', business_type = 'store', business_id = '1', material_id = 'timber', delta = 10, resulting_quantity = 10, event_type = 'delivery', journal_key = 'delivery:DEL-CRASH0006' }
        W.as('cm-admin'); W.now = W.now + 10; W.M.AdminReconcile()
        check('CRASH credit journaled but status lost: completed state is reconstructed WITHOUT crediting again', W.bizDb.qty('store', '1', 'timber') == 10 and W.bizDb.deliveryBy('DEL-CRASH0006').status == 'completed' and W.bizDb.demandBy(d.reference).status == 'fulfilled' and W.bizDb.eventsOf('delivery') == 1)
    end
end

-- =================================================================== CONCURRENCY
do
    local W = newWorld(); local _, d = demand(W, 10); giveTimber(W, 1, 10); giveTimber(W, 2, 10)
    W.bizDb.interleave = true; W.invDb.interleave = true
    local r = {}
    Sched.spawn(function() r[1] = { deliver(W, 'DEL-RACE00001', d.reference, 1, 8) } end)
    Sched.spawn(function() r[2] = { deliver(W, 'DEL-RACE00002', d.reference, 2, 8) } end)
    Sched.run()
    W.bizDb.interleave = false; W.invDb.interleave = false
    local wins = (r[1][1] == true and 1 or 0) + (r[2][1] == true and 1 or 0)
    local d1 = W.bizDb.demandBy(d.reference)
    check('CONCURRENCY two deliveries of 8 against a demand of 10: exactly one is accepted (no overfill)', wins == 1 and W.bizDb.qty('store', '1', 'timber') == 8 and d1.quantity_fulfilled == 8 and d1.quantity_reserved == 0)
    check('CONCURRENCY the loser keeps its items (over_remaining before any debit)', (r[1][1] and r[2][2] == 'over_remaining' and timber(W, 2) == 10) or (r[2][1] and r[1][2] == 'over_remaining' and timber(W, 1) == 10))
    check('CONCURRENCY exactly one inventory debit and one business credit', #W.invDb.ledger == 1 and W.bizDb.eventsOf('delivery') == 1)

    local W2 = newWorld(); local _, d2 = demand(W2, 10); giveTimber(W2, 1, 10)
    W2.bizDb.interleave = true; W2.invDb.interleave = true
    local rr = {}
    for i = 1, 4 do Sched.spawn(function() rr[i] = { deliver(W2, 'DEL-DUP0000001', d2.reference, 1, 10) } end) end
    Sched.run()
    W2.bizDb.interleave = false; W2.invDb.interleave = false
    local applied, replays = 0, 0
    for _, x in ipairs(rr) do if x[1] == true then if x[2].replayed then replays = replays + 1 else applied = applied + 1 end end end
    check('CONCURRENCY four simultaneous calls with the SAME reference: debited once, credited once', applied == 1 and replays == 3 and #W2.invDb.ledger == 1 and W2.bizDb.qty('store', '1', 'timber') == 10 and W2.bizDb.eventsOf('delivery') == 1)

    -- cancellation racing a delivery
    local W3 = newWorld(); local _, d3 = demand(W3, 10); giveTimber(W3, 1, 10)
    W3.bizDb.interleave = true; W3.invDb.interleave = true
    local cr, dr = nil, nil
    Sched.spawn(function() dr = { deliver(W3, 'DEL-CANC000001', d3.reference, 1, 10) } end)
    Sched.spawn(function() W3.as('cm-commercial-ownership'); cr = { W3.M.CancelDemand(d3.reference, 'staff') } end)
    Sched.run()
    W3.bizDb.interleave = false; W3.invDb.interleave = false
    local st = W3.bizDb.demandBy(d3.reference).status
    check('CONCURRENCY cancel vs delivery: either the delivery fully settles and cancel is refused, or the cancel wins and nothing is debited - never both', (st == 'fulfilled' and dr[1] == true and cr[1] == false and timber(W3, 1) == 0 and W3.bizDb.qty('store', '1', 'timber') == 10)
        or (st == 'cancelled' and dr[1] == false and timber(W3, 1) == 10 and W3.bizDb.qty('store', '1', 'timber') == 0))
    -- cancel while a delivery is in irreversible settlement
    local W4 = newWorld(); local _, d4 = demand(W4, 10); giveTimber(W4, 1, 10)
    W4.bizDb.failOn = function(name) return name == 'stockSet' end
    deliver(W4, 'DEL-CANC000002', d4.reference, 1, 10); W4.bizDb.failOn = nil
    W4.as('cm-commercial-ownership')
    check('CONCURRENCY cancel is BLOCKED while the player debit is committed but the credit is pending', select(2, W4.M.CancelDemand(d4.reference, 'staff')) == 'delivery_in_progress' and W4.bizDb.demandBy(d4.reference).status ~= 'cancelled')
    -- business consume races
    local W5 = newWorld(); W5.as('cm-commercial-ownership'); W5.M.Credit('CRD-RACE00001', 'mechanic', '7', 'reclaimed_metal', 5, {})
    W5.bizDb.interleave = true
    local cc = {}
    for i = 1, 2 do Sched.spawn(function() W5.as('cm-commercial-ownership'); cc[i] = { W5.M.Consume('CNS-RACE0000' .. i, 'mechanic', '7', { { material = 'reclaimed_metal', quantity = 4 } }, {}) } end) end
    Sched.run(); W5.bizDb.interleave = false
    check('CONCURRENCY two consumes of 4 from a balance of 5: exactly one succeeds, never negative', ((cc[1][1] == true) ~= (cc[2][1] == true)) and W5.bizDb.qty('mechanic', '7', 'reclaimed_metal') == 1)
end

-- =================================================================== CONTRACTS (bulk_material_transport; broker only routes work)
do
    local W = newWorld()
    local _, d = demand(W, 10, { publish = true })
    check('CONTRACT a published demand creates exactly one broker contract and becomes published', #W.contracts.created == 1 and W.bizDb.demandBy(d.reference).status == 'published' and W.bizDb.demandBy(d.reference).contract_ref == 'CT-0001'
        and W.contracts.created[1].data.contractType == 'bulk_material_transport' and W.contracts.created[1].data.sourceReference == d.reference)
    check('CONTRACT the work-facing metadata carries no balance, price or business identity beyond the type', (function() local m = W.contracts.created[1].data.metadata; return m.kind == 'material_supply' and m.material == 'timber' and m.quantity == 10 and m.businessId == nil and m.price == nil end)())
    W.as('cm-admin'); W.M.AdminReconcile()
    check('CONTRACT reconciliation does not publish it again', #W.contracts.created == 1)
    check('CONTRACT publishing creates 0 stock and 0 items', W.bizDb.qty('store', '1', 'timber') == 0 and #W.invDb.ledger == 0)
    W.as('cm-contracts')
    local ctx = { reference = 'CT-0001', sourceReference = d.reference, contractType = 'bulk_material_transport', workerCharacterId = '1', mode = 'player' }
    check('CONTRACT completion BEFORE settlement is refused (a claim/completion never creates stock)', select(2, W.M.ContractComplete(ctx)) == 'delivery_not_settled' and W.bizDb.qty('store', '1', 'timber') == 0)
    giveTimber(W, 1, 10)
    check('CONTRACT a contract-routed demand requires the matching contract reference', select(2, deliver(W, 'DEL-CT00000001', d.reference, 1, 10)) == 'contract_mismatch' and select(2, deliver(W, 'DEL-CT00000002', d.reference, 1, 10, { contractReference = 'CT-9999' })) == 'contract_mismatch')
    check('CONTRACT a contract-routed demand is whole-delivery only', select(2, deliver(W, 'DEL-CT00000003', d.reference, 1, 4, { contractReference = 'CT-0001' })) == 'whole_delivery_required' and timber(W, 1) == 10)
    local ok = deliver(W, 'DEL-CT00000004', d.reference, 1, 10, { contractReference = 'CT-0001' })
    check('CONTRACT the provider delivery settles through the business platform (not through the broker)', ok == true and W.bizDb.qty('store', '1', 'timber') == 10 and timber(W, 1) == 0)
    W.as('cm-trucking'); local forbidden = select(2, W.M.ContractComplete(ctx)); W.as('cm-contracts')
    check('CONTRACT broker callbacks are broker-only', forbidden == 'forbidden')
    local snap = W.bizDb.fingerprint()
    check('CONTRACT completion after settlement succeeds and changes nothing (no stock, no items, no money)', W.M.ContractComplete(ctx) == true and W.bizDb.fingerprint() == snap)
    check('CONTRACT completion by a different worker than the one who delivered is refused', select(2, W.M.ContractComplete({ reference = 'CT-0001', sourceReference = d.reference, contractType = 'bulk_material_transport', workerCharacterId = '2' })) == 'delivery_worker_mismatch')
    check('CONTRACT a contract that does not belong to the demand is rejected', select(2, W.M.ContractComplete({ reference = 'CT-7777', sourceReference = d.reference, contractType = 'bulk_material_transport', workerCharacterId = '1' })) == 'forbidden')
    -- fallback: nobody delivers
    local W2 = newWorld(); local _, d2 = demand(W2, 10, { publish = true })
    W2.as('cm-contracts')
    local fb, fres = W2.M.ContractFallback({ reference = 'CT-0001', sourceReference = d2.reference, contractType = 'bulk_material_transport', attempt = 1 })
    check('CONTRACT fallback EXPIRES the demand and creates NO stock (no free material generation, no worker)', fb == true and W2.bizDb.demandBy(d2.reference).status == 'expired' and W2.bizDb.qty('store', '1', 'timber') == 0 and #W2.invDb.ledger == 0 and #W2.bizDb.events == 0)
    check('CONTRACT a second fallback reports source_terminal', select(2, W2.M.ContractFallback({ reference = 'CT-0001', sourceReference = d2.reference, contractType = 'bulk_material_transport', attempt = 2 })) == 'source_terminal')
    -- fallback while a delivery is in flight
    local W3 = newWorld(); local _, d3 = demand(W3, 10, { publish = true }); giveTimber(W3, 1, 10)
    W3.bizDb.failOn = function(name) return name == 'stockSet' end
    deliver(W3, 'DEL-FB00000001', d3.reference, 1, 10, { contractReference = 'CT-0001' }); W3.bizDb.failOn = nil
    W3.as('cm-contracts')
    check('CONTRACT fallback while a delivery is settling is deferred (busy), never discarding the credit', select(2, W3.M.ContractFallback({ reference = 'CT-0001', sourceReference = d3.reference, contractType = 'bulk_material_transport', attempt = 1 })) == 'busy')
    -- cancel
    local W4 = newWorld(); local _, d4 = demand(W4, 10, { publish = true }); W4.as('cm-contracts')
    check('CONTRACT broker admin cancel cancels the demand', W4.M.ContractCancel({ reference = 'CT-0001', sourceReference = d4.reference, contractType = 'bulk_material_transport' }) == true and W4.bizDb.demandBy(d4.reference).status == 'cancelled')
    W4.as('cm-commercial-ownership')
    local _, d5 = demand(W4, 10, { publish = true }); W4.M.CancelDemand(d5.reference, 'staff')
    check('CONTRACT cancelling a demand tells the broker (best effort)', #W4.contracts.cancelled >= 1)
    -- broker down at publish time
    local W5 = newWorld(); W5.C.TestBroker = nil
    local _, d6 = demand(W5, 10, { publish = true })
    check('CONTRACT broker down: the demand stays open and publishable (publish_requested)', W5.bizDb.demandBy(d6.reference).status == 'open' and W5.bizDb.demandBy(d6.reference).contract_ref == nil)
    W5.C.TestBroker = { CreateContract = function() return true, { reference = 'CT-0042', existing = false } end, CancelContract = function() return true end }
    W5.as('cm-admin'); local st = select(2, W5.M.AdminReconcile())
    check('CONTRACT reconciliation publishes it later exactly once', st.published == 1 and W5.bizDb.demandBy(d6.reference).contract_ref == 'CT-0042')
    -- type/source wiring
    local f = assert(io.open(coRoot .. '/cm-contracts/config.lua', 'rb')); local cfgSrc = f:read('a'); f:close()
    check('CONTRACT cm-contracts allows cm-commercial-ownership to publish bulk_material_transport', cfgSrc:find('bulk_material_transport = true', 1, true) ~= nil)
end

-- =================================================================== OWNERSHIP CHANGE / ADMIN / BOUNDARIES
do
    local W = newWorld(); W.as('cm-commercial-ownership')
    W.M.Credit('CRD-OWN00001', 'store', '1', 'timber', 30, {})
    local _, d = demand(W, 10)
    W.C.MaterialsOwnerChanged({ type = 'store', id = '1' })
    check('OWNER change zeroes the material balance (journaled) like the forfeited business balance', W.bizDb.qty('store', '1', 'timber') == 0 and W.bizDb.eventsOf('ownership_reset') == 1)
    check('OWNER change cancels open demands that have nothing in flight', W.bizDb.demandBy(d.reference).status == 'cancelled' and W.bizDb.demandBy(d.reference).end_reason == 'ownership_change')
    W.as('cm-admin')
    local okL, list = W.M.AdminListDemands()
    local okI, view = W.M.AdminInspectDemand(d.reference)
    local okD, dl = W.M.AdminListDeliveries()
    local okB, bm = W.M.AdminBusinessMaterials('store', '1')
    check('ADMIN list/inspect/deliveries/business materials work for cm-admin', okL and #list >= 1 and okI and view.reference == d.reference and okD and okB and #bm.events >= 1)
    W.as('cm-evil')
    check('ADMIN every admin export refuses other callers', select(2, W.M.AdminListDemands()) == 'forbidden' and select(2, W.M.AdminInspectDemand(d.reference)) == 'forbidden' and select(2, W.M.AdminReconcile()) == 'forbidden' and select(2, W.M.AdminCancelDemand(d.reference)) == 'forbidden')
end

do   -- static boundaries
    local function read(p) local f = io.open(p, 'rb'); if not f then return '' end local s = f:read('a'); f:close(); return s end
    local mats = read(coRoot .. '/cm-materials/server/main.lua')
    check('BOUNDARY cm-materials stays read-only: no database, no inventory, no net events', not mats:find('MySQL', 1, true) and not mats:find('RegisterNetEvent', 1, true) and not mats:find('AddItem', 1, true) and not mats:find('RemoveItem', 1, true))
    local names = {}
    for n in mats:gmatch("exports%('([%w_]+)'") do names[#names + 1] = n end
    local mutating = false
    for _, n in ipairs(names) do if n:find('^Set') or n:find('^Add') or n:find('^Credit') or n:find('^Consume') or n:find('^Register') or n:find('^Create') or n:find('^Deliver') then mutating = true end end
    check('BOUNDARY cm-materials exports only read/query functions', #names >= 8 and not mutating)
    local contracts = read(coRoot .. '/cm-contracts/server/core.lua') .. read(coRoot .. '/cm-contracts/server/store.lua')
    check('BOUNDARY cm-contracts holds no business stock, inventory or demand logic', not contracts:find('cm_business_material', 1, true) and not contracts:find('ExecuteItemSink', 1, true))
    local mat = read(here .. '/server/materials.lua')
    check('BOUNDARY the business platform never writes player inventory rows or money columns itself', not mat:find('inventory_items', 1, true) and not mat:find('business_balance', 1, true) and not mat:find('RemoveItem', 1, true) and not mat:find('AddItem', 1, true))
    check('BOUNDARY no client-reachable event or command in the material platform', not mat:find('RegisterNetEvent', 1, true) and not mat:find('RegisterCommand', 1, true) and not mat:find('lib.callback', 1, true))
    local cfg = read(here .. '/config.lua')
    check('BOUNDARY no new permission ids were added (no UI yet)', not cfg:find("business.materials", 1, true))
    check('ECONOMY no money, XP or reward appears anywhere in the material platform', not mat:find('payday', 1, true) and not mat:find('AddMoney', 1, true) and not mat:find('CreditBusinessAtomic', 1, true))
end

print(('\ncm-commercial-ownership materials self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
