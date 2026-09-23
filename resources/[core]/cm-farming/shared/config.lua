CMFarming = CMFarming or {}

-- Every field currently allows every crop -- the 5 scouted Grapeseed
-- patches aren't split by crop type like the original 2-field placeholder
-- setup was.
local ALL_CROPS = { 'wheat', 'pumpkin', 'rose', 'green', 'daisy', 'poppy', 'melon', 'watermelon' }

CMFarming.Config = {
    Debug = false,

    interactKey = 38, -- E
    interactKeyLabel = 'E',
    interactDistance = 1.6,
    npcInteractDistance = 2.2,

    -- ==========================================================
    -- LEVELING
    -- Job level/xp is stored as cm-playerdata metadata, same as
    -- cm-fishing/cm-electrician. Only gates which seeds can be bought.
    -- ==========================================================
    LevelXP = {
        [0] = 0,
        [1] = 80,
        [2] = 220,
        [3] = 450,
        [4] = 800,
        [5] = 1300, -- max level
    },

    -- ==========================================================
    -- CROPS
    -- growModel is the world prop shown once a plot reaches 'grown'.
    -- Custom (non-vanilla) models are streamed by cm-farming-assets:
    -- prop_veg_crop_rose/green/daisy/poppy (.ydr), 0r_melon (.ydr),
    -- prop_veg_crop_03_cab (.yft, overrides the vanilla name on purpose).
    -- wheat/pumpkin use stock GTA props, no streaming needed.
    -- ==========================================================
    Crops = {
        wheat = {
            -- growModel was 'prop_veg_crop_06' -- that's one of GTA's
            -- wind-swayed procedural grass props, not a normal static prop,
            -- and renders distorted/oversized when force-spawned standalone
            -- via CreateObject instead of the game's own grass batch system.
            -- prop_haybale_03 is a guaranteed-static prop and still reads as
            -- "wheat, ready to harvest".
            label = 'Wheat', seedItem = 'wheat_seed', seedLabel = 'Wheat Seeds', cropItem = 'wheat',
            growModel = 'prop_haybale_03', growTimeSec = 240, harvestAmount = 3,
            seedPrice = 6, sellPrice = 14, xpReward = 8, requiredLevel = 0,
            description = 'A staple grain crop. Fast growing and always in demand.',
        },
        pumpkin = {
            label = 'Pumpkin', seedItem = 'pumpkin_seed', seedLabel = 'Pumpkin Seeds', cropItem = 'pumpkin',
            growModel = 'prop_veg_crop_03_pump', growTimeSec = 400, harvestAmount = 1,
            seedPrice = 11, sellPrice = 24, xpReward = 15, requiredLevel = 0,
            description = 'A single large pumpkin per plant. Sells well for the effort.',
        },
        rose = {
            label = 'Rose', seedItem = 'rose_seed', seedLabel = 'Rose Seeds', cropItem = 'rose',
            growModel = 'prop_veg_crop_rose', growTimeSec = 300, harvestAmount = 3,
            seedPrice = 8, sellPrice = 18, xpReward = 10, requiredLevel = 1,
            description = 'Ornamental flowers grown for the florist trade.',
        },
        green = {
            label = 'Green Bean', seedItem = 'green_seed', seedLabel = 'Green Bean Seeds', cropItem = 'green',
            growModel = 'prop_veg_crop_green', growTimeSec = 280, harvestAmount = 3,
            seedPrice = 7, sellPrice = 16, xpReward = 9, requiredLevel = 1,
            description = 'Hardy green vegetables, quick to bring to market.',
        },
        daisy = {
            label = 'Daisy', seedItem = 'daisy_seed', seedLabel = 'Daisy Seeds', cropItem = 'daisy',
            growModel = 'prop_veg_crop_daisy', growTimeSec = 260, harvestAmount = 3,
            seedPrice = 7, sellPrice = 15, xpReward = 9, requiredLevel = 1,
            description = 'Simple field flowers, cheap to plant and reliable to sell.',
        },
        poppy = {
            label = 'Poppy', seedItem = 'poppy_seed', seedLabel = 'Poppy Seeds', cropItem = 'poppy',
            growModel = 'prop_veg_crop_poppy', growTimeSec = 260, harvestAmount = 3,
            seedPrice = 7, sellPrice = 15, xpReward = 9, requiredLevel = 1,
            description = 'Bright field flowers popular with the florist trade.',
        },
        melon = {
            label = 'Melon', seedItem = 'melon_seed', seedLabel = 'Melon Seeds', cropItem = 'melon',
            growModel = '0r_melon', growTimeSec = 420, harvestAmount = 1,
            seedPrice = 12, sellPrice = 26, xpReward = 16, requiredLevel = 2,
            description = 'Slow growing but the best payout per plant of the basic crops.',
        },
        watermelon = {
            label = 'Watermelon', seedItem = 'watermelon_seed', seedLabel = 'Watermelon Seeds', cropItem = 'watermelon',
            growModel = 'prop_veg_crop_03_cab', growTimeSec = 420, harvestAmount = 1,
            seedPrice = 13, sellPrice = 28, xpReward = 16, requiredLevel = 2,
            description = 'A large, high-value melon crop for experienced farmers.',
        },
    },

    -- Shown on 'planted' and 'watered' plots, before the crop's own model
    -- takes over at 'grown'. Streamed by cm-farming-assets.
    SeedlingModel = '0r_sapling',

    -- ==========================================================
    -- FIELDS
    -- Plantable points are generated procedurally around `center`
    -- (expanding rings, `spacing` apart, rotated by `rotation`, capped
    -- at `maxPoints` and filtered to stay within `radius`) rather than
    -- hand-placed one at a time. Fields are open access -- any player
    -- can work any unclaimed plot, no party/lobby gating.
    -- ==========================================================
    -- Scouted with /farmzone (walked boundary, fitted circle) on the live
    -- server -- real locations, not guesses. maxPoints is sized roughly to
    -- radius at 5.0 spacing, capped at 60 so the biggest fields don't get
    -- absurdly dense.
    Fields = {
        {
            key = 'grapeseed_field_1',
            label = 'Grapeseed Field 1',
            center = vector3(2220.0193, 5064.8899, 57.5633),
            radius = 73.0,
            rotation = 0.0,
            spacing = 5.0,
            maxPoints = 60,
            allowedCrops = ALL_CROPS,
            blip = { enabled = true, sprite = 773, color = 2, scale = 0.8, name = 'Grapeseed Field 1' },
        },
        {
            key = 'grapeseed_field_2',
            label = 'Grapeseed Field 2',
            center = vector3(2153.2405, 5173.1189, 54.5872),
            radius = 69.0,
            rotation = 0.0,
            spacing = 5.0,
            maxPoints = 60,
            allowedCrops = ALL_CROPS,
            blip = { enabled = true, sprite = 773, color = 2, scale = 0.8, name = 'Grapeseed Field 2' },
        },
        {
            key = 'grapeseed_field_3',
            label = 'Grapeseed Field 3',
            center = vector3(2307.2183, 5129.4655, 48.5170),
            radius = 42.0,
            rotation = 0.0,
            spacing = 5.0,
            maxPoints = 50,
            allowedCrops = ALL_CROPS,
            blip = { enabled = true, sprite = 773, color = 2, scale = 0.8, name = 'Grapeseed Field 3' },
        },
        {
            key = 'grapeseed_field_4',
            label = 'Grapeseed Field 4',
            center = vector3(2539.7155, 4811.0988, 34.1704),
            radius = 45.0,
            rotation = 0.0,
            spacing = 5.0,
            maxPoints = 54,
            allowedCrops = ALL_CROPS,
            blip = { enabled = true, sprite = 773, color = 2, scale = 0.8, name = 'Grapeseed Field 4' },
        },
        {
            key = 'grapeseed_field_5',
            label = 'Grapeseed Field 5',
            center = vector3(2012.9591, 4897.5750, 48.0955),
            radius = 48.0,
            rotation = 0.0,
            spacing = 5.0,
            maxPoints = 58,
            allowedCrops = ALL_CROPS,
            blip = { enabled = true, sprite = 773, color = 2, scale = 0.8, name = 'Grapeseed Field 5' },
        },
    },

    -- ==========================================================
    -- MARKET
    -- Single NPC, instant buy/sell (no drone delivery).
    -- ==========================================================
    Market = {
        coords = vector4(2416.1697, 4993.7061, 45.25, 135.0),
        model = 'a_m_m_farmer_01',
        blip = { enabled = true, sprite = 522, color = 2, scale = 0.8, name = 'Farmers Market' },
    },

    Tools = {
        watering_can = {
            label = 'Watering Can', price = 35, image = 'watering_can.png',
            description = 'Refillable watering can. Never runs out -- required to water plots.',
        },
        farming_tablet = {
            label = 'Farming Tablet', price = 120, image = 'farming_tablet.png', usable = true,
            description = 'Opens the farming menu from anywhere.',
        },
    },

    -- Hold-to-interact durations, and how far a single watering action
    -- also waters other 'planted' plots in the same field around the target.
    Timings = {
        plantMs = 3000,
        waterMs = 2500,
        harvestMs = 3000,
        waterAreaRadius = 5.0,
        growthTickMs = 15000,
    },

    Security = {
        actionCooldownMs = 500,
        actionRangeSlack = 1.0,
    },

    -- ==========================================================
    -- LIVESTOCK (cows)
    -- feed -> wait requiredFeedingTimeSec -> milk (up to maxMilkPerCow
    -- times) -> cow goes back to 'hungry'. Open access like the crop
    -- fields -- no ownership, any player can feed/milk any cow. Real
    -- coordinates/timings carried over from the source resource.
    -- ==========================================================
    Livestock = {
        feedItem = 'cow_feed',
        feedLabel = 'Cow Feed',
        feedPrice = 5,
        milkItem = 'milk',
        milkLabel = 'Milk Bottle',
        milkSellPriceRange = { min = 50, max = 100 },
        requiredFeedingTimeSec = 30,
        maxMilkPerCow = 3,
        feedMs = 2000,
        milkMs = 2500,
        interactDistance = 1.8,
        xpRewardPerMilk = 10,
        Cows = {
            { key = 'cow_1', coords = vector4(2266.6200, 4893.6500, 39.90, 240.85), model = 'a_c_cow' },
            { key = 'cow_2', coords = vector4(2263.7666, 4890.4160, 39.90, 228.5575), model = 'a_c_cow' },
            { key = 'cow_3', coords = vector4(2267.2371, 4896.5601, 39.90, 240.85), model = 'a_c_cow' },
        },
        blip = { enabled = true, sprite = 177, color = 5, scale = 0.8, name = 'Dairy Farm' },
    },
}
