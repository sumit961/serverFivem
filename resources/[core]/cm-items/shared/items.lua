CMItems = CMItems or {}

-- Physical inventory items only.
-- These can be stored in cm-inventory later.
CMItems.Items = {
    -- Food / drink examples. Remove if you do not want food systems yet.
    water = {
        label = 'Water Bottle',
        image = 'water.png',
        weight = 500,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'drink',
        description = 'A bottle of clean water.'
    },

    sandwich = {
        label = 'Sandwich',
        image = 'sandwich.png',
        weight = 350,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'food',
        description = 'A simple packed sandwich.'
    },

    -- Medical
    bandage = {
        label = 'Bandage',
        image = 'bandage.png',
        weight = 100,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        description = 'Used to treat minor injuries.'
    },

    medkit = {
        label = 'Medical Kit',
        image = 'medkit.png',
        weight = 1200,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        description = 'A medical kit for serious injuries.'
    },

    armor = {
        label = 'Body Armor',
        image = 'armor.png',
        weight = 2500,
        stack = false,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        description = 'Protective armor vest.'
    },

    -- Tools
    repairkit = {
        label = 'Repair Kit',
        image = 'repairkit.png',
        weight = 1800,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'tool',
        description = 'A basic vehicle repair kit.'
    },

    lockpick = {
        label = 'Lockpick',
        image = 'lockpick.png',
        weight = 80,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'tool',
        illegal = true,
        description = 'A small tool used to pick locks.'
    },

    advanced_lockpick = {
        label = 'Advanced Lockpick',
        image = 'advanced_lockpick.png',
        weight = 120,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'tool',
        illegal = true,
        description = 'A stronger lockpick for harder locks.'
    },

    -- Documents can be inventory items if you want physical documents.
    -- ID/driver license can also be made virtual later, but physical docs are useful for RP/search/evidence.
    id_card = {
        label = 'ID Card',
        image = 'id_card.png',
        weight = 30,
        stack = false,
        unique = true,
        usable = true,
        close = true,
        category = 'document',
        metadataRequired = { 'characterId', 'firstname', 'lastname', 'dob' },
        description = 'Official identity card.'
    },

    driver_license = {
        label = 'Driver License',
        image = 'driver_license.png',
        weight = 30,
        stack = false,
        unique = true,
        usable = true,
        close = true,
        category = 'document',
        metadataRequired = { 'characterId', 'licenseClass' },
        description = 'Driving license document.'
    },

    -- Materials
    plastic = {
        label = 'Plastic',
        image = 'plastic.png',
        weight = 40,
        stack = true,
        unique = false,
        usable = false,
        category = 'material',
        description = 'Crafting material.'
    },

    metal_scrap = {
        label = 'Metal Scrap',
        image = 'metal_scrap.png',
        weight = 120,
        stack = true,
        unique = false,
        usable = false,
        category = 'material',
        description = 'Scrap metal used in crafting.'
    },

    -- Weapons as inventory items. Actual weapon equip should be validated server-side later.
    weapon_pistol = {
        label = 'Pistol',
        image = 'weapon_pistol.png',
        weight = 1200,
        stack = false,
        unique = true,
        usable = true,
        close = true,
        category = 'weapon',
        weapon = true,
        metadataRequired = { 'serial' },
        description = 'A registered or unregistered pistol.'
    },

    ammo_9mm = {
        label = '9mm Ammo',
        image = 'ammo_9mm.png',
        weight = 15,
        stack = true,
        unique = false,
        usable = true,
        close = false,
        category = 'ammo',
        ammoType = 'AMMO_PISTOL',
        description = '9mm pistol ammunition.'
    }
}
