fx_version 'cerulean'
game 'gta5'
lua54 'yes'

version '2.6.0-v15-admin-timer-capture-fix'
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
    'cm-core',
    'screenshot-basic',
}