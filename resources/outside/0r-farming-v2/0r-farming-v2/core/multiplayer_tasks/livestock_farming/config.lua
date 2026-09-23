return {
    teamSize = {
        min = 1, -- Minimum number of players required to start the task.
        max = 4, -- Maximum number of players allowed to start the task.
    },

    infoBoxTable = {
        locale("livestock_farming.steps.1"),
        locale("livestock_farming.steps.2"),
        locale("livestock_farming.steps.3"),
        locale("livestock_farming.steps.4"),
        locale("livestock_farming.steps.5"),
    },

    ---@type table<string, BlipConfig>
    --- Task blips configuration.
    blips = {
        cow = { sprite = 177, color = 5, scale = 0.8, name = locale("livestock_farming.blips.cow"), },
        truck = { sprite = 853, color = 5, scale = 0.8, name = locale("livestock_farming.blips.truck"), },
        feed = { sprite = 618, color = 5, scale = 0.8, name = locale("livestock_farming.blips.feed"), },
    },

    milkBottleSalesPriceRange = { min = 50, max = 100 },

    animalFeed = {
        targetModels = { 1700312454, 533342826 },
        hold = {
            model = "prop_haybale_01",
            offset = vector3(0.01, -0.02, -0.12),
            rotation = vector3(-90.0, 0.0, 0.0),
            bone = 28422,
            dict = "anim@heists@box_carry@",
            name = "idle",
            type = "feed",
        },
        requiredFeedingTimeForMilk = 10, -- Required feeding time for milk production (in seconds)
        maxMilkPerCow = 3,               -- Maximum milk that can be obtained from each cow
        milkProp = {
            model = "prop_old_churn_01",
            offset = vector3(0.2, -0.15, -0.90),
            rotation = vector3(0.0, 0.0, 80.0),
            bone = 28422,
            dict = "anim@heists@narcotics@trash",
            name = "idle",
            type = "milk",
        },
    },

    ---@type LivestockFarmingField[]>
    fields = {
        [1] = {
            cowLocations = {
                {
                    coords = vector4(2266.62, 4893.65, 39.90, 240.85), -- Example coordinates for cow locations
                    model = "a_c_cow",                                 -- Model of the cow
                },
                {
                    coords = vector4(2263.7666, 4890.4160, 39.90, 228.5575), -- Example coordinates for cow locations
                    model = "a_c_cow",                                       -- Model of the cow
                },
                {
                    coords = vector4(2267.2371, 4896.5601, 39.90, 240.85), -- Example coordinates for cow locations
                    model = "a_c_cow",                                     -- Model of the cow
                }
            },
            truckLocation = {
                coords = vector4(2260.34, 4888.05, 40.9, 44.93), -- Coordinates where the truck is spawned
                model = "mule3",                                 -- Model of the truck
            },
            feedBlipLocations = {
                vector3(2279.7319, 4891.0884, 40.4996), -- Example coordinates for feed blip locations
            },
        },
    },

    feedMarker = {
        type = 1,
        scale = vector3(2.0, 2.0, 1.0),
        color = { r = 255, g = 229, b = 145, a = 100 },
    },
}
