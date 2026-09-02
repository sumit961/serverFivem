Config = {}

Config.AdminResource = 'cm-admin'
Config.PlayerDataResource = 'cm-playerdata'
Config.AdminPermission = 'orgs.manage'
Config.MenuCommand = 'laworg'
Config.MenuKey = 'F6' -- physical mapping is owned centrally by cm-core/client/organization-keys.lua
Config.FacilityInteractDistance = 2.5
-- Default key for the cuff/uncuff bind. cm-law and cm-police both ship 'X',
-- which gives players two entries on the same key in the keybind settings.
-- The shared cmCuffed statebag means the systems interoperate correctly
-- either way -- this only exists so one of them can be moved off X without
-- editing client code. Players can also rebind it themselves in Settings.
Config.CuffKey = 'X'
Config.FacilityDrawDistance = 18.0
Config.CinematicResponseDuration = 2200

-- Retention sweep (server/retention.lua). The dashboard only reads the newest
-- slice of cm_legal_activity_logs, so older rows are unreachable dead weight.
Config.LogRetentionDays = 90        -- delete cm_legal_activity_logs rows after this many days
Config.IncidentRetentionDays = 30   -- delete closed/expired dispatch calls after this many days
Config.RetentionSweepMs = 21600000  -- how often to sweep (6 hours)
Config.Capabilities = {
    'dispatch', 'mdt', 'arrest', 'search', 'citations', 'impound', 'radar',
    'spikes', 'barricades', 'clamp', 'k9', 'alpr', 'armory', 'fleet',
    'evidence', 'prisonIntake',
}
Config.FacilityTypes = {
    front_desk = { label = 'Front Desk', role = 'Public Services', icon = 'shield', public = true },
    wardrobe = { label = 'Wardrobe', role = 'Uniform Specialist', icon = 'shirt', allowOffDuty = true },
    armory = { label = 'Armory', role = 'Quartermaster', icon = 'gun' },
    storage = { label = 'Storage', role = 'Department Storekeeper', icon = 'box' },
    evidence = { label = 'Evidence Storage', role = 'Evidence Custodian', icon = 'fingerprint' },
    fleet = { label = 'Fleet', role = 'Fleet Coordinator', icon = 'car' },
    impound = { label = 'Impound Operator', role = 'Vehicle Impound', icon = 'truck-ramp-box', public = true },
    intake = { label = 'Prison Intake', role = 'Booking Officer', icon = 'building-lock' },
}

-- Tier-based permission ladder shared by every organization below, so rank
-- actually gates access instead of every non-leader rank getting the full
-- Config.DefaultPermissions set. Leader bypasses all of this in code
-- (member.isLeader checks throughout server/main.lua) -- command is given
-- the full ladder anyway so its stored permissions row is meaningful on
-- its own if isLeader is ever unset for that character.
local recruitPermissions = { 'law.view_members', 'law.chat', 'law.radio' }
local memberPermissions = {
    'law.view_members', 'law.chat', 'law.radio', 'law.receive_dispatch',
    'law.mdt', 'law.cuff', 'law.drag', 'law.search', 'law.vehicle',
    'law.spike', 'law.barricade', 'law.cite', 'law.impound', 'law.radar',
    'law.clamp',
    'law.logistics.request',
}
local supervisorPermissions = {
    'law.view_members', 'law.chat', 'law.radio', 'law.receive_dispatch',
    'law.mdt', 'law.cuff', 'law.drag', 'law.search', 'law.vehicle',
    'law.armory', 'law.storage', 'law.spike', 'law.barricade', 'law.cite',
    'law.impound', 'law.radar', 'law.clamp', 'law.alpr',
    'law.logistics.request', 'law.logistics.accept', 'law.logistics.prepare',
    'law.logistics.load', 'law.logistics.deliver', 'law.logistics.cancel', 'law.logistics.recover',
}
local commandPermissions = {
    'law.view_members', 'law.chat', 'law.radio', 'law.receive_dispatch',
    'law.mdt', 'law.cuff', 'law.drag', 'law.search', 'law.vehicle',
    'law.armory', 'law.storage', 'law.spike', 'law.barricade', 'law.fleet',
    'law.cite', 'law.manage_citations', 'law.impound', 'law.manage_impound',
    'law.radar', 'law.clamp', 'law.k9', 'law.alpr', 'law.manage_alpr', 'law.manage_members',
    'law.manage_ranks', 'law.manage_permissions', 'law.manage_armory',
    'law.logistics.request', 'law.logistics.accept', 'law.logistics.prepare',
    'law.logistics.load', 'law.logistics.deliver', 'law.logistics.cancel', 'law.logistics.recover',
}

-- LSPD remains owned by cm-police while its mature gameplay modules are
-- migrated. These organizations are owned here from the beginning and use
-- stable IDs everywhere; display names can change without breaking records.
Config.Organizations = {
    sahp = {
        label = 'San Andreas Highway Patrol',
        shortLabel = 'SAHP',
        type = 'law_enforcement',
        icon = 'road',
        color = '#d8b84b',
        jurisdiction = 'State highways and statewide traffic enforcement',
        chatChannel = 'sahp_nonrp', radioChannel = 'sahp_rp',
        fleetNamespace = 'sahp', armoryNamespace = 'sahp', wardrobeNamespace = 'sahp',
        serviceNpc = { name = 'Trooper Walker', role = 'SAHP Public Desk', model = 's_m_y_hwaycop_01' },
        ranks = {
            { tier = 100, name = 'Commissioner', leader = true, permissions = commandPermissions },
            { tier = 80, name = 'Assistant Commissioner', permissions = commandPermissions },
            { tier = 60, name = 'Captain', permissions = supervisorPermissions },
            { tier = 40, name = 'Sergeant', permissions = supervisorPermissions },
            { tier = 20, name = 'Trooper', permissions = memberPermissions },
            { tier = 1, name = 'Cadet', permissions = recruitPermissions },
        },
    },
    sheriff = {
        label = "Blaine County Sheriff's Office",
        shortLabel = 'BCSO',
        type = 'law_enforcement',
        icon = 'star',
        color = '#c5a46d', jurisdiction = 'Blaine County and county contract areas',
        chatChannel = 'sheriff_nonrp', radioChannel = 'sheriff_rp',
        fleetNamespace = 'sheriff', armoryNamespace = 'sheriff', wardrobeNamespace = 'sheriff',
        serviceNpc = { name = 'Deputy Reed', role = 'Sheriff Public Desk', model = 's_m_y_sheriff_01' },
        ranks = {
            { tier = 100, name = 'Sheriff', leader = true, permissions = commandPermissions },
            { tier = 80, name = 'Undersheriff', permissions = commandPermissions },
            { tier = 50, name = 'Sergeant', permissions = supervisorPermissions },
            { tier = 20, name = 'Deputy', permissions = memberPermissions },
            { tier = 1, name = 'Cadet', permissions = recruitPermissions },
        },
    },
    fib = {
        label = 'Federal Investigation Bureau',
        shortLabel = 'FIB',
        type = 'law_enforcement',
        icon = 'building-shield',
        color = '#4b86b4', jurisdiction = 'Federal investigations and inter-agency operations',
        chatChannel = 'fib_nonrp', radioChannel = 'fib_rp',
        fleetNamespace = 'fib', armoryNamespace = 'fib', wardrobeNamespace = 'fib',
        -- Special Agent and higher may begin duty in approved plain clothes.
        -- Probationary Agents must use the wardrobe uniform flow.
        plainclothesMinTier = 20,
        serviceNpc = { name = 'Agent Monroe', role = 'FIB Reception', model = 's_m_m_fiboffice_01' },
        ranks = {
            { tier = 100, name = 'Director', leader = true, permissions = commandPermissions },
            { tier = 80, name = 'Deputy Director', permissions = commandPermissions },
            { tier = 50, name = 'Special Agent in Charge', permissions = supervisorPermissions },
            { tier = 20, name = 'Special Agent', permissions = memberPermissions },
            { tier = 1, name = 'Probationary Agent', permissions = recruitPermissions },
        },
    },
    army = {
        label = 'San Andreas Army',
        shortLabel = 'Army',
        type = 'military',
        icon = 'person-military-rifle',
        color = '#71835a', jurisdiction = 'Military installations and authorized state deployments',
        chatChannel = 'army_nonrp', radioChannel = 'army_rp',
        fleetNamespace = 'army', armoryNamespace = 'army', wardrobeNamespace = 'army',
        serviceNpc = { name = 'Sergeant Harris', role = 'Army Administration', model = 's_m_y_marine_01' },
        -- New enforcement powers are opt-in for Army. Existing administrator
        -- overrides are retained by the seed migration.
        capabilityDefaults = { citations = false, impound = false, radar = false,
            clamp = false, k9 = false, alpr = false },
        ranks = {
            { tier = 100, name = 'General', leader = true, permissions = commandPermissions },
            { tier = 80, name = 'Colonel', permissions = commandPermissions },
            { tier = 50, name = 'Major', permissions = supervisorPermissions },
            { tier = 20, name = 'Sergeant', permissions = memberPermissions },
            { tier = 1, name = 'Private', permissions = recruitPermissions },
        },
    },
}

-- Cuffing/escort mechanic (server/cuffs.lua, client/cuffs.lua+escort.lua).
Config.Cuffs = { InteractDistance = 2.5, VehicleSeatDistance = 6.0 }
Config.Enforcement = {
    DirectDistance = 4.0,
    ClampDistance = 3.0,
    CitationCooldownMs = 1500,
    K9 = {
        Model = 'a_c_shepherd', TrackRadius = 150.0, ChaseDistance = 75.0,
        AttackDistance = 20.0, SearchDistance = 4.0,
        ThreatMemoryMs = 120000,
    },
    Violations = {
        { id = 'speeding', label = 'Speeding', fine = 250, jailMinutes = 0, description = 'Operating above the posted speed limit.' },
        { id = 'reckless_driving', label = 'Reckless Driving', fine = 500, jailMinutes = 10, description = 'Driving with disregard for public safety.' },
        { id = 'failure_to_comply', label = 'Failure to Comply', fine = 300, jailMinutes = 10, description = 'Failure to comply with a lawful direction.' },
        { id = 'no_license', label = "No Driver's License", fine = 150, jailMinutes = 0, description = 'Operating without a valid driving licence.' },
        { id = 'illegal_parking', label = 'Illegal Parking', fine = 100, jailMinutes = 0, description = 'Parking contrary to traffic restrictions.' },
        { id = 'resisting_arrest', label = 'Resisting Arrest', fine = 750, jailMinutes = 20, description = 'Resisting a lawful arrest.' },
    },
}
-- Every organization has its own intake NPC, while these settings govern one
-- shared physical jail spawn pool and release point owned by cm-law.
-- Booking sentences are calculated from server-owned charge definitions.
-- Clients only submit charge ids; labels and jail time are never trusted.
Config.Custody = {
    IntakeRadius = 8.0,
    SpawnCapacity = 2,
    SurrenderMinutesPerStar = 15,
    MaxCharges = 10,
    MaxSentenceMinutes = 180,
    Charges = {
        { id = 'reckless_driving', label = 'Reckless Driving', jailMinutes = 10 },
        { id = 'failure_to_comply', label = 'Failure to Comply', jailMinutes = 10 },
        { id = 'resisting_arrest', label = 'Resisting Arrest', jailMinutes = 20 },
        { id = 'evading', label = 'Evading Law Enforcement', jailMinutes = 20 },
        { id = 'assault', label = 'Assault', jailMinutes = 20 },
        { id = 'assault_leo', label = 'Assault on a Legal Officer', jailMinutes = 30 },
        { id = 'illegal_weapon', label = 'Possession of an Illegal Weapon', jailMinutes = 20 },
        { id = 'armed_robbery', label = 'Armed Robbery', jailMinutes = 40 },
        { id = 'kidnapping', label = 'Kidnapping', jailMinutes = 45 },
        { id = 'murder', label = 'Murder', jailMinutes = 60 },
    },
}

-- 911/dispatch (server/dispatch.lua, client/dispatch.lua). Citizens use
-- /reportlaw -- cm-police already owns /reportcrime and cm-ems owns /911,
-- so this needed its own command. Calls broadcast to every on-duty member
-- with law.receive_dispatch across ALL FOUR organizations, not just one --
-- a citizen calling for help has no way to know which agency is on shift.
Config.Dispatch = {
    Cooldown = 30000,
    BackupCooldown = 30000,
    PanicCooldown = 60000,
    ExpireAfterMs = 600000,
    HistoryLimit = 50,
    BlipSprite = 161,
    BlipColour = 5,
    BackupBlipColour = 47,
    PanicBlipColour = 1,
}

Config.DefaultPermissions = {
    'law.view_members', 'law.receive_dispatch', 'law.radio', 'law.chat',
    'law.mdt', 'law.cuff', 'law.drag', 'law.search', 'law.vehicle',
    'law.armory', 'law.storage', 'law.spike', 'law.barricade', 'law.fleet',
    'law.cite', 'law.impound', 'law.radar', 'law.clamp',
    'law.logistics.request',
}

Config.Logistics = {
    SourceOrganization = 'army',
    SourceFacilityType = 'armory',
    ReceivingFacilityType = 'armory',
    MaxOpenOrdersPerOrganization = 3,
    MaxLinesPerOrder = 8,
    MaxQuantityPerLine = 1000,
    MaxTotalQuantity = 5000,
    RequestCooldownMs = 1500,
    DeliveryRadius = 15.0,
    ShipmentVehicleModel = 'barracks',
    ShipmentVehicleLabel = 'Army Logistics Transport',
    DefaultReceivingMaxStock = 10000,
    -- Phase 4 uses the same temporary shipment vehicle and order rows as
    -- Phase 3.  Empty extraction points intentionally disable the final
    -- gang-credit step until an operator configures safe world locations.
    Robbery = {
        Enabled = true,
        GangPermission = 'gang.rob_items',
        BreachSeconds = 20,
        MaxStoppedSpeed = 0.75,
        RearDistance = 3.5,
        InteractionDistance = 2.5,
        VisualRadius = 100.0,
        CargoModel = 'prop_cs_cardbox_01',
        CargoUnits = {
            ammo_9mm = 250, ammo_9x19_smg = 250, ammo_556nato = 250,
            armor_light = 5,
        },
        CargoExpirySeconds = 1800,
        DroppedExpirySeconds = 1800,
        ReconcileIntervalMs = 3000,
        HeartbeatIntervalMs = 2500,
        ExtractionRadius = 4.0,
        NotifyDestination = true,
        RecoveryRadius = 6.0,
        -- Entries use { id, x, y, z, bucket }.  No extraction location is
        -- inferred from a gang HQ or a law facility.
        ExtractionPoints = {},
    },
    Permissions = {
        request = 'law.logistics.request', accept = 'law.logistics.accept',
        prepare = 'law.logistics.prepare', load = 'law.logistics.load',
        deliver = 'law.logistics.deliver', cancel = 'law.logistics.cancel',
        recover = 'law.logistics.recover',
    },
    RequestableItems = {
        'ammo_9mm', 'ammo_9x19_smg', 'ammo_556nato', 'armor_light',
    },
    ReceivingPoints = {},
}

-- Phase 5 is a separate, rare major event. It never changes the routine
-- logistics order state machine above. Coordinates and manifests are
-- operator-owned; the empty database tables are deliberately fail-closed.
Config.ArsenalResupply = {
    Enabled = false,
    DailySchedule = { enabled = true, hour = 22, minute = 0, warmupSeconds = 300 },
    MinimumArmyOnline = 2,
    PreparationSeconds = 120,
    MaximumDurationSeconds = 3600,
    IntelIntervalSeconds = 75,
    IntelEnabled = true,
    ApproximateSearchRadius = 750.0,
    UnloadSeconds = 20,
    LeadEscortCount = 1,
    CargoTruckCount = 2,
    RearEscortCount = 1,
    MaxStoppedSpeed = 0.75,
    ArrivalRadius = 28.0,
    InteractionDistance = 2.5,
    BreachSeconds = 20,
    CargoExpirySeconds = 1800,
    DroppedExpirySeconds = 1800,
    ReconcileIntervalMs = 3000,
    ResultQuickViewSeconds = 60,
    Presentation = {
        id = 'arsenal_resupply',
        title = 'Arsenal Resupply',
        subtitle = 'Major military shipment',
        description = 'A major military shipment is preparing to move. Intercept military cargo before Army forces secure it.',
        image = 'nui://cm-gang/html/assets/events/arsenal-resupply-placeholder.svg',
        rules = {
            'Army must secure physical cargo at its warehouse.',
            'Multiple gangs compete independently by extracted cargo value.',
            'Stolen cargo must reach a configured extraction point.',
            'Temporary convoy vehicles cannot be stored or claimed.',
        },
    },
    LeadVehicleModel = 'barracks',
    CargoVehicleModel = 'barracks',
    RearVehicleModel = 'barracks',
    VehicleSpacing = 12.0,
    Manifest = {
        { item = 'ammo_9x19_smg', quantity = 500, crateSize = 250, valueWeight = 1 },
        { item = 'ammo_556nato', quantity = 500, crateSize = 250, valueWeight = 1 },
    },
    -- Route rows and extraction points should normally be captured by the
    -- restricted cm-law admin exports documented in docs/ARSENAL_RESUPPLY.md.
    Routes = {},
    ExtractionPoints = {},
}

-- Flat, ungrouped id -> label map (matches cm-police's own Config.Permissions
-- shape) for the F9 Ranks & Access permission-checkbox grid. Every id used
-- anywhere in the tier ladder above must appear here or it can never be
-- granted/labeled from the UI.
Config.Permissions = {
    ['law.view_members'] = 'View organization roster',
    ['law.chat'] = 'Use organization chat channel',
    ['law.radio'] = 'Use organization radio channel',
    ['law.receive_dispatch'] = 'Receive 911 dispatch calls',
    ['law.mdt'] = 'Access the MDT',
    ['law.cuff'] = 'Cuff, escort, and book suspects',
    ['law.drag'] = 'Drag/escort restrained suspects',
    ['law.search'] = 'Search suspects',
    ['law.vehicle'] = 'Call fleet vehicles',
    ['law.armory'] = 'Access the armory',
    ['law.manage_armory'] = 'Manage armory equipment and stock',
    ['law.logistics.request'] = 'Request routine Army supplies',
    ['law.logistics.accept'] = 'Accept Army supply orders',
    ['law.logistics.prepare'] = 'Prepare supply shipments',
    ['law.logistics.load'] = 'Load supply shipments',
    ['law.logistics.deliver'] = 'Deliver supply shipments',
    ['law.logistics.cancel'] = 'Cancel or release supply orders',
    ['law.logistics.recover'] = 'Recover interrupted supply shipments',
    ['law.storage'] = 'Access department storage',
    ['law.spike'] = 'Deploy and recall spike strips',
    ['law.barricade'] = 'Deploy and recall barricades',
    ['law.cite'] = 'Issue citations from the legal catalog',
    ['law.manage_citations'] = 'Void and manage organization citations',
    ['law.impound'] = 'Tow and impound vehicles',
    ['law.manage_impound'] = 'Manage impound configuration and releases',
    ['law.radar'] = 'Use speed radar',
    ['law.clamp'] = 'Apply and remove wheel clamps',
    ['law.k9'] = 'Deploy and command a K9 unit',
    ['law.alpr'] = 'Receive and use ALPR intelligence',
    ['law.manage_alpr'] = 'Manage ALPR cameras and settings',
    ['law.view_member_map'] = 'View organization members on the map',
    ['law.set_meeting'] = 'Set and clear organization meeting points',
    ['law.fleet'] = 'Manage fleet vehicles (location, rank, recall all)',
    ['law.manage_members'] = 'Hire, rank, suspend, and remove members',
    ['law.manage_ranks'] = 'Create, edit, and delete ranks',
    ['law.manage_permissions'] = 'Assign rank permissions',
}
