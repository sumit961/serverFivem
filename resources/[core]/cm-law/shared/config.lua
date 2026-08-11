Config = {}

Config.AdminResource = 'cm-admin'
Config.PlayerDataResource = 'cm-playerdata'
Config.AdminPermission = 'orgs.manage'
Config.MenuCommand = 'laworg'
Config.MenuKey = 'F7' -- physical mapping is owned centrally by cm-police/client/org_keys.lua
Config.FacilityInteractDistance = 2.5
Config.FacilityDrawDistance = 18.0
Config.CinematicResponseDuration = 2200
Config.FacilityTypes = {
    front_desk = { label = 'Front Desk', role = 'Public Services', icon = 'shield', public = true },
    wardrobe = { label = 'Wardrobe', role = 'Uniform Specialist', icon = 'shirt', allowOffDuty = true },
    armory = { label = 'Armory', role = 'Quartermaster', icon = 'gun' },
    storage = { label = 'Storage', role = 'Department Storekeeper', icon = 'box' },
    evidence = { label = 'Evidence Storage', role = 'Evidence Custodian', icon = 'fingerprint' },
    fleet = { label = 'Fleet', role = 'Fleet Coordinator', icon = 'car' },
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
    'law.spike', 'law.barricade',
}
local supervisorPermissions = {
    'law.view_members', 'law.chat', 'law.radio', 'law.receive_dispatch',
    'law.mdt', 'law.cuff', 'law.drag', 'law.search', 'law.vehicle',
    'law.armory', 'law.storage', 'law.spike', 'law.barricade',
}
local commandPermissions = {
    'law.view_members', 'law.chat', 'law.radio', 'law.receive_dispatch',
    'law.mdt', 'law.cuff', 'law.drag', 'law.search', 'law.vehicle',
    'law.armory', 'law.storage', 'law.spike', 'law.barricade', 'law.fleet', 'law.manage_members',
    'law.manage_ranks', 'law.manage_permissions', 'law.manage_armory',
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
    ['law.storage'] = 'Access department storage',
    ['law.spike'] = 'Deploy and recall spike strips',
    ['law.barricade'] = 'Deploy and recall barricades',
    ['law.fleet'] = 'Manage fleet vehicles (location, rank, recall all)',
    ['law.manage_members'] = 'Hire, rank, suspend, and remove members',
    ['law.manage_ranks'] = 'Create, edit, and delete ranks',
    ['law.manage_permissions'] = 'Assign rank permissions',
}
