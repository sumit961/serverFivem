-- cm-contracts configuration. Contract types, trusted sources and trusted providers are
-- configuration: adding a contract type or job never requires editing server/core.lua.
CMContracts = CMContracts or {}
local C = {}
CMContracts.Config = C

-- Trusted SOURCES (GetInvokingResource allowlist). A source may only publish the types
-- listed. The broker calls back the named exports; each must check
-- GetInvokingResource() == 'cm-contracts' and be idempotent:
--   completeExport(ctx)  player completion  -> true[, { replayed }] | false, reason ('source_terminal' = order is over)
--   fallbackExport(ctx)  deadline fallback  -> true[, { replayed }] | false, reason ('source_terminal' | retryable reason)
--   cancelExport(ctx)    admin cancel       -> true | false, reason  (the source decides whether it permits it)
--   eventExport(ctx)     optional best-effort notices ('claimed' | 'active' | 'released')
C.Sources = {
    ['cm-commercial-ownership'] = {
        types = { business_supply = true, bulk_material_transport = true },
        completeExport = 'ContractSourceComplete',
        fallbackExport = 'ContractSourceFallback',
        cancelExport = 'ContractSourceCancel',
        eventExport = 'ContractSourceEvent',
    },
    -- Mechanic requests: the request owner is also the mechanic work provider. Fallback = cancel/expire, NEVER an automatic repair.
    ['cm-mechanic'] = {
        types = { mechanic_request = true },
        completeExport = 'ContractSourceComplete',
        fallbackExport = 'ContractSourceFallback',
        cancelExport = 'ContractSourceCancel',
        eventExport = 'ContractSourceEvent',
    },
}

-- Trusted PROVIDER resources and the provider types each may register (RegisterProvider).
-- Provider resources are allowlisted here; they are not self-declared by clients.
C.Providers = {
    ['cm-trucking'] = { providerTypes = { trucking = true } },
    ['cm-courier'] = { providerTypes = { courier = true } },
    ['cm-garbage'] = { providerTypes = { garbage = true } },
    ['cm-recycling'] = { providerTypes = { recycling = true } },
    ['cm-mechanic'] = { providerTypes = { mechanic = true } },
}

-- Contract types. providerType = which job family may work it.
--   fallbackMinutes (+Min/Max): player-first window before the SOURCE completes it automatically.
--   leaseSeconds: a claimed-but-not-started contract returns to the board after this.
--   activeTimeoutMinutes / onActiveExpire: an active contract whose worker vanished 'release's (or goes to 'fallback').
--   deferFallbackWhileWorked: a live worker gets deferSeconds extra, up to maxDeferrals times, before fallback fires.
--   maxFailures: provider-reported failures before the contract goes to fallback.
local function t(providerType, fb, fbMin, fbMax, extra)
    local x = { providerType = providerType, fallbackMinutes = fb, fallbackMinMinutes = fbMin, fallbackMaxMinutes = fbMax,
        leaseSeconds = 900, activeTimeoutMinutes = 240, onActiveExpire = 'release', maxClaimsPerCharacter = 1,
        maxFailures = 3, deferFallbackWhileWorked = true, deferSeconds = 600, maxDeferrals = 2 }
    for k, v in pairs(extra or {}) do x[k] = v end
    return x
end
C.Types = {
    business_supply         = t('trucking', 30, 20, 45),
    bulk_material_transport = t('trucking', 60, 40, 120, { activeTimeoutMinutes = 360 }),
    courier_delivery        = t('courier', 15, 10, 25, { leaseSeconds = 600, activeTimeoutMinutes = 120 }),
    commercial_waste        = t('garbage', 30, 20, 60),
    recycling_pickup        = t('recycling', 30, 20, 60),
    mechanic_request        = t('mechanic', 8, 5, 15, { leaseSeconds = 300, activeTimeoutMinutes = 60, maxDeferrals = 1 }),
    construction_work       = t('construction', 60, 30, 180),
    warehouse_task          = t('warehouse', 30, 15, 90),
}

C.Fallback = { retryBase = 60, retryCap = 1800, batch = 20 }  -- failed source fallbacks back off 60s, 120s ... 30 min, never spam
C.CompletingTimeoutSeconds = 120   -- a 'completing' contract older than this (crash) is replayed against the (idempotent) source
C.SweepSeconds = 30
C.AdminCallers = { ['cm-admin'] = true }
C.SelfTest = { convar = 'cm_environment', value = 'development' }
