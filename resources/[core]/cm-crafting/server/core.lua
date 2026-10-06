-- cm-crafting core: recipe + station registry and the craft SESSION lifecycle. Dependency-injected (no FiveM natives, no SQL).
--
--   content server -> RegisterRecipe/Station -> Begin (validate, snapshot the transaction, start the server timer)
--     -> Complete (timer reached, final validation) -> commit_started -> inventory ExecuteCraftTransaction (atomic + idempotent by reference)
--     -> completed.  Inputs are NOT consumed at start (no reservations): the final atomic commit revalidates everything.
--
-- The core never removes or adds items itself. All settlement goes through the injected `inventory` contract; when that contract is not
-- available, Begin/Complete fail closed. Identity is the character id; sources are never stored.
CMCrafting = CMCrafting or {}
local Core = {}
Core.__index = Core
CMCrafting.Core = Core

local REF_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local OPEN = { 'active', 'committing' }

local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function isInt(v) return math.type(v) == 'integer' end
local function isCid(v) return type(v) == 'string' and #v >= 1 and #v <= 20 and v:match('^%d+$') ~= nil end
local function isRef(v) return type(v) == 'string' and #v >= 6 and #v <= 24 and v:match('^[%w%-]+$') ~= nil end
local function isItem(v) return type(v) == 'string' and #v >= 2 and #v <= 48 and v:match('^[%w_%-]+$') ~= nil end
local function dist(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0) return math.sqrt(dx * dx + dy * dy + dz * dz) end

function Core.New(deps)
    assert(type(deps) == 'table' and type(deps.cfg) == 'table' and deps.store, 'cm-crafting core needs cfg + store')
    local self = setmetatable({}, Core)
    self.cfg, self.store = deps.cfg, deps.store
    self.now = deps.now or os.time
    self.rand = deps.rand or math.random
    self.encode = deps.encode or function() return '' end
    self.decode = deps.decode or function() return nil end
    self.chars = deps.chars            -- sourceOf(cid)->src|nil, position(src)->{x,y,z,bucket}|nil
    self.items = deps.items            -- exists(name)->bool|nil, validateMetadata(name, meta)->bool
    self.inventory = deps.inventory    -- ready()->bool, validate(cid, tx), execute(ref, cid, tx), status(ref)
    self.owners = deps.owners or { started = function() return true end, call = function() return false, 'unavailable' end }
    self.audit = deps.audit or function() end
    self.rate = deps.rate or function() return true end
    self.log = deps.log or function() end
    self.recipes, self.stations, self.locks = {}, {}, {}
    self.offlineSince, self.ownerDownSince, self.unknownSince = {}, {}, {}
    return self
end

function Core:_ref()
    local s = {}
    for i = 1, 8 do local n = self.rand(1, #REF_CHARS); s[i] = REF_CHARS:sub(n, n) end
    return 'CRAFT-' .. table.concat(s)
end

function Core:_lock(key, fn)
    if self.locks[key] then return false, 'busy' end
    self.locks[key] = true
    local res = table.pack(pcall(fn))
    self.locks[key] = nil
    if not res[1] then self.log('error', tostring(res[2])); return false, 'internal_error' end
    return table.unpack(res, 2, res.n)
end

function Core:_event(s, kind, detail, key)
    return self.store.eventInsert({ session_ref = s.reference, recipe_id = s.recipe_id, kind = kind, character_id = s.character_id,
        key = key and (s.reference .. ':' .. key) or nil, detail = detail and self.encode(detail):sub(1, 480) or nil })
end

function Core:_mirror(kind, s, extra)
    local d = { craft = s.reference, recipe = s.recipe_id, owner = s.owner_resource, character = s.character_id, station = s.station_id, quantity = s.quantity }
    for k, v in pairs(extra or {}) do d[k] = v end
    pcall(self.audit, kind, d)
end

-- ------------------------------------------------------------------ registry

local function cleanLines(self, raw, maxLines, what)
    if type(raw) ~= 'table' or #raw < 1 or #raw > maxLines then return nil, 'invalid_' .. what end
    local L, out, seen = self.cfg.Limits, {}, {}
    for _, line in ipairs(raw) do
        if type(line) ~= 'table' then return nil, 'invalid_' .. what end
        for k, v in pairs(line) do if type(v) == 'function' or type(v) == 'userdata' then return nil, 'invalid_' .. what end end
        if not isItem(line.item) or seen[line.item] then return nil, 'invalid_' .. what end
        if not isInt(line.amount) or line.amount < 1 or line.amount > L.maxAmount then return nil, 'invalid_amount' end
        seen[line.item] = true
        local entry = { item = line.item, amount = line.amount }
        if line.metadata ~= nil then
            if what ~= 'outputs' then return nil, 'invalid_metadata' end
            if type(line.metadata) ~= 'table' or #self.encode(line.metadata) > L.maxMetadataBytes then return nil, 'invalid_metadata' end
            for mk, mv in pairs(line.metadata) do
                if type(mk) ~= 'string' or not (type(mv) == 'string' or type(mv) == 'number' or type(mv) == 'boolean') then return nil, 'invalid_metadata' end
            end
            entry.metadata = line.metadata
        end
        out[#out + 1] = entry
    end
    return out
end

function Core:_normalizeRecipe(owner, raw)
    local L = self.cfg.Limits
    if type(raw) ~= 'table' then return nil, 'invalid_recipe' end
    for _, v in pairs(raw) do if type(v) == 'function' or type(v) == 'userdata' then return nil, 'invalid_recipe' end end
    if type(raw.id) ~= 'string' or #raw.id > 48 or not raw.id:match('^[%l%d_]+:[%l%d_]+$') then return nil, 'invalid_id' end
    if raw.label ~= nil and (type(raw.label) ~= 'string' or #raw.label < 2 or #raw.label > 48 or raw.label:find('[%c]')) then return nil, 'invalid_label' end
    local r = { id = raw.id, owner = owner, label = raw.label or raw.id, category = type(raw.category) == 'string' and raw.category:match('^[%l%d_]+$') and #raw.category <= 24 and raw.category or 'general' }
    local inputs, why = cleanLines(self, raw.inputs, L.maxInputs, 'inputs'); if not inputs then return nil, why end
    local outputs, why2 = cleanLines(self, raw.outputs, L.maxOutputs, 'outputs'); if not outputs then return nil, why2 end
    r.inputs, r.outputs = inputs, outputs
    local tools = {}
    if raw.tools ~= nil then
        if type(raw.tools) ~= 'table' or #raw.tools > L.maxTools then return nil, 'invalid_tools' end
        for _, t in ipairs(raw.tools) do
            if type(t) ~= 'table' or not isItem(t.item) then return nil, 'invalid_tools' end
            local use = t.durabilityUse
            if use ~= nil and (not isInt(use) or use < 1 or use > L.maxDurabilityUse) then return nil, 'invalid_tools' end
            tools[#tools + 1] = { item = t.item, durabilityUse = use }
        end
    end
    r.tools = tools
    -- recursion / no-op guard: an output may not also be an input or a tool
    local inSet = {}
    for _, l in ipairs(inputs) do inSet[l.item] = true end
    for _, t in ipairs(tools) do inSet[t.item] = true end
    for _, o in ipairs(outputs) do if inSet[o.item] then return nil, 'recursive_recipe' end end
    local batch = type(raw.batch) == 'table' and raw.batch or {}
    r.batch = { min = num(batch.min, 1), max = num(batch.max, 1) }
    if not isInt(r.batch.min) or not isInt(r.batch.max) or r.batch.min < 1 or r.batch.max < r.batch.min or r.batch.max > L.maxBatch then return nil, 'invalid_batch' end
    for _, l in ipairs(inputs) do if l.amount * r.batch.max > L.maxTotalAmount then return nil, 'invalid_amount' end end
    for _, l in ipairs(outputs) do if l.amount * r.batch.max > L.maxTotalAmount then return nil, 'invalid_amount' end end
    r.secondsPerUnit = num(raw.durationSeconds, nil)
    if not r.secondsPerUnit or not isInt(r.secondsPerUnit) or r.secondsPerUnit < L.secondsPerUnit[1] or r.secondsPerUnit > L.secondsPerUnit[2] then return nil, 'invalid_duration' end
    if r.secondsPerUnit * r.batch.max > L.maxTotalSeconds then return nil, 'invalid_duration' end
    r.handcraft = raw.handcraft == true
    r.stations = {}
    if raw.stations ~= nil then
        if type(raw.stations) ~= 'table' or #raw.stations > 8 then return nil, 'invalid_station' end
        for _, st in ipairs(raw.stations) do
            if type(st) ~= 'string' or not st:match('^[%l%d_]+$') or #st > 24 then return nil, 'invalid_station' end
            r.stations[st] = true
        end
    end
    if not r.handcraft and next(r.stations) == nil then return nil, 'invalid_station' end   -- never "craftable anywhere" by omission
    if raw.eligibilityExport ~= nil then
        if type(raw.eligibilityExport) ~= 'string' or not raw.eligibilityExport:match('^[%w_]+$') or #raw.eligibilityExport > 48 then return nil, 'invalid_eligibility' end
        r.eligibilityExport = raw.eligibilityExport
    end
    return r
end

-- Item references are checked against cm-items (the definition authority). Unknown or unavailable item authority fails closed.
function Core:_checkItems(r)
    local names = {}
    for _, l in ipairs(r.inputs) do names[l.item] = true end
    for _, l in ipairs(r.outputs) do names[l.item] = true end
    for _, t in ipairs(r.tools) do names[t.item] = true end
    for name in pairs(names) do
        local ok = self.items.exists(name)
        if ok == nil then return false, 'items_unavailable' end
        if ok ~= true then return false, 'unknown_item' end
    end
    for _, o in ipairs(r.outputs) do
        if o.metadata and self.items.validateMetadata and self.items.validateMetadata(o.item, o.metadata) ~= true then return false, 'invalid_metadata' end
    end
    return true
end

function Core:RegisterRecipe(invoker, raw)
    if type(invoker) ~= 'string' or not (self.cfg.TrustedOwners or {})[invoker] then return false, 'untrusted_resource' end
    local r, why = self:_normalizeRecipe(invoker, raw)
    if not r then return false, why end
    local existing = self.recipes[r.id]
    if existing and existing.owner ~= invoker then return false, 'owner_mismatch' end
    local ok, why2 = self:_checkItems(r)
    if not ok then return false, why2 end
    self.recipes[r.id] = r      -- the same owner re-registering (restart / hot reload) replaces its own definition
    return true, { id = r.id, replaced = existing ~= nil }
end

function Core:RegisterStation(invoker, raw)
    if type(invoker) ~= 'string' or not (self.cfg.TrustedOwners or {})[invoker] then return false, 'untrusted_resource' end
    if type(raw) ~= 'table' then return false, 'invalid_station' end
    if type(raw.id) ~= 'string' or #raw.id > 48 or not raw.id:match('^[%l%d_:%-]+$') then return false, 'invalid_id' end
    if type(raw.type) ~= 'string' or not raw.type:match('^[%l%d_]+$') or #raw.type > 24 then return false, 'invalid_station' end
    local c = raw.coords
    if type(c) ~= 'table' or not tonumber(c.x) or not tonumber(c.y) or not tonumber(c.z) then return false, 'invalid_coords' end
    local radius = num(raw.radius, 2.5)
    if radius < 0.5 or radius > 25.0 then return false, 'invalid_radius' end
    local bucket = raw.bucket
    if bucket ~= nil and not isInt(bucket) then return false, 'invalid_bucket' end
    local existing = self.stations[raw.id]
    if existing and existing.owner ~= invoker then return false, 'owner_mismatch' end
    self.stations[raw.id] = { id = raw.id, owner = invoker, type = raw.type, coords = { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 }, radius = radius,
        bucket = bucket, shared = raw.shared == true }
    return true, { id = raw.id, replaced = existing ~= nil }
end

function Core:_recipeFor(invoker, recipeId)
    local r = type(recipeId) == 'string' and self.recipes[recipeId] or nil
    if not r then return nil, 'unknown_recipe' end
    if r.owner ~= invoker then return nil, 'forbidden' end
    return r
end

function Core:GetRecipes(invoker, filter)
    if not (self.cfg.TrustedOwners or {})[invoker or ''] then return false, 'untrusted_resource' end
    filter = type(filter) == 'table' and filter or {}
    local out = {}
    for id, r in pairs(self.recipes) do
        if r.owner == invoker and (not filter.category or r.category == filter.category) then
            out[#out + 1] = { id = id, label = r.label, category = r.category, batch = r.batch, secondsPerUnit = r.secondsPerUnit, handcraft = r.handcraft }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return true, out
end

-- ------------------------------------------------------------- transaction

-- Authoritative inputs/outputs/tools generated from the REGISTERED recipe and the validated quantity. Nothing client-supplied reaches it.
function Core:_buildTx(r, quantity)
    local tx = { inputs = {}, outputs = {}, tools = {} }
    for _, l in ipairs(r.inputs) do tx.inputs[#tx.inputs + 1] = { item = l.item, amount = l.amount * quantity } end
    for _, l in ipairs(r.outputs) do tx.outputs[#tx.outputs + 1] = { item = l.item, amount = l.amount * quantity, metadata = l.metadata } end
    for _, t in ipairs(r.tools) do tx.tools[#tx.tools + 1] = { item = t.item, durabilityUse = t.durabilityUse and math.min(self.cfg.Limits.maxDurabilityUse, t.durabilityUse * quantity) or nil } end
    return tx
end

local VALIDATION_FAIL = { insufficient_input = true, tool_missing = true, no_capacity = true, invalid_transaction = true,
    tool_durability = true, invalid_item = true, invalid_metadata = true, reference_conflict = true }   -- definite refusals of cm-inventory: nothing applied

-- ----------------------------------------------------------------- begin

function Core:_checkStation(r, stationId, cid, bucketOnly, bucket)
    if stationId == nil then
        if not r.handcraft then return false, 'station_required' end
        return true, nil
    end
    if type(stationId) ~= 'string' then return false, 'invalid_station' end
    local st = self.stations[stationId]
    if not st then return false, 'unknown_station' end
    if st.owner ~= r.owner and not st.shared then return false, 'station_forbidden' end
    if not r.stations[st.type] then return false, 'wrong_station_type' end
    local src = self.chars.sourceOf(cid)
    if not src then return false, 'character_offline' end
    local pos = self.chars.position(src)
    if not pos then return false, 'position_unavailable' end
    if st.bucket ~= nil and pos.bucket ~= st.bucket then return false, 'wrong_bucket' end
    if bucket ~= nil and pos.bucket ~= bucket then return false, 'bucket_changed' end
    if dist(pos, st.coords) > st.radius then return false, 'too_far' end
    return true, st
end

function Core:_eligible(r, cid, quantity, stationId)
    if not r.eligibilityExport then return true end
    if not self.owners.started(r.owner) then return false, 'owner_unavailable' end
    local ok, a, b = self.owners.call(r.owner, r.eligibilityExport, cid, r.id, quantity, stationId)
    if not ok then return false, 'eligibility_unavailable' end   -- owner failure fails closed
    if a ~= true then return false, type(b) == 'string' and b:match('^[%w_]+$') and b:sub(1, 32) or 'not_eligible' end
    return true
end

function Core:_prepare(invoker, cid, recipeId, quantity, stationId)
    local r, why = self:_recipeFor(invoker, recipeId)
    if not r then return nil, why end
    if not isCid(cid) then return nil, 'invalid_character' end
    if not isInt(quantity) or quantity < r.batch.min or quantity > r.batch.max then return nil, 'invalid_quantity' end
    local src = self.chars.sourceOf(cid)
    if not src then return nil, 'character_offline' end
    local pos = self.chars.position(src)
    if not pos then return nil, 'position_unavailable' end
    local okS, st = self:_checkStation(r, stationId, cid)
    if not okS then return nil, st end
    local okE, whyE = self:_eligible(r, cid, quantity, stationId)
    if not okE then return nil, whyE end
    if self.cfg.RequireAtomicInventory and not self.inventory.ready() then return nil, 'settlement_unavailable' end
    local tx = self:_buildTx(r, quantity)
    local okV, whyV = self.inventory.validate(cid, tx)
    if okV ~= true then return nil, VALIDATION_FAIL[whyV] and whyV or 'inventory_unavailable' end
    return { recipe = r, tx = tx, bucket = pos.bucket }
end

function Core:CanCraft(invoker, cid, recipeId, quantity, stationId)
    local p, why = self:_prepare(invoker, cid, recipeId, quantity, stationId)
    if not p then return false, why end
    return true, { allowed = true }
end

local CTX_KEYS = { idempotencyKey = true, speedModifier = true }

function Core:Begin(invoker, cid, recipeId, quantity, stationId, ctx)
    if ctx ~= nil and type(ctx) ~= 'table' then return false, 'invalid_request' end
    ctx = ctx or {}
    local L = self.cfg.Limits
    local idem
    if ctx.idempotencyKey ~= nil then
        if type(ctx.idempotencyKey) ~= 'string' or #ctx.idempotencyKey > 48 or not ctx.idempotencyKey:match('^[%w_%-:%.]+$') then return false, 'invalid_key' end
        idem = invoker .. ':' .. ctx.idempotencyKey
        local prior = self.store.sessGetByIdem(idem)
        if prior then
            if prior.recipe_id ~= recipeId or prior.character_id ~= cid then return false, 'idempotency_conflict' end
            return true, { reference = prior.reference, status = prior.status, readyAt = prior.ready_at, expiresAt = prior.expires_at, existing = true }
        end
    end
    if isCid(cid) and not self.rate(invoker .. ':' .. cid, 'begin') then return false, 'rate_limited' end
    local p, why = self:_prepare(invoker, cid, recipeId, quantity, stationId)
    if not p then return false, why end
    local r = p.recipe
    local mod = 1.0
    if ctx.speedModifier ~= nil then
        if type(ctx.speedModifier) ~= 'number' or ctx.speedModifier ~= ctx.speedModifier then return false, 'invalid_request' end
        mod = math.max(L.speedModifier[1], math.min(L.speedModifier[2], ctx.speedModifier))
    end
    -- server-decided duration: base seconds x batch, optional clamped trusted modifier, never below 1 s
    local duration = math.max(1, math.floor(r.secondsPerUnit * quantity / mod + 0.5))
    return self:_lock('char:' .. cid, function()
        if self.store.sessActiveByChar(cid) then return false, 'already_crafting' end
        local now = self.now()
        local s = { reference = self:_ref(), recipe_id = r.id, owner_resource = invoker, character_id = cid, station_id = stationId, quantity = quantity,
            status = 'active', active_key = cid, idem_key = idem, bucket = p.bucket, started_at = now, ready_at = now + duration,
            expires_at = now + duration + self.cfg.Session.graceAfterReadySeconds, tx_json = self.encode(p.tx), commit_attempts = 0, updated_at = now }
        local id, why2 = self.store.sessInsert(s)
        if not id then
            if why2 == 'duplicate_key' then local prior = idem and self.store.sessGetByIdem(idem); if prior then return true, { reference = prior.reference, status = prior.status, existing = true } end end
            return false, why2 == 'already_crafting' and 'already_crafting' or 'internal_error'
        end
        self:_event(s, 'started', { quantity = quantity, station = stationId, seconds = duration }, 'started')
        return true, { reference = s.reference, status = 'active', durationSeconds = duration, readyAt = s.ready_at, expiresAt = s.expires_at }
    end)
end

-- ---------------------------------------------------------------- session

function Core:_mine(invoker, ref, cid)
    if not isRef(ref) then return nil, 'invalid_reference' end
    local s = self.store.sessGet(ref)
    if not s then return nil, 'not_found' end
    if s.owner_resource ~= invoker then return nil, 'forbidden' end
    if cid ~= nil and s.character_id ~= cid then return nil, 'forbidden' end   -- forged character id
    return s
end

function Core:_view(s)
    return { reference = s.reference, recipeId = s.recipe_id, characterId = s.character_id, stationId = s.station_id, quantity = s.quantity, status = s.status,
        startedAt = s.started_at, readyAt = s.ready_at, expiresAt = s.expires_at, committedAt = s.committed_at, failureReason = s.failure_reason }
end

function Core:Get(invoker, ref)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    return true, self:_view(s)
end

function Core:_terminal(s, status, reason)
    local now = self.now()
    local n = self.store.sessCas(s.reference, { 'active' }, { status = status, active_key = false, failure_reason = reason, updated_at = now })
    if n ~= 1 then return false end
    self:_event(s, status, { reason = reason }, 'terminal')
    self:_mirror('craft_' .. status, s, { reason = reason })
    return true
end

function Core:Cancel(invoker, ref, cid, reason)
    local s, why = self:_mine(invoker, ref, cid)
    if not s then return false, why end
    if not self.rate(invoker .. ':' .. s.character_id, 'cancel') then return false, 'rate_limited' end
    reason = type(reason) == 'string' and reason:match('^[%w_%-]+$') and reason:sub(1, 32) or 'cancelled'
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status == 'cancelled' then return true, { status = 'cancelled', replayed = true } end
        if s.status ~= 'active' then return false, 'cancel_not_allowed' end   -- committing/completed are irreversible; failed/expired are already terminal
        -- V1 consumes nothing before the final atomic commit, so cancelling is just ending the session
        if not self:_terminal(s, 'cancelled', reason) then return false, 'cancel_not_allowed' end
        return true, { status = 'cancelled' }
    end)
end

function Core:Fail(invoker, ref, reason)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    reason = type(reason) == 'string' and reason:match('^[%w_%-]+$') and reason:sub(1, 32) or 'failed'
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status == 'failed' then return true, { status = 'failed', replayed = true } end
        if s.status ~= 'active' then return false, s.status == 'committing' and 'commit_in_progress' or 'terminal_' .. s.status end
        if not self:_terminal(s, 'failed', reason) then return false, 'terminal' end
        return true, { status = 'failed' }
    end)
end

-- ---------------------------------------------------------------- commit

function Core:_markCompleted(s, replayed)
    local now = self.now()
    local n = self.store.sessCas(s.reference, { 'committing' }, { status = 'completed', active_key = false, committed_at = now, updated_at = now })
    if n ~= 1 then return false end
    self:_event(s, 'inventory_committed', nil, 'inventory_committed')
    self:_event(s, 'completed', { reconciled = replayed or nil }, 'terminal')
    self:_mirror('craft_completed', s, { reconciled = replayed or nil })
    return true
end

function Core:_resultOf(s)
    local tx = self.decode(s.tx_json) or {}
    return { reference = s.reference, status = 'completed', outputs = tx.outputs or {}, quantity = s.quantity }
end

-- Run (or re-run, idempotently) the inventory transaction for a session already in `committing`.
function Core:_settle(s)
    local tx = self.decode(s.tx_json)
    if type(tx) ~= 'table' then
        self.store.sessCas(s.reference, { 'committing' }, { status = 'failed', active_key = false, failure_reason = 'invalid_snapshot', updated_at = self.now() })
        return false, 'invalid_snapshot'
    end
    local now = self.now()
    local ok, res = self.inventory.execute(s.reference, s.character_id, tx)
    if ok == true then
        self.unknownSince[s.reference] = nil
        if not self:_markCompleted(s) then local cur = self.store.sessGet(s.reference); if cur and cur.status == 'completed' then return true, 'replayed' end return false, 'state_changed' end
        return true
    end
    if VALIDATION_FAIL[res] then
        -- the inventory contract guarantees nothing was applied on a definite failure: safe to fail the session
        local n = self.store.sessCas(s.reference, { 'committing' }, { status = 'failed', active_key = false, failure_reason = res, updated_at = now })
        if n == 1 then self:_event(s, 'failed', { reason = res }, 'terminal'); self:_mirror('craft_failed', s, { reason = res }) end
        return false, res
    end
    -- unavailable / unknown: do NOT guess. Stay committing; reconciliation asks the inventory owner for the transaction status.
    local attempts = (tonumber(s.commit_attempts) or 0) + 1
    local delay = self.cfg.Session.commitRetryBaseSeconds * attempts
    self.store.sessCas(s.reference, { 'committing' }, { commit_attempts = attempts, next_commit_at = now + delay, updated_at = now })
    return false, 'reconciling'
end

function Core:_reconcileOne(s)
    local now = self.now()
    local st = self.inventory.status(s.reference)
    if st == 'committed' then
        self.unknownSince[s.reference] = nil
        if self:_markCompleted(s, true) then self:_event(s, 'reconciled', { result = 'committed' }) end
        return 'committed'
    end
    if st == 'not_applied' then
        if (tonumber(s.commit_attempts) or 0) >= self.cfg.Session.maxCommitAttempts then
            local n = self.store.sessCas(s.reference, { 'committing' }, { status = 'failed', active_key = false, failure_reason = 'commit_failed', updated_at = now })
            if n == 1 then self:_event(s, 'failed', { reason = 'commit_failed' }, 'terminal'); self:_event(s, 'reconciled', { result = 'not_applied' }); self:_mirror('craft_failed', s, { reason = 'commit_failed' }) end
            return 'failed'
        end
        if now >= (tonumber(s.next_commit_at) or 0) then self:_settle(s) end   -- idempotent by reference under the inventory contract
        return 'retried'
    end
    -- unknown / unavailable
    self.unknownSince[s.reference] = self.unknownSince[s.reference] or now
    if now - self.unknownSince[s.reference] >= self.cfg.Session.reconcileFlagSeconds then
        if self:_event(s, 'reconcile_stuck', nil, 'reconcile_stuck') then self:_mirror('craft_reconcile_stuck', s) end
    end
    return 'unknown'
end

function Core:Complete(invoker, ref, cid, ctx)
    local s, why = self:_mine(invoker, ref, cid)
    if not s then return false, why end
    if not self.rate(invoker .. ':' .. s.character_id, 'complete') then return false, 'rate_limited' end
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status == 'completed' then return true, self:_resultOf(s), 'replayed' end
        if s.status == 'committing' then
            local r = self:_reconcileOne(s)
            local cur = self.store.sessGet(ref)
            if cur.status == 'completed' then return true, self:_resultOf(cur), 'replayed' end
            if cur.status == 'failed' then return false, cur.failure_reason or 'failed' end
            return false, 'reconciling'
        end
        if s.status ~= 'active' then return false, 'terminal_' .. s.status end
        local now = self.now()
        if now >= (tonumber(s.expires_at) or now) then self:_terminal(s, 'expired', 'timeout'); return false, 'expired' end
        if now < (tonumber(s.ready_at) or now) then return false, 'too_early' end        -- the client cannot shorten the server timer
        if self.cfg.RequireAtomicInventory and not self.inventory.ready() then return false, 'settlement_unavailable' end

        local r = self.recipes[s.recipe_id]
        if not r then return false, 'owner_unavailable' end                              -- owner has not re-registered: stay active until expiry
        -- final validation: live, same bucket, still at the station, still eligible
        local okS, whyS = self:_checkStation(r, s.station_id, s.character_id, true, s.bucket)
        if not okS then
            if whyS == 'character_offline' then return false, 'character_offline' end
            return false, whyS
        end
        if s.station_id == nil then
            local src = self.chars.sourceOf(s.character_id); if not src then return false, 'character_offline' end
            local pos = self.chars.position(src); if not pos or pos.bucket ~= s.bucket then return false, 'bucket_changed' end
        end
        local okE, whyE = self:_eligible(r, s.character_id, s.quantity, s.station_id)
        if not okE then return false, whyE end
        local tx = self.decode(s.tx_json)
        local okV, whyV = self.inventory.validate(s.character_id, tx)
        if okV ~= true then
            if VALIDATION_FAIL[whyV] then self:_terminal(s, 'failed', whyV); return false, whyV end   -- ingredients/tool gone or no room: fail safely, nothing consumed
            return false, 'inventory_unavailable'
        end
        -- single winner vs cancel/fail/expiry: only one compare-and-swap leaves 'active'
        local n = self.store.sessCas(ref, { 'active' }, { status = 'committing', commit_started_at = now, updated_at = now })
        if n ~= 1 then local cur = self.store.sessGet(ref); return false, 'terminal_' .. tostring(cur and cur.status or 'unknown') end
        self:_event(s, 'commit_started', { tx = ref }, 'commit_started')
        s = self.store.sessGet(ref)
        local okC, whyC = self:_settle(s)
        if okC then return true, self:_resultOf(self.store.sessGet(ref)) end
        return false, whyC
    end)
end

-- ----------------------------------------------------------------- recovery

-- Startup: uncommitted timers cannot be trusted across a restart (station/bucket/owner state is gone): fail them. Committing sessions reconcile.
function Core:Recover()
    local failed = 0
    for _, s in ipairs(self.store.sessListOpen(500)) do
        if s.status == 'active' then
            self:_lock('sess:' .. s.reference, function()
                local cur = self.store.sessGet(s.reference)
                if cur and cur.status == 'active' and self:_terminal(cur, 'failed', 'restart') then failed = failed + 1 end
            end)
        end
    end
    local _, st = self:Sweep()
    st.failedOnRestart = failed
    return true, st
end

function Core:Sweep()
    local now = self.now()
    local stats = { expired = 0, disconnected = 0, ownerStopped = 0, reconciled = 0 }
    for _, row in ipairs(self.store.sessListOpen(200)) do
        self:_lock('sess:' .. row.reference, function()
            local s = self.store.sessGet(row.reference)
            if not s then return end
            if s.status == 'committing' then
                local r = self:_reconcileOne(s)
                if r == 'committed' or r == 'failed' then stats.reconciled = stats.reconciled + 1 end
                return
            end
            if s.status ~= 'active' then return end
            if now >= (tonumber(s.expires_at) or now) then
                if self:_terminal(s, 'expired', 'timeout') then stats.expired = stats.expired + 1 end
                return
            end
            if self.owners.started(s.owner_resource) and self.recipes[s.recipe_id] then self.ownerDownSince[s.reference] = nil
            else
                self.ownerDownSince[s.reference] = self.ownerDownSince[s.reference] or now
                if now - self.ownerDownSince[s.reference] >= self.cfg.Session.ownerStopGraceSeconds then
                    if self:_terminal(s, 'failed', 'owner_stopped') then stats.ownerStopped = stats.ownerStopped + 1 end
                    return
                end
            end
            if self.chars.sourceOf(s.character_id) then self.offlineSince[s.reference] = nil
            else
                self.offlineSince[s.reference] = self.offlineSince[s.reference] or now
                if now - self.offlineSince[s.reference] >= self.cfg.Session.disconnectGraceSeconds then
                    -- no offline outputs: nothing was consumed, so failing loses nothing
                    if self:_terminal(s, 'failed', 'disconnected') then stats.disconnected = stats.disconnected + 1 end
                end
            end
        end)
    end
    return true, stats
end

-- ------------------------------------------------------------------- admin

function Core:AdminList()
    local out = {}
    for _, s in ipairs(self.store.sessListOpen(100)) do out[#out + 1] = self:_view(s) end
    return true, out
end

function Core:AdminInspect(ref)
    if not isRef(ref) then return false, 'invalid_reference' end
    local s = self.store.sessGet(ref)
    if not s then return false, 'not_found' end
    return true, { session = self:_view(s), transaction = self.decode(s.tx_json), commitAttempts = s.commit_attempts, events = self.store.eventList(ref, 60) }
end

function Core:AdminCancel(ref, label)
    if not isRef(ref) then return false, 'invalid_reference' end
    return self:_lock('sess:' .. ref, function()
        local s = self.store.sessGet(ref)
        if not s then return false, 'not_found' end
        if s.status == 'committing' then return false, 'committing_use_reconcile' end
        if s.status ~= 'active' then return false, 'terminal_' .. s.status end
        if not self:_terminal(s, 'cancelled', 'admin_cancel') then return false, 'terminal' end
        self:_event(s, 'admin_cancel', { by = label or 'admin' })
        return true
    end)
end

function Core:AdminReconcile(ref, label)
    if ref == nil then return self:Sweep() end
    if not isRef(ref) then return false, 'invalid_reference' end
    return self:_lock('sess:' .. ref, function()
        local s = self.store.sessGet(ref)
        if not s then return false, 'not_found' end
        if s.status ~= 'committing' then return true, { status = s.status } end
        self.store.sessCas(ref, { 'committing' }, { next_commit_at = 0 })
        local r = self:_reconcileOne(self.store.sessGet(ref))
        self:_event(s, 'reconciled', { by = label or 'admin', result = r })
        return true, { result = r, status = self.store.sessGet(ref).status }
    end)
end
