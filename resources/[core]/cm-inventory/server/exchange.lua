-- cm-inventory/exchange.lua
-- Atomic TWO-CHARACTER item exchange for cm-trade (A's offered items <-> B's offered items), on the same engine as craft.lua:
-- per-character locks, SELECT ... FOR UPDATE row locks, guarded writes, and the UNIQUE-reference ledger `cm_inventory_transactions` (tx_type trade_exchange).
-- Loaded after craft.lua (needs CMInventory.Tx). Everything is inside a do-block (no permanent top-level locals).
--
-- Contract (matches cm-trade/docs/SHARED_INTEGRATION.md; server-only; caller allowlist Cfg.exchangeTrusted = cm-trade):
--   GetTradeSnapshot(characterId)                  -> { { ref, item, label, image, quantity, tradeable, summary, fp } ... }   (carry slots only)
--   ValidateItemExchange(tradeRef, a, b)           -> true | false, reason                                   (read-only dry run)
--   ExecuteItemExchange(tradeRef, a, b)            -> true, { replayed } | false, reason (definite, terminal) | false, 'pending' | 'unavailable' (outcome not known: ask the status)
--   GetItemExchangeStatus(tradeRef)                -> 'committed' | 'pending' | 'not_applied' | 'not_submitted' | 'unknown'   (not_applied is TERMINAL)
--   FenceItemExchange(tradeRef)                    -> 'committed' | 'not_applied' | 'pending' | false, reason   (makes not_applied permanent when provable)
--   a / b = { characterId, lines = { { ref = '<inventory row id>', quantity = n, fp = '<row fingerprint from the snapshot>' } } }
--
-- Semantics
--   * The offered ROW (by id) must belong to that character, sit in a carry slot (never an equipment slot), hold enough quantity, be tradeable per the
--     authoritative cm-items policy (CanTradeItem) and still match its snapshot fingerprint (item + exact metadata): otherwise item_changed, nothing moves.
--   * A whole row moves by UPDATE (same row id, metadata, serial, durability, custom data: identity is preserved, never destroyed and recreated).
--     A partial quantity (stackable items only) splits: the source row keeps the rest and the receiver gets a merge into a compatible stack (the normal
--     rowCanStackWithMetadata rule) or a new row with the exact same metadata. Non-stackable rows move whole or not at all.
--   * CAPACITY is final-state: each side = current - own offer + counterpart offer (slots, unlocked backpack, singleton rule, weight), planned in memory
--     on the locked rows before anything is written.
--   * LOCK ORDER: both characters are always locked lowest id first (in-process lock and row locks), so A<->B and B<->A can never deadlock.
--   * One transaction: lock rows, ledger check, plan, removals, move-out (to unique temporary slots), inserts, final slots, audit, ledger row, commit.
do
    local Tx = CMInventory.Tx
    local EX_TYPE = 'trade_exchange'
    local Cfg = Tx.Cfg

    local function rowFingerprint(row)
        return Tx.fnv1a(tostring(row.item_name):lower() .. '|' .. stableEncode(decode(row.metadata)))
    end

    local function canTrade(itemName, meta)
        local ok = safeItemCall('CanTradeItem', itemName, meta)
        if ok == nil then return nil end   -- cm-items unavailable: fail closed as unavailable
        return ok == true
    end

    local function summaryOf(row, def)
        local meta = decode(row.metadata)
        local d = tonumber(meta.durability)
        if d then return ('Durability %d%%'):format(math.floor(d)) end
        if meta.serial then return ('Serial %s'):format(tostring(meta.serial):sub(1, 20)) end
        return nil
    end

    -- ------------------------------------------------------------------ normalization (no database)
    local function normalizeSide(side)
        if type(side) ~= 'table' then return nil end
        for k in pairs(side) do if k ~= 'characterId' and k ~= 'lines' then return nil end end
        local cid = Tx.validCharacterId(side.characterId)
        if not cid then return nil end
        local lines = side.lines
        if lines == nil then lines = {} end
        if type(lines) ~= 'table' or #lines > Cfg.exchangeMaxLines then return nil end
        local n = 0
        for k in pairs(lines) do if type(k) ~= 'number' then return nil end n = n + 1 end
        if n ~= #lines then return nil end
        local out, seen = {}, {}
        for _, l in ipairs(lines) do
            if type(l) ~= 'table' then return nil end
            for k in pairs(l) do if k ~= 'ref' and k ~= 'quantity' and k ~= 'fp' then return nil end end
            local ref = l.ref
            if type(ref) == 'number' then ref = tostring(math.floor(ref)) end
            if type(ref) ~= 'string' or #ref < 1 or #ref > 20 or not ref:match('^%d+$') or seen[ref] then return nil end
            if not Tx.isInt(l.quantity, 1, Cfg.exchangeMaxQuantity) then return nil end
            if l.fp ~= nil and (type(l.fp) ~= 'string' or #l.fp ~= 16 or not l.fp:match('^%x+$')) then return nil end
            seen[ref] = true
            out[#out + 1] = { ref = ref, quantity = l.quantity, fp = l.fp }
        end
        table.sort(out, function(x, y) return tonumber(x.ref) < tonumber(y.ref) end)
        return { cid = cid, lines = out }
    end

    -- Returns lo, hi (sorted by numeric character id) or nil, reason.
    local function normalizeExchange(a, b)
        local sa, sb = normalizeSide(a), normalizeSide(b)
        if not sa or not sb or sa.cid == sb.cid then return nil, 'invalid_transaction' end
        if #sa.lines == 0 and #sb.lines == 0 then return nil, 'invalid_transaction' end
        if tonumber(sa.cid) > tonumber(sb.cid) then sa, sb = sb, sa end
        return sa, sb
    end

    local function payloadOf(lo, hi)
        local function side(s) local l = {} for _, x in ipairs(s.lines) do l[#l + 1] = { ref = x.ref, quantity = x.quantity, fp = x.fp } end return { character = s.cid, lines = l } end
        return stableEncode({ type = EX_TYPE, lo = side(lo), hi = side(hi) })
    end

    -- ------------------------------------------------------------------ planning (pure over locked rows)
    local function prep(cid, rawRows)
        local rows, byId = {}, {}
        for _, r in ipairs(rawRows) do
            local row = { id = tonumber(r.id), slot = tostring(r.slot), item_name = tostring(r.item_name):lower(), qty = tonumber(r.quantity) or 0, orig = tonumber(r.quantity) or 0,
                metadata = r.metadata, meta = decode(r.metadata) }
            rows[#rows + 1] = row; byId[row.id] = row
        end
        return { cid = cid, rows = rows, byId = byId, incoming = {}, bag = Tx.bagInfoFromRows(rows), occupied = {} }
    end

    local function planExchange(lo, hi, rawLo, rawHi)
        local S = { [lo.cid] = prep(lo.cid, rawLo), [hi.cid] = prep(hi.cid, rawHi) }
        local sides = { { norm = lo, sim = S[lo.cid], other = S[hi.cid] }, { norm = hi, sim = S[hi.cid], other = S[lo.cid] } }

        -- A. outgoing: validate every offered row and detach it from the giver
        for _, g in ipairs(sides) do
            for _, line in ipairs(g.norm.lines) do
                local row = g.sim.byId[tonumber(line.ref)]
                if not row or row.qty <= 0 then return nil, 'invalid_item' end
                if Tx.isEquipSlot(row.slot) then return nil, 'not_tradeable' end
                local def = getItemDef(row.item_name)
                if not def then return nil, 'invalid_item' end
                local ok = canTrade(row.item_name, row.meta)
                if ok == nil then return nil, 'unavailable' end
                if not ok then return nil, 'not_tradeable' end
                if line.fp and line.fp ~= rowFingerprint({ item_name = row.item_name, metadata = row.metadata }) then return nil, 'item_changed' end
                if line.quantity > row.qty then return nil, 'insufficient_quantity' end
                local stackable = def.stack ~= false and def.unique ~= true
                local whole = line.quantity == row.qty
                if not whole and not stackable then return nil, 'invalid_quantity' end
                local piece = { item = row.item_name, qty = line.quantity, meta = Tx.deepCopy(row.meta), raw = row.metadata, src = row, whole = whole, from = g.sim.cid, def = def }
                if whole then row.qty = 0; row.leaving = piece else row.qty = row.qty - line.quantity end
                g.other.incoming[#g.other.incoming + 1] = piece
            end
        end

        -- B. placement into each receiver's post-removal state
        for _, r in ipairs({ S[lo.cid], S[hi.cid] }) do
            for _, row in ipairs(r.rows) do if row.qty > 0 then r.occupied[row.slot] = true end end
        end
        for _, r in ipairs({ S[lo.cid], S[hi.cid] }) do
            for _, piece in ipairs(r.incoming) do
                local def = piece.def
                if def.singleton == true then
                    for _, row in ipairs(r.rows) do if row.item_name == piece.item and row.qty > 0 then return nil, 'singleton_conflict' end end
                    for _, other in ipairs(r.incoming) do if other ~= piece and other.item == piece.item then return nil, 'singleton_conflict' end end
                end
                local cands = {}
                for _, row in ipairs(r.rows) do
                    if row.item_name == piece.item and row.qty > 0 and not Tx.isEquipSlot(row.slot)
                        and rowCanStackWithMetadata({ item_name = row.item_name, slot = row.slot, metadata = row.metadata }, piece.item, piece.meta) then
                        cands[#cands + 1] = row
                    end
                end
                table.sort(cands, Tx.byStackOrder)
                local target = cands[1]
                if target then
                    if target.qty + piece.qty > Tx.Cfg.maxRowQuantity then return nil, 'no_capacity' end
                    target.qty = target.qty + piece.qty
                    piece.merged = true
                else
                    local slot
                    for i = 1, Config.Slots.pockets.count do local s = Config.Slots.pockets.prefix .. i; if not r.occupied[s] then slot = s break end end
                    if not slot then
                        for i = 1, math.min(Config.Slots.backpack.count, r.bag.backpackSlots or 0) do local s = Config.Slots.backpack.prefix .. i; if not r.occupied[s] then slot = s break end end
                    end
                    if not slot or not canPlaceInSlot(piece.item, slot) then return nil, 'no_capacity' end
                    r.occupied[slot] = true
                    piece.slot = slot
                    piece.placed = true
                end
            end
        end

        -- C. final weight per character (rows after the exchange + newly placed pieces)
        for _, r in ipairs({ S[lo.cid], S[hi.cid] }) do
            local weight = 0
            for _, row in ipairs(r.rows) do if row.qty > 0 then local d = getItemDef(row.item_name); weight = weight + ((d and tonumber(d.weight) or 0) * row.qty) end end
            for _, piece in ipairs(r.incoming) do if piece.placed then weight = weight + ((tonumber(piece.def.weight) or 0) * piece.qty) end end
            if weight > r.bag.maxWeight then return nil, 'no_capacity' end
        end

        -- D. operations
        local ops = { updates = {}, deletes = {}, moves = {}, inserts = {}, audit = {}, pieces = 0 }
        for _, r in ipairs({ S[lo.cid], S[hi.cid] }) do
            for _, row in ipairs(r.rows) do
                if row.qty ~= row.orig then
                    if row.leaving and row.leaving.placed then
                        -- whole row moves (same row id): handled below
                    elseif row.qty <= 0 then ops.deletes[#ops.deletes + 1] = { id = row.id, qty = row.orig, owner = r.cid }
                    else ops.updates[#ops.updates + 1] = { id = row.id, qty = row.qty, old = row.orig, owner = r.cid } end
                end
            end
        end
        for _, r in ipairs({ S[lo.cid], S[hi.cid] }) do
            for _, piece in ipairs(r.incoming) do
                ops.pieces = ops.pieces + 1
                ops.audit[#ops.audit + 1] = { cid = piece.from, action = 'trade_out', item = piece.item, qty = piece.qty }
                ops.audit[#ops.audit + 1] = { cid = r.cid, action = 'trade_in', item = piece.item, qty = piece.qty }
                if piece.placed and piece.whole then
                    ops.moves[#ops.moves + 1] = { id = piece.src.id, from = piece.from, fromSlot = piece.src.slot, qty = piece.qty, to = r.cid, slot = piece.slot }
                elseif piece.placed then
                    ops.inserts[#ops.inserts + 1] = { owner = r.cid, slot = piece.slot, item = piece.item, qty = piece.qty, metadata = piece.raw }
                end
            end
        end
        return ops
    end

    -- ------------------------------------------------------------------ exports
    local function snapshot(characterId)
        if not Tx.trusted(Cfg.exchangeTrusted) then return false, 'forbidden' end
        local cid = Tx.validCharacterId(characterId)
        if not cid then return false, 'invalid_character' end
        local ok, rows = pcall(function() return MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY id', { Config.OwnerType or 'character', cid }) end)
        if not ok or type(rows) ~= 'table' then return false, 'unavailable' end
        local out = {}
        for _, row in ipairs(rows) do
            if not Tx.isEquipSlot(tostring(row.slot)) and #out < 200 then
                local def = getItemDef(row.item_name)
                if def then
                    local meta = decode(row.metadata)
                    local ok2 = canTrade(row.item_name, meta)
                    out[#out + 1] = { ref = tostring(row.id), item = tostring(row.item_name):lower(), label = tostring(meta.label or def.label or row.item_name):sub(1, 60), image = def.image,
                        quantity = tonumber(row.quantity) or 0, tradeable = ok2 == true, summary = summaryOf(row, def), fp = rowFingerprint(row) }
                end
            end
        end
        return out
    end

    local function loadRows(q, cid, lock)
        local sql = lock and 'SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY id FOR UPDATE'
            or 'SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY id'
        return q(sql, { Config.OwnerType or 'character', cid })
    end

    local function validate(...)
        if not Tx.trusted(Cfg.exchangeTrusted) then return false, 'forbidden' end
        local ref, a, b = Tx.stripSelf(...)
        if not Tx.validReference(ref) then return false, 'invalid_transaction' end
        local lo, hi = normalizeExchange(a, b)
        if not lo then return false, hi end
        for _, c in ipairs({ lo.cid, hi.cid }) do
            local exists = Tx.characterExists(c)
            if exists == nil then return false, 'unavailable' end
            if not exists then return false, 'invalid_transaction' end
        end
        local function q(sql, p) return MySQL.query.await(sql, p) end
        local okR, rawLo = pcall(loadRows, q, lo.cid, false)
        local okH, rawHi = pcall(loadRows, q, hi.cid, false)
        if not okR or not okH or type(rawLo) ~= 'table' or type(rawHi) ~= 'table' then return false, 'unavailable' end
        local plan, reason = planExchange(lo, hi, rawLo, rawHi)
        if not plan then return false, reason end
        return true
    end

    -- ------------------------------------------------------------------ durable exchange intent (ledger lifecycle)
    -- cm_inventory_transactions row for a trade_exchange reference moves   (none) -> prepared -> committed
    --                                                                                         \-> not_applied   (TERMINAL)
    --   prepared     an executor holds a lease (result_json = {"lease":token,"exp":epoch}); outcome pending
    --   committed    the item transaction committed (written INSIDE that transaction, guarded on the lease still being ours)
    --   not_applied  no item mutation can ever commit under this reference (written by a definite failure, by an executor releasing nothing,
    --                or by FenceItemExchange); every later ExecuteItemExchange for the reference is refused
    -- Every transition is a compare-and-set on (status, result_json), so exactly one of {commit, fence/reclaim} wins; the loser changes nothing.
    -- Correctness never depends on the lease length: a stale or zombie executor can only commit while its own lease token is still in the row.
    local function leaseSeconds() return tonumber(Cfg.exchangeLeaseSeconds) or 60 end
    local tokenSeq = 0
    local function newLease(untilEpoch)
        tokenSeq = tokenSeq + 1
        return ('{"lease":"%x-%x-%x","exp":%d}'):format(os.time(), tokenSeq, math.random(0x100000, 0xFFFFFF), untilEpoch or (os.time() + leaseSeconds()))
    end
    local function leaseUntil(text)
        local t = decode(text)
        return tonumber(t.exp) or 0
    end
    local function released(text) return (tostring(text):gsub('"exp":%d+', '"exp":0')) end

    local function ledgerUpdate(sql, params)
        local ok, n = pcall(function() return MySQL.update.await(sql, params) end)
        if not ok or n == nil then return nil end
        return tonumber(n) or 0
    end
    local function insertPrepared(ref, cid, payload, lease)
        local ok, r = pcall(function()
            return MySQL.insert.await([[INSERT INTO cm_inventory_transactions
                (reference, tx_type, character_id, payload_hash, payload, status, result_json)
                VALUES (?, ?, ?, ?, ?, 'prepared', ?)]], { ref, EX_TYPE, cid, Tx.fnv1a(payload), payload, lease })
        end)
        return ok and r ~= nil
    end
    local function insertTombstone(ref)
        local ok, r = pcall(function()
            return MySQL.insert.await([[INSERT INTO cm_inventory_transactions
                (reference, tx_type, character_id, payload_hash, payload, status, result_json)
                VALUES (?, ?, ?, ?, ?, 'not_applied', ?)]], { ref, EX_TYPE, '0', '0000000000000000', '', encode({ reason = 'fenced' }) })
        end)
        return ok and r ~= nil
    end
    local function casLease(ref, oldText, newText)
        return ledgerUpdate([[UPDATE cm_inventory_transactions SET result_json = ?
            WHERE reference = ? AND status = 'prepared' AND result_json = ?]], { newText, ref, oldText }) == 1
    end
    local function casTerminal(ref, oldText, reason)
        return ledgerUpdate([[UPDATE cm_inventory_transactions SET status = 'not_applied', result_json = ?
            WHERE reference = ? AND status = 'prepared' AND result_json = ?]], { encode({ reason = reason }), ref, oldText }) == 1
    end

    local function status(...)
        if not Tx.trusted(Cfg.exchangeTrusted) then return false, 'forbidden' end
        local ref = Tx.stripSelf(...)
        if not Tx.validReference(ref) then return false, 'invalid_reference' end
        if not Tx.ensureLedger() then return 'unknown' end
        local row, err = Tx.ledgerLookup(ref)
        if err then return 'unknown' end
        if not row then return 'not_submitted' end          -- never claimed; an in-flight call may still arrive: fence it before compensating
        if row.tx_type ~= EX_TYPE then return false, 'reference_conflict' end
        if row.status == 'committed' then return 'committed' end
        if row.status == 'not_applied' then return 'not_applied' end
        return 'pending'
    end

    -- Makes `not_applied` true and permanent when (and only when) that can be proven. -> 'committed' | 'not_applied' | 'pending' | false, reason
    local function fence(...)
        if not Tx.trusted(Cfg.exchangeTrusted) then return false, 'forbidden' end
        local ref = Tx.stripSelf(...)
        if not Tx.validReference(ref) then return false, 'invalid_reference' end
        if not Tx.ensureLedger() then return false, 'unavailable' end
        for _ = 1, 3 do
            local row, err = Tx.ledgerLookup(ref)
            if err then return false, 'unavailable' end
            if not row then
                if insertTombstone(ref) then
                    print(('[CM-INVENTORY] exchange %s fenced before submission (terminal not_applied)'):format(ref))
                    return 'not_applied'
                end
            else
                if row.tx_type ~= EX_TYPE then return false, 'reference_conflict' end
                if row.status == 'committed' then return 'committed' end
                if row.status == 'not_applied' then return 'not_applied' end
                if leaseUntil(row.result_json) > os.time() then return 'pending' end   -- a live executor still owns it
                if casTerminal(ref, row.result_json, 'fenced_stale') then
                    print(('[CM-INVENTORY] exchange %s stale executor fenced (terminal not_applied)'):format(ref))
                    return 'not_applied'
                end
            end
        end
        return 'pending'
    end

    -- -> 'claimed' | 'replayed' | 'conflict' | 'terminal' | 'busy' | 'unavailable', lease
    local function claim(ref, cid, payload)
        local lease = newLease()
        if insertPrepared(ref, cid, payload, lease) then return 'claimed', lease end
        local row, err = Tx.ledgerLookup(ref)
        if err or not row then return 'unavailable' end
        if row.tx_type ~= EX_TYPE then return 'conflict' end
        if row.status == 'committed' then return (row.payload == payload) and 'replayed' or 'conflict' end
        if row.status == 'not_applied' then return 'terminal' end
        if row.payload ~= payload then return 'conflict' end
        if leaseUntil(row.result_json) > os.time() then return 'busy' end
        if casLease(ref, row.result_json, lease) then
            print(('[CM-INVENTORY] exchange %s stale executor lease reclaimed'):format(ref))
            return 'claimed', lease
        end
        return 'busy'
    end

    local function execute(...)
        if not Tx.trusted(Cfg.exchangeTrusted) then return false, 'forbidden' end
        local ref, a, b = Tx.stripSelf(...)
        if not Tx.validReference(ref) then return false, 'invalid_transaction' end
        local lo, hi = normalizeExchange(a, b)
        if not lo then return false, hi end
        local payload = payloadOf(lo, hi)
        if #payload > 6000 then return false, 'invalid_transaction' end
        if not Tx.ensureLedger() then return false, 'unavailable' end

        -- durable intent + execution claim BEFORE any item row is touched
        local claimed, lease = claim(ref, lo.cid, payload)
        if claimed == 'replayed' then return true, { replayed = true } end
        if claimed == 'conflict' then return false, 'reference_conflict' end
        if claimed == 'terminal' then return false, 'not_applied' end
        if claimed == 'busy' then return false, 'pending' end
        if claimed ~= 'claimed' then return false, 'unavailable' end
        Tx.failpoint('exchange_after_claim')

        local ownerType = Config.OwnerType or 'character'
        local keyLo, keyHi = Tx.lockKey(ownerType, lo.cid), Tx.lockKey(ownerType, hi.cid)
        -- deterministic order: lowest character id first. A<->B and B<->A therefore queue in the same order and cannot deadlock.
        if not Tx.acquire(keyLo) then casLease(ref, lease, released(lease)) return false, 'unavailable' end
        if not Tx.acquire(keyHi) then Tx.release(keyLo) casLease(ref, lease, released(lease)) return false, 'unavailable' end

        local result
        local okRun, errRun = pcall(function()
            local outcome = {}
            local committed = MySQL.startTransaction(function(query)
                local okBody, bodyErr = pcall(function()
                    local function q(sql, params)
                        local r = query(sql, params)
                        if r == nil then error('query_failed') end
                        return r
                    end
                    local function affected(sql, params)
                        local r = q(sql, params)
                        local n = type(r) == 'table' and r.affectedRows or r
                        if tonumber(n) ~= 1 then error('guard_failed') end
                    end
                    Tx.failpoint('exchange_begin')
                    local rawLo = loadRows(q, lo.cid, true)        -- lowest id first
                    Tx.failpoint('exchange_after_lock_a')
                    local rawHi = loadRows(q, hi.cid, true)
                    Tx.failpoint('exchange_after_lock_both')
                    -- the ledger row is locked and must still carry OUR lease: a fence/reclaim that won earlier makes this attempt a no-op
                    local led = q('SELECT status, result_json, payload FROM cm_inventory_transactions WHERE reference = ? FOR UPDATE', { ref })[1]
                    if not led or led.status ~= 'prepared' or led.result_json ~= lease then outcome.lost = led or false return end
                    for _, c in ipairs({ lo.cid, hi.cid }) do
                        if not q('SELECT id FROM characters WHERE id = ? LIMIT 1', { c })[1] then outcome.fail = 'invalid_transaction' return end
                    end
                    local ops, reason = planExchange(lo, hi, rawLo, rawHi)
                    if not ops then outcome.fail = reason return end
                    Tx.failpoint('exchange_after_validation')

                    local function audit(a2)
                        q('INSERT INTO inventory_audit (character_id, action, item_name, quantity, from_slot, to_slot, reason) VALUES (?, ?, ?, ?, ?, ?, ?)',
                            { a2.cid, a2.action, a2.item, a2.qty, nil, nil, ref })
                    end
                    -- 1. removals and quantity changes on existing rows
                    for _, side in ipairs({ lo.cid, hi.cid }) do      -- lowest character id first, same order as the locks
                        for _, u in ipairs(ops.updates) do if u.owner == side then affected('UPDATE inventory_items SET quantity = ? WHERE id = ? AND quantity = ?', { u.qty, u.id, u.old }) end end
                        for _, d in ipairs(ops.deletes) do if d.owner == side then affected('DELETE FROM inventory_items WHERE id = ? AND quantity = ?', { d.id, d.qty }) end end
                        Tx.failpoint(side == lo.cid and 'exchange_after_remove_a' or 'exchange_after_remove_b')
                    end
                    -- 2. whole rows leave their owner to unique temporary slots (frees every outgoing slot; avoids swap cycles on the UNIQUE slot key)
                    for _, m in ipairs(ops.moves) do
                        affected('UPDATE inventory_items SET owner_id = ?, slot = ? WHERE id = ? AND owner_type = ? AND owner_id = ? AND quantity = ?',
                            { m.to, 'xfer-' .. m.id, m.id, ownerType, m.from, m.qty })
                    end
                    -- 3. new rows for partial pieces
                    for _, i in ipairs(ops.inserts) do
                        q('INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata) VALUES (?, ?, ?, ?, ?, ?)', { ownerType, i.owner, i.slot, i.item, i.qty, i.metadata })
                        Tx.failpoint('exchange_after_first_add')
                    end
                    -- 4. final slots of the moved rows
                    for _, m in ipairs(ops.moves) do
                        affected('UPDATE inventory_items SET slot = ? WHERE id = ? AND owner_type = ? AND owner_id = ? AND slot = ?', { m.slot, m.id, ownerType, m.to, 'xfer-' .. m.id })
                    end
                    Tx.failpoint('exchange_after_adds')
                    for _, a2 in ipairs(ops.audit) do audit(a2) end
                    Tx.failpoint('exchange_before_ledger')
                    -- commit marker: same transaction, guarded on status + lease (0 rows => the whole transaction rolls back)
                    affected([[UPDATE cm_inventory_transactions SET status = 'committed', result_json = ?, committed_at = NOW()
                        WHERE reference = ? AND status = 'prepared' AND result_json = ?]], { encode({ pieces = ops.pieces }), ref, lease })
                    Tx.failpoint('exchange_after_ledger')
                    outcome.ok = true
                    outcome.pieces = ops.pieces
                end)
                if not okBody then outcome.error = tostring(bodyErr); outcome.ok = nil return false end
                if not outcome.ok then return false end
                return true
            end)

            local function settled()
                local row, lookupErr = Tx.ledgerLookup(ref)    -- the ledger is the only authority on what happened
                if lookupErr or not row then return false, 'unavailable' end
                if row.tx_type ~= EX_TYPE then return false, 'reference_conflict' end
                if row.status == 'committed' then return (row.payload == payload) and true or false, (row.payload == payload) and { replayed = true } or 'reference_conflict' end
                if row.status == 'not_applied' then return false, 'not_applied' end
                return false, 'pending'
            end
            if outcome.ok and committed == true then
                result = { true, { replayed = false, pieces = outcome.pieces } }
                Tx.failpoint('exchange_after_commit')
            elseif outcome.lost ~= nil then
                local okS, whyS = settled()
                result = { okS, whyS }
            elseif outcome.fail then
                -- definite: nothing was applied and the plan can never be accepted for this reference -> make it permanent
                -- ('unavailable' = cm-items/dependency down while planning: nothing applied, but not a property of the exchange, so only release the lease)
                if outcome.fail == 'unavailable' then casLease(ref, lease, released(lease)) else casTerminal(ref, lease, outcome.fail) end
                result = { false, outcome.fail }
            else
                -- error/unknown: the transaction may or may not have committed. Do not decide; the ledger row stays `prepared` (lease expires, then a
                -- re-execute reclaims it or a fence proves not_applied). Only an explicitly rolled-back transaction releases the lease early.
                local okS, whyS = settled()
                if okS == true then result = { true, whyS }
                else
                    if committed == false and whyS == 'pending' then casLease(ref, lease, released(lease)) end
                    result = { false, 'unavailable' }
                end
            end
        end)
        Tx.release(keyHi); Tx.release(keyLo)
        if not okRun then
            print(('^1[CM-INVENTORY]^7 exchange error reference=%s error=%s'):format(tostring(ref), tostring(errRun)))
            local row = Tx.ledgerLookup(ref)
            if row and row.tx_type == EX_TYPE and row.status == 'committed' and row.payload == payload then return true, { replayed = true } end
            return false, 'unavailable'
        end
        if result[1] == true and result[2] and result[2].replayed == false then Tx.refreshOnline(lo.cid); Tx.refreshOnline(hi.cid) end
        return result[1], result[2]
    end

    exports('GetTradeSnapshot', function(...) local c = Tx.stripSelf(...); return snapshot(c) end)
    exports('ValidateItemExchange', validate)
    exports('ExecuteItemExchange', execute)
    exports('GetItemExchangeStatus', status)
    exports('FenceItemExchange', fence)
end
