Config = Config or {}

Config.Debug = false
Config.Framework = 'cm-core'
Config.Inventory = 'cm-inventory'
Config.WeaponsResource = 'cm-weapons'
Config.ItemsResource = 'cm-items'
Config.PurchaseDistance = 15.0 -- server-side distance check before a buy can complete

Config.EnableDebugCommand = false
Config.DebugCommand = 'guntargetdebug'
Config.AdminCommand = 'gunadmin'
Config.AdminAce = 'cm.gunstore.admin'

-- Price mode is config-only. /gunadmin can only set stock and Store/Hidden.
Config.PriceMode = 'config'
Config.RequireStoreConfigPrice = true
Config.SyncConfigCatalogOnStart = true
-- Store catalog is config-owned. On sync, old DB rows not listed here are hidden,
-- and stock/enabled are forced from Config.StoreCatalog so the player store never shows stale ammo-only rows.
Config.StrictStoreCatalog = true
Config.ForceConfigStockEnabled = true
Config.AmmoQuantity = { min = 1, max = 999, default = 1 }

Config.Target = {
    enabled = false, -- disabled: gunstore uses custom screen interaction + E key, not ox_target.
    resource = 'ox_target',
    distance = 2.4,
    zoneRadius = 1.35, -- backup target zone around NPC, fixes raycast/interior issues
    debugZones = false,
    iconStore = 'fa-solid fa-gun',
    iconAdmin = 'fa-solid fa-screwdriver-wrench',
    labelStore = 'Talk to clerk',
    labelAdmin = 'Gun Store Admin'
}

Config.Interact = {
    distance = 2.2,
    markerDistance = 18.0,
    markerType = 2,
    drawMarker = false, -- NPC interaction is cleaner than ground markers.
    key = 38, -- E
    prompt = 'Press ~INPUT_CONTEXT~ to open Gun Store',
    title = 'Talk to Clerk',
    subtitle = 'Browse weapons, ammo, and armor',
    keyLabel = 'E'
}

Config.Ped = {
    enabled = true,
    model = 's_m_y_ammucity_01',
    scenario = 'WORLD_HUMAN_GUARD_STAND',
    invincible = true,
    freeze = true,
    blockEvents = true,

    -- Text/voice speech settings.
    -- Custom dialog text is drawn above the NPC. GTA native voice barks are played
    -- at the same time because FiveM cannot voice arbitrary custom sentences.
    voiceEnabled = true,
    greetingVoices = { 'GENERIC_HI', 'GENERIC_HOWS_IT_GOING', 'SHOP_GREET' },
    farewellVoices = { 'GENERIC_BYE', 'GENERIC_THANKS', 'SHOP_GOODBYE' },
    speechBackground = true,

    -- Names are picked randomly for each NPC when the resource starts.
    showName = true,
    nameHeight = 1.32,
    nameDistance = 7.0,
    names = {
        'Marcus Reed',
        'Calvin Brooks',
        'Eddie Knox',
        'Victor Hale',
        'Derek Stone',
        'Liam Carter',
        'Ray Morgan',
        'Noah Briggs'
    },

    -- Random speech shown above the NPC when a player walks close.
    speechDistance = 6.0,
    speechDuration = 5500,
    speechCooldown = 15000,
    greetings = {
        'Welcome in. Looking for something reliable?',
        'Evening. Take your time and have a look.',
        'Need protection, or just browsing?',
        'Fresh stock came in today.',
        'Tell me what you need and I will sort you out.'
    },
    farewells = {
        'Alright, see you around.',
        'No worries. Come back anytime.',
        'Stay safe out there.',
        'Okay, maybe next time.',
        'Take care.'
    },

    dialog = {
        title = 'How can I help you today?',
        optionStore = 'Show me the catalog',
        optionClose = 'Maybe later'
    }
}

Config.Accounts = {
    cash = 'cash',
    bank = 'bank'
}

-- Ammu-Nation style shop locations. Add/remove as needed.
Config.Shops = {
    {
        label = 'Gun Store',
        coords = vec3(22.03, -1107.17, 29.80),
        pedCoords = vec4(22.66, -1105.31, 29.80, 155.0),
        blip = { sprite = 110, color = 1, scale = 0.65 }
    },
    {
        label = 'Gun Store',
        coords = vec3(252.30, -50.00, 69.94),
        pedCoords = vec4(253.54, -51.67, 69.94, 72.0),
        blip = { sprite = 110, color = 1, scale = 0.65 }
    },
    {
        label = 'Gun Store',
        coords = vec3(842.11, -1035.37, 28.19),
        pedCoords = vec4(841.68, -1035.33, 28.19, 0.0),
        blip = { sprite = 110, color = 1, scale = 0.65 }
    },
    {
        label = 'Gun Store',
        coords = vec3(-331.62, 6083.57, 31.45),
        pedCoords = vec4(-331.41, 6085.35, 31.45, 225.0),
        blip = { sprite = 110, color = 1, scale = 0.65 }
    },
    {
        label = 'Gun Store',
        coords = vec3(-662.14, -935.64, 21.83),
        pedCoords = vec4(-661.90, -933.50, 21.83, 180.0),
        blip = { sprite = 110, color = 1, scale = 0.65 }
    }
}

-- Store catalog is the only place for gun-store prices. Prices below are unit prices.
-- Ammo price is per 1 round because cm-weapons packSize is 1.
Config.StoreCatalog = {
    { itemType = 'ammo', itemName = 'ammo_9mm', price = 30, stock = -1, enabled = true, sortOrder = 1 },
    { itemType = 'ammo', itemName = 'ammo_44magnum', price = 90, stock = -1, enabled = true, sortOrder = 2 },
    { itemType = 'ammo', itemName = 'ammo_9x19_smg', price = 40, stock = -1, enabled = true, sortOrder = 3 },
    { itemType = 'ammo', itemName = 'ammo_556nato', price = 80, stock = -1, enabled = true, sortOrder = 4 },
    { itemType = 'ammo', itemName = 'ammo_762nato', price = 110, stock = -1, enabled = true, sortOrder = 5 },
    { itemType = 'ammo', itemName = 'ammo_12gauge', price = 70, stock = -1, enabled = true, sortOrder = 6 },
    { itemType = 'ammo', itemName = 'ammo_308win', price = 160, stock = -1, enabled = true, sortOrder = 7 },
    { itemType = 'weapon', itemName = 'weapon_pistol', price = 2500, stock = -1, enabled = true, sortOrder = 8 },
    { itemType = 'weapon', itemName = 'weapon_pistol_mk2', price = 3500, stock = -1, enabled = true, sortOrder = 9 },
    { itemType = 'weapon', itemName = 'weapon_combatpistol', price = 3200, stock = -1, enabled = true, sortOrder = 10 },
    { itemType = 'weapon', itemName = 'weapon_appistol', price = 3500, stock = -1, enabled = true, sortOrder = 11 },
    { itemType = 'weapon', itemName = 'weapon_pistol50', price = 3500, stock = -1, enabled = true, sortOrder = 12 },
    { itemType = 'weapon', itemName = 'weapon_snspistol', price = 1800, stock = -1, enabled = true, sortOrder = 13 },
    { itemType = 'weapon', itemName = 'weapon_snspistol_mk2', price = 3500, stock = -1, enabled = true, sortOrder = 14 },
    { itemType = 'weapon', itemName = 'weapon_heavypistol', price = 3500, stock = -1, enabled = true, sortOrder = 15 },
    { itemType = 'weapon', itemName = 'weapon_vintagepistol', price = 3500, stock = -1, enabled = true, sortOrder = 16 },
    { itemType = 'weapon', itemName = 'weapon_ceramicpistol', price = 3500, stock = -1, enabled = true, sortOrder = 17 },
    { itemType = 'weapon', itemName = 'weapon_marksmanpistol', price = 9000, stock = -1, enabled = true, sortOrder = 18 },
    { itemType = 'weapon', itemName = 'weapon_revolver', price = 8500, stock = -1, enabled = true, sortOrder = 19 },
    { itemType = 'weapon', itemName = 'weapon_revolver_mk2', price = 12000, stock = -1, enabled = true, sortOrder = 20 },
    { itemType = 'weapon', itemName = 'weapon_doubleaction', price = 3500, stock = -1, enabled = true, sortOrder = 21 },
    { itemType = 'weapon', itemName = 'weapon_navyrevolver', price = 3500, stock = -1, enabled = true, sortOrder = 22 },
    { itemType = 'weapon', itemName = 'weapon_gadgetpistol', price = 3500, stock = -1, enabled = true, sortOrder = 23 },
    { itemType = 'weapon', itemName = 'weapon_pistolxm3', price = 3500, stock = -1, enabled = true, sortOrder = 24 },
    { itemType = 'weapon', itemName = 'weapon_microsmg', price = 12000, stock = -1, enabled = true, sortOrder = 25 },
    { itemType = 'weapon', itemName = 'weapon_smg', price = 12000, stock = -1, enabled = true, sortOrder = 26 },
    { itemType = 'weapon', itemName = 'weapon_smg_mk2', price = 12000, stock = -1, enabled = true, sortOrder = 27 },
    { itemType = 'weapon', itemName = 'weapon_assaultsmg', price = 12000, stock = -1, enabled = true, sortOrder = 28 },
    { itemType = 'weapon', itemName = 'weapon_combatpdw', price = 12000, stock = -1, enabled = true, sortOrder = 29 },
    { itemType = 'weapon', itemName = 'weapon_machinepistol', price = 12000, stock = -1, enabled = true, sortOrder = 30 },
    { itemType = 'weapon', itemName = 'weapon_minismg', price = 12000, stock = -1, enabled = true, sortOrder = 31 },
    { itemType = 'weapon', itemName = 'weapon_tecpistol', price = 12000, stock = -1, enabled = true, sortOrder = 32 },
    { itemType = 'weapon', itemName = 'weapon_assaultrifle', price = 28000, stock = -1, enabled = true, sortOrder = 33 },
    { itemType = 'weapon', itemName = 'weapon_assaultrifle_mk2', price = 28000, stock = -1, enabled = true, sortOrder = 34 },
    { itemType = 'weapon', itemName = 'weapon_carbinerifle', price = 28000, stock = -1, enabled = true, sortOrder = 35 },
    { itemType = 'weapon', itemName = 'weapon_carbinerifle_mk2', price = 28000, stock = -1, enabled = true, sortOrder = 36 },
    { itemType = 'weapon', itemName = 'weapon_advancedrifle', price = 28000, stock = -1, enabled = true, sortOrder = 37 },
    { itemType = 'weapon', itemName = 'weapon_specialcarbine', price = 28000, stock = -1, enabled = true, sortOrder = 38 },
    { itemType = 'weapon', itemName = 'weapon_specialcarbine_mk2', price = 28000, stock = -1, enabled = true, sortOrder = 39 },
    { itemType = 'weapon', itemName = 'weapon_bullpuprifle', price = 28000, stock = -1, enabled = true, sortOrder = 40 },
    { itemType = 'weapon', itemName = 'weapon_bullpuprifle_mk2', price = 28000, stock = -1, enabled = true, sortOrder = 41 },
    { itemType = 'weapon', itemName = 'weapon_compactrifle', price = 28000, stock = -1, enabled = true, sortOrder = 42 },
    { itemType = 'weapon', itemName = 'weapon_militaryrifle', price = 28000, stock = -1, enabled = true, sortOrder = 43 },
    { itemType = 'weapon', itemName = 'weapon_heavyrifle', price = 28000, stock = -1, enabled = true, sortOrder = 44 },
    { itemType = 'weapon', itemName = 'weapon_battlerifle', price = 28000, stock = -1, enabled = true, sortOrder = 45 },
    { itemType = 'weapon', itemName = 'weapon_tacticalrifle', price = 28000, stock = -1, enabled = true, sortOrder = 46 },
    { itemType = 'weapon', itemName = 'weapon_pumpshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 47 },
    { itemType = 'weapon', itemName = 'weapon_pumpshotgun_mk2', price = 15000, stock = -1, enabled = true, sortOrder = 48 },
    { itemType = 'weapon', itemName = 'weapon_sawnoffshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 49 },
    { itemType = 'weapon', itemName = 'weapon_assaultshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 50 },
    { itemType = 'weapon', itemName = 'weapon_bullpupshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 51 },
    { itemType = 'weapon', itemName = 'weapon_heavyshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 52 },
    { itemType = 'weapon', itemName = 'weapon_dbshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 53 },
    { itemType = 'weapon', itemName = 'weapon_autoshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 54 },
    { itemType = 'weapon', itemName = 'weapon_combatshotgun', price = 15000, stock = -1, enabled = true, sortOrder = 55 },
    { itemType = 'weapon', itemName = 'weapon_sniperrifle', price = 55000, stock = -1, enabled = true, sortOrder = 56 },
    { itemType = 'weapon', itemName = 'weapon_heavysniper', price = 55000, stock = -1, enabled = true, sortOrder = 57 },
    { itemType = 'weapon', itemName = 'weapon_heavysniper_mk2', price = 55000, stock = -1, enabled = true, sortOrder = 58 },
    { itemType = 'weapon', itemName = 'weapon_marksmanrifle', price = 55000, stock = -1, enabled = true, sortOrder = 59 },
    { itemType = 'weapon', itemName = 'weapon_marksmanrifle_mk2', price = 55000, stock = -1, enabled = true, sortOrder = 60 },
    { itemType = 'weapon', itemName = 'weapon_precisionrifle', price = 55000, stock = -1, enabled = true, sortOrder = 61 },
    { itemType = 'weapon', itemName = 'weapon_mg', price = 70000, stock = -1, enabled = true, sortOrder = 62 },
    { itemType = 'weapon', itemName = 'weapon_combatmg', price = 70000, stock = -1, enabled = true, sortOrder = 63 },
    { itemType = 'weapon', itemName = 'weapon_combatmg_mk2', price = 70000, stock = -1, enabled = true, sortOrder = 64 },
    { itemType = 'weapon', itemName = 'weapon_gusenberg', price = 70000, stock = -1, enabled = true, sortOrder = 65 },
    { itemType = 'weapon', itemName = 'weapon_minigun', price = 250000, stock = -1, enabled = false, sortOrder = 66 },
    { itemName = 'armor_light', itemType = 'armor', price = 3500, stock = -1, enabled = true, sortOrder = 500 },
}

-- One default armor item. For custom vest images, keep using the clothing/vest capture flow in /gunadmin.
Config.DefaultArmor = {
    itemName = 'armor_light',
    label = 'Light Armor Vest',
    price = 3500,
    armorValue = 50,
    stock = -1,
    enabled = true,
    image = 'images/armor_light.svg',
    description = 'Standard light body armor vest.',
    componentId = 9,
    drawableId = nil,
    textureId = 0,
    gender = 'both',
    sortOrder = 500
}
