-- Vehicle legal-state core (registration + insurance).
--
-- Pure logic: no FiveM natives, no SQL. Everything environmental (database,
-- money, clock, randomness, audit sink) is injected through `deps`, so the
-- same code runs in the server (server/legal.lua) and in the deterministic
-- local self-test (tests/legal_selftest.lua).
--
-- Identity model
--   vehicle_id      authoritative persistent identity (cm_owned_vehicles.id)
--   plate           internal lookup key used by the rest of the framework
--   license_number  public legal registration ("REG-123456"); never an identity
--
-- Legal state lives on the cm_owned_vehicles row, so a state sale / permanent
-- deletion of the row removes the legal state with it (no orphans).
CMVehicles = CMVehicles or {}

local Core = {}
Core.__index = Core

Core.REG = { UNREGISTERED = 'UNREGISTERED', ACTIVE = 'ACTIVE', EXPIRED = 'EXPIRED', REVOKED = 'REVOKED', EXEMPT = 'EXEMPT' }
Core.INS = { NONE = 'NONE', ACTIVE = 'ACTIVE', EXPIRED = 'EXPIRED', EXEMPT = 'EXEMPT' }

local DAY = 86400

local function num(v, default)
    v = tonumber(v)
    if v == nil then return default end
    return v
end

local function clamp(v, lo, hi)
    if lo and v < lo then v = lo end
    if hi and hi > 0 and v > hi then v = hi end
    return v
end

local function str(v) return v ~= nil and tostring(v) or nil end

function Core.New(deps)
    assert(type(deps) == 'table' and type(deps.cfg) == 'table' and type(deps.store) == 'table', 'legal core needs cfg and store')
    local self = setmetatable({}, Core)
    self.cfg = deps.cfg
    self.store = deps.store
    self.money = deps.money
    self.now = deps.now or os.time
    self.rand = deps.rand or math.random
    self.onApplied = deps.onApplied
    self.locks = {}
    self.replay = {}
    self.replayCount = 0
    return self
end

-- ---------------------------------------------------------------- eligibility

function Core:isEligible(row)
    if type(row) ~= 'table' then return false end
    local ownerType = tostring(row.owner_type or 'character')
    return (self.cfg.EligibleOwnerTypes or {})[ownerType] == true
end

local function ownerKey(row)
    return str(row.owner_character_id)
end

-- ------------------------------------------------------------------ valuation

-- Authoritative value: persisted state_value, then trusted metadata, then the
-- catalog price. Never client-supplied. A floor protects against zero-price
-- catalog rows ever producing $0 registration / insurance.
function Core:valuation(row)
    local meta = type(row.metadata) == 'table' and row.metadata or {}
    local value = 0
    for _, candidate in ipairs({ row.state_value, meta.stateValue, meta.state_value, meta.storePrice,
        meta.store_price, meta.purchasePrice, meta.purchase_price, meta.price }) do
        local n = tonumber(candidate)
        if n and n > 0 then value = math.floor(n); break end
    end
    if value <= 0 and self.store.catalogPrice then
        local model = tostring(row.model or ''):lower()
        local replacement = tostring(meta.replacementType or '')
        if (replacement == 'temporary' or replacement == 'restoring') and tostring(meta.replacementOriginalModel or '') ~= '' then
            model = tostring(meta.replacementOriginalModel):lower()
        end
        local price = tonumber(self.store.catalogPrice(model))
        if price and price > 0 then value = math.floor(price) end
    end
    local floor = math.floor(num(self.cfg.MinimumValuation, 150000))
    return math.max(value, floor), value
end

function Core:registrationFee(value)
    local r = self.cfg.Registration
    return math.floor(clamp(num(r.baseFee, 0) + value * num(r.valueRate, 0), num(r.baseFee, 0), num(r.maxFee, 0)))
end

function Core:insurancePremium(value)
    local i = self.cfg.Insurance
    return math.floor(clamp(value * num(i.rate, 0), num(i.minimum, 0), num(i.maximum, 0)))
end

-- --------------------------------------------------------------------- status

local function owns(row, cid)
    return cid ~= nil and tostring(cid) ~= '' and tostring(row.owner_type or 'character') == 'character'
        and ownerKey(row) == tostring(cid)
end

function Core:registrationStatus(row, now)
    if not self:isEligible(row) then return Core.REG.EXEMPT end
    if not row.license_number or tostring(row.license_number) == '' then return Core.REG.UNREGISTERED end
    if tonumber(row.registration_revoked_at) then return Core.REG.REVOKED end
    local exp = tonumber(row.registration_expires_at)
    if exp == nil then return Core.REG.ACTIVE end -- legacy permanent registration
    return exp > now and Core.REG.ACTIVE or Core.REG.EXPIRED
end

-- A policy belongs to the owner who bought it. If the row's owner changed for
-- any reason (even through a path that never called the transfer hook) the
-- policy no longer matches and reads as NONE.
function Core:insuranceStatus(row, now)
    if not self:isEligible(row) then return Core.INS.EXEMPT end
    local exp = tonumber(row.insurance_expires_at)
    if not exp or not row.insurance_owner_id or tostring(row.insurance_owner_id) ~= ownerKey(row) then
        return Core.INS.NONE
    end
    return exp > now and Core.INS.ACTIVE or Core.INS.EXPIRED
end

function Core:IsInsured(row, now)
    return self:insuranceStatus(row, now or self.now()) == Core.INS.ACTIVE
end

-- Safe public shape. Owner data only when explicitly requested by a trusted
-- caller (the export layer decides who is trusted).
function Core:legalStatus(row, opts)
    opts = opts or {}
    local now = self.now()
    local insExp = tonumber(row.insurance_expires_at)
    local insStatus = self:insuranceStatus(row, now)
    local out = {
        vehicleId = tonumber(row.id),
        registrationNumber = row.license_number and tostring(row.license_number) or nil,
        registrationStatus = self:registrationStatus(row, now),
        registrationExpiresAt = tonumber(row.registration_expires_at),
        insuranceStatus = insStatus,
        insuranceExpiresAt = (insStatus == Core.INS.ACTIVE or insStatus == Core.INS.EXPIRED) and insExp or nil,
        exempt = not self:isEligible(row),
    }
    if opts.includeOwner then
        out.ownerType = tostring(row.owner_type or 'character')
        out.ownerCharacterId = ownerKey(row)
        out.ownerName = row.owner_name and tostring(row.owner_name) or nil
        out.plate = row.plate and tostring(row.plate) or nil
    end
    return out
end

function Core:GetLegalStatus(vehicleId, opts)
    local row = self.store.getById(tonumber(vehicleId))
    if not row then return nil end
    return self:legalStatus(row, opts)
end

function Core:LookupByRegistration(number, opts)
    local row = self.store.getByLicense(number)
    if not row then return nil end
    return self:legalStatus(row, opts)
end

-- ---------------------------------------------------------------------- quote

-- Per-action availability for one owned row. Pure: no side effects.
function Core:quote(row)
    local now = self.now()
    local value, rawValue = self:valuation(row)
    local reg, ins = self.cfg.Registration, self.cfg.Insurance
    local regStatus, insStatus = self:registrationStatus(row, now), self:insuranceStatus(row, now)
    local q = {
        vehicleId = tonumber(row.id), value = value, valueFloored = rawValue < value,
        registrationStatus = regStatus, insuranceStatus = insStatus,
        registrationNumber = row.license_number and tostring(row.license_number) or nil,
        registrationExpiresAt = tonumber(row.registration_expires_at),
        insuranceExpiresAt = tonumber(row.insurance_expires_at),
        registration = { price = self:registrationFee(value), available = false, action = nil, reason = nil },
        insurance = { price = self:insurancePremium(value), available = false, action = nil, reason = nil },
    }
    if regStatus == Core.REG.EXEMPT then
        q.registration.reason, q.insurance.reason = 'exempt', 'exempt'
        q.registration.price, q.insurance.price = 0, 0
        return q
    end

    -- registration
    local regExp = tonumber(row.registration_expires_at)
    if regStatus == Core.REG.UNREGISTERED then
        q.registration.available, q.registration.action = true, 'register'
    elseif regStatus == Core.REG.REVOKED then
        q.registration.reason = 'registration_revoked'
    elseif regExp == nil then
        q.registration.reason = 'legacy_permanent'
    elseif regStatus == Core.REG.EXPIRED or regExp - now <= num(reg.renewWindowDays, 7) * DAY then
        q.registration.available, q.registration.action = true, 'renew'
    else
        q.registration.reason = 'not_due'
    end

    -- insurance (requires a valid registration: an unregistered / revoked
    -- vehicle has no legal identity to insure)
    local insExp = tonumber(row.insurance_expires_at)
    if regStatus == Core.REG.UNREGISTERED or regStatus == Core.REG.REVOKED then
        q.insurance.reason = 'registration_required'
    elseif insStatus == Core.INS.ACTIVE and insExp - now > num(ins.renewWindowDays, 3) * DAY then
        q.insurance.reason = 'not_due'
    else
        q.insurance.available = true
        q.insurance.action = (insExp and tostring(row.insurance_owner_id) == ownerKey(row)) and 'renew' or 'buy'
    end
    return q
end

-- -------------------------------------------------------------------- helpers

function Core:_event(event, row, actorCid, source, amount, details)
    if not self.store.insertEvent then return end
    pcall(self.store.insertEvent, {
        vehicleId = tonumber(row.id), event = event, actorCid = actorCid and tostring(actorCid) or nil,
        source = source, registration = row.license_number and tostring(row.license_number) or nil,
        amount = amount, details = details,
    })
end

-- Returns true, <fn results...> when fn ran; false, 'busy' | 'internal_error'
-- otherwise. The lock is always released, even when fn raises.
function Core:_withLock(vehicleId, fn)
    if self.locks[vehicleId] then return false, 'busy' end
    self.locks[vehicleId] = true
    local packed = table.pack(pcall(fn))
    self.locks[vehicleId] = nil
    if not packed[1] then return false, 'internal_error', tostring(packed[2]) end
    return true, table.unpack(packed, 2, packed.n)
end

function Core:_remember(key, result)
    local now = self.now()
    if self.replayCount > 256 then
        for k, v in pairs(self.replay) do
            if now - v.at > 600 then self.replay[k] = nil; self.replayCount = self.replayCount - 1 end
        end
    end
    if not self.replay[key] then self.replayCount = self.replayCount + 1 end
    self.replay[key] = { at = now, result = result }
end

function Core:_refund(src, cid, vehicleId, amount, reason)
    local refunded = self.money and self.money.add and self.money.add(src, amount, reason, self.cfg.Account) == true
    if not refunded and self.store.queueRefund then
        pcall(self.store.queueRefund, { vehicleId = vehicleId, characterId = cid, amount = amount,
            account = self.cfg.Account, reason = reason })
    end
    return refunded
end

-- Unique registration number. The UNIQUE index is the real guard: the claim is
-- one conditional UPDATE that sets the number AND its expiry together (so a
-- failure can never leave a numbered registration without an expiry) and fails
-- on duplicate, so a collision just retries. `guard` pins the validated owner.
function Core:_claimNumber(vehicleId, expiresAt, guard)
    local prefix = tostring((self.cfg.Registration or {}).numberPrefix or 'REG-')
    for _ = 1, math.floor(num((self.cfg.Registration or {}).claimAttempts, 8)) do
        local candidate = ('%s%06d'):format(prefix, self.rand(100000, 999999))
        if self.store.claimLicense(vehicleId, candidate, expiresAt, guard) == true then return candidate end
    end
    return nil
end

-- ------------------------------------------------------- player self-service

-- service: 'registration' | 'insurance'.  actor = { src, cid }.
-- opts.requestId makes retries replay-safe; opts.expectedPrice (from the
-- client's confirmation dialog) is only a confirmation check: the charged
-- price is always the freshly computed server quote.
function Core:Purchase(actor, vehicleId, service, opts)
    opts = opts or {}
    vehicleId = tonumber(vehicleId)
    if type(actor) ~= 'table' or not actor.cid or not vehicleId then
        return { ok = false, error = 'invalid_request', message = 'Invalid request.' }
    end
    if service ~= 'registration' and service ~= 'insurance' then
        return { ok = false, error = 'invalid_service', message = 'Unknown service.' }
    end
    if self.cfg.Enabled == false then return { ok = false, error = 'disabled', message = 'Vehicle services are unavailable.' } end

    local requestId = opts.requestId and tostring(opts.requestId):sub(1, 64) or nil
    local replayKey = requestId and ('%s:%s:%s:%s'):format(actor.cid, vehicleId, service, requestId) or nil
    if replayKey and self.replay[replayKey] then
        local prior = self.replay[replayKey].result
        return { ok = prior.ok, error = prior.error, message = prior.message, replayed = true, charged = 0,
            registrationNumber = prior.registrationNumber, expiresAt = prior.expiresAt }
    end

    local ran, result, detail = self:_withLock(vehicleId, function()
        -- Always re-read under the lock: a concurrent call or ownership change
        -- may have settled while this request waited.
        local row = self.store.getById(vehicleId)
        if not row then return { ok = false, error = 'vehicle_not_found', message = 'Vehicle not found.' } end
        if not owns(row, actor.cid) then
            return { ok = false, error = 'not_owner', message = 'You do not own this vehicle.' }
        end
        if not self:isEligible(row) then
            return { ok = false, error = 'exempt', message = 'This vehicle is not eligible for personal registration or insurance.' }
        end
        if row.sale_pending_token and tostring(row.sale_pending_token) ~= '' then
            return { ok = false, error = 'vehicle_busy', message = 'This vehicle is being sold.' }
        end

        local q = self:quote(row)
        local entry = q[service]
        if not entry.available then
            return { ok = false, error = entry.reason or 'unavailable', message = 'This service is not available for this vehicle right now.', quote = q }
        end
        local price = entry.price
        if opts.expectedPrice ~= nil and math.floor(num(opts.expectedPrice, -1)) ~= price then
            return { ok = false, error = 'price_changed', message = 'The price changed. Please review and confirm again.', quote = q }
        end

        local now = self.now()
        local fields, event, regNumber
        if service == 'registration' then
            regNumber = row.license_number and tostring(row.license_number) or nil
            local base = now
            local cur = tonumber(row.registration_expires_at)
            if entry.action == 'renew' and cur and cur > now then base = cur end
            fields = { registration_expires_at = base + math.floor(num(self.cfg.Registration.durationDays, 21) * DAY) }
            event = entry.action == 'register' and 'registration_issued' or 'registration_renewed'
        else
            local base = now
            local cur = tonumber(row.insurance_expires_at)
            if entry.action == 'renew' and cur and cur > now and tostring(row.insurance_owner_id) == ownerKey(row) then base = cur end
            fields = { insurance_expires_at = base + math.floor(num(self.cfg.Insurance.durationDays, 14) * DAY),
                insurance_owner_id = ownerKey(row) }
            event = entry.action == 'renew' and 'insurance_renewed' or 'insurance_purchased'
        end

        -- 1. charge exactly once
        if price > 0 then
            if not (self.money and self.money.remove) then
                return { ok = false, error = 'payment_unavailable', message = 'Payment is unavailable.' }
            end
            if self.money.remove(actor.src, price, 'vehicle-' .. service .. '-' .. entry.action, self.cfg.Account) ~= true then
                return { ok = false, error = 'insufficient_funds', message = ('You need $%d.'):format(price), price = price }
            end
        end

        -- 2. number allocation (registration only), 3. guarded state change
        local applied = false
        local guard = { owner_character_id = ownerKey(row) }
        if service == 'registration' and entry.action == 'register' then
            regNumber = self:_claimNumber(vehicleId, fields.registration_expires_at, guard)
            applied = regNumber ~= nil
        else
            applied = self.store.applyLegal(vehicleId, guard, fields) == 1
        end
        if not applied then
            if price > 0 then
                local refunded = self:_refund(actor.src, actor.cid, vehicleId, price, 'vehicle-legal-refund')
                self:_event(refunded and 'charge_refunded' or 'refund_queued', row, actor.cid, actor.source or 'player', price, { service = service })
            end
            return { ok = false, error = 'apply_failed', message = 'The change could not be applied. You were not charged.' }
        end

        row.license_number = regNumber or row.license_number
        for k, v in pairs(fields) do row[k] = v end
        self:_event(event, row, actor.cid, actor.source or 'player', price, { service = service, expiresAt = fields.registration_expires_at or fields.insurance_expires_at })
        if self.onApplied then pcall(self.onApplied, row, service) end
        return { ok = true, service = service, action = entry.action, charged = price, registrationNumber = regNumber,
            expiresAt = fields.registration_expires_at or fields.insurance_expires_at }
    end)

    if not ran then
        if result == 'busy' then return { ok = false, error = 'busy', message = 'This vehicle is already being processed.' } end
        return { ok = false, error = 'internal_error', message = 'The request could not be completed.', detail = detail }
    end
    if replayKey and (result.ok or result.error == 'insufficient_funds' or result.error == 'not_due') then
        self:_remember(replayKey, result)
    end
    return result
end

-- -------------------------------------------------- trusted (law / ownership)

-- Free, officer-issued registration. Existing workflow preserved: no fee, any
-- existing row, number allocated once. Eligible vehicles also get an expiry so
-- they follow the same lifecycle as self-service registrations.
function Core:IssueRegistration(vehicleId, actorCid, source)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'Invalid vehicle.' end
    local ran, ok, msg, number = self:_withLock(vehicleId, function()
        local row = self.store.getById(vehicleId)
        if not row then return false, 'That vehicle does not exist.' end
        if row.license_number and tostring(row.license_number) ~= '' then return false, 'That vehicle is already registered.' end
        local exp = self:isEligible(row) and (self.now() + math.floor(num(self.cfg.Registration.durationDays, 21) * DAY)) or nil
        local number = self:_claimNumber(vehicleId, exp, nil)
        if not number then return false, 'Could not issue a registration number. Try again.' end
        row.license_number, row.registration_expires_at = number, exp
        self:_event('registration_issued', row, actorCid, source or 'law', 0, { free = true })
        if self.onApplied then pcall(self.onApplied, row, 'registration') end
        return true, ('Registration issued: %s'):format(number), number
    end)
    if not ran then return false, ok == 'busy' and 'That vehicle is being processed.' or 'Could not issue a registration number. Try again.' end
    return ok, msg, number
end

function Core:RevokeRegistration(vehicleId, actorCid, reason, source)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle' end
    local ran, r = self:_withLock(vehicleId, function()
        local row = self.store.getById(vehicleId)
        if not row then return { ok = false, error = 'vehicle_not_found' } end
        if not row.license_number or tostring(row.license_number) == '' then return { ok = false, error = 'not_registered' } end
        if tonumber(row.registration_revoked_at) then return { ok = false, error = 'already_revoked' } end
        if self.store.applyLegal(vehicleId, {}, { registration_revoked_at = self.now() }) ~= 1 then
            return { ok = false, error = 'apply_failed' }
        end
        row.registration_revoked_at = self.now()
        self:_event('registration_revoked', row, actorCid, source or 'law', 0, { reason = reason and tostring(reason):sub(1, 200) or nil })
        return { ok = true }
    end)
    if not ran then return false, r end
    return r.ok == true, r.error
end

-- Counterpart to revoke: without it a revocation would be a dead end. The
-- registration number is kept, and an expired registration stays EXPIRED.
function Core:ReinstateRegistration(vehicleId, actorCid, reason, source)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle' end
    local ran, r = self:_withLock(vehicleId, function()
        local row = self.store.getById(vehicleId)
        if not row then return { ok = false, error = 'vehicle_not_found' } end
        if not tonumber(row.registration_revoked_at) then return { ok = false, error = 'not_revoked' } end
        if self.store.applyLegal(vehicleId, {}, { registration_revoked_at = false }) ~= 1 then
            return { ok = false, error = 'apply_failed' }
        end
        row.registration_revoked_at = nil
        self:_event('registration_reinstated', row, actorCid, source or 'law', 0, { reason = reason and tostring(reason):sub(1, 200) or nil })
        return { ok = true }
    end)
    if not ran then return false, r end
    return r.ok == true, r.error
end

-- Ownership changed: public registration stays with the vehicle, insurance does
-- not follow the vehicle to a new owner.
function Core:OnOwnershipChanged(vehicleId, reason, source)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle' end
    local ran, r = self:_withLock(vehicleId, function()
        local row = self.store.getById(vehicleId)
        if not row then return { ok = false, error = 'vehicle_not_found' } end
        if not row.insurance_expires_at and not row.insurance_owner_id then return { ok = true, changed = false } end
        if self.store.applyLegal(vehicleId, {}, { insurance_expires_at = false, insurance_owner_id = false }) ~= 1 then
            return { ok = false, error = 'apply_failed' }
        end
        self:_event('insurance_invalidated', row, nil, source or 'ownership', 0, { reason = reason and tostring(reason):sub(1, 120) or 'ownership_change' })
        return { ok = true, changed = true }
    end)
    if not ran then return false, r end
    return r.ok == true, r.error, r.changed
end

CMVehicles.LegalCore = Core
return Core
