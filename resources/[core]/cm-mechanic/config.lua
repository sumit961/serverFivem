-- cm-mechanic configuration. Everything that decides WHAT a service is, WHO may sell it and WHAT it costs lives here
-- (server-side, never client-supplied). Prices are formulas over authoritative vehicle state; see docs/README.md.
CMMechanic = CMMechanic or {}
local C = {}
CMMechanic.Config = C

C.Debug = false

-- Platform identifiers (reuse, never re-implemented here).
C.BusinessType = 'mechanic'          -- cm-commercial-ownership business type (registry entry + cm_mechanic_shops table)
C.ContractType = 'mechanic_request'  -- cm-contracts type (already shipped by the broker)
C.ProviderType = 'mechanic'          -- cm-contracts provider family
C.PhoneService = 'mechanic'          -- cm-phone catalog id

-- Business permissions (enforced HERE through cm-commercial-ownership:HasBusinessPermission; never rank names).
C.Permissions = {
    accept = 'mechanic.accept_requests',
    quote = 'mechanic.create_quote',
    service = 'mechanic.service_vehicle',
    complete = 'mechanic.complete_work',
    manage = 'mechanic.manage_services',
}

-- Predefined mechanic businesses (no player purchase flow yet: an owner is assigned by an admin with
-- `cm_mechanic_setowner <shopId> <characterId>`). Ownership, employees, ranks and the balance are cm-commercial-ownership's.
-- location = { x, y, z, radius } of the workshop bay area. NO workshop MLO exists in this repository yet, so it is nil:
-- roadside services work, workshop-only services stay unavailable until a location is configured.
-- WORKSHOP LOCATION CONFIG REQUIRED.
C.Shops = {
    { id = 'main', label = 'Los Santos Mechanic', location = nil, roadside = true },
}

C.Policy = {
    allowOrganizationVehicles = false,   -- police/EMS/gang/fleet vehicles are never serviced by a player business
    allowAdminVehicles = false,          -- temporary admin vehicles have no persistent row
    allowStoredVehicles = false,         -- a vehicle parked in a garage/impound is not physically here
    selfService = false,                 -- a mechanic may not accept their own request
}

C.Proximity = {
    mechanicToVehicle = 8.0,
    customerToVehicle = 30.0,            -- roadside: the requester must be near their car
    mechanicToCustomer = 60.0,
    workshopBay = 40.0,                  -- default radius when a shop location omits one
}

C.Request = {
    hints = { diagnostic = 'Diagnostic', repair = 'Repair', body = 'Body work', tires = 'Tyres', tuning = 'Tuning' },
    maxNote = 120,
    fallbackAfterSeconds = 480,          -- broker clamps to the mechanic_request window (5-15 min). Expiry CANCELS: it never repairs.
    publishRetrySeconds = 120,           -- an unpublished request is retried by the sweep for this long, then expires
    customerOfflineSeconds = 180,        -- an open request whose customer left is cancelled after this
    statusLingerSeconds = 300,           -- a finished request stays visible on the phone this long
    approxRoundMetres = 100,             -- location published to the board is rounded to this grid
}

C.Quote = {
    validSeconds = 300,                  -- the customer must answer within this
    invoiceExpirySeconds = 600,          -- cm-billing invoice lifetime (an expired invoice returns the order to diagnosing)
    maxDeclines = 3,                     -- the order is cancelled after this many declined quotes
    staleOrderSeconds = 1800,            -- an assigned order with no progress for this long is released
    mechanicOfflineSeconds = 180,
}

-- Pay-before-mutate: the vehicle is changed only after cm-billing reports the invoice paid, then exactly once.
C.Commit = {
    autoCommitAfterSeconds = 300,        -- paid but the mechanic never finished: the server applies the service itself
    maxAttempts = 8,
    retryBaseSeconds = 20,
    durationToleranceSeconds = 1,
}

-- Absolute price bounds for REPAIR services (the invoice limit itself is cm-billing's `cm-mechanic` provider policy).
C.Pricing = {
    fallbackVehicleValue = 300000,       -- when cm_vehicle_catalog has no price for the model
    valueCap = 20000000,
    minMissingHealth = 30,               -- a part within this many points of full is "not needed"
    parts = {
        engine = { base = 1200, perPoint = 6.0, valuePct = 0.004 },
        tank = { base = 400, perPoint = 1.5, valuePct = 0.0005 },
        body = { base = 900, perPoint = 4.0, valuePct = 0.003 },
        cosmetic = { perItem = 250, maxItems = 16 },   -- broken windows + damaged/broken doors
        tyres = { perItem = 350, maxItems = 8 },
    },
}

-- Service catalogue. mode: 'roadside' | 'workshop' | 'both'. access: 'use' (owner or key/family holder) | 'owner'.
-- parts: which authoritative condition parts the service restores (empty = inspection only).
-- tuning/modification stays owned by cm-tuning: its entry carries `authority` and is never priced or applied from here.
C.Services = {
    diagnostic = { label = 'Vehicle diagnostic', category = 'DIAGNOSTIC', mode = 'both', access = 'use',
        parts = {}, base = 1500, minPrice = 1500, maxPrice = 1500, durationSeconds = 8, permission = 'service' },
    repair_basic = { label = 'Engine and fuel system repair', category = 'BASIC_REPAIR', mode = 'both', access = 'use',
        parts = { 'engine', 'tank' }, base = 1500, minPrice = 2000, maxPrice = 45000, durationSeconds = 20, permission = 'service' },
    repair_body = { label = 'Body and glass repair', category = 'BODY_REPAIR', mode = 'both', access = 'use',
        parts = { 'body', 'cosmetic' }, base = 1000, minPrice = 1500, maxPrice = 40000, durationSeconds = 20, permission = 'service' },
    tire_service = { label = 'Tyre service', category = 'TIRE_SERVICE', mode = 'roadside', access = 'use',
        parts = { 'tyres' }, base = 300, minPrice = 500, maxPrice = 6000, durationSeconds = 12, permission = 'service' },
    repair_full = { label = 'Full workshop repair', category = 'BASIC_REPAIR', mode = 'workshop', access = 'use',
        parts = { 'engine', 'tank', 'body', 'cosmetic', 'tyres' }, base = 2500, minPrice = 4000, maxPrice = 49000, durationSeconds = 30, permission = 'service' },
    -- Mechanic-mediated tuning: cm-tuning prices and applies it (authority), this resource runs the same work order / approval / invoice.
    -- mode 'both' = roadside or workshop like the repairs; set 'workshop' to require a configured bay. access 'owner': only the owner commissions it.
    tuning_request = { label = 'Vehicle tuning', category = 'TUNING', mode = 'both', access = 'owner', authority = 'cm-tuning',
        parts = {}, base = 0, minPrice = 0, maxPrice = 0, durationSeconds = 20, permission = 'service' },
}

-- Which catalogue services a customer's phone category suggests (display/ordering only; the mechanic still picks, the server prices).
C.HintServices = {
    diagnostic = { 'diagnostic' },
    repair = { 'repair_basic', 'repair_full', 'diagnostic' },
    body = { 'repair_body', 'repair_full' },
    tires = { 'tire_service', 'repair_full' },
    tuning = { 'tuning_request' },
}

C.RateLimits = {            -- { max, windowSeconds } per character
    request = { 4, 60 },
    cancel = { 6, 30 },
    board = { 10, 10 },
    claim = { 8, 30 },
    diagnose = { 10, 30 },
    quote = { 10, 30 },
    respond = { 8, 30 },
    service = { 10, 30 },
    tuning = { 6, 30 },
}

-- Mechanic-mediated tuning. The invoice limit is NOT configured here: it is cm-billing's provider policy for 'cm-mechanic'
-- (Config.Providers['cm-mechanic'].maxAmount, read through GetProviderPolicy). A tuning quote above it is REFUSED (never clamped,
-- repriced or auto-split).
C.Tuning = {
    shops = { chip = true, workshop = true, livery = true },   -- cm-tuning categories: performance / body & paint / livery (harness stays self-service)
}

C.SweepSeconds = 5
C.AdminCallers = { ['cm-admin'] = true }
C.SelfTest = { convar = 'cm_environment', value = 'development' }
