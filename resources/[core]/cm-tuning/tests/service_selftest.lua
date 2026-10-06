-- Deterministic self-test: mechanic-mediated tuning authorization (server/service_core.lua + server/service.lua) AND the unchanged self-service path.
--   lua tests/service_selftest.lua        (run from resources/[core]/cm-tuning)
-- See tests/harness.lua for what is REAL (config, core, main.lua, service.lua) and what is a labelled double (FiveM runtime, exports, SQL, journal store).
local here = (arg and arg[0] or ''):match('^(.*)[/\\]tests[/\\]') or '.'
local H = dofile(here .. '/tests/harness.lua')
local vec, json = H.vec, H.json
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond == true then passed = passed + 1; print('PASS  ' .. name)
    else failed = failed + 1; print('FAIL  ' .. name .. (detail ~= nil and ('  (' .. tostring(detail) .. ')') or '')) end
end

local MECH, CUST = '5', '1'
local function scene(opts)
    local W = H.build(opts)
    W.addPlayer(11, MECH, vec(2, 0, 0)); W.addPlayer(12, CUST, vec(0, 3, 0))
    W.addVehicle(77, { plate = 'AB12CD', owner_character_id = 1, pos = vec(0, 0, 0) })
    return W
end
local function ctx(over)
    local c = { workOrder = 'WO-1', mechanicCid = MECH, customerCid = CUST, businessType = 'mechanic', businessId = 'main', vehicleId = 77, shop = 'chip', maxAmount = 50000 }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end
local CAPS = { engine = 3, brakes = 3, transmission = 3, suspension = 3, armor = 4 }
local function authorize(W, over) local ok, a = W.as('cm-mechanic', 'CreateMechanicTuningAuthorization', ctx(over)); return ok, a end
local function propose(W, ref, changes, caps)
    local ok, why = W.as('cm-mechanic', 'OpenMechanicTuningSession', ref, 11, 977)
    if ok ~= true then return false, why end
    local token = W.lastClient('cm-tuning:client:openService').args[1].token
    W.timer = W.timer + 5000; W.clearEvents()
    W.fire(11, 'cm-tuning:server:servicePropose', { token = token, caps = caps or CAPS, changes = changes })
    local denied = W.lastClient('cm-tuning:client:purchaseDenied')
    if denied then return false, denied.args[1] end
    return true, W.lastClient('cm-tuning:client:serviceProposed').args[1]
end
local function quoted(W, changes, over)
    local ok, a = authorize(W, over); assert(ok, a)
    local okP, p = propose(W, a.reference, changes); assert(okP, p)
    return a.reference, p
end
local function pay(W, ref)   -- the mechanic's side of the saga: bind the invoice, billing reports paid, mark paid
    W.invoices['INV-' .. ref] = 'pending'
    local okB = W.as('cm-mechanic', 'BindMechanicTuningInvoice', ref, 'INV-' .. ref)
    W.invoices['INV-' .. ref] = 'paid'
    return okB, W.as('cm-mechanic', 'MarkMechanicTuningPaid', ref, 'INV-' .. ref)
end
local TURBO = { toggles = { turbo = true } }

-- ================================================================== trusted callers
do
    local W = scene()
    local names = { 'CreateMechanicTuningAuthorization', 'OpenMechanicTuningSession', 'GetMechanicTuningQuote', 'ValidateMechanicTuningQuote', 'BindMechanicTuningInvoice',
        'ReleaseMechanicTuningInvoice', 'MarkMechanicTuningPaid', 'ExecuteMechanicTuning', 'GetMechanicTuningStatus', 'CancelMechanicTuning' }
    for _, who in ipairs({ 'cm-trade', 'cm-phone', 'cm-billing', 'cm-vehicles', 'rogue', '' }) do
        local allDenied = true
        for _, n in ipairs(names) do local ok, why = W.as(who, n, ctx()); if ok ~= false or why ~= 'forbidden' then allDenied = false end end
        check('TRUST ' .. (who == '' and '<empty>' or who) .. ' is denied on every mechanic-service export', allDenied)
    end
    W.invoker = nil
    check('TRUST nil invoker fails closed', select(2, W.registry.CreateMechanicTuningAuthorization(ctx())) == 'forbidden')
    W.invoker = 'cm-mechanic'
    local ok = authorize(W)
    check('TRUST cm-mechanic may create an authorization', ok == true)
    local netExposed = false
    for name in pairs(W.netHandlers) do if name:lower():find('mechanic') or name:lower():find('authoriz') then netExposed = true end end
    check('TRUST no net event creates, binds, pays or executes a mechanic authorization', netExposed == false)
    check('TRUST the only service net event is the mechanic session proposal', W.netHandlers['cm-tuning:server:servicePropose'] ~= nil)
    check('TRUST the quoted notice is a LOCAL server event (clients cannot trigger it)', (function() for name in pairs(W.netHandlers) do if name == 'cm-tuning:service:quoted' then return false end end return true end)())
end

-- ================================================================== authorization binding
do
    local W = scene()
    local ok, a = authorize(W)
    check('AUTH valid authorization is bound and returns only a reference', ok == true and a.reference:match('^TUN%-') ~= nil and a.shop == 'chip')
    local row = W.store.get(a.reference)
    check('AUTH row binds work order, mechanic, customer, business, vehicle_id and shop', row.work_order_ref == 'WO-1' and row.mechanic_cid == MECH and row.customer_cid == CUST and row.business_type == 'mechanic'
        and row.business_id == 'main' and row.vehicle_id == 77 and row.shop == 'chip' and row.status == 'created' and row.owner_snapshot == 'character:1')
    local ok2, a2 = authorize(W)
    check('AUTH replay of the same context returns the same authorization (idempotent)', ok2 == true and a2.reference == a.reference and a2.replayed == true)
    local ok3, a3 = authorize(W, { shop = 'workshop' })
    check('AUTH a changed context for the same work order supersedes the unpaid one', ok3 == true and a3.reference ~= a.reference and W.store.get(a.reference).status == 'cancelled')
    check('AUTH unsupported shop / repair-like operation is rejected', select(2, authorize(W, { shop = 'repair', workOrder = 'WO-2' })) == 'unsupported_operation' and select(2, authorize(W, { shop = 'engine_rebuild', workOrder = 'WO-2' })) == 'unsupported_operation')
    check('AUTH missing / malformed fields rejected', select(2, authorize(W, { workOrder = '' })) == 'invalid_request' and select(2, authorize(W, { vehicleId = 'x', workOrder = 'WO-3' })) == 'invalid_request'
        and select(2, authorize(W, { mechanicCid = false, workOrder = 'WO-3' })) == 'invalid_request')
    check('AUTH unknown vehicle rejected', select(2, authorize(W, { vehicleId = 999, workOrder = 'WO-4' })) == 'vehicle_not_found')
    W.addVehicle(78, { plate = 'ZZ99ZZ', owner_character_id = 1 })
    local okV, whyV = authorize(W, { workOrder = 'WO-5' })
    check('AUTH a second live authorization on the SAME vehicle is refused (one mechanic tuning operation per vehicle)', okV == false and whyV == 'vehicle_busy')
    check('AUTH a different vehicle is independent', select(1, authorize(W, { workOrder = 'WO-6', vehicleId = 78 })) == true)
    -- expiry before payment
    W.clock = W.clock + 5000
    check('AUTH an unpaid authorization expires', (function() W.core:ExpireSweep(); return W.store.get(a3.reference).status == 'expired' end)())
    check('AUTH an expired authorization cannot be opened or quoted', select(2, W.as('cm-mechanic', 'OpenMechanicTuningSession', a3.reference, 11, 977)) == 'invalid_state')
    check('AUTH and the vehicle is free again for a new authorization', select(1, authorize(W, { workOrder = 'WO-7' })) == true)
end

-- ================================================================== session binding (the mechanic's tuning UI session)
do
    local W = scene()
    local _, a = authorize(W)
    W.addPlayer(13, '9', vec(1, 0, 0))
    check('SESSION a different character cannot open the mechanic session', select(2, W.as('cm-mechanic', 'OpenMechanicTuningSession', a.reference, 13, 977)) == 'wrong_mechanic')
    check('SESSION a different vehicle is refused (vehicle_id from server state, not the client handle)', (function() W.addVehicle(79, { plate = 'OT1', owner_character_id = 1 }); return select(2, W.as('cm-mechanic', 'OpenMechanicTuningSession', a.reference, 11, 979)) == 'wrong_vehicle' end)())
    W.players[11].pos = vec(50, 0, 0)
    check('SESSION the mechanic must be next to the vehicle', select(2, W.as('cm-mechanic', 'OpenMechanicTuningSession', a.reference, 11, 977)) == 'too_far')
    W.players[11].pos = vec(2, 0, 0); W.players[11].bucket = 3
    check('SESSION routing bucket must match', select(2, W.as('cm-mechanic', 'OpenMechanicTuningSession', a.reference, 11, 977)) == 'wrong_bucket')
    W.players[11].bucket = 0
    check('SESSION valid session opens the tuning UI for the mechanic only', W.as('cm-mechanic', 'OpenMechanicTuningSession', a.reference, 11, 977) == true and W.lastClient('cm-tuning:client:openService').src == 11)
    local token = W.lastClient('cm-tuning:client:openService').args[1].token
    -- forged token / other player cannot propose
    W.timer = W.timer + 5000; W.clearEvents()
    W.fire(12, 'cm-tuning:server:servicePropose', { token = token, caps = CAPS, changes = TURBO })
    check('SESSION another player cannot use the mechanic\'s token', W.lastClient('cm-tuning:client:purchaseDenied') ~= nil and W.store.get(a.reference).status == 'created')
    W.timer = W.timer + 5000; W.clearEvents()
    W.fire(11, 'cm-tuning:server:servicePropose', { token = 'forged', caps = CAPS, changes = TURBO })
    check('SESSION a forged token is refused', W.lastClient('cm-tuning:client:purchaseDenied') ~= nil and W.store.get(a.reference).status == 'created')
    -- a service session has NO self-service path: no direct charge, ever
    W.timer = W.timer + 5000; W.clearEvents()
    local cash0 = W.cash[MECH]
    W.fire(11, 'cm-tuning:server:purchase', { token = token, changes = TURBO, account = 'cash' })
    check('SESSION a service session cannot be used for a self-service purchase (no charge, no mods)', W.lastClient('cm-tuning:client:purchaseDenied') ~= nil and W.cash[MECH] == cash0 and #W.charges == 0 and W.vehicles[77].mods == nil)
    W.fire(11, 'cm-tuning:server:installHarness', { token = token }); W.fire(11, 'cm-tuning:server:repairEngine', { token = token })
    check('SESSION harness / engine repair are also closed to it', #W.charges == 0 and W.lastClient('cm-tuning:client:specialDenied') ~= nil)
end

-- ================================================================== quote (cm-tuning is the price owner)
do
    local W = scene()
    local ref, p = quoted(W, TURBO)
    check('QUOTE price comes from cm-tuning config (turbo)', p.amount == W.Config.Turbo.price and p.amount == 25000)
    local row = W.store.get(ref)
    check('QUOTE snapshot stores amount, revision, diff and base hash; status quoted', row.status == 'quoted' and row.amount == 25000 and row.revision == 1 and row.base_hash ~= nil and row.changes_json:find('turbo') ~= nil)
    local okQ, q = W.as('cm-mechanic', 'GetMechanicTuningQuote', ref)
    check('QUOTE the mechanic reads the bound quote (work order, parties, vehicle, amount, description)', okQ == true and q.workOrder == 'WO-1' and q.mechanicCid == MECH and q.customerCid == CUST and q.vehicleId == 77 and q.amount == 25000 and q.description:find('Turbo') ~= nil)
    check('QUOTE the proposal notified the mechanic resource through the local event', (function() for _, e in ipairs(W.localEvents) do if e.name == 'cm-tuning:service:quoted' and e.args[1] == ref then return true end end return false end)())
    -- client-supplied prices are ignored
    local W2 = scene()
    local ref2 = select(1, quoted(W2, { toggles = { turbo = true }, price = 1, amount = 1, total = 1 }))
    check('QUOTE client price fields are ignored', W2.store.get(ref2).amount == 25000)
    -- performance level pricing
    local W3 = scene()
    local _, p3 = quoted(W3, { slots = { engine = 1 } })
    check('QUOTE performance level price = pricePerLevel * (index + 1)', p3.amount == 12000 * 2)
    -- over the invoice cap: refused, never clamped
    local W4 = scene()
    local _, a4 = authorize(W4)
    local ok4, why4 = propose(W4, a4.reference, { slots = { engine = 3 }, toggles = { turbo = true } })
    check('QUOTE a job above the invoice cap is REFUSED (engine L4 + turbo = 73,000 > 50,000), not clamped or repriced', ok4 == false and why4:find('maximum invoice') ~= nil and W4.store.get(a4.reference).status == 'created')
    local ok5 = propose(W4, a4.reference, { slots = { engine = 3 } })
    check('QUOTE the maximum single performance item (48,000) fits the cap', ok5 == true and W4.store.get(a4.reference).amount == 48000)
    -- re-quote: a changed selection replaces the old quote (revision), the cheap option cannot be reused for the expensive one
    local W5 = scene()
    local ref5 = select(1, quoted(W5, TURBO))
    local okR = propose(W5, ref5, { slots = { brakes = 1 } })
    local row5 = W5.store.get(ref5)
    check('QUOTE changing the selection re-quotes the same authorization (revision 2, new amount, new diff)', okR == true and row5.revision == 2 and row5.amount == 16000 and row5.changes_json:find('turbo') == nil)
    -- invalid / repair-like / unsupported operations
    local W6 = scene()
    local _, a6 = authorize(W6)
    check('QUOTE no selection is refused', select(1, propose(W6, a6.reference, {})) == false)
    check('QUOTE an engine repair is not a tuning operation (nothing billable)', select(1, propose(W6, a6.reference, { repairEngine = true, engineHealth = 1000, fullRebuild = true })) == false)
    check('QUOTE harness is not a mechanic-service operation', select(1, propose(W6, a6.reference, { toggles = { harness = true } })) == false)
    check('QUOTE an out-of-range level is refused', select(1, propose(W6, a6.reference, { slots = { engine = 9 } })) == false)
    check('QUOTE an unknown slot is refused', select(1, propose(W6, a6.reference, { slots = { warpDrive = 1 } })) == false)
    check('QUOTE a stock/no-op target is not billable', select(1, propose(W6, a6.reference, { toggles = { turbo = false } })) == false)
    check('QUOTE nothing was persisted and nobody was charged by any refused proposal', W6.vehicles[77].mods == nil and #W6.charges == 0)
end

-- ================================================================== revalidate / stale quote
do
    local W = scene()
    local ref = select(1, quoted(W, TURBO))
    check('REVALIDATE a fresh quote revalidates at the quoted price', select(1, W.as('cm-mechanic', 'ValidateMechanicTuningQuote', ref)) == true and select(2, W.as('cm-mechanic', 'ValidateMechanicTuningQuote', ref)).amount == 25000)
    W.vehicles[77].mods = json.encode({ mods = { ['11'] = 1 } })       -- the vehicle was tuned meanwhile (self-service)
    local ok, why = W.as('cm-mechanic', 'ValidateMechanicTuningQuote', ref)
    check('REVALIDATE a vehicle changed since the quote invalidates it (requote needed)', ok == false and why == 'vehicle_changed')
    W.vehicles[77].mods = nil
    W.vehicles[77].owner_character_id = 2
    local ok2, why2 = W.as('cm-mechanic', 'ValidateMechanicTuningQuote', ref)
    check('REVALIDATE an ownership change before payment invalidates it', ok2 == false and why2 == 'ownership_changed')
    W.vehicles[77].owner_character_id = 1
    W.clock = W.clock + 100000
    check('REVALIDATE an expired unpaid quote is refused', select(2, W.as('cm-mechanic', 'ValidateMechanicTuningQuote', ref)) == 'expired')
    -- price rises: refused
    local W2 = scene()
    local ref2 = select(1, quoted(W2, TURBO))
    W2.Config.Turbo.price = 30000
    check('REVALIDATE a higher current price makes the quote stale (the customer never pays more than quoted)', select(2, W2.as('cm-mechanic', 'ValidateMechanicTuningQuote', ref2)) == 'quote_changed')
end

-- ================================================================== invoice / payment / apply
do
    local W = scene()
    local ref = select(1, quoted(W, TURBO))
    check('PAY unpaid quote cannot be executed', select(2, W.as('cm-mechanic', 'ExecuteMechanicTuning', ref)) == 'not_paid' and W.vehicles[77].mods == nil)
    check('PAY marking paid before an invoice is bound is refused', select(2, W.as('cm-mechanic', 'MarkMechanicTuningPaid', ref, 'INV-X')) == 'invalid_state')
    W.invoices['INV-1'] = 'pending'
    check('PAY the invoice binds once; the same bind replays; a different invoice conflicts', W.as('cm-mechanic', 'BindMechanicTuningInvoice', ref, 'INV-1') == true and select(2, W.as('cm-mechanic', 'BindMechanicTuningInvoice', ref, 'INV-1')).replayed == true
        and select(2, W.as('cm-mechanic', 'BindMechanicTuningInvoice', ref, 'INV-2')) == 'invoice_conflict')
    check('PAY a changed selection after the invoice exists is refused (no re-quote of an invoiced authorization)', (function()
        W.as('cm-mechanic', 'OpenMechanicTuningSession', ref, 11, 977); return select(2, W.as('cm-mechanic', 'OpenMechanicTuningSession', ref, 11, 977)) == 'invalid_state' end)())
    check('PAY unpaid invoice is not accepted as paid', select(2, W.as('cm-mechanic', 'MarkMechanicTuningPaid', ref, 'INV-1')) == 'not_paid')
    W.billingDown = true
    check('PAY billing unavailable is transient (not a failure of the operation)', select(2, W.as('cm-mechanic', 'MarkMechanicTuningPaid', ref, 'INV-1')) == 'billing_unavailable')
    W.billingDown = false
    W.invoices['INV-1'] = 'paid'
    check('PAY the wrong invoice reference is refused even when billing says paid', select(2, W.as('cm-mechanic', 'MarkMechanicTuningPaid', ref, 'INV-2')) == 'invoice_conflict')
    check('PAY billing says paid -> paid; replay is idempotent', W.as('cm-mechanic', 'MarkMechanicTuningPaid', ref, 'INV-1') == true and select(2, W.as('cm-mechanic', 'MarkMechanicTuningPaid', ref, 'INV-1')).replayed == true and W.store.get(ref).status == 'paid')
    check('PAY after payment the quote can no longer be released or cancelled (forward-only, no refund API)', select(2, W.as('cm-mechanic', 'ReleaseMechanicTuningInvoice', ref)) == 'paid_forward_only' and select(2, W.as('cm-mechanic', 'CancelMechanicTuning', ref, 'x')) == 'paid_forward_only')
    W.clock = W.clock + 1000000; W.core:ExpireSweep()
    check('PAY a paid operation never expires', W.store.get(ref).status == 'paid')
    local ok, r = W.as('cm-mechanic', 'ExecuteMechanicTuning', ref)
    check('APPLY paid authorization applies once and persists the modification on the vehicle_id', ok == true and r.replayed == false and W.mods(77).turbo == true and W.modWrites == 1 and W.store.get(ref).status == 'committed')
    local ok2, r2 = W.as('cm-mechanic', 'ExecuteMechanicTuning', ref)
    check('APPLY a duplicate execute replays the committed result (no second write)', ok2 == true and r2.replayed == true and W.modWrites == 1)
    check('APPLY the client was told to show it on the streamed vehicle', W.lastClient('cm-tuning:client:serviceApplied') ~= nil and W.lastClient('cm-tuning:client:serviceApplied').args[1] == 977)
    check('APPLY no direct cm-tuning charge happened anywhere in the mechanic flow', #W.charges == 0 and #W.refunds == 0)
    local st = select(2, W.as('cm-mechanic', 'GetMechanicTuningStatus', ref))
    check('APPLY status reports committed with the bound invoice and amount', st.status == 'committed' and st.invoiceRef == 'INV-1' and st.amount == 25000 and st.appliedAt ~= nil)
    check('APPLY the vehicle is free for the next authorization', select(1, authorize(W, { workOrder = 'WO-NEXT' })) == true)
end

-- ================================================================== forward recovery / idempotency
do
    -- response lost after commit
    local W = scene()
    local ref = select(1, quoted(W, TURBO)); pay(W, ref)
    W.as('cm-mechanic', 'ExecuteMechanicTuning', ref)       -- result discarded
    check('RECOVERY response lost after commit: a retry replays, nothing is applied twice', select(2, W.as('cm-mechanic', 'ExecuteMechanicTuning', ref)).replayed == true and W.modWrites == 1)
    -- crash while applying: row stuck in `applying`, nothing written
    local W2 = scene()
    local ref2 = select(1, quoted(W2, TURBO)); pay(W2, ref2)
    W2.store.cas(ref2, { 'paid' }, { status = 'applying', attempts = 1 })
    local ok, r = W2.as('cm-mechanic', 'ExecuteMechanicTuning', ref2)
    check('RECOVERY crash while applying: a retry resumes forward and applies once', ok == true and r.installed == 'written' and W2.mods(77).turbo == true and W2.modWrites == 1 and W2.store.get(ref2).attempts == 2)
    -- crash after the write but before the journal commit: target already installed
    local W3 = scene()
    local ref3 = select(1, quoted(W3, TURBO)); pay(W3, ref3)
    W3.vehicles[77].mods = json.encode(W3.T.Internal.defaultMods(json.encode({ turbo = true })))   -- the write landed, the journal did not
    W3.store.cas(ref3, { 'paid' }, { status = 'applying' })
    local ok3, r3 = W3.as('cm-mechanic', 'ExecuteMechanicTuning', ref3)
    check('RECOVERY target already installed: reconciled to committed without a second write', ok3 == true and r3.installed == 'already' and W3.modWrites == 0 and W3.store.get(ref3).status == 'committed')
    -- cm-tuning restart: a fresh service engine over the same journal
    local W4 = scene()
    local ref4 = select(1, quoted(W4, TURBO)); pay(W4, ref4)
    local W4b = scene({ store = W4.store, clock = W4.clock })
    W4b.vehicles[77].mods = W4.vehicles[77].mods
    local ok4, r4 = W4b.as('cm-mechanic', 'ExecuteMechanicTuning', ref4)
    check('RECOVERY cm-tuning restart between payment and apply: the paid journal row resumes forward', ok4 == true and W4b.mods(77).turbo == true and W4b.store.get(ref4).status == 'committed')
    -- restart at quote / invoice stages
    local W5 = scene()
    local ref5 = select(1, quoted(W5, TURBO))
    local W5b = scene({ store = W5.store, clock = W5.clock })
    check('RECOVERY restart after the quote: the quote is intact and still validates', select(1, W5b.as('cm-mechanic', 'GetMechanicTuningQuote', ref5)) == true)
    -- vehicle unavailable after payment: forward-only, never lost
    local W6 = scene()
    local ref6 = select(1, quoted(W6, TURBO)); pay(W6, ref6)
    local saved = W6.vehicles[77]; W6.vehicles[77] = nil
    local okU, whyU = W6.as('cm-mechanic', 'ExecuteMechanicTuning', ref6)
    check('RECOVERY vehicle temporarily unavailable after payment: not applied, not cancelled, stays pending forward', okU == false and whyU == 'vehicle_unavailable' and W6.store.get(ref6).status == 'applying')
    W6.vehicles[77] = saved
    check('RECOVERY ... and applies exactly once when the vehicle returns', select(1, W6.as('cm-mechanic', 'ExecuteMechanicTuning', ref6)) == true and W6.mods(77).turbo == true and W6.modWrites == 1)
    -- ownership changed AFTER payment: still applies (customer paid)
    local W7 = scene()
    local ref7 = select(1, quoted(W7, TURBO)); pay(W7, ref7)
    W7.vehicles[77].owner_character_id = 2
    check('RECOVERY ownership change after payment does not void the paid service', select(1, W7.as('cm-mechanic', 'ExecuteMechanicTuning', ref7)) == true and W7.mods(77).turbo == true)
end

-- ================================================================== concurrency / no lost modifications
do
    -- mechanic apply vs a self-service session on the same vehicle
    local W = scene()
    local ref = select(1, quoted(W, TURBO)); pay(W, ref)
    W.T.Internal.openServiceSession(12, { mode = 'self', plate = 'AB12CD', token = 't', expiresAt = 1e12 })   -- (any player session holding the vehicle lock)
    local ok, why = W.as('cm-mechanic', 'ExecuteMechanicTuning', ref)
    check('CONCURRENCY a player session holds the vehicle: the paid apply waits (busy), nothing is lost', ok == false and why == 'busy' and W.vehicles[77].mods == nil and W.store.get(ref).status == 'paid')
    W.T.Internal.releaseSession(12, 'done')
    check('CONCURRENCY ... and applies once the session is gone', select(1, W.as('cm-mechanic', 'ExecuteMechanicTuning', ref)) == true and W.mods(77).turbo == true)
    -- a compare-and-swap loss is retried against the fresh state
    local W2 = scene()
    local ref2 = select(1, quoted(W2, TURBO)); pay(W2, ref2)
    W2.casFailOnce = true
    local ok2, r2 = W2.as('cm-mechanic', 'ExecuteMechanicTuning', ref2)
    check('CONCURRENCY a lost compare-and-swap is retried and still applies exactly once', ok2 == true and W2.modWrites == 1 and W2.mods(77).turbo == true)
    -- a different slot changed after payment is preserved (diff merge, no downgrade of unrelated fields)
    local W3 = scene()
    local ref3 = select(1, quoted(W3, TURBO)); pay(W3, ref3)
    W3.vehicles[77].mods = json.encode({ mods = { ['11'] = 2, ['12'] = 1 }, primaryColor = 27 })   -- tuned meanwhile
    W3.as('cm-mechanic', 'ExecuteMechanicTuning', ref3)
    local m = W3.mods(77)
    check('CONCURRENCY post-payment apply merges ONLY the paid change: later engine/brake/paint work is preserved', m.turbo == true and m.mods['11'] == 2 and m.mods['12'] == 1 and m.primaryColor == 27)
    -- level upgrade is absolute (no stacking, no downgrade of a slot that is higher already is NOT silently skipped: the paid target wins)
    local W4 = scene()
    local ref4 = select(1, quoted(W4, { slots = { engine = 1 } })); pay(W4, ref4)
    W4.as('cm-mechanic', 'ExecuteMechanicTuning', ref4); W4.as('cm-mechanic', 'ExecuteMechanicTuning', ref4)
    check('CONCURRENCY an upgrade level is an absolute target (replays never stack)', W4.mods(77).mods['11'] == 1 and W4.modWrites == 1)
    -- two authorizations racing for the same vehicle: exactly one wins
    local W5 = scene()
    local a = select(1, authorize(W5, { workOrder = 'WO-A' })); local b, why5 = authorize(W5, { workOrder = 'WO-B' })
    check('CONCURRENCY two mechanic tuning operations for the same vehicle: one wins, the other is refused', a == true and b == false and why5 == 'vehicle_busy')
    -- self-service session open denied while the mechanic session holds the vehicle
    local W6 = scene()
    local _, a6 = authorize(W6)
    W6.as('cm-mechanic', 'OpenMechanicTuningSession', a6.reference, 11, 977)
    W6.vehicles[77].pos = W6.Config.Shops.chip.Locations[1]; W6.entities[W6.vehicles[77].entity].pos = W6.Config.Shops.chip.Locations[1]
    W6.players[12].pos = W6.Config.Shops.chip.Locations[1]; W6.players[12].inVeh = W6.vehicles[77].entity; W6.players[12].seat = -1
    W6.clearEvents(); W6.timer = W6.timer + 5000
    W6.fire(12, 'cm-tuning:server:requestOpen', { shop = 'chip', netId = 977, plate = 'AB12CD', caps = CAPS })
    check('CONCURRENCY self-service cannot open on a vehicle the mechanic session holds', W6.lastClient('cm-tuning:client:denied') ~= nil and W6.lastClient('cm-tuning:client:open') == nil)
end

-- ================================================================== cancellation / release before payment
do
    local W = scene()
    local ref = select(1, quoted(W, TURBO))
    check('CANCEL an unpaid quote can be cancelled and frees the vehicle', W.as('cm-mechanic', 'CancelMechanicTuning', ref, 'declined') == true and W.store.get(ref).status == 'cancelled' and select(1, authorize(W, { workOrder = 'WO-9' })) == true)
    local W2 = scene()
    local ref2 = select(1, quoted(W2, TURBO)); W2.invoices['INV-1'] = 'pending'; W2.as('cm-mechanic', 'BindMechanicTuningInvoice', ref2, 'INV-1')
    check('CANCEL an invoiced authorization is not cancellable directly (the invoice owner must void it)', select(2, W2.as('cm-mechanic', 'CancelMechanicTuning', ref2, 'x')) == 'invoice_pending')
    check('CANCEL ... releasing the voided/expired invoice kills the quote and frees the vehicle', W2.as('cm-mechanic', 'ReleaseMechanicTuningInvoice', ref2) == true and W2.store.get(ref2).status == 'cancelled' and select(1, authorize(W2, { workOrder = 'WO-9' })) == true)
    check('CANCEL unknown reference', select(2, W2.as('cm-mechanic', 'CancelMechanicTuning', 'TUN-NOPE', 'x')) == 'not_found')
end

-- ================================================================== SELF-SERVICE tuning is unchanged
do
    local W = scene()
    local shopPos = W.Config.Shops.chip.Locations[1]
    W.vehicles[77].pos = shopPos; W.entities[W.vehicles[77].entity].pos = shopPos
    W.players[12].pos = shopPos; W.players[12].inVeh = W.vehicles[77].entity; W.players[12].seat = -1
    W.clearEvents(); W.timer = W.timer + 5000
    W.fire(12, 'cm-tuning:server:requestOpen', { shop = 'chip', netId = 977, plate = 'AB12CD', caps = CAPS })
    local open = W.lastClient('cm-tuning:client:open')
    check('SELF-SERVICE the owner in the driver seat opens the session as before', open ~= nil and open.src == 12)
    W.timer = W.timer + 5000; W.clearEvents()
    W.fire(12, 'cm-tuning:server:purchase', { token = open.args[1].token, changes = TURBO, account = 'cash' })
    check('SELF-SERVICE purchase still charges the customer directly at the config price', #W.charges == 1 and W.charges[1].amount == 25000 and W.charges[1].cid == CUST and W.cash[CUST] == 100000 - 25000)
    check('SELF-SERVICE the modification is persisted and approved to the client', W.mods(77).turbo == true and W.lastClient('cm-tuning:client:purchaseApproved') ~= nil and W.lastClient('cm-tuning:client:purchaseApproved').args[1].price == 25000)
    check('SELF-SERVICE no mechanic journal row is involved', #W.store.rows == 0)
    -- price unchanged for performance and cosmetic
    local W2 = scene()
    W2.vehicles[77].pos = shopPos; W2.entities[W2.vehicles[77].entity].pos = shopPos
    W2.players[12].pos = shopPos; W2.players[12].inVeh = W2.vehicles[77].entity; W2.players[12].seat = -1
    W2.timer = W2.timer + 5000
    W2.fire(12, 'cm-tuning:server:requestOpen', { shop = 'chip', netId = 977, plate = 'AB12CD', caps = CAPS })
    W2.timer = W2.timer + 5000
    W2.fire(12, 'cm-tuning:server:purchase', { token = W2.lastClient('cm-tuning:client:open').args[1].token, changes = { slots = { engine = 1 }, tyres = 2 }, account = 'cash' })
    check('SELF-SERVICE performance pricing is unchanged (engine L2 24,000 + tyres L2 14,000)', W2.charges[1] and W2.charges[1].amount == 24000 + 14000)
    -- engine rebuild stays closed
    local W3 = scene()
    W3.vehicles[77].pos = shopPos; W3.entities[W3.vehicles[77].entity].pos = shopPos
    W3.players[12].pos = shopPos; W3.players[12].inVeh = W3.vehicles[77].entity; W3.players[12].seat = -1
    W3.timer = W3.timer + 5000
    W3.fire(12, 'cm-tuning:server:requestOpen', { shop = 'chip', netId = 977, plate = 'AB12CD', caps = CAPS })
    local tok3 = W3.lastClient('cm-tuning:client:open').args[1].token
    W3.timer = W3.timer + 5000; W3.clearEvents()
    W3.fire(12, 'cm-tuning:server:repairEngine', { token = tok3 })
    check('SELF-SERVICE the engine rebuild stays closed (repair belongs to cm-mechanic)', #W3.charges == 0 and W3.lastClient('cm-tuning:client:specialDenied').args[1]:find('mechanic') ~= nil and W3.Config.EngineRepair.enabled == false)
end

-- ================================================================== pricing ownership
do
    local W = scene()
    local cfg = W.Config
    local P = W.T.Internal
    check('PRICING cm-tuning keeps performance, cosmetic and harness prices (no mechanic formula involved)', cfg.Turbo.price == 25000 and cfg.Harness.price == 18000 and cfg.Performance[1].pricePerLevel == 12000 and cfg.resprayPrice == 2500)
    local src = H.slurp(here .. '/server/service_core.lua') .. H.slurp(here .. '/server/service.lua')
    check('PRICING cm-tuning never calls ServiceVehicle or the mechanic repair formulas', not src:find('ServiceVehicle', 1, true) and not src:find('Pricing.parts', 1, true) and not src:find('CMMechanic', 1, true))
    check('PRICING the mechanic-service path contains no money movement (RemoveMoney/AddMoney)', not src:find('RemoveMoney', 1, true) and not src:find('AddMoney', 1, true))
end

print(('cm-tuning service self-test: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
