Config = Config or {}

local DOC_IMG = 'https://docs-backend.fivem.net/weapons/%s.png'
local function img(hash) return DOC_IMG:format(hash) end

-- Fixed ammo list. The LABEL can be 9mm/7mm/etc, but ammoKey controls which GTA pickup hash is used on drop.
-- Store prices are NOT managed here. /gunadmin controls sale price and store visibility.
Config.DefaultAmmo = {
    { itemName = 'ammo_9mm',       label = '9mm Ammo',       ammoKey = 'pistol',  packSize = 30, weight = 10,  enabled = true, description = '9mm pistol rounds.' },
    { itemName = 'ammo_45acp',     label = '.45 ACP Ammo',   ammoKey = 'pistol',  packSize = 30, weight = 11,  enabled = true, description = '.45 ACP pistol rounds.' },
    { itemName = 'ammo_smg_9mm',   label = 'SMG 9mm Ammo',   ammoKey = 'smg',     packSize = 60, weight = 10,  enabled = true, description = '9mm SMG rounds.' },
    { itemName = 'ammo_556',       label = '5.56 Rifle Ammo',ammoKey = 'rifle',   packSize = 60, weight = 13,  enabled = true, description = '5.56 rifle rounds.' },
    { itemName = 'ammo_762',       label = '7.62 Rifle Ammo',ammoKey = 'rifle',   packSize = 60, weight = 15,  enabled = true, description = '7.62 rifle rounds.' },
    { itemName = 'ammo_mg_762',    label = '7.62 MG Ammo',   ammoKey = 'mg',      packSize = 100, weight = 17,  enabled = false, description = 'Machine gun belt/box ammo.' },
    { itemName = 'ammo_12gauge',   label = '12 Gauge Shells',ammoKey = 'shotgun', packSize = 20, weight = 18,  enabled = true, description = 'Shotgun shells.' },
    { itemName = 'ammo_308',       label = '.308 Sniper Ammo',ammoKey = 'sniper', packSize = 10, weight = 22,  enabled = false, description = 'Sniper rifle rounds.' },
    { itemName = 'ammo_40mm',      label = '40mm Grenades',  ammoKey = 'grenade', packSize = 1, weight = 400, enabled = false, description = 'Grenade launcher round.' },
    { itemName = 'ammo_rocket',    label = 'Rocket Ammo',    ammoKey = 'rocket',  packSize = 1, weight = 1200,enabled = false, description = 'RPG/rocket round.' },
    { itemName = 'ammo_minigun',   label = 'Minigun Ammo',   ammoKey = 'minigun', packSize = 250,weight = 20,  enabled = false, description = 'Minigun rounds.' }
}

-- Fixed weapon list. Damage belongs to the GUN, not ammo.
-- Store prices are NOT managed here. /gunadmin controls sale price and store visibility.
-- Many guns can use the same ammo item.
Config.DefaultWeapons = {
    -- Pistols
    { itemName = 'weapon_pistol',          label = 'Pistol',                 weaponHash = 'WEAPON_PISTOL',          group = 'pistol',  ammoItem = 'ammo_9mm',     damage = 26, magazineSize = 12,  weight = 1100, enabled = true },
    { itemName = 'weapon_pistol_mk2',      label = 'Pistol Mk II',           weaponHash = 'WEAPON_PISTOL_MK2',      group = 'pistol',  ammoItem = 'ammo_9mm',     damage = 28, magazineSize = 12, weight = 1200, enabled = false },
    { itemName = 'weapon_combatpistol',    label = 'Combat Pistol',          weaponHash = 'WEAPON_COMBATPISTOL',    group = 'pistol',  ammoItem = 'ammo_9mm',     damage = 27, magazineSize = 12,  weight = 1100, enabled = true },
    { itemName = 'weapon_appistol',        label = 'AP Pistol',              weaponHash = 'WEAPON_APPISTOL',        group = 'pistol',  ammoItem = 'ammo_9mm',     damage = 24, magazineSize = 18, weight = 1150, enabled = false },
    { itemName = 'weapon_pistol50',        label = 'Pistol .50',             weaponHash = 'WEAPON_PISTOL50',        group = 'pistol',  ammoItem = 'ammo_45acp',   damage = 51, magazineSize = 9, weight = 1400, enabled = false },
    { itemName = 'weapon_snspistol',       label = 'SNS Pistol',             weaponHash = 'WEAPON_SNSPISTOL',       group = 'pistol',  ammoItem = 'ammo_9mm',     damage = 25, magazineSize = 6, weight = 900,  enabled = true },
    { itemName = 'weapon_heavypistol',     label = 'Heavy Pistol',           weaponHash = 'WEAPON_HEAVYPISTOL',     group = 'pistol',  ammoItem = 'ammo_45acp',   damage = 40, magazineSize = 18, weight = 1300, enabled = false },
    { itemName = 'weapon_vintagepistol',   label = 'Vintage Pistol',         weaponHash = 'WEAPON_VINTAGEPISTOL',   group = 'pistol',  ammoItem = 'ammo_9mm',     damage = 30, magazineSize = 7, weight = 1000, enabled = false },
    { itemName = 'weapon_revolver',        label = 'Heavy Revolver',         weaponHash = 'WEAPON_REVOLVER',        group = 'pistol',  ammoItem = 'ammo_45acp',   damage = 70, magazineSize = 6, weight = 1500, enabled = false },

    -- SMG
    { itemName = 'weapon_microsmg',        label = 'Micro SMG',              weaponHash = 'WEAPON_MICROSMG',        group = 'smg',     ammoItem = 'ammo_smg_9mm', damage = 22, magazineSize = 16, weight = 2000, enabled = false },
    { itemName = 'weapon_smg',             label = 'SMG',                    weaponHash = 'WEAPON_SMG',             group = 'smg',     ammoItem = 'ammo_smg_9mm', damage = 23, magazineSize = 30, weight = 2600, enabled = false },
    { itemName = 'weapon_smg_mk2',         label = 'SMG Mk II',              weaponHash = 'WEAPON_SMG_MK2',         group = 'smg',     ammoItem = 'ammo_smg_9mm', damage = 25, magazineSize = 30, weight = 2700, enabled = false },
    { itemName = 'weapon_assaultsmg',      label = 'Assault SMG',            weaponHash = 'WEAPON_ASSAULTSMG',      group = 'smg',     ammoItem = 'ammo_smg_9mm', damage = 24, magazineSize = 30, weight = 2800, enabled = false },
    { itemName = 'weapon_combatpdw',       label = 'Combat PDW',             weaponHash = 'WEAPON_COMBATPDW',       group = 'smg',     ammoItem = 'ammo_smg_9mm', damage = 25, magazineSize = 30, weight = 2900, enabled = false },
    { itemName = 'weapon_machinepistol',   label = 'Machine Pistol',         weaponHash = 'WEAPON_MACHINEPISTOL',   group = 'smg',     ammoItem = 'ammo_smg_9mm', damage = 21, magazineSize = 12, weight = 1400, enabled = false },
    { itemName = 'weapon_minismg',         label = 'Mini SMG',               weaponHash = 'WEAPON_MINISMG',         group = 'smg',     ammoItem = 'ammo_smg_9mm', damage = 22, magazineSize = 20, weight = 1800, enabled = false },

    -- Rifles
    { itemName = 'weapon_assaultrifle',    label = 'Assault Rifle',          weaponHash = 'WEAPON_ASSAULTRIFLE',    group = 'rifle',   ammoItem = 'ammo_762',     damage = 30, magazineSize = 30, weight = 3500, enabled = false },
    { itemName = 'weapon_assaultrifle_mk2',label = 'Assault Rifle Mk II',    weaponHash = 'WEAPON_ASSAULTRIFLE_MK2',group = 'rifle',   ammoItem = 'ammo_762',     damage = 33, magazineSize = 30, weight = 3600, enabled = false },
    { itemName = 'weapon_carbinerifle',    label = 'Carbine Rifle',          weaponHash = 'WEAPON_CARBINERIFLE',    group = 'rifle',   ammoItem = 'ammo_556',     damage = 32, magazineSize = 30, weight = 3700, enabled = false },
    { itemName = 'weapon_carbinerifle_mk2',label = 'Carbine Rifle Mk II',    weaponHash = 'WEAPON_CARBINERIFLE_MK2',group = 'rifle',   ammoItem = 'ammo_556',     damage = 34, magazineSize = 30, weight = 3800, enabled = false },
    { itemName = 'weapon_advancedrifle',   label = 'Advanced Rifle',         weaponHash = 'WEAPON_ADVANCEDRIFLE',   group = 'rifle',   ammoItem = 'ammo_556',     damage = 30, magazineSize = 30, weight = 3400, enabled = false },
    { itemName = 'weapon_specialcarbine',  label = 'Special Carbine',        weaponHash = 'WEAPON_SPECIALCARBINE',  group = 'rifle',   ammoItem = 'ammo_556',     damage = 32, magazineSize = 30, weight = 3600, enabled = false },
    { itemName = 'weapon_bullpuprifle',    label = 'Bullpup Rifle',          weaponHash = 'WEAPON_BULLPUPRIFLE',    group = 'rifle',   ammoItem = 'ammo_556',     damage = 30, magazineSize = 30, weight = 3400, enabled = false },
    { itemName = 'weapon_compactrifle',    label = 'Compact Rifle',          weaponHash = 'WEAPON_COMPACTRIFLE',    group = 'rifle',   ammoItem = 'ammo_762',     damage = 29, magazineSize = 30, weight = 3000, enabled = false },
    { itemName = 'weapon_militaryrifle',   label = 'Military Rifle',         weaponHash = 'WEAPON_MILITARYRIFLE',   group = 'rifle',   ammoItem = 'ammo_556',     damage = 34, magazineSize = 30, weight = 3700, enabled = false },
    { itemName = 'weapon_heavyrifle',      label = 'Heavy Rifle',            weaponHash = 'WEAPON_HEAVYRIFLE',      group = 'rifle',   ammoItem = 'ammo_762',     damage = 36, magazineSize = 30, weight = 3800, enabled = false },
    { itemName = 'weapon_tacticalrifle',   label = 'Service Carbine',        weaponHash = 'WEAPON_TACTICALRIFLE',   group = 'rifle',   ammoItem = 'ammo_556',     damage = 32, magazineSize = 30, weight = 3600, enabled = false },

    -- Shotgun
    { itemName = 'weapon_pumpshotgun',     label = 'Pump Shotgun',           weaponHash = 'WEAPON_PUMPSHOTGUN',     group = 'shotgun', ammoItem = 'ammo_12gauge', damage = 60, magazineSize = 8, weight = 3800, enabled = false },
    { itemName = 'weapon_sawnoffshotgun',  label = 'Sawed-Off Shotgun',      weaponHash = 'WEAPON_SAWNOFFSHOTGUN',  group = 'shotgun', ammoItem = 'ammo_12gauge', damage = 75, magazineSize = 2, weight = 3000, enabled = false },
    { itemName = 'weapon_assaultshotgun',  label = 'Assault Shotgun',        weaponHash = 'WEAPON_ASSAULTSHOTGUN',  group = 'shotgun', ammoItem = 'ammo_12gauge', damage = 55, magazineSize = 8, weight = 4000, enabled = false },
    { itemName = 'weapon_bullpupshotgun',  label = 'Bullpup Shotgun',        weaponHash = 'WEAPON_BULLPUPSHOTGUN',  group = 'shotgun', ammoItem = 'ammo_12gauge', damage = 58, magazineSize = 14, weight = 3900, enabled = false },
    { itemName = 'weapon_dbshotgun',       label = 'Double Barrel Shotgun',  weaponHash = 'WEAPON_DBSHOTGUN',       group = 'shotgun', ammoItem = 'ammo_12gauge', damage = 80, magazineSize = 2, weight = 3200, enabled = false },

    -- Sniper / Heavy
    { itemName = 'weapon_sniperrifle',     label = 'Sniper Rifle',           weaponHash = 'WEAPON_SNIPERRIFLE',     group = 'sniper',  ammoItem = 'ammo_308',     damage = 101, magazineSize = 10,weight = 5000, enabled = false },
    { itemName = 'weapon_heavysniper',     label = 'Heavy Sniper',           weaponHash = 'WEAPON_HEAVYSNIPER',     group = 'sniper',  ammoItem = 'ammo_308',     damage = 216, magazineSize = 6, weight = 5500, enabled = false },
    { itemName = 'weapon_marksmanrifle',   label = 'Marksman Rifle',         weaponHash = 'WEAPON_MARKSMANRIFLE',   group = 'sniper',  ammoItem = 'ammo_308',     damage = 65,  magazineSize = 8, weight = 4800, enabled = false },
    { itemName = 'weapon_grenadelauncher', label = 'Grenade Launcher',       weaponHash = 'WEAPON_GRENADELAUNCHER', group = 'heavy',   ammoItem = 'ammo_40mm',    damage = 120, magazineSize = 10,weight = 5000, enabled = false },
    { itemName = 'weapon_rpg',             label = 'RPG',                    weaponHash = 'WEAPON_RPG',             group = 'heavy',   ammoItem = 'ammo_rocket',  damage = 220, magazineSize = 1, weight = 7000, enabled = false },
    { itemName = 'weapon_minigun',         label = 'Minigun',                weaponHash = 'WEAPON_MINIGUN',         group = 'heavy',   ammoItem = 'ammo_minigun', damage = 30,  magazineSize = 250,weight = 9000, enabled = false }
}

for _, weapon in ipairs(Config.DefaultWeapons) do
    weapon.image = weapon.image or img(weapon.weaponHash)
end
