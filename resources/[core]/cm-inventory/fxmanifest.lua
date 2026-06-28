fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CM Development'
description 'CM Inventory v3.9.1 - metadata and bag display cleanup'
version '3.9.1'

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
