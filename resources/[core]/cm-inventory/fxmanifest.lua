fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Development'
description 'CM Inventory v4.1 - shared 6x5 external storage UI'
version '4.1.0'

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
