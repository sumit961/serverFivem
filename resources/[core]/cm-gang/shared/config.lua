Config = Config or {}

-- Exactly five immutable persistence slots. The IDs are authoritative and map
-- deterministically to the approved canonical gang identities below.
Config.GangIds = { 'gang_1', 'gang_2', 'gang_3', 'gang_4', 'gang_5' }
Config.GangIdSet = {}
for _, gangId in ipairs(Config.GangIds) do
    Config.GangIdSet[gangId] = true
end

-- Rows from the superseded five-gang experiment are retained for explicit
-- admin recovery only. Startup never migrates or deletes their membership.
Config.LegacyGangIds = { 'marabunta', 'bloods', 'ballas', 'families', 'vagos' }
Config.LegacyGangIdSet = {}
for _, gangId in ipairs(Config.LegacyGangIds) do
    Config.LegacyGangIdSet[gangId] = true
end

-- Canonical identity defaults. cm-admin may still manage enabled state and
-- administrative metadata; it must not create additional gang IDs.
Config.CanonicalIdentity = {
    gang_1 = { displayName = 'Marabunta', shortTag = 'MAR', color = '#2563EB', enabled = false },
    gang_2 = { displayName = 'Bloods', shortTag = 'BLD', color = '#EF4444', enabled = false },
    gang_3 = { displayName = 'Ballas', shortTag = 'BAL', color = '#A855F7', enabled = false },
    gang_4 = { displayName = 'Families', shortTag = 'FAM', color = '#22C55E', enabled = false },
    gang_5 = { displayName = 'Vagos', shortTag = 'VAG', color = '#EAB308', enabled = false },
}

-- Native GTA radar colour indexes used by sprite 543 (radar_jugg).
Config.GangRadarColours = { gang_1 = 3, gang_2 = 1, gang_3 = 7, gang_4 = 2, gang_5 = 5 }

Config.Commands = {
    dashboard = 'gang',
    chat = 'g',
    chatRp = 'gr',
}

Config.Keys = {
    dashboard = 'F8',
}

Config.Progression = {
    trustedContributionResources = {},
    maximumAwardPoints = 10000,
    maximumTotalContribution = 2147483647,
    referenceMaximumLength = 128,
    metadataMaximumKeys = 8,
    metadataKeyMaximumLength = 32,
    metadataValueMaximumLength = 96,
    metadataMaximumBytes = 1024,
    levels = {
        { level = 1, threshold = 0, label = 'Unproven' },
        { level = 2, threshold = 100, label = 'Proven' },
        { level = 3, threshold = 300, label = 'Trusted' },
        { level = 4, threshold = 750, label = 'Respected' },
        { level = 5, threshold = 1500, label = 'Elite' },
    },
}

Config.Security = {
    interactionDistance = 3.0,
    inviteExpirySeconds = 60,
    inviteCooldownSeconds = 10,
    mutationCooldownSeconds = 2,
    robberyCooldownSeconds = 3,
    robberyCashCooldownSeconds = 30,
    robberyLotteryCooldownSeconds = 60,
    robberyLotteryChancePercent = 15,
    armoryCooldownSeconds = 2,
    vehicleCooldownSeconds = 3,
    meetingCooldownSeconds = 10,
    wardrobeCooldownSeconds = 2,
    profitCollectCooldownSeconds = 5,
}

-- Runtime defaults only. Database/admin configuration overrides these values.
Config.GangEvents = {
    bucketMin = 7100, bucketMax = 7199, zoneRadiusMin = 25.0, zoneRadiusMax = 1000.0,
    joinCooldownMs = 1500, syncIntervalMs = 5000, zonePollMs = 750,
    supplyWar = {
        presentation = {
            id = 'supply_war',
            title = 'Supply War',
            subtitle = 'Gang Combat Event',
            image = 'nui://cm-gang/html/assets/events/supply-war-placeholder.svg',
            description = 'Fight opposing gangs and secure supply crates for your gang armory.',
            rules = {
                'Gang members only', 'Join from the outer event ring', 'On-foot combat',
                'Death sends you to hospital', 'Event deaths do not drop your weapons',
            },
        },
        resultQuickViewSeconds = 60,
        debug = false,
        type = 'supply_war', killPoints = 1, antiFarmSeconds = 90,
        boundaryGraceSeconds = 5, boundaryReentryCooldownSeconds = 120,
        joinRingWidth = 8.0, joinRingTolerance = 0.75, deathReentryCooldownSeconds = 120,
        vehiclePolicy = { allowVehicles = false, allowedClasses = {} },
        worldBoundary = { enabled = true, renderDistance = 150.0, segments = 64 },
        supplyNotificationEnabled = true, warmupAreaMessageEnabled = true,
        zoneCheckMs = 750,
        combatPairThrottleMs = 200, combatValidationMaxDistance = 250.0,
        combatTagNotifyThresholdSeconds = 1,
        reserveFinalDropSlot = true,
        combatTagSeconds = 15, reentryCooldownSeconds = 40,
        captureSeconds = 4, finalCaptureSeconds = 7, objectiveTickMs = 400,
        captureDecayPerSecond = 8, takeoverProgress = 0, claimRadius = 3.0, contestRadius = 6.0,
        schedule = { autoStart = true, intervalHours = 2, anchorHour = 0, anchorMinute = 0, graceMinutes = 5, warmupMinutes = 5 },
        rewardPackage = {
            { item = 'weapon_smg', amount = 1 },
            { item = 'weapon_assaultrifle', amount = 1 },
            { item = 'ammo_9x19_smg', amount = 100 },
            { item = 'ammo_556nato', amount = 120 },
        },
        heatHot = 5, heatMostWanted = 8, heatRevealIntervalSeconds = 20,
        heatRevealRadius = 80.0, mostWantedKillBonus = 1,
        mvp = { kill = 2, assist = 1, drop = 6, finalDrop = 10, defense = 2, death = -1 },
        assistWindowSeconds = 15, activityPlacementRewards = { 100, 50, 25 },
        resultSeconds = 14, crateModel = 'ex_prop_adv_case_sm', parachuteModel = 'p_cargo_chute_s',
        parachuteDescentSeconds = 12, parachuteSpawnHeight = 70.0, smokeSeconds = 45,
        maxActiveDrops = 2, killFeedSeconds = 6,
        drops = {
            { at = 10, points = 5 },
            { at = 300, points = 5 },
            { at = 600, points = 5 },
            { at = 900, points = 5 },
            { at = 1100, points = 10, final = true },
        },
    },
}

Config.Storage = { stashSlots = 60, facilityDistance = 3.0 }

Config.ContactStreaming = {
    spawnDistance = 125.0,
    despawnDistance = 150.0,
    interactionDistance = 2.5,
    modelLoadTimeoutMs = 5000,
}

-- Physical headquarters presentation defaults. The authoritative location,
-- heading, routing bucket, enabled state, NPC model, display name, and role
-- label remain in cm_gang_facilities and are managed through cm-admin. These
-- values deliberately contain no world coordinates, so an unconfigured HQ
-- cannot accidentally create a permanent world location.
Config.Headquarters = {
    interactionDistance = 2.5,
    markerDistance = 35.0,
    marker = {
        type = 1,
        scale = { x = 0.72, y = 0.72, z = 0.22 },
        colour = { r = 49, g = 230, b = 255, a = 125 },
        bobUpAndDown = false,
        faceCamera = false,
        rotate = false,
        direction = { x = 0.0, y = 0.0, z = 0.0 },
    },
}

Config.ContactGreetings = {
    "What's up? What do you need?",
    'What can I do for you?',
    'Need something?',
    "What's happening?",
}

Config.Ranks = {
    maximum = 12,
    nameMaximumLength = 48,
}

Config.AssetKeys = {
    logos = {},
    artwork = {},
}

-- Headquarters/profit peds are selected by admins from this local,
-- code-owned list. A database value outside the list is ignored by clients.
Config.NpcModels = {
    a_m_m_business_01 = true,
    a_m_y_business_02 = true,
    g_m_y_mexgoon_01 = true,
    g_m_y_lost_01 = true,
}

-- One code-owned contact pool per canonical gang. A contact is selected once
-- per cm-gang runtime and remains stable until the resource/server restarts.
-- Models and clothing remain allowlisted here; browser/client payloads can
-- never choose an arbitrary ped or component set.
Config.ContactNpcs = {
    gang_1 = {
        names = { 'Marabunta Contact' }, nicknames = { 'MAR' },
        models = { 'g_m_y_mexgoon_01' }, outfits = { { components = { [3]={0,0}, [4]={1,2}, [6]={1,0}, [8]={15,0}, [11]={0,2} } } },
        refusals = { main='This gang service is for members only.', vehicle='These fleet keys are for members only.' },
    },
    gang_2 = {
        names = { 'Bloods Contact' }, nicknames = { 'BLD' },
        models = { 'a_m_y_business_02' }, outfits = { { components = { [3]={0,0}, [4]={1,3}, [6]={1,0}, [8]={15,0}, [11]={0,3} } } },
        refusals = { main='This gang service is for members only.', vehicle='These fleet keys are for members only.' },
    },
    gang_3 = {
        names = { 'Ballas Contact' }, nicknames = { 'BAL' },
        models = { 'a_m_m_business_01' }, outfits = { { components = { [3]={0,0}, [4]={1,5}, [6]={1,0}, [8]={15,0}, [11]={0,5} } } },
        refusals = { main='This gang service is for members only.', vehicle='These fleet keys are for members only.' },
    },
    gang_4 = {
        names = { 'Families Contact' }, nicknames = { 'FAM' },
        models = { 'a_m_y_business_02' }, outfits = { { components = { [3]={0,0}, [4]={1,2}, [6]={1,0}, [8]={15,0}, [11]={0,2} } } },
        refusals = { main='This gang service is for members only.', vehicle='These fleet keys are for members only.' },
    },
    gang_5 = {
        names = { 'Vagos Contact' }, nicknames = { 'VAG' },
        models = { 'g_m_y_mexgoon_01' }, outfits = { { components = { [3]={0,0}, [4]={1,6}, [6]={1,0}, [8]={15,0}, [11]={0,6} } } },
        refusals = { main='This gang service is for members only.', vehicle='These fleet keys are for members only.' },
    },
}

Config.Chat = {
    maximumLength = 180,
    cooldownSeconds = 2,
}

-- Headquarters is the physical NPC-anchored facility in V1.
-- 'armory'/'stash'/'fleet' remain location-only (accessed through the
-- headquarters service NPC / dashboard).
Config.FacilityTypes = {
    headquarters = true,
    armory = true,
    stash = true,
    fleet = true,
}

Config.NpcFacilityTypes = {
    headquarters = true,
}

Config.Meeting = {
    ttlSeconds = 240,
    maxCoordDelta = 25.0,
}

Config.Tracking = {
    updateMs = 1500,
    nearbyDistance = 100.0,
    blipSprite = 1,
    blipColor = 3,
    blipScale = 0.72,
}

-- Hourly profit tick. `activityToProfitRate` is intentionally 0 until a
-- future gang-activity/event system exists — no invented payouts.
Config.Profit = {
    tickIntervalSeconds = 3600,
    activityToProfitRate = 0,
    maxCollectAmount = 1000000,
    maxBonusAmount = 100000,
    bonusDistance = 5.0,
}

Config.Graffiti = {
    requiredItem = 'spray_can',
    requiredItemAmount = 1,
    gasPerSpray = 2,
    enabled = true,
    repaintDuration = 10000,
    alertThrottleSeconds = 60,
    moneyPerTag = 500,
    payoutMode = 'full',
    moneyType = 'cash',
    interactionDistance = 2.5,
    streamDistance = 90.0,
    wallOffset = 0.025,
    activeSessionTimeout = 20,
    designs = {
        gang_1 = { { id='default', texture='gang_1' } },
        gang_2 = { { id='default', texture='gang_2' } },
        gang_3 = { { id='default', texture='gang_3' } },
        gang_4 = { { id='default', texture='gang_4' } },
        gang_5 = { { id='default', texture='gang_5' } },
    },
}

-- Canonical V1 rank seed. SQL migrations mirror this definition for database
-- bootstrap; existing rank rows and member assignments are never rewritten.
Config.RankDefinitions = {
    { tier = 100, name = 'Leader', isLeaderRank = true, permissions = {
        'gang.view_members', 'gang.manage_members', 'gang.manage_ranks',
        'gang.manage_permissions', 'gang.chat', 'gang.vehicle',
        'gang.manage_vehicles', 'gang.armory', 'gang.manage_armory',
        'gang.stash', 'gang.manage_stash', 'gang.invite', 'gang.view_logs',
    } },
    { tier = 80, name = 'Underboss', isLeaderRank = false, permissions = {
        'gang.view_members', 'gang.manage_members', 'gang.chat', 'gang.vehicle',
        'gang.manage_vehicles', 'gang.armory', 'gang.manage_armory',
        'gang.stash', 'gang.manage_stash', 'gang.invite', 'gang.view_logs',
    } },
    { tier = 60, name = 'Enforcer', isLeaderRank = false, permissions = {
        'gang.view_members', 'gang.chat', 'gang.vehicle', 'gang.armory',
        'gang.stash', 'gang.invite',
    } },
    { tier = 40, name = 'Member', isLeaderRank = false, permissions = {
        'gang.view_members', 'gang.chat', 'gang.vehicle', 'gang.armory',
        'gang.stash',
    } },
    { tier = 20, name = 'Recruit', isLeaderRank = false, permissions = {
        'gang.view_members', 'gang.chat',
    } },
}

Config.Permissions = {
    { key = 'gang.view_members',       group = 'members' },
    { key = 'gang.manage_members',     group = 'members' },
    { key = 'gang.manage_ranks',       group = 'management' },
    { key = 'gang.manage_permissions', group = 'management' },
    { key = 'gang.chat',               group = 'social' },
    { key = 'gang.vehicle',            group = 'vehicles' },
    { key = 'gang.vehicle_trunk',      group = 'vehicles' },
    { key = 'gang.manage_vehicles',    group = 'vehicles' },
    { key = 'gang.armory',             group = 'armory' },
    { key = 'gang.armory_deposit',     group = 'armory' },
    { key = 'gang.manage_armory',      group = 'armory' },
    { key = 'gang.stash',              group = 'stash' },
    { key = 'gang.manage_stash',       group = 'stash' },
    { key = 'gang.invite',             group = 'members' },
    { key = 'gang.view_logs',          group = 'management' },
}

-- Script-owned recurring gang events. Weekdays follow os.date: Sunday=1 ... Saturday=7.
-- Times use the FXServer host clock.
Config.ScriptedEvents = {
    { id='turf_war', title='Turf War', description='Fight for control of active gang territory.', weekdays={6}, hour=21, minute=0, durationMinutes=120, gangs='all' },
    { id='cash_drop_run', title='Cash Drop Run', description='Secure the drop and return the payout to your gang.', weekdays={7}, hour=19, minute=30, durationMinutes=90, gangs='all' },
    { id='gang_convoy', title='Gang Convoy', description='Move with your crew and protect the convoy route.', weekdays={1}, hour=20, minute=0, durationMinutes=60, gangs='all' },
}

function Config.IsFixedGangId(gangId)
    return type(gangId) == 'string' and Config.GangIdSet[gangId] == true
end

function Config.IsLegacyGangId(gangId)
    return type(gangId) == 'string' and Config.LegacyGangIdSet[gangId] == true
end
