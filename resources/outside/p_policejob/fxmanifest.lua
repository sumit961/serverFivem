fx_version 'cerulean'
game 'gta5'
author 'pScripts [pscripts-store.com]'
description 'Police Job v3 [BETA]'
lua54 'yes'
version '3.0.0'

ui_page 'web/build/index.html'

dependencies {
	'p_bridge', -- https://github.com/PiotreeQ/p_bridge
	'object_gizmo', -- https://github.com/DemiAutomatic/object_gizmo
	'ox_lib' -- https://github.com/overextended/ox_lib
}

client_scripts {
	'editable/client.lua',
	'modules/**/client.lua',
	'modules/prison/client_mugshot.lua',
	'modules/prison/client_management.lua',
	'modules/prison/client_shops.lua',
	'modules/prison/client_npcs.lua',
	'modules/prison/client_jobs.lua',
	'modules/prison/client_officer_tasks.lua',
	'modules/prison/client_community.lua',
	'modules/prison/client_cell_stash.lua',
	'modules/departments/client_armoury.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'config/server.lua',
	'editable/server.lua',
	'modules/**/server.lua',
	'modules/departments/server_armoury.lua'
}

escrow_ignore {
	'config/server.lua',
	'editable/client.lua',
	'editable/server.lua',
	'modules/handsup/client.lua',
	'modules/garage/server.lua',
	'config/shared.lua',
	'modules/**/config.lua',
	'modules/vehicleshop/server.lua',
	'modules/vests/client.lua',
	'maps/departments/*.lua',
	'maps/prisons/*.lua',
}

files {
	'web/handradar.html',
	'web/build/index.html',
	'web/build/**/*',
	'web/build/sounds/*.ogg',
	'web/build/assets/*.webp',
	'web/build/assets/*.png',
  	'locales/*.json',
	'maps/departments/*.lua',
	'maps/prisons/*.lua',
	'trunks.json',
	'stream/meta/*.meta',
	'stream/meta2/*.meta',
}

shared_scripts {
	'@ox_lib/init.lua',
	'@p_bridge/imports.lua',
	'config/shared.lua',
	'modules/**/config.lua'
}

data_file 'DLC_ITYP_REQUEST' 'stream/bzzz_lumberjack_wood_pack.ytyp'
-- CREDITS TO PROPS https://bzzz.tebex.io/

data_file 'DLC_ITYP_REQUEST' 'stream/prop_trackingband_01.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/props.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/e_ducktape.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/e_ch.ytyp.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/clamp.ytyp'
data_file "DLC_ITYP_REQUEST" 'stream/cuffs_main.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/rambar.ytyp'

data_file 'WEAPON_METADATA_FILE' 'stream/meta/weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'stream/meta/weaponanimations.meta'
data_file 'PED_PERSONALITY_FILE' 'stream/meta/pedpersonality.meta'
data_file 'WEAPONINFO_FILE' 'stream/meta/weapons.meta'

data_file 'WEAPON_METADATA_FILE' 'stream/meta2/weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'stream/meta2/weaponanimations.meta'
data_file 'PED_PERSONALITY_FILE' 'stream/meta2/pedpersonality.meta'
data_file 'WEAPONINFO_FILE' 'stream/meta2/weapons.meta'
data_file 'LOADOUTSFILE' 'stream/meta2/loadouts.meta'
data_file 'CONTENT_UNLOCKING_META_FILE' 'stream/meta2/contentunlocks.meta'
dependency '/assetpacks'