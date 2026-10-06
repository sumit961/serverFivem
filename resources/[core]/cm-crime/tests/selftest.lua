-- Deterministic local self-test for cm-crime (no FiveM, no database).
--   lua tests/selftest.lua        (run from resources/[core]/cm-crime)
-- REAL: cm-crime core + config. DOUBLES (labelled): the in-memory store (same CAS / UNIQUE semantics as server/store.lua), characters,
-- the law police-count adapter and the law dispatch adapter. `test_small_crime` exists ONLY here: it is not live gameplay.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
CMCrime = {}
dofile(here .. '/config.lua')
dofile(here .. '/server/core.lua')

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
local function ser(v)
    if type(v) == 'table' then
        local keys = {} for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local o = {} for _, k in ipairs(keys) do o[#o + 1] = tostring(k) .. '=' .. ser(v[k]) end
        return '{' .. table.concat(o, ',') .. '}'
    end
    return tostring(v)
end
local function deepcopy(t) if type(t) ~= 'table' then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end

-- --------------------------------------------------------- fake store (mirrors server/store.lua)
local function newStore()
    local S = { sessions = {}, parts = {}, cooldowns = {}, events = {} }
    local function copy(r) if not r then return nil end local c = {} for k, v in pairs(r) do c[k] = v end return c end
    local function inList(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
    local function find(ref) for _, s in ipairs(S.sessions) do if s.reference == ref then return s end end end
    function S.sessInsert(s)
        for _, x in ipairs(S.sessions) do
            if s.idem_key and x.idem_key == s.idem_key then return nil, 'duplicate_key' end
            if s.active_site and x.active_site == s.active_site then return nil, 'site_occupied' end
        end
        local c = copy(s); c.id = #S.sessions + 1; c.dispatch_attempts = 0; S.sessions[#S.sessions + 1] = c; return c.id
    end
    function S.sessGet(ref) return copy(find(ref)) end
    function S.sessGetByIdem(k) for _, x in ipairs(S.sessions) do if x.idem_key == k then return copy(x) end end end
    function S.siteActive(site) for _, x in ipairs(S.sessions) do if x.active_site == site and (x.status == 'created' or x.status == 'active') then return copy(x) end end end
    function S.sessListActive() local o = {} for _, x in ipairs(S.sessions) do if x.status == 'created' or x.status == 'active' then o[#o + 1] = copy(x) end end return o end
    function S.rewardsPending(before) local o = {} for _, x in ipairs(S.sessions) do if x.status == 'succeeded' and x.reward_state == 'pending' and x.completed_at < before then o[#o + 1] = copy(x) end end return o end
    function S.sessCas(ref, from, patch, where)
        local s = find(ref)
        if not s or not inList(from, s.status) then return 0 end
        if where and where.current_stage and s.current_stage ~= where.current_stage then return 0 end
        if where and where.reward_states and not inList(where.reward_states, s.reward_state) then return 0 end
        for k, v in pairs(patch) do if v == false then s[k] = nil else s[k] = v end end
        return 1
    end
    function S.partInsert(p)
        for _, x in ipairs(S.parts) do if p.active_key and x.active_key == p.active_key then return false, 'character_busy' end
            if x.session_ref == p.session_ref and x.character_id == p.character_id then return false, 'character_busy' end end
        local c = copy(p); c.state = 'active'; S.parts[#S.parts + 1] = c; return true
    end
    function S.partGet(ref, cid) for _, x in ipairs(S.parts) do if x.session_ref == ref and x.character_id == cid then return copy(x) end end end
    function S.partList(ref) local o = {} for _, x in ipairs(S.parts) do if x.session_ref == ref then o[#o + 1] = copy(x) end end return o end
    function S.partCountActive(ref) local n = 0 for _, x in ipairs(S.parts) do if x.session_ref == ref and x.state == 'active' then n = n + 1 end end return n end
    function S.charBusy(cid, group) for _, x in ipairs(S.parts) do if x.active_key == cid .. ':' .. group then return true end end return false end
    function S.partCas(ref, cid, from, patch)
        for _, x in ipairs(S.parts) do
            if x.session_ref == ref and x.character_id == cid and inList(from, x.state) then
                for k, v in pairs(patch) do if v == false then x[k] = nil else x[k] = v end end
                return 1
            end
        end
        return 0
    end
    function S.partReleaseAll(ref, state, reason) for _, x in ipairs(S.parts) do if x.session_ref == ref and x.state == 'active' then x.state, x.active_key, x.left_reason = state, nil, reason end end end
    function S.cooldownGet(scope, key, act) local c = S.cooldowns[scope .. '|' .. key .. '|' .. act]; return c and c.expires_at end
    function S.cooldownSet(scope, key, act, exp, reason, ref)
        local k = scope .. '|' .. key .. '|' .. act
        local c = S.cooldowns[k]
        if c then c.expires_at = math.max(c.expires_at, exp) else S.cooldowns[k] = { scope = scope, scope_key = key, activity_id = act, expires_at = exp, reason = reason, session_ref = ref } end
    end
    function S.cooldownList() local o = {} for _, c in pairs(S.cooldowns) do o[#o + 1] = copy(c) end return o end
    function S.eventInsert(e)
        if e.key then for _, x in ipairs(S.events) do if x.key == e.key then return false end end end
        S.events[#S.events + 1] = copy(e); return true
    end
    function S.eventList(ref) local o = {} for _, e in ipairs(S.events) do if e.session_ref == ref then o[#o + 1] = e end end return o end
    function S.count(kind, ref) local n = 0 for _, e in ipairs(S.events) do if e.kind == kind and (not ref or e.session_ref == ref) then n = n + 1 end end return n end
    function S.cooldownRows() local n = 0 for _ in pairs(S.cooldowns) do n = n + 1 end return n end
    return S
end

-- ------------------------------------------------------------------------------ world
local W
local OWNER, OTHER = 'cm-test-crime', 'cm-other-crime'
local DEF = { id = 'test_small_crime', category = 'retail', label = 'Test Small Crime', minPolice = 1, participants = { min = 1, max = 3 }, allowJoin = true,
    sessionSeconds = 600, siteMode = 'exclusive', busyGroup = 'high_value',
    cooldowns = { site = 1800, activity = 60, character = 300, onFailure = 'partial', partialFactor = 0.5 },
    dispatch = { mode = 'immediate', priority = 2, types = { alarm = 'Alarm triggered', shots = 'Shots fired' } },
    stages = { 'approach', 'breach', 'escape' }, strictOrder = true,
    policy = { onInitiatorLeave = 'continue', disconnectGraceSeconds = 60, ownerStopGraceSeconds = 60 } }

local function newWorld(store, keepWorld)
    local prev = W
    W = keepWorld and prev or { now = 1000000, online = {}, bucket = {}, police = 2, dispatchLog = {}, dispatchOk = true, ownersUp = { [OWNER] = true, [OTHER] = true },
        audits = {}, rateBlock = false, sources = 0 }
    if not keepWorld then
        for _, cid in ipairs({ '101', '102', '103', '104', '105' }) do W.sources = W.sources + 1; W.online[cid] = 1000 + W.sources; W.bucket[W.online[cid]] = 0 end
    end
    local cfg = deepcopy(CMCrime.Config)
    cfg.TrustedOwners = { [OWNER] = true, [OTHER] = true }
    W.cfg = cfg
    W.store = store or W.store or newStore()
    local seq = W.seed or 12345
    W.seed = (W.seed or 12345) + 7919   -- distinct deterministic stream per core instance (references never collide across restarts)
    W.core = CMCrime.Core.New({
        cfg = cfg, store = W.store, now = function() return W.now end,
        rand = function(a, b) seq = (seq * 1103515245 + 12345) % 2147483648; if a then return (seq // 65536) % (b - a + 1) + a end return W.randValue or 0.0 end,
        encode = ser,
        chars = { sourceOf = function(cid) return W.online[cid] end, bucket = function(src) return W.bucket[src] end },
        police = { count = function(org) return W.police end },
        dispatch = { send = function(info) W.dispatchLog[#W.dispatchLog + 1] = info; return W.dispatchOk end },
        owners = { started = function(r) return W.ownersUp[r] == true end },
        audit = function(kind, d) W.audits[#W.audits + 1] = { kind = kind, detail = d } end,
        rate = function() return not W.rateBlock end,
    })
    W.core.rand = W.core.rand
    return W
end
local function register(def, owner) return W.core:RegisterActivity(owner or OWNER, def or DEF) end
local function begin(cids, site, extra)
    local ctx = { siteKey = site or 'store:24', leaderCharacterId = cids[1], participantCharacterIds = { table.unpack(cids, 2) }, siteLabel = 'Test Store 24',
        coords = { x = 100.0, y = 200.0, z = 30.0 } }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    return W.core:Begin(OWNER, 'test_small_crime', ctx)
end
local function fresh() newWorld(); register(); return W end
local function stageUp(ref, ...) local prev, ok, r = 'approach' for _, nxt in ipairs({ ... }) do ok, r = W.core:Advance(OWNER, ref, prev, nxt, {}); prev = nxt end return ok, r end
local function sess(ref) return W.store.sessGet(ref) end
local function countKind(kind, ref) return W.store.count(kind, ref) end

-- ======================================================================================== REGISTRATION
do
    newWorld()
    check('REGISTRATION trusted owner registers a valid activity', select(1, register()) == true)
    check('REGISTRATION re-registering the same owner replaces its own definition (restart/hot reload)', select(2, register()).replaced == true)
    check('REGISTRATION untrusted resource rejected', select(2, W.core:RegisterActivity('cm-evil', DEF)) == 'untrusted_resource')
    check('REGISTRATION nil/empty invoker rejected (a client can never register)', select(2, W.core:RegisterActivity(nil, DEF)) == 'untrusted_resource' and select(2, W.core:RegisterActivity('', DEF)) == 'untrusted_resource')
    check('REGISTRATION duplicate activity id from another trusted owner rejected (owner pinned)', select(2, W.core:RegisterActivity(OTHER, DEF)) == 'owner_mismatch')
    check('REGISTRATION definition keeps the original owner after a rejected takeover', W.core.activities.test_small_crime.owner == OWNER)
    check('REGISTRATION invalid ids/definitions rejected', select(2, register({ id = 'Bad Id' })) == 'invalid_id' and select(2, register('x')) == 'invalid_definition' and select(2, register({ id = 'ab' })) == 'invalid_id')
    check('REGISTRATION participants min > max rejected', select(2, register({ id = 'bad_parts', participants = { min = 3, max = 2 } })) == 'invalid_participants')
    check('REGISTRATION dispatch mode without types rejected', select(2, register({ id = 'bad_disp', dispatch = { mode = 'immediate' } })) == 'invalid_dispatch')
    check('REGISTRATION duplicate stage names rejected', select(2, register({ id = 'bad_stage', stages = { 'a1', 'a1' } })) == 'invalid_stages')
    check('REGISTRATION bounds are clamped (huge police/session/cooldown cannot exceed limits)', (function()
        register({ id = 'clamp_me', minPolice = 9999, sessionSeconds = 99999999, cooldowns = { site = 999999999 } })
        local d = W.core.activities.clamp_me; return d.minPolice == 32 and d.sessionSeconds == 7200 and d.cooldowns.site == 30 * 24 * 3600 end)())
    check('REGISTRATION defaults: exclusive site, 1 participant, no police, no dispatch', (function()
        register({ id = 'plain_one' }); local d = W.core.activities.plain_one
        return d.siteMode == 'exclusive' and d.participants.max == 1 and d.minPolice == 0 and d.dispatch.mode == 'none' end)())
    check('REGISTRATION empty TrustedOwners (shipped default) is fail closed', select(2, CMCrime.Core.New({ cfg = CMCrime.Config, store = newStore(), chars = {} }):RegisterActivity('anything', DEF)) == 'untrusted_resource')
    check('REGISTRATION wrong owner cannot begin a session of another owner\'s activity', select(2, W.core:Begin(OTHER, 'test_small_crime', { siteKey = 'store:1', leaderCharacterId = '101' })) == 'forbidden')
    check('REGISTRATION unknown activity rejected', select(2, W.core:Begin(OWNER, 'nope_nope', {})) == 'unknown_activity')
end

-- ======================================================================================== START
do
    fresh()
    local ok, r = begin({ '101' })
    check('START valid session is created with a reference, stage and expiry', ok == true and r.reference:match('^CR%-') ~= nil and r.status == 'created' and r.stage == 'approach' and r.expiresAt == W.now + 600)
    local s = sess(r.reference)
    check('START persisted session carries owner, site, leader, bucket', s.owner_resource == OWNER and s.site_key == 'store:24' and s.leader_cid == '101' and s.bucket == 0)
    check('START leader is a participant by CHARACTER id', W.store.partGet(r.reference, '101').role == 'leader')
    check('START nothing but character ids is persisted (no source ids)', (function()
        for _, p in ipairs(W.store.parts) do for k in pairs(p) do if k:find('source_id') or k:find('server_id') or k == 'src' then return false end end end
        for k in pairs(s) do if k:find('source_id') or k:find('server_id') or k == 'src' then return false end end return true end)())
    check('START creates $0 / 0 items / 0 XP: the core exposes no economy surface', (function()
        for k in pairs(CMCrime.Core) do local l = k:lower(); if l:find('cash') or l:find('money') or l:find('item') or l:find('xp') or l:find('pay') then return false end end return true end)())
    check('START session_created + participant_added events recorded', countKind('session_created', r.reference) == 1 and countKind('participant_added', r.reference) == 1)
    check('START unknown activity rejected', select(2, W.core:Begin(OWNER, 'unknown_one', { siteKey = 'store:9', leaderCharacterId = '102' })) == 'unknown_activity')
    check('START invalid site key rejected (no free-form / coordinate sites)', select(2, begin({ '102' }, 'x y')) == 'invalid_site' and select(2, begin({ '102' }, nil, { siteKey = 123 })) == 'invalid_site')
    check('START invalid / non-numeric character id rejected', select(2, begin({ 'abc' }, 'store:30')) == 'invalid_character' and select(2, W.core:Begin(OWNER, 'test_small_crime', { siteKey = 'store:30' })) == 'invalid_character')
    check('START offline leader rejected', select(2, begin({ '999' }, 'store:31')) == 'participant_offline')
    check('START character already busy in an active crime rejected', select(2, begin({ '101' }, 'store:25')) == 'character_busy')
    W.police = 0
    check('START police insufficient rejected', select(2, begin({ '102' }, 'store:26')) == 'not_enough_police')
    W.police = nil
    check('START police unknown fails CLOSED (no guessing)', select(2, begin({ '102' }, 'store:26')) == 'police_unavailable')
    W.police = 1
    check('START police exactly at the minimum is allowed', select(1, begin({ '102' }, 'store:26')) == true)
    register({ id = 'no_police', siteMode = 'exclusive' })
    W.police = nil
    check('START activity with minPolice 0 does not need the police adapter', select(1, W.core:Begin(OWNER, 'no_police', { siteKey = 'atm:1', leaderCharacterId = '103' })) == true)
    W.police = 2
    check('START participant count outside min/max rejected', select(2, begin({ '104', '105', '103', '102' }, 'store:40')) == 'participant_count')
    check('START participants must share a routing bucket', (function() W.bucket[W.online['105']] = 7; local why = select(2, begin({ '104', '105' }, 'store:41')); W.bucket[W.online['105']] = 0; return why == 'bucket_mismatch' end)())
    check('START metadata too large / non-table rejected', select(2, begin({ '104' }, 'store:42', { metadata = 'x' })) == 'invalid_metadata' and select(2, begin({ '104' }, 'store:42', { metadata = { blob = string.rep('x', 2000) } })) == 'invalid_metadata')
    check('START malformed coords rejected', select(2, begin({ '104' }, 'store:42', { coords = { x = 1 } })) == 'invalid_coords')
    check('START rate limit enforced', (function() W.rateBlock = true; local why = select(2, begin({ '104' }, 'store:43')); W.rateBlock = false; return why == 'rate_limited' end)())
    check('START CanBegin is a read-only pre-check with the same rules', select(1, W.core:CanBegin(OWNER, 'test_small_crime', { siteKey = 'store:50', leaderCharacterId = '104' })) == true and select(2, W.core:CanBegin(OWNER, 'test_small_crime', { siteKey = 'store:24', leaderCharacterId = '104' })) == 'site_occupied' and select(1, W.core:CanBegin(OWNER, 'test_small_crime', { siteKey = 'store:50', leaderCharacterId = '104' })) == true)
    check('START CanBegin created nothing', (function() local n = 0 for _, x in ipairs(W.store.sessions) do if x.site_key == 'store:50' then n = n + 1 end end return n == 0 end)())
    check('START idempotency key returns the same session (retry safe)', (function()
        local a = select(2, begin({ '104' }, 'store:60', { idempotencyKey = 'k1' })); local b = select(2, begin({ '104' }, 'store:60', { idempotencyKey = 'k1' }))
        return a.reference == b.reference and b.existing == true end)())
    check('START idempotency key reused for a different activity is a conflict', select(2, W.core:Begin(OWNER, 'no_police', { siteKey = 'atm:9', leaderCharacterId = '105', idempotencyKey = 'k1' })) == 'idempotency_conflict')
end

-- ======================================================================================== SITE LOCK / BUSY
do
    fresh()
    local a = select(2, begin({ '101' }, 'store:24'))
    check('SITE first group wins the site', a ~= nil and a.reference ~= nil)
    check('SITE second group at the same site rejected', select(2, begin({ '102' }, 'store:24')) == 'site_occupied')
    check('SITE a different site is independent', select(1, begin({ '102' }, 'store:25')) == true)
    check('SITE same site key under another activity id is still locked (site key is the authority)', (function()
        register({ id = 'other_act' }); return select(2, W.core:Begin(OWNER, 'other_act', { siteKey = 'store:24', leaderCharacterId = '103' })) == 'site_occupied' end)())
    check('SITE released after a terminal state', (function() W.core:Cancel(OWNER, a.reference, 'abort'); return select(1, begin({ '103' }, 'store:24')) == true end)())
    check('SITE no-lock activity allows concurrent sessions at one site key', (function()
        register({ id = 'open_site', siteMode = 'none' })
        local x = select(1, W.core:Begin(OWNER, 'open_site', { siteKey = 'zone:1', leaderCharacterId = '104' }))
        local y = select(1, W.core:Begin(OWNER, 'open_site', { siteKey = 'zone:1', leaderCharacterId = '105' })); return x == true and y == true end)())
    check('SITE race: two simultaneous starts, only one holds the lock (UNIQUE active_site)', (function()
        fresh(); local one = begin({ '101' }, 'store:70'); local two = begin({ '102' }, 'store:70')
        return one == true and two == false end)())
    check('BUSY a character in one high_value crime cannot start another', (function() fresh(); begin({ '101' }, 'store:1'); return select(2, begin({ '101' }, 'store:2')) == 'character_busy' end)())
    check('BUSY a different busyGroup may coexist (configurable compatibility)', (function()
        register({ id = 'low_value', busyGroup = 'low_value' }); return select(1, W.core:Begin(OWNER, 'low_value', { siteKey = 'atm:5', leaderCharacterId = '101' })) == true end)())
    check('BUSY a character is freed when the session ends', (function() fresh(); local r = select(2, begin({ '101' }, 'store:1')); W.core:Cancel(OWNER, r.reference); return select(1, begin({ '101' }, 'store:2')) == true end)())
end

-- ======================================================================================== PARTICIPANTS
do
    fresh()
    local r = select(2, begin({ '101' })); local ref = r.reference
    check('PARTICIPANTS leader is recorded', sess(ref).leader_cid == '101' and W.core:Get(OWNER, ref) and select(2, W.core:Get(OWNER, ref)).leaderCharacterId == '101')
    check('PARTICIPANTS join adds a member', select(1, W.core:Join(OWNER, ref, '102')) == true and W.store.partGet(ref, '102').role == 'member')
    check('PARTICIPANTS duplicate join is idempotent', select(2, W.core:Join(OWNER, ref, '102')).replayed == true and W.store.partCountActive(ref) == 2)
    check('PARTICIPANTS join respects max participants', (function() W.core:Join(OWNER, ref, '103'); return select(2, W.core:Join(OWNER, ref, '104')) == 'session_full' end)())
    check('PARTICIPANTS foreign participant (offline character) rejected', (function() fresh(); local r2 = select(2, begin({ '101' })); return select(2, W.core:Join(OWNER, r2.reference, '999')) == 'participant_offline' end)())
    check('PARTICIPANTS invalid cid rejected', select(2, W.core:Join(OWNER, ref, 'x1')) == 'invalid_character')
    check('PARTICIPANTS joiner in another routing bucket rejected', (function()
        fresh(); local r2 = select(2, begin({ '101' })); W.bucket[W.online['102']] = 9
        local why = select(2, W.core:Join(OWNER, r2.reference, '102')); W.bucket[W.online['102']] = 0; return why == 'bucket_mismatch' end)())
    check('PARTICIPANTS joiner busy in another crime rejected', (function()
        fresh(); local r2 = select(2, begin({ '101' }, 'store:1')); begin({ '102' }, 'store:2'); return select(2, W.core:Join(OWNER, r2.reference, '102')) == 'character_busy' end)())
    check('PARTICIPANTS joiner on character cooldown rejected', (function()
        fresh(); local r2 = select(2, begin({ '101' })); W.store.cooldownSet('character', '102', 'test_small_crime', W.now + 100, 'x', 'CR-X')
        return select(2, W.core:Join(OWNER, r2.reference, '102')) == 'character_cooldown' end)())
    check('PARTICIPANTS join after activation is refused when the activity disallows it', (function()
        fresh(); register({ id = 'closed_join', allowJoin = false, participants = { min = 1, max = 3 } })
        local r2 = select(2, W.core:Begin(OWNER, 'closed_join', { siteKey = 'atm:20', leaderCharacterId = '101' })); W.core:Advance(OWNER, r2.reference, 'started', 'go', {})
        return select(2, W.core:Join(OWNER, r2.reference, '102')) == 'join_closed' end)())
    check('PARTICIPANTS leave removes a member and frees the character', (function()
        fresh(); local r2 = select(2, begin({ '101', '102' })); local ok, x = W.core:Leave(OWNER, r2.reference, '102', 'left', 'quit')
        return ok == true and x.remaining == 1 and W.store.partGet(r2.reference, '102').state == 'left' and select(1, begin({ '102' }, 'store:9')) == true end)())
    check('PARTICIPANTS leaving twice is rejected', (function() fresh(); local r2 = select(2, begin({ '101', '102' })); W.core:Leave(OWNER, r2.reference, '102'); return select(2, W.core:Leave(OWNER, r2.reference, '102')) == 'not_participant' end)())
    check('PARTICIPANTS a member who left cannot silently rejoin', (function() fresh(); local r2 = select(2, begin({ '101', '102' })); W.core:Leave(OWNER, r2.reference, '102'); return select(2, W.core:Join(OWNER, r2.reference, '102')) == 'already_left' end)())
    check('PARTICIPANTS initiator leaves: session continues by default policy', (function()
        fresh(); local r2 = select(2, begin({ '101', '102' })); W.core:Leave(OWNER, r2.reference, '101'); return sess(r2.reference).status == 'created' and W.store.partCountActive(r2.reference) == 1 end)())
    check('PARTICIPANTS initiator leaves: session fails when the activity says so', (function()
        fresh(); register({ id = 'leader_fail', participants = { min = 1, max = 2 }, policy = { onInitiatorLeave = 'fail' } })
        local r2 = select(2, W.core:Begin(OWNER, 'leader_fail', { siteKey = 'atm:30', leaderCharacterId = '101', participantCharacterIds = { '102' } })); W.core:Leave(OWNER, r2.reference, '101')
        return sess(r2.reference).status == 'failed' and sess(r2.reference).end_reason == 'initiator_left' end)())
    check('PARTICIPANTS last participant gone fails the session', (function()
        fresh(); local r2 = select(2, begin({ '101' })); local ok, x = W.core:Leave(OWNER, r2.reference, '101', 'failed', 'incapacitated')
        return ok and x.sessionEnded == true and sess(r2.reference).status == 'failed' and sess(r2.reference).end_reason == 'all_participants_gone' end)())
    check('PARTICIPANTS participant failed state is recorded for incapacitation', (function()
        fresh(); local r2 = select(2, begin({ '101', '102' })); W.core:Leave(OWNER, r2.reference, '102', 'failed', 'incapacitated'); return W.store.partGet(r2.reference, '102').state == 'failed' end)())
end

-- ======================================================================================== STAGES
do
    fresh()
    local ref = select(2, begin({ '101' })).reference
    check('STAGES first advance activates the session', (function() local ok, r = W.core:Advance(OWNER, ref, 'approach', 'breach', {}); return ok and r.status == 'active' and sess(ref).status == 'active' and sess(ref).started_at == W.now end)())
    check('STAGES session_active journalled once', countKind('session_active', ref) == 1)
    check('STAGES stale expected stage rejected', select(2, W.core:Advance(OWNER, ref, 'approach', 'escape', {})) == 'stale_stage')
    check('STAGES replay of the same transition is idempotent', (function() local ok, r = W.core:Advance(OWNER, ref, 'approach', 'breach', {}); return ok == true and r.replayed == true and countKind('stage_advanced', ref) == 1 end)())
    check('STAGES skipping a stage is rejected when strictOrder', (function()
        fresh(); local r2 = select(2, begin({ '101' })).reference; return select(2, W.core:Advance(OWNER, r2, 'approach', 'escape', {})) == 'stage_order' end)())
    check('STAGES unknown stage rejected against the declared list', (function() fresh(); local r2 = select(2, begin({ '101' })).reference; return select(2, W.core:Advance(OWNER, r2, 'approach', 'teleport', {})) == 'unknown_stage' end)())
    check('STAGES owner mismatch rejected', (function() fresh(); local r2 = select(2, begin({ '101' })).reference; return select(2, W.core:Advance(OTHER, r2, 'approach', 'breach', {})) == 'forbidden' end)())
    check('STAGES forged character (not a participant) rejected', (function() fresh(); local r2 = select(2, begin({ '101' })).reference; return select(2, W.core:Advance(OWNER, r2, 'approach', 'breach', { characterId = '102' })) == 'not_participant' end)())
    check('STAGES participant in another routing bucket cannot progress it', (function()
        fresh(); local r2 = select(2, begin({ '101' })).reference; W.bucket[W.online['101']] = 4
        local why = select(2, W.core:Advance(OWNER, r2, 'approach', 'breach', { characterId = '101' })); W.bucket[W.online['101']] = 0; return why == 'bucket_mismatch' end)())
    check('STAGES valid participant advance accepted and attributed', (function()
        fresh(); local r2 = select(2, begin({ '101' })).reference; return select(1, W.core:Advance(OWNER, r2, 'approach', 'breach', { characterId = '101' })) == true end)())
    check('STAGES terminal session cannot advance', (function() fresh(); local r2 = select(2, begin({ '101' })).reference; W.core:Cancel(OWNER, r2); return select(2, W.core:Advance(OWNER, r2, 'approach', 'breach', {})) == 'terminal' end)())
    check('STAGES activity without a stage list uses free-form names', (function()
        register({ id = 'free_form' }); local r2 = select(2, W.core:Begin(OWNER, 'free_form', { siteKey = 'atm:70', leaderCharacterId = '101' })).reference
        return select(1, W.core:Advance(OWNER, r2, 'started', 'anything_goes', {})) == true end)())
    check('STAGES invalid stage ids rejected', select(2, W.core:Advance(OWNER, 'CR-ZZZZZZZZ', 'a b', 'c', {})) ~= true)
end

-- ======================================================================================== DISPATCH
do
    fresh()
    local ref = select(2, begin({ '101' })).reference
    check('DISPATCH before activation is refused', select(2, W.core:Dispatch(OWNER, ref, 'alarm')) == 'not_active')
    stageUp(ref, 'breach')
    local ok, r = W.core:Dispatch(OWNER, ref, 'alarm')
    check('DISPATCH valid immediate dispatch is sent via the law adapter', ok and r.state == 'sent' and #W.dispatchLog == 1 and sess(ref).dispatch_state == 'sent')
    local d = W.dispatchLog[1]
    check('DISPATCH payload is safe: category, label, text, coords, priority, reference only', d.category == 'retail' and d.label == 'Test Store 24' and d.reference == ref and d.priority == 2 and d.coords.x == 100.0
        and d.text == 'Test Store 24: Alarm triggered' and d.participants == nil and d.characterId == nil and d.leader == nil)
    check('DISPATCH once: duplicate type is ignored (no second call)', (function() local ok2, r2 = W.core:Dispatch(OWNER, ref, 'alarm'); return ok2 and r2.replayed == true and #W.dispatchLog == 1 end)())
    check('DISPATCH a different type is allowed', select(1, W.core:Dispatch(OWNER, ref, 'shots')) == true and #W.dispatchLog == 2)
    check('DISPATCH invalid type rejected (the client cannot supply text)', select(2, W.core:Dispatch(OWNER, ref, 'Free Text!')) == 'invalid_dispatch_type')
    check('DISPATCH wrong owner rejected', select(2, W.core:Dispatch(OTHER, ref, 'alarm')) == 'forbidden')
    check('DISPATCH unknown session rejected', select(2, W.core:Dispatch(OWNER, 'CR-NOPE0000', 'alarm')) == 'not_found')
    check('DISPATCH activity with mode none refuses', (function() register({ id = 'quiet_one' }); local r2 = select(2, W.core:Begin(OWNER, 'quiet_one', { siteKey = 'atm:80', leaderCharacterId = '102' })).reference
        W.core:Advance(OWNER, r2, 'started', 'go', {}); return select(2, W.core:Dispatch(OWNER, r2, 'alarm')) == 'dispatch_disabled' end)())
    check('DISPATCH race: concurrent identical triggers send once (journal key)', (function()
        fresh(); local r2 = select(2, begin({ '101' })).reference; stageUp(r2, 'breach')
        local before = #W.dispatchLog; W.core:Dispatch(OWNER, r2, 'alarm'); W.core:Dispatch(OWNER, r2, 'alarm'); return #W.dispatchLog - before == 1 end)())
    check('DISPATCH law unavailable keeps it pending and retries (client cannot suppress)', (function()
        fresh(); W.dispatchOk = false; local r2 = select(2, begin({ '101' })).reference; stageUp(r2, 'breach')
        local ok2, res = W.core:Dispatch(OWNER, r2, 'alarm'); local pending = sess(r2).dispatch_state == 'pending'
        W.dispatchOk = true; W.now = W.now + 31; W.core:Sweep()
        return ok2 and res.state == 'pending' and pending and sess(r2).dispatch_state == 'sent' end)())
    check('DISPATCH retries are bounded then marked failed', (function()
        fresh(); register({ id = 'long_disp', sessionSeconds = 7200, dispatch = { mode = 'immediate', types = { alarm = 'Alarm' } } }); W.dispatchOk = false
        local r2 = select(2, W.core:Begin(OWNER, 'long_disp', { siteKey = 'atm:120', leaderCharacterId = '101', coords = { x = 1.0, y = 2.0, z = 3.0 } })).reference
        W.core:Advance(OWNER, r2, 'started', 'go', {}); W.core:Dispatch(OWNER, r2, 'alarm')
        for _ = 1, 8 do W.now = W.now + 200; W.core:Sweep() end
        W.dispatchOk = true; return sess(r2).dispatch_state == 'failed' end)())
    check('DISPATCH delayed policy: pending, then sent after the delay by the sweep', (function()
        register({ id = 'delayed_one', dispatch = { mode = 'delayed', delaySeconds = 30, types = { alarm = 'Silent alarm' } } })
        local r2 = select(2, W.core:Begin(OWNER, 'delayed_one', { siteKey = 'atm:90', leaderCharacterId = '103', coords = { x = 1.0, y = 2.0, z = 3.0 } })).reference
        W.core:Advance(OWNER, r2, 'started', 'go', {}); local n = #W.dispatchLog
        local st = select(2, W.core:Dispatch(OWNER, r2, 'alarm')).state; local early = #W.dispatchLog == n
        W.now = W.now + 31; W.core:Sweep()
        return st == 'pending' and early and #W.dispatchLog == n + 1 and sess(r2).dispatch_state == 'sent' end)())
    check('DISPATCH chance policy is server-side: roll above chance suppresses', (function()
        register({ id = 'chance_one', dispatch = { mode = 'chance', chance = 0.5, types = { alarm = 'Maybe alarm' } } })
        local r2 = select(2, W.core:Begin(OWNER, 'chance_one', { siteKey = 'atm:91', leaderCharacterId = '104', coords = { x = 1.0, y = 2.0, z = 3.0 } })).reference
        W.core:Advance(OWNER, r2, 'started', 'go', {}); W.randValue = 0.9; local n = #W.dispatchLog
        local st = select(2, W.core:Dispatch(OWNER, r2, 'alarm')).state; return st == 'suppressed' and #W.dispatchLog == n and sess(r2).dispatch_state == 'suppressed' end)())
    check('DISPATCH chance policy: roll within chance sends', (function()
        register({ id = 'chance_two', dispatch = { mode = 'chance', chance = 0.5, types = { alarm = 'Maybe alarm' } } })
        local r2 = select(2, W.core:Begin(OWNER, 'chance_two', { siteKey = 'atm:92', leaderCharacterId = '105', coords = { x = 1.0, y = 2.0, z = 3.0 } })).reference
        W.core:Advance(OWNER, r2, 'started', 'go', {}); W.randValue = 0.1; return select(2, W.core:Dispatch(OWNER, r2, 'alarm')).state == 'sent' end)())
    check('DISPATCH stage policy only fires in the configured stage', (function()
        fresh(); register({ id = 'stage_one', stages = { 'a1', 'b1' }, dispatch = { mode = 'stage', stages = { 'b1' }, types = { alarm = 'Stage alarm' } } })
        local r2 = select(2, W.core:Begin(OWNER, 'stage_one', { siteKey = 'atm:93', leaderCharacterId = '101', coords = { x = 1.0, y = 2.0, z = 3.0 } })).reference
        W.core:Advance(OWNER, r2, 'a1', 'b1', {})
        local ok2, res = W.core:Dispatch(OWNER, r2, 'alarm'); return ok2 == true and res.state == 'sent' end)())
    check('DISPATCH stage policy rejects other stages', (function()
        fresh(); register({ id = 'stage_two', stages = { 'a1', 'b1', 'c1' }, dispatch = { mode = 'stage', stages = { 'b1' }, types = { alarm = 'Stage alarm' } } })
        local r2 = select(2, W.core:Begin(OWNER, 'stage_two', { siteKey = 'atm:94', leaderCharacterId = '102', coords = { x = 1.0, y = 2.0, z = 3.0 } })).reference
        W.core:Advance(OWNER, r2, 'a1', 'c1', {}); return select(2, W.core:Dispatch(OWNER, r2, 'alarm')) == 'dispatch_stage' end)())
    check('DISPATCH total per session is capped', (function()
        fresh(); register({ id = 'many_types', dispatch = { mode = 'immediate', types = { t1 = 'one', t2 = 'two', t3 = 'three', t4 = 'four', t5 = 'five', t6 = 'six' } } })
        local r2 = select(2, W.core:Begin(OWNER, 'many_types', { siteKey = 'atm:95', leaderCharacterId = '103', coords = { x = 1.0, y = 2.0, z = 3.0 } })).reference
        W.core:Advance(OWNER, r2, 'started', 'go', {})
        for _, t in ipairs({ 't1', 't2', 't3', 't4', 't5' }) do W.core:Dispatch(OWNER, r2, t) end
        return select(2, W.core:Dispatch(OWNER, r2, 't6')) == 'dispatch_limit' end)())
    check('DISPATCH without configured coordinates cannot be sent (no client coordinates)', (function()
        fresh(); W.dispatchOk = true; local r2 = select(2, W.core:Begin(OWNER, 'test_small_crime', { siteKey = 'store:99', leaderCharacterId = '101' })).reference; stageUp(r2, 'breach')
        local n = #W.dispatchLog; W.core:Dispatch(OWNER, r2, 'alarm'); return #W.dispatchLog == n end)())
    check('DISPATCH terminal session refuses', (function() fresh(); local r2 = select(2, begin({ '101' })).reference; stageUp(r2, 'breach'); W.core:Fail(OWNER, r2, 'x'); return select(2, W.core:Dispatch(OWNER, r2, 'alarm')) == 'terminal' end)())
end

-- ======================================================================================== FAILURE / COOLDOWN
do
    fresh()
    local ref = select(2, begin({ '101' })).reference; stageUp(ref, 'breach')
    local ok, r = W.core:Fail(OWNER, ref, 'caught')
    check('FAILURE explicit failure ends the session', ok and r.status == 'failed' and sess(ref).status == 'failed' and sess(ref).end_reason == 'caught')
    check('FAILURE releases the site lock and participants', W.store.siteActive('store:24') == nil and W.store.charBusy('101', 'high_value') == false)
    check('FAILURE partial policy halves the site cooldown (1800 -> 900)', (function() local ok2, c = W.core:GetCooldown(OWNER, 'test_small_crime', 'site', 'store:24'); return c.remaining == 900 end)())
    check('FAILURE partial policy halves the activity and character cooldowns', select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'activity')).remaining == 30 and select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'character', '101')).remaining == 150)
    check('FAILURE repeat fail is idempotent', select(2, W.core:Fail(OWNER, ref, 'again')).replayed == true)
    check('FAILURE cancel after failure rejected (one terminal state)', select(2, W.core:Cancel(OWNER, ref)) == 'terminal_failed')
    check('FAILURE site cooldown blocks the next attempt', select(2, begin({ '102' }, 'store:24')) == 'site_cooldown' or select(2, begin({ '102' }, 'store:24')) == 'activity_cooldown')
    W.now = W.now + 31
    check('FAILURE activity cooldown expiry (30s) lets another site start', select(1, begin({ '103' }, 'store:25')) == true)
    check('FAILURE character cooldown blocks the same character at another site', (function()
        local r2 = select(2, begin({ '101' }, 'store:26')); return r2 == 'character_cooldown' end)())
    check('FAILURE cooldown expiry (site) after its duration', (function() W.now = W.now + 900; W.core:Cancel(OWNER, W.store.sessions[#W.store.sessions].reference); return select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'site', 'store:24')).remaining == 0 end)())
    check('FAILURE policy none: no cooldown at all', (function()
        register({ id = 'no_cd_fail', cooldowns = { site = 100, activity = 100, character = 100, onFailure = 'none' } })
        local r2 = select(2, W.core:Begin(OWNER, 'no_cd_fail', { siteKey = 'atm:100', leaderCharacterId = '104' })).reference; W.core:Advance(OWNER, r2, 'started', 'go', {}); W.core:Fail(OWNER, r2, 'x')
        return select(2, W.core:GetCooldown(OWNER, 'no_cd_fail', 'site', 'atm:100')).remaining == 0 end)())
    check('FAILURE policy full: full duration applied', (function()
        register({ id = 'full_cd_fail', cooldowns = { site = 100, onFailure = 'full' } })
        local r2 = select(2, W.core:Begin(OWNER, 'full_cd_fail', { siteKey = 'atm:101', leaderCharacterId = '105' })).reference; W.core:Fail(OWNER, r2, 'x')
        return select(2, W.core:GetCooldown(OWNER, 'full_cd_fail', 'site', 'atm:101')).remaining == 100 end)())
    check('FAILURE cancel applies no cooldown (nothing was attempted)', (function()
        fresh(); local r2 = select(2, begin({ '101' }, 'store:3')).reference; W.core:Cancel(OWNER, r2, 'abort'); return select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'site', 'store:3')).remaining == 0 end)())
    check('FAILURE cooldown rows are unique per scope/key/activity (no duplicates)', (function()
        fresh(); local r2 = select(2, begin({ '101' }, 'store:4')).reference; W.core:Fail(OWNER, r2, 'x'); W.now = W.now + 5000
        local r3 = select(2, begin({ '101' }, 'store:4')).reference; W.core:Fail(OWNER, r3, 'x'); local n = 0
        for k in pairs(W.store.cooldowns) do if k:find('site|store:4') then n = n + 1 end end return n == 1 end)())
    check('FAILURE cooldown never shortens an existing longer cooldown', (function()
        fresh(); W.store.cooldownSet('site', 'store:5', 'test_small_crime', W.now + 99999, 'x', 'CR-X'); W.store.cooldownSet('site', 'store:5', 'test_small_crime', W.now + 5, 'x', 'CR-Y')
        return W.store.cooldownGet('site', 'store:5', 'test_small_crime') == W.now + 99999 end)())
    check('FAILURE cooldown query scope validated', select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'bogus', 'x')) == 'invalid_scope' and select(2, W.core:GetCooldown(OTHER, 'test_small_crime', 'site', 'x')) == 'forbidden')
end

-- ======================================================================================== EXPIRY / DISCONNECT
do
    fresh()
    local ref = select(2, begin({ '101' })).reference; stageUp(ref, 'breach')
    W.now = W.now + 599; W.core:Sweep()
    check('EXPIRY a live session is not expired early', sess(ref).status == 'active')
    W.now = W.now + 2; local _, st = W.core:Sweep()
    check('EXPIRY a stale session expires at its maximum duration', sess(ref).status == 'expired' and st.expired == 1)
    check('EXPIRY releases the lock and applies the failure cooldown policy', W.store.siteActive('store:24') == nil and select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'site', 'store:24')).remaining > 0)
    check('EXPIRY expired session cannot be completed', select(2, W.core:Complete(OWNER, ref)) == 'terminal_expired')
    check('EXPIRY session_expired journalled once', countKind('session_expired', ref) == 1)
    fresh(); local r2 = select(2, begin({ '101', '102' })).reference; stageUp(r2, 'breach')
    W.online['102'] = nil; W.core:Sweep(); W.now = W.now + 30; W.core:Sweep()
    check('DISCONNECT brief disconnect within grace keeps the participant', W.store.partGet(r2, '102').state == 'active')
    W.now = W.now + 40; W.core:Sweep()
    check('DISCONNECT past grace removes the participant, session continues', W.store.partGet(r2, '102').state == 'left' and sess(r2).status == 'active')
    W.online['102'] = 1002
    W.online['101'] = nil; W.core:Sweep(); W.now = W.now + 61; W.core:Sweep()
    check('DISCONNECT all participants gone fails the session', sess(r2).status == 'failed' and sess(r2).end_reason == 'all_participants_gone')
    check('DISCONNECT reconnecting does not reopen a terminal session', (function() W.online['101'] = 1001; W.core:Sweep(); return sess(r2).status == 'failed' end)())
    check('DISCONNECT after success never duplicates the reward', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); local tok = select(2, W.core:Complete(OWNER, r3)).rewardToken
        W.online['101'] = nil; W.now = W.now + 500; W.core:Sweep(); W.core:Sweep()
        return sess(r3).status == 'succeeded' and sess(r3).reward_token == tok and countKind('reward_authorized', r3) == 1 end)())
    check('OWNER STOP: owner gone past grace fails its sessions', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.ownersUp[OWNER] = false
        W.core:Sweep(); W.now = W.now + 30; W.core:Sweep(); local mid = sess(r3).status; W.now = W.now + 40; W.core:Sweep()
        W.ownersUp[OWNER] = true; return mid == 'active' and sess(r3).status == 'failed' and sess(r3).end_reason == 'owner_stopped' end)())
    check('OWNER STOP: owner back within grace keeps the session', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.ownersUp[OWNER] = false; W.core:Sweep(); W.now = W.now + 30; W.ownersUp[OWNER] = true; W.core:Sweep(); W.now = W.now + 100; W.core:Sweep()
        return sess(r3).status == 'active' end)())
    check('OWNER STOP: audit history is retained after the owner stops', (function() fresh(); local r3 = select(2, begin({ '101' })).reference; W.ownersUp[OWNER] = false; W.core:Sweep(); W.now = W.now + 70; W.core:Sweep(); W.ownersUp[OWNER] = true; return #W.store.eventList(r3) >= 3 end)())
    check('OWNER STOP: activity not re-registered after a restart is treated as an absent owner', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.core.activities = {}; W.core:Sweep(); W.now = W.now + 130; W.core:Sweep(); return sess(r3).status == 'failed' end)())
end

-- ======================================================================================== SUCCESS / RACES / REWARD
do
    fresh()
    local ref = select(2, begin({ '101' })).reference
    check('SUCCESS completing a session that was never activated is refused', select(2, W.core:Complete(OWNER, ref)) == 'not_active')
    stageUp(ref, 'breach')
    local ok, r = W.core:Complete(OWNER, ref, { tier = 'standard' })
    check('SUCCESS valid completion succeeds with reward pending and ONE token', ok and r.status == 'succeeded' and r.rewardState == 'pending' and type(r.rewardToken) == 'string' and #r.rewardToken == 24)
    check('SUCCESS releases site/participants and applies the full cooldown', W.store.siteActive('store:24') == nil and select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'site', 'store:24')).remaining == 1800)
    check('SUCCESS outcome tier is recorded', sess(ref).outcome == 'standard')
    local ok2, r2 = W.core:Complete(OWNER, ref, { tier = 'other' })
    check('REWARD duplicate completion returns the SAME token and state (no second issuance)', ok2 and r2.replayed == true and r2.rewardToken == r.rewardToken and countKind('reward_authorized', ref) == 1)
    check('REWARD exactly one authorization event even after many replays', (function() for _ = 1, 5 do W.core:Complete(OWNER, ref) end return countKind('reward_authorized', ref) == 1 and countKind('session_succeeded', ref) == 1 end)())
    check('REWARD confirm with the right token marks delivered once', (function()
        local ok3, x = W.core:ConfirmReward(OWNER, ref, r.rewardToken); local ok4, y = W.core:ConfirmReward(OWNER, ref, r.rewardToken)
        return ok3 and x.rewardState == 'delivered' and ok4 and y.replayed == true and sess(ref).reward_state == 'delivered' and countKind('reward_delivered', ref) == 1 end)())
    check('REWARD completion replay after delivery still returns the previous state', select(2, W.core:Complete(OWNER, ref)).rewardState == 'delivered')
    check('SUCCESS race: fail after success is rejected (one terminal state)', select(2, W.core:Fail(OWNER, ref, 'late')) == 'terminal_succeeded' and sess(ref).status == 'succeeded')
    check('SUCCESS race: cancel after success rejected', select(2, W.core:Cancel(OWNER, ref)) == 'terminal_succeeded')
    check('SUCCESS race: complete after fail rejected', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.core:Fail(OWNER, r3, 'x')
        return select(2, W.core:Complete(OWNER, r3)) == 'terminal_failed' and sess(r3).reward_token == nil end)())
    check('SUCCESS race: complete vs expiry, only one terminal state', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.now = W.now + 700
        local c = W.core:Complete(OWNER, r3); W.core:Sweep()
        local st = sess(r3).status; return (c == true and st == 'succeeded') or (c == false and st == 'expired') and countKind('session_succeeded', r3) + countKind('session_expired', r3) == 1 end)())
    check('SUCCESS single terminal journal event for every outcome', countKind('session_succeeded', ref) == 1)
    check('SUCCESS wrong owner cannot complete another owner\'s session', (function() fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); return select(2, W.core:Complete(OTHER, r3)) == 'forbidden' and sess(r3).status == 'active' end)())
    check('REWARD arbitrary payload rejected (cash/items/xp keys)', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach')
        local a = select(2, W.core:Complete(OWNER, r3, { cash = 5000 })); local b = select(2, W.core:Complete(OWNER, r3, { items = { 'gold' } }))
        local c = select(2, W.core:Complete(OWNER, r3, { tier = { 'x' } })); local d = select(2, W.core:Complete(OWNER, r3, 'bag')); local e = select(2, W.core:Complete(OWNER, r3, { xp = '99' }))
        return a == 'invalid_result' and b == 'invalid_result' and c == 'invalid_result' and d == 'invalid_result' and e == 'invalid_result' and sess(r3).status == 'active' end)())
    check('REWARD tier string is bounded and charset-limited', (function() fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); return select(2, W.core:Complete(OWNER, r3, { tier = string.rep('x', 40) })) == 'invalid_result' and select(2, W.core:Complete(OWNER, r3, { tier = 'a;b' })) == 'invalid_result' end)())
    check('REWARD wrong token / wrong owner rejected', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); local t = select(2, W.core:Complete(OWNER, r3)).rewardToken
        return select(2, W.core:ConfirmReward(OWNER, r3, 'WRONGTOKEN')) == 'invalid_token' and select(2, W.core:ConfirmReward(OTHER, r3, t)) == 'forbidden' and sess(r3).reward_state == 'pending' end)())
    check('REWARD confirm on a non-succeeded session rejected', (function() fresh(); local r3 = select(2, begin({ '101' })).reference; return select(2, W.core:ConfirmReward(OWNER, r3, 'x')) == 'no_reward' end)())
    check('REWARD failed delivery is recorded for reconciliation', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); local t = select(2, W.core:Complete(OWNER, r3)).rewardToken
        local ok3 = W.core:ReportRewardFailure(OWNER, r3, t, 'economy_down'); return ok3 == true and sess(r3).reward_state == 'failed' and countKind('reward_failed', r3) == 1 end)())
    check('REWARD retry after a reported failure can still be confirmed once', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); local t = select(2, W.core:Complete(OWNER, r3)).rewardToken
        W.core:ReportRewardFailure(OWNER, r3, t, 'x'); local ok3 = W.core:ConfirmReward(OWNER, r3, t); local again = select(2, W.core:ReportRewardFailure(OWNER, r3, t, 'x'))
        return ok3 == true and sess(r3).reward_state == 'delivered' and again == 'already_delivered' end)())
    check('REWARD unconfirmed reward is flagged for reconciliation by the sweep (no auto-delivery, no re-issue)', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); local t = select(2, W.core:Complete(OWNER, r3)).rewardToken
        W.now = W.now + 901; local _, st = W.core:Sweep()
        return sess(r3).reward_state == 'failed' and st.rewardsFlagged == 1 and sess(r3).reward_token == t and countKind('reconciliation', r3) == 1 end)())
    check('REWARD admin reconcile resolves a flagged reward exactly', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.core:Complete(OWNER, r3); W.now = W.now + 901; W.core:Sweep()
        local ok3 = W.core:AdminReconcile(r3, 'delivered', 'tester'); return ok3 == true and sess(r3).reward_state == 'delivered' end)())
    check('REWARD an activity with reward disabled issues no token', (function()
        fresh(); register({ id = 'no_reward', reward = { enabled = false } }); local r3 = select(2, W.core:Begin(OWNER, 'no_reward', { siteKey = 'atm:110', leaderCharacterId = '102' })).reference
        W.core:Advance(OWNER, r3, 'started', 'go', {}); local c = select(2, W.core:Complete(OWNER, r3)); return c.rewardState == 'none' and c.rewardToken == nil end)())
    check('REWARD framework made no economy calls (no adapter for money/items/xp exists in the core deps)', (function()
        local deps = {}; for k in pairs(W.core) do deps[#deps + 1] = k end
        for _, k in ipairs(deps) do local l = tostring(k):lower(); if l:find('money') or l:find('cash') or l:find('inventory') or l:find('xp') or l:find('bank') then return false end end return true end)())
end

-- ======================================================================================== RESTART
do
    fresh()
    local store = W.store
    local refA = select(2, begin({ '101' }, 'store:1')).reference; stageUp(refA, 'breach')
    local refB = select(2, begin({ '102' }, 'store:2')).reference; stageUp(refB, 'breach'); W.core:Dispatch(OWNER, refB, 'alarm')
    local refC = select(2, begin({ '103' }, 'store:3')).reference; stageUp(refC, 'breach'); local tokC = select(2, W.core:Complete(OWNER, refC)).rewardToken
    W.now = W.now + 61   -- clear the 60s activity cooldown that refC's success applied
    local refD = select(2, begin({ '104' }, 'store:4')).reference; stageUp(refD, 'breach'); W.core:Fail(OWNER, refD, 'caught')
    local dispatchesBefore = #W.dispatchLog
    -- restart: new core instance over the SAME persisted store; definitions are re-registered by their owners
    newWorld(store, true); register(); W.now = W.now + 61
    check('RESTART active sessions restore from the store', sess(refA).status == 'active' and W.core:Get(OWNER, refA) == true)
    check('RESTART site locks are reconstructed (second group still rejected)', select(2, begin({ '105' }, 'store:1')) == 'site_occupied')
    check('RESTART character busy state is reconstructed', select(2, begin({ '101' }, 'store:9')) == 'character_busy')
    check('RESTART completed session remains terminal', sess(refC).status == 'succeeded' and select(2, W.core:Fail(OWNER, refC, 'x')) == 'terminal_succeeded')
    check('RESTART reward journal restored: same token, still pending, no new issuance', select(2, W.core:Complete(OWNER, refC)).rewardToken == tokC and countKind('reward_authorized', refC) == 1)
    check('RESTART delivery can still be confirmed once after the restart', select(1, W.core:ConfirmReward(OWNER, refC, tokC)) == true and sess(refC).reward_state == 'delivered')
    check('RESTART cooldowns survive (site + character of the failed session)', select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'site', 'store:4')).remaining > 0 and select(2, W.core:GetCooldown(OWNER, 'test_small_crime', 'character', '104')).remaining > 0)
    check('RESTART dispatch is not duplicated by recovery', (function() W.core:Sweep(); W.core:Sweep(); return #W.dispatchLog == dispatchesBefore end)())
    check('RESTART dispatch-once journal survives (type already sent for that session)', (function() local ok2, r2 = W.core:Dispatch(OWNER, refB, 'alarm'); return ok2 and r2.replayed == true and #W.dispatchLog == dispatchesBefore end)())
    W.now = W.now + 700; W.core:Sweep()
    check('RESTART stale sessions expire on recovery', sess(refA).status == 'expired' and sess(refB).status == 'expired')
    check('RESTART expired sessions released their locks', W.store.siteActive('store:1') == nil and W.store.siteActive('store:2') == nil)
    check('RESTART terminal sessions keep their audit timeline', #W.store.eventList(refA) >= 4)
    check('RESTART second recovery sweep changes nothing', (function() local before = #W.store.events; W.core:Sweep(); return #W.store.events == before end)())
end

-- ======================================================================================== SECURITY / ADMIN
do
    fresh()
    local ref = select(2, begin({ '101' })).reference; stageUp(ref, 'breach')
    check('SECURITY cross-resource mutation rejected on every mutating call', (function()
        local c = W.core
        return select(2, c:Join(OTHER, ref, '102')) == 'forbidden' and select(2, c:Leave(OTHER, ref, '101')) == 'forbidden' and select(2, c:Advance(OTHER, ref, 'breach', 'escape', {})) == 'forbidden'
            and select(2, c:Dispatch(OTHER, ref, 'alarm')) == 'forbidden' and select(2, c:Complete(OTHER, ref)) == 'forbidden' and select(2, c:Fail(OTHER, ref, 'x')) == 'forbidden'
            and select(2, c:Cancel(OTHER, ref, 'x')) == 'forbidden' and select(2, c:ConfirmReward(OTHER, ref, 'x')) == 'forbidden' and select(2, c:Get(OTHER, ref)) == 'forbidden' end)())
    check('SECURITY the session is untouched by the rejected calls', sess(ref).status == 'active' and sess(ref).current_stage == 'breach')
    check('SECURITY forged resource names (nil / empty / non-string) are rejected', select(2, W.core:Complete(nil, ref)) == 'forbidden' and select(2, W.core:Complete(42, ref)) == 'forbidden')
    check('SECURITY forged CID in begin (non-numeric / overlong) rejected', select(2, begin({ '1; DROP' }, 'store:55')) == 'invalid_character' and select(2, begin({ string.rep('9', 30) }, 'store:55')) == 'invalid_character')
    check('SECURITY forged site (injection / path) rejected', select(2, begin({ '102' }, "store:1' OR '1'='1")) == 'invalid_site' and select(2, begin({ '102' }, '../etc')) == 'invalid_site')
    check('SECURITY malformed references are rejected safely', select(2, W.core:Get(OWNER, "CR-1' OR 1=1")) == 'invalid_reference' and select(2, W.core:Get(OWNER, {})) == 'invalid_reference' and select(2, W.core:Get(OWNER, nil)) == 'invalid_reference')
    check('SECURITY direct client pathway absent: no network event / NUI / command registration in the resource', (function()
        local bad = 0
        for _, f in ipairs({ 'server/main.lua', 'server/core.lua', 'server/store.lua' }) do
            local h = io.open(here .. '/' .. f, 'r'); local src = h:read('a'); h:close()
            for _, pat in ipairs({ 'RegisterNetEvent', 'RegisterServerEvent', 'RegisterNUICallback', 'lib%.callback%.register', 'TriggerClientEvent' }) do if src:find(pat) then bad = bad + 1 end end
            local cmds = select(2, src:gsub('RegisterCommand%(', '')); if cmds > 0 and not (cmds == 1 and src:find('if src ~= 0 then return end', 1, true)) then bad = bad + 1 end
        end
        local m = io.open(here .. '/fxmanifest.lua', 'r'):read('a'); if m:find('client_script') or m:find('ui_page') then bad = bad + 1 end
        return bad == 0 end)())
    check('SECURITY no source id appears in the schema', (function() local h = io.open(here .. '/server/store.lua', 'r'); local s = h:read('a'); h:close(); return not s:find('source_id') and not s:find('server_id') and not s:find('license') end)())
    check('SECURITY exports are all bound to the invoking resource (static)', (function()
        local h = io.open(here .. '/server/main.lua', 'r'); local src = h:read('a'); h:close()
        local n = 0 for line in src:gmatch("exports%('([%w]+)'") do n = n + 1; end
        local owned = select(2, src:gsub("exports%('[%w]+', owned%(", '')) local adm = select(2, src:gsub("exports%('[%w]+', admin%(", ''))
        return n == owned + adm and n > 0 end)())
    check('SECURITY admin surface: inspect / list / cooldowns', (function()
        local okL, list = W.core:AdminList(); local okI, info = W.core:AdminInspect(ref); local okC, cds = W.core:AdminCooldowns()
        return okL and #list >= 1 and okI and info.session.reference == ref and #info.events > 0 and info.rewardToken == nil and okC end)())
    check('SECURITY admin inspect does not leak the reward token', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); local t = select(2, W.core:Complete(OWNER, r3)).rewardToken
        local _, info = W.core:AdminInspect(r3); return ser(info):find(t, 1, true) == nil end)())
    check('ADMIN cancel a stuck session releases locks and cooldown-free', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); local ok = W.core:AdminCancel(r3, 'tester')
        return ok == true and sess(r3).status == 'cancelled' and W.store.siteActive('store:24') == nil and countKind('admin_cancel', r3) == 1 end)())
    check('ADMIN cancel of a terminal session refused', (function() fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.core:Complete(OWNER, r3); return select(2, W.core:AdminCancel(r3, 'tester')) == 'terminal_succeeded' end)())
    check('ADMIN reconcile with no ref runs the full recovery sweep', select(1, W.core:AdminReconcile(nil)) == true)
    check('ADMIN reconcile unknown / invalid references rejected', select(2, W.core:AdminReconcile('CR-NOPE0000', 'delivered')) == 'not_found' and select(2, W.core:AdminReconcile("x'y")) == 'invalid_reference')
    check('ADMIN reconcile cannot fabricate a reward for a failed session', (function() fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.core:Fail(OWNER, r3, 'x'); return select(2, W.core:AdminReconcile(r3, 'delivered')) == 'no_reward' end)())
    check('AUDIT terminal outcomes are mirrored to the admin log without secrets', (function()
        local blob = ser(W.audits); return #W.audits > 0 and not blob:find('token') and not blob:find('license') end)())
    check('AUDIT timeline holds the required event kinds', (function()
        fresh(); local r3 = select(2, begin({ '101', '102' })).reference; stageUp(r3, 'breach'); W.core:Dispatch(OWNER, r3, 'alarm'); W.core:Leave(OWNER, r3, '102'); W.core:Complete(OWNER, r3)
        local t = select(2, W.core:AdminInspect(r3)).events; local kinds = {} for _, e in ipairs(t) do kinds[e.kind] = true end
        return kinds.session_created and kinds.participant_added and kinds.participant_removed and kinds.session_active and kinds.stage_advanced and kinds.dispatch_triggered and kinds.session_succeeded and kinds.reward_authorized and kinds.cooldown_applied end)())
    check('SECURITY lock contention returns busy instead of double-applying', (function()
        fresh(); local r3 = select(2, begin({ '101' })).reference; stageUp(r3, 'breach'); W.core.locks['sess:' .. r3] = true
        local why = select(2, W.core:Complete(OWNER, r3)); W.core.locks['sess:' .. r3] = nil; return why == 'busy' and sess(r3).status == 'active' end)())
end

print(('\ncm-crime selftest: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
