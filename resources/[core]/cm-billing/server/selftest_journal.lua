-- Development-only owner-journal self-test (runs after the other suites from `cm_billing_selftest`). REAL cm-playerdata / cm-family exports against
-- synthetic fixtures (family 987655, characters 99999911 / 99999912): exact-once money operations that survive response loss, lost generic
-- logs (economy_transactions / cm_family_bank_log rows are deleted to simulate logging disabled or unavailable) and duplicate calls, plus a real
-- refund saga over the real owners. Every fixture row is removed afterwards.
local S = CMBilling.Server
local Config = CMBilling.Config

function S.RefundJournalSelfTest()
    local results, failed = {}, 0
    local function check(name, cond, detail)
        results[#results + 1] = name
        if cond ~= true then
            failed = failed + 1
            print(('[cm-billing:journal-selftest] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-billing:journal-selftest] PASS  %s'):format(name))
        end
    end
    local FAM, PAYER, DEST = 987655, 99999911, 99999912
    local ACC1, ACC2 = 'qa-j-acc1', 'qa-j-acc2'
    local PD, FM = GetResourceState('cm-playerdata') == 'started', GetResourceState('cm-family') == 'started'
    if not (PD and FM) then
        check('journal.skipped_owners_not_started', true)
        print('[cm-billing:journal-selftest] RESULT PASS: 1 checks, 0 failed')
        return
    end
    local function clean()
        MySQL.query.await("DELETE r FROM cm_billing_refunds r JOIN cm_billing_invoices i ON i.id = r.invoice_id WHERE i.recipient_character_id IN (?, ?)", { tostring(PAYER), tostring(DEST) })
        MySQL.query.await("DELETE e FROM cm_billing_events e JOIN cm_billing_invoices i ON i.id = e.invoice_id WHERE i.recipient_character_id IN (?, ?)", { tostring(PAYER), tostring(DEST) })
        MySQL.query.await('DELETE FROM cm_billing_invoices WHERE recipient_character_id IN (?, ?)', { tostring(PAYER), tostring(DEST) })
        MySQL.query.await("DELETE FROM cm_character_money_operations WHERE reference LIKE 'qa-j-%' OR (reference LIKE 'cm-billing-rfd-%' AND character_id IN (?, ?))", { tostring(PAYER), tostring(DEST) })
        MySQL.query.await('DELETE FROM cm_family_treasury_operations WHERE family_id = ?', { FAM })
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { FAM })
        MySQL.query.await('DELETE FROM cm_families WHERE id = ?', { FAM })
        MySQL.query.await('DELETE FROM economy_transactions WHERE character_id IN (?, ?)', { PAYER, DEST })
        MySQL.query.await('DELETE FROM characters WHERE id IN (?, ?)', { tostring(PAYER), tostring(DEST) })
        MySQL.query.await('DELETE FROM accounts WHERE id IN (?, ?)', { ACC1, ACC2 })
    end
    clean()
    MySQL.query.await("INSERT INTO accounts (id, username, password_hash) VALUES (?, ?, 'x'), (?, ?, 'x')", { ACC1, ACC1, ACC2, ACC2 })
    MySQL.query.await("INSERT INTO characters (id, account_id, slot, first_name, last_name, cash, bank) VALUES (?, ?, 1, 'Qa', 'Payer', 0, 10000), (?, ?, 1, 'Qa', 'Dest', 0, 5000)",
        { tostring(PAYER), ACC1, tostring(DEST), ACC2 })
    MySQL.query.await("INSERT INTO cm_families (id, name, founder_cid, bank_balance) VALUES (?, 'QA Journal Family', 'qa-none', 10000)", { FAM })

    local pd, fam = exports['cm-playerdata'], exports['cm-family']
    local function bank(id) return tonumber(MySQL.scalar.await('SELECT bank FROM characters WHERE id = ?', { tostring(id) })) end
    local function fbal() return tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { FAM })) end
    local function cJournal(ref) return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_character_money_operations WHERE reference = ?', { ref })) or -1 end
    local function fJournal(ref) return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_treasury_operations WHERE reference = ?', { ref })) or -1 end

    -- OWNER JOURNAL: schema ------------------------------------------------------------------
    check('schema.character_journal_unique_reference', (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'cm_character_money_operations' AND index_name = 'uq_money_op_reference' AND non_unique = 0")) or 0) == 1)
    check('schema.family_journal_unique_reference', (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'cm_family_treasury_operations' AND index_name = 'uq_treasury_op_reference' AND non_unique = 0")) or 0) == 1)

    -- CHARACTER DEBIT --------------------------------------------------------------------------
    local ok1, r1 = pd:RemoveMoneyFromCharacter(DEST, 'bank', 3000, 'qa-j-c-001', { invoice = 'INV-QA' })
    check('char.debit_applies_once_with_journal_row', ok1 == true and r1 == 'applied' and bank(DEST) == 2000 and cJournal('qa-j-c-001') == 1)
    local ok2, r2 = pd:RemoveMoneyFromCharacter(DEST, 'bank', 3000, 'qa-j-c-001', { invoice = 'INV-QA' })
    check('char.replay_returns_replayed_and_does_not_debit', ok2 == true and r2 == 'replayed' and bank(DEST) == 2000 and cJournal('qa-j-c-001') == 1)
    local ok3, r3 = pd:RemoveMoneyFromCharacter(DEST, 'bank', 4000, 'qa-j-c-001')
    check('char.same_reference_different_amount_conflicts_no_second_debit', ok3 == false and r3 == 'idempotency_conflict' and bank(DEST) == 2000)
    check('char.same_reference_different_account_conflicts', select(2, pd:RemoveMoneyFromCharacter(DEST, 'cash', 3000, 'qa-j-c-001')) == 'idempotency_conflict')
    check('char.same_reference_different_character_conflicts', select(2, pd:RemoveMoneyFromCharacter(PAYER, 'bank', 3000, 'qa-j-c-001')) == 'idempotency_conflict' and bank(PAYER) == 10000)
    check('char.same_reference_credit_vs_debit_conflicts', select(2, pd:AddMoneyToCharacterOnce(DEST, 'bank', 3000, 'qa-j-c-001')) == 'idempotency_conflict' and bank(DEST) == 2000)
    -- the generic log is optional: delete it (simulating TransactionLog disabled / unavailable) and the replay is STILL provably exact-once
    MySQL.query.await('DELETE FROM economy_transactions WHERE character_id IN (?, ?)', { PAYER, DEST })
    local ok4, r4 = pd:RemoveMoneyFromCharacter(DEST, 'bank', 3000, 'qa-j-c-001')
    local st = pd:GetCharacterMoneyOperation('qa-j-c-001')
    check('char.no_generic_log_replay_still_exact_once', ok4 == true and r4 == 'replayed' and bank(DEST) == 2000 and type(st) == 'table' and st.status == 'committed' and st.direction == 'debit' and st.characterId == tostring(DEST) and st.amount == 3000)
    check('char.unknown_reference_status_is_false_not_applied', pd:GetCharacterMoneyOperation('qa-j-never-applied') == false)
    local ok5, r5 = pd:RemoveMoneyFromCharacter(DEST, 'bank', 99999, 'qa-j-c-002')
    check('char.insufficient_funds_changes_nothing_and_is_not_journaled', ok5 == false and r5 == 'insufficient_funds' and bank(DEST) == 2000 and cJournal('qa-j-c-002') == 0)
    MySQL.query.await('UPDATE characters SET bank = 200000 WHERE id = ?', { tostring(DEST) })
    local ok6, r6 = pd:RemoveMoneyFromCharacter(DEST, 'bank', 99999, 'qa-j-c-002')
    check('char.same_reference_retryable_after_funds_return', ok6 == true and r6 == 'applied' and bank(DEST) == 100001 and cJournal('qa-j-c-002') == 1)
    MySQL.query.await('UPDATE characters SET bank = 5000 WHERE id = ?', { tostring(DEST) })
    -- duplicate calls racing (the database unique key decides, not the Lua lock)
    local race, outs = 'qa-j-c-race', {}
    for i = 1, 4 do CreateThread(function() outs[i] = { pd:RemoveMoneyFromCharacter(DEST, 'bank', 1000, race) } end) end
    local waited = 0
    while (not outs[1] or not outs[2] or not outs[3] or not outs[4]) and waited < 8000 do Wait(50) waited = waited + 50 end
    local applied, replayed = 0, 0
    for _, o in ipairs(outs) do if o[1] == true and o[2] == 'applied' then applied = applied + 1 elseif o[1] == true and o[2] == 'replayed' then replayed = replayed + 1 end end
    check('char.four_concurrent_duplicates_exactly_one_debit', applied == 1 and replayed == 3 and bank(DEST) == 4000 and cJournal(race) == 1, ('applied=%d replayed=%d bal=%s'):format(applied, replayed, tostring(bank(DEST))))
    -- credit
    local c1, cr1 = pd:AddMoneyToCharacterOnce(PAYER, 'bank', 1500, 'qa-j-c-003')
    local c2, cr2 = pd:AddMoneyToCharacterOnce(PAYER, 'bank', 1500, 'qa-j-c-003')
    check('char.credit_once_then_replayed', c1 == true and cr1 == 'applied' and c2 == true and cr2 == 'replayed' and bank(PAYER) == 11500 and select(2, pd:AddMoneyToCharacterOnce(PAYER, 'bank', 1600, 'qa-j-c-003')) == 'idempotency_conflict' and bank(PAYER) == 11500)
    check('char.invalid_arguments_rejected_before_any_change', select(2, pd:RemoveMoneyFromCharacter(DEST, 'bank', 0, 'qa-j-x')) == 'invalid_request' and select(2, pd:RemoveMoneyFromCharacter(DEST, 'bank', 5, 'bad reference!')) == 'invalid_reason'
        and select(2, pd:RemoveMoneyFromCharacter(99999999, 'bank', 5, 'qa-j-nochar')) == 'not_found' and cJournal('qa-j-nochar') == 0 and bank(DEST) == 4000)

    -- FAMILY DEBIT ---------------------------------------------------------------------------------
    local f1, fr1 = fam:DebitFamilyTreasuryAtomic(FAM, 4000, { reason = 'qa-j-f-001', category = 'refund' })
    check('family.debit_applies_once_with_journal_row', f1 == true and fr1.replayed == false and fbal() == 6000 and fJournal('qa-j-f-001') == 1)
    local f2, fr2 = fam:DebitFamilyTreasuryAtomic(FAM, 4000, { reason = 'qa-j-f-001' })
    check('family.replay_does_not_debit', f2 == true and fr2.replayed == true and fbal() == 6000)
    local f3, fr3 = fam:DebitFamilyTreasuryAtomic(FAM, 5000, { reason = 'qa-j-f-001' })
    check('family.same_reference_different_amount_conflicts', f3 == false and fr3 == 'idempotency_conflict' and fbal() == 6000)
    MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { FAM })     -- bank log lost/unavailable
    local f4, fr4 = fam:DebitFamilyTreasuryAtomic(FAM, 4000, { reason = 'qa-j-f-001' })
    check('family.no_bank_log_replay_still_exact_once', f4 == true and fr4.replayed == true and fbal() == 6000 and fam:HasFamilyTreasuryEntry(FAM, 'debit', 'qa-j-f-001') == true)
    check('family.entry_status_is_family_scoped', fam:HasFamilyTreasuryEntry(FAM + 1, 'debit', 'qa-j-f-001') == false and fam:HasFamilyTreasuryEntry(FAM, 'debit', 'qa-j-f-nope') == false)
    local f5, fr5 = fam:DebitFamilyTreasuryAtomic(FAM, 50000, { reason = 'qa-j-f-002' })
    check('family.insufficient_changes_nothing_not_journaled', f5 == false and fr5 == 'insufficient_funds' and fbal() == 6000 and fJournal('qa-j-f-002') == 0)
    MySQL.query.await('UPDATE cm_families SET bank_balance = 100000 WHERE id = ?', { FAM })
    local f6 = fam:DebitFamilyTreasuryAtomic(FAM, 50000, { reason = 'qa-j-f-002' })
    check('family.same_reference_retryable_after_replenishment', f6 == true and fbal() == 50000 and fJournal('qa-j-f-002') == 1)
    MySQL.query.await('UPDATE cm_families SET bank_balance = 10000 WHERE id = ?', { FAM })
    local fouts = {}
    for i = 1, 4 do CreateThread(function() fouts[i] = { fam:DebitFamilyTreasuryAtomic(FAM, 1000, { reason = 'qa-j-f-race' }) } end) end
    waited = 0
    while (not fouts[1] or not fouts[2] or not fouts[3] or not fouts[4]) and waited < 8000 do Wait(50) waited = waited + 50 end
    local fa, frp = 0, 0
    for _, o in ipairs(fouts) do if o[1] == true and o[2].replayed == false then fa = fa + 1 elseif o[1] == true and o[2].replayed == true then frp = frp + 1 end end
    check('family.four_concurrent_duplicates_exactly_one_debit', fa == 1 and frp == 3 and fbal() == 9000 and fJournal('qa-j-f-race') == 1, ('applied=%d replayed=%d bal=%s'):format(fa, frp, tostring(fbal())))
    check('family.invalid_arguments_rejected', select(2, fam:DebitFamilyTreasuryAtomic(FAM, 0, { reason = 'qa-j-y' })) == 'invalid_amount' and select(2, fam:DebitFamilyTreasuryAtomic(FAM, 5, {})) == 'invalid_reason'
        and select(2, fam:DebitFamilyTreasuryAtomic(FAM + 7, 5, { reason = 'qa-j-nofam' })) == 'family_not_found' and fJournal('qa-j-nofam') == 0 and fbal() == 9000)

    -- REAL REFUND SAGA OVER THE REAL OWNERS (payment side stubbed; refund side uses the production owner adapters) -----------
    S.TestCharacters = { [tostring(PAYER)] = true, [tostring(DEST)] = true }
    S.TestProviders = { ['qa-journal'] = { maxAmount = 100000, issuerTypes = { system = true, business = true }, destinations = { character = true, family = true },
        allowOffline = true, metadataNamespace = 'qj', canVoid = true, canRefund = true } }
    local orig = { Money = S.Money, Dest = S.Destinations, Notifier = S.Notifier }
    S.Money = { Debit = function() return true end, CreditCharacter = function() return true end, Balance = function() return 0 end }
    S.Destinations = {
        city = orig.Dest.city,
        character = { available = function() return true end, validate = function(id) return id == tostring(DEST) end, credit = function(inv) return true, tonumber(inv.amount) end, evidence = function() return false end },
        family = { available = function() return true end, validate = function(id) return tonumber(id) == FAM end, credit = function(inv) return true, tonumber(inv.amount) end, evidence = function() return false end },
    }
    S.Notifier = { created = function() end, paid = function() end, refunded = function() end }
    local function paid(destType, destId, amount)
        local ok, inv = S.CreateInvoice('qa-journal', { recipientCharacterId = tostring(PAYER), amount = amount, label = 'QA', issuerLabel = 'QA', issuerType = 'business', destination = { type = destType, id = destId } })
        if not ok then return nil, inv end
        local pok = S.PayInvoice(tostring(PAYER), tostring(PAYER), inv.reference, 'bank')
        return pok and inv.reference or nil
    end
    local realDest = { character = S.RefundDestinations.character, family = S.RefundDestinations.family }
    local realPayer = S.RefundPayer
    local function stale(r) MySQL.update.await("UPDATE cm_billing_refunds SET updated_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 HOUR) WHERE refund_reference = ?", { r }) end

    -- character destination: payer paid 4000 to DEST (state set to the post-payment world), then the provider refunds
    MySQL.query.await('UPDATE characters SET bank = 6000 WHERE id = ?', { tostring(PAYER) })
    MySQL.query.await('UPDATE characters SET bank = 4000 WHERE id = ?', { tostring(DEST) })
    local cinv = paid('character', tostring(DEST), 4000)
    check('saga.char.invoice_paid', cinv ~= nil)
    S.RefundDestinations.character = { available = realDest.character.available, evidence = realDest.character.evidence,
        debit = function(j) realDest.character.debit(j) error('response lost after the owner applied the debit') end }
    local rOk, rv = S.RequestRefund('qa-journal', cinv, 'qa-j-saga-char-1', nil, 'service_failed')
    check('saga.char.owner_applied_but_response_lost_is_unknown', rOk == true and rv.status == 'needs_reconciliation' and rv.debitState == 'unknown' and bank(DEST) == 0 and bank(PAYER) == 6000)
    S.RefundDestinations.character = realDest.character
    MySQL.query.await('DELETE FROM economy_transactions WHERE character_id IN (?, ?)', { PAYER, DEST })   -- generic log gone/disabled
    local credits = 0
    S.RefundPayer = { Evidence = realPayer.Evidence, Credit = function(j) local ok = realPayer.Credit(j) credits = credits + 1 error('payer credit response lost') end }
    local _, rv2 = S.AdminReconcileRefund('console', 'qa-j-saga-char-1', 'qa-journal')
    check('saga.char.retry_uses_owner_journal_no_second_debit_credit_pending', rv2.status == 'destination_debited' and rv2.debitState == 'committed' and bank(DEST) == 0 and bank(PAYER) == 10000)
    S.RefundPayer = realPayer
    MySQL.query.await('DELETE FROM economy_transactions WHERE character_id IN (?, ?)', { PAYER, DEST })
    local _, rv3 = S.AdminReconcileRefund('console', 'qa-j-saga-char-1', 'qa-journal')
    check('saga.char.credit_evidence_from_journal_completes_without_second_credit', rv3.status == 'completed' and bank(DEST) == 0 and bank(PAYER) == 10000 and bank(PAYER) + bank(DEST) == 10000)
    local _, rv4 = S.RequestRefund('qa-journal', cinv, 'qa-j-saga-char-1', nil, 'service_failed')
    S.RetryRefund('qa-journal', 'qa-j-saga-char-1'); stale('qa-j-saga-char-1'); S.ReconcileRefunds()
    local jid = MySQL.scalar.await('SELECT id FROM cm_billing_refunds WHERE refund_reference = ?', { 'qa-j-saga-char-1' })
    check('saga.char.replays_and_sweeps_after_completion_change_nothing', rv4.status == 'completed' and bank(DEST) == 0 and bank(PAYER) == 10000
        and cJournal(S.RefundDebitKey({ invoice_reference = cinv, id = jid })) == 1 and cJournal(S.RefundCreditKey({ invoice_reference = cinv, id = jid })) == 1)
    -- insufficient destination funds stays retryable under the SAME owner reference
    MySQL.query.await('UPDATE characters SET bank = 10000 WHERE id = ?', { tostring(PAYER) })
    MySQL.query.await('UPDATE characters SET bank = 0 WHERE id = ?', { tostring(DEST) })
    local cinv2 = paid('character', tostring(DEST), 2500)
    MySQL.query.await('UPDATE characters SET bank = 100 WHERE id = ?', { tostring(DEST) })    -- the recipient spent the money
    local _, rs = S.RequestRefund('qa-journal', cinv2, 'qa-j-saga-char-2', nil, 'service_failed')
    check('saga.char.insufficient_destination_waits_in_reconciliation_unjournaled', rs.status == 'needs_reconciliation' and rs.failureReason == 'insufficient_destination_funds' and bank(DEST) == 100)
    MySQL.query.await('UPDATE characters SET bank = 2600 WHERE id = ?', { tostring(DEST) })
    local payerBefore = bank(PAYER)
    local _, rs2 = S.AdminReconcileRefund('console', 'qa-j-saga-char-2', 'qa-journal')
    check('saga.char.same_reference_completes_once_funds_return', rs2.status == 'completed' and bank(DEST) == 100 and bank(PAYER) == payerBefore + 2500)

    -- family destination
    MySQL.query.await('UPDATE characters SET bank = 10000 WHERE id = ?', { tostring(PAYER) })
    MySQL.query.await('UPDATE cm_families SET bank_balance = 7000 WHERE id = ?', { FAM })
    local finv = paid('family', tostring(FAM), 3000)
    check('saga.family.invoice_paid', finv ~= nil)
    MySQL.query.await('UPDATE characters SET bank = 7000 WHERE id = ?', { tostring(PAYER) })     -- payer is out 3000 (stubbed payment)
    S.RefundDestinations.family = { available = realDest.family.available, evidence = realDest.family.evidence,
        debit = function(j) realDest.family.debit(j) error('response lost after the owner applied the debit') end }
    local _, fv = S.RequestRefund('qa-journal', finv, 'qa-j-saga-fam-1', nil, 'service_failed')
    check('saga.family.owner_applied_but_response_lost_is_unknown', fv.status == 'needs_reconciliation' and fv.debitState == 'unknown' and fbal() == 4000 and bank(PAYER) == 7000)
    S.RefundDestinations.family = realDest.family
    MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { FAM })             -- bank log gone: the journal is the proof
    local _, fv2 = S.AdminReconcileRefund('console', 'qa-j-saga-fam-1', 'qa-journal')
    check('saga.family.retry_uses_owner_journal_no_second_debit_then_completes', fv2.status == 'completed' and fbal() == 4000 and bank(PAYER) == 10000)
    S.RetryRefund('qa-journal', 'qa-j-saga-fam-1'); stale('qa-j-saga-fam-1'); S.ReconcileRefunds()
    check('saga.family.replays_after_completion_change_nothing', fbal() == 4000 and bank(PAYER) == 10000)
    check('saga.family.fully_refunded_invoice_rejects_more', select(2, S.RequestRefund('qa-journal', finv, 'qa-j-saga-fam-over', 1, 'service_failed')) == 'already_refunded')

    -- unavailable owner journal is "unknown", never "not applied"
    MySQL.query.await('UPDATE characters SET bank = 10000 WHERE id = ?', { tostring(PAYER) })
    MySQL.query.await('UPDATE characters SET bank = 0 WHERE id = ?', { tostring(DEST) })
    local uinv = paid('character', tostring(DEST), 1200)
    MySQL.query.await('UPDATE characters SET bank = 1200 WHERE id = ?', { tostring(DEST) })
    local uref = 'qa-j-saga-unknown'
    S.RefundDestinations.character = { available = realDest.character.available, debit = function() error('timeout') end, evidence = function() error('owner database unavailable') end }
    local _, uv = S.RequestRefund('qa-journal', uinv, uref, nil, 'service_failed')
    local _, uv2 = S.AdminReconcileRefund('console', uref, 'qa-journal')
    check('saga.unavailable_owner_stays_reconciliation_pending_never_redebited', uv.status == 'needs_reconciliation' and uv2.status == 'needs_reconciliation' and uv2.failureReason == 'debit_evidence_unavailable' and bank(DEST) == 1200)
    S.RefundDestinations.character = realDest.character
    local _, uv3 = S.AdminReconcileRefund('console', uref, 'qa-journal')
    check('saga.owner_returns_and_the_refund_completes_once', uv3.status == 'completed' and bank(DEST) == 0)

    S.Money, S.Destinations, S.Notifier, S.RefundDestinations.character, S.RefundDestinations.family, S.RefundPayer = orig.Money, orig.Dest, orig.Notifier, realDest.character, realDest.family, realPayer
    S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
    clean()
    check('cleanup.journal_fixtures_removed', cJournal('qa-j-c-001') == 0 and fJournal('qa-j-f-001') == 0 and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM characters WHERE id IN (?, ?)', { tostring(PAYER), tostring(DEST) })) or 1) == 0)
    print(('[cm-billing:journal-selftest] RESULT %s: %d checks, %d failed'):format(failed == 0 and 'PASS' or 'FAIL', #results, failed))
end
