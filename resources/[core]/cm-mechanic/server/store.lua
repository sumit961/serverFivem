-- cm-mechanic SQL store. Additive and idempotent (CREATE TABLE IF NOT EXISTS). Times are epoch seconds (BIGINT) set by the core.
-- Every state transition is ONE guarded UPDATE (compare-and-swap); the UNIQUE active_key columns are the duplicate guards:
--   cm_mechanic_requests.active_key     = customer character id while the request is open  -> one open request per character
--   cm_mechanic_work_orders.active_key  = request reference while the order is open        -> one live order per request
--   cm_mechanic_events.journal_key      = '<scope>:<key>'                                  -> once-only audit events
-- Persistent vehicle state is NOT stored here (cm-vehicles owns it); only vehicle_id and a short label are kept.
CMMechanic = CMMechanic or {}
local S = {}
CMMechanic.Store = S

local REQ_COLS = {
    status = true, active_key = true, contract_ref = true, work_order_ref = true, end_reason = true, updated_at = true,
}
local WO_COLS = {
    state = true, active_key = true, vehicle_id = true, vehicle_label = true, owner_snapshot = true, service_id = true,
    quote_amount = true, quote_json = true, patch_json = true, diagnosis_json = true, quote_expires_at = true,
    invoice_ref = true, invoice_key = true, invoice_attempt = true, declines = true, commit_state = true, commit_started_at = true,
    commit_attempts = true, next_commit_at = true, service_started_at = true, approved_at = true, paid_at = true,
    completed_at = true, end_reason = true, updated_at = true,
}
local NUM = { 'pos_x', 'pos_y', 'pos_z', 'created_at', 'updated_at', 'vehicle_id', 'quote_amount', 'quote_expires_at', 'invoice_attempt',
    'declines', 'commit_started_at', 'commit_attempts', 'next_commit_at', 'service_started_at', 'approved_at', 'paid_at', 'completed_at' }

function S.EnsureSchema()
    -- The mechanic business "adapter": ownership + balance live in this table, exactly like cm_stores / cm_gas_stations,
    -- and cm-commercial-ownership reads it through Config.BusinessTypes.mechanic. No second owner or treasury is created.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_mechanic_shops (
        shop_id VARCHAR(48) NOT NULL PRIMARY KEY,
        label VARCHAR(80) NOT NULL,
        owner_character_id BIGINT NULL,
        owner_name VARCHAR(100) NULL,
        business_balance BIGINT NOT NULL DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_mechanic_requests (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(24) NOT NULL,
        customer_cid VARCHAR(32) NOT NULL,
        hint VARCHAR(16) NOT NULL,
        note VARCHAR(200) NULL,
        pos_x DOUBLE NOT NULL, pos_y DOUBLE NOT NULL, pos_z DOUBLE NOT NULL DEFAULT 0,
        status VARCHAR(12) NOT NULL DEFAULT 'open',
        active_key VARCHAR(32) NULL,
        contract_ref VARCHAR(40) NULL,
        work_order_ref VARCHAR(24) NULL,
        end_reason VARCHAR(40) NULL,
        created_at BIGINT NOT NULL,
        updated_at BIGINT NOT NULL,
        UNIQUE KEY uq_mech_req_ref (reference),
        UNIQUE KEY uq_mech_req_active (active_key),
        INDEX idx_mech_req_customer (customer_cid, id),
        INDEX idx_mech_req_contract (contract_ref),
        INDEX idx_mech_req_status (status)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_mechanic_work_orders (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(24) NOT NULL,
        request_ref VARCHAR(24) NOT NULL,
        contract_ref VARCHAR(40) NOT NULL,
        customer_cid VARCHAR(32) NOT NULL,
        mechanic_cid VARCHAR(32) NOT NULL,
        business_type VARCHAR(24) NOT NULL,
        business_id VARCHAR(48) NOT NULL,
        vehicle_id BIGINT NULL,
        vehicle_label VARCHAR(80) NULL,
        owner_snapshot VARCHAR(80) NULL,
        service_id VARCHAR(32) NULL,
        quote_amount INT NULL,
        quote_json VARCHAR(1000) NULL,
        patch_json TEXT NULL,
        diagnosis_json VARCHAR(500) NULL,
        quote_expires_at BIGINT NULL,
        state VARCHAR(20) NOT NULL DEFAULT 'assigned',
        active_key VARCHAR(24) NULL,
        invoice_ref VARCHAR(48) NULL,
        invoice_key VARCHAR(80) NULL,
        invoice_attempt INT NOT NULL DEFAULT 1,
        declines INT NOT NULL DEFAULT 0,
        commit_state VARCHAR(12) NOT NULL DEFAULT 'none',
        commit_started_at BIGINT NULL,
        commit_attempts INT NOT NULL DEFAULT 0,
        next_commit_at BIGINT NULL,
        service_started_at BIGINT NULL,
        approved_at BIGINT NULL, paid_at BIGINT NULL, completed_at BIGINT NULL,
        end_reason VARCHAR(40) NULL,
        created_at BIGINT NOT NULL,
        updated_at BIGINT NOT NULL,
        UNIQUE KEY uq_mech_wo_ref (reference),
        UNIQUE KEY uq_mech_wo_active (active_key),
        INDEX idx_mech_wo_request (request_ref),
        INDEX idx_mech_wo_mechanic (mechanic_cid, state),
        INDEX idx_mech_wo_customer (customer_cid, state),
        INDEX idx_mech_wo_state (state)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_mechanic_events (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        request_ref VARCHAR(24) NULL,
        work_ref VARCHAR(24) NULL,
        kind VARCHAR(32) NOT NULL,
        actor VARCHAR(32) NULL,
        journal_key VARCHAR(120) NULL,
        detail VARCHAR(500) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_mech_event_journal (journal_key),
        INDEX idx_mech_event_request (request_ref, id),
        INDEX idx_mech_event_work (work_ref, id)
    )]])
    return true
end

-- Seed the configured shop definitions (never overwrites an existing owner or balance).
function S.SeedShops(shops)
    for _, shop in ipairs(shops) do
        MySQL.query.await('INSERT IGNORE INTO cm_mechanic_shops (shop_id, label) VALUES (?, ?)', { shop.id, shop.label })
        MySQL.query.await('UPDATE cm_mechanic_shops SET label = ? WHERE shop_id = ? AND label <> ?', { shop.label, shop.id, shop.label })
    end
end

function S.SetShopOwner(shopId, characterId, ownerName)
    return MySQL.update.await('UPDATE cm_mechanic_shops SET owner_character_id = ?, owner_name = ? WHERE shop_id = ?', { characterId, ownerName, shopId })
end

local function norm(row)
    if row then for _, k in ipairs(NUM) do if row[k] ~= nil then row[k] = tonumber(row[k]) end end end
    return row
end

local function build(cols, ref, refCol, fromCol, fromList, patch, where)
    local names = {}
    for col in pairs(patch) do
        if not cols[col] then return nil end
        names[#names + 1] = col
    end
    if #names == 0 then return nil end
    table.sort(names)
    local sets, values = {}, {}
    for _, col in ipairs(names) do
        local v = patch[col]
        if v == false then sets[#sets + 1] = ('`%s` = NULL'):format(col)
        else sets[#sets + 1] = ('`%s` = ?'):format(col); values[#values + 1] = v end
    end
    local marks = {}
    for _ in ipairs(fromList) do marks[#marks + 1] = '?' end
    local sql = ('UPDATE %s SET %s WHERE reference = ? AND %s IN (%s)'):format(refCol, table.concat(sets, ', '), fromCol, table.concat(marks, ','))
    values[#values + 1] = ref
    for _, st in ipairs(fromList) do values[#values + 1] = st end
    if where and where.commit_state then sql = sql .. ' AND commit_state = ?'; values[#values + 1] = where.commit_state end
    return sql, values
end

-- ---- requests
function S.reqInsert(r)
    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT IGNORE INTO cm_mechanic_requests
            (reference, customer_cid, hint, note, pos_x, pos_y, pos_z, status, active_key, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)]],
            { r.reference, r.customer_cid, r.hint, r.note, r.pos_x, r.pos_y, r.pos_z, r.active_key, r.created_at, r.updated_at })
    end)
    if ok and tonumber(id) and tonumber(id) > 0 then return id end
    return nil, 'duplicate_active'
end
function S.reqGetByRef(ref) return norm(MySQL.single.await('SELECT * FROM cm_mechanic_requests WHERE reference = ? LIMIT 1', { ref })) end
function S.reqGetByContract(ref) return norm(MySQL.single.await('SELECT * FROM cm_mechanic_requests WHERE contract_ref = ? LIMIT 1', { ref })) end
function S.reqOpenByCustomer(cid) return norm(MySQL.single.await("SELECT * FROM cm_mechanic_requests WHERE active_key = ? AND status IN ('open','assigned') LIMIT 1", { cid })) end
function S.reqLatestByCustomer(cid) return norm(MySQL.single.await('SELECT * FROM cm_mechanic_requests WHERE customer_cid = ? ORDER BY id DESC LIMIT 1', { cid })) end
function S.reqListOpen(limit) return MySQL.query.await("SELECT * FROM cm_mechanic_requests WHERE status IN ('open','assigned') ORDER BY id ASC LIMIT ?", { limit or 100 }) or {} end
function S.reqCas(ref, from, patch)
    local sql, values = build(REQ_COLS, ref, 'cm_mechanic_requests', 'status', from, patch)
    if not sql then return 0 end
    return tonumber(MySQL.update.await(sql, values)) or 0
end

-- ---- work orders
function S.woInsert(w)
    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT IGNORE INTO cm_mechanic_work_orders
            (reference, request_ref, contract_ref, customer_cid, mechanic_cid, business_type, business_id, state, active_key, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'assigned', ?, ?, ?)]],
            { w.reference, w.request_ref, w.contract_ref, w.customer_cid, w.mechanic_cid, w.business_type, w.business_id, w.active_key, w.created_at, w.updated_at })
    end)
    if ok and tonumber(id) and tonumber(id) > 0 then return id end
    return nil, 'duplicate_active'
end
function S.woGetByRef(ref) return norm(MySQL.single.await('SELECT * FROM cm_mechanic_work_orders WHERE reference = ? LIMIT 1', { ref })) end
function S.woActiveByRequest(reqRef) return norm(MySQL.single.await('SELECT * FROM cm_mechanic_work_orders WHERE active_key = ? LIMIT 1', { reqRef })) end
local OPEN = "('assigned','diagnosing','quoted','awaiting_payment','servicing')"
function S.woActiveByMechanic(cid) return norm(MySQL.single.await('SELECT * FROM cm_mechanic_work_orders WHERE mechanic_cid = ? AND state IN ' .. OPEN .. ' ORDER BY id DESC LIMIT 1', { cid })) end
function S.woActiveByCustomer(cid, state)
    if state then return norm(MySQL.single.await('SELECT * FROM cm_mechanic_work_orders WHERE customer_cid = ? AND state = ? ORDER BY id DESC LIMIT 1', { cid, state })) end
    return norm(MySQL.single.await('SELECT * FROM cm_mechanic_work_orders WHERE customer_cid = ? AND state IN ' .. OPEN .. ' ORDER BY id DESC LIMIT 1', { cid }))
end
function S.woListOpen(limit) return MySQL.query.await('SELECT * FROM cm_mechanic_work_orders WHERE state IN ' .. OPEN .. ' ORDER BY id ASC LIMIT ?', { limit or 100 }) or {} end
function S.woCas(ref, from, patch, where)
    local sql, values = build(WO_COLS, ref, 'cm_mechanic_work_orders', 'state', from, patch, where)
    if not sql then return 0 end
    return tonumber(MySQL.update.await(sql, values)) or 0
end

-- ---- events (append-only audit timeline)
function S.eventInsert(e)
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT IGNORE INTO cm_mechanic_events (request_ref, work_ref, kind, actor, journal_key, detail) VALUES (?, ?, ?, ?, ?, ?)',
            { e.request_ref, e.work_ref, e.kind, e.actor, e.key, e.detail })
    end)
    return ok and tonumber(id) ~= nil and tonumber(id) > 0 or false
end
function S.eventList(ref, limit)
    return MySQL.query.await('SELECT id, work_ref, kind, actor, detail, created_at FROM cm_mechanic_events WHERE request_ref = ? OR work_ref = ? ORDER BY id DESC LIMIT ?', { ref, ref, limit or 40 }) or {}
end
