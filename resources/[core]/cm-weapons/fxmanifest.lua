fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-weapons'
author 'Sumit Yadav / CM Framework'
description 'Central CM weapon and ammo registry. Saves weapons/ammo, syncs to cm-items, exposes pickup hashes and weapon rules.'
version '1.3.1'

ui_page 'web/index.html'

shared_scripts {
    'shared/config.lua',
    'shared/defaults.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/images/*.svg',
    'web/images/custom/*.png',
    'web/images/custom/*.jpg',
    'web/images/custom/*.jpeg',
    'web/images/custom/*.webp'
}

dependencies {
    'oxmysql',
    'cm-items'
}
