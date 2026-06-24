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
        virtual = false,
        worldModel = nil
    },

    WorldModels = {
        default = 'prop_cs_cardbox_01',
        food = 'prop_sandwich_01',
        drink = 'prop_ld_flow_bottle',
        medical = 'prop_ld_health_pack',
        tool = 'prop_tool_box_04',
        material = 'prop_boxpile_04a',
        document = 'prop_cs_documents_01',
        clothing = 'prop_cs_tshirt_box',
        weapon = 'prop_box_guncase_01a',
        ammo = 'prop_ld_ammo_pack_01'
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
        clothing = true,
        misc = true,
        virtual = true,
        service = true
    }
}
