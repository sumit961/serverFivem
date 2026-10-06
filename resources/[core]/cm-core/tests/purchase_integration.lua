-- Cross-resource integration: the shared item-purchase settlement against the REAL owner implementations.
--   lua tests/purchase_integration.lua        (run from resources/[core]/cm-core)
--
-- REAL (production code, not mocks):
--   cm-core/shared/item_purchase.lua                          (settlement state machine + owner adapters)
--   cm-inventory server/craft.lua (+ db/items/slots/bags/equipment/external) via the inventory harness
--                                                             (ExecuteItemGrant / GetItemGrantStatus / CancelItemGrant, planner, ledger, trust policy)
--   cm-playerdata server/main.lua money-operation block       (extracted verbatim: journaled debit/credit/status, fingerprint, caller gate)
-- TEST DOUBLES (labelled): the FiveM runtime; the SQL layer under cm-inventory (in-memory engine of the harness) and under the playerdata block
--   (a small engine that understands exactly its statements incl. ROW_COUNT()-conditional inserts, UNIQUE reference and transaction rollback);
--   the purchase journal SQL (in-memory, same guards as the real statements; real SQL is tests/item_purchase_mysql_smoke.py).
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local invPath = here .. '/../cm-inventory'
local H = dofile(invPath .. '/tests/craft_harness.lua')(invPath)
local ITEMS = H.ITEMS
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end
ITEMS.water = { weight = 500 }; ITEMS.sandwich = { weight = 350 }; ITEMS.clothing_bags = ITEMS.clothing_bags or { weight = 500 }
ITEMS.clothing_pants = { weight = 100 }; ITEMS.heavy_box = { weight = 14000 }

CMItemPurchase = nil
dofile(here .. '/shared/item_purchase.lua')
local P = CMItemPurchase

-- ----------------------------------------------------------------------------------------------- real inventory
local idb = H.newDb(); idb.addChar(1); idb.addChar(2)
local W = H.newWorld(idb)

-- ----------------------------------------------------------------------------------------------- real playerdata money block
local INVOKER = 'cm-store'
local function readFile(path) local f = assert(io.open(path, 'rb')); local s = f:read('a'); f:close(); return s end
local pdSrc = (readFile(here .. '/../cm-playerdata/server/main.lua'):gsub('\r\n', '\n'))
local function between(a, b)
    local i = assert(pdSrc:find(a, 1, true), 'marker not found: ' .. a)
    local j = assert(pdSrc:find(b, i, true), 'marker not found: ' .. b)
    return pdSrc:sub(i, j - 1)
end
local function fn(name)
    local i = assert(pdSrc:find('local function ' .. name .. '(', 1, true))
    local j = assert(pdSrc:find('\nend\n', i, true))
    return pdSrc:sub(i, j + 4)
end

local money = { chars = { [1] = { cash = 5000, bank = 9000 }, [2] = { cash = 100, bank = 100 } }, journal = {}, econ = {}, jcount = 0 }
local function snapshot() local c = {} for id, a in pairs(money.chars) do c[id] = { cash = a.cash, bank = a.bank } end local j = {} for k, v in pairs(money.journal) do j[k] = v end return { chars = c, journal = j, econ = #money.econ } end
local function restore(s) money.chars = s.chars; money.journal = s.journal; while #money.econ > s.econ do table.remove(money.econ) end end
local fakeMySQL = { single = {}, transaction = {} }
function fakeMySQL.single.await(sql, p)
    if sql:find('FROM cm_character_money_operations WHERE reference', 1, true) then
        if money.failRead then error('db down') end
        local r = money.journal[p[1]]
        return r and { reference = p[1], character_id = r.character_id, account = r.account, direction = r.direction, amount = r.amount, fingerprint = r.fingerprint } or nil
    end
    local acct = sql:match('^SELECT (%a+) AS balance FROM characters WHERE id')
    if acct then local c = money.chars[tonumber(p[1])]; return c and { balance = c[acct] } or nil end
    error('money SQL double: unsupported single ' .. sql)
end
function fakeMySQL.transaction.await(queries)
    local snap = snapshot()
    local last = 0
    local ok, err = pcall(function()
        for _, q in ipairs(queries) do
            local sql, p = q.query, q.values
            local acct = sql:match('^UPDATE characters SET (%a+) = ')
            if acct then
                local c = money.chars[p[#p - ((sql:find('>= %?') and 1) or 0)] or p[2]]
                if sql:find('%- %?') then
                    c = money.chars[p[2]]
                    if c and c[acct] >= p[3] then c[acct] = c[acct] - p[1]; last = 1 else last = 0 end
                else
                    c = money.chars[p[2]]
                    if c then c[acct] = c[acct] + p[1]; last = 1 else last = 0 end
                end
            elseif sql:find('^INSERT INTO cm_character_money_operations') then
                if last ~= 1 then last = 0 else
                    if money.journal[p[1]] then error('Duplicate entry') end
                    money.journal[p[1]] = { character_id = p[2], account = p[3], direction = p[4], amount = p[5], fingerprint = p[6], resource = p[7] }
                    last = 1
                end
            elseif sql:find('^INSERT INTO economy_transactions') then
                if last == 1 then money.econ[#money.econ + 1] = p end
            else
                error('money SQL double: unsupported ' .. sql)
            end
        end
    end)
    if not ok then restore(snap); error(err) end
    return true
end

local pdRegistry = {}
local pdEnv = setmetatable({
    MySQL = fakeMySQL, PlayerData = {}, MoneyMutationLocks = {},
    Config = { Money = { TransactionLog = true, MaxSingleChange = 1000000000 } },
    ValidMoneyAccounts = { cash = true, bank = true },
    GetInvokingResource = function() return INVOKER end, GetCurrentResourceName = function() return 'cm-playerdata' end,
    CanMutate = function() return true end, Log = function() end, EncodeJson = H.json.encode,
    SetState = function() end, PushUpdate = function() end, Audit = function() end, TriggerEvent = function() end, TriggerClientEvent = function() end,
    exports = function(name, f) pdRegistry[name] = f end,
    math = math, tostring = tostring, tonumber = tonumber, type = type, pairs = pairs, ipairs = ipairs, pcall = pcall, error = error, string = string, table = table, select = select,
}, { __index = function() return nil end })
local chunk = fn('NormalizeAccount') .. fn('NormalizeAmount') .. between('local MONEY_OP_SQL = {', "exports('AddCash'")
assert(load(chunk, '@cm-playerdata/money-ops', 't', pdEnv))()

-- ----------------------------------------------------------------------------------------------- wiring: exports table dispatching to both real owners
local function ownerExports()
    return setmetatable({}, { __index = function(_, resource)
        local registry = resource == 'cm-playerdata' and pdRegistry or W.registry
        return setmetatable({}, { __index = function(_, name)
            return function(_, ...) -- colon-style call, exactly like production adapters
                INVOKER = W.invoker
                return registry[name](...)
            end
        end })
    end })
end
local function stateOf() return 'started' end

-- the purchase journal double
local function newJournal(world)
    local db = {}
    local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
    if not world.rows then world.rows = {}; world.store = { stock = 100, owner = 7, balance = 0 } end
    function db.insert(o) if world.rows[o.reference] then return false end local r = copy(o); r.state = 'pending'; r.reserved_units = 0; r.items_state = 'pending'; world.rows[o.reference] = r return true end
    function db.get(ref) local r = world.rows[ref]; return r and copy(r) or false end
    function db.reserve(ref, _, units) local r, s = world.rows[ref], world.store if r and r.state == 'pending' and r.reserved_units == 0 and s.stock >= units then s.stock = s.stock - units; r.reserved_units = units return true end return false end
    function db.setItems(ref, to) local r = world.rows[ref] if r and r.state == 'pending' and r.items_state == 'pending' then r.items_state = to return true end return false end
    function db.finalize(ref, state, refund, release, share)
        local r, s = world.rows[ref], world.store
        if not r or r.state ~= 'pending' then return false end
        r.state, r.refund_amount = state, refund; s.stock = math.min(8000, s.stock + release); if s.owner then s.balance = s.balance + share end
        return true
    end
    function db.stale() local o = {} for ref, r in pairs(world.rows) do if r.state == 'pending' then o[#o + 1] = ref end end table.sort(o) return o end
    return db
end

local seq = 0
local function newEngine(caller, wrap)
    local world = {}
    local owners = P.ownerDeps(ownerExports(), stateOf)
    if wrap then wrap(owners, world) end
    local engine = P.new({ db = newJournal(world), money = owners.money, items = owners.items, log = function() end })
    local function run(o)
        seq = seq + 1
        local base = { reference = ('%s-%04d'):format(caller == 'nv_cloth' and 'CLOTH-PUR-1' or 'STORE-PUR-1', seq), character_id = 1, scope_id = 1, account = 'bank', total = 70, units = 5, owner_pct = 80,
            items = { { item = 'water', amount = 3 }, { item = 'sandwich', amount = 2 } } }
        for k, v in pairs(o or {}) do base[k] = v end
        W.invoker = caller
        local r = engine.run(base)
        return r, base
    end
    return engine, world, run
end
local function setup(caller)
    idb.clear('1'); idb.ledger = {}; idb.audit = {}
    money.chars[1] = { cash = 5000, bank = 9000 }; money.journal = {}; money.econ = {}
    W.invoker = caller
end
local function bank() return money.chars[1].bank end
local function opCount() local n = 0 for _ in pairs(money.journal) do n = n + 1 end return n end
local function boom() error('simulated exception') end

-- 1 NORMAL ---------------------------------------------------------------------------------------------------------------
do
    setup('cm-store'); local _, world, run = newEngine('cm-store')
    local r, o = run()
    check('REAL NORMAL store purchase completes', r.code == 'completed' and r.delivered and r.paid == 70, r.code)
    check('REAL NORMAL debit journaled in cm-playerdata (<ref>:debit, bank) and balance moved once', bank() == 9000 - 70 and money.journal[o.reference .. ':debit'] and money.journal[o.reference .. ':debit'].account == 'bank' and opCount() == 1)
    check('REAL NORMAL whole cart in inventory via ONE grant ledger row (item_grant)', idb.count('1', 'water') == 3 and idb.count('1', 'sandwich') == 2 and #idb.ledger == 1 and idb.ledger[1].tx_type == 'item_grant')
    check('REAL NORMAL stock consumed 100 -> 95, owner share 56 credited once', world.store.stock == 95 and world.store.balance == 56)
end

-- 2 DEFINITIVE DELIVERY FAILURE (real planner refuses: no capacity) ------------------------------------------------------
do
    setup('cm-store'); idb.give('1', 'pocket-1', 'heavy_box', 1); local _, world, run = newEngine('cm-store')
    local r, o = run({ items = { { item = 'water', amount = 3 }, { item = 'heavy_box', amount = 5 } }, total = 90, units = 8 })
    check('REAL no-capacity: ZERO lines delivered (all-or-nothing), full refund via AddMoneyToCharacterOnce, stock back',
        r.code == 'compensated' and r.refund == 90 and idb.count('1', 'water') == 0 and bank() == 9000 and world.store.stock == 100, r.code)
    check('REAL refund journaled once (<ref>:refund credit) next to the debit; grant reference fenced in the inventory ledger',
        money.journal[o.reference .. ':refund'] and money.journal[o.reference .. ':refund'].direction == 'credit' and opCount() == 2 and idb.ledger[1] and idb.ledger[1].status == 'cancelled')
    W.invoker = 'cm-store'
    local ok, why = W.registry.ExecuteItemGrant(o.reference, '1', { { item = 'water', amount = 3 } })
    check('REAL late grant after the refund is impossible (fenced)', ok == false and why == 'cancelled' and idb.count('1', 'water') == 0)
end

-- 3 EXCEPTION BEFORE DELIVERY ----------------------------------------------------------------------------------------------
do
    setup('cm-store')
    local _, world, run = newEngine('cm-store', function(owners)
        local real = owners.money.debit
        owners.money.debit = function(...) local a, b = real(...); boom() end   -- debit COMMITTED in cm-playerdata, then the flow throws
    end)
    local r, o = run()
    check('REAL exception after payment, before delivery: compensated, customer whole exactly once, stock back, nothing delivered',
        r.code == 'compensated' and bank() == 9000 and opCount() == 2 and world.store.stock == 100 and idb.count('1', 'water') == 0 and idb.ledger[1].status == 'cancelled', r.code)
end

-- 4 EXCEPTION AFTER DELIVERY ----------------------------------------------------------------------------------------------
do
    setup('cm-store')
    local _, world, run = newEngine('cm-store', function(owners)
        local real = owners.items.grant
        owners.items.grant = function(...) real(...); boom() end                -- grant COMMITTED in cm-inventory, then the flow throws
    end)
    local r, o = run()
    check('REAL exception after delivery commit reconciles to success: no refund, no stock release, no redelivery',
        r.code == 'completed' and r.delivered and bank() == 9000 - 70 and opCount() == 1 and world.store.stock == 95 and idb.count('1', 'water') == 3 and #idb.ledger == 1, r.code)
end

-- 5 RESPONSE LOSS (the owner committed, the answer was lost) ------------------------------------------------------------------
do
    setup('cm-store')
    local _, world, run = newEngine('cm-store', function(owners)
        local real = owners.money.debit
        owners.money.debit = function(...) real(...); return false, 'unavailable' end
    end)
    local r = run()
    check('REAL debit response lost: single debit, delivery proceeds, success', r.code == 'completed' and bank() == 9000 - 70 and opCount() == 1 and idb.count('1', 'water') == 3, r.code)

    setup('cm-store')
    local _, world2, run2 = newEngine('cm-store', function(owners)
        local real = owners.items.grant
        owners.items.grant = function(...) real(...); return false, 'unavailable' end
    end)
    local r2 = run2()
    check('REAL grant response lost (delivered): success, NO refund, no second delivery', r2.code == 'completed' and r2.refund == 0 and opCount() == 1 and idb.count('1', 'water') == 3 and #idb.ledger == 1, r2.code)

    setup('cm-store'); idb.give('1', 'pocket-1', 'heavy_box', 1)
    local lost = true
    local engine3, world3, run3 = newEngine('cm-store', function(owners)
        local real = owners.money.credit
        owners.money.credit = function(...) local ok, why = real(...); if lost then return false, 'unavailable' end return ok, why end
    end)
    local r3, o3 = run3({ items = { { item = 'heavy_box', amount = 5 } }, total = 90, units = 5 })
    check('REAL refund response lost: order pending, refund already committed once', r3.code == 'pending' and bank() == 9000 and opCount() == 2)
    lost = false
    local rec = engine3.recover(0)
    check('REAL refund retry replays the SAME journaled reference: no double refund, one terminal state, stock restored once', rec.compensated == 1 and bank() == 9000 and opCount() == 2 and world3.store.stock == 100)
end

-- 6 RESTART (fresh engine, journal row only) ------------------------------------------------------------------------------
do
    setup('cm-store')
    local engine1, world, run = newEngine('cm-store', function(owners, world)
        local real = owners.money.debit
        owners.money.debit = function(...) real(...); money.failRead = true; boom() end -- crash right after the debit; the owner ledger is unreachable
    end)
    local r, o = run()
    check('REAL crash after payment: pending (obligation survives, no guess while the money ledger is unreachable)', r.code == 'pending' and bank() == 9000 - 70 and world.rows[o.reference].state == 'pending')
    money.failRead = nil
    local owners = P.ownerDeps(ownerExports(), stateOf)
    W.invoker = 'cm-store'
    local fresh = P.new({ db = newJournal(world), money = owners.money, items = owners.items })   -- restarted resource: new instance, same journal row
    local rec = fresh.recover(0)
    check('REAL restart recovery: paid-but-undelivered -> compensated (refund once via the real money ops, grant fenced, stock restored), no player involved',
        rec.compensated == 1 and bank() == 9000 and opCount() == 2 and world.store.stock == 100 and idb.count('1', 'water') == 0 and idb.ledger[1] and idb.ledger[1].status == 'cancelled')
    check('REAL restart recovery is idempotent', fresh.recover(0).examined == 0 and bank() == 9000 and opCount() == 2)

    setup('cm-store')
    local engineB, worldB, runB = newEngine('cm-store', function(owners)
        local real = owners.items.grant
        owners.items.grant = function(...) real(...); money.failRead = true; boom() end   -- delivered, then crash with the money ledger unreachable
    end)
    local rB, oB = runB()
    check('REAL crash after delivery: pending, delivery stands (no refund guess)', rB.code == 'pending' and idb.count('1', 'water') == 3 and opCount() == 1)
    money.failRead = nil
    local freshB = P.new({ db = newJournal(worldB), money = owners.money, items = owners.items })
    local recB = freshB.recover(0)
    check('REAL restart reconciles delivered order to success: no refund, no stock release, owner share once',
        recB.completed == 1 and bank() == 9000 - 70 and opCount() == 1 and worldB.store.stock == 95 and worldB.store.balance == 56 and idb.count('1', 'water') == 3)
end

-- 7 CALLER GATES (real) --------------------------------------------------------------------------------------------------
do
    setup('cm-store')
    INVOKER = 'cm-store'
    local ok1 = pdRegistry.RemoveMoneyFromCharacter(1, 'bank', 5, 'STORE-PUR-1-gate:debit')
    local ok2, why2 = pdRegistry.RemoveMoneyFromCharacter(1, 'bank', 5, 'GAS-PUR-1-gate:debit')
    INVOKER = 'nv_cloth'
    local ok3 = pdRegistry.RemoveMoneyFromCharacter(1, 'cash', 5, 'CLOTH-PUR-1-gate:debit')
    local ok4, why4 = pdRegistry.RemoveMoneyFromCharacter(1, 'cash', 5, 'STORE-PUR-1-gate2:debit')
    INVOKER = 'cm-gasstations'
    local ok5, why5 = pdRegistry.RemoveMoneyFromCharacter(1, 'bank', 5, 'GAS-PUR-1-gate:debit')
    local ok6 = pdRegistry.RemoveMoneyFromCharacter(1, 'cash', 5, 'GAS-PUR-1-gate:debit')
    INVOKER = 'cm-evil'
    local ok7, why7 = pdRegistry.AddMoneyToCharacterOnce(1, 'cash', 5, 'STORE-PUR-1-evil:refund')
    local st7, sw7 = pdRegistry.GetCharacterMoneyOperation('STORE-PUR-1-gate:debit')
    INVOKER = 'cm-billing'
    local ok8 = pdRegistry.RemoveMoneyFromCharacter(1, 'bank', 5, 'INV-gate:debit')
    check('REAL gate: cm-store only STORE-PUR-* (cash/bank); nv_cloth only CLOTH-PUR-*; gasstations cash+GAS-PUR-* only; strangers refused; billing unaffected',
        ok1 == true and ok2 == false and why2 == 'forbidden' and ok3 == true and ok4 == false and why4 == 'forbidden' and ok5 == false and why5 == 'forbidden' and ok6 == true
        and ok7 == false and why7 == 'forbidden' and st7 == nil and sw7 == 'forbidden' and ok8 == true)
    INVOKER = 'cm-store'
    local ra, rb = pdRegistry.RemoveMoneyFromCharacter(1, 'bank', 6, 'STORE-PUR-1-gate:debit')
    check('REAL money op: same reference with another amount is an idempotency conflict', ra == false and rb == 'idempotency_conflict')
    local rc, rd = pdRegistry.RemoveMoneyFromCharacter(1, 'bank', 5, 'STORE-PUR-1-gate:debit')
    check('REAL money op: same reference + same payload replays (no second debit)', rc == true and rd == 'replayed')
    local re, rf = pdRegistry.RemoveMoneyFromCharacter(2, 'bank', 5000, 'STORE-PUR-1-poor:debit')
    check('REAL money op: insufficient funds is a DEFINITE refusal and journals nothing', re == false and rf == 'insufficient_funds' and not money.journal['STORE-PUR-1-poor:debit'])
end

-- 8 INVENTORY GRANT POLICY (real) ----------------------------------------------------------------------------------------
do
    setup('cm-store')
    local lines = { { item = 'clothing_pants', amount = 1, metadata = { drawableId = 5, textureId = 2, categoryType = 'pants', gender = 'male', label = 'Jeans' } } }
    W.invoker = 'cm-store'
    local a, b = W.registry.ExecuteItemGrant('POLICY-STORE-0001', '1', lines)
    check('REAL grant policy: cm-store may NOT grant clothing', a == false and b == 'invalid_item' and idb.count('1', 'clothing_pants') == 0)
    W.invoker = 'nv_cloth'
    local c, d = W.registry.ExecuteItemGrant('POLICY-CLOTH-0001', '1', lines)
    check('REAL grant policy: nv_cloth grants clothing with metadata in one ledgered transaction', c == true and idb.count('1', 'clothing_pants') >= 1 and #idb.ledger == 1, tostring(d))
    local e, f = W.registry.ExecuteItemGrant('POLICY-CLOTH-0002', '1', { { item = 'weapon_pistol', amount = 1 } })
    check('REAL grant policy: nv_cloth cannot grant weapons', e == false and f == 'invalid_item')
    W.invoker = 'cm-evil'
    local g, h = W.registry.ExecuteItemGrant('POLICY-EVIL-0001', '1', { { item = 'water', amount = 1 } })
    check('REAL grant policy: an unlisted resource is forbidden', g == false and h == 'forbidden')
    W.invoker = 'nv_cloth'
    local big = {}
    for i = 1, 20 do big[i] = { item = 'clothing_pants', amount = 1, metadata = { drawableId = i, textureId = 0, categoryType = 'pants', gender = 'male', label = ('Pants %d'):format(i), description = ('x'):rep(300) } } end
    idb.clear('1')
    local i1, i2 = W.registry.ExecuteItemGrant('POLICY-CLOTH-0003', '1', big)
    check('REAL grant policy: a 20-garment clothing cart (large metadata) fits the clothing limits or is refused cleanly (never half-applied)', (i1 == true and idb.count('1', 'clothing_pants') == 20) or (i1 == false and idb.count('1', 'clothing_pants') == 0), tostring(i2))
end

-- 9 CLOTHING PURCHASE END-TO-END (nv_cloth shape) ---------------------------------------------------------------------------
do
    setup('nv_cloth')
    local _, world, run = newEngine('nv_cloth')
    local lines = {
        { item = 'clothing_pants', amount = 1, metadata = { drawableId = 5, textureId = 2, categoryType = 'pants', gender = 'male', label = 'Jeans' } },
        { item = 'clothing_pants', amount = 1, metadata = { drawableId = 6, textureId = 0, categoryType = 'pants', gender = 'male', label = 'Chinos' } },
    }
    local r, o = run({ items = lines, total = 400, units = 2, account = 'cash' })
    check('REAL clothing purchase: debit (cash, CLOTH-PUR-) + one clothing grant + stock + owner share', r.code == 'completed' and money.chars[1].cash == 5000 - 400 and idb.count('1', 'clothing_pants') == 2 and world.store.stock == 98 and world.store.balance == 320 and money.journal[o.reference .. ':debit'].account == 'cash', r.code)
    setup('nv_cloth'); idb.give('1', 'pocket-1', 'heavy_box', 1)
    local _, world2, run2 = newEngine('nv_cloth')
    local r2 = run2({ items = { lines[1], { item = 'heavy_box', amount = 5 } }, total = 400, units = 2, account = 'cash' })
    check('REAL clothing purchase with one undeliverable line: zero garments delivered, refunded in full, stock restored (no partial)', r2.code == 'compensated' and money.chars[1].cash == 5000 and idb.count('1', 'clothing_pants') == 0 and world2.store.stock == 100, r2.code)
end

print(('\ncm-core purchase integration (real money ops + real inventory grant): %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
