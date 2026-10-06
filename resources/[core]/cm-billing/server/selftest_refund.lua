-- Development-only refund self-test (runs after the main suite from `cm_billing_selftest`; cm_environment=development, console only).
-- Real MySQL for invoices + refund journal; the money owners are in-memory stand-ins with crash/timeout injection (applied-then-error,
-- error-before-apply, insufficient funds). Synthetic characters "qa-bill-*"; every row is removed afterwards.
local S = CMBilling.Server
local Config = CMBilling.Config

local PREFIX = 'qa-bill-'

local function cleanup()
    local like = PREFIX .. '%'
    MySQL.query.await('DELETE r FROM cm_billing_refunds r JOIN cm_billing_invoices i ON i.id = r.invoice_id WHERE i.recipient_character_id LIKE ?', { like })
    MySQL.query.await('DELETE e FROM cm_billing_events e JOIN cm_billing_invoices i ON i.id = e.invoice_id WHERE i.recipient_character_id LIKE ?', { like })
    MySQL.query.await('DELETE FROM cm_billing_invoices WHERE recipient_character_id LIKE ?', { like })
end
S.RefundSelfTestCleanup = cleanup

function S.RefundSelfTest()
    local results, failed = {}, 0
    local function check(name, cond, detail)
        results[#results + 1] = name
        if cond ~= true then
            failed = failed + 1
            print(('[cm-billing:refund-selftest] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-billing:refund-selftest] PASS  %s'):format(name))
        end
    end

    cleanup()
    local A, B = PREFIX .. 'a', PREFIX .. 'b' -- A = payer, B = character destination
    S.TestCharacters = { [A] = true, [B] = true }
    S.TestProviders = {
        ['qa-refund'] = { maxAmount = 100000, issuerTypes = { system = true, business = true }, destinations = { city = true, character = true, family = true, business = true },
                          allowOffline = true, metadataNamespace = 'qa', canVoid = true, canRefund = true },
        ['qa-refund-other'] = { maxAmount = 100000, issuerTypes = { system = true }, destinations = { city = true }, allowOffline = true, metadataNamespace = 'oth', canVoid = true, canRefund = true },
        ['qa-refund-none'] = { maxAmount = 100000, issuerTypes = { system = true }, destinations = { city = true }, allowOffline = true, metadataNamespace = 'non', canVoid = true },
    }
    local P = 'qa-refund'

    -- stand-in money owners --------------------------------------------------------------
    local payerBal = { bank = { [A] = 1000000 }, cash = { [A] = 0 } }
    local dest = {} -- ['business:qa1'] = balance ; ['character:B'] ; ['family:7']
    local applied = { debit = {}, credit = {} }
    local counts = { debit = 0, credit = 0 }
    local inj = {}
    local origMoney, origDest, origNotifier, origDestRefund, origPayer = S.Money, S.Destinations, S.Notifier, S.RefundDestinations, S.RefundPayer
    local origCfg = { city = Config.Destinations.city.refundable }

    S.Money = {
        Debit = function(src, account, amount) if (payerBal[account][src] or 0) < amount then return false end payerBal[account][src] = payerBal[account][src] - amount return true end,
        CreditCharacter = function(cid, account, amount) payerBal[account][cid] = (payerBal[account][cid] or 0) + amount return true end,
        Balance = function(src, account) return payerBal[account][src] or 0 end,
    }
    local function destKey(type_, id) return type_ .. ':' .. tostring(id) end
    local function payDest(type_, accept)
        return {
            available = function() return true end,
            validate = function(id) return type_ == 'business' and (id == 'qa:1' or id == 'mechanic:qa1') or type_ == 'family' and tonumber(id) == 7 or type_ == 'character' and id == B end,
            credit = function(inv)
                local k = destKey(type_, inv.destination_id)
                local take = accept and accept(inv) or tonumber(inv.amount)
                dest[k] = (dest[k] or 0) + take
                return true, take
            end,
            evidence = function() return false end,
        }
    end
    S.Destinations = { city = origDest.city, business = payDest('business'), character = payDest('character'), family = payDest('family', function(inv) return math.floor(tonumber(inv.amount) / 2) end) }
    S.Notifier = { created = function() end, paid = function() end }

    -- refund-side owner doubles: idempotent by key, injectable failures
    local function refundDest(type_)
        return {
            available = function() return inj.destDown ~= true end,
            debit = function(j)
                local key = S.RefundDebitKey(j)
                if inj.debitWait then Wait(inj.debitWait) end
                if inj.debitThrowBefore then inj.debitThrowBefore = nil error('owner timeout (not applied)') end
                if applied.debit[key] then return true end
                local k = destKey(type_, j.destination_id)
                if (dest[k] or 0) < tonumber(j.amount) then return false, 'insufficient_funds' end
                dest[k] = dest[k] - tonumber(j.amount)
                applied.debit[key] = true
                counts.debit = counts.debit + 1
                if inj.debitThrowAfter then inj.debitThrowAfter = nil error('owner timeout (applied, response lost)') end
                return true
            end,
            evidence = function(j) return applied.debit[S.RefundDebitKey(j)] == true end,
        }
    end
    S.RefundDestinations = { business = refundDest('business'), character = refundDest('character'), family = refundDest('family') }
    S.RefundPayer = {
        Credit = function(j)
            local key = S.RefundCreditKey(j)
            if inj.creditThrowBefore then inj.creditThrowBefore = nil error('credit timeout (not applied)') end
            if applied.credit[key] then return true end
            payerBal[j.payment_account][j.payer_character_id] = (payerBal[j.payment_account][j.payer_character_id] or 0) + tonumber(j.amount)
            applied.credit[key] = true
            counts.credit = counts.credit + 1
            if inj.creditThrowAfter then inj.creditThrowAfter = nil error('credit timeout (applied, response lost)') end
            return true
        end,
        Evidence = function(j) return applied.credit[S.RefundCreditKey(j)] == true end,
    }

    local seq = 0
    local function ref(prefix) seq = seq + 1 return ('%s-%d-%d'):format(prefix or 'qa-rfd', GetGameTimer(), seq) end
    local function paidInvoice(destType, destId, amount, provider)
        local ok, inv = S.CreateInvoice(provider or P, { recipientCharacterId = A, amount = amount, label = 'QA service', issuerLabel = 'QA Garage',
            issuerType = destType == 'city' and 'system' or 'business', destination = { type = destType, id = destId } })
        if not ok then return nil, inv end
        local paid, info = S.PayInvoice(A, A, inv.reference, 'bank')
        if not paid then return nil, info end
        return inv.reference
    end
    local function invRow(r) return S.GetRow(r) end
    local function total() local t = payerBal.bank[A] + payerBal.cash[A] for _, v in pairs(dest) do t = t + v end return t end

    -- ELIGIBILITY ------------------------------------------------------------------------
    local biz = paidInvoice('business', 'qa:1', 20000)
    check('setup.paid_business_invoice', biz ~= nil)
    local before = total()
    check('elig.untrusted_resource_forbidden', select(2, S.RequestRefund('random-resource', biz, ref(), nil, 'service_failed')) == 'forbidden')
    check('elig.nil_caller_forbidden', select(2, S.RequestRefund(nil, biz, ref(), nil, 'service_failed')) == 'forbidden')
    check('elig.disabled_provider_forbidden', select(2, S.RequestRefund('cm-law', biz, ref(), nil, 'service_failed')) == 'forbidden')
    check('elig.provider_without_canRefund_forbidden', select(2, S.RequestRefund('qa-refund-none', biz, ref(), nil, 'service_failed')) == 'forbidden')
    check('elig.wrong_provider_not_found', select(2, S.RequestRefund('qa-refund-other', biz, ref(), nil, 'service_failed')) == 'not_found')
    check('elig.unknown_invoice', select(2, S.RequestRefund(P, 'INV-NOPE0000', ref(), nil, 'service_failed')) == 'not_found')
    check('elig.malformed_invoice_reference', select(2, S.RequestRefund(P, "x'; DROP", ref(), nil, 'service_failed')) == 'not_found')
    local okP, pend = S.CreateInvoice(P, { recipientCharacterId = A, amount = 1000, label = 'x', issuerLabel = 'y', issuerType = 'business', destination = { type = 'business', id = 'qa:1' } })
    check('elig.unpaid_rejected', select(2, S.RequestRefund(P, pend.reference, ref(), nil, 'service_failed')) == 'not_paid')
    S.VoidInvoice(P, pend.reference, 'qa')
    check('elig.voided_rejected', select(2, S.RequestRefund(P, pend.reference, ref(), nil, 'service_failed')) == 'not_paid')
    local _, exp = S.CreateInvoice(P, { recipientCharacterId = A, amount = 1000, label = 'x', issuerLabel = 'y', issuerType = 'business', destination = { type = 'business', id = 'qa:1' } })
    MySQL.update.await("UPDATE cm_billing_invoices SET status = 'expired' WHERE public_reference = ?", { exp.reference })
    check('elig.expired_rejected', select(2, S.RequestRefund(P, exp.reference, ref(), nil, 'service_failed')) == 'not_paid')
    local _, stl = S.CreateInvoice(P, { recipientCharacterId = A, amount = 1000, label = 'x', issuerLabel = 'y', issuerType = 'business', destination = { type = 'business', id = 'qa:1' } })
    MySQL.update.await("UPDATE cm_billing_invoices SET status = 'settling', settle_token = 'qa' WHERE public_reference = ?", { stl.reference })
    check('elig.settling_rejected_payment_refund_interlock', select(2, S.RequestRefund(P, stl.reference, ref(), nil, 'service_failed')) == 'not_paid')
    check('elig.bad_reason_rejected', select(2, S.RequestRefund(P, biz, ref(), nil, 'because i said so')) == 'invalid_reason')
    check('elig.nil_reason_rejected', select(2, S.RequestRefund(P, biz, ref(), nil, nil)) == 'invalid_reason')
    check('elig.short_reference_rejected', select(2, S.RequestRefund(P, biz, 'a', nil, 'service_failed')) == 'invalid_refund_reference')
    check('elig.hostile_reference_rejected', select(2, S.RequestRefund(P, biz, "x' OR 1=1 --", nil, 'service_failed')) == 'invalid_refund_reference')
    check('elig.oversized_reference_rejected', select(2, S.RequestRefund(P, biz, string.rep('a', 65), nil, 'service_failed')) == 'invalid_refund_reference')
    check('elig.nothing_moved_by_rejections', total() == before and counts.debit == 0 and counts.credit == 0)

    -- AMOUNT -----------------------------------------------------------------------------
    for _, bad in ipairs({ 0, -5, 1.5, 'abc', false, 1e300 }) do
        check('amount.invalid_' .. tostring(bad), select(2, S.RequestRefund(P, biz, ref(), bad, 'service_failed')) == 'invalid_amount')
    end
    check('amount.above_paid_rejected', select(2, S.RequestRefund(P, biz, ref(), 20001, 'service_failed')) == 'refund_exceeds_paid')
    dest['business:qa:1'] = (dest['business:qa:1'] or 0) -- paid 20000 sits there
    check('amount.business_holds_paid_amount', dest['business:qa:1'] == 20000)

    -- PARTIAL then cumulative (supported) ---------------------------------------------------
    local r1 = ref('qa-part')
    local ok1, v1 = S.RequestRefund(P, biz, r1, 5000, 'service_cancelled')
    check('partial.first_completes', ok1 == true and v1.status == 'completed' and v1.final == true and v1.amount == 5000, v1 and v1.status)
    local inv1 = invRow(biz)
    check('partial.invoice_stays_paid_with_refund_state', inv1.status == 'paid' and inv1.refund_state == 'partial' and tonumber(inv1.refunded_amount) == 5000 and inv1.paid_ts ~= nil)
    check('partial.destination_debited_payer_credited', dest['business:qa:1'] == 15000 and payerBal.bank[A] == 1000000 - 20000 + 5000)
    local st = S.GetInvoiceRefundState(P, biz)
    check('partial.net_paid_canonical', st.paidAmount == 20000 and st.refundedAmount == 5000 and st.netPaidAmount == 15000 and st.refundableAmount == 15000 and st.refundState == 'partial')
    check('partial.public_view_keeps_paid_status', S.PublicInvoice(invRow(biz)).status == 'paid' and S.PublicInvoice(invRow(biz)).netPaid == 15000)
    check('partial.cumulative_over_refund_rejected', select(2, S.RequestRefund(P, biz, ref(), 15001, 'service_failed')) == 'refund_exceeds_paid')
    local ok2, v2 = S.RequestRefund(P, biz, ref('qa-rest'), nil, 'service_failed')
    check('full.remaining_refunded_with_nil_amount', ok2 == true and v2.status == 'completed' and v2.amount == 15000)
    local inv2 = invRow(biz)
    check('full.terminal_refunded_state_history_preserved', inv2.refund_state == 'refunded' and tonumber(inv2.refunded_amount) == 20000 and inv2.status == 'paid' and inv2.paid_ts ~= nil)
    check('full.already_refunded_rejected', select(2, S.RequestRefund(P, biz, ref(), nil, 'service_failed')) == 'already_refunded')
    check('full.already_refunded_exact_rejected', select(2, S.RequestRefund(P, biz, ref(), 1, 'service_failed')) == 'already_refunded')
    check('conserve.business_refunded_to_zero_payer_whole', dest['business:qa:1'] == 0 and payerBal.bank[A] == 1000000 and total() == before)
    check('conserve.exactly_one_debit_one_credit_per_refund', counts.debit == 2 and counts.credit == 2)

    -- IDEMPOTENCY ---------------------------------------------------------------------------
    local biz2 = paidInvoice('business', 'qa:1', 8000)
    local rr = ref('qa-idem')
    local okA, vA = S.RequestRefund(P, biz2, rr, 3000, 'duplicate_charge')
    local d0, c0, t0 = counts.debit, counts.credit, total()
    local okB, vB = S.RequestRefund(P, biz2, rr, 3000, 'duplicate_charge') -- lost response: provider retries
    check('idem.replay_returns_same_result', okB == true and vB.refundReference == vA.refundReference and vB.status == 'completed' and vB.amount == 3000)
    check('idem.replay_moves_no_money', counts.debit == d0 and counts.credit == c0 and total() == t0)
    check('idem.replay_after_completion_does_not_double_reserve', tonumber(invRow(biz2).refund_reserved_amount) == 3000)
    check('idem.same_ref_different_amount_conflict', select(2, S.RequestRefund(P, biz2, rr, 4000, 'duplicate_charge')) == 'idempotency_conflict')
    check('idem.same_ref_full_vs_exact_conflict', select(2, S.RequestRefund(P, biz2, rr, nil, 'duplicate_charge')) == 'idempotency_conflict')
    local other = paidInvoice('business', 'qa:1', 3000)
    check('idem.same_ref_different_invoice_conflict', select(2, S.RequestRefund(P, other, rr, 3000, 'duplicate_charge')) == 'idempotency_conflict')
    check('idem.reference_namespaced_per_provider', select(2, S.RequestRefund('qa-refund-other', biz2, rr, 3000, 'duplicate_charge')) == 'not_found')
    check('idem.status_read_scoped_to_provider', S.GetRefundStatus(P, rr) ~= nil and S.GetRefundStatus('qa-refund-other', rr) == nil)
    check('idem.unique_journal_constraint', pcall(function()
        MySQL.insert.await([[INSERT INTO cm_billing_refunds (provider_resource, refund_reference, invoice_id, invoice_reference, payer_character_id, payment_account,
            destination_type, amount, reason) VALUES (?, ?, 1, 'x', 'x', 'bank', 'business', 1, 'service_failed')]], { P, rr })
    end) == false)
    local fullRef = ref('qa-fullreplay')
    local okF1, vF1 = S.RequestRefund(P, biz2, fullRef, nil, 'service_failed')
    local okF2, vF2 = S.RequestRefund(P, biz2, fullRef, nil, 'service_failed')
    check('idem.full_mode_replay_ok', okF1 == true and okF2 == true and vF1.amount == 5000 and vF2.amount == 5000 and vF2.status == 'completed')

    -- DESTINATIONS --------------------------------------------------------------------------
    local chr = paidInvoice('character', B, 4000)
    local okC, vC = S.RequestRefund(P, chr, ref('qa-chr'), nil, 'service_cancelled')
    check('dest.character_refund_debits_recipient', okC == true and vC.status == 'completed' and dest['character:' .. B] == 0)
    local fam = paidInvoice('family', '7', 10000)
    check('dest.family_paid_amount_is_accepted_half', S.PaidAmount(invRow(fam)) == 5000 and dest['family:7'] == 5000)
    local okFam, vFam = S.RequestRefund(P, fam, ref('qa-fam'), nil, 'service_failed')
    check('dest.family_full_refund_is_what_family_received', okFam == true and vFam.amount == 5000 and dest['family:7'] == 0)
    check('dest.family_cannot_refund_beyond_accepted', select(2, S.RequestRefund(P, fam, ref(), 6000, 'service_failed')) == 'already_refunded')
    local city = paidInvoice('city', nil, 1500)
    check('dest.city_paid', city ~= nil)
    check('dest.city_not_refundable_would_mint_cash', select(2, S.RequestRefund(P, city, ref(), nil, 'service_failed')) == 'destination_not_refundable')
    local org = paidInvoice('business', 'qa:1', 1000)
    MySQL.update.await("UPDATE cm_billing_invoices SET destination_type = 'organization' WHERE public_reference = ?", { org })
    check('dest.unsupported_destination_rejected', select(2, S.RequestRefund(P, org, ref(), nil, 'service_failed')) == 'destination_not_refundable')
    MySQL.update.await("UPDATE cm_billing_invoices SET destination_type = 'business' WHERE public_reference = ?", { org })
    local unk = paidInvoice('family', '7', 2000)
    MySQL.update.await("UPDATE cm_billing_invoices SET settlement_note = 'partial_refund_failed_1000' WHERE public_reference = ?", { unk })
    check('dest.unknown_paid_amount_fails_closed', select(2, S.RequestRefund(P, unk, ref(), nil, 'service_failed')) == 'paid_amount_unknown')

    -- FUNDS ---------------------------------------------------------------------------------
    local poor = paidInvoice('business', 'qa:1', 6000)
    dest['business:qa:1'] = 100 -- the business spent the money
    local payerBefore, destBefore = payerBal.bank[A], dest['business:qa:1']
    local rp = ref('qa-poor')
    local okP2, vP = S.RequestRefund(P, poor, rp, nil, 'service_failed')
    check('funds.insufficient_enters_reconciliation', okP2 == true and vP.status == 'needs_reconciliation' and vP.failureReason == 'insufficient_destination_funds' and vP.debitState == 'none', vP and vP.status)
    check('funds.no_negative_no_payer_credit', dest['business:qa:1'] == destBefore and payerBal.bank[A] == payerBefore)
    check('funds.reservation_held_blocks_second_refund', select(2, S.RequestRefund(P, poor, ref(), nil, 'service_failed')) == 'refund_in_progress')
    check('funds.invoice_state_processing', invRow(poor).refund_state == 'processing')
    check('funds.listed_as_stuck', (function()
        MySQL.update.await("UPDATE cm_billing_refunds SET updated_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 HOUR) WHERE refund_reference = ?", { rp })
        for _, v in ipairs(S.AdminListStuckRefunds('console', 100)) do if v.refundReference == rp then return true end end
        return false
    end)())
    dest['business:qa:1'] = 7000 -- business earns again
    MySQL.update.await("UPDATE cm_billing_refunds SET updated_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 HOUR) WHERE refund_reference = ?", { rp })
    S.ReconcileRefunds()
    check('funds.sweep_completes_once_destination_can_cover', S.GetRefundStatus(P, rp).status == 'completed' and dest['business:qa:1'] == 1000 and payerBal.bank[A] == payerBefore + 6000)
    local poor2 = paidInvoice('business', 'qa:1', 2500)
    dest['business:qa:1'] = 0
    local rp2 = ref('qa-abandon')
    local _, vp2 = S.RequestRefund(P, poor2, rp2, nil, 'service_failed')
    check('funds.abandon_requires_admin', select(2, S.AdminAbandonRefund('cm-mechanic', rp2, P)) == 'forbidden')
    local abOk, abV = S.AdminAbandonRefund('console', rp2, P, 'qa')
    check('funds.abandon_without_debit_releases_reservation', abOk == true and abV.status == 'failed' and tonumber(invRow(poor2).refund_reserved_amount) == 0 and invRow(poor2).refund_state == 'none')
    dest['business:qa:1'] = 2500
    check('funds.refund_possible_again_after_abandon', select(1, S.RequestRefund(P, poor2, ref('qa-again'), nil, 'service_failed')) == true)
    check('funds.failed_journal_replay_is_terminal', S.GetRefundStatus(P, rp2).status == 'failed')

    -- RECOVERY ------------------------------------------------------------------------------
    local function fresh(amount) dest['business:qa:1'] = (dest['business:qa:1'] or 0) return paidInvoice('business', 'qa:1', amount) end
    local function stale(r) MySQL.update.await("UPDATE cm_billing_refunds SET updated_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 HOUR) WHERE refund_reference = ?", { r }) end
    -- (a) owner error BEFORE apply: outcome unknown, evidence says not applied, retry debits once
    local rec1 = fresh(3000)
    local ra = ref('qa-recA')
    inj.debitThrowBefore = true
    local d1 = counts.debit
    local _, va = S.RequestRefund(P, rec1, ra, nil, 'service_failed')
    check('recover.a.unknown_outcome_stays_reconciliation', va.status == 'needs_reconciliation' and va.debitState == 'unknown' and counts.debit == d1)
    local _, va2 = S.AdminReconcileRefund('console', ra, P)
    check('recover.a.retry_debits_once_then_completes', va2.status == 'completed' and counts.debit == d1 + 1)
    -- (b) owner APPLIED but the response was lost: retry must NOT debit again
    local rec2 = fresh(3300)
    local rb = ref('qa-recB')
    inj.debitThrowAfter = true
    local d2, c2 = counts.debit, counts.credit
    local _, vb = S.RequestRefund(P, rec2, rb, nil, 'service_failed')
    check('recover.b.applied_but_unknown_recorded', vb.status == 'needs_reconciliation' and vb.debitState == 'unknown' and counts.debit == d2 + 1)
    local _, vb2 = S.AdminReconcileRefund('console', rb, P)
    check('recover.b.retry_uses_evidence_no_second_debit', vb2.status == 'completed' and counts.debit == d2 + 1 and counts.credit == c2 + 1)
    -- (c) destination debited, payer credit fails before apply: forward-only, credit retried, debit untouched
    local rec3 = fresh(3600)
    local rc = ref('qa-recC')
    inj.creditThrowBefore = true
    local d3, c3 = counts.debit, counts.credit
    local _, vc = S.RequestRefund(P, rec3, rc, nil, 'service_failed')
    check('recover.c.destination_debited_credit_pending', vc.status == 'destination_debited' and vc.debitState == 'committed' and vc.creditState == 'unknown' and vc.final == false and counts.credit == c3)
    stale(rc)
    S.ReconcileRefunds()
    check('recover.c.sweep_credits_once_without_new_debit', S.GetRefundStatus(P, rc).status == 'completed' and counts.debit == d3 + 1 and counts.credit == c3 + 1)
    -- (d) payer credit applied, journal stale: complete without crediting again
    local rec4 = fresh(3900)
    local rd = ref('qa-recD')
    inj.creditThrowAfter = true
    local d4, c4 = counts.debit, counts.credit
    local _, vd = S.RequestRefund(P, rec4, rd, nil, 'service_failed')
    check('recover.d.credit_applied_response_lost', vd.status == 'destination_debited' and counts.credit == c4 + 1)
    local _, vd2 = S.RetryRefund(P, rd)
    check('recover.d.retry_completes_without_second_credit', vd2.status == 'completed' and counts.credit == c4 + 1 and counts.debit == d4 + 1)
    -- (e) completed: retry/reconcile are no-ops
    local d5, c5, t5 = counts.debit, counts.credit, total()
    S.RetryRefund(P, rd) S.AdminReconcileRefund('console', rd, P) stale(rd) S.ReconcileRefunds()
    check('recover.e.completed_is_terminal_noop', counts.debit == d5 and counts.credit == c5 and total() == t5)
    -- (f) restart: claimed journal with nothing applied (process died right after the claim) is driven by the sweep
    local rec6 = fresh(4200)
    local row6 = invRow(rec6)
    local rf = ref('qa-recF')
    MySQL.transaction.await({
        { query = S.RefundSQL.reserve, values = { 4200, row6.id, P, 4200, 4200 } },
        { query = S.RefundSQL.insert, values = { P, rf, row6.id, rec6, A, 'bank', 'business', 'qa:1', 4200, 'full', 'service_failed' } },
    })
    check('recover.f.claimed_pending_before_debit', S.GetRefundStatus(P, rf).status == 'pending' and counts.debit == d5)
    stale(rf)
    S.ReconcileRefunds()
    check('recover.f.restart_sweep_completes_exactly_once', S.GetRefundStatus(P, rf).status == 'completed' and counts.debit == d5 + 1 and counts.credit == c5 + 1)
    -- (g) destination owner unavailable: nothing attempted, stays reconciliation-pending
    local rec7 = fresh(1100)
    inj.destDown = true
    local _, vg = S.RequestRefund(P, rec7, ref('qa-recG'), nil, 'service_failed')
    inj.destDown = nil
    check('recover.g.owner_down_is_reconciliation_not_failure', vg.status == 'needs_reconciliation' and vg.failureReason == 'destination_unavailable' and vg.debitState == 'none')
    check('recover.g.abandon_refuses_after_debit', (function()
        local r = ref('qa-recH')
        local rec8 = fresh(1200)
        inj.creditThrowBefore = true
        S.RequestRefund(P, rec8, r, nil, 'service_failed')
        local ok, why = S.AdminAbandonRefund('console', r, P, 'qa')
        S.RetryRefund(P, r)
        return ok == false and why == 'destination_already_debited'
    end)())

    -- CONCURRENCY ---------------------------------------------------------------------------
    local race = fresh(20000)
    local out = {}
    inj.debitWait = 80
    for i = 1, 2 do
        CreateThread(function()
            local ok, v = S.RequestRefund(P, race, ref('qa-race' .. i), 15000, 'service_failed')
            out[i] = { ok, v }
        end)
    end
    local waited = 0
    while (not out[1] or not out[2]) and waited < 8000 do Wait(50) waited = waited + 50 end
    inj.debitWait = nil
    local wins = (out[1] and out[1][1] == true and 1 or 0) + (out[2] and out[2][1] == true and 1 or 0)
    check('race.two_15000_refunds_on_20000_only_one_wins', wins == 1, ('wins=%d'):format(wins))
    local losing = out[1] and out[1][1] ~= true and out[1] or out[2]
    check('race.loser_told_exceeds_paid', losing and losing[2] == 'refund_exceeds_paid', losing and tostring(losing[2]))
    local rrow = invRow(race)
    check('race.total_refunded_never_exceeds_paid', tonumber(rrow.refunded_amount) <= 20000 and tonumber(rrow.refund_reserved_amount) == 15000 and tonumber(rrow.refunded_amount) == 15000)
    -- reconcile vs live refund: a concurrent reconcile must not double-drive
    local live = fresh(5000)
    local lr = ref('qa-live')
    local dl, cl = counts.debit, counts.credit
    inj.debitWait = 300
    local liveOut
    CreateThread(function() liveOut = { S.RequestRefund(P, live, lr, nil, 'service_failed') } end)
    Wait(120)
    local okRec, vRec = S.AdminReconcileRefund('console', lr, P)
    check('race.reconcile_during_live_refund_does_not_double_drive', okRec == true and vRec.status ~= 'completed' and counts.debit <= dl + 1)
    waited = 0
    while not liveOut and waited < 5000 do Wait(50) waited = waited + 50 end
    inj.debitWait = nil
    check('race.live_refund_finishes_with_single_debit_credit', liveOut and liveOut[1] == true and liveOut[2].status == 'completed' and counts.debit == dl + 1 and counts.credit == cl + 1)
    -- payment vs refund: a refund requested while the invoice is still settling is refused; once paid it is accepted
    local _, late = S.CreateInvoice(P, { recipientCharacterId = A, amount = 900, label = 'x', issuerLabel = 'y', issuerType = 'business', destination = { type = 'business', id = 'qa:1' } })
    MySQL.update.await("UPDATE cm_billing_invoices SET status = 'settling', settle_token = 'qa-tok' WHERE public_reference = ?", { late.reference })
    check('race.refund_refused_while_settling', select(2, S.RequestRefund(P, late.reference, ref(), nil, 'service_failed')) == 'not_paid')

    -- SECURITY ------------------------------------------------------------------------------
    local sec = fresh(2000)
    local payerBeforeSec = payerBal.bank[A]
    local okS, vS = S.RequestRefund(P, sec, ref('qa-sec'), nil, 'service_failed', { payer = 'qa-bill-attacker', destination = 'character:evil', recipientCharacterId = 'qa-bill-attacker' })
    check('sec.extra_payer_destination_arguments_ignored', okS == true and payerBal.bank[A] == payerBeforeSec + 2000 and payerBal.bank['qa-bill-attacker'] == nil and dest['character:evil'] == nil)
    check('sec.admin_exports_gated', S.AdminListStuckRefunds('cm-mechanic', 5) == nil and S.AdminInspectRefund('qa-refund', 'x') == nil and select(2, S.AdminReconcileRefund('qa-refund', 'x')) == 'forbidden')
    check('sec.admin_inspect_console_ok', S.AdminInspectRefund('console', ref('qa-missing')) == nil and (S.AdminInspectRefund('console', rr, P) or {}).status == 'completed')
    local src = LoadResourceFile(GetCurrentResourceName(), 'server/refund.lua') or ''
    local surface = (LoadResourceFile(GetCurrentResourceName(), 'server/main.lua') or '') .. (LoadResourceFile(GetCurrentResourceName(), 'server/exports.lua') or '')
    check('sec.no_client_refund_surface', #src > 0 and not src:find('RegisterNetEvent', 1, true) and not src:find('lib.callback', 1, true)
        and not surface:find('RegisterNetEvent', 1, true) and not surface:lower():find("callback%.register%('cm%-billing:[%w_]*refund"))
    check('sec.refund_never_creates_negative_invoice', tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_billing_invoices WHERE recipient_character_id LIKE ? AND amount < 0', { PREFIX .. '%' }) or 0) == 0)
    check('sec.void_behaviour_unchanged', select(2, S.VoidInvoice(P, biz, 'qa')) == 'not_pending')

    -- SERVICE INTEGRATION PROOF (hypothetical, deterministic): paid mechanic invoice -> service fails BEFORE any irreversible vehicle
    -- mutation -> the provider requests a refund -> business debit -> customer credit -> completes exactly once.
    S.TestOnline = { [A] = A }
    dest['business:mechanic:qa1'] = 0
    local okM, mech = S.CreateInvoice('cm-mechanic', { recipientCharacterId = A, amount = 12000, label = 'Engine repair', issuerLabel = 'QA Customs',
        issuerType = 'business', issuerEntityId = 'mechanic:qa1', destination = { type = 'business', id = 'mechanic:qa1' }, metadata = { ['mechanic.workOrder'] = 'WO-17' } })
    check('proof.mechanic_invoice_created_by_real_provider_policy', okM == true, mech)
    local paidM = S.PayInvoice(A, A, mech.reference, 'bank')
    S.TestOnline = nil
    local custBefore, bizBefore = payerBal.bank[A], dest['business:mechanic:qa1']
    check('proof.customer_paid_business_credited', paidM == true and bizBefore == 12000)
    local dM, cM = counts.debit, counts.credit
    local proofTotal = total()
    local okR, vR = S.RequestRefund('cm-mechanic', mech.reference, 'mechanic-wo-17-refund', nil, 'service_failed')
    check('proof.refund_completes', okR == true and vR.status == 'completed' and vR.amount == 12000, vR and vR.status)
    check('proof.business_debited_customer_credited', dest['business:mechanic:qa1'] == bizBefore - 12000 and payerBal.bank[A] == custBefore + 12000)
    check('proof.exactly_once_even_if_provider_retries', (function()
        S.RequestRefund('cm-mechanic', mech.reference, 'mechanic-wo-17-refund', nil, 'service_failed')
        S.RetryRefund('cm-mechanic', 'mechanic-wo-17-refund')
        return counts.debit == dM + 1 and counts.credit == cM + 1
    end)())
    check('proof.invoice_history_paid_and_refunded', invRow(mech.reference).status == 'paid' and invRow(mech.reference).refund_state == 'refunded')
    check('proof.other_provider_cannot_refund_mechanic_invoice', select(2, S.RequestRefund('cm-commercial-ownership', mech.reference, 'attacker-refund-ref', nil, 'service_failed')) == 'not_found')

    -- JOURNAL / AUDIT -------------------------------------------------------------------------
    check('audit.saga_events_journaled', (tonumber(MySQL.scalar.await([[SELECT COUNT(DISTINCT e.event) FROM cm_billing_events e JOIN cm_billing_invoices i ON i.id = e.invoice_id
        WHERE i.recipient_character_id LIKE ? AND e.event LIKE 'refund_%']], { PREFIX .. '%' })) or 0) >= 7)
    check('conserve.proof_refund_net_zero', total() == proofTotal)

    S.Money, S.Destinations, S.Notifier, S.RefundDestinations, S.RefundPayer = origMoney, origDest, origNotifier, origDestRefund, origPayer
    S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
    Config.Destinations.city.refundable = origCfg.city
    cleanup()
    check('cleanup.refund_rows_removed', (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_billing_refunds r JOIN cm_billing_invoices i ON i.id = r.invoice_id WHERE i.recipient_character_id LIKE ?', { PREFIX .. '%' })) or 1) == 0)
    print(('[cm-billing:refund-selftest] RESULT %s: %d checks, %d failed'):format(failed == 0 and 'PASS' or 'FAIL', #results, failed))
end

-- Real owner contracts (no doubles): the new debit exports on cm-family and cm-playerdata, plus the business debit allow-list.
-- Synthetic fixtures only (family id 987654, character 99999901 with its own account row); everything is removed afterwards.
function S.RefundOwnerSelfTest()
    local results, failed = {}, 0
    local function check(name, cond, detail)
        results[#results + 1] = name
        if cond ~= true then
            failed = failed + 1
            print(('[cm-billing:refund-owner-test] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-billing:refund-owner-test] PASS  %s'):format(name))
        end
    end
    local FAM, CHAR, ACC = 987654, 99999901, 'qa-rfd-acc'
    local function clean()
        MySQL.query.await('DELETE FROM cm_family_treasury_operations WHERE family_id = ?', { FAM })
        MySQL.query.await('DELETE FROM cm_character_money_operations WHERE character_id = ?', { tostring(CHAR) })
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { FAM })
        MySQL.query.await('DELETE FROM cm_families WHERE id = ?', { FAM })
        MySQL.query.await('DELETE FROM economy_transactions WHERE character_id = ?', { CHAR })
        MySQL.query.await('DELETE FROM characters WHERE id = ?', { tostring(CHAR) })
        MySQL.query.await('DELETE FROM accounts WHERE id = ?', { ACC })
    end
    clean()
    if GetResourceState('cm-family') == 'started' then
        MySQL.query.await("INSERT INTO cm_families (id, name, founder_cid, bank_balance) VALUES (?, 'QA Refund Family', 'qa-none', 10000)", { FAM })
        local fam = exports['cm-family']
        local function bal() return tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { FAM })) end
        local ok1, r1 = fam:DebitFamilyTreasuryAtomic(FAM, 4000, { reason = 'qa-rfd-fam-1', category = 'refund' })
        check('owner.family.debit_applies', ok1 == true and r1.balance == 6000 and bal() == 6000 and r1.replayed == false)
        local ok2, r2 = fam:DebitFamilyTreasuryAtomic(FAM, 4000, { reason = 'qa-rfd-fam-1' })
        check('owner.family.replay_does_not_debit_again', ok2 == true and r2.replayed == true and bal() == 6000)
        local ok3, why3 = fam:DebitFamilyTreasuryAtomic(FAM, 9000, { reason = 'qa-rfd-fam-2' })
        check('owner.family.insufficient_refused_never_negative', ok3 == false and why3 == 'insufficient_funds' and bal() == 6000)
        check('owner.family.ledger_evidence', fam:HasFamilyTreasuryEntry(FAM, 'withdraw', 'qa-rfd-fam-1') == true and fam:HasFamilyTreasuryEntry(FAM, 'withdraw', 'qa-rfd-fam-2') == false)
        check('owner.family.invalid_arguments_rejected', select(2, fam:DebitFamilyTreasuryAtomic(FAM, 0, { reason = 'x' })) == 'invalid_amount'
            and select(2, fam:DebitFamilyTreasuryAtomic(FAM, 1.5, { reason = 'x' })) == 'invalid_amount'
            and select(2, fam:DebitFamilyTreasuryAtomic(FAM, 5, {})) == 'invalid_reason'
            and select(2, fam:DebitFamilyTreasuryAtomic(FAM + 1, 5, { reason = 'x' })) == 'family_not_found' and bal() == 6000)
        local ok4 = fam:DebitFamilyTreasuryAtomic(FAM, 6000, { reason = 'qa-rfd-fam-3' })
        check('owner.family.exact_balance_debit_to_zero', ok4 == true and bal() == 0)
        check('owner.family.withdraw_rows_are_unattributed_ledger', tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ? AND direction = 'withdraw' AND character_id IS NULL AND category = 'refund'", { FAM })) == 2)
    else
        check('owner.family.skipped_not_started', true)
    end

    if GetResourceState('cm-playerdata') == 'started' then
        MySQL.query.await("INSERT INTO accounts (id, username, password_hash) VALUES (?, ?, 'x')", { ACC, ACC })
        MySQL.query.await("INSERT INTO characters (id, account_id, slot, first_name, last_name, cash, bank) VALUES (?, ?, 1, 'Qa', 'Refund', 100, 5000)", { tostring(CHAR), ACC })
        local pd = exports['cm-playerdata']
        local function bank() return tonumber(MySQL.scalar.await('SELECT bank FROM characters WHERE id = ?', { tostring(CHAR) })) end
        local ok1 = pd:RemoveMoneyFromCharacter(CHAR, 'bank', 3000, 'qa-rfd-pd-1', { invoice = 'INV-QA' })
        check('owner.playerdata.offline_debit_applies', ok1 == true and bank() == 2000)
        local ok2 = pd:RemoveMoneyFromCharacter(CHAR, 'bank', 3000, 'qa-rfd-pd-1', { invoice = 'INV-QA' })
        check('owner.playerdata.replay_does_not_debit_again', ok2 == true and bank() == 2000)
        local ok3, why3 = pd:RemoveMoneyFromCharacter(CHAR, 'bank', 2001, 'qa-rfd-pd-2')
        check('owner.playerdata.insufficient_refused_never_negative', ok3 == false and why3 == 'insufficient_funds' and bank() == 2000)
        local ok4, why4 = pd:RemoveMoneyFromCharacter(99999902, 'bank', 1, 'qa-rfd-pd-3')
        check('owner.playerdata.unknown_character_refused', ok4 == false and why4 == 'not_found')
        check('owner.playerdata.invalid_arguments_refused', select(2, pd:RemoveMoneyFromCharacter(CHAR, 'bank', 0, 'x')) == 'invalid_request'
            and select(2, pd:RemoveMoneyFromCharacter(CHAR, 'gold', 5, 'x')) == 'invalid_request'
            and select(2, pd:RemoveMoneyFromCharacter(CHAR, 'bank', 5, '')) == 'invalid_reason'
            and select(2, pd:RemoveMoneyFromCharacter({ 1 }, 'bank', 5, 'x')) == 'invalid_character' and bank() == 2000)
        local ledger = MySQL.single.await("SELECT amount, action, balance_before, balance_after FROM economy_transactions WHERE character_id = ? AND reason = 'qa-rfd-pd-1'", { CHAR })
        check('owner.playerdata.ledger_row_written_once', ledger and tonumber(ledger.amount) == -3000 and ledger.action == 'remove' and tonumber(ledger.balance_before) == 5000 and tonumber(ledger.balance_after) == 2000)
        check('owner.playerdata.credit_evidence_pairs_with_add_money', pd:AddMoneyToCharacter(CHAR, 'bank', 3000, 'qa-rfd-pd-credit') == true and bank() == 5000
            and (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM economy_transactions WHERE character_id = ? AND action = 'add' AND reason = 'qa-rfd-pd-credit'", { CHAR })) or 0) == 1)
    else
        check('owner.playerdata.skipped_not_started', true)
    end

    if GetResourceState('cm-commercial-ownership') == 'started' then
        local dOk, dWhy = exports['cm-commercial-ownership']:DebitBusinessAtomic('store', 'qa-no-such-business', 10, 'invoice_refund', { idempotencyKey = 'billing-refund-debit:QA:1' })
        check('owner.business.billing_is_allowed_caller_and_unknown_business_refused_not_forbidden', dOk == false and dWhy ~= 'forbidden', dWhy)
    end
    clean()
    check('owner.cleanup_done', (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM characters WHERE id = ?', { tostring(CHAR) })) or 1) == 0
        and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_families WHERE id = ?', { FAM })) or 1) == 0)
    print(('[cm-billing:refund-owner-test] RESULT %s: %d checks, %d failed'):format(failed == 0 and 'PASS' or 'FAIL', #results, failed))
end
