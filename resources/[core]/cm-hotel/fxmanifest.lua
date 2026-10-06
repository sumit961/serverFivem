fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cm-hotel'
author 'CM Framework'
description 'CM Roleplay beginner hotel, reception, first spawn, lifts, and temporary rentals'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/setup.lua'
}

server_scripts {
    'server/setup.lua',
    'server/main.lua'
}

dependencies {
    'cm-core',
    'cm-ui',
    'cm-lift',
    'cm-admin'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'data/hotel_setup.json'
}
