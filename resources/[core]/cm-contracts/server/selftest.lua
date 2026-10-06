-- Development-only SQL smoke test:  server console -> cm_contracts_selftest
-- Requires cm_environment=development; console only. Runs the real core against the real MySQL store with a
-- synthetic source ('qa-source') and provider ('qa-provider'), a controllable clock and doubles for the
-- cross-resource calls, then deletes every row it created. The full state-machine matrix lives in tests/selftest.lua.
local Config, Core, Store = CMContracts.Config, CMContracts.Core, CMContracts.Store

RegisterCommand('cm_contracts_selftest', function(src)
    if src ~= 0 then return end
    if GetConvar(Config.SelfTest.convar, 'production') ~= Config.SelfTest.value then
        print('[cm-contracts:selftest] refused: cm_environment is not development'); return
    end
    local passed, failed = 0, 0
    local function check(name, ok, detail)
        if ok == true then passed = passed + 1; print(('[cm-contracts:selftest] PASS  %s'):format(name))
        else failed = failed + 1; print(('[cm-contracts:selftest] FAIL  %s %s'):format(name, detail and ('(' .. tostring(detail) .. ')') or '')) end
    end
    local function cleanup()
        MySQL.query.await("DELETE FROM cm_contract_events WHERE contract_id IN (SELECT id FROM cm_contracts WHERE source_resource = 'qa-source')")
        MySQL.query.await("DELETE FROM cm_contracts WHERE source_resource = 'qa-source'")
    end
    cleanup()

    local cfg = setmetatable({
        Sources = { ['qa-source'] = { types = { business_supply = true }, completeExport = 'C', fallbackExport = 'F', cancelExport = 'X' } },
        Providers = { ['qa-provider'] = { providerTypes = { trucking = true } } },
    }, { __index = Config })
    local clock, applied, fallbackCalls = os.time(), 0, 0
    local function call(resource, name)
        if resource == 'qa-source' and name == 'C' then applied = applied + 1; return true, true end
        if resource == 'qa-source' and name == 'F' then fallbackCalls = fallbackCalls + 1; applied = applied + 1; return true, true end
        return true, true
    end
    -- The sweep must only ever see this test's own rows (never real contracts, which the fake call would "complete").
    local qaStore = setmetatable({ query = function(kind, arg, limit)
        local out = {}
        for _, r in ipairs(Store.query(kind, arg, 200)) do if r.source_resource == 'qa-source' then out[#out + 1] = r end end
        return out
    end }, { __index = Store })
    local core = Core.New({ cfg = cfg, store = qaStore, now = function() return clock end, call = call,
        encode = function(t) local ok, s = pcall(json.encode, t); return ok and s or '' end })
    check('register provider', core:RegisterProvider('qa-provider', 'trucking', { types = { 'business_supply' } }) == true)

    local ok, a = core:CreateContract('qa-source', { contractType = 'business_supply', sourceReference = 'QA-1', title = 'qa', metadata = { units = 5 } })
    check('create', ok == true and a.reference ~= nil and a.existing == false)
    local ok2, a2 = core:CreateContract('qa-source', { contractType = 'business_supply', sourceReference = 'QA-1' })
    check('unique source key returns existing', ok2 == true and a2.existing == true and a2.reference == a.reference
        and tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_contracts WHERE source_resource = 'qa-source'")) == 1)
    check('untrusted source rejected', select(2, core:CreateContract('qa-evil', { contractType = 'business_supply', sourceReference = 'QA-X' })) == 'untrusted_source')
    local _, list = core:ListAvailable('qa-provider', 'trucking', {}, '9001')
    check('list available', #list == 1 and list[1].reference == a.reference)

    -- claim race: both attempts hit the guarded UPDATE; exactly one wins
    local r1 = { core:Claim('qa-provider', a.reference, '9001') }
    local r2 = { core:Claim('qa-provider', a.reference, '9002') }
    check('claim race: one winner', r1[1] == true and r2[1] == false and r2[2] == 'already_claimed')
    check('claimed character persisted (no source id)', MySQL.scalar.await('SELECT claimed_character_id FROM cm_contracts WHERE reference = ?', { a.reference }) == '9001')
    check('mark active', core:MarkActive('qa-provider', a.reference, '9001') == true)
    check('wrong worker cannot complete', select(2, core:Complete('qa-provider', a.reference, '9002')) == 'not_claimant')
    local cok, cres = core:Complete('qa-provider', a.reference, '9001')
    check('player completion once', cok == true and cres.rewardable == true and applied == 1)
    local rok, rres = core:Complete('qa-provider', a.reference, '9001')
    check('completion replay not rewardable', rok == true and rres.rewardable == false and applied == 1)
    check('terminal event written once', tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_contract_events e JOIN cm_contracts c ON c.id = e.contract_id WHERE c.reference = ? AND e.journal_key = 'terminal'", { a.reference })) == 1)

    -- fallback: nobody works it, the clock passes the deadline
    local _, b = core:CreateContract('qa-source', { contractType = 'business_supply', sourceReference = 'QA-2' })
    clock = clock + 31 * 60
    core:Sweep(); core:Sweep()
    local row = Store.getByRef(b.reference)
    check('fallback completes once with mode fallback', row.status == 'completed' and row.completion_mode == 'fallback' and fallbackCalls == 1 and row.claimed_character_id == nil)

    -- lease expiry then reappears
    local _, c = core:CreateContract('qa-source', { contractType = 'business_supply', sourceReference = 'QA-3' })
    core:Claim('qa-provider', c.reference, '9003')
    clock = clock + 901
    core:Sweep()
    check('lease expiry releases claim', Store.getByRef(c.reference).status == 'available' and Store.getByRef(c.reference).claimed_character_id == nil)
    check('admin inspect has timeline', (function() local ok3, d = core:AdminInspect(c.reference); return ok3 and #d.events >= 3 end)())
    check('source cancel', core:Cancel('qa-source', 'business_supply', 'QA-3', 'qa') == true and Store.getByRef(c.reference).status == 'cancelled')

    cleanup()
    check('cleanup', tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_contracts WHERE source_resource = 'qa-source'")) == 0)
    print(('[cm-contracts:selftest] %d checks, %d failed'):format(passed + failed, failed))
end, true)
