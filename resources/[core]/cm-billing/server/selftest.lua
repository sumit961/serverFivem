-- Development-only service-layer self-test:   server console  ->  cm_billing_selftest
-- Requires cm_environment=development; console only. Uses synthetic characters "qa-bill-*", an in-memory money ledger and
-- stand-in destinations, injects failures, and removes every row it created. It exercises the same service functions the
-- exports and callbacks use (the calling resource name is a parameter of the core so provider checks can be tested).
local S = CMBilling.Server
local Config = CMBilling.Config

local PREFIX = 'qa-bill-'

local function enabled()
    return GetConvar(Config.SelfTest.convar, 'production') == Config.SelfTest.value
end

local function cleanup()
    local like = PREFIX .. '%'
    MySQL.query.await('DELETE r FROM cm_billing_refunds r JOIN cm_billing_invoices i ON i.id = r.invoice_id WHERE i.recipient_character_id LIKE ?', { like })
    MySQL.query.await('DELETE e FROM cm_billing_events e JOIN cm_billing_invoices i ON i.id = e.invoice_id WHERE i.recipient_character_id LIKE ?', { like })
    MySQL.query.await('DELETE FROM cm_billing_invoices WHERE recipient_character_id LIKE ?', { like })
end

local function run()
    local results, failed = {}, 0
    local function check(name, cond, detail)
        results[#results + 1] = name
        if cond ~= true then
            failed = failed + 1
            print(('[cm-billing:selftest] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-billing:selftest] PASS  %s'):format(name))
        end
    end

    cleanup()
    local A, B, C, D = PREFIX .. 'a', PREFIX .. 'b', PREFIX .. 'c', PREFIX .. 'd'
    S.TestCharacters = { [A] = true, [B] = true, [C] = true, [D] = true }
    S.TestProviders = {
        ['qa-billing'] = { maxAmount = 100000, issuerTypes = { system = true, organization = true }, destinations = { city = true, character = true, family = true, business = true },
                           allowOffline = true, metadataNamespace = 'qa', canVoid = true },
        ['qa-billing-big'] = { maxAmount = 999999999, issuerTypes = { system = true }, destinations = { city = true }, allowOffline = true, metadataNamespace = 'big', canVoid = true },
        ['qa-billing-online'] = { maxAmount = 5000, issuerTypes = { system = true }, destinations = { city = true }, allowOffline = false, metadataNamespace = 'on', canVoid = true },
        ['qa-billing-other'] = { maxAmount = 5000, issuerTypes = { system = true }, destinations = { city = true }, allowOffline = true, metadataNamespace = 'oth', canVoid = true },
    }
    local P = 'qa-billing'

    -- stand-in money ledger -----------------------------------------------------------
    local ledger = { cash = { [A] = 10000, [B] = 500 }, bank = { [A] = 50000, [B] = 0 }, debits = 0, credits = {}, refunds = 0, failCredit = false, failRefund = false, slow = false }
    local origMoney, origDest, origLedger, origNotifier = S.Money, S.Destinations, S.Ledger, S.Notifier
    S.Money = {
        Debit = function(src, account, amount, reason)
            if ledger.slow then Wait(150) end
            local cid = src -- in tests the "source" IS the character id
            if (ledger[account][cid] or 0) < amount then return false end
            ledger[account][cid] = ledger[account][cid] - amount
            ledger.debits = ledger.debits + 1
            return true
        end,
        CreditCharacter = function(characterId, account, amount, reason)
            if reason:sub(1, 22) == 'cm-billing-pay-refund:' or reason:sub(1, 25) == 'cm-billing-pay-remainder:' then
                if ledger.failRefund then return false end
                ledger[account][characterId] = (ledger[account][characterId] or 0) + amount
                ledger.refunds = ledger.refunds + 1
                return true
            end
            if ledger.failCredit then return false end
            ledger[account][characterId] = (ledger[account][characterId] or 0) + amount
            ledger.credits[#ledger.credits + 1] = { characterId, amount }
            return true
        end,
        Balance = function(src, account) return ledger[account][src] or 0 end,
    }
    S.Ledger = { HasDebit = function() return ledger.hasDebit == true end, HasRefund = function() return ledger.hasRefund == true end }
    S.Destinations = {
        city = origDest.city,
        character = {
            available = function() return true end,
            validate = function(id, recipient) return id ~= nil and id ~= '' and id ~= recipient and S.CharacterExists(id) end,
            credit = function(inv, account) return S.Money.CreditCharacter(inv.destination_id, account, tonumber(inv.amount), 'cm-billing-credit:' .. inv.public_reference) end,
            evidence = function() return ledger.creditEvidence == true end,
        },
        family = {
            available = function() return true end,
            validate = function(id) return tonumber(id) == 7 end,
            credit = function(inv) return true, math.floor(tonumber(inv.amount) / 2) end, -- treasury accepts half
            evidence = function() return false end,
        },
    }
    -- Never touch the real phone/HUD with synthetic characters.
    S.Notifier = { created = function() end, paid = function() end }
    local function create(over, provider)
        local data = { recipientCharacterId = A, amount = 1000, label = 'Test service', issuerLabel = 'QA Garage', destination = { type = 'city' } }
        for k, v in pairs(over or {}) do data[k] = v end
        return S.CreateInvoice(provider or P, data)
    end
    local function row(ref) return S.GetRow(ref) end
    local function status(ref) return row(ref).status end

    -- CREATION ------------------------------------------------------------------------
    check('create.untrusted_resource_rejected', select(2, S.CreateInvoice('some-random-resource', { recipientCharacterId = A, amount = 100, label = 'x', issuerLabel = 'y' })) == 'forbidden')
    check('create.disabled_provider_rejected', select(2, S.CreateInvoice('cm-law', { recipientCharacterId = A, amount = 100, label = 'x', issuerLabel = 'y' })) == 'forbidden')
    check('create.nil_caller_rejected', select(2, S.CreateInvoice(nil, {})) == 'forbidden')
    local ok, inv = create()
    check('create.trusted_ok', ok == true and inv.reference and inv.reference:match('^INV%-[A-Z0-9]+$') ~= nil)
    check('create.invalid_recipient', select(2, create({ recipientCharacterId = 'qa-bill-ghost' })) == 'invalid_recipient')
    check('create.offline_recipient_supported', create({ recipientCharacterId = D }) == true)
    check('create.offline_rejected_when_provider_requires_online', select(2, create({ recipientCharacterId = A, amount = 100 }, 'qa-billing-online')) == 'recipient_offline')
    S.TestOnline = { [A] = -3001 }
    check('create.online_recipient_allowed_for_online_provider', create({ amount = 100 }, 'qa-billing-online') == true)
    S.TestOnline = nil
    for _, bad in ipairs({ 0, -5, 1.5, 'abc', false }) do
        check('create.invalid_amount_' .. tostring(bad), select(2, create({ amount = bad })) == 'invalid_amount')
    end
    check('create.nil_amount_rejected', select(2, S.CreateInvoice(P, { recipientCharacterId = A, label = 'x', issuerLabel = 'y' })) == 'invalid_amount')
    check('create.over_provider_max_rejected', select(2, create({ amount = 100001 })) == 'amount_exceeds_provider_limit')
    check('create.over_hard_max_rejected', select(2, create({ amount = Config.HardMaxAmount + 1 }, 'qa-billing-big')) == 'amount_exceeds_platform_limit')
    check('create.unknown_destination_rejected', select(2, create({ destination = { type = 'bank_of_mars' } })) == 'invalid_destination')
    check('create.unavailable_business_destination_rejected', select(2, create({ destination = { type = 'business', id = '1' } })) == 'invalid_destination')
    check('create.destination_not_allowed_for_provider', select(2, create({ destination = { type = 'character', id = B } }, 'qa-billing-other')) == 'destination_not_allowed')
    check('create.character_destination_cannot_be_recipient', select(2, create({ destination = { type = 'character', id = A } })) == 'invalid_destination')
    check('create.character_destination_must_exist', select(2, create({ destination = { type = 'character', id = 'qa-bill-ghost' } })) == 'invalid_destination')
    check('create.issuer_type_restricted', select(2, create({ issuerType = 'character' })) == 'forbidden_issuer_type')
    check('create.metadata_namespace_enforced', select(2, create({ metadata = { law = 1 } })) == 'invalid_metadata' and create({ metadata = { ['qa.note'] = 'x' } }) == true)
    check('create.missing_label_rejected', select(2, create({ label = '   ' })) == 'invalid_request')
    local _, idem1 = create({ idempotencyKey = 'k-1' })
    local _, idem2 = create({ idempotencyKey = 'k-1' })
    check('create.idempotency_key_returns_same_invoice', idem1.reference == idem2.reference and idem2.existing == true)
    check('create.client_cannot_pick_issuer_resource', row(inv.reference).issuer_resource == P)

    -- ACCESS --------------------------------------------------------------------------
    local view = S.GetOwnInvoice(A, inv.reference)
    check('access.recipient_can_view', view ~= nil and view.amount == 1000 and view.status == 'pending')
    check('access.other_character_cannot_view', S.GetOwnInvoice(B, inv.reference) == nil)
    local leaked = {}
    for _, key in ipairs({ 'id', 'issuer_resource', 'destination_type', 'destination_id', 'metadata', 'recipient_character_id', 'issuer_entity_id', 'settle_token' }) do
        if view[key] ~= nil then leaked[#leaked + 1] = key end
    end
    check('access.internal_fields_not_leaked', #leaked == 0, table.concat(leaked, ','))
    check('access.list_scoped_to_recipient', #S.ListInvoices(B, 'pending') == 0 and #S.ListInvoices(A, 'pending') >= 1)
    check('access.other_provider_cannot_read', select(2, S.GetIssuedInvoice('qa-billing-other', inv.reference)) == 'not_found')
    check('access.issuer_provider_can_read', S.GetIssuedInvoice(P, inv.reference).recipientCharacterId == A)

    -- PAYMENT -------------------------------------------------------------------------
    local _, big = create({ amount = 20000 })
    ok, view = S.PayInvoice(B, B, big.reference, 'cash')
    check('pay.other_character_cannot_pay', ok == false and view == 'not_found')
    ok, view = S.PayInvoice(A, A, big.reference, 'crypto')
    check('pay.invalid_account_rejected', ok == false and view == 'invalid_account')
    local cashBefore = ledger.cash[A]
    ok, view = S.PayInvoice(A, A, big.reference, 'cash')
    check('pay.insufficient_funds_rejected', ok == false and view == 'insufficient_funds' and ledger.cash[A] == cashBefore and status(big.reference) == 'pending' and ledger.debits == 0)
    local _, cashInv = create({ amount = 1200 })
    ok, view = S.PayInvoice(A, A, cashInv.reference, 'cash')
    check('pay.cash_success', ok == true and ledger.cash[A] == cashBefore - 1200 and ledger.debits == 1 and status(cashInv.reference) == 'paid')
    check('pay.city_destination_is_a_sink', #ledger.credits == 0)
    ok, view = S.PayInvoice(A, A, cashInv.reference, 'cash')
    check('pay.paid_invoice_cannot_be_paid_again', ok == false and view == 'not_pending' and ledger.debits == 1 and ledger.cash[A] == cashBefore - 1200)
    local _, bankInv = create({ amount = 3000 })
    local bankBefore = ledger.bank[A]
    ok = S.PayInvoice(A, A, bankInv.reference, 'bank')
    check('pay.bank_success', ok == true and ledger.bank[A] == bankBefore - 3000 and status(bankInv.reference) == 'paid' and row(bankInv.reference).payment_account == 'bank')

    -- simultaneous requests on one invoice
    local _, raceInv = create({ amount = 500 })
    ledger.slow = true
    local debitsBefore, balBefore, outcomes = ledger.debits, ledger.cash[A], {}
    for i = 1, 3 do
        CreateThread(function() outcomes[i] = { S.PayInvoice(A, A, raceInv.reference, 'cash') } end)
    end
    local waited = 0
    while (not outcomes[1] or not outcomes[2] or not outcomes[3]) and waited < 4000 do Wait(50) waited = waited + 50 end
    ledger.slow = false
    local wins = 0
    for i = 1, 3 do if outcomes[i] and outcomes[i][1] == true then wins = wins + 1 end end
    check('pay.simultaneous_requests_settle_once', wins == 1 and ledger.debits == debitsBefore + 1 and ledger.cash[A] == balBefore - 500 and status(raceInv.reference) == 'paid', ('wins=%d'):format(wins))

    -- expiry
    local _, expInv = create({ amount = 100, expiresInSeconds = 60 })
    MySQL.update.await("UPDATE cm_billing_invoices SET expires_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 5 SECOND) WHERE public_reference = ?", { expInv.reference })
    ok, view = S.PayInvoice(A, A, expInv.reference, 'cash')
    check('pay.expired_invoice_cannot_be_paid', ok == false and view == 'not_pending')
    S.ExpireDue()
    check('expiry.sweep_marks_expired', status(expInv.reference) == 'expired')
    check('expiry.invalid_expiry_rejected', select(2, create({ expiresInSeconds = 5 })) == 'invalid_expiry')

    -- DESTINATIONS --------------------------------------------------------------------
    local _, chInv = create({ amount = 700, destination = { type = 'character', id = B } })
    ledger.credits = {}
    local aCash = ledger.cash[A]
    ok = S.PayInvoice(A, A, chInv.reference, 'cash')
    check('dest.character_credited_exactly_once', ok == true and #ledger.credits == 1 and ledger.credits[1][1] == B and ledger.credits[1][2] == 700 and ledger.cash[A] == aCash - 700)
    check('dest.money_conserved', (aCash - ledger.cash[A]) == 700 and ledger.credits[1][2] == 700)

    local _, failInv = create({ amount = 800, destination = { type = 'character', id = B } })
    ledger.failCredit = true
    aCash = ledger.cash[A]
    ok, view = S.PayInvoice(A, A, failInv.reference, 'cash')
    check('dest.credit_failure_refunds_payer', ok == false and view == 'settlement_failed' and ledger.cash[A] == aCash and ledger.refunds >= 1)
    check('dest.credit_failure_returns_invoice_to_pending', status(failInv.reference) == 'pending' and row(failInv.reference).settlement_note == 'credit_failed_refunded')
    ledger.failCredit = false
    ok = S.PayInvoice(A, A, failInv.reference, 'cash')
    check('dest.retry_after_failure_succeeds_once', ok == true and ledger.cash[A] == aCash - 800 and status(failInv.reference) == 'paid')

    -- credit AND refund both fail -> stays settling for reconciliation
    local _, stuckInv = create({ amount = 900, destination = { type = 'character', id = B } })
    ledger.failCredit, ledger.failRefund = true, true
    ok, view = S.PayInvoice(A, A, stuckInv.reference, 'cash')
    check('dest.refund_failure_keeps_invoice_settling', ok == false and status(stuckInv.reference) == 'settling' and row(stuckInv.reference).settlement_note == 'manual_review_refund_failed')
    check('dest.settling_invoice_cannot_be_repaid_or_voided', select(2, S.PayInvoice(A, A, stuckInv.reference, 'cash')) == 'not_pending' and select(2, S.VoidInvoice(P, stuckInv.reference, 'try')) == 'not_pending')
    ledger.failCredit, ledger.failRefund = false, false
    MySQL.update.await("UPDATE cm_billing_invoices SET settle_started_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 600 SECOND) WHERE public_reference = ?", { stuckInv.reference })
    ledger.hasDebit, ledger.hasRefund, ledger.creditEvidence = true, false, false
    local creditsBefore = #ledger.credits
    S.ReconcileSettling()
    check('recover.charged_but_uncredited_is_completed_once', status(stuckInv.reference) == 'paid' and #ledger.credits == creditsBefore + 1 and row(stuckInv.reference).settlement_note == '')
    S.ReconcileSettling()
    check('recover.second_sweep_does_nothing', #ledger.credits == creditsBefore + 1)

    local _, noChargeInv = create({ amount = 50 })
    MySQL.update.await("UPDATE cm_billing_invoices SET status = 'settling', settle_token = 'tok', settle_started_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 600 SECOND), payment_account = 'cash' WHERE public_reference = ?", { noChargeInv.reference })
    ledger.hasDebit = false
    S.ReconcileSettling()
    check('recover.no_charge_returns_to_pending', status(noChargeInv.reference) == 'pending')
    ledger.hasDebit = false

    -- family destination with partial acceptance
    local _, famInv = create({ amount = 1000, destination = { type = 'family', id = 7 } })
    aCash, ledger.refunds = ledger.cash[A], 0
    ok = S.PayInvoice(A, A, famInv.reference, 'cash')
    check('dest.family_partial_accept_refunds_remainder', ok == true and ledger.cash[A] == aCash - 500 and ledger.refunds == 1 and row(famInv.reference).settlement_note == 'partial_refund_500')
    check('dest.invalid_family_rejected', select(2, create({ destination = { type = 'family', id = 99 } })) == 'invalid_destination')

    -- VOID ----------------------------------------------------------------------------
    local _, voidInv = create({ amount = 400 })
    check('void.unauthorized_provider_rejected', select(2, S.VoidInvoice('qa-billing-other', voidInv.reference, 'nope')) == 'forbidden')
    check('void.untrusted_caller_rejected', select(2, S.VoidInvoice('random-resource', voidInv.reference, 'nope')) == 'forbidden')
    check('void.reason_required', select(2, S.VoidInvoice(P, voidInv.reference, '  ')) == 'invalid_request')
    check('void.issuer_can_void_pending', S.VoidInvoice(P, voidInv.reference, 'Issued in error') == true and status(voidInv.reference) == 'voided')
    check('void.records_reason_and_time', row(voidInv.reference).void_reason == 'Issued in error' and S.GetRow(voidInv.reference).status == 'voided')
    check('void.voided_invoice_cannot_be_paid', select(2, S.PayInvoice(A, A, voidInv.reference, 'cash')) == 'not_pending')
    check('void.paid_invoice_cannot_be_voided', select(2, S.VoidInvoice(P, cashInv.reference, 'late')) == 'not_pending')
    check('void.unknown_reference', select(2, S.VoidInvoice(P, 'INV-NOSUCH1', 'x')) == 'not_found')

    -- PHONE / NOTIFICATIONS -----------------------------------------------------------
    S.Notifier = { created = function() error('phone exploded') end, paid = function() error('hud exploded') end }
    local notifOk, notifInv = create({ amount = 150 })
    Wait(100)
    check('phone.creation_succeeds_when_notification_fails', notifOk == true and status(notifInv.reference) == 'pending')
    ok = S.PayInvoice(A, A, notifInv.reference, 'cash')
    Wait(100)
    check('phone.payment_succeeds_when_notification_fails', ok == true and status(notifInv.reference) == 'paid')
    S.Notifier = origNotifier
    local message = S.CreatedMessage(12500)
    check('phone.message_is_minimal', message == 'New invoice received - $12,500' and not message:find('Test service', 1, true) and not message:find('INV-', 1, true))

    -- Real cm-phone trusted-export path (allowlist change), using a synthetic character; its phone rows are removed below.
    if GetResourceState('cm-phone') == 'started' then
        local phoneOk, sent = pcall(function() return exports['cm-phone']:SendSystemMessage(A, 'Billing', S.CreatedMessage(1200)) end)
        local stored = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_phone_conversation_members WHERE character_id = ?', { A })) or 0
        check('phone.trusted_export_delivers_system_message', phoneOk == true and sent == true and stored == 1, tostring(sent))
        local body = MySQL.scalar.await([[SELECT m.body FROM cm_phone_messages m JOIN cm_phone_conversation_members cm ON cm.conversation_id = m.conversation_id
            WHERE cm.character_id = ? ORDER BY m.id DESC LIMIT 1]], { A })
        check('phone.delivered_text_is_minimal', body == 'New invoice received - $1,200')
        MySQL.query.await('DELETE m FROM cm_phone_messages m JOIN cm_phone_conversation_members cm ON cm.conversation_id = m.conversation_id WHERE cm.character_id = ?', { A })
        MySQL.query.await('DELETE c FROM cm_phone_conversations c JOIN cm_phone_conversation_members cm ON cm.conversation_id = c.id WHERE cm.character_id = ?', { A })
        MySQL.query.await('DELETE FROM cm_phone_conversation_members WHERE character_id = ?', { A })
    end

    -- PERSISTENCE ---------------------------------------------------------------------
    local pendingList, historyList = S.ListInvoices(A, 'pending'), S.ListInvoices(A, 'history')
    local function has(list, ref) for _, i in ipairs(list) do if i.reference == ref then return true end end return false end
    check('persist.pending_listed_from_db', has(pendingList, inv.reference) and has(pendingList, big.reference))
    check('persist.paid_and_voided_in_history', has(historyList, cashInv.reference) and has(historyList, voidInv.reference) and has(historyList, expInv.reference))
    check('persist.history_not_in_pending', not has(pendingList, cashInv.reference) and not has(pendingList, voidInv.reference))
    check('persist.offline_invoice_waits_for_login', #S.ListInvoices(D, 'pending') == 1)
    check('persist.events_journal_written', (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_billing_events e JOIN cm_billing_invoices i ON i.id = e.invoice_id WHERE i.recipient_character_id LIKE ?', { PREFIX .. '%' })) or 0) > 10)
    check('persist.unique_reference_constraint', pcall(function()
        MySQL.insert.await("INSERT INTO cm_billing_invoices (public_reference, recipient_character_id, issuer_type, issuer_label, issuer_resource, destination_type, amount, label) VALUES (?, 'qa-bill-x', 'system', 'x', 'x', 'city', 1, 'x')", { inv.reference })
    end) == false)

    S.Money, S.Destinations, S.Ledger, S.Notifier = origMoney, origDest, origLedger, origNotifier
    S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
    cleanup()
    check('cleanup.rows_removed', (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_billing_invoices WHERE recipient_character_id LIKE ?', { PREFIX .. '%' })) or 1) == 0)
    print(('[cm-billing:selftest] RESULT %s: %d checks, %d failed'):format(failed == 0 and 'PASS' or 'FAIL', #results, failed))
end

RegisterCommand('cm_billing_selftest', function(source)
    if source ~= 0 then return end
    if not enabled() then print('[cm-billing:selftest] BLOCKED: requires cm_environment=development') return end
    if not S.AwaitSchema() then print('[cm-billing:selftest] BLOCKED: schema not ready') return end
    local ok, err = pcall(run)
    if not ok then
        S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
        pcall(cleanup)
        print('[cm-billing:selftest] ERROR ' .. tostring(err))
    end
    -- refund foundation suite (server/selftest_refund.lua)
    if S.RefundOwnerSelfTest then pcall(S.RefundOwnerSelfTest) end
    if S.RefundSelfTest then
        local rok, rerr = pcall(S.RefundSelfTest)
        if not rok then
            S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
            pcall(cleanup)
            print('[cm-billing:refund-selftest] ERROR ' .. tostring(rerr))
        end
    end
    if S.RefundJournalSelfTest then
        local jok, jerr = pcall(S.RefundJournalSelfTest)
        if not jok then pcall(cleanup) print('[cm-billing:journal-selftest] ERROR ' .. tostring(jerr)) end
    end
    if S.PaymentJournalSelfTest then
        local yok, yerr = pcall(S.PaymentJournalSelfTest)
        if not yok then pcall(cleanup) print('[cm-billing:payment-selftest] ERROR ' .. tostring(yerr)) end
    end
    if S.PolicySelfTest then
        local pok, perr = pcall(S.PolicySelfTest)
        if not pok then
            S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
            pcall(cleanup)
            print('[cm-billing:policy-selftest] ERROR ' .. tostring(perr))
        end
    end
end, true)
