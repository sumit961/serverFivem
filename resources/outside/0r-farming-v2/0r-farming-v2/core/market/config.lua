return {
    --[[ Drone Delivery Settings ]]
    droneDelivery = {
        time = 10,                                         -- Time (in seconds) before the drone arrives. Minimum recommended: 60 sec for realism.
        objectModel = 1657647215,                          -- Object model hash for the drone entity.
        bagModel = "xm_prop_x17_bag_01a",                  -- Bag object model.
        blip = { sprite = 627, color = 5, text = "Drone" } -- Blip icon and color shown on the map during delivery.
    },

    ---@type MarketItem[]
    items = {
        { itemName = "wheat",           price = 15,  sellPrice = 7,  label = "Wheat",           description = "A common cereal grain used for food.",      level = 1, type = "sell" },
        { itemName = "wheat_seed",      price = 5,   sellPrice = 1,  label = "Wheat Seed",      description = "Seed used to grow wheat.",                  level = 1, type = "buy" },

        { itemName = "rose",            price = 20,  sellPrice = 10, label = "Rose",            description = "A fragrant herb used in cooking.",          level = 1, type = "sell" },
        { itemName = "rose_seed",       price = 20,  sellPrice = 10, label = "Rose Seed",       description = "Seed used to grow roses.",                  level = 1, type = "buy" },

        { itemName = "green",           price = 25,  sellPrice = 15, label = "Green",           description = "A fragrant herb used in cooking.",          level = 2, type = "sell" },
        { itemName = "green_seed",      price = 25,  sellPrice = 15, label = "Green Seed",      description = "Seed used to grow greens.",                 level = 2, type = "buy" },

        { itemName = "daisy",           price = 30,  sellPrice = 20, label = "Daisy",           description = "A fragrant herb used in cooking.",          level = 2, type = "sell" },
        { itemName = "daisy_seed",      price = 30,  sellPrice = 20, label = "Daisy Seed",      description = "Seed used to grow daisies.",                level = 2, type = "buy" },

        { itemName = "poppy",           price = 35,  sellPrice = 25, label = "Poppy",           description = "A fragrant herb used in cooking.",          level = 3, type = "sell" },
        { itemName = "poppy_seed",      price = 35,  sellPrice = 25, label = "Poppy Seed",      description = "Seed used to grow poppies.",                level = 3, type = "buy" },

        { itemName = "melon",           price = 40,  sellPrice = 20, label = "Melon",           description = "A juicy and sweet melon.",                  level = 1, type = "sell" },
        { itemName = "melon_seed",      price = 10,  sellPrice = 2,  label = "Melon Seed",      description = "Seed used to grow melons.",                 level = 1, type = "buy" },

        { itemName = "watermelon",      price = 40,  sellPrice = 20, label = "Watermelon",      description = "A juicy and sweet watermelon.",             level = 1, type = "sell" },
        { itemName = "watermelon_seed", price = 10,  sellPrice = 2,  label = "Watermelon Seed", description = "Seed used to grow watermelons.",            level = 1, type = "buy" },

        { itemName = "pumpkin",         price = 50,  sellPrice = 20, label = "Pumpkin",         description = "A round orange pumpkin.",                   level = 1, type = "sell" },
        { itemName = "pumpkin_seed",    price = 12,  sellPrice = 2,  label = "Pumpkin Seed",    description = "Seed used to grow pumpkins.",               level = 1, type = "buy" },

        { itemName = "watering_can",    price = 30,  sellPrice = 10, label = "Watering Can",    description = "Used to water crops.",                      level = 1, type = "buy" },

        { itemName = "farming_tablet",  price = 100, sellPrice = 50, label = "Farming Tablet",  description = "A tablet used to access the farming menu.", level = 1, type = "buy" },
    }
}
