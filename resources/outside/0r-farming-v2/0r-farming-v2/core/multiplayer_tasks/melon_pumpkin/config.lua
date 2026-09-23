return {

    requiredLevel     = 1,   -- Task level, used for task progression and unlocking.

    requiredJobNames  = nil, -- Required job names to start the task. => nil means no job requirement. => Example: {"farmer", "miner"} or just "farmer"

    teamSize          = {
        min = 1, -- Minimum number of players required to start the task.
        max = 4, -- Maximum number of players allowed to start the task.
    },

    timeLimit         = 900, -- Time limit for the task in seconds.

    -- Information box displayed when the task is started.
    infoBoxTable      = {
        locale("melon_pumpkin.steps.1"),
        locale("melon_pumpkin.steps.2"),
        locale("melon_pumpkin.steps.3"),
        locale("melon_pumpkin.steps.4"),
        locale("melon_pumpkin.steps.5"),
        locale("melon_pumpkin.steps.6"),
    },

    ---@type table<string, BlipConfig>
    -- Task blips configuration.
    blips             = {
        field = { sprite = 237, color = 5, scale = 0.8, name = locale("melon_pumpkin.blips.field"), },
        point = { sprite = 270, color = 0, scale = 0.4, name = locale("melon_pumpkin.blips.point"), },
        deliveryVehicle = { sprite = 326, color = 5, scale = 0.8, name = locale("melon_pumpkin.blips.delivery_vehicle"), },
    },

    wateringCan       = {
        itemName = "watering_can",
    },

    holdObjectOffsets = {
        vector3(-0.8, -0.25, -0.13),
        vector3(-0.4, -0.25, -0.13),
        vector3(0.0, -0.25, -0.13),
        vector3(0.4, -0.25, -0.13),
        vector3(0.8, -0.25, -0.13),

        vector3(-0.8, -0.70, -0.13),
        vector3(-0.4, -0.70, -0.13),
        vector3(0.0, -0.70, -0.13),
        vector3(0.4, -0.70, -0.13),
        vector3(0.8, -0.70, -0.13),

        vector3(-0.8, -1.15, -0.13),
        vector3(-0.4, -1.15, -0.13),
        vector3(0.0, -1.15, -0.13),
        vector3(0.4, -1.15, -0.13),
        vector3(0.8, -1.15, -0.13),
    },

    ---@type table<string, CropConfig>
    -- Crop configurations for the farming task.
    crops             = {
        ["melon"] = {
            label = locale("melon_pumpkin.crop.melon"),
            growthTime = 5,
            seedItem = "melon_seed",
            harvestItem = "melon",
            seedModel = "0r_sapling",
            growthModel = "0r_melon",
            attachOffset = vector3(-0.01, 0.35, 0.15),
            spawnOffset = vector3(0.0, 0.0, -0.005),
            sellPrice = 20,
        },
        ["pumpkin"] = {
            label = locale("melon_pumpkin.crop.pumpkin"),
            growthTime = 5,
            seedItem = "pumpkin_seed",
            harvestItem = "pumpkin",
            seedModel = "0r_sapling",
            growthModel = "prop_veg_crop_03_pump",
            attachOffset = vector3(0.0200, 0.35, -0.1200),
            spawnOffset = vector3(0.0, 0.0, 0.0),
            sellPrice = 20,
        },
        ["watermelon"] = {
            label = locale("melon_pumpkin.crop.watermelon"),
            growthTime = 5,
            seedItem = "watermelon_seed",
            harvestItem = "watermelon",
            seedModel = "0r_sapling",
            growthModel = "prop_veg_crop_03_cab",
            attachOffset = vector3(0.0200, 0.35, -0.1200),
            spawnOffset = vector3(0.0, 0.0, 0.0),
            sellPrice = 20,
        },
    },

    ---@type MelonPumpkinField[]
    -- Farming zones configuration.
    fields            = {
        [1] = {
            center = vector3(2874.1814, 4657.3740, 48.3337), -- Field center coordinates
            radius = 40,                                     -- Radius for blip
            maxPoints = 49,                                  -- Maximum number of planting points
            rotation = 195.0,                                -- Rotation of the field

            deliveryVehicle = {
                model = "youga",                                    -- Vehicle model for delivery
                location = vector4(2889.48, 4672.78, 48.33, 180.0), -- Vehicle spawn point
            },
        },
    },
}
