return {

    requiredLevel = 1,              -- Task level, used for task progression and unlocking.

    requiredJobNames = nil, -- Required job names to start the task. => nil means no job requirement. => Example: {"farmer", "miner"} or just "farmer"

    teamSize = {
        min = 1, -- Minimum number of players required to start the task.
        max = 4, -- Maximum number of players allowed to start the task.
    },

    timeLimit = 900, -- Time limit for the task in seconds.

    -- Information box displayed when the task is started.
    infoBoxTable = {
        locale("freelance.steps.1"), -- Get tractor and attach seed machine
        locale("freelance.steps.2"), -- Plant seeds with seed machine
        locale("freelance.steps.3"), -- Water the crops
        locale("freelance.steps.4"), -- Wait for crops to grow
        locale("freelance.steps.5"), -- Harvest with harvester
        locale("freelance.steps.6"), -- Deliver harvested bales
    },

    ---@type table<string, BlipConfig>
    -- Task blips configuration.
    blips = {
        field             = { sprite = 237, color = 5, scale = 0.8, name = locale("freelance.blips.field"), },
        tractor           = { sprite = 846, color = 5, scale = 0.8, name = locale("freelance.blips.tractor"), },
        harvester         = { sprite = 270, color = 5, scale = 0.8, name = locale("freelance.blips.harvester"), },
        trailer           = { sprite = 479, color = 5, scale = 0.8, name = locale("freelance.blips.trailer"), },
        seeder            = { sprite = 270, color = 5, scale = 0.8, name = locale("freelance.blips.seeder"), },
        point             = { sprite = 270, color = 0, scale = 0.4, name = locale("freelance.blips.point"), },
        dropHarvestedBale = { sprite = 270, color = 0, scale = 0.8, name = locale("freelance.blips.dropHarvestedBale"), },
    },

    wateringCan = {
        itemName = "watering_can",
    },

    detachTrailerKey = "G", -- Key to detach the trailer from the tractor.

    ---@type table<string, CropConfig>
    -- Crop configurations for the farming task.
    crops = {
        ["wheat"] = {
            label = locale("freelance.crop.wheat"),
            growthTime = 30,
            harvestAmount = 3,
            seedItem = "wheat_seed",
            harvestItem = "wheat",
            model = "prop_veg_crop_06",             -- Model used for the crop in the world
            harvestedBaleModel = "prop_haybale_03", -- Model used for the harvested bale in the world
        },
        ["rose"] = {
            label = locale("freelance.crop.rose"),
            growthTime = 30,
            harvestAmount = 3,
            seedItem = "rose_seed",
            harvestItem = "rose",
            model = "prop_veg_crop_rose",
            harvestedBaleModel = "prop_haybale_rose",
        },
        ["green"] = {
            label = locale("freelance.crop.green"),
            growthTime = 30,
            harvestAmount = 3,
            seedItem = "green_seed",
            harvestItem = "green",
            model = "prop_veg_crop_green",
            harvestedBaleModel = "prop_haybale_green",
        },
        ["daisy"] = {
            label = locale("freelance.crop.daisy"),
            growthTime = 30,
            harvestAmount = 3,
            seedItem = "daisy_seed",
            harvestItem = "daisy",
            model = "prop_veg_crop_daisy",
            harvestedBaleModel = "prop_haybale_green",
        },
        ["poppy"] = {
            label = locale("freelance.crop.poppy"),
            growthTime = 30,
            harvestAmount = 3,
            seedItem = "poppy_seed",
            harvestItem = "poppy",
            model = "prop_veg_crop_poppy",
            harvestedBaleModel = "prop_haybale_green",
        },
    },

    ---@type FreelanceField[]
    -- Farming zones configuration.
    fields = {
        [1] = {
            center = vector3(2522.7273, 4369.6699, 39.0057),            -- Field center coordinates
            radius = 30,                                                -- Radius for blip
            rotation = 45.0,                                            -- Rotation angle for box shape
            maxPoints = 49,                                             -- Maximum number of planting points
            dropHarvestedBaleCoords = vector3(2412.05, 4989.32, 45.25), -- Coordinates where the harvested bale is dropped after harvesting

            tractor = {
                model = "tractor2",                                -- Model of the tractor
                locations = {
                    [1] = vector4(2513.26, 4398.51, 37.41, 230.0), -- Coordinates where the tractor is spawned
                },
            },
            harvester = {
                model = "tractor3",                                -- Model of the harvester
                locations = {
                    [1] = vector4(2505.40, 4394.40, 37.21, 230.0), -- Coordinates where the harvester is spawned
                },
            },
            trailer = {
                model = "baletrailer",                             -- Model of the trailer
                locations = {
                    [1] = vector4(2501.21, 4387.72, 37.83, 230.0), -- Coordinates where the trailer is spawned
                },
            },
            seeder = {
                model = -1106934735,                               -- Model of the seed machine
                locations = {
                    [1] = vector4(2510.36, 4401.49, 37.22, 230.0), -- Coordinates where the seed machine is spawned
                },
            },
        },
    },
}
