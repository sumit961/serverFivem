-- Player-facing callbacks: only what a player may do themselves (view own invoices, pay own invoice).
local S = CMBilling.Server
local Config = CMBilling.Config

local function register(name, bucket, fn)
    lib.callback.register('cm-billing:' .. name, function(src, a, b)
        local cid = S.CharacterOf(src)
        if not cid then return { ok = false, error = 'character_not_loaded' } end
        if bucket and not S.RateLimit(cid, bucket) then return { ok = false, error = 'rate_limited' } end
        local called, ok, data = pcall(fn, src, cid, a, b)
        if not called then
            print(('[cm-billing] %s failed: %s'):format(name, tostring(ok)))
            return { ok = false, error = 'internal_error' }
        end
        if ok then return { ok = true, data = data } end
        return { ok = false, error = tostring(data or 'failed') }
    end)
end

local function snapshot(src, cid)
    return {
        pending = S.ListInvoices(cid, 'pending'),
        history = S.ListInvoices(cid, 'history'),
        balances = { cash = S.Money.Balance(src, 'cash'), bank = S.Money.Balance(src, 'bank') },
    }
end

register('list', 'list', function(src, cid)
    if not S.SchemaReady then return false, 'unavailable' end
    return true, snapshot(src, cid)
end)

register('pay', 'pay', function(src, cid, data)
    data = type(data) == 'table' and data or {}
    local ok, result = S.PayInvoice(cid, src, tostring(data.reference or ''), data.account)
    if not ok then return false, result end
    local state = snapshot(src, cid)
    state.paid = result
    return true, state
end)

-- Background maintenance: expiry sweep and stuck-settlement reconciliation.
CreateThread(function()
    if not S.AwaitSchema() then return end
    pcall(S.ReconcileSettling)
    pcall(S.ReconcileRefunds)
    while true do
        Wait(Config.DefaultExpiryCheckSeconds * 1000)
        pcall(S.ExpireDue)
        pcall(S.ReconcileSettling)
        pcall(S.ReconcileRefunds)
    end
end)
