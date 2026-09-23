-- cm-law/server/charges.lua
-- Editable Criminal Code: charges used to be hardcoded in
-- Config.Custody.Charges (shared/config.lua), which meant adding or tuning a
-- charge required editing Lua and restarting the resource. They now live in
-- cm_legal_charges, editable live from an MDT-adjacent admin page. The old
-- config list is used ONLY as a one-time seed the first time the table is
-- empty (fresh install or upgrade from before this feature), so nothing
-- changes for a server that's already running -- after that, the database
-- is authoritative and shared/config.lua's list is no longer read.
--
-- Cached in memory (ChargeCache/ChargeById) and reloaded after every edit,
-- so booking.lua's per-arrest catalog lookups don't hit the database.

local ChargesReady = false
local ChargeCache, ChargeById = {}, {}

local function clean(value, limit)
    return tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, limit)
end

local function slugify(value)
    return clean(value, 48):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
end

-- Shared gate for the Criminal Code page: any organization's leader, or
-- cm-admin permission -- matches the shared jail settings' own gate
-- (LawAdminSetSharedJail in server/booking.lua), since this catalog affects
-- every organization's bookings equally rather than being org-scoped.
local function chargeAdmin(src)
    local member, actorCid = activeMemberForSource(src)
    if member and member.isLeader then return true, actorCid end
    if adminAllowed(src) then return true, actorCid or (member and member.characterId) or 'admin' end
    return false, actorCid
end

local function publicCharge(row)
    return {
        id = row.id, label = row.label, jailMinutes = tonumber(row.jail_minutes) or 0,
        fine = tonumber(row.fine) or 0, enabled = tonumber(row.enabled) == 1,
        updatedBy = row.updated_by, updatedAt = tostring(row.updated_at or ''),
    }
end

local function reloadCharges()
    local rows = MySQL.query.await('SELECT * FROM cm_legal_charges ORDER BY label ASC') or {}
    ChargeCache, ChargeById = {}, {}
    for _, row in ipairs(rows) do
        local charge = publicCharge(row)
        ChargeById[charge.id] = charge
        if charge.enabled then ChargeCache[#ChargeCache + 1] = charge end
    end
end

-- Used by server/booking.lua exactly like the old local chargeCatalog()
-- function it replaces: returns the bookable (enabled) list plus an id
-- lookup table.
function LawChargeCatalog()
    return ChargeCache, ChargeById
end

lib.callback.register('cm-law:server:listCharges', function(src)
    local allowed = chargeAdmin(src)
    if not allowed then return { ok = false, error = 'Only an organization leader or admin can manage the Criminal Code.' } end
    local rows = MySQL.query.await('SELECT * FROM cm_legal_charges ORDER BY label ASC') or {}
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = publicCharge(row) end
    return { ok = true, charges = list }
end)

lib.callback.register('cm-law:server:createCharge', function(src, data)
    local allowed, actorCid = chargeAdmin(src)
    if not allowed then return { ok = false, error = 'Only an organization leader or admin can manage the Criminal Code.' } end
    if not rateLimit(src, 'law_charge_create', 1000) then return { ok = false, error = 'Please wait.' } end
    data = type(data) == 'table' and data or {}
    local id = slugify(data.id ~= nil and data.id or data.label)
    local label = clean(data.label, 96)
    local jailMinutes = math.max(0, math.min(180, math.floor(tonumber(data.jailMinutes) or 0)))
    local fine = math.max(0, math.min(100000, math.floor(tonumber(data.fine) or 0)))
    if id == '' or label == '' then return { ok = false, error = 'Enter a charge name.' } end
    if jailMinutes < 1 and fine < 1 then return { ok = false, error = 'A charge needs jail time, a fine, or both.' } end
    if ChargeById[id] then return { ok = false, error = 'A charge with that id already exists.' } end
    local ok = pcall(function()
        MySQL.insert.await([[INSERT INTO cm_legal_charges (id, label, jail_minutes, fine, enabled, updated_by)
            VALUES (?, ?, ?, ?, 1, ?)]], { id, label, jailMinutes, fine, actorCid })
    end)
    if not ok then return { ok = false, error = 'That charge could not be saved.' } end
    reloadCharges()
    logActivity('shared', actorCid, 'charge_created', { chargeId = id, label = label, jailMinutes = jailMinutes, fine = fine })
    return { ok = true, message = ('"%s" added to the Criminal Code.'):format(label) }
end)

lib.callback.register('cm-law:server:updateCharge', function(src, data)
    local allowed, actorCid = chargeAdmin(src)
    if not allowed then return { ok = false, error = 'Only an organization leader or admin can manage the Criminal Code.' } end
    if not rateLimit(src, 'law_charge_update', 1000) then return { ok = false, error = 'Please wait.' } end
    data = type(data) == 'table' and data or {}
    local id = clean(data.id, 48)
    if not ChargeById[id] and not MySQL.scalar.await('SELECT id FROM cm_legal_charges WHERE id = ? LIMIT 1', { id }) then
        return { ok = false, error = 'That charge no longer exists.' }
    end
    local label = clean(data.label, 96)
    local jailMinutes = math.max(0, math.min(180, math.floor(tonumber(data.jailMinutes) or 0)))
    local fine = math.max(0, math.min(100000, math.floor(tonumber(data.fine) or 0)))
    local enabled = data.enabled ~= false
    if label == '' then return { ok = false, error = 'Enter a charge name.' } end
    if jailMinutes < 1 and fine < 1 then return { ok = false, error = 'A charge needs jail time, a fine, or both.' } end
    MySQL.update.await([[UPDATE cm_legal_charges SET label = ?, jail_minutes = ?, fine = ?, enabled = ?, updated_by = ?
        WHERE id = ?]], { label, jailMinutes, fine, enabled and 1 or 0, actorCid, id })
    reloadCharges()
    logActivity('shared', actorCid, 'charge_updated', { chargeId = id, label = label, jailMinutes = jailMinutes, fine = fine, enabled = enabled })
    return { ok = true, message = ('"%s" updated.'):format(label) }
end)

lib.callback.register('cm-law:server:deleteCharge', function(src, id)
    local allowed, actorCid = chargeAdmin(src)
    if not allowed then return { ok = false, error = 'Only an organization leader or admin can manage the Criminal Code.' } end
    id = clean(id, 48)
    if id == '' then return { ok = false, error = 'Invalid charge.' } end
    local affected = MySQL.update.await('DELETE FROM cm_legal_charges WHERE id = ?', { id })
    if tonumber(affected) ~= 1 then return { ok = false, error = 'That charge no longer exists.' } end
    reloadCharges()
    logActivity('shared', actorCid, 'charge_deleted', { chargeId = id })
    return { ok = true, message = 'Charge removed from the Criminal Code.' }
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_charges (
        id VARCHAR(48) NOT NULL,
        label VARCHAR(96) NOT NULL,
        jail_minutes INT UNSIGNED NOT NULL DEFAULT 0,
        fine INT UNSIGNED NOT NULL DEFAULT 0,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local existing = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_legal_charges')) or 0
    if existing == 0 then
        for _, configured in ipairs(Config.Custody.Charges or {}) do
            local id, label = slugify(configured.id), clean(configured.label, 96)
            local jailMinutes = math.max(0, math.floor(tonumber(configured.jailMinutes) or 0))
            local fine = math.max(0, math.floor(tonumber(configured.fine) or 0))
            if id ~= '' and label ~= '' then
                pcall(function()
                    MySQL.insert.await([[INSERT INTO cm_legal_charges (id, label, jail_minutes, fine, enabled, updated_by)
                        VALUES (?, ?, ?, ?, 1, 'seed') ON DUPLICATE KEY UPDATE id = id]],
                        { id, label, jailMinutes, fine })
                end)
            end
        end
    end
    reloadCharges()
    ChargesReady = true
end)
