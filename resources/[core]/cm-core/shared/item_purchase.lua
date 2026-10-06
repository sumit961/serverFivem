-- cm-core / shared / item_purchase.lua
-- Exact-once settlement of one customer item purchase (cm-store, nv_cloth). SERVER-ONLY helper: consumers include it with
--     server_scripts { '@cm-core/shared/item_purchase.lua', ... }
-- and instantiate it with their own journal table, stock table and reference prefix. It owns no business rules (prices, carts, revenue
-- percentage stay with the caller); it only guarantees that an order terminates in exactly one economic result.
--
-- Same architecture as cm-gasstations/server/settlement.lua, specialised to "items only, all-or-nothing":
--   journal row (state pending -> completed | compensated) written BEFORE any side effect, identity = character id
--   stock reserve        : one guarded UPDATE joined to the journal row (stock + reserved_units commit together)
--   customer debit       : cm-playerdata RemoveMoneyFromCharacter, ref  <ref>:debit   (journaled, replay-safe, status-queryable)
--   item delivery        : cm-inventory ExecuteItemGrant, whole cart in ONE all-or-nothing grant, ref <ref>
--   delivery decision    : GetItemGrantStatus; CancelItemGrant fences the reference BEFORE any refund so a late grant can never land
--   refund               : cm-playerdata AddMoneyToCharacterOnce, ref  <ref>:refund    (full amount; there is no partial delivery)
--   terminal transition  : ONE UPDATE = journal state + undelivered-stock release (capped) + owner revenue (success only)
-- Unknown outcomes (timeout, exception, resource down) never count as "not delivered"; the row stays pending and is re-resolved
-- (live flow, exception path and the periodic recovery sweep all call the same idempotent resolve()).
CMItemPurchase = CMItemPurchase or {}

local PENDING, COMPLETED, COMPENSATED = 'pending', 'completed', 'compensated'

-- A debit refusal that provably committed nothing; anything else is UNKNOWN and is answered by the money-operation status.
local DEFINITE_DEBIT_FAILURE = {
    insufficient_funds = true, busy = true, invalid_character = true, invalid_request = true,
    invalid_reason = true, forbidden = true, not_found = true, persistence_failed = true,
}

local function intOf(value) return math.floor(tonumber(value) or 0) end

local function ident(name)
    assert(type(name) == 'string' and name:match('^[%a_][%w_]*$'), 'invalid SQL identifier: ' .. tostring(name))
    return name
end

-- cfg = { journal, stockTable, stockKey, ownerColumn, ownedOnly (bool: stock tracked only while owned), capacity (fn -> max units), refPrefix }
function CMItemPurchase.sqlFor(cfg)
    local j, st, key, owner = ident(cfg.journal), ident(cfg.stockTable), ident(cfg.stockKey), ident(cfg.ownerColumn)
    local ownedJoin = cfg.ownedOnly and (' AND s.' .. owner .. ' IS NOT NULL') or ''
    return {
        ddl = ([[CREATE TABLE IF NOT EXISTS %s (
            reference VARCHAR(64) NOT NULL,
            character_id BIGINT NOT NULL,
            scope_id VARCHAR(64) NOT NULL,
            state VARCHAR(16) NOT NULL DEFAULT 'pending',
            account VARCHAR(8) NOT NULL DEFAULT 'bank',
            total_cash INT NOT NULL DEFAULT 0,
            reserved_units INT NOT NULL DEFAULT 0,
            owner_pct INT NOT NULL DEFAULT 0,
            items_state VARCHAR(12) NOT NULL DEFAULT 'pending',
            refund_amount INT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            finished_at TIMESTAMP NULL DEFAULT NULL,
            PRIMARY KEY (reference),
            KEY idx_%s_state (state, created_at)
        )]]):format(j, j),
        insert = ([[INSERT INTO %s (reference, character_id, scope_id, state, account, total_cash, owner_pct, items_state)
            VALUES (?, ?, ?, 'pending', ?, ?, ?, 'pending')]]):format(j),
        get = ('SELECT * FROM %s WHERE reference = ? LIMIT 1'):format(j),
        -- reservation and journal are one statement: stock can never leave the store without the journal knowing how much to return
        reserve = ([[UPDATE %s s JOIN %s p ON p.reference = ?
            SET s.stock = s.stock - ?, p.reserved_units = ?
            WHERE s.%s = ?%s AND s.stock >= ? AND p.state = 'pending' AND p.reserved_units = 0]]):format(st, j, key,
            cfg.ownedOnly and (' AND s.' .. owner .. ' IS NOT NULL') or ''),
        -- the delivery decision is first-writer-wins and never changes once made
        setItems = ("UPDATE %s SET items_state = ? WHERE reference = ? AND state = 'pending' AND items_state = 'pending'"):format(j),
        -- THE terminal transition (see header). LEFT JOIN so a store row that vanished/changed owner still lets the order terminate.
        finalize = ([[UPDATE %s p
            LEFT JOIN %s s ON s.%s = p.scope_id%s
            SET p.state = ?, p.refund_amount = ?, p.finished_at = NOW(),
                s.stock = LEAST(?, s.stock + ?),
                s.business_balance = s.business_balance + IF(s.%s IS NOT NULL, ?, 0),
                s.daily_income = s.daily_income + IF(s.%s IS NOT NULL, ?, 0),
                s.weekly_income = s.weekly_income + IF(s.%s IS NOT NULL, ?, 0)
            WHERE p.reference = ? AND p.state = 'pending']]):format(j, st, key, ownedJoin, owner, owner, owner),
        stale = ("SELECT reference FROM %s WHERE state = 'pending' AND created_at < (NOW() - INTERVAL ? SECOND) ORDER BY created_at LIMIT 50"):format(j),
    }
end

function CMItemPurchase.mysqlDb(MySQL, cfg)
    local q = CMItemPurchase.sqlFor(cfg)
    local db = {}
    local function guard(fn)
        local ok, res = pcall(fn)
        if not ok then return nil end
        return res
    end
    local function affected(n)
        if n == nil then return nil end
        return (tonumber(n) or 0) >= 1
    end
    function db.insert(o)
        return affected(guard(function()
            return MySQL.update.await(q.insert, { o.reference, o.character_id, tostring(o.scope_id), o.account, o.total_cash, o.owner_pct })
        end))
    end
    function db.get(ref)
        local ok, row = pcall(function() return MySQL.single.await(q.get, { ref }) end)
        if not ok then return nil end
        return row or false
    end
    function db.reserve(ref, scopeId, units)
        return affected(guard(function() return MySQL.update.await(q.reserve, { ref, units, units, scopeId, units }) end))
    end
    function db.setItems(ref, to)
        return affected(guard(function() return MySQL.update.await(q.setItems, { to, ref }) end))
    end
    function db.finalize(ref, state, refund, release, share)
        return affected(guard(function()
            return MySQL.update.await(q.finalize, { state, refund, cfg.capacity(), release, share, share, share, ref })
        end))
    end
    function db.stale(seconds)
        local rows = guard(function() return MySQL.query.await(q.stale, { seconds }) end)
        local out = {}
        for _, r in ipairs(rows or {}) do out[#out + 1] = r.reference end
        return out
    end
    return db
end

-- deps = { db, money, items, log }
--   db     insert(o)->true|false|nil, get(ref)->row|false|nil, reserve(ref, scope, units)->true|false|nil, setItems(ref, to)->bool|nil,
--          finalize(ref, state, refund, release, share)->true(won)|false(lost)|nil(unknown), stale(seconds)->refs
--   money  debit(ref, cid, account, amount)->ok, reason ; credit(...)->ok, reason ; status(ref)->{status='committed',...}|false|nil
--   items  grant(ref, cid, lines)->ok, reason ; status(ref)->'committed'|'not_applied'|'cancelled'|'unknown' ; cancel(ref, cid)->ok, detail
function CMItemPurchase.new(deps)
    local db, money, items = deps.db, deps.money, deps.items
    local log = deps.log or function() end
    local S = { inFlight = {} }

    local function deferred(reason) return { code = 'pending', ok = false, pending = true, reason = reason } end

    local function terminalOf(p)
        local refund = intOf(p.refund_amount)
        return {
            code = p.state, ok = p.state == COMPLETED, refunded = refund > 0, refund = refund,
            paid = intOf(p.total_cash) - refund, delivered = p.items_state == 'delivered',
        }
    end

    local function debitRef(ref) return ref .. ':debit' end
    local function refundRef(ref) return ref .. ':refund' end

    -- Decide the delivery authoritatively. Returns 'delivered' | 'failed' | nil (cannot be decided yet).
    local function decideItems(ref, p)
        local st = items.status(ref)
        if st == 'committed' then return 'delivered' end
        if st == 'cancelled' then return 'failed' end
        if st ~= 'not_applied' then return nil end
        -- Not delivered YET: fence the reference so a late/in-flight grant can never land after we refund.
        local ok, detail = items.cancel(ref, tonumber(p.character_id))
        if ok then return 'failed' end
        if detail == 'already_committed' then return 'delivered' end
        return nil
    end

    local function persistItems(ref, to)
        local wrote = db.setItems(ref, to)
        if wrote == nil then return false end
        return db.get(ref) ~= nil
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

        if p.items_state == 'pending' then
            if not charged then
                -- Nothing was taken, so nothing may be delivered: fence the grant and close the leg.
                local ok, detail = items.cancel(ref, cid)
                if not ok then
                    if detail == 'already_committed' then log('CRITICAL: goods delivered without a committed payment', ref) end
                    return deferred('inventory_' .. tostring(detail))
                end
                if not persistItems(ref, 'failed') then return deferred('journal_unavailable') end
            else
                local decided = decideItems(ref, p)
                if not decided then return deferred('inventory_unavailable') end
                if not persistItems(ref, decided) then return deferred('journal_unavailable') end
            end
        end

        p = db.get(ref)
        if not p then return deferred('journal_unavailable') end
        if p.state ~= PENDING then return terminalOf(p) end

        local delivered = p.items_state == 'delivered'
        local refund = 0
        if charged and not delivered and total > 0 then
            refund = total -- all-or-nothing delivery: an undelivered order is refunded in full
            local ok, why = money.credit(refundRef(ref), cid, p.account, refund)
            if not ok then return deferred('refund_' .. tostring(why)) end
        end

        local release = delivered and 0 or math.max(0, intOf(p.reserved_units))
        local share = (delivered and total > 0) and math.floor(total * (intOf(p.owner_pct) / 100)) or 0
        local won = db.finalize(ref, delivered and COMPLETED or COMPENSATED, refund, release, share)
        if won == nil then return deferred('journal_unavailable') end
        local final = db.get(ref)
        if not final then return deferred('journal_unavailable') end
        return terminalOf(final)
    end

    -- order: reference, character_id, scope_id, account ('cash'|'bank'), total, units (stock to reserve, 0 = untracked), owner_pct,
    -- items = { { item, amount [, metadata] } ... } built by the CALLER from authoritative data. Returns the result; never throws.
    local function runInner(o)
        local ref = o.reference
        local total = intOf(o.total)
        local inserted = db.insert({
            reference = ref, character_id = o.character_id, scope_id = o.scope_id, account = o.account,
            total_cash = total, owner_pct = intOf(o.owner_pct),
        })
        if inserted ~= true then return { code = 'unavailable', ok = false } end

        if intOf(o.units) > 0 then
            local reserved = db.reserve(ref, o.scope_id, intOf(o.units))
            if reserved ~= true then
                S.resolve(ref) -- closes the empty journal row (a reservation that did commit is returned by the journal itself)
                return { code = reserved == false and 'no_stock' or 'unavailable', ok = false }
            end
        end

        if total > 0 then
            local ok, reason = money.debit(debitRef(ref), tonumber(o.character_id), o.account, total)
            if not ok then
                if DEFINITE_DEBIT_FAILURE[reason] then
                    S.resolve(ref)
                    return { code = 'payment_failed', ok = false, reason = reason }
                end
                local op = money.status(debitRef(ref))
                if op == nil then return deferred('money_unavailable') end
                if op == false or op.status ~= 'committed' then
                    S.resolve(ref)
                    return { code = 'payment_failed', ok = false, reason = reason }
                end
            end
        end

        local granted = items.grant(ref, tonumber(o.character_id), o.items)
        if granted then db.setItems(ref, 'delivered') end -- failures are decided by resolve() through the inventory ledger
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

    -- Restart / periodic recovery: resolve every stale pending order that this resource is not currently processing.
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

-- Real owners. Every call is pcall-wrapped: an exception is an UNKNOWN outcome, reported as nil/'unavailable', never "not applied".
function CMItemPurchase.ownerDeps(exportsTable, getResourceState)
    local function call(resource, fn, ...)
        if getResourceState(resource) ~= 'started' then return false end
        local args = table.pack(...)
        local ok, a, b = pcall(function() return exportsTable[resource][fn](exportsTable[resource], table.unpack(args, 1, args.n)) end)
        if not ok then return false end
        return true, a, b
    end
    local money, items = {}, {}
    function money.debit(ref, cid, account, amount)
        local called, ok, why = call('cm-playerdata', 'RemoveMoneyFromCharacter', cid, account, amount, ref, { source = 'item_purchase' })
        if not called then return false, 'unavailable' end
        if ok == true then return true, why end
        return false, why or 'unavailable'
    end
    function money.credit(ref, cid, account, amount)
        local called, ok, why = call('cm-playerdata', 'AddMoneyToCharacterOnce', cid, account, amount, ref, { source = 'item_purchase' })
        if not called then return false, 'unavailable' end
        if ok == true then return true, why end
        return false, why or 'unavailable'
    end
    function money.status(ref)
        local called, op = call('cm-playerdata', 'GetCharacterMoneyOperation', ref)
        if not called or op == nil then return nil end
        return op
    end
    function items.grant(ref, cid, lines)
        local called, ok = call('cm-inventory', 'ExecuteItemGrant', ref, cid, lines)
        return called and ok == true
    end
    function items.status(ref)
        local called, st = call('cm-inventory', 'GetItemGrantStatus', ref)
        if called and (st == 'committed' or st == 'not_applied' or st == 'cancelled') then return st end
        return 'unknown'
    end
    function items.cancel(ref, cid)
        local called, ok, detail = call('cm-inventory', 'CancelItemGrant', ref, cid)
        if not called then return false, 'unavailable' end
        return ok == true, detail
    end
    return { money = money, items = items }
end
