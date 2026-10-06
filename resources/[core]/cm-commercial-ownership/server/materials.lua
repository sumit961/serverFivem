-- cm-commercial-ownership/server/materials.lua
-- Business Material Demand & Settlement Foundation (v2.3.0).
--
-- OWNERSHIP
--   cm-materials      read-only catalog (what a material is / whether it is approved)           -- never mutated here
--   cm-inventory      custody of PLAYER items; the consume-only item sink removes delivered items atomically + idempotently
--   THIS RESOURCE     business material BALANCE (a counter per business+material, not items, not retail product stock),
--                     material DEMAND, and the player -> business DELIVERY settlement saga
--   cm-contracts      optional broker for the WORK of delivering (type bulk_material_transport); creates 0 items / 0 money / 0 stock
--   Agent 3 content   physical gathering/transport/delivery; calls DeliverBusinessMaterials after validating the physical task
--
-- NOTHING here mints materials or money. Material custody MOVES: player inventory -> business balance, exactly once.
--
-- DELIVERY SAGA (every step idempotent; the reference is durable)
--   1 prepare   : txn: lock demand row, check remaining = required - fulfilled - reserved, reserve qty, INSERT delivery (prepared)
--   2 debit     : cm-inventory ExecuteItemSinkTransaction('BMD-<reference>')   (atomic, UNIQUE-reference ledger)
--   3 committed : delivery prepared -> inventory_committed   (from here the debit is IRREVERSIBLE: there is NO refund path)
--   4 credit    : ONE txn: stock += qty (journal key delivery:<ref>), demand progress, delivery -> completed
--   crash after 2 -> status lookup says committed -> only step 3/4 are retried;  crash after 4 -> completed, nothing replays.
--   inventory definitely not applied (refused / timeout) -> reservation released, delivery failed/cancelled.
local C = CMB
local RESOURCE = GetCurrentResourceName()
local MAT = {}
C.Materials = MAT

local function mcfg() return Config.Materials end
local function invoker() return C.TestInvoker or GetInvokingResource() or RESOURCE end
local function now() return C.TestNow and C.TestNow() or os.time() end
local function encode(t) local ok, s = pcall(json.encode, t); return ok and s or '' end

local BROKER = 'cm-contracts'
local CONTRACT_TYPE = 'bulk_material_transport'

------------------------------------------------------------------------------------------------------------------------ SQL (verbatim-checked by tests/materials_mysql_smoke.py)
local SQL = {
    stockEnsure = 'INSERT INTO cm_business_material_stock (business_type, business_id, material_id, quantity) VALUES (?, ?, ?, 0) ON DUPLICATE KEY UPDATE quantity = quantity',
    stockLock = 'SELECT quantity FROM cm_business_material_stock WHERE business_type = ? AND business_id = ? AND material_id = ? FOR UPDATE',
    stockSet = 'UPDATE cm_business_material_stock SET quantity = ? WHERE business_type = ? AND business_id = ? AND material_id = ? AND quantity = ?',
    stockRead = 'SELECT quantity FROM cm_business_material_stock WHERE business_type = ? AND business_id = ? AND material_id = ?',
    stockList = 'SELECT material_id, quantity FROM cm_business_material_stock WHERE business_type = ? AND business_id = ? AND quantity > 0 ORDER BY material_id',
    stockAllPositive = 'SELECT material_id, quantity FROM cm_business_material_stock WHERE business_type = ? AND business_id = ? AND quantity > 0 FOR UPDATE',
    eventInsert = 'INSERT INTO cm_business_material_events (reference, business_type, business_id, material_id, delta, resulting_quantity, event_type, source_resource, character_id, journal_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    eventByJournal = 'SELECT reference, business_type, business_id, material_id, delta FROM cm_business_material_events WHERE journal_key = ? LIMIT 1',
    consumeEvents = "SELECT business_type, business_id, material_id, delta FROM cm_business_material_events WHERE reference = ? AND event_type = 'consume' ORDER BY material_id",
    eventsForBusiness = 'SELECT reference, material_id, delta, resulting_quantity, event_type, source_resource, character_id FROM cm_business_material_events WHERE business_type = ? AND business_id = ? ORDER BY id DESC LIMIT 40',
    demandInsert = 'INSERT INTO cm_business_material_demands (reference, idempotency_key, business_type, business_id, material_id, quantity_required, category, deadline_epoch, publish_requested, created_by, created_epoch) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    demandByRef = 'SELECT * FROM cm_business_material_demands WHERE reference = ? LIMIT 1',
    demandLock = 'SELECT * FROM cm_business_material_demands WHERE reference = ? FOR UPDATE',
    demandByIdem = 'SELECT * FROM cm_business_material_demands WHERE idempotency_key = ? LIMIT 1',
    demandOpenForBusiness = "SELECT material_id, quantity_required, quantity_fulfilled FROM cm_business_material_demands WHERE business_type = ? AND business_id = ? AND status IN ('open','published','partially_fulfilled')",
    demandReserve = 'UPDATE cm_business_material_demands SET quantity_reserved = ? WHERE id = ? AND quantity_reserved = ?',
    demandProgress = 'UPDATE cm_business_material_demands SET quantity_fulfilled = ?, quantity_reserved = ?, status = ? WHERE id = ? AND quantity_fulfilled = ? AND quantity_reserved = ?',
    demandFulfilled = "UPDATE cm_business_material_demands SET quantity_fulfilled = ?, quantity_reserved = ?, status = 'fulfilled', completed_epoch = ? WHERE id = ? AND quantity_fulfilled = ? AND quantity_reserved = ?",
    demandEnd = "UPDATE cm_business_material_demands SET status = ?, end_reason = ?, completed_epoch = ? WHERE id = ? AND quantity_reserved = 0 AND status IN ('open','published','partially_fulfilled')",
    demandPublished = "UPDATE cm_business_material_demands SET contract_ref = ?, status = 'published' WHERE id = ? AND contract_ref IS NULL AND status = 'open'",
    demandsToPublish = "SELECT * FROM cm_business_material_demands WHERE publish_requested = 1 AND contract_ref IS NULL AND status = 'open' ORDER BY id LIMIT 20",
    demandsExpired = "SELECT * FROM cm_business_material_demands WHERE status IN ('open','published','partially_fulfilled') AND deadline_epoch IS NOT NULL AND deadline_epoch <= ? AND quantity_reserved = 0 ORDER BY id LIMIT 20",
    demandsOpenOfBusiness = "SELECT * FROM cm_business_material_demands WHERE business_type = ? AND business_id = ? AND status IN ('open','published','partially_fulfilled')",
    demandsList = 'SELECT * FROM cm_business_material_demands WHERE business_type = ? AND business_id = ? ORDER BY id DESC LIMIT 40',
    demandsAdminList = 'SELECT * FROM cm_business_material_demands ORDER BY id DESC LIMIT 50',
    deliveryInsert = "INSERT INTO cm_business_material_deliveries (reference, demand_id, demand_reference, business_type, business_id, character_id, material_id, quantity, contract_ref, inventory_reference, payload, status, created_epoch, updated_epoch) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'prepared', ?, ?)",
    deliveryByRef = 'SELECT * FROM cm_business_material_deliveries WHERE reference = ? LIMIT 1',
    deliveryLock = 'SELECT * FROM cm_business_material_deliveries WHERE reference = ? FOR UPDATE',
    deliveryCas = 'UPDATE cm_business_material_deliveries SET status = ?, updated_epoch = ?, failure_reason = ? WHERE reference = ? AND status = ?',
    deliveryComplete = "UPDATE cm_business_material_deliveries SET status = 'completed', updated_epoch = ?, completed_epoch = ? WHERE reference = ? AND status = 'inventory_committed'",
    deliveriesOpen = "SELECT * FROM cm_business_material_deliveries WHERE status IN ('prepared','inventory_committed') AND updated_epoch <= ? ORDER BY id LIMIT 50",
    deliveryCompletedForDemand = "SELECT reference, character_id FROM cm_business_material_deliveries WHERE demand_id = ? AND status = 'completed' AND contract_ref = ? ORDER BY id LIMIT 1",
    deliveriesAdminList = 'SELECT * FROM cm_business_material_deliveries ORDER BY id DESC LIMIT 50',
}
MAT.SQL = SQL

------------------------------------------------------------------------------------------------------------------------ helpers
local function isInt(n, lo, hi) return type(n) == 'number' and n == n and n % 1 == 0 and n >= lo and n <= hi end
local function validRef(ref) return type(ref) == 'string' and #ref >= 8 and #ref <= 40 and ref:match('^[%w_%-]+$') ~= nil end
local function validCid(cid)
    if type(cid) == 'number' then cid = tostring(math.floor(cid)) end
    return type(cid) == 'string' and #cid >= 1 and #cid <= 20 and cid:match('^%d+$') ~= nil and cid or nil
end
local function callerOk(kind) return mcfg().Callers[kind] ~= nil and mcfg().Callers[kind][invoker()] == true end

local function affected(r)
    local n = type(r) == 'table' and r.affectedRows or r
    return tonumber(n) or 0
end

-- Runs `body(q, out)` inside ONE SQL transaction. The body signals a definite refusal with `out.fail = reason` (rollback) or success with
-- `out.ok = true` (commit). Any error or failed statement rolls back. Returns out, committed.
local function runTxn(body)
    local out = {}
    local committed = MySQL.startTransaction(function(query)
        local ok, err = pcall(function()
            local function q(sql, params)
                local r = query(sql, params)
                if r == nil then error('query_failed') end
                return r
            end
            body(q, out)
        end)
        if not ok then out.error = tostring(err); out.ok = nil; return false end
        if not out.ok then return false end
        return true
    end)
    return out, committed
end

local function catalog(name, ...)
    if C.TestMaterials then return C.TestMaterials[name](...) end
    if GetResourceState('cm-materials') ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, res = pcall(function() return exports['cm-materials'][name](exports['cm-materials'], table.unpack(args, 1, args.n)) end)
    if ok then return res end
    return nil
end

-- Approved = known to the READ-ONLY catalog and not DEFERRED (plastic is DEFERRED until it has a sink).
local function approvedMaterial(id)
    if type(id) ~= 'string' or #id > 64 or not id:match('^[a-z0-9_]+$') then return false, 'invalid_material' end
    local isMat = catalog('IsMaterial', id)
    if isMat == nil then return false, 'unavailable' end
    if isMat ~= true then return false, 'invalid_material' end
    local m = catalog('GetMaterial', id)
    if type(m) ~= 'table' then return false, 'unavailable' end
    if m.status == 'DEFERRED' then return false, 'material_deferred' end
    return true, m
end
MAT.ApprovedMaterial = approvedMaterial

-- The business must exist and be OWNED (an ownerless business could hand its stock to the next buyer).
local function business(t, i)
    local biz, why = C.Resolve(t, i)
    if not biz then return nil, (why == 'unknown_business' or why == 'invalid_business') and why or 'unavailable' end
    if not biz.ownerCharacterId then return nil, 'no_owner' end
    return biz
end

local function lockBusiness(biz, fn) return C.withBusinessLock('mat:' .. biz.type .. ':' .. biz.id, fn) end

local function audit(biz, action, cid, amount, meta)
    pcall(function() C.LogActivity({ type = biz.type, id = biz.id }, action, cid, nil, amount, meta, false) end)
end

local function newRef(prefix)
    local chars, out = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', {}
    for _ = 1, 8 do local n = math.random(1, #chars); out[#out + 1] = chars:sub(n, n) end
    return prefix .. '-' .. table.concat(out)
end

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

local function inventoryCall(name, ...)
    local args = table.pack(...)
    if C.TestInventory then return C.TestInventory[name](table.unpack(args, 1, args.n)) end
    if GetResourceState('cm-inventory') ~= 'started' then return false, 'unavailable' end
    local res = table.pack(pcall(function() return exports['cm-inventory'][name](exports['cm-inventory'], table.unpack(args, 1, args.n)) end))
    if not res[1] then return false, 'unavailable' end
    return res[2], res[3]
end

------------------------------------------------------------------------------------------------------------------------ business material BALANCE
-- credit inside an open transaction. Returns true or sets out.fail. `opts.ignoreCap` is used ONLY by delivery settlement (the items are
-- already gone from the player; the cap is enforced at demand creation and on standalone credits).
local function creditInTxn(q, out, a)
    local jr = q(SQL.eventByJournal, { a.journalKey })
    if jr[1] then out.replayedEvent = jr[1]; return true, true end
    q(SQL.stockEnsure, { a.t, a.i, a.material })
    local rows = q(SQL.stockLock, { a.t, a.i, a.material })
    local cur = tonumber(rows[1] and rows[1].quantity) or 0
    local nxt = cur + a.quantity
    if not a.ignoreCap and nxt > mcfg().MaxStockPerMaterial then out.fail = 'over_capacity'; return false end
    if affected(q(SQL.stockSet, { nxt, a.t, a.i, a.material, cur })) ~= 1 then error('guard_failed') end
    q(SQL.eventInsert, { a.reference, a.t, a.i, a.material, a.quantity, nxt, a.eventType, a.source, a.cid, a.journalKey })
    out.quantity = nxt
    return true, false
end

-- Reads (any server resource may read; nothing here is secret and there is no client path).
function MAT.GetStock(t, i, materialId)
    local biz, why = C.readBusiness(t, i)
    if not biz then return false, why or 'invalid_business' end
    if type(materialId) ~= 'string' or not materialId:match('^[a-z0-9_]+$') or #materialId > 64 then return false, 'invalid_material' end
    local ok, row = pcall(function() return MySQL.single.await(SQL.stockRead, { biz.type, biz.id, materialId }) end)
    if not ok then return false, 'unavailable' end
    return true, math.floor(tonumber(row and row.quantity) or 0)
end

function MAT.GetMaterials(t, i)
    local biz, why = C.readBusiness(t, i)
    if not biz then return false, why or 'invalid_business' end
    local ok, rows = pcall(function() return MySQL.query.await(SQL.stockList, { biz.type, biz.id }) end)
    if not ok then return false, 'unavailable' end
    local out = {}
    for _, r in ipairs(rows or {}) do out[#out + 1] = { materialId = r.material_id, quantity = math.floor(tonumber(r.quantity) or 0) } end
    return true, out
end

-- CreditBusinessMaterial(reference, businessType, businessId, materialId, quantity, context) -> true, { quantity, replayed } | false, reason
function MAT.Credit(reference, t, i, materialId, quantity, context)
    if not callerOk('credit') then return false, 'forbidden' end
    if not validRef(reference) then return false, 'invalid_reference' end
    if not isInt(quantity, 1, mcfg().MaxQuantityPerOperation) then return false, 'invalid_quantity' end
    local okM, mat = approvedMaterial(materialId)
    if not okM then return false, mat end
    local biz, why = business(t, i)
    if not biz then return false, why end
    context = type(context) == 'table' and context or {}
    local cid = validCid(context.characterId)
    return lockBusiness(biz, function()
        local args = { t = biz.type, i = biz.id, material = materialId, quantity = quantity, eventType = 'credit', source = invoker():sub(1, 48), cid = cid,
            journalKey = 'credit:' .. reference, reference = reference }
        local out, committed = runTxn(function(q, o)
            local _, replay = creditInTxn(q, o, args)
            if o.fail then return end
            if replay then
                local ev = o.replayedEvent
                if ev.business_type ~= biz.type or ev.business_id ~= biz.id or ev.material_id ~= materialId or tonumber(ev.delta) ~= quantity then o.fail = 'reference_conflict' return end
                o.replay = true
                return
            end
            o.ok = true
        end)
        if out.ok and committed == true then
            audit(biz, 'material_credit', cid, quantity, { material = materialId, reference = reference })
            return true, { quantity = out.quantity, replayed = false }
        end
        if out.replay then local _, cur = MAT.GetStock(biz.type, biz.id, materialId); return true, { quantity = cur, replayed = true } end
        if out.fail then return false, out.fail end
        -- unknown outcome: the journal decides
        local ok, row = pcall(function() return MySQL.single.await(SQL.eventByJournal, { 'credit:' .. reference }) end)
        if ok and row then
            if row.business_type == biz.type and row.business_id == biz.id and row.material_id == materialId and tonumber(row.delta) == quantity then
                local _, cur = MAT.GetStock(biz.type, biz.id, materialId); return true, { quantity = cur, replayed = true }
            end
            return false, 'reference_conflict'
        end
        return false, 'unavailable'
    end)
end

local function normalizeRequirements(requirements)
    if type(requirements) ~= 'table' or #requirements < 1 or #requirements > mcfg().MaxRequirementLines then return nil end
    local seen, list = {}, {}
    for _, r in ipairs(requirements) do
        if type(r) ~= 'table' or type(r.material) ~= 'string' or seen[r.material] or not isInt(r.quantity, 1, mcfg().MaxQuantityPerOperation) then return nil end
        for k in pairs(r) do if k ~= 'material' and k ~= 'quantity' then return nil end end
        seen[r.material] = true
        list[#list + 1] = { material = r.material, quantity = r.quantity }
    end
    table.sort(list, function(x, y) return x.material < y.material end)
    return list
end

-- ConsumeBusinessMaterial(reference, businessType, businessId, requirements, context)
--   requirements = { { material, quantity } ... }   all-or-nothing, idempotent by reference, never negative
function MAT.Consume(reference, t, i, requirements, context)
    if not callerOk('consume') then return false, 'forbidden' end
    if not validRef(reference) then return false, 'invalid_reference' end
    local list = normalizeRequirements(requirements)
    if not list then return false, 'invalid_requirements' end
    for _, r in ipairs(list) do local ok, m = approvedMaterial(r.material); if not ok then return false, m end end
    local biz, why = business(t, i)
    if not biz then return false, why end
    context = type(context) == 'table' and context or {}
    local cid = validCid(context.characterId)
    local function sameSet(rows)
        if #rows ~= #list then return false end
        for idx, r in ipairs(list) do
            local row = rows[idx]
            if not row or row.business_type ~= biz.type or row.business_id ~= biz.id or row.material_id ~= r.material or -tonumber(row.delta) ~= r.quantity then return false end
        end
        return true
    end
    return lockBusiness(biz, function()
        local out, committed = runTxn(function(q, o)
            local prior = q(SQL.consumeEvents, { reference })
            if prior[1] then
                if sameSet(prior) then o.replay = true else o.fail = 'reference_conflict' end
                return
            end
            local current = {}
            for _, r in ipairs(list) do   -- sorted order: deterministic lock order, no deadlocks between two multi-material consumes
                q(SQL.stockEnsure, { biz.type, biz.id, r.material })
                local rows = q(SQL.stockLock, { biz.type, biz.id, r.material })
                current[r.material] = tonumber(rows[1] and rows[1].quantity) or 0
            end
            for _, r in ipairs(list) do
                if current[r.material] < r.quantity then o.fail = 'insufficient_material'; o.short = r.material return end
            end
            for _, r in ipairs(list) do
                local nxt = current[r.material] - r.quantity
                if affected(q(SQL.stockSet, { nxt, biz.type, biz.id, r.material, current[r.material] })) ~= 1 then error('guard_failed') end
                q(SQL.eventInsert, { reference, biz.type, biz.id, r.material, -r.quantity, nxt, 'consume', invoker():sub(1, 48), cid, 'consume:' .. reference .. ':' .. r.material })
            end
            o.ok = true
        end)
        if out.ok and committed == true then
            audit(biz, 'material_consume', cid, nil, { reference = reference })
            return true, { replayed = false }
        end
        if out.replay then return true, { replayed = true } end
        if out.fail then return false, out.fail, out.short end
        local ok, rows = pcall(function() return MySQL.query.await(SQL.consumeEvents, { reference }) end)
        if ok and rows and rows[1] then return sameSet(rows) and true or false, sameSet(rows) and { replayed = true } or 'reference_conflict' end
        return false, 'unavailable'
    end)
end

------------------------------------------------------------------------------------------------------------------------ DEMAND
local OPEN = { open = true, published = true, partially_fulfilled = true }

local function demandView(d)
    if not d then return nil end
    local required, fulfilled, reserved = tonumber(d.quantity_required) or 0, tonumber(d.quantity_fulfilled) or 0, tonumber(d.quantity_reserved) or 0
    return {
        reference = d.reference, businessType = d.business_type, businessId = d.business_id, material = d.material_id,
        required = required, fulfilled = fulfilled, reserved = reserved, remaining = math.max(0, required - fulfilled - reserved),
        status = d.status, category = d.category, deadline = d.deadline_epoch and tonumber(d.deadline_epoch) or nil,
        contractRef = d.contract_ref, createdAt = tonumber(d.created_epoch), endReason = d.end_reason,
    }
end
MAT.DemandView = demandView

local function getDemand(ref)
    if not validRef(ref) then return nil end
    local ok, row = pcall(function() return MySQL.single.await(SQL.demandByRef, { ref }) end)
    if not ok then return nil, 'unavailable' end
    return row
end

-- Publishes the WORK (not the stock) to the broker. Only work-facing facts cross; idempotent on both sides.
local function publish(d)
    if d.contract_ref or d.status ~= 'open' or tonumber(d.publish_requested) ~= 1 then return false end
    local ok, created, info = brokerCall('CreateContract', {
        contractType = CONTRACT_TYPE, sourceReference = d.reference,
        title = ('Material delivery: %s'):format(d.material_id), description = ('%d x %s to a local business'):format(tonumber(d.quantity_required) or 0, d.material_id),
        pickupHint = mcfg().PickupHint, destinationHint = ('%s business'):format(d.business_type), cargoClass = 'bulk', urgency = 'normal',
        fallbackAfterSeconds = math.floor((tonumber(mcfg().ContractFallbackMinutes) or 60) * 60),
        metadata = { kind = 'material_supply', material = d.material_id, quantity = tonumber(d.quantity_required), businessType = d.business_type },
    })
    if not (ok and created == true and type(info) == 'table' and info.reference) then return false end
    local n = affected(MySQL.update.await(SQL.demandPublished, { info.reference, d.id }))
    return n == 1
end

-- CreateMaterialDemand(opts) -> true, view | false, reason       (trusted callers only; no player-facing path)
function MAT.CreateDemand(opts)
    if not callerOk('demand') then return false, 'forbidden' end
    if type(opts) ~= 'table' then return false, 'invalid_request' end
    if not isInt(opts.quantity, 1, mcfg().MaxDemandQuantity) then return false, 'invalid_quantity' end
    local okM, mat = approvedMaterial(opts.materialId)
    if not okM then return false, mat end
    local category = opts.category == nil and 'business_need' or opts.category
    if type(category) ~= 'string' or not mcfg().DemandCategories[category] then return false, 'invalid_category' end
    local deadline
    if opts.deadlineMinutes ~= nil then
        local dm = mcfg().DeadlineMinutes
        if not isInt(opts.deadlineMinutes, dm.min, dm.max) then return false, 'invalid_deadline' end
        deadline = now() + opts.deadlineMinutes * 60
    end
    local idem
    if opts.idempotencyKey ~= nil then
        if type(opts.idempotencyKey) ~= 'string' or #opts.idempotencyKey < 4 or #opts.idempotencyKey > 40 or not opts.idempotencyKey:match('^[%w_%-:%.]+$') then return false, 'invalid_key' end
    end
    local biz, why = business(opts.businessType, opts.businessId)
    if not biz then return false, why end
    if opts.idempotencyKey then idem = (invoker() .. ':' .. biz.type .. ':' .. biz.id .. ':' .. opts.idempotencyKey):sub(1, 120) end
    local cid = validCid(opts.characterId)
    return lockBusiness(biz, function()
        if idem then
            local ex = MySQL.single.await(SQL.demandByIdem, { idem })
            if ex then
                if ex.material_id == opts.materialId and tonumber(ex.quantity_required) == opts.quantity and ex.business_type == biz.type and ex.business_id == biz.id then
                    return true, demandView(ex), 'replayed'
                end
                return false, 'idempotency_conflict'
            end
        end
        local open = MySQL.query.await(SQL.demandOpenForBusiness, { biz.type, biz.id }) or {}
        if #open >= mcfg().MaxOpenDemandsPerBusiness then return false, 'too_many_demands' end
        local pending = 0
        for _, r in ipairs(open) do if r.material_id == opts.materialId then pending = pending + (tonumber(r.quantity_required) - tonumber(r.quantity_fulfilled)) end end
        local okS, stock = MAT.GetStock(biz.type, biz.id, opts.materialId)
        if not okS then return false, 'unavailable' end
        if stock + pending + opts.quantity > mcfg().MaxStockPerMaterial then return false, 'over_capacity' end
        local ref = newRef('MD')
        local okI, err = pcall(function()
            MySQL.insert.await(SQL.demandInsert, { ref, idem, biz.type, biz.id, opts.materialId, opts.quantity, category, deadline, opts.publish == true and 1 or 0, cid, now() })
        end)
        if not okI then return false, 'unavailable' end
        local row = getDemand(ref)
        if not row then return false, 'unavailable' end
        if opts.publish == true then publish(row); row = getDemand(ref) or row end
        audit(biz, 'material_demand_created', cid, opts.quantity, { demand = ref, material = opts.materialId })
        return true, demandView(row)
    end)
end

function MAT.GetDemand(ref)
    local d, why = getDemand(ref)
    if not d then return false, why or 'not_found' end
    return true, demandView(d)
end

function MAT.ListDemands(t, i)
    local biz, why = C.readBusiness(t, i)
    if not biz then return false, why or 'invalid_business' end
    local rows = MySQL.query.await(SQL.demandsList, { biz.type, biz.id }) or {}
    local out = {}
    for _, d in ipairs(rows) do out[#out + 1] = demandView(d) end
    return true, out
end

-- Ends a demand (cancel / expire) only while NO delivery is in irreversible settlement (reserved == 0).
local function endDemand(ref, status, reason, noBroker)
    local out, committed = runTxn(function(q, o)
        local rows = q(SQL.demandLock, { ref })
        local d = rows[1]
        if not d then o.fail = 'not_found' return end
        if d.status == status then o.replay = d return end
        if not OPEN[d.status] then o.fail = 'invalid_state' return end
        if (tonumber(d.quantity_reserved) or 0) > 0 then o.fail = 'delivery_in_progress' return end
        if affected(q(SQL.demandEnd, { status, reason, now(), d.id })) ~= 1 then error('guard_failed') end
        o.demand = d
        o.ok = true
    end)
    if out.ok and committed == true then
        if out.demand.contract_ref then brokerCall('CancelContract', CONTRACT_TYPE, ref, reason) end   -- best effort
        return true, { replayed = false }
    end
    if out.replay then return true, { replayed = true } end
    return false, out.fail or 'unavailable'
end

function MAT.CancelDemand(ref, reason)
    if not callerOk('demand') then return false, 'forbidden' end
    if not validRef(ref) then return false, 'invalid_reference' end
    return endDemand(ref, 'cancelled', 'cancel:' .. tostring(reason or 'cancel'):gsub('[^%w_%-]', ''):sub(1, 24))
end

------------------------------------------------------------------------------------------------------------------------ DELIVERY SAGA
local DEFINITE = { insufficient_input = true, invalid_item = true, invalid_transaction = true, forbidden = true, reference_conflict = true, invalid_metadata = true }

local function payloadOf(demand, cid, qty, contractRef)
    return table.concat({ demand.reference, demand.material_id, tostring(cid), tostring(qty), tostring(contractRef or '') }, '|')
end
local function invRef(deliveryRef) return ('BMD-' .. deliveryRef):sub(1, 64) end

local function deliveryResult(row, replayed)
    return { reference = row.reference, status = row.status, quantity = tonumber(row.quantity), material = row.material_id, replayed = replayed == true }
end

-- Step 4: ONE transaction credits the balance, advances the demand and completes the delivery.
local function finalize(row)
    local out, committed = runTxn(function(q, o)
        local drows = q(SQL.deliveryLock, { row.reference })
        local d = drows[1]
        if not d then o.fail = 'not_found' return end
        if d.status == 'completed' then o.replay = true return end
        if d.status ~= 'inventory_committed' then o.fail = 'invalid_state' return end
        local qty = tonumber(d.quantity)
        local _, replayedCredit = creditInTxn(q, o, { t = d.business_type, i = d.business_id, material = d.material_id, quantity = qty, eventType = 'delivery',
            source = 'cm-commercial-ownership', cid = d.character_id, journalKey = 'delivery:' .. d.reference, reference = d.reference, ignoreCap = true })
        if o.fail then return end
        local demand = q(SQL.demandLock, { d.demand_reference })
        local dem = demand[1]
        if not dem then error('demand_missing') end
        local fulfilled, reserved = tonumber(dem.quantity_fulfilled), tonumber(dem.quantity_reserved)
        if reserved < qty then error('reservation_missing') end
        local newF, newR = fulfilled + qty, reserved - qty
        if newF >= tonumber(dem.quantity_required) then
            if affected(q(SQL.demandFulfilled, { newF, newR, now(), dem.id, fulfilled, reserved })) ~= 1 then error('guard_failed') end
        else
            if affected(q(SQL.demandProgress, { newF, newR, 'partially_fulfilled', dem.id, fulfilled, reserved })) ~= 1 then error('guard_failed') end
        end
        if affected(q(SQL.deliveryComplete, { now(), now(), d.reference })) ~= 1 then error('guard_failed') end
        o.ok = true
        o.credited = not replayedCredit
    end)
    if out.ok and committed == true then return true, 'completed' end
    if out.replay then return true, 'completed' end
    if out.fail then return false, out.fail end
    -- unknown: re-read
    local ok, cur = pcall(function() return MySQL.single.await(SQL.deliveryByRef, { row.reference }) end)
    if ok and cur and cur.status == 'completed' then return true, 'completed' end
    return false, 'unavailable'
end

-- The inventory definitely did NOT debit: release the reservation and close the delivery.
local function releaseDelivery(row, newStatus, reason)
    local out, committed = runTxn(function(q, o)
        local d = q(SQL.deliveryLock, { row.reference })[1]
        if not d or d.status ~= 'prepared' then o.fail = 'invalid_state' return end
        local dem = q(SQL.demandLock, { d.demand_reference })[1]
        if not dem then error('demand_missing') end
        local reserved = tonumber(dem.quantity_reserved)
        if reserved < tonumber(d.quantity) then error('reservation_missing') end
        if affected(q(SQL.demandReserve, { reserved - tonumber(d.quantity), dem.id, reserved })) ~= 1 then error('guard_failed') end
        if affected(q(SQL.deliveryCas, { newStatus, now(), tostring(reason or ''):sub(1, 40), d.reference, 'prepared' })) ~= 1 then error('guard_failed') end
        o.ok = true
    end)
    return out.ok and committed == true
end

local function settle(row)
    if row.status == 'prepared' then
        local ok, res = inventoryCall('ExecuteItemSinkTransaction', invRef(row.reference), tostring(row.character_id), { { item = row.material_id, amount = tonumber(row.quantity) } })
        if ok == true then
            local n = affected(MySQL.update.await(SQL.deliveryCas, { 'inventory_committed', now(), nil, row.reference, 'prepared' }))
            if n ~= 1 then
                local cur = MySQL.single.await(SQL.deliveryByRef, { row.reference })
                if not cur or (cur.status ~= 'inventory_committed' and cur.status ~= 'completed') then return false, 'unavailable' end
            end
        elseif DEFINITE[res] then
            releaseDelivery(row, 'failed', tostring(res))
            return false, tostring(res)
        else
            return false, 'unavailable'   -- unknown: stays prepared; reconciliation asks the inventory ledger
        end
    end
    local ok2, why2 = finalize(row)
    if not ok2 then return false, why2 end
    return true
end

-- DeliverBusinessMaterials(reference, demandReference, characterId, quantity, context)
--   -> true, { reference, status = 'completed', quantity, material, replayed } | false, reason | false, 'unavailable' (settlement continues via reconciliation)
function MAT.Deliver(reference, demandRef, characterId, quantity, context)
    if not callerOk('delivery') then return false, 'forbidden' end
    if not validRef(reference) then return false, 'invalid_reference' end
    if not validRef(demandRef) then return false, 'invalid_demand' end
    local cid = validCid(characterId)
    if not cid then return false, 'invalid_character' end
    if not isInt(quantity, 1, mcfg().MaxQuantityPerOperation) then return false, 'invalid_quantity' end
    context = type(context) == 'table' and context or {}
    local contractRef = context.contractReference
    if contractRef ~= nil and (type(contractRef) ~= 'string' or #contractRef > 24 or not contractRef:match('^[%w_%-]+$')) then return false, 'invalid_contract' end
    return C.withBusinessLock('mdel:' .. reference, function()
        local demand = getDemand(demandRef)
        if not demand then return false, 'demand_not_found' end
        local payload = payloadOf(demand, cid, quantity, contractRef)
        local existing = MySQL.single.await(SQL.deliveryByRef, { reference })
        if existing then
            if existing.payload ~= payload then return false, 'reference_conflict' end
            if existing.status == 'completed' then return true, deliveryResult(existing, true) end
            if existing.status == 'failed' or existing.status == 'cancelled' then return false, (existing.failure_reason and existing.failure_reason ~= '') and existing.failure_reason or 'delivery_cancelled' end
            local ok, why = settle(existing)
            if not ok then return false, why end
            return true, deliveryResult(MySQL.single.await(SQL.deliveryByRef, { reference }) or existing, true)
        end
        -- business validity is re-checked by the demand row itself (type/id/material are fixed at creation); the material must still be approved
        local okM, mat = approvedMaterial(demand.material_id)
        if not okM then return false, mat end
        local out, committed = runTxn(function(q, o)
            local dem = q(SQL.demandLock, { demandRef })[1]
            if not dem then o.fail = 'demand_not_found' return end
            if not OPEN[dem.status] then o.fail = 'demand_closed' return end
            if dem.deadline_epoch and tonumber(dem.deadline_epoch) <= now() then o.fail = 'deadline_passed' return end
            if dem.material_id ~= demand.material_id or dem.business_type ~= demand.business_type or dem.business_id ~= demand.business_id then o.fail = 'demand_changed' return end
            local required, fulfilled, reserved = tonumber(dem.quantity_required), tonumber(dem.quantity_fulfilled), tonumber(dem.quantity_reserved)
            local remaining = required - fulfilled - reserved
            if quantity > remaining then o.fail = 'over_remaining' return end
            if dem.contract_ref then
                -- contract-routed demands are WHOLE-delivery only (one contract per demand), bound to that contract
                if contractRef ~= dem.contract_ref then o.fail = 'contract_mismatch' return end
                if quantity ~= required or fulfilled ~= 0 or reserved ~= 0 then o.fail = 'whole_delivery_required' return end
            elseif contractRef ~= nil then o.fail = 'contract_mismatch' return end
            if affected(q(SQL.demandReserve, { reserved + quantity, dem.id, reserved })) ~= 1 then error('guard_failed') end
            q(SQL.deliveryInsert, { reference, dem.id, dem.reference, dem.business_type, dem.business_id, cid, dem.material_id, quantity, contractRef, invRef(reference), payload, now(), now() })
            o.ok = true
        end)
        if not (out.ok and committed == true) then
            if out.fail then return false, out.fail end
            local again = MySQL.single.await(SQL.deliveryByRef, { reference })   -- a lost race on the UNIQUE reference
            if again and again.payload == payload then local ok, why = settle(again); if ok then return true, deliveryResult(MySQL.single.await(SQL.deliveryByRef, { reference }) or again, false) end return false, why end
            return false, 'unavailable'
        end
        local row = MySQL.single.await(SQL.deliveryByRef, { reference })
        local ok, why = settle(row)
        if not ok then return false, why end
        return true, deliveryResult(MySQL.single.await(SQL.deliveryByRef, { reference }) or row, false)
    end)
end

function MAT.GetDeliveryStatus(reference)
    if not validRef(reference) then return false, 'invalid_reference' end
    local ok, row = pcall(function() return MySQL.single.await(SQL.deliveryByRef, { reference }) end)
    if not ok then return false, 'unavailable' end
    if not row then return true, 'not_found' end
    return true, row.status
end

------------------------------------------------------------------------------------------------------------------------ RECONCILIATION
function MAT.Reconcile()
    if not mcfg().Enabled then return {} end
    local stats = { completed = 0, retried = 0, cancelled = 0, expired = 0, published = 0 }
    local rows = MySQL.query.await(SQL.deliveriesOpen, { now() - 5 }) or {}
    for _, listed in ipairs(rows) do
        C.withBusinessLock('mdel:' .. listed.reference, function()
            local row = MySQL.single.await(SQL.deliveryByRef, { listed.reference })
            if not row then return end
            if row.status == 'inventory_committed' then
                if settle(row) then stats.completed = stats.completed + 1 end
            elseif row.status == 'prepared' then
                local st = inventoryCall('GetItemSinkTransactionStatus', invRef(row.reference))   -- first return value is the status
                if st == 'committed' then
                    if settle(row) then stats.completed = stats.completed + 1 end   -- settle() would re-execute (idempotent replay) then credit
                elseif st == 'not_applied' then
                    if now() - (tonumber(row.created_epoch) or 0) > mcfg().PrepareTimeoutSeconds then
                        -- re-check the ledger right before cancelling: a definitive not_applied for a reference we alone execute
                        local st2 = inventoryCall('GetItemSinkTransactionStatus', invRef(row.reference))
                        if st2 == 'not_applied' and releaseDelivery(row, 'cancelled', 'inventory_not_applied') then stats.cancelled = stats.cancelled + 1 end
                    else
                        if settle(row) then stats.retried = stats.retried + 1 end
                    end
                end
            end
        end)
    end
    for _, d in ipairs(MySQL.query.await(SQL.demandsExpired, { now() }) or {}) do
        if endDemand(d.reference, 'expired', 'deadline') then stats.expired = stats.expired + 1 end
    end
    for _, d in ipairs(MySQL.query.await(SQL.demandsToPublish, {}) or {}) do
        if publish(d) then stats.published = stats.published + 1 end
    end
    return stats
end

------------------------------------------------------------------------------------------------------------------------ cm-contracts SOURCE callbacks (type bulk_material_transport; caller must be the broker)
local function brokerOnly() return invoker() == BROKER end

local function brokerDemand(ctx)
    if not brokerOnly() then return nil, 'forbidden' end
    if type(ctx) ~= 'table' or type(ctx.sourceReference) ~= 'string' or type(ctx.reference) ~= 'string' then return nil, 'invalid_request' end
    local d = getDemand(ctx.sourceReference)
    if not d then return nil, 'source_terminal' end
    if d.contract_ref and d.contract_ref ~= ctx.reference then return nil, 'forbidden' end
    return d
end

-- The worker's delivery must already be SETTLED (inventory debited + balance credited) by DeliverBusinessMaterials.
-- Completing a contract never creates stock, items or money.
function MAT.ContractComplete(ctx)
    local d, why = brokerDemand(ctx)
    if not d then return false, why end
    if d.status == 'cancelled' or d.status == 'expired' then return false, 'source_terminal' end
    local row = MySQL.single.await(SQL.deliveryCompletedForDemand, { d.id, ctx.reference })
    if not row then return false, 'delivery_not_settled' end
    if tostring(row.character_id) ~= tostring(ctx.workerCharacterId) then return false, 'delivery_worker_mismatch' end
    return true
end

-- Deadline fallback: NO material is generated for free. The unfulfilled demand simply expires (no worker is paid, no stock appears).
function MAT.ContractFallback(ctx)
    local d, why = brokerDemand(ctx)
    if not d then return false, why end
    if d.status == 'fulfilled' then return true, { replayed = true } end
    if d.status == 'cancelled' or d.status == 'expired' then return false, 'source_terminal' end
    if (tonumber(d.quantity_reserved) or 0) > 0 then return false, 'busy' end
    local ok, res = endDemand(d.reference, 'expired', 'contract_fallback', true)
    if ok then return true, res end
    return false, res
end

function MAT.ContractCancel(ctx)
    local d, why = brokerDemand(ctx)
    if not d then return false, why == 'source_terminal' and 'invalid_state' or why end
    if d.status == 'cancelled' then return true, { replayed = true } end
    local ok, res = endDemand(d.reference, 'cancelled', 'admin', true)
    if ok then return true end
    return false, res
end

function MAT.ContractEvent(ctx)
    local d = brokerDemand(ctx)
    return d ~= nil
end

------------------------------------------------------------------------------------------------------------------------ ownership change
-- Material balances belong to an owner tenure exactly like the business balance: a sale/forfeiture zeroes them (journaled) so stock cannot
-- be laundered across owners. Open demands without a delivery in flight are cancelled; an in-flight delivery completes into the current tenure.
function C.MaterialsOwnerChanged(biz)
    for _, d in ipairs(MySQL.query.await(SQL.demandsOpenOfBusiness, { biz.type, biz.id }) or {}) do
        endDemand(d.reference, 'cancelled', 'ownership_change')
    end
    runTxn(function(q, o)
        local rows = q(SQL.stockAllPositive, { biz.type, biz.id })
        for _, r in ipairs(rows) do
            local cur = tonumber(r.quantity)
            if affected(q(SQL.stockSet, { 0, biz.type, biz.id, r.material_id, cur })) ~= 1 then error('guard_failed') end
            q(SQL.eventInsert, { newRef('RESET'), biz.type, biz.id, r.material_id, -cur, 0, 'ownership_reset', 'cm-commercial-ownership', nil,
                ('reset:%d:%d:%s'):format(now(), math.random(1, 2147483647), r.material_id) })
        end
        o.ok = true
    end)
end

------------------------------------------------------------------------------------------------------------------------ admin / observability (callers allowlisted; cm-admin remains the permission gate)
local function adminOk() return Config.AdminCallers[invoker()] == true end

function MAT.AdminListDemands(filter)
    if not adminOk() then return false, 'forbidden' end
    local rows = MySQL.query.await(SQL.demandsAdminList, {}) or {}
    local out = {}
    for _, d in ipairs(rows) do out[#out + 1] = demandView(d) end
    return true, out
end

function MAT.AdminInspectDemand(ref)
    if not adminOk() then return false, 'forbidden' end
    local d = getDemand(ref)
    if not d then return false, 'not_found' end
    return true, demandView(d)
end

function MAT.AdminListDeliveries()
    if not adminOk() then return false, 'forbidden' end
    local rows = MySQL.query.await(SQL.deliveriesAdminList, {}) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { reference = r.reference, demandId = tonumber(r.demand_id), characterId = tostring(r.character_id), material = r.material_id, quantity = tonumber(r.quantity),
            status = r.status, failure = r.failure_reason, inventoryReference = r.inventory_reference }
    end
    return true, out
end

function MAT.AdminBusinessMaterials(t, i)
    if not adminOk() then return false, 'forbidden' end
    local ok, list = MAT.GetMaterials(t, i)
    if not ok then return false, list end
    local events = MySQL.query.await(SQL.eventsForBusiness, { t, i }) or {}
    return true, { materials = list, events = events }
end

function MAT.AdminCancelDemand(ref, reason)
    if not adminOk() then return false, 'forbidden' end
    return endDemand(ref, 'cancelled', 'admin:' .. tostring(reason or 'cancel'):gsub('[^%w_%-]', ''):sub(1, 24))
end

function MAT.AdminReconcile()
    if not adminOk() then return false, 'forbidden' end
    return true, MAT.Reconcile()
end

CreateThread(function()
    Wait(10000)
    pcall(MAT.Reconcile)
    while true do
        Wait(math.max(10, tonumber(mcfg().ReconcileSeconds) or 30) * 1000)
        if C.schemaReady then pcall(MAT.Reconcile) end
    end
end)
