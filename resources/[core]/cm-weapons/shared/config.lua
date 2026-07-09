Config = Config or {}

Config.Debug = false
Config.AdminAce = 'cm.weapons.admin'
Config.AdminCommand = 'cmweaponadmin'
Config.InventoryResource = 'cm-inventory'
Config.ItemsResource = 'cm-items'

-- Fixed catalog mode: guns/ammo are defined in shared/defaults.lua.
-- Admin panel can upload/replace item images only; damage, weight, ammo link,
-- description, magazine size, and enabled state are config-controlled.
Config.FixedCatalogOnly = true
Config.StrictFixedCatalog = true
Config.AllowAdminImagePath = true

-- Avoid DB spam when cm-gunstore asks for many definitions.
Config.ExportCacheMs = 2500

-- Sync config defaults into DB every start. Existing custom uploaded images are preserved.
Config.SeedDefaults = true
Config.SyncDefaultsToCmItems = true
Config.SyncDbRowsToCmItemsOnStart = true

-- Weapon damage is stored here as your server rule.
-- Real GTA damage multiplier is optional and OFF by default so it does not break balance by surprise.
Config.UseClientDamageModifier = false
Config.DamageModifierBase = 30.0

-- Seven ammo families only. No RPG / grenade launcher / explosive ammo here.
Config.AmmoPickupHashes = {
    pistol = 544828034,      -- PICKUP_AMMO_PISTOL
    revolver = 544828034,    -- GTA has no separate revolver pickup; inventory item is separate.
    smg = 292537574,         -- PICKUP_AMMO_SMG
    rifle = 3837603782,      -- PICKUP_AMMO_RIFLE
    mg = 3730366643,         -- PICKUP_AMMO_MG
    shotgun = 2012476125,    -- PICKUP_AMMO_SHOTGUN
    sniper = 3224170789      -- PICKUP_AMMO_SNIPER
}

Config.AmmoGroups = {
    { key = 'pistol', label = '9mm Parabellum', pickupHash = Config.AmmoPickupHashes.pistol },
    { key = 'revolver', label = '.44 Magnum', pickupHash = Config.AmmoPickupHashes.revolver },
    { key = 'smg', label = '9x19mm SMG', pickupHash = Config.AmmoPickupHashes.smg },
    { key = 'rifle', label = '5.56 NATO Rifle', pickupHash = Config.AmmoPickupHashes.rifle },
    { key = 'mg', label = '7.62 NATO Machine Gun', pickupHash = Config.AmmoPickupHashes.mg },
    { key = 'shotgun', label = '12 Gauge Shotgun', pickupHash = Config.AmmoPickupHashes.shotgun },
    { key = 'sniper', label = '.308 Winchester Sniper', pickupHash = Config.AmmoPickupHashes.sniper }
}

-- Used if an inventory wants a normal object drop instead of GTA pickup hash.
Config.AmmoDropModels = {
    pistol = 'prop_ld_ammo_pack_01',
    revolver = 'prop_ld_ammo_pack_01',
    smg = 'prop_ld_ammo_pack_02',
    rifle = 'prop_ld_ammo_pack_03',
    mg = 'prop_box_ammo03a',
    shotgun = 'prop_box_ammo04a',
    sniper = 'prop_box_ammo03a'
}
