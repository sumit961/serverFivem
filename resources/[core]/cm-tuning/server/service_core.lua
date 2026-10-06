-- cm-tuning mechanic-service core: the durable journal + state machine for MECHANIC-MEDIATED tuning.
-- PURE (no FiveM natives, no SQL): server/service_store.lua is the SQL store, server/main.lua wires the real adapters, and
-- tests/service_selftest.lua / cm-mechanic/tests/tuning_integration.lua drive it with deterministic doubles.
--
-- One authorization = one quote = one invoice = one payment = one modification = one durable outcome:
--
--   created --Quote--> quoted --BindInvoice--> invoiced --MarkPaid--> paid --Execute--> applying --> committed
--      \________________\______cancel/expire______/   \--ReleaseInvoice (invoice voided/expired, never paid)--> cancelled
--
--   * The CLIENT never reaches this module. Only cm-mechanic (export trust list in server/main.lua) drives it, and the price comes from
--     cm-tuning's own calculator (deps.mods.quote), never from the caller.
--   * Money never moves here. Payment is cm-billing's: MarkPaid only accepts an invoice that cm-billing itself reports `paid`.
--   * After payment the operation is FORWARD-ONLY (cm-billing has no generic refund): it cannot be cancelled, it does not expire, and a
--     transient failure is retried by the caller. The approved change is stored as a DIFF (absolute field values), so applying it is
--     idempotent, never downgrades unrelated fields changed meanwhile, and "already installed" is recognised as done.
CMTuning = CMTuning or {}
local Core = {}
Core.__index = Core
CMTuning.ServiceCore = Core

Core.SHOPS = { chip = true, workshop = true, livery = true }
local PRE_PAY = { created = true, quoted = true }
local LIVE = { created = true, quoted = true, invoiced = true, paid = true, applying = true }
Core.LIVE = LIVE

local REF_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

-- ------------------------------------------------------------------ pure helpers
local function deepCopy(v)
    if type(v) ~= 'table' then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deepCopy(x) end
    return o
end
Core.deepCopy = deepCopy

-- Deterministic serialization (sorted keys) for comparisons and hashes.
local function stable(v)
    local t = type(v)
    if t == 'table' then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local out = {}
        for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. '=' .. stable(v[k]) end
        return '{' .. table.concat(out, ',') .. '}'
    elseif t == 'string' then return ('%q'):format(v)
    else return tostring(v) end
end
Core.stable = stable

function Core.hash(str)
    local h = -3750763034362895579 -- FNV-1a 64-bit offset basis
    for i = 1, #str do h = (h ~ str:byte(i)) * 1099511628211 end
    return ('%016x'):format(h)
end

-- Diff between two NORMALISED mods tables (see main.lua defaultMods): only fields that the approved result changes.
function Core.DiffMods(base, approved)
    base, approved = type(base) == 'table' and base or {}, type(approved) == 'table' and approved or {}
    local d = { set = {}, slots = {} }
    for k, v in pairs(approved) do
        if k == 'mods' then
            local bm = type(base.mods) == 'table' and base.mods or {}
            for mk, mv in pairs(v) do if stable(bm[mk]) ~= stable(mv) then d.slots[tostring(mk)] = mv end end
        elseif k ~= 'extras' then
            if stable(base[k]) ~= stable(v) then d.set[k] = deepCopy(v) end
        end
    end
    return d
end

-- Applies the diff onto the CURRENT state (absolute values: idempotent, order independent, leaves every other field alone).
function Core.MergeMods(current, diff)
    local out = deepCopy(type(current) == 'table' and current or {})
    out.mods = type(out.mods) == 'table' and out.mods or {}
    if type(diff) ~= 'table' then return out end
    for k, v in pairs(diff.set or {}) do out[k] = deepCopy(v) end
    for mk, mv in pairs(diff.slots or {}) do out.mods[tostring(mk)] = mv end
    return out
end

local function isInt(n, lo, hi) return type(n) == 'number' and n == n and n % 1 == 0 and n >= lo and n <= hi end

-- ------------------------------------------------------------------ construction
-- deps: cfg { authorizationSeconds, quoteSeconds, maxAmount }, store, now, rand, encode, decode,
--       vehicles { get(vehicleId) -> { id, plate, ownerKey, mods = <raw> } | nil, casMods(vehicleId, oldRaw, newRaw) -> bool, lock(vehicleId) -> release | nil },
--       mods { default(raw) -> normalised, quote(shop, raw, caps, changes) -> approved, price, err, cleanCaps, describe(diff) -> string },
--       billing { status(invoiceRef) -> 'paid' | ... | nil }, sync(row, merged) (best effort), log(level, msg), audit(kind, detail)
function Core.New(deps)
    assert(type(deps) == 'table' and deps.store and deps.vehicles and deps.mods and deps.billing, 'cm-tuning service core needs store/vehicles/mods/billing')
    local self = setmetatable({}, Core)
    self.cfg = deps.cfg or {}
    self.store, self.vehicles, self.mods, self.billing = deps.store, deps.vehicles, deps.mods, deps.billing
    self.now = deps.now or os.time
    self.rand = deps.rand or math.random
    self.encode = deps.encode or function() return '' end
    self.decode = deps.decode or function() return nil end
    self.sync = deps.sync or function() end
    self.log = deps.log or function() end
    self.audit = deps.audit or function() end
    self.locks = {}
    return self
end

function Core:_ref()
    local s = {}
    for i = 1, 8 do local n = self.rand(1, #REF_CHARS); s[i] = REF_CHARS:sub(n, n) end
    return 'TUN-' .. table.concat(s)
end

function Core:_lock(key, fn)
    if self.locks[key] then return false, 'busy' end
    self.locks[key] = true
    local res = table.pack(pcall(fn))
    self.locks[key] = nil
    if not res[1] then self.log('error', tostring(res[2])); return false, 'internal_error' end
    return table.unpack(res, 2, res.n)
end

local function release(row) return { status = row.status, active_key = false, vehicle_key = false } end

function Core:_expired(row, now)
    return PRE_PAY[row.status] and (tonumber(row.expires_at) or 0) < now
end

function Core:_expire(row)
    local n = self.store.cas(row.reference, { 'created', 'quoted' }, { status = 'expired', active_key = false, vehicle_key = false, failure_reason = 'expired', updated_at = self.now() })
    return n == 1
end

-- ------------------------------------------------------------------ authorization
-- ctx = { workOrder, mechanicCid, customerCid, businessType, businessId, vehicleId, shop, maxAmount? }
-- cm-mechanic has ALREADY validated the work order, the mechanic's business permission, the customer, the vehicle (vehicle_id) and proximity.
function Core:Authorize(ctx)
    if type(ctx) ~= 'table' then return false, 'invalid_request' end
    local wo, mCid, cCid = ctx.workOrder, ctx.mechanicCid, ctx.customerCid
    local bType, bId = ctx.businessType, ctx.businessId
    local vehicleId = tonumber(ctx.vehicleId)
    for _, s in ipairs({ wo, mCid, cCid, bType, bId }) do
        if type(s) ~= 'string' or s == '' or #s > 48 then return false, 'invalid_request' end
    end
    if not vehicleId or not isInt(vehicleId, 1, 2 ^ 53) then return false, 'invalid_request' end
    if type(ctx.shop) ~= 'string' or not Core.SHOPS[ctx.shop] then return false, 'unsupported_operation' end
    local maxAmount = tonumber(ctx.maxAmount) or tonumber(self.cfg.maxAmount) or 50000
    if maxAmount < 1 then return false, 'invalid_request' end

    return self:_lock('wo:' .. wo, function()
        local now = self.now()
        local veh = self.vehicles.get(vehicleId)
        if not veh then return false, 'vehicle_not_found' end
        local hash = Core.hash(stable({ wo, mCid, cCid, bType, bId, vehicleId, ctx.shop, maxAmount }))
        local existing = self.store.activeByWork(wo)
        if existing then
            if self:_expired(existing, now) then self:_expire(existing); existing = self.store.get(existing.reference) end
        end
        if existing and LIVE[existing.status] then
            if PRE_PAY[existing.status] then
                if existing.request_hash == hash and existing.status == 'created' then
                    return true, { reference = existing.reference, shop = existing.shop, expiresAt = existing.expires_at, replayed = true }
                end
                self.store.cas(existing.reference, { 'created', 'quoted' }, { status = 'cancelled', active_key = false, vehicle_key = false, failure_reason = 'superseded', updated_at = now })
            else
                return false, 'authorization_active'
            end
        end
        local row = {
            reference = self:_ref(), work_order_ref = wo, active_key = wo, vehicle_key = tostring(vehicleId), mechanic_cid = mCid, customer_cid = cCid,
            business_type = bType, business_id = bId, vehicle_id = vehicleId, shop = ctx.shop, owner_snapshot = veh.ownerKey, revision = 0,
            max_amount = math.floor(maxAmount), request_hash = hash, status = 'created', attempts = 0, created_at = now, updated_at = now,
            expires_at = now + (tonumber(self.cfg.authorizationSeconds) or 900),
        }
        local id, why = self.store.insert(row)
        if not id and why == 'duplicate_vehicle' then
            local other = self.store.activeByVehicle(vehicleId)
            if other and self:_expired(other, now) and self:_expire(other) then id, why = self.store.insert(row) end
        end
        if not id then return false, why == 'duplicate_vehicle' and 'vehicle_busy' or (why == 'duplicate_active' and 'authorization_active' or 'service_unavailable') end
        self.audit('tuning_service_authorized', { reference = row.reference, workOrder = wo, vehicleId = vehicleId, shop = ctx.shop })
        return true, { reference = row.reference, shop = row.shop, expiresAt = row.expires_at }
    end)
end

function Core:Get(ref)
    if type(ref) ~= 'string' or ref == '' or #ref > 24 then return nil end
    return self.store.get(ref)
end

-- ------------------------------------------------------------------ quote (cm-tuning is the price owner)
function Core:Quote(ref, caps, changes)
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    return self:_lock('ref:' .. row.reference, function()
        row = self.store.get(row.reference)
        if not PRE_PAY[row.status] then return false, 'invalid_state' end
        local now = self.now()
        if self:_expired(row, now) then self:_expire(row); return false, 'expired' end
        local veh = self.vehicles.get(row.vehicle_id)
        if not veh then return false, 'vehicle_not_found' end
        if veh.ownerKey ~= row.owner_snapshot then
            self.store.cas(row.reference, { 'created', 'quoted' }, { status = 'cancelled', active_key = false, vehicle_key = false, failure_reason = 'ownership_changed', updated_at = now })
            return false, 'ownership_changed'
        end
        local approved, price, err, cleanCaps = self.mods.quote(row.shop, veh.mods, caps, changes)
        if not approved then return false, err or 'invalid_operation' end
        if price > tonumber(row.max_amount) then return false, 'amount_over_limit' end
        if price < 1 then return false, 'nothing_billable' end
        local base = self.mods.default(veh.mods)
        local diff = Core.DiffMods(base, approved)
        if next(diff.set) == nil and next(diff.slots) == nil then return false, 'no_changes' end
        local requestJson = self.encode(changes)
        if #requestJson > 6000 then return false, 'too_large' end
        local revision = (tonumber(row.revision) or 0) + 1
        local n = self.store.cas(row.reference, { 'created', 'quoted' }, {
            status = 'quoted', amount = math.floor(price), revision = revision, request_json = requestJson, caps_json = self.encode(cleanCaps or {}),
            changes_json = self.encode(diff), base_hash = Core.hash(stable(base)), description = (self.mods.describe and self.mods.describe(diff) or ''):sub(1, 160),
            expires_at = now + (tonumber(self.cfg.quoteSeconds) or 420), updated_at = now })
        if n ~= 1 then return false, 'invalid_state' end
        self.audit('tuning_service_quoted', { reference = row.reference, amount = math.floor(price), revision = revision })
        return true, { reference = row.reference, amount = math.floor(price), revision = revision, shop = row.shop }
    end)
end

-- What cm-mechanic needs to bind its work order to this quote.
function Core:GetQuote(ref)
    local row = self:Get(ref)
    if not row or row.status ~= 'quoted' then return false, row and 'invalid_state' or 'not_found' end
    return true, {
        reference = row.reference, workOrder = row.work_order_ref, mechanicCid = row.mechanic_cid, customerCid = row.customer_cid,
        businessType = row.business_type, businessId = row.business_id, vehicleId = tonumber(row.vehicle_id), shop = row.shop,
        amount = tonumber(row.amount), revision = tonumber(row.revision), description = row.description or '', expiresAt = tonumber(row.expires_at),
    }
end

-- Before the customer's approval becomes an invoice: the quote must still describe the vehicle exactly as it was priced.
function Core:Revalidate(ref)
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    if row.status ~= 'quoted' then return false, 'invalid_state' end
    local now = self.now()
    if self:_expired(row, now) then self:_expire(row); return false, 'expired' end
    local veh = self.vehicles.get(row.vehicle_id)
    if not veh then return false, 'vehicle_not_found' end
    if veh.ownerKey ~= row.owner_snapshot then return false, 'ownership_changed' end
    if Core.hash(stable(self.mods.default(veh.mods))) ~= row.base_hash then return false, 'vehicle_changed' end
    local changes, caps = self.decode(row.request_json), self.decode(row.caps_json)
    local approved, price = self.mods.quote(row.shop, veh.mods, caps, changes)
    if not approved then return false, 'vehicle_changed' end
    if price > tonumber(row.amount) then return false, 'quote_changed' end
    return true, { amount = tonumber(row.amount), revision = tonumber(row.revision) }
end

-- ------------------------------------------------------------------ invoice / payment
function Core:BindInvoice(ref, invoiceRef)
    if type(invoiceRef) ~= 'string' or invoiceRef == '' or #invoiceRef > 48 then return false, 'invalid_request' end
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    return self:_lock('ref:' .. row.reference, function()
        row = self.store.get(row.reference)
        if row.invoice_ref and row.invoice_ref ~= '' then
            if row.invoice_ref == invoiceRef and (row.status == 'invoiced' or row.status == 'paid' or row.status == 'applying' or row.status == 'committed') then return true, { replayed = true } end
            return false, 'invoice_conflict'
        end
        if row.status ~= 'quoted' then return false, 'invalid_state' end
        local n = self.store.cas(row.reference, { 'quoted' }, { status = 'invoiced', invoice_ref = invoiceRef, updated_at = self.now() })
        if n ~= 1 then return false, 'invalid_state' end
        return true
    end)
end

-- The invoice was voided/expired without payment: the quote is dead. (Forward-only applies after payment: never reachable then.)
function Core:ReleaseInvoice(ref)
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    return self:_lock('ref:' .. row.reference, function()
        row = self.store.get(row.reference)
        if row.status == 'cancelled' or row.status == 'expired' then return true, { replayed = true } end
        if row.status == 'paid' or row.status == 'applying' or row.status == 'committed' then return false, 'paid_forward_only' end
        local n = self.store.cas(row.reference, { 'created', 'quoted', 'invoiced' }, { status = 'cancelled', active_key = false, vehicle_key = false, failure_reason = 'invoice_released', updated_at = self.now() })
        return n == 1, n == 1 and nil or 'invalid_state'
    end)
end

function Core:MarkPaid(ref, invoiceRef)
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    return self:_lock('ref:' .. row.reference, function()
        row = self.store.get(row.reference)
        if row.status == 'paid' or row.status == 'applying' or row.status == 'committed' then
            if row.invoice_ref == invoiceRef then return true, { replayed = true } end
            return false, 'invoice_conflict'
        end
        if row.status ~= 'invoiced' then return false, 'invalid_state' end
        if row.invoice_ref ~= invoiceRef then return false, 'invoice_conflict' end
        local st = self.billing.status(invoiceRef)
        if st == nil then return false, 'billing_unavailable' end     -- transient: the caller retries
        if st ~= 'paid' then return false, 'not_paid' end
        local now = self.now()
        local n = self.store.cas(row.reference, { 'invoiced' }, { status = 'paid', paid_at = now, expires_at = now, updated_at = now })
        if n ~= 1 then return false, 'invalid_state' end
        self.audit('tuning_service_paid', { reference = row.reference, invoice = invoiceRef, amount = row.amount })
        return true
    end)
end

-- ------------------------------------------------------------------ apply (forward-only, idempotent)
function Core:Execute(ref)
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    return self:_lock('ref:' .. row.reference, function()
        row = self.store.get(row.reference)
        if row.status == 'committed' then return true, { replayed = true } end
        if row.status ~= 'paid' and row.status ~= 'applying' then return false, 'not_paid' end
        local releaseVehicle = self.vehicles.lock and self.vehicles.lock(row.vehicle_id)
        if self.vehicles.lock and not releaseVehicle then return false, 'busy' end     -- a player session holds this vehicle: transient
        local ok, a, b = pcall(function() return self:_apply(row) end)
        if releaseVehicle then releaseVehicle() end
        if not ok then self.log('error', tostring(a)); return false, 'internal_error' end
        return a, b
    end)
end

function Core:_apply(row)
    local now = self.now()
    local n = self.store.cas(row.reference, { 'paid', 'applying' }, { status = 'applying', attempts = (tonumber(row.attempts) or 0) + 1, updated_at = now })
    if n ~= 1 then
        local cur = self.store.get(row.reference)
        if cur and cur.status == 'committed' then return true, { replayed = true } end
        return false, 'invalid_state'
    end
    local diff = self.decode(row.changes_json)
    if type(diff) ~= 'table' then return false, 'corrupt_operation' end
    local merged, installed
    for _ = 1, 3 do
        local veh = self.vehicles.get(row.vehicle_id)
        if not veh then
            self.store.cas(row.reference, { 'applying' }, { failure_reason = 'vehicle_unavailable', updated_at = self.now() })
            return false, 'vehicle_unavailable'
        end
        local current = self.mods.default(veh.mods)
        merged = Core.MergeMods(current, diff)
        if stable(merged) == stable(current) then installed = 'already'; break end
        if self.vehicles.casMods(row.vehicle_id, veh.mods, self.encode(merged)) then installed = 'written'; break end
    end
    if not installed then
        self.store.cas(row.reference, { 'applying' }, { failure_reason = 'conflict_retry', updated_at = self.now() })
        return false, 'conflict_retry'
    end
    local done = self.now()
    local c = self.store.cas(row.reference, { 'applying' }, { status = 'committed', applied_at = done, active_key = false, vehicle_key = false, failure_reason = false, updated_at = done })
    if c ~= 1 then
        local cur = self.store.get(row.reference)
        if cur and cur.status == 'committed' then return true, { replayed = true } end
        return false, 'invalid_state'
    end
    pcall(self.sync, row, merged)
    self.audit('tuning_service_committed', { reference = row.reference, vehicleId = row.vehicle_id, amount = row.amount, installed = installed })
    return true, { replayed = false, installed = installed }
end

-- ------------------------------------------------------------------ status / cancel / expiry
function Core:Status(ref)
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    return true, {
        reference = row.reference, status = row.status, workOrder = row.work_order_ref, vehicleId = tonumber(row.vehicle_id), amount = tonumber(row.amount),
        invoiceRef = row.invoice_ref, revision = tonumber(row.revision), attempts = tonumber(row.attempts), failure = row.failure_reason,
        paidAt = tonumber(row.paid_at), appliedAt = tonumber(row.applied_at),
    }
end

function Core:Cancel(ref, reason)
    local row = self:Get(ref)
    if not row then return false, 'not_found' end
    return self:_lock('ref:' .. row.reference, function()
        row = self.store.get(row.reference)
        if row.status == 'cancelled' or row.status == 'expired' then return true, { replayed = true } end
        if row.status == 'committed' then return false, 'already_committed' end
        if row.status == 'paid' or row.status == 'applying' then return false, 'paid_forward_only' end
        if row.status == 'invoiced' then return false, 'invoice_pending' end   -- the invoice owner must void it first (ReleaseInvoice)
        local n = self.store.cas(row.reference, { 'created', 'quoted' }, { status = 'cancelled', active_key = false, vehicle_key = false,
            failure_reason = type(reason) == 'string' and reason:sub(1, 40) or 'cancelled', updated_at = self.now() })
        return n == 1, n == 1 and nil or 'invalid_state'
    end)
end

-- Unpaid authorizations/quotes lapse; invoiced/paid/applying never expire here (the invoice owner and forward recovery own them).
function Core:ExpireSweep()
    local count = 0
    for _, row in ipairs(self.store.listExpirable(self.now(), 50) or {}) do
        if self:_expire(row) then count = count + 1 end
    end
    return count
end
