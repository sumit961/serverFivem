Config = {}

-- ============================================================
--  General
-- ============================================================
Config.Debug = false
Config.HouseResource = 'cm-house'
Config.VehiclesResource = 'cm-vehicles'
Config.VehicleKeysResource = 'cm-vehiclekeys'
Config.VehicleShopResource = 'rn-vehicleshop'
Config.PlayerDataResource = 'cm-playerdata'
Config.InventoryResource = 'cm-inventory'
Config.ChatResource = 'cm-chat'

-- Database bootstrap. Keep enabled so fresh installs and older partial schemas
-- are repaired before any family callback can touch the database. When the DB
-- user has no CREATE/ALTER permission, install the base schema/migrations manually.
-- Migration 007 is a non-destructive legacy-grade diagnostic.
Config.Database = {
    autoInstall = true,
}

-- Maximum number of ranks a family may have (including the founder rank).
Config.MaxRanks = 15

-- Default required level applied to a family vehicle that has no explicit
-- per-vehicle entry yet. Keep low so newly parked cars are broadly usable
-- until an officer restricts them.
Config.DefaultVehicleLevel = 1

-- ============================================================
--  NPC
--  The family registrar. Talk to it and press E to open the create/join flow.
-- ============================================================
Config.NPC = {
    enabled = true,
    model = 'a_m_y_business_01',
    coords = vector4(-544.36, -204.98, 38.22, 205.0),   -- near Legion Square; move freely
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    interactionDistance = 2.0,
    drawDistance = 20.0,
    blip = {
        enabled = true,
        sprite = 280,
        color = 3,
        scale = 0.8,
        label = 'Family Registrar',
    },
}

-- The command that opens the full-screen family menu for a member.
Config.MenuCommand = 'family'

-- Key control id used for the NPC E prompt (38 = INPUT_CONTEXT = E).
Config.PromptKey = 38

-- ============================================================
--  Permissions
--
--  These are the cm-family permission keys shown in the rank editor. Two groups:
--    management keys  -> govern the family itself (invite, kick, ranks, bank)
--    house keys       -> forwarded to cm-house's HasHousePermission gate
--
--  A rank grants a permission when its JSON permissions[key] == true. The
--  founder rank implicitly holds everything regardless of stored JSON.
-- ============================================================
Config.Permissions = {
    -- Family management
    { key = 'family.invite',        label = 'Invite members',        group = 'management' },
    { key = 'family.kick',          label = 'Kick members',          group = 'management' },
    { key = 'family.promote',       label = 'Promote members',       group = 'management' },
    { key = 'family.demote',        label = 'Demote members',        group = 'management' },
    { key = 'family.manage_ranks',  label = 'Create / edit ranks',   group = 'management' },
    { key = 'family.manage_perms',  label = 'Edit rank permissions', group = 'management' },
    { key = 'family.manage_vehicles', label = 'Set vehicle levels',  group = 'management' },
    { key = 'family.rename',        label = 'Rename family',         group = 'management' },
    { key = 'family.manage_tags',   label = 'Manage family symbol',     group = 'management' },
    { key = 'family.manage_titles', label = 'Manage member titles',  group = 'management' },
    { key = 'family.view_logs',     label = 'View family activity',  group = 'management' },
    { key = 'family.set_meeting',   label = 'Set meeting point',     group = 'management' },
    { key = 'vehicle.track',        label = 'Track shared vehicles', group = 'vehicles' },

    -- Bank
    { key = 'bank.view',            label = 'View bank',             group = 'bank' },
    { key = 'bank.deposit',         label = 'Deposit',               group = 'bank' },
    { key = 'bank.withdraw',        label = 'Withdraw',              group = 'bank' },

    -- House-forwarded (answered to cm-house)
    { key = 'door.enter',           label = 'Enter house',           group = 'house' },
    { key = 'door.lock',            label = 'Lock / unlock',         group = 'house' },
    { key = 'garage.access',        label = 'Open garage',           group = 'house' },
    { key = 'garage.take',          label = 'Take vehicles',         group = 'house' },
    { key = 'garage.store',         label = 'Store vehicles',        group = 'house' },
    { key = 'garage.manage_shared', label = 'Manage shared cars',    group = 'house' },
    { key = 'trunk.access',         label = 'Use shared car trunks', group = 'house' },
    { key = 'weapon_storage.access',   label = 'Open weapon storage', group = 'house' },
    { key = 'weapon_storage.deposit',  label = 'Deposit weapons',    group = 'house' },
    { key = 'weapon_storage.withdraw', label = 'Withdraw weapons',   group = 'house' },
    { key = 'storage.access',       label = 'General storage',       group = 'house' },
    { key = 'helipad.use',          label = 'Use helipad',           group = 'house' },
}

-- The subset of permission keys that cm-house asks about through
-- HasHousePermission. Anything not in this set is treated as management-only.
Config.HousePermissionKeys = {
    ['door.enter'] = true, ['door.lock'] = true,
    ['garage.access'] = true, ['garage.take'] = true, ['garage.store'] = true,
    ['garage.manage_shared'] = true, ['garage.take_any'] = true,
    ['weapon_storage.access'] = true, ['weapon_storage.deposit'] = true,
    ['weapon_storage.withdraw'] = true,
    ['storage.access'] = true, ['trunk.access'] = true, ['helipad.use'] = true,
}

-- Vehicle actions gated by per-vehicle LEVEL (tier >= level) rather than a
-- flat permission. When cm-house asks about one of these AND the action targets
-- a specific vehicle, cm-family applies the level check as well as the base
-- garage permission.
Config.VehicleLevelActions = {
    ['garage.take'] = true,
    ['garage.access'] = true,
    ['garage.manage_shared'] = true,
    ['helipad.use'] = true,
}

-- Every active family member receives these baseline permissions at the linked
-- family house. Rank permissions still control management actions (locking,
-- shared-vehicle administration, rank editing, bank withdrawals, etc.).
-- This is intentionally DB-membership based so legacy rank-id/grade schemas
-- cannot strand a valid member outside their own family property.
Config.BasicMemberHousePermissions = {
    ['door.enter'] = true,
    ['garage.access'] = true,
    ['garage.take'] = true,
    ['garage.store'] = true,
    ['weapon_storage.access'] = true,
    ['weapon_storage.deposit'] = true,
    ['weapon_storage.withdraw'] = true,
    ['storage.access'] = true,
}

-- ============================================================
--  Default ranks created for a new family.
--  Founder is always tier == Config.MaxRanks and holds everything.
--  Ordered high tier -> low tier.
-- ============================================================
Config.DefaultRanks = {
    {
        tier = 15, name = 'Head', is_founder = true, bank_daily_limit = -1,
        overhead_symbol = 'crown', overhead_color = '#ffd76a',
        permissions = 'ALL',   -- sentinel: every permission true
    },
    {
        tier = 10, name = 'Officer', bank_daily_limit = 100000,
        overhead_symbol = 'shield', overhead_color = '#00f0ff',
        permissions = {
            'family.invite', 'family.kick', 'family.promote', 'family.demote',
            'family.manage_vehicles', 'family.manage_tags', 'family.manage_titles', 'family.view_logs', 'vehicle.track',
            'bank.view', 'bank.deposit', 'bank.withdraw',
            'door.enter', 'door.lock', 'garage.access', 'garage.take', 'garage.store',
            'garage.manage_shared', 'trunk.access', 'weapon_storage.access', 'weapon_storage.deposit',
            'weapon_storage.withdraw', 'storage.access', 'helipad.use',
        },
    },
    {
        tier = 5, name = 'Member', bank_daily_limit = 25000,
        overhead_symbol = 'star', overhead_color = '#75e6ff',
        permissions = {
            'bank.view', 'bank.deposit',
            'door.enter', 'garage.access', 'garage.take', 'garage.store',
            'trunk.access', 'weapon_storage.access', 'storage.access',
        },
    },
    {
        tier = 1, name = 'Recruit', bank_daily_limit = 0,
        overhead_symbol = 'flower', overhead_color = '#9be7ff',
        permissions = {
            'bank.view', 'door.enter', 'garage.access',
            'garage.take', 'garage.store', 'trunk.access',
            'weapon_storage.access', 'weapon_storage.deposit', 'weapon_storage.withdraw',
            'storage.access',
        },
    },
}

-- ============================================================
--  Bank
-- ============================================================
Config.Bank = {
    -- Money account used when depositing to / withdrawing from the family bank.
    account = 'bank',
    maxBalance = 2000000000,
    -- Daily withdrawal limits reset at this server hour (0-23, local server time).
    dailyResetHour = 0,
}

-- ============================================================
--  Family creation rules
-- ============================================================
Config.Create = {
    -- Only these house types can become a family house (mirrors cm-house, which
    -- rejects apartments). cm-house also requires family_eligible == true; the
    -- create list is filtered to houses that satisfy both.
    minNameLength = 3,
    maxNameLength = 32,
    tagMaxLength = 5,
    creationFee = 0,   -- optional fee charged from the founder on creation
}


-- ============================================================
--  Overhead family identity / G-menu / chat
-- ============================================================
Config.Identity = {
    -- Overhead identity is symbol-only. Family tag/rank/custom-title text stays
    -- available for chat, profiles and menus but is never rendered above a ped.
    symbolOnly = true,
    symbolVisible = true,
    defaultSymbol = 'shield',
    defaultColor = '#00f0ff',
    symbolOrder = { 'crown', 'flower', 'star', 'shield', 'diamond', 'skull', 'heart', 'bolt', 'moon', 'sun' },
    allowedSymbols = {
        crown = { label = 'Crown' },
        flower = { label = 'Flower' },
        star = { label = 'Star' },
        shield = { label = 'Shield' },
        diamond = { label = 'Diamond' },
        skull = { label = 'Skull' },
        heart = { label = 'Heart' },
        bolt = { label = 'Lightning' },
        moon = { label = 'Moon' },
        sun = { label = 'Sun' },
    },
    customTitleMaxLength = 24,
    -- The icon is public family identity. cm-playerdata still protects the
    -- actual player name with the known-player / Stranger rules.
    publicOverheadSymbol = true,
}

Config.GMenu = {
    enabled = true,
    pageLabel = 'Family',
    inviteRank = 'lowest',
}

Config.Invites = {
    expiresSeconds = 300, -- database invitation lifetime
    promptSeconds = 30,   -- top-screen Y/N prompt lifetime
}

Config.Chat = {
    enabled = true,
    commands = { 'f', 'familychat' },
    maxLength = 180,
    cooldownMs = 1200,
    prefix = 'Family',
}


-- ============================================================
--  Family map tracking
-- ============================================================
Config.Tracking = {
    members = {
        enabled = true,
        -- Viewer preference is local and defaults on. Only nearby online
        -- members of the same family are rendered as minimap short-range blips.
        defaultEnabled = true,
        -- Only streamed family members within this distance appear. Their
        -- blip is removed on the next update as soon as they leave the range.
        nearbyDistance = 100.0,
        updateMs = 500,
        blipSprite = 1,
        blipColor = 3,
        blipScale = 0.72,
        label = 'Family member',
    },
    vehicles = {
        enabled = true,
        permission = 'vehicle.track',
        cooldownSeconds = 300,
        blipDurationSeconds = 300,
        blipSprite = 225,
        blipColor = 3,
        blipScale = 0.85,
    },
}


-- ============================================================
--  Family activity audit
-- ============================================================
Config.Audit = {
    enabled = true,
    menuLimit = 75,
    adminLimit = 250,
    retentionDays = 180,
    retryIntervalMs = 15000,
    highRiskBankAmount = 100000,
    pendingFile = 'audit_pending.json',

    -- Only these server resources may write gameplay activity through the
    -- WriteFamilyActivity export. This is never a network event.
    authorizedWriters = {
        ['cm-family'] = true,
        ['cm-house'] = true,
        ['cm-vehicles'] = true,
        ['cm-vehiclekeys'] = true,
        ['cm-chat'] = true,
        ['cm-inventory'] = true,
        ['cm-admin'] = true,
    },

    -- Read access to cross-family/high-risk history is reserved for cm-admin.
    adminReaders = {
        ['cm-admin'] = true,
    },
}
