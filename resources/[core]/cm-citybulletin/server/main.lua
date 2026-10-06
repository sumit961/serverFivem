CMCityBulletin = CMCityBulletin or {}

local RESOURCE = GetCurrentResourceName()
local adminLocks = {}
local noticeLocks = {}
local readThrottle = {}
local sourceCharacters = {}

local function result(ok, reason, extra)
    local value = extra or {}
    value.ok = ok
    if reason then value.reason = reason end
    return value
end

local function trim(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%z\1-\8\11\12\14-\31]', '')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > max then return nil end
    return value
end

local function noticeId(value)
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
    value = trim(tostring(value):lower(), Config.Security.maxNoticeId)
    if not value or not value:match('^[a-z0-9][a-z0-9_%-]*$') then return nil end
    return value
end

local function characterId(value)
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
    value = trim(tostring(value), 64)
    if not value or not value:match('^[%w_%-]+$') then return nil end
    return value
end

local function currentTime()
    return os.time()
end

local function databaseReady()
    return CMCityBulletin.DatabaseReady == true
end

local function lock(bucket, key, milliseconds)
    local locks = bucket == 'notice' and noticeLocks or adminLocks
    local lockKey = ('%s:%s'):format(bucket, tostring(key))
    local now = GetGameTimer()
    if (locks[lockKey] or 0) > now then return false end
    locks[lockKey] = now + milliseconds
    return true
end

local function noticeLock(id)
    if noticeLocks[id] then return false end
    noticeLocks[id] = true
    return true
end

local function releaseNoticeLock(id)
    noticeLocks[id] = nil
end

local function currentCharacter(src)
    src = tonumber(src)
    if not src or src <= 0 or GetPlayerName(src) == nil then return nil end

    local loadedOk, loaded = pcall(function()
        return exports['cm-playerdata']:IsCharacterLoaded(src)
    end)
    if not loadedOk or loaded ~= true then return nil end

    local idOk, rawId = pcall(function()
        return exports['cm-playerdata']:GetCharacterId(src)
    end)
    local id = idOk and characterId(rawId) or nil
    if id then sourceCharacters[src] = id end
    return id
end

local function isDead(src)
    local ok, dead = pcall(function()
        return exports['cm-playerdata']:IsDead(src)
    end)
    return not ok or dead ~= false
end

local function parseBoolean(value)
    if value == true or value == 1 or value == '1' then return true end
    if value == false or value == 0 or value == '0' then return false end
    return nil
end

local function parseTimestamp(value, allowClear)
    if allowClear and (value == false or value == '') then return nil, true end
    local timestamp = tonumber(value)
    if not timestamp or timestamp % 1 ~= 0 or timestamp < 1 or timestamp > Config.Security.maxTimestamp then
        return nil, false
    end
    return timestamp, true
end

local function normalizeNotice(raw, existing)
    if type(raw) ~= 'table' then return nil, 'invalid_notice' end

    local id = noticeId(raw.noticeId ~= nil and raw.noticeId or raw.notice_id or (existing and existing.notice_id))
    local title = trim(raw.title ~= nil and raw.title or (existing and existing.title) or '', Config.Security.maxTitle)
    local summary = trim(raw.summary ~= nil and raw.summary or (existing and existing.summary) or '', Config.Security.maxSummary)
    local body = trim(raw.body ~= nil and raw.body or (existing and existing.body) or '', Config.Security.maxBody)
    local category = trim(tostring(raw.category ~= nil and raw.category or (existing and existing.category) or ''):lower(), Config.Security.maxCategory)
    local priority = trim(tostring(raw.priority ~= nil and raw.priority or (existing and existing.priority) or ''):lower(), Config.Security.maxPriority)

    if not id then return nil, 'invalid_notice_id' end
    if not title or not summary or not body then return nil, 'missing_notice_text' end
    if not category or not Config.Categories[category] then return nil, 'invalid_category' end
    if not priority or not Config.Priorities[priority] then return nil, 'invalid_priority' end

    local enabled = existing and tonumber(existing.enabled) == 1 or true
    if raw.enabled ~= nil then
        enabled = parseBoolean(raw.enabled)
        if enabled == nil then return nil, 'invalid_enabled_state' end
    end

    local pinned = existing and tonumber(existing.pinned) == 1 or false
    if raw.pinned ~= nil then
        pinned = parseBoolean(raw.pinned)
        if pinned == nil then return nil, 'invalid_pinned_state' end
    end

    local expiresProvided = raw.expiresAt ~= nil or raw.expires_at ~= nil
    local expiresAt = existing and tonumber(existing.expires_ts) or nil
    if expiresProvided then
        local rawExpiry = raw.expiresAt ~= nil and raw.expiresAt or raw.expires_at
        local valid
        expiresAt, valid = parseTimestamp(rawExpiry, true)
        if not valid then return nil, 'invalid_expiry_timestamp' end
        if expiresAt and expiresAt <= currentTime() then return nil, 'expiry_must_be_in_future' end
    end

    if existing and tonumber(existing.archived) == 1 and enabled then
        return nil, 'archived_notice_cannot_be_enabled'
    end
    if enabled and expiresAt and expiresAt <= currentTime() then
        return nil, 'expired_notice_cannot_be_enabled'
    end

    return {
        noticeId = id,
        title = title,
        summary = summary,
        body = body,
        category = category,
        priority = priority,
        expiresAt = expiresAt,
        enabled = enabled,
        pinned = pinned,
    }
end

local function adminAuthorized(adminSrc)
    if GetInvokingResource() ~= Config.Admin.invokingResource then return false end
    if GetResourceState(Config.Admin.invokingResource) ~= 'started' then return false end
    adminSrc = tonumber(adminSrc)
    if not adminSrc or adminSrc <= 0 or GetPlayerName(adminSrc) == nil then return false end

    local ok, allowed = pcall(function()
        return exports[Config.Admin.invokingResource]:HasPermission(adminSrc, Config.Admin.permission)
    end)
    return ok and allowed == true
end

local function adminMutation(adminSrc, lockKey)
    if not adminAuthorized(adminSrc) then return false, 'admin_permission_required' end
    if not databaseReady() then return false, 'database_unavailable' end
    local actor = currentCharacter(adminSrc)
    if not actor or isDead(adminSrc) then return false, 'admin_character_unavailable' end
    if not lock('admin', ('%s:%s'):format(adminSrc, lockKey or 'general'), Config.Security.adminCooldownMs) then
        return false, 'rate_limited'
    end
    return true, actor
end

local function withNoticeLock(id, callback)
    if not noticeLock(id) then return result(false, 'request_in_progress') end
    local ok, response = pcall(callback)
    releaseNoticeLock(id)
    if not ok then return result(false, 'request_failed') end
    return response
end

local function noticeRow(id)
    return MySQL.single.await([[SELECT notice_id, title, summary, body, category, priority,
        UNIX_TIMESTAMP(published_at) AS published_ts, UNIX_TIMESTAMP(expires_at) AS expires_ts,
        enabled, archived, pinned, created_by_character_id, updated_by_character_id,
        archived_by_character_id, UNIX_TIMESTAMP(archived_at) AS archived_ts,
        UNIX_TIMESTAMP(created_at) AS created_ts, UNIX_TIMESTAMP(updated_at) AS updated_ts
        FROM cm_citybulletin_notices WHERE notice_id = ? LIMIT 1]], { id })
end

local function publicNotice(row, read)
    if not row then return nil end
    return {
        id = row.notice_id,
        title = row.title,
        summary = row.summary,
        body = row.body,
        category = row.category,
        priority = row.priority,
        publishedAt = tonumber(row.published_ts),
        expiresAt = row.expires_ts and tonumber(row.expires_ts) or nil,
        enabled = tonumber(row.enabled) == 1,
        archived = tonumber(row.archived) == 1,
        pinned = tonumber(row.pinned) == 1,
        archivedAt = row.archived_ts and tonumber(row.archived_ts) or nil,
        read = read == true,
    }
end

local function adminNotice(row)
    local value = publicNotice(row, false)
    if not value then return nil end
    value.createdByCharacterId = row.created_by_character_id
    value.updatedByCharacterId = row.updated_by_character_id
    value.archivedByCharacterId = row.archived_by_character_id
    value.createdAt = row.created_ts and tonumber(row.created_ts) or nil
    value.updatedAt = row.updated_ts and tonumber(row.updated_ts) or nil
    return value
end

local function audit(adminSrc, action, id)
    pcall(function()
        TriggerEvent('cm-admin:server:addLog', adminSrc, 'citybulletin_' .. action, {
            category = 'system',
            noticeId = id,
        })
    end)
end

exports('AdminCreateNotice', function(adminSrc, raw)
    local allowed, actorOrReason = adminMutation(adminSrc, 'create')
    if not allowed then return result(false, actorOrReason) end
    if type(raw) ~= 'table' then return result(false, 'invalid_notice') end

    local notice, reason = normalizeNotice(raw)
    if not notice then return result(false, reason) end
    local now = currentTime()
    local ok, changed = pcall(function()
        return MySQL.update.await([[INSERT INTO cm_citybulletin_notices
            (notice_id, title, summary, body, category, priority, published_at, expires_at,
             enabled, archived, pinned, created_by_character_id, updated_by_character_id)
            VALUES (?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?, 0, ?, ?, ?)]], {
            notice.noticeId, notice.title, notice.summary, notice.body, notice.category,
            notice.priority, now, notice.expiresAt, notice.enabled and 1 or 0,
            notice.pinned and 1 or 0, actorOrReason, actorOrReason,
        })
    end)
    if not ok or tonumber(changed) ~= 1 then return result(false, 'notice_create_failed') end
    audit(adminSrc, 'created', notice.noticeId)
    return result(true, nil, { notice = adminNotice(noticeRow(notice.noticeId)) })
end)

exports('AdminUpdateNotice', function(adminSrc, rawId, raw)
    local id = noticeId(rawId)
    if not id then return result(false, 'invalid_notice_id') end
    local allowed, actorOrReason = adminMutation(adminSrc, id)
    if not allowed then return result(false, actorOrReason) end
    return withNoticeLock(id, function()
        local existing = noticeRow(id)
        if not existing then return result(false, 'notice_not_found') end
        raw = type(raw) == 'table' and raw or {}
        raw.noticeId = id
        local notice, reason = normalizeNotice(raw, existing)
        if not notice then return result(false, reason) end
        local ok, changed = pcall(function()
            return MySQL.update.await([[UPDATE cm_citybulletin_notices SET
                title = ?, summary = ?, body = ?, category = ?, priority = ?,
                expires_at = FROM_UNIXTIME(?), enabled = ?, pinned = ?, updated_by_character_id = ?
                WHERE notice_id = ? AND archived = ?]], {
                notice.title, notice.summary, notice.body, notice.category, notice.priority,
                notice.expiresAt, notice.enabled and 1 or 0, notice.pinned and 1 or 0,
                actorOrReason, id, tonumber(existing.archived) == 1 and 1 or 0,
            })
        end)
        if not ok or changed == nil then return result(false, 'notice_update_failed') end
        audit(adminSrc, 'updated', id)
        return result(true, nil, { notice = adminNotice(noticeRow(id)) })
    end)
end)

exports('AdminSetNoticeEnabled', function(adminSrc, rawId, enabled)
    local id = noticeId(rawId)
    enabled = parseBoolean(enabled)
    if not id then return result(false, 'invalid_notice_id') end
    if enabled == nil then return result(false, 'invalid_enabled_state') end
    local allowed, actorOrReason = adminMutation(adminSrc, id)
    if not allowed then return result(false, actorOrReason) end
    return withNoticeLock(id, function()
        local existing = noticeRow(id)
        if not existing then return result(false, 'notice_not_found') end
        if tonumber(existing.archived) == 1 and enabled then return result(false, 'archived_notice_cannot_be_enabled') end
        if enabled and existing.expires_ts and tonumber(existing.expires_ts) <= currentTime() then
            return result(false, 'expired_notice_cannot_be_enabled')
        end
        local changed = MySQL.update.await([[UPDATE cm_citybulletin_notices
            SET enabled = ?, updated_by_character_id = ? WHERE notice_id = ?]], {
            enabled and 1 or 0, actorOrReason, id,
        })
        if changed == nil then return result(false, 'notice_update_failed') end
        audit(adminSrc, enabled and 'enabled' or 'disabled', id)
        return result(true, nil, { enabled = enabled })
    end)
end)

exports('AdminSetNoticePinned', function(adminSrc, rawId, pinned)
    local id = noticeId(rawId)
    pinned = parseBoolean(pinned)
    if not id then return result(false, 'invalid_notice_id') end
    if pinned == nil then return result(false, 'invalid_pinned_state') end
    local allowed, actorOrReason = adminMutation(adminSrc, id)
    if not allowed then return result(false, actorOrReason) end
    return withNoticeLock(id, function()
        local existing = noticeRow(id)
        if not existing then return result(false, 'notice_not_found') end
        if pinned and (tonumber(existing.archived) == 1 or tonumber(existing.enabled) ~= 1) then
            return result(false, 'only_active_notice_can_be_pinned')
        end
        local changed = MySQL.update.await([[UPDATE cm_citybulletin_notices
            SET pinned = ?, updated_by_character_id = ? WHERE notice_id = ?]], {
            pinned and 1 or 0, actorOrReason, id,
        })
        if changed == nil then return result(false, 'notice_update_failed') end
        audit(adminSrc, pinned and 'pinned' or 'unpinned', id)
        return result(true, nil, { pinned = pinned })
    end)
end)

exports('AdminArchiveNotice', function(adminSrc, rawId)
    local id = noticeId(rawId)
    if not id then return result(false, 'invalid_notice_id') end
    local allowed, actorOrReason = adminMutation(adminSrc, id)
    if not allowed then return result(false, actorOrReason) end
    return withNoticeLock(id, function()
        local existing = noticeRow(id)
        if not existing then return result(false, 'notice_not_found') end
        if tonumber(existing.archived) == 1 then return result(true, nil, { alreadyArchived = true }) end
        local changed = MySQL.update.await([[UPDATE cm_citybulletin_notices SET
            enabled = 0, archived = 1, pinned = 0, archived_by_character_id = ?,
            archived_at = FROM_UNIXTIME(?), updated_by_character_id = ?
            WHERE notice_id = ? AND archived = 0]], {
            actorOrReason, currentTime(), actorOrReason, id,
        })
        if changed == nil then return result(false, 'notice_archive_failed') end
        audit(adminSrc, 'archived', id)
        return result(true, nil, { archived = true })
    end)
end)

exports('AdminListNotices', function(adminSrc)
    local allowed, actorOrReason = adminMutation(adminSrc, 'list')
    if not allowed then return result(false, actorOrReason) end
    local rows = MySQL.query.await([[SELECT notice_id, title, summary, body, category, priority,
        UNIX_TIMESTAMP(published_at) AS published_ts, UNIX_TIMESTAMP(expires_at) AS expires_ts,
        enabled, archived, pinned, created_by_character_id, updated_by_character_id,
        archived_by_character_id, UNIX_TIMESTAMP(archived_at) AS archived_ts,
        UNIX_TIMESTAMP(created_at) AS created_ts, UNIX_TIMESTAMP(updated_at) AS updated_ts
        FROM cm_citybulletin_notices ORDER BY published_at DESC LIMIT ?]], {
        Config.Security.adminListLimit,
    }) or {}
    local notices = {}
    for _, row in ipairs(rows) do notices[#notices + 1] = adminNotice(row) end
    return result(true, nil, { notices = notices })
end)

local function dashboard(src)
    if not databaseReady() then return result(false, 'database_unavailable') end
    local cid = currentCharacter(src)
    if not cid or isDead(src) then return result(false, 'character_unavailable') end

    local timestamp = currentTime()
    local rows = MySQL.query.await([[SELECT n.notice_id, n.title, n.summary, n.body,
        n.category, n.priority, UNIX_TIMESTAMP(n.published_at) AS published_ts,
        UNIX_TIMESTAMP(n.expires_at) AS expires_ts, n.enabled, n.archived, n.pinned,
        UNIX_TIMESTAMP(n.archived_at) AS archived_ts, r.notice_id AS read_notice_id
        FROM cm_citybulletin_notices n
        LEFT JOIN cm_citybulletin_reads r ON r.notice_id = n.notice_id AND r.character_id = ?
        WHERE n.enabled = 1 AND n.archived = 0
          AND n.published_at <= FROM_UNIXTIME(?)
          AND (n.expires_at IS NULL OR n.expires_at > FROM_UNIXTIME(?))
        ORDER BY n.pinned DESC, FIELD(n.priority, 'urgent', 'important', 'normal'),
                 n.published_at DESC LIMIT ?]], { cid, timestamp, timestamp, Config.Security.dashboardLimit }) or {}

    local archived = MySQL.query.await([[SELECT n.notice_id, n.title, n.summary, n.body,
        n.category, n.priority, UNIX_TIMESTAMP(n.published_at) AS published_ts,
        UNIX_TIMESTAMP(n.expires_at) AS expires_ts, n.enabled, n.archived, n.pinned,
        UNIX_TIMESTAMP(n.archived_at) AS archived_ts, r.notice_id AS read_notice_id
        FROM cm_citybulletin_notices n
        LEFT JOIN cm_citybulletin_reads r ON r.notice_id = n.notice_id AND r.character_id = ?
        WHERE n.archived = 1
        ORDER BY n.archived_at DESC, n.published_at DESC LIMIT ?]], { cid, Config.Security.dashboardLimit }) or {}

    local current, archive, categories = {}, {}, {}
    local categorySeen = {}
    for _, row in ipairs(rows) do
        current[#current + 1] = publicNotice(row, row.read_notice_id ~= nil)
        if not categorySeen[row.category] then categorySeen[row.category] = true; categories[#categories + 1] = row.category end
    end
    for _, row in ipairs(archived) do
        archive[#archive + 1] = publicNotice(row, row.read_notice_id ~= nil)
        if not categorySeen[row.category] then categorySeen[row.category] = true; categories[#categories + 1] = row.category end
    end
    table.sort(categories)
    return result(true, nil, {
        serverTime = timestamp,
        current = current,
        archived = archive,
        categories = categories,
    })
end

lib.callback.register('cm-citybulletin:server:getDashboard', function(src)
    return dashboard(src)
end)

lib.callback.register('cm-citybulletin:server:markRead', function(src, request)
    if not databaseReady() then return result(false, 'database_unavailable') end
    request = type(request) == 'table' and request or {}
    local id = noticeId(request.noticeId or request.notice_id)
    local cid = currentCharacter(src)
    if not id then return result(false, 'invalid_notice_id') end
    if not cid or isDead(src) then return result(false, 'character_unavailable') end

    local row = MySQL.single.await([[SELECT notice_id FROM cm_citybulletin_notices
        WHERE notice_id = ? AND (archived = 1 OR (enabled = 1 AND archived = 0
        AND published_at <= FROM_UNIXTIME(?) AND (expires_at IS NULL OR expires_at > FROM_UNIXTIME(?))))
        LIMIT 1]], { id, currentTime(), currentTime() })
    if not row then return result(false, 'notice_unavailable') end

    local throttleKey = ('%s:%s'):format(cid, id)
    local now = GetGameTimer()
    if (readThrottle[throttleKey] or 0) > now then
        return result(true, nil, { alreadyRead = true, noticeId = id })
    end
    readThrottle[throttleKey] = now + 250

    local changed = MySQL.update.await([[INSERT IGNORE INTO cm_citybulletin_reads
        (character_id, notice_id, read_at) VALUES (?, ?, NOW())]], { cid, id })
    if changed == nil then return result(false, 'read_state_failed') end
    return result(true, nil, { read = tonumber(changed) == 1, alreadyRead = tonumber(changed) ~= 1, noticeId = id })
end)

local function clearSource(src)
    src = tonumber(src)
    if not src then return end
    local cid = sourceCharacters[src]
    if cid then
        for key in pairs(readThrottle) do
            if key:sub(1, #cid + 1) == cid .. ':' then readThrottle[key] = nil end
        end
    end
    for key in pairs(adminLocks) do
        if key:match('^admin:' .. tostring(src) .. ':') then adminLocks[key] = nil end
    end
    sourceCharacters[src] = nil
end

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    clearSource(src)
end)

AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, dead)
    if dead == true then clearSource(src) end
end)

AddEventHandler('playerDropped', function()
    clearSource(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then
        adminLocks, noticeLocks, readThrottle, sourceCharacters = {}, {}, {}, {}
    end
end)
