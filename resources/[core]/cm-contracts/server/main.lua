-- cm-contracts: FiveM wiring for server/core.lua. No client events are exposed: contracts are
-- created only by allowlisted SOURCE resources and advanced only by allowlisted PROVIDER
-- resources (GetInvokingResource). Workers interact through their job resource, never with the
-- broker directly, so there is nothing for a hostile client to call.
--
-- This resource creates no money, items, stock or XP and never touches another resource's tables.
local Config = CMContracts.Config
local Core, Store = CMContracts.Core, CMContracts.Store
local RESOURCE = GetCurrentResourceName()

-- Cross-resource call: pcall'd, fails closed if the resource is not started.
local function call(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then return false, 'resource_unavailable' end
    local args = table.pack(...)
    local res = table.pack(pcall(function() return exports[resource][name](exports[resource], table.unpack(args, 1, args.n)) end))
    if not res[1] then return false, 'call_failed' end
    return true, res[2], res[3]
end

local broker = Core.New({
    cfg = Config, store = Store, now = os.time, call = call,
    encode = function(t) local ok, s = pcall(json.encode, t); return ok and s or string.rep('x', 4096) end,
    rand = math.random,
})
CMContracts.Broker = broker
local ready = false

local function guard(fn)
    return function(...)
        if not ready then return false, 'broker_not_ready' end
        return fn(GetInvokingResource() or RESOURCE, ...)
    end
end

-- ---- providers -------------------------------------------------------------------
exports('RegisterProvider', guard(function(inv, providerType, def) return broker:RegisterProvider(inv, providerType, def) end))
exports('ListAvailableContracts', guard(function(inv, providerType, filters, cid) return broker:ListAvailable(inv, providerType, filters, cid) end))
exports('GetWorkerContracts', guard(function(inv, providerType, cid) return broker:GetClaim(inv, providerType, cid) end))
exports('ClaimContract', guard(function(inv, ref, cid, opts) return broker:Claim(inv, ref, cid, opts) end))
exports('ReleaseContract', guard(function(inv, ref, cid, reason) return broker:Release(inv, ref, cid, reason) end))
exports('MarkContractActive', guard(function(inv, ref, cid, opts) return broker:MarkActive(inv, ref, cid, opts) end))
exports('FailContract', guard(function(inv, ref, cid, reason) return broker:Fail(inv, ref, cid, reason) end))
exports('CompleteContract', guard(function(inv, ref, cid, opts) return broker:Complete(inv, ref, cid, opts) end))
exports('ReportWorkerDisconnected', guard(function(inv, providerType, cid) return broker:ReportWorkerDisconnected(inv, providerType, cid) end))

-- ---- sources ---------------------------------------------------------------------
exports('CreateContract', guard(function(inv, data) return broker:CreateContract(inv, data) end))
exports('CancelContract', guard(function(inv, ctype, sourceRef, reason) return broker:Cancel(inv, ctype, sourceRef, reason) end))
exports('GetSourceContract', guard(function(inv, ctype, sourceRef) return broker:GetSourceContract(inv, ctype, sourceRef) end))

-- ---- admin / recovery (caller must be cm-admin; console commands below for operators) ----
local function admin(fn)
    return function(...)
        if not ready then return false, 'broker_not_ready' end
        if not Config.AdminCallers[GetInvokingResource() or ''] then return false, 'forbidden' end
        return fn(...)
    end
end
exports('AdminInspectContract', admin(function(ref) return broker:AdminInspect(ref) end))
exports('AdminListContracts', admin(function(filter) return broker:AdminList(filter) end))
exports('AdminReleaseContract', admin(function(ref, reason) return broker:AdminRelease(ref, reason) end))
exports('AdminCancelContract', admin(function(ref, reason) return broker:AdminCancel(ref, reason) end))
exports('AdminReconcileContracts', admin(function() return true, broker:Sweep() end))

-- ---- sweep / recovery ------------------------------------------------------------
local sweeping = false
local function sweep()
    if sweeping or not ready then return end
    sweeping = true
    local ok, err = pcall(function() return broker:Sweep() end)
    sweeping = false
    if not ok then print(('[cm-contracts] sweep error: %s'):format(tostring(err))) end
end

CreateThread(function()
    local ok, err = pcall(Store.EnsureSchema)
    if not ok then print(('[cm-contracts] ^1schema error: %s^7'):format(tostring(err))); return end
    ready = true
    Wait(1000)
    sweep() -- restart recovery: expired claims release, due fallbacks run, completed stays terminal
    -- Providers keep their registration in memory: ask them to register again.
    TriggerEvent('cm-contracts:server:providerRegistryReady')
    while true do
        Wait(math.max(10, tonumber(Config.SweepSeconds) or 30) * 1000)
        sweep()
    end
end)

-- ---- operator console (server console only: source 0) ------------------------------
local function consoleOnly(name, fn)
    RegisterCommand(name, function(src, args)
        if src ~= 0 then return end
        local ok, a, b = pcall(fn, args)
        print(('[cm-contracts] %s -> %s'):format(name, ok and (json.encode({ a, b }) or '') or tostring(a)))
    end, true)
end
consoleOnly('cm_contracts_inspect', function(a) return broker:AdminInspect(a[1]) end)
consoleOnly('cm_contracts_list', function(a) return broker:AdminList({ status = a[1], providerType = a[2] }) end)
consoleOnly('cm_contracts_release', function(a) return broker:AdminRelease(a[1], 'console') end)
consoleOnly('cm_contracts_cancel', function(a) return broker:AdminCancel(a[1], 'console') end)
consoleOnly('cm_contracts_reconcile', function() return true, broker:Sweep() end)
