-- cm-gasstations / settlement.lua
-- Exact-once settlement of one customer order (fuel and/or vehicle items) across: stock reservation, cash debit, item grant,
-- fuel application, refund and stock release. Loaded before server/main.lua.
--
-- One journal row per order (cm_gas_purchases, keyed by a stable server-side reference GAS-PUR-...). The row is written BEFORE any
-- side effect and has exactly one terminal transition (pending -> completed | compensated), performed by a single atomic
-- statement that also releases the unconsumed stock and credits the station revenue. Every side effect is independently
-- idempotent under the same reference, so the live flow, an exception handler and the restart recovery can all call resolve()
-- any number of times, in any order, and converge on the same single result:
--
--   stock reserve  : atomic with the journal row (reserved_units), released only by the terminal statement (once)
--   customer debit : cm-playerdata journaled money op   GAS-PUR-x:debit   (replay-safe, status-queryable, character-id addressed)
--   customer refund: cm-playerdata journaled money op   GAS-PUR-x:refund  (same amount on every retry; legs are persisted first)
--   item delivery  : cm-inventory ExecuteItemGrant, all-or-nothing; "was it delivered?" is answered by the inventory ledger, and
--                    CancelItemGrant fences the reference so a refund can never race a late delivery
--   fuel delivery  : absolute ServiceVehicle fuel set; recorded as soon as it is confirmed
--
-- Never assumed: timeout / exception / unavailable resource == "not delivered". Unknown outcomes leave the journal row pending and
-- are re-resolved (restart recovery) until the owner can answer.
CMGas = CMGas or {}
local Settlement = {}
CMGas.Settlement = Settlement

Settlement.DDL = [[CREATE TABLE IF NOT EXISTS cm_gas_purchases (
    reference VARCHAR(64) NOT NULL,
    character_id BIGINT NOT NULL,
    station_id INT NOT NULL,
    state VARCHAR(16) NOT NULL DEFAULT 'pending',
    total_cash INT NOT NULL DEFAULT 0,
    fuel_cost INT NOT NULL DEFAULT 0,
    items_cost INT NOT NULL DEFAULT 0,
    fuel_units INT NOT NULL DEFAULT 0,
    reserved_units INT NOT NULL DEFAULT 0,
    plate VARCHAR(16) NULL,
    fuel_before INT NOT NULL DEFAULT 0,
    fuel_target INT NOT NULL DEFAULT 0,
    items_json TEXT NULL,
    owner_pct INT NOT NULL DEFAULT 0,
    fuel_state VARCHAR(12) NOT NULL DEFAULT 'none',
    items_state VARCHAR(12) NOT NULL DEFAULT 'none',
    refund_amount INT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (reference),
    KEY idx_cm_gas_purchases_state (state, created_at)
)]]

local PENDING, COMPLETED, COMPENSATED = 'pending', 'completed', 'compensated'

-- A debit refusal that provably committed nothing. Anything else (unavailable, conflict, exception) is UNKNOWN and is
-- answered by the money-operation status, never guessed.
local DEFINITE_DEBIT_FAILURE = {
    insufficient_funds = true, busy = true, invalid_character = true, invalid_request = true,
    invalid_reason = true, forbidden = true, not_found = true, persistence_failed = true,
}

local function intOf(value) return math.floor(tonumber(value) or 0) end

------------------------------------------------------------------------------------------------------------------ SQL
-- All journal SQL lives here (tests/purchase_mysql_smoke.py runs these exact statements against a scratch database).
Settlement.SQL = {
    insert = [[INSERT INTO cm_gas_purchases
        (reference, character_id, station_id, state, total_cash, fuel_cost, items_cost, fuel_units, plate, fuel_before, fuel_target, items_json, owner_pct, fuel_state, items_state)
        VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    get = 'SELECT * FROM cm_gas_purchases WHERE reference = ? LIMIT 1',
    -- reservation and journal are one statement: stock can never leave the station without the journal knowing how much to return
    reserve = [[UPDATE cm_gas_stations s JOIN cm_gas_purchases p ON p.reference = ?
        SET s.stock = s.stock - ?, p.reserved_units = ?
        WHERE s.station_id = ? AND s.owner_character_id IS NOT NULL AND s.stock >= ? AND p.state = 'pending' AND p.reserved_units = 0]],
    -- leg outcome: first writer wins; a decided leg never changes. 'applying' is the live flow's claim on the fuel leg: once claimed, a
    -- resolver may no longer call the leg failed on the grounds that it "has not happened yet" without consulting the vehicle itself.
    setLeg = {
        fuel = "UPDATE cm_gas_purchases SET fuel_state = ? WHERE reference = ? AND state = 'pending' AND fuel_state IN ('pending', 'applying')",
        items = "UPDATE cm_gas_purchases SET items_state = ? WHERE reference = ? AND state = 'pending' AND items_state = 'pending'",
    },
    -- the live flow may only touch the vehicle if it wins this claim; a resolver that already closed the leg makes it a no-op
    claimFuel = "UPDATE cm_gas_purchases SET fuel_state = 'applying' WHERE reference = ? AND state = 'pending' AND fuel_state = 'pending'",
    -- THE terminal transition. One statement: journal state, undelivered-stock release and owner revenue commit together or not at all,
    -- and only the first caller matches state = 'pending'. LEFT JOIN so an unowned (sink) station still terminates.
    finalize = [[UPDATE cm_gas_purchases p
        LEFT JOIN cm_gas_stations s ON s.station_id = p.station_id AND s.owner_character_id IS NOT NULL
        SET p.state = ?, p.refund_amount = ?, p.finished_at = NOW(),
            s.stock = LEAST(?, s.stock + ?),
            s.business_balance = s.business_balance + ?, s.daily_income = s.daily_income + ?, s.weekly_income = s.weekly_income + ?
        WHERE p.reference = ? AND p.state = 'pending']],
    stale = "SELECT reference FROM cm_gas_purchases WHERE state = 'pending' AND created_at < (NOW() - INTERVAL ? SECOND) ORDER BY created_at LIMIT 50",
}

-- SQL-backed journal. `MySQL` is oxmysql's global; `maxStock` a function returning the station capacity.
function Settlement.mysqlDb(MySQL, maxStock)
    local q = Settlement.SQL
    local db = {}
    local function guard(fn)
        local ok, res = pcall(fn)
        if not ok then return nil end
        return res
    end
    function db.insert(o)
        local n = guard(function()
            return MySQL.update.await(q.insert, {
                o.reference, o.character_id, o.station_id, o.total_cash, o.fuel_cost, o.items_cost, o.fuel_units, o.plate,
                o.fuel_before, o.fuel_target, o.items_json, o.owner_pct, o.fuel_state, o.items_state })
        end)
        if n == nil then return nil end
        return (tonumber(n) or 0) >= 1
    end
    function db.get(ref)
        local ok, row = pcall(function() return MySQL.single.await(q.get, { ref }) end)
        if not ok then return nil end
        return row or false
    end
    function db.reserve(ref, stationId, units)
        local n = guard(function() return MySQL.update.await(q.reserve, { ref, units, units, stationId, units }) end)
        if n == nil then return nil end
        return (tonumber(n) or 0) >= 1
    end
    function db.setLeg(ref, leg, to)
        local n = guard(function() return MySQL.update.await(q.setLeg[leg], { to, ref }) end)
        if n == nil then return nil end
        return (tonumber(n) or 0) >= 1
    end
    function db.claimFuel(ref)
        local n = guard(function() return MySQL.update.await(q.claimFuel, { ref }) end)
        if n == nil then return nil end
        return (tonumber(n) or 0) >= 1
    end
    function db.finalize(ref, state, refund, release, share)
        local n = guard(function()
            return MySQL.update.await(q.finalize, { state, refund, maxStock(), release, share, share, share, ref })
        end)
        if n == nil then return nil end
        return (tonumber(n) or 0) >= 1
    end
    function db.stale(seconds)
        local rows = guard(function() return MySQL.query.await(q.stale, { seconds }) end)
        local out = {}
        for _, r in ipairs(rows or {}) do out[#out + 1] = r.reference end
        return out
    end
    return db
end

------------------------------------------------------------------------------------------------------------------ state machine
-- deps = { db, money, items, fuel, log }
--   db     insert(o)->true|false|nil, get(ref)->row|false|nil, reserve(ref, stationId, units)->true|false|nil,
--          setLeg(ref, leg, to)->bool|nil, claimFuel(ref)->bool|nil, finalize(ref, state, refund, release, share)->true(won)|false(lost)|nil(unknown), stale(seconds)->refs
--   money  debit(ref, cid, amount)->ok, reason ; credit(ref, cid, amount)->ok, reason ; status(ref)->{ status='committed', ... } | false | nil
--   items  grant(ref, cid, lines)->ok, reason ; status(ref)->'committed'|'not_applied'|'cancelled'|'unknown' ; cancel(ref, cid)->ok, detail
--   fuel   apply(plate, target)->bool ; read(plate)->number|nil
function Settlement.new(deps)
    local db, money, items, fuel = deps.db, deps.money, deps.items, deps.fuel
    local log = deps.log or function() end
    local S = { inFlight = {} }

    local function deferred(reason) return { code = 'pending', ok = false, pending = true, reason = reason } end

    local function terminalOf(p)
        local refund = intOf(p.refund_amount)
        return {
            code = p.state, ok = p.state == COMPLETED, refunded = refund > 0, refund = refund,
            paid = intOf(p.total_cash) - refund,
            fuelDelivered = p.fuel_state == 'delivered', itemsDelivered = p.items_state == 'delivered',
            fuelUnits = p.fuel_state == 'delivered' and intOf(p.fuel_units) or 0,
        }
    end

    local function debitRef(ref) return ref .. ':debit' end
    local function refundRef(ref) return ref .. ':refund' end

    local function decodeItems(p)
        local lines = {}
        if type(p.items_json) == 'string' and p.items_json ~= '' then
            for item, amount in p.items_json:gmatch('([%w_]+)=(%d+)') do lines[#lines + 1] = { item = item, amount = tonumber(amount) } end
            table.sort(lines, function(a, b) return a.item < b.item end)
        end
        return lines
    end
    S.decodeItems = decodeItems

    function S.encodeItems(lines)
        local parts = {}
        local sorted = {}
        for _, l in ipairs(lines or {}) do sorted[#sorted + 1] = l end
        table.sort(sorted, function(a, b) return a.item < b.item end)
        for _, l in ipairs(sorted) do parts[#parts + 1] = ('%s=%d'):format(l.item, l.amount) end
        return table.concat(parts, ',')
    end

    -- Decide the items leg authoritatively. Returns 'delivered' | 'failed' | nil (cannot be decided yet).
    local function decideItems(ref, p)
        local st = items.status(ref)
        if st == 'committed' then return 'delivered' end
        if st == 'cancelled' then return 'failed' end
        if st ~= 'not_applied' then return nil end
        -- Not delivered YET. Fence the reference so a late/in-flight grant can never land after we refund.
        local ok, detail = items.cancel(ref, tonumber(p.character_id))
        if ok then return 'failed' end
        if detail == 'already_committed' then return 'delivered' end
        return nil
    end

    -- Fuel is an absolute set on a persistent vehicle. After a crash window the only authoritative evidence is the vehicle's own
    -- PERSISTED fuel (fuel_before is recorded from that same column): it moved up from the recorded value, or now equals the target.
    -- If the persisted value was already the target there is no observable evidence either way: refund (never charged-and-empty).
    local function decideFuel(p)
        if not p.plate or p.plate == '' then return 'failed' end
        local current = fuel.read(p.plate)
        if current == nil then return nil end
        local before, target = intOf(p.fuel_before), intOf(p.fuel_target)
        if math.abs(before - target) < 1 then return 'failed' end
        if current >= before + 1 or math.abs(current - target) < 1 then return 'delivered' end
        return 'failed'
    end

    local function persistLeg(ref, leg, to)
        local wrote = db.setLeg(ref, leg, to)
        if wrote == nil then return nil end
        local p = db.get(ref)
        if not p then return nil end
        return p[leg .. '_state'], p
    end

    -- Idempotent convergence to the single terminal result. Safe to call concurrently, repeatedly and after a restart.
    function S.resolve(ref)
        local p = db.get(ref)
        if p == nil then return deferred('unavailable') end
        if p == false then return { code = 'missing', ok = false } end
        if p.state ~= PENDING then return terminalOf(p) end

        local cid = tonumber(p.character_id)
        local total = intOf(p.total_cash)

        local charged = true
        if total > 0 then
            local op = money.status(debitRef(ref))
            if op == nil then return deferred('money_unavailable') end
            charged = op ~= false and op.status == 'committed'
        end

        if not charged then
            -- Nothing was taken, so nothing may be delivered: fence the grant, close the legs, release the stock.
            if p.items_state == 'pending' then
                local ok, detail = items.cancel(ref, cid)
                if not ok then
                    if detail == 'already_committed' then log('CRITICAL: goods delivered without a committed payment', ref) end
                    return deferred('inventory_' .. tostring(detail))
                end
                if persistLeg(ref, 'items', 'failed') == nil then return deferred('journal_unavailable') end
            end
            if (p.fuel_state == 'pending' or p.fuel_state == 'applying') and persistLeg(ref, 'fuel', 'failed') == nil then return deferred('journal_unavailable') end
        else
            if p.items_state == 'pending' then
                local decided = decideItems(ref, p)
                if not decided then return deferred('inventory_unavailable') end
                if persistLeg(ref, 'items', decided) == nil then return deferred('journal_unavailable') end
            end
            p = db.get(ref)
            if not p then return deferred('journal_unavailable') end
            if p.fuel_state == 'pending' or p.fuel_state == 'applying' then
                local decided = decideFuel(p)
                if not decided then return deferred('vehicle_unavailable') end
                if persistLeg(ref, 'fuel', decided) == nil then return deferred('journal_unavailable') end
            end
        end

        p = db.get(ref)
        if not p then return deferred('journal_unavailable') end
        if p.state ~= PENDING then return terminalOf(p) end

        -- Both legs are now persisted, so the refund below is identical on every retry.
        local refund = 0
        if charged then
            if p.items_state == 'failed' then refund = refund + intOf(p.items_cost) end
            if p.fuel_state == 'failed' then refund = refund + intOf(p.fuel_cost) end
            if refund > 0 then
                local ok, why = money.credit(refundRef(ref), cid, refund)
                if not ok then return deferred('refund_' .. tostring(why)) end
            end
        end

        local fuelDelivered = p.fuel_state == 'delivered'
        local delivered = fuelDelivered or p.items_state == 'delivered'
        local state = delivered and COMPLETED or COMPENSATED
        local release = math.max(0, intOf(p.reserved_units) - (fuelDelivered and intOf(p.fuel_units) or 0))
        local paid = math.max(0, total - refund)
        local share = (charged and paid > 0) and math.floor(paid * (intOf(p.owner_pct) / 100)) or 0

        local won = db.finalize(ref, state, refund, release, share)
        if won == nil then return deferred('journal_unavailable') end
        local final = db.get(ref)
        if not final then return deferred('journal_unavailable') end
        return terminalOf(final)
    end

    -- Run one order. `order`: reference, character_id, station_id, reserve_units, fuel_units, fuel_cost, items_cost, items {{item,amount}},
    -- plate, fuel_before, fuel_target, owner_pct. Returns the terminal/pending result; never throws.
    local function runInner(o)
        local ref = o.reference
        local total = intOf(o.fuel_cost) + intOf(o.items_cost)
        local inserted = db.insert({
            reference = ref, character_id = o.character_id, station_id = o.station_id, total_cash = total,
            fuel_cost = intOf(o.fuel_cost), items_cost = intOf(o.items_cost), fuel_units = intOf(o.fuel_units),
            plate = o.plate, fuel_before = intOf(o.fuel_before), fuel_target = intOf(o.fuel_target),
            items_json = S.encodeItems(o.items), owner_pct = intOf(o.owner_pct),
            fuel_state = intOf(o.fuel_units) > 0 and 'pending' or 'none',
            items_state = (o.items and #o.items > 0) and 'pending' or 'none',
        })
        if inserted ~= true then return { code = 'unavailable', ok = false } end

        if intOf(o.reserve_units) > 0 then
            local reserved = db.reserve(ref, o.station_id, intOf(o.reserve_units))
            if reserved ~= true then
                S.resolve(ref) -- closes the empty journal row (a reservation that did commit is returned by the journal itself)
                return { code = reserved == false and 'no_stock' or 'unavailable', ok = false }
            end
        end

        if total > 0 then
            local ok, reason = money.debit(debitRef(ref), tonumber(o.character_id), total)
            if not ok then
                if DEFINITE_DEBIT_FAILURE[reason] then
                    S.resolve(ref)
                    return { code = 'payment_failed', ok = false, reason = reason }
                end
                -- Unknown: the money owner's own ledger is the only authority.
                local op = money.status(debitRef(ref))
                if op == nil then return deferred('money_unavailable') end
                if op == false or op.status ~= 'committed' then
                    S.resolve(ref)
                    return { code = 'payment_failed', ok = false, reason = reason }
                end
            end
        end

        if o.items and #o.items > 0 then
            local ok = items.grant(ref, tonumber(o.character_id), o.items)
            if ok then db.setLeg(ref, 'items', 'delivered') end -- failures are decided by resolve() through the inventory ledger
        end

        if intOf(o.fuel_units) > 0 and o.plate and db.claimFuel(ref) == true then
            -- claimed: no resolver can have refunded this leg. A false/unknown answer is decided by resolve() from the vehicle's own fuel.
            if fuel.apply(o.plate, intOf(o.fuel_target)) then db.setLeg(ref, 'fuel', 'delivered') end
        end

        return S.resolve(ref)
    end

    function S.run(order)
        local ref = order.reference
        S.inFlight[ref] = true
        local ok, result = xpcall(runInner, debug.traceback, order)
        if not ok then
            log('order error', ref, tostring(result))
            local okResolve, resolved = pcall(S.resolve, ref)
            result = okResolve and resolved or deferred('exception')
        end
        S.inFlight[ref] = nil
        return result
    end

    -- Restart / periodic recovery: resolve every stale pending order that is not currently being processed in this resource.
    function S.recover(staleSeconds)
        local refs = db.stale(staleSeconds or 60)
        local report = { examined = 0, completed = 0, compensated = 0, pending = 0 }
        for _, ref in ipairs(refs) do
            if not S.inFlight[ref] then
                report.examined = report.examined + 1
                S.inFlight[ref] = true
                local ok, result = pcall(S.resolve, ref)
                S.inFlight[ref] = nil
                if ok and result.code == COMPLETED then report.completed = report.completed + 1
                elseif ok and result.code == COMPENSATED then report.compensated = report.compensated + 1
                else report.pending = report.pending + 1 end
            end
        end
        return report
    end

    return S
end

------------------------------------------------------------------------------------------------------------------ owner adapters
-- Real owners (cm-playerdata journaled money ops, cm-inventory grant ledger, cm-vehicles). Every call is pcall-wrapped: an exception
-- is an UNKNOWN outcome, reported as nil/'unavailable', never as "not applied".
function Settlement.ownerDeps(exportsTable, getResourceState)
    local function call(resource, fn, ...)
        if getResourceState(resource) ~= 'started' then return false, nil, 'unavailable' end
        local args = table.pack(...)
        local ok, a, b = pcall(function() return exportsTable[resource][fn](exportsTable[resource], table.unpack(args, 1, args.n)) end)
        if not ok then return false, nil, 'unavailable' end
        return true, a, b
    end

    local money, items, fuel = {}, {}, {}
    function money.debit(ref, cid, amount)
        local called, ok, why = call('cm-playerdata', 'RemoveMoneyFromCharacter', cid, 'cash', amount, ref, { source = 'cm-gasstations' })
        if not called then return false, 'unavailable' end
        if ok == true then return true, why end
        return false, why or 'unavailable'
    end
    function money.credit(ref, cid, amount)
        local called, ok, why = call('cm-playerdata', 'AddMoneyToCharacterOnce', cid, 'cash', amount, ref, { source = 'cm-gasstations' })
        if not called then return false, 'unavailable' end
        if ok == true then return true, why end
        return false, why or 'unavailable'
    end
    function money.status(ref)
        local called, op, why = call('cm-playerdata', 'GetCharacterMoneyOperation', ref)
        if not called then return nil, 'unavailable' end
        if op == nil then return nil, why or 'unavailable' end
        return op
    end

    function items.grant(ref, cid, lines)
        local called, ok, detail = call('cm-inventory', 'ExecuteItemGrant', ref, cid, lines)
        if not called then return false, 'unavailable' end
        return ok == true, detail
    end
    function items.status(ref)
        local called, st = call('cm-inventory', 'GetItemGrantStatus', ref)
        if not called then return 'unknown' end
        if st == 'committed' or st == 'not_applied' or st == 'cancelled' then return st end
        return 'unknown'
    end
    function items.cancel(ref, cid)
        local called, ok, detail = call('cm-inventory', 'CancelItemGrant', ref, cid)
        if not called then return false, 'unavailable' end
        return ok == true, detail
    end

    function fuel.apply(plate, target)
        local called, result = call('cm-vehicles', 'ServiceVehicle', plate, { fuel = target })
        return called and result ~= false and result ~= nil
    end
    function fuel.read(plate)
        local called, row = call('cm-vehicles', 'GetVehicleByPlate', plate)
        if not called or type(row) ~= 'table' then return nil end
        return tonumber(row.fuel)
    end
    return { money = money, items = items, fuel = fuel }
end
