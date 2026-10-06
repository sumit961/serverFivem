-- cm-trade <-> cm-inventory item exchange integration (deterministic, no FiveM, no database).
--   lua tests/exchange_integration.lua        (run from resources/[core]/cm-trade)
--
-- REAL: cm-trade server/core.lua + config.lua (sessions, offers, confirmations, the settlement saga, journal, Reconcile, and ITS adapter `P.items` that talks to
--       cm-inventory through exports), and the REAL cm-inventory chunk incl. craft.lua/exchange.lua + the REAL cm-items trade policy (via the inventory harness).
-- DOUBLES (labelled): FiveM runtime; presence/identity/money providers (wallets + an economy ledger with the same evidence semantics as economy_transactions);
--       the cm-trade journal SQL (cm_trade_transactions/events, in-memory); the SQL layer under cm-inventory (in-memory, transactional undo, FOR UPDATE row locks).
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local invPath = here .. '/../cm-inventory'
local H = dofile(invPath .. '/tests/craft_harness.lua')(invPath)
local ITEMS = H.ITEMS
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
ITEMS.water = { weight = 500 }; ITEMS.sandwich = { weight = 350 }; ITEMS.bandage = { weight = 100 }; ITEMS.weapon_pistol = ITEMS.weapon_pistol or { weight = 1200, stack = false, unique = true }
ITEMS.rare_gem = { weight = 100, stack = false, unique = true, tradeable = true }
ITEMS.heavy_box = { weight = 14000, tradeable = true }

-- ------------------------------------------------------------------ cm-trade journal SQL double
local function newTradeDb()
    local db = { tx = {}, events = {} }
    function db.exec(kind, sql, p)
        if sql:find('^INSERT INTO cm_trade_events') then db.events[#db.events + 1] = { ref = p[1], kind = p[2] } return 1 end
        if sql:find('^INSERT INTO cm_trade_transactions') then
            for _, r in ipairs(db.tx) do if r.reference == p[1] then error('Duplicate entry') end end
            db.tx[#db.tx + 1] = { reference = p[1], char_a = p[2], char_b = p[3], cash_a = p[4], cash_b = p[5], item_lines = p[6], items_json = p[7], status = 'debiting' } return 1
        end
        if sql:find('^UPDATE cm_trade_transactions SET status') then
            for _, r in ipairs(db.tx) do if r.reference == p[4] then r.status = p[1]; r.detail = p[2] return 1 end end return 0
        end
        if sql:find('^SELECT %* FROM cm_trade_transactions WHERE status IN') then
            local o = {} for _, r in ipairs(db.tx) do if r.status == 'debiting' or r.status == 'debited' or r.status == 'items_done' or r.status == 'needs_reconciliation' then local c = {} for k, v in pairs(r) do c[k] = v end o[#o + 1] = c end end return o
        end
        error('trade SQL double: unsupported ' .. sql)
    end
    return db
end

local function build(shared)
    shared = shared or {}
    local invDb = shared.invDb or H.newDb(); for c = 1, 3 do invDb.addChar(c) end
    local invW = shared.invW or H.newWorld(invDb)
    local tradeDb = shared.tradeDb or newTradeDb()
    local W = { invDb = invDb, invW = invW, tradeDb = tradeDb, events = {}, wallets = shared.wallets or { [1] = 5000, [2] = 5000, [3] = 5000 }, ledger = shared.ledger or {},
        online = { [1] = 101, [2] = 102, [3] = 103 }, offline = {}, srcCid = { [101] = 1, [102] = 2, [103] = 3 }, bridgeDown = false }
    local noop = function() end
    local bridge = setmetatable({}, { __index = function(_, res)
        if res ~= 'cm-inventory' then return setmetatable({}, { __index = function() return noop end }) end
        return setmetatable({}, { __index = function(_, name)
            local fn = invW.registry[name]
            return function(self, ...)
                if W.bridgeDown then error('inventory unavailable') end
                invW.invoker = 'cm-trade'
                if W.beforeExecute and name == 'ExecuteItemExchange' then W.beforeExecute() end
                local a, b = fn(self, ...)
                if W.afterExecute and name == 'ExecuteItemExchange' then local x, y = W.afterExecute(a, b); return x, y end
                return a, b
            end
        end })
    end })
    local env = setmetatable({}, { __index = _G })
    env.exports = bridge
    env.MySQL = { insert = { await = function(sql, p) return tradeDb.exec('insert', sql, p) end }, update = { await = function(sql, p) return tradeDb.exec('update', sql, p) end },
        query = { await = function(sql, p) return tradeDb.exec('query', sql, p) end }, single = { await = function() return nil end }, scalar = { await = function() return 0 end } }
    env.json = H.json
    env.GetCurrentResourceName = function() return 'cm-trade' end
    env.GetResourceState = function(r) if r == 'cm-inventory' then return 'started' end return 'missing' end
    env.TriggerClientEvent = function(name, src, payload) W.events[#W.events + 1] = { name = name, src = src, payload = payload } end
    env.CreateThread = noop; env.Wait = noop; env.AddEventHandler = noop; env.RegisterNetEvent = noop; env.RegisterCommand = noop
    env.GetPlayerRoutingBucket = function() return 0 end
    env.os, env.math, env.string, env.table, env.pairs, env.ipairs, env.type, env.tostring, env.tonumber, env.pcall, env.error, env.print = os, math, string, table, pairs, ipairs, type, tostring, tonumber, pcall, error, function() end
    local function load1(path) local f = assert(io.open(here .. '/' .. path, 'rb')); local s = f:read('a'); f:close(); assert(load(s, '@' .. path, 't', env))() end
    load1('config.lua'); load1('server/core.lua')
    local T = env.CMTrade
    T.TestNoAdminLog = true
    env.Config.RateLimits = { invite = { 999, 1 }, offer = { 999, 1 }, confirm = { 999, 1 }, cancel = { 999, 1 }, inventory = { 999, 1 } }
    local P = T.P
    P.presence = { cidOf = function(src) if W.offline[src] then return nil end return W.srcCid[src] end, srcOf = function(cid) return W.online[cid] and not W.offline[W.online[cid]] and W.online[cid] or nil end,
        bucket = function() return 0 end, distance = function() return 1.0 end, dead = function() return false end }
    P.identity = { label = function(_, _, cid) return 'Stranger #' .. cid end }
    P.money = {
        cash = function(cid) return W.wallets[cid] end,
        debit = function(cid, amount, reason)
            if W.offline[W.online[cid]] or (W.wallets[cid] or 0) < amount then return false end
            W.wallets[cid] = W.wallets[cid] - amount; W.ledger[#W.ledger + 1] = { cid = cid, action = 'remove', reason = reason, amount = amount } return true
        end,
        credit = function(cid, amount, reason) W.wallets[cid] = (W.wallets[cid] or 0) + amount; W.ledger[#W.ledger + 1] = { cid = cid, action = 'add', reason = reason, amount = amount } return true end,
        evidence = function(cid, action, reason) for _, e in ipairs(W.ledger) do if e.cid == cid and e.action == action and e.reason == reason then return true end end return false end,
    }
    W.T, W.env, W.P = T, env, P
    return W
end

-- a terminal not_applied ledger row (the owner's proof) may exist; what must never exist is a committed one
local function committedRows(W) local n = 0 for _, r in ipairs(W.invDb.ledger) do if r.status == 'committed' then n = n + 1 end end return n end
local function cashTotal(W) local n = 0 for _, v in pairs(W.wallets) do n = n + v end return n end
local function snapRef(W, cid, item)
    W.invW.invoker = 'cm-trade'
    for _, r in ipairs(W.invW.registry.GetTradeSnapshot(cid)) do if r.item == item then return r end end
end
local function inv(db, cid, rows) db.clear(cid) for _, r in ipairs(rows) do db.give(cid, r[1], r[2], r[3], r[4]) end end
local function open(W, a, b)
    local ok, id = W.T.Invite(a or 101, b or 102); assert(ok, id)
    assert(W.T.Respond(b or 102, id, true)); return W.T.sessions[id]
end
local function confirmBoth(W, s)
    W.T.Confirm(s.a.src, s.id, s.rev)
    return W.T.Confirm(s.b.src, s.id, s.rev)
end
local function row(W, ref) for _, r in ipairs(W.tradeDb.tx) do if r.reference == ref then return r end end end

-- ============================================================ detection / enablement
do
    local W = build()
    check('ENABLE cm-trade detects the real exchange contract (items enabled, no config change)', W.P.items.enabled() == true)
    local W2 = build(); W2.bridgeDown = true
    check('ENABLE inventory unavailable -> items disabled (fail closed)', W2.P.items.enabled() == false)
    check('ENABLE the adapter maps committed/not_applied and never treats anything else as evidence', W.P.items.status('TRD-NEVERSEEN') == 'not_submitted')
end

-- ============================================================ offers
do
    local W = build()
    inv(W.invDb, 1, { { 'pocket-1', 'water', 10 }, { 'pocket-2', 'weapon_pistol', 1, { serial = 'W-1' } } }); inv(W.invDb, 2, { { 'pocket-1', 'sandwich', 4 } })
    local s = open(W)
    local water = snapRef(W, 1, 'water')
    local gun = snapRef(W, 1, 'weapon_pistol')
    local rev0 = s.rev
    check('OFFER add a tradeable item bumps the revision and clears confirmations', (function()
        W.T.Confirm(101, s.id, s.rev); local ok = W.T.AddItem(101, s.id, water.ref, 3)
        return ok == true and s.rev > rev0 and next(s.confirmed) == nil and #s.offers[1].items == 1 end)())
    check('OFFER the stored line keeps the server-side fingerprint; the client view never carries it', s.offers[1].items[1].fp == water.fp and W.T.View(s, 1).you.offer.items[1].fp == nil)
    check('OFFER change quantity resets confirmations again', (function() local r = s.rev; W.T.Confirm(102, s.id, s.rev); W.T.AddItem(101, s.id, water.ref, 5); return s.rev > r and next(s.confirmed) == nil end)())
    check('OFFER a weapon is rejected (not tradeable)', select(2, W.T.AddItem(101, s.id, gun.ref, 1)) == 'not_tradeable')
    check('OFFER a forged ref (the other player\'s row) is rejected', select(2, W.T.AddItem(101, s.id, snapRef(W, 2, 'sandwich').ref, 1)) == 'invalid_item')
    check('OFFER a made-up ref / malformed ref / excessive or fractional quantity are rejected', select(2, W.T.AddItem(101, s.id, '999999', 1)) == 'invalid_item' and select(2, W.T.AddItem(101, s.id, "1;DROP", 1)) == 'invalid_item'
        and select(2, W.T.AddItem(101, s.id, water.ref, 101)) == 'invalid_amount' and select(2, W.T.AddItem(101, s.id, water.ref, 1.5)) == 'invalid_amount' and select(2, W.T.AddItem(101, s.id, water.ref, 11)) == 'insufficient_quantity')
    check('OFFER remove an item resets confirmations', (function() local r = s.rev; local ok = W.T.RemoveItem(101, s.id, water.ref); return ok == true and s.rev > r and #s.offers[1].items == 0 end)())
    check('OFFER a non-participant cannot touch the session', select(2, W.T.AddItem(103, s.id, water.ref, 1)) == 'invalid_state')
    check('OFFER too many lines are rejected', (function()
        local rows = {} for i = 1, 6 do rows[#rows + 1] = { 'pocket-' .. i, i % 2 == 0 and 'water' or 'bandage', 1, { n = i } } end
        inv(W.invDb, 1, rows); local okAll = true
        for _, r in ipairs(W.invW.registry.GetTradeSnapshot(1)) do local ok = W.T.AddItem(101, s.id, r.ref, 1); okAll = okAll and ok end
        inv(W.invDb, 1, { { 'pocket-1', 'water', 1 }, { 'pocket-2', 'water', 1, { a = 1 } }, { 'pocket-3', 'water', 1, { a = 2 } }, { 'pocket-4', 'water', 1, { a = 3 } }, { 'pocket-5', 'water', 1, { a = 4 } }, { 'pocket-6', 'water', 1, { a = 5 } } })
        return true end)())
end

-- ============================================================ ITEM-ONLY settlement
do
    local W = build()
    inv(W.invDb, 1, { { 'pocket-1', 'water', 10 } }); inv(W.invDb, 2, { { 'pocket-1', 'sandwich', 4 }, { 'pocket-2', 'rare_gem', 1, { serial = 'GEM-7', durability = 66 } } })
    local gemId = W.invDb.rowsOf(2)[2].id
    local s = open(W)
    W.T.AddItem(101, s.id, snapRef(W, 1, 'water').ref, 4)
    W.T.AddItem(102, s.id, snapRef(W, 2, 'sandwich').ref, 2); W.T.AddItem(102, s.id, snapRef(W, 2, 'rare_gem').ref, 1)
    local cash0 = cashTotal(W)
    local ok = confirmBoth(W, s)
    local jr = row(W, s.id)
    check('ITEM-ONLY a two-sided item trade completes atomically through the real inventory exchange', ok == true and W.invDb.count(1, 'water') == 6 and W.invDb.count(2, 'water') == 4 and W.invDb.count(1, 'sandwich') == 2 and W.invDb.count(1, 'rare_gem') == 1 and W.invDb.count(2, 'rare_gem') == 0)
    check('ITEM-ONLY the unique item kept its row id, serial and durability', (function() for _, r in ipairs(W.invDb.rowsOf(1)) do if r.item_name == 'rare_gem' then return r.id == gemId and W.invW.env and true and (r.metadata or ''):find('GEM%-7') ~= nil and (r.metadata or ''):find('66') ~= nil end end return false end)())
    check('ITEM-ONLY journal completed, one inventory ledger row, no money moved', jr and jr.status == 'completed' and #W.invDb.ledger == 1 and W.invDb.ledger[1].tx_type == 'trade_exchange' and cashTotal(W) == cash0 and #W.ledger == 0)
    check('ITEM-ONLY both clients were told the trade completed; the session is released', (function() local n = 0 for _, e in ipairs(W.events) do if e.name == 'cm-trade:client:ended' and e.payload.outcome == 'completed' then n = n + 1 end end return n == 2 and W.T.byCid[1] == nil and W.T.byCid[2] == nil end)())
end

-- ============================================================ CASH-ONLY unchanged
do
    local W = build()
    local s = open(W)
    W.T.SetCash(101, s.id, 1500); W.T.SetCash(102, s.id, 400)
    local ok = confirmBoth(W, s)
    check('CASH-ONLY unchanged: cash swaps once through the existing saga, no inventory call', ok == true and W.wallets[1] == 5000 - 1500 + 400 and W.wallets[2] == 5000 - 400 + 1500 and row(W, s.id).status == 'completed' and #W.invDb.ledger == 0 and #W.invDb.inventory_items == 0)
    check('CASH-ONLY the journal holds the legs as separate ledger rows (debit/credit evidence)', (function() local d, c = 0, 0 for _, e in ipairs(W.ledger) do if e.reason:find(':debit') then d = d + 1 elseif e.reason:find(':credit') then c = c + 1 end end return d == 2 and c == 2 end)())
end

-- ============================================================ MIXED cash + items
do
    local function mixed()
        local W = build()
        inv(W.invDb, 1, { { 'pocket-1', 'water', 10 } }); inv(W.invDb, 2, { { 'pocket-1', 'sandwich', 4 } })
        local s = open(W)
        W.T.AddItem(101, s.id, snapRef(W, 1, 'water').ref, 4); W.T.AddItem(102, s.id, snapRef(W, 2, 'sandwich').ref, 2)
        W.T.SetCash(101, s.id, 1000); W.T.SetCash(102, s.id, 300)
        return W, s
    end
    local W, s = mixed()
    local ok = confirmBoth(W, s)
    check('MIXED cash + items complete: items swapped once, cash swapped once, journal completed', ok == true and W.invDb.count(2, 'water') == 4 and W.invDb.count(1, 'sandwich') == 2 and W.wallets[1] == 5000 - 1000 + 300 and W.wallets[2] == 5000 - 300 + 1000 and row(W, s.id).status == 'completed')
    check('MIXED order of effects: both debits before the pivot, credits after (evidence in the ledger)', (function()
        local firstCredit, lastDebit = 99, 0
        for i, e in ipairs(W.ledger) do if e.reason:find(':debit') then lastDebit = i elseif e.reason:find(':credit') and i < firstCredit then firstCredit = i end end
        return lastDebit < firstCredit end)())

    -- inventory refuses at final validation: nothing is debited at all
    W, s = mixed()
    W.invDb.rowsOf(1)[1].quantity = 1   -- the offered water was used up after the offer
    local cash0 = cashTotal(W)
    confirmBoth(W, s)
    check('MIXED stale inventory at final validation: nothing is debited, nothing moves, session cancelled', cashTotal(W) == cash0 and #W.ledger == 0 and #W.invDb.ledger == 0 and s.state == 'cancelled' and s.endReason == 'items_failed')
    W, s = mixed()
    local sandwichRow = W.invDb.rowsOf(2)[1]; sandwichRow.metadata = W.env.CMTrade and '{"swapped":true}' or nil
    cash0 = cashTotal(W)
    confirmBoth(W, s)
    check('MIXED the other side\'s item changed after the offer (metadata/variant): refused before any debit', cashTotal(W) == cash0 and #W.ledger == 0 and s.state == 'cancelled')
    W = build()
    inv(W.invDb, 2, { { 'pocket-1', 'sandwich', 4 }, { 'pocket-2', 'heavy_box', 1 }, { 'pocket-3', 'water', 20 } })
    inv(W.invDb, 1, { { 'pocket-1', 'water', 10 }, { 'pocket-2', 'heavy_box', 1 } })
    s = open(W); W.T.AddItem(101, s.id, snapRef(W, 1, 'water').ref, 1); W.T.AddItem(102, s.id, snapRef(W, 2, 'water').ref, 20); W.T.SetCash(101, s.id, 100)
    cash0 = cashTotal(W)
    confirmBoth(W, s)
    check('MIXED final-state capacity failure on one side: nothing debited, nothing moved', cashTotal(W) == cash0 and #W.ledger == 0 and #W.invDb.ledger == 0)

    -- crash / failure boundaries after the debits start
    W, s = mixed()
    W.T.TestCrashAt = 'debit_a'
    confirmBoth(W, s)
    local jr = row(W, s.id)
    check('MIXED boundary: crash after A\'s debit -> journal needs_reconciliation, A debited, items untouched', jr.status == 'needs_reconciliation' and W.wallets[1] == 4000 and W.invDb.count(2, 'water') == 0)
    W.T.Reconcile()
    check('MIXED boundary: reconcile refunds A (the exchange never applied) -> rolled_back, no cash lost, no items moved', row(W, s.id).status == 'rolled_back' and W.wallets[1] == 5000 and W.wallets[2] == 5000 and W.invDb.count(2, 'water') == 0 and committedRows(W) == 0)

    W, s = mixed()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    check('MIXED boundary: crash after both debits, before the pivot -> both debited, items untouched', row(W, s.id).status == 'needs_reconciliation' and W.wallets[1] == 4000 and W.wallets[2] == 4700 and #W.invDb.ledger == 0)
    W.T.Reconcile()
    check('MIXED boundary: reconcile refunds both debits; items never moved', row(W, s.id).status == 'rolled_back' and W.wallets[1] == 5000 and W.wallets[2] == 5000 and W.invDb.count(1, 'water') == 10)
    W.T.Reconcile()
    check('MIXED boundary: a second reconcile is a no-op (no double refund)', W.wallets[1] == 5000 and W.wallets[2] == 5000)

    W, s = mixed()
    W.T.TestCrashAt = 'items_done'
    confirmBoth(W, s)
    check('MIXED boundary: crash after the item exchange committed -> items moved ONCE, credits pending', W.invDb.count(2, 'water') == 4 and #W.invDb.ledger == 1 and W.wallets[1] == 4000 and W.wallets[2] == 4700)
    W.T.Reconcile()
    check('MIXED boundary: reconcile rolls FORWARD (credits) and never exchanges again', row(W, s.id).status == 'completed' and W.wallets[1] == 4300 and W.wallets[2] == 5700 and #W.invDb.ledger == 1 and W.invDb.count(2, 'water') == 4)
    W.T.Reconcile()
    check('MIXED boundary: repeated reconcile changes nothing (credits keyed by evidence)', W.wallets[1] == 4300 and W.wallets[2] == 5700 and #W.invDb.ledger == 1)

    W, s = mixed()
    W.T.TestCrashAt = 'credit_leg'
    confirmBoth(W, s)
    W.T.Reconcile()
    check('MIXED boundary: crash mid credit legs -> reconcile completes the remaining leg exactly once', row(W, s.id).status == 'completed' and W.wallets[1] == 4300 and W.wallets[2] == 5700 and #W.invDb.ledger == 1)

    -- exchange committed but the response was lost
    W, s = mixed()
    W.afterExecute = function(a, b) return false, 'unavailable' end
    confirmBoth(W, s)
    check('MIXED boundary: exchange committed but the response was lost -> status "committed" lets the saga continue; no refund, no second exchange', row(W, s.id).status == 'completed' and W.invDb.count(2, 'water') == 4 and #W.invDb.ledger == 1 and W.wallets[1] == 4300 and W.wallets[2] == 5700)

    -- exchange definitely fails after the debits (inventory changed between validation and execution)
    W, s = mixed()
    W.beforeExecute = function() W.invDb.rowsOf(1)[1].quantity = 1 end
    confirmBoth(W, s)
    check('MIXED boundary: the exchange is refused after the debits -> both refunded, nothing exchanged', row(W, s.id).status == 'rolled_back' and W.wallets[1] == 5000 and W.wallets[2] == 5000 and committedRows(W) == 0)

    -- inventory unavailable at recovery time: never guess
    W, s = mixed()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    W.bridgeDown = true
    W.T.Reconcile()
    check('MIXED recovery with the inventory unavailable leaves the journal untouched (no guess, no refund)', row(W, s.id).status == 'needs_reconciliation' and W.wallets[1] == 4000)
    W.bridgeDown = false; W.T.Reconcile()
    check('MIXED recovery resumes once the inventory is back', row(W, s.id).status == 'rolled_back' and W.wallets[1] == 5000)

    -- restart: a fresh cm-trade against the same databases
    W, s = mixed()
    W.T.TestCrashAt = 'items_done'
    confirmBoth(W, s)
    local W2 = build({ invDb = W.invDb, tradeDb = W.tradeDb, wallets = W.wallets, ledger = W.ledger })
    W2.T.Reconcile()
    check('RESTART item exchange committed but the trade status stale: a restarted cm-trade completes it without a second exchange', row(W2, s.id).status == 'completed' and #W.invDb.ledger == 1 and W.wallets[1] == 4300 and W.wallets[2] == 5700)
    W, s = mixed()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    local W3 = build({ invDb = W.invDb, tradeDb = W.tradeDb, wallets = W.wallets, ledger = W.ledger })
    W3.T.Reconcile()
    check('RESTART not-applied exchange: a restarted cm-trade safely refunds', row(W3, s.id).status == 'rolled_back' and W.wallets[1] == 5000 and W.wallets[2] == 5000 and committedRows(W) == 0)

    -- disconnect boundaries
    W, s = mixed()
    W.T.DropPlayer(101)
    check('DISCONNECT before confirmation: the trade is cancelled, nothing moves', s.state == 'cancelled' and s.endReason == 'disconnected' and W.invDb.count(2, 'water') == 0 and #W.ledger == 0)
    W, s = mixed()
    W.T.Confirm(101, s.id, s.rev); W.offline[101] = true
    W.T.Confirm(102, s.id, s.rev)
    check('DISCONNECT after both confirmations but before anything moved: refused deterministically, nothing moves', s.state == 'cancelled' and #W.ledger == 0 and #W.invDb.ledger == 0)
    W, s = mixed()
    W.T.Confirm(101, s.id, s.rev)
    W.beforeExecute = nil
    local origDebit = W.P.money.debit
    W.P.money.debit = function(cid, amount, reason) if cid == 2 then W.offline[102] = true end return origDebit(cid, amount, reason) end
    W.T.Confirm(102, s.id, s.rev)
    check('DISCONNECT during settlement (B drops while debiting): deterministic outcome, cash restored, no items moved', row(W, s.id).status == 'rolled_back' and W.wallets[1] == 5000 and W.invDb.count(2, 'water') == 0 and #W.invDb.ledger == 0)
    W, s = mixed()
    W.T.TestCrashAt = 'items_done'
    confirmBoth(W, s)
    W.T.DropPlayer(101); W.T.DropPlayer(102)
    W.T.Reconcile()
    check('DISCONNECT after the item commit, before trade finalization: both leave, recovery still completes (offline-safe credits)', row(W, s.id).status == 'completed' and W.wallets[1] == 4300 and W.wallets[2] == 5700)
end

-- ============================================================ SETTLEMENT RECONCILIATION HARDENING (pending / fence / re-execute)
-- REAL cm-trade core + adapter against the REAL cm-inventory exchange (durable prepared -> committed | not_applied ledger).
-- The in-flight item transaction is held with an inventory failpoint and a cooperative coroutine (no sleeps); lease expiry uses a controllable clock.
do
    local Sched = H.Sched
    local function mixed2()
        local W = build()
        W.clock = os.time()
        W.invW.env.os = setmetatable({ time = function() return W.clock end }, { __index = os })
        inv(W.invDb, 1, { { 'pocket-1', 'water', 10 } }); inv(W.invDb, 2, { { 'pocket-1', 'sandwich', 4 } })
        local s = open(W)
        W.T.AddItem(101, s.id, snapRef(W, 1, 'water').ref, 4); W.T.AddItem(102, s.id, snapRef(W, 2, 'sandwich').ref, 2)
        W.T.SetCash(101, s.id, 1000); W.T.SetCash(102, s.id, 300)
        return W, s
    end
    local function restart(W) local W2 = build({ invDb = W.invDb, invW = W.invW, tradeDb = W.tradeDb, wallets = W.wallets, ledger = W.ledger }); W2.clock = W.clock; return W2 end
    -- the exact payload cm-trade submits, rebuilt from the journal (what a restarted cm-trade would send)
    local function payloadOf(W, ref)
        local r = row(W, ref); local saved = W.env.json.decode(r.items_json)
        return { characterId = r.char_a, lines = saved.a }, { characterId = r.char_b, lines = saved.b }
    end
    local function holdAt(W, point, gate)
        W.invW.env.CMInventory.SetCraftFailpoint(function(name) if name == point and not gate.open then gate.reached = true; while not gate.open do coroutine.yield() end end end)
    end
    local function fullyDone(W, ref)
        local r = row(W, ref)
        return r.status == 'completed' and W.invDb.count(1, 'water') == 6 and W.invDb.count(2, 'water') == 4 and W.invDb.count(1, 'sandwich') == 2 and W.invDb.count(2, 'sandwich') == 2
            and W.wallets[1] == 5000 - 1000 + 300 and W.wallets[2] == 5000 - 300 + 1000 and committedRows(W) == 1
    end
    local function refunded(W) for _, e in ipairs(W.ledger) do if e.reason:find(':refund') then return true end end return false end

    -- ---------------------------------------------------------- ACCEPTANCE: the original race
    local W, s = mixed2()
    W.T.TestCrashAt = 'debited'                                   -- cm-trade debited both players, then crashed right before/while submitting
    confirmBoth(W, s)
    local ref = s.id
    check('RACE setup: both debited, journal needs_reconciliation, owner has never seen the reference', row(W, ref).status == 'needs_reconciliation' and W.wallets[1] == 4000 and W.wallets[2] == 4700
        and W.invW.registry.GetItemExchangeStatus(ref) == 'not_submitted')
    local sa, sb = payloadOf(W, ref)
    local gate = { open = false }
    holdAt(W, 'exchange_after_lock_both', gate)
    local res
    Sched.spawn(function() W.invW.invoker = 'cm-trade'; res = { W.invW.registry.ExecuteItemExchange(ref, sa, sb) } end)   -- the submitted call, still in flight
    local W2 = restart(W)                                         -- fresh cm-trade (empty memory) runs recovery while the exchange is in flight
    local duringStatus, stDuring, refundedDuring, walletsDuring
    Sched.spawn(function()
        coroutine.yield(); coroutine.yield()
        duringStatus = W2.P.items.status(ref)
        W2.T.Reconcile()
        stDuring = row(W2, ref); refundedDuring = refunded(W2); walletsDuring = { W2.wallets[1], W2.wallets[2] }
        gate.open = true
    end)
    Sched.run()
    check('RACE recovery sees the in-flight exchange as pending (not not_applied, not not_submitted)', gate.reached == true and duringStatus == 'pending', duringStatus)
    check('RACE recovery while pending does NOT refund and keeps both debits', refundedDuring == false and walletsDuring[1] == 4000 and walletsDuring[2] == 4700 and stDuring.status == 'needs_reconciliation' and stDuring.detail == 'items_pending')
    check('RACE the held exchange then commits once', res[1] == true and res[2].replayed == false and W.invDb.count(2, 'water') == 4 and committedRows(W) == 1)
    W2.T.Reconcile()
    check('RACE recovery now sees committed and moves FORWARD: credits settle, trade completed, consistent final state', fullyDone(W2, ref) and not refunded(W2))
    W2.T.Reconcile(); W2.T.Reconcile()
    check('RACE repeated recovery changes nothing (no duplicate cash, no second exchange)', fullyDone(W2, ref))
    W.invW.env.CMInventory.SetCraftFailpoint(nil)

    -- ---------------------------------------------------------- LEGACY MODEL: the old unsafe outcome (status semantics 'not committed => not_applied')
    W, s = mixed2()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    ref = s.id
    sa, sb = payloadOf(W, ref)
    gate = { open = false }
    holdAt(W, 'exchange_after_lock_both', gate)
    res = nil
    Sched.spawn(function() W.invW.invoker = 'cm-trade'; res = { W.invW.registry.ExecuteItemExchange(ref, sa, sb) } end)
    W2 = restart(W)
    local realStatus = W2.P.items.status
    W2.P.items.status = function(r) local st = realStatus(r); if st == 'pending' or st == 'not_submitted' then return 'not_applied' end return st end   -- LEGACY GetItemExchangeStatus: no committed row => not_applied
    Sched.spawn(function() coroutine.yield(); coroutine.yield(); W2.T.Reconcile(); gate.open = true end)
    Sched.run()
    W2.P.items.status = realStatus
    check('LEGACY MODEL (old semantics) reproduces the inconsistency: cash refunded AND items exchanged', refunded(W2) == true and res[1] == true and W.invDb.count(2, 'water') == 4 and W.invDb.count(1, 'sandwich') == 2,
        'refunded=' .. tostring(refunded(W2)))
    W.invW.env.CMInventory.SetCraftFailpoint(nil)

    -- ---------------------------------------------------------- ABANDONED PENDING (executor vanished after the durable claim)
    W, s = mixed2()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    ref = s.id
    sa, sb = payloadOf(W, ref)
    W.invW.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_claim' then error('executor vanished') end end)
    pcall(function() W.invW.invoker = 'cm-trade'; W.invW.registry.ExecuteItemExchange(ref, sa, sb) end)
    W.invW.env.CMInventory.SetCraftFailpoint(nil)
    W2 = restart(W)
    W2.T.Reconcile()
    check('ABANDONED live lease: recovery waits (no refund, no double executor)', row(W2, ref).status == 'needs_reconciliation' and not refunded(W2) and committedRows(W2) == 0 and W2.wallets[1] == 4000)
    W2.clock = W2.clock + 3600; W.clock = W2.clock
    W2.T.Reconcile()
    check('ABANDONED lease expired: the SAME reference is re-executed exactly once and the trade completes', fullyDone(W2, ref) and not refunded(W2))
    W2.T.Reconcile()
    check('ABANDONED nothing repeats on later recovery', fullyDone(W2, ref))

    -- ---------------------------------------------------------- cm-trade sees pending DURING settlement (no refund, no session lie)
    W, s = mixed2()
    W.invW.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_claim' and not W.crashDone then W.crashDone = true; error('other executor died after claiming') end end)
    local ref2 = s.id
    pcall(function() local a, b = payloadOf(W, ref2) end)   -- (journal row does not exist yet; claim below is done directly with the same payload shape)
    do
        local a = { characterId = 1, lines = { { ref = snapRef(W, 1, 'water').ref, quantity = 4, fp = snapRef(W, 1, 'water').fp } } }
        local b = { characterId = 2, lines = { { ref = snapRef(W, 2, 'sandwich').ref, quantity = 2, fp = snapRef(W, 2, 'sandwich').fp } } }
        pcall(function() W.invW.invoker = 'cm-trade'; W.invW.registry.ExecuteItemExchange(ref2, a, b) end)
    end
    W.invW.env.CMInventory.SetCraftFailpoint(nil)
    confirmBoth(W, s)
    check('PENDING DURING SETTLEMENT: owner answers pending -> cash stays debited, journal needs_reconciliation/items_pending, NO refund', row(W, ref2).status == 'needs_reconciliation' and row(W, ref2).detail == 'items_pending'
        and not refunded(W) and W.wallets[1] == 4000 and W.wallets[2] == 4700 and committedRows(W) == 0)
    check('PENDING DURING SETTLEMENT: the players are told it is being finalised, not that nothing happened', (function()
        for _, e in ipairs(W.events) do if e.name == 'cm-trade:client:ended' and e.payload.message == W.T.MESSAGES.pending then return true end end return false end)())
    W.clock = W.clock + 3600; W.invW.env.os = setmetatable({ time = function() return W.clock end }, { __index = os })
    W.T.Reconcile()
    check('PENDING DURING SETTLEMENT: later recovery completes the trade forward', fullyDone(W, ref2))

    -- ---------------------------------------------------------- inventory unavailable while pending
    W, s = mixed2()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    ref = s.id
    sa, sb = payloadOf(W, ref)
    W.invW.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_claim' then error('vanished') end end)
    pcall(function() W.invW.invoker = 'cm-trade'; W.invW.registry.ExecuteItemExchange(ref, sa, sb) end)
    W.invW.env.CMInventory.SetCraftFailpoint(nil)
    W.bridgeDown = true
    W.T.Reconcile(); W.T.Reconcile()
    check('UNAVAILABLE inventory down while pending: no refund, no change', not refunded(W) and W.wallets[1] == 4000 and row(W, ref).status == 'needs_reconciliation')
    W.bridgeDown = false; W.clock = W.clock + 3600
    W.T.Reconcile()
    check('UNAVAILABLE inventory back: re-execution continues and completes forward', fullyDone(W, ref))

    -- ---------------------------------------------------------- DEFINITELY NOT APPLIED (terminal) then refund; the reference can never commit later
    W, s = mixed2()
    W.beforeExecute = function() W.invDb.rowsOf(1)[1].quantity = 1 end
    confirmBoth(W, s)
    ref = s.id
    check('NOT_APPLIED definite exchange failure -> terminal not_applied -> both refunded, nothing exchanged', row(W, ref).status == 'rolled_back' and W.wallets[1] == 5000 and W.wallets[2] == 5000 and committedRows(W) == 0
        and W.invW.registry.GetItemExchangeStatus(ref) == 'not_applied')
    W.beforeExecute = nil
    inv(W.invDb, 1, { { 'pocket-1', 'water', 10 } })
    local okLate, whyLate = W.invW.registry.ExecuteItemExchange(ref, { characterId = 1, lines = { { ref = snapRef(W, 1, 'water').ref, quantity = 4 } } }, { characterId = 2, lines = {} })
    check('NOT_APPLIED a later execute under the refunded reference is refused (refund can never be followed by a commit)', okLate == false and whyLate == 'not_applied' and committedRows(W) == 0 and W.invDb.count(2, 'water') == 0)

    -- ---------------------------------------------------------- never-submitted: fence, refund, and a late queued call can never commit
    W, s = mixed2()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    ref = s.id
    sa, sb = payloadOf(W, ref)
    W2 = restart(W)
    W2.T.Reconcile()
    check('FENCE never-submitted reference: fenced to terminal not_applied, then both refunded', row(W2, ref).status == 'rolled_back' and W2.wallets[1] == 5000 and W2.wallets[2] == 5000 and W.invW.registry.GetItemExchangeStatus(ref) == 'not_applied')
    local okQ, whyQ = W.invW.registry.ExecuteItemExchange(ref, sa, sb)
    check('FENCE the queued late submit (the RPC that was in flight when cm-trade crashed) is refused after the refund', okQ == false and whyQ == 'not_applied' and committedRows(W) == 0 and W.invDb.count(2, 'water') == 0 and W.invDb.count(1, 'water') == 10)

    -- ---------------------------------------------------------- two recovery workers on one stale pending exchange
    W, s = mixed2()
    W.T.TestCrashAt = 'debited'
    confirmBoth(W, s)
    ref = s.id
    sa, sb = payloadOf(W, ref)
    W.invW.env.CMInventory.SetCraftFailpoint(function(name) if name == 'exchange_after_claim' then error('vanished') end end)
    pcall(function() W.invW.invoker = 'cm-trade'; W.invW.registry.ExecuteItemExchange(ref, sa, sb) end)
    W.invW.env.CMInventory.SetCraftFailpoint(nil)
    W.clock = W.clock + 3600
    local Wa, Wb = restart(W), restart(W)
    W.invDb.interleave = true
    Sched.spawn(function() Wa.T.Reconcile() end)
    Sched.spawn(function() Wb.T.Reconcile() end)
    Sched.run(); W.invDb.interleave = false
    Wa.T.Reconcile()
    check('TWO WORKERS two recovery loops on one stale exchange: exactly one commit, one credit pair, consistent', fullyDone(Wa, ref) and committedRows(W) == 1)

    -- ---------------------------------------------------------- ITEM-ONLY / CASH-ONLY pending
    W = build(); W.clock = os.time(); W.invW.env.os = setmetatable({ time = function() return W.clock end }, { __index = os })
    inv(W.invDb, 1, { { 'pocket-1', 'water', 10 } }); inv(W.invDb, 2, { { 'pocket-1', 'sandwich', 4 } })
    s = open(W); W.T.AddItem(101, s.id, snapRef(W, 1, 'water').ref, 4); W.T.AddItem(102, s.id, snapRef(W, 2, 'sandwich').ref, 2)
    W.T.TestCrashAt = 'debited'     -- item-only has no debit; crash after setStatus(debited)
    confirmBoth(W, s)
    W.T.Reconcile()
    check('ITEM-ONLY crash before the exchange: fenced not_applied, journal rolled_back, nothing moved, no cash moved', row(W, s.id).status == 'rolled_back' and W.invDb.count(2, 'water') == 0 and #W.ledger == 0)
end

-- ============================================================ conservation / one active trade
do
    local W = build()
    inv(W.invDb, 1, { { 'pocket-1', 'water', 10 } }); inv(W.invDb, 2, { { 'pocket-1', 'sandwich', 4 } })
    local s = open(W)
    check('ONE ACTIVE TRADE a third party or either participant cannot start a second trade', select(2, W.T.Invite(103, 101)) == 'busy' and select(2, W.T.Invite(101, 103)) == 'busy')
    W.T.AddItem(101, s.id, snapRef(W, 1, 'water').ref, 10); W.T.AddItem(102, s.id, snapRef(W, 2, 'sandwich').ref, 4)
    local before = { w = W.invDb.count(1, 'water') + W.invDb.count(2, 'water'), s = W.invDb.count(1, 'sandwich') + W.invDb.count(2, 'sandwich') }
    confirmBoth(W, s)
    check('CONSERVATION total quantities are unchanged by the settlement', W.invDb.count(1, 'water') + W.invDb.count(2, 'water') == before.w and W.invDb.count(1, 'sandwich') + W.invDb.count(2, 'sandwich') == before.s and #W.invDb.rowsOf(1) == 1 and #W.invDb.rowsOf(2) == 1)
    check('DOUBLE SUBMIT confirming again after completion cannot settle twice', (function() local ok = W.T.Confirm(101, s.id, s.rev); return ok == false or #W.invDb.ledger == 1 end)() and #W.invDb.ledger == 1)
end

print(('\ncm-trade <-> cm-inventory exchange integration: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
