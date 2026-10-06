-- cm-crafting SQL store (additive, idempotent). Times are epoch seconds. Recipes and stations are NOT persisted: the trusted content
-- resources are the authoritative definitions and re-register on start / on 'cm-crafting:server:registryReady'. Sessions are persisted
-- because an interrupted commit must be reconciled. No FiveM source id and no account identifier is stored.
--   cm_crafting_sessions.active_key  = character id while active|committing -> one live craft per character
--   cm_crafting_sessions.idem_key    = '<owner>:<key>'                       -> a retried Begin returns the same session
--   cm_crafting_sessions.reference   = the deterministic inventory transaction reference
--   cm_crafting_events.journal_key   = '<session>:<key>'                     -> once-only started/commit_started/inventory_committed/terminal
CMCrafting = CMCrafting or {}
local S = {}
CMCrafting.Store = S

local COLS = {
    status = true, active_key = true, committed_at = true, commit_started_at = true, commit_attempts = true, next_commit_at = true,
    failure_reason = true, updated_at = true,
}
local NUM = { 'quantity', 'bucket', 'started_at', 'ready_at', 'expires_at', 'committed_at', 'commit_started_at', 'commit_attempts', 'next_commit_at', 'updated_at' }

function S.EnsureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_crafting_sessions (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(24) NOT NULL,
        recipe_id VARCHAR(48) NOT NULL,
        owner_resource VARCHAR(64) NOT NULL,
        character_id VARCHAR(20) NOT NULL,
        station_id VARCHAR(48) NULL,
        quantity INT NOT NULL,
        status VARCHAR(12) NOT NULL DEFAULT 'active',
        active_key VARCHAR(20) NULL,
        idem_key VARCHAR(120) NULL,
        bucket INT NOT NULL DEFAULT 0,
        started_at BIGINT NOT NULL,
        ready_at BIGINT NOT NULL,
        expires_at BIGINT NOT NULL,
        committed_at BIGINT NULL,
        commit_started_at BIGINT NULL,
        commit_attempts INT NOT NULL DEFAULT 0,
        next_commit_at BIGINT NULL,
        tx_json TEXT NOT NULL,
        failure_reason VARCHAR(32) NULL,
        updated_at BIGINT NOT NULL,
        UNIQUE KEY uq_craft_ref (reference),
        UNIQUE KEY uq_craft_active (active_key),
        UNIQUE KEY uq_craft_idem (idem_key),
        INDEX idx_craft_status (status, expires_at),
        INDEX idx_craft_char (character_id, id)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_crafting_events (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        session_ref VARCHAR(24) NOT NULL,
        recipe_id VARCHAR(48) NOT NULL,
        kind VARCHAR(24) NOT NULL,
        character_id VARCHAR(20) NULL,
        journal_key VARCHAR(80) NULL,
        detail VARCHAR(500) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_craft_event_journal (journal_key),
        INDEX idx_craft_event_session (session_ref, id)
    )]])
    return true
end

local function norm(row)
    if row then for _, k in ipairs(NUM) do if row[k] ~= nil then row[k] = tonumber(row[k]) end end end
    return row
end

function S.sessInsert(s)
    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT IGNORE INTO cm_crafting_sessions
            (reference, recipe_id, owner_resource, character_id, station_id, quantity, status, active_key, idem_key, bucket, started_at, ready_at, expires_at, tx_json, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?)]],
            { s.reference, s.recipe_id, s.owner_resource, s.character_id, s.station_id, s.quantity, s.active_key, s.idem_key, s.bucket, s.started_at, s.ready_at, s.expires_at, s.tx_json, s.updated_at })
    end)
    if ok and tonumber(id) and tonumber(id) > 0 then return id end
    if s.idem_key and S.sessGetByIdem(s.idem_key) then return nil, 'duplicate_key' end
    if S.sessActiveByChar(s.character_id) then return nil, 'already_crafting' end
    return nil, 'internal_error'
end
function S.sessGet(ref) return norm(MySQL.single.await('SELECT * FROM cm_crafting_sessions WHERE reference = ? LIMIT 1', { ref })) end
function S.sessGetByIdem(key) return norm(MySQL.single.await('SELECT * FROM cm_crafting_sessions WHERE idem_key = ? LIMIT 1', { key })) end
function S.sessActiveByChar(cid) return norm(MySQL.single.await("SELECT * FROM cm_crafting_sessions WHERE active_key = ? AND status IN ('active','committing') LIMIT 1", { cid })) end
function S.sessListOpen(limit)
    local rows = MySQL.query.await("SELECT * FROM cm_crafting_sessions WHERE status IN ('active','committing') ORDER BY id ASC LIMIT ?", { limit or 100 }) or {}
    for _, r in ipairs(rows) do norm(r) end
    return rows
end
function S.sessCas(ref, from, patch)
    local names = {}
    for col in pairs(patch) do if not COLS[col] then return 0 end names[#names + 1] = col end
    if #names == 0 then return 0 end
    table.sort(names)
    local sets, values = {}, {}
    for _, col in ipairs(names) do
        if patch[col] == false then sets[#sets + 1] = ('`%s` = NULL'):format(col)
        else sets[#sets + 1] = ('`%s` = ?'):format(col); values[#values + 1] = patch[col] end
    end
    local marks = {}
    for _ in ipairs(from) do marks[#marks + 1] = '?' end
    values[#values + 1] = ref
    for _, st in ipairs(from) do values[#values + 1] = st end
    return tonumber(MySQL.update.await(('UPDATE cm_crafting_sessions SET %s WHERE reference = ? AND status IN (%s)'):format(table.concat(sets, ', '), table.concat(marks, ',')), values)) or 0
end

function S.eventInsert(e)
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT IGNORE INTO cm_crafting_events (session_ref, recipe_id, kind, character_id, journal_key, detail) VALUES (?, ?, ?, ?, ?, ?)',
            { e.session_ref, e.recipe_id, e.kind, e.character_id, e.key, e.detail })
    end)
    return ok and tonumber(id) ~= nil and tonumber(id) > 0 or false
end
function S.eventList(ref, limit)
    return MySQL.query.await('SELECT id, kind, character_id, detail, created_at FROM cm_crafting_events WHERE session_ref = ? ORDER BY id DESC LIMIT ?', { ref, limit or 60 }) or {}
end
