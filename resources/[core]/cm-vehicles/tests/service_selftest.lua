-- Deterministic local self-test for server/service_core.lua + Config.Service.TrustedCallers (no FiveM, no DB).
--   lua tests/service_selftest.lua        (run from resources/[core]/cm-vehicles)
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
dofile(here .. '/shared/config.lua')
dofile(here .. '/shared/utils.lua')
dofile(here .. '/server/service_core.lua')
local Core, U = CMVehicles.ServiceCore, CMVehicles.Utils
local trusted = (CMVehicles.Config or Config).Service.TrustedCallers

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and (' (' .. tostring(detail) .. ')') or '')) end
end
local function caller(r) return Core.ResolveCaller(r, 'cm-vehicles', trusted) end
local function fieldsOf(r) local ok, f = caller(r); return ok and f or nil end

-- ------------------------------------------------------------ caller matrix
check('CALLER cm-mechanic allowed', (caller('cm-mechanic')))
check('CALLER cm-vehicles internal (nil invoker) allowed, unrestricted', select(2, caller(nil)) == nil and (caller(nil)))
check('CALLER cm-vehicles self via export allowed', (caller('cm-vehicles')))
for _, r in ipairs({ 'cm-law', 'cm-ems', 'cm-gang', 'cm-carwash', 'cm-gasstations' }) do
    check('CALLER ' .. r .. ' allowed (proven consumer)', (caller(r)))
end
for _, r in ipairs({ 'cm-trade', 'cm-phone', 'cm-tuning', 'cm-billing', 'cm-admin', 'rogue_test_resource', '' }) do
    local ok, why = caller(r)
    check('CALLER ' .. (r == '' and '<empty>' or r) .. ' denied', ok == false and why == r)
end
check('CALLER malformed trust table fails closed', Core.ResolveCaller('cm-mechanic', 'cm-vehicles', nil) == false)

-- ------------------------------------------------------------ mechanic patches
local mech = fieldsOf('cm-mechanic')
local c, why = Core.Sanitize(U, { engineHealth = 1000.0, tankHealth = 1000.0, bodyHealth = 1000.0 }, mech)
check('PATCH engine/tank/body repair valid', c and c.engineHealth == 1000.0 and c.tankHealth == 1000.0 and c.bodyHealth == 1000.0, why)
c = Core.Sanitize(U, { engineHealth = 1000.0 }, mech)
local c2 = Core.Sanitize(U, { engineHealth = 1000.0 }, mech)
check('PATCH absolute: replay yields identical clean patch', c and c2 and c.engineHealth == c2.engineHealth)
c, why = Core.Sanitize(U, { conditionState = { windowSchema = 2, brokenWindows = {}, doors = {}, tyres = {} } }, mech)
check('PATCH conditionState (windows/doors/tyres) valid', c and type(c.conditionState) == 'table', why)
c, why = Core.Sanitize(U, { clearVisualDamage = true }, mech)
check('PATCH clearVisualDamage -> empty conditionState, flag consumed', c and type(c.conditionState) == 'table' and c.clearVisualDamage == nil, why)
c, why = Core.Sanitize(U, { engineHealth = 5000 }, mech)
check('PATCH out-of-range health clamped to 1000', c and c.engineHealth == 1000.0, why)
c, why = Core.Sanitize(U, { engineHealth = -50 }, mech)
check('PATCH negative health clamped to 0 (genuine zero preserved)', c and c.engineHealth == 0.0, why)

-- ------------------------------------------------------------ rejections
local function rej(name, patch, allowed, reason)
    local r, w = Core.Sanitize(U, patch, allowed)
    check(name, r == nil and w == reason, w)
end
for _, f in ipairs({ 'owner_character_id', 'owner_id', 'owner_type', 'model', 'plate', 'license_number', 'registration_expires_at',
    'insurance_expires_at', 'metadata', 'mods', 'keys', 'garage', 'location', 'price', 'money', 'id' }) do
    rej('REJECT field ' .. f, { [f] = 1, engineHealth = 1000 }, mech, 'unsupported_field')
end
rej('REJECT field_not_permitted: mechanic cannot set fuel', { fuel = 100 }, mech, 'field_not_permitted')
rej('REJECT field_not_permitted: mechanic cannot set dirt', { dirtLevel = 0 }, mech, 'field_not_permitted')
rej('REJECT carwash cannot repair engine', { engineHealth = 1000 }, fieldsOf('cm-carwash'), 'field_not_permitted')
rej('REJECT gasstations cannot set engine', { engineHealth = 1000 }, fieldsOf('cm-gasstations'), 'field_not_permitted')
rej('REJECT non-table patch', 'engineHealth', mech, 'invalid_patch')
rej('REJECT nil patch', nil, mech, 'invalid_patch')
rej('REJECT empty patch', {}, mech, 'invalid_patch')
rej('REJECT string health', { engineHealth = 'full' }, mech, 'invalid_patch')
rej('REJECT NaN health', { engineHealth = 0 / 0 }, mech, 'invalid_patch')
rej('REJECT inf health', { bodyHealth = math.huge }, mech, 'invalid_patch')
rej('REJECT table health', { bodyHealth = {} }, mech, 'invalid_patch')
rej('REJECT conditionState non-table', { conditionState = 'x' }, mech, 'invalid_patch')
rej('REJECT clearVisualDamage non-boolean', { clearVisualDamage = 1 }, mech, 'invalid_patch')
rej('REJECT clearVisualDamage=false alone (no mutation)', { clearVisualDamage = false }, mech, 'invalid_patch')
rej('REJECT numeric key', { [1] = 5 }, mech, 'unsupported_field')

-- ------------------------------------------------------------ other consumers still work
c, why = Core.Sanitize(U, { dirtLevel = 0.0 }, fieldsOf('cm-carwash'))
check('CARWASH dirt patch valid', c and c.dirtLevel == 0.0, why)
c, why = Core.Sanitize(U, { fuel = 130.4 }, fieldsOf('cm-gasstations'))
check('GAS fuel clamped to 100 and floored', c and c.fuel == 100, why)
c, why = Core.Sanitize(U, { fuel = 100, engineHealth = 1000.0, bodyHealth = 1000.0, tankHealth = 1000.0, dirtLevel = 0,
    conditionState = {}, clearVisualDamage = true }, fieldsOf('cm-law'))
check('LAW/EMS fleet baseline patch valid', c ~= nil, why)
c, why = Core.Sanitize(U, { fuel = 100, engineHealth = 1000.0, bodyHealth = 1000.0, tankHealth = 1000.0, clearVisualDamage = true }, fieldsOf('cm-gang'))
check('GANG fleet baseline patch valid', c ~= nil, why)
c, why = Core.Sanitize(U, { fuel = 50, dirtLevel = 3, bodyHealth = 800 }, nil)
check('INTERNAL unrestricted patch valid', c and c.fuel == 50 and c.dirtLevel == 3, why)
check('INTERNAL still rejects unknown field', Core.Sanitize(U, { owner_id = 'x' }, nil) == nil)

-- ------------------------------------------------------------ pricing ownership (static)
local function slurp(p) local f = io.open(here .. '/../' .. p, 'rb'); if not f then return nil end local s = f:read('*a'); f:close(); return s end
local tun = slurp('cm-tuning/server/main.lua')
if tun then
    check('PRICING cm-tuning no longer calls ServiceVehicle', not tun:find("exports['cm-vehicles']:ServiceVehicle", 1, true))
    check('PRICING cm-tuning rebuild handler is deny-only', tun:find("Engine repair is handled by a mechanic", 1, true) ~= nil)
    check('PRICING cm-tuning rebuild handler does not charge', not tun:match("repairEngine'.-charge%(src"))
end
check('PRICING cm-tuning is not a trusted service caller', trusted['cm-tuning'] == nil)
local tcfg = slurp('cm-tuning/shared/config.lua')
if tcfg then check('PRICING tuning EngineRepair disabled', tcfg:match('EngineRepair = {%s*enabled = false') ~= nil) end
local mc = slurp('cm-mechanic/config.lua')
if mc then check('TUNING_REQUEST is owned by cm-tuning (authority) and carries no repair parts', mc:match("tuning_request = {[^}]-authority = 'cm%-tuning'") ~= nil and mc:match("tuning_request = {[^}]-parts = {}") ~= nil) end

print(('service self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
