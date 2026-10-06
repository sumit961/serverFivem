-- cm-contracts broker core. Pure logic: no FiveM natives, no SQL, no money/items/XP.
-- Everything environmental (store, clock, cross-resource calls) is injected, so the
-- same code runs in the server (server/main.lua) and the local self-test.
--
-- The broker owns ONLY: publication, provider handoff, availability, claim/lease,
-- state transitions, fallback trigger, audit and recovery. The SOURCE resource owns
-- the request/order, payment, stock and final service application; the PROVIDER job
-- owns gameplay and rewards.
--
-- States:
--   available -> claimed -> active -> completing -> completed(player)
--   claimed|active -> available            (release / lease expiry / provider failure)
--   available|claimed|active -> fallback -> completed(fallback)   (deadline; source applies it)
--   available|claimed|active -> cancelled  (source cancel / admin)
--   fallback|completing -> cancelled       (source reports terminal)
CMContracts = CMContracts or {}

local Core = {}
Core.__index = Core

local DAY_REF_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local OPEN = { 'available', 'claimed', 'active' }
local WORKED = { claimed = true, active = true }
local TERMINAL = { completed = true, cancelled = true, failed = true }

local function num(v, d) v = tonumber(v); if v == nil then return d end; return v end
local function isRef(v, max) return type(v) == 'string' and #v >= 1 and #v <= (max or 64) and v:match('^[%w_%-:%.]+$') ~= nil end
local function text(v, max) if v == nil then return nil end; if type(v) ~= 'string' then return false end
    v = v:gsub('[%c]', ' '); if #v > max then return false end; return v end

function Core.New(deps)
    assert(type(deps) == 'table' and deps.cfg and deps.store, 'cm-contracts core needs cfg and store')
    local self = setmetatable({}, Core)
    self.cfg, self.store = deps.cfg, deps.store
    self.now = deps.now or os.time
    self.call = deps.call or function() return false, 'no_call' end -- (resource, export, ...) -> ok, r1, r2
    self.encode = deps.encode or function(t) return tostring(#tostring(t)) end
    self.rand = deps.rand or math.random
    self.providers = {} -- providerType -> definition (runtime, re-registered by the provider on start)
    return self
end

-- ------------------------------------------------------------------ helpers

function Core:typeCfg(t) return (self.cfg.Types or {})[t] end

function Core:_ref()
    local s = {}
    for i = 1, 10 do local n = self.rand(1, #DAY_REF_CHARS); s[i] = DAY_REF_CHARS:sub(n, n) end
    return 'CT-' .. table.concat(s)
end

function Core:_event(c, kind, actor, detail, journalKey)
    return self.store.insertEvent(c.id, kind, actor, detail, journalKey)
end

-- Safe provider-facing view: no source reference, no owner identity, no money.
function Core:view(c, forCid)
    local now = self.now()
    return {
        reference = c.reference, contractType = c.contract_type, providerType = c.provider_type, status = c.status,
        title = c.title, description = c.description, pickupHint = c.pickup_hint, destinationHint = c.destination_hint,
        cargoClass = c.cargo_class, urgency = c.urgency, region = c.region, metadata = c.metadata or {},
        fallbackInSeconds = c.fallback_at and math.max(0, c.fallback_at - now) or nil,
        claimExpiresAt = c.claim_expires_at, claimedByYou = forCid ~= nil and c.claimed_character_id == tostring(forCid) or nil,
    }
end

function Core:_providerFor(invoker, providerType)
    local def = self.providers[providerType]
    if not def or def.resource ~= invoker then return nil end
    return def
end

-- Best-effort notices; a failing/absent receiver never changes contract state.
function Core:_notifyProvider(c, event, reason)
    local def = self.providers[c.provider_type]
    if def and def.eventExport and c.claimed_character_id then
        self.call(def.resource, def.eventExport, c.reference, c.claimed_character_id, event, reason)
    end
end

function Core:_notifySource(c, event)
    local src = (self.cfg.Sources or {})[c.source_resource]
    if src and src.eventExport then
        self.call(c.source_resource, src.eventExport, { event = event, sourceReference = c.source_reference, contractType = c.contract_type, reference = c.reference })
    end
end

local CLEAR_CLAIM = { claimed_character_id = false, claimed_at = false, claim_expires_at = false, active_at = false, provider_ref = false }
local function release(patch) for k, v in pairs(CLEAR_CLAIM) do patch[k] = v end; return patch end

-- ----------------------------------------------------------------- providers

-- Provider resources register themselves (server-side only, never a client event).
function Core:RegisterProvider(invoker, providerType, def)
    local allow = (self.cfg.Providers or {})[invoker]
    if not allow or not (allow.providerTypes or {})[providerType] then return false, 'untrusted_provider' end
    if type(def) ~= 'table' then return false, 'invalid_definition' end
    local types = {}
    for _, t in ipairs(def.types or {}) do
        local tc = self:typeCfg(t)
        if not tc or tc.providerType ~= providerType then return false, 'unsupported_type' end
        types[t] = true
    end
    if next(types) == nil then return false, 'unsupported_type' end
    local policy = def.disconnectPolicy == 'release' and 'release' or 'grace'
    self.providers[providerType] = {
        resource = invoker, types = types, leaseSeconds = math.floor(num(def.leaseSeconds, 0)),
        disconnectPolicy = policy, graceSeconds = math.floor(num(def.graceSeconds, 120)),
        eligibilityExport = type(def.eligibilityExport) == 'string' and def.eligibilityExport or nil,
        eventExport = type(def.eventExport) == 'string' and def.eventExport or nil,
    }
    return true, { providerType = providerType }
end

-- ----------------------------------------------------------------- publication

function Core:CreateContract(invoker, data)
    local src = (self.cfg.Sources or {})[invoker]
    if not src then return false, 'untrusted_source' end
    if type(data) ~= 'table' then return false, 'invalid_request' end
    local ctype = data.contractType
    local tc = type(ctype) == 'string' and self:typeCfg(ctype) or nil
    if not tc or not (src.types or {})[ctype] then return false, 'unsupported_type' end
    if not isRef(data.sourceReference) then return false, 'invalid_source_reference' end

    local existing = self.store.getBySource(invoker, data.sourceReference, ctype)
    if existing then
        return true, { reference = existing.reference, status = existing.status, existing = true, completionMode = existing.completion_mode }
    end

    local title, desc = text(data.title, 80), text(data.description, 240)
    local pickup, dest = text(data.pickupHint, 120), text(data.destinationHint, 120)
    local cargo, region = text(data.cargoClass, 32), text(data.region, 32)
    if title == false or desc == false or pickup == false or dest == false or cargo == false or region == false then return false, 'invalid_field' end
    local urgency = data.urgency == nil and 'normal' or data.urgency
    if urgency ~= 'low' and urgency ~= 'normal' and urgency ~= 'high' then return false, 'invalid_field' end
    local meta = data.metadata == nil and {} or data.metadata
    if type(meta) ~= 'table' or #self.encode(meta) > 2048 then return false, 'invalid_metadata' end

    local fmin = num(tc.fallbackMinMinutes, tc.fallbackMinutes) * 60
    local fmax = num(tc.fallbackMaxMinutes, tc.fallbackMinutes) * 60
    local after = data.fallbackAfterSeconds ~= nil and num(data.fallbackAfterSeconds, nil) or num(tc.fallbackMinutes, 30) * 60
    if not after then return false, 'invalid_field' end
    after = math.floor(math.max(fmin, math.min(fmax, after)))

    local now = self.now()
    local row = {
        reference = self:_ref(), source_resource = invoker, source_reference = data.sourceReference, contract_type = ctype,
        provider_type = tc.providerType, status = 'available', title = title, description = desc, pickup_hint = pickup,
        destination_hint = dest, cargo_class = cargo, urgency = urgency, region = region, metadata = meta,
        fallback_at = now + after, created_at = now,
    }
    local id, why = self.store.insert(row)
    if not id then
        local again = self.store.getBySource(invoker, data.sourceReference, ctype) -- lost a creation race
        if again then return true, { reference = again.reference, status = again.status, existing = true, completionMode = again.completion_mode } end
        return false, why or 'internal_error'
    end
    row.id = id
    self:_event(row, 'created', nil, { fallbackAt = row.fallback_at })
    return true, { reference = row.reference, status = 'available', existing = false, fallbackAt = row.fallback_at }
end

-- ---------------------------------------------------------------- availability

function Core:ListAvailable(invoker, providerType, filters, characterId)
    if not self:_providerFor(invoker, providerType) then return false, 'untrusted_provider' end
    filters = type(filters) == 'table' and filters or {}
    local rows = self.store.listAvailable(providerType, self.now(), {
        contractType = type(filters.contractType) == 'string' and filters.contractType or nil,
        cargoClass = type(filters.cargoClass) == 'string' and filters.cargoClass or nil,
        region = type(filters.region) == 'string' and filters.region or nil,
        urgency = type(filters.urgency) == 'string' and filters.urgency or nil,
        limit = math.min(50, math.floor(num(filters.limit, 25))),
    }, characterId and tostring(characterId) or nil)
    local out = {}
    for _, c in ipairs(rows) do out[#out + 1] = self:view(c, characterId) end
    return true, out
end

-- Not publication-listed: a worker's own live claim.
function Core:GetClaim(invoker, providerType, characterId)
    if not self:_providerFor(invoker, providerType) then return false, 'untrusted_provider' end
    local rows = self.store.listByCharacter(tostring(characterId), providerType, { 'claimed', 'active' })
    local out = {}
    for _, c in ipairs(rows) do out[#out + 1] = self:view(c, characterId) end
    return true, out
end

-- ------------------------------------------------------------------- claiming

function Core:Claim(invoker, reference, characterId, opts)
    opts = type(opts) == 'table' and opts or {}
    if not isRef(reference) or characterId == nil or tostring(characterId) == '' or #tostring(characterId) > 50 then return false, 'invalid_request' end
    characterId = tostring(characterId)
    local c = self.store.getByRef(reference)
    if not c then return false, 'not_found' end
    local def = self:_providerFor(invoker, c.provider_type)
    if not def then return false, 'forbidden' end
    local tc = self:typeCfg(c.contract_type)
    if not tc or not def.types[c.contract_type] then return false, 'unsupported_type' end

    if WORKED[c.status] and c.claimed_character_id == characterId then
        return true, self:view(c, characterId), true -- duplicate claim by the same worker
    end
    if c.status ~= 'available' then return false, TERMINAL[c.status] and 'terminal' or 'already_claimed' end
    local now = self.now()
    if c.fallback_at <= now then return false, 'fallback_due' end
    if self.store.countByCharacter(characterId, c.provider_type, { 'claimed', 'active' }) >= num(tc.maxClaimsPerCharacter, 1) then
        return false, 'too_many_claims'
    end

    -- Eligibility is the provider's authority (job access, level, licence, session...). Fail closed.
    if def.eligibilityExport then
        local ok, eligible, reason = self.call(def.resource, def.eligibilityExport, characterId, self:view(c))
        if not ok then return false, 'provider_error' end
        if eligible ~= true then return false, type(reason) == 'string' and reason:sub(1, 40) or 'not_eligible' end
    end

    local lease = def.leaseSeconds > 0 and def.leaseSeconds or num(tc.leaseSeconds, 900)
    local providerRef = isRef(opts.providerRef) and opts.providerRef or nil
    local n = self.store.cas(reference, { 'available' }, {
        status = 'claimed', claimed_character_id = characterId, claimed_at = now, claim_expires_at = now + lease,
        provider_ref = providerRef,
    }, { fallback_after = now })
    if n ~= 1 then return false, 'already_claimed' end -- another worker (or fallback) won the race
    local fresh = self.store.getByRef(reference)
    self:_event(fresh, 'claimed', characterId, { lease = lease })
    self:_notifySource(fresh, 'claimed')
    return true, self:view(fresh, characterId)
end

function Core:Release(invoker, reference, characterId, reason)
    local c = self.store.getByRef(tostring(reference))
    if not c then return false, 'not_found' end
    if not self:_providerFor(invoker, c.provider_type) then return false, 'forbidden' end
    if c.status == 'available' and not c.claimed_character_id then return true, { replayed = true } end
    if not WORKED[c.status] or c.claimed_character_id ~= tostring(characterId) then return false, 'not_claimant' end
    local n = self.store.cas(reference, { 'claimed', 'active' }, release({ status = 'available' }), { claimed_character_id = tostring(characterId) })
    if n ~= 1 then return false, 'invalid_state' end
    self:_event(c, 'released', tostring(characterId), { reason = type(reason) == 'string' and reason:sub(1, 40) or nil })
    self:_notifySource(c, 'released')
    return true, { released = true }
end

function Core:MarkActive(invoker, reference, characterId, opts)
    local c = self.store.getByRef(tostring(reference))
    if not c then return false, 'not_found' end
    if not self:_providerFor(invoker, c.provider_type) then return false, 'forbidden' end
    if c.claimed_character_id ~= tostring(characterId) then return false, 'not_claimant' end
    if c.status == 'active' then return true, { replayed = true } end
    if c.status ~= 'claimed' then return false, 'invalid_state' end
    local tc = self:typeCfg(c.contract_type)
    local now = self.now()
    local n = self.store.cas(reference, { 'claimed' }, {
        status = 'active', active_at = now, claim_expires_at = now + math.floor(num(tc.activeTimeoutMinutes, 240) * 60),
        provider_ref = type(opts) == 'table' and isRef(opts.providerRef) and opts.providerRef or nil,
    }, { claimed_character_id = tostring(characterId), claim_not_expired = now })
    if n ~= 1 then return false, 'invalid_state' end
    self:_event(c, 'active', tostring(characterId))
    self:_notifySource(c, 'active')
    return true, { active = true }
end

-- Provider-side failure (vehicle destroyed, route abandoned...). The contract is not rewarded
-- and returns to the board, or goes to fallback after too many failures.
function Core:Fail(invoker, reference, characterId, reason)
    local c = self.store.getByRef(tostring(reference))
    if not c then return false, 'not_found' end
    if not self:_providerFor(invoker, c.provider_type) then return false, 'forbidden' end
    if not WORKED[c.status] or c.claimed_character_id ~= tostring(characterId) then return false, 'not_claimant' end
    local tc = self:typeCfg(c.contract_type)
    local fails = (tonumber(c.fail_count) or 0) + 1
    local patch = release({ status = 'available', fail_count = fails })
    if fails >= num(tc.maxFailures, 3) then patch.fallback_at = self.now() end -- sweep hands it to the source
    local n = self.store.cas(reference, { 'claimed', 'active' }, patch, { claimed_character_id = tostring(characterId) })
    if n ~= 1 then return false, 'invalid_state' end
    self:_event(c, 'failed', tostring(characterId), { reason = type(reason) == 'string' and reason:sub(1, 40) or nil, failCount = fails })
    return true, { failCount = fails, toFallback = fails >= num(tc.maxFailures, 3) }
end

-- ---------------------------------------------------------------- completion

-- Provider reports finished gameplay. The SOURCE applies the service; only then is the
-- contract completed. `rewardable` is true exactly once: that is the provider's only
-- permission to pay the worker.
function Core:Complete(invoker, reference, characterId, opts)
    opts = type(opts) == 'table' and opts or {}
    local c = self.store.getByRef(tostring(reference))
    if not c then return false, 'not_found' end
    if not self:_providerFor(invoker, c.provider_type) then return false, 'forbidden' end
    characterId = tostring(characterId)

    if c.status == 'completed' then
        if c.completion_mode == 'player' and c.claimed_character_id == characterId then
            return true, { mode = 'player', rewardable = false, replayed = true }
        end
        return false, c.completion_mode == 'fallback' and 'completed_by_fallback' or 'terminal'
    end
    if c.status == 'fallback' then return false, 'fallback_in_progress' end
    if c.status == 'cancelled' or c.status == 'failed' then return false, 'terminal' end
    if c.claimed_character_id ~= characterId then return false, 'not_claimant' end
    if c.status ~= 'active' then return false, 'invalid_state' end

    local now = self.now()
    -- Durable compare-and-swap: fallback and player completion cannot both proceed.
    local n = self.store.cas(reference, { 'active' }, { status = 'completing', completing_at = now }, { claimed_character_id = characterId })
    if n ~= 1 then return false, 'invalid_state' end
    self:_event(c, 'completing', characterId)

    local ok, res1, res2 = self.call(c.source_resource, ((self.cfg.Sources or {})[c.source_resource] or {}).completeExport or 'ContractSourceComplete', {
        reference = c.reference, sourceReference = c.source_reference, contractType = c.contract_type,
        workerCharacterId = characterId, mode = 'player', payload = type(opts.payload) == 'table' and opts.payload or nil })
    if ok and res1 == true then
        local done = self.store.cas(reference, { 'completing' }, { status = 'completed', completion_mode = 'player', completed_at = self.now(), completing_at = false, claim_expires_at = false }, nil)
        if done ~= 1 then return false, 'state_changed' end
        self:_event(c, 'completed_player', characterId, { replayed = type(res2) == 'table' and res2.replayed or nil }, 'terminal')
        return true, { mode = 'player', rewardable = true, source = type(res2) == 'table' and res2 or nil }
    end
    if ok and res1 == false and res2 == 'source_terminal' then
        self.store.cas(reference, { 'completing' }, { status = 'cancelled', end_reason = 'source_terminal', completing_at = false }, nil)
        self:_event(c, 'source_terminal', characterId, nil, 'terminal')
        return false, 'contract_cancelled'
    end
    -- Source unavailable or rejected for a retryable reason: the worker may try again.
    self.store.cas(reference, { 'completing' }, { status = 'active', completing_at = false }, { claimed_character_id = characterId })
    return false, ok and (type(res2) == 'string' and res2:sub(1, 40) or 'source_rejected') or 'source_unavailable'
end

-- ------------------------------------------------------- source-side controls

-- Source cancelled its own request (business cancel, ownership change...). No callback needed.
function Core:Cancel(invoker, contractType, sourceReference, reason)
    if not (self.cfg.Sources or {})[invoker] then return false, 'untrusted_source' end
    local c = self.store.getBySource(invoker, tostring(sourceReference), tostring(contractType))
    if not c then return false, 'not_found' end
    if c.status == 'cancelled' then return true, { replayed = true } end
    if c.status == 'completed' or c.status == 'failed' then return false, 'terminal' end
    if c.status == 'completing' then return false, 'in_progress' end
    local n = self.store.cas(c.reference, { 'available', 'claimed', 'active', 'fallback' }, release({ status = 'cancelled', end_reason = type(reason) == 'string' and reason:sub(1, 40) or 'source_cancel', completed_at = self.now() }), nil)
    if n ~= 1 then return false, 'in_progress' end
    self:_event(c, 'cancelled', nil, { by = 'source' }, 'terminal')
    self:_notifyProvider(c, 'cancelled', reason)
    return true, { cancelled = true }
end

function Core:GetSourceContract(invoker, contractType, sourceReference)
    if not (self.cfg.Sources or {})[invoker] then return false, 'untrusted_source' end
    local c = self.store.getBySource(invoker, tostring(sourceReference), tostring(contractType))
    if not c then return false, 'not_found' end
    return true, { reference = c.reference, status = c.status, completionMode = c.completion_mode, claimed = c.claimed_character_id ~= nil, fallbackAt = c.fallback_at }
end

-- ----------------------------------------------------------- worker disconnect

-- Called by the provider when its worker drops. Broker only manages lease state; the
-- provider cleans up vehicles/cargo/routes itself.
function Core:ReportWorkerDisconnected(invoker, providerType, characterId)
    local def = self:_providerFor(invoker, providerType)
    if not def then return false, 'forbidden' end
    local rows = self.store.listByCharacter(tostring(characterId), providerType, { 'claimed', 'active' })
    local changed, now = 0, self.now()
    for _, c in ipairs(rows) do
        if def.disconnectPolicy == 'release' then
            if self.store.cas(c.reference, { 'claimed', 'active' }, release({ status = 'available' }), { claimed_character_id = tostring(characterId) }) == 1 then
                self:_event(c, 'released', tostring(characterId), { reason = 'disconnect' }); changed = changed + 1
            end
        else
            local soon = now + def.graceSeconds
            if (c.claim_expires_at or soon + 1) > soon then
                self.store.cas(c.reference, { 'claimed', 'active' }, { claim_expires_at = soon }, { claimed_character_id = tostring(characterId) })
                self:_event(c, 'grace_started', tostring(characterId), { graceSeconds = def.graceSeconds }); changed = changed + 1
            end
        end
    end
    return true, { changed = changed, policy = def.disconnectPolicy }
end

-- ------------------------------------------------------------------- fallback

-- Source owns the actual service mutation; the broker only says "deadline expired".
function Core:_runFallback(c, fresh)
    local fb = self.cfg.Fallback or {}
    local now = self.now()
    local tc = self:typeCfg(c.contract_type) or {}
    if fresh then
        if WORKED[c.status] and tc.deferFallbackWhileWorked ~= false and (tonumber(c.fallback_deferrals) or 0) < num(tc.maxDeferrals, 2) then
            local n = self.store.cas(c.reference, { c.status }, { fallback_at = now + math.floor(num(tc.deferSeconds, 600)), fallback_deferrals = (tonumber(c.fallback_deferrals) or 0) + 1 },
                { fallback_due = now, claimed_character_id = c.claimed_character_id })
            if n == 1 then self:_event(c, 'fallback_deferred', c.claimed_character_id, nil); return 'deferred' end
            return 'raced'
        end
        local n = self.store.cas(c.reference, OPEN, { status = 'fallback', fallback_next_at = now + 120 }, { fallback_due = now })
        if n ~= 1 then return 'raced' end -- player completion (or release/cancel) won
        self:_event(c, 'fallback_started', nil, { from = c.status })
        if WORKED[c.status] then self:_notifyProvider(c, 'fallback', 'deadline') end
    else
        -- retry: take the processing lease so concurrent sweeps do not double-run
        local n = self.store.cas(c.reference, { 'fallback' }, { fallback_next_at = now + 120 }, { fallback_retry_due = now })
        if n ~= 1 then return 'raced' end
    end

    local attempt = (tonumber(c.fallback_attempts) or 0) + 1
    local src = (self.cfg.Sources or {})[c.source_resource] or {}
    local ok, res1, res2 = self.call(c.source_resource, src.fallbackExport or 'ContractSourceFallback', {
        reference = c.reference, sourceReference = c.source_reference, contractType = c.contract_type, attempt = attempt, mode = 'fallback' })
    if ok and res1 == true then
        local done = self.store.cas(c.reference, { 'fallback' }, { status = 'completed', completion_mode = 'fallback', completed_at = self.now(), fallback_attempts = attempt, fallback_next_at = false, claim_expires_at = false }, nil)
        if done == 1 then self:_event(c, 'completed_fallback', nil, { attempt = attempt, replayed = type(res2) == 'table' and res2.replayed or nil }, 'terminal') end
        return 'completed'
    end
    if ok and res1 == false and res2 == 'source_terminal' then
        self.store.cas(c.reference, { 'fallback' }, release({ status = 'cancelled', end_reason = 'source_terminal', completed_at = self.now() }), nil)
        self:_event(c, 'source_terminal', nil, nil, 'terminal')
        return 'cancelled'
    end
    local delay = math.min(num(fb.retryCap, 1800), num(fb.retryBase, 60) * (2 ^ (attempt - 1)))
    self.store.cas(c.reference, { 'fallback' }, { fallback_attempts = attempt, fallback_next_at = self.now() + math.floor(delay) }, nil)
    self:_event(c, 'fallback_retry', nil, { attempt = attempt, reason = ok and tostring(res2 or 'rejected'):sub(1, 40) or 'source_unavailable', nextInSeconds = math.floor(delay) })
    return 'retry'
end

-- ----------------------------------------------------------- sweep / recovery

-- Runs at start-up and periodically; idempotent and bounded. Every decision is a CAS on
-- durable state, so restarts and overlapping runs cannot reopen or double-complete.
function Core:Sweep()
    local now, batch = self.now(), math.floor(num((self.cfg.Fallback or {}).batch, 20))
    local stats = { released = 0, recovered = 0, fallback = 0 }

    for _, c in ipairs(self.store.query('expired_claims', now, batch)) do
        if self.store.cas(c.reference, { 'claimed' }, release({ status = 'available' }), { claim_expired = now }) == 1 then
            self:_event(c, 'lease_expired', c.claimed_character_id); self:_notifyProvider(c, 'lease_expired'); self:_notifySource(c, 'released'); stats.released = stats.released + 1
        end
    end
    for _, c in ipairs(self.store.query('expired_active', now, batch)) do
        local tc = self:typeCfg(c.contract_type) or {}
        local patch = release({ status = 'available' })
        if tc.onActiveExpire == 'fallback' then patch.fallback_at = now end
        if self.store.cas(c.reference, { 'active' }, patch, { claim_expired = now }) == 1 then
            self:_event(c, 'active_expired', c.claimed_character_id); self:_notifyProvider(c, 'lease_expired'); self:_notifySource(c, 'released'); stats.released = stats.released + 1
        end
    end
    -- Player completion interrupted by a crash: the source call is idempotent, so replay it.
    local stuck = now - math.floor(num(self.cfg.CompletingTimeoutSeconds, 120))
    for _, c in ipairs(self.store.query('stuck_completing', stuck, batch)) do
        if self.store.cas(c.reference, { 'completing' }, { completing_at = now }, { completing_before = stuck }) == 1 then
            self:_event(c, 'recovered', c.claimed_character_id, { from = 'completing' })
            local src = (self.cfg.Sources or {})[c.source_resource] or {}
            local ok, r1, r2 = self.call(c.source_resource, src.completeExport or 'ContractSourceComplete', {
                reference = c.reference, sourceReference = c.source_reference, contractType = c.contract_type,
                workerCharacterId = c.claimed_character_id, mode = 'player', recovered = true })
            if ok and r1 == true then
                if self.store.cas(c.reference, { 'completing' }, { status = 'completed', completion_mode = 'player', completed_at = now, completing_at = false, claim_expires_at = false }, nil) == 1 then
                    self:_event(c, 'completed_player', c.claimed_character_id, { recovered = true }, 'terminal')
                end
            elseif ok and r1 == false and r2 == 'source_terminal' then
                self.store.cas(c.reference, { 'completing' }, { status = 'cancelled', end_reason = 'source_terminal', completing_at = false }, nil)
                self:_event(c, 'source_terminal', nil, nil, 'terminal')
            else
                self.store.cas(c.reference, { 'completing' }, { status = 'active', completing_at = false }, nil)
            end
            stats.recovered = stats.recovered + 1
        end
    end
    for _, c in ipairs(self.store.query('fallback_due', now, batch)) do
        local r = self:_runFallback(c, true)
        if r ~= 'raced' then stats.fallback = stats.fallback + 1 end
    end
    for _, c in ipairs(self.store.query('fallback_retry', now, batch)) do
        local r = self:_runFallback(c, false)
        if r ~= 'raced' then stats.fallback = stats.fallback + 1 end
    end
    return stats
end

-- --------------------------------------------------------------------- admin

function Core:AdminInspect(reference)
    local c = self.store.getByRef(tostring(reference))
    if not c then return false, 'not_found' end
    return true, { contract = c, events = self.store.events(c.id) }
end

function Core:AdminList(filter)
    filter = type(filter) == 'table' and filter or {}
    return true, self.store.listAdmin(filter.status, filter.providerType, math.min(100, math.floor(num(filter.limit, 50))))
end

function Core:AdminRelease(reference, reason)
    local c = self.store.getByRef(tostring(reference))
    if not c then return false, 'not_found' end
    if not WORKED[c.status] then return false, 'invalid_state' end
    if self.store.cas(reference, { 'claimed', 'active' }, release({ status = 'available' }), nil) ~= 1 then return false, 'invalid_state' end
    self:_event(c, 'released', 'admin', { reason = type(reason) == 'string' and reason:sub(1, 40) or 'admin' })
    self:_notifyProvider(c, 'released', 'admin')
    return true
end

-- Cancel only where the source permits it: the source performs its own authoritative
-- cancel (and refund) first; only then is the contract cancelled.
function Core:AdminCancel(reference, reason)
    local c = self.store.getByRef(tostring(reference))
    if not c then return false, 'not_found' end
    if TERMINAL[c.status] then return false, 'terminal' end
    local src = (self.cfg.Sources or {})[c.source_resource] or {}
    if not src.cancelExport then return false, 'source_does_not_permit' end
    local ok, r1, r2 = self.call(c.source_resource, src.cancelExport, { reference = c.reference, sourceReference = c.source_reference, contractType = c.contract_type, reason = reason })
    if not ok then return false, 'source_unavailable' end
    if r1 ~= true then return false, type(r2) == 'string' and r2 or 'source_does_not_permit' end
    self.store.cas(reference, { 'available', 'claimed', 'active', 'fallback', 'completing' }, release({ status = 'cancelled', end_reason = 'admin', completed_at = self.now() }), nil)
    self:_event(c, 'cancelled', 'admin', { reason = type(reason) == 'string' and reason:sub(1, 40) or nil }, 'terminal')
    self:_notifyProvider(c, 'cancelled', 'admin')
    return true
end

CMContracts.Core = Core
return Core
