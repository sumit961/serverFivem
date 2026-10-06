-- Invoice refunds: a durable, exact-once saga that returns money from a PAID invoice to its ORIGINAL payer by first
-- reversing the value out of the invoice's ORIGINAL destination. Never mints money, never creates a negative invoice, and never
-- changes the paid fact (invoice.status stays 'paid'; refunded_amount / refund_state carry the refund history).
--
--   RequestRefund -> [1] validate (provider owns invoice, invoice paid, destination refundable, amount <= paid - reserved)
--                    [2] claim: ONE SQL transaction reserves the amount on the invoice row (guarded UPDATE) and inserts the
--                        journal row (unique per provider+refund_reference). A refund can only start on a committed `paid` invoice
--                        (payment claims go pending->settling->paid; refunds require paid), so refund and payment cannot race.
--                    [3] destination debit  (business/family/character owner contract, idempotent by journal key)
--                    [4] payer credit       (cm-playerdata AddMoneyToCharacterOnce, evidence = owner journal status)
--                    [5] journal -> completed AND invoice refunded_amount/refund_state, one SQL transaction.
-- Every external step is preceded by a durable *_state = 'attempting' write and followed by an evidence check on retry, so a
-- timeout or crash is never read as "not applied": recovery asks the owner's ledger. After the destination debit commits the
-- refund is forward-only (only the payer credit remains); it is never expired or cancelled.
--
-- Journal status:  pending -> destination_debited -> completed
--                  needs_reconciliation (pre-debit only: destination short of funds / owner unavailable / outcome unknown)
--                  failed (admin abandon, only with ledger proof that no debit happened; releases the reservation)
local S = CMBilling.Server
local Config = CMBilling.Config
local RC = Config.Refund

local SQL = {
    -- Guarded reservation: only a paid invoice of this provider, never beyond the paid amount (completed + in flight).
    reserve = [[UPDATE cm_billing_invoices SET refund_reserved_amount = refund_reserved_amount + ?, refund_state = 'processing'
        WHERE id = ? AND status = 'paid' AND issuer_resource = ? AND refund_reserved_amount + ? <= ?]],
    -- Inserts only when the reservation changed exactly one row; a duplicate (provider, reference) aborts and rolls the reservation back.
    insert = [[INSERT INTO cm_billing_refunds (provider_resource, refund_reference, invoice_id, invoice_reference, payer_character_id,
        payment_account, destination_type, destination_id, amount, amount_mode, reason)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? FROM DUAL WHERE ROW_COUNT() = 1]],
    complete_journal = [[UPDATE cm_billing_refunds SET status = 'completed', credit_state = 'committed', failure_reason = '',
        completed_at = CURRENT_TIMESTAMP WHERE id = ? AND status = 'destination_debited']],
    complete_invoice = [[UPDATE cm_billing_invoices SET refunded_amount = refunded_amount + ?, refunded_at = CURRENT_TIMESTAMP,
        refund_state = IF(refunded_amount >= ?, 'refunded', IF(refund_reserved_amount > refunded_amount, 'processing', 'partial'))
        WHERE id = ? AND ROW_COUNT() = 1]],
    fail_journal = [[UPDATE cm_billing_refunds SET status = 'failed', failure_reason = ?, completed_at = CURRENT_TIMESTAMP
        WHERE id = ? AND status IN ('pending','needs_reconciliation') AND debit_state <> 'committed']],
    release_invoice = [[UPDATE cm_billing_invoices SET refund_reserved_amount = refund_reserved_amount - ?,
        refund_state = IF(refunded_amount >= ?, 'refunded', IF(refund_reserved_amount > refunded_amount, 'processing', IF(refunded_amount > 0, 'partial', 'none')))
        WHERE id = ? AND ROW_COUNT() = 1]],
    debit_attempt = "UPDATE cm_billing_refunds SET debit_state = 'attempting' WHERE id = ? AND status IN ('pending','needs_reconciliation') AND debit_state <> 'committed'",
    debit_commit = "UPDATE cm_billing_refunds SET status = 'destination_debited', debit_state = 'committed', failure_reason = '' WHERE id = ? AND status IN ('pending','needs_reconciliation')",
    recon = "UPDATE cm_billing_refunds SET status = 'needs_reconciliation', failure_reason = ?, debit_state = ? WHERE id = ? AND status IN ('pending','needs_reconciliation') AND debit_state <> 'committed'",
    credit_state = "UPDATE cm_billing_refunds SET credit_state = ?, failure_reason = ? WHERE id = ? AND status = 'destination_debited'",
    touch = 'UPDATE cm_billing_refunds SET attempts = attempts + 1 WHERE id = ?',
}
S.RefundSQL = SQL

local JOURNAL_COLS = [[id, provider_resource, refund_reference, invoice_id, invoice_reference, payer_character_id, payment_account,
    destination_type, destination_id, amount, amount_mode, reason, status, debit_state, credit_state, failure_reason, attempts,
    UNIX_TIMESTAMP(created_at) AS created_ts, UNIX_TIMESTAMP(completed_at) AS completed_ts]]

local function getById(id) return MySQL.single.await('SELECT ' .. JOURNAL_COLS .. ' FROM cm_billing_refunds WHERE id = ? LIMIT 1', { id }) end
local function getByRef(provider, ref)
    return MySQL.single.await('SELECT ' .. JOURNAL_COLS .. ' FROM cm_billing_refunds WHERE provider_resource = ? AND refund_reference = ? LIMIT 1', { provider, ref })
end

local function isFinal(j) return j.status == 'completed' or j.status == 'failed' end

function S.RefundView(j)
    return {
        refundReference = j.refund_reference,
        invoiceReference = j.invoice_reference,
        amount = tonumber(j.amount),
        reason = j.reason,
        status = j.status,
        final = isFinal(j),
        debitState = j.debit_state,
        creditState = j.credit_state,
        failureReason = j.failure_reason ~= '' and j.failure_reason or nil,
        createdAt = tonumber(j.created_ts),
        completedAt = tonumber(j.completed_ts),
    }
end

-- ---------------------------------------------------------------------------
-- Paid amount: what the destination actually received. A family treasury may have accepted less than the invoice amount (the
-- remainder was returned to the payer at payment time and is recorded in settlement_note). Unknown => refuse (fail closed).
-- ---------------------------------------------------------------------------
function S.PaidAmount(row)
    local amount = tonumber(row.amount)
    if not amount then return nil, 'paid_amount_unknown' end
    local note = row.settlement_note or ''
    local remainder = note:match('^partial_refund_(%d+)$')
    if remainder then
        local paid = amount - tonumber(remainder)
        if paid < 1 then return nil, 'paid_amount_unknown' end
        return paid
    end
    if note:find('partial_refund_failed', 1, true) or note == 'manual_review_refund_failed' then return nil, 'paid_amount_unknown' end
    if note == 'recovered_paid' and row.destination_type == 'family' then return nil, 'paid_amount_unknown' end
    return amount
end

function S.NetPaid(row)
    local paid = S.PaidAmount(row)
    if not paid then return nil end
    return math.max(0, paid - (tonumber(row.refunded_amount) or 0))
end

-- ---------------------------------------------------------------------------
-- Destination reversal adapters (the money owners keep balance authority) and the payer credit adapter. Replaceable by tests.
-- debit(j) -> true | false, reason  (a returned reason means the owner definitively did NOT apply it; an error means unknown)
-- ---------------------------------------------------------------------------
local function debitKey(j) return ('cm-billing-rfd-debit:%s:%d'):format(j.invoice_reference, j.id) end
local function creditKey(j) return ('cm-billing-rfd-credit:%s:%d'):format(j.invoice_reference, j.id) end
S.RefundDebitKey, S.RefundCreditKey = debitKey, creditKey

S.RefundDestinations = {
    business = {
        available = function() return GetResourceState('cm-commercial-ownership') == 'started' end,
        debit = function(j)
            local t, i = tostring(j.destination_id or ''):match('^([%w_]+):([%w_%-%.]+)$')
            if not t then return false, 'invalid_destination' end
            local applied, info = exports['cm-commercial-ownership']:DebitBusinessAtomic(t, i, tonumber(j.amount), 'invoice_refund',
                { idempotencyKey = debitKey(j), reference = j.invoice_reference })
            if applied == true then return true end
            return false, type(info) == 'string' and info or 'rejected'
        end,
        evidence = function(j) return exports['cm-commercial-ownership']:HasBusinessTransaction(debitKey(j)) == true end,
    },
    character = {
        available = function() return GetResourceState('cm-playerdata') == 'started' end,
        debit = function(j)
            local applied, info = exports['cm-playerdata']:RemoveMoneyFromCharacter(j.destination_id, j.payment_account, tonumber(j.amount), debitKey(j),
                { invoice = j.invoice_reference })
            if applied == true then return true end
            return false, type(info) == 'string' and info or 'rejected'
        end,
        -- Authoritative owner journal status (never the generic transaction log). false = never applied; an error = owner cannot answer.
        evidence = function(j)
            local op, why = exports['cm-playerdata']:GetCharacterMoneyOperation(debitKey(j))
            if op == nil then error('character money journal ' .. tostring(why)) end
            return op ~= false and op.direction == 'debit' and op.characterId == tostring(j.destination_id)
        end,
    },
    family = {
        available = function() return GetResourceState('cm-family') == 'started' end,
        debit = function(j)
            local applied, info = exports['cm-family']:DebitFamilyTreasuryAtomic(tonumber(j.destination_id), tonumber(j.amount),
                { reason = debitKey(j), category = 'refund' })
            if applied == true then return true end
            return false, type(info) == 'string' and info or 'rejected'
        end,
        evidence = function(j) return exports['cm-family']:HasFamilyTreasuryEntry(tonumber(j.destination_id), 'debit', debitKey(j)) == true end,
    },
    -- city: deliberately absent. It is a sink with no treasury; reversing it would create cash (Config.Destinations.city.refundable = false).
}

S.RefundPayer = {
    -- Exactly once through the playerdata operation journal (unique reference); true for applied AND replayed.
    Credit = function(j)
        local ok = exports['cm-playerdata']:AddMoneyToCharacterOnce(j.payer_character_id, j.payment_account, tonumber(j.amount), creditKey(j),
            { invoice = j.invoice_reference, refund = j.refund_reference })
        return ok == true
    end,
    Evidence = function(j)
        local op, why = exports['cm-playerdata']:GetCharacterMoneyOperation(creditKey(j))
        if op == nil then error('character money journal ' .. tostring(why)) end
        return op ~= false and op.direction == 'credit' and op.characterId == tostring(j.payer_character_id)
    end,
}

-- ---------------------------------------------------------------------------
-- Journal bookkeeping
-- ---------------------------------------------------------------------------
local function event(j, name, detail)
    S.EventLog(j.invoice_id, name, j.provider_resource, ('%s %s'):format(j.refund_reference, detail or ''))
end

local function setRecon(j, failure, debitState)
    local changed = MySQL.update.await(SQL.recon, { failure, debitState, j.id })
    if (tonumber(changed) or 0) > 0 and j.failure_reason ~= failure then
        event(j, 'refund_reconcile', failure)
        S.audit('cm_billing_refund_reconciliation', { refund = j.refund_reference, invoice = j.invoice_reference, provider = j.provider_resource,
            amount = tonumber(j.amount), reason = failure })
    end
end

local function complete(j, paid)
    local ok = pcall(function()
        return MySQL.transaction.await({
            { query = SQL.complete_journal, values = { j.id } },
            { query = SQL.complete_invoice, values = { tonumber(j.amount), paid, j.invoice_id } },
        })
    end)
    local fresh = getById(j.id)
    if fresh and fresh.status == 'completed' then
        if ok then
            event(j, 'refund_completed', tostring(j.amount))
            S.audit('cm_billing_refund_completed', { refund = j.refund_reference, invoice = j.invoice_reference, provider = j.provider_resource,
                payer = j.payer_character_id, amount = tonumber(j.amount), destination = j.destination_type, destinationId = j.destination_id })
            CreateThread(function()
                if S.Notifier and S.Notifier.refunded then pcall(S.Notifier.refunded, j.payer_character_id, { amount = tonumber(j.amount), reference = j.invoice_reference }) end
            end)
        end
        return true
    end
    return false
end

local function invoiceRow(j) return MySQL.single.await('SELECT ' .. S.INVOICE_COLUMNS .. ' FROM cm_billing_invoices WHERE id = ? LIMIT 1', { j.invoice_id }) end

-- One forward step-through of the saga. Idempotent at every boundary; never debits the destination twice.
local function step(id)
    local j = getById(id)
    if not j or isFinal(j) then return j end
    MySQL.update.await(SQL.touch, { j.id })
    local dest = S.RefundDestinations[j.destination_type]
    if not dest then setRecon(j, 'destination_unsupported', j.debit_state) return getById(id) end
    local inv = invoiceRow(j)
    local paid = inv and S.PaidAmount(inv)
    if not paid then setRecon(j, 'paid_amount_unknown', j.debit_state) return getById(id) end

    if j.status ~= 'destination_debited' then
        local committed = j.debit_state == 'committed'
        if not committed and j.debit_state ~= 'none' then
            -- A previous attempt may have reached the owner: ask the owner's ledger, never guess.
            local ok, seen = pcall(dest.evidence, j)
            if not ok or seen == nil then setRecon(j, 'debit_evidence_unavailable', j.debit_state) return getById(id) end
            committed = seen == true
        end
        if not committed then
            local okAvail, avail = pcall(dest.available)
            if not okAvail or avail ~= true then setRecon(j, 'destination_unavailable', j.debit_state) return getById(id) end
            MySQL.update.await(SQL.debit_attempt, { j.id })
            event(j, 'refund_debit_start', j.destination_type)
            local called, applied, why = pcall(dest.debit, j)
            if called and applied == true then
                committed = true
            elseif called and applied == false and type(why) == 'string' then
                -- The owner states the debit was NOT applied (e.g. insufficient funds). Stay in reconciliation; retried later.
                setRecon(j, why == 'insufficient_funds' and 'insufficient_destination_funds' or why:sub(1, 60), 'none')
                return getById(id)
            else
                setRecon(j, 'debit_outcome_unknown', 'unknown')
                return getById(id)
            end
        end
        MySQL.update.await(SQL.debit_commit, { j.id })
        event(j, 'refund_debit_done', j.destination_type)
        j = getById(id)
        if not j or j.status ~= 'destination_debited' then return j end
    end

    -- Destination value is gone: from here the refund is forward-only (payer credit, then journal completion).
    local credited = j.credit_state == 'committed'
    if not credited and j.credit_state ~= 'none' then
        local ok, seen = pcall(S.RefundPayer.Evidence, j)
        if not ok or seen == nil then
            MySQL.update.await(SQL.credit_state, { 'unknown', 'credit_evidence_unavailable', j.id })
            return getById(id)
        end
        credited = seen == true
    end
    if not credited then
        MySQL.update.await(SQL.credit_state, { 'attempting', '', j.id })
        event(j, 'refund_credit_start', j.payment_account)
        local called, ok = pcall(S.RefundPayer.Credit, j)
        if called and ok == true then
            credited = true
        else
            MySQL.update.await(SQL.credit_state, { 'unknown', 'payer_credit_pending', j.id })
            S.audit('cm_billing_refund_critical', { refund = j.refund_reference, invoice = j.invoice_reference, state = 'payer_credit_pending', amount = tonumber(j.amount) })
            return getById(id)
        end
    end
    event(j, 'refund_credit_done', j.payment_account)
    complete(j, paid)
    return getById(id)
end

-- Runs the saga under a per-journal lock. Returns the fresh journal row and 'busy' when another thread is already driving it.
local function drive(id)
    local key = 'refund:' .. tostring(id)
    if not S.Lock(key) then return getById(id), 'busy' end
    local ok, res = pcall(step, id)
    S.Unlock(key)
    if not ok then
        print('[cm-billing] refund step error: ' .. tostring(res))
        return getById(id), 'internal_error'
    end
    return res or getById(id)
end
S.DriveRefund = drive

-- ---------------------------------------------------------------------------
-- Public service functions (caller = GetInvokingResource() from exports.lua)
-- ---------------------------------------------------------------------------
local function validRef(value, maxLen) return type(value) == 'string' and #value >= 1 and #value <= maxLen and value:match('^[%w_:%.%-]+$') ~= nil end

local function replay(j, invoiceRef, mode, requested)
    if j.invoice_reference ~= invoiceRef then return false, 'idempotency_conflict' end
    if mode ~= j.amount_mode then return false, 'idempotency_conflict' end
    if mode == 'exact' and tonumber(j.amount) ~= requested then return false, 'idempotency_conflict' end
    local fresh = j
    if not isFinal(j) then fresh = drive(j.id) end
    return true, S.RefundView(fresh or j)
end

-- RequestRefund(caller, invoiceReference, refundReference, amount|nil, reason)
-- amount == nil refunds everything still refundable. Returns true, view | false, reason.
-- `true` means the refund is journaled and the saga owns it; read view.status (completed | destination_debited | pending |
-- needs_reconciliation | failed). `false` means nothing was reserved or moved.
function S.RequestRefund(caller, invoiceRef, refundRef, amount, reason)
    local provider = S.ProviderFor(caller)
    if not provider or provider.canRefund ~= true then return false, 'forbidden' end
    if not S.SchemaReady then return false, 'unavailable' end
    if not validRef(invoiceRef, 16) then return false, 'not_found' end
    if not validRef(refundRef, 64) or #refundRef < 8 then return false, 'invalid_refund_reference' end
    if type(reason) ~= 'string' or RC.Reasons[reason] ~= true then return false, 'invalid_reason' end
    local mode, requested = 'full', nil
    if amount ~= nil then
        requested = tonumber(amount)
        if not requested or requested ~= requested or requested ~= math.floor(requested) or requested < 1 or requested > 9007199254740991 then
            return false, 'invalid_amount'
        end
        mode = 'exact'
    end

    local existing = getByRef(caller, refundRef)
    if existing then return replay(existing, invoiceRef, mode, requested) end

    local row = S.GetRow(invoiceRef)
    if not row or row.issuer_resource ~= caller then return false, 'not_found' end
    if row.status ~= 'paid' then return false, 'not_paid' end
    local destCfg = Config.Destinations[row.destination_type]
    if not destCfg or destCfg.refundable ~= true or not S.RefundDestinations[row.destination_type] then return false, 'destination_not_refundable' end
    if not Config.PayAccounts[row.payment_account] then return false, 'payment_account_unknown' end
    local paid, why = S.PaidAmount(row)
    if not paid then return false, why end

    local reserved = tonumber(row.refund_reserved_amount) or 0
    local remaining = paid - reserved
    if remaining < 1 then
        return false, (tonumber(row.refunded_amount) or 0) >= paid and 'already_refunded' or 'refund_in_progress'
    end
    if mode == 'full' then requested = remaining end
    if requested > remaining then return false, 'refund_exceeds_paid' end

    local ok = pcall(function()
        return MySQL.transaction.await({
            { query = SQL.reserve, values = { requested, row.id, caller, requested, paid } },
            { query = SQL.insert, values = { caller, refundRef, row.id, row.public_reference, row.recipient_character_id, row.payment_account,
                row.destination_type, row.destination_id, requested, mode, reason } },
        })
    end)
    local j = getByRef(caller, refundRef)
    if not j then
        -- Nothing was reserved (guard failed or DB error). Report the stable reason from fresh state.
        if not ok then print('[cm-billing] refund claim transaction failed for ' .. tostring(invoiceRef)) end
        local fresh = S.GetRow(invoiceRef)
        if not fresh or fresh.status ~= 'paid' then return false, 'not_paid' end
        return false, ((tonumber(fresh.refunded_amount) or 0) >= paid) and 'already_refunded' or 'refund_exceeds_paid'
    end
    if j.invoice_reference ~= invoiceRef then return false, 'idempotency_conflict' end

    event(j, 'refund_requested', ('%s %s'):format(reason, tostring(requested)))
    S.audit('cm_billing_refund_requested', { refund = refundRef, invoice = invoiceRef, provider = caller, amount = requested, reason = reason,
        destination = row.destination_type })
    local fresh = drive(j.id)
    return true, S.RefundView(fresh or j)
end

-- Provider-scoped status read.
function S.GetRefundStatus(caller, refundRef)
    if not S.ProviderFor(caller) then return nil, 'forbidden' end
    if not validRef(refundRef, 64) then return nil, 'not_found' end
    local j = getByRef(caller, refundRef)
    if not j then return nil, 'not_found' end
    return S.RefundView(j)
end

-- Provider-scoped invoice refund summary (the canonical net amount, so consumers never recompute it).
function S.GetInvoiceRefundState(caller, invoiceRef)
    if not S.ProviderFor(caller) then return nil, 'forbidden' end
    local row = S.GetRow(invoiceRef)
    if not row or row.issuer_resource ~= caller then return nil, 'not_found' end
    local paid = S.PaidAmount(row)
    local refunded, reserved = tonumber(row.refunded_amount) or 0, tonumber(row.refund_reserved_amount) or 0
    return {
        reference = row.public_reference,
        status = row.status == 'settling' and 'processing' or row.status,
        refundState = row.refund_state,
        paidAmount = row.status == 'paid' and paid or nil,
        refundedAmount = refunded,
        inFlightAmount = reserved - refunded,
        refundableAmount = (row.status == 'paid' and paid) and math.max(0, paid - reserved) or 0,
        netPaidAmount = row.status == 'paid' and paid and math.max(0, paid - refunded) or nil,
    }
end

-- Provider retry of ITS OWN refund: only continues the saga forward (idempotent), never changes the request.
function S.RetryRefund(caller, refundRef)
    local provider = S.ProviderFor(caller)
    if not provider or provider.canRefund ~= true then return false, 'forbidden' end
    if not validRef(refundRef, 64) then return false, 'not_found' end
    local j = getByRef(caller, refundRef)
    if not j then return false, 'not_found' end
    if isFinal(j) then return true, S.RefundView(j) end
    local fresh = drive(j.id)
    return true, S.RefundView(fresh or j)
end

-- ---------------------------------------------------------------------------
-- Admin / reconcile (cm-admin export gate or server console). Observability + forward continuation only.
-- ---------------------------------------------------------------------------
function S.RefundAdminAllowed(caller) return caller == 'console' or RC.AdminResources[caller or ''] == true end

local function adminLookup(refundRef, provider)
    if not validRef(refundRef, 64) then return nil, 'not_found' end
    if provider ~= nil then return getByRef(tostring(provider), refundRef) end
    local rows = MySQL.query.await('SELECT ' .. JOURNAL_COLS .. ' FROM cm_billing_refunds WHERE refund_reference = ? LIMIT 2', { refundRef }) or {}
    if #rows > 1 then return nil, 'ambiguous_reference' end
    return rows[1]
end

function S.AdminInspectRefund(caller, refundRef, provider)
    if not S.RefundAdminAllowed(caller) then return nil, 'forbidden' end
    local j, why = adminLookup(refundRef, provider)
    if not j then return nil, why or 'not_found' end
    local view = S.RefundView(j)
    view.provider = j.provider_resource
    view.attempts = tonumber(j.attempts)
    view.destination = j.destination_type
    view.destinationId = j.destination_id
    view.payerCharacterId = j.payer_character_id
    view.account = j.payment_account
    return view
end

function S.AdminListStuckRefunds(caller, limit)
    if not S.RefundAdminAllowed(caller) then return nil, 'forbidden' end
    limit = math.max(1, math.min(100, math.floor(tonumber(limit) or 50)))
    local rows = MySQL.query.await(('SELECT %s FROM cm_billing_refunds WHERE status NOT IN (\'completed\',\'failed\') AND updated_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? SECOND) ORDER BY id LIMIT ?'):format(JOURNAL_COLS),
        { RC.StaleSeconds, limit }) or {}
    local out = {}
    for _, j in ipairs(rows) do
        local view = S.RefundView(j)
        view.provider, view.attempts = j.provider_resource, tonumber(j.attempts)
        out[#out + 1] = view
    end
    return out
end

function S.AdminReconcileRefund(caller, refundRef, provider)
    if not S.RefundAdminAllowed(caller) then return false, 'forbidden' end
    local j, why = adminLookup(refundRef, provider)
    if not j then return false, why or 'not_found' end
    S.audit('cm_billing_refund_reconcile', { refund = j.refund_reference, invoice = j.invoice_reference, actor = caller })
    if isFinal(j) then return true, S.RefundView(j) end
    local fresh = drive(j.id)
    return true, S.RefundView(fresh or j)
end

-- Abandon a refund that provably never debited the destination (releases the reservation). Refuses once any debit may have happened.
function S.AdminAbandonRefund(caller, refundRef, provider, note)
    if not S.RefundAdminAllowed(caller) then return false, 'forbidden' end
    local j, why = adminLookup(refundRef, provider)
    if not j then return false, why or 'not_found' end
    if isFinal(j) then return j.status == 'failed', j.status == 'failed' and S.RefundView(j) or 'already_completed' end
    if j.status == 'destination_debited' or j.debit_state == 'committed' then return false, 'destination_already_debited' end
    local key = 'refund:' .. tostring(j.id)
    if not S.Lock(key) then return false, 'busy' end
    local function finish(ok, res) S.Unlock(key) return ok, res end
    local dest = S.RefundDestinations[j.destination_type]
    local seen = false
    if dest then
        local okEv, ev = pcall(dest.evidence, j)
        if not okEv or ev == nil then return finish(false, 'debit_evidence_unavailable') end
        seen = ev == true
    end
    if seen then return finish(false, 'destination_already_debited') end
    local failure = ('abandoned:%s'):format(S.cleanText(tostring(note or 'admin'), 40) or 'admin')
    local inv = invoiceRow(j)
    local paid = inv and S.PaidAmount(inv) or tonumber(j.amount)
    local ok = pcall(function()
        return MySQL.transaction.await({
            { query = SQL.fail_journal, values = { failure, j.id } },
            { query = SQL.release_invoice, values = { tonumber(j.amount), paid, j.invoice_id } },
        })
    end)
    local fresh = getById(j.id)
    if ok and fresh and fresh.status == 'failed' then
        event(j, 'refund_failed', failure)
        S.audit('cm_billing_refund_failed', { refund = j.refund_reference, invoice = j.invoice_reference, actor = caller, amount = tonumber(j.amount) })
        return finish(true, S.RefundView(fresh))
    end
    return finish(false, 'abandon_failed')
end

-- Restart / periodic recovery: drives stale in-flight refunds forward and retries reconciliation-pending ones with back-off.
function S.ReconcileRefunds()
    local rows = MySQL.query.await([[SELECT id FROM cm_billing_refunds
        WHERE (status IN ('pending','destination_debited') AND updated_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? SECOND))
           OR (status = 'needs_reconciliation' AND updated_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? SECOND))
        ORDER BY id LIMIT ?]], { RC.StaleSeconds, RC.RetrySeconds, RC.SweepLimit }) or {}
    for _, r in ipairs(rows) do drive(r.id) end
    return #rows
end

-- Console-only operator commands (no player/client path exists).
local function cmd(name, fn)
    RegisterCommand(name, function(source, args)
        if source ~= 0 then return end
        if not S.AwaitSchema() then print('[cm-billing] schema not ready') return end
        local ok, err = pcall(fn, args)
        if not ok then print(('[cm-billing] %s error: %s'):format(name, tostring(err))) end
    end, true)
end

local function printView(v)
    print(('[cm-billing] refund %s invoice=%s amount=%s status=%s debit=%s credit=%s failure=%s attempts=%s provider=%s'):format(
        tostring(v.refundReference), tostring(v.invoiceReference), tostring(v.amount), tostring(v.status), tostring(v.debitState),
        tostring(v.creditState), tostring(v.failureReason), tostring(v.attempts), tostring(v.provider)))
end

cmd('cm_billing_refund_inspect', function(args)
    local v, why = S.AdminInspectRefund('console', args[1], args[2])
    if v then printView(v) else print('[cm-billing] ' .. tostring(why)) end
end)
cmd('cm_billing_refund_stuck', function()
    local list = S.AdminListStuckRefunds('console', 50)
    print(('[cm-billing] %d stuck refund(s)'):format(#list))
    for _, v in ipairs(list) do printView(v) end
end)
cmd('cm_billing_refund_reconcile', function(args)
    local ok, v = S.AdminReconcileRefund('console', args[1], args[2])
    if ok then printView(v) else print('[cm-billing] ' .. tostring(v)) end
end)
cmd('cm_billing_refund_abandon', function(args)
    local ok, v = S.AdminAbandonRefund('console', args[1], args[2], 'console')
    if ok then printView(v) else print('[cm-billing] ' .. tostring(v)) end
end)
