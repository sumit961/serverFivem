-- Source-level wiring checks for the purchase-settlement consumers.
--   lua tests/consumer_wiring_test.lua        (run from resources/[core]/cm-core)
-- Fails if cm-store / nv_cloth fall back to plain money or AddItem calls on the purchase path, if their reference prefixes drift from the
-- cm-playerdata gate, or if the restock paths go back to absolute stock writes.
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1; print('PASS  ' .. name) else failed = failed + 1; print('FAIL  ' .. name) end
end
local function read(rel) local f = assert(io.open(here .. '/../' .. rel, 'rb')); local s = f:read('a'):gsub('\r\n', '\n'); f:close(); return s end

local store, cloth = read('cm-store/server/main.lua'), read('nv_cloth/server/sv_cloth.lua')
local storeMf, clothMf = read('cm-store/fxmanifest.lua'), read('nv_cloth/fxmanifest.lua')
local co, pd = read('cm-commercial-ownership/server/main.lua'), read('cm-playerdata/server/main.lua')
local inv = read('cm-inventory/server/craft.lua')

local function checkoutBody(src, from, to) local a = assert(src:find(from, 1, true)); local b = assert(src:find(to, a, true)); return src:sub(a, b) end
local storeFlow = checkoutBody(store, 'local function processCheckout(src, data)', "RegisterNetEvent('cm-store:server:checkoutOrder'")
local clothFlow = checkoutBody(cloth, 'local function processBuyClothes(src, method, outfit)', "RegisterNetEvent('nvCloth:buyClothes')")

check('cm-store checkout settles through the shared engine', storeFlow:find('engine.run({', 1, true) ~= nil and storeFlow:find('STORE-PUR-', 1, true) ~= nil)
check('cm-store checkout has no plain money or AddItem calls', not storeFlow:find('removeCash') and not storeFlow:find('removeBank') and not storeFlow:find('addCash') and not storeFlow:find('addBank') and not storeFlow:find('AddItem') and not storeFlow:find('giveItem'))
check('cm-store has no reservation tracker / unreferenced refund helpers left', not store:find('PendingStock') and not store:find('releaseStock') and not store:find('refundPlayer') and not store:find('chargePlayer'))
check('cm-store includes the shared module before server/main.lua', storeMf:find("'@cm-core/shared/item_purchase.lua'", 1, true) ~= nil and storeMf:find("item_purchase.lua'", 1, true) < storeMf:find("'server/main.lua'", 1, true))
check('cm-store price comes from the server catalog, never the client', storeFlow:find('entry.price', 1, true) ~= nil and not storeFlow:find('orderItem.price') and not storeFlow:find('data.total') and not storeFlow:find('data.price'))
check('cm-store restock writes are deltas capped by LEAST (no absolute stock = ? from a stale read)', not store:find('price_tier = ?, stock = ?', 1, true) and select(2, store:gsub('stock = LEAST%(%?, stock %+ %?%)', '')) == 2)

check('nv_cloth purchase settles through the shared engine', clothFlow:find('engine.run({', 1, true) ~= nil and clothFlow:find('CLOTH-PUR-', 1, true) ~= nil)
check('nv_cloth purchase has no plain money / AddItem / RemoveItem calls', not cloth:find('RemoveMoney') and not cloth:find('AddMoney') and not cloth:find(':AddItem') and not cloth:find('%.AddItem') and not cloth:find(':RemoveItem') and not cloth:find('takeCharacterMoney') and not cloth:find('refundCharacterMoney'))
check('nv_cloth has no loose stock reserve/release statements left', not cloth:find('stock = stock - ?', 1, true) and not cloth:find('stock = stock + ?', 1, true) and not cloth:find('releaseReservedStock'))
check('nv_cloth includes the shared module before its server scripts', clothMf:find("'@cm-core/shared/item_purchase.lua'", 1, true) ~= nil and clothMf:find('item_purchase.lua', 1, true) < clothMf:find("'server/sv_*.lua'", 1, true))
check('nv_cloth checks the grant payload size before money moves', clothFlow:find('#encoded > 7000', 1, true) ~= nil and clothFlow:find('engine.run', 1, true) > clothFlow:find('#encoded > 7000', 1, true))

check('commercial-ownership Manage restock is a capped delta, price tier is a separate write', co:find('SET stock = LEAST(?, stock + ?) WHERE shop_id = ? AND owner_character_id = ?', 1, true) ~= nil and not co:find('SET price_tier = ?, stock = ?', 1, true))

check('cm-playerdata gate lists exactly the purchase prefixes used by the consumers', pd:find("prefix = 'STORE-PUR-'", 1, true) ~= nil and pd:find("prefix = 'CLOTH-PUR-'", 1, true) ~= nil and pd:find("prefix = 'GAS-PUR-'", 1, true) ~= nil)
check('cm-inventory grant allowlist lists exactly the three purchase owners', inv:find("['cm-gasstations'] = {}", 1, true) ~= nil and inv:find("['cm-store']", 1, true) ~= nil and inv:find("['nv_cloth']", 1, true) ~= nil and select(2, inv:gsub("grantTrusted = {", '')) == 1)
check('only nv_cloth has the clothing grant privilege', select(2, inv:gsub('clothing = true', '')) >= 1 and inv:find("['nv_cloth'] = { clothing = true", 1, true) ~= nil and not inv:find("['cm-store'] = { clothing", 1, true))

print(('\nconsumer wiring: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
