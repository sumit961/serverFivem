Config = Config or {}

-- Immutable persistence allowlist. Display identity is database-owned after
-- sql/003_cm_gang_five_gangs.sql first seeds these five canonical rows.
Config.GangIds = { 'marabunta', 'bloods', 'ballas', 'families', 'vagos' }
Config.GangIdSet = {}
for _, gangId in ipairs(Config.GangIds) do
    Config.GangIdSet[gangId] = true
end

-- Retired pre-migration slots. Never written to by boot repair, never
-- treated as a fixed gang id, kept only so cm-admin can offer a manual
-- migration of any legacy membership/configuration onto a canonical id.
Config.LegacyGangIds = { 'gang_1', 'gang_2', 'gang_3', 'gang_4' }
Config.LegacyGangIdSet = {}
for _, gangId in ipairs(Config.LegacyGangIds) do
    Config.LegacyGangIdSet[gangId] = true
end

-- Canonical identity defaults, applied by the seed migration. Admins may
-- still adjust the exact shade afterwards; the underlying gang id/name
-- pairing itself is fixed.
Config.CanonicalIdentity = {
    marabunta = { displayName = 'Marabunta', shortTag = 'MRB', color = '#2563eb' },
    bloods    = { displayName = 'Bloods',    shortTag = 'BLD', color = '#ef4444' },
    ballas    = { displayName = 'Ballas',    shortTag = 'BAL', color = '#a855f7' },
    families  = { displayName = 'Families',  shortTag = 'FAM', color = '#22c55e' },
    vagos     = { displayName = 'Vagos',     shortTag = 'VGS', color = '#eab308' },
}

-- Native GTA radar colour indexes used by sprite 543 (radar_jugg).
Config.GangRadarColours = { marabunta = 3, bloods = 1, ballas = 7, families = 2, vagos = 5 }

Config.Commands = {
    dashboard = 'gang',
    chat = 'g',
    chatRp = 'gr',
}

Config.Keys = {
    dashboard = 'F8',
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
    marabunta = {
        names = { 'Mateo Cruz', 'Rafael Ortega', 'Diego Santos' }, nicknames = { 'Azul', 'Mako', 'Cruce' },
        models = { 'g_m_y_mexgoon_01' }, outfits = { { components = { [3]={0,0}, [4]={1,2}, [6]={1,0}, [8]={15,0}, [11]={0,2} } } },
        refusals = { main='This is Marabunta business. If Azul did not send for you, keep moving.', vehicle='These keys only move for Marabunta. Find your own ride.', profit='You have no share in this money. Walk away before I count you as a problem.' },
    },
    bloods = {
        names = { 'Darius King', 'Malik Carter', 'Andre Brooks' }, nicknames = { 'Red', 'Kilo', 'Ace' },
        models = { 'a_m_y_business_02' }, outfits = { { components = { [3]={0,0}, [4]={1,3}, [6]={1,0}, [8]={15,0}, [11]={0,3} } } },
        refusals = { main='You are standing on Bloods ground without Bloods colors. State your business somewhere else.', vehicle='No Blood rides leave this yard for outsiders.', profit='This count belongs to the Bloods. Your name is not in my book.' },
    },
    ballas = {
        names = { 'Lamar Hayes', 'Terrence Cole', 'Jamal Price' }, nicknames = { 'Violet', 'Tone', 'Saint' },
        models = { 'a_m_m_business_01' }, outfits = { { components = { [3]={0,0}, [4]={1,5}, [6]={1,0}, [8]={15,0}, [11]={0,5} } } },
        refusals = { main='Ballas handle Ballas business. You are not on the list.', vehicle='Purple keys stay with the set. I cannot help you.', profit='This account is closed to outsiders. Do not ask twice.' },
    },
    families = {
        names = { 'Marcus Green', 'Calvin Reed', 'DeShawn Miles' }, nicknames = { 'Grove', 'Cee', 'Mills' },
        models = { 'a_m_y_business_02' }, outfits = { { components = { [3]={0,0}, [4]={1,2}, [6]={1,0}, [8]={15,0}, [11]={0,2} } } },
        refusals = { main='Families look after family. I do not know you, so there is nothing to discuss.', vehicle='These vehicles are for the family circle only.', profit='Family money stays in the family. Keep it moving.' },
    },
    vagos = {
        names = { 'Javier Flores', 'Luis Navarro', 'Emilio Vega' }, nicknames = { 'Oro', 'Lobo', 'Vega' },
        models = { 'g_m_y_mexgoon_01' }, outfits = { { components = { [3]={0,0}, [4]={1,1}, [6]={1,0}, [8]={15,0}, [11]={0,1} } } },
        refusals = { main='This is Vagos territory, amigo. Members talk business; visitors keep walking.', vehicle='No colors, no keys. The Vagos garage is closed to you.', profit='You did not earn a cut here. There is nothing for you to collect.' },
    },
}

Config.Chat = {
    maximumLength = 180,
    cooldownSeconds = 2,
}

-- 'headquarters' and 'profit' are physical, NPC-anchored facilities.
-- 'armory'/'stash'/'fleet' remain location-only (accessed through the
-- headquarters service NPC / dashboard).
Config.FacilityTypes = {
    headquarters = true,
    armory = true,
    stash = true,
    fleet = true,
    profit = true,
}

Config.NpcFacilityTypes = {
    headquarters = true,
    profit = true,
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
        marabunta = { { id='default', texture='marabunta' } },
        bloods = { { id='default', texture='bloods' } },
        ballas = { { id='default', texture='ballas' } },
        families = { { id='default', texture='families' } },
        vagos = { { id='default', texture='vagos' } },
    },
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
    { key = 'gang.wardrobe',           group = 'armory' },
    { key = 'gang.stash',              group = 'stash' },
    { key = 'gang.manage_stash',       group = 'stash' },
    { key = 'gang.invite',             group = 'members' },
    { key = 'gang.search',             group = 'robbery' },
    { key = 'gang.rob_cash',           group = 'robbery' },
    { key = 'gang.rob_items',          group = 'robbery' },
    { key = 'gang.view_map',           group = 'coordination' },
    { key = 'gang.set_meeting_point',  group = 'coordination' },
    { key = 'gang.blacklist',          group = 'management' },
    { key = 'gang.manage_blacklist',   group = 'management' },
    { key = 'gang.collect_profit',     group = 'management' },
    { key = 'gang.issue_bonus',        group = 'management' },
    { key = 'gang.graffiti',           group = 'coordination' },
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
