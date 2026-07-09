Config = Config or {}

Config.Debug = false
Config.AdminAce = 'cm.weapons.admin'
Config.AdminCommand = 'cmweaponadmin'
Config.InventoryResource = 'cm-inventory'
Config.ItemsResource = 'cm-items'

-- If true, default ammo/weapons below are inserted only when missing.
-- It will NOT overwrite admin-edited rows.
Config.SeedDefaults = true
Config.SyncDefaultsToCmItems = true
Config.SyncDbRowsToCmItemsOnStart = true

-- Weapon damage is stored here as your server rule.
-- Real GTA damage multiplier is optional and OFF by default so it does not break balance by surprise.
Config.UseClientDamageModifier = false
Config.DamageModifierBase = 30.0

-- User supplied pickup hashes. These are used by cm-inventory/drop systems through exports.
Config.AmmoPickupHashes = {
    pistol = 544828034,              -- PICKUP_AMMO_PISTOL
    smg = 292537574,                 -- PICKUP_AMMO_SMG
    rifle = 3837603782,              -- PICKUP_AMMO_RIFLE
    mg = 3730366643,                 -- PICKUP_AMMO_MG
    shotgun = 2012476125,            -- PICKUP_AMMO_SHOTGUN
    sniper = 3224170789,             -- PICKUP_AMMO_SNIPER
    grenade = 2283450536,            -- PICKUP_AMMO_GRENADELAUNCHER
    rocket = 2223210455,             -- PICKUP_AMMO_RPG
    minigun = 4065984953             -- PICKUP_AMMO_MINIGUN
}

Config.AmmoGroups = {
    { key = 'pistol', label = 'Pistol Ammo', pickupHash = Config.AmmoPickupHashes.pistol },
    { key = 'smg', label = 'SMG Ammo', pickupHash = Config.AmmoPickupHashes.smg },
    { key = 'rifle', label = 'Rifle Ammo', pickupHash = Config.AmmoPickupHashes.rifle },
    { key = 'mg', label = 'MG Ammo', pickupHash = Config.AmmoPickupHashes.mg },
    { key = 'shotgun', label = 'Shotgun Ammo', pickupHash = Config.AmmoPickupHashes.shotgun },
    { key = 'sniper', label = 'Sniper Ammo', pickupHash = Config.AmmoPickupHashes.sniper },
    { key = 'grenade', label = 'Grenade Launcher Ammo', pickupHash = Config.AmmoPickupHashes.grenade },
    { key = 'rocket', label = 'RPG/Rocket Ammo', pickupHash = Config.AmmoPickupHashes.rocket },
    { key = 'minigun', label = 'Minigun Ammo', pickupHash = Config.AmmoPickupHashes.minigun }
}

-- Used if an inventory wants a normal object drop instead of GTA pickup hash.
Config.AmmoDropModels = {
    pistol = 'prop_ld_ammo_pack_01',
    smg = 'prop_ld_ammo_pack_02',
    rifle = 'prop_ld_ammo_pack_03',
    mg = 'prop_ld_ammo_pack_03',
    shotgun = 'prop_box_ammo04a',
    sniper = 'prop_box_ammo03a',
    grenade = 'prop_box_ammo07a',
    rocket = 'prop_ld_ammo_pack_03',
    minigun = 'prop_ld_ammo_pack_03'
}
