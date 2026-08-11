fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-doctor'
author 'CM Framework'
description 'Static doctor NPCs -- paid treatment and medical supply purchases'
version '2.4.1-medicine-routes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

dependencies {
    'ox_lib',
    'cm-playerdata',
    'cm-items',
    'cm-inventory',
    'cm-itemactions',
    'cm-ems',
}
