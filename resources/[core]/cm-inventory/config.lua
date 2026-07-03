CMInventory = CMInventory or {}

CMInventory.Config = {
    Debug = true,
    OpenKey = 'I',

    OwnerType = 'character',

    Slots = {
        quick = { prefix = 'quickaccess-', count = 5 },
        pockets = { prefix = 'pocket-', count = 6 },
        backpack = { prefix = 'backpack-', count = 30 },
        equipment = {
            'mask', 'glasses', 'headwear', 'earrings',
            'outerwear', 'shirt', 'bodyarmor', 'bag',
            'accessory', 'weapon', 'ammo',
            'watch', 'pants', 'shoes'
        }
    },

    -- Bag-level player inventory rules.
    -- Pockets + quick slots are always open. Backpack slots and capacity depend on the equipped bag.
    BagLevels = {
        [0] = { label = 'No Bag',      backpackSlots = 0,  maxWeight = 25000 },
        [1] = { label = 'Bag Level 1', backpackSlots = 6,  maxWeight = 45000 },
        [2] = { label = 'Bag Level 2', backpackSlots = 8,  maxWeight = 55000 },
        [3] = { label = 'Bag Level 3', backpackSlots = 30, maxWeight = 82000 },
        [4] = { label = 'Bag Level 4', backpackSlots = 30, maxWeight = 100000 }
    },

    Weight = {
        max = 25000 -- fallback grams if bag config is missing
    },

    Use = {
        defaultCooldownMs = 1500,
        defaultProgressMs = 1000,
        cooldowns = {
            bandage = 5000,
            medkit = 8000,
            armor = 5000,
            body_armor = 5000,
            weapon_pistol = 1200,
            ammo_9mm = 800,
            lockpick = 3000,
            repairkit = 6000,
            water = 1200,
            sandwich = 1500,
            bag_level1 = 1000,
            bag_level2 = 1000,
            bag_level3 = 1000,
            bag_level4 = 1000
        },
        progress = {
            bandage = { ms = 3000, label = 'Using bandage...' },
            medkit = { ms = 5000, label = 'Using medkit...' },
            armor = { ms = 3000, label = 'Equipping body armor...' },
            body_armor = { ms = 3000, label = 'Equipping body armor...' },
            weapon_pistol = { ms = 900, label = 'Equipping weapon...' },
            ammo_9mm = { ms = 650, label = 'Preparing ammo...' },
            lockpick = { ms = 2500, label = 'Using lockpick...' },
            repairkit = { ms = 5000, label = 'Using repair kit...' },
            water = { ms = 1000, label = 'Drinking water...' },
            sandwich = { ms = 1200, label = 'Eating sandwich...' },
            bag_level1 = { ms = 900, label = 'Equipping bag...' },
            bag_level2 = { ms = 900, label = 'Equipping bag...' },
            bag_level3 = { ms = 900, label = 'Equipping bag...' },
            bag_level4 = { ms = 900, label = 'Equipping bag...' }
        }
    },

    Drops = {
        enabled = true,
        expireMinutes = 10,
        pickupDistance = 2.0,
        markerDistance = 18.0,
        markerType = 2
    },

    Give = {
        enabled = true,
        distance = 3.0
    },

    Ammo = {
        enabled = true,
        slot = 'ammo',
        weapons = {
            weapon_pistol = { ammo = 'ammo_9mm' },
            weapon_combatpistol = { ammo = 'ammo_9mm' },
            weapon_appistol = { ammo = 'ammo_9mm' },
            weapon_smg = { ammo = 'ammo_9mm' }
        }
    },

    BlockedInventoryItems = {
        phone = true,
        vehicle_key = true,
        house_key = true,
        business_key = true
    },

    -- Dynamic items created at runtime by other resources (e.g. cm-gunstore
    -- armor vests / weapons named armor_xxx, weapon_xxx). cm-items does not know
    -- these, so we resolve them by name prefix to a sensible default def.
    -- Metadata stored on the actual item (label, image, weight) overrides these.
    DynamicItemPatterns = {
        { prefix = 'armor_',  def = { label = 'Armor Vest', category = 'armor',  equipmentSlot = 'bodyarmor', itemType = 'rare',   rarity = 'rare',   weight = 2500, stack = false, usable = true, image = 'armor.png',         description = 'Wearable armor vest.' } },
        { prefix = 'weapon_', def = { label = 'Weapon',     category = 'weapon', equipmentSlot = 'weapon',    itemType = 'unique', rarity = 'unique', weight = 1500, stack = false, usable = true, image = 'weapon_pistol.png', description = 'A firearm.' } },
        { prefix = 'ammo_',   def = { label = 'Ammo',       category = 'ammo',   equipmentSlot = 'ammo',      itemType = 'normal', rarity = 'normal', weight = 15,   stack = true,  usable = true, image = 'ammo_9mm.png',     description = 'Ammunition.' } },
    },

    EquipmentRules = {
        mask = { 'mask' },
        glasses = { 'glasses' },
        headwear = { 'headwear', 'hat' },
        earrings = { 'earrings' },
        outerwear = { 'outerwear', 'jacket' },
        shirt = { 'shirt', 'tshirt' },
        bodyarmor = { 'armor', 'bodyarmor' },
        bag = { 'bag' },
        accessory = { 'accessory' },
        weapon = { 'weapon' },
        ammo = { 'ammo' },
        watch = { 'watch' },
        pants = { 'pants' },
        shoes = { 'shoes' }
    },

    DefaultImages = {
        water = 'water.png',
        sandwich = 'sandwich.png',
        bandage = 'bandage.png',
        medkit = 'medkit.png',
        armor = 'armor.png',
        repairkit = 'repairkit.png',
        lockpick = 'lockpick.png',
        weapon_pistol = 'weapon_pistol.png',
        ammo_9mm = 'ammo_9mm.png',
        id_card = 'id_card.png',
        clothing_tshirt = 'clothing.png',
        clothing_torso = 'clothing.png',
        clothing_pants = 'clothing.png',
        clothing_legs = 'clothing.png',
        clothing_shoes = 'clothing.png',
        clothing_chains = 'clothing.png',
        clothing_bags = 'clothing.png',
        clothing_hat = 'clothing.png',
        clothing_glasses = 'clothing.png',
        clothing_earrings = 'clothing.png',
        clothing_watches = 'clothing.png',
        bag_level1 = 'placeholder.png',
        bag_level2 = 'placeholder.png',
        bag_level3 = 'placeholder.png',
        bag_level4 = 'placeholder.png'
    },

    FallbackItems = {
        water = { label = 'Water Bottle', category = 'drink', itemType = 'normal', rarity = 'normal', weight = 500, stack = true, usable = true, image = 'water.png', description = 'Clean drinking water.' },
        sandwich = { label = 'Sandwich', category = 'food', itemType = 'normal', rarity = 'normal', weight = 350, stack = true, usable = true, image = 'sandwich.png', description = 'A simple sandwich.' },
        bandage = { label = 'Bandage', category = 'medical', itemType = 'normal', rarity = 'normal', weight = 100, stack = true, usable = true, image = 'bandage.png', description = 'Used to recover small injuries.' },
        medkit = { label = 'Medkit', category = 'medical', itemType = 'rare', rarity = 'rare', weight = 900, stack = true, usable = true, image = 'medkit.png', description = 'Medical kit for bigger injuries.' },
        armor = { label = 'Body Armor', category = 'armor', equipmentSlot = 'bodyarmor', itemType = 'rare', rarity = 'rare', weight = 2500, stack = false, usable = true, image = 'armor.png', description = 'Protective body armor.', durability = 100 },
        repairkit = { label = 'Repair Kit', category = 'tool', itemType = 'normal', rarity = 'normal', weight = 1800, stack = true, usable = true, image = 'repairkit.png', description = 'Used to repair a vehicle.', durability = 100 },
        lockpick = { label = 'Lockpick', category = 'tool', itemType = 'normal', rarity = 'normal', weight = 80, stack = true, usable = true, image = 'lockpick.png', description = 'A small lockpicking tool.', durability = 100 },
        id_card = { label = 'ID Card', category = 'document', itemType = 'unique', rarity = 'unique', weight = 50, stack = false, usable = true, image = 'id_card.png', description = 'Personal identification card.' },
        weapon_pistol = { label = 'Pistol', category = 'weapon', equipmentSlot = 'weapon', itemType = 'unique', rarity = 'unique', weight = 1200, stack = false, usable = true, image = 'weapon_pistol.png', description = 'A small firearm.', durability = 100 },
        ammo_9mm = { label = '9mm Ammo', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 15, stack = true, usable = true, image = 'ammo_9mm.png', description = '9mm ammunition.' },
        clothing_tshirt = { label = 'T-Shirt', category = 'clothing', equipmentSlot = 'shirt', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_torso = { label = 'Torso', category = 'clothing', equipmentSlot = 'outerwear', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_pants = { label = 'Pants', category = 'clothing', equipmentSlot = 'pants', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_legs = { label = 'Pants', category = 'clothing', equipmentSlot = 'pants', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_shoes = { label = 'Shoes', category = 'clothing', equipmentSlot = 'shoes', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_chains = { label = 'Chain', category = 'clothing', equipmentSlot = 'accessory', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_bags = { label = 'Bag', category = 'clothing', equipmentSlot = 'bag', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_hat = { label = 'Hat', category = 'clothing', equipmentSlot = 'headwear', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_glasses = { label = 'Glasses', category = 'clothing', equipmentSlot = 'glasses', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_earrings = { label = 'Earrings', category = 'clothing', equipmentSlot = 'earrings', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },
        clothing_watches = { label = 'Watch', category = 'clothing', equipmentSlot = 'watch', itemType = 'unique', rarity = 'normal', weight = 250, stack = false, usable = true, image = 'clothing.png', description = 'Wearable clothing item.' },

        bag_level1 = { label = 'Small Backpack', category = 'bag', equipmentSlot = 'bag', bagLevel = 1, itemType = 'normal', rarity = 'normal', weight = 800, stack = false, usable = true, image = 'placeholder.png', description = 'Level 1 bag. Unlocks 6 backpack slots.' },
        bag_level2 = { label = 'Medium Backpack', category = 'bag', equipmentSlot = 'bag', bagLevel = 2, itemType = 'rare', rarity = 'rare', weight = 1100, stack = false, usable = true, image = 'placeholder.png', description = 'Level 2 bag. Unlocks 8 backpack slots and more capacity.' },
        bag_level3 = { label = 'Large Backpack', category = 'bag', equipmentSlot = 'bag', bagLevel = 3, itemType = 'unique', rarity = 'unique', weight = 1500, stack = false, usable = true, image = 'placeholder.png', description = 'Level 3 bag. Unlocks all backpack slots.' },
        bag_level4 = { label = 'Elite Backpack', category = 'bag', equipmentSlot = 'bag', bagLevel = 4, itemType = 'unique', rarity = 'unique', weight = 1800, stack = false, usable = true, image = 'placeholder.png', description = 'Level 4 bag. All slots and maximum capacity.' }
    }
}
