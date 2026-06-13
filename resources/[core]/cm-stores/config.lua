CMStores = CMStores or {}

CMStores.Config = {
    Debug = true,

    InteractionKey = 38, -- E
    InteractionDistance = 2.0,
    DrawTextDistance = 15.0,

    Currency = 'cash',
    StoreTitle = '24/7 Service',
    StoreSubtitle = 'Everyday essentials',

    Ped = {
        model = 'mp_m_shopkeep_01',
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        freeze = true,
        invincible = true,
        blockEvents = true
    },

    Blip = {
        enabled = true,
        sprite = 52,
        color = 2,
        scale = 0.75,
        name = '24/7 Store'
    },

    -- Add/edit store locations here.
    Stores = {
        {
            id = '247_legion',
            name = '24/7 Legion Square',
            npcName = 'Store Clerk',
            coords = vector4(24.47, -1346.62, 29.5, 271.66),
            items = {
                { name = 'water', price = 0, max = 20 },
                { name = 'sandwich', price = 15, max = 20 },
                { name = 'bandage', price = 75, max = 10 },
                { name = 'medkit', price = 350, max = 5 },
                { name = 'repairkit', price = 500, max = 3 },
                { name = 'lockpick', price = 250, max = 5 }
            }
        },
        {
            id = '247_sandy',
            name = '24/7 Sandy Shores',
            npcName = 'Store Clerk',
            coords = vector4(1961.44, 3740.63, 32.34, 298.98),
            items = {
                { name = 'water', price = 10, max = 20 },
                { name = 'sandwich', price = 15, max = 20 },
                { name = 'bandage', price = 75, max = 10 },
                { name = 'repairkit', price = 500, max = 3 }
            }
        }
    }
}
