fx_version 'cerulean'
game 'gta5'

name 'cm-store'
author 'CM'
description 'Convenience store system with gas-station styled UI, ownership, overstock, cm-ui E-interact and NPC dialogue.'
version '2.0.0'
lua54 'yes'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/images/*.svg',
    'web/images/custom/*.png',
    'web/images/custom/*.jpg',
    'web/images/custom/*.jpeg',
    'web/images/custom/*.webp',
    'sql/001_cm_store.sql'
}

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'cm-core',
    'cm-playerdata',
    'cm-inventory',
    'cm-items',
    'cm-ui',
    'oxmysql'
}
