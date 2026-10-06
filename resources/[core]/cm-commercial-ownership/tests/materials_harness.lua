-- Test doubles for the business material platform (server/materials.lua). Used by materials_selftest.lua.
--
-- REAL: server/materials.lua (the production module, loaded unmodified), config.lua (Config.Materials), cm-materials catalog + its REAL server exports,
--       cm-items DEFINITIONS, and the REAL cm-inventory craft/sink code (via cm-inventory/tests/craft_harness.lua).
-- DOUBLES (labelled): the FiveM runtime; the business SQL layer (in-memory, understands exactly MAT.SQL, with transactional undo, UNIQUE keys,
--       SELECT ... FOR UPDATE row locks between cooperative threads, and failure injection); the foundation (Resolve/readBusiness/withBusinessLock);
--       the cm-contracts broker. It does NOT prove MySQL semantics: tests/materials_mysql_smoke.py does that for the same statements.
return function(coRoot)
    local invH = dofile(coRoot .. '/cm-inventory/tests/craft_harness.lua')(coRoot .. '/cm-inventory')
    local json, deepcopy, Sched, yieldMaybe = invH.json, invH.deepcopy, invH.Sched, invH.yieldMaybe
    local H = { inv = invH, Sched = Sched, json = json }

    -- ------------------------------------------------------------------ business SQL double
    function H.newBizDb(SQL)
        local names = {}
        for name, sql in pairs(SQL) do names[sql] = name end
        local db = { stock = {}, events = {}, demands = {}, deliveries = {}, nextId = 0, failOn = nil, interleave = false, locks = {}, txn = {}, writes = 0 }
        local function id() db.nextId = db.nextId + 1; return db.nextId end
        local function cur() return db.txn[coroutine.running()] end
        local function undo(fn) local t = cur(); if t then t.undo[#t.undo + 1] = fn end end
        local function setf(row, k, v) local old = row[k]; row[k] = v; db.writes = db.writes + 1; undo(function() row[k] = old end) end
        local function ins(list, row) list[#list + 1] = row; db.writes = db.writes + 1; undo(function() for i, r in ipairs(list) do if r == row then table.remove(list, i) break end end end) end
        local function copy(r) return r and deepcopy(r) or nil end
        local function lock(key)
            local t = cur(); if not t then return end
            local guard = 0
            while db.locks[key] and db.locks[key] ~= t do
                guard = guard + 1; if guard > 5000 then error('lock wait timeout (deadlock?)') end
                yieldMaybe()
            end
            db.locks[key] = t; t.held[#t.held + 1] = key
        end
        local function findDemand(ref) for _, d in ipairs(db.demands) do if d.reference == ref then return d end end end
        local function findDelivery(ref) for _, d in ipairs(db.deliveries) do if d.reference == ref then return d end end end
        local OPEN = { open = true, published = true, partially_fulfilled = true }
        local function stockRow(p) for _, r in ipairs(db.stock) do if r.business_type == p[1] and r.business_id == p[2] and r.material_id == p[3] then return r end end end

        local H2 = {}
        function H2.stockEnsure(p) if not stockRow(p) then ins(db.stock, { business_type = p[1], business_id = p[2], material_id = p[3], quantity = 0 }) end return { affectedRows = 1 } end
        function H2.stockLock(p) lock('stock:' .. p[1] .. ':' .. p[2] .. ':' .. p[3]); local r = stockRow(p); return r and { copy(r) } or {} end
        function H2.stockSet(p) local r = stockRow({ p[2], p[3], p[4] }); if r and r.quantity == p[5] then if p[1] < 0 then error('BIGINT UNSIGNED out of range') end setf(r, 'quantity', p[1]) return { affectedRows = 1 } end return { affectedRows = 0 } end
        function H2.stockRead(p) local r = stockRow(p); return r and { copy(r) } or {} end
        function H2.stockList(p) local o = {} for _, r in ipairs(db.stock) do if r.business_type == p[1] and r.business_id == p[2] and r.quantity > 0 then o[#o + 1] = copy(r) end end table.sort(o, function(a, b) return a.material_id < b.material_id end) return o end
        function H2.stockAllPositive(p) local o = H2.stockList(p); for _, r in ipairs(o) do lock('stock:' .. p[1] .. ':' .. p[2] .. ':' .. r.material_id) end return o end
        function H2.eventInsert(p)
            for _, e in ipairs(db.events) do if e.journal_key == p[10] then error('Duplicate entry for uq_material_journal') end end
            local row = { id = id(), reference = p[1], business_type = p[2], business_id = p[3], material_id = p[4], delta = p[5], resulting_quantity = p[6], event_type = p[7], source_resource = p[8], character_id = p[9], journal_key = p[10] }
            ins(db.events, row); return { affectedRows = 1, insertId = row.id }
        end
        function H2.eventByJournal(p) for _, e in ipairs(db.events) do if e.journal_key == p[1] then return { copy(e) } end end return {} end
        function H2.consumeEvents(p) local o = {} for _, e in ipairs(db.events) do if e.reference == p[1] and e.event_type == 'consume' then o[#o + 1] = copy(e) end end table.sort(o, function(a, b) return a.material_id < b.material_id end) return o end
        function H2.eventsForBusiness(p) local o = {} for i = #db.events, 1, -1 do local e = db.events[i]; if e.business_type == p[1] and e.business_id == p[2] then o[#o + 1] = copy(e) end end return o end
        function H2.demandInsert(p)
            for _, d in ipairs(db.demands) do
                if d.reference == p[1] then error('Duplicate entry for uq_material_demand_ref') end
                if p[2] ~= nil and d.idempotency_key == p[2] then error('Duplicate entry for uq_material_demand_idem') end
            end
            local row = { id = id(), reference = p[1], idempotency_key = p[2], business_type = p[3], business_id = p[4], material_id = p[5], quantity_required = p[6], quantity_fulfilled = 0, quantity_reserved = 0,
                status = 'open', category = p[7], deadline_epoch = p[8], publish_requested = p[9], contract_ref = nil, created_by = p[10], created_epoch = p[11] }
            ins(db.demands, row); return row.id
        end
        function H2.demandByRef(p) local d = findDemand(p[1]); return d and { copy(d) } or {} end
        function H2.demandLock(p) lock('demand:' .. tostring(p[1])); local d = findDemand(p[1]); return d and { copy(d) } or {} end
        function H2.demandByIdem(p) for _, d in ipairs(db.demands) do if d.idempotency_key == p[1] then return { copy(d) } end end return {} end
        function H2.demandOpenForBusiness(p) local o = {} for _, d in ipairs(db.demands) do if d.business_type == p[1] and d.business_id == p[2] and OPEN[d.status] then o[#o + 1] = copy(d) end end return o end
        local function byId(i) for _, d in ipairs(db.demands) do if d.id == i then return d end end end
        function H2.demandReserve(p) local d = byId(p[2]); if d and d.quantity_reserved == p[3] then setf(d, 'quantity_reserved', p[1]) return { affectedRows = 1 } end return { affectedRows = 0 } end
        function H2.demandProgress(p) local d = byId(p[4]); if d and d.quantity_fulfilled == p[5] and d.quantity_reserved == p[6] then setf(d, 'quantity_fulfilled', p[1]); setf(d, 'quantity_reserved', p[2]); setf(d, 'status', p[3]) return { affectedRows = 1 } end return { affectedRows = 0 } end
        function H2.demandFulfilled(p) local d = byId(p[4]); if d and d.quantity_fulfilled == p[5] and d.quantity_reserved == p[6] then setf(d, 'quantity_fulfilled', p[1]); setf(d, 'quantity_reserved', p[2]); setf(d, 'status', 'fulfilled'); setf(d, 'completed_epoch', p[3]) return { affectedRows = 1 } end return { affectedRows = 0 } end
        function H2.demandEnd(p) local d = byId(p[4]); if d and d.quantity_reserved == 0 and OPEN[d.status] then setf(d, 'status', p[1]); setf(d, 'end_reason', p[2]); setf(d, 'completed_epoch', p[3]) return { affectedRows = 1 } end return { affectedRows = 0 } end
        function H2.demandPublished(p) local d = byId(p[2]); if d and d.contract_ref == nil and d.status == 'open' then setf(d, 'contract_ref', p[1]); setf(d, 'status', 'published') return 1 end return 0 end
        function H2.demandsToPublish() local o = {} for _, d in ipairs(db.demands) do if d.publish_requested == 1 and d.contract_ref == nil and d.status == 'open' then o[#o + 1] = copy(d) end end return o end
        function H2.demandsExpired(p) local o = {} for _, d in ipairs(db.demands) do if OPEN[d.status] and d.deadline_epoch and d.deadline_epoch <= p[1] and d.quantity_reserved == 0 then o[#o + 1] = copy(d) end end return o end
        function H2.demandsOpenOfBusiness(p) return H2.demandOpenForBusiness(p) end
        function H2.demandsList(p) local o = {} for i = #db.demands, 1, -1 do local d = db.demands[i]; if d.business_type == p[1] and d.business_id == p[2] then o[#o + 1] = copy(d) end end return o end
        function H2.demandsAdminList() local o = {} for i = #db.demands, 1, -1 do o[#o + 1] = copy(db.demands[i]) end return o end
        function H2.deliveryInsert(p)
            for _, d in ipairs(db.deliveries) do
                if d.reference == p[1] then error('Duplicate entry for uq_material_delivery_ref') end
                if d.inventory_reference == p[10] then error('Duplicate entry for uq_material_delivery_inventory') end
            end
            local row = { id = id(), reference = p[1], demand_id = p[2], demand_reference = p[3], business_type = p[4], business_id = p[5], character_id = p[6], material_id = p[7], quantity = p[8],
                contract_ref = p[9], inventory_reference = p[10], payload = p[11], status = 'prepared', failure_reason = nil, created_epoch = p[12], updated_epoch = p[13] }
            ins(db.deliveries, row); return { affectedRows = 1, insertId = row.id }
        end
        function H2.deliveryByRef(p) local d = findDelivery(p[1]); return d and { copy(d) } or {} end
        function H2.deliveryLock(p) lock('delivery:' .. tostring(p[1])); local d = findDelivery(p[1]); return d and { copy(d) } or {} end
        function H2.deliveryCas(p) local d = findDelivery(p[4]); if d and d.status == p[5] then setf(d, 'status', p[1]); setf(d, 'updated_epoch', p[2]); setf(d, 'failure_reason', p[3]) return 1 end return 0 end
        function H2.deliveryComplete(p) local d = findDelivery(p[3]); if d and d.status == 'inventory_committed' then setf(d, 'status', 'completed'); setf(d, 'updated_epoch', p[1]); setf(d, 'completed_epoch', p[2]) return 1 end return 0 end
        function H2.deliveriesOpen(p) local o = {} for _, d in ipairs(db.deliveries) do if (d.status == 'prepared' or d.status == 'inventory_committed') and d.updated_epoch <= p[1] then o[#o + 1] = copy(d) end end return o end
        function H2.deliveryCompletedForDemand(p) for _, d in ipairs(db.deliveries) do if d.demand_id == p[1] and d.status == 'completed' and d.contract_ref == p[2] then return { copy(d) } end end return {} end
        function H2.deliveriesAdminList() local o = {} for i = #db.deliveries, 1, -1 do o[#o + 1] = copy(db.deliveries[i]) end return o end

        local READS = { stockRead = true, stockList = true, eventByJournal = true, consumeEvents = true, eventsForBusiness = true, demandByRef = true, demandByIdem = true, demandOpenForBusiness = true,
            demandsToPublish = true, demandsExpired = true, demandsOpenOfBusiness = true, demandsList = true, demandsAdminList = true, deliveryByRef = true, deliveriesOpen = true,
            deliveryCompletedForDemand = true, deliveriesAdminList = true, stockLock = true, demandLock = true, deliveryLock = true, stockAllPositive = true }

        local function run(sql, p, inTxn)
            local name = names[sql]
            if not name then error('business SQL double: unknown statement: ' .. tostring(sql)) end
            if db.failOn and db.failOn(name) then if inTxn then return nil end error('injected SQL failure on ' .. name) end
            if db.interleave then yieldMaybe() end
            return H2[name](p or {})
        end
        db.MySQL = { single = {}, query = {}, insert = {}, update = {}, scalar = {} }
        db.MySQL.single.await = function(sql, p) local r = run(sql, p); if type(r) == 'table' and r[1] ~= nil then return r[1] end if type(r) == 'table' and next(r) == nil then return nil end return type(r) == 'table' and r or nil end
        db.MySQL.query.await = function(sql, p) local r = run(sql, p); return type(r) == 'table' and r or {} end
        db.MySQL.insert.await = function(sql, p) local r = run(sql, p); return type(r) == 'table' and r.insertId or r end
        db.MySQL.update.await = function(sql, p) local r = run(sql, p); return type(r) == 'table' and r.affectedRows or r end
        db.MySQL.scalar.await = function() return nil end
        db.MySQL.startTransaction = function(cb)
            local co = coroutine.running()
            local t = { undo = {}, held = {} }
            db.txn[co] = t
            local function finish() for _, k in ipairs(t.held) do if db.locks[k] == t then db.locks[k] = nil end end db.txn[co] = nil end
            local ok, res = pcall(cb, function(sql, p) return run(sql, p, true) end)
            if not ok or res == false then
                for i = #t.undo, 1, -1 do t.undo[i]() end
                finish(); return false
            end
            finish(); return true
        end
        function db.fingerprint()
            local function ser(v) if type(v) == 'table' then local k = {} for key in pairs(v) do k[#k + 1] = key end table.sort(k, function(a, b) return tostring(a) < tostring(b) end) local o = {} for _, key in ipairs(k) do o[#o + 1] = tostring(key) .. '=' .. ser(v[key]) end return '{' .. table.concat(o, ',') .. '}' end return tostring(v) end
            return ser({ db.stock, db.events, db.demands, db.deliveries })
        end
        function db.qty(t, i, m) local r = stockRow({ t, i, m }); return r and r.quantity or 0 end
        function db.eventsOf(kind) local n = 0 for _, e in ipairs(db.events) do if e.event_type == kind then n = n + 1 end end return n end
        function db.demandBy(ref) return findDemand(ref) end
        function db.deliveryBy(ref) return findDelivery(ref) end
        return db
    end

    -- ------------------------------------------------------------------ load the REAL materials module + the REAL cm-materials exports
    function H.loadMaterialsModule(opts)
        local env = setmetatable({}, { __index = _G })
        local C = { schemaReady = true, logs = {}, now = opts.now }
        C.businesses = opts.businesses
        function C.Resolve(t, i) local b = C.businesses[t .. ':' .. i]; if not b then return nil, 'unknown_business' end return { type = t, id = i, ownerCharacterId = b.owner, epoch = 1 } end
        function C.readBusiness(t, i) local b = C.businesses[t .. ':' .. i]; if not b then return nil, 'unknown_business' end return { type = t, id = i, ownerCharacterId = b.owner } end
        function C.LogActivity(biz, action, actor, target, amount, meta) C.logs[#C.logs + 1] = { action = action, amount = amount } end
        local held = {}
        function C.withBusinessLock(key, fn, ...)
            local waited = 0
            while held[key] do waited = waited + 1; yieldMaybe(); if waited > 3000 then return false, 'busy' end end
            held[key] = true
            local res = table.pack(pcall(fn, ...))
            held[key] = nil
            if not res[1] then error(res[2], 0) end
            return table.unpack(res, 2, res.n)
        end
        env.CMB, env.Config, env.MySQL, env.json = C, opts.Config, opts.MySQL, json
        env.GetCurrentResourceName = function() return 'cm-commercial-ownership' end
        env.GetInvokingResource = function() return C.TestInvoker end
        env.GetResourceState = function() return 'started' end
        env.CreateThread = function() end   -- the reconciliation loop is driven explicitly by the tests
        env.Wait = function() yieldMaybe() end
        env.exports = setmetatable({}, { __call = function() end, __index = function() return setmetatable({}, { __index = function() return function() error('no export') end end }) end })
        local f = assert(io.open(opts.path, 'rb')); local src = f:read('a'); f:close()
        local chunk, err = load(src, '@materials.lua', 't', env); assert(chunk, err)
        chunk()
        return C, env
    end

    -- the REAL cm-materials server exports, loaded unmodified over the real cm-items definitions
    function H.loadMaterialsCatalog(coRoot)
        local reg = {}
        local env = setmetatable({}, { __index = _G })
        env.CMMaterials = nil
        env.CMItems = { Items = nil }
        local items = {}
        local itemsEnv = setmetatable({ CMItems = {} }, { __index = _G })
        assert(load(assert(io.open(coRoot .. '/cm-items/shared/items.lua', 'rb')):read('a'), '@items', 't', itemsEnv))()
        env.exports = setmetatable({}, { __call = function(_, name, fn) reg[name] = fn end,
            __index = function(_, res) return { GetItem = function(_, n) local d = itemsEnv.CMItems.Items[n]; if type(d) == 'table' then local c = deepcopy(d); c.name = n; return c end return nil end } end })
        env.GetResourceState = function() return 'started' end
        env.CreateThread = function(fn) fn() end
        env.Wait = function() end
        env.pcall = pcall; env.print = function() end
        env.RegisterCommand = function() end
        for _, fn in ipairs({ '/cm-materials/shared/catalog.lua', '/cm-materials/shared/graph.lua', '/cm-materials/server/main.lua' }) do
            local f = assert(io.open(coRoot .. fn, 'rb')); local src = f:read('a'); f:close()
            local chunk, err = load(src, '@' .. fn, 't', env); assert(chunk, err); chunk()
        end
        return reg, env
    end

    return H
end
