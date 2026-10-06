-- Invoice payment: recipient -> deduction -> destination. Exactly-once settlement:
--   1. a process lock per invoice (fast rejection of double clicks; NOT the correctness mechanism),
--   2. a DB claim pending -> settling guarded by status/recipient/amount/expiry (cross-instance safe),
--   3. debit the payer through the money owner (cm-playerdata operation journal, unique reference cm-billing-pay-debit:<invoice>),
--   4. credit the destination through ITS owner with a unique reference (character: cm-playerdata journal; family: cm-family treasury journal;
--      business: cm-commercial-ownership idempotency key; city = sink),
--   5. settling -> paid (token-guarded).
-- Every owner step is exactly-once by a stable reference, so recovery never guesses: it asks the owner's durable operation status (never a generic
-- transaction log) and re-issues the SAME reference. An owner that cannot answer leaves the invoice `settling` (unknown is never "not applied").
-- Definitive destination failure: the payer is refunded exactly once (cm-billing-pay-refund:<invoice>) and the invoice returns to pending.
-- A destination that accepted less than requested (family capacity) returns the remainder exactly once (cm-billing-pay-remainder:<invoice>);
-- the accepted amount is authoritative and is recorded in settlement_note as partial_refund_<remainder>.
local S = CMBilling.Server
local Config = CMBilling.Config

-- Owner operation references (distinct namespaces and directions; refund references live in refund.lua: cm-billing-rfd-*).
function S.PayKeys(reference)
    return {
        debit = 'cm-billing-pay-debit:' .. reference,
        credit = 'cm-billing-pay-credit:' .. reference,
        refund = 'cm-billing-pay-refund:' .. reference,
        remainder = 'cm-billing-pay-remainder:' .. reference,
    }
end

local function ownerStatus(reference)
    local api = S.playerData()
    if not api then error('character money journal unavailable') end
    local op, why = api:GetCharacterMoneyOperation(reference)
    if op == nil then error('character money journal ' .. tostring(why)) end
    return op ~= false and op or false
end

-- Ledger evidence adapters (replaced by the self-test). Durable OWNER status, never generic transaction-log text.
-- Return true/false; raise when the owner cannot answer.
S.Ledger = {
    HasDebit = function(cid, reference)
        local op = ownerStatus(S.PayKeys(reference).debit)
        return op ~= false and op.direction == 'debit' and op.characterId == tostring(cid)
    end,
    HasRefund = function(cid, reference)
        local op = ownerStatus(S.PayKeys(reference).refund)
        return op ~= false and op.direction == 'credit' and op.characterId == tostring(cid)
    end,
}

local function release(row, token, note)
    MySQL.update.await("UPDATE cm_billing_invoices SET status = 'pending', settle_token = '', settle_started_at = NULL, payment_account = '', settlement_note = ? WHERE id = ? AND settle_token = ? AND status = 'settling'",
        { note or '', row.id, token })
end

local function markPaid(row, token, account, note)
    local changed = MySQL.update.await("UPDATE cm_billing_invoices SET status = 'paid', paid_at = CURRENT_TIMESTAMP, payment_account = ?, settlement_note = ?, settle_token = '' WHERE id = ? AND settle_token = ? AND status = 'settling'",
        { account, note or '', row.id, token })
    return (tonumber(changed) or 0) > 0
end

local function note(row, token, text)
    MySQL.update.await("UPDATE cm_billing_invoices SET settlement_note = ? WHERE id = ? AND settle_token = ? AND status = 'settling'", { text, row.id, token })
end

-- Credit the payer back through the owner journal. Returns true | false, 'failed' (definitive) | false, 'unknown'.
local function giveBack(cid, account, amount, key, reference)
    local called, ok, why = pcall(S.Money.CreditCharacter, cid, account, amount, key, { invoice = reference })
    if called and ok == true then return true end
    if called and why ~= 'unavailable' and why ~= 'busy' and ok ~= nil then return false, 'failed' end
    return false, 'unknown'
end

-- destination credit outcome: 'credited', accepted | 'failed' | 'unknown'
local function creditDestination(adapter, row, account)
    local called, a, b = pcall(adapter.credit, row, account)
    if called and a == true then return 'credited', type(b) == 'number' and b or tonumber(row.amount) end
    if called and a == false then return 'failed' end
    return 'unknown'
end

-- The accepted amount is authoritative; any remainder goes back to the payer exactly once. Returns 'done' | 'pending'.
local function settleRemainder(cid, account, row, accepted)
    local amount = tonumber(row.amount)
    if accepted >= amount then return 'done', '' end
    local remainder = amount - accepted
    if giveBack(cid, account, remainder, S.PayKeys(row.public_reference).remainder, row.public_reference) then
        return 'done', 'partial_refund_' .. remainder
    end
    return 'pending', remainder
end

local function settle(cid, src, row, account)
    local reference = row.public_reference
    local amount = tonumber(row.amount)
    local keys = S.PayKeys(reference)
    local token = ('%s-%d-%d'):format(reference, GetGameTimer(), math.random(1, 999999))

    local claimed = MySQL.update.await([[UPDATE cm_billing_invoices
        SET status = 'settling', settle_token = ?, settle_started_at = CURRENT_TIMESTAMP, payment_account = ?
        WHERE id = ? AND status = 'pending' AND recipient_character_id = ? AND amount = ?
          AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)]], { token, account, row.id, tostring(cid), amount })
    if (tonumber(claimed) or 0) < 1 then return false, 'not_pending' end
    S.EventLog(row.id, 'settling', tostring(cid), account)

    local destType = row.destination_type
    local adapter = S.Destinations[destType]
    local destCfg = Config.Destinations[destType]
    if not adapter or not destCfg or destCfg.available ~= true or not adapter.available() or not adapter.validate(row.destination_id, cid) then
        release(row, token, 'destination_unavailable')
        return false, 'destination_unavailable'
    end

    local debited, whyDebit = S.Money.Debit(src, account, amount, keys.debit, cid)
    if debited ~= true then
        if whyDebit == 'unavailable' then
            -- The owner could not answer: the payer may or may not have been charged. Stay settling; recovery asks the owner journal.
            note(row, token, 'debit_outcome_unknown')
            S.EventLog(row.id, 'settle_pending', 'cm-billing', 'debit_unknown')
            return false, 'settlement_pending'
        end
        release(row, token, 'insufficient_funds')
        return false, 'insufficient_funds'
    end

    local outcome, accepted = creditDestination(adapter, row, account)
    if outcome == 'unknown' then
        -- NEVER refund on an unknown outcome: the destination may already have been credited.
        note(row, token, 'credit_outcome_unknown')
        S.EventLog(row.id, 'settle_pending', 'cm-billing', 'credit_unknown')
        return false, 'settlement_pending'
    end
    if outcome == 'failed' then
        local refunded, kind = giveBack(cid, account, amount, keys.refund, reference)
        if refunded then
            release(row, token, 'credit_failed_refunded')
            S.EventLog(row.id, 'settle_failed', 'cm-billing', 'refunded')
            return false, 'settlement_failed'
        end
        note(row, token, kind == 'failed' and 'manual_review_refund_failed' or 'refund_outcome_unknown')
        S.EventLog(row.id, 'settle_failed', 'cm-billing', kind == 'failed' and 'refund_failed' or 'refund_unknown')
        if kind == 'failed' then
            S.audit('cm_billing_settlement_critical', { reference = reference, recipient = cid, amount = amount, destination = destType, state = 'refund_failed' })
        end
        return false, 'settlement_failed'
    end

    local state, noteText = settleRemainder(cid, account, row, accepted)
    if state ~= 'done' then
        note(row, token, 'remainder_pending_' .. tostring(noteText))
        S.EventLog(row.id, 'settle_pending', 'cm-billing', 'remainder_pending')
        return false, 'settlement_pending'
    end

    if not markPaid(row, token, account, noteText) then
        S.audit('cm_billing_settlement_critical', { reference = reference, recipient = cid, amount = amount, destination = destType, state = 'mark_paid_failed' })
        return false, 'internal_error'
    end
    S.EventLog(row.id, 'paid', tostring(cid), account)
    S.audit('cm_billing_invoice_paid', { reference = reference, recipient = cid, issuerType = row.issuer_type, issuerResource = row.issuer_resource,
        amount = amount, destination = destType, destinationId = row.destination_id, account = account })
    CreateThread(function() pcall(S.Notifier.paid, cid, { amount = amount, reference = reference }) end)
    return true, { reference = reference, amount = amount, account = account }
end

-- cid/src come from the caller's session; reference/account are untrusted client input.
function S.PayInvoice(cid, src, reference, account)
    account = type(account) == 'string' and account or ''
    if not Config.PayAccounts[account] then return false, 'invalid_account' end
    local row = S.GetRow(reference)
    if not row or tostring(row.recipient_character_id) ~= tostring(cid) then return false, 'not_found' end
    if row.status ~= 'pending' then return false, 'not_pending' end

    local key = 'pay:' .. tostring(row.id)
    if not S.Lock(key) then return false, 'busy' end
    local ok, a, b = pcall(settle, tostring(cid), src, row, account)
    S.Unlock(key)
    if not ok then
        print('[cm-billing] payment error: ' .. tostring(a))
        return false, 'internal_error'
    end
    return a, b
end

-- Recovery for claims left in `settling`. Idempotent: owner status first, then the SAME owner references are re-issued. Safe against concurrent
-- workers and restarts (the owners' unique references decide; the in-process lock below only avoids needless duplicate work).
function S.ReconcileSettling()
    local rows = MySQL.query.await(("SELECT %s, settle_token FROM cm_billing_invoices WHERE status = 'settling' AND settle_started_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? SECOND) LIMIT 50"):format(S.INVOICE_COLUMNS),
        { Config.SettlingStaleSeconds }) or {}
    local handled = 0
    for _, row in ipairs(rows) do
        local lockKey = 'pay:' .. tostring(row.id)
        if S.Lock(lockKey) then
            local ok, err = pcall(function()
                local cid, reference, token = tostring(row.recipient_character_id), row.public_reference, row.settle_token
                local account = row.payment_account ~= '' and row.payment_account or 'bank'
                local amount = tonumber(row.amount)
                local keys = S.PayKeys(reference)
                local debitSeen = S.Ledger.HasDebit(cid, reference)            -- raises when the owner cannot answer: row stays settling
                if not debitSeen then
                    -- The reference may still be debited by a slow in-flight call; a journal-less debit reference is simply never used again.
                    release(row, token, 'recovered_no_charge')
                    S.EventLog(row.id, 'recovered', 'cm-billing', 'no_charge')
                    return
                end
                if S.Ledger.HasRefund(cid, reference) then
                    release(row, token, 'recovered_refunded')
                    S.EventLog(row.id, 'recovered', 'cm-billing', 'refunded')
                    return
                end
                local adapter = S.Destinations[row.destination_type]
                if not adapter then return end
                local credited, accepted = adapter.evidence(row)                -- raises when the owner cannot answer
                if credited ~= true then
                    local outcome
                    outcome, accepted = creditDestination(adapter, row, account)
                    if outcome == 'unknown' then return end
                    if outcome == 'failed' then
                        local refunded, kind = giveBack(cid, account, amount, keys.refund, reference)
                        if refunded then
                            release(row, token, 'recovered_refunded')
                            S.EventLog(row.id, 'recovered', 'cm-billing', 'refunded')
                        elseif kind == 'failed' then
                            S.audit('cm_billing_settlement_critical', { reference = reference, recipient = cid, amount = amount, state = 'reconcile_manual_review' })
                        end
                        return
                    end
                end
                accepted = type(accepted) == 'number' and accepted or amount
                local state, noteText = settleRemainder(cid, account, row, accepted)
                if state ~= 'done' then return end                              -- remainder return not yet confirmed: stay settling, retry next sweep
                markPaid(row, token, account, noteText)
                S.EventLog(row.id, 'recovered', 'cm-billing', 'paid')
            end)
            S.Unlock(lockKey)
            if not ok then print('[cm-billing] settling recovery deferred for ' .. tostring(row.public_reference) .. ': ' .. tostring(err)) end
        end
        handled = handled + 1
    end
    return handled
end
