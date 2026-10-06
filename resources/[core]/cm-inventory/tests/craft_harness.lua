-- Shared test doubles for the cm-inventory craft tests (used by craft_selftest.lua and cm-crafting/tests/integration_inventory.lua).
-- Loads the REAL cm-inventory files (db/items/slots/bags/equipment/external/craft) into one chunk against a FiveM + cm-items + SQL double.
-- See craft_selftest.lua for what is real and what is a double.
return function(here)
-- ------------------------------------------------------------------ tiny JSON (double for FiveM `json`)
local json = {}
local function jenc(v)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' or t == 'number' then return tostring(v) end
    if t == 'string' then return '"' .. v:gsub('[%c"\\]', function(c) return ('\\u%04x'):format(c:byte()) end) .. '"' end
    local keys, n = {}, 0
    for k in pairs(v) do keys[#keys + 1] = k; n = n + 1 end
    if n == #v and n > 0 then
        local o = {} for i = 1, n do o[i] = jenc(v[i]) end return '[' .. table.concat(o, ',') .. ']'
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local o = {} for _, k in ipairs(keys) do o[#o + 1] = jenc(tostring(k)) .. ':' .. jenc(v[k]) end
    return '{' .. table.concat(o, ',') .. '}'
end
json.encode = jenc
function json.decode(s)
    local i = 1
    local function ws() i = s:find('%S', i) or #s + 1 end
    local val
    local function str()
        local j, out = i + 1, {}
        while s:sub(j, j) ~= '"' do
            local c = s:sub(j, j)
            if c == '\\' then
                local n = s:sub(j + 1, j + 1)
                if n == 'u' then out[#out + 1] = string.char(tonumber(s:sub(j + 2, j + 5), 16)); j = j + 6
                else out[#out + 1] = n; j = j + 2 end
            else out[#out + 1] = c; j = j + 1 end
        end
        i = j + 1
        return table.concat(out)
    end
    function val()
        ws()
        local c = s:sub(i, i)
        if c == '{' then
            i = i + 1; local o = {}; ws()
            if s:sub(i, i) == '}' then i = i + 1 return o end
            while true do
                ws(); local k = str(); ws(); i = i + 1; o[k] = val(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == '}' then return o end
            end
        elseif c == '[' then
            i = i + 1; local o = {}; ws()
            if s:sub(i, i) == ']' then i = i + 1 return o end
            while true do
                o[#o + 1] = val(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == ']' then return o end
            end
        elseif c == '"' then return str()
        elseif s:sub(i, i + 3) == 'true' then i = i + 4 return true
        elseif s:sub(i, i + 4) == 'false' then i = i + 5 return false
        elseif s:sub(i, i + 3) == 'null' then i = i + 4 return nil
        else
            local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', i); i = i + #num; return tonumber(num)
        end
    end
    local ok, r = pcall(val)
    if not ok then error('bad json') end
    return r
end

local function deepcopy(t) if type(t) ~= 'table' then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end
local function ser(v)
    if type(v) == 'table' then
        local keys = {} for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local o = {} for _, k in ipairs(keys) do o[#o + 1] = tostring(k) .. '=' .. ser(v[k]) end
        return '{' .. table.concat(o, ',') .. '}'
    end
    return tostring(v)
end

-- ------------------------------------------------------------------ scheduler (cooperative threads, like FiveM)
local Sched = { tasks = {} }
function Sched.spawn(fn) local co = coroutine.create(fn); Sched.tasks[#Sched.tasks + 1] = co; return co end
function Sched.run()
    local guard = 0
    while true do
        local alive = false
        for _, co in ipairs(Sched.tasks) do
            if coroutine.status(co) ~= 'dead' then
                alive = true
                local ok, err = coroutine.resume(co)
                if not ok then error(err, 0) end
            end
        end
        guard = guard + 1
        if not alive then break end
        if guard > 100000 then error('scheduler runaway') end
    end
    Sched.tasks = {}
end
local function yieldMaybe() if coroutine.isyieldable() then coroutine.yield() end end

-- ------------------------------------------------------------------ SQL double
local function newDb()
    local db = {
        inventory_items = {}, characters = {}, ledger = {}, audit = {},
        nextId = 100, nextLedgerId = 1, interleave = false, failOn = nil, txnStack = {}, writes = 0, txnLocks = {}, rowLocks = {}, lockLog = {},
    }
    local function norm(sql) return (sql:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')) end
    local function current() return db.txnStack[coroutine.running()] end
    local function undoable(fn) local t = current(); if t then t[#t + 1] = fn end end
    local function insRow(tbl, row) tbl[#tbl + 1] = row; db.writes = db.writes + 1; undoable(function() for i, r in ipairs(tbl) do if r == row then table.remove(tbl, i) break end end end) end
    local function delRow(tbl, row)
        for i, r in ipairs(tbl) do if r == row then table.remove(tbl, i); db.writes = db.writes + 1; undoable(function() table.insert(tbl, i, row) end) return 1 end end
        return 0
    end
    local function setField(row, k, v) local old = row[k]; row[k] = v; db.writes = db.writes + 1; undoable(function() row[k] = old end) end
    local function copyRows(list) local o = {} for _, r in ipairs(list) do o[#o + 1] = deepcopy(r) end return o end
    local function sorted(list, key) table.sort(list, key); return list end

    local function exec(sql, p)
        sql = norm(sql)
        p = p or {}
        if db.failOn and db.failOn(sql) then return nil end
        if db.interleave then yieldMaybe() end
        if sql:find('^CREATE TABLE') then return {} end
        if sql:find('^SELECT id FROM characters WHERE id = %? LIMIT 1') then
            return db.characters[tostring(p[1])] and { { id = p[1] } } or {}
        end
        if sql:find('^SELECT %* FROM inventory_items WHERE owner_type = %? AND owner_id = %? ORDER BY id') then
            if sql:find('FOR UPDATE', 1, true) then
                local t = db.txnLocks[coroutine.running()]
                if t then
                    local key = 'inv:' .. tostring(p[2])
                    local guard = 0
                    while db.rowLocks[key] and db.rowLocks[key] ~= t do
                        guard = guard + 1
                        if guard > 4000 then db.deadlocks = (db.deadlocks or 0) + 1; error('Deadlock found when trying to get lock (inventory rows of ' .. key .. ')') end
                        yieldMaybe()
                    end
                    db.rowLocks[key] = t; t[#t + 1] = key
                    db.lockLog[#db.lockLog + 1] = tostring(p[2])
                end
            end
            local o = {} for _, r in ipairs(db.inventory_items) do if r.owner_type == p[1] and r.owner_id == tostring(p[2]) then o[#o + 1] = r end end
            return sorted(copyRows(o), function(a, b) return a.id < b.id end)
        end
        if sql:find('^SELECT %* FROM inventory_items WHERE owner_type = %? AND owner_id = %? ORDER BY slot ASC') then
            local o = {} for _, r in ipairs(db.inventory_items) do if r.owner_type == p[1] and r.owner_id == tostring(p[2]) then o[#o + 1] = r end end
            return sorted(copyRows(o), function(a, b) return a.slot < b.slot end)
        end
        if sql:find('^SELECT %* FROM inventory_items WHERE owner_type = %? AND owner_id = %? AND slot = %? LIMIT 1') then
            for _, r in ipairs(db.inventory_items) do if r.owner_type == p[1] and r.owner_id == tostring(p[2]) and r.slot == p[3] then return { deepcopy(r) } end end
            return {}
        end
        if sql:find('^SELECT %* FROM inventory_items WHERE owner_type = %? AND owner_id = %? AND item_name = %?') then
            local o = {} for _, r in ipairs(db.inventory_items) do if r.owner_type == p[1] and r.owner_id == tostring(p[2]) and r.item_name == p[3] then o[#o + 1] = r end end
            return sorted(copyRows(o), function(a, b) if a.quantity ~= b.quantity then return a.quantity > b.quantity end return a.id < b.id end)
        end
        if sql:find('^UPDATE inventory_items SET quantity = quantity %+ %?, metadata = %? WHERE id = %?') then
            for _, r in ipairs(db.inventory_items) do if r.id == p[3] then setField(r, 'quantity', r.quantity + p[1]); setField(r, 'metadata', p[2]) return 1 end end
            return 0
        end
        if sql:find('^UPDATE inventory_items SET quantity = quantity %- %? WHERE id = %?') then
            for _, r in ipairs(db.inventory_items) do if r.id == p[2] then setField(r, 'quantity', r.quantity - p[1]) return 1 end end
            return 0
        end
        if sql:find('^UPDATE inventory_items SET quantity = %? WHERE id = %? AND quantity = %?') then
            for _, r in ipairs(db.inventory_items) do if r.id == p[2] and r.quantity == p[3] then setField(r, 'quantity', p[1]) return 1 end end
            return 0
        end
        if sql:find('^UPDATE inventory_items SET metadata = %? WHERE id = %? AND metadata <=> %?') then
            for _, r in ipairs(db.inventory_items) do if r.id == p[2] and r.metadata == p[3] then setField(r, 'metadata', p[1]) return 1 end end
            return 0
        end
        if sql:find('^UPDATE inventory_items SET owner_id = %?, slot = %? WHERE id = %? AND owner_type = %? AND owner_id = %? AND quantity = %?') then
            for _, r in ipairs(db.inventory_items) do
                if r.id == p[3] and r.owner_type == p[4] and r.owner_id == tostring(p[5]) and r.quantity == p[6] then
                    for _, o in ipairs(db.inventory_items) do if o ~= r and o.owner_type == p[4] and o.owner_id == tostring(p[1]) and o.slot == p[2] then return nil end end   -- UNIQUE slot
                    setField(r, 'owner_id', tostring(p[1])); setField(r, 'slot', p[2]) return 1
                end
            end
            return 0
        end
        if sql:find('^UPDATE inventory_items SET slot = %? WHERE id = %? AND owner_type = %? AND owner_id = %? AND slot = %?') then
            for _, r in ipairs(db.inventory_items) do
                if r.id == p[2] and r.owner_type == p[3] and r.owner_id == tostring(p[4]) and r.slot == p[5] then
                    for _, o in ipairs(db.inventory_items) do if o ~= r and o.owner_type == p[3] and o.owner_id == tostring(p[4]) and o.slot == p[1] then return nil end end
                    setField(r, 'slot', p[1]) return 1
                end
            end
            return 0
        end
        if sql:find('^DELETE FROM inventory_items WHERE id = %? AND quantity = %?') then
            for _, r in ipairs(db.inventory_items) do if r.id == p[1] and r.quantity == p[2] then return delRow(db.inventory_items, r) end end
            return 0
        end
        if sql:find('^DELETE FROM inventory_items WHERE id = %?') then
            for _, r in ipairs(db.inventory_items) do if r.id == p[1] then return delRow(db.inventory_items, r) end end
            return 0
        end
        if sql:find('^INSERT INTO inventory_items') then
            for _, r in ipairs(db.inventory_items) do
                if r.owner_type == p[1] and r.owner_id == tostring(p[2]) and r.slot == p[3] then return nil end -- UNIQUE owner/slot
            end
            db.nextId = db.nextId + 1
            insRow(db.inventory_items, { id = db.nextId, owner_type = p[1], owner_id = tostring(p[2]), slot = p[3], item_name = p[4], quantity = p[5], metadata = p[6] })
            return db.nextId
        end
        if sql:find('^INSERT INTO inventory_audit') then
            if sql:find('character_id, action, item_name, quantity, from_slot, to_slot, reason%)') and #p == 7 then
                insRow(db.audit, { character_id = p[1], action = p[2], item_name = p[3], quantity = p[4], reason = p[7] })
            else
                insRow(db.audit, { character_id = p[1], action = p[2], item_name = p[3], quantity = p[4], reason = p[7] })
            end
            return 1
        end
        if sql:find('^SELECT reference, character_id, payload_hash, payload, status, result_json, tx_type FROM cm_inventory_transactions') then
            for _, r in ipairs(db.ledger) do if r.reference == p[1] then return { deepcopy(r) } end end
            return {}
        end
        if sql:find('^SELECT reference, character_id, payload, result_json FROM cm_inventory_transactions WHERE reference = %?') then
            for _, r in ipairs(db.ledger) do if r.reference == p[1] then return { deepcopy(r) } end end
            return {}
        end
        if sql:find('^INSERT INTO cm_inventory_transactions') then
            for _, r in ipairs(db.ledger) do if r.reference == p[1] then return nil end end -- UNIQUE reference
            local st = sql:find("'prepared'", 1, true) and 'prepared' or sql:find("'not_applied'", 1, true) and 'not_applied' or sql:find("'cancelled'", 1, true) and 'cancelled' or 'committed'
            insRow(db.ledger, { reference = p[1], tx_type = p[2], character_id = p[3], payload_hash = p[4], payload = p[5], status = st, result_json = p[6] })
            return 1
        end
        -- exchange ledger lifecycle (InnoDB semantics: FOR UPDATE and writes on the ledger row queue behind another open transaction's lock)
        local function ledgerLock(ref)
            local key = 'led:' .. tostring(ref)
            local mine = db.txnLocks[coroutine.running()]
            local guard = 0
            while db.rowLocks[key] and db.rowLocks[key] ~= mine do
                guard = guard + 1
                if guard > 4000 then error('Lock wait timeout exceeded (ledger ' .. key .. ')') end
                yieldMaybe()
            end
            if mine and db.rowLocks[key] ~= mine then db.rowLocks[key] = mine; mine[#mine + 1] = key end
        end
        if sql:find('^SELECT status, result_json, payload FROM cm_inventory_transactions WHERE reference = %? FOR UPDATE') then
            ledgerLock(p[1])
            for _, r in ipairs(db.ledger) do if r.reference == p[1] then return { { status = r.status, result_json = r.result_json, payload = r.payload } } end end
            return {}
        end
        if sql:find('^UPDATE cm_inventory_transactions SET') then
            ledgerLock(p[2])
            if db.afterLedgerLock then db.afterLedgerLock(sql, p) end
            for _, r in ipairs(db.ledger) do
                if r.reference == p[2] and r.status == 'prepared' and r.result_json == p[3] then
                    if sql:find("SET status = 'committed'", 1, true) then setField(r, 'status', 'committed'); setField(r, 'result_json', p[1])
                    elseif sql:find("SET status = 'not_applied'", 1, true) then setField(r, 'status', 'not_applied'); setField(r, 'result_json', p[1])
                    else setField(r, 'result_json', p[1]) end
                    return 1
                end
            end
            return 0
        end
        error('SQL double: unsupported statement: ' .. sql)
    end

    db.MySQL = { query = {}, single = {}, scalar = {}, update = {}, insert = {} }
    db.MySQL.query.await = function(sql, p) return exec(sql, p) end
    db.MySQL.single.await = function(sql, p) return exec(sql, p)[1] end
    db.MySQL.scalar.await = function(sql, p) local r = exec(sql, p)[1]; if not r then return nil end for _, v in pairs(r) do return v end end
    db.MySQL.update.await = function(sql, p) return exec(sql, p) end
    db.MySQL.insert.await = function(sql, p) return exec(sql, p) end
    db.MySQL.startTransaction = function(cb)
        local co = coroutine.running()
        local undo = {}
        db.txnStack[co] = undo
        local lockHolder = {}
        db.txnLocks[co] = lockHolder
        local function releaseLocks() for _, k in ipairs(lockHolder) do if db.rowLocks[k] == lockHolder then db.rowLocks[k] = nil end end db.txnLocks[co] = nil end
        -- like the real oxmysql transaction connection: writes return the raw ResultSetHeader table, selects return the rows
        local ok, res = pcall(cb, function(sql, p)
            local r = exec(sql, p)
            if type(r) == 'number' then
                if norm(sql):find('^INSERT') then return { affectedRows = 1, insertId = r } end
                return { affectedRows = r, insertId = 0 }
            end
            return r
        end)
        db.txnStack[co] = nil
        if not ok or res == false then
            for i = #undo, 1, -1 do undo[i]() end
            releaseLocks()
            return false
        end
        releaseLocks()
        return true
    end

    function db.addChar(id) db.characters[tostring(id)] = true end
    function db.give(cid, slot, item, qty, meta)
        db.nextId = db.nextId + 1
        db.inventory_items[#db.inventory_items + 1] = { id = db.nextId, owner_type = 'character', owner_id = tostring(cid), slot = slot, item_name = item, quantity = qty, metadata = meta and jenc(meta) or nil }
    end
    function db.clear(cid)
        for i = #db.inventory_items, 1, -1 do if db.inventory_items[i].owner_id == tostring(cid) then table.remove(db.inventory_items, i) end end
    end
    function db.count(cid, item, plainOnly)
        local n = 0
        for _, r in ipairs(db.inventory_items) do
            if r.owner_id == tostring(cid) and r.item_name == item then
                if not plainOnly or r.metadata == nil or r.metadata == '{}' or r.metadata == '[]' then n = n + r.quantity end
            end
        end
        return n
    end
    function db.rowsOf(cid) local o = {} for _, r in ipairs(db.inventory_items) do if r.owner_id == tostring(cid) then o[#o + 1] = r end end return o end
    function db.fingerprint() return ser({ db.inventory_items, db.ledger, #db.audit }) end
    return db
end

-- ------------------------------------------------------------------ FiveM + cm-items doubles, real file loading
local ITEMS = {
    iron_ore = { weight = 100 }, iron_ingot = { weight = 300 }, material = { weight = 100 }, plate = { weight = 400 },
    big_ore = { weight = 1000 }, heavy_box = { weight = 14000 }, junk1 = { weight = 10 }, junk2 = { weight = 10 }, junk3 = { weight = 10 },
    junk4 = { weight = 10 }, junk5 = { weight = 10 }, junk6 = { weight = 10 },
    hammer = { weight = 500, stack = false, durability = 100 }, tongs = { weight = 300, stack = false },
    one_only = { weight = 50, singleton = true },
    repair_kit = { weight = 3000 }, wash_kit = { weight = 1500 },
    schema_item = { weight = 10, requiresGrade = true },
    weapon_pistol = { weight = 1000, stack = false, unique = true },
    clothing_pants = { weight = 100 },
    ghost_item = { weight = 1, virtual = true },
}
-- REAL cm-items policy (config + categories + definitions + api), used by the double's CanTradeItem unless a test sets ITEMS[name].tradeable explicitly
local realItems
do
    local env = setmetatable({ CMItems = {}, json = json }, { __index = _G })
    local ok = pcall(function()
        for _, f in ipairs({ 'config.lua', 'shared/categories.lua', 'shared/items.lua', 'shared/virtual.lua', 'shared/api.lua' }) do
            local fh = assert(io.open(here .. '/../cm-items/' .. f, 'rb')); local src = fh:read('a'); fh:close()
            assert(load(src, '@cm-items/' .. f, 't', env))()
        end
    end)
    if ok then realItems = env.CMItems end
end
local function newWorld(db, opts)
    opts = opts or {}
    local W = { db = db, registry = {}, events = {}, invoker = 'cm-crafting', netEvents = {}, convars = { cm_environment = 'development', cm_qa_enabled = '1' } }
    local noop = function() end
    local exportsT = setmetatable({}, {
        __call = function(_, name, fn) W.registry[name] = fn end,
        __index = function(_, resource)
            if resource == 'cm-items' then
                return {
                    GetItem = function(a, b) local n = type(a) == 'table' and b or a; local d = ITEMS[n]; if not d or d.virtual then return nil end local c = {} for k, v in pairs(d) do c[k] = v end c.label = n return c end,
                    IsInventoryItem = function(a, b) local n = type(a) == 'table' and b or a; local d = ITEMS[n]; return d ~= nil and not d.virtual end,
                    CanTradeItem = function(a, b, c)
                        local n, m = a, b
                        if type(a) == 'table' then n, m = b, c end
                        if W.itemsDown then return nil end
                        local d = ITEMS[n]
                        if d and d.tradeable ~= nil then
                            if d.tradeable ~= true then return false, 'not_tradeable' end
                            if type(m) == 'table' and (m.bound == true or m.nonTransferable == true) then return false, 'bound_item' end
                            return true
                        end
                        if realItems and realItems.CanTradeItem then return realItems.CanTradeItem(n, m) end
                        return false, 'unknown_item'
                    end,
                    IsVirtualItem = function(a, b) local n = type(a) == 'table' and b or a; return ITEMS[n] ~= nil and ITEMS[n].virtual == true end,
                    ValidateMetadata = function(a, b, c)
                        local n, m = a, b
                        if type(a) == 'table' then n, m = b, c end
                        if W.itemsDown then return nil end
                        if ITEMS[n] and ITEMS[n].requiresGrade then if type(m) ~= 'table' or m.grade == nil then return false, 'Missing metadata field: grade' end end
                        return true
                    end,
                }
            elseif resource == 'cm-playerdata' then
                return { GetSourceByCharId = function(_, cid) if tostring(cid) == '1' then return 7 end return nil end }
            end
            return setmetatable({}, { __index = function() return noop end })
        end,
    })
    local env = setmetatable({
        exports = exportsT, json = json, MySQL = db.MySQL, CMInventory = nil,
        GetResourceState = function(r) if r == 'cm-items' or r == 'cm-playerdata' then return 'started' end return 'missing' end,
        GetInvokingResource = function() return W.invoker end,
        GetCurrentResourceName = function() return 'cm-inventory' end,
        GetConvar = function(k, d) return W.convars[k] or d end,
        CreateThread = function(fn) fn() end,
        Wait = function() yieldMaybe() end,
        Player = function() return { state = {} } end,
        GetPlayerIdentifiers = function() return {} end,
        TriggerClientEvent = function(name, src, payload) W.events[#W.events + 1] = { name = name, src = src, payload = payload } end,
        RegisterNetEvent = function(name) W.netEvents[#W.netEvents + 1] = tostring(name) end,
        AddEventHandler = noop, RegisterCommand = noop, TriggerEvent = noop,
        GetPlayerPed = function() return 0 end,
        os = os, math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, type = type, tostring = tostring, tonumber = tonumber,
        pcall = pcall, error = error, select = select, print = function() end, next = next, setmetatable = setmetatable, getmetatable = getmetatable,
        coroutine = coroutine, rawget = rawget, unpack = table.unpack, assert = assert, load = load,
    }, { __index = function(_, k) return nil end })
    env._G = env
    -- unknown FiveM globals used only at call time resolve to nil (and would error loudly if actually hit)
    local function load1(path, label)
        local f = assert(io.open(here .. '/' .. path, 'rb')); local s = f:read('a'); f:close()
        return s
    end
    local cfgSrc = load1('config.lua')
    assert(load(cfgSrc, '@config.lua', 't', env))()
    local parts = {}
    for _, fn in ipairs({ 'server/db.lua', 'server/items.lua', 'server/slots.lua', 'server/bags.lua', 'server/equipment.lua', 'server/external.lua', 'server/craft.lua', 'server/exchange.lua' }) do
        parts[#parts + 1] = '\n-- >>> ' .. fn .. '\n' .. load1(fn) .. '\n-- <<< ' .. fn .. '\n'
    end
    -- test-only probe appended to the SAME chunk so it can reach the real (wrapped) local internals
    parts[#parts + 1] = '\nTESTPROBE = { Add = function(...) return AddItemInternal(...) end, Remove = function(...) return RemoveItemInternal(...) end }\n'
    local chunk, err = load(table.concat(parts), '@cm-inventory/server/combined.lua', 't', env)
    assert(chunk, err)
    chunk()
    W.env = env
    return W
end


return { json = json, deepcopy = deepcopy, ser = ser, Sched = Sched, yieldMaybe = yieldMaybe, newDb = newDb, newWorld = newWorld, ITEMS = ITEMS }
end
