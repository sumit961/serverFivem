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
        worldModel = 'prop_ld_flow_bottle',
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
        worldModel = 'prop_sandwich_01',
        description = 'A simple packed sandwich.'
    },

    -- Medical
    bandage = {
        label = 'Bandage',
        image = 'nui://cm-items/ui/images/medical_bandage.svg',
        weight = 100,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        worldModel = 'prop_ld_health_pack',
        description = 'Restores 20 health. Cannot be used at full health.'
    },

    medkit = {
        label = 'Medical Kit',
        image = 'nui://cm-items/ui/images/medical_kit.svg',
        weight = 1200,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        worldModel = 'prop_ld_health_pack',
        description = 'A medical kit that restores health.'
    },

    medikit = {
        label = 'Medikit',
        image = 'nui://cm-items/ui/images/medical_kit.svg',
        weight = 900,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        worldModel = 'prop_ld_health_pack',
        description = 'Fully heals you or revives a nearby player.'
    },

    armor = {
        label = 'Body Armor',
        image = 'nui://cm-items/ui/images/medical_armor.svg',
        weight = 2500,
        stack = false,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        worldModel = 'prop_armour_pickup',
        description = 'Protective armor vest.'
    },

    -- Doctor NPC catalog (cm-doctor). Effects registered by cm-doctor at
    -- startup via exports['cm-itemactions']:RegisterItem.
    painkillers = {
        label = 'Painkillers',
        image = 'nui://cm-items/ui/images/medical_painkillers.svg',
        weight = 50,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        worldModel = 'prop_cs_pills',
        description = 'Restores 10 health. Cannot be used at full health.'
    },

    antibiotics = {
        label = 'Antibiotics',
        image = 'nui://cm-items/ui/images/medical_antibiotics.svg',
        weight = 60,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        worldModel = 'prop_cs_pills',
        description = 'Supports recovery and restores 25 health.'
    },

    adrenaline_shot = {
        label = 'Adrenaline Shot',
        image = 'nui://cm-items/ui/images/medical_adrenaline.svg',
        weight = 80,
        stack = true,
        unique = false,
        usable = true,
        close = true,
        category = 'medical',
        worldModel = 'prop_syringe_01',
        description = 'Restores 40 health. Cannot be used at full health.'
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
        worldModel = 'prop_tool_box_04',
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
        worldModel = 'prop_tool_screwdvr01',
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
        worldModel = 'prop_tool_screwdvr01',
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
        worldModel = 'prop_cs_documents_01',
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
        worldModel = 'prop_cs_documents_01',
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
        worldModel = 'prop_boxpile_04a',
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
        worldModel = 'prop_boxpile_04a',
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
        worldModel = 'prop_box_guncase_01a',
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
        worldModel = 'prop_ld_ammo_pack_01',
        ammoType = 'AMMO_PISTOL',
        description = '9mm pistol ammunition.'
    }
,

    -- Clothing items created by nvCloth / clothing shop buy-to-inventory.
    -- clothing_legs was removed as a duplicate; use clothing_pants. The API keeps clothing_legs as an alias.
    clothing_tshirt = {
        label = 'T-Shirt', image = 'clothing.png', weight = 250, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_tshirt_box', equipmentSlot = 'shirt',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_torso = {
        label = 'Top', image = 'clothing.png', weight = 350, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_tshirt_box', equipmentSlot = 'outerwear',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender', arms = 'number_optional', armsTexture = 'number_optional', undershirt = 'number_optional', undershirtTexture = 'number_optional' },
        description = 'Wearable clothing item.'
    },

    clothing_pants = {
        label = 'Pants', image = 'clothing.png', weight = 300, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_tshirt_box', equipmentSlot = 'pants',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_shoes = {
        label = 'Shoes', image = 'clothing.png', weight = 450, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_tshirt_box', equipmentSlot = 'shoes',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_chains = {
        label = 'Chain', image = 'clothing.png', weight = 150, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'p_jewel_necklace01_s', equipmentSlot = 'accessory',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_bags = {
        label = 'Bag', image = 'clothing.png', weight = 800, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_tshirt_box', equipmentSlot = 'bag',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender', bagLevel = 'number_optional' },
        description = 'Wearable clothing item.'
    },

    clothing_mask = {
        label = 'Mask', image = 'clothing.png', weight = 150, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_mask_ballistic', equipmentSlot = 'mask',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable mask item.'
    },

    clothing_arms = {
        label = 'Arms / Gloves', image = 'clothing.png', weight = 120, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_tshirt_box', equipmentSlot = 'arms',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable arms or gloves item.'
    },

    clothing_decals = {
        label = 'Decals', image = 'clothing.png', weight = 50, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_tshirt_box', equipmentSlot = 'decals',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable decal item.'
    },

    clothing_hat = {
        label = 'Hat', image = 'clothing.png', weight = 250, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_proxy_hat_01', equipmentSlot = 'headwear',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_glasses = {
        label = 'Glasses', image = 'clothing.png', weight = 100, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'prop_cs_sol_glasses', equipmentSlot = 'glasses',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_earrings = {
        label = 'Earrings', image = 'clothing.png', weight = 50, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'p_jewel_necklace01_s', equipmentSlot = 'earrings',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_watches = {
        label = 'Watch', image = 'clothing.png', weight = 120, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'p_watch_01', equipmentSlot = 'watch',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable clothing item.'
    },

    clothing_bracelet = {
        label = 'Bracelet', image = 'clothing.png', weight = 80, stack = false, unique = true, usable = true, close = true,
        category = 'clothing', worldModel = 'p_watch_01', equipmentSlot = 'bracelet',
        metadataRequired = { 'drawableId', 'textureId', 'categoryType' },
        metadataSchema = { drawableId = 'number', textureId = 'number', categoryType = 'string', gender = 'gender' },
        description = 'Wearable bracelet item.'
    }
}
