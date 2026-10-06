-- cm-trade/server/core.lua
-- Server-owned trade sessions + a journaled settlement saga.
--
-- cm-trade COORDINATES a trade across the money owner (cm-playerdata) and the inventory owner (cm-inventory). It never
-- touches inventory SQL, never persists FiveM source ids, and never creates money or items.
--
-- Settlement is a saga with a pivot, NOT a single database transaction:
--   1. final revalidation (presence, bucket, distance, cash, items)
--   2. journal row (debiting)               -- from here on every step is resumable from evidence
--   3. debit each payer's cash              -- compensable: refunds keyed cm-trade:<ref>:refund
--   4. item exchange (PIVOT)                -- ONE transaction inside cm-inventory, idempotent per <ref>
--   5. credit each recipient (forward-only) -- offline-safe, idempotent per <ref>:credit evidence
-- Before the pivot a crash/failure rolls BACK (refund debits). After the pivot it only rolls FORWARD (credits).
-- The ledger reasons in economy_transactions (and the inventory exchange status) are the evidence for recovery.

CMTrade = CMTrade or {}
local T = CMTrade
T.sessions, T.byCid = {}, {}
local P = {}
T.P = P
local active = {}   -- [ref] = true while a live commit thread owns the journal row

local RESOURCE = GetCurrentResourceName()

-- ============================================================
-- Providers (replaced by test doubles in selftest.lua)
-- ============================================================

local function playerdata()
    if GetResourceState(Config.PlayerData) ~= 'started' then return nil end
    return exports[Config.PlayerData]
end

P.presence = {
    cidOf = function(src)
        local pd = playerdata()
        if not pd or not tonumber(src) then return nil end
        local ok, id = pcall(function() return pd:GetCharacterId(tonumber(src)) end)
        return ok and tonumber(id) or nil
    end,
    srcOf = function(cid)
        local pd = playerdata()
        if not pd then return nil end
        local ok, src = pcall(function() return pd:GetSourceByCharId(tonumber(cid)) end)
        return ok and tonumber(src) and tonumber(src) > 0 and tonumber(src) or nil
    end,
    bucket = function(src) return GetPlayerRoutingBucket(tonumber(src)) end,
    distance = function(a, b)
        local pa, pb = GetPlayerPed(tonumber(a)), GetPlayerPed(tonumber(b))
        if not pa or pa == 0 or not pb or pb == 0 then return nil end
        return #(GetEntityCoords(pa) - GetEntityCoords(pb))
    end,
    dead = function(src)
        local pd = playerdata()
        if not pd then return false end
        local ok, dead = pcall(function() return pd:IsDead(tonumber(src)) end)
        return ok and dead == true
    end,
}

P.identity = {
    -- Known players show their name; strangers show only their character id (no source ids, no account data).
    label = function(viewerCid, otherSrc, otherCid)
        local pd = playerdata()
        if pd then
            local okK, known = pcall(function() return pd:GetKnownIdentities(viewerCid) end)
            if okK and type(known) == 'table' and known[otherCid] then
                local okN, name = pcall(function() return pd:GetCharacterFullName(otherSrc) end)
                if okN and type(name) == 'string' and name ~= '' then return name:sub(1, 60) end
            end
        end
        return 'Stranger #' .. tostring(otherCid)
    end,
}

P.money = {
    cash = function(cid)
        local pd, src = playerdata(), P.presence.srcOf(cid)
        if not pd or not src then return nil end
        local ok, v = pcall(function() return pd:GetCash(src) end)
        return ok and tonumber(v) or nil
    end,
    debit = function(cid, amount, reason)
        local pd, src = playerdata(), P.presence.srcOf(cid)
        if not pd or not src then return false end
        local ok, r = pcall(function() return pd:RemoveCash(src, amount, reason) end)
        return ok and r == true
    end,
    credit = function(cid, amount, reason)
        local pd = playerdata()
        if not pd then return false end
        local ok, r = pcall(function() return pd:AddMoneyToCharacter(cid, Config.Money.Account, amount, reason, { resource = 'cm-trade' }) end)
        return ok and r == true
    end,
    -- True when the ledger already holds this movement (crash recovery must never repeat a leg).
    evidence = function(cid, action, reason)
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM economy_transactions WHERE character_id = ? AND action = ? AND reason = ?', { cid, action, reason })
        return (tonumber(n) or 0) > 0
    end,
}

-- Item settlement uses the cm-inventory exchange contract (docs/SHARED_INTEGRATION.md). Absent contract = items disabled (fail closed).
local itemProbe = { at = 0, ok = false }
local function inventory()
    if GetResourceState(Config.Inventory) ~= 'started' then return nil end
    return exports[Config.Inventory]
end
P.items = {
    enabled = function()
        if Config.Items.Enabled == false then return false end
        if os.time() - itemProbe.at > 30 then
            local inv = inventory()
            local ok = false
            if inv then ok = (pcall(function() return inv:GetItemExchangeStatus('cm-trade-probe') end)) end
            itemProbe = { at = os.time(), ok = ok }
        end
        return itemProbe.ok
    end,
    snapshot = function(cid)
        local inv = inventory()
        if not inv then return nil end
        local ok, list = pcall(function() return inv:GetTradeSnapshot(cid) end)
        return ok and type(list) == 'table' and list or nil
    end,
    validate = function(ref, a, b)
        local inv = inventory()
        if not inv then return false, 'items_unavailable' end
        local ok, res, why = pcall(function() return inv:ValidateItemExchange(ref, a, b) end)
        if not ok then return false, 'items_unavailable' end
        return res == true, why
    end,
    execute = function(ref, a, b)
        local inv = inventory()
        if not inv then return false, 'items_unavailable' end
        local ok, res, why = pcall(function() return inv:ExecuteItemExchange(ref, a, b) end)
        if not ok then return false, 'items_unavailable' end
        return res == true, why
    end,
    -- cm-inventory status contract (the owner decides; cm-trade never infers):
    --   committed     -> 'applied'        the item transaction committed: settlement only moves FORWARD
    --   not_applied   -> 'not_applied'    TERMINAL: no item mutation can ever commit under this reference -> the only state that allows a cash refund
    --   pending       -> 'pending'        claimed/in flight/lease not expired: NEVER refund, re-execute or wait
    --   not_submitted -> 'not_submitted'  the owner never saw the reference: NOT proof (a call may still be in flight) -> fence it first
    --   anything else (unknown, false, 'forbidden', RPC failure, resource down) -> nil: decide later, never guess
    status = function(ref)
        local inv = inventory()
        if not inv then return nil end
        local ok, s = pcall(function() return inv:GetItemExchangeStatus(ref) end)
        if not ok then return nil end
        if s == 'committed' or s == 'applied' then return 'applied' end
        if s == 'not_applied' or s == 'pending' or s == 'not_submitted' then return s end
        return nil
    end,
    -- Asks the owner to make `not_applied` permanent for a reference that was never submitted (or whose executor is provably gone).
    fence = function(ref)
        local inv = inventory()
        if not inv then return nil end
        local ok, s = pcall(function() return inv:FenceItemExchange(ref) end)
        if not ok then return nil end
        if s == 'committed' then return 'applied' end
        if s == 'not_applied' or s == 'pending' then return s end
        return nil
    end,
}

-- ============================================================
-- Helpers
-- ============================================================

local hits = {}
function T.RateLimited(cid, bucket)
    local cfg = Config.RateLimits[bucket]
    if not cfg then return false end
    local key, now = tostring(cid) .. ':' .. bucket, os.time()
    local kept = {}
    for _, t in ipairs(hits[key] or {}) do if now - t < cfg[2] then kept[#kept + 1] = t end end
    if #kept >= cfg[1] then hits[key] = kept; return true end
    kept[#kept + 1] = now
    hits[key] = kept
    return false
end
function T.ResetRateLimits() hits = {} end

local function notify(src, message, kind)
    if not src then return end
    if GetResourceState('cm-hud') == 'started' then
        TriggerClientEvent('cm-hud:client:notify', src, tostring(message or ''), kind or 'info')
    end
end

local function encode(t)
    local ok, s = pcall(json.encode, t or {})
    return ok and s:sub(1, 1500) or '{}'
end

local CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function newRef()
    local out = {}
    for i = 1, 8 do local k = math.random(1, #CHARS); out[i] = CHARS:sub(k, k) end
    return 'TRD-' .. table.concat(out)
end

local function logEvent(ref, kind, cidA, cidB, meta)
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_trade_events (session_ref, kind, char_a, char_b, metadata) VALUES (?, ?, ?, ?, ?)', { ref, kind, cidA, cidB, meta and encode(meta) or nil })
    end)
end

local function adminLog(action, src, data)
    if T.TestNoAdminLog or GetResourceState('cm-admin') ~= 'started' then return end
    pcall(function() exports['cm-admin']:AddLog(src or 0, action, data) end)
end

local MESSAGES = {
    busy = 'One of you is already in a trade.', too_far = 'You are too far apart.', rate_limited = 'Slow down.', invalid_target = 'Invalid person.',
    wrong_bucket = 'You are not in the same place.', dead = 'You cannot trade right now.', expired = 'The trade request expired.', declined = 'The trade was declined.',
    cancelled = 'The trade was cancelled.', separated = 'The trade was cancelled because you moved apart.', disconnected = 'The other person left.',
    insufficient_cash = 'Not enough cash.', invalid_amount = 'Invalid amount.', items_disabled = 'Item trading is not available yet.',
    invalid_item = 'That item cannot be offered.', insufficient_quantity = 'Not enough of that item.', not_tradeable = 'That item cannot be traded.', too_many_lines = 'Too many items.',
    pending = 'The trade is being finalised. It will settle automatically.', stale = 'The offer changed. Review it again.', invalid_state = 'Not possible right now.', timeout = 'The trade timed out.', failed = 'The trade could not be completed. Nothing was exchanged.',
    items_failed = 'An item could not be exchanged. Nothing was exchanged.', cash_failed = 'Payment failed. Nothing was exchanged.',
}
T.MESSAGES = MESSAGES

-- ============================================================
-- Presence / validation
-- ============================================================

local function denied(name)
    name = tostring(name or ''):lower()
    for _, pat in ipairs(Config.Items.DenyPatterns) do
        if name:find(pat) then return true end
    end
    return false
end
T.IsDeniedItem = denied

-- Both sides must still be the same loaded characters on the same sources, same bucket, in range, alive.
local function checkPresence(s, maxDistance)
    for _, who in ipairs({ s.a, s.b }) do
        if P.presence.cidOf(who.src) ~= who.cid then return false, 'disconnected' end
        if Config.Session.CancelOnDeath and P.presence.dead(who.src) then return false, 'dead' end
    end
    if P.presence.bucket(s.a.src) ~= P.presence.bucket(s.b.src) then return false, 'wrong_bucket' end
    local d = P.presence.distance(s.a.src, s.b.src)
    if d == nil or d > maxDistance then return false, 'too_far' end
    return true
end

local function side(s, cid) if s.a.cid == cid then return s.a, s.b end if s.b.cid == cid then return s.b, s.a end end

-- ============================================================
-- Views
-- ============================================================

local function offerView(offer)
    local items = {}
    for _, l in ipairs(offer.items) do
        items[#items + 1] = { ref = l.ref, label = l.label, image = l.image, quantity = l.quantity, summary = l.summary }
    end
    return { cash = offer.cash, items = items }
end

function T.View(s, cid)
    local me, other = side(s, cid)
    if not me then return nil end
    return {
        id = s.id, state = s.state, rev = s.rev,
        you = { offer = offerView(s.offers[me.cid]), confirmed = s.confirmed[me.cid] == true },
        other = { label = P.identity.label(me.cid, other.src, other.cid), offer = offerView(s.offers[other.cid]), confirmed = s.confirmed[other.cid] == true },
        caps = { items = P.items.enabled() == true, maxCash = Config.Limits.MaxCash, maxLines = Config.Limits.MaxItemLines, maxQuantity = Config.Limits.MaxQuantityPerLine },
        wallet = P.money.cash(me.cid),
    }
end

local function push(s, extra)
    for _, who in ipairs({ s.a, s.b }) do
        local v = T.View(s, who.cid)
        if v then
            if extra then for k, val in pairs(extra) do v[k] = val end end
            TriggerClientEvent('cm-trade:client:state', who.src, v)
        end
    end
end

-- ============================================================
-- Session lifecycle
-- ============================================================

local function release(s)
    if T.byCid[s.a.cid] == s.id then T.byCid[s.a.cid] = nil end
    if T.byCid[s.b.cid] == s.id then T.byCid[s.b.cid] = nil end
end

-- Terminal (nothing moved). Never valid once committing started.
function T.CancelSession(s, reason, notifyBoth)
    if not s or (s.state ~= 'invited' and s.state ~= 'open') then return false, 'invalid_state' end
    s.state = 'cancelled'
    s.endReason = reason
    release(s)
    logEvent(s.id, 'cancelled', s.a.cid, s.b.cid, { reason = reason })
    for _, who in ipairs({ s.a, s.b }) do
        TriggerClientEvent('cm-trade:client:ended', who.src, { id = s.id, outcome = 'cancelled', message = MESSAGES[reason] or MESSAGES.cancelled })
    end
    return true
end

function T.Invite(srcA, srcB)
    srcA, srcB = tonumber(srcA), tonumber(srcB)
    local cidA, cidB = P.presence.cidOf(srcA), P.presence.cidOf(srcB)
    if not srcA or not srcB or srcA == srcB or not cidA or not cidB or cidA == cidB then return false, 'invalid_target' end
    if T.RateLimited(cidA, 'invite') then return false, 'rate_limited' end
    if T.byCid[cidA] or T.byCid[cidB] then return false, 'busy' end
    local s = {
        id = newRef(), state = 'invited', rev = 1, createdAt = os.time(), expiresAt = os.time() + Config.Invite.ExpirySeconds,
        a = { cid = cidA, src = srcA }, b = { cid = cidB, src = srcB }, confirmed = {},
        offers = { [cidA] = { cash = 0, items = {} }, [cidB] = { cash = 0, items = {} } },
    }
    local okP, why = checkPresence(s, Config.Invite.MaxDistance)
    if not okP then return false, why end
    T.sessions[s.id] = s
    T.byCid[cidA], T.byCid[cidB] = s.id, s.id
    logEvent(s.id, 'invited', cidA, cidB)
    TriggerClientEvent('cm-trade:client:invite', srcB, { id = s.id, from = P.identity.label(cidB, srcA, cidA), expiresIn = Config.Invite.ExpirySeconds })
    notify(srcA, 'Trade request sent.', 'info')
    return true, s.id
end

function T.Respond(src, id, accept)
    local s = type(id) == 'string' and T.sessions[id] or nil
    local cid = P.presence.cidOf(src)
    if not s or not cid or s.b.cid ~= cid or s.b.src ~= tonumber(src) then return false, 'invalid_state' end
    if s.state ~= 'invited' then return false, 'invalid_state' end
    if os.time() > s.expiresAt then T.CancelSession(s, 'expired'); return false, 'expired' end
    if accept ~= true then T.CancelSession(s, 'declined'); return true, 'declined' end
    local okP, why = checkPresence(s, Config.Invite.MaxDistance)
    if not okP then T.CancelSession(s, why); return false, why end
    s.state = 'open'
    s.openedAt = os.time()
    logEvent(s.id, 'accepted', s.a.cid, s.b.cid)
    for _, who in ipairs({ s.a, s.b }) do TriggerClientEvent('cm-trade:client:open', who.src, T.View(s, who.cid)) end
    return true, 'open'
end

-- Resolves the session for a caller and proves the caller is one of its two registered participants.
local function participant(src, id, states)
    local s = type(id) == 'string' and T.sessions[id] or nil
    local cid = P.presence.cidOf(src)
    if not s or not cid then return nil, 'invalid_state' end
    local me = side(s, cid)
    if not me or me.src ~= tonumber(src) then return nil, 'invalid_state' end
    if states and not states[s.state] then return nil, 'invalid_state' end
    return s, nil, cid
end
T.Participant = participant

local function touch(s)
    s.rev = s.rev + 1
    s.confirmed = {}
end

function T.SetCash(src, id, amount)
    local s, why, cid = participant(src, id, { open = true })
    if not s then return false, why end
    if T.RateLimited(cid, 'offer') then return false, 'rate_limited' end
    if type(amount) ~= 'number' or amount ~= amount or amount ~= math.floor(amount) or amount < 0 or amount > Config.Limits.MaxCash then return false, 'invalid_amount' end
    local wallet = P.money.cash(cid)
    if not wallet or wallet < amount then return false, 'insufficient_cash' end
    if s.offers[cid].cash ~= amount then s.offers[cid].cash = amount; touch(s) end
    push(s)
    return true
end

function T.AddItem(src, id, ref, quantity)
    local s, why, cid = participant(src, id, { open = true })
    if not s then return false, why end
    if T.RateLimited(cid, 'offer') then return false, 'rate_limited' end
    if not P.items.enabled() then return false, 'items_disabled' end
    if type(ref) ~= 'string' or #ref < 1 or #ref > 64 or not ref:match('^[%w_%-:]+$') then return false, 'invalid_item' end
    if type(quantity) ~= 'number' or quantity ~= math.floor(quantity) or quantity < 1 or quantity > Config.Limits.MaxQuantityPerLine then return false, 'invalid_amount' end
    local offer = s.offers[cid]
    local existing
    for _, l in ipairs(offer.items) do if l.ref == ref then existing = l end end
    if not existing and #offer.items >= Config.Limits.MaxItemLines then return false, 'too_many_lines' end
    local snap = P.items.snapshot(cid)
    if not snap then return false, 'items_disabled' end
    local row
    for _, r in ipairs(snap) do if tostring(r.ref) == ref then row = r break end end
    if not row then return false, 'invalid_item' end
    if row.tradeable == false or denied(row.item) then return false, 'not_tradeable' end
    if quantity > (tonumber(row.quantity) or 0) then return false, 'insufficient_quantity' end
    local line = { ref = ref, item = tostring(row.item), label = tostring(row.label or row.item):sub(1, 60), image = row.image and tostring(row.image) or nil, quantity = quantity, summary = row.summary and tostring(row.summary):sub(1, 80) or nil,
        fp = row.fp and tostring(row.fp):sub(1, 16) or nil }   -- server-side only: the inventory refuses the exchange if the row's item/metadata changed since this snapshot
    if existing then
        if existing.quantity == quantity then return true end
        for i, l in ipairs(offer.items) do if l.ref == ref then offer.items[i] = line end end
    else
        offer.items[#offer.items + 1] = line
    end
    touch(s)
    push(s)
    return true
end

function T.RemoveItem(src, id, ref)
    local s, why, cid = participant(src, id, { open = true })
    if not s then return false, why end
    if T.RateLimited(cid, 'offer') then return false, 'rate_limited' end
    local offer = s.offers[cid]
    for i, l in ipairs(offer.items) do
        if l.ref == ref then
            table.remove(offer.items, i)
            touch(s)
            push(s)
            return true
        end
    end
    return false, 'invalid_item'
end

function T.Confirm(src, id, rev)
    local s, why, cid = participant(src, id, { open = true })
    if not s then return false, why end
    if T.RateLimited(cid, 'confirm') then return false, 'rate_limited' end
    if rev ~= s.rev then return false, 'stale' end
    if s.confirmed[cid] then return true end
    s.confirmed[cid] = true
    logEvent(s.id, 'confirmed', cid, nil, { rev = s.rev })
    push(s)
    if s.confirmed[s.a.cid] and s.confirmed[s.b.cid] then
        return T.Commit(s)
    end
    return true
end

function T.Cancel(src, id)
    local s, why, cid = participant(src, id, { invited = true, open = true })
    if not s then return false, why end
    if T.RateLimited(cid, 'cancel') then return false, 'rate_limited' end
    local other = select(2, side(s, cid))
    local ok = T.CancelSession(s, 'cancelled')
    if ok then notify(other.src, 'The other person cancelled the trade.', 'info') end
    return ok
end

-- ============================================================
-- Settlement saga
-- ============================================================

-- Development self-test crash injection (set only by server/selftest.lua).
local function crashAt(point)
    if T.TestCrashAt == point then
        T.TestCrashAt = nil
        error('cm-trade test crash at ' .. point)
    end
end

local function setStatus(ref, status, detail)
    MySQL.update.await('UPDATE cm_trade_transactions SET status = ?, detail = ?, completed_at = IF(? IN (\'completed\',\'rolled_back\'), UTC_TIMESTAMP(), completed_at) WHERE reference = ?', { status, detail, status, ref })
end

local function itemSides(s)
    local function lines(cid)
        local out = {}
        for _, l in ipairs(s.offers[cid].items) do out[#out + 1] = { ref = l.ref, quantity = l.quantity, fp = l.fp } end
        return { characterId = cid, lines = out }
    end
    return lines(s.a.cid), lines(s.b.cid)
end

local function creditOnce(cid, amount, reason)
    if amount <= 0 then return true end
    if P.money.evidence(cid, 'add', reason) then return true end
    return P.money.credit(cid, amount, reason) == true
end

local function refundLeg(ref, cid, amount)
    if amount <= 0 then return true end
    if not P.money.evidence(cid, 'remove', ref .. ':debit') then return true end   -- nothing was taken
    return creditOnce(cid, amount, ref .. ':refund')
end

-- Final revalidation immediately before anything moves.
function T.Revalidate(s)
    local okP, why = checkPresence(s, Config.Session.MaxDistance)
    if not okP then return false, why end
    for _, who in ipairs({ s.a, s.b }) do
        local cash = s.offers[who.cid].cash
        if cash > 0 then
            local wallet = P.money.cash(who.cid)
            if not wallet or wallet < cash then return false, 'insufficient_cash' end
        end
    end
    local ia, ib = itemSides(s)
    if #ia.lines > 0 or #ib.lines > 0 then
        if not P.items.enabled() then return false, 'items_disabled' end
        for _, sd in ipairs({ { s.a, ia }, { s.b, ib } }) do
            for _, l in ipairs(s.offers[sd[1].cid].items) do
                if denied(l.item) then return false, 'not_tradeable' end
            end
        end
        local okI, whyI = P.items.validate(s.id, ia, ib)
        if not okI then return false, 'items_failed', whyI end
    end
    return true
end

local function finishSession(s, outcome, reason)
    release(s)
    s.state = outcome == 'completed' and 'completed' or 'cancelled'
    s.endReason = reason
    for _, who in ipairs({ s.a, s.b }) do
        TriggerClientEvent('cm-trade:client:ended', who.src, { id = s.id, outcome = outcome, message = outcome == 'completed' and 'Trade complete.' or (MESSAGES[reason] or MESSAGES.failed) })
    end
end

function T.Commit(s)
    if s.state ~= 'open' or active[s.id] then return false, 'invalid_state' end
    s.state = 'committing'            -- synchronous: no second confirm can enter
    active[s.id] = true
    push(s)
    local ok, result = pcall(T.Settle, s)
    active[s.id] = nil
    if not ok then
        if not tostring(result):find('test crash', 1, true) then print(('[cm-trade] settlement error for %s: %s'):format(s.id, tostring(result))) end
        pcall(setStatus, s.id, 'needs_reconciliation', 'exception')
        finishSession(s, 'cancelled', 'failed')
        return false, 'failed'
    end
    return result == true, s.endReason
end

function T.Settle(s)
    local ok, why = T.Revalidate(s)
    if not ok then
        finishSession(s, 'cancelled', why)
        logEvent(s.id, 'settlement_rejected', s.a.cid, s.b.cid, { reason = why })
        return false
    end
    local cashA, cashB = s.offers[s.a.cid].cash, s.offers[s.b.cid].cash
    local ia, ib = itemSides(s)
    local lineCount = #ia.lines + #ib.lines
    local ref = s.id
    MySQL.insert.await("INSERT INTO cm_trade_transactions (reference, char_a, char_b, cash_a, cash_b, item_lines, items_json, status) VALUES (?, ?, ?, ?, ?, ?, ?, 'debiting')",
        { ref, s.a.cid, s.b.cid, cashA, cashB, lineCount, encode({ a = ia.lines, b = ib.lines }) })

    local function rollback(reason)
        refundLeg(ref, s.a.cid, cashA)
        refundLeg(ref, s.b.cid, cashB)
        setStatus(ref, 'rolled_back', reason)
        logEvent(ref, 'rolled_back', s.a.cid, s.b.cid, { reason = reason })
        adminLog('trade_rolled_back', s.a.src, { category = 'trade', reference = ref, reason = reason })
        finishSession(s, 'cancelled', reason == 'items' and 'items_failed' or 'cash_failed')
        return false
    end

    -- 3. debits (compensable)
    if cashA > 0 and not P.money.debit(s.a.cid, cashA, ref .. ':debit') then return rollback('cash') end
    crashAt('debit_a')
    if cashB > 0 and not P.money.debit(s.b.cid, cashB, ref .. ':debit') then return rollback('cash') end
    setStatus(ref, 'debited')
    crashAt('debited')

    -- 4. pivot: the single item exchange
    if lineCount > 0 then
        logEvent(ref, 'items_submitted', s.a.cid, s.b.cid)
        local okI = P.items.execute(ref, ia, ib)
        if not okI then
            -- A failed/ambiguous exchange is only rolled back when the owner proves it can never apply (terminal not_applied).
            -- pending / not_submitted / owner unavailable are NOT proof: keep the cash debited and hand the trade to reconciliation.
            local st = P.items.status(ref)
            if st == 'applied' then
                logEvent(ref, 'items_applied_after_error', s.a.cid, s.b.cid)
            elseif st == 'not_applied' then
                return rollback('items')
            else
                setStatus(ref, 'needs_reconciliation', 'items_pending')
                logEvent(ref, 'items_pending', s.a.cid, s.b.cid, { owner = st or 'unreachable' })
                adminLog('trade_items_pending', s.a.src, { category = 'trade', reference = ref, characterA = s.a.cid, characterB = s.b.cid })
                finishSession(s, 'cancelled', 'pending')
                return false
            end
        end
    end
    setStatus(ref, 'items_done')
    crashAt('items_done')

    -- 5. forward-only credits
    local credited = true
    for _, leg in ipairs({ { s.b.cid, cashA }, { s.a.cid, cashB } }) do
        local done = false
        for attempt = 1, 3 do
            if creditOnce(leg[1], leg[2], ref .. ':credit') then done = true break end
            Wait(250)
        end
        if not done then credited = false end
        crashAt('credit_leg')
    end
    if not credited then
        setStatus(ref, 'needs_reconciliation', 'credit_pending')
        logEvent(ref, 'credit_pending', s.a.cid, s.b.cid)
    else
        setStatus(ref, 'completed')
    end
    logEvent(ref, 'completed', s.a.cid, s.b.cid, { cashAtoB = cashA, cashBtoA = cashB, lines = lineCount })
    adminLog('trade_completed', s.a.src, { category = 'trade', reference = ref, characterA = s.a.cid, characterB = s.b.cid, cashAtoB = cashA, cashBtoA = cashB, itemLines = lineCount })
    finishSession(s, 'completed')
    return true
end

-- Recovery from evidence. Idempotent; safe to run repeatedly and after restarts.
function T.ReconcileOne(row)
    local ref = row.reference
    if active[ref] then return false end
    local cashA, cashB = tonumber(row.cash_a) or 0, tonumber(row.cash_b) or 0
    local cidA, cidB = tonumber(row.char_a), tonumber(row.char_b)
    local needItems = (tonumber(row.item_lines) or 0) > 0
    local itemsApplied = false
    local debitedA = cashA <= 0 or P.money.evidence(cidA, 'remove', ref .. ':debit')
    local debitedB = cashB <= 0 or P.money.evidence(cidB, 'remove', ref .. ':debit')
    if needItems then
        local st = P.items.status(ref)
        if st == nil then return false end                      -- owner unavailable: decide later, never guess
        if st == 'not_submitted' then
            -- The owner has never claimed this reference. That is not proof: a call may still be queued. Fence it (terminal not_applied).
            st = P.items.fence(ref)
            if st == nil then return false end
            if st == 'not_applied' then logEvent(ref, 'items_fenced_not_applied', cidA, cidB) end
        end
        if st == 'pending' then
            -- Claimed by an executor that may still be running. Never refund. Re-submit under the SAME reference: the owner reclaims a
            -- stale lease (exactly one executor wins) or answers pending while a live one still owns it.
            if debitedA and debitedB then
                local okJ, saved = pcall(json.decode, row.items_json or '')
                if okJ and type(saved) == 'table' and type(saved.a) == 'table' and type(saved.b) == 'table' then
                    local okE = P.items.execute(ref, { characterId = cidA, lines = saved.a }, { characterId = cidB, lines = saved.b })
                    st = P.items.status(ref)
                    if okE and st == 'applied' then logEvent(ref, 'items_reexecuted', cidA, cidB) end
                end
            end
            if st == 'pending' or st == nil then
                if row.detail ~= 'items_pending' then
                    setStatus(ref, 'needs_reconciliation', 'items_pending')
                    logEvent(ref, 'items_pending', cidA, cidB, { by = 'reconcile' })
                end
                return false
            end
        end
        itemsApplied = st == 'applied'
        if not itemsApplied then logEvent(ref, 'compensation_started', cidA, cidB, { reason = 'items_not_applied' }) end
    end
    local forward = (not needItems and debitedA and debitedB and row.status ~= 'rolled_back') or itemsApplied
    if forward and not (debitedA and debitedB) then
        -- cannot happen (items run after both debits); refuse to guess
        setStatus(ref, 'needs_reconciliation', 'inconsistent')
        return false
    end
    if forward then
        if itemsApplied and row.detail == 'items_pending' then logEvent(ref, 'forward_settlement_resumed', cidA, cidB) end
        local ok = creditOnce(cidB, cashA, ref .. ':credit') and creditOnce(cidA, cashB, ref .. ':credit')
        if ok then setStatus(ref, 'completed', 'reconciled'); logEvent(ref, 'reconciled_completed', cidA, cidB); return true end
        setStatus(ref, 'needs_reconciliation', 'credit_pending')
        return false
    end
    local ok = refundLeg(ref, cidA, cashA) and refundLeg(ref, cidB, cashB)
    if ok then setStatus(ref, 'rolled_back', 'reconciled'); logEvent(ref, 'reconciled_rolled_back', cidA, cidB); return true end
    setStatus(ref, 'needs_reconciliation', 'refund_pending')
    return false
end

function T.Reconcile()
    local rows = MySQL.query.await("SELECT * FROM cm_trade_transactions WHERE status IN ('debiting','debited','items_done','needs_reconciliation') AND updated_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL ? SECOND) ORDER BY id LIMIT 50", { Config.Reconcile.StaleSeconds }) or {}
    local fixed = 0
    for _, row in ipairs(rows) do
        local ok, res = pcall(T.ReconcileOne, row)
        if ok and res then fixed = fixed + 1 end
    end
    return fixed
end

-- ============================================================
-- Disconnect / distance / expiry watcher
-- ============================================================

function T.DropPlayer(src)
    for _, s in pairs(T.sessions) do
        if (s.state == 'invited' or s.state == 'open') and (s.a.src == tonumber(src) or s.b.src == tonumber(src)) then
            local other = s.a.src == tonumber(src) and s.b or s.a
            T.CancelSession(s, 'disconnected')
            notify(other.src, MESSAGES.disconnected, 'info')
        end
    end
end

function T.Tick()
    local now = os.time()
    for id, s in pairs(T.sessions) do
        if s.state == 'invited' then
            if now > s.expiresAt then T.CancelSession(s, 'expired') end
        elseif s.state == 'open' then
            if now - s.createdAt > Config.Session.MaxMinutes * 60 then
                T.CancelSession(s, 'timeout')
            else
                local okP, why = checkPresence(s, Config.Session.CancelDistance)
                if not okP then T.CancelSession(s, why == 'too_far' and 'separated' or why) end
            end
        elseif s.state == 'completed' or s.state == 'cancelled' then
            T.sessions[id] = nil
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.Session.CheckIntervalMs)
        pcall(T.Tick)
    end
end)

CreateThread(function()
    Wait(6000)
    pcall(T.Reconcile)
    while true do
        Wait(Config.Reconcile.IntervalSeconds * 1000)
        pcall(T.Reconcile)
    end
end)

AddEventHandler('playerDropped', function() T.DropPlayer(source) end)
