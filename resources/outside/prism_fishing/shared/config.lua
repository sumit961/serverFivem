return {
    -- =========================
    -- GENERAL SETTINGS
    -- =========================

    ThemeUI = '#ff0000',        -- Primary UI theme color
    debugPrint = false,         -- Enable debug logging (development only)
    UITransparency = 0.8,       -- UI opacity (0.0 - 1.0)
    Currency = '£',             -- Currency symbol shown in UI
    Locale = 'en',              -- Language used for localization
    ContextImgFormat = '.webp', -- Image format used in context menus
    RadiusNearPoint = 4.0,      -- Radius Is Near Vehicle Point Spawn Boat
    Bait = {
        { name = 'worms',           label = "Worms",           waitDivisor = 1.0 },
        { name = 'commonbait',      label = "Common Bait",     waitDivisor = 3.0 },
        { name = 'artificial_bait', label = "Artificial Bait", waitDivisor = 6.0 },
    },
    Boats = {

        Karnaval = {
            coords = vector4(-1799.1460, -1224.3214, 1.5967, 139.6530), -- NPC location

            spawnCoords = {                                             -- Boat spawn positions
                vector4(-1795.8723, -1227.4860, 0.9236, 139.6530),
                vector4(-1789.5032, -1230.3000, 0.1764, 164.8888)
            },

            model = 'a_m_m_skater_01', -- NPC ped model

            blip = {
                enable = true,
                name = 'Rental Boat',
                sprite = 410,
                color = 29,
                scale = 0.6
            },

            payment = 'cash', -- Payment type: 'cash' or 'bank'

            listBoat = {      -- Available boats for rent
                {
                    name = 'seashark',
                    label = 'Sea Shark',
                    image = 'https://docs.fivem.net/vehicles/seashark.webp',
                    price = 500,
                },
                {
                    name = 'dinghy',
                    label = 'Dinghy',
                    image = 'https://docs.fivem.net/vehicles/dinghy.webp',
                    price = 1000,
                },
                {
                    name = 'suntrap',
                    label = 'Suntrap',
                    image = 'https://docs.fivem.net/vehicles/suntrap.webp',
                    price = 1500,
                },
            },
        },

        Harbor = {
            coords = vector4(-801.1674, -1513.2627, 1.5952, 285.4315),

            spawnCoords = {
                vector4(-790.3859, -1499.6721, -0.5349, 110.2479),
            },

            model = 'a_m_m_skater_01',

            blip = {
                enable = true,
                name = 'Rental Boat',
                sprite = 410,
                color = 29,
                scale = 0.6
            },

            payment = 'bank',

            listBoat = {
                {
                    name = 'seashark',
                    label = 'Sea Shark',
                    image = 'https://docs.fivem.net/vehicles/seashark.webp',
                    price = 500,
                },
                {
                    name = 'dinghy',
                    label = 'Dinghy',
                    image = 'https://docs.fivem.net/vehicles/dinghy.webp',
                    price = 1000,
                },
                {
                    name = 'suntrap',
                    label = 'Suntrap',
                    image = 'https://docs.fivem.net/vehicles/suntrap.webp',
                    price = 1500,
                },
            },
        },
    },

    Fish = {
        ['anchovy']     = { label = "Anchovy", chance = 35, rarity = 'Common', xpReward = 5, requiredLevel = 0, skillcheck = { 'easy', 'medium' } },
        ['trout']       = { label = "Trout", chance = 35, rarity = 'Common', xpReward = 1, requiredLevel = 0, skillcheck = { 'easy', 'medium' } },
        ['fish']        = { label = "Fish", chance = 40, rarity = 'Common', xpReward = 1, requiredLevel = 0, skillcheck = { 'easy', 'medium' } },

        ['piranha']     = { label = "Piranha", chance = 25, rarity = 'Rare', xpReward = 2, requiredLevel = 1, skillcheck = { 'easy', 'medium', 'hard' } },
        ['grouper']     = { label = "Grouper", chance = 25, rarity = 'Rare', xpReward = 2, requiredLevel = 1, skillcheck = { 'easy', 'medium', 'medium', 'medium' } },
        ['stingray']    = { label = "Stingray", chance = 15, rarity = 'Rare', xpReward = 2, requiredLevel = 1, skillcheck = { 'easy', 'medium', 'medium' } },

        ['haddock']     = { label = "Haddock", chance = 20, rarity = 'Epic', xpReward = 3, requiredLevel = 2, skillcheck = { 'easy', 'medium' } },
        ['salmon']      = { label = "Salmon", chance = 10, rarity = 'Epic', xpReward = 3, requiredLevel = 2, skillcheck = { 'easy', 'medium', 'medium' } },
        ['red_snapper'] = { label = "Red Snapper", chance = 20, rarity = 'Mythic', xpReward = 4, requiredLevel = 3, skillcheck = { 'easy', 'medium', 'medium', 'medium' } },
        ['mahi_mahi']   = { label = "Mahi Mahi", chance = 20, rarity = 'Mythic', xpReward = 4, requiredLevel = 3, skillcheck = { 'easy', 'medium', 'medium', 'medium' } },
        ['humpback']    = { label = "Humpback", chance = 1, rarity = 'Mythic', xpReward = 4, requiredLevel = 4, ped = `a_c_humpback`, skillcheck = { 'medium', 'medium', 'hard', 'hard' } },
        ['killerwhale'] = { label = "Killer Whale", chance = 1, rarity = 'Mythic', xpReward = 4, requiredLevel = 4, ped = `a_c_killerwhale`, skillcheck = { 'medium', 'hard', 'hard' } },

        ['tuna']        = { label = "Tuna", chance = 5, rarity = 'Legend', xpReward = 5, requiredLevel = 5, skillcheck = { 'easy', 'medium', 'hard' } },
        ['shark']       = { label = "Shark", chance = 1, rarity = 'Legend', xpReward = 5, requiredLevel = 5, ped = `a_c_sharktiger`, skillcheck = { 'easy', 'medium', 'hard' } },
        ['tigershark']  = { label = "Tiger Shark", chance = 1, rarity = 'Legend', xpReward = 5, requiredLevel = 5, ped = `a_c_sharktiger`, skillcheck = { 'medium', 'hard', 'hard' } },
        ['hammershark'] = { label = "Hammer Shark", chance = 2, rarity = 'Legend', xpReward = 5, requiredLevel = 5, ped = `A_C_SharkHammer`, skillcheck = { 'medium', 'hard', 'hard' } },

        ['dolphin']     = { label = "Dolphin", chance = 3, rarity = 'Legend', xpReward = 5, requiredLevel = 5, ped = `a_c_dolphin`, skillcheck = { 'medium', 'hard', 'hard' } },
    },

    MinigameSettings = {
        easy = {
            playerWidth = 10,       -- width white box
            fishSpeed = 0.2,        -- speed icon fish
            moveSpeed = 2,          -- move speed when u q or e
            progressGainRate = 1.2, -- progress gain when white box in icon fish
            progressLossRate = 0.2, -- progress loss when white box out icon fish
        },
        medium = {
            playerWidth = 15,
            fishSpeed = 0.35,
            moveSpeed = 2,
            progressGainRate = 0.9,
            progressLossRate = 0.35,
        },
        hard = {
            playerWidth = 12,
            fishSpeed = 0.7,
            moveSpeed = 2,
            progressGainRate = 1.2,
            progressLossRate = 0.5,
        },
    },

    outside = { -- customizable if player fishing in out zone
        enable = true,
        waitTime = { min = 10, max = 25 },
        fishList = { -- fishlist
            'trout', 'anchovy', 'haddock', 'salmon'
        }
    },



    FishingArea = {
        Karnaval = {
            blip = {
                enable = true,
                name = 'Fishing Spot',
                sprite = 317,
                color = 29,
                scale = 0.6
            },
            locations = {
                vector3(-1870.6555, -1220.9153, 13.0170),
            },
            debug = true,   -- debug zone
            radius = 100.0, -- radius zone
            minLevel = 1,
            waitTime = { min = 1, max = 5 },
            fishList = {
                'anchovy', 'salmon'
            }
        },
        StabsCity = {
            blip = {
                enable = true,
                name = 'Fishing Spot',
                sprite = 317,
                color = 29,
                scale = 0.6
            },
            locations = {
                vector3(-170.9095, 4153.7803, 31.6733),
            },
            debug = false, -- debug zone
            radius = 100.0,
            minLevel = 1,
            waitTime = { min = 1, max = 5 },
            fishList = {
                'mahi_mahi', 'tuna', 'salmon', 'stingray'
            }
        },
        IllegalSpot = {
            blip = { -- Disable Blip Because Illegal
                enable = false,
                name = 'Illegal Spot',
                sprite = 317,
                color = 29,
                scale = 0.6
            },
            debug = false, -- debug zone
            locations = {
                vector3(3671.7588, 4967.5903, 15.9253),
            },
            radius = 100.0,
            minLevel = 1,
            waitTime = { min = 1, max = 5 },
            fishList = {
                'dolphin', 'hammershark', 'tigershark', 'trout', 'fish', 'piranha', 'grouper'
            }
        },
    },

    FishingRod = {
        basic_rod = {
            breakChange = 25, -- percentage
        },
        rod_2 = {
            breakChange = 10, -- percentage
        },
        rod_3 = {
            breakChange = 5, -- percentage
        },
    },

    LevelXP = {
        [0] = 0,
        [1] = 35,
        [2] = 65,
        [3] = 100,
        [4] = 135,
        [5] = 150 -- max level
    },

    OpenMenuStore = {
        model = 'a_m_m_skater_01',
        coords = vector4(-1827.3832, -1246.1781, 13.0173, 320.1692),
        blip = {
            enable = true,
            name = 'Fishing Store',
            sprite = 52,
            color = 29,
            scale = 0.6
        },
    },

    -- UI Settings --
    Store = {
        {
            name = 'basic_rod',
            label = 'Basic Rod',
            price = 50,
            category = 'rod',
            image = 'images/Rods/basic_rod.png',
        },
        {
            name = 'rod_2',
            label = 'Rod Level 2',
            price = 100,
            requiredLevel = 2,
            category = 'rod',
            image = 'images/Rods/rod_2.png',
        },
        {
            name = 'rod_3',
            label = 'Rod Level 3',
            price = 150,
            requiredLevel = 3,
            category = 'rod',
            image = 'images/Rods/rod_3.png',
        },
        {
            name = 'worms',
            label = 'Worms',
            price = 5,
            category = 'bait',
            image = 'images/Bait/worms.png',
        },
        {
            name = 'commonbait',
            label = 'Common Bait',
            price = 10,
            category = 'bait',
            image = 'images/Bait/commonbait.png',
        },
        {
            name = 'artificial_bait',
            label = 'Artificial Bait',
            price = 15,
            category = 'bait',
            image = 'images/Bait/artificial_bait.png',
        },
    },

    FishExchange = {
        {
            name = "anchovy",
            label = "Anchovy",
            category = "Fish Level 1",
            image = "images/Fish/anchovy.png",
            price = 50,
        },
        {
            name = "dolphin",
            label = "Dolphin",
            category = "Fish Level 1",
            image = "images/Fish/dolphin.png",
            price = 50,
        },
        {
            name = "fish",
            label = "Fish",
            category = "Fish Level 1",
            image = "images/Fish/fish.png",
            price = 50,
        },
        {
            name = "grouper",
            label = "Grouper",
            category = "Fish Level 1",
            image = "images/Fish/grouper.png",
            price = 50,
        },
        {
            name = "haddock",
            label = "Haddock",
            category = "Fish Level 1",
            image = "images/Fish/haddock.png",
            price = 50,
        },
        {
            name = "hammershark",
            label = "Hammer Shark",
            category = "Fish Level 1",
            image = "images/Fish/hammershark.png",
            price = 50,
        },
        {
            name = "humpback",
            label = "Humpback",
            category = "Fish Level 1",
            image = "images/Fish/humpback.png",
            price = 50,
        },
        {
            name = "killerwhale",
            label = "Killer Whale",
            category = "Fish Level 1",
            image = "images/Fish/killerwhale.png",
            price = 50,
        },
        {
            name = "mahi_mahi",
            label = "Mahi Mahi",
            category = "Fish Level 1",
            image = "images/Fish/mahi_mahi.png",
            price = 50,
        },
        {
            name = "piranha",
            label = "Piranha",
            category = "Fish Level 1",
            image = "images/Fish/piranha.png",
            price = 50,
        },
        {
            name = "red_snapper",
            label = "Red Snapper",
            category = "Fish Level 1",
            image = "images/Fish/red_snapper.png",
            price = 50,
        },
        {
            name = "salmon",
            label = "Salmon",
            category = "Fish Level 1",
            image = "images/Fish/salmon.png",
            price = 50,
        },
        {
            name = "shark",
            label = "Shark",
            category = "Fish Level 1",
            image = "images/Fish/shark.png",
            price = 50,
        },
        {
            name = "stingray",
            label = "Stingray",
            category = "Fish Level 1",
            image = "images/Fish/stingray.png",
            price = 50,
        },
        {
            name = "tigershark",
            label = "Tiger Shark",
            category = "Fish Level 1",
            image = "images/Fish/tigershark.png",
            price = 50,
        },
        {
            name = "trout",
            label = "Trout",
            category = "Fish Level 1",
            image = "images/Fish/trout.png",
            price = 50,
        },
        {
            name = "tuna",
            label = "Tuna",
            category = "Fish Level 1",
            image = "images/Fish/tuna.png",
            price = 50,
        },
    },

    FishLevel = {
        {
            name = "anchovy",
            label = "Anchovy",
            category = "Fish Level 1",
            image = "images/Fish/anchovy.png",
            description = "A tiny saltwater fish that provides low experience.",
        },
        {
            name = "dolphin",
            label = "Dolphin",
            category = "Fish Level 3",
            image = "images/Fish/dolphin.png",
            description = "A rare marine mammal. Yields high experience due to its size.",
        },
        {
            name = "fish",
            label = "Fish",
            category = "Fish Level 1",
            image = "images/Fish/fish.png",
            description = "A basic fish commonly caught by beginners.",
        },
        {
            name = "grouper",
            label = "Grouper",
            category = "Fish Level 2",
            image = "images/Fish/grouper.png",
            description = "A strong deep-water fish that grants moderate experience.",
        },
        {
            name = "haddock",
            label = "Haddock",
            category = "Fish Level 2",
            image = "images/Fish/haddock.png",
            description = "A common white fish that offers steady experience gain.",
        },
        {
            name = "hammershark",
            label = "Hammer Shark",
            category = "Fish Level 3",
            image = "images/Fish/hammershark.png",
            description = "A dangerous shark species. Catching it rewards high experience.",
        },
        {
            name = "humpback",
            label = "Humpback",
            category = "Fish Level 3",
            image = "images/Fish/humpback.png",
            description = "A massive ocean creature. Extremely high experience reward.",
        },
        {
            name = "killerwhale",
            label = "Killer Whale",
            category = "Fish Level 3",
            image = "images/Fish/killerwhale.png",
            description = "A powerful apex predator. Grants very high experience.",
        },
        {
            name = "mahi_mahi",
            label = "Mahi Mahi",
            category = "Fish Level 2",
            image = "images/Fish/mahi_mahi.png",
            description = "A colorful fish known for its speed, offering moderate XP.",
        },
        {
            name = "piranha",
            label = "Piranha",
            category = "Fish Level 1",
            image = "images/Fish/piranha.png",
            description = "A small but aggressive freshwater fish with sharp teeth.",
        },
        {
            name = "red_snapper",
            label = "Red Snapper",
            category = "Fish Level 2",
            image = "images/Fish/red_snapper.png",
            description = "A popular saltwater fish that yields solid experience.",
        },
        {
            name = "salmon",
            label = "Salmon",
            category = "Fish Level 2",
            image = "images/Fish/salmon.png",
            description = "A common fish found in rivers and lakes. Provides moderate experience.",
        },
        {
            name = "shark",
            label = "Shark",
            category = "Fish Level 3",
            image = "images/Fish/shark.png",
            description = "A large ocean predator. Catching it gives a big XP reward.",
        },
        {
            name = "stingray",
            label = "Stingray",
            category = "Fish Level 2",
            image = "images/Fish/stingray.png",
            description = "A flat-bodied fish with a venomous tail. Offers good experience.",
        },
        {
            name = "tigershark",
            label = "Tiger Shark",
            category = "Fish Level 3",
            image = "images/Fish/tigershark.png",
            description = "A fierce shark species with high XP value.",
        },
        {
            name = "trout",
            label = "Trout",
            category = "Fish Level 1",
            image = "images/Fish/trout.png",
            description = "A freshwater fish that provides small but steady experience.",
        },
        {
            name = "tuna",
            label = "Tuna",
            category = "Fish Level 2",
            image = "images/Fish/tuna.png",
            description = "A powerful and fast-swimming fish worth good experience.",
        },
    },
}
