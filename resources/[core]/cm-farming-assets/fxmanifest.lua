fx_version 'cerulean'
game 'gta5'

description 'CM Farming Assets - streamed crop/seedling props used by cm-farming'
author 'CM Framework'
version '1.0.0'

-- Hand-authored manifest. The original third-party source folders these
-- files were pulled from (resources/outside/0r-farming-v2/0r_farming_assets,
-- 0r_plant_assets, 0r_plantsnew) had their fxmanifest.lua tampered with by a
-- cracking group -- each injected an obfuscated `lb-phoneapp` loader script
-- behind a "decrypted by <discord link>" banner. None of that is present
-- here: this manifest only registers the actual stream archetypes below.

data_file 'DLC_ITYP_REQUEST' 'stream/0r_farming_props.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/0r_plant.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/0r_plantsnew.ytyp'

files {
    'stream/0r_farming_props.ytyp',
    'stream/0r_plant.ytyp',
    'stream/0r_plantsnew.ytyp',
    'stream/prop_veg_crop_daisy.ydr',
    'stream/prop_veg_crop_green.ydr',
    'stream/prop_veg_crop_poppy.ydr',
    'stream/prop_veg_crop_rose.ydr',
    'stream/0r_melon.ydr',
    'stream/0r_sapling.ydr',
    'stream/prop_veg_crop_03_cab.yft',
    'stream/res_markers.ytd',
}
