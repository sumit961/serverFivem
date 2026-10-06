-- cm-trade/server/selftest.lua
-- Development-only service-layer self-test:   server console  ->  cm_trade_selftest
-- Requires cm_environment=development; console only. Replaces the presence/money/item providers with in-memory
-- test doubles (synthetic sources 101-106, characters 92000xx), captures client events, injects failures and crashes,
-- and removes every journal row it created. It exercises the same functions the net events use.
-- NOTE: the inventory double implements the PROPOSED cm-inventory exchange contract; it proves cm-trade's
-- orchestration, not cm-inventory itself (see docs/SHARED_INTEGRATION.md).

local T = CMTrade

local function enabled()
    return GetConvar(Config.SelfTest.convar, 'production') == Config.SelfTest.value
end

local CID = { [101] = 9200001, [102] = 9200002, [103] = 9200003, [104] = 9200004, [105] = 9200005, [106] = 9200006 }
local A, B, C, D, E, F = 9200001, 9200002, 9200003, 9200004, 9200005, 9200006

local function cleanup()
    MySQL.query.await('DELETE FROM cm_trade_transactions WHERE char_a >= 9200000 AND char_a < 9300000')
    MySQL.query.await('DELETE FROM cm_trade_events WHERE char_a >= 9200000 AND char_a < 9300000')
end

local function run()
    local total, failed = 0, 0
    local function check(name, cond, detail)
        total = total + 1
        if cond ~= true then
            failed = failed + 1
            print(('[cm-trade:selftest] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-trade:selftest] PASS  %s'):format(name))
        end
    end

    -- ---- world / provider doubles ------------------------------------------------------------------------------
    local origP = { presence = T.P.presence, money = T.P.money, items = T.P.items, identity = T.P.identity }
    local origTrigger = TriggerClientEvent
    local sent = {}
    TriggerClientEvent = function(name, src, payload) sent[#sent + 1] = { name = name, src = src, payload = payload } end
    T.TestNoAdminLog = true

    local pos, bucket, dead, srcOfCid = {}, {}, {}, {}
    for src, cid in pairs(CID) do pos[src] = { 0, 0, 0 }; bucket[src] = 0; srcOfCid[cid] = src end
    pos[104] = { 50, 0, 0 }; bucket[105] = 7; dead[106] = true
    local cidMap = {}
    for k, v in pairs(CID) do cidMap[k] = v end
    cidMap[999] = A   -- a forged source claiming character A's identity

    local W, led = {}, {}
    local failDebit, failCredit = {}, {}
    local function ledKey(cid, action, reason) return cid .. '|' .. action .. '|' .. reason end

    T.P.presence = {
        cidOf = function(src) return cidMap[tonumber(src)] end,
        srcOf = function(cid) return srcOfCid[cid] end,
        bucket = function(src) return bucket[tonumber(src)] or 0 end,
        distance = function(a, b) local pa, pb = pos[tonumber(a)], pos[tonumber(b)]; if not pa or not pb then return nil end return math.sqrt((pa[1] - pb[1]) ^ 2 + (pa[2] - pb[2]) ^ 2 + (pa[3] - pb[3]) ^ 2) end,
        dead = function(src) return dead[tonumber(src)] == true end,
    }
    T.P.identity = { label = function(viewer, _, other) return 'Stranger #' .. other end }
    T.P.money = {
        cash = function(cid) return W[cid] end,
        debit = function(cid, amount, reason)
            if failDebit[cid] or (W[cid] or 0) < amount or amount <= 0 then return false end
            W[cid] = W[cid] - amount; led[ledKey(cid, 'remove', reason)] = true; return true
        end,
        credit = function(cid, amount, reason)
            if failCredit[cid] or amount <= 0 then return false end
            W[cid] = (W[cid] or 0) + amount; led[ledKey(cid, 'add', reason)] = true; return true
        end,
        evidence = function(cid, action, reason) return led[ledKey(cid, action, reason)] == true end,
    }

    -- inventory double implementing the proposed exchange contract
    local inv, applied, itemsOn, failExec, capRows, rowSeq = {}, {}, true, false, {}, 1000
    local execCalls = 0
    local function addRow(cid, ref, item, qty, meta, tradeable, label)
        inv[cid] = inv[cid] or {}
        inv[cid][ref] = { ref = ref, item = item, label = label or item, quantity = qty, meta = meta or {}, tradeable = tradeable ~= false }
    end
    local function countRows(cid) local n = 0 for _ in pairs(inv[cid] or {}) do n = n + 1 end return n end
    local function validateExchange(a, b)
        local newRows = { [a.characterId] = 0, [b.characterId] = 0 }
        local removed = { [a.characterId] = 0, [b.characterId] = 0 }
        local sides = { { a, b }, { b, a } }
        for _, sd in ipairs(sides) do
            local from, to = sd[1], sd[2]
            for _, l in ipairs(from.lines) do
                local row = (inv[from.characterId] or {})[l.ref]
                if not row then return false, 'missing_item' end
                if not row.tradeable then return false, 'not_tradeable' end
                if l.quantity < 1 or l.quantity > row.quantity then return false, 'insufficient_quantity' end
                newRows[to.characterId] = newRows[to.characterId] + 1
                if l.quantity == row.quantity then removed[from.characterId] = removed[from.characterId] + 1 end
            end
        end
        for _, cid in ipairs({ a.characterId, b.characterId }) do
            if countRows(cid) - removed[cid] + newRows[cid] > (capRows[cid] or 10) then return false, 'no_capacity' end
        end
        return true
    end
    T.P.items = {
        enabled = function() return itemsOn end,
        snapshot = function(cid)
            local out = {}
            for _, r in pairs(inv[cid] or {}) do out[#out + 1] = { ref = r.ref, item = r.item, label = r.label, quantity = r.quantity, tradeable = r.tradeable, summary = r.meta.serial and ('Serial ' .. r.meta.serial) or nil } end
            table.sort(out, function(x, y) return x.ref < y.ref end)
            return out
        end,
        validate = function(ref, a, b) return validateExchange(a, b) end,
        execute = function(ref, a, b)
            execCalls = execCalls + 1
            if applied[ref] then return true end                       -- idempotent per trade reference
            if failExec then return false, 'exec_failed' end
            local ok, why = validateExchange(a, b)
            if not ok then return false, why end
            local moves = {}
            for _, sd in ipairs({ { a, b }, { b, a } }) do
                for _, l in ipairs(sd[1].lines) do moves[#moves + 1] = { from = sd[1].characterId, to = sd[2].characterId, ref = l.ref, qty = l.quantity } end
            end
            for _, m in ipairs(moves) do
                local row = inv[m.from][m.ref]
                local copy = { item = row.item, label = row.label, meta = row.meta, tradeable = row.tradeable }
                if m.qty == row.quantity then inv[m.from][m.ref] = nil else row.quantity = row.quantity - m.qty end
                rowSeq = rowSeq + 1
                local merged = false
                if next(copy.meta) == nil then
                    for _, r in pairs(inv[m.to] or {}) do if r.item == copy.item and next(r.meta) == nil then r.quantity = r.quantity + m.qty merged = true break end end
                end
                if not merged then addRow(m.to, 'r' .. rowSeq, copy.item, m.qty, copy.meta, copy.tradeable, copy.label) end
            end
            applied[ref] = true
            return true
        end,
        status = function(ref) return applied[ref] and 'applied' or 'not_applied' end,
    }

    local function wallet(cid, v) W[cid] = v end
    local function journal(ref) return MySQL.single.await('SELECT * FROM cm_trade_transactions WHERE reference = ?', { ref }) end
    local function eventCount(kind, ref) return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_trade_events WHERE session_ref = ? AND kind = ?', { ref, kind })) or 0 end
    local function sentTo(src, name) local n = 0 for _, e in ipairs(sent) do if e.src == src and e.name == name then n = n + 1 end end return n end
    local function open(sa, sb)
        T.ResetRateLimits()
        local ok, id = T.Invite(sa or 101, sb or 102)
        if not ok then return nil, id end
        T.Respond(sb or 102, id, true)
        return T.sessions[id], id
    end
    local function endAll() for _, s in pairs(T.sessions) do if s.state == 'open' or s.state == 'invited' then T.CancelSession(s, 'cancelled') end end T.sessions, T.byCid = {}, {} end
    local function bothConfirm(s) T.Confirm(s.a.src, s.id, s.rev); return T.Confirm(s.b.src, s.id, s.rev) end

    -- ---- INVITES -------------------------------------------------------------------------------------------------------
    T.ResetRateLimits(); wallet(A, 10000); wallet(B, 10000); wallet(C, 10000); wallet(D, 100); wallet(E, 100); wallet(F, 100)
    local okInv, id1 = T.Invite(101, 102)
    check('invite.valid_nearby', okInv == true and T.sessions[id1].state == 'invited' and sentTo(102, 'cm-trade:client:invite') == 1)
    check('invite.self_rejected', select(2, T.Invite(101, 101)) == 'invalid_target')
    check('invite.unknown_source_rejected', select(2, T.Invite(101, 4242)) == 'invalid_target' and select(2, T.Invite(nil, 102)) == 'invalid_target')
    check('invite.duplicate_rejected_while_pending', select(2, T.Invite(101, 102)) == 'busy' and select(2, T.Invite(102, 101)) == 'busy')
    check('invite.third_party_rejected_while_busy', select(2, T.Invite(103, 102)) == 'busy' and select(2, T.Invite(101, 103)) == 'busy')
    check('invite.non_target_cannot_accept', select(2, T.Respond(103, id1, true)) == 'invalid_state' and select(2, T.Respond(101, id1, true)) == 'invalid_state' and T.sessions[id1].state == 'invited')
    check('invite.garbage_id_rejected', select(2, T.Respond(102, 'TRD-NOPE', true)) == 'invalid_state' and select(2, T.Respond(102, nil, true)) == 'invalid_state' and select(2, T.Respond(102, {}, true)) == 'invalid_state')
    local okD = T.Respond(102, id1, false)
    check('invite.decline', okD == true and T.sessions[id1].state == 'cancelled' and T.byCid[A] == nil and T.byCid[B] == nil)
    T.ResetRateLimits()
    local _, id2 = T.Invite(101, 102)
    T.sessions[id2].expiresAt = os.time() - 1
    check('invite.expired_cannot_accept', select(2, T.Respond(102, id2, true)) == 'expired' and T.sessions[id2].state == 'cancelled' and T.byCid[A] == nil)
    T.ResetRateLimits()
    local _, id3 = T.Invite(101, 102)
    T.sessions[id3].expiresAt = os.time() - 1
    T.Tick()
    check('invite.tick_expires_and_frees_players', T.sessions[id3] == nil or T.sessions[id3].state == 'cancelled')
    endAll()
    T.ResetRateLimits()
    check('invite.far_target_rejected', select(2, T.Invite(101, 104)) == 'too_far')
    check('invite.other_bucket_rejected', select(2, T.Invite(101, 105)) == 'wrong_bucket')
    check('invite.dead_target_rejected', select(2, T.Invite(101, 106)) == 'dead')
    T.ResetRateLimits()
    local rl = 0
    for _ = 1, 8 do local ok, why = T.Invite(101, 102); if ok then T.CancelSession(T.sessions[T.byCid[A]], 'cancelled') end if why == 'rate_limited' then rl = rl + 1 end end
    check('invite.rate_limited', rl >= 1)
    endAll(); T.ResetRateLimits()
    local s = open()
    check('invite.accept_opens_session', s ~= nil and s.state == 'open' and sentTo(101, 'cm-trade:client:open') >= 1 and sentTo(102, 'cm-trade:client:open') >= 1)
    check('invite.accept_revalidates_distance', (function()
        endAll(); T.ResetRateLimits()
        local ok, id = T.Invite(101, 102)
        pos[102] = { 20, 0, 0 }
        local r = select(2, T.Respond(102, id, true))
        pos[102] = { 0, 0, 0 }
        return r == 'too_far' and T.sessions[id].state == 'cancelled'
    end)())

    -- ---- SESSION ---------------------------------------------------------------------------------------------------------
    endAll()
    s = open()
    check('session.one_active_trade_per_player', select(2, T.Invite(101, 103)) == 'busy' and select(2, T.Invite(103, 101)) == 'busy' and select(2, T.Invite(103, 102)) == 'busy')
    check('session.third_party_cannot_act', select(2, T.SetCash(103, s.id, 5)) == 'invalid_state' and select(2, T.Confirm(103, s.id, s.rev)) == 'invalid_state' and select(2, T.Cancel(103, s.id)) == 'invalid_state')
    check('session.foreign_or_garbage_id_rejected', select(2, T.SetCash(101, 'TRD-ZZZZZZZZ', 5)) == 'invalid_state' and select(2, T.SetCash(101, nil, 5)) == 'invalid_state' and select(2, T.SetCash(101, { }, 5)) == 'invalid_state')
    check('session.forged_source_for_participant_rejected', select(2, T.SetCash(999, s.id, 5)) == 'invalid_state' and s.offers[A].cash == 0)
    check('session.cancel', T.Cancel(101, s.id) == true and s.state == 'cancelled' and T.byCid[A] == nil and sentTo(102, 'cm-trade:client:ended') >= 1)
    check('session.cancelled_cannot_reopen', select(2, T.Respond(102, s.id, true)) == 'invalid_state' and select(2, T.SetCash(101, s.id, 1)) == 'invalid_state' and select(2, T.Confirm(101, s.id, 1)) == 'invalid_state')
    s = open()
    T.DropPlayer(102)
    check('session.disconnect_cancels_and_frees', s.state == 'cancelled' and T.byCid[A] == nil and T.byCid[B] == nil)
    s = open()
    pos[102] = { 9, 0, 0 }
    T.Tick()
    check('session.separation_cancels', s.state == 'cancelled')
    pos[102] = { 0, 0, 0 }
    s = open()
    s.createdAt = os.time() - Config.Session.MaxMinutes * 60 - 5
    T.Tick()
    check('session.timeout_cancels', s.state == 'cancelled')
    s = open()
    dead[102] = true
    T.Tick()
    dead[102] = nil
    check('session.death_cancels', s.state == 'cancelled')
    endAll()

    -- ---- CASH --------------------------------------------------------------------------------------------------------------
    s = open()
    check('cash.zero_ok', T.SetCash(101, s.id, 0) == true)
    for _, bad in ipairs({ -1, 1.5, 0 / 0, math.huge, Config.Limits.MaxCash + 1 }) do
        check('cash.rejected_' .. tostring(bad), select(2, T.SetCash(101, s.id, bad)) == 'invalid_amount')
    end
    check('cash.non_number_rejected', select(2, T.SetCash(101, s.id, '5000')) == 'invalid_amount' and select(2, T.SetCash(101, s.id, nil)) == 'invalid_amount' and select(2, T.SetCash(101, s.id, true)) == 'invalid_amount')
    check('cash.insufficient_rejected', select(2, T.SetCash(104 == 0 and 101 or 101, s.id, 10001)) == 'insufficient_cash')
    check('cash.valid_offer_sets_only_own_side', T.SetCash(101, s.id, 5000) == true and s.offers[A].cash == 5000 and s.offers[B].cash == 0)
    T.ResetRateLimits()
    local rev0 = s.rev
    T.Confirm(101, s.id, s.rev)
    check('cash.offer_change_resets_confirmations', s.confirmed[A] == true and (T.SetCash(102, s.id, 100) == true) and next(s.confirmed) == nil and s.rev > rev0)
    T.SetCash(102, s.id, 0)
    -- wallet drops after the offer, before commit
    wallet(A, 100)
    bothConfirm(s)
    check('cash.wallet_changed_before_commit_moves_nothing', s.state == 'cancelled' and W[A] == 100 and W[B] == 10000 and next(led) == nil)
    endAll(); wallet(A, 10000); wallet(B, 10000)
    -- exactly-once settlement
    s = open()
    T.SetCash(101, s.id, 5000)
    T.Confirm(101, s.id, s.rev)
    check('cash.one_confirmation_does_not_commit', s.state == 'open' and W[A] == 10000)
    local okS = T.Confirm(102, s.id, s.rev)
    local j = journal(s.id)
    check('cash.settlement_exactly_once', okS == true and W[A] == 5000 and W[B] == 15000 and j.status == 'completed' and s.state == 'completed')
    check('cash.no_money_created', W[A] + W[B] == 20000)
    check('cash.replay_after_completion_rejected', select(2, T.Confirm(101, s.id, s.rev)) == 'invalid_state' and select(2, T.Commit(s)) == 'invalid_state' and W[A] == 5000 and W[B] == 15000)
    check('cash.lifecycle_audited', eventCount('completed', s.id) == 1 and eventCount('accepted', s.id) == 1 and eventCount('invited', s.id) == 1)
    wallet(A, 10000); wallet(B, 10000)
    T.ResetRateLimits()
    s = open()
    T.SetCash(101, s.id, 3000); T.SetCash(102, s.id, 1000)
    bothConfirm(s)
    check('cash.two_way_swap', W[A] == 8000 and W[B] == 12000 and journal(s.id).status == 'completed')
    wallet(A, 10000); wallet(B, 10000); endAll()

    -- ---- ITEMS ---------------------------------------------------------------------------------------------------------------
    inv = {}
    addRow(A, 'a1', 'water', 10, {}, true, 'Water Bottle')
    addRow(A, 'a2', 'lockpick_adv', 1, { serial = 'SN-77', durability = 63 }, true, 'Advanced Lockpick')
    addRow(A, 'a3', 'id_item', 1, {}, false, 'Protected Thing')
    addRow(A, 'a4', 'weapon_pistol', 1, { serial = 'WP-1', ammo = 12 }, true, 'Pistol')
    addRow(B, 'b1', 'sandwich', 4, {}, true, 'Sandwich')
    s = open()
    itemsOn = false
    check('items.disabled_means_cash_only', select(2, T.AddItem(101, s.id, 'a1', 1)) == 'items_disabled')
    itemsOn = true
    check('items.valid_stack', T.AddItem(101, s.id, 'a1', 10) == true and #s.offers[A].items == 1)
    check('items.partial_quantity', T.AddItem(101, s.id, 'a1', 3) == true and #s.offers[A].items == 1 and s.offers[A].items[1].quantity == 3)
    check('items.duplicate_reference_updates_not_duplicates', (function() T.AddItem(101, s.id, 'a1', 3) T.AddItem(101, s.id, 'a1', 4) return #s.offers[A].items == 1 and s.offers[A].items[1].quantity == 4 end)())
    check('items.missing_item_rejected', select(2, T.AddItem(101, s.id, 'zz9', 1)) == 'invalid_item')
    check('items.other_players_row_rejected', select(2, T.AddItem(101, s.id, 'b1', 1)) == 'invalid_item' and select(2, T.AddItem(102, s.id, 'a1', 1)) == 'invalid_item')
    check('items.insufficient_quantity_rejected', select(2, T.AddItem(101, s.id, 'a1', 11)) == 'insufficient_quantity')
    check('items.protected_item_rejected', select(2, T.AddItem(101, s.id, 'a3', 1)) == 'not_tradeable')
    check('items.denylist_blocks_weapons_and_keys', select(2, T.AddItem(101, s.id, 'a4', 1)) == 'not_tradeable' and T.IsDeniedItem('vehicle_key_ab12') and T.IsDeniedItem('weapon_smg') and not T.IsDeniedItem('water'))
    check('items.bad_ref_and_quantity_rejected', select(2, T.AddItem(101, s.id, "a1'; DROP", 1)) == 'invalid_item' and select(2, T.AddItem(101, s.id, 'a1', 0)) == 'invalid_amount' and select(2, T.AddItem(101, s.id, 'a1', 1.5)) == 'invalid_amount' and select(2, T.AddItem(101, s.id, 'a1', Config.Limits.MaxQuantityPerLine + 1)) == 'invalid_amount' and select(2, T.AddItem(101, s.id, {}, 1)) == 'invalid_item')
    check('items.line_limit', (function()
        for i = 1, 9 do addRow(A, 'x' .. i, 'misc' .. i, 1, {}, true) end
        local last
        for i = 1, 9 do last = select(2, T.AddItem(101, s.id, 'x' .. i, 1)) end
        return last == 'too_many_lines' and #s.offers[A].items == Config.Limits.MaxItemLines
    end)())
    for i = 1, 9 do inv[A]['x' .. i] = nil end
    check('items.remove_line_resets_confirmations', (function() T.Confirm(101, s.id, s.rev) T.RemoveItem(101, s.id, 'a1') return next(s.confirmed) == nil end)())
    endAll()
    -- full item swap with unique metadata
    s = open()
    T.AddItem(101, s.id, 'a2', 1); T.AddItem(102, s.id, 'b1', 2)
    T.SetCash(101, s.id, 250)
    wallet(A, 10000); wallet(B, 10000)
    bothConfirm(s)
    local moved
    for _, r in pairs(inv[B]) do if r.item == 'lockpick_adv' then moved = r end end
    check('items.unique_item_metadata_preserved', moved ~= nil and moved.meta.serial == 'SN-77' and moved.meta.durability == 63 and moved.quantity == 1 and inv[A]['a2'] == nil)
    check('items.partial_stack_moves_exact_quantity', inv[B]['b1'].quantity == 2 and (function() for _, r in pairs(inv[A]) do if r.item == 'sandwich' then return r.quantity == 2 end end end)())
    check('items.cash_and_items_settle_together', W[A] == 9750 and W[B] == 10250 and journal(s.id).status == 'completed' and applied[s.id] == true)
    check('items.no_items_created_or_destroyed', (function() local n = 0 for _, cid in ipairs({ A, B }) do for _, r in pairs(inv[cid]) do if r.item == 'sandwich' then n = n + r.quantity end end end return n == 4 end)())
    check('items.replay_does_not_move_again', select(2, T.Commit(s)) == 'invalid_state' and execCalls == 1)
    endAll()
    -- capacity failure
    inv = {}; capRows[B] = 2
    addRow(A, 'a1', 'water', 10, {}, true); addRow(A, 'a2', 'lockpick_adv', 1, { serial = 'SN-1' }, true); addRow(A, 'a5', 'bandage', 3, {}, true)
    addRow(B, 'b1', 'sandwich', 4, {}, true); addRow(B, 'b2', 'phone', 1, {}, true)
    wallet(A, 10000); wallet(B, 10000)
    s = open()
    T.AddItem(101, s.id, 'a1', 1); T.AddItem(101, s.id, 'a2', 1); T.SetCash(101, s.id, 500)
    bothConfirm(s)
    check('items.destination_capacity_failure_moves_nothing', s.state == 'cancelled' and W[A] == 10000 and W[B] == 10000 and countRows(A) == 3 and countRows(B) == 2 and applied[s.id] == nil and journal(s.id) == nil)
    capRows[B] = nil; endAll()
    -- item changes after both want to confirm
    s = open()
    T.AddItem(101, s.id, 'a1', 5); T.SetCash(102, s.id, 100)
    T.Confirm(101, s.id, s.rev)
    inv[A]['a1'] = nil                                   -- the item disappears (used/dropped) before the last confirm
    bothConfirm(s)
    check('items.item_changed_after_confirmation_blocks_commit', s.state == 'cancelled' and W[B] == 10000 and W[A] == 10000 and journal(s.id) == nil)
    endAll()

    -- ---- CONFIRMATION ----------------------------------------------------------------------------------------------------------
    addRow(A, 'a1', 'water', 10, {}, true)
    s = open()
    local r0 = s.rev
    check('confirm.stale_revision_rejected', select(2, T.Confirm(101, s.id, r0 - 1)) == 'stale' and select(2, T.Confirm(101, s.id, 'x')) == 'stale' and select(2, T.Confirm(101, s.id, nil)) == 'stale')
    check('confirm.only_a', T.Confirm(101, s.id, s.rev) == true and s.confirmed[A] == true and s.confirmed[B] == nil and s.state == 'open')
    check('confirm.repeat_is_idempotent', T.Confirm(101, s.id, s.rev) == true and s.state == 'open')
    T.SetCash(102, s.id, 0)
    check('confirm.zero_change_does_not_reset', s.confirmed[A] == true)
    T.AddItem(102, s.id, 'zz', 1)
    T.AddItem(101, s.id, 'a1', 1)
    check('confirm.offer_change_resets_both', next(s.confirmed) == nil)
    T.ResetRateLimits()
    local spam = 0
    for _ = 1, 20 do if select(2, T.Confirm(102, s.id, -5)) == 'rate_limited' then spam = spam + 1 end end
    check('confirm.spam_rate_limited', spam > 0)
    T.ResetRateLimits()
    check('confirm.only_b', T.Confirm(102, s.id, s.rev) == true and s.confirmed[B] == true and s.state == 'open')
    check('confirm.spoofed_confirmation_rejected', select(2, T.Confirm(103, s.id, s.rev)) == 'invalid_state' and select(2, T.Confirm(999, s.id, s.rev)) == 'invalid_state')
    bothConfirm(s)
    check('confirm.both_commit', s.state == 'completed' and journal(s.id).status == 'completed')
    endAll()
    T.ResetRateLimits()
    s = open()
    local cancelSpam = 0
    for _ = 1, 12 do local ok = T.Cancel(101, s.id); if not ok then cancelSpam = cancelSpam + 1 end end
    check('confirm.cancel_is_final_and_idempotent', s.state == 'cancelled' and cancelSpam >= 11)

    -- ---- SECURITY ---------------------------------------------------------------------------------------------------------------
    endAll(); wallet(A, 10000); wallet(B, 10000); inv = {}; addRow(A, 'a1', 'water', 10, {}, true); addRow(B, 'b1', 'sandwich', 4, {}, true)
    s = open()
    check('security.cash_only_affects_callers_own_offer', T.SetCash(102, s.id, 77) == true and s.offers[A].cash == 0 and s.offers[B].cash == 77)
    check('security.view_never_contains_sources_or_accounts', (function()
        local v = T.View(s, A)
        local blob = json.encode(v)
        return not blob:find('"src"') and not blob:find('license') and not blob:find('identifier') and v.other.label == 'Stranger #9200002'
    end)())
    check('security.no_item_without_snapshot_ownership', select(2, T.AddItem(101, s.id, 'b1', 1)) == 'invalid_item')
    endAll()

    -- ---- ATOMICITY / SAGA --------------------------------------------------------------------------------------------------------
    local function fresh()
        endAll(); T.ResetRateLimits(); led = {}; applied = {}; inv = {}; failExec = false; failDebit = {}; failCredit = {}
        wallet(A, 10000); wallet(B, 10000)
        addRow(A, 'a1', 'water', 10, {}, true); addRow(A, 'a2', 'lockpick_adv', 1, { serial = 'SN-9' }, true); addRow(B, 'b1', 'sandwich', 4, {}, true)
    end
    local function totalCash() return (W[A] or 0) + (W[B] or 0) end
    fresh()
    s = open(); T.SetCash(101, s.id, 2000); T.SetCash(102, s.id, 1500); T.AddItem(101, s.id, 'a2', 1); T.AddItem(102, s.id, 'b1', 2)
    failDebit[B] = true
    bothConfirm(s)
    check('saga.money_failure_before_item_move_rolls_back', s.state == 'cancelled' and W[A] == 10000 and W[B] == 10000 and next(applied) == nil and inv[A]['a2'] ~= nil and journal(s.id).status == 'rolled_back')
    check('saga.rollback_refund_keyed_once', led[A .. '|add|' .. s.id .. ':refund'] == true and led[B .. '|add|' .. s.id .. ':refund'] == nil)
    fresh()
    s = open(); T.SetCash(101, s.id, 2000); T.SetCash(102, s.id, 1500); T.AddItem(101, s.id, 'a2', 1)
    failExec = true
    bothConfirm(s)
    check('saga.item_failure_after_debits_refunds_both', s.state == 'cancelled' and W[A] == 10000 and W[B] == 10000 and inv[A]['a2'] ~= nil and journal(s.id).status == 'rolled_back')
    check('saga.failure_tells_both_players', sentTo(101, 'cm-trade:client:ended') >= 1 and sentTo(102, 'cm-trade:client:ended') >= 1)
    -- crashes: reconcile from evidence
    local function reconcileFor(ref) return T.ReconcileOne(journal(ref)) end
    fresh()
    s = open(); T.SetCash(101, s.id, 2000); T.SetCash(102, s.id, 1500)
    T.TestCrashAt = 'debit_a'
    bothConfirm(s)
    check('saga.crash_between_debits_leaves_recoverable_journal', W[A] == 8000 and W[B] == 10000 and journal(s.id).status == 'needs_reconciliation')
    reconcileFor(s.id); reconcileFor(s.id)
    check('saga.reconcile_rolls_back_half_debit_once', W[A] == 10000 and W[B] == 10000 and journal(s.id).status == 'rolled_back')
    fresh()
    s = open(); T.SetCash(101, s.id, 2000); T.AddItem(101, s.id, 'a2', 1)
    T.TestCrashAt = 'debited'
    bothConfirm(s)
    check('saga.crash_before_pivot_reconciles_backward', W[A] == 8000 and next(applied) == nil)
    reconcileFor(s.id)
    check('saga.crash_before_pivot_refunds_and_keeps_items', W[A] == 10000 and inv[A]['a2'] ~= nil and journal(s.id).status == 'rolled_back')
    fresh()
    s = open(); T.SetCash(101, s.id, 2000); T.SetCash(102, s.id, 500); T.AddItem(101, s.id, 'a2', 1); T.AddItem(102, s.id, 'b1', 4)
    T.TestCrashAt = 'items_done'
    bothConfirm(s)
    check('saga.crash_after_pivot_has_items_moved_cash_held', applied[s.id] == true and W[A] == 8000 and W[B] == 9500 and journal(s.id).status == 'needs_reconciliation')
    reconcileFor(s.id); reconcileFor(s.id); reconcileFor(s.id)
    check('saga.crash_after_pivot_reconciles_forward_once', W[A] == 8500 and W[B] == 11500 and totalCash() == 20000 and journal(s.id).status == 'completed')
    check('saga.reconcile_repeats_do_not_duplicate_money', led[B .. '|add|' .. s.id .. ':credit'] == true and totalCash() == 20000)
    fresh()
    s = open(); T.SetCash(101, s.id, 1000); T.SetCash(102, s.id, 400)
    T.TestCrashAt = 'credit_leg'
    bothConfirm(s)
    reconcileFor(s.id); reconcileFor(s.id)
    check('saga.crash_mid_credit_completes_remaining_leg_only', totalCash() == 20000 and W[A] == 9400 and W[B] == 10600 and journal(s.id).status == 'completed')
    fresh()
    s = open(); T.SetCash(101, s.id, 1000)
    failCredit[B] = true
    bothConfirm(s)
    check('saga.credit_failure_keeps_value_in_journal', s.state == 'completed' and W[A] == 9000 and W[B] == 10000 and journal(s.id).status == 'needs_reconciliation')
    failCredit = {}
    reconcileFor(s.id); reconcileFor(s.id)
    check('saga.credit_failure_recovers_exactly_once', W[B] == 11000 and totalCash() == 20000 and journal(s.id).status == 'completed')
    fresh()
    s = open(); T.SetCash(101, s.id, 300)
    bothConfirm(s)
    local before = totalCash()
    check('saga.repeated_settlement_call_is_inert', select(2, T.Commit(s)) == 'invalid_state' and totalCash() == before and reconcileFor(s.id) ~= nil)
    fresh()
    s = open(); T.SetCash(101, s.id, 300); T.AddItem(101, s.id, 'a2', 1)
    T.P.items.status = function() return nil end
    T.TestCrashAt = 'debited'
    bothConfirm(s)
    check('saga.unavailable_inventory_owner_never_guesses', reconcileFor(s.id) == false and W[A] == 9700 and journal(s.id).status ~= 'rolled_back')
    T.P.items.status = function(ref) return applied[ref] and 'applied' or 'not_applied' end
    reconcileFor(s.id)
    check('saga.recovers_when_owner_returns', W[A] == 10000 and journal(s.id).status == 'rolled_back')
    -- exception inside settlement
    fresh()
    s = open(); T.SetCash(101, s.id, 100)
    T.TestCrashAt = 'debit_a'
    bothConfirm(s)
    check('saga.exception_marks_needs_reconciliation_and_closes_session', s.state == 'cancelled' and journal(s.id).status == 'needs_reconciliation' and T.byCid[A] == nil)

    -- ---- RESTART ---------------------------------------------------------------------------------------------------------------------
    fresh()
    s = open(); T.SetCash(101, s.id, 500)
    local openId = s.id
    T.sessions, T.byCid = {}, {}                           -- process restart: memory gone
    check('restart.open_trade_leaves_no_journal_and_no_lock', journal(openId) == nil and W[A] == 10000)
    endAll(); T.ResetRateLimits()
    local fresh1 = open()
    check('restart.players_can_trade_again', fresh1 ~= nil and fresh1.state == 'open')
    endAll()
    check('restart.reconcile_skips_terminal_journals', T.Reconcile() >= 0)

    -- teardown
    T.P.presence, T.P.money, T.P.items, T.P.identity = origP.presence, origP.money, origP.items, origP.identity
    TriggerClientEvent = origTrigger
    T.TestNoAdminLog = nil
    T.TestCrashAt = nil
    return total, failed
end

RegisterCommand('cm_trade_selftest', function(src)
    if src ~= 0 then return end
    if not enabled() then
        print('[cm-trade:selftest] refused: requires cm_environment=development')
        return
    end
    if not CMTrade.EnsureSchema() then
        print('[cm-trade:selftest] BLOCKED: schema not ready')
        return
    end
    cleanup()
    local saved = { presence = CMTrade.P.presence, money = CMTrade.P.money, items = CMTrade.P.items, identity = CMTrade.P.identity }
    local savedTrigger = TriggerClientEvent
    local ok, total, failed = pcall(run)
    CMTrade.P.presence, CMTrade.P.money, CMTrade.P.items, CMTrade.P.identity = saved.presence, saved.money, saved.items, saved.identity
    TriggerClientEvent = savedTrigger
    CMTrade.TestNoAdminLog, CMTrade.TestCrashAt = nil, nil
    local cleaned = pcall(cleanup)
    if not ok then
        print(('[cm-trade:selftest] ERROR %s'):format(tostring(total)))
        return
    end
    print(('[cm-trade:selftest] %d checks, %d failed, cleanup=%s'):format(total, failed, tostring(cleaned)))
end, true)
