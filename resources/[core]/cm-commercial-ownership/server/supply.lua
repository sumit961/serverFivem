-- cm-commercial-ownership/server/supply.lua
-- Business Supply / Orders platform.
--
-- BUSINESS side (this resource): quotes, orders, wholesale pricing, payment from the business balance,
-- lifecycle, refunds, stock credit, audit. Provider claims, leases, the player-first window and the automatic
-- fallback timer belong to the generic broker (cm-contracts): this resource PUBLISHES an external order as a
-- `business_supply` contract and answers the broker's source callbacks (ContractSource*), which are the ONLY way a
-- delivery reaches stock. Physical delivery, driver pay and XP belong to the provider job (cm-trucking).
--
-- Lifecycle (server-authoritative, compare-and-swap in SQL, terminal states never reopen):
--   pending_payment -> awaiting_fulfillment            (debit succeeded; external orders are published to the broker)
--   pending_payment -> failed                          (debit failed)
--   awaiting_fulfillment -> delivering -> delivered    (player completion OR deadline fallback; stock credited exactly once)
--   awaiting_fulfillment -> cancelled                  (business cancel / admin / ownership change; refund unless forfeited)
--   awaiting_fulfillment -> failed                     (fallback impossible after repeated attempts; refund)
--   (claimed / in_transit remain in the status enum for legacy rows only; the broker owns claims now)

local C = CMB
local RESOURCE = GetCurrentResourceName()
local S = {}
C.Supply = S

local quotes = {}

local function invoker() return C.TestInvoker or GetInvokingResource() or RESOURCE end

local BROKER = 'cm-contracts'
-- pcall'd call into the broker. C.TestBroker lets the development self-test substitute a double.
local function brokerCall(name, ...)
    local args = table.pack(...)
    local fn
    if C.TestBroker then fn = C.TestBroker[name]
    elseif GetResourceState(BROKER) == 'started' then fn = function(...) return exports[BROKER][name](exports[BROKER], ...) end end
    if not fn then return false, 'broker_unavailable' end
    local res = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    if not res[1] then return false, 'broker_error' end
    return true, res[2], res[3]
end

local function supplyCfg() return Config.Supply end
local function typeCfg(t) return C.supplyTypes[t] end
C.supplyTypes = Config.Supply.Types

local function nowSql() return 'UTC_TIMESTAMP()' end

local function encode(t)
    local ok, s = pcall(json.encode, t or {})
    return ok and s:sub(1, 480) or '{}'
end

-- ============================================================
-- Wholesale model
-- ============================================================

-- unit = max(floor, ceil(retail * percent)); rules merge type default < category < item.
function S.WholesaleUnit(tcfg, item)
    local retail = math.floor(tonumber(item.retail) or 0)
    if retail < 1 then return nil end
    local w = tcfg.wholesale or {}
    local rule = { percent = w.percent, floor = w.floor }
    local layers = { (w.categories or {})[item.category or ''], (w.items or {})[item.id] }
    for idx = 1, 2 do
        local layer = layers[idx]
        if type(layer) == 'table' then
            if layer.percent ~= nil then rule.percent = layer.percent end
            if layer.floor ~= nil then rule.floor = layer.floor end
            if layer.fixed ~= nil then rule.fixed = layer.fixed end
        end
    end
    local unit
    if rule.fixed then
        unit = math.floor(tonumber(rule.fixed) or 0)
    else
        local pct, floor = tonumber(rule.percent), math.floor(tonumber(rule.floor) or 1)
        if not pct or pct <= 0 or pct > 1 then return nil end
        unit = math.max(floor, math.ceil(retail * pct - 1e-6))
    end
    if unit < 1 then return nil end
    return unit
end

-- ============================================================
-- Authoritative catalog sources (retail price always comes from the owner of the price)
-- ============================================================

local clothingCache = { at = 0, items = {} }

local function sourceStore()
    if GetResourceState('cm-store') ~= 'started' then return nil end
    local ok, list = pcall(function() return exports['cm-store']:GetCatalog() end)
    if not ok or type(list) ~= 'table' then return nil end
    local out = {}
    for _, e in ipairs(list) do
        out[#out + 1] = { id = tostring(e.name), label = tostring(e.label or e.name), category = tostring(e.category or 'misc'), retail = tonumber(e.price) }
    end
    return out
end

local function sourceClothing()
    if os.time() - clothingCache.at < 60 and #clothingCache.items > 0 then return clothingCache.items end
    local ok, rows = pcall(function()
        return MySQL.query.await("SELECT category, COUNT(*) AS n, AVG(price) AS avg_price FROM clothing_catalog WHERE enabled = 1 AND price > 0 AND category IS NOT NULL AND category <> '' GROUP BY category ORDER BY category")
    end)
    if not ok or type(rows) ~= 'table' then return nil end
    local out = {}
    for _, r in ipairs(rows) do
        local cat = tostring(r.category):sub(1, 50)
        if cat:match('^[%w_%- ]+$') then
            out[#out + 1] = { id = 'cat:' .. cat, label = cat:sub(1, 1):upper() .. cat:sub(2) .. ' (avg item)', category = cat, retail = math.floor((tonumber(r.avg_price) or 0) + 0.5) }
        end
    end
    clothingCache = { at = os.time(), items = out }
    return out
end

local function sourceConfig(tcfg)
    local out = {}
    for _, l in ipairs(tcfg.lines or {}) do
        out[#out + 1] = { id = l.id, label = l.label, category = l.category or 'misc', retail = l.retail }
    end
    return out
end

-- Returns { [id] = { id, label, category, retail, unitCost } }, ordered list
function S.Catalog(btype)
    local tcfg = typeCfg(btype)
    if not tcfg then return nil end
    local raw
    if C.TestCatalog and C.TestCatalog[btype] then
        raw = C.TestCatalog[btype]()
    elseif tcfg.source == 'cm-store' then raw = sourceStore()
    elseif tcfg.source == 'clothing_catalog' then raw = sourceClothing()
    else raw = sourceConfig(tcfg) end
    if not raw then return nil end
    local map, list = {}, {}
    for _, item in ipairs(raw) do
        local id = tostring(item.id or '')
        if #id >= 1 and #id <= 64 and not map[id] then
            local cost = S.WholesaleUnit(tcfg, item)
            if cost then
                local entry = { id = id, label = tostring(item.label or id):sub(1, 120), category = tostring(item.category or ''):sub(1, 60), retail = math.floor(item.retail), unitCost = cost }
                map[id] = entry
                list[#list + 1] = entry
            end
        end
    end
    table.sort(list, function(a, b) if a.category ~= b.category then return a.category < b.category end return a.label < b.label end)
    return map, list
end

-- ============================================================
-- Stock adapter (the business's own table is the only stock total)
-- ============================================================

local function stockDef(btype)
    local def = C.types[btype]
    if not def or type(def.stockColumn) ~= 'string' or not def.stockColumn:match('^[%w_]+$') then return nil end
    return def
end

function S.GetStock(biz)
    local def = stockDef(biz.type)
    if not def then return nil end
    local v = MySQL.scalar.await(('SELECT `%s` FROM `%s` WHERE `%s` = ? LIMIT 1'):format(def.stockColumn, def.table, def.idColumn), { biz.id })
    return v ~= nil and math.max(0, math.floor(tonumber(v) or 0)) or nil
end

local function openUnits(biz)
    return tonumber(MySQL.scalar.await("SELECT COALESCE(SUM(units),0) FROM cm_business_supply_orders WHERE business_type = ? AND business_id = ? AND status IN ('pending_payment','awaiting_fulfillment','claimed','in_transit','delivering')", { biz.type, biz.id })) or 0
end

local function openCount(biz)
    return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_business_supply_orders WHERE business_type = ? AND business_id = ? AND status IN ('pending_payment','awaiting_fulfillment','claimed','in_transit','delivering')", { biz.type, biz.id })) or 0
end

-- ============================================================
-- Events / views
-- ============================================================

local function addEvent(orderId, kind, actorCid, provider, amount, meta)
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_business_supply_events (order_id, kind, actor_character_id, provider, amount, metadata) VALUES (?, ?, ?, ?, ?, ?)',
            { orderId, kind, actorCid, provider, amount, meta and encode(meta) or nil })
    end)
end

local function activity(order, action, actorCid, meta)
    local biz = { type = order.business_type, id = order.business_id }
    C.LogActivity(biz, action, actorCid, nil, tonumber(order.total), { order = order.reference, units = order.units, provider = order.provider, extra = meta }, action == 'supply_refunded' or action == 'supply_cancelled' or action == 'supply_admin_action')
end

local function getOrder(ref)
    if type(ref) ~= 'string' or #ref < 4 or #ref > 16 or not ref:match('^[%w%-]+$') then return nil end
    return MySQL.single.await('SELECT * FROM cm_business_supply_orders WHERE reference = ? LIMIT 1', { ref })
end

local function getLines(orderId)
    return MySQL.query.await('SELECT item_id, label, category, quantity, unit_cost, line_total FROM cm_business_supply_order_lines WHERE order_id = ? ORDER BY id', { orderId }) or {}
end

local ACTIVE = { pending_payment = true, awaiting_fulfillment = true, claimed = true, in_transit = true, delivering = true }

local function businessView(order, withLines)
    local v = {
        reference = order.reference, status = order.status, total = tonumber(order.total), units = tonumber(order.units),
        createdAt = tostring(order.created_at or ''), deliveredAt = order.delivered_at and tostring(order.delivered_at) or nil,
        endReason = order.end_reason, refunded = order.refunded_at ~= nil, canCancel = order.status == 'awaiting_fulfillment',
        fulfillment = order.fulfillment_mode,
    }
    local lines = getLines(order.id)
    v.itemCount = #lines
    if withLines then
        v.lines = {}
        for _, l in ipairs(lines) do
            v.lines[#v.lines + 1] = { id = l.item_id, label = l.label, quantity = tonumber(l.quantity), unitCost = tonumber(l.unit_cost), lineTotal = tonumber(l.line_total) }
        end
    end
    return v
end

local function notifyBusiness(order, message, kind)
    local targets = { tonumber(order.requested_by) }
    local owner = C.GetBusinessOwner(order.business_type, order.business_id)
    if owner then targets[#targets + 1] = tonumber(owner) end
    local seen = {}
    for _, cid in ipairs(targets) do
        if cid and not seen[cid] then
            seen[cid] = true
            C.notifySrc(C.sourceOfCid(cid), message, kind)
        end
    end
end

-- ============================================================
-- Money: refunds are idempotent through the business ledger key
-- ============================================================

local function refund(order, reason)
    if order.refunded_at ~= nil then return true, 'already' end
    local total = tonumber(order.total) or 0
    local ok, res = C.MoveBalance('credit', order.business_type, order.business_id, total, {
        kind = 'supply_refund', reason = 'supply refund', key = 'supply-refund:' .. order.reference, metadata = { order = order.reference, why = reason },
    })
    if ok then
        MySQL.update.await('UPDATE cm_business_supply_orders SET refunded_at = ' .. nowSql() .. ', refund_amount = ? WHERE id = ? AND refunded_at IS NULL', { total, order.id })
        addEvent(order.id, 'refunded', nil, nil, total, { why = reason, replayed = res and res.replayed or false })
        activity(order, 'supply_refunded', nil, reason)
        return true
    end
    if res == 'no_owner' or res == 'unknown_business' then
        -- The business was forfeited: the prepaid funds are forfeited with it (same as the balance they came from).
        MySQL.update.await('UPDATE cm_business_supply_orders SET refunded_at = ' .. nowSql() .. ", refund_amount = 0, end_reason = CONCAT(COALESCE(end_reason,''), '+forfeited') WHERE id = ? AND refunded_at IS NULL", { order.id })
        addEvent(order.id, 'refund_forfeited', nil, nil, total, { why = reason })
        return true, 'forfeited'
    end
    addEvent(order.id, 'refund_pending', nil, nil, total, { why = reason, error = tostring(res) })
    return false, res
end

-- Publishes an external order to the broker as work. Only work-facing facts cross: no prices, balance, refund or
-- accounting state. Idempotent on both sides (broker unique key + contract_ref IS NULL guard).
local function publish(order)
    if order.contract_ref or order.fulfillment_mode ~= 'external' or order.status ~= 'awaiting_fulfillment' then return false end
    local manifest = {}
    for _, l in ipairs(getLines(order.id)) do
        if #manifest < 12 then manifest[#manifest + 1] = { label = l.label, quantity = tonumber(l.quantity) } end
    end
    local ok, created, info = brokerCall('CreateContract', {
        contractType = 'business_supply', sourceReference = order.reference,
        title = ('Supply delivery: %s'):format(order.business_type),
        description = ('%d units of %s cargo'):format(tonumber(order.units) or 0, tostring(order.cargo_class or 'general')),
        pickupHint = supplyCfg().PickupHint, destinationHint = ('%s business'):format(order.business_type),
        cargoClass = order.cargo_class, urgency = order.urgency or 'normal',
        fallbackAfterSeconds = math.floor((tonumber(supplyCfg().ExternalFallbackMinutes) or 30) * 60),
        metadata = { units = tonumber(order.units), businessType = order.business_type, manifest = manifest },
    })
    if not (ok and created == true and type(info) == 'table' and info.reference) then return false end
    MySQL.update.await('UPDATE cm_business_supply_orders SET contract_ref = ? WHERE id = ? AND contract_ref IS NULL', { info.reference, order.id })
    addEvent(order.id, 'contract_published', nil, nil, nil, { contract = info.reference, existing = info.existing })
    return true
end

-- Moves an order to a terminal state with a compare-and-swap, then refunds (exactly once).
local function terminate(order, fromList, newStatus, reason, actorCid, provider, opts)
    opts = opts or {}
    local stamp = newStatus == 'cancelled' and 'cancelled_at' or 'failed_at'
    local marks, params = {}, { newStatus, reason }
    for _, st in ipairs(fromList) do marks[#marks + 1] = '?'; params[#params + 1] = st end
    params[#params + 1] = order.id
    local sql = 'UPDATE cm_business_supply_orders SET status = ?, end_reason = ?, ' .. stamp .. ' = UTC_TIMESTAMP(), claim_expires_at = NULL WHERE status IN (' .. table.concat(marks, ',') .. ') AND id = ?'
    local n = MySQL.update.await(sql, params)
    if n ~= 1 then return false, 'invalid_state' end
    addEvent(order.id, newStatus, actorCid, provider, tonumber(order.total), { reason = reason })
    -- Tell the broker the work is gone (best effort: if it is down, its next source callback reports source_terminal).
    if order.contract_ref then brokerCall('CancelContract', 'business_supply', order.reference, reason) end
    local fresh = getOrder(order.reference)
    activity(fresh, newStatus == 'cancelled' and 'supply_cancelled' or 'supply_failed', actorCid, reason)
    if not opts.noRefund then refund(fresh, reason) end
    notifyBusiness(fresh, ('Supply order %s %s.'):format(fresh.reference, newStatus), newStatus == 'cancelled' and 'info' or 'error')
    return true
end

-- ============================================================
-- Quote / place / cancel (business side, actor = character id)
-- ============================================================

local function randomRef()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local out = {}
    for i = 1, 6 do
        local k = math.random(1, #chars)
        out[i] = chars:sub(k, k)
    end
    return 'SUP-' .. table.concat(out)
end

local function normalizeLines(lines, tcfg)
    if type(lines) ~= 'table' or #lines < 1 or #lines > 20 then return nil, 'invalid_lines' end
    local merged, order = {}, {}
    for _, l in ipairs(lines) do
        if type(l) ~= 'table' then return nil, 'invalid_lines' end
        local id = l.id
        local qty = tonumber(l.qty or l.quantity)
        if type(id) ~= 'string' or #id < 1 or #id > 64 then return nil, 'invalid_item' end
        if not qty or qty ~= math.floor(qty) or qty < 1 or qty > tcfg.maxLineQuantity then return nil, 'invalid_quantity' end
        if not merged[id] then merged[id] = 0; order[#order + 1] = id end
        merged[id] = merged[id] + qty
        if merged[id] > tcfg.maxLineQuantity then return nil, 'invalid_quantity' end
    end
    local out = {}
    for _, id in ipairs(order) do out[#out + 1] = { id = id, qty = merged[id] } end
    return out
end

-- Server-side pricing of normalized lines. Returns priced table or nil, reason.
local function price(biz, tcfg, lines)
    local map = S.Catalog(biz.type)
    if not map then return nil, 'catalog_unavailable' end
    local priced, units, subtotal = {}, 0, 0
    for _, l in ipairs(lines) do
        local item = map[l.id]
        if not item then return nil, 'invalid_item' end
        local lineTotal = item.unitCost * l.qty
        priced[#priced + 1] = { id = item.id, label = item.label, category = item.category, qty = l.qty, retail = item.retail, unitCost = item.unitCost, lineTotal = lineTotal }
        units = units + l.qty
        subtotal = subtotal + lineTotal
    end
    if units > tcfg.maxOrderUnits then return nil, 'order_too_large' end
    return { lines = priced, units = units, subtotal = subtotal, fee = 0, total = subtotal }
end

local function supportContext(actorCid, t, i)
    if not supplyCfg().Enabled then return nil, nil, nil, 'supply_disabled' end
    local biz, ctx, why = C.authorize(actorCid, t, i, 'business.manage_orders')
    if not biz then return nil, nil, nil, why end
    local tcfg = typeCfg(biz.type)
    if not tcfg or not stockDef(biz.type) then return nil, nil, nil, 'supply_unsupported' end
    return biz, ctx, tcfg
end

local function capacityView(biz, tcfg, addUnits)
    local stock = S.GetStock(biz) or 0
    local open = openUnits(biz)
    return { stock = stock, open = open, capacity = tcfg.capacity, after = stock + open + (addUnits or 0), unit = tcfg.unit or 'units' }
end

function S.GetCatalog(actorCid, t, i)
    local biz, ctx, tcfg, why = supportContext(actorCid, t, i)
    if not biz then return false, why end
    local map, list = S.Catalog(biz.type)
    if not map then return false, 'catalog_unavailable' end
    local items = {}
    for _, e in ipairs(list) do items[#items + 1] = { id = e.id, label = e.label, category = e.category, unitCost = e.unitCost } end
    return true, { items = items, maxLine = tcfg.maxLineQuantity, maxUnits = tcfg.maxOrderUnits, capacity = capacityView(biz, tcfg, 0), fulfillment = tcfg.fulfillment }
end

function S.Quote(actorCid, t, i, rawLines)
    if C.RateLimited('c' .. tostring(actorCid), 'quote') then return false, 'rate_limited' end
    local biz, ctx, tcfg, why = supportContext(actorCid, t, i)
    if not biz then return false, why end
    local lines, lwhy = normalizeLines(rawLines, tcfg)
    if not lines then return false, lwhy end
    local priced, pwhy = price(biz, tcfg, lines)
    if not priced then return false, pwhy end
    local cap = capacityView(biz, tcfg, priced.units)
    if cap.after > tcfg.capacity then return false, 'over_capacity', cap end
    local token = ('%x%x%x'):format(math.random(0, 0xfffffff), GetGameTimer(), math.random(0, 0xfffffff))
    local expires = os.time() + supplyCfg().QuoteSeconds
    quotes[token] = { cid = tonumber(actorCid), t = biz.type, i = biz.id, epoch = biz.epoch, lines = lines, total = priced.total, expires = expires }
    return true, {
        token = token, expiresIn = supplyCfg().QuoteSeconds, lines = priced.lines, units = priced.units, subtotal = priced.subtotal, fee = priced.fee, total = priced.total,
        capacity = cap, affordable = biz.balance >= priced.total, balance = ctx.perms['business.view_finance'] and biz.balance or nil,
    }
end

local function findByKey(key)
    return MySQL.single.await('SELECT * FROM cm_business_supply_orders WHERE idempotency_key = ? LIMIT 1', { key })
end

-- opts: { token, lines, idempotencyKey }  (lines is the internal/test path; the UI always uses a quote token)
function S.Place(actorCid, t, i, opts)
    opts = type(opts) == 'table' and opts or {}
    if C.RateLimited('c' .. tostring(actorCid), 'supply') then return false, 'rate_limited' end
    local biz, ctx, tcfg, why = supportContext(actorCid, t, i)
    if not biz then return false, why end
    local key = type(opts.idempotencyKey) == 'string' and opts.idempotencyKey:match('^[%w%-_:]+$') and #opts.idempotencyKey <= 60 and (biz.type .. ':' .. biz.id .. ':' .. opts.idempotencyKey) or nil
    if opts.idempotencyKey ~= nil and not key then return false, 'invalid_idempotency_key' end
    if key then
        local existing = findByKey(key)
        if existing then
            if existing.business_type ~= biz.type or existing.business_id ~= biz.id or tonumber(existing.requested_by) ~= tonumber(actorCid) then return false, 'idempotency_conflict' end
            return true, businessView(existing, true), true
        end
    end
    local lines, quoted
    if opts.token ~= nil then
        local q = type(opts.token) == 'string' and quotes[opts.token] or nil
        if not q or q.cid ~= tonumber(actorCid) or q.t ~= biz.type or q.i ~= biz.id then return false, 'invalid_quote' end
        quotes[opts.token] = nil
        if os.time() > q.expires then return false, 'quote_expired' end
        if q.epoch ~= biz.epoch then return false, 'invalid_quote' end
        lines, quoted = q.lines, q.total
    else
        local nl, lwhy = normalizeLines(opts.lines, tcfg)
        if not nl then return false, lwhy end
        lines = nl
    end
    local ok, view, replayed, instantRef = C.withBusinessLock('supply:' .. biz.type .. ':' .. biz.id, function()
        local priced, pwhy = price(biz, tcfg, lines)
        if not priced then return false, pwhy end
        if quoted and priced.total ~= quoted then return false, 'price_changed' end
        if openCount(biz) >= supplyCfg().MaxOpenOrdersPerBusiness then return false, 'too_many_orders' end
        local cap = capacityView(biz, tcfg, priced.units)
        if cap.after > tcfg.capacity then return false, 'over_capacity' end
        if biz.balance < priced.total then return false, 'insufficient_funds' end

        local ref
        local orderId
        for _ = 1, 5 do
            ref = randomRef()
            local ok, id = pcall(function()
                return MySQL.insert.await([[INSERT INTO cm_business_supply_orders
                    (reference, business_type, business_id, requested_by, status, units, subtotal, fee, total, fulfillment_mode, cargo_class, idempotency_key, owner_epoch)
                    VALUES (?, ?, ?, ?, 'pending_payment', ?, ?, 0, ?, ?, ?, ?, ?)]],
                    { ref, biz.type, biz.id, actorCid, priced.units, priced.subtotal, priced.total, tcfg.fulfillment or 'external', tcfg.cargoClass or 'general', key, biz.epoch })
            end)
            if ok and id then orderId = id; break end
            if key then
                local existing = findByKey(key)
                if existing then return true, businessView(existing, true), true end
            end
        end
        if not orderId then return false, 'internal_error' end
        for _, l in ipairs(priced.lines) do
            MySQL.insert.await('INSERT INTO cm_business_supply_order_lines (order_id, item_id, label, category, quantity, unit_retail, unit_cost, line_total) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                { orderId, l.id, l.label, l.category, l.qty, l.retail, l.unitCost, l.lineTotal })
        end
        addEvent(orderId, 'created', actorCid, nil, priced.total, { units = priced.units })
        local ok, res = C.MoveBalance('debit', biz.type, biz.id, priced.total, {
            kind = 'supply', reason = 'supply order', key = 'supply-debit:' .. ref, actorCid = actorCid, metadata = { order = ref },
        })
        if not ok then
            MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'failed', failed_at = UTC_TIMESTAMP(), end_reason = ? WHERE id = ? AND status = 'pending_payment'", { 'payment_' .. tostring(res), orderId })
            addEvent(orderId, 'payment_failed', actorCid, nil, priced.total, { reason = res })
            return false, res == 'insufficient_funds' and 'insufficient_funds' or 'payment_failed'
        end
        MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'awaiting_fulfillment' WHERE id = ? AND status = 'pending_payment'", { orderId })
        addEvent(orderId, 'paid', actorCid, nil, priced.total)
        local order = getOrder(ref)
        activity(order, 'supply_order_created', actorCid)
        return true, businessView(getOrder(ref), true), false, tcfg.fulfillment == 'instant' and ref or nil
    end)
    if ok and instantRef then
        S.DeliverInternal(getOrder(instantRef), 'supplier')
        view = businessView(getOrder(instantRef), true)
    end
    if ok and not replayed and not instantRef and type(view) == 'table' and view.status == 'awaiting_fulfillment' and view.fulfillment == 'external' then
        publish(getOrder(view.reference)) -- a failed publish is retried by Reconcile
    end
    return ok, view, replayed
end

function S.Cancel(actorCid, t, i, ref)
    if C.RateLimited('c' .. tostring(actorCid), 'supply') then return false, 'rate_limited' end
    local biz, ctx, tcfg, why = supportContext(actorCid, t, i)
    if not biz then return false, why end
    return C.withBusinessLock('supply:' .. biz.type .. ':' .. biz.id, function()
        local order = getOrder(ref)
        if not order or order.business_type ~= biz.type or order.business_id ~= biz.id then return false, 'order_not_found' end
        if order.contract_ref then
            -- The broker decides whether work is already in flight (a delivery being applied cannot be cancelled).
            local okb, cancelled = brokerCall('CancelContract', 'business_supply', order.reference, 'cancelled_by_business')
            if not okb then return false, 'broker_unavailable' end
            if cancelled ~= true then return false, 'invalid_state' end
        end
        local ok, err = terminate(order, { 'awaiting_fulfillment' }, 'cancelled', 'cancelled_by_business', actorCid, nil)
        if not ok then return false, err end
        return true, businessView(getOrder(ref), true)
    end)
end

function S.List(actorCid, t, i, limit)
    local biz, ctx, tcfg, why = supportContext(actorCid, t, i)
    if not biz then return false, why end
    limit = math.min(30, math.max(1, math.floor(tonumber(limit) or 15)))
    local rows = MySQL.query.await('SELECT * FROM cm_business_supply_orders WHERE business_type = ? AND business_id = ? ORDER BY id DESC LIMIT ?', { biz.type, biz.id, limit }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = businessView(r, false) end
    return true, out
end

function S.Detail(actorCid, t, i, ref)
    local biz, ctx, tcfg, why = supportContext(actorCid, t, i)
    if not biz then return false, why end
    local order = getOrder(ref)
    if not order or order.business_type ~= biz.type or order.business_id ~= biz.id then return false, 'order_not_found' end
    return true, businessView(order, true)
end

-- ============================================================
-- Delivery: exactly-once stock credit
-- ============================================================

-- Order must already be in 'delivering' (claimed by the caller through CAS). Reverts to revertTo on a safe failure.
local function deliverLocked(order, provider, revertTo)
    local def = stockDef(order.business_type)
    local tcfg = typeCfg(order.business_type)
    local function revert(reason)
        MySQL.update.await("UPDATE cm_business_supply_orders SET status = ? WHERE id = ? AND status = 'delivering'", { revertTo, order.id })
        addEvent(order.id, 'delivery_rejected', nil, provider, nil, { reason = reason })
        return false, reason
    end
    if not def or not tcfg then return revert('supply_unsupported') end
    local biz = C.Resolve(order.business_type, order.business_id)
    if not biz or not biz.ownerCharacterId then return revert('no_owner') end
    local units = tonumber(order.units)
    local credited = pcall(function()
        return MySQL.transaction.await({
            { query = ('UPDATE `%s` SET `%s` = `%s` + ? WHERE `%s` = ? AND `%s` IS NOT NULL AND `%s` + ? <= ?'):format(def.table, def.stockColumn, def.stockColumn, def.idColumn, def.ownerColumn, def.stockColumn),
              values = { units, biz.id, units, tcfg.capacity } },
            { query = "INSERT INTO cm_business_supply_events (order_id, kind, provider, journal_key, amount, metadata) SELECT ?, 'stock_credited', ?, 'stock', ?, ? FROM DUAL WHERE ROW_COUNT() = 1",
              values = { order.id, provider, units, encode({ units = units }) } },
        })
    end)
    local journal = MySQL.scalar.await("SELECT id FROM cm_business_supply_events WHERE order_id = ? AND journal_key = 'stock'", { order.id })
    if not journal then
        return revert(credited and 'over_capacity' or 'stock_error')
    end
    MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'delivered', delivered_at = UTC_TIMESTAMP(), claim_expires_at = NULL WHERE id = ? AND status = 'delivering'", { order.id })
    addEvent(order.id, 'delivered', nil, provider, tonumber(order.total), { units = units })
    local fresh = getOrder(order.reference)
    activity(fresh, 'supply_delivered', nil)
    notifyBusiness(fresh, ('Supply order %s delivered: +%d stock.'):format(fresh.reference, units), 'success')
    return true, { stock = S.GetStock(biz), units = units }
end

-- CAS the order into 'delivering' from `fromStatus`, then credit. Used by instant/scheduled/admin/provider paths.
function S.DeliverFrom(order, fromStatus, provider)
    local n = MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'delivering' WHERE id = ? AND status = ?", { order.id, fromStatus })
    if n ~= 1 then return false, 'invalid_state' end
    return C.withBusinessLock('supply:' .. order.business_type .. ':' .. order.business_id, deliverLocked, order, provider, fromStatus)
end

function S.DeliverInternal(order, provider)
    return S.DeliverFrom(order, 'awaiting_fulfillment', provider)
end

-- ============================================================
-- Generic broker (cm-contracts) source callbacks. Caller must be the broker; every callback is idempotent.
-- Result contract: true[, data] | false, reason   ('source_terminal' = the order is over, stop retrying)
-- ============================================================

local function brokerOnly() return invoker() == BROKER end

-- Resolves the order a broker callback refers to and rejects a contract that does not belong to it.
local function brokerOrder(ctx)
    if not brokerOnly() then return nil, 'forbidden' end
    if type(ctx) ~= 'table' or type(ctx.sourceReference) ~= 'string' or type(ctx.reference) ~= 'string' then return nil, 'invalid_request' end
    local order = getOrder(ctx.sourceReference)
    if not order then return nil, 'source_terminal' end
    if order.contract_ref and order.contract_ref ~= ctx.reference then return nil, 'forbidden' end -- cross-contract
    return order
end

-- Delivery for a worker (player) or for the deadline fallback. Both go through the same exactly-once stock credit.
local function brokerDeliver(order, provider)
    if order.status == 'delivered' then return true, { replayed = true } end
    if order.status == 'cancelled' or order.status == 'failed' then return false, 'source_terminal' end
    if order.status == 'delivering' then return false, 'busy' end
    if order.status ~= 'awaiting_fulfillment' then return false, 'invalid_state' end
    return S.DeliverFrom(order, 'awaiting_fulfillment', provider)
end

function S.ContractComplete(ctx)
    local order, why = brokerOrder(ctx)
    if not order then return false, why end
    -- V1 is full-order fulfilment: if the provider reports quantities they must match exactly.
    local payload = ctx.payload
    if type(payload) == 'table' and payload.lines ~= nil then
        if type(payload.lines) ~= 'table' then return false, 'invalid_provider_data' end
        local expected, n, seen = {}, 0, 0
        for _, l in ipairs(getLines(order.id)) do expected[l.item_id] = tonumber(l.quantity); n = n + 1 end
        for _, l in ipairs(payload.lines) do
            if type(l) ~= 'table' or expected[l.id] ~= tonumber(l.qty or l.quantity) then return false, 'delivery_mismatch' end
            seen = seen + 1
        end
        if seen ~= n then return false, 'delivery_mismatch' end
    end
    return brokerDeliver(order, 'contract:player')
end

function S.ContractFallback(ctx)
    local order, why = brokerOrder(ctx)
    if not order then return false, why end
    local ok, res = brokerDeliver(order, 'supplier')
    if ok then
        if not (type(res) == 'table' and res.replayed) then addEvent(order.id, 'fallback_delivered', nil, 'supplier', nil, { attempt = ctx.attempt }) end
        return true, res
    end
    -- A delivery that can never succeed (over capacity / ownerless) must not retry forever: fail + refund the business.
    if (res == 'over_capacity' or res == 'no_owner' or res == 'supply_unsupported') and (tonumber(ctx.attempt) or 0) >= 8 then
        terminate(order, { 'awaiting_fulfillment' }, 'failed', 'fallback_failed:' .. res, nil, 'supplier')
        return false, 'source_terminal'
    end
    return false, res
end

-- Admin cancel routed by the broker: this resource decides whether it permits it and refunds exactly once.
function S.ContractCancel(ctx)
    local order, why = brokerOrder(ctx)
    if not order then return false, why == 'source_terminal' and 'invalid_state' or why end
    if order.status == 'cancelled' then return true, { replayed = true } end
    local reason = tostring(ctx.reason or 'cancel'):gsub('[^%w_%-]', ''):sub(1, 25)
    local ok, err = terminate(order, { 'awaiting_fulfillment', 'pending_payment' }, 'cancelled', 'admin:' .. reason, nil, 'admin')
    if ok then return true end
    return false, err
end

-- Best-effort progress notices (the broker holds claim state; this resource keeps no copy of it).
function S.ContractEvent(ctx)
    local order = brokerOrder(ctx)
    if not order or type(ctx.event) ~= 'string' then return false end
    if ctx.event == 'claimed' then notifyBusiness(order, ('Supply order %s accepted by a carrier.'):format(order.reference), 'info')
    elseif ctx.event == 'active' then notifyBusiness(order, ('Supply order %s is on its way.'):format(order.reference), 'info') end
    addEvent(order.id, 'contract_' .. ctx.event:gsub('[^%w_]', ''):sub(1, 20), nil, BROKER)
    return true
end

-- Deprecated provider exports. There is ONE claim system (cm-contracts); these fail closed with a clear reason so a
-- stale provider cannot silently use a second path.
local function deprecated() return false, 'deprecated_use_cm-contracts' end
S.ListAvailable = function() return nil, 'deprecated_use_cm-contracts' end
S.Claim, S.Release, S.InTransit, S.Complete, S.Fail = deprecated, deprecated, deprecated, deprecated, deprecated
S.ProviderStatus = function() return nil, 'deprecated_use_cm-contracts' end

-- ============================================================
-- Reconciliation / sweeps
-- ============================================================

function S.Reconcile()
    if not C.EnsureSchema() then return 0 end
    local fixed = 0
    -- Payment started but the order never left pending_payment (crash): the ledger decides.
    for _, o in ipairs(MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status = 'pending_payment' AND created_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 60 SECOND)") or {}) do
        if C.ledgerByKey('supply-debit:' .. o.reference) then
            MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'awaiting_fulfillment' WHERE id = ? AND status = 'pending_payment'", { o.id })
            addEvent(o.id, 'reconciled_paid')
        else
            MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'failed', failed_at = UTC_TIMESTAMP(), end_reason = 'payment_incomplete' WHERE id = ? AND status = 'pending_payment'", { o.id })
            addEvent(o.id, 'reconciled_unpaid')
        end
        fixed = fixed + 1
    end
    -- Delivery started but not finished: the stock journal decides.
    for _, o in ipairs(MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status = 'delivering' AND updated_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 60 SECOND)") or {}) do
        if MySQL.scalar.await("SELECT id FROM cm_business_supply_events WHERE order_id = ? AND journal_key = 'stock'", { o.id }) then
            MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'delivered', delivered_at = UTC_TIMESTAMP() WHERE id = ? AND status = 'delivering'", { o.id })
            addEvent(o.id, 'reconciled_delivered')
        else
            MySQL.update.await("UPDATE cm_business_supply_orders SET status = ? WHERE id = ? AND status = 'delivering'", { o.contract_ref and 'awaiting_fulfillment' or 'in_transit', o.id })
            addEvent(o.id, 'reconciled_undelivered')
        end
        fixed = fixed + 1
    end
    -- Expired claims go back to the board.
    fixed = fixed + (MySQL.update.await("UPDATE cm_business_supply_orders SET status = 'awaiting_fulfillment', provider = NULL, provider_ref = NULL, claim_expires_at = NULL WHERE status = 'claimed' AND claim_expires_at < UTC_TIMESTAMP()") or 0)
    -- In-transit orders that never complete are failed and refunded.
    for _, o in ipairs(MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status = 'in_transit' AND transit_deadline < UTC_TIMESTAMP()") or {}) do
        terminate(o, { 'in_transit' }, 'failed', 'transit_timeout', nil, o.provider)
        fixed = fixed + 1
    end
    -- External orders whose publish failed (broker down at placement time) are published now; idempotent.
    for _, o in ipairs(MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status = 'awaiting_fulfillment' AND fulfillment_mode = 'external' AND contract_ref IS NULL ORDER BY id LIMIT 20") or {}) do
        if publish(o) then fixed = fixed + 1 end
    end
    -- Safety net ONLY while the broker is not running: an unpublished external order is never stranded.
    if not C.TestBroker and GetResourceState(BROKER) ~= 'started' then
        for _, o in ipairs(MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status = 'awaiting_fulfillment' AND fulfillment_mode = 'external' AND contract_ref IS NULL AND created_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL ? MINUTE) LIMIT 20", { tonumber(supplyCfg().BrokerDownFallbackMinutes) or 90 }) or {}) do
            S.DeliverInternal(o, 'supplier')
            fixed = fixed + 1
        end
    end
    -- 'scheduled' = NPC-only supplier mode: never published to the broker, no player work, so no competing timer.
    for _, o in ipairs(MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status = 'awaiting_fulfillment' AND fulfillment_mode = 'scheduled' AND created_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL ? MINUTE)", { supplyCfg().ScheduledDeliveryMinutes }) or {}) do
        S.DeliverInternal(o, 'supplier')
        fixed = fixed + 1
    end
    -- Cancelled/failed orders whose refund did not complete are retried (idempotent ledger key).
    for _, o in ipairs(MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status IN ('cancelled','failed') AND refunded_at IS NULL AND (end_reason IS NULL OR end_reason NOT LIKE 'ownership_change%') AND (end_reason IS NULL OR end_reason NOT LIKE 'payment_%') AND (end_reason IS NULL OR end_reason <> 'payment_incomplete') LIMIT 50") or {}) do
        if C.ledgerByKey('supply-debit:' .. o.reference) then
            refund(o, 'reconcile')
            fixed = fixed + 1
        end
    end
    return fixed
end

-- Ownership change: uncommitted orders (no cargo yet) die with the old tenure and are NOT refunded
-- (the funds were forfeited with the business). In-transit orders continue so drivers are not stranded.
function C.SupplyOwnerChanged(biz)
    local rows = MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE business_type = ? AND business_id = ? AND status IN ('pending_payment','awaiting_fulfillment','claimed')", { biz.type, biz.id }) or {}
    for _, o in ipairs(rows) do
        terminate(o, { 'pending_payment', 'awaiting_fulfillment', 'claimed' }, 'cancelled', 'ownership_change', nil, nil, { noRefund = true })
        MySQL.update.await("UPDATE cm_business_supply_orders SET refunded_at = UTC_TIMESTAMP(), refund_amount = 0 WHERE id = ? AND refunded_at IS NULL", { o.id })
    end
end

CreateThread(function()
    Wait(9000)
    pcall(S.Reconcile)
    while true do
        Wait(60000)
        if C.schemaReady then
            pcall(S.Reconcile)
            for token, q in pairs(quotes) do if os.time() > q.expires then quotes[token] = nil end end
        end
    end
end)

-- ============================================================
-- Admin / recovery (callers allowlisted; cm-admin remains the permission gate)
-- ============================================================

local function adminOk() return Config.AdminCallers[invoker()] == true end

function S.AdminList(filter)
    if not adminOk() then return nil, 'forbidden' end
    filter = type(filter) == 'table' and filter or {}
    local rows
    if filter.stuck then
        rows = MySQL.query.await("SELECT * FROM cm_business_supply_orders WHERE status IN ('pending_payment','delivering','claimed','in_transit') OR (status IN ('cancelled','failed') AND refunded_at IS NULL) ORDER BY id DESC LIMIT 100") or {}
    else
        rows = MySQL.query.await('SELECT * FROM cm_business_supply_orders ORDER BY id DESC LIMIT 100') or {}
    end
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = businessView(r, false) end
    return out
end

function S.AdminInspect(ref)
    if not adminOk() then return nil, 'forbidden' end
    local order = getOrder(ref)
    if not order then return nil, 'order_not_found' end
    local events = MySQL.query.await('SELECT kind, actor_character_id, provider, amount, created_at FROM cm_business_supply_events WHERE order_id = ? ORDER BY id', { order.id }) or {}
    local v = businessView(order, true)
    v.provider, v.businessType, v.businessId = order.provider, order.business_type, order.business_id
    return { order = v, events = events }
end

function S.AdminCancel(ref, reason)
    if not adminOk() then return false, 'forbidden' end
    local order = getOrder(ref)
    if not order then return false, 'order_not_found' end
    local ok, err = terminate(order, { 'awaiting_fulfillment', 'claimed', 'in_transit', 'pending_payment' }, 'cancelled', 'admin:' .. tostring(reason or 'cancel'):gsub('[^%w_%-]', ''):sub(1, 25), nil, 'admin')
    return ok, err
end

function S.AdminReconcile()
    if not adminOk() then return nil, 'forbidden' end
    return S.Reconcile()
end

-- Development/test fulfilment (not a gameplay path): requires cm_environment=development or Config.Supply.AllowAdminFulfill.
function S.AdminDeliver(ref)
    if not adminOk() then return false, 'forbidden' end
    if not (supplyCfg().AllowAdminFulfill or GetConvar(Config.SelfTest.convar, 'production') == Config.SelfTest.value) then return false, 'disabled' end
    local order = getOrder(ref)
    if not order then return false, 'order_not_found' end
    if order.status ~= 'awaiting_fulfillment' and order.status ~= 'claimed' and order.status ~= 'in_transit' then return false, 'invalid_state' end
    return S.DeliverFrom(order, order.status, 'admin')
end

C.SupplyGetOrder = getOrder
function S._quotes() return quotes end -- development self-test only
