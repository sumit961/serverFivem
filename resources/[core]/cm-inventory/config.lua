CMInventory = CMInventory or {}

CMInventory.Config = {
    Debug = false,
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

    -- Tier 2: giving items to nearby players.
    Give = {
        enabled = true,
        distance = 3.0,   -- metres; players within this range are offered as targets
    },

    -- Tier 2: what drops on death.
    Death = {
        dropWeapons = true,   -- equipped gun + ammo drop to the ground on death
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
            medikit = 8000,
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
            medikit = { ms = 5000, label = 'Using medikit...' },
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
        expireMinutes = 1,
        pickupDistance = 2.0,
        markerDistance = 18.0,
        uiDistance = 2.4,
        propStreamDistance = 55.0,
        propDespawnDistance = 70.0,
        groupDistance = 1.2,
        cleanupSeconds = 15,
        markerType = 2,
        defaultProp = 'prop_paper_bag_small',
        PropModels = {
            food = 'prop_food_bs_burger2',
            drink = 'prop_ld_flow_bottle',
            medical = 'prop_ld_health_pack',
            tool = 'prop_tool_box_04',
            weapon = 'w_pi_pistol',
            ammo = 'prop_box_ammo03a',
            clothing = 'prop_ld_suitcase_01',
            armor = 'prop_bodyarmour_03',
            bodyarmor = 'prop_bodyarmour_03',
            bag = 'prop_ld_suitcase_01'
        }
    },

    Give = {
        enabled = true,
        distance = 3.0
    },

    Ammo = {
        enabled = true,
        slot = 'ammo',
        weapons = {
            -- Pistols / SMGs
            weapon_pistol = { ammo = 'ammo_9mm' },
            weapon_combatpistol = { ammo = 'ammo_9mm' },
            weapon_appistol = { ammo = 'ammo_9mm' },
            weapon_pistol_mk2 = { ammo = 'ammo_9mm' },
            weapon_snspistol = { ammo = 'ammo_9mm' },
            weapon_snspistol_mk2 = { ammo = 'ammo_9mm' },
            weapon_vintagepistol = { ammo = 'ammo_9mm' },
            weapon_smg = { ammo = 'ammo_9mm' },
            weapon_smg_mk2 = { ammo = 'ammo_9mm' },
            weapon_microsmg = { ammo = 'ammo_9mm' },
            weapon_minismg = { ammo = 'ammo_9mm' },

            -- Rifles / shotguns. Add these ammo items in cm-items if your gun store sells them.
            weapon_carbinerifle = { ammo = 'ammo_556' },
            weapon_carbinerifle_mk2 = { ammo = 'ammo_556' },
            weapon_assaultrifle = { ammo = 'ammo_556' },
            weapon_assaultrifle_mk2 = { ammo = 'ammo_556' },
            weapon_bullpuprifle = { ammo = 'ammo_556' },
            weapon_compactrifle = { ammo = 'ammo_556' },
            weapon_pumpshotgun = { ammo = 'ammo_shotgun' },
            weapon_pumpshotgun_mk2 = { ammo = 'ammo_shotgun' },
            weapon_sawnoffshotgun = { ammo = 'ammo_shotgun' },
            weapon_heavyshotgun = { ammo = 'ammo_shotgun' },
            weapon_sniperrifle = { ammo = 'ammo_762' },
            weapon_marksmanrifle = { ammo = 'ammo_762' }
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
        { prefix = 'armor_',  def = { label = 'Armor Vest', category = 'armor',  equipmentSlot = 'bodyarmor', itemType = 'rare',   rarity = 'rare',   weight = 2500, stack = false, usable = true, image = 'nui://cm-items/ui/images/medical_armor.svg', description = 'Wearable armor vest.' } },
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
        bandage = 'nui://cm-items/ui/images/medical_bandage.svg',
        medkit = 'nui://cm-items/ui/images/medical_kit.svg',
        medikit = 'nui://cm-items/ui/images/medical_kit.svg',
        armor = 'armor.png',
        repairkit = 'repairkit.png',
        lockpick = 'lockpick.png',
        weapon_pistol = 'weapon_pistol.png',
        ammo_9mm = 'ammo_9mm.png',
        ammo_556 = 'ammo_9mm.png',
        ammo_762 = 'ammo_9mm.png',
        ammo_shotgun = 'ammo_9mm.png',
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
        bandage = { label = 'Bandage', category = 'medical', itemType = 'normal', rarity = 'normal', weight = 100, stack = true, usable = true, image = 'nui://cm-items/ui/images/medical_bandage.svg', description = 'Used to recover small injuries.' },
        medkit = { label = 'Medkit', category = 'medical', itemType = 'rare', rarity = 'rare', weight = 900, stack = true, usable = true, image = 'nui://cm-items/ui/images/medical_kit.svg', description = 'Medical kit for bigger injuries.' },
        medikit = { label = 'Medikit', category = 'medical', itemType = 'rare', rarity = 'rare', weight = 900, stack = true, usable = true, image = 'nui://cm-items/ui/images/medical_kit.svg', description = 'Fully heals you or revives a nearby player.' },
        armor = { label = 'Body Armor', category = 'armor', equipmentSlot = 'bodyarmor', itemType = 'rare', rarity = 'rare', weight = 2500, stack = false, usable = true, image = 'nui://cm-items/ui/images/medical_armor.svg', description = 'Protective body armor.', durability = 100 },
        repairkit = { label = 'Repair Kit', category = 'tool', itemType = 'normal', rarity = 'normal', weight = 1800, stack = true, usable = true, image = 'repairkit.png', description = 'Used to repair a vehicle.', durability = 100 },
        lockpick = { label = 'Lockpick', category = 'tool', itemType = 'normal', rarity = 'normal', weight = 80, stack = true, usable = true, image = 'lockpick.png', description = 'A small lockpicking tool.', durability = 100 },
        id_card = { label = 'ID Card', category = 'document', itemType = 'unique', rarity = 'unique', weight = 50, stack = false, usable = true, image = 'id_card.png', description = 'Personal identification card.' },
        weapon_pistol = { label = 'Pistol', category = 'weapon', equipmentSlot = 'weapon', itemType = 'unique', rarity = 'unique', weight = 1200, stack = false, usable = true, image = 'weapon_pistol.png', description = 'A small firearm.', durability = 100 },
        ammo_9mm = { label = '9mm Ammo', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 15, stack = true, usable = true, image = 'ammo_9mm.png', description = '9mm ammunition.' },
        ammo_556 = { label = '5.56 Ammo', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 18, stack = true, usable = true, image = 'ammo_9mm.png', description = '5.56 rifle ammunition.' },
        ammo_762 = { label = '7.62 Ammo', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 22, stack = true, usable = true, image = 'ammo_9mm.png', description = '7.62 rifle ammunition.' },
        ammo_shotgun = { label = 'Shotgun Shells', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 30, stack = true, usable = true, image = 'ammo_9mm.png', description = 'Shotgun ammunition.' },
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



-- ============================================================
-- CM Weapons ammo sync patch v4.3.0
-- cm-weapons is the source of truth; this fallback keeps inventory
-- using the same 7 fixed ammo items even if cm-weapons is restarting.
-- ============================================================
do
    local C = CMInventory.Config
    C.Ammo = C.Ammo or {}
    C.Ammo.enabled = true
    C.Ammo.slot = C.Ammo.slot or 'ammo'
    C.Ammo.weapons = {
        weapon_pistol = { ammo = 'ammo_9mm' },
        weapon_pistol_mk2 = { ammo = 'ammo_9mm' },
        weapon_combatpistol = { ammo = 'ammo_9mm' },
        weapon_appistol = { ammo = 'ammo_9mm' },
        weapon_pistol50 = { ammo = 'ammo_9mm' },
        weapon_snspistol = { ammo = 'ammo_9mm' },
        weapon_snspistol_mk2 = { ammo = 'ammo_9mm' },
        weapon_heavypistol = { ammo = 'ammo_9mm' },
        weapon_vintagepistol = { ammo = 'ammo_9mm' },
        weapon_ceramicpistol = { ammo = 'ammo_9mm' },
        weapon_marksmanpistol = { ammo = 'ammo_9mm' },
        weapon_revolver = { ammo = 'ammo_44magnum' },
        weapon_revolver_mk2 = { ammo = 'ammo_44magnum' },
        weapon_doubleaction = { ammo = 'ammo_44magnum' },
        weapon_navyrevolver = { ammo = 'ammo_44magnum' },
        weapon_gadgetpistol = { ammo = 'ammo_9mm' },
        weapon_pistolxm3 = { ammo = 'ammo_9mm' },
        weapon_microsmg = { ammo = 'ammo_9x19_smg' },
        weapon_smg = { ammo = 'ammo_9x19_smg' },
        weapon_smg_mk2 = { ammo = 'ammo_9x19_smg' },
        weapon_assaultsmg = { ammo = 'ammo_9x19_smg' },
        weapon_combatpdw = { ammo = 'ammo_9x19_smg' },
        weapon_machinepistol = { ammo = 'ammo_9x19_smg' },
        weapon_minismg = { ammo = 'ammo_9x19_smg' },
        weapon_tecpistol = { ammo = 'ammo_9x19_smg' },
        weapon_assaultrifle = { ammo = 'ammo_556nato' },
        weapon_assaultrifle_mk2 = { ammo = 'ammo_556nato' },
        weapon_carbinerifle = { ammo = 'ammo_556nato' },
        weapon_carbinerifle_mk2 = { ammo = 'ammo_556nato' },
        weapon_advancedrifle = { ammo = 'ammo_556nato' },
        weapon_specialcarbine = { ammo = 'ammo_556nato' },
        weapon_specialcarbine_mk2 = { ammo = 'ammo_556nato' },
        weapon_bullpuprifle = { ammo = 'ammo_556nato' },
        weapon_bullpuprifle_mk2 = { ammo = 'ammo_556nato' },
        weapon_compactrifle = { ammo = 'ammo_556nato' },
        weapon_militaryrifle = { ammo = 'ammo_556nato' },
        weapon_heavyrifle = { ammo = 'ammo_556nato' },
        weapon_battlerifle = { ammo = 'ammo_556nato' },
        weapon_tacticalrifle = { ammo = 'ammo_556nato' },
        weapon_pumpshotgun = { ammo = 'ammo_12gauge' },
        weapon_pumpshotgun_mk2 = { ammo = 'ammo_12gauge' },
        weapon_sawnoffshotgun = { ammo = 'ammo_12gauge' },
        weapon_assaultshotgun = { ammo = 'ammo_12gauge' },
        weapon_bullpupshotgun = { ammo = 'ammo_12gauge' },
        weapon_heavyshotgun = { ammo = 'ammo_12gauge' },
        weapon_dbshotgun = { ammo = 'ammo_12gauge' },
        weapon_autoshotgun = { ammo = 'ammo_12gauge' },
        weapon_combatshotgun = { ammo = 'ammo_12gauge' },
        weapon_sniperrifle = { ammo = 'ammo_308win' },
        weapon_heavysniper = { ammo = 'ammo_308win' },
        weapon_heavysniper_mk2 = { ammo = 'ammo_308win' },
        weapon_marksmanrifle = { ammo = 'ammo_308win' },
        weapon_marksmanrifle_mk2 = { ammo = 'ammo_308win' },
        weapon_precisionrifle = { ammo = 'ammo_308win' },
        weapon_mg = { ammo = 'ammo_762nato' },
        weapon_combatmg = { ammo = 'ammo_762nato' },
        weapon_combatmg_mk2 = { ammo = 'ammo_762nato' },
        weapon_gusenberg = { ammo = 'ammo_762nato' },
        weapon_minigun = { ammo = 'ammo_762nato' },
    }
    C.Ammo.LegacyAliases = {
        ammo_556 = 'ammo_556nato',
        ammo_762 = 'ammo_308win',
        ammo_shotgun = 'ammo_12gauge',
        ammo_smg = 'ammo_9x19_smg',
        ammo_revolver = 'ammo_44magnum'
    }
    C.DefaultImages = C.DefaultImages or {}
    C.DefaultImages.ammo_9mm = C.DefaultImages.ammo_9mm or 'ammo_9mm.png'
    C.DefaultImages.ammo_44magnum = C.DefaultImages.ammo_44magnum or 'ammo_9mm.png'
    C.DefaultImages.ammo_9x19_smg = C.DefaultImages.ammo_9x19_smg or 'ammo_9mm.png'
    C.DefaultImages.ammo_556nato = C.DefaultImages.ammo_556nato or 'ammo_9mm.png'
    C.DefaultImages.ammo_762nato = C.DefaultImages.ammo_762nato or 'ammo_9mm.png'
    C.DefaultImages.ammo_12gauge = C.DefaultImages.ammo_12gauge or 'ammo_9mm.png'
    C.DefaultImages.ammo_308win = C.DefaultImages.ammo_308win or 'ammo_9mm.png'
    C.FallbackItems = C.FallbackItems or {}
    C.FallbackItems.ammo_9mm = { label = '9mm Parabellum', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 8, stack = true, usable = true, image = 'ammo_9mm.png', description = 'Standard pistol round used by every regular pistol on CM.' }
    C.FallbackItems.ammo_44magnum = { label = '.44 Magnum Revolver Round', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 16, stack = true, usable = true, image = 'ammo_9mm.png', description = 'High-power revolver round used by heavy revolvers only.' }
    C.FallbackItems.ammo_9x19_smg = { label = '9x19mm SMG Round', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 9, stack = true, usable = true, image = 'ammo_9mm.png', description = 'Submachine-gun round used by every SMG class weapon.' }
    C.FallbackItems.ammo_556nato = { label = '5.56 NATO Rifle Round', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 13, stack = true, usable = true, image = 'ammo_9mm.png', description = 'Rifle round used by every assault and carbine rifle.' }
    C.FallbackItems.ammo_762nato = { label = '7.62 NATO MG Belt Round', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 18, stack = true, usable = true, image = 'ammo_9mm.png', description = 'Machine-gun round used by MG class weapons.' }
    C.FallbackItems.ammo_12gauge = { label = '12 Gauge Shotgun Shell', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 20, stack = true, usable = true, image = 'ammo_9mm.png', description = 'Shotgun shell used by every shotgun.' }
    C.FallbackItems.ammo_308win = { label = '.308 Winchester Sniper Round', category = 'ammo', equipmentSlot = 'ammo', itemType = 'normal', rarity = 'normal', weight = 28, stack = true, usable = true, image = 'ammo_9mm.png', description = 'Sniper round used by every sniper and marksman rifle.' }
    C.Use = C.Use or {}; C.Use.cooldowns = C.Use.cooldowns or {}; C.Use.progress = C.Use.progress or {}
    C.Use.cooldowns.ammo_9mm = C.Use.cooldowns.ammo_9mm or 650
    C.Use.progress.ammo_9mm = C.Use.progress.ammo_9mm or { ms = 650, label = 'Preparing ammo...' }
    C.Use.cooldowns.ammo_44magnum = C.Use.cooldowns.ammo_44magnum or 650
    C.Use.progress.ammo_44magnum = C.Use.progress.ammo_44magnum or { ms = 650, label = 'Preparing ammo...' }
    C.Use.cooldowns.ammo_9x19_smg = C.Use.cooldowns.ammo_9x19_smg or 650
    C.Use.progress.ammo_9x19_smg = C.Use.progress.ammo_9x19_smg or { ms = 650, label = 'Preparing ammo...' }
    C.Use.cooldowns.ammo_556nato = C.Use.cooldowns.ammo_556nato or 650
    C.Use.progress.ammo_556nato = C.Use.progress.ammo_556nato or { ms = 650, label = 'Preparing ammo...' }
    C.Use.cooldowns.ammo_762nato = C.Use.cooldowns.ammo_762nato or 650
    C.Use.progress.ammo_762nato = C.Use.progress.ammo_762nato or { ms = 650, label = 'Preparing ammo...' }
    C.Use.cooldowns.ammo_12gauge = C.Use.cooldowns.ammo_12gauge or 650
    C.Use.progress.ammo_12gauge = C.Use.progress.ammo_12gauge or { ms = 650, label = 'Preparing ammo...' }
    C.Use.cooldowns.ammo_308win = C.Use.cooldowns.ammo_308win or 650
    C.Use.progress.ammo_308win = C.Use.progress.ammo_308win or { ms = 650, label = 'Preparing ammo...' }
end
