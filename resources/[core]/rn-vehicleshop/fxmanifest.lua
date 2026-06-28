fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '2.0.0-cm-adapted'
author 'RN Vehicleshop adapted for CM Framework'
description 'Vehicle shop with CM ownership, vehicleadmin catalog, and dealership map'

this_is_a_map 'yes'

shared_script 'config.lua'

client_scripts {
    'client/capture.lua',
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/main.js',
    'ui/images/vehicles/*.png',
    'ui/images/vehicles/*.webp',
    'stream/*.ytyp',
}

data_file 'DLC_ITYP_REQUEST' 'stream/vstudios_udxm.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/vstudios_udxm_dealer.ytyp'

escrow_ignore {
    'stream/ch1_07_build01.ydr',
}

dependencies {
    'oxmysql',
    'cm-vehicles',
    'cm-core',
    'screenshot-basic',
    '/assetpacks'
}