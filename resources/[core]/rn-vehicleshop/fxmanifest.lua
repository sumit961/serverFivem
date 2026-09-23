fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '3.3.0-safe-model-replacement'
author 'RN Vehicleshop adapted for CM Framework'

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
    'ui/vendor/jquery.min.js',
    'ui/vendor/slick-lite.js',
    'ui/vendor/slick-lite.css',
    'ui/vendor/fa-lite.css',
    'ui/images/vehicles/*.png',
    'ui/images/vehicles/*.webp',
}




dependencies {
    'oxmysql',
    'cm-vehicles',
    'cm-tuning',       -- EMS appearance editor: GetVisualCatalog (paint/livery/wheel/tyre/neon options)
    'cm-playerdata',   -- money: GetMoney / RemoveMoney / AddMoney / GetAccounts
    'cm-core',         -- character resolution only
    'cm-house',        -- assign purchased vehicles to an owned garage slot
    'cm-ui',           -- shared "Press E" interact prompt + cinematic NPC dialogue
    'screenshot-basic',
}
