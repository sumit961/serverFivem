-- Deterministic crash/recovery self-test for the item-exchange ledger lifecycle (prepared -> committed | not_applied) in server/exchange.lua.
--   lua tests/exchange_recovery_selftest.lua        (run from resources/[core]/cm-inventory)
-- REAL: the production inventory chunk. DOUBLES: FiveM runtime, SQL layer (in-memory, transactional undo, InnoDB-style ledger row locks), cm-items surface.
-- In-flight calls are held with failpoints + a cooperative scheduler (no sleeps, no wall-clock races); lease expiry uses a controllable clock.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local H = dofile(here .. '/tests/craft_harness.lua')(here)
local Sched, newDb, newWorld, ITEMS, ser = H.Sched, H.newDb, H.newWorld, H.ITEMS, H.ser
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
ITEMS.water = { weight = 500 }; ITEMS.sandwich = { weight = 350 }

local function world()
    local db = newDb(); for c = 1, 3 do db.addChar(c) end
    local W = newWorld(db)
    W.invoker = 'cm-trade'
    W.clock = os.time()
    W.env.os = setmetatable({ time = function() return W.clock end }, { __index = os })
    db.give(1, 'pocket-1', 'water', 10); db.give(2, 'pocket-1', 'sandwich', 4)
    return W, db
end
local function reg(W, name, ...) W.invoker = 'cm-trade'; return W.registry[name](...) end
local function snapRow(W, cid, item) for _, r in ipairs(reg(W, 'GetTradeSnapshot', cid)) do if r.item == item then return r end end end
local function sides(W, qa, qb)
    local a, b = snapRow(W, 1, 'water'), snapRow(W, 2, 'sandwich')
    return { characterId = 1, lines = { { ref = a.ref, quantity = qa or 3, fp = a.fp } } }, { characterId = 2, lines = { { ref = b.ref, quantity = qb or 2, fp = b.fp } } }
end
local function items(db) return ser({ db.inventory_items, #db.audit }) end
local function count(db, cid, item) return db.count(cid, item) end
local function ledgerOf(db, ref) for _, r in ipairs(db.ledger) do if r.reference == ref then return r end end end
local function R(n) return ('TRD-REC%05d'):format(n) end
local function pump(n) for _ = 1, n do coroutine.yield() end end

-- holds the transaction at a named failpoint until `gate.open`
local function hold(W, point, gate)
    W.env.CMInventory.SetCraftFailpoint(function(name)
        if name == point and not gate.open then gate.reached = true; while not gate.open do coroutine.yield() end end
    end)
end

-- ======================================================================= ORIGINAL RACE (inventory side)
do
    local W, db = world(); local sa, sb = sides(W)
    local gate = { open = false }
    hold(W, 'exchange_after_lock_both', gate)
    local res
    Sched.spawn(function() res = { reg(W, 'ExecuteItemExchange', R(1), sa, sb) } end)
    local probe = {}
    Sched.spawn(function()
        pump(3)
        probe.reached = gate.reached
        probe.status = reg(W, 'GetItemExchangeStatus', R(1))                       -- in flight
        probe.fence = reg(W, 'FenceItemExchange', R(1))                            -- live lease: must NOT declare not_applied
        probe.dup, probe.dupWhy = reg(W, 'ExecuteItemExchange', R(1), sa, sb)      -- a second executor must not run
        probe.itemsDuring = count(db, 1, 'water')
        gate.open = true
    end)
    Sched.run()
    check('RACE exchange is held in flight at the item transaction', probe.reached == true)
    check('RACE while in flight: status is pending (never not_applied)', probe.status == 'pending', probe.status)
    check('RACE while in flight: fencing a live lease refuses to declare not_applied', probe.fence == 'pending', probe.fence)
    check('RACE while in flight: a second execute of the same reference does not run', probe.dup == false and probe.dupWhy == 'pending')
    check('RACE no item moved while in flight', probe.itemsDuring == 10)
    check('RACE the held exchange then commits exactly once', res[1] == true and res[2].replayed == false and count(db, 1, 'water') == 7 and count(db, 2, 'water') == 3)
    check('RACE status committed afterwards and fence agrees', reg(W, 'GetItemExchangeStatus', R(1)) == 'committed' and reg(W, 'FenceItemExchange', R(1)) == 'committed')
    W.env.CMInventory.SetCraftFailpoint(nil)
end

-- ======================================================================= ZOMBIE EXECUTOR vs FENCE (lease expired, executor still alive)
do
    local W, db = world(); local sa, sb = sides(W)
    local gate = { open = false }
    hold(W, 'exchange_after_lock_both', gate)       -- held BEFORE the ledger row is re-checked
    local res, fenced
    Sched.spawn(function() res = { reg(W, 'ExecuteItemExchange', R(2), sa, sb) } end)
    Sched.spawn(function()
        pump(3)
        W.clock = W.clock + 3600                     -- lease long expired, executor is merely slow
        fenced = reg(W, 'FenceItemExchange', R(2))
        gate.open = true
    end)
    Sched.run()
    check('ZOMBIE stale lease fenced to terminal not_applied', fenced == 'not_applied', fenced)
    check('ZOMBIE the late executor cannot commit (lost lease): nothing moved, answer not_applied', res[1] == false and res[2] == 'not_applied' and count(db, 1, 'water') == 10 and count(db, 2, 'sandwich') == 4, tostring(res[2]))
    check('ZOMBIE ledger is terminal and a fresh execute is refused', ledgerOf(db, R(2)).status == 'not_applied' and select(2, reg(W, 'ExecuteItemExchange', R(2), sa, sb)) == 'not_applied' and count(db, 1, 'water') == 10)
    W.env.CMInventory.SetCraftFailpoint(nil)
end

-- ======================================================================= FENCE vs COMMIT inside the transaction (ledger row lock)
do
    local W, db = world(); local sa, sb = sides(W)
    local gate = { open = false }
    hold(W, 'exchange_after_validation', gate)      -- AFTER the ledger row was locked FOR UPDATE
    local res, fenced
    Sched.spawn(function() res = { reg(W, 'ExecuteItemExchange', R(3), sa, sb) } end)
    Sched.spawn(function()
        pump(3)
        W.clock = W.clock + 3600
        Sched.spawn(function() fenced = reg(W, 'FenceItemExchange', R(3)) end)   -- queues behind the row lock
        pump(5)
        gate.open = true
    end)
    Sched.run()
    check('LOCK fence queued behind the committing transaction observes committed, never not_applied', fenced == 'committed', fenced)
    check('LOCK exchange committed exactly once', res[1] == true and count(db, 1, 'water') == 7 and #db.ledger == 1 and ledgerOf(db, R(3)).status == 'committed')
    W.env.CMInventory.SetCraftFailpoint(nil)
end

-- ======================================================================= ABANDONED PENDING (executor vanished before mutation)
do
    local W, db = world(); local sa, sb = sides(W)
    W.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_claim' then error('executor crashed after claim') end end)
    local okCall = pcall(function() reg(W, 'ExecuteItemExchange', R(4), sa, sb) end)
    W.env.CMInventory.SetCraftFailpoint(nil)
    check('ABANDONED executor vanished after the durable claim, before any mutation', okCall == false and ledgerOf(db, R(4)).status == 'prepared' and count(db, 1, 'water') == 10)
    check('ABANDONED status is pending (not not_applied) and the lease still protects it', reg(W, 'GetItemExchangeStatus', R(4)) == 'pending')
    local ok1, why1 = reg(W, 'ExecuteItemExchange', R(4), sa, sb)
    check('ABANDONED an immediate retry does not steal a live lease', ok1 == false and why1 == 'pending' and count(db, 1, 'water') == 10)
    check('ABANDONED same reference with a changed payload is a conflict', (function() local a5, b5 = sides(W, 5); return select(2, reg(W, 'ExecuteItemExchange', R(4), a5, b5)) == 'reference_conflict' end)())
    W.clock = W.clock + 3600
    check('ABANDONED status stays pending until someone acts (no time-based guess)', reg(W, 'GetItemExchangeStatus', R(4)) == 'pending')
    local ok2, res2 = reg(W, 'ExecuteItemExchange', R(4), sa, sb)
    check('ABANDONED stale lease reclaimed and the SAME reference re-executes exactly once', ok2 == true and res2.replayed == false and count(db, 1, 'water') == 7 and count(db, 2, 'water') == 3 and #db.ledger == 1)
    check('ABANDONED replay after the reclaim mutates nothing', (function() local s = items(db); local ok3, r3 = reg(W, 'ExecuteItemExchange', R(4), sa, sb); return ok3 == true and r3.replayed == true and items(db) == s end)())
end

-- ======================================================================= TWO RECLAIMERS race for an expired lease
do
    local W, db = world(); local sa, sb = sides(W)
    W.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_claim' and not W.crashDone then W.crashDone = true; error('crash') end end)
    pcall(function() reg(W, 'ExecuteItemExchange', R(5), sa, sb) end)
    W.env.CMInventory.SetCraftFailpoint(nil)
    W.clock = W.clock + 3600
    db.interleave = true
    local rr = {}
    for i = 1, 3 do Sched.spawn(function() rr[i] = { reg(W, 'ExecuteItemExchange', R(5), sa, sb) } end) end
    Sched.run(); db.interleave = false
    local applied = 0
    for _, x in ipairs(rr) do if x[1] == true and x[2].replayed == false then applied = applied + 1 end end
    check('RECLAIM three simultaneous recovery workers: exactly one commit, items moved once', applied == 1 and count(db, 1, 'water') == 7 and count(db, 2, 'water') == 3 and #db.ledger == 1)
end

-- ======================================================================= DEFINITELY NOT APPLIED
do
    local W, db = world(); local sa, sb = sides(W)
    local bad = { characterId = 1, lines = { { ref = sa.lines[1].ref, quantity = 3, fp = '0123456789abcdef' } } }
    local s0 = items(db)
    local ok, why = reg(W, 'ExecuteItemExchange', R(6), bad, sb)
    check('NOT_APPLIED a definite rejection (item_changed) moves nothing', ok == false and why == 'item_changed' and items(db) == s0)
    check('NOT_APPLIED the owner records it as terminal', reg(W, 'GetItemExchangeStatus', R(6)) == 'not_applied' and ledgerOf(db, R(6)).status == 'not_applied')
    local ok2, why2 = reg(W, 'ExecuteItemExchange', R(6), sa, sb)
    check('NOT_APPLIED a later (now valid) execute under the same reference can never commit', ok2 == false and why2 == 'not_applied' and items(db) == s0)
    W.clock = W.clock + 3600
    check('NOT_APPLIED terminal state is permanent (fence agrees, no revival after time passes)', reg(W, 'FenceItemExchange', R(6)) == 'not_applied' and select(2, reg(W, 'ExecuteItemExchange', R(6), sa, sb)) == 'not_applied')
    -- fencing a reference that was never submitted (cash debited, exchange never reached the inventory)
    check('NOT_APPLIED a never-submitted reference reports not_submitted (NOT a proof)', reg(W, 'GetItemExchangeStatus', R(7)) == 'not_submitted')
    check('NOT_APPLIED fence turns it into a permanent not_applied', reg(W, 'FenceItemExchange', R(7)) == 'not_applied' and reg(W, 'GetItemExchangeStatus', R(7)) == 'not_applied')
    local ok3, why3 = reg(W, 'ExecuteItemExchange', R(7), sa, sb)
    check('NOT_APPLIED a late in-flight execute after the fence is refused (the RPC that was still queued)', ok3 == false and why3 == 'not_applied' and items(db) == s0)
    check('NOT_APPLIED other references are unaffected', (reg(W, 'ExecuteItemExchange', R(8), sa, sb)) == true and count(db, 1, 'water') == 7)
    -- dependency down during planning is not a property of the exchange: not terminal
    local W2, db2 = world(); local a2, b2 = sides(W2)
    W2.itemsDown = true
    local okD, whyD = reg(W2, 'ExecuteItemExchange', R(9), a2, b2)
    W2.itemsDown = false
    check('NOT_APPLIED cm-items outage during planning: unavailable, nothing moved, NOT terminal', okD == false and whyD == 'unavailable' and ledgerOf(db2, R(9)).status == 'prepared')
    check('NOT_APPLIED ... and a retry then commits', (reg(W2, 'ExecuteItemExchange', R(9), a2, b2)) == true and count(db2, 1, 'water') == 7)
end

-- ======================================================================= RESPONSE LOST AFTER DB COMMIT
do
    local W, db = world(); local sa, sb = sides(W)
    W.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_commit' then error('response lost') end end)
    local ok1, r1 = reg(W, 'ExecuteItemExchange', R(10), sa, sb)
    W.env.CMInventory.SetCraftFailpoint(nil)
    check('RESPONSE LOSS committed in the database, caller error: still answers committed', ok1 == true and r1.replayed == true and count(db, 1, 'water') == 7 and reg(W, 'GetItemExchangeStatus', R(10)) == 'committed')
    local W2 = newWorld(db); W2.invoker = 'cm-trade'
    check('RESTART the committed state survives a restart and replays without a second exchange', (function() local s = items(db); local ok, r = W2.registry.ExecuteItemExchange(R(10), sa, sb); return ok == true and r.replayed == true and items(db) == s end)())
end

-- ======================================================================= ERROR inside the transaction (rolled back): ambiguous -> pending, then safe retry
do
    local W, db = world(); local sa, sb = sides(W)
    W.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_adds' then error('injected') end end)
    local ok1, why1 = reg(W, 'ExecuteItemExchange', R(11), sa, sb)
    W.env.CMInventory.SetCraftFailpoint(nil)
    check('ERROR rolled back transaction: unavailable, nothing moved, status pending', ok1 == false and why1 == 'unavailable' and count(db, 1, 'water') == 10 and reg(W, 'GetItemExchangeStatus', R(11)) == 'pending')
    check('ERROR retry of the same reference commits exactly once', (reg(W, 'ExecuteItemExchange', R(11), sa, sb)) == true and count(db, 1, 'water') == 7 and #db.ledger == 1)
end

-- ======================================================================= TRUST + legacy ledgers
do
    local W, db = world(); local sa, sb = sides(W)
    W.invoker = 'cm-evil'
    check('TRUST fence/status/execute are cm-trade only', select(2, W.registry.FenceItemExchange(R(12))) == 'forbidden' and select(2, W.registry.GetItemExchangeStatus(R(12))) == 'forbidden' and select(2, W.registry.ExecuteItemExchange(R(12), sa, sb)) == 'forbidden' and #db.ledger == 0)
    W.invoker = 'cm-trade'
    check('TRUST malformed reference rejected by fence', select(2, W.registry.FenceItemExchange('x')) == 'invalid_reference')
    W.invoker = 'cm-crafting'
    W.registry.ExecuteCraftTransaction('CRAFT-REC00001', '1', { inputs = { { item = 'water', amount = 1 } } })
    W.invoker = 'cm-trade'
    check('LEGACY a craft ledger reference is a conflict through fence/status', select(2, W.registry.FenceItemExchange('CRAFT-REC00001')) == 'reference_conflict' and select(2, W.registry.GetItemExchangeStatus('CRAFT-REC00001')) == 'reference_conflict')
    db.ledger[#db.ledger + 1] = { reference = R(13), tx_type = 'trade_exchange', character_id = '1', payload_hash = 'x', payload = 'old', status = 'committed', result_json = '{}' }
    check('LEGACY a pre-existing committed exchange row is still readable', reg(W, 'GetItemExchangeStatus', R(13)) == 'committed' and reg(W, 'FenceItemExchange', R(13)) == 'committed')
end

print(('cm-inventory exchange recovery self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
