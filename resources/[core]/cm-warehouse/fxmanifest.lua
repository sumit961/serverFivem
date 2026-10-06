fx_version 'cerulean'
game 'gta5'
lua54 'yes'

description 'CM Warehouse - Port Logistics, Freight Handling & Physical Cargo Operations'
author 'CM Framework'
version '1.0.0'

shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/npc.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'shared/config.lua',
    'server/contracts.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

dependencies {
    'oxmysql',
    'cm-ui',
    'cm-playerdata',
}

