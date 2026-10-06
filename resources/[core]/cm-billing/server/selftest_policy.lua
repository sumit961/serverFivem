-- Development-only provider-policy / high-value billing self-test (runs after the main and refund suites from `cm_billing_selftest`).
-- Real MySQL for invoices + refund journal; money owners are in-memory stand-ins. Uses the REAL Config.Providers['cm-mechanic'] policy.
local S = CMBilling.Server
local Config = CMBilling.Config

local PREFIX = 'qa-bill-'

function S.PolicySelfTest()
    local results, failed = {}, 0
    local function check(name, cond, detail)
        results[#results + 1] = name
        if cond ~= true then
            failed = failed + 1
            print(('[cm-billing:policy-selftest] FAIL  %s %s'):format(name, detail ~= nil and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-billing:policy-selftest] PASS  %s'):format(name))
        end
    end

    S.RefundSelfTestCleanup()
    local A = PREFIX .. 'a'
    S.TestCharacters = { [A] = true }
    local HARD = Config.HardMaxAmount
    local MECH = Config.Providers['cm-mechanic']
    local MECH_LIMIT = math.min(MECH.maxAmount, HARD)
    S.TestProviders = {
        ['qa-high'] = { maxAmount = 2000000, issuerTypes = { system = true, business = true }, destinations = { city = true, business = true }, allowOffline = true, metadataNamespace = 'hi', canVoid = true, canRefund = true },
        ['qa-low'] = { maxAmount = 50000, issuerTypes = { system = true, business = true }, destinations = { city = true, business = true }, allowOffline = true, metadataNamespace = 'lo', canVoid = true, canRefund = true },
        ['qa-huge'] = { maxAmount = 999999999, issuerTypes = { system = true }, destinations = { city = true }, allowOffline = true, metadataNamespace = 'hg', canVoid = true },
        ['qa-broken'] = { maxAmount = 'lots', issuerTypes = { system = true }, destinations = { city = true }, allowOffline = true, metadataNamespace = 'br', canVoid = true },
    }

    -- doubles ------------------------------------------------------------------------------
    local bank = { [A] = 20000000 }
    local biz = {}
    local applied = { debit = {}, credit = {} }
    local counts = { debit = 0, credit = 0 }
    local audits = {}
    local orig = { Money = S.Money, Dest = S.Destinations, Notifier = S.Notifier, RDest = S.RefundDestinations, RPayer = S.RefundPayer, audit = S.audit }
    S.audit = function(kind, detail) audits[#audits + 1] = { kind = kind, detail = detail } end
    S.Money = {
        Debit = function(src, account, amount) if (bank[src] or 0) < amount then return false end bank[src] = bank[src] - amount return true end,
        CreditCharacter = function(cid, account, amount) bank[cid] = (bank[cid] or 0) + amount return true end,
        Balance = function(src) return bank[src] or 0 end,
    }
    S.Destinations = {
        city = orig.Dest.city,
        business = {
            available = function() return true end,
            validate = function(id) return type(id) == 'string' and id:match('^[%w_]+:[%w_]+$') ~= nil end,
            credit = function(inv) biz[inv.destination_id] = (biz[inv.destination_id] or 0) + tonumber(inv.amount) return true, tonumber(inv.amount) end,
            evidence = function() return false end,
        },
        character = { available = function() return true end, validate = function() return true end, credit = function() return true end, evidence = function() return false end },
        family = { available = function() return true end, validate = function() return true end, credit = function() return true end, evidence = function() return false end },
    }
    S.Notifier = { created = function() end, paid = function() end }
    S.RefundDestinations = { business = {
        available = function() return true end,
        debit = function(j)
            local key = S.RefundDebitKey(j)
            if applied.debit[key] then return true end
            if (biz[j.destination_id] or 0) < tonumber(j.amount) then return false, 'insufficient_funds' end
            biz[j.destination_id] = biz[j.destination_id] - tonumber(j.amount)
            applied.debit[key] = true; counts.debit = counts.debit + 1
            return true
        end,
        evidence = function(j) return applied.debit[S.RefundDebitKey(j)] == true end,
    } }
    S.RefundPayer = {
        Credit = function(j)
            local key = S.RefundCreditKey(j)
            if applied.credit[key] then return true end
            bank[j.payer_character_id] = (bank[j.payer_character_id] or 0) + tonumber(j.amount)
            applied.credit[key] = true; counts.credit = counts.credit + 1
            return true
        end,
        Evidence = function(j) return applied.credit[S.RefundCreditKey(j)] == true end,
    }
    local seq = 0
    local function ref(p) seq = seq + 1 return ('%s-%d-%d'):format(p or 'qa-pol', GetGameTimer(), seq) end
    local function mk(provider, amount, over)
        local d = { recipientCharacterId = A, amount = amount, label = 'QA job', issuerLabel = 'QA Garage', issuerType = 'system', destination = { type = 'city' } }
        for k, v in pairs(over or {}) do d[k] = v end
        return S.CreateInvoice(provider, d)
    end
    local function mkBiz(provider, amount, id) return mk(provider, amount, { issuerType = 'business', destination = { type = 'business', id = id or 'qa:1' } }) end

    -- PROVIDER POLICY ---------------------------------------------------------------------
    local pol = S.GetProviderPolicy('cm-mechanic')
    check('policy.mechanic_limit_is_provider_specific_not_global', pol and pol.maxInvoiceAmount == MECH_LIMIT and MECH_LIMIT > 50000 and Config.Providers['cm-commercial-ownership'].maxAmount == 50000)
    check('policy.mechanic_view_shape', pol.canRefund == true and pol.platformMaxAmount == HARD and #pol.destinations == 1 and pol.destinations[1] == 'business' and pol.issuerTypes[1] == 'business' and pol.allowOffline == false)
    check('policy.view_never_exposes_other_providers_or_metadata', pol.metadataNamespace == nil and pol.maxAmount == nil)
    check('policy.unknown_provider_forbidden', select(2, S.GetProviderPolicy('totally-unknown')) == 'forbidden')
    check('policy.disabled_provider_forbidden', select(2, S.GetProviderPolicy('cm-law')) == 'forbidden' and select(2, mk('cm-law', 100)) == 'forbidden')
    check('policy.nil_caller_forbidden', select(2, S.GetProviderPolicy(nil)) == 'forbidden')
    check('policy.low_cap_provider', S.GetProviderPolicy('qa-low').maxInvoiceAmount == 50000)
    check('policy.platform_ceiling_clamps_huge_provider_limit', S.GetProviderPolicy('qa-huge').maxInvoiceAmount == HARD)
    check('policy.misconfigured_limit_fails_closed', S.GetProviderPolicy('qa-broken').maxInvoiceAmount == 0 and select(2, mk('qa-broken', 1)) == 'amount_exceeds_provider_limit')
    check('policy.commercial_ownership_limit_unchanged_50000', select(1, S.GetProviderPolicy('cm-commercial-ownership')) ~= nil and S.GetProviderPolicy('cm-commercial-ownership').maxInvoiceAmount == 50000)

    -- AMOUNT BOUNDS -----------------------------------------------------------------------
    for _, bad in ipairs({ 0, -1, -50000, 1.5, '100', '1e6', 0 / 0, math.huge, -math.huge, true, false }) do
        check('amount.invalid_' .. tostring(bad), select(2, mk('qa-high', bad)) == 'invalid_amount')
    end
    check('amount.provider_max_minus_one_accepted', mk('qa-high', 1999999) == true)
    check('amount.provider_max_accepted', mk('qa-high', 2000000) == true)
    check('amount.provider_max_plus_one_rejected_with_stable_reason', select(2, mk('qa-high', 2000001)) == 'amount_exceeds_provider_limit')
    check('amount.platform_max_accepted_when_provider_allows', mk('qa-huge', HARD) == true)
    check('amount.platform_max_plus_one_rejected_with_platform_reason', select(2, mk('qa-huge', HARD + 1)) == 'amount_exceeds_platform_limit')
    check('amount.platform_max_never_reachable_by_a_lower_provider', select(2, mk('qa-high', HARD)) == 'amount_exceeds_provider_limit')
    check('amount.stored_exactly_in_bigint', (function()
        local _, v = mk('qa-huge', HARD)
        return tonumber(MySQL.scalar.await('SELECT amount FROM cm_billing_invoices WHERE public_reference = ?', { v.reference })) == HARD end)())
    local rejects = {}
    for _, a in ipairs(audits) do if a.kind == 'cm_billing_invoice_rejected' then rejects[#rejects + 1] = a.detail end end
    check('audit.rejections_record_provider_amount_limit_reason', #rejects >= 3 and rejects[1].provider ~= nil and rejects[1].limit ~= nil and rejects[1].amount ~= nil and rejects[1].reason ~= nil)

    -- PROVIDER ISOLATION ------------------------------------------------------------------
    check('isolation.same_amount_accepted_from_high_rejected_from_low', mk('qa-high', 120000) == true and select(2, mk('qa-low', 120000)) == 'amount_exceeds_provider_limit')
    check('isolation.mechanic_accepts_high_value', (function() S.TestOnline = { [A] = A } local ok = mkBiz('cm-mechanic', 120000, 'mechanic:qa1') S.TestOnline = nil return ok == true end)())
    check('isolation.cannot_impersonate_mechanic_by_data_fields', (function()
        local ok, v = mk('qa-low', 120000, { provider = 'cm-mechanic', issuerResource = 'cm-mechanic', maxAmount = 999999999, issuerEntityId = 'mechanic:x' })
        return ok == false and v == 'amount_exceeds_provider_limit' end)())
    check('isolation.invoice_pins_the_real_invoking_provider', (function()
        local ok, v = mk('qa-low', 900, { provider = 'cm-mechanic', issuerResource = 'cm-mechanic' })
        local row = S.GetRow(v.reference)
        return ok == true and row.issuer_resource == 'qa-low' end)())
    check('isolation.arbitrary_resource_cannot_issue_under_mechanics_limit', select(2, mk('some-random-resource', 120000)) == 'forbidden' and select(2, mk('cm-mechanic-fake', 120000)) == 'forbidden')
    check('isolation.client_supplied_cap_ignored', select(2, mk('qa-low', 60000, { maxInvoiceAmount = 999999999, limit = 999999999 })) == 'amount_exceeds_provider_limit')

    -- DESTINATION POLICY -------------------------------------------------------------------
    S.TestOnline = { [A] = A }
    check('dest.mechanic_business_destination_with_mechanic_prefix_ok', mkBiz('cm-mechanic', 5000, 'mechanic:main') == true)
    check('dest.mechanic_other_business_type_rejected', select(2, mkBiz('cm-mechanic', 5000, 'store:3')) == 'destination_not_allowed')
    check('dest.mechanic_city_destination_rejected', select(2, mk('cm-mechanic', 5000, { issuerType = 'business', destination = { type = 'city' } })) == 'destination_not_allowed')
    check('dest.mechanic_character_destination_rejected', select(2, mk('cm-mechanic', 5000, { issuerType = 'business', destination = { type = 'character', id = A } })) == 'destination_not_allowed')
    check('dest.mechanic_family_destination_rejected', select(2, mk('cm-mechanic', 5000, { issuerType = 'business', destination = { type = 'family', id = '7' } })) == 'destination_not_allowed')
    check('dest.mechanic_system_issuer_rejected', select(2, mk('cm-mechanic', 5000, { issuerType = 'system', destination = { type = 'business', id = 'mechanic:main' } })) == 'forbidden_issuer_type')
    check('dest.unknown_destination_type_still_invalid', select(2, mk('qa-high', 100, { destination = { type = 'bank_of_mars' } })) == 'invalid_destination')
    S.TestOnline = nil
    local before = #audits
    mk('qa-low', 100, { issuerType = 'business', destination = { type = 'character', id = A } })
    check('audit.destination_rejection_recorded', audits[#audits] and audits[#audits].kind == 'cm_billing_invoice_rejected' and audits[#audits].detail.reason == 'destination_not_allowed' and #audits > before)

    -- EXISTING INVOICE COMPATIBILITY (creation limit only) ---------------------------------------
    local okI, inv = mkBiz('qa-high', 1800000, 'qa:cap')
    check('existing.high_value_invoice_issued_under_current_policy', okI == true)
    S.TestProviders['qa-high'].maxAmount = 80000     -- config later lowers the cap
    check('existing.cap_lowered_blocks_only_NEW_creation', select(2, mkBiz('qa-high', 1800000, 'qa:cap')) == 'amount_exceeds_provider_limit' and S.GetProviderPolicy('qa-high').maxInvoiceAmount == 80000)
    local paid, info = S.PayInvoice(A, A, inv.reference, 'bank')
    check('existing.invoice_still_payable_after_cap_lowered', paid == true and S.GetRow(inv.reference).status == 'paid' and biz['qa:cap'] == 1800000, info)
    local rOk, rView = S.RequestRefund('qa-high', inv.reference, ref('qa-lowered'), 300000, 'service_failed')
    check('existing.invoice_still_refundable_after_cap_lowered_partial', rOk == true and rView.status == 'completed' and rView.amount == 300000)
    local rOk2, rView2 = S.RequestRefund('qa-high', inv.reference, ref('qa-rest'), nil, 'service_cancelled')
    check('existing.remaining_refundable_in_full_beyond_current_cap', rOk2 == true and rView2.amount == 1500000 and S.GetInvoiceRefundState('qa-high', inv.reference).refundState == 'refunded')
    S.TestProviders['qa-high'].maxAmount = 2000000

    -- HIGH-VALUE REFUND (real mechanic policy, 120,000) -------------------------------------------
    S.TestOnline = { [A] = A }
    local okM, mech = mkBiz('cm-mechanic', 120000, 'mechanic:qa2')
    S.TestOnline = nil
    local paidM = S.PayInvoice(A, A, mech.reference, 'bank')
    local custBefore, bizBefore = bank[A], biz['mechanic:qa2']
    local d0, c0 = counts.debit, counts.credit
    check('refund.high_value_mechanic_invoice_paid', okM == true and paidM == true and bizBefore == 120000)
    local fOk, fv = S.RequestRefund('cm-mechanic', mech.reference, 'mechanic-hv-full-001', nil, 'service_failed')
    check('refund.high_value_full_refund_completes_exactly_once', fOk == true and fv.status == 'completed' and fv.amount == 120000 and biz['mechanic:qa2'] == 0 and bank[A] == custBefore + 120000 and counts.debit == d0 + 1 and counts.credit == c0 + 1)
    S.RequestRefund('cm-mechanic', mech.reference, 'mechanic-hv-full-001', nil, 'service_failed'); S.RetryRefund('cm-mechanic', 'mechanic-hv-full-001')
    check('refund.high_value_replay_moves_nothing', counts.debit == d0 + 1 and counts.credit == c0 + 1 and biz['mechanic:qa2'] == 0)
    S.TestOnline = { [A] = A }
    local _, mech2 = mkBiz('cm-mechanic', 120000, 'mechanic:qa3')
    S.TestOnline = nil
    S.PayInvoice(A, A, mech2.reference, 'bank')
    local pOk, pv = S.RequestRefund('cm-mechanic', mech2.reference, 'mechanic-hv-part-001', 20000, 'service_cancelled')
    local st = S.GetInvoiceRefundState('cm-mechanic', mech2.reference)
    check('refund.high_value_partial_refund_net_paid', pOk == true and pv.status == 'completed' and st.paidAmount == 120000 and st.refundedAmount == 20000 and st.netPaidAmount == 100000 and biz['mechanic:qa3'] == 100000)
    check('refund.high_value_cumulative_bound', select(2, S.RequestRefund('cm-mechanic', mech2.reference, 'mechanic-hv-part-002', 100001, 'service_failed')) == 'refund_exceeds_paid'
        and select(1, S.RequestRefund('cm-mechanic', mech2.reference, 'mechanic-hv-part-003', 100000, 'service_failed')) == true and S.GetInvoiceRefundState('cm-mechanic', mech2.reference).refundState == 'refunded')
    check('refund.not_limited_by_creation_cap', (function()
        local limitNow = S.ProviderLimit(Config.Providers['cm-mechanic'])
        return limitNow >= 120000 and S.RefundSQL ~= nil and not (LoadResourceFile(GetCurrentResourceName(), 'server/refund.lua') or ''):find('ProviderLimit', 1, true) end)())

    -- CONCURRENT HIGH-VALUE PAYMENT --------------------------------------------------------------
    local _, c1 = mkBiz('qa-high', 1500000, 'qa:race')
    local _, c2 = mkBiz('qa-high', 1500000, 'qa:race')
    bank[A] = 2000000
    local bizRace0, out = biz['qa:race'] or 0, {}
    for i, r in ipairs({ c1.reference, c2.reference }) do
        CreateThread(function() out[i] = { S.PayInvoice(A, A, r, 'bank') } end)
    end
    local waited = 0
    while (not out[1] or not out[2]) and waited < 8000 do Wait(50) waited = waited + 50 end
    local wins = (out[1] and out[1][1] == true and 1 or 0) + (out[2] and out[2][1] == true and 1 or 0)
    check('concurrent.two_1_5M_invoices_one_payer_2M_exactly_one_pays', wins == 1 and bank[A] == 500000 and (biz['qa:race'] or 0) == bizRace0 + 1500000)
    local statuses = { S.GetRow(c1.reference).status, S.GetRow(c2.reference).status }
    table.sort(statuses)
    check('concurrent.invoice_states_consistent_no_stuck_settling', statuses[1] == 'paid' and statuses[2] == 'pending')

    -- SECURITY ----------------------------------------------------------------------------------
    local function src(f) return LoadResourceFile(GetCurrentResourceName(), f) or '' end
    local all = src('server/invoices.lua') .. src('server/exports.lua') .. src('server/main.lua') .. src('server/refund.lua')
    check('security.no_net_event_or_callback_can_change_limits', not all:find('RegisterNetEvent', 1, true) and not all:lower():find("callback%.register%('cm%-billing:[%w_]*limit") and not all:lower():find("callback%.register%('cm%-billing:[%w_]*polic"))
    check('security.no_export_registers_or_mutates_provider_policy', not all:find('Config%.Providers%[[^%]]*%]%s*=[^=]') and not all:find('SetProviderPolicy', 1, true) and not all:find('RegisterProvider', 1, true))
    check('security.policy_export_takes_no_provider_argument', src('server/exports.lua'):find("exports%('GetProviderPolicy', function%(%)") ~= nil)

    S.audit, S.Money, S.Destinations, S.Notifier, S.RefundDestinations, S.RefundPayer = orig.audit, orig.Money, orig.Dest, orig.Notifier, orig.RDest, orig.RPayer
    S.TestProviders, S.TestCharacters, S.TestOnline = nil, nil, nil
    S.RefundSelfTestCleanup()
    check('cleanup.policy_rows_removed', (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_billing_invoices WHERE recipient_character_id LIKE ?', { PREFIX .. '%' })) or 1) == 0)
    print(('[cm-billing:policy-selftest] RESULT %s: %d checks, %d failed'):format(failed == 0 and 'PASS' or 'FAIL', #results, failed))
end
