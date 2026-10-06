-- Deterministic self-test for cm-law's authoritative on-duty count (server/duty_count.lua) and its wiring in server/main.lua.
--   lua tests/duty_count_selftest.lua        (run from resources/[core]/cm-law)
-- REAL: server/duty_count.lua (the production factory). DOUBLES (labelled): the member tables and the connected-character set. The SQL that feeds the factory is
-- extracted from server/main.lua and verified against real MySQL by tests/duty_count_mysql_smoke.py.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
local function readAll(p) local f = io.open(p, 'rb'); if not f then return '' end local s = f:read('a'); f:close(); return s end
dofile(here .. '/server/duty_count.lua')

-- world: members[org] = list of { cid, duty, suspended }, loaded = set of loaded character ids
local function world()
    local W = { central = { sahp = {}, sheriff = {}, fib = {}, army = {} }, legacy = {}, loaded = {}, lawReady = true, legacyReady = true, calls = 0, dbError = false, loadedError = false }
    local function onDuty(list)
        local rows = {}
        for _, m in ipairs(list) do if m.duty and not m.suspended and m.ranked ~= false then rows[#rows + 1] = { character_id = m.cid } end end
        return rows
    end
    W.counter = LawDutyCount.New({
        callers = { ['cm-crime'] = true, ['cm-admin'] = true, ['cm-law'] = true },
        isCentralOrg = function(id) return W.central[id] ~= nil end,
        lawReady = function() return W.lawReady end,
        legacyReady = function() return W.legacyReady end,
        queryCentral = function(id) W.calls = W.calls + 1; if W.dbError then error('db down') end return onDuty(W.central[id]) end,
        queryLegacy = function() W.calls = W.calls + 1; if W.dbError then error('db down') end return onDuty(W.legacy) end,
        isLoaded = function(cid) if W.loadedError then error('playerdata down') end return W.loaded[cid] == true end,
    })
    function W.add(org, cid, duty, extra)
        local m = { cid = cid, duty = duty }
        for k, v in pairs(extra or {}) do m[k] = v end
        local list = org == 'police' and W.legacy or W.central[org]
        list[#list + 1] = m
        if not (extra and extra.offline) then W.loaded[cid] = true end
    end
    function W.count(org, who) return W.counter.count(org, who or 'cm-crime') end
    return W
end

-- ----------------------------------------------------------------- valid org
do
    local W = world()
    check('ORG zero officers: a healthy law system answers 0 (not unavailable)', W.count('police') == 0 and W.count('sahp') == 0)
    W.add('police', '1001', true)
    check('ORG one officer', W.count('police') == 1)
    W.add('police', '1002', true); W.add('police', '1003', true)
    check('ORG several officers', W.count('police') == 3)
end

-- ----------------------------------------------------------------- duty / suspension / rank
do
    local W = world()
    W.add('sahp', '2001', true); W.add('sahp', '2002', false); W.add('sahp', '2003', true, { suspended = true }); W.add('sahp', '2004', true, { ranked = false })
    check('DUTY on-duty counted; off-duty, suspended and rank-less rows ignored', W.count('sahp') == 1)
    W.add('police', '3001', true); W.add('police', '3002', false); W.add('police', '3003', true, { suspended = true })
    check('DUTY legacy police: same rules', W.count('police') == 1)
end

-- ----------------------------------------------------------------- connection
do
    local W = world()
    W.add('police', '4001', true); W.add('police', '4002', true, { offline = true })
    check('CONNECTION an on-duty row whose character is not loaded (stale after a crash/restart) is NOT counted', W.count('police') == 1)
    W.loaded['4002'] = true
    check('CONNECTION the same character counts once it is loaded again', W.count('police') == 2)
    W.loaded['4002'] = nil
    check('CONNECTION a character that disconnected again stops counting immediately', W.count('police') == 1)
end

-- ----------------------------------------------------------------- organizations
do
    local W = world()
    W.add('police', '5001', true); W.add('sahp', '5002', true); W.add('sheriff', '5003', true); W.add('sheriff', '5004', true); W.add('fib', '5005', true)
    check('ORG only the requested organization is counted (police/sahp/sheriff/fib are independent)', W.count('police') == 1 and W.count('sahp') == 1 and W.count('sheriff') == 2 and W.count('fib') == 1 and W.count('army') == 0)
    check('ORG ids are normalized (case/whitespace)', W.count('  SHERIFF ') == 2 and W.count('Police') == 1)
    check('ORG invalid / unknown / malformed ids return invalid_organization (never 0)', select(2, W.count('ems')) == 'invalid_organization' and select(2, W.count('gang_x')) == 'invalid_organization'
        and select(2, W.count('')) == 'invalid_organization' and select(2, W.count(nil)) == 'invalid_organization' and select(2, W.count(42)) == 'invalid_organization'
        and select(2, W.count("sahp'; DROP")) == 'invalid_organization' and select(2, W.count({})) == 'invalid_organization' and W.count('ems') == nil)
    check('ORG a new law organization added to the central config works with no code change', (function() W.central.newlaw = {}; table.insert(W.central.newlaw, { cid = '5900', duty = true }); W.loaded['5900'] = true; return W.count('newlaw') == 1 end)())
end

-- ----------------------------------------------------------------- duplicates / non-law
do
    local W = world()
    W.add('police', '6001', true); W.add('police', '6001', true)
    check('DUPLICATE the same character cannot count twice', W.count('police') == 1)
    W.add('sahp', '6002', true)   -- a character appears in two organizations: each org counts it once, independently
    W.add('sheriff', '6002', true)
    check('DUPLICATE the same character in two organizations counts once per organization', W.count('sahp') == 1 and W.count('sheriff') == 1)
    W.loaded['7001'] = true; W.loaded['7002'] = true   -- loaded civilians / EMS / gang members have no law member row
    check('NON-LAW civilians, EMS, gang and other unrelated characters are never counted (membership rows only)', W.count('police') == 1 and W.count('sahp') == 1)
    check('NON-LAW an admin who merely holds permissions has no member row and is not counted', W.count('fib') == 0)
end

-- ----------------------------------------------------------------- unavailable vs zero
do
    local W = world()
    W.add('police', '8001', true)
    W.lawReady = false
    check('UNAVAILABLE central law not ready -> nil, unavailable (not 0)', (function() local n, why = W.count('sahp'); return n == nil and why == 'unavailable' end)())
    check('UNAVAILABLE the legacy police organization has its own readiness', W.count('police') == 1)
    W.legacyReady = false
    check('UNAVAILABLE embedded police not ready -> nil, unavailable', (function() local n, why = W.count('police'); return n == nil and why == 'unavailable' end)())
    W.legacyReady, W.lawReady = true, true
    W.dbError = true
    check('UNAVAILABLE a database error -> nil, unavailable (never a guessed 0)', select(2, W.count('police')) == 'unavailable' and select(2, W.count('sahp')) == 'unavailable' and W.count('police') == nil)
    W.dbError = false; W.loadedError = true
    check('UNAVAILABLE a character-state error counts as not loaded, never as on duty', W.count('police') == 0)
    W.loadedError = false
    check('RESTART when law is ready again the count resumes with no other action', W.count('police') == 1)
end

-- ----------------------------------------------------------------- security
do
    local W = world()
    W.add('police', '9001', true)
    check('SECURITY an unlisted resource is forbidden', select(2, W.count('police', 'cm-evil')) == 'forbidden' and W.count('police', 'cm-evil') == nil)
    check('SECURITY a nil invoker is forbidden (fail closed)', select(2, W.counter.count('police', nil)) == 'forbidden')
    check('SECURITY allowlisted resources (cm-crime, cm-admin, cm-law) may read', W.count('police', 'cm-crime') == 1 and W.count('police', 'cm-admin') == 1 and W.count('police', 'cm-law') == 1)
    check('PRIVACY the result is a bare number: no table, names, ids, ranks or positions', type(W.count('police')) == 'number')
end

-- ----------------------------------------------------------------- wiring in the production source
do
    local main = readAll(here .. '/server/main.lua')
    local cfg = readAll(here .. '/shared/config.lua')
    local manifest = readAll(here .. '/fxmanifest.lua')
    check('WIRING the export exists, goes through the pure factory with the invoker and returns false, reason on failure (a leading nil would lose the reason)', main:find("exports('GetOnDutyCount'", 1, true) ~= nil and main:find('dutyCounter.count(orgId, GetInvokingResource() or RESOURCE)', 1, true) ~= nil and main:find('if n == nil then return false, reason end', 1, true) ~= nil)
    check('WIRING there is no client path: no net event, command or callback for the count', (function()
        for line in main:gmatch('[^\n]+') do if line:find('GetOnDutyCount', 1, true) and (line:find('RegisterNetEvent', 1, true) or line:find('lib.callback', 1, true) or line:find('RegisterCommand', 1, true)) then return false end end
        return not main:find("callback.register%('cm%-law:server:onDutyCount") and not main:find("RegisterNetEvent%('cm%-law:server:onDutyCount") end)())
    check('WIRING the central query is by organization, on duty, ranked and not suspended; the legacy query has the matching rules', main:find('m.organization_id = ? AND m.on_duty = 1 AND m.suspended_until IS NULL', 1, true) ~= nil
        and main:find('JOIN cm_legal_ranks r ON r.id = m.rank_id AND r.organization_id = m.organization_id', 1, true) ~= nil
        and main:find('FROM cm_police_members m JOIN cm_police_ranks r ON r.id = m.rank_id', 1, true) ~= nil and main:find('m.suspended_until IS NULL OR m.suspended_until <= NOW()', 1, true) ~= nil)
    check('WIRING liveness uses the same loaded-character resolution as the rest of law (sourceFor + a connected player name)', main:find('local src = sourceFor(characterId)', 1, true) ~= nil and main:find('GetPlayerName(src) ~= nil', 1, true) ~= nil)
    check('WIRING the caller allowlist is configuration and lists cm-crime', cfg:find('Config.OnDutyCountCallers', 1, true) ~= nil and cfg:find("['cm-crime'] = true", 1, true) ~= nil)
    check('WIRING the factory loads before main.lua', (function() local a, b = manifest:find("server/duty_count.lua", 1, true), manifest:find("'server/main.lua'", 1, true); return a and b and a < b end)())
    check('SCOPE cm-law knows nothing about crime policy (no minPolice / robbery / tier words in the factory)', (function() local f = readAll(here .. '/server/duty_count.lua'):lower(); return not f:find('minpolice') and not f:find('robbery') and not f:find('cooldown') end)())
end

print(('\ncm-law on-duty count self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
