fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Development'
description 'CM Inventory v4.2 - gun-slot-only weapons, fast access swapping, prop drops'
version '4.2.0'

dependencies {
    'oxmysql',
    'cm-items'
}

shared_scripts {
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/images/*.png',
    'ui/images/*.jpg',
    'ui/images/*.webp'
}
