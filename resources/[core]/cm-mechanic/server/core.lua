-- cm-mechanic engine: mechanic service REQUESTS (source owner) and WORK ORDERS (provider side).
-- Dependency-injected (no FiveM natives, no SQL): server/main.lua wires the real store/adapters, tests/selftest.lua wires
-- deterministic doubles. Every authority decision (identity, business, permission, vehicle, price, invoice, completion) is made here.
--
--   PHONE -> create() -> request(open) -> cm-contracts publish -> mechanic claims (cm-contracts) -> work order(assigned)
--     -> diagnose (vehicle_id bound) -> quote (server price) -> customer approves -> cm-billing invoice -> customer pays
--     -> paid detected -> service start/finish (or server auto-commit) -> vehicle patch (once) -> contract complete
--
-- Money never moves here: cm-billing settles the customer's payment into the business balance. No job payout, no commission.
--
-- TUNING (service 'tuning_request', authority 'cm-tuning'): the SAME work order / approval / invoice / payment / commit machinery, but the
-- quote and the modification belong to cm-tuning. patch_json holds { tuning = <cm-tuning authorization reference> } instead of a vehicle patch;
-- the commit calls cm-tuning (idempotent) instead of cm-vehicles ServiceVehicleById. After payment it is forward-only (no refund API).
CMMechanic = CMMechanic or {}
local Core = {}
Core.__index = Core
CMMechanic.Core = Core

local REF_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local OPEN_REQ = { open = true, assigned = true }
local OPEN_WO = { assigned = true, diagnosing = true, quoted = true, awaiting_payment = true, servicing = true }
local PRE_INVOICE = { assigned = true, diagnosing = true, quoted = true }

Core.OPEN_WO = OPEN_WO

local function num(v, d) v = tonumber(v); if v == nil then return d end return v end
local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Core.New(deps)
    assert(type(deps) == 'table' and type(deps.cfg) == 'table' and deps.store, 'cm-mechanic core needs cfg + store')
    local self = setmetatable({}, Core)
    self.cfg, self.store = deps.cfg, deps.store
    self.now = deps.now or os.time
    self.rand = deps.rand or math.random
    self.encode = deps.encode or function() return '' end
    self.decode = deps.decode or function() return nil end
    self.clean = deps.clean or function(s, max) if type(s) ~= 'string' then return nil end s = s:gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '') if s == '' then return nil end return s:sub(1, max) end
    self.chars, self.vehicles, self.business = deps.chars, deps.vehicles, deps.business
    self.billing, self.contracts = deps.billing, deps.contracts
    self.tuning = deps.tuning            -- optional cm-tuning adapter (see server/main.lua); absent = tuning service not offered
    self.notify = deps.notify or function() end
    self.audit = deps.audit or function() end
    self.rate = deps.rate or function() return true end
    self.log = deps.log or function() end
    self.pricing = CMMechanic.Pricing
    self.locks, self.offlineSince = {}, {}
    return self
end

-- ------------------------------------------------------------------ helpers

function Core:_ref(prefix)
    local s = {}
    for i = 1, 8 do local n = self.rand(1, #REF_CHARS); s[i] = REF_CHARS:sub(n, n) end
    return prefix .. '-' .. table.concat(s)
end

function Core:_lock(key, fn)
    if self.locks[key] then return false, 'busy' end
    self.locks[key] = true
    local res = table.pack(pcall(fn))
    self.locks[key] = nil
    if not res[1] then self.log('error', tostring(res[2])); return false, 'internal_error' end
    return table.unpack(res, 2, res.n)
end

function Core:_event(req, wo, kind, actor, detail, key)
    local scope = (wo and wo.reference) or (req and req.reference) or ''
    local ok = self.store.eventInsert({
        request_ref = req and req.reference or (wo and wo.request_ref) or nil, work_ref = wo and wo.reference or nil,
        kind = kind, actor = actor and tostring(actor) or nil, key = key and (scope .. ':' .. key) or nil,
        detail = detail and self.encode(detail):sub(1, 480) or nil,
    })
    return ok
end

function Core:_mirrorAdmin(kind, detail) pcall(self.audit, kind, detail) end

function Core:_perm(name) return self.cfg.Permissions[name] end

function Core:_has(cid, wo, permKey)
    return self.business.has(wo.business_type, wo.business_id, cid, self:_perm(permKey)) == true
end

function Core:_service(id)
    local s = type(id) == 'string' and self.cfg.Services[id] or nil
    if not s or s.enabled == false then return nil end
    return s
end

-- Mechanic businesses this character may work for (owner or employee) with the given permission.
function Core:_businessesFor(cid, permKey)
    local out = {}
    for _, b in ipairs(self.business.list(cid) or {}) do
        if b.type == self.cfg.BusinessType then
            local biz = self.business.get(b.type, b.id)
            if biz and biz.owned and self.business.has(b.type, b.id, cid, self:_perm(permKey)) == true then
                out[#out + 1] = { type = b.type, id = b.id, label = biz.label }
            end
        end
    end
    return out
end

function Core:_anyProvider()
    for _, shop in ipairs(self.cfg.Shops) do
        local biz = self.business.get(self.cfg.BusinessType, shop.id)
        if biz and biz.owned then return true end
    end
    return false
end

function Core:_shop(id)
    for _, s in ipairs(self.cfg.Shops) do if s.id == id then return s end end
end

-- ----------------------------------------------------------------- public views

local function phoneView(self, req, wo)
    local st = req.status
    local v = { ref = req.reference, canCancel = false }
    if st == 'completed' then v.state, v.detail = 'completed', 'Service completed'
    elseif st == 'cancelled' then v.state, v.detail = 'cancelled', 'Request cancelled'
    elseif st == 'expired' then v.state, v.detail = 'no_provider', 'No mechanic available'
    elseif not wo or not OPEN_WO[wo.state] then v.state, v.detail, v.canCancel = 'searching', 'Looking for a mechanic', true
    else
        v.workerLabel = 'Mechanic assigned'
        local s = wo.state
        if s == 'assigned' then v.state, v.detail, v.canCancel = 'assigned', 'Mechanic on the way', true
        elseif s == 'diagnosing' then v.state, v.detail, v.canCancel = 'active', 'Diagnosing your vehicle', true
        elseif s == 'quoted' then v.state, v.detail, v.canCancel = 'active', 'Awaiting your approval', true
        elseif s == 'awaiting_payment' then v.state, v.detail, v.canCancel = 'active', 'Awaiting payment - open Bills', true
        else v.state, v.detail = 'active', 'Service in progress' end
    end
    return v
end

function Core:_phoneViewFor(req)
    local wo = req.work_order_ref and self.store.woGetByRef(req.work_order_ref) or nil
    return phoneView(self, req, wo), wo
end

function Core:_push(req)
    local view = self:_phoneViewFor(req)
    pcall(self.notify, req.customer_cid, 'phone', view)
end

-- ------------------------------------------------------------ phone adapter

function Core:Availability()
    return self:_anyProvider()
end

function Core:CreateRequest(cid, fields, ctx)
    cid = cid and tostring(cid)
    if not cid or cid == '' then return false, 'not_allowed' end
    if not self.rate(cid, 'request') then return false, 'cooldown' end
    local src = self.chars.sourceOf(cid)
    if not src then return false, 'service_unavailable' end
    if self.chars.isDead(src) then return false, 'dead' end
    fields = type(fields) == 'table' and fields or {}
    local hint = fields.service
    if type(hint) ~= 'string' or not self.cfg.Request.hints[hint] then return false, 'not_allowed' end

    local existing = self.store.reqOpenByCustomer(cid)
    if existing then
        local v = self:_phoneViewFor(existing)
        return true, v
    end
    if not self:_anyProvider() then return false, 'no_provider' end
    local pos = type(ctx) == 'table' and ctx.position or nil
    if type(pos) ~= 'table' or type(pos.x) ~= 'number' or type(pos.y) ~= 'number' then return false, 'service_unavailable' end

    local now = self.now()
    local note = self.clean(fields.details, self.cfg.Request.maxNote)
    local req = {
        reference = self:_ref('MR'), customer_cid = cid, hint = hint, note = note, status = 'open', active_key = cid,
        pos_x = pos.x, pos_y = pos.y, pos_z = tonumber(pos.z) or 0.0, created_at = now, updated_at = now,
    }
    local id, why = self.store.reqInsert(req)
    if not id then
        local again = self.store.reqOpenByCustomer(cid)
        if again then return true, (self:_phoneViewFor(again)) end
        return false, why == 'duplicate_active' and 'already_active' or 'service_unavailable'
    end
    self:_event(req, nil, 'request_created', cid, { hint = hint })
    local ok = self:_publish(req)
    if not ok then
        self.store.reqCas(req.reference, { 'open' }, { status = 'cancelled', active_key = false, end_reason = 'publish_failed', updated_at = self.now() })
        self:_event(req, nil, 'request_cancelled', cid, { reason = 'publish_failed' })
        return false, 'service_unavailable'
    end
    local fresh = self.store.reqGetByRef(req.reference) or req
    return true, (self:_phoneViewFor(fresh))
end

-- Publish (idempotent: the broker keeps one contract per source reference).
function Core:_publish(req)
    local cfg = self.cfg
    local r = cfg.Request.approxRoundMetres
    local rx = math.floor((req.pos_x or 0) / r + 0.5) * r
    local ry = math.floor((req.pos_y or 0) / r + 0.5) * r
    local label = cfg.Request.hints[req.hint] or 'Service'
    local desc = req.note and (label .. ': ' .. req.note) or label
    local ok, res = self.contracts.create({
        contractType = cfg.ContractType, sourceReference = req.reference, title = 'Mechanic request', description = desc:sub(1, 240),
        pickupHint = ('Roadside near %d, %d'):format(rx, ry), cargoClass = req.hint, urgency = 'normal',
        fallbackAfterSeconds = cfg.Request.fallbackAfterSeconds, metadata = { hint = req.hint },
    })
    if ok ~= true or type(res) ~= 'table' or not res.reference then return false end
    self.store.reqCas(req.reference, { 'open', 'assigned' }, { contract_ref = res.reference, updated_at = self.now() })
    req.contract_ref = res.reference
    return true
end

function Core:RequestStatus(cid)
    cid = tostring(cid)
    local req = self.store.reqLatestByCustomer(cid)
    if not req then return true, nil end
    if not OPEN_REQ[req.status] and self.now() - (tonumber(req.updated_at) or 0) > self.cfg.Request.statusLingerSeconds then return true, nil end
    return true, (self:_phoneViewFor(req))
end

function Core:CancelRequest(cid, ref)
    cid = tostring(cid)
    if not self.rate(cid, 'cancel') then return false, 'cooldown' end
    local req = self.store.reqGetByRef(tostring(ref))
    if not req or req.customer_cid ~= cid then return false, 'not_found' end
    return self:_lock('req:' .. req.reference, function()
        req = self.store.reqGetByRef(req.reference)
        if not OPEN_REQ[req.status] then return false, 'cancel_not_allowed' end
        local wo = req.work_order_ref and self.store.woGetByRef(req.work_order_ref) or nil
        if wo and OPEN_WO[wo.state] then
            if wo.state == 'servicing' then return false, 'cancel_not_allowed' end
            if wo.state == 'awaiting_payment' then
                local okV = self:_voidInvoice(wo)
                if not okV then return false, 'cancel_not_allowed' end
            end
        end
        -- Broker first: it refuses when a completion is being applied. 'not_found' = nothing was ever published.
        local ok, why = self.contracts.cancel(self.cfg.ContractType, req.reference, 'requester_cancel')
        if ok ~= true and why ~= 'not_found' and why ~= 'terminal' then return false, 'cancel_not_allowed' end
        if wo and OPEN_WO[wo.state] then
            self.store.woCas(wo.reference, { 'assigned', 'diagnosing', 'quoted', 'awaiting_payment' },
                { state = 'cancelled', active_key = false, end_reason = 'customer_cancel', updated_at = self.now() })
            self:_event(req, wo, 'work_cancelled', cid, { reason = 'customer_cancel' })
            pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'cancelled', work = wo.reference })
        end
        local n = self.store.reqCas(req.reference, { 'open', 'assigned' }, { status = 'cancelled', active_key = false, end_reason = 'customer_cancel', updated_at = self.now() })
        if n ~= 1 then return false, 'cancel_not_allowed' end
        self:_event(req, nil, 'request_cancelled', cid, { by = 'customer' })
        return true
    end)
end

-- ----------------------------------------------------------- provider eligibility

-- Called by the broker (via ContractEligible) before a claim. true | false, reason
function Core:Eligible(cid, view)
    cid = tostring(cid)
    if not self.chars.sourceOf(cid) then return false, 'not_loaded' end
    local req = type(view) == 'table' and self.store.reqGetByContract(view.reference) or nil
    if not req then return false, 'not_found' end
    if req.status ~= 'open' then return false, 'not_open' end
    if self.cfg.Policy.selfService ~= true and req.customer_cid == cid then return false, 'self_service' end
    if #self:_businessesFor(cid, 'accept') == 0 then return false, 'not_mechanic' end
    return true
end

-- Mechanic board: published requests this character may claim + their own active order.
function Core:Board(cid)
    cid = tostring(cid)
    if not self.rate(cid, 'board') then return false, 'rate_limited' end
    if #self:_businessesFor(cid, 'accept') == 0 then return false, 'not_mechanic' end
    local ok, list = self.contracts.list({ contractType = self.cfg.ContractType }, cid)
    if ok ~= true then return false, 'service_unavailable' end
    local out = {}
    for _, c in ipairs(list or {}) do
        if c.claimedByYou ~= true then
            local req = self.store.reqGetByContract(c.reference)
            if req and req.status == 'open' and (self.cfg.Policy.selfService == true or req.customer_cid ~= cid) then
                out[#out + 1] = { contract = c.reference, title = c.title, description = c.description, area = c.pickupHint,
                    hint = req.hint, expiresInSeconds = c.fallbackInSeconds }
            end
        end
    end
    return true, { requests = out, active = self:_activeFor(cid) }
end

function Core:_activeFor(cid)
    local wo = self.store.woActiveByMechanic(tostring(cid))
    return wo and self:MechanicView(wo) or nil
end

-- ------------------------------------------------------------------------ claim

function Core:Claim(cid, contractRef, businessId)
    cid = tostring(cid)
    if not self.rate(cid, 'claim') then return false, 'rate_limited' end
    if type(contractRef) ~= 'string' then return false, 'invalid_request' end
    local req = self.store.reqGetByContract(contractRef)
    if not req then return false, 'not_found' end
    return self:_lock('req:' .. req.reference, function()
        req = self.store.reqGetByRef(req.reference)
        local existing = self.store.woActiveByRequest(req.reference)
        if existing and existing.mechanic_cid == cid then return true, self:MechanicView(existing) end
        if req.status ~= 'open' then return false, 'not_open' end
        if self.cfg.Policy.selfService ~= true and req.customer_cid == cid then return false, 'self_service' end
        local candidates = self:_businessesFor(cid, 'accept')
        local chosen
        for _, b in ipairs(candidates) do
            if businessId == nil or tostring(businessId) == b.id then chosen = chosen or b end
        end
        if not chosen then return false, 'not_mechanic' end

        local woRef = self:_ref('WO')
        local ok, res, dup = self.contracts.claim(contractRef, cid, { providerRef = woRef })
        if ok ~= true then return false, type(res) == 'string' and res or 'claim_failed' end
        if dup == true then
            local again = self.store.woActiveByRequest(req.reference)
            if again and again.mechanic_cid == cid then return true, self:MechanicView(again) end
        end
        local now = self.now()
        local wo = {
            reference = woRef, request_ref = req.reference, contract_ref = contractRef, customer_cid = req.customer_cid,
            mechanic_cid = cid, business_type = chosen.type, business_id = chosen.id, state = 'assigned', active_key = req.reference,
            commit_state = 'none', invoice_attempt = 1, declines = 0, commit_attempts = 0, created_at = now, updated_at = now,
        }
        local id = self.store.woInsert(wo)
        if not id then
            self.contracts.release(contractRef, cid, 'work_order_failed')
            return false, 'busy'
        end
        local n = self.store.reqCas(req.reference, { 'open' }, { status = 'assigned', work_order_ref = woRef, updated_at = now })
        if n ~= 1 then
            self.store.woCas(woRef, { 'assigned' }, { state = 'cancelled', active_key = false, end_reason = 'request_changed', updated_at = now })
            self.contracts.release(contractRef, cid, 'request_changed')
            return false, 'not_open'
        end
        self:_event(req, wo, 'mechanic_claimed', cid, { business = chosen.type .. ':' .. chosen.id })
        req.status, req.work_order_ref = 'assigned', woRef
        self:_push(req)
        return true, self:MechanicView(wo)
    end)
end

-- --------------------------------------------------------------- mechanic view

function Core:MechanicView(wo)
    local req = self.store.reqGetByRef(wo.request_ref)
    local view = {
        workOrder = wo.reference, state = wo.state, service = wo.service_id, serviceLabel = wo.service_id and self.cfg.Services[wo.service_id] and self.cfg.Services[wo.service_id].label or nil,
        quote = wo.quote_amount, business = wo.business_type .. ':' .. wo.business_id,
        hint = req and req.hint, note = req and req.note,
        customerPosition = req and { x = req.pos_x, y = req.pos_y } or nil,
        vehicleLabel = wo.vehicle_label, declines = wo.declines,
    }
    if wo.diagnosis then view.diagnosis = wo.diagnosis
    elseif wo.diagnosis_json and wo.diagnosis_json ~= '' then view.diagnosis = self.decode(wo.diagnosis_json) end
    if wo.state == 'diagnosing' then
        local offers = {}
        for id, s in pairs(self.cfg.Services) do
            if s.enabled ~= false and (s.authority ~= 'cm-tuning' or self.tuning) then
                offers[#offers + 1] = { id = id, label = s.label, category = s.category, mode = s.mode, tuning = s.authority == 'cm-tuning' or nil }
            end
        end
        table.sort(offers, function(a, b) return a.id < b.id end)
        view.offers = offers
    end
    return view
end

function Core:GetWork(cid, ref)
    local wo
    if ref ~= nil then wo = self.store.woGetByRef(tostring(ref)) else wo = self.store.woActiveByMechanic(tostring(cid)) end
    if not wo or wo.mechanic_cid ~= tostring(cid) then return false, 'not_found' end
    return true, self:MechanicView(wo)
end

-- ----------------------------------------------------------- vehicle resolution

-- netId (server-observed entity) -> persistent vehicle_id, with full eligibility + proximity validation.
-- Returns true, ctx{ vehicleId, row, customerSrc, mechanicSrc } | false, reason
function Core:_resolveVehicle(wo, netId, accessLevel, approval)
    local mSrc = self.chars.sourceOf(wo.mechanic_cid)
    if not mSrc and not approval then return false, 'mechanic_offline' end
    local cSrc = self.chars.sourceOf(wo.customer_cid)
    if not cSrc then return false, 'customer_offline' end
    local vehicleId, why = self.vehicles.fromNet(netId)
    if not vehicleId then return false, why or 'vehicle_not_found' end
    if wo.vehicle_id and tonumber(wo.vehicle_id) ~= tonumber(vehicleId) then return false, 'wrong_vehicle' end
    local row = self.vehicles.get(vehicleId)
    if not row then return false, 'vehicle_not_found' end
    local pol = self.cfg.Policy
    if row.admin == true and pol.allowAdminVehicles ~= true then return false, 'vehicle_protected' end
    if tostring(row.ownerType or 'character') ~= 'character' and pol.allowOrganizationVehicles ~= true then return false, 'vehicle_protected' end
    if row.stored == true and pol.allowStoredVehicles ~= true then return false, 'vehicle_not_present' end

    local vpos = self.vehicles.position(vehicleId)
    if not vpos then return false, 'vehicle_not_present' end
    local mpos
    if not approval then
        -- Physical action: mechanic, customer and vehicle must share a routing bucket and be close together.
        mpos = self.chars.position(mSrc)
        local cpos = self.chars.position(cSrc)
        if not mpos or not cpos then return false, 'position_unavailable' end
        local px = self.cfg.Proximity
        if (vpos.bucket or 0) ~= (mpos.bucket or 0) or (cpos.bucket or 0) ~= (mpos.bucket or 0) then return false, 'wrong_bucket' end
        if dist(mpos, vpos) > px.mechanicToVehicle then return false, 'too_far' end
        if dist(cpos, vpos) > px.customerToVehicle then return false, 'customer_too_far' end
    end
    local okAccess = self.vehicles.canUse(cSrc, vehicleId, accessLevel or 'use')
    if okAccess ~= true then return false, 'no_access' end
    return true, { vehicleId = vehicleId, row = row, customerSrc = cSrc, mechanicSrc = mSrc, mechanicPos = mpos }
end

function Core:_ownerKey(row) return tostring(row.ownerType or 'character') .. ':' .. tostring(row.ownerCharacterId or '') end

-- ------------------------------------------------------------------- diagnosis

function Core:BeginDiagnosis(cid, woRef, netId)
    cid = tostring(cid)
    if not self.rate(cid, 'diagnose') then return false, 'rate_limited' end
    local wo = self.store.woGetByRef(tostring(woRef))
    if not wo or wo.mechanic_cid ~= cid then return false, 'not_found' end
    if not self:_has(cid, wo, 'quote') then return false, 'forbidden' end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        if wo.state ~= 'assigned' and wo.state ~= 'diagnosing' then return false, 'invalid_state' end
        local ok, v = self:_resolveVehicle(wo, netId, 'use')
        if not ok then return false, v end
        local cond, why = self.vehicles.condition(v.vehicleId, v.row)
        if not cond then return false, why or 'condition_unavailable' end
        local diag = self.pricing.diagnose(cond, self.cfg)
        local summary = self.pricing.summary(diag)
        local n = self.store.woCas(wo.reference, { 'assigned', 'diagnosing' }, {
            state = 'diagnosing', vehicle_id = v.vehicleId, vehicle_label = (v.row.label or v.row.model or ''):sub(1, 60),
            owner_snapshot = self:_ownerKey(v.row), diagnosis_json = self.encode(summary), updated_at = self.now() })
        if n ~= 1 then
            -- A re-scan in the same second changes no column, which some SQL drivers report as 0 rows: confirm the state before failing.
            local cur = self.store.woGetByRef(wo.reference)
            if not cur or (cur.state ~= 'assigned' and cur.state ~= 'diagnosing') then return false, 'invalid_state' end
        end
        if wo.state == 'assigned' then
            self.contracts.active(wo.contract_ref, cid)
            self:_event(nil, wo, 'diagnosis_started', cid, { vehicleId = v.vehicleId })
        end
        local fresh = self.store.woGetByRef(wo.reference)
        fresh.diagnosis = summary
        local req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
        return true, self:MechanicView(fresh)
    end)
end

-- ------------------------------------------------------------------------ quote

-- roadside / workshop policy (shared by repair quotes and tuning sessions)
function Core:_serviceLocation(wo, svc, v, approval)
    if svc.mode == 'workshop' then
        local shop = self:_shop(wo.business_id)
        local loc = shop and shop.location
        if not loc then return false, 'workshop_not_configured' end
        local radius = num(loc.radius, self.cfg.Proximity.workshopBay)
        if not approval and dist(v.mechanicPos, loc) > radius then return false, 'not_in_workshop' end
    else
        -- roadside / both: a shop that does not offer roadside may only serve from its own bay area.
        local shop = self:_shop(wo.business_id)
        if shop and shop.roadside == false then
            local loc = shop.location
            if svc.mode == 'roadside' or not loc then return false, 'roadside_disabled' end
            if not approval and dist(v.mechanicPos, loc) > num(loc.radius, self.cfg.Proximity.workshopBay) then return false, 'roadside_disabled' end
        end
    end
    return true
end

function Core:_buildQuote(wo, serviceId, netId, approval)
    local svc = self:_service(serviceId)
    if not svc then return false, 'invalid_service' end
    local ok, v = self:_resolveVehicle(wo, netId, svc.access == 'owner' and 'owner' or 'use', approval)
    if not ok then return false, v end
    if wo.owner_snapshot and wo.owner_snapshot ~= self:_ownerKey(v.row) then return false, 'ownership_changed' end
    local okL, whyL = self:_serviceLocation(wo, svc, v, approval)
    if not okL then return false, whyL end
    local cond, why = self.vehicles.condition(v.vehicleId, v.row)
    if not cond then return false, why or 'condition_unavailable' end
    local diag = self.pricing.diagnose(cond, self.cfg)
    local value = self.vehicles.value(v.row.model)
    local okQ, q = self.pricing.quote(self.cfg, serviceId, diag, value)
    if not okQ then return false, q end
    q.patch = self.pricing.buildPatch(q.parts, cond.conditionState)
    q.summary = self.pricing.summary(diag)
    return true, q, v, svc
end

function Core:CreateQuote(cid, woRef, serviceId, netId)
    cid = tostring(cid)
    if not self.rate(cid, 'quote') then return false, 'rate_limited' end
    local wo = self.store.woGetByRef(tostring(woRef))
    if not wo or wo.mechanic_cid ~= cid then return false, 'not_found' end
    if not self:_has(cid, wo, 'quote') then return false, 'forbidden' end
    local svcDef = self:_service(serviceId)
    if svcDef and not self:_has(cid, wo, svcDef.permission or 'service') then return false, 'forbidden' end
    -- A service whose price belongs to another owner (cm-tuning) is never quoted here: it needs the authorization session (StartTuning).
    if svcDef and svcDef.authority then return false, 'use_tuning_session' end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        if wo.state ~= 'diagnosing' or not wo.vehicle_id then return false, 'invalid_state' end
        local ok, q, v, svc = self:_buildQuote(wo, serviceId, netId)
        if not ok then return false, q end
        local now = self.now()
        local n = self.store.woCas(wo.reference, { 'diagnosing' }, {
            state = 'quoted', service_id = serviceId, quote_amount = q.amount, quote_json = self.encode({ lines = q.lines, base = q.base, parts = q.parts }),
            patch_json = self.encode(q.patch), quote_expires_at = now + self.cfg.Quote.validSeconds, updated_at = now })
        if n ~= 1 then return false, 'invalid_state' end
        self:_event(nil, wo, 'quote_created', cid, { service = serviceId, amount = q.amount, vehicleId = wo.vehicle_id })
        local biz = self.business.get(wo.business_type, wo.business_id)
        pcall(self.notify, wo.customer_cid, 'quote', { service = svc.label, amount = q.amount, business = biz and biz.label or 'Mechanic', category = svc.category })
        local req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
        return true, { amount = q.amount, service = svc.label, lines = q.lines }
    end)
end

-- ------------------------------------------------------------- tuning (cm-tuning owns the quote and the modification)

local TRANSIENT = { unavailable = true, billing_unavailable = true, busy = true, internal_error = true, service_unavailable = true, conflict_retry = true }

function Core:_isTuning(wo)
    local svc = wo and wo.service_id and self.cfg.Services[wo.service_id]
    return svc ~= nil and svc.authority == 'cm-tuning'
end

function Core:_tuningRef(wo)
    if not self:_isTuning(wo) or type(wo.patch_json) ~= 'string' or wo.patch_json == '' then return nil end
    local linked = self.decode(wo.patch_json)
    return type(linked) == 'table' and type(linked.tuning) == 'string' and linked.tuning or nil
end

-- Pre-payment only: the authorization/quote dies with the work order's quote (cm-tuning refuses once paid). Best effort: it also expires on its own.
function Core:_tuningDrop(wo)
    local ref = self.tuning and self:_tuningRef(wo)
    if ref then pcall(self.tuning.release, ref) end
end

function Core:_resetToDiagnosing(wo, now, event, detail)
    self:_tuningDrop(wo)
    self.store.woCas(wo.reference, { 'quoted' }, { state = 'diagnosing', quote_amount = false, service_id = false, patch_json = false, quote_json = false, updated_at = now })
    if event then self:_event(nil, wo, event, nil, detail) end
end

-- The mechanic opens cm-tuning's UI on the customer's vehicle. cm-tuning records a server-side authorization bound to this order; it
-- returns nothing the client could replay (the session is bound to the mechanic's character and the vehicle_id).
function Core:StartTuning(cid, woRef, netId, shop, mechanicSrc)
    cid = tostring(cid)
    if not self.tuning then return false, 'service_unavailable' end
    if not self.rate(cid, 'tuning') then return false, 'rate_limited' end
    local wo = self.store.woGetByRef(tostring(woRef))
    if not wo or wo.mechanic_cid ~= cid then return false, 'not_found' end
    local svc = self:_service('tuning_request')
    if not svc then return false, 'invalid_service' end
    if not self:_has(cid, wo, 'quote') or not self:_has(cid, wo, svc.permission or 'service') then return false, 'forbidden' end
    if type(shop) ~= 'string' or not (self.cfg.Tuning and self.cfg.Tuning.shops and self.cfg.Tuning.shops[shop]) then return false, 'invalid_service' end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        if wo.state ~= 'diagnosing' or not wo.vehicle_id then return false, 'invalid_state' end
        local ok, v = self:_resolveVehicle(wo, netId, svc.access == 'owner' and 'owner' or 'use')
        if not ok then return false, v end
        if wo.owner_snapshot and wo.owner_snapshot ~= self:_ownerKey(v.row) then return false, 'ownership_changed' end
        local okL, whyL = self:_serviceLocation(wo, svc, v, false)
        if not okL then return false, whyL end
        -- The invoice limit is cm-billing's provider policy (never duplicated here); no policy => fail closed.
        local limit = self.billing.limit and self.billing.limit()
        if not limit then return false, 'billing_unavailable' end
        local okA, auth = self.tuning.authorize({
            workOrder = wo.reference, mechanicCid = wo.mechanic_cid, customerCid = wo.customer_cid, businessType = wo.business_type,
            businessId = wo.business_id, vehicleId = v.vehicleId, shop = shop, maxAmount = limit })
        if not okA then return false, type(auth) == 'string' and auth or 'service_unavailable' end
        local now = self.now()
        local n = self.store.woCas(wo.reference, { 'diagnosing' }, { service_id = 'tuning_request', patch_json = self.encode({ tuning = auth.reference }), updated_at = now })
        if n ~= 1 then pcall(self.tuning.release, auth.reference); return false, 'invalid_state' end
        local okO, whyO = self.tuning.open(auth.reference, mechanicSrc, netId)
        if not okO then
            pcall(self.tuning.release, auth.reference)
            self.store.woCas(wo.reference, { 'diagnosing' }, { service_id = false, patch_json = false, updated_at = self.now() })
            return false, type(whyO) == 'string' and whyO or 'service_unavailable'
        end
        self:_event(nil, wo, 'tuning_authorized', cid, { shop = shop, vehicleId = v.vehicleId, tuning = auth.reference })
        return true, { opened = true }
    end)
end

-- cm-tuning recorded a server-priced proposal (local server event). Pull it through the trusted export and bind it to the order.
function Core:OnTuningQuoted(ref)
    if not self.tuning or type(ref) ~= 'string' or ref == '' then return false, 'invalid_request' end
    local okQ, q = self.tuning.quote(ref)
    if not okQ then return false, q end
    local wo = self.store.woGetByRef(tostring(q.workOrder))
    if not wo then pcall(self.tuning.release, ref); return false, 'not_found' end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        local svc = self:_service('tuning_request')
        local function reject(why) pcall(self.tuning.release, ref); return false, why end
        if not svc then return reject('invalid_service') end
        if wo.state ~= 'diagnosing' or wo.service_id ~= 'tuning_request' or self:_tuningRef(wo) ~= ref then return reject('binding_mismatch') end
        if wo.mechanic_cid ~= q.mechanicCid or wo.customer_cid ~= q.customerCid or wo.business_type ~= q.businessType or wo.business_id ~= q.businessId
            or tonumber(wo.vehicle_id) ~= tonumber(q.vehicleId) then return reject('binding_mismatch') end
        if not self:_has(wo.mechanic_cid, wo, 'quote') or not self:_has(wo.mechanic_cid, wo, svc.permission or 'service') then return reject('forbidden') end
        local amount = tonumber(q.amount)
        local limit = self.billing.limit and self.billing.limit()
        if not limit then return reject('billing_unavailable') end
        if not amount or amount < 1 or amount > limit then return reject('amount_over_limit') end
        local now = self.now()
        local n = self.store.woCas(wo.reference, { 'diagnosing' }, {
            state = 'quoted', quote_amount = math.floor(amount), quote_json = self.encode({ tuning = true, shop = q.shop, detail = q.description, revision = q.revision }),
            quote_expires_at = now + self.cfg.Quote.validSeconds, updated_at = now })
        if n ~= 1 then return reject('invalid_state') end
        self:_event(nil, wo, 'quote_created', wo.mechanic_cid, { service = 'tuning_request', amount = math.floor(amount), vehicleId = wo.vehicle_id, tuning = ref, revision = q.revision })
        local biz = self.business.get(wo.business_type, wo.business_id)
        pcall(self.notify, wo.customer_cid, 'quote', { service = svc.label, amount = math.floor(amount), business = biz and biz.label or 'Mechanic', category = svc.category, detail = q.description })
        pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'quoted', work = wo.reference })
        local req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
        return true, { amount = math.floor(amount) }
    end)
end

-- The customer's pending quote (their own order only).
function Core:PendingQuote(cid)
    local wo = self.store.woActiveByCustomer(tostring(cid), 'quoted')
    if not wo then return nil end
    local svc = self.cfg.Services[wo.service_id or '']
    local biz = self.business.get(wo.business_type, wo.business_id)
    return { service = svc and svc.label or 'Service', amount = wo.quote_amount, business = biz and biz.label or 'Mechanic', expiresIn = math.max(0, (wo.quote_expires_at or 0) - self.now()) }
end

-- ------------------------------------------------------------ customer response

-- The caller is the customer; the order is resolved from THEIR character id, never from client input.
function Core:RespondQuote(cid, approve)
    cid = tostring(cid)
    if not self.rate(cid, 'respond') then return false, 'rate_limited' end
    local wo = self.store.woActiveByCustomer(cid, 'quoted')
    if not wo then return false, 'not_found' end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        if wo.state ~= 'quoted' then return false, 'invalid_state' end
        local now = self.now()
        if (wo.quote_expires_at or 0) < now then
            self:_tuningDrop(wo)
            self.store.woCas(wo.reference, { 'quoted' }, { state = 'diagnosing', quote_amount = false, service_id = false, patch_json = false, quote_json = false, updated_at = now })
            return false, 'quote_expired'
        end
        if approve ~= true then
            local declines = (tonumber(wo.declines) or 0) + 1
            self:_tuningDrop(wo)
            self.store.woCas(wo.reference, { 'quoted' }, { state = 'diagnosing', declines = declines, quote_amount = false, service_id = false, patch_json = false, quote_json = false, updated_at = now })
            self:_event(nil, wo, 'quote_declined', cid, { declines = declines })
            pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'declined', work = wo.reference })
            if declines >= self.cfg.Quote.maxDeclines then
                self:_cancelWork(wo, 'declined_too_often', true)
            end
            return true, { declined = true }
        end
        -- Approve: re-derive the price server-side; a higher fresh price invalidates the quote (the customer never pays more than quoted).
        local netId = self.vehicles.netIdOf(wo.vehicle_id)
        if not netId then return false, 'vehicle_not_present' end
        if self:_isTuning(wo) then
            -- cm-tuning re-prices against the CURRENT vehicle: the customer never pays for a quote that no longer describes it.
            local ref = self:_tuningRef(wo)
            local svc = self.cfg.Services[wo.service_id]
            local okV, v = self:_resolveVehicle(wo, netId, svc.access == 'owner' and 'owner' or 'use', true)
            if not okV then
                if v == 'no_access' or v == 'vehicle_protected' then self:_resetToDiagnosing(wo, now) end
                return false, v
            end
            if wo.owner_snapshot and wo.owner_snapshot ~= self:_ownerKey(v.row) then
                self:_resetToDiagnosing(wo, now, 'quote_changed', { reason = 'ownership_changed' })
                return false, 'ownership_changed'
            end
            local okT, t
            if ref and self.tuning then okT, t = self.tuning.validate(ref) end
            if not okT or tonumber(t and t.amount) ~= tonumber(wo.quote_amount) then
                if okT == nil or (not okT and TRANSIENT[t]) then return false, 'service_unavailable' end
                self:_resetToDiagnosing(wo, now, 'quote_changed', { was = wo.quote_amount, reason = okT and 'amount' or tostring(t) })
                return false, 'quote_changed'
            end
        else
        local ok, q = self:_buildQuote(wo, wo.service_id, netId, true)
        if not ok then
            if q == 'ownership_changed' or q == 'no_access' or q == 'vehicle_protected' then
                self.store.woCas(wo.reference, { 'quoted' }, { state = 'diagnosing', quote_amount = false, service_id = false, patch_json = false, quote_json = false, updated_at = now })
            end
            return false, q
        end
        if q.amount > tonumber(wo.quote_amount) then
            self.store.woCas(wo.reference, { 'quoted' }, { state = 'diagnosing', quote_amount = false, service_id = false, patch_json = false, quote_json = false, updated_at = now })
            self:_event(nil, wo, 'quote_changed', cid, { was = wo.quote_amount, now = q.amount })
            return false, 'quote_changed'
        end
        end
        local n = self.store.woCas(wo.reference, { 'quoted' }, { state = 'awaiting_payment', approved_at = now, updated_at = now })
        if n ~= 1 then return false, 'invalid_state' end
        self:_event(nil, wo, 'quote_approved', cid, { amount = wo.quote_amount })
        wo.state = 'awaiting_payment'
        local okI, why = self:_ensureInvoice(wo)
        if not okI then
            -- Nothing was billed (idempotency key unchanged): reopen the quote so the customer may retry.
            self.store.woCas(wo.reference, { 'awaiting_payment' }, { state = 'quoted', updated_at = self.now() })
            return false, why
        end
        local req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
        return true, { approved = true, invoice = true }
    end)
end

-- Create (or re-resolve) the single invoice for this order attempt. Idempotent by key.
function Core:_ensureInvoice(wo)
    wo = self.store.woGetByRef(wo.reference)
    if wo.invoice_ref and wo.invoice_ref ~= '' then return true, wo.invoice_ref end
    local svc = self.cfg.Services[wo.service_id]
    local biz = self.business.get(wo.business_type, wo.business_id)
    if not svc or not biz or not biz.owned then return false, 'business_unavailable' end
    local key = ('mechinv:%s:%d'):format(wo.reference, tonumber(wo.invoice_attempt) or 1)
    local detail, tuningRef
    if svc.authority == 'cm-tuning' then
        tuningRef = self:_tuningRef(wo)
        if not tuningRef then return false, 'business_unavailable' end
        local qj = self.decode(wo.quote_json or '')
        detail = type(qj) == 'table' and type(qj.detail) == 'string' and qj.detail ~= '' and qj.detail or nil
    end
    local ok, res = self.billing.create({
        recipientCharacterId = wo.customer_cid, amount = tonumber(wo.quote_amount), label = ('Vehicle service: %s'):format(svc.label):sub(1, 80),
        description = (detail and ('%s (%s) for work order %s'):format(svc.label, detail, wo.reference) or ('%s for work order %s'):format(svc.label, wo.reference)):sub(1, 400),
        issuerType = 'business', issuerLabel = (biz.label or 'Mechanic'):sub(1, 64), issuerCharacterId = wo.mechanic_cid,
        issuerEntityId = wo.business_type .. ':' .. wo.business_id,
        destination = { type = 'business', id = wo.business_type .. ':' .. wo.business_id },
        expiresInSeconds = self.cfg.Quote.invoiceExpirySeconds, idempotencyKey = key,
        metadata = { ['mechanic.work'] = wo.reference, ['mechanic.service'] = wo.service_id, ['mechanic.tuning'] = tuningRef },
    })
    if ok ~= true and res == 'amount_exceeds_provider_limit' then return false, 'amount_over_limit' end   -- stable billing reason, surfaced to the mechanic
    if ok ~= true or type(res) ~= 'table' or not res.reference then return false, 'billing_unavailable' end
    self.store.woCas(wo.reference, { 'awaiting_payment' }, { invoice_ref = res.reference, invoice_key = key, updated_at = self.now() })
    if tuningRef and self.tuning then pcall(self.tuning.bind, tuningRef, res.reference) end   -- idempotent; reconcile repeats it until cm-tuning confirms
    self:_event(nil, wo, 'invoice_created', wo.mechanic_cid, { reference = res.reference, amount = wo.quote_amount, business = wo.business_type .. ':' .. wo.business_id }, 'invoice:' .. key)
    self:_mirrorAdmin('mechanic_invoice_created', { work = wo.reference, invoice = res.reference, amount = wo.quote_amount, business = wo.business_type .. ':' .. wo.business_id })
    pcall(self.notify, wo.customer_cid, 'invoice', { amount = wo.quote_amount })
    return true, res.reference
end

function Core:_voidInvoice(wo)
    if not wo.invoice_ref or wo.invoice_ref == '' then return true end
    local ok = self.billing.void(wo.invoice_ref, 'mechanic_cancel')
    if ok == true then self:_tuningDrop(wo); return true end
    local st = self.billing.status(wo.invoice_ref)
    if st == 'voided' or st == 'expired' then self:_tuningDrop(wo); return true end
    return false
end

-- ---------------------------------------------------------------------- cancel

-- Cancel an order that has no paid invoice. returnToBoard = also end the request (customer/mechanic decision) instead of re-opening it.
function Core:_cancelWork(wo, reason, endRequest)
    wo = self.store.woGetByRef(wo.reference)
    if not wo or not OPEN_WO[wo.state] or wo.state == 'servicing' then return false, 'invalid_state' end
    if wo.state == 'awaiting_payment' and not self:_voidInvoice(wo) then return false, 'invoice_settling' end
    local now = self.now()
    local n = self.store.woCas(wo.reference, { 'assigned', 'diagnosing', 'quoted', 'awaiting_payment' },
        { state = 'cancelled', active_key = false, end_reason = reason, updated_at = now })
    if n ~= 1 then return false, 'invalid_state' end
    self:_tuningDrop(wo)
    self:_event(nil, wo, 'work_cancelled', nil, { reason = reason })
    local req = self.store.reqGetByRef(wo.request_ref)
    if endRequest then
        self.contracts.cancel(self.cfg.ContractType, wo.request_ref, reason)
        self.store.reqCas(wo.request_ref, { 'open', 'assigned' }, { status = 'cancelled', active_key = false, end_reason = reason, updated_at = now })
        self:_event(req, nil, 'request_cancelled', nil, { reason = reason })
    else
        self.contracts.release(wo.contract_ref, wo.mechanic_cid, reason)
        self.store.reqCas(wo.request_ref, { 'assigned' }, { status = 'open', work_order_ref = false, updated_at = now })
    end
    pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'cancelled', work = wo.reference })
    req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
    return true
end

-- Mechanic walks away before an invoice is paid: the request goes back to the board.
function Core:AbandonWork(cid, woRef)
    cid = tostring(cid)
    if not self.rate(cid, 'cancel') then return false, 'rate_limited' end
    local wo = self.store.woGetByRef(tostring(woRef))
    if not wo or wo.mechanic_cid ~= cid then return false, 'not_found' end
    return self:_lock('wo:' .. wo.reference, function() return self:_cancelWork(wo, 'mechanic_abandon', false) end)
end

-- ----------------------------------------------------------------- reconcile

-- Payment detection, invoice expiry, commit recovery and stale cleanup. Idempotent; safe to run on any schedule and after a restart.
function Core:Reconcile()
    local now = self.now()
    local stats = { paid = 0, expired = 0, committed = 0, cancelled = 0, published = 0 }
    for _, wo in ipairs(self.store.woListOpen(100)) do
        self:_lock('wo:' .. wo.reference, function()
            wo = self.store.woGetByRef(wo.reference)
            if not wo or not OPEN_WO[wo.state] then return end
            self:_reconcileOne(wo, now, stats)
        end)
    end
    for _, req in ipairs(self.store.reqListOpen(100)) do
        self:_lock('req:' .. req.reference, function() self:_reconcileRequest(req, now, stats) end)
    end
    return true, stats
end

function Core:_online(cid, now)
    if self.chars.sourceOf(cid) then self.offlineSince[cid] = nil; return true, 0 end
    self.offlineSince[cid] = self.offlineSince[cid] or now
    return false, now - self.offlineSince[cid]
end

function Core:_reconcileOne(wo, now, stats)
    local q = self.cfg.Quote
    if wo.state == 'awaiting_payment' then
        if not wo.invoice_ref or wo.invoice_ref == '' then
            -- crash window between approval and invoice creation: the idempotency key makes this safe to repeat
            local ok = self:_ensureInvoice(wo)
            if not ok and now - (tonumber(wo.updated_at) or now) > q.invoiceExpirySeconds then
                self.store.woCas(wo.reference, { 'awaiting_payment' }, { state = 'quoted', updated_at = now })
            end
            return
        end
        local isTuning = self:_isTuning(wo) and self.tuning ~= nil
        local tuningRef = isTuning and self:_tuningRef(wo) or nil
        if isTuning and tuningRef then
            -- crash window between invoice creation and cm-tuning's binding: idempotent, repeated until confirmed
            local okB, whyB = self.tuning.bind(tuningRef, wo.invoice_ref)
            if not okB and whyB == 'invoice_conflict' then self:_event(nil, wo, 'tuning_bind_conflict', nil, { invoice = wo.invoice_ref }, 'bind_conflict') end
        end
        local st = self.billing.status(wo.invoice_ref)
        if st == 'paid' and isTuning then
            -- cm-tuning verifies the payment with cm-billing itself. Money is already taken: a transient failure only delays (never refunds, never cancels).
            local okP, whyP = false, 'no_reference'
            if tuningRef then okP, whyP = self.tuning.paid(tuningRef, wo.invoice_ref) end
            if not okP then
                if TRANSIENT[whyP] then return end
                self:_event(nil, wo, 'tuning_paid_mismatch', nil, { invoice = wo.invoice_ref, reason = tostring(whyP) }, 'paid_mismatch')
                self:_mirrorAdmin('mechanic_tuning_paid_mismatch', { work = wo.reference, invoice = wo.invoice_ref, reason = tostring(whyP) })
            end
        end
        if st == 'paid' then
            local n = self.store.woCas(wo.reference, { 'awaiting_payment' }, { state = 'servicing', paid_at = now, updated_at = now })
            if n == 1 then
                stats.paid = stats.paid + 1
                self:_event(nil, wo, 'payment_confirmed', wo.customer_cid, { invoice = wo.invoice_ref, amount = wo.quote_amount }, 'paid')
                pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'paid', work = wo.reference })
                local req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
            end
        elseif st == 'voided' or st == 'expired' then
            if isTuning then self:_tuningDrop(wo) end
            local n = self.store.woCas(wo.reference, { 'awaiting_payment' }, {
                state = 'diagnosing', invoice_ref = false, invoice_key = false, invoice_attempt = (tonumber(wo.invoice_attempt) or 1) + 1,
                quote_amount = false, service_id = false, patch_json = false, quote_json = false, updated_at = now })
            if n == 1 then
                stats.expired = stats.expired + 1
                self:_event(nil, wo, 'invoice_' .. st, nil, { invoice = wo.invoice_ref })
                pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'invoice_' .. st, work = wo.reference })
                local req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
            end
        end
        return
    end
    if wo.state == 'servicing' then
        local due = (wo.commit_state == 'committing')
            or (now - (tonumber(wo.paid_at) or now) >= self.cfg.Commit.autoCommitAfterSeconds)
        if wo.commit_state ~= 'committed' and due and now >= (tonumber(wo.next_commit_at) or 0) then
            local ok = self:_commit(wo, 'recovery')
            if ok then stats.committed = stats.committed + 1 end
        end
        return
    end
    if wo.state == 'quoted' and (wo.quote_expires_at or 0) < now then
        self:_tuningDrop(wo)
        self.store.woCas(wo.reference, { 'quoted' }, { state = 'diagnosing', quote_amount = false, service_id = false, patch_json = false, quote_json = false, updated_at = now })
        return
    end
    -- Pre-invoice orders: an absent mechanic returns the request to the board, an absent customer ends it.
    if PRE_INVOICE[wo.state] then
        local mOn, mOff = self:_online(wo.mechanic_cid, now)
        if not mOn and mOff >= q.mechanicOfflineSeconds then
            if self:_cancelWork(wo, 'mechanic_offline', false) then stats.cancelled = stats.cancelled + 1 end
            return
        end
        local cOn, cOff = self:_online(wo.customer_cid, now)
        if not cOn and cOff >= self.cfg.Request.customerOfflineSeconds then
            if self:_cancelWork(wo, 'customer_offline', true) then stats.cancelled = stats.cancelled + 1 end
            return
        end
        if now - (tonumber(wo.updated_at) or now) > q.staleOrderSeconds then
            if self:_cancelWork(wo, 'stale', false) then stats.cancelled = stats.cancelled + 1 end
        end
    end
end

function Core:_reconcileRequest(req, now, stats)
    req = self.store.reqGetByRef(req.reference)
    if not req or not OPEN_REQ[req.status] then return end
    if not req.contract_ref then
        if now - (tonumber(req.created_at) or now) > self.cfg.Request.publishRetrySeconds then
            if self.store.reqCas(req.reference, { 'open' }, { status = 'expired', active_key = false, end_reason = 'unpublished', updated_at = now }) == 1 then
                self:_event(req, nil, 'request_expired', nil, { reason = 'unpublished' }); self:_push(req)
            end
        elseif self:_publish(req) then stats.published = stats.published + 1 end
        return
    end
    if req.status == 'open' then
        local on, off = self:_online(req.customer_cid, now)
        if not on and off >= self.cfg.Request.customerOfflineSeconds then
            self.contracts.cancel(self.cfg.ContractType, req.reference, 'customer_offline')
            if self.store.reqCas(req.reference, { 'open' }, { status = 'cancelled', active_key = false, end_reason = 'customer_offline', updated_at = now }) == 1 then
                self:_event(req, nil, 'request_cancelled', nil, { reason = 'customer_offline' })
            end
            return
        end
    end
    local ok, c = self.contracts.get(self.cfg.ContractType, req.reference)
    if ok == true and type(c) == 'table' and (c.status == 'cancelled' or c.status == 'failed' or (c.status == 'completed' and c.completionMode == 'fallback')) then
        -- Broker ended it: only valid when no paid work depends on it.
        local wo = req.work_order_ref and self.store.woGetByRef(req.work_order_ref) or nil
        if wo and OPEN_WO[wo.state] then
            if wo.state ~= 'awaiting_payment' and wo.state ~= 'servicing' then self:_cancelWork(wo, 'contract_ended', true) end
        else
            if self.store.reqCas(req.reference, { 'open', 'assigned' }, { status = 'expired', active_key = false, end_reason = 'contract_' .. tostring(c.status), updated_at = now }) == 1 then
                self:_event(req, nil, 'request_expired', nil, { contract = c.status }); self:_push(req)
            end
        end
    end
end

-- ------------------------------------------------------------- physical service

function Core:StartService(cid, woRef, netId)
    cid = tostring(cid)
    if not self.rate(cid, 'service') then return false, 'rate_limited' end
    local wo = self.store.woGetByRef(tostring(woRef))
    if not wo or wo.mechanic_cid ~= cid then return false, 'not_found' end
    if not self:_has(cid, wo, 'service') then return false, 'forbidden' end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        if wo.state == 'awaiting_payment' then self:_reconcileOne(wo, self.now(), {}); wo = self.store.woGetByRef(wo.reference) end
        if wo.state ~= 'servicing' or wo.commit_state == 'committed' then return false, 'invalid_state' end
        local ok, v = self:_resolveVehicle(wo, netId, 'use')
        if not ok then return false, v end
        local svc = self.cfg.Services[wo.service_id]
        local now = self.now()
        if not wo.service_started_at then
            self.store.woCas(wo.reference, { 'servicing' }, { service_started_at = now, updated_at = now })
            wo.service_started_at = now
        end
        return true, { durationSeconds = svc and svc.durationSeconds or 10, startedAt = wo.service_started_at }
    end)
end

function Core:FinishService(cid, woRef, netId)
    cid = tostring(cid)
    if not self.rate(cid, 'service') then return false, 'rate_limited' end
    local wo = self.store.woGetByRef(tostring(woRef))
    if not wo or wo.mechanic_cid ~= cid then return false, 'not_found' end
    if not self:_has(cid, wo, 'complete') then return false, 'forbidden' end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        if wo.state == 'completed' then return true, { replayed = true } end
        if wo.state == 'awaiting_payment' then self:_reconcileOne(wo, self.now(), {}); wo = self.store.woGetByRef(wo.reference) end
        if wo.state ~= 'servicing' then return false, wo.state == 'awaiting_payment' and 'payment_pending' or 'invalid_state' end
        if not wo.service_started_at then return false, 'service_not_started' end
        local svc = self.cfg.Services[wo.service_id]
        local need = (svc and svc.durationSeconds or 0) - self.cfg.Commit.durationToleranceSeconds
        if self.now() - wo.service_started_at < need then return false, 'too_early' end
        local ok, v = self:_resolveVehicle(wo, netId, 'use')
        if not ok then return false, v end
        local done, why = self:_commit(wo, 'mechanic')
        if not done then return false, why end
        return true, { completed = true }
    end)
end

-- Exactly-once service application. Pay-before-mutate: only reachable from state 'servicing' (invoice confirmed paid).
-- Patches hold ABSOLUTE target values, so a replay after a crash writes the same state and cannot repair "twice".
function Core:_commit(wo, by)
    wo = self.store.woGetByRef(wo.reference)
    if wo.state == 'completed' or wo.commit_state == 'committed' then return true, 'replayed' end
    if wo.state ~= 'servicing' then return false, 'invalid_state' end
    local now = self.now()
    if wo.commit_state == 'none' then
        local n = self.store.woCas(wo.reference, { 'servicing' }, { commit_state = 'committing', commit_started_at = now, updated_at = now }, { commit_state = 'none' })
        if n ~= 1 then return false, 'busy' end
        self:_event(nil, wo, 'service_commit_started', by, nil, 'commit_started')
    end
    local patch = {}
    if wo.patch_json and wo.patch_json ~= '' then patch = self.decode and self.decode(wo.patch_json) or {} end
    patch = type(patch) == 'table' and patch or {}
    local svcDef = self.cfg.Services[wo.service_id or '']
    local isTuning = svcDef ~= nil and svcDef.authority == 'cm-tuning'
    local okApply = true
    if isTuning then
        -- cm-tuning applies the approved modification once (idempotent by authorization reference; already-installed counts as done).
        local ref = type(patch.tuning) == 'string' and patch.tuning or nil
        okApply = ref ~= nil and self.tuning ~= nil and self.tuning.execute(ref) == true
    elseif next(patch) ~= nil then
        okApply = self.vehicles.apply(wo.vehicle_id, patch)
    end
    if isTuning or next(patch) ~= nil then
        if okApply ~= true then
            local attempts = (tonumber(wo.commit_attempts) or 0) + 1
            local delay = math.min(600, self.cfg.Commit.retryBaseSeconds * (2 ^ (attempts - 1)))
            self.store.woCas(wo.reference, { 'servicing' }, { commit_attempts = attempts, next_commit_at = now + math.floor(delay), updated_at = now })
            self:_event(nil, wo, 'service_commit_failed', by, { attempt = attempts, vehicleId = wo.vehicle_id })
            if attempts >= self.cfg.Commit.maxAttempts then
                self:_mirrorAdmin('mechanic_commit_stuck', { work = wo.reference, vehicleId = wo.vehicle_id, attempts = attempts })
            end
            return false, 'vehicle_service_failed'
        end
    end
    local n = self.store.woCas(wo.reference, { 'servicing' }, { state = 'completed', commit_state = 'committed', active_key = false, completed_at = now, updated_at = now })
    if n ~= 1 then return true, 'replayed' end
    local first = self:_event(nil, wo, 'service_committed', by, { service = wo.service_id, vehicleId = wo.vehicle_id, amount = wo.quote_amount }, 'committed')
    if first then
        self:_mirrorAdmin('mechanic_service_committed', { work = wo.reference, vehicleId = wo.vehicle_id, service = wo.service_id, amount = wo.quote_amount, business = wo.business_type .. ':' .. wo.business_id })
    end
    self:_closeContract(wo)
    return true
end

-- Order is committed: end the request and complete the contract. No reward exists, so `rewardable` is ignored by design.
function Core:_closeContract(wo)
    local now = self.now()
    local ok = self.contracts.complete(wo.contract_ref, wo.mechanic_cid, { payload = { work = wo.reference } })
    if ok ~= true then self.contracts.cancel(self.cfg.ContractType, wo.request_ref, 'work_done') end
    self.store.reqCas(wo.request_ref, { 'open', 'assigned' }, { status = 'completed', active_key = false, end_reason = 'completed', updated_at = now })
    self:_event(self.store.reqGetByRef(wo.request_ref), wo, 'request_completed', wo.mechanic_cid, nil, 'request_completed')
    local req = self.store.reqGetByRef(wo.request_ref); if req then self:_push(req) end
    pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'completed', work = wo.reference })
end

-- ------------------------------------------------------- broker source callbacks

-- All of these are called by cm-contracts (the export layer checks GetInvokingResource() == 'cm-contracts').
function Core:SourceComplete(ctx)
    local req = self.store.reqGetByRef(tostring(ctx.sourceReference))
    if not req then return false, 'source_terminal' end
    local wo = req.work_order_ref and self.store.woGetByRef(req.work_order_ref) or nil
    if req.status == 'completed' then return true, { replayed = true } end
    if req.status == 'cancelled' or req.status == 'expired' then return false, 'source_terminal' end
    if not wo or wo.state ~= 'completed' or wo.commit_state ~= 'committed' then return false, 'work_not_finished' end
    if tostring(ctx.workerCharacterId) ~= wo.mechanic_cid then return false, 'not_assigned_worker' end
    self.store.reqCas(req.reference, { 'open', 'assigned' }, { status = 'completed', active_key = false, end_reason = 'completed', updated_at = self.now() })
    return true
end

-- Deadline reached with no completed work. NEVER repairs the vehicle: an unserved request is cancelled and no worker is rewarded.
function Core:SourceFallback(ctx)
    local ref = tostring(ctx.sourceReference)
    local req = self.store.reqGetByRef(ref)
    if not req then return false, 'source_terminal' end
    return self:_lock('req:' .. ref, function()
        req = self.store.reqGetByRef(ref)
        if not OPEN_REQ[req.status] then return false, 'source_terminal' end
        local wo = req.work_order_ref and self.store.woGetByRef(req.work_order_ref) or nil
        local now = self.now()
        if wo and OPEN_WO[wo.state] then
            local live = wo.state == 'awaiting_payment' or wo.state == 'servicing'
                or (wo.state ~= 'assigned' and now - (tonumber(wo.updated_at) or now) <= self.cfg.Quote.staleOrderSeconds)
            if live then return false, 'work_in_progress' end -- the broker retries with backoff; the order resolves itself
            self:_cancelWork(wo, 'timeout', true)
            return false, 'source_terminal'
        end
        if self.store.reqCas(ref, { 'open', 'assigned' }, { status = 'expired', active_key = false, end_reason = 'no_mechanic', updated_at = now }) == 1 then
            self:_event(req, nil, 'request_expired', nil, { reason = 'no_mechanic' }, 'expired')
            req.status = 'expired'; self:_push(req)
        end
        return false, 'source_terminal'
    end)
end

function Core:SourceCancel(ctx)
    local ref = tostring(ctx.sourceReference)
    local req = self.store.reqGetByRef(ref)
    if not req then return false, 'source_terminal' end
    return self:_lock('req:' .. ref, function()
        local wo = req.work_order_ref and self.store.woGetByRef(req.work_order_ref) or nil
        if wo and (wo.state == 'servicing' or wo.state == 'awaiting_payment') then
            if wo.state == 'servicing' then return false, 'invalid_state' end
            if not self:_voidInvoice(wo) then return false, 'invalid_state' end
        end
        if wo and OPEN_WO[wo.state] then
            self:_tuningDrop(wo)
            self.store.woCas(wo.reference, { 'assigned', 'diagnosing', 'quoted', 'awaiting_payment' }, { state = 'cancelled', active_key = false, end_reason = 'admin_cancel', updated_at = self.now() })
            self:_event(req, wo, 'work_cancelled', nil, { reason = 'admin_cancel' })
        end
        self.store.reqCas(ref, { 'open', 'assigned' }, { status = 'cancelled', active_key = false, end_reason = 'admin_cancel', updated_at = self.now() })
        self:_event(req, nil, 'request_cancelled', nil, { by = 'contract_cancel' })
        local fresh = self.store.reqGetByRef(ref); if fresh then self:_push(fresh) end
        return true
    end)
end

-- Optional broker notices. 'released' = the claim lapsed or was released; pre-invoice work returns to the board.
function Core:SourceEvent(ctx)
    if ctx.event ~= 'released' then return true end
    local req = self.store.reqGetByRef(tostring(ctx.sourceReference))
    if not req or req.status ~= 'assigned' then return true end
    local wo = req.work_order_ref and self.store.woGetByRef(req.work_order_ref) or nil
    if not wo or not OPEN_WO[wo.state] then return true end
    if wo.state == 'servicing' or wo.state == 'awaiting_payment' then return true end -- paid/pending work survives the lapse; reconcile completes it
    local now = self.now()
    self:_tuningDrop(wo)
    self.store.woCas(wo.reference, { 'assigned', 'diagnosing', 'quoted' }, { state = 'cancelled', active_key = false, end_reason = 'claim_released', updated_at = now })
    self.store.reqCas(req.reference, { 'assigned' }, { status = 'open', work_order_ref = false, updated_at = now })
    self:_event(req, wo, 'work_cancelled', nil, { reason = 'claim_released' })
    pcall(self.notify, wo.mechanic_cid, 'mechanic', { kind = 'cancelled', work = wo.reference })
    local fresh = self.store.reqGetByRef(req.reference); if fresh then self:_push(fresh) end
    return true
end

-- ----------------------------------------------------------------------- admin

function Core:AdminInspect(ref)
    ref = tostring(ref)
    local req = self.store.reqGetByRef(ref)
    local wo = self.store.woGetByRef(ref)
    if not req and wo then req = self.store.reqGetByRef(wo.request_ref) end
    if not wo and req and req.work_order_ref then wo = self.store.woGetByRef(req.work_order_ref) end
    if not req then return false, 'not_found' end
    return true, { request = req, workOrder = wo, events = self.store.eventList(req.reference, 40) }
end

function Core:AdminCancel(ref, adminLabel)
    local ok, info = self:AdminInspect(ref)
    if not ok then return false, 'not_found' end
    local req, wo = info.request, info.workOrder
    return self:_lock('req:' .. req.reference, function()
        if wo and OPEN_WO[wo.state] then
            if wo.state == 'servicing' then return false, 'paid_use_reconcile' end
            local okC, why = self:_cancelWork(wo, 'admin_cancel', true)
            if not okC then return false, why end
        else
            self.contracts.cancel(self.cfg.ContractType, req.reference, 'admin_cancel')
            self.store.reqCas(req.reference, { 'open', 'assigned' }, { status = 'cancelled', active_key = false, end_reason = 'admin_cancel', updated_at = self.now() })
        end
        self:_event(req, wo, 'admin_cancel', adminLabel or 'admin', nil)
        self:_mirrorAdmin('mechanic_admin_cancel', { request = req.reference, by = adminLabel })
        return true
    end)
end

-- Reconcile one order immediately (paid but not committed, stuck commit, ...). Applies the paid service server-side when owed.
function Core:AdminReconcile(ref, adminLabel)
    local ok, info = self:AdminInspect(ref)
    if not ok then return false, 'not_found' end
    local wo = info.workOrder
    if not wo then return true, { nothing = true } end
    return self:_lock('wo:' .. wo.reference, function()
        wo = self.store.woGetByRef(wo.reference)
        if wo.state == 'servicing' and wo.commit_state ~= 'committed' then
            self.store.woCas(wo.reference, { 'servicing' }, { next_commit_at = 0 })
            local done, why = self:_commit(self.store.woGetByRef(wo.reference), 'admin')
            self:_event(info.request, wo, 'admin_reconcile', adminLabel or 'admin', { result = done and 'committed' or why })
            return done, why
        end
        self:_reconcileOne(wo, self.now(), {})
        self:_event(info.request, wo, 'admin_reconcile', adminLabel or 'admin', nil)
        return true
    end)
end

-- ------------------------------------------------------------ disconnect hooks

function Core:OnMechanicDropped(cid)
    self.offlineSince[tostring(cid)] = self.offlineSince[tostring(cid)] or self.now()
    return self.contracts.disconnected(tostring(cid))
end

function Core:OnCharacterJoined(cid) self.offlineSince[tostring(cid)] = nil end
