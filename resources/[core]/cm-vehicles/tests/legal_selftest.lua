-- Deterministic local self-test for server/legal_core.lua (no FiveM, no DB).
--   lua tests/legal_selftest.lua          (run from resources/[core]/cm-vehicles)
-- The in-memory store mirrors the guarded-UPDATE semantics of server/legal.lua
-- (sale-pending guard, owner guard, UNIQUE license_number).
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
dofile(here .. '/server/legal_core.lua')
local Core = CMVehicles.LegalCore

local DAY = 86400
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and (' (' .. tostring(detail) .. ')') or '')) end
end

local cfg = {
    Enabled = true, Account = 'cash', MinimumValuation = 150000, EligibleOwnerTypes = { character = true },
    Registration = { numberPrefix = 'REG-', baseFee = 20000, valueRate = 0.005, maxFee = 150000, durationDays = 21, renewWindowDays = 7, claimAttempts = 8 },
    Insurance = { rate = 0.012, minimum = 6000, maximum = 200000, durationDays = 14, renewWindowDays = 3, recoveryDiscount = 0.5 },
}

-- --------------------------------------------------------------- fake world
local W
local function newWorld()
    W = { rows = {}, events = {}, refunds = {}, balance = {}, clock = 1000000, failApplyOnce = false,
        failAdd = false, usedNumbers = {}, forcedNumbers = {}, charges = 0, catalog = {} }
    local store = {}
    function store.getById(id) local r = W.rows[id]; if not r then return nil end
        local c = {}; for k, v in pairs(r) do c[k] = v end; return c end
    function store.getByLicense(n) for _, r in pairs(W.rows) do if r.license_number == n then return store.getById(r.id) end end end
    function store.catalogPrice(model) return W.catalog[model] end
    function store.claimLicense(id, cand, expiresAt, guard)
        local forced = table.remove(W.forcedNumbers, 1)
        if forced then cand = forced end
        if W.failClaim then return false end
        for _, r in pairs(W.rows) do if r.license_number == cand then return false end end -- UNIQUE
        local row = W.rows[id]
        if not row or row.license_number or row.sale_pending_token then return false end
        if guard and guard.owner_character_id and (row.owner_type ~= 'character' or row.owner_character_id ~= guard.owner_character_id) then return false end
        row.license_number = cand; row.registration_expires_at = expiresAt; row.registration_revoked_at = nil; return true
    end
    function store.applyLegal(id, guard, fields)
        if W.failApplyOnce then W.failApplyOnce = false; return 0 end
        local r = W.rows[id]
        if not r or r.sale_pending_token then return 0 end
        if guard and guard.owner_character_id and (r.owner_type ~= 'character' or r.owner_character_id ~= guard.owner_character_id) then return 0 end
        for k, v in pairs(fields) do if v == false then r[k] = nil else r[k] = v end end
        return 1
    end
    function store.insertEvent(e) W.events[#W.events + 1] = e end
    function store.queueRefund(r) W.refunds[#W.refunds + 1] = r end
    local money = {
        remove = function(src, amount) if (W.balance[src] or 0) < amount then return false end
            W.balance[src] = W.balance[src] - amount; W.charges = W.charges + 1; return true end,
        add = function(src, amount) if W.failAdd then return false end W.balance[src] = (W.balance[src] or 0) + amount; return true end,
    }
    local seq = 0
    local core = Core.New({ cfg = cfg, store = store, money = money, now = function() return W.clock end,
        rand = function(lo, hi) seq = seq + 1; return lo + (seq * 7919) % (hi - lo) end })
    return core, store
end

local function addRow(id, fields)
    local r = { id = id, plate = 'PL' .. id, owner_type = 'character', owner_character_id = 'A', owner_name = 'Alice',
        model = 'm' .. id, state_value = 260000, metadata = {} }
    for k, v in pairs(fields or {}) do r[k] = v end
    W.rows[id] = r; return r
end
local A = function(src) return { src = src or 1, cid = 'A' } end

-- =========================================================== REGISTRATION
do
    local core = newWorld(); addRow(1); W.balance[1] = 1000000
    local before = W.balance[1]
    local r = core:Purchase(A(), 1, 'registration')
    check('REG valid owner registers', r.ok == true and r.action == 'register', r.error)
    check('REG number format + attached to vehicle_id', tostring(W.rows[1].license_number):match('^REG%-%d%d%d%d%d%d$') ~= nil)
    check('REG expiry set 21 days', W.rows[1].registration_expires_at == W.clock + 21 * DAY)
    check('REG status ACTIVE', core:GetLegalStatus(1).registrationStatus == 'ACTIVE')
    check('REG debited exactly once', before - W.balance[1] == r.charged and W.charges == 1)

    local s = core:Purchase({ src = 2, cid = 'B' }, 1, 'registration')
    check('REG non-owner rejected', s.ok == false and s.error == 'not_owner')

    local again = core:Purchase(A(), 1, 'registration')
    check('REG duplicate sequential request rejected (not due, no charge)', again.ok == false and again.error == 'not_due' and W.charges == 1)

    W.clock = W.clock + 15 * DAY -- 6 days remaining -> inside renew window
    local oldExp = W.rows[1].registration_expires_at
    local renew = core:Purchase(A(), 1, 'registration')
    check('REG renew inside window', renew.ok and renew.action == 'renew', renew.error)
    check('REG renew extends from existing expiry (no lost time)', W.rows[1].registration_expires_at == oldExp + 21 * DAY)
    check('REG number stable across renewal', W.rows[1].license_number == core:GetLegalStatus(1).registrationNumber)

    W.clock = W.rows[1].registration_expires_at + 1
    check('REG expiry deterministic -> EXPIRED', core:GetLegalStatus(1).registrationStatus == 'EXPIRED')
    local late = core:Purchase(A(), 1, 'registration')
    check('REG renew after expiry works, restarts from now', late.ok and W.rows[1].registration_expires_at == W.clock + 21 * DAY)
end

-- unique number / collision retry
do
    local core = newWorld(); addRow(1); addRow(2); W.balance[1] = 1e7
    W.rows[2].license_number = 'REG-111111'
    W.forcedNumbers = { 'REG-111111', 'REG-111111', 'REG-222222' } -- two collisions, then free
    local r = core:Purchase(A(), 1, 'registration')
    check('REG collision retried until unique', r.ok and W.rows[1].license_number == 'REG-222222', W.rows[1].license_number)
    local n = 0; for _, row in pairs(W.rows) do if row.license_number == 'REG-222222' then n = n + 1 end end
    check('REG unique across vehicles', n == 1)

    local core2 = newWorld(); addRow(1); W.balance[1] = 1e7
    for i = 1, 20 do W.forcedNumbers[i] = 'REG-333333' end
    addRow(2, { license_number = 'REG-333333' })
    local before = W.balance[1]
    local f = core2:Purchase(A(), 1, 'registration')
    check('REG exhausted collisions -> refunded, no number', f.ok == false and W.balance[1] == before and W.rows[1].license_number == nil, f.error)
end

-- revoke / reinstate / trusted issue
do
    local core = newWorld(); addRow(1); W.balance[1] = 1e7
    core:Purchase(A(), 1, 'registration')
    local ok = core:RevokeRegistration(1, 'officer-9', 'test', 'cm-law')
    check('REG revoke', ok == true and core:GetLegalStatus(1).registrationStatus == 'REVOKED')
    check('REG revoked keeps number (MDT still resolves)', core:LookupByRegistration(W.rows[1].license_number) ~= nil)
    local again = core:Purchase(A(), 1, 'registration')
    check('REG owner cannot renew a revoked registration', again.ok == false and again.error == 'registration_revoked')
    local ins = core:Purchase(A(), 1, 'insurance')
    check('INS revoked vehicle cannot buy insurance', ins.ok == false and ins.error == 'registration_required')
    check('REG revoke twice rejected', select(1, core:RevokeRegistration(1, 'officer-9', 'x', 'cm-law')) == false)
    check('REG reinstate', core:ReinstateRegistration(1, 'officer-9', 'appeal', 'cm-law') == true
        and core:GetLegalStatus(1).registrationStatus == 'ACTIVE')

    addRow(5)
    local ok2, msg, num = core:IssueRegistration(5, 'officer-9', 'cm-law')
    check('LAW trusted issue (free) works', ok2 == true and num ~= nil and W.rows[5].registration_expires_at ~= nil, msg)
    local ok3 = core:IssueRegistration(5, 'officer-9', 'cm-law')
    check('LAW issue twice rejected', ok3 == false)
    check('REG events recorded', (function() local seen = {} for _, e in ipairs(W.events) do seen[e.event] = true end
        return seen.registration_issued and seen.registration_revoked and seen.registration_reinstated end)())
end

-- legacy permanent registration
do
    local core = newWorld(); addRow(1, { license_number = 'REG-654321' })
    check('REG legacy permanent registration reads ACTIVE', core:GetLegalStatus(1).registrationStatus == 'ACTIVE')
    local q = core:quote(W.rows[1])
    check('REG legacy permanent not renewable (compat)', q.registration.available == false and q.registration.reason == 'legacy_permanent')
end

-- =============================================================== INSURANCE
do
    local core = newWorld(); addRow(1, { license_number = 'REG-100001' }); W.balance[1] = 1e7
    local pre = core:Purchase(A(), 1, 'insurance')
    check('INS buy', pre.ok and pre.action == 'buy', pre.error)
    check('INS ACTIVE + bound to owner', core:GetLegalStatus(1).insuranceStatus == 'ACTIVE' and W.rows[1].insurance_owner_id == 'A')
    check('INS expiry 14 days', W.rows[1].insurance_expires_at == W.clock + 14 * DAY)
    check('INS duplicate sequential rejected (not due)', core:Purchase(A(), 1, 'insurance').error == 'not_due' and W.charges == 1)
    W.clock = W.clock + 12 * DAY
    local rn = core:Purchase(A(), 1, 'insurance')
    check('INS renew in window', rn.ok and rn.action == 'renew', rn.error)
    W.clock = W.rows[1].insurance_expires_at + 5
    check('INS expires deterministically', core:GetLegalStatus(1).insuranceStatus == 'EXPIRED')
    check('INS non-owner rejected', core:Purchase({ src = 2, cid = 'B' }, 1, 'insurance').error == 'not_owner')
    check('INS unregistered vehicle cannot be insured', (function()
        addRow(2); return core:Purchase(A(), 2, 'insurance').error == 'registration_required' end)())
end

-- ============================================================== ECONOMY
do
    local core = newWorld()
    local cases = { { 'starter', 260000 }, { 'commuter', 525000 }, { 'sedan', 1050000 }, { 'sports', 4400000 },
        { 'super', 8750000 }, { 'ultra', 17500000 } }
    local ins = {}
    for _, c in ipairs(cases) do
        local row = addRow(100 + #ins, { state_value = c[2] })
        local q = core:quote(row)
        ins[#ins + 1] = q.insurance.price
        print(('      %-9s value=%9d registration=%7d insurance=%7d'):format(c[1], c[2], q.registration.price, q.insurance.price))
    end
    check('ECON premium scales with value (sedan < sports < super)', ins[3] < ins[4] and ins[4] < ins[5])
    check('ECON high-value premium > starter premium', ins[5] > ins[1])
    check('ECON premium respects maximum', ins[6] == 200000)
    local zero = addRow(200, { state_value = 0 })
    local qz = core:quote(zero)
    check('ECON zero-price vehicle floored (registration > 0)', qz.registration.price >= 20000 and qz.value == 150000)
    check('ECON zero-price vehicle floored (insurance > 0)', qz.insurance.price >= 6000)
    W.catalog['catalogcar'] = 0
    local zc = addRow(201, { state_value = 0, model = 'catalogcar' })
    check('ECON zero catalog price floored', core:quote(zc).insurance.price >= 6000)
    W.catalog['pricey'] = 4400000
    local pc = addRow(202, { state_value = 0, model = 'pricey' })
    check('ECON catalog price used when row value missing', core:quote(pc).value == 4400000)
end

-- ================================================================ MONEY
do
    local core = newWorld(); addRow(1); W.balance[1] = 100
    local r = core:Purchase(A(), 1, 'registration')
    check('MONEY insufficient funds rejected, nothing changed', r.ok == false and r.error == 'insufficient_funds'
        and W.rows[1].license_number == nil and W.balance[1] == 100 and W.charges == 0)

    W.balance[1] = 1e6
    W.failClaim = true
    local before = W.balance[1]
    local f = core:Purchase(A(), 1, 'registration')
    check('MONEY failed state change refunds (registration)', f.ok == false and f.error == 'apply_failed' and W.balance[1] == before)
    check('MONEY failed claim leaves no half-registered row', W.rows[1].license_number == nil and W.rows[1].registration_expires_at == nil)
    W.failClaim = false

    addRow(9, { license_number = 'REG-999999' }); W.balance[1] = 1e6
    local b9 = W.balance[1]
    W.failApplyOnce = true
    local f2 = core:Purchase(A(), 9, 'insurance')
    check('MONEY failed state change refunds (insurance)', f2.ok == false and f2.error == 'apply_failed' and W.balance[1] == b9)

    W.failApplyOnce = true; W.failAdd = true
    local g = core:Purchase(A(), 9, 'insurance')
    check('MONEY failed refund is journaled for later payout', g.ok == false and #W.refunds == 1 and W.refunds[1].amount > 0)
    W.failAdd = false
    W.balance[1] = 1e6

    -- replay safety
    local rid = 'req-1'
    local s1 = core:Purchase(A(), 1, 'registration', { requestId = rid })
    local balanceAfter, charges = W.balance[1], W.charges
    local s2 = core:Purchase(A(), 1, 'registration', { requestId = rid })
    check('MONEY replay returns prior result, no second charge', s1.ok and s2.replayed == true and s2.ok == true
        and W.balance[1] == balanceAfter and W.charges == charges)

    -- price confirmation
    addRow(2, { license_number = 'REG-777777', registration_expires_at = W.clock + 1 * DAY })
    local pc = core:Purchase(A(), 2, 'registration', { expectedPrice = 1 })
    check('MONEY stale/forged confirmation price rejected', pc.ok == false and pc.error == 'price_changed')
    check('MONEY client cannot reduce price (charged = server quote)', (function()
        local q = core:quote(W.rows[2]).registration.price
        local b = W.balance[1]
        local ok = core:Purchase(A(), 2, 'registration', { expectedPrice = q })
        return ok.ok and b - W.balance[1] == q end)())

    -- concurrency: a second request arriving mid-operation settles once
    local core3 = newWorld(); addRow(1); W.balance[1] = 1e6
    local nested
    local origRemove = nil
    local store = core3.store
    local realClaim = store.claimLicense
    store.claimLicense = function(id, cand)
        nested = core3:Purchase(A(), 1, 'registration') -- re-entrant while lock held
        return realClaim(id, cand)
    end
    local outer = core3:Purchase(A(), 1, 'registration')
    check('LOCK simultaneous request rejected busy, original settles once', outer.ok == true
        and nested.ok == false and nested.error == 'busy' and W.charges == 1)
    check('LOCK released after completion', core3:Purchase(A(), 1, 'insurance').ok == true)

    -- lock released after internal error
    local core4 = newWorld(); addRow(1); W.balance[1] = 1e6
    core4.store.claimLicense = function() error('boom') end
    local e1 = core4:Purchase(A(), 1, 'registration')
    check('LOCK internal error contained', e1.ok == false and e1.error == 'internal_error')
    core4.store.claimLicense = function(id, c) W.rows[id].license_number = c; return true end
    check('LOCK released after internal error', core4:Purchase(A(), 1, 'registration').ok == true)
end

-- ================================================================ IDENTITY
do
    local core = newWorld(); addRow(7, { plate = 'ABC123' }); addRow(8, { plate = 'XYZ789' }); W.balance[1] = 1e7
    core:Purchase(A(), 7, 'registration')
    local num = W.rows[7].license_number
    local byReg = core:LookupByRegistration(num)
    check('ID registration lookup resolves correct vehicle_id', byReg and byReg.vehicleId == 7)
    check('ID internal plate unchanged by registration', W.rows[7].plate == 'ABC123')
    check('ID public status excludes owner data by default', byReg.ownerCharacterId == nil and byReg.ownerName == nil and byReg.plate == nil)
    local trusted = core:LookupByRegistration(num, { includeOwner = true })
    check('ID trusted lookup includes owner', trusted.ownerCharacterId == 'A' and trusted.plate == 'ABC123')
    check('ID unknown registration -> nil', core:LookupByRegistration('REG-000000') == nil)
end

-- ================================================================ TRANSFER
do
    local core = newWorld(); addRow(1); W.balance[1] = 1e7; W.balance[2] = 1e7
    core:Purchase(A(), 1, 'registration'); core:Purchase(A(), 1, 'insurance')
    local number = W.rows[1].license_number
    -- ownership changes (hook called)
    W.rows[1].owner_character_id = 'B'; W.rows[1].owner_name = 'Bob'
    local ok, _, changed = core:OnOwnershipChanged(1, 'sale', 'test')
    check('XFER insurance invalidated by hook', ok and changed and core:GetLegalStatus(1).insuranceStatus == 'NONE')
    check('XFER public registration stays attached', W.rows[1].license_number == number
        and core:GetLegalStatus(1).registrationStatus == 'ACTIVE')
    check('XFER old owner loses service authority', core:Purchase(A(), 1, 'insurance').error == 'not_owner')
    local b = core:Purchase({ src = 2, cid = 'B' }, 1, 'insurance')
    check('XFER new owner buys own policy', b.ok and b.action == 'buy', b.error)

    -- defence in depth: owner changed WITHOUT the hook -> policy still invalid
    local core2 = newWorld(); addRow(1, { license_number = 'REG-424242' }); W.balance[1] = 1e7
    core2:Purchase(A(), 1, 'insurance')
    W.rows[1].owner_character_id = 'C'
    check('XFER policy invalid for new owner even if hook missed', core2:GetLegalStatus(1).insuranceStatus == 'NONE')

    -- ownership changed mid-request (guarded UPDATE refuses stale owner)
    local core3 = newWorld(); addRow(1, { license_number = 'REG-515151' }); W.balance[1] = 1e7
    local realApply = core3.store.applyLegal
    core3.store.applyLegal = function(id, guard, fields) W.rows[id].owner_character_id = 'Z'; return realApply(id, guard, fields) end
    local before = W.balance[1]
    local r = core3:Purchase(A(), 1, 'insurance')
    check('XFER owner change mid-request: not applied, refunded', r.ok == false and W.balance[1] == before and W.rows[1].insurance_expires_at == nil)

    -- pending state sale blocks legal changes
    local core4 = newWorld(); addRow(1, { sale_pending_token = 'tok' }); W.balance[1] = 1e7
    check('XFER pending sale blocks service', core4:Purchase(A(), 1, 'registration').error == 'vehicle_busy')
end

-- ================================================================== FLEET
do
    local core = newWorld(); W.balance[1] = 1e7
    addRow(1, { owner_type = 'organization', owner_character_id = 'organization:police', owner_name = 'LSPD' })
    local st = core:GetLegalStatus(1)
    check('FLEET organization vehicle exempt', st.registrationStatus == 'EXEMPT' and st.insuranceStatus == 'EXEMPT' and st.exempt)
    local r = core:Purchase({ src = 1, cid = 'organization:police' }, 1, 'registration')
    check('FLEET purchase refused, nothing charged', r.ok == false and W.charges == 0)
    local ok, _, number = core:IssueRegistration(1, 'officer', 'cm-law')
    check('FLEET law-issued number allowed (legacy compat), no expiry', ok and number and W.rows[1].registration_expires_at == nil)
end

-- ========================================================= RESTART / PERSISTENCE
do
    local core = newWorld(); addRow(1); W.balance[1] = 1e7
    core:Purchase(A(), 1, 'registration'); core:Purchase(A(), 1, 'insurance')
    local snapshot = { reg = W.rows[1].license_number, rexp = W.rows[1].registration_expires_at, iexp = W.rows[1].insurance_expires_at }
    -- "restart": a brand new core instance over the same persisted rows
    local store = core.store
    local core2 = Core.New({ cfg = cfg, store = store, money = { remove = function() return true end, add = function() return true end },
        now = function() return W.clock end })
    local st = core2:GetLegalStatus(1)
    check('RESTART state survives', st.registrationNumber == snapshot.reg and st.registrationExpiresAt == snapshot.rexp
        and st.insuranceExpiresAt == snapshot.iexp and st.registrationStatus == 'ACTIVE' and st.insuranceStatus == 'ACTIVE')
    local again = core2:Purchase(A(), 1, 'registration')
    check('RESTART no duplicate registration generated', again.ok == false and again.error == 'not_due' and W.rows[1].license_number == snapshot.reg)
    W.clock = snapshot.rexp + 1
    check('RESTART expiry deterministic after restart', core2:GetLegalStatus(1).registrationStatus == 'EXPIRED')
end

-- ================================================================ RECOVERY
do
    local core = newWorld(); addRow(1, { license_number = 'REG-909090' }); W.balance[1] = 1e7
    check('RECOVERY uninsured vehicle not insured', core:IsInsured(W.rows[1]) == false)
    core:Purchase(A(), 1, 'insurance')
    check('RECOVERY active policy detected', core:IsInsured(W.rows[1]) == true)
    W.clock = W.rows[1].insurance_expires_at + 1
    check('RECOVERY expired policy not insured', core:IsInsured(W.rows[1]) == false)
end

-- ================================================================= INPUTS
do
    local core = newWorld(); addRow(1)
    check('INPUT bad service rejected', core:Purchase(A(), 1, 'x').error == 'invalid_service')
    check('INPUT missing vehicle rejected', core:Purchase(A(), 99, 'registration').error == 'vehicle_not_found')
    check('INPUT nil vehicle id rejected', core:Purchase(A(), nil, 'registration').error == 'invalid_request')
    check('INPUT missing actor rejected', core:Purchase({ src = 1 }, 1, 'registration').error == 'invalid_request')
end

print(('\nlegal self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
