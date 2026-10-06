-- cm-tuning mechanic-service journal (SQL store for server/service_core.lua). Additive and idempotent (CREATE TABLE IF NOT EXISTS).
-- Every state change is ONE guarded UPDATE (compare-and-swap on `status`). Duplicate guards are UNIQUE keys:
--   active_key   = work order reference while the authorization is live  -> one live tuning authorization per work order
--   vehicle_key  = vehicle_id while the authorization is live            -> one live mechanic tuning operation per vehicle
-- The vehicle's tuning state itself stays in cm_owned_vehicles.mods (written only through CAS in main.lua); nothing else is duplicated here.
CMTuning = CMTuning or {}
local S = {}
CMTuning.ServiceStore = S

S.COLS = {
    status = true, active_key = true, vehicle_key = true, revision = true, request_json = true, caps_json = true, changes_json = true,
    base_hash = true, amount = true, description = true, invoice_ref = true, expires_at = true, paid_at = true, applied_at = true,
    attempts = true, failure_reason = true, owner_snapshot = true, updated_at = true,
}
local NUM = { 'vehicle_id', 'revision', 'amount', 'max_amount', 'created_at', 'updated_at', 'expires_at', 'paid_at', 'applied_at', 'attempts' }

S.DDL = [[CREATE TABLE IF NOT EXISTS cm_tuning_service_operations (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(24) NOT NULL,
        work_order_ref VARCHAR(48) NOT NULL,
        active_key VARCHAR(48) NULL,
        vehicle_key VARCHAR(24) NULL,
        mechanic_cid VARCHAR(48) NOT NULL,
        customer_cid VARCHAR(48) NOT NULL,
        business_type VARCHAR(48) NOT NULL,
        business_id VARCHAR(48) NOT NULL,
        vehicle_id BIGINT NOT NULL,
        shop VARCHAR(16) NOT NULL,
        owner_snapshot VARCHAR(80) NULL,
        revision INT NOT NULL DEFAULT 0,
        max_amount INT NOT NULL,
        amount INT NULL,
        description VARCHAR(160) NULL,
        request_json TEXT NULL,
        caps_json TEXT NULL,
        changes_json TEXT NULL,
        base_hash CHAR(16) NULL,
        request_hash CHAR(16) NOT NULL,
        invoice_ref VARCHAR(48) NULL,
        status VARCHAR(12) NOT NULL DEFAULT 'created',
        attempts INT NOT NULL DEFAULT 0,
        failure_reason VARCHAR(40) NULL,
        created_at BIGINT NOT NULL,
        updated_at BIGINT NOT NULL,
        expires_at BIGINT NULL,
        paid_at BIGINT NULL,
        applied_at BIGINT NULL,
        UNIQUE KEY uq_tun_ref (reference),
        UNIQUE KEY uq_tun_active (active_key),
        UNIQUE KEY uq_tun_vehicle (vehicle_key),
        INDEX idx_tun_status (status, expires_at),
        INDEX idx_tun_invoice (invoice_ref)
    )]]

S.INSERT = [[INSERT INTO cm_tuning_service_operations
        (reference, work_order_ref, active_key, vehicle_key, mechanic_cid, customer_cid, business_type, business_id, vehicle_id, shop,
         owner_snapshot, revision, max_amount, request_hash, status, attempts, created_at, updated_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]]
S.SELECT_REF = 'SELECT * FROM cm_tuning_service_operations WHERE reference = ? LIMIT 1'
S.SELECT_ACTIVE = 'SELECT * FROM cm_tuning_service_operations WHERE active_key = ? LIMIT 1'
S.SELECT_VEHICLE = 'SELECT * FROM cm_tuning_service_operations WHERE vehicle_key = ? LIMIT 1'
S.SELECT_EXPIRABLE = "SELECT * FROM cm_tuning_service_operations WHERE status IN ('created','quoted') AND expires_at < ? ORDER BY id LIMIT ?"

function S.EnsureSchema()
    MySQL.query.await(S.DDL)
    return true
end

local function norm(row)
    if row then for _, k in ipairs(NUM) do if row[k] ~= nil then row[k] = tonumber(row[k]) end end end
    return row
end

-- UPDATE ... SET <cols> WHERE reference = ? AND status IN (...)   (patch value false = NULL)
function S.BuildCas(ref, from, patch)
    local names = {}
    for col in pairs(patch) do
        if not S.COLS[col] then return nil end
        names[#names + 1] = col
    end
    if #names == 0 or #from == 0 then return nil end
    table.sort(names)
    local sets, values = {}, {}
    for _, col in ipairs(names) do
        local v = patch[col]
        if v == false then sets[#sets + 1] = ('`%s` = NULL'):format(col)
        else sets[#sets + 1] = ('`%s` = ?'):format(col); values[#values + 1] = v end
    end
    local marks = {}
    for _ in ipairs(from) do marks[#marks + 1] = '?' end
    values[#values + 1] = ref
    for _, st in ipairs(from) do values[#values + 1] = st end
    return ('UPDATE cm_tuning_service_operations SET %s WHERE reference = ? AND status IN (%s)'):format(table.concat(sets, ', '), table.concat(marks, ',')), values
end

-- -> id | nil, 'duplicate_active' | 'duplicate_vehicle' | 'error'
function S.insert(r)
    local ok, res = pcall(function()
        return MySQL.insert.await(S.INSERT, { r.reference, r.work_order_ref, r.active_key, r.vehicle_key, r.mechanic_cid, r.customer_cid, r.business_type, r.business_id,
            r.vehicle_id, r.shop, r.owner_snapshot, r.revision, r.max_amount, r.request_hash, r.status, r.attempts, r.created_at, r.updated_at, r.expires_at })
    end)
    if ok and tonumber(res) and tonumber(res) > 0 then return tonumber(res) end
    local msg = tostring(res or '')
    if msg:find('uq_tun_vehicle', 1, true) then return nil, 'duplicate_vehicle' end
    if msg:find('uq_tun_active', 1, true) then return nil, 'duplicate_active' end
    return nil, 'error'
end
function S.get(ref) return norm(MySQL.single.await(S.SELECT_REF, { ref })) end
function S.activeByWork(wo) return norm(MySQL.single.await(S.SELECT_ACTIVE, { wo })) end
function S.activeByVehicle(vehicleId) return norm(MySQL.single.await(S.SELECT_VEHICLE, { tostring(vehicleId) })) end
function S.cas(ref, from, patch)
    local sql, values = S.BuildCas(ref, from, patch)
    if not sql then return 0 end
    return tonumber(MySQL.update.await(sql, values)) or 0
end
function S.listExpirable(now, limit)
    local rows = MySQL.query.await(S.SELECT_EXPIRABLE, { now, limit or 50 }) or {}
    for _, r in ipairs(rows) do norm(r) end
    return rows
end
