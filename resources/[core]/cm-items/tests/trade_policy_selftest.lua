-- Deterministic self-test for the cm-items trade policy (CMItems.CanTradeItem) over the REAL definitions.
--   lua tests/trade_policy_selftest.lua        (run from resources/[core]/cm-items)
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
local function jsonEncode(v)
    if type(v) == 'table' then local o = {} for k, x in pairs(v) do o[#o + 1] = tostring(k) .. ':' .. jsonEncode(x) end table.sort(o) return '{' .. table.concat(o, ',') .. '}' end
    return tostring(v)
end
json = { encode = jsonEncode }
CMItems = {}
for _, f in ipairs({ 'config.lua', 'shared/categories.lua', 'shared/items.lua', 'shared/virtual.lua', 'shared/api.lua' }) do dofile(here .. '/' .. f) end
local function can(name, meta) return CMItems.CanTradeItem(name, meta) end

for _, n in ipairs({ 'water', 'sandwich', 'bandage', 'medkit', 'painkillers', 'repairkit' }) do
    check('POLICY explicitly approved item is tradeable: ' .. n, can(n) == true)
end
check('POLICY the approved set is small and explicit (6 definitions carry tradeable = true)', (function() local c = 0 for _, d in pairs(CMItems.Items) do if d.tradeable == true then c = c + 1 end end return c == 6 end)())
for _, n in ipairs({ 'weapon_pistol', 'ammo_9mm', 'id_card', 'driver_license', 'boat_license', 'air_license', 'armor' }) do
    check('POLICY sensitive item blocked: ' .. n, can(n) == false)
end
check('POLICY a vehicle key / admin / dev / test item is blocked by name even if a definition said tradeable', (function()
    for _, n in ipairs({ 'vehicle_key', 'key_house', 'admin_wand', 'dev_tool', 'test_item', 'debug_x', 'license_card', 'weapon_knife' }) do
        CMItems.Items[n] = { label = n, weight = 1, stack = true, category = 'misc', tradeable = true }
        if can(n) ~= false then return false, n end
    end return true end)())
check('POLICY a tradeable flag cannot override a hard-blocked class (weapon / document / robbery-protected / singleton / characterId-bound)', (function()
    CMItems.Items.fancy_gun = { label = 'x', weight = 1, category = 'misc', weapon = true, tradeable = true }
    CMItems.Items.fancy_doc = { label = 'x', weight = 1, category = 'document', tradeable = true }
    CMItems.Items.fancy_safe = { label = 'x', weight = 1, category = 'misc', robberyProtected = true, tradeable = true }
    CMItems.Items.fancy_one = { label = 'x', weight = 1, category = 'misc', singleton = true, tradeable = true }
    CMItems.Items.fancy_bound = { label = 'x', weight = 1, category = 'misc', metadataRequired = { 'characterId' }, tradeable = true }
    for _, n in ipairs({ 'fancy_gun', 'fancy_doc', 'fancy_safe', 'fancy_one', 'fancy_bound' }) do if can(n) ~= false then return false, n end end return true end)())
check('POLICY fail closed: no flag means not tradeable (clothing, materials, tools, catalog-style items)', can('clothing_hat') == false and can('iron_ore') == false and can('timber') == false and can('plastic') == false and can('lockpick') == false)
check('POLICY the approved COMMODITY materials are NOT tradeable by default (flip tradeable per item when sources go live)', can('metal_scrap') == false and can('reclaimed_metal') == false)
check('POLICY unknown / malformed names are blocked', can('no_such_item') == false and can(nil) == false and can('') == false and can(42) == false)
check('POLICY a bound / soulbound / non-transferable / character-bound instance is blocked', can('water', { bound = true }) == false and can('water', { soulbound = true }) == false and can('water', { nonTransferable = true }) == false
    and can('water', { tradeable = false }) == false and can('water', { characterId = 5 }) == false)
check('POLICY plain and benign metadata is accepted; oversized or non-table metadata is rejected', can('water', { batch = 'A1' }) == true and can('water', {}) == true and can('water', { s = string.rep('x', 5000) }) == false and can('water', 'x') == false)
check('POLICY the default for a new definition is false', (function() local out = CMItems.GetItem('water'); return out ~= nil and out.tradeable == true and CMItems.GetItem('iron_ore').tradeable == false end)())
print(('\ncm-items trade policy self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
