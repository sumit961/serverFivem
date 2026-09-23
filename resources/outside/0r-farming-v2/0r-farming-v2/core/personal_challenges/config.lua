return {
    ---@type PersonalChallenge[]
    challengeTemplates = {
        -- Basic Farming Challenges
        {
            id = "harvest_wheat",
            label = "Wheat Harvesting Master",
            description =
            "Harvest wheat crops to become a master farmer. Challenge level increases with each completion.",
            objective = {
                label = "Harvest wheat",
                type = "harvested",
                targetName = "wheat",
                baseTarget = 50,
                target = 50,
                scalingMultiplier = 1.2
            },
            reward = {
                exp = 200,
                money = 150
            },
        },
        {
            id = "plant_wheat",
            label = "Wheat Planting Specialist",
            description = "Plant wheat crops using the seed machine to improve your farming skills.",
            objective = {
                label = "Plant wheat crops",
                type = "planted",
                targetName = "wheat",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "plant_crops",
            label = "Universal Crop Planter",
            description = "Plant different types of crops to advance in farming mastery.",
            objective = {
                label = "Plant any crop",
                type = "planted",
                targetName = "any",
                baseTarget = 40,
                target = 40,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 180,
                money = 120
            },
        },
        {
            id = "water_plants",
            label = "Hydration Expert",
            description = "Keep your crops healthy by watering them regularly with precision.",
            objective = {
                label = "Water plants",
                type = "watered",
                targetName = "any",
                baseTarget = 25,
                target = 25,
                scalingMultiplier = 1.25
            },
            reward = {
                exp = 120,
                money = 80
            },
        },
        {
            id = "plant_rose",
            label = "Rose Planting Specialist",
            description = "Plant rose crops using the seed machine to improve your farming skills.",
            objective = {
                label = "Plant rose crops",
                type = "planted",
                targetName = "rose",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "harvest_rose",
            label = "Rose Harvesting Master",
            description =
            "Harvest rose crops to become a master farmer. Challenge level increases with each completion.",
            objective = {
                label = "Harvest roses",
                type = "harvested",
                targetName = "rose",
                baseTarget = 50,
                target = 50,
                scalingMultiplier = 1.2
            },
            reward = {
                exp = 200,
                money = 150
            },
        },
        {
            id = "plant_green",
            label = "Green Planting Specialist",
            description = "Plant green crops using the seed machine to improve your farming skills.",
            objective = {
                label = "Plant green crops",
                type = "planted",
                targetName = "green",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "harvest_green",
            label = "Green Harvesting Master",
            description =
            "Harvest green crops to become a master farmer. Challenge level increases with each completion.",
            objective = {
                label = "Harvest greens",
                type = "harvested",
                targetName = "green",
                baseTarget = 50,
                target = 50,
                scalingMultiplier = 1.2
            },
            reward = {
                exp = 200,
                money = 150
            },
        },
        {
            id = "plant_daisy",
            label = "Daisy Planting Specialist",
            description = "Plant daisy crops using the seed machine to improve your farming skills.",
            objective = {
                label = "Plant daisy crops",
                type = "planted",
                targetName = "daisy",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "harvest_daisy",
            label = "Daisy Harvesting Master",
            description =
            "Harvest daisy crops to become a master farmer. Challenge level increases with each completion.",
            objective = {
                label = "Harvest daisies",
                type = "harvested",
                targetName = "daisy",
                baseTarget = 50,
                target = 50,
                scalingMultiplier = 1.2
            },
            reward = {
                exp = 200,
                money = 150
            },
        },
        {
            id = "plant_poppy",
            label = "Poppy Planting Specialist",
            description = "Plant poppy crops using the seed machine to improve your farming skills.",
            objective = {
                label = "Plant poppy crops",
                type = "planted",
                targetName = "poppy",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "harvest_poppy",
            label = "Poppy Harvesting Master",
            description =
            "Harvest poppy crops to become a master farmer. Challenge level increases with each completion.",
            objective = {
                label = "Harvest poppies",
                type = "harvested",
                targetName = "poppy",
                baseTarget = 50,
                target = 50,
                scalingMultiplier = 1.2
            },
            reward = {
                exp = 200,
                money = 150
            },
        },
        {
            id = "plant_melon",
            label = "Melon Planting Specialist",
            description = "Plant melon crops using the seed machine to improve your farming skills.",
            objective = {
                label = "Plant melon crops",
                type = "planted",
                targetName = "melon",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "harvest_melon",
            label = "Melon Harvesting Master",
            description =
            "Harvest melon crops to become a master farmer. Challenge level increases with each completion.",
            objective = {
                label = "Harvest melons",
                type = "harvested",
                targetName = "melon",
                baseTarget = 50,
                target = 50,
                scalingMultiplier = 1.2
            },
            reward = {
                exp = 200,
                money = 150
            },
        },
        {
            id = "plant_pumpkin",
            label = "Pumpkin Planting Specialist",
            description = "Plant pumpkin crops using the seed machine to improve your farming skills.",
            objective = {
                label = "Plant pumpkin crops",
                type = "planted",
                targetName = "pumpkin",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "harvest_pumpkin",
            label = "Pumpkin Harvesting Master",
            description =
            "Harvest pumpkin crops to become a master farmer. Challenge level increases with each completion.",
            objective = {
                label = "Harvest pumpkins",
                type = "harvested",
                targetName = "pumpkin",
                baseTarget = 50,
                target = 50,
                scalingMultiplier = 1.2
            },
            reward = {
                exp = 200,
                money = 150
            },
        },
        {
            id = "feed_cow",
            label = "Cow Feeding Specialist",
            description = "Feed cows to improve your farming skills.",
            objective = {
                label = "Feed cows",
                type = "fed",
                targetName = "cow",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        },
        {
            id = "milk_cow",
            label = "Cow Milking Expert",
            description = "Milk cows to enhance your farming expertise.",
            objective = {
                label = "Milk cows",
                type = "milked",
                targetName = "cow",
                baseTarget = 30,
                target = 30,
                scalingMultiplier = 1.15
            },
            reward = {
                exp = 150,
                money = 100
            },
        }
    },

    -- Reward scaling settings
    -- Determines how rewards increase with each level
    rewardScaling = {
        expMultiplier = 1.1,  -- Each level increases exp by 10%
        moneyMultiplier = 1.1 -- Each level increases money by 10%
    }
}
