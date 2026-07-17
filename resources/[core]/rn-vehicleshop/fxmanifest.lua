fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '3.0.1-family-image-export'
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
    'cm-playerdata',   -- money: GetMoney / RemoveMoney / AddMoney / GetAccounts
    'cm-core',         -- character resolution only
    'screenshot-basic',
}