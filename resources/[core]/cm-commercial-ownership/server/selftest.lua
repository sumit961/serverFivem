-- cm-commercial-ownership/server/selftest.lua
-- Development-only service-layer self-test:   server console  ->  cm_business_selftest
-- Requires cm_environment=development; console only. Uses synthetic character ids (91000xx), a QA-only fixture table
-- (cm_business_qa_shops, type "qa") and a stand-in character credit; removes every row it created.
-- It drives the same functions the exports/UI use (actor ids are explicit so presence checks, which need real
-- players, are not covered here -- see docs/CONTRACTS.md manual tests).

local C = CMB

local function enabled()
    return GetConvar(Config.SelfTest.convar, 'production') == Config.SelfTest.value
end

local OWN1, MGR, EMP, OUT, MGR2, OWN2, NEWOWN, OWN3 = 9100001, 9100002, 9100003, 9100004, 9100005, 9100010, 9100020, 9100030
local FIXTURE = 'cm_business_qa_shops'
local RESOURCE = GetCurrentResourceName()

local function cleanup()
    for _, t in ipairs({ 'cm_business_state', 'cm_business_ranks', 'cm_business_employees', 'cm_business_activity', 'cm_business_transactions' }) do
        MySQL.query.await(('DELETE FROM %s WHERE business_type = ?'):format(t), { 'qa' })
    end
    pcall(function()
        MySQL.query.await("DELETE FROM cm_business_supply_order_lines WHERE order_id IN (SELECT id FROM cm_business_supply_orders WHERE business_type = 'qa')")
        MySQL.query.await("DELETE FROM cm_business_supply_events WHERE order_id IN (SELECT id FROM cm_business_supply_orders WHERE business_type = 'qa')")
        MySQL.query.await("DELETE FROM cm_business_supply_orders WHERE business_type = 'qa'")
    end)
    if C.supplyTypes then C.supplyTypes.qa = nil end
    C.TestCatalog = nil
    C.TestBroker = nil
    MySQL.query.await('DROP TABLE IF EXISTS ' .. FIXTURE)
    C.types.qa = nil
    C.TestCreditCharacter = nil
    C.TestPayrollEvidence = nil
    C.TestSkipIssuer = nil
    C.TestInvoker = nil
    for token, inv in pairs(C.invites()) do if inv.type == 'qa' then C.invites()[token] = nil end end
end

local function parallel(n, fn)
    local done, results = 0, {}
    for k = 1, n do
        CreateThread(function()
            results[k] = table.pack(fn(k))
            done = done + 1
        end)
    end
    local waited = 0
    while done < n and waited < 15000 do Wait(20); waited = waited + 20 end
    return results
end

function C.hireForTest(owner, target, t, i, rankName)
    local rid
    for _, r in ipairs(C.GetRanks(t, i)) do if r.name == rankName then rid = r.id end end
    local ok, tok = C.InviteCore(owner, target, t, i, rid)
    if ok then C.RespondCore(target, tok, true, 'QA ' .. target) end
end

local function run()
    local total, failed = 0, 0
    local function check(name, cond, detail)
        total = total + 1
        if cond ~= true then
            failed = failed + 1
            print(('[cm-commercial-ownership:selftest] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-commercial-ownership:selftest] PASS  %s'):format(name))
        end
    end

    C.EnsureSchema()
    cleanup()
    C.TestInvoker = 'cm-commercial-ownership' -- console commands have no invoking resource; stand in for a trusted caller
    MySQL.query.await(('CREATE TABLE %s (shop_id VARCHAR(50) NOT NULL PRIMARY KEY, owner_character_id BIGINT NULL, owner_name VARCHAR(120) NULL, business_balance BIGINT NOT NULL DEFAULT 0, stock INT NOT NULL DEFAULT 0)'):format(FIXTURE))
    for _, row in ipairs({ { '1', OWN1 }, { '2', OWN2 }, { '3', OWN3 }, { '4', nil }, { '5', 9100040 }, { '6', 9100041 } }) do
        MySQL.query.await(('INSERT INTO %s (shop_id, owner_character_id, owner_name) VALUES (?, ?, ?)'):format(FIXTURE), { row[1], row[2], row[2] and ('QA Owner ' .. row[1]) or nil })
    end
    C.types.qa = { label = 'QA Shop', table = FIXTURE, idColumn = 'shop_id', ownerColumn = 'owner_character_id', balanceColumn = 'business_balance', nameColumn = 'owner_name', stockColumn = 'stock' }

    local function rankByName(t, i, name)
        for _, r in ipairs(C.GetRanks(t, i)) do if r.name == name then return r end end
    end
    local function hire(actor, t, i, target, rankId)
        local ok, tok = C.InviteCore(actor, target, t, i, rankId)
        if not ok then return false, tok end
        return C.RespondCore(target, tok, true, 'QA ' .. target)
    end
    local function balance(i) return C.GetBusinessBalance('qa', i) end
    local function setOwner(i, cid)
        MySQL.update.await(('UPDATE %s SET owner_character_id = ?, owner_name = ? WHERE shop_id = ?'):format(FIXTURE), { cid, cid and 'QA New' or nil, tostring(i) })
    end

    -- BUSINESS IDENTITY ---------------------------------------------------------------
    local biz = C.GetBusiness('qa', '1')
    check('identity.valid_business', biz ~= nil and biz.owned == true and biz.ownerCharacterId == OWN1)
    check('identity.unknown_business_rejected', C.GetBusiness('qa', '999') == nil)
    check('identity.unknown_type_rejected', C.GetBusiness('nope', '1') == nil)
    check('identity.injection_id_rejected', C.GetBusiness('qa', "1' OR 1=1 --") == nil and C.GetBusiness('qa', nil) == nil and C.GetBusiness(nil, '1') == nil)
    check('identity.owner_resolved', select(1, C.GetBusinessOwner('qa', '1')) == OWN1)
    check('identity.real_types_registered', C.types.store ~= nil and C.types.gasstation ~= nil and C.types.clothing ~= nil and C.types.barber ~= nil)

    -- REAL BUSINESS TYPES (read-only: proves the same foundation resolves cm-store / cm-gasstations / books) --
    for _, spec in ipairs({ { 'store', 'cm_stores', 'store_id' }, { 'gasstation', 'cm_gas_stations', 'station_id' },
                            { 'clothing', 'cm_clothing_stores', 'shop_id' }, { 'barber', 'cm_barber_shops', 'shop_id' } }) do
        local def = C.types[spec[1]]
        local exists = MySQL.scalar.await('SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1', { spec[2] })
        if exists then
            local first = MySQL.scalar.await(('SELECT `%s` FROM `%s` ORDER BY `%s` LIMIT 1'):format(spec[3], spec[2], spec[3]))
            if first ~= nil then
                local b = C.GetBusiness(spec[1], tostring(first))
                check('real.' .. spec[1] .. '_resolves', b ~= nil and type(b.owned) == 'boolean' and b.type == spec[1])
                check('real.' .. spec[1] .. '_unowned_grants_nothing', b == nil or b.owned or C.HasBusinessPermission(spec[1], tostring(first), 9199999, 'business.invite') == false)
            else
                print(('[cm-commercial-ownership:selftest] SKIP  real.%s (no rows yet)'):format(spec[1]))
            end
            check('real.' .. spec[1] .. '_unknown_id_rejected', C.GetBusiness(spec[1], 'no-such-business-id') == nil)
        else
            print(('[cm-commercial-ownership:selftest] SKIP  real.%s (table %s absent)'):format(spec[1], spec[2]))
        end
    end

    -- RANKS ------------------------------------------------------------------------------
    local ranks = C.GetRanks('qa', '1')
    check('ranks.default_seeded', #ranks == 3 and rankByName('qa', '1', 'Manager') ~= nil and rankByName('qa', '1', 'Employee') ~= nil and rankByName('qa', '1', 'Trainee') ~= nil)
    local empRank = rankByName('qa', '1', 'Employee')
    check('ranks.owner_can_rename', C.UpdateRank(OWN1, 'qa', '1', empRank.id, { name = 'Associate' }) == true)
    C.GetRanks('qa', '1'); C.GetRanks('qa', '1')
    check('ranks.restart_does_not_overwrite_or_duplicate', #C.GetRanks('qa', '1') == 3 and rankByName('qa', '1', 'Associate') ~= nil and rankByName('qa', '1', 'Employee') == nil)
    check('ranks.rename_back', C.UpdateRank(OWN1, 'qa', '1', empRank.id, { name = 'Employee' }) == true)
    local mgrRank, trainee = rankByName('qa', '1', 'Manager'), rankByName('qa', '1', 'Trainee')

    -- INVITES / EMPLOYEES ------------------------------------------------------------
    check('invite.outsider_forbidden', select(2, C.InviteCore(OUT, MGR, 'qa', '1')) == 'forbidden')
    check('invite.self_rejected', C.InviteCore(OWN1, OWN1, 'qa', '1') == false)
    local ok, tok = C.InviteCore(OWN1, MGR, 'qa', '1', mgrRank.id)
    check('invite.owner_can_invite', ok == true and type(tok) == 'string')
    check('invite.duplicate_pending_rejected', select(2, C.InviteCore(OWN1, MGR, 'qa', '1')) == 'invite_pending')
    check('invite.wrong_target_cannot_accept', select(2, C.RespondCore(EMP, tok, true)) == 'invalid_invite')
    check('invite.garbage_token_rejected', select(2, C.RespondCore(MGR, 'zzz', true)) == 'invalid_invite' and select(2, C.RespondCore(MGR, nil, true)) == 'invalid_invite')
    local acc, res = C.RespondCore(MGR, tok, true, 'QA Manager')
    check('invite.accept_creates_employee', acc == true and res == 'accepted' and C.IsEmployee('qa', '1', MGR) == true)
    check('invite.token_single_use', select(2, C.RespondCore(MGR, tok, true)) == 'invalid_invite')
    check('invite.duplicate_employment_rejected', select(2, C.InviteCore(OWN1, MGR, 'qa', '1')) == 'already_employed')
    check('invite.owner_cannot_be_invited', select(2, C.InviteCore(MGR, OWN1, 'qa', '1')) == 'already_employed')
    local _, tok2 = C.InviteCore(OWN1, EMP, 'qa', '1')
    local dok, dres = C.RespondCore(EMP, tok2, false)
    check('invite.decline', dok == true and dres == 'declined' and C.IsEmployee('qa', '1', EMP) == false)
    local _, tok3 = C.InviteCore(OWN1, EMP, 'qa', '1')
    C.invites()[tok3].expires = os.time() - 1
    check('invite.expired_rejected', select(2, C.RespondCore(EMP, tok3, true)) == 'expired' and C.IsEmployee('qa', '1', EMP) == false)
    local hired, hireWhy = hire(MGR, 'qa', '1', EMP)
    check('invite.manager_hires_entry_rank', hired == true and C.GetEmployee('qa', '1', EMP) ~= nil and C.GetEmployee('qa', '1', EMP).rankName == 'Employee', tostring(hireWhy) .. '/' .. tostring(C.GetEmployee('qa', '1', EMP) and C.GetEmployee('qa', '1', EMP).rankName))
    check('invite.spoof_equal_rank_rejected', select(2, C.InviteCore(MGR, OUT, 'qa', '1', mgrRank.id)) == 'hierarchy')
    check('invite.spoof_foreign_rank_rejected', select(2, C.InviteCore(OWN1, OUT, 'qa', '1', (C.GetRanks('qa', '2')[1] or {}).id)) == 'rank_not_found')
    check('invite.spoof_unknown_rank_rejected', select(2, C.InviteCore(OWN1, OUT, 'qa', '1', 999999)) == 'rank_not_found')

    -- HIERARCHY / PERMISSIONS ---------------------------------------------------------
    check('hierarchy.manager_cannot_remove_owner', select(2, C.RemoveEmployee(MGR, 'qa', '1', OWN1)) == 'owner_protected')
    check('hierarchy.manager_cannot_rank_owner', select(2, C.SetEmployeeRank(MGR, 'qa', '1', OWN1, trainee.id)) == 'owner_protected')
    check('hierarchy.second_manager_hired', hire(OWN1, 'qa', '1', MGR2, mgrRank.id) == true)
    check('hierarchy.equal_tier_cannot_remove', select(2, C.RemoveEmployee(MGR, 'qa', '1', MGR2)) == 'hierarchy')
    check('hierarchy.equal_tier_cannot_rerank', select(2, C.SetEmployeeRank(MGR, 'qa', '1', MGR2, trainee.id)) == 'hierarchy')
    check('hierarchy.cannot_promote_to_own_tier', select(2, C.SetEmployeeRank(MGR, 'qa', '1', EMP, mgrRank.id)) == 'hierarchy')
    check('hierarchy.cannot_rerank_self', select(2, C.SetEmployeeRank(MGR, 'qa', '1', MGR, trainee.id)) == 'hierarchy')
    check('hierarchy.manager_can_demote_lower', C.SetEmployeeRank(MGR, 'qa', '1', EMP, trainee.id) == true and C.GetEmployee('qa', '1', EMP).rankName == 'Trainee')
    check('hierarchy.rank_assignment_back', C.SetEmployeeRank(MGR, 'qa', '1', EMP, empRank.id) == true)
    check('hierarchy.employee_cannot_remove_manager', select(2, C.RemoveEmployee(EMP, 'qa', '1', MGR)) == 'forbidden')
    check('hierarchy.employee_cannot_invite', select(2, C.InviteCore(EMP, OUT, 'qa', '1')) == 'forbidden')
    check('hierarchy.employee_cannot_rerank', select(2, C.SetEmployeeRank(EMP, 'qa', '1', EMP, trainee.id)) == 'forbidden')
    check('hierarchy.not_employee_target', select(2, C.SetEmployeeRank(OWN1, 'qa', '1', OUT, empRank.id)) == 'not_employee')
    check('security.spoof_business_id_forbidden', select(2, C.InviteCore(MGR, OUT, 'qa', '2')) == 'forbidden' and C.HasBusinessPermission('qa', '2', MGR, 'business.invite') == false)
    check('security.forged_permission_rejected', C.HasBusinessPermission('qa', '1', EMP, 'business.hack') == false and C.HasBusinessPermission('qa', '1', EMP, nil) == false)
    check('permission.employee_stock_yes_prices_no', C.HasBusinessPermission('qa', '1', EMP, 'business.manage_stock') == true and C.HasBusinessPermission('qa', '1', EMP, 'business.manage_prices') == false)
    check('permission.owner_has_everything', C.HasBusinessPermission('qa', '1', OWN1, 'business.withdraw') == true and C.HasBusinessPermission('qa', '1', OWN1, 'business.manage_ranks') == true)
    local perms = C.GetEmployeePermissions('qa', '1', EMP)
    check('permission.list_for_employee', #perms == 2)
    check('permission.outsider_has_nothing', C.HasBusinessPermission('qa', '1', OUT, 'business.manage_stock') == false and #C.GetEmployeePermissions('qa', '1', OUT) == 0)
    check('hierarchy.resign_allowed', hire(OWN1, 'qa', '1', OUT, trainee.id) == true and C.RemoveEmployee(OUT, 'qa', '1', OUT) == true and C.IsEmployee('qa', '1', OUT) == false)
    check('hierarchy.owner_cannot_resign', select(2, C.RemoveEmployee(OWN1, 'qa', '1', OWN1)) == 'owner_protected')

    -- RANK MANAGEMENT -----------------------------------------------------------------
    check('rankmgmt.manager_without_permission_forbidden', select(2, C.CreateRank(MGR, 'qa', '1', { name = 'Sup', tier = 50 })) == 'forbidden')
    local current = mgrRank.permissions
    local widened = { table.unpack(current) }
    widened[#widened + 1] = 'business.manage_ranks'; widened[#widened + 1] = 'business.manage_permissions'
    check('rankmgmt.owner_edits_permissions', C.UpdateRank(OWN1, 'qa', '1', mgrRank.id, { permissions = widened }) == true)
    check('rankmgmt.tier_at_or_above_own_rejected', select(2, C.CreateRank(MGR, 'qa', '1', { name = 'Boss', tier = 80 })) == 'hierarchy')
    check('rankmgmt.permission_escalation_rejected', select(2, C.CreateRank(MGR, 'qa', '1', { name = 'Sup', tier = 50, permissions = { 'business.withdraw' } })) == 'permission_escalation')
    local created, supId = C.CreateRank(MGR, 'qa', '1', { name = 'Supervisor', tier = 50, permissions = { 'business.manage_stock' } })
    check('rankmgmt.create_ok', created == true and supId ~= nil)
    check('rankmgmt.duplicate_name_rejected', select(2, C.CreateRank(MGR, 'qa', '1', { name = 'Supervisor', tier = 45 })) == 'duplicate_name')
    check('rankmgmt.invalid_input_rejected', select(2, C.CreateRank(OWN1, 'qa', '1', { name = '', tier = 20 })) == 'invalid_name'
        and select(2, C.CreateRank(OWN1, 'qa', '1', { name = 'Zero', tier = 0 })) == 'invalid_tier'
        and select(2, C.CreateRank(OWN1, 'qa', '1', { name = 'Huge', tier = Config.OwnerTier })) == 'invalid_tier')
    check('rankmgmt.cannot_edit_equal_or_higher', select(2, C.UpdateRank(MGR, 'qa', '1', mgrRank.id, { name = 'Mgr2' })) == 'hierarchy')
    check('rankmgmt.cannot_strip_unheld_permission', (function()
        -- Owner grants the Supervisor rank a permission the manager does not hold, then the manager tries to remove it.
        C.UpdateRank(OWN1, 'qa', '1', supId, { permissions = { 'business.manage_stock', 'business.withdraw' } })
        return select(2, C.UpdateRank(MGR, 'qa', '1', supId, { permissions = { 'business.manage_stock' } })) == 'permission_escalation'
    end)())
    check('rankmgmt.delete_in_use_rejected', select(2, C.DeleteRank(OWN1, 'qa', '1', empRank.id)) == 'rank_in_use')
    check('rankmgmt.delete_unused_ok', C.DeleteRank(MGR, 'qa', '1', supId) == true and C.getRank({ type = 'qa', id = '1' }, supId) == nil)
    check('rankmgmt.cross_business_rank_rejected', select(2, C.DeleteRank(OWN2, 'qa', '2', empRank.id)) == 'rank_not_found')
    check('rankmgmt.last_rank_protected', (function()
        for _, r in ipairs(C.GetRanks('qa', '3')) do
            if r.name ~= 'Manager' then C.DeleteRank(OWN3, 'qa', '3', r.id) end
        end
        local m = rankByName('qa', '3', 'Manager')
        return m ~= nil and select(2, C.DeleteRank(OWN3, 'qa', '3', m.id)) == 'last_rank'
    end)())
    local act = MySQL.scalar.await("SELECT COUNT(*) FROM cm_business_activity WHERE business_type = 'qa' AND business_id = '1' AND action = 'permissions_changed'")
    check('activity.permission_change_logged', tonumber(act) >= 1)

    -- MULTIPLE BUSINESSES ---------------------------------------------------------------
    local trainee2 = rankByName('qa', '2', 'Trainee')
    check('multi.same_character_two_businesses', hire(OWN2, 'qa', '2', EMP, trainee2.id) == true and C.IsEmployee('qa', '1', EMP) and C.IsEmployee('qa', '2', EMP))
    check('multi.permissions_isolated', C.HasBusinessPermission('qa', '1', EMP, 'business.manage_stock') == true and C.HasBusinessPermission('qa', '2', EMP, 'business.manage_stock') == false)
    local mine = C.GetPlayerBusinesses(EMP)
    check('multi.player_business_list', #mine == 2)
    check('multi.removal_isolated', C.RemoveEmployee(OWN2, 'qa', '2', EMP) == true and C.IsEmployee('qa', '1', EMP) == true)

    -- BALANCE CONTRACT --------------------------------------------------------------------
    local mv = C.MoveBalance
    local okc, rc = mv('credit', 'qa', '2', 1000, { kind = 'deposit', key = 'qa-k1' })
    check('balance.credit', okc == true and rc.balance == 1000 and balance('2') == 1000)
    local okr, rr = mv('credit', 'qa', '2', 1000, { kind = 'deposit', key = 'qa-k1' })
    check('balance.idempotent_replay_no_double_credit', okr == true and rr.replayed == true and balance('2') == 1000)
    check('balance.key_conflict_rejected', select(2, mv('credit', 'qa', '2', 999, { kind = 'deposit', key = 'qa-k1' })) == 'idempotency_conflict' and balance('2') == 1000)
    local okd, rd = mv('debit', 'qa', '2', 400, { kind = 'withdraw', key = 'qa-d1' })
    check('balance.debit', okd == true and rd.balance == 600 and balance('2') == 600)
    check('balance.insufficient_funds_rejected', select(2, mv('debit', 'qa', '2', 700, { kind = 'withdraw', key = 'qa-d2' })) == 'insufficient_funds' and balance('2') == 600)
    check('balance.failed_debit_leaves_no_ledger', C.ledgerByKey('qa-d2') == nil)
    for _, bad in ipairs({ 0, -5, 1.5, 'x', false, 3000000000 }) do
        check('balance.invalid_amount_' .. tostring(bad), select(2, mv('credit', 'qa', '2', bad, { kind = 'x' })) == 'invalid_amount')
    end
    check('balance.nil_amount_rejected', select(2, mv('credit', 'qa', '2', nil, { kind = 'x' })) == 'invalid_amount')
    check('balance.unowned_rejected', select(2, mv('credit', 'qa', '4', 10, { kind = 'x' })) == 'no_owner')
    check('balance.unknown_business_rejected', select(2, mv('credit', 'qa', '999', 10, { kind = 'x' })) == 'unknown_business' and select(2, mv('credit', 'nope', '1', 10, { kind = 'x' })) == 'invalid_business')
    MySQL.update.await(('UPDATE %s SET business_balance = 1999999999 WHERE shop_id = ?'):format(FIXTURE), { '2' })
    check('balance.cap_enforced', select(2, mv('credit', 'qa', '2', 5, { kind = 'x', key = 'qa-cap' })) == 'rejected' and balance('2') == 1999999999)
    MySQL.update.await(('UPDATE %s SET business_balance = 600 WHERE shop_id = ?'):format(FIXTURE), { '2' })
    local debits = parallel(10, function(k) return mv('debit', 'qa', '2', 100, { kind = 'withdraw', key = 'qa-par-' .. k }) end)
    local won = 0
    for _, r in ipairs(debits) do if r[1] == true then won = won + 1 end end
    check('balance.concurrent_debits_cannot_overdraw', won == 6 and balance('2') == 0, ('won=%d balance=%s'):format(won, tostring(balance('2'))))
    local same = parallel(5, function() return mv('credit', 'qa', '2', 50, { kind = 'deposit', key = 'qa-same' }) end)
    local applied = 0
    for _, r in ipairs(same) do if r[1] == true and r[2] and r[2].replayed == false then applied = applied + 1 end end
    check('balance.concurrent_same_key_applies_once', applied == 1 and balance('2') == 50, ('applied=%d balance=%s'):format(applied, tostring(balance('2'))))
    check('balance.caller_allowlist', C.CallerAllowed('credit', 'cm-billing') == true and C.CallerAllowed('credit', 'cm-store') == false
        and C.CallerAllowed('debit', 'cm-billing') == true and C.CallerAllowed('debit', 'cm-store') == false and C.CallerAllowed('debit', 'evil') == false and C.CallerAllowed('credit', RESOURCE) == true)
    mv('credit', 'qa', '2', 77, { kind = 'invoice', key = 'billing-credit:INV-QA' })
    check('balance.ledger_evidence', C.HasBusinessTransaction('billing-credit:INV-QA') == true and C.HasBusinessTransaction('billing-credit:INV-NONE') == false)

    C.ResetRateLimits()
    -- PAYROLL ----------------------------------------------------------------------------
    local credits, failCredit = {}, false
    C.TestCreditCharacter = function(cid, amount) if failCredit then return false end credits[#credits + 1] = { cid, amount } return true end
    local empRank1 = rankByName('qa', '1', 'Employee')
    check('payroll.manager_cannot_set_pay_without_permission', select(2, C.UpdateRank(MGR, 'qa', '1', empRank1.id, { payAmount = 500 })) == 'forbidden')
    check('payroll.over_max_rejected', select(2, C.UpdateRank(OWN1, 'qa', '1', empRank1.id, { payAmount = 999999 })) == 'invalid_amount')
    check('payroll.below_min_rejected', select(2, C.UpdateRank(OWN1, 'qa', '1', empRank1.id, { payAmount = 50 })) == 'invalid_amount')
    check('payroll.owner_sets_pay', C.UpdateRank(OWN1, 'qa', '1', empRank1.id, { payAmount = 500 }) == true)
    check('payroll.employee_forbidden', select(2, C.PayEmployee(EMP, 'qa', '1', EMP)) == 'forbidden')
    check('payroll.self_payment_rejected', select(2, C.PayEmployee(MGR, 'qa', '1', MGR)) == 'self_payment')
    check('payroll.peer_hierarchy_rejected', select(2, C.PayEmployee(MGR, 'qa', '1', MGR2)) == 'hierarchy')
    check('payroll.non_employee_rejected', select(2, C.PayEmployee(OWN1, 'qa', '1', OUT)) == 'not_employee')
    check('payroll.owner_not_payable', select(2, C.PayEmployee(MGR, 'qa', '1', OWN1)) == 'owner_protected')
    check('payroll.insufficient_funds_rejected', select(2, C.PayEmployee(OWN1, 'qa', '1', EMP)) == 'insufficient_funds' and #credits == 0)
    mv('credit', 'qa', '1', 5000, { kind = 'deposit', key = 'qa-fund-1' })
    local p1, pr1 = C.PayEmployee(OWN1, 'qa', '1', EMP)
    check('payroll.insufficient_attempt_did_not_burn_cooldown', p1 == true and pr1.amount == 500)
    check('payroll.paid_from_business_funds', balance('1') == 4500 and #credits == 1 and credits[1][1] == EMP and credits[1][2] == 500)
    check('payroll.exactly_once_cooldown', select(2, C.PayEmployee(OWN1, 'qa', '1', EMP)) == 'cooldown' and balance('1') == 4500 and #credits == 1)
    MySQL.update.await("UPDATE cm_business_employees SET last_paid_at = NULL WHERE business_type = 'qa'")
    failCredit = true
    check('payroll.credit_failure_refunds_business', select(2, C.PayEmployee(OWN1, 'qa', '1', EMP)) == 'settlement_failed' and balance('1') == 4500)
    local refunded = MySQL.scalar.await("SELECT COUNT(*) FROM cm_business_transactions WHERE business_type = 'qa' AND kind = 'payroll' AND status = 'refunded'")
    check('payroll.failed_payment_marked_refunded', tonumber(refunded) == 1)
    failCredit = false
    check('payroll.failure_does_not_burn_cooldown', C.PayEmployee(MGR, 'qa', '1', EMP) == true and balance('1') == 4000)
    MySQL.update.await("UPDATE cm_business_employees SET last_paid_at = NULL WHERE business_type = 'qa'")
    local races = parallel(5, function() return C.PayEmployee(OWN1, 'qa', '1', EMP) end)
    local paid = 0
    for _, r in ipairs(races) do if r[1] == true then paid = paid + 1 end end
    check('payroll.concurrent_requests_pay_once', paid == 1 and balance('1') == 3500, ('paid=%d balance=%s'):format(paid, tostring(balance('1'))))
    local sumCredits = 0
    for _, c in ipairs(credits) do sumCredits = sumCredits + c[2] end
    local settled = tonumber(MySQL.scalar.await("SELECT COALESCE(SUM(amount),0) FROM cm_business_transactions WHERE business_type = 'qa' AND kind = 'payroll' AND status = 'settled'"))
    check('payroll.no_money_minted', settled == sumCredits and (5000 - balance('1')) == sumCredits, ('settled=%s credits=%s'):format(tostring(settled), tostring(sumCredits)))
    local before = balance('1')
    mv('debit', 'qa', '1', 100, { kind = 'payroll', key = 'qa-pending', targetCid = EMP, status = 'pending' })
    MySQL.update.await("UPDATE cm_business_transactions SET created_at = DATE_SUB(UTC_TIMESTAMP(), INTERVAL 5 MINUTE) WHERE idempotency_key = 'qa-pending'")
    check('payroll.reconcile_refunds_unsettled', C.ReconcilePayroll() >= 1 and balance('1') == before and C.ledgerByKey('qa-pending').status == 'refunded')

    C.ResetRateLimits()
    -- OWNERSHIP CHANGE ---------------------------------------------------------------------
    local _, pendTok = C.InviteCore(OWN1, OUT, 'qa', '1')
    local epochBefore = tonumber(MySQL.scalar.await("SELECT epoch FROM cm_business_state WHERE business_type = 'qa' AND business_id = '1'"))
    C.CreateRank(OWN1, 'qa', '1', { name = 'OldCustom', tier = 33 })
    check('ownership.staff_exists_before_change', #C.GetEmployees('qa', '1') >= 3)
    setOwner(1, NEWOWN)
    check('ownership.old_owner_loses_authority', C.HasBusinessPermission('qa', '1', OWN1, 'business.manage_ranks') == false and select(2, C.InviteCore(OWN1, OUT, 'qa', '1')) == 'forbidden')
    check('ownership.new_owner_established', C.GetBusinessOwner('qa', '1') == NEWOWN and C.HasBusinessPermission('qa', '1', NEWOWN, 'business.manage_ranks') == true)
    check('ownership.employees_cleared', #C.GetEmployees('qa', '1') == 0 and C.HasBusinessPermission('qa', '1', MGR, 'business.invite') == false and C.IsEmployee('qa', '1', EMP) == false)
    check('ownership.pending_invites_invalidated', select(2, C.RespondCore(OUT, pendTok, true)) == 'invalid_invite')
    check('ownership.custom_ranks_reset', rankByName('qa', '1', 'OldCustom') == nil and #C.GetRanks('qa', '1') == 3)
    local epochAfter = tonumber(MySQL.scalar.await("SELECT epoch FROM cm_business_state WHERE business_type = 'qa' AND business_id = '1'"))
    check('ownership.epoch_bumped', epochAfter == epochBefore + 1)
    check('ownership.change_audited', tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_business_activity WHERE business_type = 'qa' AND business_id = '1' AND action = 'ownership_changed'")) == 1)
    check('ownership.payroll_stops_for_old_staff', select(2, C.PayEmployee(NEWOWN, 'qa', '1', EMP)) == 'not_employee' and select(2, C.PayEmployee(OWN1, 'qa', '1', EMP)) == 'forbidden')
    check('ownership.resolve_is_stable', (function()
        for _ = 1, 3 do C.Resolve('qa', '1') end
        return tonumber(MySQL.scalar.await("SELECT epoch FROM cm_business_state WHERE business_type = 'qa' AND business_id = '1'")) == epochAfter and #C.GetRanks('qa', '1') == 3
    end)())
    check('ownership.new_owner_can_hire', hire(NEWOWN, 'qa', '1', EMP) == true)
    setOwner(1, nil)
    check('forfeiture.no_owner_no_authority', C.HasBusinessPermission('qa', '1', NEWOWN, 'business.invite') == false and C.IsEmployee('qa', '1', EMP) == false and select(2, C.InviteCore(NEWOWN, OUT, 'qa', '1')) == 'no_owner')
    check('forfeiture.credit_rejected', select(2, mv('credit', 'qa', '1', 10, { kind = 'x' })) == 'no_owner' and C.GetBusinessBalance('qa', '1') == nil)
    setOwner(1, OWN1)
    check('forfeiture.rebuy_starts_clean', #C.GetEmployees('qa', '1') == 0 and C.HasBusinessPermission('qa', '1', OWN1, 'business.invite') == true)

    -- RESTART / FIRST OBSERVATION --------------------------------------------------------------
    check('restart.first_observation_keeps_staff', (function()
        hire(OWN1, 'qa', '1', EMP)
        MySQL.query.await("DELETE FROM cm_business_state WHERE business_type = 'qa' AND business_id = '1'") -- simulate fresh state row
        C.Resolve('qa', '1')
        return C.IsEmployee('qa', '1', EMP) == true
    end)())

    C.ResetRateLimits()
    -- ADMIN RECOVERY -----------------------------------------------------------------------------
    MySQL.query.await("INSERT INTO cm_business_employees (business_type, business_id, character_id, rank_id) VALUES ('qa', '1', ?, 999999)", { OUT })
    check('admin.orphan_rank_has_no_permissions', C.HasBusinessPermission('qa', '1', OUT, 'business.manage_stock') == false and C.GetEmployee('qa', '1', OUT).rankMissing == true)
    check('admin.orphan_cannot_be_paid', select(2, C.PayEmployee(OWN1, 'qa', '1', OUT)) == 'rank_missing')
    local inspect = C.AdminInspect('qa', '1')
    check('admin.inspect', inspect ~= nil and #inspect.employees >= 2 and #inspect.ranks == 3)
    local repair = C.AdminRepair('qa', '1', 'selftest')
    check('admin.repair_rehomes_orphans', repair ~= nil and repair.employeesRepaired >= 1 and C.GetEmployee('qa', '1', OUT).rankMissing == false)
    check('admin.reset_rank', C.AdminResetEmployeeRank('qa', '1', OUT, trainee.id and rankByName('qa', '1', 'Trainee').id, 'selftest') == true)
    check('admin.remove_employee', C.AdminRemoveEmployee('qa', '1', OUT, 'selftest') == true and C.IsEmployee('qa', '1', OUT) == false)
    check('admin.activity_readable', #(C.AdminGetActivity('qa', '1', 20) or {}) > 0)
    check('admin.caller_allowlist', Config.AdminCallers['cm-admin'] == true and Config.AdminCallers['evil'] == nil)

    -- SUPPLY / ORDERS (selftest_supply.lua) ---------------------------------------------------------------
    C.TestInvoker = 'cm-commercial-ownership'
    C.RunSupplyTests(check, {})
    C.TestInvoker = nil
    C.ResetRateLimits()
    -- BILLING INTEGRATION ----------------------------------------------------------------------------
    if GetResourceState('cm-billing') == 'started' then
        C.TestSkipIssuer = true -- synthetic actor ids are not characters
        local real = MySQL.scalar.await('SELECT id FROM characters ORDER BY id LIMIT 1')
        local function dest(d) return exports['cm-billing']:CreateInvoice({ recipientCharacterId = tostring(real or ''), amount = 100, label = 'QA business invoice', issuerType = 'business', issuerLabel = 'QA Shop', destination = d, metadata = { ['business.type'] = 'qa' } }) end
        check('billing.unknown_business_destination_rejected', select(2, dest({ type = 'business', id = 'qa:999' })) == 'invalid_destination')
        check('billing.garbage_destination_rejected', select(2, dest({ type = 'business', id = "qa:1';DROP" })) == 'invalid_destination' and select(2, dest({ type = 'business', id = '' })) == 'invalid_destination')
        check('billing.unowned_destination_rejected', select(2, dest({ type = 'business', id = 'qa:4' })) == 'invalid_destination')
        if real then
            local okInv, inv = C.CreateBusinessInvoice(OWN1, 'qa', '1', { recipientCharacterId = real, amount = 100, label = 'QA business invoice' })
            check('billing.owner_creates_business_invoice', okInv == true and type(inv) == 'table' and type(inv.reference) == 'string', okInv == true and '' or inv)
            if okInv == true then
                check('billing.invoice_voidable_by_issuer', exports['cm-billing']:VoidInvoice(inv.reference, 'selftest cleanup') == true)
            end
            check('billing.outsider_cannot_create_invoice', select(2, C.CreateBusinessInvoice(9100099, 'qa', '1', { recipientCharacterId = real, amount = 100, label = 'x y' })) == 'forbidden')
            check('billing.amount_bounds', select(2, C.CreateBusinessInvoice(OWN1, 'qa', '1', { recipientCharacterId = real, amount = Config.Invoices.MaxAmount + 1, label = 'x y' })) == 'invalid_amount'
                and select(2, C.CreateBusinessInvoice(OWN1, 'qa', '1', { recipientCharacterId = real, amount = 0, label = 'x y' })) == 'invalid_amount')
            check('billing.cannot_invoice_self', select(2, C.CreateBusinessInvoice(OWN1, 'qa', '1', { recipientCharacterId = OWN1, amount = 100, label = 'x y' })) == 'invalid_recipient')
            check('billing.unauthorised_employee_cannot_invoice', (function()
                C.UpdateRank(OWN1, 'qa', '1', rankByName('qa', '1', 'Trainee').id, { name = 'Trainee' })
                hire(OWN1, 'qa', '1', OUT, rankByName('qa', '1', 'Trainee').id)
                return select(2, C.CreateBusinessInvoice(OUT, 'qa', '1', { recipientCharacterId = real, amount = 100, label = 'x y' })) == 'forbidden'
            end)())
        end
    else
        print('[cm-commercial-ownership:selftest] SKIP  billing integration (cm-billing not started)')
    end

    return total, failed
end

RegisterCommand('cm_business_selftest', function(src)
    if src ~= 0 then return end
    if not enabled() then
        print('[cm-commercial-ownership:selftest] refused: requires cm_environment=development')
        return
    end
    if not C.EnsureSchema() then
        print('[cm-commercial-ownership:selftest] BLOCKED: schema not ready')
        return
    end
    local ok, total, failed = pcall(run)
    local cleaned = pcall(cleanup)
    if not ok then
        print(('[cm-commercial-ownership:selftest] ERROR %s'):format(tostring(total)))
        return
    end
    print(('[cm-commercial-ownership:selftest] %d checks, %d failed, cleanup=%s'):format(total, failed, tostring(cleaned)))
end, true)

CreateThread(function()
    Wait(1500)
    print(('[cm-commercial-ownership] business foundation ready (schema=%s, types=%d)'):format(tostring(CMB.schemaReady), (function() local n = 0 for _ in pairs(CMB.types) do n = n + 1 end return n end)()))
end)
