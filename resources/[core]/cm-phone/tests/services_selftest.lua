-- Deterministic local self-test for the cm-phone Service Marketplace core (no FiveM, no database).
--   lua tests/services_selftest.lua      (run from resources/[core]/cm-phone)
-- Adapters are doubles that mimic a SOURCE OWNER (a taxi-like owner that holds the only request record, and a
-- cm-contracts-backed courier-like owner). The phone core must never hold request state of its own.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
CMPhone = {}
vector3 = function(x, y, z) return { x = x, y = y, z = z } end -- FiveM global used by config.lua
dofile(here .. '/config.lua')
dofile(here .. '/server/services_core.lua')
local Core, Config = CMPhone.ServicesCore, CMPhone.Config
-- Fixture: the 'soon' (Coming Soon) state is exercised with the mechanic entry forced to comingSoon. In production config mechanic is LIVE
-- (cm-mechanic registers the adapter); its real end-to-end flow is covered by cm-mechanic/tests/selftest.lua.
Config.Services.Catalog.mechanic.comingSoon = true

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

local function cleanText(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' then return nil end
    return v:sub(1, max)
end

local W
local function world()
    W = { started = { ['cm-taxi'] = true, ['cm-courier'] = true }, requests = {}, calls = {}, emitted = {}, audits = {}, rate = true,
        dead = false, pos = { x = 100.0, y = 200.0, z = 30.0, bucket = 0 }, now = 1000, nextRef = 0, availability = 'available',
        online = { ['101'] = true, ['102'] = true }, rawStatus = nil, sourceBroken = false, cancelRefuse = false }

    -- Source owner double #1: taxi-like. Holds the ONLY request record; derives ownership from the character id.
    local taxi = {
        PhoneCreate = function(cid, service, fields, ctx)
            if W.sourceBroken then error('owner crashed') end
            W.calls[#W.calls + 1] = 'create:' .. cid
            if W.requests[cid] and not W.requests[cid].terminal then return false, 'already_active' end
            W.nextRef = W.nextRef + 1
            W.requests[cid] = { ref = 'TX-' .. W.nextRef, state = 'searching', fields = fields, ctx = ctx, owner = cid }
            return true, { ref = W.requests[cid].ref, state = 'searching', canCancel = true }
        end,
        PhoneStatus = function(cid)
            if W.sourceBroken then error('owner crashed') end
            if W.rawStatus then return true, W.rawStatus end
            local r = W.requests[cid]
            if not r then return true, nil end
            return true, { ref = r.ref, state = r.state, canCancel = r.canCancel ~= false, workerLabel = r.worker, etaSeconds = r.eta,
                -- everything below is internal and must never surface
                claimed_character_id = 'secret-cid', claim_expires_at = 123, fallback = true }
        end,
        PhoneCancel = function(cid, service, ref)
            W.calls[#W.calls + 1] = 'cancel:' .. cid .. ':' .. ref
            local r = W.requests[cid]
            if not r or r.ref ~= ref then return false, 'not_found' end
            if W.cancelRefuse or r.terminal then return false, 'cancel_not_allowed' end
            r.state, r.terminal = 'cancelled', true
            return true
        end,
        PhoneAvailable = function() if W.availability == 'offline' then return false end return W.availability end,
    }
    local function call(resource, name, ...)
        if resource ~= 'cm-taxi' and resource ~= 'cm-courier' and resource ~= 'cm-mechanic' then return false, 'resource_unavailable' end
        if not W.started[resource] then return false, 'resource_unavailable' end
        local fn = taxi[name]
        if not fn then return false, 'no_export' end
        local res = table.pack(pcall(fn, ...))
        if not res[1] then return false, 'call_failed' end
        return true, res[2], res[3]
    end
    local core = Core.New({ cfg = Config, call = call, started = function(r) return W.started[r] == true end, now = function() return W.now end,
        rateLimit = function() return W.rate end, position = function() return W.pos end, isDead = function() return W.dead end,
        emit = function(cid, ev, payload) if not W.online[cid] then return false end W.emitted[#W.emitted + 1] = { cid = cid, ev = ev, payload = payload }; return true end,
        audit = function(src, kind) W.audits[#W.audits + 1] = kind end, cleanText = cleanText })
    return core
end
local TAXI = { create = 'PhoneCreate', status = 'PhoneStatus', cancel = 'PhoneCancel', availability = 'PhoneAvailable' }
local function taxiCore() local c = world(); assert(c:RegisterAdapter('cm-taxi', 'taxi', TAXI)); return c end
local function find(list, id) for _, e in ipairs(list) do if e.id == id then return e end end end

-- ============================================================== REGISTRY
do
    local core = world()
    check('REGISTRY trusted service registers', core:RegisterAdapter('cm-taxi', 'taxi', TAXI) == true)
    check('REGISTRY untrusted registration rejected', select(2, core:RegisterAdapter('cm-evil', 'taxi', TAXI)) == 'untrusted_source')
    check('REGISTRY trusted resource for a service it does not own rejected', select(2, core:RegisterAdapter('cm-taxi', 'courier', TAXI)) == 'untrusted_source')
    check('REGISTRY unknown service id rejected', select(2, core:RegisterAdapter('cm-taxi', 'nope', TAXI)) == 'untrusted_source')
    check('REGISTRY invalid export names rejected', select(2, core:RegisterAdapter('cm-taxi', 'taxi', { create = 'a b', status = 'x' })) == 'invalid_definition'
        and select(2, core:RegisterAdapter('cm-taxi', 'taxi', { create = 'ok' })) == 'invalid_definition')
    local c2 = world()
    Config.Services.Sources['cm-other'] = { taxi = true }
    c2:RegisterAdapter('cm-taxi', 'taxi', TAXI)
    check('REGISTRY duplicate service id from another resource rejected', select(2, c2:RegisterAdapter('cm-other', 'taxi', TAXI)) == 'duplicate_service')
    Config.Services.Sources['cm-other'] = nil
    check('REGISTRY same owner may re-register (restart)', c2:RegisterAdapter('cm-taxi', 'taxi', TAXI) == true)
    Config.Services.Enabled = false
    check('REGISTRY disabled marketplace rejects registration', select(2, world():RegisterAdapter('cm-taxi', 'taxi', TAXI)) == 'disabled')
    Config.Services.Enabled = true
    c2:UnregisterResource('cm-taxi')
    check('REGISTRY owner stop removes adapter', c2.adapters.taxi == nil)
end

-- =============================================================== LISTING
do
    local core = taxiCore()
    local _, list = core:ListServices('101')
    local taxi, mech, courier = find(list, 'taxi'), find(list, 'mechanic'), find(list, 'courier')
    check('LISTING registered+started service is available', taxi and taxi.state == 'available' and taxi.canRequest == true)
    check('LISTING mechanic is Coming Soon (no owner exists)', mech and mech.state == 'soon' and mech.canRequest == false)
    check('LISTING courier without adapter is unavailable (provider missing)', courier and courier.state == 'offline' and courier.reason == 'provider_unavailable' and courier.canRequest == false)
    check('LISTING order is stable', list[1].id == 'taxi' and list[2].id == 'mechanic' and list[3].id == 'courier')
    check('LISTING does not leak internal config', (function()
        for _, e in ipairs(list) do
            if e.activePolicy or e.positionRequired or e.adapter or e.resource or e.source or e.sources then return false end
            for k in pairs(e) do if k:find('resource') or k:find('export') then return false end end
        end return true end)())
    W.started['cm-taxi'] = false
    local _, l2 = core:ListServices('101')
    check('LISTING source resource stopped -> offline', find(l2, 'taxi').state == 'offline')
    W.started['cm-taxi'] = true
    W.availability = 'limited'
    check('LISTING owner availability limited surfaces as LIMITED and still requestable', (function() local _, l3 = core:ListServices('101'); local t = find(l3, 'taxi'); return t.state == 'limited' and t.canRequest end)())
    W.availability = 'offline'
    check('LISTING owner availability offline blocks requests', (function() local _, l3 = core:ListServices('101'); local t = find(l3, 'taxi'); return t.state == 'offline' and not t.canRequest end)())
    W.availability = 'available'
    Config.Services.HideOffline = true
    check('LISTING HideOffline policy hides unavailable owners', find(select(2, core:ListServices('101')), 'courier') == nil and find(select(2, core:ListServices('101')), 'mechanic') ~= nil)
    Config.Services.HideOffline = false
    check('LISTING current request is attached for the requester only', (function()
        core:Request(1, '101', 'taxi', {})
        local _, a = core:ListServices('101'); local _, b = core:ListServices('102')
        return find(a, 'taxi').current ~= nil and find(b, 'taxi').current == nil end)())
    check('LISTING comingSoon service cannot be forced available by registering an adapter', (function()
        Config.Services.Sources['cm-mechanic'] = { mechanic = true }
        local c = world(); W.started['cm-mechanic'] = true
        c:RegisterAdapter('cm-mechanic', 'mechanic', TAXI)
        local _, l = c:ListServices('101'); return find(l, 'mechanic').state == 'soon' end)())
end

-- ================================================================ REQUEST
do
    local core = taxiCore()
    local ok, st = core:Request(1, '101', 'taxi', { destination = { x = 10.5, y = -20.5 }, details = 'Airport please' })
    check('REQUEST valid request creates via owner', ok == true and st.state == 'searching' and st.ref == 'TX-1' and st.label == 'Looking for a worker')
    check('REQUEST owner received only validated fields + server position', (function()
        local r = W.requests['101']
        return r.fields.details == 'Airport please' and r.fields.destination.x == 10.5 and r.ctx.position.x == 100.0 end)())
    check('REQUEST no second record in the phone (owner holds the only one)', (function() local n = 0 for _ in pairs(W.requests) do n = n + 1 end
        for k in pairs(core) do if tostring(k):find('request') or tostring(k):find('history') then return false end end return n == 1 end)())
    check('REQUEST audited', W.audits[1] == 'cm_phone_service_request')
    check('REQUEST one-active policy returns current request', (function() local ok2, why, cur = core:Request(1, '101', 'taxi', {}); return ok2 == false and why == 'already_active' and cur.ref == 'TX-1' end)())
    check('REQUEST other character unaffected', core:Request(2, '102', 'taxi', {}) == true)
    check('REQUEST invalid service', select(2, core:Request(1, '101', 'pizza', {})) == 'invalid_service' and select(2, core:Request(1, '101', 'tax i', {})) == 'invalid_service')
    check('REQUEST disabled/coming-soon service', select(2, core:Request(1, '101', 'mechanic', { service = 'repair' })) == 'service_unavailable')
    check('REQUEST courier without provider', select(2, core:Request(1, '101', 'courier', { details = 'x', destination = { x = 1, y = 2 } })) == 'service_unavailable')
    local c = taxiCore()
    check('REQUEST unknown key rejected', select(2, c:Request(1, '101', 'taxi', { details = 'x', cost = 0 })) == 'invalid_field')
    check('REQUEST injected worker/owner keys rejected', select(2, c:Request(1, '101', 'taxi', { workerCharacterId = '9', requester = '102', state = 'completed' })) == 'invalid_field')
    check('REQUEST oversize text rejected', select(2, c:Request(1, '101', 'taxi', { details = string.rep('x', 600) })) == 'invalid_field')
    check('REQUEST text is trimmed to field max', (function() local ok2 = c:Request(1, '101', 'taxi', { details = string.rep('y', 120) }); return ok2 == true and #W.requests['101'].fields.details <= 120 end)())
    check('REQUEST wrong field types rejected', select(2, c:Request(1, '101', 'taxi', { details = { 'nested' } })) == 'invalid_field'
        and select(2, c:Request(1, '101', 'taxi', { details = 42 })) == 'invalid_field')
    local c3 = taxiCore()
    check('REQUEST malformed destination rejected', select(2, c3:Request(1, '101', 'taxi', { destination = 'ls' })) == 'invalid_field'
        and select(2, c3:Request(1, '101', 'taxi', { destination = { x = 'a', y = 1 } })) == 'invalid_field'
        and select(2, c3:Request(1, '101', 'taxi', { destination = { x = 0 / 0, y = 1 } })) == 'invalid_field'
        and select(2, c3:Request(1, '101', 'taxi', { destination = { x = 99999, y = 1 } })) == 'invalid_field'
        and select(2, c3:Request(1, '101', 'taxi', { destination = { x = 1, y = 2, evil = function() end } })) == 'invalid_field')
    check('REQUEST bad payload types rejected', select(2, c3:Request(1, '101', 'taxi', 'x')) == 'invalid_request' and select(2, c3:Request(1, '101', 'taxi', 5)) == 'invalid_request')
    check('REQUEST rejected requests never reach the owner', #W.calls == 0)
    local c4 = taxiCore(); c4:RegisterAdapter('cm-courier', 'courier', TAXI)
    Config.Services.Sources['cm-courier'] = { courier = true }
    c4:RegisterAdapter('cm-courier', 'courier', TAXI)
    check('REQUEST required field enforced', select(2, c4:Request(1, '101', 'courier', { destination = { x = 1, y = 2 } })) == 'missing_field'
        and select(2, c4:Request(1, '101', 'courier', { details = 'box' })) == 'missing_field')
    check('REQUEST enum validated', select(2, c4:Request(1, '101', 'courier', { details = 'box', destination = { x = 1, y = 2 }, size = 'huge' })) == 'invalid_field'
        and c4:Request(1, '101', 'courier', { details = 'box', destination = { x = 1, y = 2 }, size = 'small' }) == true)
    local c5 = taxiCore(); W.sourceBroken = true
    check('REQUEST source failure -> safe error, no fake success', select(2, c5:Request(1, '101', 'taxi', {})) == 'service_unavailable' and next(W.requests) == nil)
    W.sourceBroken = false; W.started['cm-taxi'] = false
    check('REQUEST source unavailable', select(2, c5:Request(1, '101', 'taxi', {})) == 'service_unavailable')
    W.started['cm-taxi'] = true; W.rate = false
    check('REQUEST rate limited', select(2, c5:Request(1, '101', 'taxi', {})) == 'rate_limited')
    W.rate = true; W.dead = true
    check('REQUEST dead player cannot request', select(2, c5:Request(1, '101', 'taxi', {})) == 'unavailable')
    W.dead = false; W.pos = nil
    check('REQUEST needs a server-observed position', select(2, c5:Request(1, '101', 'taxi', {})) == 'location_unavailable')
    W.pos = { x = 1.0, y = 2.0, z = 3.0, bucket = 0 }
    check('REQUEST adapter reason allowlist (unknown reasons are not echoed)', (function()
        local c6 = taxiCore(); local orig = c6.call
        c6.call = function(r, n, ...) if n == 'PhoneCreate' then return true, false, 'SELECT * FROM secrets' end return orig(r, n, ...) end
        return select(2, c6:Request(1, '101', 'taxi', {})) == 'service_failed' end)())
    check('REQUEST simultaneous duplicate settles once (lock)', (function()
        local c7 = taxiCore(); local orig = c7.call; local inner
        c7.call = function(r, n, ...) if n == 'PhoneCreate' then inner = { c7:Request(1, '101', 'taxi', {}) } end return orig(r, n, ...) end
        local ok2 = c7:Request(1, '101', 'taxi', {})
        return ok2 == true and inner[1] == false and inner[2] == 'busy' and W.nextRef == 1 end)())
end

-- ================================================================= STATUS
do
    local core = taxiCore()
    core:Request(1, '101', 'taxi', {})
    local function state() local ok, s = core:Status('101', 'taxi'); return ok and s end
    check('STATUS waiting', state().state == 'searching' and state().tone == 'wait')
    W.requests['101'].state, W.requests['101'].worker, W.requests['101'].eta = 'assigned', 'Driver assigned', 240
    local s = state()
    check('STATUS assigned (+worker label, eta)', s.state == 'assigned' and s.tone == 'good' and s.workerLabel == 'Driver assigned' and s.etaSeconds == 240)
    W.requests['101'].state = 'enroute'
    check('STATUS on the way', state().label == 'Worker on the way')
    W.requests['101'].state = 'active'
    check('STATUS in progress', state().label == 'Service in progress' and state().tone == 'active')
    W.requests['101'].state, W.requests['101'].terminal = 'completed', true
    check('STATUS completed is terminal and not cancellable', state().terminal == true and state().canCancel == false)
    W.requests['101'].state = 'fallback_completed'
    check('STATUS fallback completion shown as automatic', state().label == 'Completed automatically' and state().terminal == true)
    W.requests['101'].state = 'cancelled'
    check('STATUS cancelled', state().state == 'cancelled' and state().tone == 'bad')
    W.requests['101'].state = 'no_provider'
    check('STATUS no provider', state().label == 'No provider available')
    check('STATUS internal fields never leak', (function() local t = state()
        for k in pairs(t) do if k:find('claim') or k:find('fallback') or k:find('cid') or k:find('secret') then return false end end return true end)())
    W.rawStatus = { state = 'fallback', ref = 'X' }
    check('STATUS unknown/internal state rejected as unavailable', select(2, core:Status('101', 'taxi')) == 'status_unavailable')
    W.rawStatus = { state = 'claimed', claimed_character_id = '9' }
    check('STATUS broker-internal state names are not accepted', select(2, core:Status('101', 'taxi')) == 'status_unavailable')
    W.rawStatus = nil; W.sourceBroken = true
    check('STATUS source status unavailable', select(2, core:Status('101', 'taxi')) == 'status_unavailable')
    W.sourceBroken = false
    check('STATUS no request -> nil', select(2, core:Status('102', 'taxi')) == nil)
    check('STATUS bad service id', select(2, core:Status('101', 'x y')) == 'invalid_service')
    W.rawStatus = { state = 'active', ref = 'A', detail = string.rep('d', 500), workerLabel = string.rep('w', 500), etaSeconds = -5 }
    local t = state()
    check('STATUS text bounded, bad eta dropped', #t.detail <= 80 and #t.workerLabel <= 40 and t.etaSeconds == nil)
    W.rawStatus = nil
    check('STATUS contract translation', Core.MapContractState('available') == 'searching' and Core.MapContractState('claimed') == 'assigned'
        and Core.MapContractState('active') == 'active' and Core.MapContractState('completing') == 'active'
        and Core.MapContractState('completed', 'player') == 'completed' and Core.MapContractState('completed', 'fallback') == 'fallback_completed'
        and Core.MapContractState('fallback') == 'searching' and Core.MapContractState('failed') == 'cancelled' and Core.MapContractState('cancelled') == 'cancelled')
end

-- ================================================================== CANCEL
do
    local core = taxiCore()
    core:Request(1, '101', 'taxi', {})
    check('CANCEL allowed through the owner', core:Cancel(1, '101', 'taxi', 'TX-1') == true and W.requests['101'].state == 'cancelled' and W.calls[#W.calls] == 'cancel:101:TX-1')
    check('CANCEL after completion/cancellation disallowed', select(2, core:Cancel(1, '101', 'taxi', 'TX-1')) == 'cancel_not_allowed')
    local c2 = taxiCore(); c2:Request(1, '101', 'taxi', {})
    W.cancelRefuse = true; W.requests['101'].canCancel = false
    check('CANCEL owner says not cancellable (e.g. passenger boarded)', select(2, c2:Cancel(1, '101', 'taxi', 'TX-' .. W.nextRef)) == 'cancel_not_allowed' and #W.calls == 1)
    W.requests['101'].canCancel = true
    check('CANCEL owner refuses at call time', select(2, c2:Cancel(1, '101', 'taxi', 'TX-' .. W.nextRef)) == 'cancel_not_allowed')
    W.cancelRefuse = false
    local c3 = taxiCore(); c3:Request(1, '101', 'taxi', {}); c3:Request(2, '102', 'taxi', {})
    local before = #W.calls
    check('CANCEL foreign request ref rejected (never reaches owner)', select(2, c3:Cancel(1, '101', 'taxi', W.requests['102'].ref)) == 'not_found' and #W.calls == before and W.requests['102'].state == 'searching')
    check('CANCEL invalid ref rejected', select(2, c3:Cancel(1, '101', 'taxi', 'a b')) == 'invalid_request' and select(2, c3:Cancel(1, '101', 'taxi', nil)) == 'invalid_request')
    check('CANCEL service without cancel capability', (function()
        local c4 = world(); c4:RegisterAdapter('cm-taxi', 'taxi', { create = 'PhoneCreate', status = 'PhoneStatus' })
        c4:Request(1, '101', 'taxi', {}); return select(2, c4:Cancel(1, '101', 'taxi', 'TX-1')) == 'cancel_not_allowed' end)())
    check('CANCEL source unavailable', (function() local c5 = taxiCore(); c5:Request(1, '101', 'taxi', {}); W.started['cm-taxi'] = false
        local r = select(2, c5:Cancel(1, '101', 'taxi', 'TX-1')); W.started['cm-taxi'] = true; return r == 'status_unavailable' end)())
    W.rate = false
    check('CANCEL rate limited', select(2, c3:Cancel(1, '101', 'taxi', 'TX-1')) == 'rate_limited')
    W.rate = true
end

-- ============================================================ STATUS PUSH
do
    local core = taxiCore()
    core:Request(1, '101', 'taxi', {})
    check('PUSH owner pushes a status to the requester', core:Push('cm-taxi', '101', 'taxi', { state = 'assigned', ref = 'TX-1', workerLabel = 'Driver assigned' }) == true
        and W.emitted[1].ev == 'cm-phone:client:serviceStatus' and W.emitted[1].payload.message == 'Taxi: Worker assigned')
    check('PUSH forged resource rejected', select(2, core:Push('cm-evil', '101', 'taxi', { state = 'completed' })) == 'forbidden')
    check('PUSH other service owner rejected', select(2, core:Push('cm-courier', '101', 'taxi', { state = 'completed' })) == 'forbidden')
    check('PUSH contract-state spoof rejected', select(2, core:Push('cm-taxi', '101', 'taxi', { state = 'claimed', claimed_character_id = '9' })) == 'invalid_status')
    check('PUSH forwards only the public shape', (function()
        core:Push('cm-taxi', '101', 'taxi', { state = 'enroute', claimed_character_id = 'x', claim_expires_at = 1, fallback = true, ref = 'TX-1' })
        local p = W.emitted[#W.emitted].payload.status
        for k in pairs(p) do if k:find('claim') or k:find('fallback') or k:find('cid') then return false end end return p.state == 'enroute' end)())
    local n = #W.emitted
    core:Push('cm-taxi', '101', 'taxi', { state = 'enroute', ref = 'TX-1' })
    check('PUSH identical repeat is throttled (no spam)', #W.emitted == n)
    check('PUSH offline requester is not an error for the owner', select(2, core:Push('cm-taxi', '999', 'taxi', { state = 'active' })) == 'offline')
    check('PUSH invalid service rejected', select(2, core:Push('cm-taxi', '101', 'zzz', { state = 'active' })) == 'invalid_service')
end

-- ================================================================ SECURITY
do
    local core = taxiCore()
    check('SECURITY forged service id cannot reach another owner', select(2, core:Request(1, '101', 'courier', { details = 'x', destination = { x = 1, y = 2 } })) == 'service_unavailable'
        and select(2, core:Request(1, '101', '../taxi', {})) == 'invalid_service')
    core:Request(1, '101', 'taxi', {})
    check('SECURITY request owner comes from the session character, not the payload', W.requests['101'] ~= nil and W.requests['102'] == nil)
    check('SECURITY forged owner in payload rejected', select(2, taxiCore():Request(1, '101', 'taxi', { characterId = '102' })) == 'invalid_field')
    check('SECURITY contract-state spoof in payload rejected', select(2, taxiCore():Request(1, '101', 'taxi', { contractState = 'completed', status = 'completed' })) == 'invalid_field')
    check('SECURITY marketplace calls no money/item/xp exports', (function()
        for _, c in ipairs(W.calls) do if c:find('money') or c:find('item') or c:find('xp') or c:find('pay') then return false end end return true end)())
    check('SECURITY marketplace holds no persisted request state', (function() local c = taxiCore(); c:Request(1, '101', 'taxi', {})
        for k, v in pairs(c) do if type(v) == 'table' and k ~= 'adapters' and k ~= 'locks' and k ~= 'lastPush' and k ~= 'cfg' then return false end end return true end)())
end

print(('\nservices self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
