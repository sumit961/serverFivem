Config = Config or {}

Config.Debug = false
Config.Framework = 'cm-core'
Config.Inventory = 'cm-inventory'
Config.ItemsResource = 'cm-items'
Config.PurchaseDistance = 15.0 -- server-side distance check before an order can complete

Config.Accounts = {
    cash = 'cash',
    bank = 'bank'
}

Config.Interact = {
    distance = 2.4,
    markerDistance = 18.0,
    markerType = 2,
    drawMarker = false,
    key = 38, -- E
    prompt = 'Press ~INPUT_CONTEXT~ to talk to Store Clerk',
    title = 'CONVENIENCE STORE',
    subtitle = 'Talk to clerk / browse catalog',
    keyLabel = 'E'
}

Config.Ped = {
    enabled = true,
    model = 'mp_m_shopkeep_01',
    scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    shelfScenario = 'WORLD_HUMAN_CLIPBOARD',
    invincible = true,
    freeze = false,
    blockEvents = true,
    showName = true,
    nameHeight = 1.32,
    nameDistance = 7.0,
    storeRadius = 11.5,
    soundEnabled = true,
    voiceEnabled = true,
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
    greetings = {
        'SHOP_GREET',
        'GENERIC_HI',
        'GENERIC_HOWS_IT_GOING'
    },
    dialog = {
        title = 'Welcome to 24/7! How can I help you today?',
        optionCatalog = 'Browse Store Catalog',
        optionDeliver = "I'm here to deliver the stock",
        optionRob = 'Give me all your cash right now! [Rob Store]'
    }
}

-- ============================================================
-- STORE OWNERSHIP CONFIGURATION (Modeled after cm-gasstations)
-- ============================================================
Config.Ownership = {
    enabled = true,
    purchasePrice = 200000,       -- Bank cost to purchase an unowned store
    taxAmount = 12000,            -- Cost per 7-day tax renewal
    taxPeriodDays = 7,            -- 7 days between tax cycles
    ownerRevenuePercent = 80,     -- 80% of sales goes to owner's business balance; 20% city fee
    defaultStock = 1000,          -- Initial stock when newly established
    maxStock = 5000,              -- Standard maximum inventory units
    overstockLimit = 8000,        -- Maximum units allowed via overstock delivery
    restockBatch = 500,           -- Standard batch size
    restockUnitPrice = 6,         -- Cost per unit when under maxStock ($3,000 per 500 units)
    overstockUnitPrice = 8,       -- Premium cost per unit when overstocking ($4,000 per 500 units)
    priceTiers = {
        low = {
            multiplier = 0.85,
            label = 'LOW (-15%)',
            description = 'Discount pricing to attract more customers'
        },
        normal = {
            multiplier = 1.00,
            label = 'NORMAL (100%)',
            description = 'Standard city-regulated pricing'
        },
        high = {
            multiplier = 1.25,
            label = 'HIGH (+25%)',
            description = 'Premium markup for maximum profit'
        }
    }
}

-- 24/7 / LTD convenience-store locations
-- pedCoords = where the clerk stands behind the counter (vec4 = x,y,z,heading).
Config.Shops = {
    {
        id = 1,
        name = 'Strawberry 24/7',
        label = '24/7 Supermarket',
        coords = vec3(27.0, -1346.0, 29.5),
        registerCoords = vec3(25.4, -1347.0, 29.5),
        pedCoords = vec4(24.5, -1347.0, 29.5, 270.0),
        counterOpening = vec3(24.6, -1344.2, 29.5),
        counterOpeningAisle = vec3(26.4, -1344.2, 29.5),
        counterOpeningBehind = vec3(24.6, -1344.2, 29.5),
        shelfStations = {
            { coords = vec4(27.0, -1345.5, 29.5, 180.0), scenario = 'WORLD_HUMAN_STAND_MOBILE', behindCounter = false }, -- Main aisle on phone
            { coords = vec4(28.0, -1346.5, 29.5, 90.0),  scenario = 'WORLD_HUMAN_CLIPBOARD',    behindCounter = false }, -- Grocery shelves checking stock
            { coords = vec4(29.4, -1343.5, 29.5, 0.0),   scenario = 'WORLD_HUMAN_STAND_MOBILE', behindCounter = false }, -- Drink coolers checking phone
            { coords = vec4(28.0, -1344.0, 29.5, 270.0), scenario = 'WORLD_HUMAN_CLIPBOARD',    behindCounter = false }, -- Center snack display with clipboard
            { coords = vec4(29.4, -1346.5, 29.5, 90.0),  scenario = 'WORLD_HUMAN_STAND_MOBILE', behindCounter = false }, -- Side shelf checking phone
        },
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    {
        id = 2,
        name = 'Little Seoul LTD',
        label = 'LTD Gasoline Store',
        coords = vec3(-48.2, -1758.0, 29.42),
        pedCoords = vec4(-47.02, -1757.51, 29.42, 51.0),
        shelfCoords = vec4(-45.8, -1754.6, 29.42, 230.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    {
        id = 3,
        name = 'Vinewood LTD',
        label = 'LTD Gasoline Store',
        coords = vec3(-1486.4, -378.6, 40.16),
        pedCoords = vec4(-1487.55, -379.14, 40.16, 133.0),
        shelfCoords = vec4(-1484.8, -377.2, 40.16, 315.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    {
        id = 4,
        name = 'Sandy Shores 24/7',
        label = '24/7 Supermarket',
        coords = vec3(1960.2, 3740.5, 32.34),
        pedCoords = vec4(1961.48, 3740.24, 32.34, 300.0),
        shelfCoords = vec4(1958.5, 3741.2, 32.34, 120.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    },
    {
        id = 5,
        name = 'Grapeseed 24/7',
        label = '24/7 Supermarket',
        coords = vec3(1729.5, 6415.0, 35.03),
        pedCoords = vec4(1728.66, 6414.16, 35.03, 242.0),
        shelfCoords = vec4(1732.2, 6414.8, 35.03, 60.0),
        blip = { sprite = 52, color = 2, scale = 0.7 }
    }
}

Config.Categories = {
    { id = 'consumable', label = 'Food & Drinks' },
    { id = 'tool',       label = 'Tools & Gear' },
    { id = 'fishing',    label = 'Fishing Supply' },
    { id = 'material',   label = 'Materials' },
    { id = 'misc',       label = 'General / Misc' }
}

-- ============================================================
-- AUTHORITATIVE STORE CATALOG
-- ============================================================
Config.Catalog = {
    -- Food & Drinks
    {
        name = 'water',
        label = 'Water Bottle',
        category = 'consumable',
        price = 15,
        weight = 500,
        usable = true,
        image = 'nui://cm-inventory/ui/images/water.png',
        description = 'A refreshing bottle of clean spring water.'
    },
    {
        name = 'sandwich',
        label = 'Sandwich',
        category = 'consumable',
        price = 25,
        weight = 350,
        usable = true,
        image = 'nui://cm-inventory/ui/images/sandwich.png',
        description = 'Freshly made packaged deli sandwich.'
    },
    {
        name = 'cigarettes',
        label = 'Cigarettes',
        category = 'consumable',
        price = 450,
        weight = 20,
        usable = true,
        description = 'A pack of Redwood brand cigarettes.'
    },

    -- Fishing (from cm-fishing)
    {
        name = 'basic_rod',
        label = 'Basic Fishing Rod',
        category = 'fishing',
        price = 50,
        weight = 1800,
        usable = false,
        image = 'nui://cm-fishing/ui/images/basic_rod.png',
        description = 'A reliable starter fishing rod. Never breaks.'
    },
    {
        name = 'rod_2',
        label = 'Fishing Rod Level 2',
        category = 'fishing',
        price = 100,
        weight = 1800,
        usable = false,
        image = 'nui://cm-fishing/ui/images/rod_2.png',
        description = 'Shortens the wait for a bite. Never breaks.'
    },
    {
        name = 'rod_3',
        label = 'Fishing Rod Level 3',
        category = 'fishing',
        price = 150,
        weight = 1800,
        usable = false,
        image = 'nui://cm-fishing/ui/images/rod_3.png',
        description = 'The fastest bites in the game. Never breaks.'
    },
    {
        name = 'worms',
        label = 'Worms (Bait)',
        category = 'fishing',
        price = 5,
        weight = 60,
        usable = false,
        image = 'nui://cm-fishing/ui/images/worms.png',
        description = 'Cheap and reliable live bait for ocean and river fishing.'
    },
    {
        name = 'commonbait',
        label = 'Common Bait',
        category = 'fishing',
        price = 10,
        weight = 60,
        usable = false,
        image = 'nui://cm-fishing/ui/images/commonbait.png',
        description = 'Faster bites and noticeably better odds at Rare+ fish.'
    },
    {
        name = 'artificial_bait',
        label = 'Artificial Bait',
        category = 'fishing',
        price = 15,
        weight = 60,
        usable = false,
        image = 'nui://cm-fishing/ui/images/artificial_bait.png',
        description = 'Top tier lure with highest bite rate and rare fish attraction.'
    },

    -- Tools & Gear
    {
        name = 'crowbar',
        label = 'Crowbar',
        category = 'tool',
        price = 1500,
        weight = 1500,
        usable = true,
        description = 'Heavy-duty steel crowbar for prying and salvage.'
    },
    {
        name = 'pickaxe_1',
        label = 'Level 1 Pickaxe',
        category = 'tool',
        price = 2500,
        weight = 2000,
        usable = true,
        description = 'Standard mining pickaxe suitable for surface ore.'
    },
    {
        name = 'pickaxe_2',
        label = 'Level 2 Pickaxe',
        category = 'tool',
        price = 10000,
        weight = 2000,
        usable = true,
        description = 'Tempered steel pickaxe for deep mining veins.'
    },
    {
        name = 'tent',
        label = 'Camping Tent',
        category = 'tool',
        price = 1250,
        weight = 3000,
        usable = true,
        description = 'Foldable waterproof shelter for wilderness camping.'
    },
    {
        name = 'campfire',
        label = 'Campfire Kit',
        category = 'tool',
        price = 750,
        weight = 2500,
        usable = true,
        description = 'Portable wood and tinder campfire setup.'
    },

    -- Materials
    {
        name = 'red_fabric',
        label = 'Red Fabric',
        category = 'material',
        price = 250,
        weight = 100,
        description = 'Roll of high quality dyed red fabric.'
    },
    {
        name = 'blue_fabric',
        label = 'Blue Fabric',
        category = 'material',
        price = 250,
        weight = 100,
        description = 'Roll of high quality dyed blue fabric.'
    },
    {
        name = 'yellow_fabric',
        label = 'Yellow Fabric',
        category = 'material',
        price = 250,
        weight = 100,
        description = 'Roll of high quality dyed yellow fabric.'
    },
    {
        name = 'green_fabric',
        label = 'Green Fabric',
        category = 'material',
        price = 250,
        weight = 100,
        description = 'Roll of high quality dyed green fabric.'
    },
    {
        name = 'purple_fabric',
        label = 'Purple Fabric',
        category = 'material',
        price = 250,
        weight = 100,
        description = 'Roll of high quality dyed purple fabric.'
    },

    -- General & Misc
    {
        name = 'sim_card',
        label = 'SIM Card',
        category = 'misc',
        price = 250,
        weight = 10,
        description = 'Prepaid cellular SIM card for mobile communication.'
    },
    {
        name = 'map_ls',
        label = 'Map of Los Santos',
        category = 'misc',
        price = 1450,
        weight = 50,
        description = 'Detailed cartographic street map of Los Santos.'
    },
    {
        name = 'lottery_ticket',
        label = 'Regular Lottery Ticket',
        category = 'misc',
        price = 10000,
        weight = 5,
        usable = true,
        description = 'San Andreas State instant scratch-off lottery ticket.'
    },
    {
        name = 'single_firework',
        label = 'Single Fireworks',
        category = 'misc',
        price = 1250,
        weight = 500,
        usable = true,
        description = 'Single aerial rocket firework.'
    },
    {
        name = 'big_firework',
        label = 'Big Fireworks',
        category = 'misc',
        price = 7500,
        weight = 1500,
        usable = true,
        description = 'Multi-shot celebratory fireworks box.'
    }
}
