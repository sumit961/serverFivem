-- MySQL store for the cm-contracts core. All times are epoch seconds (BIGINT) supplied by the
-- core, so every transition is one guarded UPDATE (compare-and-swap) and is unit-testable.
CMContracts = CMContracts or {}
local S = {}
CMContracts.Store = S

local COLS = {
    status = true, claimed_character_id = true, claimed_at = true, claim_expires_at = true, active_at = true,
    completing_at = true, completed_at = true, completion_mode = true, end_reason = true, fallback_at = true,
    fallback_deferrals = true, fallback_attempts = true, fallback_next_at = true, fail_count = true, provider_ref = true,
}
local TIME_COLS = { 'claim_expires_at', 'fallback_at', 'claimed_at', 'active_at', 'completing_at', 'completed_at', 'fallback_next_at', 'created_at' }

function S.EnsureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_contracts (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(16) NOT NULL,
        source_resource VARCHAR(48) NOT NULL,
        source_reference VARCHAR(64) NOT NULL,
        contract_type VARCHAR(40) NOT NULL,
        provider_type VARCHAR(32) NOT NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'available',
        claimed_character_id VARCHAR(50) NULL,
        claimed_at BIGINT NULL, claim_expires_at BIGINT NULL, active_at BIGINT NULL,
        completing_at BIGINT NULL, completed_at BIGINT NULL,
        completion_mode VARCHAR(10) NULL, end_reason VARCHAR(40) NULL,
        fallback_at BIGINT NOT NULL,
        fallback_deferrals INT NOT NULL DEFAULT 0, fallback_attempts INT NOT NULL DEFAULT 0, fallback_next_at BIGINT NULL,
        fail_count INT NOT NULL DEFAULT 0,
        provider_ref VARCHAR(64) NULL,
        title VARCHAR(80) NULL, description VARCHAR(240) NULL, pickup_hint VARCHAR(120) NULL, destination_hint VARCHAR(120) NULL,
        cargo_class VARCHAR(32) NULL, urgency VARCHAR(8) NOT NULL DEFAULT 'normal', region VARCHAR(32) NULL,
        metadata LONGTEXT NULL,
        created_at BIGINT NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_contract_reference (reference),
        UNIQUE KEY uq_contract_source (source_resource, source_reference, contract_type),
        INDEX idx_contract_board (status, provider_type, fallback_at),
        INDEX idx_contract_due (status, fallback_at),
        INDEX idx_contract_worker (claimed_character_id, status)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_contract_events (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        contract_id BIGINT NOT NULL,
        kind VARCHAR(32) NOT NULL,
        actor VARCHAR(50) NULL,
        journal_key VARCHAR(16) NULL,
        detail LONGTEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_contract_journal (contract_id, journal_key),
        INDEX idx_event_contract (contract_id)
    )]])
    return true
end

local function norm(row)
    if row then
        local ok, m = pcall(json.decode, row.metadata or '{}')
        row.metadata = ok and type(m) == 'table' and m or {}
        for _, k in ipairs(TIME_COLS) do if row[k] ~= nil then row[k] = tonumber(row[k]) end end
    end
    return row
end

function S.getByRef(ref) return norm(MySQL.single.await('SELECT * FROM cm_contracts WHERE reference = ? LIMIT 1', { ref })) end
function S.getBySource(res, ref, ctype)
    return norm(MySQL.single.await('SELECT * FROM cm_contracts WHERE source_resource = ? AND source_reference = ? AND contract_type = ? LIMIT 1', { res, ref, ctype }))
end

-- The UNIQUE(source_resource, source_reference, contract_type) index is the duplicate guard.
function S.insert(r)
    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT INTO cm_contracts
            (reference, source_resource, source_reference, contract_type, provider_type, status, title, description, pickup_hint,
             destination_hint, cargo_class, urgency, region, metadata, fallback_at, created_at)
            VALUES (?, ?, ?, ?, ?, 'available', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            r.reference, r.source_resource, r.source_reference, r.contract_type, r.provider_type, r.title, r.description,
            r.pickup_hint, r.destination_hint, r.cargo_class, r.urgency, r.region, json.encode(r.metadata or {}), r.fallback_at, r.created_at })
    end)
    if ok and id then return id end
    return nil, 'duplicate'
end

-- One guarded UPDATE. `where` keys: claimed_character_id | fallback_after (fallback_at > n) | fallback_due (<= n) |
-- fallback_retry_due | claim_expired | claim_not_expired | completing_before.
function S.cas(ref, fromList, patch, where)
    local sets, values = {}, {}
    local cols = {}
    for col in pairs(patch) do
        if not COLS[col] then return 0 end
        cols[#cols + 1] = col
    end
    table.sort(cols)
    for _, col in ipairs(cols) do
        local v = patch[col]
        if v == false then sets[#sets + 1] = ('`%s` = NULL'):format(col)
        else sets[#sets + 1] = ('`%s` = ?'):format(col); values[#values + 1] = v end
    end
    if #sets == 0 then return 0 end
    local marks = {}
    for _, st in ipairs(fromList) do marks[#marks + 1] = '?' end
    local sql = ('UPDATE cm_contracts SET %s WHERE reference = ? AND status IN (%s)'):format(table.concat(sets, ', '), table.concat(marks, ','))
    values[#values + 1] = ref
    for _, st in ipairs(fromList) do values[#values + 1] = st end
    if where then
        if where.claimed_character_id then sql = sql .. ' AND claimed_character_id = ?'; values[#values + 1] = tostring(where.claimed_character_id) end
        if where.fallback_after then sql = sql .. ' AND fallback_at > ?'; values[#values + 1] = where.fallback_after end
        if where.fallback_due then sql = sql .. ' AND fallback_at <= ?'; values[#values + 1] = where.fallback_due end
        if where.fallback_retry_due then sql = sql .. ' AND fallback_next_at <= ?'; values[#values + 1] = where.fallback_retry_due end
        if where.claim_expired then sql = sql .. ' AND claim_expires_at < ?'; values[#values + 1] = where.claim_expired end
        if where.claim_not_expired then sql = sql .. ' AND (claim_expires_at IS NULL OR claim_expires_at > ?)'; values[#values + 1] = where.claim_not_expired end
        if where.completing_before then sql = sql .. ' AND completing_at < ?'; values[#values + 1] = where.completing_before end
    end
    return tonumber(MySQL.update.await(sql, values)) or 0
end

local function statusMarks(statuses)
    local marks = {}
    for i = 1, #statuses do marks[i] = '?' end
    return table.concat(marks, ',')
end

function S.countByCharacter(cid, providerType, statuses)
    local params = { cid, providerType }
    for _, s in ipairs(statuses) do params[#params + 1] = s end
    return tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM cm_contracts WHERE claimed_character_id = ? AND provider_type = ? AND status IN (%s)'):format(statusMarks(statuses)), params)) or 0
end

function S.listByCharacter(cid, providerType, statuses)
    local params = { cid, providerType }
    for _, s in ipairs(statuses) do params[#params + 1] = s end
    local rows = MySQL.query.await(('SELECT * FROM cm_contracts WHERE claimed_character_id = ? AND provider_type = ? AND status IN (%s) LIMIT 20'):format(statusMarks(statuses)), params) or {}
    for _, r in ipairs(rows) do norm(r) end
    return rows
end

function S.listAvailable(providerType, now, f, cid)
    local sql = "SELECT * FROM cm_contracts WHERE status = 'available' AND provider_type = ? AND fallback_at > ?"
    local params = { providerType, now }
    for _, pair in ipairs({ { 'contractType', 'contract_type' }, { 'cargoClass', 'cargo_class' }, { 'region', 'region' }, { 'urgency', 'urgency' } }) do
        if f[pair[1]] then sql = sql .. (' AND %s = ?'):format(pair[2]); params[#params + 1] = f[pair[1]] end
    end
    sql = sql .. ' ORDER BY id ASC LIMIT ' .. math.floor(f.limit or 25)
    local rows = MySQL.query.await(sql, params) or {}
    for _, r in ipairs(rows) do norm(r) end
    if cid then for _, r in ipairs(S.listByCharacter(cid, providerType, { 'claimed', 'active' })) do rows[#rows + 1] = r end end
    return rows
end

local DUE = {
    expired_claims   = "status = 'claimed' AND claim_expires_at < ?",
    expired_active   = "status = 'active' AND claim_expires_at < ?",
    stuck_completing = "status = 'completing' AND completing_at < ?",
    fallback_due     = "status IN ('available','claimed','active') AND fallback_at <= ?",
    fallback_retry   = "status = 'fallback' AND fallback_next_at <= ?",
}
function S.query(kind, arg, limit)
    local where = DUE[kind]
    if not where then return {} end
    local rows = MySQL.query.await(('SELECT * FROM cm_contracts WHERE %s ORDER BY id ASC LIMIT %d'):format(where, math.floor(limit or 20)), { arg }) or {}
    for _, r in ipairs(rows) do norm(r) end
    return rows
end

-- journalKey (e.g. 'terminal') is UNIQUE per contract: a terminal event can be written only once.
function S.insertEvent(contractId, kind, actor, detail, journalKey)
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT IGNORE INTO cm_contract_events (contract_id, kind, actor, journal_key, detail) VALUES (?, ?, ?, ?, ?)',
            { contractId, kind, actor and tostring(actor):sub(1, 50) or nil, journalKey, detail and json.encode(detail) or nil })
    end)
    return ok and tonumber(id) ~= nil and tonumber(id) > 0 or false
end

function S.events(contractId)
    return MySQL.query.await('SELECT kind, actor, journal_key, detail, created_at FROM cm_contract_events WHERE contract_id = ? ORDER BY id ASC LIMIT 200', { contractId }) or {}
end

function S.listAdmin(status, providerType, limit)
    local sql, params = 'SELECT * FROM cm_contracts WHERE 1=1', {}
    if status then sql = sql .. ' AND status = ?'; params[#params + 1] = status
    else sql = sql .. " AND status NOT IN ('completed','cancelled','failed')" end
    if providerType then sql = sql .. ' AND provider_type = ?'; params[#params + 1] = providerType end
    local rows = MySQL.query.await(sql .. ' ORDER BY id DESC LIMIT ' .. math.floor(limit or 50), params) or {}
    for _, r in ipairs(rows) do norm(r) end
    return rows
end

return S
