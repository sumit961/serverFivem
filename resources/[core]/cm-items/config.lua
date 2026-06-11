CMItems = CMItems or {}

CMItems.Config = {
    Debug = false,

    -- Inventory should only store physical items.
    -- Phone and keys are virtual and should be managed by cm-phone / cm-keys later.
    InventoryOnlyPhysical = true,

    -- Weight is in grams. Keep integer grams to avoid decimal bugs.
    WeightUnit = 'g',

    Defaults = {
        image = 'default.png',
        weight = 0,
        stack = true,
        unique = false,
        usable = false,
        close = true,
        category = 'misc',
        description = '',
        inventory = true,
        virtual = false
    },

    Categories = {
        food = true,
        drink = true,
        medical = true,
        tool = true,
        material = true,
        weapon = true,
        ammo = true,
        document = true,
        misc = true,
        virtual = true,
        service = true
    }
}
