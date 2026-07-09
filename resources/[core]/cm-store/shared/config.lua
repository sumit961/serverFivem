Config = Config or {}

Config.Debug = false
Config.Framework = 'cm-core'
Config.Inventory = 'cm-inventory'
Config.ItemsResource = 'cm-items'
Config.PurchaseDistance = 15.0 -- server-side distance check before a buy can complete

-- Debug/test commands stay disabled in production.
Config.EnableDebugCommand = false
Config.DebugCommand = 'storetargetdebug'

-- Command for admin catalog management.
Config.AdminCommand = 'storeadmin'

-- Permission used before opening the admin UI.
-- Add to server.cfg later when you lock admin tools:
-- add_ace group.admin cm.store.admin allow
Config.AdminAce = 'cm.store.admin'

Config.Target = {
    enabled = false, -- disabled: gunstore uses custom screen interaction + E key, not ox_target.
    resource = 'ox_target',
    distance = 2.4,
    zoneRadius = 1.35, -- backup target zone around NPC, fixes raycast/interior issues
    debugZones = false,
    iconStore = 'fa-solid fa-store',
    iconAdmin = 'fa-solid fa-screwdriver-wrench',
    labelStore = 'Talk to clerk',
    labelAdmin = 'Store Admin'
}

Config.Interact = {
    distance = 2.2,
    markerDistance = 18.0,
    markerType = 2,
    drawMarker = false, -- NPC interaction is cleaner than ground markers.
    key = 38, -- E
    prompt = 'Press ~INPUT_CONTEXT~ to open Store',
    title = 'Talk to Clerk',
    subtitle = 'Browse items for sale',
    keyLabel = 'E'
}

Config.Ped = {
    enabled = true,
    model = 'mp_m_shopkeep_01',
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

-- 24/7 / LTD convenience-store locations (separate from the gun stores).
-- pedCoords = where the clerk stands behind the counter (vec4 = x,y,z,heading).
Config.Shops = {
    { -- Innocence Blvd, Strawberry (24/7)
        label = 'Store',
        coords = vec3(24.5, -1346.6, 29.5),
        pedCoords = vec4(25.7, -1347.3, 29.5, 270.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    { -- Little Seoul (LTD)
        label = 'Store',
        coords = vec3(-48.2, -1758.0, 29.42),
        pedCoords = vec4(-47.02, -1757.51, 29.42, 51.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    { -- Prosperity St, Vinewood (LTD)
        label = 'Store',
        coords = vec3(-1486.4, -378.6, 40.16),
        pedCoords = vec4(-1487.55, -379.14, 40.16, 133.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    { -- Sandy Shores (24/7)
        label = 'Store',
        coords = vec3(1960.2, 3740.5, 32.34),
        pedCoords = vec4(1961.48, 3740.24, 32.34, 300.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    { -- Grapeseed (24/7)
        label = 'Store',
        coords = vec3(1729.5, 6415.0, 35.03),
        pedCoords = vec4(1728.66, 6414.16, 35.03, 242.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    }
}

-- Item definitions (label, image, weight, use action, drop prop) live in cm-items.
-- cm-store only stores which items are for sale + price / stock / category / visibility.
-- Category tabs shown in the store UI. 'all' is always added by the client.
Config.Categories = {
    { id = 'consumable', label = 'Consumables' },
    { id = 'tool',       label = 'Tools' },
    { id = 'material',   label = 'Materials' },
    { id = 'misc',       label = 'Misc' },
}

-- ============================================================
-- HARD-CODED STORE CATALOG
-- The store is defined here in code. There is no admin "add item" UI.
-- On start, each entry is created as a cm-items definition (so it can be given,
-- dropped with a prop, and used) and shown in the store for sale.
--
-- Fields: name (id), label, category, price, weight(g), usable, stock (-1 = unlimited),
--         image (optional filename/nui path), description (optional).
-- What an item DOES when used is defined in code (cm-itemactions / the owning
-- resource), keyed by name -- never here.
-- ============================================================
Config.Catalog = {
    { name = 'sim_card',       label = 'SIM Card',            category = 'misc',       price = 250,   weight = 10 },
    { name = 'map_ls',         label = 'Map of Los Santos',   category = 'misc',       price = 1450,  weight = 50 },
    { name = 'cigarettes',     label = 'Cigarettes',          category = 'consumable', price = 450,   weight = 20,   usable = true },
    { name = 'crowbar',        label = 'Crowbar',             category = 'tool',       price = 1500,  weight = 1500, usable = true },
    { name = 'pickaxe_1',      label = 'Level 1 Pickaxe',     category = 'tool',       price = 2500,  weight = 2000, usable = true },
    { name = 'pickaxe_2',      label = 'Level 2 Pickaxe',     category = 'tool',       price = 10000, weight = 2000, usable = true },
    { name = 'red_fabric',     label = 'Red Fabric',          category = 'material',   price = 250,   weight = 100 },
    { name = 'blue_fabric',    label = 'Blue Fabric',         category = 'material',   price = 250,   weight = 100 },
    { name = 'yellow_fabric',  label = 'Yellow Fabric',       category = 'material',   price = 250,   weight = 100 },
    { name = 'green_fabric',   label = 'Green Fabric',        category = 'material',   price = 250,   weight = 100 },
    { name = 'purple_fabric',  label = 'Purple Fabric',       category = 'material',   price = 250,   weight = 100 },
    { name = 'tent',           label = 'Tent',                category = 'tool',       price = 1250,  weight = 3000, usable = true },
    { name = 'campfire',       label = 'Campfire',            category = 'tool',       price = 750,   weight = 2500, usable = true },
    { name = 'fishing_rod_1',  label = 'Level 1 Fishing Rod', category = 'tool',       price = 2500,  weight = 1200, usable = true },
    { name = 'fishing_rod_2',  label = 'Level 2 Fishing Rod', category = 'tool',       price = 10000, weight = 1200, usable = true },
    { name = 'lottery_ticket', label = 'Regular Lottery Ticket', category = 'misc',    price = 10000, weight = 5,    usable = true },
    { name = 'single_firework',label = 'Single Fireworks',    category = 'misc',       price = 1250,  weight = 500,  usable = true },
    { name = 'big_firework',   label = 'Big Fireworks',       category = 'misc',       price = 7500,  weight = 1500, usable = true },
}
