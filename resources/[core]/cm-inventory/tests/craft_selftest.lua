-- Deterministic self-test for the cm-inventory craft settlement (server/craft.lua).
--   lua tests/craft_selftest.lua        (run from resources/[core]/cm-inventory)
--
-- REAL (production code, loaded exactly like server/main.lua does: one concatenated chunk):
--   server/db.lua, items.lua, slots.lua, bags.lua, equipment.lua, external.lua, craft.lua and config.lua
--   -> normalization, planning (inputs/tools/durability/outputs/stacking/slots/weight), idempotency/ledger decisions, locking,
--      the wrapped legacy AddItemInternal/RemoveItemInternal, exports and trust checks.
-- TEST DOUBLES (labelled): the FiveM runtime (exports/GetInvokingResource/threads), cm-items (item definitions), and the SQL layer:
--   an in-memory engine that understands exactly the statements these files issue, with transactional undo (rollback), a UNIQUE
--   reference constraint, and failure injection. It does NOT prove MySQL semantics (row locks, FOR UPDATE, isolation) --
--   that is what the isolated MySQL smoke test (tests/craft_mysql_smoke.lua) is for.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

local H = dofile(here .. '/tests/craft_harness.lua')(here)
local json, deepcopy, ser, Sched, yieldMaybe, newDb, newWorld, ITEMS = H.json, H.deepcopy, H.ser, H.Sched, H.yieldMaybe, H.newDb, H.newWorld, H.ITEMS

local function freshWorld()
    local db = newDb()
    db.addChar(1); db.addChar(2)
    local W = newWorld(db)
    return W, db
end

local function call(W, name, ...) return W.registry[name](...) end
local function exec(W, ref, cid, tx) return call(W, 'ExecuteCraftTransaction', ref, cid, tx) end
local function validate(W, cid, tx) return call(W, 'ValidateCraftTransaction', cid, tx) end
local function status(W, ref) return call(W, 'GetCraftTransactionStatus', ref) end
local function R(n) return ('CRAFT-TEST%04d'):format(n) end

local BAG = { slot = 'bag', item = 'clothing_bags', meta = { bagLevel = 1 } }
local function inv(db, cid, rows)
    db.clear(cid)
    for _, r in ipairs(rows) do db.give(cid, r[1], r[2], r[3], r[4]) end
end
local ingotTx = { inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'iron_ingot', amount = 1 } } }
local function tx(t) return deepcopy(t) end

-- =================================================================== TRUST
do
    local W, db = freshWorld()
    check('exports registered on the real chunk', W.registry.ValidateCraftTransaction ~= nil and W.registry.ExecuteCraftTransaction ~= nil and W.registry.GetCraftTransactionStatus ~= nil)
    inv(db, 1, { { 'pocket-1', 'iron_ore', 5 } })
    W.invoker = 'cm-evil'
    local ok, why = exec(W, R(1), '1', tx(ingotTx))
    check('TRUST untrusted resource cannot execute', ok == false and why == 'forbidden')
    check('TRUST untrusted resource cannot validate', select(2, validate(W, '1', tx(ingotTx))) == 'forbidden')
    check('TRUST untrusted resource cannot read status', select(2, status(W, R(1))) == 'forbidden')
    W.invoker = nil
    check('TRUST nil invoker (fail closed)', select(2, exec(W, R(1), '1', tx(ingotTx))) == 'forbidden')
    check('TRUST untrusted call changed nothing', db.count(1, 'iron_ore') == 5 and #db.ledger == 0)
    W.invoker = 'cm-crafting'
    local ok2 = exec(W, R(1), '1', tx(ingotTx))
    check('TRUST cm-crafting accepted', ok2 == true)
    local crafty = false
    for _, n in ipairs(W.netEvents) do if n:lower():find('craft') then crafty = true end end
    check('TRUST no client/net event for craft execution', crafty == false)
    check('TRUST colon-style call (hidden self) accepted', (function()
        local ok3 = W.registry.GetCraftTransactionStatus({}, R(1))
        return ok3 == 'committed'
    end)())
end

-- =================================================================== VALIDATION
do
    local W, db = freshWorld()
    inv(db, 1, { { 'pocket-1', 'iron_ore', 50 } })
    local function reason(t, cid) local ok, why = validate(W, cid or '1', t); return ok, why end
    check('VALIDATION valid transaction', validate(W, '1', tx(ingotTx)) == true)
    check('VALIDATION tx not a table', select(2, reason('x')) == 'invalid_transaction')
    check('VALIDATION unknown top-level field', select(2, reason({ inputs = {}, outputs = { { item = 'iron_ingot', amount = 1 } }, extra = 1 })) == 'invalid_transaction')
    check('VALIDATION unknown line field', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1, price = 5 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION inputs not an array', select(2, reason({ inputs = { a = { item = 'iron_ore', amount = 1 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION duplicate input item', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 }, { item = 'iron_ore', amount = 1 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION empty transaction', select(2, reason({})) == 'invalid_transaction')
    check('VALIDATION outputs from nothing (mint)', select(2, reason({ outputs = { { item = 'iron_ingot', amount = 1 } } })) == 'invalid_transaction')
    check('VALIDATION unknown input item', select(2, reason({ inputs = { { item = 'nonexistent', amount = 1 } }, outputs = {} })) == 'invalid_item')
    check('VALIDATION unknown output item', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'nonexistent', amount = 1 } } })) == 'invalid_item')
    check('VALIDATION virtual item rejected', select(2, reason({ inputs = { { item = 'ghost_item', amount = 1 } }, outputs = {} })) == 'invalid_item')
    check('VALIDATION bad item name format', select(2, reason({ inputs = { { item = 'Iron Ore;', amount = 1 } }, outputs = {} })) == 'invalid_item')
    check('VALIDATION zero amount', select(2, reason({ inputs = { { item = 'iron_ore', amount = 0 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION negative amount', select(2, reason({ inputs = { { item = 'iron_ore', amount = -3 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION fractional amount', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1.5 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION NaN amount', select(2, reason({ inputs = { { item = 'iron_ore', amount = 0 / 0 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION excessive quantity per line', select(2, reason({ inputs = { { item = 'iron_ore', amount = 10001 } }, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION excessive aggregate quantity', select(2, reason({ inputs = { { item = 'iron_ore', amount = 10000 }, { item = 'material', amount = 10000 }, { item = 'plate', amount = 10000 }, { item = 'junk1', amount = 10000 }, { item = 'junk2', amount = 10000 }, { item = 'junk3', amount = 1 } }, outputs = {} })) == 'invalid_transaction')
    local many = {} for i = 1, 9 do many[i] = { item = 'iron_ore', amount = 1 } end
    check('VALIDATION too many input lines', select(2, reason({ inputs = many, outputs = {} })) == 'invalid_transaction')
    check('VALIDATION invalid metadata (function)', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'iron_ingot', amount = 1, metadata = { f = function() end } } } })) == 'invalid_metadata')
    check('VALIDATION invalid metadata (too deep)', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'iron_ingot', amount = 1, metadata = { a = { b = { c = { d = { e = 1 } } } } } } } })) == 'invalid_metadata')
    check('VALIDATION invalid metadata (oversized)', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'iron_ingot', amount = 1, metadata = { s = string.rep('x', 2000) } } } })) == 'invalid_metadata')
    check('VALIDATION cm-items schema rejects metadata', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'schema_item', amount = 1, metadata = {} } } })) == 'invalid_metadata')
    check('VALIDATION cm-items schema accepts metadata', validate(W, '1', { inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'schema_item', amount = 1, metadata = { grade = 'A' } } } }) == true)
    check('VALIDATION unique output unsupported', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'weapon_pistol', amount = 1 } } })) == 'invalid_item')
    check('VALIDATION clothing output unsupported', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'clothing_pants', amount = 1 } } })) == 'invalid_item')
    check('VALIDATION singleton output amount > 1', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'one_only', amount = 2 } } })) == 'invalid_item')
    check('VALIDATION durability input rejected (needs metadata semantics)', select(2, reason({ inputs = { { item = 'hammer', amount = 1 } }, outputs = {} })) == 'invalid_item')
    check('VALIDATION tool durabilityUse out of range', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = {}, tools = { { item = 'hammer', durabilityUse = 0 } } })) == 'invalid_transaction')
    check('VALIDATION tool that is also an input', select(2, reason({ inputs = { { item = 'iron_ore', amount = 1 } }, outputs = {}, tools = { { item = 'iron_ore' } } })) == 'invalid_transaction')
    check('VALIDATION bad character id', select(2, validate(W, "1; DROP", tx(ingotTx))) == 'invalid_transaction')
    check('VALIDATION unknown character', select(2, validate(W, '999', tx(ingotTx))) == 'invalid_transaction')
    check('VALIDATION cm-items down -> unavailable', (function() W.itemsDown = true; local _, why = validate(W, '1', { inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'schema_item', amount = 1, metadata = { grade = 'A' } } } }); W.itemsDown = nil; return why == 'unavailable' end)())
    local before = db.fingerprint(); local w0 = db.writes
    validate(W, '1', tx(ingotTx)); validate(W, '1', { inputs = { { item = 'iron_ore', amount = 999 } }, outputs = {} })
    check('VALIDATION is read-only', db.fingerprint() == before and db.writes == w0)
end

-- =================================================================== INPUTS
do
    local W, db = freshWorld()
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } })
    local ok, res = exec(W, R(10), '1', tx(ingotTx))
    check('INPUTS exact stack consumed, row removed, output created', ok == true and db.count(1, 'iron_ore') == 0 and db.count(1, 'iron_ingot') == 1)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 3 }, { 'pocket-2', 'iron_ore', 2 } })
    ok = exec(W, R(11), '1', { inputs = { { item = 'iron_ore', amount = 4 } }, outputs = { { item = 'iron_ingot', amount = 2 } } })
    check('INPUTS span multiple stacks (largest first)', ok == true and db.count(1, 'iron_ore') == 1 and db.count(1, 'iron_ingot') == 2)
    local left; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'iron_ore' then left = r end end
    check('INPUTS remainder stays in the smaller stack', left and left.slot == 'pocket-2' and left.quantity == 1)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 1 } })
    local fp = db.fingerprint()
    local ok2, why2 = exec(W, R(12), '1', tx(ingotTx))
    check('INPUTS insufficient -> insufficient_input, nothing applied', ok2 == false and why2 == 'insufficient_input' and db.fingerprint() == fp)
    check('INPUTS insufficient leaves status not_applied', status(W, R(12)) == 'not_applied')

    inv(db, 1, { { 'pocket-1', 'iron_ore', 5, { purity = 'high' } }, { 'pocket-2', 'iron_ore', 1 } })
    fp = db.fingerprint()
    ok2, why2 = exec(W, R(13), '1', tx(ingotTx))
    check('INPUTS metadata-sensitive stack is NOT consumed as a generic input', ok2 == false and why2 == 'insufficient_input' and db.fingerprint() == fp)
    inv(db, 1, { { 'pocket-1', 'iron_ore', 5, { purity = 'high' } }, { 'pocket-2', 'iron_ore', 2 } })
    ok2 = exec(W, R(14), '1', tx(ingotTx))
    check('INPUTS plain stack consumed, quality stack untouched', ok2 == true and db.count(1, 'iron_ore') == 5 and db.count(1, 'iron_ore', true) == 0)
    inv(db, 1, { { 'weapon', 'iron_ore', 9 }, { 'pocket-2', 'iron_ore', 1 } })
    ok2, why2 = exec(W, R(15), '1', tx(ingotTx))
    check('INPUTS equipment slot items are never consumed', ok2 == false and why2 == 'insufficient_input')
    inv(db, 2, { { 'pocket-1', 'iron_ore', 2 } })
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } })
    exec(W, R(16), '1', tx(ingotTx))
    check('INPUTS another character is untouched', db.count(2, 'iron_ore') == 2)
end

-- =================================================================== OUTPUTS
do
    local W, db = freshWorld()
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 }, { 'pocket-2', 'iron_ingot', 4 } })
    local ok = exec(W, R(20), '1', tx(ingotTx))
    local stacks = 0; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'iron_ingot' then stacks = stacks + 1 end end
    check('OUTPUTS stack onto existing compatible stack', ok == true and stacks == 1 and db.count(1, 'iron_ingot') == 5)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } })
    ok = exec(W, R(21), '1', tx(ingotTx))
    check('OUTPUTS new slot when no stack exists', ok == true and db.count(1, 'iron_ingot') == 1)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'iron_ingot', 1, { purity = 'fine' } } })
    ok = exec(W, R(22), '1', { inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'iron_ingot', amount = 1 } } })
    stacks = 0; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'iron_ingot' then stacks = stacks + 1 end end
    check('OUTPUTS incompatible-metadata stack is not merged into', ok == true and stacks == 2)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 } })
    ok = exec(W, R(23), '1', { inputs = { { item = 'iron_ore', amount = 4 } }, outputs = { { item = 'iron_ingot', amount = 2 }, { item = 'plate', amount = 3 } } })
    check('OUTPUTS multiple outputs', ok == true and db.count(1, 'iron_ingot') == 2 and db.count(1, 'plate') == 3 and db.count(1, 'iron_ore') == 0)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } })
    ok = exec(W, R(24), '1', { inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'schema_item', amount = 1, metadata = { grade = 'B' } } } })
    local row; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'schema_item' then row = r end end
    check('OUTPUTS trusted recipe metadata stored', ok == true and row and json.decode(row.metadata).grade == 'B')

    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 }, { 'pocket-2', 'one_only', 1 } })
    local fp = db.fingerprint()
    local ok2, why2 = exec(W, R(25), '1', { inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'one_only', amount = 1 } } })
    check('OUTPUTS singleton already carried is refused, nothing applied', ok2 == false and why2 == 'no_capacity' and db.fingerprint() == fp)
    check('OUTPUTS no unique/serial output was minted anywhere', db.count(1, 'weapon_pistol') == 0)
end

-- =================================================================== CAPACITY
do
    local W, db = freshWorld()
    -- no bag: 6 pockets, 25000 g
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 }, { 'pocket-2', 'junk1', 1 }, { 'pocket-3', 'junk2', 1 }, { 'pocket-4', 'junk3', 1 }, { 'pocket-5', 'junk4', 1 }, { 'pocket-6', 'junk5', 1 } })
    local ok = exec(W, R(30), '1', tx(ingotTx))
    check('CAPACITY consumed input frees the slot the output needs', ok == true and db.count(1, 'iron_ingot') == 1 and db.count(1, 'iron_ore') == 0)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 5 }, { 'pocket-2', 'junk1', 1 }, { 'pocket-3', 'junk2', 1 }, { 'pocket-4', 'junk3', 1 }, { 'pocket-5', 'junk4', 1 }, { 'pocket-6', 'junk5', 1 } })
    local fp = db.fingerprint()
    local ok2, why2 = exec(W, R(31), '1', tx(ingotTx))
    check('CAPACITY no free slot after consumption -> no_capacity, inventory unchanged', ok2 == false and why2 == 'no_capacity' and db.fingerprint() == fp)
    check('CAPACITY failed commit leaves no ledger row', status(W, R(31)) == 'not_applied' and #db.ledger == 1)

    -- weight: 24 big_ore = 24000 g. naive pre-consumption check would reject 24000 + 1600.
    inv(db, 1, { { 'pocket-1', 'big_ore', 24 } })
    ok = exec(W, R(32), '1', { inputs = { { item = 'big_ore', amount = 10 } }, outputs = { { item = 'plate', amount = 4 } } })
    check('CAPACITY weight uses the post-transaction state (inputs free weight)', ok == true and db.count(1, 'big_ore') == 14 and db.count(1, 'plate') == 4)
    inv(db, 1, { { 'pocket-1', 'big_ore', 24 } })
    fp = db.fingerprint()
    ok2, why2 = exec(W, R(33), '1', { inputs = { { item = 'big_ore', amount = 2 } }, outputs = { { item = 'plate', amount = 20 } } })
    check('CAPACITY final weight over the limit -> no_capacity', ok2 == false and why2 == 'no_capacity' and db.fingerprint() == fp)

    -- bag level 1: 6 backpack slots, 45000 g
    inv(db, 1, { { 'bag', 'clothing_bags', 1, { bagLevel = 1 } }, { 'pocket-1', 'iron_ore', 2 }, { 'pocket-2', 'junk1', 1 }, { 'pocket-3', 'junk2', 1 }, { 'pocket-4', 'junk3', 1 }, { 'pocket-5', 'junk4', 1 }, { 'pocket-6', 'junk5', 1 }, { 'backpack-1', 'junk6', 1 } })
    ok = exec(W, R(34), '1', { inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'iron_ingot', amount = 1 } } })
    local slot; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'iron_ingot' then slot = r.slot end end
    check('CAPACITY bag-unlocked backpack slot used (real bag logic)', ok == true and slot == 'backpack-2', slot)

    -- input = output: 10 material -> 8 material
    inv(db, 1, { { 'pocket-1', 'material', 10 } })
    ok = exec(W, R(35), '1', { inputs = { { item = 'material', amount = 10 } }, outputs = { { item = 'material', amount = 8 } } })
    check('INPUT=OUTPUT whole stack processed in place', ok == true and db.count(1, 'material') == 8)
    inv(db, 1, { { 'pocket-1', 'material', 20 } })
    ok = exec(W, R(36), '1', { inputs = { { item = 'material', amount = 10 } }, outputs = { { item = 'material', amount = 8 } } })
    check('INPUT=OUTPUT partial stack nets correctly', ok == true and db.count(1, 'material') == 18 and #db.rowsOf(1) == 1)
end

-- =================================================================== TOOLS
do
    local W, db = freshWorld()
    local tool = { inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'iron_ingot', amount = 1 } } }
    local function withTool(t) local c = tx(tool); c.tools = t; return c end
    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'tongs', 1 } })
    local ok = exec(W, R(40), '1', withTool({ { item = 'tongs' } }))
    local t; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'tongs' then t = r end end
    check('TOOLS required tool present and kept', ok == true and t and t.quantity == 1 and t.metadata == nil)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 } })
    local fp = db.fingerprint()
    local ok2, why2 = exec(W, R(41), '1', withTool({ { item = 'tongs' } }))
    check('TOOLS missing tool -> tool_missing, nothing applied', ok2 == false and why2 == 'tool_missing' and db.fingerprint() == fp)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'hammer', 1, { durability = 50 } } })
    ok = exec(W, R(42), '1', withTool({ { item = 'hammer', durabilityUse = 10 } }))
    t = nil; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'hammer' then t = r end end
    check('TOOLS durability decremented in the same transaction', ok == true and json.decode(t.metadata).durability == 40 and db.count(1, 'iron_ingot') == 1)
    local replayOk, replay = exec(W, R(42), '1', withTool({ { item = 'hammer', durabilityUse = 10 } }))
    t = nil; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'hammer' then t = r end end
    check('TOOLS replay does not decrement twice', replayOk == true and replay.replayed == true and json.decode(t.metadata).durability == 40)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'hammer', 1 } })
    ok = exec(W, R(43), '1', withTool({ { item = 'hammer', durabilityUse = 10 } }))
    t = nil; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'hammer' then t = r end end
    check('TOOLS missing durability metadata falls back to the item definition (100 -> 90)', ok == true and json.decode(t.metadata).durability == 90)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'hammer', 1, { durability = 5 } } })
    fp = db.fingerprint()
    ok2, why2 = exec(W, R(44), '1', withTool({ { item = 'hammer', durabilityUse = 10 } }))
    check('TOOLS insufficient durability -> tool_durability, nothing applied', ok2 == false and why2 == 'tool_durability' and db.fingerprint() == fp)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'hammer', 1, { durability = 15 } }, { 'pocket-3', 'hammer', 1, { durability = 80 } } })
    ok = exec(W, R(45), '1', withTool({ { item = 'hammer', durabilityUse = 10 } }))
    local d = {}; for _, r in ipairs(db.rowsOf(1)) do if r.item_name == 'hammer' then d[r.slot] = json.decode(r.metadata).durability end end
    check('TOOLS the most worn sufficient tool is used', ok == true and d['pocket-2'] == 5 and d['pocket-3'] == 80)

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'hammer', 2, { durability = 80 } } })
    ok2, why2 = exec(W, R(46), '1', withTool({ { item = 'hammer', durabilityUse = 10 } }))
    check('TOOLS stacked tools cannot be partially worn', ok2 == false and why2 == 'tool_missing')

    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'hammer', 1, { durability = 80 } } })
    db.failOn = function(sql) return sql:find('^INSERT INTO cm_inventory_transactions') end
    fp = db.fingerprint()
    ok2 = exec(W, R(47), '1', withTool({ { item = 'hammer', durabilityUse = 10 } }))
    db.failOn = nil
    check('TOOLS durability rolled back together with a failed settlement', ok2 == false and db.fingerprint() == fp)
end

-- =================================================================== ATOMICITY
do
    local W, db = freshWorld()
    local base = { { 'pocket-1', 'iron_ore', 4 }, { 'pocket-2', 'hammer', 1, { durability = 50 } }, { 'pocket-3', 'iron_ingot', 2 } }
    local atx = { inputs = { { item = 'iron_ore', amount = 4 } }, outputs = { { item = 'iron_ingot', amount = 1 }, { item = 'plate', amount = 2 } }, tools = { { item = 'hammer', durabilityUse = 10 } } }
    for i, point in ipairs({ 'begin', 'after_validation', 'after_inputs', 'before_outputs', 'before_ledger', 'after_ledger' }) do
        inv(db, 1, base); db.ledger = {}; db.audit = {}
        local fp = db.fingerprint()
        W.env.CMInventory.SetCraftFailpoint(function(name) if name == point then error('injected failure at ' .. point) end end)
        local ok, why = exec(W, R(50 + i), '1', tx(atx))
        W.env.CMInventory.SetCraftFailpoint(nil)
        check('ATOMICITY failure at ' .. point .. ' rolls back everything', ok == false and why == 'unavailable' and db.fingerprint() == fp)
        check('ATOMICITY failure at ' .. point .. ' -> status not_applied', status(W, R(50 + i)) == 'not_applied')
        local retry, res = exec(W, R(50 + i), '1', tx(atx))
        check('ATOMICITY retry of the SAME reference after ' .. point .. ' commits once', retry == true and res.replayed == false and db.count(1, 'iron_ore') == 0 and db.count(1, 'plate') == 2 and #db.ledger == 1)
    end
    for _, pat in ipairs({ '^UPDATE inventory_items SET quantity', '^DELETE FROM inventory_items', '^INSERT INTO inventory_items', '^INSERT INTO inventory_audit', '^UPDATE inventory_items SET metadata' }) do
        inv(db, 1, base); db.ledger = {}; db.audit = {}
        local fp = db.fingerprint()
        db.failOn = function(sql) return sql:find(pat) end
        local ok = exec(W, R(70), '1', tx(atx))
        db.failOn = nil
        check('ATOMICITY SQL error on ' .. pat:sub(2, 30) .. ' rolls back everything', ok == false and db.fingerprint() == fp)
    end
    inv(db, 1, base); db.ledger = {}
    local fp = db.fingerprint()
    db.failOn = function(sql) return sql:find('^SELECT %* FROM inventory_items') end
    local ok, why = exec(W, R(71), '1', tx(atx))
    db.failOn = nil
    check('ATOMICITY read failure -> unavailable, nothing applied', ok == false and why == 'unavailable' and db.fingerprint() == fp)
end

-- =================================================================== IDEMPOTENCY / STATUS / RESTART
do
    local W, db = freshWorld()
    inv(db, 1, { { 'pocket-1', 'iron_ore', 10 } })
    local ok, res = exec(W, R(80), '1', tx(ingotTx))
    check('IDEMPOTENCY first commit', ok == true and res.replayed == false and db.count(1, 'iron_ingot') == 1 and db.count(1, 'iron_ore') == 8)
    local snap = db.fingerprint()
    local ok2, res2 = exec(W, R(80), '1', tx(ingotTx))
    check('IDEMPOTENCY same reference + same payload returns committed result without mutating', ok2 == true and res2.replayed == true and db.fingerprint() == snap)
    local changed = tx(ingotTx); changed.inputs[1].amount = 3
    local ok3, why3 = exec(W, R(80), '1', changed)
    check('IDEMPOTENCY same reference + changed payload rejected', ok3 == false and why3 == 'reference_conflict' and db.fingerprint() == snap)
    local ok4, why4 = exec(W, R(80), '2', tx(ingotTx))
    check('IDEMPOTENCY same reference + different character rejected', ok4 == false and why4 == 'reference_conflict' and db.fingerprint() == snap)
    local reordered = { outputs = { { item = 'iron_ingot', amount = 1 } }, inputs = { { amount = 2, item = 'iron_ore' } } }
    check('IDEMPOTENCY fingerprint is order-insensitive for fields', select(2, exec(W, R(80), '1', reordered)).replayed == true)
    check('IDEMPOTENCY ledger row is unique per reference', #db.ledger == 1 and db.ledger[1].tx_type == 'craft' and #db.ledger[1].payload_hash == 16)
    check('IDEMPOTENCY committed reference survives a later item-definition outage', (function() W.itemsDown = true; ITEMS.iron_ingot.weight = 300; local a, b = exec(W, R(80), '1', tx(ingotTx)); W.itemsDown = nil; return a == true and b.replayed == true end)())

    -- STATUS
    check('STATUS unknown reference -> not_applied', status(W, R(999)) == 'not_applied')
    check('STATUS committed', status(W, R(80)) == 'committed')
    check('STATUS malformed reference rejected', select(2, status(W, 'x')) == 'invalid_reference')
    check('STATUS DB error -> unknown (never guessed)', (function() db.failOn = function() return true end local s = status(W, R(81)) db.failOn = nil return s == 'unknown' end)())
    check('STATUS cm-crafting probe reference answers', status(W, 'CRAFT-PROBE0000') == 'not_applied')

    -- response loss: DB committed, caller never saw the result
    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 } })
    exec(W, R(82), '1', tx(ingotTx)) -- result discarded
    check('STATUS response-loss: ledger answers committed', status(W, R(82)) == 'committed')
    snap = db.fingerprint()
    local rl, rr = exec(W, R(82), '1', tx(ingotTx))
    check('STATUS response-loss retry does not duplicate', rl == true and rr.replayed == true and db.fingerprint() == snap and db.count(1, 'iron_ingot') == 1)

    -- RESTART: a fresh load of every file against the same database
    local W2 = newWorld(db)
    check('RESTART ledger survives a resource restart', status(W2, R(82)) == 'committed' and status(W2, R(80)) == 'committed')
    snap = db.fingerprint()
    local r1, r2 = exec(W2, R(82), '1', tx(ingotTx))
    check('RESTART committed replay does not repeat the output', r1 == true and r2.replayed == true and db.fingerprint() == snap)
end

-- =================================================================== CONCURRENCY
do
    local W, db = freshWorld()
    db.interleave = true
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } })
    local results = {}
    for i = 1, 2 do Sched.spawn(function() local ok, why = exec(W, R(90 + i), '1', tx(ingotTx)); results[i] = { ok, type(why) == 'string' and why or (why and why.replayed) } end) end
    Sched.run()
    local wins = (results[1][1] == true and 1 or 0) + (results[2][1] == true and 1 or 0)
    local neg = false; for _, r in ipairs(db.rowsOf(1)) do if r.quantity < 0 then neg = true end end
    check('CONCURRENCY two references compete for stock for one: exactly one wins', wins == 1 and db.count(1, 'iron_ingot') == 1 and db.count(1, 'iron_ore') == 0 and not neg)
    check('CONCURRENCY the loser fails definitely', (results[1][1] == false and results[1][2] == 'insufficient_input') or (results[2][1] == false and results[2][2] == 'insufficient_input'))

    inv(db, 1, { { 'pocket-1', 'iron_ore', 10 } }); db.ledger = {}
    results = {}
    for i = 1, 4 do Sched.spawn(function() local ok, res = exec(W, R(95), '1', tx(ingotTx)); results[i] = { ok, res } end) end
    Sched.run()
    local applied, replays = 0, 0
    for _, r in ipairs(results) do if r[1] == true then if r[2].replayed then replays = replays + 1 else applied = applied + 1 end end end
    check('CONCURRENCY simultaneous duplicate calls apply exactly once', applied == 1 and replays == 3 and db.count(1, 'iron_ingot') == 1 and db.count(1, 'iron_ore') == 8 and #db.ledger == 1)

    -- craft vs the (real, lock-wrapped) legacy RemoveItem on the same stack
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } }); db.ledger = {}
    local craftRes, removeRes
    Sched.spawn(function() craftRes = { exec(W, R(96), '1', tx(ingotTx)) } end)
    Sched.spawn(function() removeRes = { W.env.TESTPROBE.Remove({ characterId = 1 }, 'iron_ore', 2, nil, 'test') } end)
    Sched.run()
    local craftWon, removeWon = craftRes[1] == true, removeRes[1] == true
    local negative = false; for _, r in ipairs(db.rowsOf(1)) do if r.quantity < 0 then negative = true end end
    check('CONCURRENCY craft vs RemoveItem: exactly one spends the stack', craftWon ~= removeWon and not negative and db.count(1, 'iron_ore') == 0)
    check('CONCURRENCY craft vs RemoveItem: no output without input, no input lost without output',
        (craftWon and db.count(1, 'iron_ingot') == 1) or (removeWon and db.count(1, 'iron_ingot') == 0))

    -- craft vs AddItem on same character: both applied, serialized, no lost update
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } }); db.ledger = {}
    Sched.spawn(function() exec(W, R(97), '1', tx(ingotTx)) end)
    Sched.spawn(function() W.env.TESTPROBE.Add({ characterId = 1 }, 'iron_ingot', 3, nil, 'test') end)
    Sched.run()
    check('CONCURRENCY craft vs AddItem: no lost update on the shared output stack', db.count(1, 'iron_ingot') == 4 and db.count(1, 'iron_ore') == 0)
    db.interleave = false

    -- different characters never block each other
    inv(db, 1, { { 'pocket-1', 'iron_ore', 2 } }); inv(db, 2, { { 'pocket-1', 'iron_ore', 2 } })
    local a = exec(W, R(98), '1', tx(ingotTx)); local b = exec(W, R(99), '2', tx(ingotTx))
    check('CONCURRENCY different characters are independent', a == true and b == true)
end

-- =================================================================== CACHE / UI
do
    local W, db = freshWorld()
    inv(db, 1, { { 'pocket-1', 'iron_ore', 4 } })
    W.env.GetPlayerPed = function() return 0 end
    W.env.Player = function(src) return { state = { charId = '1' } } end
    exec(W, R(110), '1', tx(ingotTx))
    local updates = 0; for _, e in ipairs(W.events) do if e.name == 'cm-inventory:client:update' and e.src == 7 then updates = updates + 1 end end
    check('UI committed craft refreshes the online character through the normal inventory update path', updates == 1)
    exec(W, R(110), '1', tx(ingotTx))
    updates = 0; for _, e in ipairs(W.events) do if e.name == 'cm-inventory:client:update' then updates = updates + 1 end end
    check('UI a replay does not re-send', updates == 1)
    inv(db, 2, { { 'pocket-1', 'iron_ore', 4 } })
    exec(W, R(111), '2', tx(ingotTx))
    check('OFFLINE offline character settles from the database (no source needed)', db.count(2, 'iron_ingot') == 1)
end


-- =================================================================== ITEM SINK (consume-only, same atomic engine)
do
    local W, db = freshWorld()
    local function sink(ref, cid, items) return call(W, 'ExecuteItemSinkTransaction', ref, cid, items) end
    local function sinkStatus(ref) return call(W, 'GetItemSinkTransactionStatus', ref) end
    local items10 = { { item = 'iron_ore', amount = 10 } }
    inv(db, 1, { { 'pocket-1', 'iron_ore', 6 }, { 'pocket-2', 'iron_ore', 7 }, { 'pocket-3', 'junk1', 1 } })
    W.invoker = 'cm-commercial-ownership'
    local ok, res = sink('SINK-TEST0001', '1', items10)
    check('SINK trusted destination owner accepted; consumes across stacks, creates nothing', ok == true and res.replayed == false and db.count(1, 'iron_ore') == 3 and db.count(1, 'iron_ingot') == 0 and db.count(1, 'junk1') == 1)
    check('SINK ledger row has tx_type item_sink', db.ledger[1] and db.ledger[1].tx_type == 'item_sink')
    local snap = db.fingerprint()
    local ok2, res2 = sink('SINK-TEST0001', '1', items10)
    check('SINK replay returns the committed result and mutates nothing', ok2 == true and res2.replayed == true and db.fingerprint() == snap)
    local ok3, why3 = sink('SINK-TEST0001', '1', { { item = 'iron_ore', amount = 9 } })
    check('SINK same reference + changed payload rejected', ok3 == false and why3 == 'reference_conflict' and db.fingerprint() == snap)
    check('SINK status committed / unknown reference not_applied', sinkStatus('SINK-TEST0001') == 'committed' and sinkStatus('SINK-NEVER0001') == 'not_applied')
    check('SINK insufficient items refused, nothing applied', (function() local a, b = sink('SINK-TEST0002', '1', { { item = 'iron_ore', amount = 4 } }); return a == false and b == 'insufficient_input' and db.count(1, 'iron_ore') == 3 end)())
    check('SINK unknown item / zero amount / empty list / extra fields rejected', (function()
        local a = select(2, sink('SINK-TEST0003', '1', { { item = 'nonexistent', amount = 1 } }))
        local b = select(2, sink('SINK-TEST0004', '1', { { item = 'iron_ore', amount = 0 } }))
        local c = select(2, sink('SINK-TEST0005', '1', {}))
        local d = select(2, sink('SINK-TEST0006', '1', { { item = 'iron_ore', amount = 1, metadata = {} } }))
        return a == 'invalid_item' and b == 'invalid_transaction' and c == 'invalid_transaction' and d == 'invalid_transaction' end)())
    check('SINK cannot create items: an output-shaped line is rejected', (function()
        local a = call(W, 'ExecuteItemSinkTransaction', 'SINK-TEST0007', '1', { { item = 'iron_ore', amount = 1 }, { item = 'iron_ingot', amount = 1, metadata = {} } })
        return a == false and db.count(1, 'iron_ingot') == 0 end)())
    -- trust separation
    W.invoker = 'cm-crafting'
    check('SINK cm-crafting cannot use the sink API', select(2, sink('SINK-TEST0008', '1', { { item = 'iron_ore', amount = 1 } })) == 'forbidden')
    W.invoker = 'cm-commercial-ownership'
    check('SINK cm-commercial-ownership cannot run craft transactions (no minting path)', select(2, exec(W, 'CRAFT-TEST9001', '1', { inputs = { { item = 'iron_ore', amount = 1 } }, outputs = { { item = 'iron_ingot', amount = 3 } } })) == 'forbidden')
    W.invoker = 'cm-evil'
    check('SINK untrusted resource rejected on all three exports', select(2, sink('SINK-TEST0009', '1', { { item = 'iron_ore', amount = 1 } })) == 'forbidden' and select(2, sinkStatus('SINK-TEST0001')) == 'forbidden' and select(2, call(W, 'ValidateItemSinkTransaction', '1', { { item = 'iron_ore', amount = 1 } })) == 'forbidden')
    W.invoker = 'cm-commercial-ownership'
    check('SINK read-only validation', call(W, 'ValidateItemSinkTransaction', '1', { { item = 'iron_ore', amount = 3 } }) == true and select(2, call(W, 'ValidateItemSinkTransaction', '1', { { item = 'iron_ore', amount = 4 } })) == 'insufficient_input')
    -- reference kinds never collide
    W.invoker = 'cm-crafting'
    inv(db, 1, { { 'pocket-1', 'iron_ore', 5 } }); db.ledger = {}
    exec(W, 'CRAFT-SHARED001', '1', tx(ingotTx))
    W.invoker = 'cm-commercial-ownership'
    local ka, kb = sink('CRAFT-SHARED001', '1', { { item = 'iron_ore', amount = 2 } })
    check('SINK a reference already used by a craft transaction is a conflict', ka == false and kb == 'reference_conflict')
    check('SINK status of a craft reference through the sink API is a conflict, never a guess', select(2, sinkStatus('CRAFT-SHARED001')) == 'reference_conflict')
    -- atomicity
    inv(db, 1, { { 'pocket-1', 'iron_ore', 10 } }); db.ledger = {}; db.audit = {}
    local fp = db.fingerprint()
    for i, point in ipairs({ 'begin', 'after_validation', 'after_inputs', 'before_ledger' }) do
        W.env.CMInventory.SetCraftFailpoint(function(name) if name == point then error('inject ' .. point) end end)
        local a, b = sink('SINK-ATOM000' .. i, '1', { { item = 'iron_ore', amount = 4 } })
        W.env.CMInventory.SetCraftFailpoint(nil)
        check('SINK failure at ' .. point .. ' rolls back everything', a == false and b == 'unavailable' and db.fingerprint() == fp)
    end
    local ra, rb = sink('SINK-ATOM0004', '1', { { item = 'iron_ore', amount = 4 } })
    check('SINK retry of a previously rolled-back reference commits once', ra == true and rb.replayed == false and db.count(1, 'iron_ore') == 6 and #db.ledger == 1)
    -- concurrency: two sinks compete for stock for one
    db.interleave = true
    inv(db, 1, { { 'pocket-1', 'iron_ore', 5 } }); db.ledger = {}
    local out = {}
    for i = 1, 2 do Sched.spawn(function() out[i] = { sink('SINK-RACE000' .. i, '1', { { item = 'iron_ore', amount = 4 } }) } end) end
    Sched.run()
    db.interleave = false
    check('SINK two references compete for stock for one: exactly one wins, no negative stock', ((out[1][1] == true) ~= (out[2][1] == true)) and db.count(1, 'iron_ore') == 1)
end

-- ===================================================================================================================
-- PAID-GOODS GRANT (ExecuteItemGrant / GetItemGrantStatus / CancelItemGrant) -- cm-gasstations
do
    local W, db = freshWorld()
    local function grant(ref, cid, items) return call(W, 'ExecuteItemGrant', ref, cid, items) end
    local function gstatus(ref) return call(W, 'GetItemGrantStatus', ref) end
    local function cancel(ref, cid) return call(W, 'CancelItemGrant', ref, cid) end
    local KITS = { { item = 'repair_kit', amount = 2 }, { item = 'wash_kit', amount = 1 } }
    W.invoker = 'cm-evil'
    check('GRANT untrusted resource rejected on all three exports', select(2, grant('GRANT-TEST0001', '1', KITS)) == 'forbidden' and select(2, gstatus('GRANT-TEST0001')) == 'forbidden' and select(2, cancel('GRANT-TEST0001', '1')) == 'forbidden')
    W.invoker = 'cm-crafting'
    check('GRANT cm-crafting is not a grant caller (no output-from-nothing for crafting)', select(2, grant('GRANT-TEST0001', '1', KITS)) == 'forbidden')
    W.invoker = 'cm-gasstations'
    inv(db, 1, {}); db.ledger = {}
    local ok, res = grant('GRANT-TEST0001', '1', KITS)
    check('GRANT delivers all lines atomically and records the ledger', ok == true and res.replayed == false and db.count(1, 'repair_kit') == 2 and db.count(1, 'wash_kit') == 1 and #db.ledger == 1 and db.ledger[1].tx_type == 'item_grant')
    check('GRANT status committed / unknown reference not_applied', gstatus('GRANT-TEST0001') == 'committed' and gstatus('GRANT-NEVER0001') == 'not_applied')
    local ok2, res2 = grant('GRANT-TEST0001', '1', KITS)
    check('GRANT replay of the same reference delivers NOTHING more', ok2 == true and res2.replayed == true and db.count(1, 'repair_kit') == 2 and #db.ledger == 1)
    local _, why = grant('GRANT-TEST0001', '1', { { item = 'repair_kit', amount = 3 } })
    check('GRANT same reference with a changed payload is a conflict', why == 'reference_conflict' and db.count(1, 'repair_kit') == 2)
    _, why = grant('GRANT-TEST0001', '2', KITS)
    check('GRANT same reference for another character is a conflict', why == 'reference_conflict')
    local ca, cb = cancel('GRANT-TEST0001', '1')
    check('CANCEL of a delivered grant is refused: the caller must treat it as delivered', ca == false and cb == 'already_committed' and gstatus('GRANT-TEST0001') == 'committed' and db.count(1, 'repair_kit') == 2)
    ca, cb = cancel('GRANT-TEST0002', '1')
    check('CANCEL of an unseen reference fences it permanently', ca == true and cb == 'cancelled' and gstatus('GRANT-TEST0002') == 'cancelled')
    local ga, gb = grant('GRANT-TEST0002', '1', KITS)
    check('GRANT after CANCEL is a definite refusal and delivers nothing (no late delivery after a refund)', ga == false and gb == 'cancelled' and db.count(1, 'repair_kit') == 2)
    ca, cb = cancel('GRANT-TEST0002', '1')
    check('CANCEL is idempotent', ca == true and cb == 'cancelled')
    ca, cb = cancel('GRANT-TEST0002', '2')
    check('CANCEL of a reference fenced for another character is a conflict', ca == false and cb == 'reference_conflict')
    inv(db, 1, { { 'pocket-1', 'iron_ore', 5 } })
    W.invoker = 'cm-crafting'
    exec(W, 'CRAFT-SHARED002', '1', tx({ inputs = { { item = 'iron_ore', amount = 2 } }, outputs = { { item = 'iron_ingot', amount = 1 } } }))
    W.invoker = 'cm-gasstations'
    ca, cb = cancel('CRAFT-SHARED002', '1')
    check('CANCEL a craft-type reference through the grant API is a conflict', ca == false and cb == 'reference_conflict')
    local pa, pb = grant('GRANT-TEST0003', '1', { { item = 'weapon_pistol', amount = 1 } })
    check('GRANT outputs follow the craft output policy (no weapons/unique); nothing written', pa == false and pb == 'invalid_item' and gstatus('GRANT-TEST0003') == 'not_applied')
    pa, pb = grant('GRANT-TEST0004', '1', {})
    check('GRANT with no lines is rejected', pa == false and pb == 'invalid_transaction')
    pa, pb = grant('GRANT-TEST0006', '1', { { item = 'repair_kit', amount = 1, extra = true } })
    check('GRANT unknown line fields rejected', pa == false and pb == 'invalid_transaction')
    inv(db, 1, { { 'pocket-1', 'heavy_box', 1 } }); db.ledger = {}
    local fa, fb = grant('GRANT-TEST0007', '1', { { item = 'heavy_box', amount = 5 } })
    check('GRANT no capacity is a DEFINITE failure: nothing applied, reference still not_applied', fa == false and fb == 'no_capacity' and gstatus('GRANT-TEST0007') == 'not_applied' and #db.ledger == 0)
    inv(db, 1, {}); db.ledger = {}; db.audit = {}
    local fp = db.fingerprint()
    for i, point in ipairs({ 'begin', 'after_validation', 'before_outputs', 'before_ledger' }) do
        W.env.CMInventory.SetCraftFailpoint(function(name) if name == point then error('inject ' .. point) end end)
        local a, b = grant('GRANT-ATOM000' .. i, '1', KITS)
        W.env.CMInventory.SetCraftFailpoint(nil)
        check('GRANT failure at ' .. point .. ' rolls back everything (unknown outcome, status not committed)', a == false and b == 'unavailable' and db.fingerprint() == fp and gstatus('GRANT-ATOM000' .. i) == 'not_applied')
    end
    local ra, rb = grant('GRANT-ATOM0004', '1', KITS)
    check('GRANT retry of a rolled-back reference commits exactly once', ra == true and rb.replayed == false and db.count(1, 'repair_kit') == 2 and #db.ledger == 1)
    inv(db, 1, {}); db.ledger = {}
    W.env.CMInventory.SetCraftFailpoint(function(name) if name == 'after_ledger' then error('inject after_ledger') end end)
    local aa, ab = grant('GRANT-LATE0001', '1', KITS)
    W.env.CMInventory.SetCraftFailpoint(nil)
    check('GRANT status after an ambiguous failure is authoritative, never guessed', (aa == true or ab == 'unavailable') and ((gstatus('GRANT-LATE0001') == 'committed') == (db.count(1, 'repair_kit') == 2)))
    db.interleave = true
    local ok_race = true
    for i = 1, 12 do
        inv(db, 1, {}); db.ledger = {}
        local ref = ('GRANT-RACE%04d'):format(i)
        local out = {}
        Sched.spawn(function() out.g = { grant(ref, '1', KITS) } end)
        Sched.spawn(function() out.c = { cancel(ref, '1') } end)
        Sched.run()
        local delivered = db.count(1, 'repair_kit') == 2
        local st = gstatus(ref)
        if delivered then ok_race = ok_race and st == 'committed' and out.g[1] == true and out.c[1] == false and out.c[2] == 'already_committed'
        else ok_race = ok_race and st == 'cancelled' and out.g[1] == false and out.g[2] == 'cancelled' and out.c[1] == true end
    end
    db.interleave = false
    check('GRANT vs CANCEL race (12 interleavings): delivered+cancel refused, or fenced+grant refused; never both, never neither', ok_race)
end


-- ===================================================================================================================
-- GRANT CALLER POLICY (cm-store / nv_cloth / cm-gasstations)
do
    local W, db = freshWorld()
    local function grant(ref, cid, items) return call(W, 'ExecuteItemGrant', ref, cid, items) end
    local function gstatus(ref) return call(W, 'GetItemGrantStatus', ref) end
    local function cancel(ref, cid) return call(W, 'CancelItemGrant', ref, cid) end
    local PANTS = { { item = 'clothing_pants', amount = 1, metadata = { drawableId = 5, textureId = 2, categoryType = 'pants', gender = 'male' } } }
    inv(db, 1, {}); db.ledger = {}
    for _, who in ipairs({ 'cm-gasstations', 'cm-store', 'nv_cloth' }) do
        W.invoker = who
        local ok = grant('POLICY-OK-' .. who:gsub('[^%w]', ''), '1', { { item = 'iron_ore', amount = 1 } })
        check('POLICY ' .. who .. ' is a trusted grant caller', ok == true)
    end
    W.invoker = 'cm-store'
    local a, b = grant('POLICY-STORE-CLOTH1', '1', PANTS)
    check('POLICY cm-store cannot grant clothing', a == false and b == 'invalid_item' and gstatus('POLICY-STORE-CLOTH1') == 'not_applied')
    W.invoker = 'cm-gasstations'
    a, b = grant('POLICY-GAS-CLOTH0001', '1', PANTS)
    check('POLICY cm-gasstations cannot grant clothing', a == false and b == 'invalid_item')
    W.invoker = 'nv_cloth'
    a, b = grant('POLICY-NV-CLOTH00001', '1', PANTS)
    check('POLICY nv_cloth can grant clothing garments with metadata', a == true and db.count(1, 'clothing_pants') >= 1)
    a, b = grant('POLICY-NV-WEAPON0001', '1', { { item = 'weapon_pistol', amount = 1 } })
    check('POLICY nv_cloth cannot grant weapons / unique items', a == false and b == 'invalid_item')
    W.invoker = 'cm-evil'
    check('POLICY a resource outside the allowlist is forbidden on all three grant exports', select(2, grant('POLICY-EVIL-000001', '1', PANTS)) == 'forbidden' and select(2, gstatus('POLICY-EVIL-000001')) == 'forbidden' and select(2, cancel('POLICY-EVIL-000001', '1')) == 'forbidden')
    -- limits: 12 lines refused for the default policy (8), accepted for cm-store (24)
    local lines = {}
    for i = 1, 12 do lines[i] = { item = 'iron_ore', amount = 1 } end
    W.invoker = 'cm-gasstations'
    a, b = grant('POLICY-LINES-0000001', '1', lines)
    check('POLICY default grant limit is 8 lines', a == false and b == 'invalid_transaction')
    W.invoker = 'cm-store'
    a, b = grant('POLICY-LINES-0000002', '1', lines)
    check('POLICY cm-store may grant a larger cart (24 lines)', a == true)
    local huge = {}
    for i = 1, 25 do huge[i] = { item = 'iron_ore', amount = 1 } end
    a, b = grant('POLICY-LINES-0000003', '1', huge)
    check('POLICY cm-store limit is still bounded (25 lines refused)', a == false and b == 'invalid_transaction')
end

print(('\ncm-inventory craft self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
