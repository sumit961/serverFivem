-- Deterministic self-test for cm-gasstations purchase settlement (server/settlement.lua).
--   lua tests/purchase_selftest.lua        (run from resources/[core]/cm-gasstations)
--
-- REAL: server/settlement.lua (the state machine: resolve / run / recover, leg decisions, refund and terminal logic).
-- TEST DOUBLES (labelled): the four owners and the journal SQL.
--   money  = cm-playerdata journaled ops (unique reference, replay, status lookup, response-loss / unavailable injection)
--   items  = cm-inventory grant ledger (unique reference, all-or-nothing, CancelItemGrant fence, response-loss injection)
--   fuel   = cm-vehicles absolute fuel set (+ persisted fuel read)
--   db     = the journal statements with the same guards as the SQL (terminal transition only from 'pending', leg first-writer-wins,
--            atomic reserve). MySQL semantics themselves are proven by tests/purchase_mysql_smoke.py.
-- Crashes are modelled by an exception at a named point plus a fresh Settlement.new() instance over the same world (a restart).
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

CMGas = nil
dofile(here .. '/server/settlement.lua')
local Settlement = CMGas.Settlement

local function newWorld()
    local W = { cash = { [1] = 5000 }, ops = {}, ledger = {}, inv = { [1] = {} }, fuel = { PLATE1 = 20 }, rows = {}, station = { stock = 100, owner = 7, balance = 0, daily = 0, weekly = 0 },
        hooks = {}, inject = {}, calls = { debit = 0, credit = 0, grant = 0, cancel = 0, apply = 0 }, MAX = 25000 }
    function W.at(name)
        local h = W.hooks[name]
        if h then W.hooks[name] = nil; h() end
    end

    local money = {}
    function money.debit(ref, cid, amount)
        W.calls.debit = W.calls.debit + 1
        W.at('before_debit')
        if W.inject.debit == 'down' then return false, 'unavailable' end
        if W.ops[ref] then return true, 'replayed' end
        if (W.cash[cid] or 0) < amount then return false, 'insufficient_funds' end
        W.cash[cid] = W.cash[cid] - amount
        W.ops[ref] = { status = 'committed', direction = 'debit', characterId = tostring(cid), account = 'cash', amount = amount }
        if W.inject.debit == 'lose' then return false, 'unavailable' end
        W.at('after_debit')
        return true, 'applied'
    end
    function money.credit(ref, cid, amount)
        W.calls.credit = W.calls.credit + 1
        if W.inject.credit == 'down' then return false, 'unavailable' end
        if W.ops[ref] then
            if W.ops[ref].amount ~= amount then return false, 'idempotency_conflict' end
            return true, 'replayed'
        end
        W.cash[cid] = (W.cash[cid] or 0) + amount
        W.ops[ref] = { status = 'committed', direction = 'credit', characterId = tostring(cid), account = 'cash', amount = amount }
        if W.inject.credit == 'lose' then return false, 'unavailable' end
        return true, 'applied'
    end
    function money.status(ref)
        if W.inject.moneyStatus == 'down' then return nil, 'unavailable' end
        return W.ops[ref] or false
    end

    local items = {}
    function items.grant(ref, cid, lines)
        W.calls.grant = W.calls.grant + 1
        W.at('before_grant')
        if W.inject.grant == 'down' then return false, 'unavailable' end
        local l = W.ledger[ref]
        if l == 'cancelled' then return false, 'cancelled' end
        if l == 'committed' then return true, { replayed = true } end
        if W.inject.grant == 'no_capacity' then return false, 'no_capacity' end
        W.inv[cid] = W.inv[cid] or {}
        for _, line in ipairs(lines) do W.inv[cid][line.item] = (W.inv[cid][line.item] or 0) + line.amount end
        W.ledger[ref] = 'committed'
        if W.inject.grant == 'lose' then return false, 'unavailable' end
        W.at('after_grant')
        return true, { replayed = false }
    end
    function items.status(ref)
        if W.inject.itemStatus == 'down' then return 'unknown' end
        return W.ledger[ref] or 'not_applied'
    end
    function items.cancel(ref, cid)
        W.calls.cancel = W.calls.cancel + 1
        if W.inject.cancel == 'down' then return false, 'unavailable' end
        local l = W.ledger[ref]
        if l == 'committed' then return false, 'already_committed' end
        W.ledger[ref] = 'cancelled'
        return true, 'cancelled'
    end

    local fuel = {}
    function fuel.apply(plate, target)
        W.calls.apply = W.calls.apply + 1
        W.at('before_fuel')
        if W.inject.fuel == 'fail' then return false end
        W.fuel[plate] = target
        W.at('after_fuel')
        if W.inject.fuel == 'applied_but_false' then return false end
        return true
    end
    function fuel.read(plate)
        if W.inject.fuelRead == 'down' then return nil end
        return W.fuel[plate]
    end

    local db = {}
    local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
    function db.insert(o)
        if W.inject.dbInsert then return nil end
        if W.rows[o.reference] then return false end
        local r = copy(o); r.state = 'pending'; r.reserved_units = 0; r.refund_amount = nil
        W.rows[o.reference] = r
        return true
    end
    function db.get(ref)
        if W.inject.dbGet then return nil end
        local r = W.rows[ref]
        return r and copy(r) or false
    end
    function db.reserve(ref, sid, units)
        local r, s = W.rows[ref], W.station
        if W.inject.dbReserve then return nil end
        if r and r.state == 'pending' and r.reserved_units == 0 and s.owner and s.stock >= units then
            s.stock = s.stock - units; r.reserved_units = units; return true
        end
        return false
    end
    function db.setLeg(ref, leg, to)
        local r = W.rows[ref]
        local cur = r and r[leg .. '_state']
        if r and r.state == 'pending' and (cur == 'pending' or (leg == 'fuel' and cur == 'applying')) then r[leg .. '_state'] = to; return true end
        return false
    end
    function db.claimFuel(ref)
        local r = W.rows[ref]
        if r and r.state == 'pending' and r.fuel_state == 'pending' then r.fuel_state = 'applying'; return true end
        return false
    end
    function db.finalize(ref, state, refund, release, share)
        W.at('before_finalize')
        if W.inject.dbFinalize then return nil end
        local r, s = W.rows[ref], W.station
        if not r or r.state ~= 'pending' then return false end
        r.state, r.refund_amount = state, refund
        if s.owner then
            s.stock = math.min(W.MAX, s.stock + release)
            s.balance = s.balance + share; s.daily = s.daily + share; s.weekly = s.weekly + share
        end
        return true
    end
    function db.stale() local out = {} for ref, r in pairs(W.rows) do if r.state == 'pending' then out[#out + 1] = ref end end table.sort(out) return out end

    W.deps = { db = db, money = money, items = items, fuel = fuel, log = function() end }
    function W.engine() return Settlement.new(W.deps) end
    return W
end

local seq = 0
local function order(over)
    seq = seq + 1
    local o = { reference = ('GAS-PUR-1-%04d'):format(seq), character_id = 1, station_id = 1, reserve_units = 30, fuel_units = 30, fuel_cost = 240, items_cost = 1450,
        items = { { item = 'repair_kit', amount = 1 }, { item = 'wash_kit', amount = 1 } }, plate = 'PLATE1', fuel_before = 20, fuel_target = 50, owner_pct = 80 }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
end
local function total(o) return o.fuel_cost + o.items_cost end
local function opcount(W) local n = 0 for _ in pairs(W.ops) do n = n + 1 end return n end
local function boom() error('simulated exception') end

-- 1 NORMAL ----------------------------------------------------------------------------------------------------------------
do
    local W = newWorld(); local o = order(); local S = W.engine()
    local r = S.run(o)
    check('NORMAL purchase completes', r.code == 'completed' and r.ok and r.fuelDelivered and r.itemsDelivered and r.paid == total(o), r.code)
    check('NORMAL customer charged exactly once', W.cash[1] == 5000 - total(o) and W.calls.debit == 1 and W.calls.credit == 0)
    check('NORMAL stock consumed once (100 -> 70), nothing released', W.station.stock == 70)
    check('NORMAL items delivered once, fuel applied', W.inv[1].repair_kit == 1 and W.inv[1].wash_kit == 1 and W.fuel.PLATE1 == 50 and W.calls.grant == 1)
    check('NORMAL owner revenue 80% credited once', W.station.balance == math.floor(total(o) * 0.8) and W.rows[o.reference].state == 'completed')
    local again = S.resolve(o.reference)
    check('NORMAL re-resolve of a terminal order changes nothing', again.code == 'completed' and W.station.stock == 70 and W.station.balance == math.floor(total(o) * 0.8) and W.cash[1] == 5000 - total(o))
end

-- 2 PAYMENT FAIL ----------------------------------------------------------------------------------------------------------
do
    local W = newWorld(); W.cash[1] = 100; local o = order(); local S = W.engine()
    local r = S.run(o)
    check('PAYMENT-FAIL is reported as payment_failed', r.code == 'payment_failed' and r.reason == 'insufficient_funds', r.code)
    check('PAYMENT-FAIL stock restored exactly, no delivery, no charge, no refund', W.station.stock == 100 and not next(W.inv[1]) and W.cash[1] == 100 and W.calls.credit == 0 and W.fuel.PLATE1 == 20)
    check('PAYMENT-FAIL journal is terminal (compensated), grant fenced', W.rows[o.reference].state == 'compensated' and W.ledger[o.reference] == 'cancelled')
    check('PAYMENT-FAIL no owner revenue', W.station.balance == 0)
end

-- 3 DELIVERY DEFINITIVE FAIL ----------------------------------------------------------------------------------------------
do
    local W = newWorld(); W.inject.grant = 'no_capacity'; local o = order({ fuel_units = 0, reserve_units = 0, fuel_cost = 0, items_cost = 1450, fuel_before = 0, fuel_target = 0, plate = nil })
    local r = W.engine().run(o)
    check('DELIVERY-FAIL items-only: compensated, refund == price', r.code == 'compensated' and r.refunded and r.refund == 1450, r.code)
    check('DELIVERY-FAIL customer net zero, nothing delivered, grant fenced', W.cash[1] == 5000 and not next(W.inv[1]) and W.ledger[o.reference] == 'cancelled' and W.station.balance == 0)

    local W2 = newWorld(); W2.inject.grant = 'no_capacity'; local o2 = order(); local r2 = W2.engine().run(o2)
    check('DELIVERY-FAIL mixed: items refunded, fuel kept, completed', r2.code == 'completed' and r2.refund == 1450 and r2.paid == 240 and r2.fuelDelivered and not r2.itemsDelivered, r2.code)
    check('DELIVERY-FAIL mixed: stock consumed only for fuel, owner share on paid only', W2.station.stock == 70 and W2.station.balance == math.floor(240 * 0.8) and W2.cash[1] == 5000 - 240)

    local W3 = newWorld(); W3.inject.fuel = 'fail'; local o3 = order(); local r3 = W3.engine().run(o3)
    check('DELIVERY-FAIL fuel only: fuel cost refunded, stock released, items kept', r3.code == 'completed' and r3.refund == 240 and r3.itemsDelivered and not r3.fuelDelivered and W3.station.stock == 100 and W3.cash[1] == 5000 - 1450, r3.code)
end

-- 4 EXCEPTION BEFORE DELIVERY (acceptance) --------------------------------------------------------------------------------
do
    local W = newWorld(); local o = order()
    W.hooks.after_debit = boom   -- payment committed, then the flow throws before any delivery
    local r = W.engine().run(o)
    check('EXC-BEFORE-DELIVERY ends compensated, not charged-and-empty', r.code == 'compensated' and r.refunded and r.refund == total(o), r.code)
    check('EXC-BEFORE-DELIVERY customer made whole exactly once', W.cash[1] == 5000 and W.calls.credit == 1 and opcount(W) == 2)
    check('EXC-BEFORE-DELIVERY stock restored exactly once, no revenue', W.station.stock == 100 and W.station.balance == 0)
    check('EXC-BEFORE-DELIVERY nothing delivered and a late grant can never land', not next(W.inv[1]) and W.fuel.PLATE1 == 20 and select(2, W.deps.items.grant(o.reference, 1, o.items)) == 'cancelled' and not next(W.inv[1]))
end

-- 5 EXCEPTION AFTER DELIVERY ----------------------------------------------------------------------------------------------
do
    local W = newWorld(); local o = order()
    W.hooks.after_grant = boom   -- items delivered, flow throws before recording or fuel
    local r = W.engine().run(o)
    check('EXC-AFTER-DELIVERY reconciles to success (no refund of delivered goods)', r.itemsDelivered and r.code == 'completed', r.code)
    check('EXC-AFTER-DELIVERY items exactly once, no double delivery', W.inv[1].repair_kit == 1 and W.inv[1].wash_kit == 1 and W.calls.grant == 1)
    check('EXC-AFTER-DELIVERY fuel leg refunded (never applied), items kept, stock released for fuel', r.refund == 240 and not r.fuelDelivered and W.station.stock == 100 and W.cash[1] == 5000 - 1450)
    local W2 = newWorld(); local o2 = order()
    W2.hooks.after_fuel = boom   -- everything delivered, exception right before the response
    local r2 = W2.engine().run(o2)
    check('EXC-AFTER-ALL-DELIVERY reconciles to full success: no refund, no stock restore, no redelivery', r2.code == 'completed' and r2.refund == 0 and r2.fuelDelivered and r2.itemsDelivered and W2.station.stock == 70 and W2.cash[1] == 5000 - total(o2) and W2.calls.grant == 1 and W2.calls.apply == 1, r2.code)
end

-- 6 PAYMENT RESPONSE LOSS -------------------------------------------------------------------------------------------------
do
    local W = newWorld(); W.inject.debit = 'lose'; local o = order(); local r = W.engine().run(o)
    check('PAY-RESPONSE-LOSS (debit committed, answer lost) proceeds to delivery without a second debit', r.code == 'completed' and W.calls.debit == 1 and W.cash[1] == 5000 - total(o) and W.inv[1].repair_kit == 1, r.code)
    local W2 = newWorld(); W2.inject.debit = 'down'; local o2 = order(); local r2 = W2.engine().run(o2)
    check('PAY-UNAVAILABLE (debit never applied) is compensated with NO refund of money never taken', r2.code == 'payment_failed' and W2.cash[1] == 5000 and W2.calls.credit == 0 and W2.station.stock == 100 and W2.rows[o2.reference].state == 'compensated', r2.code)
    local W3 = newWorld(); W3.inject.debit = 'lose'; W3.inject.moneyStatus = 'down'; local o3 = order(); local S3 = W3.engine(); local r3 = S3.run(o3)
    check('PAY-UNKNOWN (answer lost AND ledger unreachable) stays pending: no delivery, no refund guess, stock held', r3.code == 'pending' and not next(W3.inv[1]) and W3.station.stock == 70 and W3.calls.credit == 0, r3.code)
    W3.inject.moneyStatus = nil
    local rec = S3.recover(0)
    check('PAY-UNKNOWN recovered once the ledger answers: charged -> compensated, refund once, stock back', rec.compensated == 1 and W3.cash[1] == 5000 and W3.station.stock == 100 and W3.calls.credit == 1)
end

-- 7 DELIVERY RESPONSE LOSS ------------------------------------------------------------------------------------------------
do
    local W = newWorld(); W.inject.grant = 'lose'; local o = order(); local r = W.engine().run(o)
    check('DELIVERY-RESPONSE-LOSS: goods WERE delivered -> success, no refund, no free item', r.code == 'completed' and r.itemsDelivered and r.refund == 0 and W.calls.credit == 0 and W.inv[1].repair_kit == 1, r.code)
    local W2 = newWorld(); W2.inject.grant = 'down'; local o2 = order(); local r2 = W2.engine().run(o2)
    check('DELIVERY-UNAVAILABLE (never applied): items refunded, fuel kept', r2.code == 'completed' and r2.refund == 1450 and not r2.itemsDelivered and not next(W2.inv[1]), r2.code)
    local W3 = newWorld(); W3.inject.grant = 'lose'; W3.inject.itemStatus = 'down'; local o3 = order(); local S3 = W3.engine(); local r3 = S3.run(o3)
    check('DELIVERY-UNKNOWN (applied, answer lost, ledger unreachable): NO refund while unknown', r3.code == 'pending' and W3.calls.credit == 0 and W3.inv[1].repair_kit == 1, r3.code)
    W3.inject.itemStatus = nil
    local rec = S3.recover(0)
    check('DELIVERY-UNKNOWN reconciled to success after the ledger answers: no refund at all, one delivery', rec.completed == 1 and W3.calls.credit == 0 and W3.cash[1] == 5000 - total(o3) and W3.inv[1].repair_kit == 1 and W3.calls.grant == 1)
end

-- 8 COMPENSATION RESPONSE LOSS --------------------------------------------------------------------------------------------
do
    local W = newWorld(); W.inject.credit = 'lose'; local o = order(); W.hooks.after_debit = boom
    local S = W.engine(); local r = S.run(o)
    check('COMP-RESPONSE-LOSS leaves the order pending (refund answer lost)', r.code == 'pending' and W.cash[1] == 5000 and W.rows[o.reference].state == 'pending', r.code)
    W.inject.credit = nil
    local rec = S.recover(0)
    check('COMP-RESPONSE-LOSS retry replays the SAME refund reference: no double refund, terminal once', rec.compensated == 1 and W.cash[1] == 5000 and W.station.stock == 100 and W.calls.credit == 2 and opcount(W) == 2)
    local again = S.recover(0)
    check('COMP-RESPONSE-LOSS further recovery is a no-op', again.examined == 0 and W.cash[1] == 5000)
    local W2 = newWorld(); W2.inject.credit = 'down'; local o2 = order(); W2.hooks.after_debit = boom
    local S2 = W2.engine(); S2.run(o2)
    check('COMP-UNAVAILABLE: customer stays owed (pending) until the money owner answers', W2.cash[1] == 5000 - total(o2) and W2.rows[o2.reference].state == 'pending' and W2.station.stock == 70)
    W2.inject.credit = nil; S2.recover(0)
    check('COMP-UNAVAILABLE later converges: refunded once, stock restored once', W2.cash[1] == 5000 and W2.station.stock == 100 and W2.rows[o2.reference].state == 'compensated')
end

-- 9 DISCONNECT / 10 RESTART -----------------------------------------------------------------------------------------------
do
    -- charged, process dies (exception + owner ledgers unreachable so the handler cannot resolve), then a fresh instance recovers
    local W = newWorld(); local o = order()
    W.hooks.after_debit = function() W.inject.moneyStatus = 'down'; boom() end
    local S1 = W.engine(); local r = S1.run(o)
    check('RESTART-1 crash after payment leaves a pending journal row (obligation survives)', r.code == 'pending' and W.rows[o.reference].state == 'pending' and W.cash[1] == 5000 - total(o))
    W.inject.moneyStatus = nil
    local S2 = W.engine()   -- restarted resource: new instance, no in-memory state, no player source anywhere
    local rec = S2.recover(0)
    check('RESTART-1 paid-but-undelivered -> compensated after restart (character-id addressed, offline-safe)', rec.compensated == 1 and W.cash[1] == 5000 and W.station.stock == 100 and not next(W.inv[1]) and W.calls.credit == 1)

    local W2 = newWorld(); local o2 = order()
    W2.inject.dbFinalize = true   -- delivered everything, completion marker cannot be written
    local S3 = W2.engine(); local r2 = S3.run(o2)
    check('RESTART-2 delivered but completion marker stale -> pending', r2.code == 'pending' and W2.inv[1].repair_kit == 1 and W2.fuel.PLATE1 == 50 and W2.rows[o2.reference].state == 'pending')
    W2.inject.dbFinalize = nil
    local rec2 = W2.engine().recover(0)
    check('RESTART-2 reconciles to success: no refund, no stock restore, revenue once', rec2.completed == 1 and W2.cash[1] == 5000 - total(o2) and W2.station.stock == 70 and W2.station.balance == math.floor(total(o2) * 0.8) and W2.calls.credit == 0 and W2.calls.grant == 1)

    local W3 = newWorld(); local o3 = order()
    local S4 = W3.engine()
    S4.inFlight[o3.reference] = true
    W3.rows[o3.reference] = { reference = o3.reference, state = 'pending' }
    check('RECOVER skips an order that is still being processed by this resource', S4.recover(0).examined == 0)
end

-- 11 CONCURRENCY: compensation vs success ---------------------------------------------------------------------------------
do
    -- compensator runs after the debit and BEFORE the live flow's grant: the fence must win, the live grant must then fail
    local W = newWorld(); local o = order(); local S = W.engine(); local S2 = W.engine()
    local early
    W.hooks.before_grant = function() early = S2.resolve(o.reference) end
    local r = S.run(o)
    check('RACE compensator-first: compensated, never both', early.code == 'compensated' and r.code == 'compensated' and W.rows[o.reference].state == 'compensated')
    check('RACE compensator-first: late grant fenced, fuel not applied after the refund, refund once, stock once', not next(W.inv[1]) and W.cash[1] == 5000 and W.calls.credit == 1 and W.station.stock == 100 and W.fuel.PLATE1 == 20 and W.calls.apply == 0, W.calls.apply)

    -- success first: grant commits, then a competing worker resolves before the live flow records anything
    local W2 = newWorld(); local o2 = order(); local A = W2.engine(); local B = W2.engine()
    local other
    W2.hooks.after_grant = function() other = B.resolve(o2.reference) end
    local r2 = A.run(o2)
    check('RACE success-first: exactly one terminal result (completed), no compensation', other.code == 'completed' and r2.code == 'completed' and W2.rows[o2.reference].state == 'completed')
    check('RACE success-first: items once; the fuel leg the other worker refunded is never applied afterwards (no free fuel)', W2.inv[1].repair_kit == 1 and W2.calls.grant == 1 and W2.fuel.PLATE1 == 20 and W2.calls.apply == 0 and r2.refund == 240 and not r2.fuelDelivered)
    check('RACE success-first: fuel refund exactly once, stock for fuel returned once, revenue on paid only, once', W2.calls.credit == 1 and W2.cash[1] == 5000 - 1450 and W2.station.stock == 100 and W2.station.balance == math.floor(1450 * 0.8))

    -- two compensation workers racing from inside each other's finalize
    local W3 = newWorld(); local o3 = order(); W3.hooks.after_debit = boom; W3.inject.credit = 'down'
    local S3 = W3.engine(); S3.run(o3)
    W3.inject.credit = nil
    local C1, C2 = W3.engine(), W3.engine()
    local inner
    W3.hooks.before_finalize = function() inner = C2.resolve(o3.reference) end
    local outer = C1.resolve(o3.reference)
    check('RACE two compensation workers: one refund, one stock release, one terminal state', inner.code == 'compensated' and outer.code == 'compensated' and W3.cash[1] == 5000 and opcount(W3) == 2 and W3.station.stock == 100 and W3.rows[o3.reference].state == 'compensated')
end

-- 12 FUEL CRASH WINDOW ----------------------------------------------------------------------------------------------------
do
    local W = newWorld(); local o = order({ items = {}, items_cost = 0 }); W.hooks.after_fuel = boom
    local r = W.engine().run(o)
    check('FUEL applied then exception before recording: persisted fuel proves delivery -> success, no refund', r.code == 'completed' and r.fuelDelivered and r.refund == 0 and W.station.stock == 70, r.code)
    local W2 = newWorld(); local o2 = order({ items = {}, items_cost = 0 }); W2.hooks.before_fuel = boom
    local r2 = W2.engine().run(o2)
    check('FUEL exception before apply: fuel never changed -> refunded, stock restored', r2.code == 'compensated' and r2.refund == 240 and W2.station.stock == 100 and W2.fuel.PLATE1 == 20, r2.code)
    local W3 = newWorld(); W3.inject.fuel = 'applied_but_false'; local o3 = order({ items = {}, items_cost = 0 }); local r3 = W3.engine().run(o3)
    check('FUEL applied but reported false: vehicle evidence wins (no refund of delivered fuel)', r3.code == 'completed' and r3.fuelDelivered and r3.refund == 0, r3.code)
    local W4 = newWorld(); W4.inject.fuelRead = 'down'; W4.inject.fuel = 'fail'; local o4 = order({ items = {}, items_cost = 0 }); local S4 = W4.engine(); local r4 = S4.run(o4)
    check('FUEL unknown (vehicle owner unreachable): stays pending, no refund guess', r4.code == 'pending' and W4.calls.credit == 0, r4.code)
end

do
    -- persisted fuel (80) higher than the live fuel the target was based on (50): evidence must be the target, not "above before"
    local W = newWorld(); W.fuel.PLATE1 = 80; local o = order({ items = {}, items_cost = 0, fuel_before = 80, fuel_target = 50 }); W.hooks.before_fuel = boom
    local r = W.engine().run(o)
    check('FUEL persisted-higher-than-live: never applied -> refunded (80 is not evidence of delivery)', r.code == 'compensated' and r.refund == 240 and W.fuel.PLATE1 == 80, r.code)
    local W2 = newWorld(); W2.fuel.PLATE1 = 80; local o2 = order({ items = {}, items_cost = 0, fuel_before = 80, fuel_target = 50 }); W2.hooks.after_fuel = boom
    local r2 = W2.engine().run(o2)
    check('FUEL persisted-higher-than-live: applied (== target) then exception -> delivered, no refund', r2.code == 'completed' and r2.fuelDelivered and r2.refund == 0 and W2.fuel.PLATE1 == 50, r2.code)
    local W3 = newWorld(); W3.fuel.PLATE1 = 50; local o3 = order({ items = {}, items_cost = 0, fuel_before = 50, fuel_target = 50 }); W3.hooks.after_fuel = boom
    local r3 = W3.engine().run(o3)
    check('FUEL no observable difference (before == target): refund rather than charged-and-empty', r3.code == 'compensated' and r3.refund == 240, r3.code)
end

-- 13 PURCHASE vs PURCHASE / UNOWNED --------------------------------------------------------------------------------------
do
    local W = newWorld(); W.station.stock = 30; local S = W.engine()
    local a = S.run(order({ items = {}, items_cost = 0 }))
    local b = S.run(order({ items = {}, items_cost = 0 }))
    check('LAST UNIT cannot be sold twice: second buyer gets no_stock and is not charged', a.code == 'completed' and b.code == 'no_stock' and W.station.stock == 0 and W.cash[1] == 5000 - 240)
    local W2 = newWorld(); W2.station.owner = nil; local o = order({ reserve_units = 0, owner_pct = 0 }); local r = W2.engine().run(o)
    check('UNOWNED station (money sink): completes, no stock/revenue touched', r.code == 'completed' and W2.station.stock == 100 and W2.station.balance == 0)
    local W3 = newWorld(); W3.station.owner = nil; W3.hooks.after_debit = boom; local o3 = order({ reserve_units = 0, owner_pct = 0 }); local r3 = W3.engine().run(o3)
    check('UNOWNED station compensation: customer refunded; no destination to reverse (sink)', r3.code == 'compensated' and W3.cash[1] == 5000 and W3.station.balance == 0)
end

-- 14 JOURNAL / DB FAILURES ------------------------------------------------------------------------------------------------
do
    local W = newWorld(); W.inject.dbInsert = true; local r = W.engine().run(order())
    check('JOURNAL write fails: nothing reserved, charged or delivered', r.code == 'unavailable' and W.station.stock == 100 and W.cash[1] == 5000 and W.calls.debit == 0)
    local W2 = newWorld(); W2.inject.dbReserve = true; local r2 = W2.engine().run(order())
    check('RESERVE outcome unknown: no charge is attempted; journal closes with whatever was reserved', r2.code == 'unavailable' and W2.calls.debit == 0 and W2.cash[1] == 5000)
    local W3 = newWorld(); W3.station.stock = 5; local r3 = W3.engine().run(order())
    check('OUT OF STOCK: no charge, no delivery, journal terminal', r3.code == 'no_stock' and W3.calls.debit == 0 and W3.cash[1] == 5000 and next(W3.rows) and select(2, next(W3.rows)).state == 'compensated')
end

print(('\ncm-gasstations purchase self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
