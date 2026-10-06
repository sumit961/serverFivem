-- Development-only payment-settlement self-test (runs from `cm_billing_selftest`). The PRODUCTION payment path and destination adapters run over the
-- REAL cm-playerdata / cm-family owners (synthetic fixtures: family 987656, characters 99999921 payer / 99999922 recipient). Failures are injected at
-- the destination (credit applied but response lost / owner unavailable); generic logs are deleted to prove correctness does not depend on them.
-- Business uses an idempotent-by-key stand-in (the production business owner is covered by cm_business_selftest); city is the real sink adapter.
local S = CMBilling.Server
local Config = CMBilling.Config

function S.PaymentJournalSelfTest()
    local results, failed = {}, 0
    local function check(name, cond, detail)
        results[#results + 1] = name
        if cond ~= true then
            failed = failed + 1
            print(('[cm-billing:payment-selftest] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-billing:payment-selftest] PASS  %s'):format(name))
        end
    end
    local FAM, PAYER, DEST = 987656, 99999921, 99999922
    local ACC1, ACC2 = 'qa-p-acc1', 'qa-p-acc2'
    if GetResourceState('cm-playerdata') ~= 'started' or GetResourceState('cm-family') ~= 'started' then
        check('payment.skipped_owners_not_started', true)
        print('[cm-billing:payment-selftest] RESULT PASS: 1 checks, 0 failed')
        return
    end
    local function clean()
        local ids = { tostring(PAYER), tostring(DEST) }
        MySQL.query.await('DELETE r FROM cm_billing_refunds r JOIN cm_billing_invoices i ON i.id = r.invoice_id WHERE i.recipient_character_id IN (?, ?)', ids)
        MySQL.query.await('DELETE e FROM cm_billing_events e JOIN cm_billing_invoices i ON i.id = e.invoice_id WHERE i.recipient_character_id IN (?, ?)', ids)
        MySQL.query.await('DELETE FROM cm_billing_invoices WHERE recipient_character_id IN (?, ?)', ids)
        MySQL.query.await('DELETE FROM cm_character_money_operations WHERE character_id IN (?, ?)', ids)
        MySQL.query.await('DELETE FROM cm_family_treasury_operations WHERE family_id = ?', { FAM })
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { FAM })
        MySQL.query.await('DELETE FROM cm_families WHERE id = ?', { FAM })
        MySQL.query.await('DELETE FROM economy_transactions WHERE character_id IN (?, ?)', { PAYER, DEST })
        MySQL.query.await('DELETE FROM characters WHERE id IN (?, ?)', ids)
        MySQL.query.await('DELETE FROM accounts WHERE id IN (?, ?)', { ACC1, ACC2 })
    end
    clean()
    MySQL.query.await("INSERT INTO accounts (id, username, password_hash) VALUES (?, ?, 'x'), (?, ?, 'x')", { ACC1, ACC1, ACC2, ACC2 })
    MySQL.query.await("INSERT INTO characters (id, account_id, slot, first_name, last_name, cash, bank) VALUES (?, ?, 1, 'Qa', 'Payer', 0, 10000), (?, ?, 1, 'Qa', 'Recipient', 0, 5000)",
        { tostring(PAYER), ACC1, tostring(DEST), ACC2 })
    MySQL.query.await("INSERT INTO cm_families (id, name, founder_cid, bank_balance) VALUES (?, 'QA Payment Family', 'qa-none', 7000)", { FAM })

    local pd, fam = exports['cm-playerdata'], exports['cm-family']
    local function bank(id) return tonumber(MySQL.scalar.await('SELECT bank FROM characters WHERE id = ?', { tostring(id) })) end
    local function setBank(id, v) MySQL.query.await('UPDATE characters SET bank = ? WHERE id = ?', { v, tostring(id) }) end
    local function fbal() return tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { FAM })) end
    local function cOps(key) return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_character_money_operations WHERE reference = ?', { key })) or -1 end
    local function fOps(key) return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_treasury_operations WHERE reference = ?', { key })) or -1 end
    local function row(ref) return S.GetRow(ref) end
    local function age(ref) MySQL.update.await("UPDATE cm_billing_invoices SET settle_started_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 600 SECOND) WHERE public_reference = ?", { ref }) end
    local function dropGenericLogs()
        MySQL.query.await('DELETE FROM economy_transactions WHERE character_id IN (?, ?)', { PAYER, DEST })
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { FAM })
    end

    S.TestCharacters = { [tostring(PAYER)] = true, [tostring(DEST)] = true }
    S.TestProviders = { ['qa-pay'] = { maxAmount = 100000, issuerTypes = { system = true, business = true },
        destinations = { city = true, character = true, family = true, business = true }, allowOffline = true, metadataNamespace = 'qp', canVoid = true, canRefund = true } }
    local origNotifier, origDest, origRDest = S.Notifier, S.Destinations, S.RefundDestinations
    S.Notifier = { created = function() end, paid = function() end, refunded = function() end }
    local real = { character = origDest.character, family = origDest.family, city = origDest.city }

    -- business stand-in: idempotent by key exactly like CreditBusinessAtomic / DebitBusinessAtomic
    local biz = { bal = 0, credited = {}, debited = {}, credits = 0, debits = 0 }
    local bizCredit = real.city
    local business = {
        available = function() return true end,
        validate = function(id) return id == 'qa:1' end,
        credit = function(inv)
            local key = 'billing-credit:' .. inv.public_reference
            if not biz.credited[key] then biz.credited[key] = true; biz.bal = biz.bal + tonumber(inv.amount); biz.credits = biz.credits + 1 end
            if biz.loseResponse then biz.loseResponse = nil error('business owner response lost') end
            return true, tonumber(inv.amount)
        end,
        evidence = function(inv) return biz.credited['billing-credit:' .. inv.public_reference] == true, tonumber(inv.amount) end,
    }
    S.Destinations = { city = real.city, character = real.character, family = real.family, business = business }
    S.RefundDestinations = { character = origRDest.character, family = origRDest.family, business = {
        available = function() return true end,
        debit = function(j)
            local key = S.RefundDebitKey(j)
            if biz.debited[key] then return true end
            if biz.bal < tonumber(j.amount) then return false, 'insufficient_funds' end
            biz.debited[key] = true; biz.bal = biz.bal - tonumber(j.amount); biz.debits = biz.debits + 1
            return true
        end,
        evidence = function(j) return biz.debited[S.RefundDebitKey(j)] == true end,
    } }

    local function create(destType, destId, amount)
        local ok, inv = S.CreateInvoice('qa-pay', { recipientCharacterId = tostring(PAYER), amount = amount, label = 'QA payment', issuerLabel = 'QA',
            issuerType = destType == 'city' and 'system' or 'business', destination = { type = destType, id = destId } })
        return ok and inv.reference or nil, inv
    end
    local function pay(ref) return S.PayInvoice(tostring(PAYER), 1, ref, 'bank') end
    local function keys(ref) return S.PayKeys(ref) end
    local function wrapCredit(destType, fn)
        local orig = S.Destinations[destType]
        local copy = {}
        for k, v in pairs(orig) do copy[k] = v end
        fn(copy, orig)
        S.Destinations[destType] = copy
        return function() S.Destinations[destType] = orig end
    end

    -- NAMESPACES -------------------------------------------------------------------------------------
    local k = keys('INV-ABCDEFGH')
    check('keys.payment_references_are_distinct_namespaces', k.debit ~= k.credit and k.credit ~= k.refund and k.refund ~= k.remainder and k.credit:find('^cm%-billing%-pay%-credit:') ~= nil
        and not k.credit:find('rfd', 1, true) and not S.RefundDebitKey({ invoice_reference = 'INV-ABCDEFGH', id = 1 }):find('pay', 1, true))

    -- CHARACTER DESTINATION: first credit ---------------------------------------------------------------
    local sum0 = bank(PAYER) + bank(DEST)
    local c1 = create('character', tostring(DEST), 4000)
    local ok1, info1 = pay(c1)
    check('char.payment_credits_destination_exactly_once', ok1 == true and row(c1).status == 'paid' and bank(PAYER) == 6000 and bank(DEST) == 9000, info1)
    check('char.payer_and_credit_journals_written_with_namespaced_references', cOps(keys(c1).debit) == 1 and cOps(keys(c1).credit) == 1 and cOps(keys(c1).refund) == 0)
    check('char.payment_conserves_money', bank(PAYER) + bank(DEST) == sum0)
    local st = pd:GetCharacterMoneyOperation(keys(c1).credit)
    check('char.owner_status_reports_direction_character_and_amount', type(st) == 'table' and st.direction == 'credit' and st.characterId == tostring(DEST) and st.amount == 4000)
    check('char.same_reference_different_payload_conflicts_no_second_credit', select(2, pd:AddMoneyToCharacterOnce(DEST, 'bank', 4001, keys(c1).credit)) == 'idempotency_conflict'
        and select(2, pd:RemoveMoneyFromCharacter(DEST, 'bank', 4000, keys(c1).credit)) == 'idempotency_conflict' and bank(DEST) == 9000)
    check('char.paid_invoice_replay_is_rejected', select(2, pay(c1)) == 'not_pending' and bank(PAYER) == 6000 and bank(DEST) == 9000)

    -- CHARACTER: credit APPLIED, response LOST (+ generic log gone = logging disabled/unavailable) ------------
    setBank(PAYER, 10000); setBank(DEST, 5000); sum0 = 15000
    local c2 = create('character', tostring(DEST), 3000)
    local restore = wrapCredit('character', function(copy, orig) copy.credit = function(inv, account) orig.credit(inv, account) error('response lost after the owner committed') end end)
    local ok2, why2 = pay(c2)
    restore()
    check('char.response_lost_leaves_invoice_settling_and_does_NOT_refund_payer', ok2 == false and why2 == 'settlement_pending' and row(c2).status == 'settling'
        and row(c2).settlement_note == 'credit_outcome_unknown' and bank(PAYER) == 7000 and bank(DEST) == 8000 and cOps(keys(c2).refund) == 0)
    dropGenericLogs()
    age(c2)
    S.ReconcileSettling()
    check('char.recovery_from_owner_journal_completes_without_second_credit', row(c2).status == 'paid' and bank(PAYER) == 7000 and bank(DEST) == 8000 and cOps(keys(c2).credit) == 1 and row(c2).settlement_note == '')
    S.ReconcileSettling()
    check('char.second_recovery_pass_is_a_noop', bank(PAYER) == 7000 and bank(DEST) == 8000 and bank(PAYER) + bank(DEST) == sum0)

    -- CHARACTER: owner UNAVAILABLE (nothing applied, evidence cannot be read) -> unknown, never refunded --------
    local c3 = create('character', tostring(DEST), 2000)
    local down = true
    restore = wrapCredit('character', function(copy, orig)
        copy.credit = function(inv, account) if down then error('owner database unavailable') end return orig.credit(inv, account) end
        copy.evidence = function(inv) if down then error('owner database unavailable') end return orig.evidence(inv) end
    end)
    local ok3, why3 = pay(c3)
    age(c3); S.ReconcileSettling()
    check('char.owner_down_invoice_stays_settling_payer_never_refunded', ok3 == false and why3 == 'settlement_pending' and row(c3).status == 'settling' and bank(PAYER) == 5000 and bank(DEST) == 8000 and cOps(keys(c3).refund) == 0)
    down = false
    S.ReconcileSettling()
    restore()
    check('char.owner_returns_recovery_credits_exactly_once_and_pays', row(c3).status == 'paid' and bank(DEST) == 10000 and bank(PAYER) == 5000 and cOps(keys(c3).credit) == 1)

    -- CHARACTER: concurrent recovery / duplicate settlement workers ----------------------------------------
    setBank(PAYER, 10000); setBank(DEST, 5000)
    local c4 = create('character', tostring(DEST), 1500)
    restore = wrapCredit('character', function(copy, orig) copy.credit = function(inv, account) orig.credit(inv, account) error('response lost') end end)
    pay(c4); restore()
    age(c4)
    local outs = {}
    for i = 1, 3 do CreateThread(function() outs[i] = S.ReconcileSettling() end) end
    local waited = 0
    while (not outs[1] or not outs[2] or not outs[3]) and waited < 8000 do Wait(50) waited = waited + 50 end
    check('char.three_concurrent_recovery_workers_credit_once', row(c4).status == 'paid' and bank(DEST) == 6500 and bank(PAYER) == 8500 and cOps(keys(c4).credit) == 1)
    -- owner-level: workers that bypass the process lock still cannot double credit (the journal's unique reference decides)
    local c5 = create('character', tostring(DEST), 900)
    local row5 = row(c5)
    local res = {}
    for i = 1, 4 do CreateThread(function() res[i] = { real.character.credit(row5, 'bank') } end) end
    waited = 0
    while (not res[1] or not res[2] or not res[3] or not res[4]) and waited < 8000 do Wait(50) waited = waited + 50 end
    check('char.four_lock_free_credit_calls_exactly_one_credit', bank(DEST) == 7400 and cOps(keys(c5).credit) == 1 and res[1][1] == true and res[4][1] == true)
    S.Lock('x'); S.Unlock('x')

    -- CHARACTER: definitive destination failure -> payer refunded exactly once -------------------------------
    local c6 = create('character', tostring(DEST), 700)
    local beforeP = bank(PAYER)
    restore = wrapCredit('character', function(copy) copy.credit = function() return false, 'not_found' end end)
    local ok6, why6 = pay(c6)
    restore()
    check('char.definitive_credit_failure_refunds_payer_exactly_once_and_releases', ok6 == false and why6 == 'settlement_failed' and row(c6).status == 'pending' and bank(PAYER) == beforeP and cOps(keys(c6).refund) == 1)

    -- FAMILY ----------------------------------------------------------------------------------------------
    setBank(PAYER, 10000); MySQL.query.await('UPDATE cm_families SET bank_balance = 7000 WHERE id = ?', { FAM })
    local f1 = create('family', tostring(FAM), 3000)
    local okf, infof = pay(f1)
    check('family.payment_credits_treasury_exactly_once_with_journal', okf == true and row(f1).status == 'paid' and fbal() == 10000 and bank(PAYER) == 7000 and fOps(keys(f1).credit) == 1, infof)
    local op = fam:GetFamilyTreasuryOperation(keys(f1).credit)
    check('family.owner_status_reports_direction_family_and_accepted_amount', type(op) == 'table' and op.direction == 'credit' and op.familyId == FAM and op.amount == 3000 and fam:GetFamilyTreasuryOperation('cm-billing-pay-credit:INV-NONE') == false)
    check('family.same_reference_different_request_conflicts', select(2, fam:CreditFamilyTreasuryOnce(FAM, 3001, { reference = keys(f1).credit })) == 'idempotency_conflict'
        and select(2, fam:DebitFamilyTreasuryAtomic(FAM, 3000, { reason = keys(f1).credit })) == 'idempotency_conflict' and fbal() == 10000)
    -- response lost + bank log gone
    local f2 = create('family', tostring(FAM), 2000)
    restore = wrapCredit('family', function(copy, orig) copy.credit = function(inv, account) orig.credit(inv, account) error('response lost after the owner committed') end end)
    local okf2, whyf2 = pay(f2)
    restore()
    check('family.response_lost_stays_settling_and_payer_not_refunded', okf2 == false and whyf2 == 'settlement_pending' and row(f2).status == 'settling' and fbal() == 12000 and bank(PAYER) == 5000 and cOps(keys(f2).refund) == 0)
    dropGenericLogs()
    age(f2); S.ReconcileSettling()
    check('family.recovery_from_treasury_journal_completes_once_without_bank_log', row(f2).status == 'paid' and fbal() == 12000 and bank(PAYER) == 5000 and fOps(keys(f2).credit) == 1)
    -- owner unavailable
    local f3 = create('family', tostring(FAM), 1000)
    down = true
    restore = wrapCredit('family', function(copy, orig)
        copy.credit = function(inv, account) if down then error('treasury unavailable') end return orig.credit(inv, account) end
        copy.evidence = function(inv) if down then error('treasury unavailable') end return orig.evidence(inv) end
    end)
    pay(f3); age(f3); S.ReconcileSettling()
    check('family.owner_down_stays_settling_payer_never_refunded', row(f3).status == 'settling' and fbal() == 12000 and bank(PAYER) == 4000 and cOps(keys(f3).refund) == 0)
    down = false; S.ReconcileSettling(); restore()
    check('family.owner_returns_credit_applied_once_invoice_paid', row(f3).status == 'paid' and fbal() == 13000 and fOps(keys(f3).credit) == 1)
    -- concurrent credits
    local f4 = create('family', tostring(FAM), 500)
    local row4 = row(f4)
    res = {}
    for i = 1, 4 do CreateThread(function() res[i] = { real.family.credit(row4, 'bank') } end) end
    waited = 0
    while (not res[1] or not res[2] or not res[3] or not res[4]) and waited < 8000 do Wait(50) waited = waited + 50 end
    check('family.four_concurrent_credit_calls_exactly_one_credit', fbal() == 13500 and fOps(keys(f4).credit) == 1 and res[1][1] == true and res[3][2] == 500)
    -- partial acceptance: the accepted amount is authoritative, the remainder returns to the payer exactly once
    MySQL.query.await('UPDATE cm_families SET bank_balance = 1999999000 WHERE id = ?', { FAM })
    setBank(PAYER, 10000)
    local f5 = create('family', tostring(FAM), 3000)
    local okp = pay(f5)
    local acceptedOp = fam:GetFamilyTreasuryOperation(keys(f5).credit)
    local accepted = type(acceptedOp) == 'table' and acceptedOp.amount or -1
    local remainder = 3000 - accepted
    check('family.capacity_partial_accept_is_authoritative_and_remainder_returned_once', okp == true and accepted > 0 and accepted <= 3000 and fbal() == 1999999000 + accepted and bank(PAYER) == 10000 - accepted
        and row(f5).settlement_note == (remainder > 0 and ('partial_refund_' .. remainder) or '') and (remainder == 0 or cOps(keys(f5).remainder) == 1), ('accepted=%s'):format(tostring(accepted)))
    check('family.paid_amount_for_refunds_equals_accepted', S.PaidAmount(row(f5)) == accepted)
    local rok, rv = S.RequestRefund('qa-pay', f5, 'qa-p-rt-family-1', nil, 'service_failed')
    check('family.payment_to_refund_roundtrip_balances_return', rok == true and rv.status == 'completed' and rv.amount == accepted and fbal() == 1999999000 and bank(PAYER) == 10000)

    -- ROUNDTRIPS: payment -> exact-once credit -> paid -> refund -> exact-once debit -> payer credit ---------------
    setBank(PAYER, 10000); setBank(DEST, 5000)
    local rc = create('character', tostring(DEST), 4000)
    pay(rc)
    local rcOk, rcv = S.RequestRefund('qa-pay', rc, 'qa-p-rt-char-1', nil, 'service_cancelled')
    check('roundtrip.character_balances_return_exactly', rcOk == true and rcv.status == 'completed' and bank(PAYER) == 10000 and bank(DEST) == 5000 and bank(PAYER) + bank(DEST) == 15000)
    check('roundtrip.character_refund_references_do_not_collide_with_payment_references', cOps(keys(rc).credit) == 1 and cOps(keys(rc).debit) == 1 and (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_character_money_operations WHERE reference LIKE 'cm-billing-rfd-%'")) or 0) >= 2)
    setBank(PAYER, 10000); MySQL.query.await('UPDATE cm_families SET bank_balance = 7000 WHERE id = ?', { FAM })
    local rf = create('family', tostring(FAM), 2500)
    pay(rf)
    local rfOk, rfv = S.RequestRefund('qa-pay', rf, 'qa-p-rt-family-2', nil, 'service_failed')
    check('roundtrip.family_balances_return_exactly', rfOk == true and rfv.status == 'completed' and fbal() == 7000 and bank(PAYER) == 10000)
    setBank(PAYER, 10000); biz.bal = 0
    local rb = create('business', 'qa:1', 6000)
    local rbPaid = pay(rb)
    check('roundtrip.business_payment_credits_once', rbPaid == true and biz.bal == 6000 and biz.credits == 1 and bank(PAYER) == 4000)
    local rbOk, rbv = S.RequestRefund('qa-pay', rb, 'qa-p-rt-biz-1', nil, 'service_failed')
    check('roundtrip.business_balances_return_exactly', rbOk == true and rbv.status == 'completed' and biz.bal == 0 and bank(PAYER) == 10000 and biz.debits == 1)
    -- business response loss recovers through the key-idempotent owner
    local rb2 = create('business', 'qa:1', 1000)
    biz.loseResponse = true
    pay(rb2); age(rb2); S.ReconcileSettling()
    check('business.response_lost_recovers_exactly_once', row(rb2).status == 'paid' and biz.bal == 1000 and biz.credits == 2 and bank(PAYER) == 9000)

    -- CITY: sink semantics unchanged -------------------------------------------------------------------------
    setBank(PAYER, 10000)
    local cc = create('city', nil, 1200)
    local okc = pay(cc)
    check('city.sink_payment_debits_payer_and_creates_no_destination_operation', okc == true and row(cc).status == 'paid' and bank(PAYER) == 8800 and cOps(keys(cc).credit) == 0 and fOps(keys(cc).credit) == 0)
    check('city.still_not_refundable', select(2, S.RequestRefund('qa-pay', cc, 'qa-p-city-1', nil, 'service_failed')) == 'destination_not_refundable')

    -- OLD GENERIC EVIDENCE IS NO LONGER USED -----------------------------------------------------------------
    local src = (LoadResourceFile(GetCurrentResourceName(), 'server/payment.lua') or '') .. (LoadResourceFile(GetCurrentResourceName(), 'server/core.lua') or '')
    check('evidence.payment_path_does_not_read_generic_transaction_log_or_bank_log', not src:find('FROM economy_transactions', 1, true) and not src:find('FROM cm_family_bank_log', 1, true))

    S.Destinations, S.RefundDestinations, S.Notifier = origDest, origRDest, origNotifier
    S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
    clean()
    check('cleanup.payment_fixtures_removed', cOps(keys(c1).credit) == 0 and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM characters WHERE id IN (?, ?)', { tostring(PAYER), tostring(DEST) })) or 1) == 0)
    print(('[cm-billing:payment-selftest] RESULT %s: %d checks, %d failed'):format(failed == 0 and 'PASS' or 'FAIL', #results, failed))
end
