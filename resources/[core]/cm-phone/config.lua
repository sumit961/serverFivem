CMPhone = CMPhone or {}

CMPhone.Config = {
    Debug = false,

    -- Open key (RegisterKeyMapping default; players can rebind in Settings > Key Bindings).
    -- F1 is unused by the other CM resources (G, F6, F7, F9, J, M, I, T, ... are taken).
    OpenKey = 'F1',
    OpenCommand = 'phone',

    -- Phone number format "AAA-BBBB". Server-generated only; never client-selected.
    Number = {
        prefixes = { '310', '323', '424', '818', '213' },
        generationAttempts = 30,
    },

    Contacts = {
        max = 150,
        nameMax = 32,
    },

    Messages = {
        textMax = 500,
        historyPage = 50,
        conversationListMax = 60,
        groupMembersMax = 8,
        groupNameMax = 32,
        locationLabelMax = 40,
        retentionDays = 0, -- 0 = keep forever
    },

    Calls = {
        ringTimeoutMs = 30000,
        historyMax = 30,
        historyRetentionDays = 30,
        maxDurationSeconds = 3600,
    },

    -- Per-character server rate limits (minIntervalMs, then burst = count per windowMs).
    RateLimits = {
        sms        = { minMs = 700,   burst = 8, windowMs = 10000 },
        call       = { minMs = 3000,  burst = 5, windowMs = 60000 },
        contact    = { minMs = 600,   burst = 10, windowMs = 30000 },
        block      = { minMs = 800,   burst = 8, windowMs = 30000 },
        group      = { minMs = 1500,  burst = 6, windowMs = 60000 },
        emergency  = { minMs = 30000, burst = 3, windowMs = 600000 },
        read       = { minMs = 150,   burst = 40, windowMs = 10000 },
        service       = { minMs = 2500, burst = 4, windowMs = 60000 },   -- creating a service request
        serviceCancel = { minMs = 1500, burst = 6, windowMs = 60000 },
    },

    -- Classifieds. Economy: a small daily-life service fee (CM_ECONOMY_STANDARD.md §3).
    -- 1,500 = ~2.4 minutes of baseline City Support income (37,500/h); a sink, not a progression wall.
    -- TEMPORARY value pending the economy rebalance; keep configurable.
    Adverts = {
        fee = 1500,
        account = 'either',   -- 'cash' | 'bank' | 'either' (cash first, then bank)
        cooldownSeconds = 300,
        textMin = 5,
        textMax = 240,
        feedSize = 40,
        expireHours = 48,
    },

    Emergency = {
        detailsMax = 200,
        -- Owner contracts (cm-ems:CreateAmbulanceCall, cm-law:CreateLawCall) are called, never re-implemented here.
    },

    -- Trusted resources allowed to push system messages / notifications (GetInvokingResource allowlist).
    TrustedResources = {
        ['cm-phone'] = true,
        ['cm-billing'] = true,
        ['cm-admin'] = true,
        ['cm-taxi'] = true,
        ['cm-store'] = true,
        ['cm-bank'] = true,
        ['cm-law'] = true,
        ['cm-ems'] = true,
        ['cm-vehicles'] = true,
        ['cm-house'] = true,
        ['cm-payday'] = true,
    },

    -- Voice: no phone-call voice backend (pma-voice/mumble/saltychat) is installed in this repo.
    -- Call STATE is authoritative here; audio routing is a documented future integration.
    Voice = {
        provider = 'none',
        stateEvent = 'cm-phone:server:callStateChanged', -- local (non-network) server event for a future voice bridge
    },

    -- Phone-in-hand animation/prop (cosmetic; cleaned up on every close path).
    Prop = {
        enabled = true,
        model = 'prop_npc_phone_02',
        bone = 28422,
        offset = vector3(0.0, 0.0, 0.0),
        rotation = vector3(0.0, 0.0, 0.0),
    },

    -- Service Marketplace (Services app). The phone is a FRONTEND: it keeps no requests, no history and no job state.
    --   PHONE -> service adapter -> SOURCE OWNER (authoritative request) -> cm-contracts -> PROVIDER (job)
    -- Catalog = trusted display/validation definitions (never client- or resource-supplied). A service becomes
    -- AVAILABLE only when its owner resource is started AND has registered an adapter (RegisterPhoneService).
    -- Sources = which resource may register an adapter for which service id (GetInvokingResource allowlist).
    -- The phone generates $0, 0 items and 0 XP and adds no service fee: payment belongs to the owner.
    Services = {
        Enabled = true,
        HideOffline = false,       -- true: hide services whose owner is not running instead of showing them as Unavailable
        WorldLimit = 8000.0,       -- |x|,|y| bound for client waypoints
        Sources = {
            ['cm-taxi'] = { taxi = true },
            ['cm-courier'] = { courier = true },
            ['cm-mechanic'] = { mechanic = true },
        },
        Catalog = {
            taxi = {
                order = 1, name = 'Taxi', icon = 'taxi', category = 'Transport',
                description = 'Request a taxi to your current location.',
                activePolicy = 'single',   -- 'single' = one open request per character; 'multi' = the owner decides
                fields = {
                    { key = 'destination', label = 'Destination', type = 'waypoint', required = false, hint = 'Optional. Set a map waypoint first.' },
                    { key = 'details', label = 'Note for the driver', type = 'text', max = 120, required = false },
                },
            },
            mechanic = {
                order = 2, name = 'Mechanic', icon = 'wrench', category = 'Vehicle',
                description = 'Roadside repair and vehicle service.',
                activePolicy = 'single',   -- owner: cm-mechanic (adapter registered on start; shows Unavailable until it is running)
                fields = {
                    { key = 'service', label = 'Service', type = 'enum', options = { 'diagnostic', 'repair', 'body', 'tires', 'tuning' }, required = true },
                    { key = 'details', label = 'What is wrong?', type = 'text', max = 120, required = false },
                },
            },
            courier = {
                order = 3, name = 'Courier', icon = 'box', category = 'Delivery',
                description = 'Send a parcel across the city.',
                activePolicy = 'multi',
                fields = {
                    { key = 'details', label = 'What needs delivering?', type = 'text', max = 120, required = true },
                    { key = 'destination', label = 'Delivery point', type = 'waypoint', required = true, hint = 'Set a map waypoint first.' },
                    { key = 'size', label = 'Parcel size', type = 'enum', options = { 'small', 'medium', 'large' }, required = false },
                },
            },
        },
    },

    -- Development self-test (server console command `cm_phone_selftest`). Requires cm_environment=development.
    SelfTest = {
        convar = 'cm_environment',
        value = 'development',
    },
}
