-- cm-crime core: activity registry + criminal SESSION lifecycle. Dependency-injected (no FiveM natives, no SQL): server/main.lua wires the
-- real store/adapters, tests/selftest.lua wires deterministic doubles.
--
--   content resource (server) -> RegisterActivity -> Begin (site lock, cooldowns, police, participants) -> Advance stages
--     -> Dispatch (existing law dispatch) -> Complete | Fail | Cancel | (expiry) -> cooldowns -> ONE reward authorization
--     -> content resource applies its own proceeds through the authoritative economy owner -> Confirm reward delivered
--
-- This core creates $0, 0 items and 0 XP and never calls an economy, inventory, evidence or police-roster owner except through the
-- injected read/dispatch adapters. Identity is the character id; FiveM sources are never stored.
CMCrime = CMCrime or {}
local Core = {}
Core.__index = Core
CMCrime.Core = Core

local REF_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local OPEN = { 'created', 'active' }
local TERMINAL = { succeeded = true, failed = true, cancelled = true, expired = true }

local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end return v end
local function clamp(v, lo, hi, d) v = num(v, d); if v < lo then return lo end if v > hi then return hi end return v end
local function isId(v, max) return type(v) == 'string' and #v >= 1 and #v <= (max or 40) and v:match('^[%w_%-%.:]+$') ~= nil end
local function isCid(v) return type(v) == 'string' and #v >= 1 and #v <= 20 and v:match('^%d+$') ~= nil end
local function copy(t) if type(t) ~= 'table' then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end

function Core.New(deps)
    assert(type(deps) == 'table' and type(deps.cfg) == 'table' and deps.store, 'cm-crime core needs cfg + store')
    local self = setmetatable({}, Core)
    self.cfg, self.store = deps.cfg, deps.store
    self.now = deps.now or os.time
    self.rand = deps.rand or math.random
    self.encode = deps.encode or function() return '' end
    self.chars = deps.chars                      -- sourceOf(cid)->src|nil, bucket(src)->int
    self.police = deps.police or { count = function() return nil end }
    self.dispatch = deps.dispatch or { send = function() return false end }
    self.owners = deps.owners or { started = function() return true end }
    self.audit = deps.audit or function() end
    self.rate = deps.rate or function() return true end
    self.log = deps.log or function() end
    self.activities, self.locks = {}, {}
    self.offlineSince, self.ownerDownSince = {}, {}
    return self
end

-- ------------------------------------------------------------------ helpers

function Core:_ref()
    local s = {}
    for i = 1, 8 do local n = self.rand(1, #REF_CHARS); s[i] = REF_CHARS:sub(n, n) end
    return 'CR-' .. table.concat(s)
end

function Core:_token()
    local s = {}
    for i = 1, 24 do local n = self.rand(1, #REF_CHARS); s[i] = REF_CHARS:sub(n, n) end
    return table.concat(s)
end

function Core:_lock(key, fn)
    if self.locks[key] then return false, 'busy' end
    self.locks[key] = true
    local res = table.pack(pcall(fn))
    self.locks[key] = nil
    if not res[1] then self.log('error', tostring(res[2])); return false, 'internal_error' end
    return table.unpack(res, 2, res.n)
end

function Core:_event(s, kind, cid, detail, key)
    return self.store.eventInsert({
        session_ref = s.reference, activity_id = s.activity_id, kind = kind, character_id = cid and tostring(cid) or nil,
        key = key and (s.reference .. ':' .. key) or nil, detail = detail and self.encode(detail):sub(1, 480) or nil,
    })
end

function Core:_mirror(kind, s, extra)
    local d = { session = s.reference, activity = s.activity_id, site = s.site_key, owner = s.owner_resource }
    for k, v in pairs(extra or {}) do d[k] = v end
    pcall(self.audit, kind, d)
end

-- ------------------------------------------------------------------ registry

-- Validate + normalise a definition. Pure; returns def | nil, reason.
function Core:_normalize(owner, raw)
    local cfg = self.cfg
    local D, L = cfg.Defaults, cfg.Limits
    if type(raw) ~= 'table' then return nil, 'invalid_definition' end
    if type(raw.id) ~= 'string' or not raw.id:match('^[%l%d_]+$') or #raw.id < 3 or #raw.id > 40 then return nil, 'invalid_id' end
    local d = { id = raw.id, owner = owner }
    d.category = type(raw.category) == 'string' and raw.category:match('^[%l%d_]+$') and #raw.category <= 24 and raw.category or D.category
    if raw.label ~= nil and (type(raw.label) ~= 'string' or #raw.label < 2 or #raw.label > 48 or raw.label:find('[%c]')) then return nil, 'invalid_label' end
    d.label = raw.label or raw.id
    d.minPolice = math.floor(clamp(raw.minPolice, 0, L.maxPolice, D.minPolice))
    d.policeOrg = type(raw.policeOrg) == 'string' and raw.policeOrg:match('^[%l%d_]+$') and raw.policeOrg or cfg.Police.org
    local p = type(raw.participants) == 'table' and raw.participants or {}
    d.participants = { min = math.floor(clamp(p.min, 1, L.maxParticipants, D.participants.min)), max = math.floor(clamp(p.max, 1, L.maxParticipants, D.participants.max)) }
    if d.participants.min > d.participants.max then return nil, 'invalid_participants' end
    d.allowJoin = raw.allowJoin == true
    d.sessionSeconds = math.floor(clamp(raw.sessionSeconds, L.sessionSeconds[1], L.sessionSeconds[2], D.sessionSeconds))
    d.siteMode = raw.siteMode == 'none' and 'none' or 'exclusive'
    d.busyGroup = type(raw.busyGroup) == 'string' and raw.busyGroup:match('^[%l%d_]+$') and #raw.busyGroup <= 24 and raw.busyGroup or D.busyGroup
    local c = type(raw.cooldowns) == 'table' and raw.cooldowns or {}
    d.cooldowns = {
        site = math.floor(clamp(c.site, 0, L.maxCooldownSeconds, 0)), activity = math.floor(clamp(c.activity, 0, L.maxCooldownSeconds, 0)),
        character = math.floor(clamp(c.character, 0, L.maxCooldownSeconds, 0)),
        onFailure = (c.onFailure == 'partial' or c.onFailure == 'none') and c.onFailure or 'full',
        partialFactor = clamp(c.partialFactor, 0, 1, D.cooldowns.partialFactor),
    }
    local dp = type(raw.dispatch) == 'table' and raw.dispatch or {}
    local mode = dp.mode
    if mode ~= 'immediate' and mode ~= 'delayed' and mode ~= 'chance' and mode ~= 'stage' then mode = 'none' end
    d.dispatch = { mode = mode, once = dp.once ~= false, priority = math.floor(clamp(dp.priority, 1, 3, D.dispatch.priority)),
        chance = clamp(dp.chance, 0, 1, 1.0), delaySeconds = math.floor(clamp(dp.delaySeconds, 0, 3600, 0)), types = {}, stages = nil }
    for key, text in pairs(type(dp.types) == 'table' and dp.types or {}) do
        if type(key) == 'string' and key:match('^[%l%d_]+$') and #key <= 24 and type(text) == 'string' and #text >= 2 and #text <= 60 and not text:find('[%c]') then
            d.dispatch.types[key] = text
        end
    end
    if mode ~= 'none' and next(d.dispatch.types) == nil then return nil, 'invalid_dispatch' end
    if mode == 'stage' then
        d.dispatch.stages = {}
        for _, st in ipairs(type(dp.stages) == 'table' and dp.stages or {}) do if type(st) == 'string' and st:match('^[%w_]+$') then d.dispatch.stages[st] = true end end
        if next(d.dispatch.stages) == nil then return nil, 'invalid_dispatch' end
    end
    if raw.stages ~= nil then
        if type(raw.stages) ~= 'table' or #raw.stages < 1 or #raw.stages > L.maxStages then return nil, 'invalid_stages' end
        d.stages, d.stageIndex = {}, {}
        for i, st in ipairs(raw.stages) do
            if type(st) ~= 'string' or not st:match('^[%l%d_]+$') or #st > 24 or d.stageIndex[st] then return nil, 'invalid_stages' end
            d.stages[i], d.stageIndex[st] = st, i
        end
    end
    d.strictOrder = raw.strictOrder == true and d.stages ~= nil
    d.reward = { enabled = not (type(raw.reward) == 'table' and raw.reward.enabled == false) }
    local pol = type(raw.policy) == 'table' and raw.policy or {}
    d.policy = {
        onInitiatorLeave = pol.onInitiatorLeave == 'fail' and 'fail' or 'continue',
        disconnectGraceSeconds = math.floor(clamp(pol.disconnectGraceSeconds, 10, 1800, D.policy.disconnectGraceSeconds)),
        onOwnerStop = pol.onOwnerStop == 'cancel' and 'cancel' or 'fail',
        ownerStopGraceSeconds = math.floor(clamp(pol.ownerStopGraceSeconds, 10, 1800, D.policy.ownerStopGraceSeconds)),
    }
    return d
end

-- Only allowlisted server resources register; the owner is pinned to the definition for the life of the registry.
function Core:RegisterActivity(invoker, raw)
    if type(invoker) ~= 'string' or not (self.cfg.TrustedOwners or {})[invoker] then return false, 'untrusted_resource' end
    local def, why = self:_normalize(invoker, raw)
    if not def then return false, why end
    local existing = self.activities[def.id]
    if existing and existing.owner ~= invoker then return false, 'owner_mismatch' end
    self.activities[def.id] = def   -- same owner re-registering (restart / hot reload) replaces its own definition
    return true, { id = def.id, replaced = existing ~= nil }
end

function Core:_own(invoker, activityId)
    local def = type(activityId) == 'string' and self.activities[activityId] or nil
    if not def then return nil, 'unknown_activity' end
    if def.owner ~= invoker then return nil, 'forbidden' end
    return def
end

-- Load a session the invoker owns (never another resource's).
function Core:_mine(invoker, ref)
    if not isId(ref, 24) then return nil, 'invalid_reference' end
    local s = self.store.sessGet(ref)
    if not s then return nil, 'not_found' end
    if s.owner_resource ~= invoker then return nil, 'forbidden' end
    return s
end

-- ----------------------------------------------------------------- cooldowns

function Core:_cooldownLeft(scope, key, activityId)
    local exp = self.store.cooldownGet(scope, tostring(key), activityId)
    if not exp then return 0 end
    return math.max(0, exp - self.now())
end

function Core:_applyCooldowns(s, def, outcome)
    local cd = def.cooldowns
    local factor = 1.0
    if outcome ~= 'succeeded' then
        if cd.onFailure == 'none' then return end
        if cd.onFailure == 'partial' then factor = cd.partialFactor end
    end
    local now = self.now()
    local function put(scope, key, seconds)
        seconds = math.floor(seconds * factor)
        if seconds <= 0 or not key then return end
        self.store.cooldownSet(scope, tostring(key), def.id, now + seconds, outcome, s.reference)
        self:_event(s, 'cooldown_applied', nil, { scope = scope, seconds = seconds }, 'cooldown:' .. scope .. ':' .. tostring(key))
    end
    put('site', s.site_key, cd.site)
    put('activity', def.id, cd.activity)
    for _, p in ipairs(self.store.partList(s.reference)) do put('character', p.character_id, cd.character) end
end

function Core:GetCooldown(invoker, activityId, scope, key)
    local def, why = self:_own(invoker, activityId)
    if not def then return false, why end
    if scope ~= 'site' and scope ~= 'activity' and scope ~= 'character' then return false, 'invalid_scope' end
    return true, { remaining = self:_cooldownLeft(scope, scope == 'activity' and def.id or key, def.id) }
end

-- ------------------------------------------------------------------ start

-- Generic start validation (no writes). Returns true, { bucket } | false, reason.
function Core:_validateStart(def, siteKey, cids)
    for _, cid in ipairs(cids) do
        if self:_cooldownLeft('character', cid, def.id) > 0 then return false, 'character_cooldown' end
    end
    if self:_cooldownLeft('activity', def.id, def.id) > 0 then return false, 'activity_cooldown' end
    if siteKey and self:_cooldownLeft('site', siteKey, def.id) > 0 then return false, 'site_cooldown' end
    if def.siteMode == 'exclusive' and siteKey and self.store.siteActive(siteKey) then return false, 'site_occupied' end
    for _, cid in ipairs(cids) do
        if self.store.charBusy(cid, def.busyGroup) then return false, 'character_busy' end
    end
    local bucket
    for _, cid in ipairs(cids) do
        local src = self.chars.sourceOf(cid)
        if not src then return false, 'participant_offline' end
        local b = self.chars.bucket(src)
        if b == nil then return false, 'participant_unavailable' end
        if bucket == nil then bucket = b elseif bucket ~= b then return false, 'bucket_mismatch' end
    end
    if def.minPolice > 0 then
        local n = self.police.count(def.policeOrg)
        if type(n) ~= 'number' then return false, 'police_unavailable' end   -- fail closed: never guess a police count
        if n < def.minPolice then return false, 'not_enough_police' end
    end
    return true, { bucket = bucket or 0 }
end

local function parseStart(def, ctx)
    if type(ctx) ~= 'table' then return nil, 'invalid_request' end
    local siteKey = ctx.siteKey
    if def.siteMode == 'exclusive' then
        if type(siteKey) ~= 'string' or #siteKey > 64 or not siteKey:match('^[%l%d_]+:[%w_%-%.]+$') then return nil, 'invalid_site' end
    elseif siteKey ~= nil and (type(siteKey) ~= 'string' or #siteKey > 64 or not siteKey:match('^[%l%d_]+:[%w_%-%.]+$')) then return nil, 'invalid_site' end
    if not isCid(ctx.leaderCharacterId) then return nil, 'invalid_character' end
    local cids, seen = { ctx.leaderCharacterId }, { [ctx.leaderCharacterId] = true }
    for _, c in ipairs(type(ctx.participantCharacterIds) == 'table' and ctx.participantCharacterIds or {}) do
        if not isCid(c) then return nil, 'invalid_character' end
        if not seen[c] then seen[c] = true; cids[#cids + 1] = c end
    end
    return { siteKey = siteKey, cids = cids }
end

function Core:CanBegin(invoker, activityId, ctx)
    local def, why = self:_own(invoker, activityId)
    if not def then return false, why end
    local p, why2 = parseStart(def, ctx)
    if not p then return false, why2 end
    if #p.cids < def.participants.min or #p.cids > def.participants.max then return false, 'participant_count' end
    local ok, r = self:_validateStart(def, p.siteKey, p.cids)
    if not ok then return false, r end
    return true, { allowed = true }
end

function Core:Begin(invoker, activityId, ctx)
    local def, why = self:_own(invoker, activityId)
    if not def then return false, why end
    local p, why2 = parseStart(def, ctx)
    if not p then return false, why2 end
    if #p.cids < def.participants.min or #p.cids > def.participants.max then return false, 'participant_count' end
    local meta = ctx.metadata
    if meta ~= nil and (type(meta) ~= 'table' or #self.encode(meta) > self.cfg.Limits.maxMetadataBytes) then return false, 'invalid_metadata' end
    local coords = ctx.coords
    if coords ~= nil and (type(coords) ~= 'table' or not tonumber(coords.x) or not tonumber(coords.y) or not tonumber(coords.z)) then return false, 'invalid_coords' end
    local siteLabel = ctx.siteLabel
    if siteLabel ~= nil and (type(siteLabel) ~= 'string' or #siteLabel > 48 or siteLabel:find('[%c]')) then return false, 'invalid_label' end
    local idem
    if ctx.idempotencyKey ~= nil then
        if not isId(ctx.idempotencyKey, 48) then return false, 'invalid_key' end
        idem = invoker .. ':' .. ctx.idempotencyKey
        local prior = self.store.sessGetByIdem(idem)
        if prior then
            if prior.activity_id ~= activityId then return false, 'idempotency_conflict' end
            return true, { reference = prior.reference, status = prior.status, existing = true }
        end
    end
    if not self.rate(invoker .. ':' .. p.cids[1], 'begin') then return false, 'rate_limited' end

    local lockKey = p.siteKey and ('site:' .. p.siteKey) or ('leader:' .. p.cids[1])
    return self:_lock(lockKey, function()
        local ok, v = self:_validateStart(def, p.siteKey, p.cids)
        if not ok then return false, v end
        local now = self.now()
        local s = {
            reference = self:_ref(), activity_id = def.id, owner_resource = invoker, site_key = p.siteKey,
            active_site = def.siteMode == 'exclusive' and p.siteKey or nil, status = 'created', leader_cid = p.cids[1],
            current_stage = def.stages and def.stages[1] or 'started', bucket = v.bucket, site_label = siteLabel or nil,
            coords_x = coords and tonumber(coords.x) or nil, coords_y = coords and tonumber(coords.y) or nil, coords_z = coords and tonumber(coords.z) or nil,
            idem_key = idem, created_at = now, expires_at = now + def.sessionSeconds, dispatch_state = 'none', dispatch_count = 0,
            reward_state = 'none', metadata = meta and self.encode(meta) or nil, updated_at = now,
        }
        local id, why3 = self.store.sessInsert(s)
        if not id then
            if why3 == 'site_occupied' then return false, 'site_occupied' end
            if why3 == 'duplicate_key' then
                local prior = idem and self.store.sessGetByIdem(idem)
                if prior then return true, { reference = prior.reference, status = prior.status, existing = true } end
            end
            return false, 'internal_error'
        end
        for i, cid in ipairs(p.cids) do
            local okP, whyP = self.store.partInsert({ session_ref = s.reference, character_id = cid, role = i == 1 and 'leader' or 'member',
                active_key = cid .. ':' .. def.busyGroup, joined_at = now })
            if not okP then
                -- another start won this character in the gap: undo this session completely (no cooldown, nothing was active)
                self.store.partReleaseAll(s.reference, 'left', 'start_failed')
                self.store.sessCas(s.reference, { 'created' }, { status = 'cancelled', active_site = false, end_reason = 'start_failed', completed_at = now, updated_at = now })
                return false, whyP == 'character_busy' and 'character_busy' or 'internal_error'
            end
        end
        self:_event(s, 'session_created', p.cids[1], { site = p.siteKey, owner = invoker, participants = #p.cids })
        for _, cid in ipairs(p.cids) do self:_event(s, 'participant_added', cid, { role = cid == p.cids[1] and 'leader' or 'member' }, 'join:' .. cid) end
        return true, { reference = s.reference, status = 'created', expiresAt = s.expires_at, stage = s.current_stage }
    end)
end

-- ------------------------------------------------------------------ views

function Core:_view(s)
    local parts = {}
    for _, p in ipairs(self.store.partList(s.reference)) do parts[#parts + 1] = { characterId = p.character_id, role = p.role, state = p.state } end
    return {
        reference = s.reference, activityId = s.activity_id, siteKey = s.site_key, status = s.status, stage = s.current_stage,
        leaderCharacterId = s.leader_cid, participants = parts, bucket = s.bucket, createdAt = s.created_at, startedAt = s.started_at,
        expiresAt = s.expires_at, completedAt = s.completed_at, outcome = s.outcome, endReason = s.end_reason,
        dispatchState = s.dispatch_state, rewardState = s.reward_state,
    }
end

function Core:Get(invoker, ref)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    return true, self:_view(s)
end

-- ------------------------------------------------------------- participants

function Core:Join(invoker, ref, cid)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    if not isCid(cid) then return false, 'invalid_character' end
    local def = self.activities[s.activity_id]
    if not def then return false, 'unknown_activity' end
    if not self.rate(invoker .. ':' .. cid, 'join') then return false, 'rate_limited' end
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status ~= 'created' and s.status ~= 'active' then return false, 'terminal' end
        local existing = self.store.partGet(ref, cid)
        if existing and existing.state == 'active' then return true, { replayed = true } end
        if existing then return false, 'already_left' end
        if s.status == 'active' and not def.allowJoin then return false, 'join_closed' end
        if self.store.partCountActive(ref) >= def.participants.max then return false, 'session_full' end
        if self:_cooldownLeft('character', cid, def.id) > 0 then return false, 'character_cooldown' end
        local src = self.chars.sourceOf(cid)
        if not src then return false, 'participant_offline' end
        if self.chars.bucket(src) ~= s.bucket then return false, 'bucket_mismatch' end
        if self.store.charBusy(cid, def.busyGroup) then return false, 'character_busy' end
        local ok, whyP = self.store.partInsert({ session_ref = ref, character_id = cid, role = 'member', active_key = cid .. ':' .. def.busyGroup, joined_at = self.now() })
        if not ok then return false, whyP == 'character_busy' and 'character_busy' or 'internal_error' end
        self:_event(s, 'participant_added', cid, { role = 'member' }, 'join:' .. cid)
        return true, { joined = true }
    end)
end

-- state: 'left' (deliberate/disconnect) | 'failed' (incapacitated etc.). The last active participant leaving fails the session.
function Core:_leave(s, cid, state, reason)
    local now = self.now()
    local n = self.store.partCas(s.reference, cid, { 'active' }, { state = state, active_key = false, left_at = now, left_reason = reason })
    if n ~= 1 then return false, 'not_participant' end
    self:_event(s, 'participant_removed', cid, { state = state, reason = reason }, 'leave:' .. cid)
    local def = self.activities[s.activity_id]
    local remaining = self.store.partCountActive(s.reference)
    if remaining == 0 then self:_finish(s, 'failed', 'all_participants_gone', nil); return true, { sessionEnded = true } end
    if cid == s.leader_cid and def and def.policy.onInitiatorLeave == 'fail' then
        self:_finish(s, 'failed', 'initiator_left', nil); return true, { sessionEnded = true }
    end
    return true, { remaining = remaining }
end

function Core:Leave(invoker, ref, cid, state, reason)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    if not isCid(cid) then return false, 'invalid_character' end
    state = state == 'failed' and 'failed' or 'left'
    reason = type(reason) == 'string' and reason:match('^[%w_%-]+$') and reason:sub(1, 32) or 'left'
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status ~= 'created' and s.status ~= 'active' then return false, 'terminal' end
        return self:_leave(s, cid, state, reason)
    end)
end

-- --------------------------------------------------------------------- stages

function Core:Advance(invoker, ref, expectedStage, nextStage, ctx)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    if not isId(expectedStage, 24) or not isId(nextStage, 24) then return false, 'invalid_stage' end
    local def = self.activities[s.activity_id]
    if not def then return false, 'unknown_activity' end
    ctx = type(ctx) == 'table' and ctx or {}
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status ~= 'created' and s.status ~= 'active' then return false, 'terminal' end
        if s.current_stage == nextStage and s.prev_stage == expectedStage then return true, { stage = nextStage, replayed = true } end
        if s.current_stage ~= expectedStage then return false, 'stale_stage' end
        if def.stages then
            local ni, ci = def.stageIndex[nextStage], def.stageIndex[expectedStage]
            if not ni then return false, 'unknown_stage' end
            if def.strictOrder and ni ~= (ci or 0) + 1 then return false, 'stage_order' end
        end
        if ctx.characterId ~= nil then
            if not isCid(ctx.characterId) then return false, 'invalid_character' end
            local part = self.store.partGet(ref, ctx.characterId)
            if not part or part.state ~= 'active' then return false, 'not_participant' end
            local src = self.chars.sourceOf(ctx.characterId)
            if not src or self.chars.bucket(src) ~= s.bucket then return false, 'bucket_mismatch' end
        end
        local now = self.now()
        local patch = { current_stage = nextStage, prev_stage = expectedStage, stage_changed_at = now, updated_at = now }
        if s.status == 'created' then patch.status, patch.started_at = 'active', now end
        local n = self.store.sessCas(ref, OPEN, patch, { current_stage = expectedStage })
        if n ~= 1 then return false, 'stale_stage' end
        if s.status == 'created' then self:_event(s, 'session_active', ctx.characterId, nil, 'active') end
        self:_event(s, 'stage_advanced', ctx.characterId, { from = expectedStage, to = nextStage })
        return true, { stage = nextStage, status = 'active' }
    end)
end

-- ------------------------------------------------------------------- dispatch

function Core:_sendDispatch(s, def, dtype)
    local label = s.site_label or def.label
    local coords = s.coords_x and { x = s.coords_x, y = s.coords_y, z = s.coords_z } or nil
    if not coords then return false end
    -- Only safe, server-built data: category, configured label/location, priority and the session reference. No participants.
    return self.dispatch.send({ category = def.category, label = label, text = ('%s: %s'):format(label, def.dispatch.types[dtype]),
        coords = coords, priority = def.dispatch.priority, reference = s.reference, bucket = s.bucket, type = dtype }) == true
end

function Core:Dispatch(invoker, ref, dtype)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    local def = self.activities[s.activity_id]
    if not def then return false, 'unknown_activity' end
    if def.dispatch.mode == 'none' then return false, 'dispatch_disabled' end
    if type(dtype) ~= 'string' or not def.dispatch.types[dtype] then return false, 'invalid_dispatch_type' end
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status ~= 'active' then return false, s.status == 'created' and 'not_active' or 'terminal' end
        if (tonumber(s.dispatch_count) or 0) >= self.cfg.Limits.maxDispatchesPerSession then return false, 'dispatch_limit' end
        if def.dispatch.mode == 'stage' and not def.dispatch.stages[s.current_stage] then return false, 'dispatch_stage' end
        if s.dispatch_pending_type then
            if s.dispatch_pending_type == dtype then return true, { state = 'pending', replayed = true } end
            return false, 'dispatch_pending'
        end
        -- once per type per session: the unique journal key makes a duplicate/race a no-op
        local first = self:_event(s, 'dispatch_requested', nil, { type = dtype }, 'dispatch:' .. dtype)
        if not first then return true, { state = s.dispatch_state, replayed = true } end
        local now = self.now()
        local mode = def.dispatch.mode
        if mode == 'chance' and self.rand() > def.dispatch.chance then
            self.store.sessCas(ref, OPEN, { dispatch_state = 'suppressed', dispatch_count = (tonumber(s.dispatch_count) or 0) + 1, updated_at = now })
            self:_event(s, 'dispatch_suppressed', nil, { type = dtype })
            return true, { state = 'suppressed' }
        end
        if mode == 'delayed' and def.dispatch.delaySeconds > 0 then
            self.store.sessCas(ref, OPEN, { dispatch_state = 'pending', dispatch_pending_type = dtype, dispatch_at = now + def.dispatch.delaySeconds,
                dispatch_attempts = 0, dispatch_count = (tonumber(s.dispatch_count) or 0) + 1, updated_at = now })
            self:_event(s, 'dispatch_pending', nil, { type = dtype, at = now + def.dispatch.delaySeconds })
            return true, { state = 'pending' }
        end
        local sent = self:_sendDispatch(s, def, dtype)
        if sent then
            self.store.sessCas(ref, OPEN, { dispatch_state = 'sent', dispatch_count = (tonumber(s.dispatch_count) or 0) + 1, updated_at = now })
            self:_event(s, 'dispatch_triggered', nil, { type = dtype })
            return true, { state = 'sent' }
        end
        -- law unavailable: keep it pending so the sweep retries; the client never decides that "police were not alerted"
        self.store.sessCas(ref, OPEN, { dispatch_state = 'pending', dispatch_pending_type = dtype, dispatch_at = now + self.cfg.Dispatch.retryBaseSeconds,
            dispatch_attempts = 1, dispatch_count = (tonumber(s.dispatch_count) or 0) + 1, updated_at = now })
        self:_event(s, 'dispatch_failed', nil, { type = dtype, retry = true })
        return true, { state = 'pending' }
    end)
end

function Core:_runPendingDispatch(s, now)
    local def = self.activities[s.activity_id]
    if not def or not s.dispatch_pending_type or (tonumber(s.dispatch_at) or 0) > now then return end
    local dtype = s.dispatch_pending_type
    if self:_sendDispatch(s, def, dtype) then
        self.store.sessCas(s.reference, OPEN, { dispatch_state = 'sent', dispatch_pending_type = false, dispatch_at = false, updated_at = now })
        self:_event(s, 'dispatch_triggered', nil, { type = dtype, delayed = true })
        return
    end
    local attempts = (tonumber(s.dispatch_attempts) or 0) + 1
    if attempts >= self.cfg.Dispatch.maxAttempts then
        self.store.sessCas(s.reference, OPEN, { dispatch_state = 'failed', dispatch_pending_type = false, dispatch_at = false, updated_at = now })
        self:_event(s, 'dispatch_failed', nil, { type = dtype, final = true })
        return
    end
    self.store.sessCas(s.reference, OPEN, { dispatch_attempts = attempts, dispatch_at = now + self.cfg.Dispatch.retryBaseSeconds * attempts, updated_at = now })
end

-- ------------------------------------------------------------------ terminal

-- The ONE place a session ends. A single guarded UPDATE decides the winner of any complete/fail/cancel/expire race.
function Core:_finish(s, status, reason, resultTier)
    local def = self.activities[s.activity_id]
    local now = self.now()
    local patch = { status = status, active_site = false, completed_at = now, outcome = status, end_reason = reason, updated_at = now,
        dispatch_pending_type = false, dispatch_at = false }
    if status == 'succeeded' then
        if def and def.reward.enabled then patch.reward_state, patch.reward_token = 'pending', self:_token() else patch.reward_state = 'none' end
        patch.outcome = resultTier or 'success'
    end
    local n = self.store.sessCas(s.reference, OPEN, patch)
    if n ~= 1 then return false end
    self.store.partReleaseAll(s.reference, 'ended', reason)
    local fresh = self.store.sessGet(s.reference) or s
    if def and status ~= 'cancelled' then self:_applyCooldowns(fresh, def, status) end
    self:_event(fresh, 'session_' .. status, nil, { reason = reason, outcome = patch.outcome }, 'terminal')
    if status == 'succeeded' and patch.reward_token then self:_event(fresh, 'reward_authorized', nil, nil, 'reward_authorized') end
    self:_mirror('crime_session_' .. status, fresh, { reason = reason })
    return true, fresh
end

local RESULT_KEYS = { tier = true, note = true }

function Core:Complete(invoker, ref, result)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    -- The result is a descriptor only. Money, items, XP or any other payload is rejected: cm-crime authorizes, the owner pays.
    if result ~= nil then
        if type(result) ~= 'table' then return false, 'invalid_result' end
        for k, v in pairs(result) do
            if not RESULT_KEYS[k] or type(v) ~= 'string' or #v > 24 or not v:match('^[%w_ %-]*$') then return false, 'invalid_result' end
        end
    end
    local tier = result and result.tier and result.tier ~= '' and result.tier or nil
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status == 'succeeded' then
            return true, { reference = ref, status = 'succeeded', replayed = true, rewardState = s.reward_state, rewardToken = s.reward_token }
        end
        if TERMINAL[s.status] then return false, 'terminal_' .. s.status end
        if s.status ~= 'active' then return false, 'not_active' end
        local ok, fresh = self:_finish(s, 'succeeded', 'completed', tier)
        if not ok then
            local cur = self.store.sessGet(ref)
            if cur and cur.status == 'succeeded' then return true, { reference = ref, status = 'succeeded', replayed = true, rewardState = cur.reward_state, rewardToken = cur.reward_token } end
            return false, 'terminal_' .. tostring(cur and cur.status or 'unknown')
        end
        return true, { reference = ref, status = 'succeeded', rewardState = fresh.reward_state, rewardToken = fresh.reward_token }
    end)
end

local function terminalCall(self, invoker, ref, status, reason, from)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    reason = type(reason) == 'string' and reason:match('^[%w_%-]+$') and reason:sub(1, 32) or status
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status == status then return true, { reference = ref, status = status, replayed = true } end
        if TERMINAL[s.status] then return false, 'terminal_' .. s.status end
        if from == 'active' and s.status ~= 'active' and s.status ~= 'created' then return false, 'invalid_state' end
        local ok = self:_finish(s, status, reason, nil)
        if not ok then
            local cur = self.store.sessGet(ref)
            if cur and cur.status == status then return true, { reference = ref, status = status, replayed = true } end
            return false, 'terminal_' .. tostring(cur and cur.status or 'unknown')
        end
        return true, { reference = ref, status = status }
    end)
end

function Core:Fail(invoker, ref, reason) return terminalCall(self, invoker, ref, 'failed', reason or 'failed', 'active') end
function Core:Cancel(invoker, ref, reason) return terminalCall(self, invoker, ref, 'cancelled', reason or 'cancelled', 'active') end

-- ---------------------------------------------------------------------- reward

-- The owner confirms it applied the proceeds through the authoritative owner. cm-crime only records that fact (once).
function Core:ConfirmReward(invoker, ref, token)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status ~= 'succeeded' or not s.reward_token then return false, 'no_reward' end
        if type(token) ~= 'string' or token ~= s.reward_token then return false, 'invalid_token' end
        if s.reward_state == 'delivered' then return true, { replayed = true, rewardState = 'delivered' } end
        local n = self.store.sessCas(ref, { 'succeeded' }, { reward_state = 'delivered', reward_at = self.now(), updated_at = self.now() }, { reward_states = { 'pending', 'failed' } })
        if n ~= 1 then return false, 'invalid_state' end
        self:_event(s, 'reward_delivered', nil, nil, 'reward_delivered')
        self:_mirror('crime_reward_delivered', s)
        return true, { rewardState = 'delivered' }
    end)
end

function Core:ReportRewardFailure(invoker, ref, token, reason)
    local s, why = self:_mine(invoker, ref)
    if not s then return false, why end
    return self:_lock('sess:' .. ref, function()
        s = self.store.sessGet(ref)
        if s.status ~= 'succeeded' or not s.reward_token then return false, 'no_reward' end
        if type(token) ~= 'string' or token ~= s.reward_token then return false, 'invalid_token' end
        if s.reward_state == 'delivered' then return false, 'already_delivered' end
        if s.reward_state == 'failed' then return true, { replayed = true, rewardState = 'failed' } end
        self.store.sessCas(ref, { 'succeeded' }, { reward_state = 'failed', updated_at = self.now() }, { reward_states = { 'pending' } })
        self:_event(s, 'reward_failed', nil, { reason = type(reason) == 'string' and reason:sub(1, 32) or nil })
        return true, { rewardState = 'failed' }
    end)
end

-- --------------------------------------------------------------------- sweep

function Core:_online(cid, now)
    if self.chars.sourceOf(cid) then self.offlineSince[cid] = nil; return true, 0 end
    self.offlineSince[cid] = self.offlineSince[cid] or now
    return false, now - self.offlineSince[cid]
end

-- Expiry, disconnects, owner stop, pending dispatch and stuck reward confirmation. Idempotent; also the restart recovery path.
function Core:Sweep()
    local now = self.now()
    local stats = { expired = 0, left = 0, ownerStopped = 0, dispatched = 0, rewardsFlagged = 0 }
    for _, row in ipairs(self.store.sessListActive(200)) do
        self:_lock('sess:' .. row.reference, function()
            local s = self.store.sessGet(row.reference)
            if not s or (s.status ~= 'created' and s.status ~= 'active') then return end
            local def = self.activities[s.activity_id]
            if now >= (tonumber(s.expires_at) or now) then
                if self:_finish(s, 'expired', 'timeout', nil) then stats.expired = stats.expired + 1 end
                return
            end
            -- content owner stopped (or never re-registered after a restart): fail/cancel after its grace
            local up = self.owners.started(s.owner_resource) and def ~= nil
            if up then self.ownerDownSince[s.reference] = nil
            else
                self.ownerDownSince[s.reference] = self.ownerDownSince[s.reference] or now
                local grace = def and def.policy.ownerStopGraceSeconds or self.cfg.Defaults.policy.ownerStopGraceSeconds
                if now - self.ownerDownSince[s.reference] >= grace then
                    local how = def and def.policy.onOwnerStop == 'cancel' and 'cancelled' or 'failed'
                    if self:_finish(s, how, 'owner_stopped', nil) then stats.ownerStopped = stats.ownerStopped + 1 end
                    return
                end
            end
            local grace = def and def.policy.disconnectGraceSeconds or self.cfg.Defaults.policy.disconnectGraceSeconds
            for _, p in ipairs(self.store.partList(s.reference)) do
                if p.state == 'active' then
                    local on, off = self:_online(p.character_id, now)
                    if not on and off >= grace then
                        local ok, r = self:_leave(s, p.character_id, 'left', 'disconnected')
                        if ok then stats.left = stats.left + 1 end
                        if ok and r and r.sessionEnded then return end
                    end
                end
            end
            if s.dispatch_pending_type then self:_runPendingDispatch(self.store.sessGet(s.reference), now); stats.dispatched = stats.dispatched + 1 end
        end)
    end
    for _, s in ipairs(self.store.rewardsPending(now - self.cfg.Reward.pendingSeconds, 100)) do
        if self.store.sessCas(s.reference, { 'succeeded' }, { reward_state = 'failed', updated_at = now }, { reward_states = { 'pending' } }) == 1 then
            self:_event(s, 'reconciliation', nil, { reason = 'reward_confirmation_timeout' }, 'reward_timeout')
            self:_mirror('crime_reward_unconfirmed', s)
            stats.rewardsFlagged = stats.rewardsFlagged + 1
        end
    end
    return true, stats
end

-- ----------------------------------------------------------------------- admin

function Core:AdminList(filter)
    local rows = self.store.sessListActive(100)
    local out = {}
    for _, s in ipairs(rows) do out[#out + 1] = self:_view(s) end
    return true, out
end

function Core:AdminInspect(ref)
    if not isId(ref, 24) then return false, 'invalid_reference' end
    local s = self.store.sessGet(ref)
    if not s then return false, 'not_found' end
    return true, { session = self:_view(s), rewardToken = nil, events = self.store.eventList(ref, 60) }
end

function Core:AdminCooldowns(filter) return true, self.store.cooldownList(type(filter) == 'table' and filter or {}) end

function Core:AdminCancel(ref, label)
    if not isId(ref, 24) then return false, 'invalid_reference' end
    return self:_lock('sess:' .. ref, function()
        local s = self.store.sessGet(ref)
        if not s then return false, 'not_found' end
        if TERMINAL[s.status] then return false, 'terminal_' .. s.status end
        local ok = self:_finish(s, 'cancelled', 'admin_cancel', nil)
        if not ok then return false, 'terminal' end
        self:_event(s, 'admin_cancel', label or 'admin', nil)
        return true
    end)
end

-- Force reconciliation: re-run sweep rules for one session, or resolve an unconfirmed reward ('delivered' | 'failed').
function Core:AdminReconcile(ref, resolution, label)
    if ref == nil then return self:Sweep() end
    if not isId(ref, 24) then return false, 'invalid_reference' end
    return self:_lock('sess:' .. ref, function()
        local s = self.store.sessGet(ref)
        if not s then return false, 'not_found' end
        if resolution == 'delivered' or resolution == 'failed' then
            if s.status ~= 'succeeded' or not s.reward_token then return false, 'no_reward' end
            local n = self.store.sessCas(ref, { 'succeeded' }, { reward_state = resolution, reward_at = resolution == 'delivered' and self.now() or nil, updated_at = self.now() },
                { reward_states = { 'pending', 'failed' } })
            if n ~= 1 and s.reward_state ~= resolution then return false, 'invalid_state' end
            self:_event(s, 'reconciliation', label or 'admin', { resolution = resolution })
            self:_mirror('crime_reconciled', s, { resolution = resolution })
            return true, { rewardState = resolution }
        end
        self:_event(s, 'reconciliation', label or 'admin', { resolution = 'sweep' })
        return true, { status = s.status }
    end)
end
