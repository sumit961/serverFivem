CMBilling = CMBilling or {}

CMBilling.Config = {
    Debug = false,
    OpenCommand = 'bills', -- no default key: every common key is already bound by another CM resource

    -- Platform emergency ceiling: effective creation limit = min(provider.maxAmount, HardMaxAmount). 5,000,000 is 2.5x the highest provider
    -- limit (cm-mechanic, 2,000,000), far below every numeric bound (invoice amount BIGINT UNSIGNED, business balance BIGINT with a
    -- 2,000,000,000 application cap, character cash/bank INT 2,147,483,647) and exact in a Lua double (< 2^53).
    -- Limits apply to NEW invoices only; an issued invoice stays payable/refundable if a limit is later lowered.
    HardMaxAmount = 5000000,
    DefaultExpiryCheckSeconds = 60,
    HistoryPage = 50,
    SettlingStaleSeconds = 90, -- a claimed payment older than this is reconciled on the next sweep/start

    -- Money accounts a recipient may pay from (cm-playerdata owns both).
    PayAccounts = { cash = true, bank = true },

    RateLimits = {
        list = { minMs = 300 },
        pay = { minMs = 1500 },
    },

    -- Destination types. An invoice moves EXISTING money: recipient -> destination. Billing never mints.
    --   city:      payment is removed from circulation (sink).
    --   character: credited with cm-playerdata:AddMoneyToCharacter (offline-safe). Only for providers that allow it.
    --   family:    credited with cm-family:CreditFamilyTreasuryAtomic (existing authoritative treasury API).
    --   business:  credited with cm-commercial-ownership:CreditBusinessAtomic (id = '<businessType>:<businessId>', owned
    --              businesses only; idempotent per invoice reference through the business ledger).
    --   organization: NO authoritative credit contract exists yet; rejected at creation (never stored unpayable).
    --   refundable: whether a PAID invoice to this destination may be refunded (the destination balance is debited, then the payer
    --   credited). city is NOT refundable: it is a money sink with no treasury, so a refund would mint cash.
    Destinations = {
        city = { available = true, refundable = false },
        character = { available = true, refundable = true },
        family = { available = true, resource = 'cm-family', refundable = true },
        business = { available = true, resource = 'cm-commercial-ownership', refundable = true },
        organization = { available = false, refundable = false },
    },

    -- Refund foundation (server/refund.lua). Reasons are a closed set; a reason is a label, never an authorisation.
    Refund = {
        Reasons = { service_failed = true, service_cancelled = true, duplicate_charge = true, provider_reversal = true, admin_reconcile = true },
        StaleSeconds = 90,          -- an in-flight refund older than this is driven forward by the sweep
        RetrySeconds = 120,         -- needs_reconciliation (e.g. destination short of funds) is retried at most this often
        SweepLimit = 25,
        -- Resources allowed to call the AdminXxx refund exports (cm-admin must be the gate). Console commands are always allowed.
        AdminResources = { ['cm-admin'] = true },
    },

    -- Trusted callers, resolved with GetInvokingResource(). Anything not listed is rejected (fail closed).
    -- Per provider: maxAmount (creation limit, deliberately per provider), issuerTypes, destinations, destinationIdPrefixes (optional: required
-- destination id prefix per destination type), allowOffline, metadataNamespace, canVoid, canRefund (default false).
    -- Examples for future owners are present but DISABLED; enable one only when that resource integrates.
    Providers = {
        ['cm-law'] = {
            enabled = false, maxAmount = 250000, issuerTypes = { system = true, organization = true },
            destinations = { city = true }, allowOffline = true, metadataNamespace = 'law', canVoid = true,
        },
        ['cm-ems'] = {
            enabled = false, maxAmount = 150000, issuerTypes = { system = true, organization = true },
            destinations = { city = true, family = true }, allowOffline = true, metadataNamespace = 'ems', canVoid = true,
        },
        -- Business invoices: ONLY the business platform issues them, after validating `business.create_invoice`
        -- and customer presence server-side (cm-commercial-ownership CreateBusinessInvoice). No NUI path reaches this.
        ['cm-commercial-ownership'] = {
            enabled = true, maxAmount = 50000, issuerTypes = { business = true },
            destinations = { business = true }, allowOffline = true, metadataNamespace = 'business', canVoid = true, canRefund = true,
        },
        -- Mechanic service invoices: issued ONLY after the customer approved a server-calculated quote for a work order whose
        -- mechanic holds the business permission. Business destination only, and only 'mechanic:<shop>' businesses.
        -- 2,000,000 covers the largest legitimate cm-tuning bundle (see cm-tuning/docs/SERVICE_INTEGRATION.md: performance bundle 242,000;
        -- a single wheel at the 200-index ceiling 1,105,500). The price stays owned by cm-tuning / cm-mechanic; this is only the authority limit.
        ['cm-mechanic'] = {
            enabled = true, maxAmount = 2000000, issuerTypes = { business = true },
            destinations = { business = true }, destinationIdPrefixes = { business = 'mechanic:' }, allowOffline = false, metadataNamespace = 'mechanic', canVoid = true, canRefund = true,
        },
        ['cm-doctor'] = {
            enabled = false, maxAmount = 100000, issuerTypes = { system = true },
            destinations = { city = true }, allowOffline = true, metadataNamespace = 'doctor', canVoid = true,
        },
    },

    -- Used only by the development self-test (console command `cm_billing_selftest`, cm_environment=development).
    SelfTest = { convar = 'cm_environment', value = 'development' },

    -- Notifications are best effort and never affect invoice state.
    Notify = {
        phone = true, -- cm-phone SendSystemMessage / CreateNotification (cm-billing must be in cm-phone's TrustedResources)
        hud = true,
    },
}
