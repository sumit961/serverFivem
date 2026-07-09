Config = Config or {}

Config.Debug = false
Config.Framework = 'cm-core'
Config.Inventory = 'cm-inventory'
Config.WeaponsResource = 'cm-weapons'
Config.ItemsResource = 'cm-items'

-- Command for admin catalog management.
Config.AdminCommand = 'gunadmin'

-- Permission used before opening the admin UI.
-- Add to server.cfg later when you lock admin tools:
-- add_ace group.admin cm.gunstore.admin allow
Config.AdminAce = 'cm.gunstore.admin'

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

-- Legacy seed kept only for old installs. v1.2+ does not create weapons/ammo here.
-- Gun and ammo definitions are managed in cm-weapons (/cmweaponadmin).
-- Gun store only stores price/stock/visibility in cm_gun_catalog.
-- Catalog seed. Admin can enable/disable, change price, label, and image from /gunadmin.
-- IMPORTANT: cm-inventory or cm-items must know these item names. A patch file is included in install/.
Config.DefaultCatalog = {
    {
        item_name = 'weapon_pistol',
        item_type = 'weapon',
        label = 'Pistol',
        weapon_hash = 'WEAPON_PISTOL',
        ammo_item = 'ammo_9mm',
        price = 2500,
        enabled = true,
        image = 'nui://cm-gunstore/web/images/weapon_pistol.svg',
        sort_order = 10,
        description = 'Standard sidearm.'
    },
    {
        item_name = 'weapon_combatpistol',
        item_type = 'weapon',
        label = 'Combat Pistol',
        weapon_hash = 'WEAPON_COMBATPISTOL',
        ammo_item = 'ammo_9mm',
        price = 4200,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/weapon_combatpistol.svg',
        sort_order = 20,
        description = 'Compact combat sidearm.'
    },
    {
        item_name = 'weapon_appistol',
        item_type = 'weapon',
        label = 'AP Pistol',
        weapon_hash = 'WEAPON_APPISTOL',
        ammo_item = 'ammo_9mm',
        price = 6500,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/weapon_appistol.svg',
        sort_order = 30,
        description = 'Automatic pistol.'
    },
    {
        item_name = 'weapon_smg',
        item_type = 'weapon',
        label = 'SMG',
        weapon_hash = 'WEAPON_SMG',
        ammo_item = 'ammo_9mm',
        price = 9500,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/weapon_smg.svg',
        sort_order = 40,
        description = 'Compact submachine gun.'
    },
    {
        item_name = 'weapon_pumpshotgun',
        item_type = 'weapon',
        label = 'Pump Shotgun',
        weapon_hash = 'WEAPON_PUMPSHOTGUN',
        ammo_item = 'ammo_shotgun',
        price = 12500,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/weapon_pumpshotgun.svg',
        sort_order = 50,
        description = 'Pump-action shotgun.'
    },
    {
        item_name = 'weapon_carbinerifle',
        item_type = 'weapon',
        label = 'Carbine Rifle',
        weapon_hash = 'WEAPON_CARBINERIFLE',
        ammo_item = 'ammo_rifle',
        price = 18000,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/weapon_carbinerifle.svg',
        sort_order = 60,
        description = 'Rifle platform.'
    },

    {
        item_name = 'armor_light',
        item_type = 'armor',
        label = 'Light Armor Vest',
        weapon_hash = '',
        ammo_item = '',
        armor_value = 35,
        price = 1800,
        enabled = true,
        image = 'nui://cm-gunstore/web/images/armor_light.svg',
        sort_order = 200,
        description = 'Light protection vest. Adds 35 armor when used.'
    },
    {
        item_name = 'armor_heavy',
        item_type = 'armor',
        label = 'Heavy Armor Vest',
        weapon_hash = '',
        ammo_item = '',
        armor_value = 100,
        price = 4500,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/armor_heavy.svg',
        sort_order = 210,
        description = 'Heavy tactical vest. Adds 100 armor when used.'
    },
    {
        item_name = 'ammo_9mm',
        item_type = 'ammo',
        label = '9mm Ammo Box',
        weapon_hash = '',
        ammo_item = '',
        pack_size = 24,
        price = 240,
        enabled = true,
        image = 'nui://cm-gunstore/web/images/ammo_9mm.svg',
        sort_order = 100,
        description = 'Box of 24 rounds.'
    },
    {
        item_name = 'ammo_shotgun',
        item_type = 'ammo',
        label = 'Shotgun Shell Box',
        weapon_hash = '',
        ammo_item = '',
        pack_size = 12,
        price = 360,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/ammo_shotgun.svg',
        sort_order = 110,
        description = 'Box of 12 shells.'
    },
    {
        item_name = 'ammo_rifle',
        item_type = 'ammo',
        label = 'Rifle Ammo Box',
        weapon_hash = '',
        ammo_item = '',
        pack_size = 30,
        price = 600,
        enabled = false,
        image = 'nui://cm-gunstore/web/images/ammo_rifle.svg',
        sort_order = 120,
        description = 'Box of 30 rifle rounds.'
    }
}
