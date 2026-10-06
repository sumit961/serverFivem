-- cm-crime SQL store. Additive and idempotent. Times are epoch seconds (BIGINT) supplied by the core (server clock, persisted).
-- Duplicate guards are UNIQUE keys, not memory:
--   cm_crime_sessions.active_site        = site key while an exclusive session is open       -> one active session per site
--   cm_crime_participants.active_key     = '<character>:<busyGroup>' while the member is active -> one active session per character/group
--   cm_crime_sessions.idem_key           = '<owner>:<key>'                                   -> a retried Begin returns the same session
--   cm_crime_cooldowns (scope, scope_key, activity_id)                                       -> one cooldown row per target
--   cm_crime_events.journal_key          = '<session>:<key>'                                 -> once-only terminal/reward/dispatch events
-- No FiveM source id and no account identifier is ever stored.
CMCrime = CMCrime or {}
local S = {}
CMCrime.Store = S

local SESS_COLS = {
    status = true, active_site = true, current_stage = true, prev_stage = true, stage_changed_at = true, started_at = true, completed_at = true,
    outcome = true, end_reason = true, dispatch_state = true, dispatch_count = true, dispatch_pending_type = true, dispatch_at = true,
    dispatch_attempts = true, reward_state = true, reward_token = true, reward_at = true, updated_at = true,
}
local PART_COLS = { state = true, active_key = true, left_at = true, left_reason = true }
local SESS_NUM = { 'bucket', 'coords_x', 'coords_y', 'coords_z', 'created_at', 'started_at', 'expires_at', 'completed_at', 'stage_changed_at', 'dispatch_count',
    'dispatch_at', 'dispatch_attempts', 'reward_at', 'updated_at' }

function S.EnsureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_crime_sessions (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(24) NOT NULL,
        activity_id VARCHAR(40) NOT NULL,
        owner_resource VARCHAR(64) NOT NULL,
        site_key VARCHAR(64) NULL,
        active_site VARCHAR(64) NULL,
        status VARCHAR(12) NOT NULL DEFAULT 'created',
        leader_cid VARCHAR(20) NOT NULL,
        current_stage VARCHAR(24) NOT NULL,
        prev_stage VARCHAR(24) NULL,
        stage_changed_at BIGINT NULL,
        bucket INT NOT NULL DEFAULT 0,
        site_label VARCHAR(48) NULL,
        coords_x DOUBLE NULL, coords_y DOUBLE NULL, coords_z DOUBLE NULL,
        idem_key VARCHAR(120) NULL,
        created_at BIGINT NOT NULL,
        started_at BIGINT NULL,
        expires_at BIGINT NOT NULL,
        completed_at BIGINT NULL,
        outcome VARCHAR(24) NULL,
        end_reason VARCHAR(40) NULL,
        dispatch_state VARCHAR(12) NOT NULL DEFAULT 'none',
        dispatch_count INT NOT NULL DEFAULT 0,
        dispatch_pending_type VARCHAR(24) NULL,
        dispatch_at BIGINT NULL,
        dispatch_attempts INT NOT NULL DEFAULT 0,
        reward_state VARCHAR(12) NOT NULL DEFAULT 'none',
        reward_token VARCHAR(32) NULL,
        reward_at BIGINT NULL,
        metadata VARCHAR(1100) NULL,
        updated_at BIGINT NOT NULL,
        UNIQUE KEY uq_crime_ref (reference),
        UNIQUE KEY uq_crime_active_site (active_site),
        UNIQUE KEY uq_crime_idem (idem_key),
        INDEX idx_crime_status (status, expires_at),
        INDEX idx_crime_owner (owner_resource, status),
        INDEX idx_crime_reward (reward_state, completed_at)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_crime_participants (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        session_ref VARCHAR(24) NOT NULL,
        character_id VARCHAR(20) NOT NULL,
        role VARCHAR(8) NOT NULL DEFAULT 'member',
        state VARCHAR(8) NOT NULL DEFAULT 'active',
        active_key VARCHAR(60) NULL,
        joined_at BIGINT NOT NULL,
        left_at BIGINT NULL,
        left_reason VARCHAR(32) NULL,
        UNIQUE KEY uq_crime_part (session_ref, character_id),
        UNIQUE KEY uq_crime_part_active (active_key),
        INDEX idx_crime_part_char (character_id)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_crime_cooldowns (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        scope VARCHAR(10) NOT NULL,
        scope_key VARCHAR(64) NOT NULL,
        activity_id VARCHAR(40) NOT NULL,
        expires_at BIGINT NOT NULL,
        reason VARCHAR(24) NULL,
        session_ref VARCHAR(24) NULL,
        UNIQUE KEY uq_crime_cooldown (scope, scope_key, activity_id),
        INDEX idx_crime_cooldown_exp (expires_at)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_crime_events (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        session_ref VARCHAR(24) NOT NULL,
        activity_id VARCHAR(40) NOT NULL,
        kind VARCHAR(32) NOT NULL,
        character_id VARCHAR(20) NULL,
        journal_key VARCHAR(120) NULL,
        detail VARCHAR(500) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_crime_event_journal (journal_key),
        INDEX idx_crime_event_session (session_ref, id)
    )]])
    return true
end

local function norm(row)
    if row then for _, k in ipairs(SESS_NUM) do if row[k] ~= nil then row[k] = tonumber(row[k]) end end end
    return row
end

-- ---- sessions
function S.sessInsert(s)
    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT IGNORE INTO cm_crime_sessions
            (reference, activity_id, owner_resource, site_key, active_site, status, leader_cid, current_stage, bucket, site_label,
             coords_x, coords_y, coords_z, idem_key, created_at, expires_at, dispatch_state, reward_state, metadata, updated_at)
            VALUES (?, ?, ?, ?, ?, 'created', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'none', 'none', ?, ?)]],
            { s.reference, s.activity_id, s.owner_resource, s.site_key, s.active_site, s.leader_cid, s.current_stage, s.bucket, s.site_label,
              s.coords_x, s.coords_y, s.coords_z, s.idem_key, s.created_at, s.expires_at, s.metadata, s.updated_at })
    end)
    if ok and tonumber(id) and tonumber(id) > 0 then return id end
    if s.idem_key and S.sessGetByIdem(s.idem_key) then return nil, 'duplicate_key' end
    if s.active_site and S.siteActive(s.active_site) then return nil, 'site_occupied' end
    return nil, 'internal_error'
end
function S.sessGet(ref) return norm(MySQL.single.await('SELECT * FROM cm_crime_sessions WHERE reference = ? LIMIT 1', { ref })) end
function S.sessGetByIdem(key) return norm(MySQL.single.await('SELECT * FROM cm_crime_sessions WHERE idem_key = ? LIMIT 1', { key })) end
function S.siteActive(site) return norm(MySQL.single.await("SELECT * FROM cm_crime_sessions WHERE active_site = ? AND status IN ('created','active') LIMIT 1", { site })) end
function S.sessListActive(limit)
    local rows = MySQL.query.await("SELECT * FROM cm_crime_sessions WHERE status IN ('created','active') ORDER BY id ASC LIMIT ?", { limit or 100 }) or {}
    for _, r in ipairs(rows) do norm(r) end
    return rows
end
function S.rewardsPending(before, limit)
    return MySQL.query.await("SELECT * FROM cm_crime_sessions WHERE status = 'succeeded' AND reward_state = 'pending' AND completed_at < ? LIMIT ?", { before, limit or 100 }) or {}
end
-- where: { current_stage = '..' } and/or { reward_states = { 'pending', 'failed' } }
function S.sessCas(ref, from, patch, where)
    local names = {}
    for col in pairs(patch) do
        if not SESS_COLS[col] then return 0 end
        names[#names + 1] = col
    end
    if #names == 0 then return 0 end
    table.sort(names)
    local sets, values = {}, {}
    for _, col in ipairs(names) do
        if patch[col] == false then sets[#sets + 1] = ('`%s` = NULL'):format(col)
        else sets[#sets + 1] = ('`%s` = ?'):format(col); values[#values + 1] = patch[col] end
    end
    local marks = {}
    for _ in ipairs(from) do marks[#marks + 1] = '?' end
    local sql = ('UPDATE cm_crime_sessions SET %s WHERE reference = ? AND status IN (%s)'):format(table.concat(sets, ', '), table.concat(marks, ','))
    values[#values + 1] = ref
    for _, st in ipairs(from) do values[#values + 1] = st end
    if where and where.current_stage then sql = sql .. ' AND current_stage = ?'; values[#values + 1] = where.current_stage end
    if where and where.reward_states then
        local m = {}
        for _, st in ipairs(where.reward_states) do m[#m + 1] = '?'; values[#values + 1] = st end
        sql = sql .. (' AND reward_state IN (%s)'):format(table.concat(m, ','))
    end
    return tonumber(MySQL.update.await(sql, values)) or 0
end

-- ---- participants
function S.partInsert(p)
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT IGNORE INTO cm_crime_participants (session_ref, character_id, role, state, active_key, joined_at) VALUES (?, ?, ?, \'active\', ?, ?)',
            { p.session_ref, p.character_id, p.role, p.active_key, p.joined_at })
    end)
    if ok and tonumber(id) and tonumber(id) > 0 then return true end
    return false, 'character_busy'
end
function S.partGet(ref, cid) return MySQL.single.await('SELECT * FROM cm_crime_participants WHERE session_ref = ? AND character_id = ? LIMIT 1', { ref, cid }) end
function S.partList(ref) return MySQL.query.await('SELECT * FROM cm_crime_participants WHERE session_ref = ? ORDER BY id ASC', { ref }) or {} end
function S.partCountActive(ref) return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_crime_participants WHERE session_ref = ? AND state = 'active'", { ref })) or 0 end
function S.charBusy(cid, group) return MySQL.scalar.await('SELECT 1 FROM cm_crime_participants WHERE active_key = ? LIMIT 1', { cid .. ':' .. group }) ~= nil end
function S.partCas(ref, cid, from, patch)
    local names = {}
    for col in pairs(patch) do if not PART_COLS[col] then return 0 end names[#names + 1] = col end
    table.sort(names)
    local sets, values = {}, {}
    for _, col in ipairs(names) do
        if patch[col] == false then sets[#sets + 1] = ('`%s` = NULL'):format(col)
        else sets[#sets + 1] = ('`%s` = ?'):format(col); values[#values + 1] = patch[col] end
    end
    local marks = {}
    for _, st in ipairs(from) do marks[#marks + 1] = '?'; end
    values[#values + 1] = ref; values[#values + 1] = cid
    for _, st in ipairs(from) do values[#values + 1] = st end
    return tonumber(MySQL.update.await(('UPDATE cm_crime_participants SET %s WHERE session_ref = ? AND character_id = ? AND state IN (%s)'):format(table.concat(sets, ', '), table.concat(marks, ',')), values)) or 0
end
function S.partReleaseAll(ref, state, reason)
    MySQL.update.await("UPDATE cm_crime_participants SET state = ?, active_key = NULL, left_at = ?, left_reason = ? WHERE session_ref = ? AND state = 'active'", { state, os.time(), reason, ref })
end

-- ---- cooldowns
function S.cooldownGet(scope, key, activityId)
    return tonumber(MySQL.scalar.await('SELECT expires_at FROM cm_crime_cooldowns WHERE scope = ? AND scope_key = ? AND activity_id = ? LIMIT 1', { scope, key, activityId }))
end
function S.cooldownSet(scope, key, activityId, expiresAt, reason, ref)
    MySQL.query.await([[INSERT INTO cm_crime_cooldowns (scope, scope_key, activity_id, expires_at, reason, session_ref) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE expires_at = GREATEST(expires_at, VALUES(expires_at)), reason = VALUES(reason), session_ref = VALUES(session_ref)]],
        { scope, key, activityId, expiresAt, reason and reason:sub(1, 24) or nil, ref })
end
function S.cooldownList(filter)
    local rows = MySQL.query.await('SELECT scope, scope_key, activity_id, expires_at, reason, session_ref FROM cm_crime_cooldowns WHERE expires_at > ? ORDER BY expires_at ASC LIMIT 200', { os.time() }) or {}
    return rows
end
function S.cooldownPurge(before) MySQL.update.await('DELETE FROM cm_crime_cooldowns WHERE expires_at < ?', { before }) end

-- ---- events (append-only)
function S.eventInsert(e)
    local ok, id = pcall(function()
        return MySQL.insert.await('INSERT IGNORE INTO cm_crime_events (session_ref, activity_id, kind, character_id, journal_key, detail) VALUES (?, ?, ?, ?, ?, ?)',
            { e.session_ref, e.activity_id, e.kind, e.character_id, e.key, e.detail })
    end)
    return ok and tonumber(id) ~= nil and tonumber(id) > 0 or false
end
function S.eventList(ref, limit)
    return MySQL.query.await('SELECT id, kind, character_id, detail, created_at FROM cm_crime_events WHERE session_ref = ? ORDER BY id DESC LIMIT ?', { ref, limit or 60 }) or {}
end
