-- cm-phone Service Marketplace core. Pure logic: no natives, no SQL (all environment is injected), so the same code
-- runs in the server and in the deterministic local self-test (tests/services_selftest.lua).
--
-- The phone is only a FRONTEND:   PHONE -> service adapter -> SOURCE OWNER -> cm-contracts -> PROVIDER.
-- It stores NO requests and NO history: the source owner holds the authoritative request; the phone asks the owner
-- (by character, never by a client-supplied owner) for the current status. It creates no money, items or XP.
CMPhone = CMPhone or {}

local Core = {}
Core.__index = Core

-- Player-facing status vocabulary. Adapters return one of these keys; internal states (fallback, claim data, leases)
-- never reach the NUI. tone drives the colour: wait=yellow, good=green, active=cyan, bad=red.
local STATES = {
    searching          = { label = 'Looking for a worker',   tone = 'wait',   terminal = false },
    assigned           = { label = 'Worker assigned',        tone = 'good',   terminal = false },
    enroute            = { label = 'Worker on the way',      tone = 'good',   terminal = false },
    active             = { label = 'Service in progress',    tone = 'active', terminal = false },
    completed          = { label = 'Completed',              tone = 'good',   terminal = true },
    fallback_completed = { label = 'Completed automatically', tone = 'good',  terminal = true },
    cancelled          = { label = 'Cancelled',              tone = 'bad',    terminal = true },
    no_provider        = { label = 'No provider available',  tone = 'bad',    terminal = true },
}
Core.States = STATES

-- Adapter failure reasons that are safe to show; anything else becomes 'service_failed'.
local PASS_REASONS = {
    already_active = true, service_unavailable = true, no_provider = true, invalid_destination = true, too_far = true,
    cooldown = true, dead = true, not_allowed = true, busy = true, not_found = true, cancel_not_allowed = true,
}

local function isName(v) return type(v) == 'string' and #v >= 1 and #v <= 48 and v:match('^[%w_]+$') ~= nil end
local function isRef(v) return type(v) == 'string' and #v >= 1 and #v <= 40 and v:match('^[%w_%-:%.]+$') ~= nil end

function Core.New(deps)
    assert(type(deps) == 'table' and type(deps.cfg) == 'table', 'services core needs cfg')
    local self = setmetatable({}, Core)
    self.cfg = deps.cfg
    self.call = deps.call or function() return false, 'no_call' end
    self.started = deps.started or function() return false end
    self.now = deps.now or os.time
    self.rateLimit = deps.rateLimit or function() return true end
    self.position = deps.position or function() return nil end
    self.isDead = deps.isDead or function() return false end
    self.emit = deps.emit or function() return false end
    self.audit = deps.audit or function() end
    self.clean = deps.cleanText
    self.adapters = {}   -- serviceId -> { resource, create, status, cancel, availability }
    self.locks = {}
    self.lastPush = {}
    return self
end

-- ----------------------------------------------------------------- registry

-- Contract-state translation for sources: broker status (+ completion mode) -> player-facing key.
function Core.MapContractState(status, mode)
    if status == 'available' or status == 'fallback' then return 'searching' end
    if status == 'claimed' then return 'assigned' end
    if status == 'active' or status == 'completing' then return 'active' end
    if status == 'completed' then return mode == 'fallback' and 'fallback_completed' or 'completed' end
    if status == 'cancelled' or status == 'failed' then return 'cancelled' end
    return 'searching'
end

-- Trusted server resources register the adapter for a service THEY own. The display definition stays in the phone's
-- trusted config catalog, so a resource can never change what the player sees, only how requests reach its owner.
function Core:RegisterAdapter(invoker, serviceId, def)
    local svc = self.cfg.Services
    if not svc or svc.Enabled == false then return false, 'disabled' end
    local allowed = (svc.Sources or {})[invoker]
    if not allowed or allowed[serviceId] ~= true then return false, 'untrusted_source' end
    if not (svc.Catalog or {})[serviceId] then return false, 'invalid_service' end
    if type(def) ~= 'table' or not isName(def.create) or not isName(def.status) then return false, 'invalid_definition' end
    if def.cancel ~= nil and not isName(def.cancel) then return false, 'invalid_definition' end
    if def.availability ~= nil and not isName(def.availability) then return false, 'invalid_definition' end
    local existing = self.adapters[serviceId]
    if existing and existing.resource ~= invoker then return false, 'duplicate_service' end
    self.adapters[serviceId] = { resource = invoker, create = def.create, status = def.status, cancel = def.cancel, availability = def.availability }
    return true
end

function Core:UnregisterResource(resource)
    for id, a in pairs(self.adapters) do if a.resource == resource then self.adapters[id] = nil end end
end

local function publicField(f)
    local o = { key = f.key, label = f.label, type = f.type, required = f.required == true, max = f.max, hint = f.hint }
    if f.options then o.options = {} for i, v in ipairs(f.options) do o.options[i] = v end end
    return o
end

function Core:_def(serviceId)
    local svc = self.cfg.Services
    if not svc or svc.Enabled == false or not isName(serviceId) then return nil end
    return (svc.Catalog or {})[serviceId]
end

-- available | limited | offline | soon. Never trusts a client; asks the (registered, started) source owner.
function Core:_availability(serviceId, def)
    if def.comingSoon == true or def.enabled == false then return 'soon' end
    local a = self.adapters[serviceId]
    if not a or not self.started(a.resource) then return 'offline', 'provider_unavailable' end
    if a.availability then
        local ok, r1 = self.call(a.resource, a.availability, serviceId)
        if not ok then return 'offline', 'provider_unavailable' end
        if r1 == 'limited' then return 'limited' end
        if r1 == false or r1 == 'offline' then return 'offline', 'provider_unavailable' end
    end
    return 'available'
end

function Core:_normalize(raw)
    if raw == nil then return nil end
    if type(raw) ~= 'table' then return false end
    local st = STATES[raw.state]
    if not st then return false end
    local out = { state = raw.state, label = st.label, tone = st.tone, terminal = st.terminal }
    out.ref = isRef(raw.ref) and raw.ref or nil
    local eta = tonumber(raw.etaSeconds)
    if eta and eta >= 0 and eta <= 86400 then out.etaSeconds = math.floor(eta) end
    out.workerLabel = type(raw.workerLabel) == 'string' and self.clean(raw.workerLabel, 40, false) or nil
    out.detail = type(raw.detail) == 'string' and self.clean(raw.detail, 80, false) or nil
    out.canCancel = raw.canCancel == true and not st.terminal
    return out
end

-- Current request status, asked of the owner for THIS character. true, nil = none.
function Core:_status(cid, serviceId)
    local a = self.adapters[serviceId]
    if not a or not self.started(a.resource) then return false, 'status_unavailable' end
    local ok, r1, r2 = self.call(a.resource, a.status, tostring(cid), serviceId)
    if not ok then return false, 'status_unavailable' end
    if r1 == false then return false, 'status_unavailable' end
    local status = self:_normalize(r2 ~= nil and r2 or (type(r1) == 'table' and r1 or nil))
    if status == false then return false, 'status_unavailable' end
    return true, status
end

function Core:Status(cid, serviceId)
    local def = self:_def(serviceId)
    if not def then return false, 'invalid_service' end
    return self:_status(cid, serviceId)
end

function Core:ListServices(cid)
    local svc = self.cfg.Services
    if not svc or svc.Enabled == false then return true, {} end
    local ids = {}
    for id in pairs(svc.Catalog or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (svc.Catalog[a].order or 99) < (svc.Catalog[b].order or 99) end)
    local out = {}
    for _, id in ipairs(ids) do
        local def = svc.Catalog[id]
        local state, reason = self:_availability(id, def)
        if not (state == 'offline' and svc.HideOffline == true) then
            local entry = {
                id = id, name = def.name, icon = def.icon, category = def.category, description = def.description,
                state = state, reason = reason, canRequest = state == 'available' or state == 'limited', fields = {},
            }
            for _, f in ipairs(def.fields or {}) do entry.fields[#entry.fields + 1] = publicField(f) end
            if entry.canRequest then
                local ok, status = self:_status(cid, id)
                if ok and status then entry.current = status end
            end
            out[#out + 1] = entry
        end
    end
    return true, out
end

-- ------------------------------------------------------------- payload checks

local function finite(n) return type(n) == 'number' and n == n and n > -1e9 and n < 1e9 end

-- Validates raw client fields against the service definition. Unknown keys, wrong types, oversized text and malformed
-- destinations are rejected; nothing outside the definition ever reaches the source owner.
function Core:_validate(def, raw)
    if raw == nil then raw = {} end
    if type(raw) ~= 'table' then return nil, 'invalid_request' end
    local byKey, count = {}, 0
    for _, f in ipairs(def.fields or {}) do byKey[f.key] = f end
    for k in pairs(raw) do
        count = count + 1
        if count > 12 or type(k) ~= 'string' or not byKey[k] then return nil, 'invalid_field' end
    end
    local clean = {}
    for _, f in ipairs(def.fields or {}) do
        local v = raw[f.key]
        if v == nil or v == '' then
            if f.required then return nil, 'missing_field' end
        elseif f.type == 'text' then
            if type(v) ~= 'string' or #v > (f.max or 120) * 4 then return nil, 'invalid_field' end
            local c = self.clean(v, f.max or 120, false)
            if not c then if f.required then return nil, 'missing_field' end else clean[f.key] = c end
        elseif f.type == 'enum' then
            local ok = false
            for _, o in ipairs(f.options or {}) do if o == v then ok = true end end
            if type(v) ~= 'string' or not ok then return nil, 'invalid_field' end
            clean[f.key] = v
        elseif f.type == 'waypoint' then
            -- Client waypoint flow only: {x, y[, z]}. Range-checked here; never used as the requester's own position.
            if type(v) ~= 'table' or not finite(v.x) or not finite(v.y) or (v.z ~= nil and not finite(v.z)) then return nil, 'invalid_field' end
            local lim = (self.cfg.Services or {}).WorldLimit or 8000.0
            if math.abs(v.x) > lim or math.abs(v.y) > lim then return nil, 'invalid_field' end
            for k2 in pairs(v) do if k2 ~= 'x' and k2 ~= 'y' and k2 ~= 'z' then return nil, 'invalid_field' end end
            clean[f.key] = { x = v.x + 0.0, y = v.y + 0.0, z = v.z and (v.z + 0.0) or nil }
        else
            return nil, 'invalid_field'
        end
    end
    return clean
end

local function failReason(r)
    if type(r) == 'string' and PASS_REASONS[r] then return r end
    return 'service_failed'
end

-- ------------------------------------------------------------------ request

function Core:Request(src, cid, serviceId, rawFields)
    if not self.rateLimit(cid, 'service') then return false, 'rate_limited' end
    local def = self:_def(serviceId)
    if not def then return false, 'invalid_service' end
    local state = self:_availability(serviceId, def)
    if state ~= 'available' and state ~= 'limited' then return false, 'service_unavailable' end
    local fields, why = self:_validate(def, rawFields)
    if not fields then return false, why end
    if self.isDead(src) then return false, 'unavailable' end
    -- Server-observed position (never a NUI coordinate); no continuous tracking: sampled once per request.
    local pos = self.position(src)
    if def.positionRequired ~= false and not pos then return false, 'location_unavailable' end

    local lockKey = tostring(cid) .. ':' .. serviceId
    if self.locks[lockKey] then return false, 'busy' end
    self.locks[lockKey] = true
    local ran, ok, a, b = pcall(function()
        if def.activePolicy ~= 'multi' then
            local sok, current = self:_status(cid, serviceId)
            if sok and current and not current.terminal then return false, 'already_active', current end
        end
        local adapter = self.adapters[serviceId]
        local cok, r1, r2 = self.call(adapter.resource, adapter.create, tostring(cid), serviceId, fields,
            { position = pos, requestedAt = self.now() })
        if not cok then return false, 'service_unavailable' end
        if r1 ~= true then return false, failReason(r2) end
        local status = self:_normalize(type(r2) == 'table' and { state = r2.state or 'searching', ref = r2.ref, etaSeconds = r2.etaSeconds,
            workerLabel = r2.workerLabel, detail = r2.detail, canCancel = r2.canCancel } or { state = 'searching' })
        if not status then status = self:_normalize({ state = 'searching' }) end
        return true, status
    end)
    self.locks[lockKey] = nil
    if not ran then return false, 'internal_error' end
    if ok then
        self.audit(src, 'cm_phone_service_request', { characterId = cid, service = serviceId })
        return true, a
    end
    return false, a, b
end

-- ------------------------------------------------------------------- cancel

-- The phone never touches the broker or owner state directly: it checks, through the owner, that the ref is the
-- character's own current request and that the owner permits cancelling, then asks the owner to cancel.
function Core:Cancel(src, cid, serviceId, ref)
    if not self.rateLimit(cid, 'serviceCancel') then return false, 'rate_limited' end
    local def = self:_def(serviceId)
    if not def then return false, 'invalid_service' end
    if not isRef(ref) then return false, 'invalid_request' end
    local a = self.adapters[serviceId]
    if not a or not a.cancel then return false, 'cancel_not_allowed' end
    local lockKey = tostring(cid) .. ':' .. serviceId
    if self.locks[lockKey] then return false, 'busy' end
    self.locks[lockKey] = true
    local ran, ok, reason, extra = pcall(function()
        local sok, current = self:_status(cid, serviceId)
        if not sok then return false, 'status_unavailable' end
        if not current or current.ref ~= ref then return false, 'not_found' end -- foreign / stale request ref
        if current.terminal then return false, 'cancel_not_allowed' end
        if current.canCancel ~= true then return false, 'cancel_not_allowed' end
        local cok, r1, r2 = self.call(a.resource, a.cancel, tostring(cid), serviceId, ref)
        if not cok then return false, 'service_unavailable' end
        if r1 ~= true then return false, failReason(r2) end
        local _, after = self:_status(cid, serviceId)
        return true, after or self:_normalize({ state = 'cancelled', ref = ref })
    end)
    self.locks[lockKey] = nil
    if not ran then return false, 'internal_error' end
    if ok then
        self.audit(src, 'cm_phone_service_cancel', { characterId = cid, service = serviceId })
        return true, reason
    end
    return false, reason, extra
end

-- --------------------------------------------------------------- status push

-- Event-driven: the source owner pushes a change; the phone sanitises it and notifies the requester. A resource can
-- only push for a service it registered, and only the whitelisted status shape is forwarded.
function Core:Push(invoker, cid, serviceId, rawStatus)
    local def = self:_def(serviceId)
    if not def then return false, 'invalid_service' end
    local a = self.adapters[serviceId]
    if not a or a.resource ~= invoker then return false, 'forbidden' end
    if cid == nil or tostring(cid) == '' then return false, 'invalid_request' end
    local status = self:_normalize(rawStatus)
    if not status then return false, 'invalid_status' end
    local key = tostring(cid) .. ':' .. serviceId
    local now = self.now()
    if self.lastPush[key] and self.lastPush[key].state == status.state and now - self.lastPush[key].at < 2 then return true, 'throttled' end
    self.lastPush[key] = { state = status.state, at = now }
    local message = ('%s: %s'):format(def.name, status.label)
    if not self.emit(tostring(cid), 'cm-phone:client:serviceStatus', { service = serviceId, status = status, message = message }) then
        return false, 'offline'
    end
    return true
end

CMPhone.ServicesCore = Core
return Core
