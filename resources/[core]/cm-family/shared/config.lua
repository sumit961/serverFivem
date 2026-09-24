Config = {}

-- ============================================================
--  General
-- ============================================================
Config.Debug = false
-- Set to false in production environments to disable in-game/console automated test commands.
-- Can be enabled via server convar `cm_dev_tests=true` or during development runs.
Config.DevTests = false
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

-- Fail-safe threshold for a family vehicle without an explicit access row.
-- The vehicle service resolves this to the family's highest existing rank;
-- MaxRanks is the safe fallback while a family's rank cache is unavailable.
Config.DefaultVehicleLevel = Config.MaxRanks

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
    { key = 'family.manage_announcement', label = 'Edit family announcement', group = 'management' },
    { key = 'family.raid_start',      label = 'Start family raids', group = 'management' },
    { key = 'family.start_events',    label = 'Start family events / operations', group = 'management' },
    { key = 'vehicle.track',        label = 'Track shared vehicles', group = 'vehicles' },

    -- Bank
    { key = 'bank.view',            label = 'View bank',             group = 'bank' },
    { key = 'bank.deposit',         label = 'Deposit',               group = 'bank' },
    { key = 'bank.withdraw',        label = 'Withdraw',              group = 'bank' },

    -- House-forwarded (answered to cm-house)
    { key = 'door.enter',           label = 'Enter house',           group = 'house' },
    { key = 'door.lock',            label = 'Lock / unlock',         group = 'house' },
    { key = 'house.manage_access',  label = 'Manage house access',   group = 'house' },
    { key = 'house.set_spawn',      label = 'Set house spawn',       group = 'house' },
    { key = 'garage.access',        label = 'Open garage',           group = 'house' },
    { key = 'garage.take',          label = 'Take vehicles',         group = 'house' },
    { key = 'garage.store',         label = 'Store vehicles',        group = 'house' },
    { key = 'garage.manage_shared', label = 'Manage shared cars',    group = 'house' },
    { key = 'trunk.access',         label = 'Use shared car trunks', group = 'house' },
    { key = 'weapon_storage.access',   label = 'Open weapon storage', group = 'house' },
    { key = 'weapon_storage.deposit',  label = 'Deposit weapons',    group = 'house' },
    { key = 'weapon_storage.withdraw', label = 'Withdraw weapons',   group = 'house' },
    { key = 'weapon_storage.manage',   label = 'Manage weapon storage', group = 'house' },
    { key = 'storage.access',       label = 'General storage',       group = 'house' },
    { key = 'storage.withdraw',     label = 'Take from storage',     group = 'house' },
    { key = 'storage.deposit',      label = 'Deposit to storage',    group = 'house' },
    { key = 'helipad.use',          label = 'Use helipad',           group = 'house' },
    { key = 'house.view_logs',      label = 'View house activity',   group = 'house' },
}

-- The subset of permission keys that cm-house asks about through
-- HasHousePermission. Anything not in this set is treated as management-only.
Config.HousePermissionKeys = {
    ['door.enter'] = true, ['door.lock'] = true,
    ['house.manage_access'] = true, ['house.set_spawn'] = true,
    ['garage.access'] = true, ['garage.take'] = true, ['garage.store'] = true,
    ['garage.manage_shared'] = true, ['garage.take_any'] = true,
    ['weapon_storage.access'] = true, ['weapon_storage.deposit'] = true,
    ['weapon_storage.withdraw'] = true, ['weapon_storage.manage'] = true,
    ['storage.access'] = true, ['storage.withdraw'] = true, ['storage.deposit'] = true,
    ['trunk.access'] = true, ['helipad.use'] = true,
    ['house.view_logs'] = true,
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

-- Every active family member receives entry at the linked house and can open
-- the armory and storage. Withdrawing weapons or storage items remains rank-authoritative.
Config.BasicMemberHousePermissions = {
    ['door.enter'] = true,
    ['weapon_storage.access'] = true,
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
            'family.manage_announcement', 'family.raid_start',
            'bank.view', 'bank.deposit', 'bank.withdraw',
            'door.enter', 'door.lock', 'house.manage_access', 'house.set_spawn',
            'garage.access', 'garage.take', 'garage.store',
            'garage.manage_shared', 'trunk.access', 'weapon_storage.access', 'weapon_storage.deposit',
            'weapon_storage.withdraw', 'weapon_storage.manage', 'storage.access', 'helipad.use',
            'house.view_logs',
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

    -- Only these server resources may charge a family's bank balance through
    -- the FamilyBankCharge export (e.g. a business/shop resource). Never a
    -- network event -- GetInvokingResource() is checked server-side.
    authorizedExternalResources = {
        -- ['cm-shops'] = true,
    },
}

-- Family-vs-family raid event. The arena circle is centered on the linked
-- family-house door; once a player joins, their existing position is kept and
-- only their routing bucket changes, isolating the fight from the public world.
Config.Raid = {
    enabled = true,
    durationSeconds = 15 * 60,
    countdownSeconds = 10,
    joinRadius = 4.0,
    -- Players may join only from the perimeter band, never from the centre.
    joinEdgeBand = 3.0,
    arenaRadius = 50.0,
    boundaryGraceSeconds = 5,
    reward = 50000,
    maxFamilies = 2,
    bucketBase = 700000,
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
--  Family gameplay events
-- ============================================================
-- Catalogue only: these entries describe events in the family dashboard.
-- ============================================================
--  Family Events & Tactical Operations (Phase 1 Engine)
-- ============================================================
Config.FamilyEvents = {
    family_raid = {
        key = 'family_raid',
        label = 'Family Raid',
        category = 'competitive',
        description = 'High-stakes tactical match against an opposing family at their headquarters.',
        minFamilyLevel = 1,
        minParticipants = 2,
        maxParticipants = 8,
        durationSeconds = 900,
        countdownSeconds = 10,
        cooldownSeconds = 10800, -- 3 hours
        rewards = {
            reputation = 750,
            treasury = 50000,
            contribution = 150,
        },
        rules = {
            allowVehicles = false,
            routingBucket = true,
            arenaRadius = 50.0,
            joinRadius = 4.0,
            joinEdgeBand = 3.0,
            boundaryGraceSeconds = 5,
        },
    },
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

-- ============================================================
--  Family Progression & Level Curve (Priority 1)
-- ============================================================
Config.Progression = {
    maxLevel = 25,
    levelXp = {
        [1]  = 1000,
        [2]  = 1500,
        [3]  = 2250,
        [4]  = 3200,
        [5]  = 4400,
        [6]  = 5900,
        [7]  = 7700,
        [8]  = 9800,
        [9]  = 12300,
        [10] = 15200,
        [11] = 18600,
        [12] = 22500,
        [13] = 27000,
        [14] = 32100,
        [15] = 37900,
        [16] = 44500,
        [17] = 52000,
        [18] = 60400,
        [19] = 69800,
        [20] = 80300,
        [21] = 92000,
        [22] = 105000,
        [23] = 119500,
        [24] = 135600,
        [25] = 153500,
    },
}

function Config.Progression.GetXpForNextLevel(level)
    level = math.max(1, math.min(tonumber(level) or 1, Config.Progression.maxLevel))
    return Config.Progression.levelXp[level] or 150000
end

-- ============================================================
--  Member Contribution Categories & Limits (Priority 2)
-- ============================================================
Config.Contribution = {
    categories = {
        activity    = { label = 'Activity', maxWeekly = 1000 },
        objective   = { label = 'Objective', maxWeekly = 2000 },
        event       = { label = 'Event', maxWeekly = 5000 },
        financial   = { label = 'Financial', maxWeekly = 500 },
        family_work = { label = 'Family Work', maxWeekly = 1500 },
        defence     = { label = 'Defence', maxWeekly = 2000 },
        management  = { label = 'Management', maxWeekly = 500 },
        support     = { label = 'Support', maxWeekly = 1000 },
    },
    moneyPerPoint = 1000,
    maxDailyFinancialPoints = 100,
}

-- ============================================================
--  Family Level Progression Unlocks (Priority 3)
-- ============================================================
Config.LevelUnlocks = {
    [1] = {
        title = 'Foundation',
        description = 'Base family capabilities, headquarters registration, 15 member capacity, and basic shared fleet.',
        memberCapacity = 15,
        sharedVehicleLimit = 4,
        perks = { 'Base family operations', '15 member capacity', '4 shared vehicle slots' },
    },
    [2] = {
        title = 'Expanded Roster',
        description = 'Expand family capacity to recruit additional active members.',
        memberCapacity = 20,
        perks = { '+5 Member capacity (20 total)' },
    },
    [3] = {
        title = 'Family Crest',
        description = 'Unlock customizable family symbols and distinctive overhead identity options.',
        perks = { 'Exclusive family symbols unlocked', 'Overhead identity styling' },
    },
    [4] = {
        title = 'Fleet Expansion I',
        description = 'Authorized storage for additional shared fleet vehicles.',
        sharedVehicleLimit = 6,
        perks = { '+2 Shared vehicle capacity (6 total)' },
    },
    [5] = {
        title = 'Quartermaster I',
        description = 'Increased family headquarters storage capacity and tier 1 storage upgrades.',
        perks = { 'HQ Storage expansion unlocked', 'Higher storage weight limit' },
    },
    [6] = {
        title = 'Syndicate Growth',
        description = 'Expand family capacity to 25 total members.',
        memberCapacity = 25,
        perks = { '+5 Member capacity (25 total)' },
    },
    [7] = {
        title = 'Rapid Fleet Tracking',
        description = 'Advanced telemetry reducing vehicle tracking cooldowns for family officers.',
        perks = { 'Vehicle tracking cooldown reduced by 50%' },
    },
    [8] = {
        title = 'Quartermaster II',
        description = 'Tier 2 headquarters general storage allowance.',
        perks = { 'HQ Storage Tier 2 upgrade available' },
    },
    [9] = {
        title = 'Fleet Expansion II',
        description = 'Increased shared fleet vehicle capacity.',
        sharedVehicleLimit = 8,
        perks = { '+2 Shared vehicle capacity (8 total)' },
    },
    [10] = {
        title = 'Armory Foundation',
        description = 'Unlock Family Armory capacity expansions and garage slot bonuses.',
        perks = { 'HQ Armory Tier 1 expansion', '+2 Garage slots bonus' },
    },
    [12] = {
        title = 'Syndicate Elite',
        description = 'Expand family capacity to 30 members and enhanced rank customizations.',
        memberCapacity = 30,
        perks = { '+5 Member capacity (30 total)', 'Expanded rank titles' },
    },
    [15] = {
        title = 'Operations Command',
        description = 'Unlock the Tactical Command Room upgrade and high-tier operations.',
        perks = { 'HQ Command Room upgrade available', 'High-tier operations access' },
    },
    [20] = {
        title = 'Los Santos Cartel',
        description = 'Major capacity expansions across fleet, armory, and roster.',
        memberCapacity = 40,
        sharedVehicleLimit = 12,
        perks = { '40 Member capacity', '12 Shared vehicle slots', 'Master armory allowance' },
    },
    [25] = {
        title = 'Apex Family',
        description = 'Pinnacle family status with maximum allowances, prestige symbol, and priority operations.',
        memberCapacity = 50,
        sharedVehicleLimit = 16,
        perks = { '50 Member capacity', '16 Shared vehicle slots', 'Prestige apex crest' },
    },
}

function Config.GetLevelUnlocks(level)
    level = tonumber(level) or 1
    local effective = {
        memberCapacity = 15,
        sharedVehicleLimit = 4,
        unlockedTiers = {},
    }
    for lvl = 1, level do
        local u = Config.LevelUnlocks[lvl]
        if u then
            if u.memberCapacity and u.memberCapacity > effective.memberCapacity then
                effective.memberCapacity = u.memberCapacity
            end
            if u.sharedVehicleLimit and u.sharedVehicleLimit > effective.sharedVehicleLimit then
                effective.sharedVehicleLimit = u.sharedVehicleLimit
            end
            effective.unlockedTiers[lvl] = u
        end
    end
    return effective
end

-- ============================================================
--  Family Headquarters Upgrades (Priority 4)
-- ============================================================
Config.HQUpgrades = {
    storage_capacity = {
        label = 'Secure Storage Expansion',
        description = 'Expands general item storage compartments inside the family headquarters.',
        maxTier = 3,
        tiers = {
            [1] = { cost = 50000,  minLevel = 5,  label = 'Tier 1 (+10 Storage Slots)' },
            [2] = { cost = 125000, minLevel = 8,  label = 'Tier 2 (+20 Storage Slots)' },
            [3] = { cost = 250000, minLevel = 14, label = 'Tier 3 (+35 Storage Slots)' },
        },
    },
    weapon_storage_capacity = {
        label = 'Armory Expansion',
        description = 'Reinforced lockers expanding weapon and ammunition storage allowance.',
        maxTier = 3,
        tiers = {
            [1] = { cost = 75000,  minLevel = 10, label = 'Tier 1 (+10 Weapon Slots)' },
            [2] = { cost = 175000, minLevel = 15, label = 'Tier 2 (+20 Weapon Slots)' },
            [3] = { cost = 350000, minLevel = 20, label = 'Tier 3 (+35 Weapon Slots)' },
        },
    },
    garage_slots = {
        label = 'Garage Expansion',
        description = 'Enhances vehicle staging and allocated family garage parking slots.',
        maxTier = 3,
        tiers = {
            [1] = { cost = 100000, minLevel = 6,  label = 'Tier 1 (+2 Garage slots)' },
            [2] = { cost = 225000, minLevel = 12, label = 'Tier 2 (+4 Garage slots)' },
            [3] = { cost = 450000, minLevel = 18, label = 'Tier 3 (+6 Garage slots)' },
        },
    },
    meeting_room = {
        label = 'Tactical Command Room',
        description = 'Designates a dedicated tactical briefing area for family operations.',
        maxTier = 1,
        tiers = {
            [1] = { cost = 150000, minLevel = 15, label = 'Operational Status: Active' },
        },
    },
}

-- ============================================================
--  Weekly Family Objectives (Priority 6)
-- ============================================================
Config.Objectives = {
    rotationCount = 3,
    pool = {
        {
            key = 'active_members',
            title = 'Roster Mobilization',
            description = 'Have 5 unique family members active in the city this week.',
            targetType = 'unique_active_members',
            targetValue = 5,
            rewardReputation = 500,
            rewardContribution = 100,
            rewardTreasury = 25000,
        },
        {
            key = 'treasury_contribute',
            title = 'War Chest Contribution',
            description = 'Contribute a combined $50,000 into the family treasury.',
            targetType = 'net_deposits',
            targetValue = 50000,
            rewardReputation = 600,
            rewardContribution = 150,
            rewardTreasury = 10000,
        },
        {
            key = 'family_activities',
            title = 'Family Engagements',
            description = 'Complete 15 approved family operations and actions.',
            targetType = 'family_actions',
            targetValue = 15,
            rewardReputation = 750,
            rewardContribution = 120,
            rewardTreasury = 30000,
        },
        {
            key = 'fleet_operations',
            title = 'Fleet Deployment',
            description = 'Store and organize 6 shared fleet vehicles in the family garage.',
            targetType = 'fleet_vehicles',
            targetValue = 6,
            rewardReputation = 450,
            rewardContribution = 80,
            rewardTreasury = 20000,
        },
        {
            key = 'syndicate_unity',
            title = 'Syndicate Unity',
            description = 'Maintain at least 6 verified members on the family roster.',
            targetType = 'member_count',
            targetValue = 6,
            rewardReputation = 400,
            rewardContribution = 75,
            rewardTreasury = 15000,
        },
    },
}

-- ============================================================
-- Shared Server/Client Week Key Helper
-- Format: YYYY-Www (e.g. 2026-W38).
-- Timezone Policy: Server local system time. Week boundaries roll over Monday 00:00:00 local time.
-- Used uniformly by objectives, weekly contributions, and future family events.
-- ============================================================
function CMFamilyGetWeekKey(timestamp)
    local dateStr = timestamp and os.date('%Y-W%W', tonumber(timestamp)) or os.date('%Y-W%W')
    local y, w = dateStr:match('^(%d+)%-W(%d+)$')
    return dateStr, tonumber(y) or 2026, tonumber(w) or 1
end
