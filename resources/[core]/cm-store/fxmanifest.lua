fx_version 'cerulean'
game 'gta5'

name 'cm-store'
author 'CM'
description 'General item store. Admin adds any cm-items item; players buy it into their inventory.'
version '1.0.0'
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
    'web/images/custom/*.webp'
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
    'oxmysql'
}

-- ox_target is optional. Ensure order in server.cfg:
-- ensure ox_lib, ensure cm-items, ensure cm-inventory, ensure cm-itemactions, ensure cm-store.
