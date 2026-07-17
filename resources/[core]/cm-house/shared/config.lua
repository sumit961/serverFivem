Config = {}

-- ============================================================
--  General
-- ============================================================
Config.Debug           = false       -- enable only while actively diagnosing
Config.AdminCommand    = 'cmhouse'

-- TEMPORARY LOCAL-DEVELOPMENT BYPASS.
-- When true, every connected player may open and use every cm-house admin
-- section and the property creator. It does NOT grant ordinary owner/family
-- gameplay access to houses, garages, storage or weapons.
-- Set this to false before opening the server to normal players.
Config.DevelopmentPublicAdmin = false

-- Unique aliases avoid conflicts with another resource registering /cmadmin.
Config.PublicAdminCommands = { 'cmadminhouse', 'cmhouseadmin', 'houseadmin' }

-- Automatically repairs additive cm-house v1.5/v1.6 columns and tables at
-- resource startup. Keep enabled for local development and normal upgrades.
-- Disable only when the database account intentionally has no ALTER/CREATE
-- permission and you manage every migration manually.
Config.AutoRepairSchema = true

-- Normal production gate used when DevelopmentPublicAdmin is false.
Config.RequireAdmin    = true

-- When RequireAdmin is on, the gate is checked in this order:
--   1. cm-core:ACLCheck(src, AdminPermission) -> cm-admin:HasPermission
--   2. native ACE fallback:  add_ace group.admin cm-house.create allow
Config.AdminPermission = 'house.create' -- legacy fallback while ranks are migrated
Config.AdminAce        = 'cm-house.create'

-- Granular keys are ready for cm-admin rank permissions. Keep the legacy
-- fallback enabled until existing ranks have these keys, then turn it off.
Config.AdminUseLegacyFallback = true
Config.AdminPermissions = {
    panel      = 'house.admin.open',
    create     = 'house.create',
    properties = 'house.admin.properties',
    interiors  = 'house.admin.interiors',
    garages    = 'house.admin.garages',
    pricing    = 'house.admin.pricing',
    photos     = 'house.admin.photos',
    recovery   = 'house.admin.recovery',
}
Config.AdminAces = {
    panel      = 'cm-house.admin',
    create     = 'cm-house.create',
    properties = 'cm-house.admin.properties',
    interiors  = 'cm-house.admin.interiors',
    garages    = 'cm-house.admin.garages',
    pricing    = 'cm-house.admin.pricing',
    photos     = 'cm-house.admin.photos',
    recovery   = 'cm-house.admin.recovery',
}

Config.WeaponStorage = {
    slots = 60,
    ownerType = 'house_weapon_storage',
    playerOwnerType = 'character',
    slotPrefix = 'weapon-',
    inventoryResource = 'cm-inventory',
    weaponsResource = 'cm-weapons',
    gunstoreResource = 'cm-gunstore',
    interactionDistance = 2.0,
    allowWeapons = true,
    allowAmmo = true,
    requireFullWeaponDurability = true,
    fullWeaponDurability = 100,
    stripWeaponSerialOnDeposit = true,
}

-- Real placement vehicles show whether the configured area actually fits.
Config.PlacementVehicles = {
    car = 'sultan',
    helicopter = 'frogger',
}


-- ============================================================
--  Garage templates
-- ============================================================
-- Garage capacity is always the number of physical placement cars saved in the
-- reusable template. Houses select an existing template; the house wizard never
-- creates or changes layouts.
Config.GarageTemplate = {
    maxVehicleExits = 8,
    maxVehicleSlots = 24,
    exitUseDistance = 1.35,
}

Config.DoorTargetRadius = 1.2
Config.GarageTargetRadius = 3.0
Config.HelipadTargetRadius = 5.0
Config.MaxLogRows      = 100         -- per page

-- Blip shown for every registered house
Config.HouseBlip = {
    sprite  = 40,
    scale   = 0.7,
    colorOwned    = 2,   -- green  (you own it / family house)
    colorForSale  = 3,   -- blue   (on the market)
    colorOther    = 4,   -- white  (someone else's)
    showOthers    = false, -- don't clutter the map with 500 blips
}

-- ============================================================
--  Rooms
--  Config only says WHERE a room is, so the wizard can teleport you there.
--  Everything INSIDE it -- spawn, exit, weapon lockers -- is walked once and saved
--  as a template. Nothing about a layout is hardcoded.
--
--  "Somewhere else" lets you type coordinates for any room not listed here,
--  so an MLO you install tomorrow needs no code change.
-- ============================================================
Config.Rooms = {
    { key='motel',    label='Motel Room',           teleport=vec4(152.11, -1004.32, -99.00, 165.0) },
    { key='apt_low',  label='Low-End Apartment',    teleport=vec4(265.97, -1007.10, -101.01, 356.0) },
    { key='apt_mid',  label='Mid-End Apartment',    teleport=vec4(347.30, -999.60, -99.20, 177.0) },
    { key='apt_high', label='High-End Apartment',   teleport=vec4(-30.80, -594.60, 79.03, 340.0),
      ipl='apa_v_mp_h_01_a' },
    { key='mansion',  label='Mansion',              teleport=vec4(-174.30, 497.20, 137.67, 122.0) },
}

Config.GarageRooms = {
    { key='g_small',  label='Small Garage',   teleport=vec4(174.00, -1004.10, -99.50, 180.0) },
    { key='g_med',    label='Medium Garage',  teleport=vec4(227.10, -998.10, -99.50, 180.0) },
    { key='g_large',  label='Large Garage',   teleport=vec4(-337.10, -132.60, 39.00, 250.0) },
}

-- ============================================================
--  Purchase
-- ============================================================
Config.Purchase = {
    account         = 'bank',
    -- Legacy rows sometimes had owner_cid = 0, which is TRUTHY in Lua, so an
    -- unowned house looked owned and never showed a Buy button. Migration 003
    -- repairs those rows; this relists anything that ends up ownerless.
    autoListUnowned = true,
    firstWeekFree   = true,
    reservationSeconds = 120, -- one buyer may reserve the property while payment finalizes
}

-- ============================================================
--  Property photos
--
--  screenshot-basic writes each approved capture directly into this resource:
--      cm-house/html/img/houses/house_<propertyId>.jpg
--
--  No webhook or remote image host is used. Keep this folder when replacing
--  the resource, otherwise previously captured property photos will be lost.
-- ============================================================
Config.Photo = {
    quality = 0.84,    -- 0.1 - 1.0; keeps locally streamed door images compact
    directory = 'html/img/houses',
    pendingMinutes = 20,
    maxBytes = 1572864,       -- maximum door-photo file size returned to NUI
    requestWindowMs = 5000,   -- photo read rate-limit window per player
    requestsPerWindow = 4,
    cacheEntries = 12,        -- server-side base64 cache
}

-- ============================================================
--  Family
--  cm-family is optional but authorization-sensitive. Every family check
--  fails closed when it is stopped, missing, errors, or returns anything other
--  than true. It integrates through the explicit imports below.
-- ============================================================
Config.Family = {
    -- Keep this enabled. When cm-family is not running every family check
    -- fails closed, so the legal house owner remains the only player with
    -- gameplay access.
    enabled = true,
    resource = 'cm-family',
    permissionExport = 'HasHousePermission',
    legacyPermissionExport = 'HasPermission',
    getFamilyExport = 'GetFamilyById',
    getFamilyForCharacterExport = 'GetFamilyForCharacter',
    getMemberCharacterIdsExport = 'GetFamilyMemberCharacterIds',
}

-- Gameplay access is intentionally strict. Old key/guest rows may remain in
-- the database for future invitation systems, but they do not grant entry,
-- garage, weapon-storage or general-storage access unless explicitly enabled here.
Config.Access = {
    allowKeys = false,
    allowGuests = false,
    allowStaffGameplayOverride = false,
}

-- ============================================================
--  Cross-resource integration permissions
--
--  Read-only exports are available to other server resources. Any export that
--  changes access, family links, garage assignments or recovery state checks
--  this scoped allowlist. Add future CM resources here deliberately rather
--  than making writable exports globally callable.
-- ============================================================
Config.Integration = {
    authorizedResources = {
        ['cm-admin'] = {
            admin = true, access = true, family = true,
            garage = true, recovery = true, weaponStorage = true,
        },
        ['cm-family'] = {
            access = true, family = true, garage = true, weaponStorage = true,
        },
        ['cm-vehicles'] = {
            garage = true, recovery = true,
        },
    },
}

-- ============================================================
--  Door prompt
--  A plain on-screen [E] prompt, not an ox_target zone. A box zone has to be
--  rotated to the door's heading, and if it is placed even slightly off it
--  never fires -- which is exactly what went wrong. Distance has no rotation
--  to get wrong.
-- ============================================================
Config.Prompt = {
    key        = 38,    -- INPUT_CONTEXT = E
    keyLabel   = 'E',
    distance   = 2.0,   -- how close before the prompt shows
    drawDist   = 15.0,  -- stop even checking beyond this
}

Config.HouseTypes = {
    { key = 'trailer',   label = 'Trailer' },
    { key = 'apartment', label = 'Apartment' },
    { key = 'house',     label = 'House' },
    { key = 'villa',     label = 'Villa' },
    { key = 'mansion',   label = 'Mansion' },
}

-- ============================================================
--  Family permissions
--  Single source of truth. The NUI rank editor renders from this,
--  and the server validates rank JSON against it.
-- ============================================================
Config.Permissions = {
    { key = 'door.enter',           label = 'Enter the house',            group = 'Access' },
    { key = 'door.lock',            label = 'Lock and unlock the door',   group = 'Access' },
    { key = 'keys.grant',           label = 'Give house keys to others',  group = 'Access' },

    { key = 'garage.access',        label = 'Enter and view the garage',  group = 'Garage' },
    { key = 'garage.take',          label = 'Take cars from the garage',  group = 'Garage' },
    { key = 'garage.store',         label = 'Store cars in the garage',   group = 'Garage' },
    { key = 'garage.take_any',      label = 'Take any car, not just family cars', group = 'Garage' },
    { key = 'garage.manage_shared', label = 'Choose which cars the family can use', group = 'Garage' },
    { key = 'helipad.use',          label = 'Use the helipad',            group = 'Garage' },

    { key = 'weapon_storage.access',   label = 'Open property weapon storage', group = 'Storage' },
    { key = 'weapon_storage.deposit',  label = 'Store weapons and ammunition', group = 'Storage' },
    { key = 'weapon_storage.withdraw', label = 'Take weapons and ammunition',  group = 'Storage' },
    { key = 'storage.access',          label = 'Open general property storage', group = 'Storage' },
    { key = 'trunk.access',         label = 'Open family car trunks',     group = 'Storage' },

    { key = 'family.invite',        label = 'Invite new members',         group = 'Family' },
    { key = 'family.kick',          label = 'Remove members',             group = 'Family' },
    { key = 'family.ranks',         label = 'Create and edit ranks',      group = 'Family' },
    { key = 'family.logs',          label = 'Read the activity log',      group = 'Family' },
}

-- Fast lookup set, built once
Config.PermissionSet = {}
for _, p in ipairs(Config.Permissions) do
    Config.PermissionSet[p.key] = true
end

-- Owner-only. Cannot be granted to any rank, ever.
Config.OwnerOnly = {
    ['house.sell']     = true,
    ['family.disband'] = true,
}

-- Ranks every new family starts with. Grade 0 is always the owner and
-- implicitly holds every permission -- its perms table is never read.
Config.DefaultRanks = {
    { name = 'Head',    grade = 0, perms = {} },
    {
        name = 'Underboss', grade = 1,
        perms = {
            ['door.enter'] = true, ['door.lock'] = true, ['keys.grant'] = true,
            ['garage.access'] = true, ['garage.take'] = true, ['garage.store'] = true, ['garage.take_any'] = true,
            ['garage.manage_shared'] = true, ['helipad.use'] = true,
            ['weapon_storage.access'] = true, ['weapon_storage.deposit'] = true, ['weapon_storage.withdraw'] = true,
            ['storage.access'] = true, ['trunk.access'] = true,
            ['family.invite'] = true, ['family.kick'] = true, ['family.logs'] = true,
        },
    },
    {
        name = 'Soldier', grade = 2,
        perms = {
            ['door.enter'] = true, ['door.lock'] = true,
            ['garage.access'] = true, ['garage.take'] = true, ['garage.store'] = true,
            ['weapon_storage.access'] = true, ['weapon_storage.deposit'] = true, ['weapon_storage.withdraw'] = true,
            ['storage.access'] = true, ['trunk.access'] = true,
            ['family.logs'] = true,
        },
    },
    {
        name = 'Associate', grade = 3,
        perms = {
            ['door.enter'] = true,
            ['weapon_storage.access'] = true, ['weapon_storage.deposit'] = true,
            ['storage.access'] = true,
        },
    },
}
Config.DefaultJoinGrade = 3   -- new invitees land here

-- ============================================================
--  Upkeep / status
-- ============================================================
Config.Upkeep = {
    hour            = 0,     -- server-time hour to run the daily charge
    graceDays       = 7,     -- days overdue before repossession is allowed
    -- Star rating from days-paid-ahead. Evaluated top-down, first match wins.
    stars = {
        { minDays =  7, stars = 5 },
        { minDays =  3, stars = 4 },
        { minDays =  1, stars = 3 },
        { minDays =  0, stars = 2 },
        { minDays = -3, stars = 1 },
        { minDays = -math.huge, stars = 0 },
    },
}

function Config.StarsFor(daysRemaining)
    for _, t in ipairs(Config.Upkeep.stars) do
        if daysRemaining >= t.minDays then return t.stars end
    end
    return 0
end

-- Log actions -> human labels for the NUI log viewer
Config.LogLabels = {
    house_create    = 'House created',
    house_buy       = 'House purchased',
    house_sell      = 'House sold',
    door_lock       = 'Door locked',
    door_unlock     = 'Door unlocked',
    garage_take     = 'Car taken',
    garage_store    = 'Car stored',
    garage_share    = 'Family car flag changed',
    heli_take       = 'Helicopter taken',
    heli_store      = 'Helicopter stored',
    weapon_storage_open     = 'Weapon storage opened',
    weapon_storage_withdraw = 'Weapon or ammunition withdrawn',
    weapon_storage_deposit  = 'Weapon or ammunition stored',
    trunk_access    = 'Trunk opened',
    key_grant       = 'Key given',
    key_revoke      = 'Key taken back',
    family_create   = 'Family founded',
    family_invite   = 'Member invited',
    family_join     = 'Member joined',
    family_kick     = 'Member removed',
    family_leave    = 'Member left',
    rank_create     = 'Rank created',
    rank_edit       = 'Rank changed',
    rank_delete     = 'Rank deleted',
    rank_assign     = 'Member reassigned',
    upkeep_paid     = 'Upkeep paid',
    upkeep_missed   = 'Upkeep missed',
}
