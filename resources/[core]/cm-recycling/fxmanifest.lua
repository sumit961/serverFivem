fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Recycling - Salvage Recovery, Material Processing & Recycling Job'
author 'CM Framework'
version '1.0.0'

shared_script 'shared/config.lua'

client_scripts {
    'client/main.lua',
    'client/npc.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js'
}

dependencies {
    'oxmysql',
    'cm-ui',
    'cm-playerdata',
}
