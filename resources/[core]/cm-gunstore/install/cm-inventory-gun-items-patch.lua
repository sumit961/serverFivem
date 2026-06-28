-- OPTIONAL BUT RECOMMENDED
-- Add this into cm-inventory/config.lua inside CMInventory.Config after the config table exists,
-- or merge the entries into your existing FallbackItems, DefaultImages, Use, and Ammo sections.
-- Without these definitions, cm-inventory may reject weapons/ammo that cm-items does not know.

CMInventory = CMInventory or {}
CMInventory.Config = CMInventory.Config or {}
CMInventory.Config.FallbackItems = CMInventory.Config.FallbackItems or {}
CMInventory.Config.DefaultImages = CMInventory.Config.DefaultImages or {}
CMInventory.Config.Ammo = CMInventory.Config.Ammo or { enabled = true, slot = 'ammo', weapons = {} }
CMInventory.Config.Ammo.weapons = CMInventory.Config.Ammo.weapons or {}
CMInventory.Config.Use = CMInventory.Config.Use or { cooldowns = {}, progress = {} }
CMInventory.Config.Use.cooldowns = CMInventory.Config.Use.cooldowns or {}
CMInventory.Config.Use.progress = CMInventory.Config.Use.progress or {}

local function nuiImage(file)
    return ('nui://cm-gunstore/web/images/%s'):format(file)
end

local weaponItems = {
    weapon_pistol = { label = 'Pistol', image = 'weapon_pistol.svg', ammo = 'ammo_9mm', weight = 1200, description = 'Standard sidearm.' },
    weapon_combatpistol = { label = 'Combat Pistol', image = 'weapon_combatpistol.svg', ammo = 'ammo_9mm', weight = 1300, description = 'Compact combat sidearm.' },
    weapon_appistol = { label = 'AP Pistol', image = 'weapon_appistol.svg', ammo = 'ammo_9mm', weight = 1350, description = 'Automatic pistol.' },
    weapon_smg = { label = 'SMG', image = 'weapon_smg.svg', ammo = 'ammo_9mm', weight = 2600, description = 'Compact submachine gun.' },
    weapon_pumpshotgun = { label = 'Pump Shotgun', image = 'weapon_pumpshotgun.svg', ammo = 'ammo_shotgun', weight = 3800, description = 'Pump-action shotgun.' },
    weapon_carbinerifle = { label = 'Carbine Rifle', image = 'weapon_carbinerifle.svg', ammo = 'ammo_rifle', weight = 4200, description = 'Rifle platform.' }
}

for itemName, data in pairs(weaponItems) do
    CMInventory.Config.DefaultImages[itemName] = nuiImage(data.image)
    CMInventory.Config.FallbackItems[itemName] = {
        label = data.label,
        category = 'weapon',
        equipmentSlot = 'weapon',
        itemType = 'unique',
        rarity = 'unique',
        weight = data.weight,
        stack = false,
        usable = true,
        image = nuiImage(data.image),
        description = data.description,
        durability = 100
    }
    CMInventory.Config.Ammo.weapons[itemName] = { ammo = data.ammo }
    CMInventory.Config.Use.cooldowns[itemName] = 1200
    CMInventory.Config.Use.progress[itemName] = { ms = 900, label = 'Equipping weapon...' }
end

local ammoItems = {
    ammo_9mm = { label = '9mm Ammo', image = 'ammo_9mm.svg', weight = 15, description = '9mm ammunition.' },
    ammo_shotgun = { label = 'Shotgun Shells', image = 'ammo_shotgun.svg', weight = 30, description = 'Shotgun shells.' },
    ammo_rifle = { label = 'Rifle Ammo', image = 'ammo_rifle.svg', weight = 22, description = 'Rifle ammunition.' }
}

for itemName, data in pairs(ammoItems) do
    CMInventory.Config.DefaultImages[itemName] = nuiImage(data.image)
    CMInventory.Config.FallbackItems[itemName] = {
        label = data.label,
        category = 'ammo',
        equipmentSlot = 'ammo',
        itemType = 'normal',
        rarity = 'normal',
        weight = data.weight,
        stack = true,
        usable = true,
        image = nuiImage(data.image),
        description = data.description
    }
    CMInventory.Config.Use.cooldowns[itemName] = 800
    CMInventory.Config.Use.progress[itemName] = { ms = 650, label = 'Preparing ammo...' }
end


local armorItems = {
    armor_light = { label = 'Light Armor Vest', image = 'armor_light.svg', weight = 2500, armor = 35, description = 'Light protection vest. Adds 35 armor when used.' },
    armor_heavy = { label = 'Heavy Armor Vest', image = 'armor_heavy.svg', weight = 4500, armor = 100, description = 'Heavy tactical vest. Adds 100 armor when used.' }
}

for itemName, data in pairs(armorItems) do
    CMInventory.Config.DefaultImages[itemName] = nuiImage(data.image)
    CMInventory.Config.FallbackItems[itemName] = {
        label = data.label,
        category = 'armor',
        equipmentSlot = 'armor',
        itemType = 'normal',
        rarity = 'rare',
        weight = data.weight,
        stack = false,
        usable = true,
        image = nuiImage(data.image),
        description = data.description,
        armorValue = data.armor
    }
    CMInventory.Config.Use.cooldowns[itemName] = 1800
    CMInventory.Config.Use.progress[itemName] = { ms = 1200, label = 'Putting on armor...' }
end

-- Generic wearable armor vest support. Custom armor_* items created from cm-gunstore admin
-- carry component/drawable/texture metadata and are handled by cm-itemactions.
CMInventory.Config.Use.cooldowns.armor_light = CMInventory.Config.Use.cooldowns.armor_light or 1800
CMInventory.Config.Use.cooldowns.armor_heavy = CMInventory.Config.Use.cooldowns.armor_heavy or 1800
