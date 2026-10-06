-- Deterministic self-test for the two-character atomic item exchange (server/exchange.lua).
--   lua tests/exchange_selftest.lua        (run from resources/[core]/cm-inventory)
-- REAL: the production inventory chunk (db/items/slots/bags/equipment/external/craft/exchange), the REAL cm-items trade policy (CanTradeItem over the real
--       definitions) unless a fixture sets ITEMS[name].tradeable. DOUBLES (labelled): FiveM runtime, cm-items export surface, the SQL layer (in-memory,
--       transactional undo, UNIQUE keys incl. the (owner,slot) key, SELECT ... FOR UPDATE row locks between cooperative threads, failure injection).
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local H = dofile(here .. '/tests/craft_harness.lua')(here)
local json, deepcopy, Sched, newDb, newWorld, ITEMS = H.json, H.deepcopy, H.Sched, H.newDb, H.newWorld, H.ITEMS
local passed, failed = 0, 0
-- items + audit only: a failed exchange may legitimately leave a TERMINAL ledger row (not_applied) but must never move an item
local function fp(db) return H.ser({ db.inventory_items, #db.audit }) end
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

-- fixtures (weights are the real cm-items values for the real items)
ITEMS.water = { weight = 500 }; ITEMS.sandwich = { weight = 350 }; ITEMS.bandage = { weight = 100 }; ITEMS.medkit = { weight = 600 }
ITEMS.rare_gem = { weight = 100, stack = false, unique = true, tradeable = true }
ITEMS.locked_token = { weight = 10, tradeable = false }
ITEMS.heavy_box = { weight = 14000, tradeable = true }
ITEMS.id_card = { weight = 30, stack = false, unique = true }
ITEMS.vehicle_key = { weight = 10, stack = false, unique = true }
ITEMS.admin_wand = { weight = 1 }
ITEMS.clothing_hat = { weight = 100, stack = false, unique = true }

local function world()
    local db = newDb(); for c = 1, 4 do db.addChar(c) end
    local W = newWorld(db)
    W.invoker = 'cm-trade'
    W.clock = os.time()
    W.env.os = setmetatable({ time = function() return W.clock end }, { __index = os })   -- controllable clock for lease expiry
    return W, db
end
local function snap(W, cid) W.invoker = 'cm-trade'; return W.registry.GetTradeSnapshot(cid) end
local function rowOf(W, cid, item, nth)
    local n = 0
    for _, r in ipairs(snap(W, cid)) do if r.item == item then n = n + 1; if n == (nth or 1) then return r end end end
end
local function line(r, qty) return { ref = r.ref, quantity = qty or r.quantity, fp = r.fp } end
local function exec(W, ref, a, b) W.invoker = 'cm-trade'; return W.registry.ExecuteItemExchange(ref, a, b) end
local function val(W, ref, a, b) W.invoker = 'cm-trade'; return W.registry.ValidateItemExchange(ref, a, b) end
local function status(W, ref) W.invoker = 'cm-trade'; return W.registry.GetItemExchangeStatus(ref) end
local function side(cid, lines) return { characterId = cid, lines = lines or {} } end
local function R(n) return ('TRD-TEST%04d'):format(n) end
local function total(db, item) local n = 0 for _, r in ipairs(db.inventory_items) do if r.item_name == item then n = n + r.quantity end end return n end
local function inv(db, cid, rows) db.clear(cid) for _, r in ipairs(rows) do db.give(cid, r[1], r[2], r[3], r[4]) end end

-- =================================================================== TRUST
do
    local W, db = world()
    inv(db, 1, { { 'pocket-1', 'water', 5 } }); inv(db, 2, { { 'pocket-1', 'sandwich', 3 } })
    local a, b = rowOf(W, 1, 'water'), rowOf(W, 2, 'sandwich')
    check('TRUST cm-trade accepted', exec(W, R(1), side(1, { line(a, 2) }), side(2, { line(b, 1) })) == true)
    for _, who in ipairs({ 'cm-crafting', 'cm-commercial-ownership', 'cm-evil' }) do
        W.invoker = who
        local ok1, w1 = W.registry.ExecuteItemExchange(R(2), side(1, { line(a, 1) }), side(2, {}))
        check('TRUST ' .. who .. ' cannot execute / validate / snapshot / read status', ok1 == false and w1 == 'forbidden' and select(2, W.registry.ValidateItemExchange(R(2), side(1, { line(a, 1) }), side(2, {}))) == 'forbidden'
            and select(2, W.registry.GetTradeSnapshot(1)) == 'forbidden' and select(2, W.registry.GetItemExchangeStatus(R(1))) == 'forbidden')
    end
    W.invoker = nil
    check('TRUST nil invoker fails closed', select(2, W.registry.ExecuteItemExchange(R(3), side(1, { line(a, 1) }), side(2, {}))) == 'forbidden')
    W.invoker = 'cm-trade'
    local netCraft = false
    for _, n in ipairs(W.netEvents) do if n:lower():find('exchange') or n:lower():find('trade') then netCraft = true end end
    check('TRUST no client/net event exists for the exchange', netCraft == false)
    check('TRUST the sink and craft APIs stay closed to cm-trade', (function() W.invoker = 'cm-trade'; return select(2, W.registry.ExecuteItemSinkTransaction('SINK-TRD00001', '1', { { item = 'water', amount = 1 } })) == 'forbidden' and select(2, W.registry.ExecuteCraftTransaction('CRAFT-TRD00001', '1', { inputs = { { item = 'water', amount = 1 } } })) == 'forbidden' end)())
end

-- =================================================================== ELIGIBILITY (real cm-items policy)
do
    local W, db = world()
    inv(db, 1, { { 'pocket-1', 'water', 5 }, { 'pocket-2', 'weapon_pistol', 1, { serial = 'WPN-123456', durability = 90 } }, { 'pocket-3', 'id_card', 1, { characterId = 1 } }, { 'pocket-4', 'vehicle_key', 1 },
        { 'pocket-5', 'locked_token', 1 }, { 'pocket-6', 'admin_wand', 1 } })
    local s = snap(W, 1)
    local by = {} for _, r in ipairs(s) do by[r.item] = r end
    check('ELIGIBILITY snapshot marks tradeable water true and everything sensitive false', by.water.tradeable == true and by.weapon_pistol.tradeable == false and by.id_card.tradeable == false and by.vehicle_key.tradeable == false and by.locked_token.tradeable == false and by.admin_wand.tradeable == false)
    inv(db, 2, { { 'pocket-1', 'sandwich', 1 } })
    local sw = rowOf(W, 2, 'sandwich')
    for k, it in ipairs({ 'weapon_pistol', 'id_card', 'vehicle_key', 'locked_token', 'admin_wand' }) do
        local before = fp(db)
        local ok, why = exec(W, R(200 + k), side(1, { line(by[it]) }), side(2, { line(sw) }))
        check('ELIGIBILITY ' .. it .. ' cannot be exchanged', ok == false and why == 'not_tradeable' and fp(db) == before)
    end
    inv(db, 1, { { 'pocket-1', 'water', 5, { bound = true } } })
    local bound = rowOf(W, 1, 'water')
    check('ELIGIBILITY a bound/non-transferable instance is blocked even for a tradeable item', select(2, exec(W, R(11), side(1, { line(bound, 1) }), side(2, {}))) == 'not_tradeable' and bound.tradeable == false)
    inv(db, 1, { { 'shirt', 'water', 1 } })
    check('ELIGIBILITY an item in an equipment slot is never offered or exchanged', rowOf(W, 1, 'water') == nil and select(2, exec(W, R(12), side(1, { { ref = tostring(db.rowsOf(1)[1].id), quantity = 1 } }), side(2, {}))) == 'not_tradeable')
    W.itemsDown = true
    inv(db, 1, { { 'pocket-1', 'water', 2 } })
    local w2 = rowOf(W, 1, 'water')
    W.itemsDown = false
    w2 = rowOf(W, 1, 'water')
    W.itemsDown = true
    check('ELIGIBILITY cm-items unavailable fails closed (unavailable)', select(2, exec(W, R(13), side(1, { line(w2, 1) }), side(2, {}))) == 'unavailable')
    W.itemsDown = false
    check('ELIGIBILITY an item the policy has never heard of is blocked', (function() ITEMS.mystery = { weight = 1 }; inv(db, 1, { { 'pocket-1', 'mystery', 1 } }); local r = rowOf(W, 1, 'mystery'); return r.tradeable == false and select(2, exec(W, R(14), side(1, { line(r) }), side(2, {}))) == 'not_tradeable' end)())
end

-- =================================================================== EXCHANGE
do
    local W, db = world()
    inv(db, 1, { { 'pocket-1', 'water', 10 } }); inv(db, 2, {})
    local a = rowOf(W, 1, 'water')
    local ok, res = exec(W, R(20), side(1, { line(a, 4) }), side(2, {}))
    check('EXCHANGE A gives a partial stack to B (one way)', ok == true and res.replayed == false and db.count(1, 'water') == 6 and db.count(2, 'water') == 4)
    inv(db, 1, {}); inv(db, 2, { { 'pocket-1', 'sandwich', 3 } })
    local b = rowOf(W, 2, 'sandwich')
    ok = exec(W, R(21), side(1, {}), side(2, { line(b) }))
    check('EXCHANGE B gives a whole stack to A (the same row id moved)', ok == true and db.count(1, 'sandwich') == 3 and db.count(2, 'sandwich') == 0 and tostring(db.rowsOf(1)[1].id) == b.ref)
    inv(db, 1, { { 'pocket-1', 'water', 5 }, { 'pocket-2', 'bandage', 2 } }); inv(db, 2, { { 'pocket-1', 'sandwich', 3 }, { 'pocket-2', 'medkit', 1 } })
    local before = { water = total(db, 'water'), sandwich = total(db, 'sandwich'), bandage = total(db, 'bandage'), medkit = total(db, 'medkit') }
    ok = exec(W, R(22), side(1, { line(rowOf(W, 1, 'water'), 5), line(rowOf(W, 1, 'bandage'), 1) }), side(2, { line(rowOf(W, 2, 'sandwich'), 2), line(rowOf(W, 2, 'medkit')) }))
    check('EXCHANGE two-way swap with multiple lines and partial stacks', ok == true and db.count(1, 'water') == 0 and db.count(2, 'water') == 5 and db.count(1, 'bandage') == 1 and db.count(2, 'bandage') == 1
        and db.count(1, 'sandwich') == 2 and db.count(2, 'sandwich') == 1 and db.count(1, 'medkit') == 1 and db.count(2, 'medkit') == 0)
    check('EXCHANGE conservation: nothing minted, nothing lost', total(db, 'water') == before.water and total(db, 'sandwich') == before.sandwich and total(db, 'bandage') == before.bandage and total(db, 'medkit') == before.medkit)
    check('EXCHANGE audit rows record both directions with the reference', (function() local o, i = 0, 0 for _, e in ipairs(db.audit) do if e.reason == R(22) then if e.action == 'trade_out' then o = o + 1 elseif e.action == 'trade_in' then i = i + 1 end end end return o == 4 and i == 4 end)())

    -- stack merge
    inv(db, 1, { { 'pocket-1', 'water', 5 } }); inv(db, 2, { { 'pocket-1', 'water', 7 } })
    ok = exec(W, R(23), side(1, { line(rowOf(W, 1, 'water'), 3) }), side(2, {}))
    local rows2 = db.rowsOf(2)
    check('EXCHANGE a compatible stack merges into the receiver (no duplicate row)', ok == true and #rows2 == 1 and rows2[1].quantity == 10 and db.count(1, 'water') == 2)
    -- incompatible metadata: separate stack, metadata preserved exactly
    inv(db, 1, { { 'pocket-1', 'water', 5, { batch = 'A7' } } }); inv(db, 2, { { 'pocket-1', 'water', 2 } })
    ok = exec(W, R(24), side(1, { line(rowOf(W, 1, 'water'), 5) }), side(2, {}))
    local plain, tagged
    for _, r in ipairs(db.rowsOf(2)) do if r.metadata and r.metadata:find('A7') then tagged = r else plain = r end end
    check('EXCHANGE a metadata-incompatible stack is NOT merged and keeps its exact metadata', ok == true and plain and plain.quantity == 2 and tagged and tagged.quantity == 5 and json.decode(tagged.metadata).batch == 'A7')
    inv(db, 1, { { 'pocket-1', 'water', 5, { batch = 'A7' } } }); inv(db, 2, { { 'pocket-1', 'water', 4, { batch = 'A7' } } })
    ok = exec(W, R(25), side(1, { line(rowOf(W, 1, 'water'), 2) }), side(2, {}))
    check('EXCHANGE a partial piece with identical metadata merges and the source row keeps the rest', ok == true and db.count(2, 'water') == 6 and db.count(1, 'water') == 3 and #db.rowsOf(2) == 1)
    -- unique item: identity preserved
    inv(db, 1, { { 'pocket-1', 'rare_gem', 1, { serial = 'GEM-0042', durability = 73, label = 'Blue Gem' } } }); inv(db, 2, { { 'pocket-1', 'water', 2 } })
    local gem = rowOf(W, 1, 'rare_gem')
    local rowId = db.rowsOf(1)[1].id; local rawMeta = db.rowsOf(1)[1].metadata
    ok = exec(W, R(26), side(1, { line(gem) }), side(2, { line(rowOf(W, 2, 'water'), 2) }))
    local moved
    for _, r in ipairs(db.rowsOf(2)) do if r.item_name == 'rare_gem' then moved = r end end
    check('EXCHANGE a unique item moves with the SAME row id, serial, durability and label (never recreated)', ok == true and moved and moved.id == rowId and moved.metadata == rawMeta and db.count(1, 'rare_gem') == 0 and db.count(1, 'water') == 2)
    inv(db, 1, { { 'pocket-1', 'rare_gem', 2, { serial = 'GEM-1' } } })
    check('EXCHANGE a partial quantity of a non-stackable row is refused', select(2, exec(W, R(27), side(1, { { ref = tostring(db.rowsOf(1)[1].id), quantity = 1 } }), side(2, {}))) == 'invalid_quantity')
    inv(db, 1, { { 'pocket-1', 'rare_gem', 1, { serial = 'S1' } } }); inv(db, 2, { { 'pocket-1', 'rare_gem', 1, { serial = 'S2' } } })
    ok = exec(W, R(28), side(1, { line(rowOf(W, 1, 'rare_gem')) }), side(2, { line(rowOf(W, 2, 'rare_gem')) }))
    local s1 = json.decode(db.rowsOf(1)[1].metadata).serial; local s2 = json.decode(db.rowsOf(2)[1].metadata).serial
    check('EXCHANGE two unique rows swap owners in place without a slot collision (two-phase move)', ok == true and s1 == 'S2' and s2 == 'S1' and #db.rowsOf(1) == 1 and #db.rowsOf(2) == 1)
    check('EXCHANGE validation is read-only', (function()
        inv(db, 1, { { 'pocket-1', 'water', 5 } }); inv(db, 2, {})
        local fp0, w0 = fp(db), db.writes
        local okV = val(W, R(29), side(1, { line(rowOf(W, 1, 'water'), 2) }), side(2, {}))
        return okV == true and fp(db) == fp0 and db.writes == w0 end)())
end

-- =================================================================== OFFER SHAPE / FORGERY / BOUNDS
do
    local W, db = world()
    inv(db, 1, { { 'pocket-1', 'water', 5 } }); inv(db, 2, { { 'pocket-1', 'sandwich', 5 } })
    local a, b = rowOf(W, 1, 'water'), rowOf(W, 2, 'sandwich')
    local whySeq = 0   -- a definite rejection is TERMINAL for its reference, so every probe uses a fresh one
    local function why(sa, sb) whySeq = whySeq + 1; return select(2, exec(W, R(300 + whySeq), sa, sb)) end
    check('OFFER forged ref (another character\'s row offered as mine) is rejected', why(side(1, { { ref = b.ref, quantity = 1 } }), side(2, {})) == 'invalid_item')
    check('OFFER non-existent row rejected', why(side(1, { { ref = '999999', quantity = 1 } }), side(2, {})) == 'invalid_item')
    check('OFFER excessive quantity rejected (bounds and stock)', why(side(1, { { ref = a.ref, quantity = 1001 } }), side(2, {})) == 'invalid_transaction' and why(side(1, { { ref = a.ref, quantity = 6 } }), side(2, {})) == 'insufficient_quantity')
    check('OFFER zero / negative / fractional quantity rejected', why(side(1, { { ref = a.ref, quantity = 0 } }), side(2, {})) == 'invalid_transaction' and why(side(1, { { ref = a.ref, quantity = -1 } }), side(2, {})) == 'invalid_transaction' and why(side(1, { { ref = a.ref, quantity = 1.5 } }), side(2, {})) == 'invalid_transaction')
    check('OFFER duplicate ref / extra fields / bad ref format rejected', why(side(1, { { ref = a.ref, quantity = 1 }, { ref = a.ref, quantity = 1 } }), side(2, {})) == 'invalid_transaction'
        and why(side(1, { { ref = a.ref, quantity = 1, price = 5 } }), side(2, {})) == 'invalid_transaction' and why(side(1, { { ref = "1; DROP", quantity = 1 } }), side(2, {})) == 'invalid_transaction')
    check('OFFER both sides empty / same character / unknown character rejected', why(side(1, {}), side(2, {})) == 'invalid_transaction' and why(side(1, { line(a, 1) }), side(1, {})) == 'invalid_transaction' and why(side(1, { line(a, 1) }), side(99, {})) == 'invalid_transaction')
    check('OFFER too many lines rejected', (function() local many = {} for i = 1, 9 do many[i] = { ref = tostring(i), quantity = 1 } end return why(side(1, many), side(2, {})) == 'invalid_transaction' end)())
    check('OFFER extra top-level / side fields rejected', select(2, exec(W, R(31), { characterId = 1, lines = {}, bank = 5 }, side(2, { line(b, 1) }))) == 'invalid_transaction')
    check('OFFER a forged fingerprint is rejected (item_changed), nothing moves', why(side(1, { { ref = a.ref, quantity = 1, fp = '0123456789abcdef' } }), side(2, {})) == 'item_changed' and db.count(2, 'water') == 0)
end

-- =================================================================== SNAPSHOT / STALE
do
    local W, db = world()
    inv(db, 1, { { 'pocket-1', 'water', 5 }, { 'pocket-2', 'rare_gem', 1, { serial = 'G1', durability = 80 } } }); inv(db, 2, { { 'pocket-1', 'sandwich', 2 } })
    local w, g, sw = rowOf(W, 1, 'water'), rowOf(W, 1, 'rare_gem'), rowOf(W, 2, 'sandwich')
    check('SNAPSHOT exposes ref/label/quantity/tradeable/summary and no inventory internals', (function() local keys = {} for k in pairs(w) do keys[#keys + 1] = k end table.sort(keys) return table.concat(keys, ',') == 'fp,image,item,label,quantity,ref,summary,tradeable' or table.concat(keys, ',') == 'fp,image,item,label,quantity,ref,tradeable' end)())
    check('SNAPSHOT summary is a short safe string (durability)', g.summary == 'Durability 80%')
    -- inventory changes after the offer
    local row = db.rowsOf(1)[1]; row.quantity = 2
    check('STALE quantity dropped after the offer: refused, nothing moves', select(2, exec(W, R(40), side(1, { line(w, 5) }), side(2, {}))) == 'insufficient_quantity' and db.count(2, 'water') == 0)
    row.quantity = 5
    db.rowsOf(1)[2].metadata = json.encode({ serial = 'G1', durability = 55 })
    check('STALE metadata changed after the offer (durability used): item_changed, nothing moves', select(2, exec(W, R(41), side(1, { line(g) }), side(2, {}))) == 'item_changed' and db.count(2, 'rare_gem') == 0)
    db.inventory_items = (function() local o = {} for _, r in ipairs(db.inventory_items) do if r.id ~= tonumber(w.ref) then o[#o + 1] = r end end return o end)()
    check('STALE row used up / dropped after the offer: invalid_item, nothing moves', select(2, exec(W, R(42), side(1, { line(w, 1) }), side(2, { line(sw, 1) }))) == 'invalid_item' and db.count(2, 'water') == 0 and db.count(1, 'sandwich') == 0)
    -- stale fingerprint after the item was swapped to another instance with the same quantity
    inv(db, 1, { { 'pocket-1', 'water', 5 } }); local w2 = rowOf(W, 1, 'water')
    db.rowsOf(1)[1].metadata = json.encode({ batch = 'SWAPPED' })
    check('STALE a different variant under the same row is detected', select(2, exec(W, R(43), side(1, { line(w2, 1) }), side(2, {}))) == 'item_changed')
end

-- =================================================================== CAPACITY
do
    local W, db = world()
    -- A: heavy_box 14000 + 20 water 10000 = 24000 of 25000. B offers 10 water (5000).
    inv(db, 1, { { 'pocket-1', 'heavy_box', 1 }, { 'pocket-2', 'water', 20 } }); inv(db, 2, { { 'pocket-1', 'water', 10 } })
    local fp0 = fp(db)
    local naive = select(2, exec(W, R(50), side(1, {}), side(2, { line(rowOf(W, 2, 'water'), 10) })))
    check('CAPACITY a one-way gift that overloads the receiver is refused and changes nothing', naive == 'no_capacity' and fp(db) == fp0)
    local ok = exec(W, R(51), side(1, { line(rowOf(W, 1, 'water'), 20) }), side(2, { line(rowOf(W, 2, 'water'), 10) }))
    check('CAPACITY A gains weight but frees enough first (final = current - offer + incoming): accepted', ok == true and db.count(1, 'water') == 10 and db.count(2, 'water') == 20)
    -- both sides near the limit: A 24000 (box + 20 water), B 21000 (box + 20 sandwich). Swapping the loads gives A 21000 and B 24000: each frees before it gains.
    inv(db, 1, { { 'pocket-1', 'heavy_box', 1 }, { 'pocket-2', 'water', 20 } }); inv(db, 2, { { 'pocket-1', 'heavy_box', 1 }, { 'pocket-2', 'sandwich', 20 } })
    ok = exec(W, R(52), side(1, { line(rowOf(W, 1, 'water'), 20) }), side(2, { line(rowOf(W, 2, 'sandwich'), 20) }))
    check('CAPACITY both sides near the limit swap loads (each frees before it gains): accepted', ok == true and db.count(1, 'sandwich') == 20 and db.count(2, 'water') == 20)
    -- A offers only 10 water (5000) for 28 sandwiches (9800): A final = 24000 - 5000 + 9800 = 28800 > 25000
    inv(db, 1, { { 'pocket-1', 'heavy_box', 1 }, { 'pocket-2', 'water', 20 } }); inv(db, 2, { { 'pocket-1', 'heavy_box', 1 }, { 'pocket-2', 'sandwich', 28 } })
    local before = fp(db)
    ok = exec(W, R(53), side(1, { line(rowOf(W, 1, 'water'), 10) }), side(2, { line(rowOf(W, 2, 'sandwich'), 28) }))
    check('CAPACITY the side whose final weight exceeds the limit fails the WHOLE exchange, no mutations on either side', ok == false and fp(db) == before)
    -- slots: A has all 6 pockets full; trading one whole row for one incoming uses the freed slot
    inv(db, 1, { { 'pocket-1', 'water', 1 }, { 'pocket-2', 'sandwich', 1 }, { 'pocket-3', 'bandage', 1 }, { 'pocket-4', 'medkit', 1 }, { 'pocket-5', 'rare_gem', 1, { serial = 'X' } }, { 'pocket-6', 'water', 1, { batch = 'Z' } } })
    inv(db, 2, { { 'pocket-1', 'bandage', 3 } })
    ok = exec(W, R(54), side(1, { line(rowOf(W, 1, 'sandwich'), 1) }), side(2, { line(rowOf(W, 2, 'bandage'), 1) }))
    check('CAPACITY a full-slot inventory can swap one row for one (the freed slot is reused)', ok == true and db.count(1, 'bandage') == 2)
    inv(db, 1, { { 'pocket-1', 'water', 1 }, { 'pocket-2', 'sandwich', 1 }, { 'pocket-3', 'bandage', 1 }, { 'pocket-4', 'medkit', 1 }, { 'pocket-5', 'rare_gem', 1, { serial = 'X' } }, { 'pocket-6', 'water', 1, { batch = 'Z' } } })
    inv(db, 2, { { 'pocket-1', 'heavy_box', 1 } })
    local before2 = fp(db)
    check('CAPACITY no free slot for an incoming distinct row: refused, nothing changes', select(2, exec(W, R(55), side(1, {}), side(2, { line(rowOf(W, 2, 'heavy_box')) }))) == 'no_capacity' and fp(db) == before2)
    check('CAPACITY a backpack-slot bag lets the incoming row use an unlocked backpack slot', (function()
        inv(db, 1, { { 'bag', 'clothing_bags', 1, { bagLevel = 1 } }, { 'pocket-1', 'water', 1 }, { 'pocket-2', 'sandwich', 1 }, { 'pocket-3', 'bandage', 1 }, { 'pocket-4', 'medkit', 1 }, { 'pocket-5', 'rare_gem', 1, { serial = 'X' } }, { 'pocket-6', 'water', 1, { batch = 'Z' } } })
        local okB = exec(W, R(56), side(1, {}), side(2, { line(rowOf(W, 2, 'heavy_box')) }))
        local slot; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'heavy_box' then slot = r.slot end end
        return okB == true and slot == 'backpack-1' end)())
    check('CAPACITY singleton item already carried by the receiver is refused', (function()
        ITEMS.one_only = { weight = 5, singleton = true, tradeable = true }
        inv(db, 1, { { 'pocket-1', 'one_only', 1 } }); inv(db, 2, { { 'pocket-1', 'one_only', 1 } })
        local r = select(2, exec(W, R(57), side(1, { line(rowOf(W, 1, 'one_only')) }), side(2, {})))
        return r == 'singleton_conflict' end)())
end

-- =================================================================== IDEMPOTENCY / STATUS / RESTART
do
    local W, db = world()
    inv(db, 1, { { 'pocket-1', 'water', 10 } }); inv(db, 2, { { 'pocket-1', 'sandwich', 4 } })
    local a, b = rowOf(W, 1, 'water'), rowOf(W, 2, 'sandwich')
    local sa, sb = side(1, { line(a, 3) }), side(2, { line(b, 2) })
    local ok, res = exec(W, R(60), sa, sb)
    check('IDEMPOTENCY first commit', ok == true and res.replayed == false and db.count(1, 'water') == 7 and db.count(2, 'water') == 3)
    local snap0 = fp(db)
    local ok2, res2 = exec(W, R(60), sa, sb)
    check('IDEMPOTENCY replay (same reference, same payload) returns the previous result and mutates nothing', ok2 == true and res2.replayed == true and fp(db) == snap0)
    check('IDEMPOTENCY the same exchange with the sides swapped is the SAME payload (replay)', select(2, exec(W, R(60), sb, sa)).replayed == true and fp(db) == snap0)
    check('IDEMPOTENCY same reference + changed quantity / item / character is a conflict', select(2, exec(W, R(60), side(1, { line(a, 2) }), sb)) == 'reference_conflict' and select(2, exec(W, R(60), side(1, { line(a, 3) }), side(3, { line(b, 2) }))) == 'reference_conflict' and fp(db) == snap0)
    check('IDEMPOTENCY ledger row is unique, typed trade_exchange, and holds no inventory snapshot', #db.ledger == 1 and db.ledger[1].tx_type == 'trade_exchange' and #db.ledger[1].payload < 400)
    check('STATUS committed / unknown reference / malformed reference', status(W, R(60)) == 'committed' and status(W, R(999)) == 'not_submitted' and select(2, status(W, 'x')) == 'invalid_reference')
    check('STATUS the cm-trade probe reference answers (item trading detection)', status(W, 'cm-trade-probe') == 'not_submitted')
    check('STATUS DB error -> unknown, never a guess', (function() db.failOn = function() return true end local s = status(W, R(61)) db.failOn = nil return s == 'unknown' end)())
    check('STATUS a craft/sink reference is a conflict through the exchange API', (function()
        W.invoker = 'cm-crafting'; inv(db, 1, { { 'pocket-1', 'iron_ore', 5 } }); ITEMS.iron_ore = ITEMS.iron_ore or { weight = 300 }
        W.registry.ExecuteCraftTransaction('CRAFT-XCHG0001', '1', { inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'iron_ingot', amount = 1 } } })
        return select(2, status(W, 'CRAFT-XCHG0001')) == 'reference_conflict' and select(2, exec(W, 'CRAFT-XCHG0001', side(1, { { ref = '1', quantity = 1 } }), side(2, {}))) == 'reference_conflict' end)())
    -- response loss + restart
    inv(db, 1, { { 'pocket-1', 'water', 10 } }); inv(db, 2, { { 'pocket-1', 'sandwich', 4 } }); db.ledger = {}
    local a2, b2 = rowOf(W, 1, 'water'), rowOf(W, 2, 'sandwich')
    exec(W, R(62), side(1, { line(a2, 3) }), side(2, { line(b2, 2) }))   -- result discarded (response lost)
    check('STATUS response loss: the ledger answers committed', status(W, R(62)) == 'committed')
    local W2 = newWorld(db); W2.invoker = 'cm-trade'
    local snapR = fp(db)
    check('RESTART the ledger survives a resource restart', W2.registry.GetItemExchangeStatus(R(62)) == 'committed')
    local okR, resR = W2.registry.ExecuteItemExchange(R(62), side(1, { line(a2, 3) }), side(2, { line(b2, 2) }))
    check('RESTART a committed replay does not repeat the exchange', okR == true and resR.replayed == true and fp(db) == snapR)
end

-- =================================================================== ATOMICITY (fault injection)
do
    local W, db = world()
    local base1 = { { 'pocket-1', 'water', 10 }, { 'pocket-2', 'rare_gem', 1, { serial = 'G9' } } }
    local base2 = { { 'pocket-1', 'sandwich', 4 }, { 'pocket-2', 'water', 3, { batch = 'Q' } } }
    local points = { 'exchange_begin', 'exchange_after_lock_a', 'exchange_after_lock_both', 'exchange_after_validation', 'exchange_after_remove_a', 'exchange_after_remove_b', 'exchange_after_first_add', 'exchange_after_adds', 'exchange_before_ledger', 'exchange_after_ledger' }
    for i, point in ipairs(points) do
        inv(db, 1, base1); inv(db, 2, base2); db.ledger = {}; db.audit = {}
        local function lines() return side(1, { line(rowOf(W, 1, 'water'), 4), line(rowOf(W, 1, 'rare_gem')) }), side(2, { line(rowOf(W, 2, 'sandwich'), 2), line(rowOf(W, 2, 'water'), 3) }) end
        local sa, sb = lines()
        local fp0 = fp(db)
        W.env.CMInventory.SetCraftFailpoint(function(name) if name == point then error('injected failure at ' .. point) end end)
        local ok, why = exec(W, R(70 + i), sa, sb)
        W.env.CMInventory.SetCraftFailpoint(nil)
        check('ATOMICITY failure at ' .. point .. ' rolls back both inventories, audit and ledger', ok == false and why == 'unavailable' and fp(db) == fp0)
        check('ATOMICITY ' .. point .. ' -> status pending (the owner never claims not_applied on an error)', status(W, R(70 + i)) == 'pending')
        local retry, rres = exec(W, R(70 + i), sa, sb)
        check('ATOMICITY the SAME reference retried after ' .. point .. ' commits exactly once', retry == true and rres.replayed == false and #db.ledger == 1 and db.count(2, 'rare_gem') == 1 and db.count(1, 'water') == 9 and db.count(2, 'water') == 4)
    end
    for _, stmt in ipairs({ 'UPDATE inventory_items SET quantity', 'INSERT INTO inventory_items', 'UPDATE inventory_items SET owner_id', 'UPDATE inventory_items SET slot', 'INSERT INTO inventory_audit', 'INSERT INTO cm_inventory_transactions' }) do
        inv(db, 1, base1); inv(db, 2, base2); db.ledger = {}; db.audit = {}
        local sa, sb = side(1, { line(rowOf(W, 1, 'water'), 4), line(rowOf(W, 1, 'rare_gem')) }), side(2, { line(rowOf(W, 2, 'sandwich'), 2) })
        local fp0 = fp(db)
        db.failOn = function(sql) return sql:find('^' .. stmt) end
        local ok = exec(W, R(90), sa, sb)
        db.failOn = nil
        check('ATOMICITY SQL error on "' .. stmt .. '" rolls back everything', ok == false and fp(db) == fp0)
    end
    check('ATOMICITY SQL error on DELETE (whole stack merging into a compatible stack) rolls back everything', (function()
        inv(db, 1, { { 'pocket-1', 'water', 5 } }); inv(db, 2, { { 'pocket-1', 'water', 2 } }); db.ledger = {}
        local sa = side(1, { line(rowOf(W, 1, 'water'), 5) })
        local fp0 = fp(db)
        db.failOn = function(sql) return sql:find('^DELETE FROM inventory_items') end
        local okD = exec(W, R(92), sa, side(2, {}))
        db.failOn = nil
        local okE = exec(W, R(92), sa, side(2, {}))
        return okD == false and okE == true and db.count(2, 'water') == 7 and #db.rowsOf(2) == 1 and db.count(1, 'water') == 0 end)())
    check('ATOMICITY a UNIQUE (owner,slot) collision during the move rolls everything back', (function()
        inv(db, 1, base1); inv(db, 2, base2); db.ledger = {}
        local sa = side(1, { line(rowOf(W, 1, 'rare_gem')) })
        local fp0 = fp(db)
        -- plant a row in the receiver's temporary transfer slot so the first move statement collides
        local gem = rowOf(W, 1, 'rare_gem')
        db.give(2, 'xfer-' .. gem.ref, 'water', 1)
        local fp1 = fp(db)
        local ok = exec(W, R(91), sa, side(2, {}))
        return ok == false and fp(db) == fp1 end)())
end

-- =================================================================== CONCURRENCY / LOCK ORDER
do
    local W, db = world()
    inv(db, 1, { { 'pocket-1', 'water', 10 }, { 'pocket-2', 'bandage', 4 } }); inv(db, 2, { { 'pocket-1', 'sandwich', 10 }, { 'pocket-2', 'medkit', 2 } })
    local a1, a2, b1, b2 = rowOf(W, 1, 'water'), rowOf(W, 1, 'bandage'), rowOf(W, 2, 'sandwich'), rowOf(W, 2, 'medkit')
    db.interleave = true
    local r = {}
    -- Exchange 1: A <-> B, Exchange 2: B <-> A (opposite argument order), same two characters, different rows
    Sched.spawn(function() W.invoker = 'cm-trade'; r[1] = { exec(W, R(100), side(1, { line(a1, 3) }), side(2, { line(b1, 3) })) } end)
    Sched.spawn(function() W.invoker = 'cm-trade'; r[2] = { exec(W, R(101), side(2, { line(b2, 1) }), side(1, { line(a2, 2) })) } end)
    Sched.run()
    db.interleave = false
    check('LOCK ORDER A<->B racing B<->A: both complete, no deadlock', r[1][1] == true and r[2][1] == true and (db.deadlocks or 0) == 0 and #db.ledger == 2)
    check('LOCK ORDER every transaction locked the lower character id first', (function()
        for i = 1, #db.lockLog, 2 do if db.lockLog[i] ~= '1' or db.lockLog[i + 1] ~= '2' then return false end end return #db.lockLog >= 4 end)(), table.concat(db.lockLog, ','))
    check('LOCK ORDER conservation after the race', total(db, 'water') == 10 and total(db, 'sandwich') == 10 and total(db, 'bandage') == 4 and total(db, 'medkit') == 2)

    -- double submit of the same trade
    inv(db, 1, { { 'pocket-1', 'water', 10 } }); inv(db, 2, { { 'pocket-1', 'sandwich', 10 } }); db.ledger = {}
    local sa, sb = side(1, { line(rowOf(W, 1, 'water'), 3) }), side(2, { line(rowOf(W, 2, 'sandwich'), 3) })
    db.interleave = true
    local rr = {}
    for i = 1, 4 do Sched.spawn(function() W.invoker = 'cm-trade'; rr[i] = { exec(W, R(102), sa, sb) } end) end
    Sched.run(); db.interleave = false
    local applied, replays, pending = 0, 0, 0
    for _, x in ipairs(rr) do if x[1] == true then if x[2].replayed then replays = replays + 1 else applied = applied + 1 end elseif x[2] == 'pending' then pending = pending + 1 end end
    check('CONCURRENCY four simultaneous submits of one trade: exactly one executor; the others replay or see pending', applied == 1 and replays + pending == 3 and #db.ledger == 1 and db.count(1, 'water') == 7 and db.count(2, 'water') == 3)
    check('CONCURRENCY a later submit replays the committed result', select(2, exec(W, R(102), sa, sb)).replayed == true and db.count(1, 'water') == 7)

    -- two trades competing for the same stock
    inv(db, 1, { { 'pocket-1', 'water', 5 } }); inv(db, 2, {}); inv(db, 3, {}); db.ledger = {}
    local w = rowOf(W, 1, 'water')
    db.interleave = true
    local cc = {}
    Sched.spawn(function() W.invoker = 'cm-trade'; cc[1] = { exec(W, R(103), side(1, { line(w, 5) }), side(2, {})) } end)
    Sched.spawn(function() W.invoker = 'cm-trade'; cc[2] = { exec(W, R(104), side(1, { line(w, 5) }), side(3, {})) } end)
    Sched.run(); db.interleave = false
    check('CONCURRENCY two trades of the same 5 water to different players: exactly one succeeds, nothing duplicated', ((cc[1][1] == true) ~= (cc[2][1] == true)) and total(db, 'water') == 5 and db.count(1, 'water') == 0)

    -- exchange vs the legacy RemoveItem on the same player
    inv(db, 1, { { 'pocket-1', 'water', 5 } }); inv(db, 2, {}); db.ledger = {}
    local w3 = rowOf(W, 1, 'water')
    db.interleave = true
    local ex, rm
    Sched.spawn(function() W.invoker = 'cm-trade'; ex = { exec(W, R(105), side(1, { line(w3, 5) }), side(2, {})) } end)
    Sched.spawn(function() rm = { W.env.TESTPROBE.Remove({ characterId = 1 }, 'water', 5, nil, 'test') } end)
    Sched.run(); db.interleave = false
    check('CONCURRENCY exchange vs RemoveItem on the same stack: exactly one spends it, never negative', (ex[1] == true) ~= (rm[1] == true) and total(db, 'water') == (ex[1] and 5 or 0) and db.count(1, 'water') + db.count(2, 'water') >= 0)
end

print(('\ncm-inventory item exchange self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
