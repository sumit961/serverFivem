-- ============================================================
-- cm-family | durable family activity audit | v1.4.0
--
-- One append-only activity table is the source of truth for family history.
-- Writes are awaited, deduplicated by event_uid, and queued to a resource file
-- when the database is temporarily unavailable. External writers are restricted
-- to a server-resource allowlist; no client/network event can write audit rows.
-- ============================================================

local B = CMFamilyBridge
local RESOURCE = GetCurrentResourceName()
local pending = {}
local pendingByUid = {}
local uidCounter = 0
local loadedPending = false

local ACTION_META = {
    family_created = { category = 'property', severity = 'info' },
    invite_sent = { category = 'membership', severity = 'info' },
    invite_declined = { category = 'membership', severity = 'info' },
    member_joined = { category = 'membership', severity = 'info' },
    member_left = { category = 'membership', severity = 'warning' },
    member_kicked = { category = 'membership', severity = 'warning', highRisk = true },
    member_promoted = { category = 'membership', severity = 'warning' },
    member_demoted = { category = 'membership', severity = 'warning' },
    member_rank_set = { category = 'membership', severity = 'warning' },
    member_title_set = { category = 'membership', severity = 'info' },
    member_tag_visibility = { category = 'identity', severity = 'info' },
    family_identity_updated = { category = 'identity', severity = 'warning' },
    family_renamed = { category = 'identity', severity = 'warning' },
    family_announcement_updated = { category = 'identity', severity = 'info' },
    family_symbol_visibility = { category = 'identity', severity = 'info' },
    family_symbol_updated = { category = 'identity', severity = 'info' },
    rank_create = { category = 'ranks', severity = 'warning' },
    rank_rename = { category = 'ranks', severity = 'warning' },
    rank_permission = { category = 'ranks', severity = 'warning', highRisk = true },
    rank_symbol_updated = { category = 'ranks', severity = 'info' },
    rank_bank_limit = { category = 'ranks', severity = 'warning' },
    rank_delete = { category = 'ranks', severity = 'critical', highRisk = true },
    founder_succeeded = { category = 'ownership', severity = 'critical', highRisk = true },
    leadership_transferred = { category = 'ownership', severity = 'critical', highRisk = true },
    admin_family_recovery = { category = 'admin', severity = 'warning', highRisk = true },
    vehicle_shared = { category = 'vehicles', severity = 'warning' },
    vehicle_unshared = { category = 'vehicles', severity = 'warning', highRisk = true },
    vehicle_level_set = { category = 'vehicles', severity = 'warning' },
    vehicle_tracked = { category = 'vehicles', severity = 'info' },
    meeting_point_set = { category = 'coordination', severity = 'info' },
    garage_drive_out = { category = 'vehicles', severity = 'info' },
    garage_enter = { category = 'vehicles', severity = 'info' },
    garage_share = { category = 'vehicles', severity = 'warning' },
    garage_assignment_cleared = { category = 'vehicles', severity = 'warning' },
    garage_recall = { category = 'vehicles', severity = 'info' },
    garage_recall_all = { category = 'vehicles', severity = 'warning' },
    garage_recall_to_slot = { category = 'vehicles', severity = 'info' },
    garage_store = { category = 'vehicles', severity = 'info' },
    garage_assign = { category = 'vehicles', severity = 'info' },
    garage_replace = { category = 'vehicles', severity = 'warning' },
    garage_remove_assignment = { category = 'vehicles', severity = 'warning' },
    garage_move_assignment = { category = 'vehicles', severity = 'info' },
    house_enter = { category = 'property', severity = 'info' },
    house_buy = { category = 'property', severity = 'critical', highRisk = true },
    house_purchase_refund = { category = 'property', severity = 'critical', highRisk = true },
    house_create = { category = 'property', severity = 'warning' },
    access_grant = { category = 'security', severity = 'warning' },
    access_revoke = { category = 'security', severity = 'warning' },
    storage_open = { category = 'storage', severity = 'info' },
    storage_deposit = { category = 'storage', severity = 'info' },
    storage_withdraw = { category = 'storage', severity = 'warning' },
    weapon_storage_deposit = { category = 'weapons', severity = 'warning' },
    weapon_storage_withdraw = { category = 'weapons', severity = 'critical', highRisk = true },
    door_lock = { category = 'security', severity = 'warning' },
    door_unlock = { category = 'security', severity = 'warning' },
    bank_deposit = { category = 'bank', severity = 'info' },
    bank_withdraw = { category = 'bank', severity = 'warning' },
    bank_external_charge = { category = 'bank', severity = 'warning' },
    family_chat_sent = { category = 'chat', severity = 'info' },
    family_chat = { category = 'chat', severity = 'info' },
    family_chat_blocked = { category = 'chat', severity = 'warning' },
    family_chat_warn = { category = 'chat', severity = 'warning' },
    family_chat_muted = { category = 'chat', severity = 'warning', highRisk = true },
    family_chat_unmuted = { category = 'chat', severity = 'warning' },
    family_chat_message_removed = { category = 'chat', severity = 'warning', highRisk = true },
    family_house_linked = { category = 'property', severity = 'warning' },
    family_house_unlinked = { category = 'property', severity = 'critical', highRisk = true },
    family_house_sell = { category = 'property', severity = 'critical', highRisk = true },
    admin_evict_family_house = { category = 'property', severity = 'critical', highRisk = true },
    admin_delete_family_house = { category = 'property', severity = 'critical', highRisk = true },
    family_deleted = { category = 'property', severity = 'critical', highRisk = true },
}

local REDACT_KEYS = {
    password = true, token = true, secret = true, license = true, discord = true,
    identifier = true, identifiers = true, ip = true, endpoint = true,
    serial = true, weaponserial = true, weapon_serial = true,
}

local function auditConfig()
    return Config.Audit or {}
end

local function trim(value, maxLength)
    value = tostring(value or ''):gsub('[\r\n\t]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, tonumber(maxLength) or 255)
end

local function sanitize(value, depth, seen)
    depth = tonumber(depth) or 0
    if depth > 4 then return '[max-depth]' end
    local kind = type(value)
    if kind == 'nil' then return nil end
    if kind == 'boolean' or kind == 'number' then return value end
    if kind == 'string' then return trim(value, 512) end
    if kind ~= 'table' then return trim(value, 128) end

    seen = seen or {}
    if seen[value] then return '[cycle]' end
    seen[value] = true
    local out, count = {}, 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 48 then
            out._truncated = true
            break
        end
        local cleanKey = trim(key, 64)
        local normalized = cleanKey:lower():gsub('[^a-z0-9_]', '')
        if REDACT_KEYS[normalized] then
            out[cleanKey] = '[redacted]'
        else
            out[cleanKey] = sanitize(child, depth + 1, seen)
        end
    end
    seen[value] = nil
    return out
end

local function buildInsert(tableName, fields)
    local columns, marks, values = {}, {}, {}
    for _, field in ipairs(fields) do
        if field[2] ~= nil then
            columns[#columns + 1] = ('`%s`'):format(field[1])
            marks[#marks + 1] = '?'
            values[#values + 1] = field[2]
        end
    end
    return ('INSERT INTO `%s` (%s) VALUES (%s)'):format(
        tableName, table.concat(columns, ', '), table.concat(marks, ', ')), values
end

local function makeUid(familyId, action)
    uidCounter = uidCounter + 1
    return ('fam:%s:%s:%s:%s:%s'):format(
        tostring(os.time()), tostring(familyId or 0), trim(action, 40),
        tostring(GetGameTimer()), tostring(uidCounter))
end

local function resolveTarget(detail, options)
    detail = type(detail) == 'table' and detail or {}
    options = type(options) == 'table' and options or {}
    return options.targetCid or detail.targetCid or detail.target or detail.to
        or detail.newFounder or detail.characterId or detail.character_id
end

local function classify(action, detail, options)
    local meta = ACTION_META[action] or {}
    local category = trim(options.category or meta.category or 'family', 32):lower()
    local severity = trim(options.severity or meta.severity or 'info', 16):lower()
    local highRisk = options.highRisk == true or meta.highRisk == true
    local amount = tonumber(options.amount or (type(detail) == 'table' and (detail.amount or detail.payout)))
    if action == 'bank_withdraw' and amount and amount >= (tonumber(auditConfig().highRiskBankAmount) or 100000) then
        highRisk, severity = true, 'critical'
    end
    return category, severity, highRisk, amount
end

local function recordFor(familyId, actorCid, action, detail, options)
    familyId = tonumber(familyId)
    action = trim(action, 64):lower():gsub('[^a-z0-9_:%-]', '_')
    detail = sanitize(type(detail) == 'table' and detail or {}) or {}
    options = type(options) == 'table' and options or {}
    local targetCid = resolveTarget(detail, options)
    local category, severity, highRisk, amount = classify(action, detail, options)
    local actorName = options.actorName
    if not actorName and actorCid ~= nil and B and B.GetCharName then
        local ok, value = pcall(B.GetCharName, actorCid)
        if ok then actorName = value end
    end
    local targetName = options.targetName
    if not targetName and targetCid ~= nil and B and B.GetCharName then
        local ok, value = pcall(B.GetCharName, targetCid)
        if ok then targetName = value end
    end
    local vehicleId = tonumber(options.vehicleId or detail.vehicleId or detail.vehicle_id or detail.vehicle)
    local houseId = tonumber(options.houseId or detail.houseId or detail.house_id)
    local entityType = trim(options.entityType or (vehicleId and 'vehicle') or (houseId and 'house') or '', 32)
    local entityId = options.entityId or (vehicleId and tostring(vehicleId)) or (houseId and tostring(houseId)) or nil

    return {
        event_uid = trim(options.eventUid or makeUid(familyId, action), 96),
        family_id = familyId,
        category = category,
        action = action,
        severity = severity,
        high_risk = highRisk == true,
        status = trim(options.status or 'success', 16):lower(),
        actor_cid = actorCid ~= nil and trim(actorCid, 64) or nil,
        actor_name = actorName and trim(actorName, 128) or nil,
        target_cid = targetCid ~= nil and trim(targetCid, 64) or nil,
        target_name = targetName and trim(targetName, 128) or nil,
        source_resource = trim(options.sourceResource or RESOURCE, 64),
        entity_type = entityType ~= '' and entityType or nil,
        entity_id = entityId and trim(entityId, 96) or nil,
        house_id = houseId,
        vehicle_id = vehicleId,
        amount = amount and math.floor(amount) or nil,
        detail = detail,
        created_at = os.date('%Y-%m-%d %H:%M:%S'),
        created_unix = os.time(),
    }
end

local function insertRecord(record)
    if not (auditConfig().enabled ~= false) then return true, 0 end
    local detailJson = json.encode(record.detail or {})
    local sql, values = buildInsert('cm_family_activity_log', {
        { 'event_uid', record.event_uid },
        { 'family_id', record.family_id },
        { 'category', record.category },
        { 'action', record.action },
        { 'severity', record.severity },
        { 'high_risk', record.high_risk and 1 or 0 },
        { 'status', record.status },
        { 'actor_cid', record.actor_cid },
        { 'actor_name', record.actor_name },
        { 'target_cid', record.target_cid },
        { 'target_name', record.target_name },
        { 'source_resource', record.source_resource },
        { 'entity_type', record.entity_type },
        { 'entity_id', record.entity_id },
        { 'house_id', record.house_id },
        { 'vehicle_id', record.vehicle_id },
        { 'amount', record.amount },
        { 'detail', detailJson },
        { 'created_at', record.created_at },
    })
    sql = sql .. ' ON DUPLICATE KEY UPDATE `event_uid` = VALUES(`event_uid`)'
    local ok, result = pcall(function() return MySQL.insert.await(sql, values) end)
    if ok then return true, tonumber(result) or 0 end
    return false, tostring(result)
end

local function persistPending()
    local ok, encoded = pcall(json.encode, pending)
    if not ok then return false end
    return SaveResourceFile(RESOURCE, tostring(auditConfig().pendingFile or 'audit_pending.json'), encoded, -1) == true
end

local function enqueue(record, reason)
    if pendingByUid[record.event_uid] then return end
    record._last_error = trim(reason or 'database_unavailable', 512)
    pending[#pending + 1] = record
    pendingByUid[record.event_uid] = true
    persistPending()
end

local function publish(record, id, queued)
    local payload = {}
    for key, value in pairs(record) do
        if key:sub(1, 1) ~= '_' then payload[key] = value end
    end
    payload.id = tonumber(id) or nil
    payload.queued = queued == true
    TriggerEvent('cm-family:server:activityLogged', payload)
    if payload.high_risk == true then
        TriggerEvent('cm-family:server:highRiskActivity', payload)
        -- cm-admin can register this server-only event or poll the read export.
        TriggerEvent('cm-admin:server:familyActivity', payload)
    end
end

local function mirrorLegacy(record)
    pcall(function()
        MySQL.insert.await(
            'INSERT INTO cm_family_log (family_id, actor_cid, action, detail) VALUES (?, ?, ?, ?)',
            { record.family_id, record.actor_cid or false, record.action, json.encode(record.detail or {}) })
    end)
end

function LogFamily(familyId, actorCid, action, detail, options)
    if auditConfig().enabled == false then return true, 0 end
    local record = recordFor(familyId, actorCid, action, detail, options)
    if not record.family_id or record.family_id <= 0 then return false, 'invalid_family_id' end

    local inserted, result = insertRecord(record)
    if inserted then
        mirrorLegacy(record)
        publish(record, result, false)
        return true, result
    end

    enqueue(record, result)
    publish(record, nil, true)
    print(('[cm-family] ^1activity audit queued after DB failure family=%s action=%s: %s^7')
        :format(tostring(record.family_id), tostring(record.action), tostring(result)))
    return false, result
end

local function decodeDetail(value)
    if type(value) == 'table' then return value end
    if value == nil or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end

function GetFamilyActivityLogs(familyId, options)
    familyId = tonumber(familyId)
    options = type(options) == 'table' and options or {}
    if not familyId then return {} end
    local limit = math.max(1, math.min(tonumber(options.limit) or tonumber(auditConfig().menuLimit) or 75, 500))
    local clauses, values = { 'family_id = ?' }, { familyId }
    if options.beforeId and tonumber(options.beforeId) then
        clauses[#clauses + 1] = 'id < ?'
        values[#values + 1] = tonumber(options.beforeId)
    end
    if options.category and tostring(options.category) ~= '' then
        clauses[#clauses + 1] = 'category = ?'
        values[#values + 1] = trim(options.category, 32):lower()
    end
    if options.highRisk == true then clauses[#clauses + 1] = 'high_risk = 1' end
    values[#values + 1] = limit
    local rows = MySQL.query.await(([[
        SELECT id, event_uid, family_id, category, action, severity, high_risk, status,
               actor_cid, actor_name, target_cid, target_name, source_resource,
               entity_type, entity_id, house_id, vehicle_id, amount, detail, created_at
        FROM cm_family_activity_log
        WHERE %s
        ORDER BY id DESC
        LIMIT ?
    ]]):format(table.concat(clauses, ' AND ')), values) or {}
    for _, row in ipairs(rows) do
        row.id = tonumber(row.id) or row.id
        row.family_id = tonumber(row.family_id) or row.family_id
        row.high_risk = row.high_risk == true or tonumber(row.high_risk) == 1
        row.house_id = tonumber(row.house_id) or row.house_id
        row.vehicle_id = tonumber(row.vehicle_id) or row.vehicle_id
        row.amount = tonumber(row.amount) or row.amount
        row.detail = decodeDetail(row.detail)
    end
    return rows
end

local function writerAllowed(invoker)
    invoker = tostring(invoker or '')
    return invoker ~= '' and auditConfig().authorizedWriters
        and auditConfig().authorizedWriters[invoker] == true
end

exports('WriteFamilyActivity', function(familyId, actorCid, action, detail, options)
    local invoker = GetInvokingResource()
    if not writerAllowed(invoker) then return false, 'resource_not_authorized' end
    options = type(options) == 'table' and options or {}
    options.sourceResource = invoker
    return LogFamily(familyId, actorCid, action, detail, options)
end)

exports('LogFamilyChatModeration', function(familyId, actorCid, targetCid, moderationAction, reason, metadata)
    local invoker = GetInvokingResource()
    if invoker ~= 'cm-chat' and invoker ~= 'cm-admin' and invoker ~= RESOURCE then
        return false, 'resource_not_authorized'
    end
    local allowed = { warn = true, muted = true, unmuted = true, message_removed = true, blocked = true }
    moderationAction = trim(moderationAction, 32):lower()
    if not allowed[moderationAction] then return false, 'invalid_moderation_action' end
    local detail = type(metadata) == 'table' and metadata or {}
    detail.target = targetCid
    detail.reason = trim(reason or '', 256)
    return LogFamily(familyId, actorCid, 'family_chat_' .. moderationAction, detail, {
        sourceResource = invoker,
        targetCid = targetCid,
        status = moderationAction == 'blocked' and 'denied' or 'success',
    })
end)

local function adminReaderAllowed(adminSource)
    local invoker = GetInvokingResource()
    if not invoker or not auditConfig().adminReaders or auditConfig().adminReaders[invoker] ~= true then
        return false, 'resource_not_authorized'
    end
    if GetResourceState(invoker) ~= 'started' then return false, 'admin_resource_not_started' end
    if adminSource == nil then return true end
    local allowed = false
    for _, permission in ipairs({ 'family.logs.view', 'admin.logs.view', 'family.view' }) do
        local ok, result = pcall(function() return exports[invoker]:HasPermission(tonumber(adminSource), permission) end)
        if ok and result == true then allowed = true break end
    end
    return allowed, allowed and nil or 'no_permission'
end

exports('AdminGetFamilyActivity', function(adminSource, familyId, options)
    local allowed, why = adminReaderAllowed(adminSource)
    if not allowed then return false, why end
    options = type(options) == 'table' and options or {}
    options.limit = math.min(tonumber(options.limit) or tonumber(auditConfig().adminLimit) or 250, 500)
    return true, GetFamilyActivityLogs(familyId, options)
end)

exports('AdminGetHighRiskFamilyActivity', function(adminSource, options)
    local allowed, why = adminReaderAllowed(adminSource)
    if not allowed then return false, why end
    options = type(options) == 'table' and options or {}
    local limit = math.max(1, math.min(tonumber(options.limit) or tonumber(auditConfig().adminLimit) or 250, 500))
    local clauses, values = { 'high_risk = 1' }, {}
    if options.familyId and tonumber(options.familyId) then
        clauses[#clauses + 1] = 'family_id = ?'
        values[#values + 1] = tonumber(options.familyId)
    end
    if options.beforeId and tonumber(options.beforeId) then
        clauses[#clauses + 1] = 'id < ?'
        values[#values + 1] = tonumber(options.beforeId)
    end
    values[#values + 1] = limit
    local rows = MySQL.query.await(([[
        SELECT id, event_uid, family_id, category, action, severity, high_risk, status,
               actor_cid, actor_name, target_cid, target_name, source_resource,
               entity_type, entity_id, house_id, vehicle_id, amount, detail, created_at
        FROM cm_family_activity_log
        WHERE %s
        ORDER BY id DESC
        LIMIT ?
    ]]):format(table.concat(clauses, ' AND ')), values) or {}
    for _, row in ipairs(rows) do
        row.high_risk = true
        row.detail = decodeDetail(row.detail)
    end
    return true, rows
end)

local function loadPending()
    if loadedPending then return end
    loadedPending = true
    local raw = LoadResourceFile(RESOURCE, tostring(auditConfig().pendingFile or 'audit_pending.json'))
    if not raw or raw == '' then return end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return end
    for _, record in ipairs(decoded) do
        if type(record) == 'table' and record.event_uid and not pendingByUid[record.event_uid] then
            pending[#pending + 1] = record
            pendingByUid[record.event_uid] = true
        end
    end
end

local function flushPending()
    if #pending == 0 then return end
    local kept = {}
    pendingByUid = {}
    for _, record in ipairs(pending) do
        local inserted, result = insertRecord(record)
        if inserted then
            mirrorLegacy(record)
            publish(record, result, false)
        else
            record._last_error = trim(result, 512)
            kept[#kept + 1] = record
            pendingByUid[record.event_uid] = true
        end
    end
    pending = kept
    persistPending()
end

CreateThread(function()
    loadPending()
    while true do
        Wait(math.max(5000, tonumber(auditConfig().retryIntervalMs) or 15000))
        local ready = type(CMFamilyIsDatabaseReady) == 'function' and select(1, CMFamilyIsDatabaseReady())
        if ready then flushPending() end
    end
end)

CreateThread(function()
    while true do
        Wait(6 * 60 * 60 * 1000)
        local days = math.max(1, tonumber(auditConfig().retentionDays) or 180)
        pcall(function()
            MySQL.update.await(
                ('DELETE FROM cm_family_activity_log WHERE created_at < DATE_SUB(NOW(), INTERVAL %d DAY)'):format(days))
        end)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE then persistPending() end
end)
