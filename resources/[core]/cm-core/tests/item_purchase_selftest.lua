-- Deterministic self-test for cm-core/shared/item_purchase.lua (cm-store, nv_cloth purchase settlement).
--   lua tests/item_purchase_selftest.lua        (run from resources/[core]/cm-core)
-- REAL: the state machine (resolve / run / recover, delivery decision, refund, terminal logic).
-- TEST DOUBLES (labelled): money owner, inventory grant ledger (incl. the CancelItemGrant fence), and the journal SQL with the same guards
-- as the real statements. The REAL money-op and inventory-grant implementations are exercised in tests/purchase_integration.lua, and the real
-- SQL in tests/item_purchase_mysql_smoke.py.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

CMItemPurchase = nil
dofile(here .. '/shared/item_purchase.lua')
local P = CMItemPurchase

local function newWorld()
    local W = { cash = { [1] = 5000 }, bank = { [1] = 9000 }, ops = {}, ledger = {}, inv = {}, rows = {},
        store = { stock = 100, owner = 7, balance = 0, daily = 0, weekly = 0 }, CAP = 8000,
        hooks = {}, inject = {}, calls = { debit = 0, credit = 0, grant = 0, cancel = 0 } }
    function W.at(name) local h = W.hooks[name]; if h then W.hooks[name] = nil; h() end end
    local function acct(a) return a == 'cash' and W.cash or W.bank end

    local money = {}
    function money.debit(ref, cid, account, amount)
        W.calls.debit = W.calls.debit + 1
        W.at('before_debit')
        if W.inject.debit == 'down' then return false, 'unavailable' end
        if W.ops[ref] then return true, 'replayed' end
        if (acct(account)[cid] or 0) < amount then return false, 'insufficient_funds' end
        acct(account)[cid] = acct(account)[cid] - amount
        W.ops[ref] = { status = 'committed', direction = 'debit', account = account, amount = amount }
        if W.inject.debit == 'lose' then return false, 'unavailable' end
        W.at('after_debit')
        return true, 'applied'
    end
    function money.credit(ref, cid, account, amount)
        W.calls.credit = W.calls.credit + 1
        if W.inject.credit == 'down' then return false, 'unavailable' end
        if W.ops[ref] then return (W.ops[ref].amount == amount), 'replayed' end
        acct(account)[cid] = (acct(account)[cid] or 0) + amount
        W.ops[ref] = { status = 'committed', direction = 'credit', account = account, amount = amount }
        if W.inject.credit == 'lose' then return false, 'unavailable' end
        return true, 'applied'
    end
    function money.status(ref)
        if W.inject.moneyStatus == 'down' then return nil end
        return W.ops[ref] or false
    end

    local items = {}
    function items.grant(ref, cid, lines)
        W.calls.grant = W.calls.grant + 1
        W.at('before_grant')
        if W.inject.grant == 'down' then return false, 'unavailable' end
        local l = W.ledger[ref]
        if l == 'cancelled' then return false, 'cancelled' end
        if l == 'committed' then return true end
        -- ALL-OR-NOTHING: any bad line (or no capacity) refuses the whole cart
        for _, line in ipairs(lines) do
            if W.inject.badLine == line.item then return false, 'invalid_item' end
        end
        if W.inject.grant == 'no_capacity' then return false, 'no_capacity' end
        W.inv[cid] = W.inv[cid] or {}
        for _, line in ipairs(lines) do W.inv[cid][line.item] = (W.inv[cid][line.item] or 0) + line.amount end
        W.ledger[ref] = 'committed'
        if W.inject.grant == 'lose' then return false, 'unavailable' end
        W.at('after_grant')
        return true
    end
    function items.status(ref)
        if W.inject.itemStatus == 'down' then return 'unknown' end
        return W.ledger[ref] or 'not_applied'
    end
    function items.cancel(ref)
        W.calls.cancel = W.calls.cancel + 1
        if W.inject.cancel == 'down' then return false, 'unavailable' end
        if W.ledger[ref] == 'committed' then return false, 'already_committed' end
        W.ledger[ref] = 'cancelled'
        return true, 'cancelled'
    end

    local db = {}
    local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
    function db.insert(o)
        if W.inject.dbInsert then return nil end
        if W.rows[o.reference] then return false end
        local r = copy(o); r.state = 'pending'; r.reserved_units = 0; r.items_state = 'pending'
        W.rows[o.reference] = r
        return true
    end
    function db.get(ref) if W.inject.dbGet then return nil end local r = W.rows[ref]; return r and copy(r) or false end
    function db.reserve(ref, scope, units)
        if W.inject.dbReserve then return nil end
        local r, s = W.rows[ref], W.store
        if r and r.state == 'pending' and r.reserved_units == 0 and s.stock >= units then s.stock = s.stock - units; r.reserved_units = units; return true end
        return false
    end
    function db.setItems(ref, to)
        local r = W.rows[ref]
        if r and r.state == 'pending' and r.items_state == 'pending' then r.items_state = to; return true end
        return false
    end
    function db.finalize(ref, state, refund, release, share)
        W.at('before_finalize')
        if W.inject.dbFinalize then return nil end
        local r, s = W.rows[ref], W.store
        if not r or r.state ~= 'pending' then return false end
        r.state, r.refund_amount = state, refund
        s.stock = math.min(W.CAP, s.stock + release)
        if s.owner then s.balance = s.balance + share; s.daily = s.daily + share; s.weekly = s.weekly + share end
        return true
    end
    function db.stale() local out = {} for ref, r in pairs(W.rows) do if r.state == 'pending' then out[#out + 1] = ref end end table.sort(out) return out end

    W.deps = { db = db, money = money, items = items, log = function() end }
    function W.engine() return P.new(W.deps) end
    return W
end

local seq = 0
local function order(over)
    seq = seq + 1
    local o = { reference = ('STORE-PUR-1-%04d'):format(seq), character_id = 1, scope_id = 1, account = 'bank', total = 70, units = 5, owner_pct = 80,
        items = { { item = 'water', amount = 3 }, { item = 'sandwich', amount = 2 } } }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
end
local function boom() error('simulated exception') end
local function opcount(W) local n = 0 for _ in pairs(W.ops) do n = n + 1 end return n end
local function holdings(W) local n = 0 for _, items in pairs(W.inv) do for _, q in pairs(items) do n = n + q end end return n end

-- NORMAL
do
    local W = newWorld(); local o = order(); local r = W.engine().run(o)
    check('NORMAL completes: all cart lines delivered in one grant', r.code == 'completed' and r.delivered and r.paid == 70 and W.inv[1].water == 3 and W.inv[1].sandwich == 2 and W.calls.grant == 1, r.code)
    check('NORMAL charged exactly once from the chosen account only', W.bank[1] == 9000 - 70 and W.cash[1] == 5000 and W.calls.debit == 1 and W.calls.credit == 0)
    check('NORMAL stock consumed (100 -> 95), nothing released; owner share 80% credited once', W.store.stock == 95 and W.store.balance == 56 and W.rows[o.reference].state == 'completed')
    local again = W.engine().resolve(o.reference)
    check('NORMAL re-resolve of a terminal order changes nothing', again.code == 'completed' and W.store.stock == 95 and W.store.balance == 56 and W.bank[1] == 8930)
    local W2 = newWorld(); local r2 = W2.engine().run(order({ account = 'cash' }))
    check('NORMAL cash purchase debits cash', r2.code == 'completed' and W2.cash[1] == 5000 - 70 and W2.bank[1] == 9000)
end

-- PAYMENT FAILURE
do
    local W = newWorld(); W.bank[1] = 10; local o = order(); local r = W.engine().run(o)
    check('PAYMENT-FAIL: payment_failed, stock restored, no grant, no charge, no refund', r.code == 'payment_failed' and r.reason == 'insufficient_funds' and W.store.stock == 100 and holdings(W) == 0 and W.bank[1] == 10 and W.calls.credit == 0)
    check('PAYMENT-FAIL journal terminal (compensated) and grant fenced', W.rows[o.reference].state == 'compensated' and W.ledger[o.reference] == 'cancelled')
end

-- DELIVERY DEFINITIVE FAILURE / PARTIAL CART
do
    local W = newWorld(); W.inject.grant = 'no_capacity'; local o = order(); local r = W.engine().run(o)
    check('DELIVERY-FAIL after payment: compensated, full refund once, stock restored once', r.code == 'compensated' and r.refunded and r.refund == 70 and W.bank[1] == 9000 and W.store.stock == 100 and W.calls.credit == 1 and W.store.balance == 0)
    check('DELIVERY-FAIL grant fenced, nothing delivered, a late grant can never land', holdings(W) == 0 and select(2, W.deps.items.grant(o.reference, 1, o.items)) == 'cancelled' and holdings(W) == 0)
    local W2 = newWorld(); W2.inject.badLine = 'sandwich'; local o2 = order(); local r2 = W2.engine().run(o2)
    check('PARTIAL CART: one bad line => ZERO lines delivered, full refund, stock back (no kept items + restored stock)', r2.code == 'compensated' and holdings(W2) == 0 and W2.bank[1] == 9000 and W2.store.stock == 100 and r2.refund == 70)
end

-- EXCEPTION BEFORE DELIVERY (critical)
do
    local W = newWorld(); local o = order(); W.hooks.after_debit = boom
    local r = W.engine().run(o)
    check('EXC-AFTER-PAYMENT-BEFORE-DELIVERY ends compensated: customer made whole exactly once', r.code == 'compensated' and r.refund == 70 and W.bank[1] == 9000 and W.calls.credit == 1 and opcount(W) == 2)
    check('EXC-AFTER-PAYMENT stock restored once, no revenue, nothing delivered, late grant fenced', W.store.stock == 100 and W.store.balance == 0 and holdings(W) == 0 and W.ledger[o.reference] == 'cancelled')
    local W2 = newWorld(); local o2 = order(); W2.hooks.before_grant = boom
    local r2 = W2.engine().run(o2)
    check('EXC immediately before grant: same (refund once, stock once)', r2.code == 'compensated' and W2.bank[1] == 9000 and W2.store.stock == 100 and holdings(W2) == 0)
    local W3 = newWorld(); local o3 = order(); W3.hooks.after_debit = nil
    local W4 = newWorld(); local o4 = order(); local r4
    W4.inject.dbReserve = true; r4 = W4.engine().run(o4)
    check('EXC/unknown right after reserve attempt: no charge attempted, journal closed', r4.code == 'unavailable' and W4.calls.debit == 0 and W4.bank[1] == 9000)
end

-- EXCEPTION AFTER DELIVERY
do
    local W = newWorld(); local o = order(); W.hooks.after_grant = boom
    local r = W.engine().run(o)
    check('EXC-AFTER-DELIVERY reconciles to success: no refund, no stock release, no redelivery', r.code == 'completed' and r.delivered and r.refund == 0 and W.calls.credit == 0 and W.store.stock == 95 and W.calls.grant == 1 and W.inv[1].water == 3 and W.bank[1] == 8930, r.code)
    check('EXC-AFTER-DELIVERY revenue credited once', W.store.balance == 56)
end

-- RESPONSE LOSS
do
    local W = newWorld(); W.inject.debit = 'lose'; local r = W.engine().run(order())
    check('DEBIT response lost (committed): proceeds, single debit', r.code == 'completed' and W.calls.debit == 1 and W.bank[1] == 8930)
    local W2 = newWorld(); W2.inject.debit = 'down'; local o2 = order(); local r2 = W2.engine().run(o2)
    check('DEBIT unavailable (never applied): compensated, nothing to refund', r2.code == 'payment_failed' and W2.calls.credit == 0 and W2.bank[1] == 9000 and W2.store.stock == 100)
    local W3 = newWorld(); W3.inject.debit = 'lose'; W3.inject.moneyStatus = 'down'; local o3 = order(); local S3 = W3.engine(); local r3 = S3.run(o3)
    check('DEBIT unknown (answer lost, ledger unreachable): pending, no delivery, stock held, no refund guess', r3.code == 'pending' and holdings(W3) == 0 and W3.store.stock == 95 and W3.calls.credit == 0)
    W3.inject.moneyStatus = nil; local rec = S3.recover(0)
    check('DEBIT unknown recovered once ledger answers: charged -> compensated, refund once, stock back', rec.compensated == 1 and W3.bank[1] == 9000 and W3.store.stock == 100 and W3.calls.credit == 1)

    local W4 = newWorld(); W4.inject.grant = 'lose'; local r4 = W4.engine().run(order())
    check('GRANT response lost (delivered): success, no refund, no second grant', r4.code == 'completed' and r4.refund == 0 and W4.calls.credit == 0 and W4.inv[1].water == 3 and W4.calls.grant == 1)
    local W5 = newWorld(); W5.inject.grant = 'lose'; W5.inject.itemStatus = 'down'; local o5 = order(); local S5 = W5.engine(); local r5 = S5.run(o5)
    check('GRANT unknown (applied, ledger unreachable): pending, NO refund while unknown', r5.code == 'pending' and W5.calls.credit == 0 and holdings(W5) == 5)
    W5.inject.itemStatus = nil; local rec5 = S5.recover(0)
    check('GRANT unknown reconciled to success: no refund, one delivery', rec5.completed == 1 and W5.calls.credit == 0 and W5.bank[1] == 8930 and W5.calls.grant == 1 and W5.store.stock == 95)
    local W6 = newWorld(); W6.inject.grant = 'down'; local r6 = W6.engine().run(order())
    check('GRANT unavailable (never applied): refunded in full', r6.code == 'compensated' and W6.bank[1] == 9000 and holdings(W6) == 0)

    local W7 = newWorld(); W7.inject.credit = 'lose'; local o7 = order(); W7.hooks.after_debit = boom
    local S7 = W7.engine(); local r7 = S7.run(o7)
    check('REFUND response lost: order stays pending (refund committed, answer lost)', r7.code == 'pending' and W7.bank[1] == 9000)
    W7.inject.credit = nil; local rec7 = S7.recover(0)
    check('REFUND retry replays the SAME reference: no double refund, one terminal state', rec7.compensated == 1 and W7.bank[1] == 9000 and opcount(W7) == 2 and W7.store.stock == 100)
    check('REFUND further recovery is a no-op', S7.recover(0).examined == 0)
    local W8 = newWorld(); W8.inject.credit = 'down'; local o8 = order(); W8.hooks.after_debit = boom; local S8 = W8.engine(); S8.run(o8)
    check('REFUND unavailable: customer stays owed (pending), stock still held', W8.bank[1] == 8930 and W8.rows[o8.reference].state == 'pending' and W8.store.stock == 95)
    W8.inject.credit = nil; S8.recover(0)
    check('REFUND later converges: refunded once, stock restored once', W8.bank[1] == 9000 and W8.store.stock == 100 and W8.rows[o8.reference].state == 'compensated')
end

-- DISCONNECT / RESTART
do
    local W = newWorld(); local o = order()
    W.hooks.after_debit = function() W.inject.moneyStatus = 'down'; boom() end
    local r = W.engine().run(o)
    check('RESTART-1 crash after payment leaves a pending journal row (obligation survives)', r.code == 'pending' and W.rows[o.reference].state == 'pending' and W.bank[1] == 8930)
    W.inject.moneyStatus = nil
    local rec = W.engine().recover(0)
    check('RESTART-1 paid-but-undelivered -> compensated after restart (character-id addressed; no player/source involved)', rec.compensated == 1 and W.bank[1] == 9000 and W.store.stock == 100 and holdings(W) == 0)

    local W2 = newWorld(); local o2 = order(); W2.inject.dbFinalize = true
    local r2 = W2.engine().run(o2)
    check('RESTART-2 delivered but completion marker cannot be written -> pending', r2.code == 'pending' and holdings(W2) == 5 and W2.rows[o2.reference].state == 'pending')
    W2.inject.dbFinalize = nil
    local rec2 = W2.engine().recover(0)
    check('RESTART-2 reconciles to success: no refund, no stock restore, revenue once', rec2.completed == 1 and W2.bank[1] == 8930 and W2.store.stock == 95 and W2.store.balance == 56 and W2.calls.credit == 0 and W2.calls.grant == 1)

    local W3 = newWorld(); local S3 = W3.engine(); S3.inFlight['X'] = true; W3.rows['X'] = { reference = 'X', state = 'pending' }
    check('RECOVER skips an order still being processed by this resource', S3.recover(0).examined == 0)
end

-- CONCURRENCY
do
    local W = newWorld(); local o = order(); local A, B = W.engine(), W.engine(); local early
    W.hooks.before_grant = function() early = B.resolve(o.reference) end
    local r = A.run(o)
    check('RACE compensator-first: compensated once, live grant fenced, never both', early.code == 'compensated' and r.code == 'compensated' and holdings(W) == 0 and W.bank[1] == 9000 and W.calls.credit == 1 and W.store.stock == 100)
    local W2 = newWorld(); local o2 = order(); local C, D = W2.engine(), W2.engine(); local other
    W2.hooks.after_grant = function() other = D.resolve(o2.reference) end
    local r2 = C.run(o2)
    check('RACE success-first: exactly one terminal result (completed), no compensation, one delivery', other.code == 'completed' and r2.code == 'completed' and W2.calls.credit == 0 and W2.calls.grant == 1 and W2.store.stock == 95 and W2.store.balance == 56)
    local W3 = newWorld(); local o3 = order(); W3.hooks.after_debit = boom; W3.inject.credit = 'down'
    W3.engine().run(o3); W3.inject.credit = nil
    local E, F = W3.engine(), W3.engine(); local inner
    W3.hooks.before_finalize = function() inner = F.resolve(o3.reference) end
    local outer = E.resolve(o3.reference)
    check('RACE two compensation workers: one refund, one stock release, one terminal state', inner.code == 'compensated' and outer.code == 'compensated' and W3.bank[1] == 9000 and opcount(W3) == 2 and W3.store.stock == 100)
end

-- STOCK / OWNERSHIP
do
    local W = newWorld(); W.store.stock = 5; local S = W.engine()
    local a = S.run(order({ units = 5 })); local b = S.run(order({ units = 1, items = { { item = 'water', amount = 1 } } }))
    check('LAST UNITS cannot be sold twice: second buyer no_stock and not charged', a.code == 'completed' and b.code == 'no_stock' and W.store.stock == 0 and W.bank[1] == 9000 - 70)
    local W2 = newWorld(); W2.store.owner = nil; local r2 = W2.engine().run(order({ owner_pct = 0 }))
    check('UNOWNED store: completes, stock consumed, no revenue (sink semantics unchanged)', r2.code == 'completed' and W2.store.stock == 95 and W2.store.balance == 0)
    local W3 = newWorld(); W3.store.owner = nil; W3.hooks.after_debit = boom; local r3 = W3.engine().run(order({ owner_pct = 0 }))
    check('UNOWNED store compensation: refunded, stock back, no destination to reverse', r3.code == 'compensated' and W3.bank[1] == 9000 and W3.store.stock == 100 and W3.store.balance == 0)
    local W4 = newWorld(); W4.store.stock = 7995; W4.CAP = 8000; W4.hooks.after_debit = boom
    W4.engine().run(order({ units = 20, items = { { item = 'water', amount = 20 } } }))
    check('RELEASE respects capacity (stock cannot exceed max after release)', W4.store.stock <= 8000, W4.store.stock)
    local W5 = newWorld(); W5.inject.dbInsert = true; local r5 = W5.engine().run(order())
    check('JOURNAL write fails: nothing reserved, charged or delivered', r5.code == 'unavailable' and W5.store.stock == 100 and W5.bank[1] == 9000 and W5.calls.debit == 0)
    local W6 = newWorld(); local r6 = W6.engine().run(order({ units = 0 }))
    check('units = 0 (untracked stock): no reservation, still exact-once', r6.code == 'completed' and W6.store.stock == 100)
end

-- SQL shape (identifiers are validated; both resources' configs build)
do
    local ok1 = pcall(P.sqlFor, { journal = 'cm_store_purchases', stockTable = 'cm_stores', stockKey = 'store_id', ownerColumn = 'owner_character_id' })
    local ok2 = pcall(P.sqlFor, { journal = 'nv_cloth_purchases', stockTable = 'cm_clothing_stores', stockKey = 'shop_id', ownerColumn = 'owner_character_id' })
    local ok3 = pcall(P.sqlFor, { journal = 'x; DROP TABLE y', stockTable = 'cm_stores', stockKey = 'store_id', ownerColumn = 'owner_character_id' })
    check('SQL builder accepts the two real configs and rejects an injected identifier', ok1 and ok2 and not ok3)
end

print(('\ncm-core item purchase self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
