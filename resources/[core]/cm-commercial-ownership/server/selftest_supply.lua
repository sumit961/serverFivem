-- cm-commercial-ownership/server/selftest_supply.lua
-- Supply / orders section of cm_business_selftest (development only). Called from selftest.lua with the shared
-- `check` helper and the QA fixture table (type "qa", shops 5 and 6 own stock/balance columns).

local C = CMB

local SO, SO2, SM, SE = 9100040, 9100041, 9100042, 9100043
local FIXTURE = 'cm_business_qa_shops'

local SAMPLE = {
    { id = 'water', label = 'Water Bottle', category = 'consumable', retail = 15 },
    { id = 'sandwich', label = 'Sandwich', category = 'consumable', retail = 25 },
    { id = 'worms', label = 'Worms (Bait)', category = 'fishing', retail = 5 },
    { id = 'basic_rod', label = 'Basic Fishing Rod', category = 'fishing', retail = 50 },
    { id = 'pickaxe_1', label = 'Level 1 Pickaxe', category = 'tool', retail = 2500 },
    { id = 'lottery_ticket', label = 'Regular Lottery Ticket', category = 'misc', retail = 10000 },
    { id = 'coat', label = 'Representative clothing item', category = 'clothing', retail = 400 },
}

function C.RunSupplyTests(check, util)
    local S = C.Supply
    local RESOURCE = GetCurrentResourceName()
    local function rl() C.ResetRateLimits() end
    local function stock(i) return tonumber(MySQL.scalar.await(('SELECT stock FROM %s WHERE shop_id = ?'):format(FIXTURE), { tostring(i) })) end
    local function setStock(i, v) MySQL.update.await(('UPDATE %s SET stock = ? WHERE shop_id = ?'):format(FIXTURE), { v, tostring(i) }) end
    local function balance(i) return C.GetBusinessBalance('qa', tostring(i)) end
    local function setBalance(i, v) MySQL.update.await(('UPDATE %s SET business_balance = ? WHERE shop_id = ?'):format(FIXTURE), { v, tostring(i) }) end
    local function setOwner(i, cid) MySQL.update.await(('UPDATE %s SET owner_character_id = ?, owner_name = ? WHERE shop_id = ?'):format(FIXTURE), { cid, cid and 'QA' or nil, tostring(i) }) end
    local function place(actor, i, lines, key) rl(); return S.Place(actor, 'qa', tostring(i), { lines = lines, idempotencyKey = key }) end
    local function order(ref) return C.SupplyGetOrder(ref) end
    local function count(sql, ...) return tonumber(MySQL.scalar.await(sql, { ... })) or 0 end
    local function asProvider(name, fn) local old = C.TestInvoker; C.TestInvoker = name; local a, b, c = fn(); C.TestInvoker = old; return a, b, c end
    local PROV = 'cm-trucking'
    local W = { { id = 'water', qty = 10 } }          -- 10 x 9 = 90 units cost
    local function fund(i, amount) MySQL.update.await(('UPDATE %s SET business_balance = ? WHERE shop_id = ?'):format(FIXTURE), { amount, tostring(i) }) end

    -- Broker test double: records what the source publishes / cancels. The real broker has its own self-test.
    local brokerLog = { created = {}, cancels = {}, payload = {} }
    local brokerMode, cancelAnswer = 'ok', true
    C.TestBroker = {
        CreateContract = function(data)
            if brokerMode == 'down' then error('broker down') end
            brokerLog.created[data.sourceReference] = (brokerLog.created[data.sourceReference] or 0) + 1
            brokerLog.payload[data.sourceReference] = data
            return true, { reference = 'CT-QA' .. data.sourceReference:gsub('[^%w]', ''):sub(1, 10), existing = brokerLog.created[data.sourceReference] > 1 }
        end,
        CancelContract = function(ctype, sref, reason) brokerLog.cancels[#brokerLog.cancels + 1] = sref; return cancelAnswer end,
    }
    local function asBroker(fn) return asProvider('cm-contracts', fn) end
    local function ctx(ref2, extra)
        local t = { sourceReference = ref2, reference = order(ref2) and order(ref2).contract_ref or 'CT-NONE' }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end

    C.TestCatalog = { qa = function() return SAMPLE end }
    local base = C.supplyTypes.store
    C.supplyTypes.qa = {
        fulfillment = 'external', cargoClass = 'general', source = 'test', unit = 'units', capacity = 500, maxLineQuantity = 100, maxOrderUnits = 200,
        wholesale = { percent = 0.60, floor = 1, categories = { consumable = { floor = 2 }, special = { percent = 0.5 } }, items = { fixedthing = { fixed = 7 } } },
    }
    local tcfg = C.supplyTypes.qa

    -- ---- WHOLESALE MODEL ----------------------------------------------------------------------------------
    local unit = S.WholesaleUnit
    check('wholesale.percent_applied', unit(tcfg, SAMPLE[1]) == 9 and unit(tcfg, SAMPLE[2]) == 15 and unit(tcfg, SAMPLE[5]) == 1500 and unit(tcfg, SAMPLE[6]) == 6000)
    check('wholesale.low_price_floor', unit(tcfg, { id = 'x', category = 'consumable', retail = 1 }) == 2 and unit(tcfg, { id = 'x', category = 'misc', retail = 1 }) == 1)
    check('wholesale.no_float_drift', unit(tcfg, { id = 'x', category = 'misc', retail = 15 }) == 9 and unit(tcfg, { id = 'x', category = 'misc', retail = 5 }) == 3)
    check('wholesale.category_override', unit(tcfg, { id = 'x', category = 'special', retail = 100 }) == 50)
    check('wholesale.item_fixed_override', unit(tcfg, { id = 'fixedthing', category = 'misc', retail = 100 }) == 7)
    check('wholesale.invalid_retail_rejected', unit(tcfg, { id = 'x', retail = 0 }) == nil and unit(tcfg, { id = 'x', retail = -5 }) == nil and unit(tcfg, { id = 'x', retail = nil }) == nil)
    check('wholesale.invalid_percent_rejected', unit({ wholesale = { percent = 0, floor = 1 } }, { id = 'x', retail = 10 }) == nil and unit({ wholesale = { percent = 1.5, floor = 1 } }, { id = 'x', retail = 10 }) == nil)
    local bad = 0
    print('[cm-commercial-ownership:selftest] MARGIN  item                    retail  wholesale  owner@normal(80%)  margin  margin@LOW(0.85)')
    for _, it in ipairs(SAMPLE) do
        local w = unit(tcfg, it)
        local owner = math.floor(it.retail * 0.8)
        local low = math.floor(math.ceil(it.retail * 0.85) * 0.8)
        print(('[cm-commercial-ownership:selftest] MARGIN  %-22s %7d %10d %18d %7d %17d'):format(it.id, it.retail, w, owner, owner - w, low - w))
        if owner - w <= 0 or low - w < 0 then bad = bad + 1 end
    end
    check('wholesale.sample_margins_positive_at_every_tier', bad == 0, bad)
    local realBad = {}
    if GetResourceState('cm-store') == 'started' then
        local ok, list = pcall(function() return exports['cm-store']:GetCatalog() end)
        if ok and type(list) == 'table' and #list > 0 then
            local real = C.supplyTypes.store
            for _, e in ipairs(list) do
                local w = unit(real, { id = e.name, category = e.category, retail = e.price })
                local low = math.floor(math.ceil(e.price * 0.85) * 0.8)
                if not w or low < w then realBad[#realBad + 1] = e.name end
            end
            check('wholesale.real_store_catalog_never_loses_money_at_low_tier', #realBad == 0, table.concat(realBad, ','))
        end
    end

    -- ---- REAL CATALOG SOURCES (read-only) -------------------------------------------------------------------------
    local sMap, sList = S.Catalog('store')
    check('real.store_catalog_from_cm_store', GetResourceState('cm-store') ~= 'started' or (sList ~= nil and #sList >= 20 and sMap.water ~= nil and sMap.water.unitCost == 9 and sMap.lottery_ticket.unitCost == 6000))
    local gMap = S.Catalog('gasstation')
    local gasUnit = gMap and gMap.fuel and gMap.fuel.unitCost
    check('real.gas_commodity_line_priced_at_half_base', gasUnit == 4)
    print(('[cm-commercial-ownership:selftest] MARGIN  gas fuel/unit: wholesale %s vs owner share LOW %.1f / NORMAL %.1f / HIGH %.1f'):format(tostring(gasUnit), 6 * 0.8, 8 * 0.8, 11 * 0.8))
    check('real.gas_never_loses_money_at_low_tier', gasUnit ~= nil and 6 * 0.8 >= gasUnit)
    local cMap, cList = S.Catalog('clothing')
    if cList and #cList > 0 then
        print(('[cm-commercial-ownership:selftest] MARGIN  clothing: %d category lines, first %s retail %d wholesale %d'):format(#cList, cList[1].id, cList[1].retail, cList[1].unitCost))
        check('real.clothing_categories_priced', cList[1].unitCost >= 5 and cList[1].unitCost <= cList[1].retail)
    else
        print('[cm-commercial-ownership:selftest] SKIP  real.clothing_categories (clothing_catalog empty/unavailable)')
    end
    check('real.service_only_types_have_no_supply', C.supplyTypes.barber == nil and C.supplyTypes.parking == nil)

    -- ---- ORDER CREATION --------------------------------------------------------------------------------------
    fund(5, 100000); fund(6, 100000); setStock(5, 100); setStock(6, 100)
    C.hireForTest(SO, SM, 'qa', '5', 'Manager')
    C.hireForTest(SO, SE, 'qa', '5', 'Employee')
    rl()
    check('create.owner_may_quote', (S.Quote(SO, 'qa', '5', W)) == true)
    check('create.manager_may_quote', (select(1, S.Quote(SM, 'qa', '5', W))) == true)
    check('create.employee_without_permission_denied', select(2, S.Quote(SE, 'qa', '5', W)) == 'forbidden' and select(2, S.GetCatalog(SE, 'qa', '5')) == 'forbidden')
    check('create.outsider_denied', select(2, S.Quote(9199999, 'qa', '5', W)) == 'forbidden' and select(2, S.Place(9199999, 'qa', '5', { lines = W })) == 'forbidden')
    rl(); check('create.invalid_business_rejected', select(2, S.Quote(SO, 'qa', '999', W)) == 'unknown_business' and select(2, S.Quote(SO, 'nope', '5', W)) == 'invalid_business')
    rl()
    local saved = C.supplyTypes.qa
    C.supplyTypes.qa = nil
    check('create.service_only_business_unsupported', select(2, S.Quote(SO, 'qa', '5', W)) == 'supply_unsupported')
    C.supplyTypes.qa = saved
    rl(); check('create.invalid_item_rejected', select(2, S.Quote(SO, 'qa', '5', { { id = 'nope', qty = 1 } })) == 'invalid_item' and select(2, S.Quote(SO, 'qa', '5', { { id = 5, qty = 1 } })) == 'invalid_item')
    for _, q in ipairs({ 0, -1, 1.5, 101, 'x' }) do
        rl(); check('create.quantity_rejected_' .. tostring(q), select(2, S.Quote(SO, 'qa', '5', { { id = 'water', qty = q } })) == 'invalid_quantity')
    end
    rl(); check('create.empty_and_garbage_lines_rejected', select(2, S.Quote(SO, 'qa', '5', {})) == 'invalid_lines' and select(2, S.Quote(SO, 'qa', '5', 'x')) == 'invalid_lines' and select(2, S.Quote(SO, 'qa', '5', { 'x' })) == 'invalid_lines')
    rl(); check('create.order_size_cap', select(2, S.Quote(SO, 'qa', '5', { { id = 'water', qty = 100 }, { id = 'sandwich', qty = 100 }, { id = 'worms', qty = 100 } })) == 'order_too_large')
    rl(); check('create.duplicate_line_merge_respects_cap', select(2, S.Quote(SO, 'qa', '5', { { id = 'water', qty = 100 }, { id = 'water', qty = 1 } })) == 'invalid_quantity')
    rl()
    local okq, q = S.Quote(SO, 'qa', '5', { { id = 'water', qty = 10, price = 1, unitCost = 1, total = 1 }, { id = 'pickaxe_1', qty = 2, retail = 1 } })
    check('create.price_authority_ignores_client_prices', okq == true and q.total == 10 * 9 + 2 * 1500 and q.units == 12 and q.lines[1].unitCost == 9 and q.fee == 0)
    check('create.quote_reports_capacity_and_affordability', q.capacity.capacity == 500 and q.capacity.stock == 100 and q.affordable == true)
    local before = balance(5)
    rl()
    local okp, view = S.Place(SO, 'qa', '5', { token = q.token })
    check('create.place_from_quote', okp == true and view.status == 'awaiting_fulfillment' and view.total == q.total and view.itemCount == 2)
    check('create.balance_debited_exactly_once', balance(5) == before - q.total and count("SELECT COUNT(*) FROM cm_business_transactions WHERE business_type = 'qa' AND business_id = '5' AND kind = 'supply'") == 1)
    check('create.debit_ledger_keyed_by_reference', C.ledgerByKey('supply-debit:' .. view.reference) ~= nil)
    check('create.stock_not_credited_before_delivery', stock(5) == 100)
    rl(); check('create.quote_token_single_use', select(2, S.Place(SO, 'qa', '5', { token = q.token })) == 'invalid_quote')
    rl(); local _, q2 = S.Quote(SO, 'qa', '5', W)
    rl(); check('create.foreign_quote_rejected', select(2, S.Place(SM, 'qa', '5', { token = q2.token })) == 'invalid_quote' and select(2, S.Place(SO, 'qa', '5', { token = 'garbage' })) == 'invalid_quote' and select(2, S.Place(SO, 'qa', '5', { token = 123 })) == 'invalid_quote')
    rl(); local _, q3 = S.Quote(SO, 'qa', '5', W)
    S._quotes()[q3.token].expires = os.time() - 1
    rl(); check('create.expired_quote_rejected', select(2, S.Place(SO, 'qa', '5', { token = q3.token })) == 'quote_expired')
    rl(); local _, q4 = S.Quote(SO, 'qa', '5', W)
    tcfg.wholesale.percent = 0.70
    rl(); check('create.stale_quote_price_changed_rejected', select(2, S.Place(SO, 'qa', '5', { token = q4.token })) == 'price_changed')
    tcfg.wholesale.percent = 0.60
    local balBefore = balance(5)
    local k1, v1 = place(SO, 5, W, 'idem-1')
    local k2, v2, replay = place(SO, 5, W, 'idem-1')
    check('create.idempotent_replay_returns_same_order', k1 == true and k2 == true and replay == true and v1.reference == v2.reference)
    check('create.idempotent_replay_debits_once', balance(5) == balBefore - 90 and count("SELECT COUNT(*) FROM cm_business_supply_orders WHERE idempotency_key = 'qa:5:idem-1'") == 1)
    check('create.idempotency_key_scoped_to_actor', select(2, place(SM, 5, W, 'idem-1')) == 'idempotency_conflict')
    check('create.bad_idempotency_key_rejected', select(2, place(SO, 5, W, 'bad key!')) == 'invalid_idempotency_key')
    setBalance(5, 50)
    local oc = count("SELECT COUNT(*) FROM cm_business_supply_orders WHERE business_type = 'qa' AND business_id = '5'")
    check('create.insufficient_funds_rejected_without_debit', select(2, place(SO, 5, W)) == 'insufficient_funds' and balance(5) == 50)
    check('create.insufficient_funds_leaves_no_open_order', count("SELECT COUNT(*) FROM cm_business_supply_orders WHERE business_type = 'qa' AND business_id = '5'") == oc)
    setBalance(5, 100000)
    setStock(5, 450)
    check('create.over_capacity_rejected', select(2, place(SO, 5, { { id = 'water', qty = 100 } })) == 'over_capacity')
    setStock(5, 100)

    -- ---- BROKER CONTRACT: publish + source callbacks -------------------------------------------------------------
    MySQL.query.await("DELETE FROM cm_business_supply_order_lines WHERE order_id IN (SELECT id FROM cm_business_supply_orders WHERE business_type = 'qa' AND business_id = '5')")
    MySQL.query.await("DELETE FROM cm_business_supply_events WHERE order_id IN (SELECT id FROM cm_business_supply_orders WHERE business_type = 'qa' AND business_id = '5')")
    MySQL.query.await("DELETE FROM cm_business_supply_orders WHERE business_type = 'qa' AND business_id = '5'")
    setBalance(5, 100000); setStock(5, 100)
    local _, o1 = place(SO, 5, { { id = 'water', qty = 20 }, { id = 'sandwich', qty = 10 } })
    local ref = o1.reference
    local pay = brokerLog.payload[ref] or {}
    check('contract.external_order_published_once', order(ref).contract_ref ~= nil and brokerLog.created[ref] == 1 and pay.contractType == 'business_supply' and pay.sourceReference == ref)
    check('contract.payload_is_work_facing_only', pay.total == nil and pay.subtotal == nil and pay.price == nil and pay.balance == nil and pay.metadata.units == 30 and #pay.metadata.manifest == 2 and pay.metadata.manifest[1].unitCost == nil)
    check('contract.order_stays_awaiting_fulfillment_no_claim_state', order(ref).status == 'awaiting_fulfillment' and order(ref).provider == nil)
    check('contract.untrusted_resource_cannot_complete_or_fallback', select(2, asProvider('evil-resource', function() return S.ContractComplete(ctx(ref)) end)) == 'forbidden'
        and select(2, asProvider('evil-resource', function() return S.ContractFallback(ctx(ref)) end)) == 'forbidden' and stock(5) == 100)
    check('contract.business_resource_itself_is_not_the_broker', select(2, asProvider(RESOURCE, function() return S.ContractComplete(ctx(ref)) end)) == 'forbidden')
    check('contract.legacy_provider_exports_deprecated', select(2, asProvider('cm-trucking', function() return S.Claim(ref, {}) end)) == 'deprecated_use_cm-contracts'
        and select(2, asProvider('cm-trucking', function() return S.Complete(ref, {}) end)) == 'deprecated_use_cm-contracts'
        and select(2, asProvider('cm-trucking', function() return S.ListAvailable() end)) == 'deprecated_use_cm-contracts' and stock(5) == 100)
    check('contract.cross_contract_rejected', select(2, asBroker(function() return S.ContractComplete({ sourceReference = ref, reference = 'CT-WRONG' }) end)) == 'forbidden' and stock(5) == 100)
    check('contract.unknown_order_is_terminal_for_broker', select(2, asBroker(function() return S.ContractComplete({ sourceReference = 'SUP-NOPE', reference = 'CT-X' }) end)) == 'source_terminal')
    cancelAnswer = false
    rl(); check('lifecycle.business_cancel_blocked_when_broker_reports_work_in_flight', select(2, S.Cancel(SO, 'qa', '5', ref)) == 'invalid_state' and order(ref).status == 'awaiting_fulfillment')
    cancelAnswer = true
    check('contract.complete_mismatch_rejected', select(2, asBroker(function() return S.ContractComplete(ctx(ref, { payload = { lines = { { id = 'water', qty = 19 }, { id = 'sandwich', qty = 10 } } } })) end)) == 'delivery_mismatch'
        and select(2, asBroker(function() return S.ContractComplete(ctx(ref, { payload = { lines = 'x' } })) end)) == 'invalid_provider_data' and stock(5) == 100)
    local dok, dres = asBroker(function() return S.ContractComplete(ctx(ref, { payload = { lines = { { id = 'water', qty = 20 }, { id = 'sandwich', qty = 10 } } } })) end)
    check('lifecycle.player_completion_credits_stock_exactly_once', dok == true and dres.units == 30 and stock(5) == 130 and order(ref).status == 'delivered')
    local rok, rres = asBroker(function() return S.ContractComplete(ctx(ref)) end)
    check('lifecycle.completion_replay_is_noop', rok == true and rres.replayed == true and stock(5) == 130)
    local fok, fres = asBroker(function() return S.ContractFallback(ctx(ref, { attempt = 1 })) end)
    check('lifecycle.fallback_after_delivery_is_noop', fok == true and fres.replayed == true and stock(5) == 130)
    check('lifecycle.delivered_cannot_cancel', (function() rl(); return select(2, S.Cancel(SO, 'qa', '5', ref)) == 'invalid_state' end)())
    check('lifecycle.stock_journal_single_row', count("SELECT COUNT(*) FROM cm_business_supply_events WHERE order_id = ? AND journal_key = 'stock'", order(ref).id) == 1)
    check('lifecycle.other_business_stock_untouched', stock(6) == 100)
    check('lifecycle.delivery_does_not_move_money', balance(5) == 100000 - (20 * 9 + 10 * 15))

    -- deadline fallback: the SOURCE credits stock, exactly once, without a worker
    local _, ofb = place(SO, 5, { { id = 'water', qty = 10 } })
    local sfb = stock(5)
    local fb1 = asBroker(function() return S.ContractFallback(ctx(ofb.reference, { attempt = 1 })) end)
    local fb2, fbr = asBroker(function() return S.ContractFallback(ctx(ofb.reference, { attempt = 2 })) end)
    check('fallback.source_credits_stock_once_and_replays', fb1 == true and fb2 == true and fbr.replayed == true and stock(5) == sfb + 10 and order(ofb.reference).status == 'delivered')
    check('fallback.records_fallback_event_once', count("SELECT COUNT(*) FROM cm_business_supply_events WHERE order_id = ? AND kind = 'fallback_delivered'", order(ofb.reference).id) == 1)
    check('fallback.delivery_does_not_move_money', balance(5) == 100000 - (20 * 9 + 10 * 15) - 90)
    setStock(5, 100)

    local _, o2 = place(SO, 5, { { id = 'water', qty = 40 } })
    setStock(5, 480)
    check('stock.capacity_enforced_at_delivery', select(2, asBroker(function() return S.ContractComplete(ctx(o2.reference)) end)) == 'over_capacity' and stock(5) == 480 and order(o2.reference).status == 'awaiting_fulfillment')
    check('stock.fallback_over_capacity_is_retryable_before_attempt_8', select(2, asBroker(function() return S.ContractFallback(ctx(o2.reference, { attempt = 3 })) end)) == 'over_capacity' and order(o2.reference).status == 'awaiting_fulfillment')
    setStock(5, 100)
    local results, done = {}, 0
    C.TestInvoker = 'cm-contracts'
    for k = 1, 5 do
        CreateThread(function() results[k] = table.pack(S.ContractComplete(ctx(o2.reference))); done = done + 1 end)
    end
    local waited = 0
    while done < 5 and waited < 10000 do Wait(20); waited = waited + 20 end
    C.TestInvoker = RESOURCE
    check('stock.concurrent_completion_credits_once', stock(5) == 140 and order(o2.reference).status == 'delivered', ('stock=%s'):format(tostring(stock(5))))
    local pFall = {}
    local _, o2b = place(SO, 5, { { id = 'water', qty = 10 } })
    setStock(5, 100)
    C.TestInvoker = 'cm-contracts'
    local done2 = 0
    CreateThread(function() pFall[1] = table.pack(S.ContractComplete(ctx(o2b.reference))); done2 = done2 + 1 end)
    CreateThread(function() pFall[2] = table.pack(S.ContractFallback(ctx(o2b.reference, { attempt = 1 }))); done2 = done2 + 1 end)
    waited = 0
    while done2 < 2 and waited < 10000 do Wait(20); waited = waited + 20 end
    C.TestInvoker = RESOURCE
    check('stock.player_vs_fallback_race_credits_once', stock(5) == 110 and order(o2b.reference).status == 'delivered' and count("SELECT COUNT(*) FROM cm_business_supply_events WHERE order_id = ? AND journal_key = 'stock'", order(o2b.reference).id) == 1)

    setStock(5, 100)
    -- ---- REFUNDS --------------------------------------------------------------------------------------------------
    local b0 = balance(5)
    local _, o3 = place(SO, 5, W)
    check('refund.cancel_awaiting_refunds_once', (function() rl(); return S.Cancel(SO, 'qa', '5', o3.reference) end)() == true and balance(5) == b0 and order(o3.reference).status == 'cancelled' and order(o3.reference).refunded_at ~= nil)
    check('refund.second_cancel_rejected', (function() rl(); return select(2, S.Cancel(SO, 'qa', '5', o3.reference)) end)() == 'invalid_state' and balance(5) == b0)
    S.Reconcile(); S.Reconcile()
    check('refund.reconcile_does_not_double_refund', balance(5) == b0 and count("SELECT COUNT(*) FROM cm_business_transactions WHERE idempotency_key = ?", 'supply-refund:' .. o3.reference) == 1)
    check('refund.cross_business_cancel_rejected', (function() rl(); return select(2, S.Cancel(SO2, 'qa', '6', o3.reference)) end)() == 'order_not_found')
    local b1 = balance(5)
    local _, o4 = place(SO, 5, W)
    setStock(5, 500)
    check('refund.fallback_impossible_before_attempt_8_keeps_order', select(2, asBroker(function() return S.ContractFallback(ctx(o4.reference, { attempt = 2 })) end)) == 'over_capacity' and order(o4.reference).status == 'awaiting_fulfillment' and balance(5) == b1 - 90)
    check('refund.fallback_impossible_after_attempt_8_fails_and_refunds_once', select(2, asBroker(function() return S.ContractFallback(ctx(o4.reference, { attempt = 8 })) end)) == 'source_terminal' and order(o4.reference).status == 'failed' and balance(5) == b1)
    setStock(5, 100)
    check('refund.failed_order_reports_terminal_to_broker', select(2, asBroker(function() return S.ContractFallback(ctx(o4.reference, { attempt = 9 })) end)) == 'source_terminal' and select(2, asBroker(function() return S.ContractComplete(ctx(o4.reference)) end)) == 'source_terminal' and balance(5) == b1 and stock(5) == 100)
    -- crash between status change and refund
    local _, o5 = place(SO, 5, W)
    local b2 = balance(5)
    MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'cancelled', end_reason = 'cancelled_by_business' WHERE reference = ?", { o5.reference })
    S.Reconcile(); S.Reconcile()
    check('refund.reconcile_completes_interrupted_refund_once', balance(5) == b2 + 90 and order(o5.reference).refunded_at ~= nil)
    -- pending_payment recovery
    local ins = function(ref2, withDebit)
        MySQL.insert.await("INSERT INTO cm_business_supply_orders (reference, business_type, business_id, requested_by, status, units, subtotal, total, created_at) VALUES (?, 'qa', '5', ?, 'pending_payment', 1, 9, 9, DATE_SUB(UTC_TIMESTAMP(), INTERVAL 5 MINUTE))", { ref2, SO })
        if withDebit then C.MoveBalance('debit', 'qa', '5', 9, { kind = 'supply', key = 'supply-debit:' .. ref2 }) end
    end
    ins('SUP-QAPAID', true); ins('SUP-QAFREE', false)
    S.Reconcile()
    check('refund.pending_payment_reconciled_by_ledger', order('SUP-QAPAID').status == 'awaiting_fulfillment' and order('SUP-QAFREE').status == 'failed')
    -- delivering recovery
    local _, o6 = place(SO, 5, W)
    MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'delivering', updated_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 5 MINUTE) WHERE reference = ?", { o6.reference })
    S.Reconcile()
    check('recovery.delivering_without_journal_reverts_to_awaiting', order(o6.reference).status == 'awaiting_fulfillment' and stock(5) == 100)
    -- publish failed at placement time (broker down): the order is published by reconciliation, once
    brokerMode = 'down'
    local _, o7 = place(SO, 5, W)
    check('recovery.broker_down_order_stays_unpublished_but_open', order(o7.reference).contract_ref == nil and order(o7.reference).status == 'awaiting_fulfillment')
    brokerMode = 'ok'
    S.Reconcile()
    check('recovery.reconcile_publishes_unpublished_order', order(o7.reference).contract_ref ~= nil and brokerLog.created[o7.reference] == 1)
    S.Reconcile()
    check('recovery.republish_is_idempotent', brokerLog.created[o7.reference] == 1 and S.Reconcile() == 0)
    MySQL.query.await("UPDATE cm_business_supply_orders SET status = 'cancelled', refunded_at = UTC_TIMESTAMP() WHERE business_type = 'qa' AND business_id = '5' AND status = 'awaiting_fulfillment'")

    -- ---- FULFILLMENT MODES ------------------------------------------------------------------------------------------
    tcfg.fulfillment = 'instant'
    local s0 = stock(5)
    local iok, iv = place(SO, 5, { { id = 'water', qty = 5 } })
    check('modes.instant_supplier_delivers_immediately_once', iok == true and iv.status == 'delivered' and stock(5) == s0 + 5)
    tcfg.fulfillment = 'scheduled'
    local sok, sv = place(SO, 5, { { id = 'water', qty = 5 } })
    check('modes.scheduled_waits', sok == true and sv.status == 'awaiting_fulfillment' and order(sv.reference).contract_ref == nil and brokerLog.created[sv.reference] == nil)
    MySQL.update.await("UPDATE cm_business_supply_orders SET created_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 60 MINUTE) WHERE reference = ?", { sv.reference })
    S.Reconcile()
    check('modes.scheduled_delivers_after_delay_once', order(sv.reference).status == 'delivered' and stock(5) == s0 + 10 and S.Reconcile() == 0)
    tcfg.fulfillment = 'external'

    -- ---- OPEN ORDER LIMIT -------------------------------------------------------------------------------------------------
    MySQL.query.await("UPDATE cm_business_supply_orders SET status = 'cancelled', refunded_at = UTC_TIMESTAMP() WHERE business_type = 'qa' AND business_id = '5' AND status IN ('awaiting_fulfillment','in_transit','claimed')")
    setStock(5, 0)
    local made = 0
    for k = 1, Config.Supply.MaxOpenOrdersPerBusiness do if place(SO, 5, { { id = 'water', qty = 1 } }) == true then made = made + 1 end end
    check('limits.open_order_cap', made == Config.Supply.MaxOpenOrdersPerBusiness and select(2, place(SO, 5, { { id = 'water', qty = 1 } })) == 'too_many_orders')
    MySQL.query.await("UPDATE cm_business_supply_orders SET status = 'cancelled', refunded_at = UTC_TIMESTAMP() WHERE business_type = 'qa' AND business_id = '5' AND status = 'awaiting_fulfillment'")

    -- ---- MULTI-BUSINESS ISOLATION -----------------------------------------------------------------------------------------
    local _, ob = place(SO2, 6, W)
    local okl, l5 = S.List(SO, 'qa', '5', 30)
    local okl2, l6 = S.List(SO2, 'qa', '6', 30)
    local has5, has6 = false, false
    for _, o in ipairs(l5) do if o.reference == ob.reference then has5 = true end end
    for _, o in ipairs(l6) do if o.reference == ob.reference then has6 = true end end
    check('multi.orders_isolated_by_business', okl and okl2 and has6 and not has5)
    check('multi.detail_of_other_business_rejected', select(2, S.Detail(SO, 'qa', '5', ob.reference)) == 'order_not_found')
    check('multi.owner_of_other_business_forbidden', select(2, S.Quote(SO2, 'qa', '5', W)) == 'forbidden')
    check('multi.stock_isolated', stock(6) == 100)

    -- ---- OWNERSHIP CHANGE ---------------------------------------------------------------------------------------------------
    MySQL.query.await("UPDATE cm_business_supply_orders SET status = 'cancelled', refunded_at = UTC_TIMESTAMP() WHERE business_type = 'qa' AND business_id = '5' AND status = 'awaiting_fulfillment'")
    setBalance(5, 100000); setStock(5, 100)
    local _, oa = place(SO, 5, W)                 -- awaiting (published)
    local _, ot = place(SO, 5, { { id = 'water', qty = 20 } })  -- awaiting (published)
    local balOld = balance(5)
    local NEW = 9100050
    setOwner(5, NEW)
    C.Resolve('qa', '5')
    check('ownership.all_uncommitted_orders_cancelled_without_refund', order(oa.reference).status == 'cancelled' and order(oa.reference).end_reason:find('ownership_change') ~= nil and order(ot.reference).status == 'cancelled' and balance(5) == balOld and order(oa.reference).refund_amount == 0)
    check('ownership.broker_told_work_is_gone', (function() local n = 0 for _, r in ipairs(brokerLog.cancels) do if r == oa.reference or r == ot.reference then n = n + 1 end end return n >= 2 end)())
    check('ownership.cancelled_order_cannot_be_delivered_by_broker', select(2, asBroker(function() return S.ContractComplete(ctx(ot.reference)) end)) == 'source_terminal' and stock(5) == 100)
    rl(); check('ownership.old_owner_loses_order_authority', select(2, S.Detail(SO, 'qa', '5', ot.reference)) == 'forbidden' and select(2, S.Cancel(SO, 'qa', '5', oa.reference)) == 'forbidden')
    rl(); check('ownership.new_owner_can_view_business_order', (S.Detail(NEW, 'qa', '5', ot.reference)) == true)
    local _, oc2 = place(NEW, 5, W)
    setOwner(5, nil)
    C.Resolve('qa', '5')
    check('ownership.forfeited_business_orders_cancelled_nothing_minted', order(oc2.reference).status == 'cancelled' and order(oc2.reference).refund_amount == 0 and order(oc2.reference).refunded_at ~= nil)
    check('ownership.forfeited_business_rejects_new_orders', select(2, place(NEW, 5, W)) == 'no_owner')
    setOwner(5, SO)

    -- ---- ADMIN ----------------------------------------------------------------------------------------------------------------
    C.TestInvoker = RESOURCE
    setBalance(5, 100000); setStock(5, 100)
    local _, ox = place(SO, 5, W)
    local ins1 = S.AdminInspect(ox.reference)
    check('admin.inspect_shows_events', ins1 ~= nil and #ins1.events >= 2 and ins1.order.lines ~= nil)
    check('admin.list_stuck', #(S.AdminList({ stuck = true }) or {}) >= 0 and S.AdminList({}) ~= nil)
    local bx = balance(5)
    check('admin.cancel_refunds_once', S.AdminCancel(ox.reference, 'stuck order') == true and balance(5) == bx + 90 and select(2, S.AdminCancel(ox.reference, 'again')) == 'invalid_state')
    local _, oy = place(SO, 5, W)
    check('admin.dev_deliver_credits_once', S.AdminDeliver(oy.reference) == true and stock(5) == 110 and select(2, S.AdminDeliver(oy.reference)) == 'invalid_state')
    check('admin.contract_cancel_untrusted_rejected', select(2, asProvider('evil-resource', function() return S.ContractCancel(ctx(oy.reference, { reason = 'x' })) end)) == 'forbidden')
    local _, oz = place(SO, 5, W)
    local bz = balance(5)
    check('admin.contract_cancel_via_broker_refunds_once', asBroker(function() return S.ContractCancel(ctx(oz.reference, { reason = 'admin' })) end) == true and balance(5) == bz + 90
        and (select(2, asBroker(function() return S.ContractCancel(ctx(oz.reference, { reason = 'admin' })) end))).replayed == true and balance(5) == bz + 90)
    C.TestInvoker = 'evil-resource'
    check('admin.untrusted_caller_rejected', select(2, S.AdminCancel(oy.reference, 'x')) == 'forbidden' and select(2, S.AdminInspect(oy.reference)) == 'forbidden' and select(2, S.AdminDeliver(oy.reference)) == 'forbidden')
    C.TestInvoker = RESOURCE

    -- ---- RESTART / PERSISTENCE ------------------------------------------------------------------------------------------------
    local pending = count("SELECT COUNT(*) FROM cm_business_supply_orders WHERE business_type = 'qa' AND status IN ('awaiting_fulfillment','claimed','in_transit')")
    S.Reconcile()
    check('restart.open_orders_survive_reconcile_unchanged', count("SELECT COUNT(*) FROM cm_business_supply_orders WHERE business_type = 'qa' AND status IN ('awaiting_fulfillment','claimed','in_transit')") == pending)
    check('restart.schema_is_idempotent', (function() CMB.schemaReady = false; return CMB.EnsureSchema() end)() == true)

    C.TestCatalog = nil
    C.TestBroker = nil
    C.supplyTypes.qa = nil
    C.supplyTypes.store = base
end
