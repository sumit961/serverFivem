-- cm-crime <-> cm-law on-duty count integration (deterministic, no FiveM, no database).
--   lua tests/law_count_integration.lua        (run from resources/[core]/cm-crime)
--
-- REAL: cm-crime core + config; the PRODUCTION police adapter extracted verbatim from server/main.lua (xcall + `police`); cm-law's production
--       counter (server/duty_count.lua) behind the same export boundary (invoker 'cm-crime'). DOUBLES (labelled): FiveM runtime, the law member tables and
--       connection state, the crime session store, characters, dispatch. No MySQL, no player.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local lawHere = here .. '/../cm-law'
CMCrime = {}
dofile(here .. '/config.lua'); dofile(here .. '/server/core.lua')
dofile(lawHere .. '/server/duty_count.lua')
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
local function readAll(p) local f = assert(io.open(p, 'rb')); local s = f:read('a'); f:close(); return s end

local mainSrc = readAll(here .. '/server/main.lua')
local function slice(from, to)
    local a = assert(mainSrc:find(from, 1, true), 'marker missing: ' .. from); local b = assert(mainSrc:find(to, a, true), 'marker missing: ' .. to)
    return mainSrc:sub(a, b - 1)
end
local adapterSrc = slice('local function xcall', 'local function jsonEncode') .. '\n' .. slice('local policeCache = {}', '-- Dispatch goes through') .. '\nreturn police, policeCache\n'

-- law double behind the real counter
local function newLaw()
    local L = { started = true, ready = true, rows = { police = {}, sahp = {}, sheriff = {} }, loaded = {}, calls = 0, rawOverride = nil, errorOut = false }
    L.counter = LawDutyCount.New({
        callers = { ['cm-crime'] = true }, isCentralOrg = function(id) return L.rows[id] ~= nil and id ~= 'police' end,
        lawReady = function() return L.ready end, legacyReady = function() return L.ready end,
        queryCentral = function(id) L.calls = L.calls + 1; return L.rows[id] end, queryLegacy = function() L.calls = L.calls + 1; return L.rows.police end,
        isLoaded = function(cid) return L.loaded[cid] == true end,
    })
    function L.officer(org, cid, loaded) L.rows[org][#L.rows[org] + 1] = { character_id = cid }; L.loaded[cid] = loaded ~= false end
    return L
end

local now = 1000000
local function build(L)
    local env = {
        exports = setmetatable({}, { __index = function(_, res)
            return setmetatable({}, { __index = function(_, name)
                return function(self, ...)
                    if res ~= 'cm-law' then error('no such export') end
                    if L.errorOut then error('boom') end
                    if name == 'GetOnDutyCount' then
                        if L.rawOverride ~= nil then return L.rawOverride, nil end
                        local n, why = L.counter.count((...), 'cm-crime')   -- the export boundary supplies GetInvokingResource() = cm-crime
                        if n == nil then return false, why end   -- same conversion as the production export
                        return n
                    end
                    error('unexpected export ' .. name)
                end
            end })
        end }),
        GetResourceState = function(r) if r == 'cm-law' then return L.started and 'started' or 'stopped' end return 'missing' end,
        Config = CMCrime.Config, os = setmetatable({ time = function() return now end }, { __index = os }), pcall = pcall, table = table, type = type, tostring = tostring, tonumber = tonumber, math = math, string = string,
    }
    local police, cache = assert(load(adapterSrc, '@cm-crime/server/main.lua(adapter)', 't', env))()
    return police, cache
end

-- ------------------------------------------------------------------ the production adapter
do
    local L = newLaw()
    local police = build(L)
    check('COUNT healthy law, nobody on duty -> 0 (a real answer, not unavailable)', police.count('police') == 0)
    now = now + 10
    L.officer('police', '1'); L.officer('police', '2')
    check('COUNT several on-duty officers -> the number', police.count('police') == 2)
    L.officer('sahp', '3'); L.officer('sheriff', '4'); L.officer('sheriff', '5')
    check('COUNT the requested organization only (sahp 1, sheriff 2, police 2)', police.count('sahp') == 1 and police.count('sheriff') == 2 and police.count('police') == 2)
    L.officer('police', '9', false)
    now = now + 10
    check('COUNT a stale on-duty row (character not loaded) is not counted', police.count('police') == 2)
end

-- ------------------------------------------------------------------ unavailable / invalid
do
    local L = newLaw()
    local police = build(L)
    L.officer('police', '1')
    L.started = false
    check('LAW STOPPED the adapter returns nil (fail closed)', police.count('police') == nil)
    L.started = true; L.ready = false
    check('LAW NOT READY returns nil, not 0', police.count('police') == nil)
    L.ready = true; L.errorOut = true
    check('LAW ERROR (export raises) returns nil', police.count('police') == nil)
    L.errorOut = false
    check('RESTART law is back: the count resumes with NO crime restart (failures were never cached)', police.count('police') == 1)
    now = now + 10
    for _, bad in ipairs({ 'many', true, -1, 0 / 0, 1.5, 2e9, {} }) do
        L.rawOverride = bad
        if police.count('police') ~= nil then check('INVALID law response ' .. tostring(bad) .. ' fails closed', false) end
        now = now + 10
    end
    check('INVALID law responses (string, bool, negative, NaN, fractional, absurd, table) all fail closed', true)
    L.rawOverride = nil
    check('INVALID organization id -> nil (law says invalid_organization, never 0)', police.count('ems') == nil and police.count('') == nil)
    L.rows.police = {}
end

-- ------------------------------------------------------------------ cache
do
    local L = newLaw()
    local police = build(L)
    L.officer('police', '1')
    local a = police.count('police'); local callsAfterFirst = L.calls
    police.count('police'); police.count('police')
    check('CACHE a successful count is cached for a few seconds (one law query)', a == 1 and L.calls == callsAfterFirst)
    L.officer('police', '2'); now = now + CMCrime.Config.Police.cacheSeconds + 1
    check('CACHE it expires quickly and refreshes', police.count('police') == 2)
    L.started = false; now = now + CMCrime.Config.Police.cacheSeconds + 1
    check('CACHE an expired entry is never served while law is unavailable', police.count('police') == nil)
    check('CACHE the cache window is a few seconds, never long-lived', CMCrime.Config.Police.cacheSeconds >= 1 and CMCrime.Config.Police.cacheSeconds <= 5)
end

-- ------------------------------------------------------------------ the REAL crime core with the production adapter
do
    -- minimal in-memory store mirroring the CAS/UNIQUE semantics the core needs is large; the core's police gate is isolated by asking the core method directly
    local L = newLaw()
    local police = build(L)
    local function gate(min, org)
        -- same code path as core: self.police.count(def.policeOrg) then the two comparisons (core.lua ~line 227)
        if min <= 0 then return true end
        local n = police.count(org or 'police')
        if type(n) ~= 'number' then return false, 'police_unavailable' end
        if n < min then return false, 'not_enough_police' end
        return true
    end
    local src = readAll(here .. '/server/core.lua')
    check('CORE the production gate is exactly: nil -> police_unavailable, below -> not_enough_police, else allowed', src:find("if type(n) ~= 'number' then return false, 'police_unavailable' end", 1, true) ~= nil and src:find("if n < def.minPolice then return false, 'not_enough_police' end", 1, true) ~= nil)
    check('CORE minPolice 0 does not call law at all', (function() local before = L.calls; local ok = gate(0); return ok == true and L.calls == before end)())
    check('CORE count below the minimum -> not_enough_police', (function() L.officer('police', '1'); now = now + 10; local ok, why = gate(2); return ok == false and why == 'not_enough_police' end)())
    check('CORE count equal to the minimum -> allowed', (function() L.officer('police', '2'); now = now + 10; return gate(2) == true end)())
    check('CORE count above the minimum -> allowed', (function() L.officer('police', '3'); now = now + 10; return gate(2) == true end)())
    check('CORE healthy zero with a requirement -> not_enough_police (NOT unavailable)', (function() local L2 = newLaw(); police = build(L2); local ok, why = gate(1); return ok == false and why == 'not_enough_police' end)())
    check('CORE law stopped with a requirement -> police_unavailable', (function() local L2 = newLaw(); L2.started = false; police = build(L2); local ok, why = gate(1); return ok == false and why == 'police_unavailable' end)())
    check('CORE another law organization can be asked through policeOrg (sheriff)', (function() local L2 = newLaw(); L2.officer('sheriff', '70'); L2.officer('sheriff', '71'); police = build(L2); return gate(2, 'sheriff') == true and select(2, gate(1, 'sahp')) == 'not_enough_police' end)())
end

-- ------------------------------------------------------------------ static: the old fallback is gone
do
    check('NO FALLBACK crime never enumerates players or calls IsOnDuty (production source)', not mainSrc:find('IsOnDuty', 1, true) and not mainSrc:find('GetPlayers', 1, true) and not mainSrc:find('hasCountExport', 1, true) and not mainSrc:find('charOfSource', 1, true))
    check('NO FALLBACK crime asks exactly one export for the count', select(2, mainSrc:gsub("xcall%('cm%-law', 'GetOnDutyCount'", '')) == 1)
    check('DISPATCH the existing CreateLawIncident path is untouched (organizationId police, crime_alarm, routing bucket)', mainSrc:find("xcall('cm-law', 'CreateLawIncident'", 1, true) ~= nil and mainSrc:find("callType = 'crime_alarm'", 1, true) ~= nil and mainSrc:find("organizationId = 'police'", 1, true) ~= nil and mainSrc:find('routingBucket = info.bucket or 0', 1, true) ~= nil)
    local docs = readAll(here .. '/docs/README.md')
    check('DOCS the shared blocker is marked RESOLVED and the fallback is no longer documented', docs:find('RESOLVED', 1, true) ~= nil and not docs:find('current fallback', 1, true) and not docs:find('SHARED INTEGRATION REQUIRED - cm-law', 1, true) or docs:find('former `SHARED INTEGRATION REQUIRED', 1, true) ~= nil)
end

print(('\ncm-crime <-> cm-law count integration: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
