-- cm-commercial-ownership/config.lua
-- Shared business employment / rank / permission / payroll foundation.
-- Ownership and business_balance remain in each business's OWN table; the
-- registry below only tells the foundation where to read them.
Config = {}

-- Canonical business identity = business_type + business_id (string).
-- Table/column names are developer-controlled constants (never client input).
Config.BusinessTypes = {
    store      = { label = 'Store',          table = 'cm_stores',         idColumn = 'store_id',   ownerColumn = 'owner_character_id', balanceColumn = 'business_balance', nameColumn = 'owner_name', stockColumn = 'stock' },
    gasstation = { label = 'Gas Station',    table = 'cm_gas_stations',   idColumn = 'station_id', ownerColumn = 'owner_character_id', balanceColumn = 'business_balance', nameColumn = 'owner_name', stockColumn = 'stock' },
    clothing   = { label = 'Clothing Store', table = 'cm_clothing_stores', idColumn = 'shop_id',    ownerColumn = 'owner_character_id', balanceColumn = 'business_balance', nameColumn = 'owner_name', stockColumn = 'stock' },
    barber     = { label = 'Hair Salon',     table = 'cm_barber_shops',   idColumn = 'shop_id',    ownerColumn = 'owner_character_id', balanceColumn = 'business_balance', nameColumn = 'owner_name' },
    -- cm-mechanic owns the table (cm_mechanic_shops, same owner/balance columns as the others); ownership is admin-assigned for now.
    mechanic   = { label = 'Mechanic Shop',  table = 'cm_mechanic_shops', idColumn = 'shop_id',    ownerColumn = 'owner_character_id', balanceColumn = 'business_balance', nameColumn = 'owner_name' },
    parking    = { label = 'Parking Lot',    table = 'cm_parking_lots',   idColumn = 'parking_id', ownerColumn = 'owner_character_id', balanceColumn = 'business_balance', nameColumn = 'owner_name' },
}

-- Permission identifiers. `implemented` = enforced by this resource today;
-- the rest are future-safe names consumer resources may check through
-- HasBusinessPermission().
Config.Permissions = {
    { id = 'business.view_employees',     label = 'View employees',      implemented = true },
    { id = 'business.invite',             label = 'Invite employees',    implemented = true },
    { id = 'business.manage_employees',   label = 'Fire / change rank',  implemented = true },
    { id = 'business.manage_ranks',       label = 'Create/edit ranks',   implemented = true },
    { id = 'business.manage_permissions', label = 'Edit rank permissions', implemented = true },
    { id = 'business.view_activity',      label = 'View activity',       implemented = true },
    { id = 'business.view_finance',       label = 'View finance',        implemented = true },
    { id = 'business.pay_employees',      label = 'Pay employees',       implemented = true },
    { id = 'business.manage_payroll',     label = 'Set rank pay',        implemented = true },
    { id = 'business.create_invoice',     label = 'Create invoices',     implemented = true },
    { id = 'business.deposit',            label = 'Deposit funds',       implemented = false },
    { id = 'business.withdraw',           label = 'Withdraw funds',      implemented = false },
    { id = 'business.manage_stock',       label = 'Manage stock',        implemented = false },
    { id = 'business.manage_prices',      label = 'Manage prices',       implemented = false },
    { id = 'business.manage_orders',      label = 'Manage orders',       implemented = false },
    -- Mechanic businesses only (enforced by cm-mechanic through HasBusinessPermission).
    { id = 'mechanic.accept_requests',    label = 'Accept service requests', implemented = false, types = { mechanic = true } },
    { id = 'mechanic.create_quote',       label = 'Diagnose and quote',      implemented = false, types = { mechanic = true } },
    { id = 'mechanic.service_vehicle',    label = 'Service vehicles',        implemented = false, types = { mechanic = true } },
    { id = 'mechanic.complete_work',      label = 'Complete work orders',    implemented = false, types = { mechanic = true } },
    { id = 'mechanic.manage_services',    label = 'Manage service settings', implemented = false, types = { mechanic = true } },
}

-- Seeded ONLY when a business has no ranks. The database is authoritative afterwards.
-- The owner is virtual (never a row): tier OwnerTier, every permission.
Config.OwnerTier = 100
Config.MaxRankTier = 90
Config.MaxRanksPerBusiness = 8
Config.MaxEmployeesPerBusiness = 40
Config.DefaultRanks = {
    { name = 'Manager',  tier = 80, entry = false, permissions = {
        'business.view_employees', 'business.invite', 'business.manage_employees', 'business.view_activity',
        'business.view_finance', 'business.pay_employees', 'business.create_invoice',
        'business.manage_stock', 'business.manage_prices', 'business.manage_orders' } },
    { name = 'Employee', tier = 40, entry = true,  permissions = { 'business.create_invoice', 'business.manage_stock' } },
    { name = 'Trainee',  tier = 10, entry = false, permissions = {} },
}

-- Per-type override of DefaultRanks (seeded only when a business has no ranks).
Config.TypeDefaultRanks = {
    mechanic = {
        { name = 'Manager',  tier = 80, entry = false, permissions = {
            'business.view_employees', 'business.invite', 'business.manage_employees', 'business.view_activity',
            'business.view_finance', 'business.pay_employees',
            'mechanic.accept_requests', 'mechanic.create_quote', 'mechanic.service_vehicle', 'mechanic.complete_work', 'mechanic.manage_services' } },
        { name = 'Mechanic', tier = 40, entry = true,  permissions = {
            'mechanic.accept_requests', 'mechanic.create_quote', 'mechanic.service_vehicle', 'mechanic.complete_work' } },
        { name = 'Trainee',  tier = 10, entry = false, permissions = { 'mechanic.accept_requests' } },
    },
}

Config.Invites = { ExpirySeconds = 60, MaxDistance = 5.0, MaxPendingPerBusiness = 5 }

-- Bounded manual payroll: paid from BUSINESS funds, never minted.
Config.Payroll = {
    Enabled = true,
    MinPayment = 100,
    MaxPayment = 20000,           -- hard cap for any single rank pay amount
    EmployeeCooldownSeconds = 600, -- per employee per business
    Account = 'bank',
}

-- Server resources allowed to move business money through the atomic exports.
Config.BalanceCallers = {
    credit = { ['cm-billing'] = true, ['cm-commercial-ownership'] = true },
    debit  = { ['cm-commercial-ownership'] = true, ['cm-billing'] = true }, -- cm-billing: invoice refunds (key billing-refund-debit:*)
}

-- Resources allowed to call the Admin* recovery exports (cm-admin must be the gate).
Config.AdminCallers = { ['cm-admin'] = true, ['cm-commercial-ownership'] = true }

-- Per-actor rate limits: { max, windowSeconds }
Config.RateLimits = {
    invite   = { 5, 60 },
    mutate   = { 12, 30 },
    rank     = { 10, 30 },
    payroll  = { 6, 30 },
    invoice  = { 6, 30 },
    supply   = { 6, 30 },
    quote    = { 20, 30 },
    open     = { 10, 10 },
}

-- Business invoices issued through cm-billing (provider entry lives in cm-billing config).
Config.Invoices = { Enabled = true, MaxAmount = 50000, MaxDistance = 6.0 }

-- ============================================================
-- Supply / orders (generic platform; physical delivery is owned by trusted providers such as a future trucking resource)
-- ============================================================
-- Wholesale unit cost = max(floor, ceil(retail * percent)), resolved per item > category > business-type default.
-- RETAIL always comes from the authoritative owner (cm-store catalog, clothing_catalog, fuel base price), never from a client.
-- Evidence for the defaults (owner keeps ownerRevenuePercent = 80 of the price actually paid):
--   store/clothing price tiers are LOW 0.85 / NORMAL 1.00 / HIGH 1.25 -> owner gross at LOW = 68% of base retail, so
--   percent 0.60 keeps a positive margin at every tier (8% / 20% / 40% of base retail).
--   gas tiers are LOW 6 / NORMAL 8 / HIGH 11 per % -> owner gross at LOW = 4.8, so wholesale must stay below that:
--   percent 0.50 (= the existing flat 4 per unit) leaves 0.8 / 2.4 / 4.8 per unit.
-- Only business types listed here support supply. Barber and parking are SERVICE ONLY (no orderable goods).
-- capacity must match the owner resource's maxStock (cm-store 5000, cm-gasstations 25000, nv_cloth 15000).
Config.Supply = {
    Enabled = true,
    QuoteSeconds = 120,
    ClaimLeaseSeconds = 900,          -- a claimed (not yet in transit) order returns to the board after this
    InTransitTimeoutMinutes = 240,    -- an in-transit order that never completes is failed and refunded
    MaxOpenOrdersPerBusiness = 5,
    ScheduledDeliveryMinutes = 20,    -- used by fulfillment mode 'scheduled' only
    AllowAdminFulfill = false,        -- AdminDeliverSupplyOrder is also allowed whenever cm_environment=development
    -- External orders are PUBLISHED to the generic broker (cm-contracts), which owns provider claims, leases and the
    -- player-first window. After ExternalFallbackMinutes with no player delivery the broker asks THIS resource to deliver
    -- (ContractSourceFallback): stock is credited exactly once and nobody is paid. Providers are allowlisted in cm-contracts.
    ExternalFallbackMinutes = 30,     -- clamped by the broker to the contract type's window (business_supply 20-45)
    -- Safety net only: if the broker is not running, an unpublished external order is delivered by the supplier after this.
    BrokerDownFallbackMinutes = 90,
    PickupHint = 'City Wholesale Depot',
    Types = {
        store = {
            fulfillment = 'external', cargoClass = 'general', source = 'cm-store',
            capacity = 5000, maxLineQuantity = 500, maxOrderUnits = 1000,
            wholesale = { percent = 0.60, floor = 1,
                categories = { consumable = { floor = 2 }, tool = { percent = 0.60 }, misc = { percent = 0.60 } },
                items = {} },
        },
        gasstation = {
            fulfillment = 'external', cargoClass = 'fuel', source = 'config', unit = 'fuel %',
            capacity = 25000, maxLineQuantity = 5000, maxOrderUnits = 5000,
            lines = { { id = 'fuel', label = 'Fuel (per % unit)', category = 'fuel', retail = 8 } },
            wholesale = { percent = 0.50, floor = 1, categories = {}, items = {} },
        },
        clothing = {
            fulfillment = 'external', cargoClass = 'general', source = 'clothing_catalog',
            capacity = 15000, maxLineQuantity = 500, maxOrderUnits = 1000,
            wholesale = { percent = 0.60, floor = 5, categories = {}, items = {} },
        },
    },
}

-- ============================================================
-- Business materials (balance + demand + delivery settlement; server/materials.lua, docs/MATERIALS.md)
-- ============================================================
-- A business material BALANCE is a commodity counter per business+material (approved by the READ-ONLY cm-materials catalog and not DEFERRED).
-- It is NOT retail product stock (cm_stores.stock etc.) and NOT player inventory. There is no player-facing withdrawal. Callers are allowlisted
-- by GetInvokingResource(); no client event exists.
Config.Materials = {
    Enabled = true,
    MaxStockPerMaterial = 100000,
    MaxQuantityPerOperation = 10000,
    MaxDemandQuantity = 5000,
    MaxOpenDemandsPerBusiness = 5,
    MaxRequirementLines = 4,
    DeadlineMinutes = { min = 10, max = 10080 },
    DemandCategories = { business_need = true, production_input = true, project_supply = true },
    PickupHint = 'Material depot',
    ContractFallbackMinutes = 60,     -- clamped by the broker to bulk_material_transport (40-120). Fallback EXPIRES the demand; it never creates stock.
    PrepareTimeoutSeconds = 120,      -- a prepared delivery whose inventory debit is definitively NOT applied is cancelled after this
    ReconcileSeconds = 30,
    Callers = {
        demand   = { ['cm-commercial-ownership'] = true },                       -- who may create/cancel demands (no UI yet)
        delivery = { ['cm-trucking'] = true, ['cm-warehouse'] = true },          -- physical providers; they validate the task, this resource settles it
        credit   = { ['cm-commercial-ownership'] = true },                       -- standalone credit (future trusted production sources)
        consume  = { ['cm-commercial-ownership'] = true },                       -- cm-mechanic is added only once approved COMPONENT materials exist
    },
}

Config.ActivityPageSize = 40
Config.SelfTest = { convar = 'cm_environment', value = 'development' }
